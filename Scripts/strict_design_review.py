#!/usr/bin/env python3
"""Native review for the October 28 explicit UI/font request. Never exports an IPA.

The former card-only source freeze remains intact for that historical review.
This request explicitly permits meal cards, the portion form and global Changa
Bold. Every other original app file remains compared with its checkpoint.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

import calorie_card_review as card
from build_ios import BuildError

BASELINE = "d0a278ec897520ec2bd5c21af4b0183fdcdf25f7"
ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {
    "Luqma/LuqmaApp.swift": "DEBUG-only portion preview uses the real existing analysis callback, matching the actual diary context",
    "Luqma/Views/DiaryView.swift": "Replace mealList/mealSection using the supplied four category photographs",
    "Luqma/Views/DailyMealCard.swift": "Native interactive reference meal card",
    "Luqma/Views/FoodAddView.swift": "Native portion form from the supplied Add Meal handoff",
    "Luqma/Views/LuqmaTypography.swift": "Explicit global Changa Bold request",
    "Luqma/Views/FitnessProfileView.swift": "Route text plus/minus through the requested font",
    "Luqma/Views/SettingsView.swift": "Accurate bundled-font attribution",
    "Luqma/Info.plist": "Register Changa-Bold.ttf only; preserve unrelated metadata",
    "Luqma/Resources/Changa-Bold.ttf": "Original licensed Changa Bold font",
    "Luqma/Resources/Changa-OFL.txt": "Full upstream font license",
    "Luqma/Resources/Changa-Font-Provenance.txt": "Pinned source, font identity and checksum",
}
for name in ("DailyMealBreakfast", "DailyMealLunch", "DailyMealDinner", "DailyMealSnack",
             "AddMealCalories", "AddMealProtein", "AddMealCarbs", "AddMealFat"):
    for file in ("Contents.json", "original.png", "source.png"):
        ALLOWED[f"Luqma/Resources/Assets.xcassets/{name}.imageset/{file}"] = "Supplied original meal photograph or Add Meal icon"


def freeze() -> dict:
    old = {}
    for item in card.git(ROOT, "ls-tree", "-r", "-z", BASELINE, "--", "Luqma/").split(b"\0"):
        if item:
            metadata, path = item.split(b"\t", 1)
            mode, kind, digest = metadata.decode().split()
            if kind != "blob": raise BuildError("Unexpected checkpoint object")
            old[path.decode()] = (mode, digest)
    current = {p.relative_to(ROOT).as_posix(): p for p in (ROOT/"Luqma").rglob("*") if p.is_file()}
    changed, violations = [], []
    for name in sorted(set(old) | set(current)):
        before = card.git(ROOT, "cat-file", "blob", old[name][1]) if name in old else None
        after = current[name].read_bytes() if name in current else None
        if before == after or (before is not None and after is not None and Path(name).suffix != ".ttf" and card.canonical(before) == card.canonical(after)):
            continue
        changed.append({"path": name, "reason": ALLOWED.get(name),
                        "sha256": hashlib.sha256(after).hexdigest() if after is not None else None})
        if name not in ALLOWED or after is None:
            violations.append({"path": name, "reason": "Original file removed or outside the requested UI/font scope"})
        elif name == "Luqma/Info.plist":
            a, b = plistlib.loads(before), plistlib.loads(after)
            expected = a.pop("UIAppFonts", []) + ["Changa-Bold.ttf"]
            actual = b.pop("UIAppFonts", [])
            if len(actual) != len(expected) or set(actual) != set(expected) or a != b:
                violations.append({"path": name, "reason": "Only the additional font registration is authorized"})
        elif name == "Luqma/Views/DiaryView.swift":
            a, b = card.canonical(before).decode(), card.canonical(after).decode()
            start, end = "    private func mealList(", "struct CalorieIntakeDetailView: View {"
            if any(s.count(marker) != 1 for s in (a, b) for marker in (start, end)) or a[:a.index(start)] != b[:b.index(start)] or a[a.index(end):] != b[b.index(end):]:
                violations.append({"path": name, "reason": "Home changed outside the requested meal-list region"})
        elif name == "Luqma/LuqmaApp.swift":
            a,b=card.canonical(before).decode(),card.canonical(after).decode()
            old_call='case .portion:FoodPortionView(food:previewPortionFood,initialMeal:ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") ? .lunch:nil)'
            new_call='case .portion:FoodPortionView(food:previewPortionFood,initialMeal:ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") ? .lunch:nil,onAnalyze:{templatePreview=nil;photoPreview=true})'
            if a.count(old_call)!=1 or a.replace(old_call,new_call)!=b:
                violations.append({"path": name,"reason":"Only the DEBUG portion preview callback may change; production navigation must remain intact"})
    return {"status": "failed" if violations else "passed", "baseline": BASELINE,
            "baseline_app_files": len(old), "changed_app_files": changed, "violations": violations,
            "unrelated_app_files_preserved": not violations,
            "approval_required": True, "merged": False, "ipa_published": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "host-build", "host-preflight", "validate"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    card.BASELINE = BASELINE
    card.freeze = freeze
    try:
        result = freeze() if args.mode == "freeze" else card.preflight_host(render=args.mode == "host-preflight") if args.mode in {"host-build", "host-preflight"} else card.validate()
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "passed" else 1
    except (BuildError, OSError, ValueError) as error:
        print("Strict UI review: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__": raise SystemExit(main())
