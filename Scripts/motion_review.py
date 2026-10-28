#!/usr/bin/env python3
"""Native motion review against the compiled pre-motion application.

This checks scope and unchanged static drawing instructions. It does not replace
native screenshot comparisons, functional tests, Instruments or physical tests.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
import calorie_card_review as card
from build_ios import BuildError

ROOT=Path(__file__).resolve().parents[1]
BASELINE='9f567b449579d78c22833b06d9d0836bb37b833d'
VIEW_FILES={'Common','StateComponents','DailyCalorieCard','DailyMealCard','DiaryView','KitchenView',
 'ProgressView','HealthActivityViews','FoodAddView','PhotoMealView','RecipeImportView',
 'AssessmentFlowView','AssessmentNumberPickers','FitnessAssessmentView','FitnessProfileView',
 'PlanView','SettingsView','AppleHealthView','GoalEditor','NotificationsView','GeminiSettingsView'}
ALLOWED={'Luqma/Views/'+name+'.swift' for name in VIEW_FILES}|{'Luqma/LuqmaApp.swift','Luqma/Views/LuqmaMotion.swift'}

def drawing_calls(text):
    # Balanced parentheses preserve actual numeric expressions, not approximated
    # measurements. Strings/comments are kept; any difference is reviewed.
    pattern=r'(?:\.(?:luqmaFont|font|frame|padding|foregroundStyle|foregroundColor|background|clipShape|cornerRadius|stroke|strokeBorder)|\b(?:Color|HStack|VStack|LazyVStack|LazyHStack|RoundedRectangle|LinearGradient))\s*\('
    calls=[]
    for match in re.finditer(pattern,text):
        start=match.start();i=match.end();depth=1;quoted=False;escaped=False
        while i<len(text) and depth:
            c=text[i]
            if quoted:
                if escaped:escaped=False
                elif c=='\\':escaped=True
                elif c=='"':quoted=False
            elif c=='"':quoted=True
            elif c=='(':depth+=1
            elif c==')':depth-=1
            i+=1
        calls.append(re.sub(r'\s+','',text[start:i]))
    return calls

def freeze():
    old={}
    for record in card.git(ROOT,'ls-tree','-r','-z',BASELINE,'--','Luqma/').split(b'\0'):
        if record:
            metadata,path=record.split(b'\t',1);old[path.decode()]=metadata.decode().split()[-1]
    current={p.relative_to(ROOT).as_posix():p for p in (ROOT/'Luqma').rglob('*') if p.is_file()}
    changed=[];errors=[];static=[]
    for name in sorted(set(old)|set(current)):
        before=card.git(ROOT,'cat-file','blob',old[name]) if name in old else None
        after=current[name].read_bytes() if name in current else None
        if before==after or before is not None and after is not None and card.canonical(before)==card.canonical(after):continue
        changed.append(name)
        if name not in ALLOWED or after is None:errors.append(name+': outside motion scope')
        if before is not None and after is not None and name in ALLOWED:
            a,b=card.canonical(before).decode(),card.canonical(after).decode()
            if name=='Luqma/LuqmaApp.swift':
                # The explicitly separate 200ms launch overlay reuses the exact
                # storyboard mark; it is absent from every settled screenshot.
                b=re.sub(r'/// The original 96pt launch mark.*?\n}\n','',b,flags=re.S)
            ac,bc=drawing_calls(a),drawing_calls(b)
            ok=ac==bc
            static.append(dict(path=name,unchanged_drawing_calls=ok,before_count=len(ac),after_count=len(bc)))
            if not ok:errors.append(name+': static drawing calls differ; inspect before proceeding')
    return dict(status='failed' if errors else 'passed',baseline=BASELINE,changed_app_files=changed,
                preserved_assets_fonts_models_services_signing=not any(n not in ALLOWED for n in changed),
                static_drawing_checks=static,errors=errors,merged=False,ipa_exported=False,
                screenshot_comparison_required=True,physical_device_verified=False)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['freeze','host-build','validate'])
    parser.add_argument('--output',type=Path)
    args=parser.parse_args();card.BASELINE=BASELINE;card.freeze=freeze
    try:
        value=freeze() if args.mode=='freeze' else card.preflight_host(render=False) if args.mode=='host-build' else card.validate()
        if args.output:args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')
        print(json.dumps(value,indent=2));return value['status']!='passed'
    except (BuildError,OSError,ValueError) as error:print(str(error),file=sys.stderr);return 1

if __name__=='__main__':sys.exit(main())
