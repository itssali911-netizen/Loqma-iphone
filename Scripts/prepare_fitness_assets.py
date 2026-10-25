#!/usr/bin/env python3
"""Bundle measured assessment assets from the saved Figma export, without network."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Docs/FitnessAssessmentDesign/assets'
OUTPUT = ROOT / 'Luqma/Resources/Assets.xcassets/Assessment'
VECTORS = {
    'AssessmentBack': '7c9b3.svg', 'AssessmentNext': 'c1a83.svg',
    'AssessmentChecked': '3ee61.svg', 'AssessmentUnchecked': '34b5e.svg',
    'AssessmentGoalLose': 'd7eee.svg', 'AssessmentGoalMuscle': '9e577.svg',
    'AssessmentGoalEndurance': '17630.svg', 'AssessmentGoalExplore': 'e89cf.svg',
    'AssessmentDietPlant': 'd7c07.svg', 'AssessmentDietBread': '0d586.svg',
    'AssessmentDietFood': 'bcfb7.svg',
    'AssessmentExercise0': 'd2138.svg', 'AssessmentExercise1': '23a45.svg',
    'AssessmentExercise2': 'd8664.svg', 'AssessmentExercise3': '6e49f.svg',
    'AssessmentExercise4': 'a929c.svg',
    **{f'AssessmentSleep{i}': name for i, name in enumerate(
        ['4b6ce.svg', '3cf2d.svg', '7828a.svg', '0eec0.svg', '44a0b.svg'])},
}
PHOTOS = {'AssessmentMale': 'a5378.png', 'AssessmentFemale': '46d16.png'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / 'Contents.json').write_text(json.dumps({'info': {'author':'xcode','version':1}},indent=2)+'\n')
    records=[]
    for name, original in {**VECTORS, **PHOTOS}.items():
        source=SOURCE / original
        target=OUTPUT / (name+'.imageset')
        target.mkdir(exist_ok=True)
        filename='source.svg' if name in VECTORS else 'artwork.jpg'
        production=target / filename
        record={'name':name,'source':str(source.relative_to(ROOT)).replace('\\','/'),
                'source_sha256':digest(source),'production':str(production.relative_to(ROOT)).replace('\\','/')}
        if name in VECTORS:
            shutil.copyfile(source,production)
            properties={'preserves-vector-representation':True}
            record['transformation']='Original SVG bytes; template tint only for navigation arrows.'
        else:
            with Image.open(source) as image:
                original_size=image.size
                image=image.convert('RGB')
                image.thumbnail((1024,1024),Image.Resampling.LANCZOS)
                image.save(production,'JPEG',quality=91,optimize=True,subsampling=0)
                record.update(original_dimensions=original_size,production_dimensions=image.size)
            properties={}
            record['transformation']='Aspect-preserving LANCZOS downsample, RGB JPEG quality91; no crop or semantic edit. Cropping is in the live card.'
        catalog={'images':[{'filename':filename,'idiom':'universal'}], 'info':{'author':'xcode','version':1}}
        if properties: catalog['properties']=properties
        (target/'Contents.json').write_text(json.dumps(catalog,indent=2)+'\n')
        record.update(sha256=digest(production),bytes=production.stat().st_size)
        records.append(record)
    manifest={'source_file':'https://www.figma.com/file/IfMCdTI3FcvXpNFy79PRUA',
              'accessible_reference_copy':'HBIa4HlRoHRjxZWJfqyrUG','source_kind':'Original Figma Community assessment assets saved before quota limit',
              'note':'Bundled artwork depicts assessment choices, never a user meal, measurement or analysis result. Swimming and fish use native SF Symbols because no corresponding original asset was extracted.',
              'total_bytes':sum(item['bytes'] for item in records),'assets':records}
    (ROOT/'Docs/FitnessAssessmentDesign/production-assets.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'Bundled {len(records)} assessment assets; {manifest["total_bytes"]} bytes')

if __name__=='__main__':main()
