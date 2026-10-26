#!/usr/bin/env python3
"""Fail closed if the exact build103 source changes beyond the HealthKit port.

Reads Git objects and both the working tree and index. Does not reset, stage,
write Git objects, fetch revisions, or trust an IPA's version number.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

BASELINE = "7007dfc72ddb622bb5bb0b4ea5ba6643b9494d39"
BASELINE_TREE = "4a0e94f32b00ab0ea11c61c5f691942e3cfd9ebc"
ROOT = Path(__file__).resolve().parents[1]
ROOT_MARKER = b"struct RootView:View {"
HEALTH_SETTINGS_ROW = 'NavigationLink{HealthSettingsView()}label:{settingsRow("Apple Health",symbol:"heart.fill")}.accessibilityIdentifier("settings.health")'
HEALTH_SOURCES = {
    "Luqma/Core/HealthReadModels.swift",
    "Luqma/Services/AppleHealthService.swift",
    "Luqma/Views/AppleHealthView.swift",
}
APP_EXCEPTIONS = {
    "Luqma/LuqmaApp.swift": "HealthKit integration",
    "Luqma/Views/SettingsView.swift": "HealthKit integration",
    "Luqma/Info.plist": "Required permissions or entitlements",
    "Luqma/Luqma.entitlements": "Required permissions or entitlements",
    "Luqma/Resources/ar.lproj/InfoPlist.strings": "Required permissions or entitlements",
    "Luqma/Resources/en.lproj/InfoPlist.strings": "Required permissions or entitlements",
}
NON_APP_EXCEPTIONS = {
    ".github/workflows/restored-healthkit.yml": "Required build compatibility change",
    ".gitignore": "Required build compatibility change",
    "Luqma.xcodeproj/project.pbxproj": "Required build compatibility change",
    "Luqma.xcodeproj/xcshareddata/xcschemes/Luqma.xcscheme": "Required build compatibility change",
    "Scripts/build_ios.py": "Required build compatibility change",
    "Scripts/build_project.py": "Required build compatibility change",
    "Scripts/healthkit_ui_validation.py": "Required build compatibility change",
    "Scripts/simulator_entitlements.py": "Required build compatibility change",
    "Scripts/verify_restored_source.py": "Required build compatibility change",
    "HEALTH-SETUP-AR.md": "HealthKit integration",
    "BuildTests/Fixtures/health_service_probe.swift": "HealthKit integration",
    "BuildTests/test_health_configuration.py": "Required permissions or entitlements",
    "BuildTests/test_health_service.py": "HealthKit integration",
    "BuildTests/test_simulator_entitlements.py": "Required build compatibility change",
    "BuildTests/test_restored_source.py": "Required build compatibility change",
    "BuildTests/test_signing.py": "Required permissions or entitlements",
    "BuildTests/test_removed_health.py": "Required permissions or entitlements",
    "Tests/HealthReadModelsTests.swift": "HealthKit integration",
    "TestsUI/AppleHealthInteractionTests.swift": "HealthKit integration",
}
GENERATED_IGNORES = {"HealthValidation/", "HealthSigning/", "BuildSigned/", "Restore103Validation/"}
HEALTH_KEY = "NSHealthShareUsageDescription"


class FreezeError(RuntimeError):
    pass


def git(root: Path, *arguments: str, data: bytes | None = None) -> bytes:
    result = subprocess.run(["git", *arguments], cwd=root, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise FreezeError("Required Git object or repository operation is unavailable: " + arguments[0])
    return result.stdout


def text(data: bytes) -> str:
    return data.decode("utf-8").replace("\r\n", "\n")


def compact(line: str) -> str:
    return re.sub(r"\s+", "", line)


def validate_app(base: bytes, current: bytes) -> str | None:
    before, after = text(base), text(current)
    marker = ROOT_MARKER.decode()
    if before.count(marker) != 1 or after.count(marker) != 1:
        return "RootView boundary is missing or ambiguous"
    if before[before.index(marker):] != after[after.index(marker):]:
        return "RootView, navigation, previews or bottom controls differ from exact build103"
    old = before[:before.index(marker)].splitlines()
    new = after[:after.index(marker)].splitlines()
    env = next((line for line in old if "RootView().luqmaFont" in line), "")
    timezone = next((line for line in old if ".onReceive(" in line and "NSSystemTimeZoneDidChange" in line), "")
    if not env or not timezone:
        return "The original build103 app wiring could not be identified"
    removable = {compact(env), compact(timezone)}
    additions = {
        "lethealth=AppleHealthService()",
        "@StateObjectprivatevarhealth=AppServices.shared.health",
        "Task{awaitAppServices.shared.health.refreshIfEnabled()}",
        "Task{awaithealth.refreshIfEnabled()}",
        "ifvalue==.background{health.suspend()}",
        "ifvalue==.background{", "health.suspend()",
        compact(env) + ".environmentObject(health)",
        "Task{awaitreminders.refresh(language:diary.language)}",
        ".onReceive(NotificationCenter.default.publisher(for:NSNotification.Name.NSSystemTimeZoneDidChange)){_in",
        "Task{awaithealth.calendarDidChange()}",
        ".onReceive(NotificationCenter.default.publisher(for:NSNotification.Name.NSCalendarDayChanged)){_inTask{awaithealth.calendarDidChange()}}",
        ".onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)){_inTask{awaithealth.calendarDidChange()}}",
        ".onReceive(NotificationCenter.default.publisher(for:NSNotification.Name.NSSystemTimeZoneDidChange)){_inTask{awaitreminders.refresh(language:diary.language)}Task{awaithealth.calendarDidChange()}}",
        "", "}",
    }
    for operation, a, b, c, d in difflib.SequenceMatcher(a=old, b=new, autojunk=False).get_opcodes():
        if operation == "equal":
            continue
        if any(compact(line) not in removable for line in old[a:b]):
            return "Existing app initialization or lifecycle behavior changed beyond HealthKit"
        if any(compact(line) not in additions for line in new[c:d]):
            return "App prefix contains an addition outside the explicit HealthKit lifecycle wiring"
    return None


def validate_settings(base: bytes, current: bytes) -> str | None:
    lines = text(current).splitlines(keepends=True)
    matches = [index for index, line in enumerate(lines) if line.strip() == HEALTH_SETTINGS_ROW]
    if len(matches) != 1:
        return "Settings must add exactly one native Health connection row"
    del lines[matches[0]]
    if "".join(lines) != text(base):
        return "Settings contains changes beyond its single Health connection row"
    return None


def meaningful_purpose(value: object) -> bool:
    if not isinstance(value, str) or len(value.strip()) < 40:
        return False
    lower = value.casefold()
    return (all(word in lower for word in ("steps", "energy", "weight", "height")) or
            all(word in value for word in ("خطوات", "طاقة", "وزن", "طول")))


def validate_plist(base: bytes, current: bytes, *, entitlements: bool = False) -> str | None:
    try:
        old, new = plistlib.loads(base), plistlib.loads(current)
    except (ValueError, TypeError, plistlib.InvalidFileException):
        return "Invalid property list"
    if not isinstance(old, dict) or not isinstance(new, dict):
        return "Property list must remain a dictionary"
    key = "com.apple.developer.healthkit" if entitlements else HEALTH_KEY
    expected = old.copy()
    if entitlements:
        if new.get(key) is not True:
            return "HealthKit must be enabled with a Boolean entitlement"
        expected[key] = True
    else:
        if not meaningful_purpose(new.get(key)):
            return "A meaningful read-only purpose covering all four data types is required"
        expected[key] = new[key]
    if new != expected:
        return "Property list changed beyond the single read-only HealthKit addition"
    return None


def validate_strings(base: bytes, current: bytes) -> str | None:
    lines = text(current).splitlines(keepends=True)
    pattern = re.compile(r'^\s*"NSHealthShareUsageDescription"\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)";\s*$')
    matches = [(index, pattern.fullmatch(line.rstrip("\n"))) for index, line in enumerate(lines)]
    found = [(index, match) for index, match in matches if match]
    if len(found) != 1 or not meaningful_purpose(found[0][1].group(1)):
        return "Localized purposes must add exactly one meaningful Health read description"
    del lines[found[0][0]]
    if "".join(lines) != text(base):
        return "Existing localized app names or camera descriptions changed"
    return None


def validate_ignore(base: bytes, current: bytes) -> str | None:
    old, new = text(base), text(current)
    added, preserved = [], []
    for line in new.splitlines(keepends=True):
        if line.rstrip("\n") in GENERATED_IGNORES:
            added.append(line.rstrip("\n"))
        else:
            preserved.append(line)
    if "".join(preserved) != old:
        return "Existing ignore rules changed"
    if len(added) != len(set(added)):
        return "Only named generated Health validation/signing directories may be ignored"
    return None


def validate_delta(path: str, base: bytes | None, current: bytes | None) -> str | None:
    if path in HEALTH_SOURCES:
        if base is not None or current is None:
            return "The three Health files must be new source additions, not replacements or deletions"
        if path.endswith("AppleHealthView.swift"):
            value = text(current)
            if "HealthProgressCard" in value or "health.summary" in value:
                return "The restored Health port must not add a Progress card"
        return None
    if path in APP_EXCEPTIONS:
        if base is None or current is None:
            return "Original app connection/configuration files must not be deleted or replaced by new paths"
        if path.endswith("LuqmaApp.swift"):
            return validate_app(base, current)
        if path.endswith("SettingsView.swift"):
            return validate_settings(base, current)
        if path.endswith("Info.plist"):
            return validate_plist(base, current)
        if path.endswith(".entitlements"):
            return validate_plist(base, current, entitlements=True)
        return validate_strings(base, current)
    if path not in NON_APP_EXCEPTIONS:
        return "Path is outside the approved HealthKit/build compatibility allowlist"
    if current is None and path != "BuildTests/test_removed_health.py":
        return "Deleting this original source or configuration file is not authorized"
    if path == ".gitignore":
        if base is None or current is None:
            return "The original ignore file must remain present"
        return validate_ignore(base, current)
    return None


def inventory(root: Path, *arguments: str) -> dict[str, tuple[str, str]]:
    result = {}
    for record in git(root, *arguments).split(b"\0"):
        if not record:
            continue
        meta, name = record.split(b"\t", 1)
        mode, kind, digest = meta.decode("ascii").split()
        if kind != "blob":
            raise FreezeError("Non-blob Git entries are outside the restored project boundary")
        result[name.decode("utf-8")] = (mode, digest)
    return result


def inspect_repository(root: Path = ROOT) -> dict:
    root = root.resolve()
    report = {"status": "failed", "baseline": BASELINE, "baseline_tree": BASELINE_TREE,
              "checked_scopes": ["working_tree", "index"], "changed_files": [], "violations": []}
    try:
        if git(root, "rev-parse", BASELINE + "^{tree}").decode().strip() != BASELINE_TREE:
            raise FreezeError("The exact authenticated build103 baseline tree is unavailable")
        original = inventory(root, "ls-tree", "-r", "-z", BASELINE)
        index = {}
        for record in git(root, "ls-files", "--stage", "-z").split(b"\0"):
            if not record:
                continue
            meta, name = record.split(b"\t", 1)
            mode, digest, stage = meta.decode("ascii").split()
            if stage != "0":
                raise FreezeError("Unresolved index conflicts must be resolved before validation")
            index[name.decode("utf-8")] = (mode, digest)
        untracked = {name.decode("utf-8") for name in git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if name}
        # A local/global ignore must not conceal a new source file or asset from
        # the source freeze. Only Xcode/Finder state may be ignored inside Luqma.
        for raw in git(root, "ls-files", "--others", "--ignored", "--exclude-standard", "-z", "--", "Luqma/").split(b"\0"):
            if not raw:
                continue
            name = raw.decode("utf-8")
            file = Path(name)
            if file.name == ".DS_Store" or file.suffix == ".xcuserstate" or "xcuserdata" in file.parts:
                continue
            untracked.add(name)
        paths = sorted(set(original) | set(index) | untracked)
        base_cache = {}
        def blob(digest: str) -> bytes:
            if digest not in base_cache:
                base_cache[digest] = git(root, "cat-file", "blob", digest)
            return base_cache[digest]
        for path in paths:
            base = original.get(path)
            scopes = []
            problems = []
            for scope in ("working_tree", "index"):
                if scope == "index":
                    current = index.get(path)
                    contents = blob(current[1]) if current and current != base else None
                else:
                    file = root / path
                    if file.is_symlink():
                        contents = os.readlink(file).encode("utf-8")
                        current = ("120000", hashlib.sha1(b"blob " + str(len(contents)).encode() + b"\0" + contents).hexdigest())
                    elif file.is_file():
                        contents = file.read_bytes()
                        digest = git(root, "hash-object", "--path=" + path, "--stdin", data=contents).decode().strip()
                        mode = index.get(path, base or ("100644", ""))[0]
                        if os.name != "nt":
                            mode = "100755" if file.stat().st_mode & 0o111 else "100644"
                        current = (mode, digest)
                    else:
                        current = None
                        contents = None
                if current == base:
                    continue
                scopes.append(scope)
                if current is not None and current[0] not in ("100644", "100755"):
                    problem = "New or modified symbolic links are not permitted"
                elif base is not None and current is not None and current[0] != base[0]:
                    problem = "Original source file mode changed"
                else:
                    problem = validate_delta(path, blob(base[1]) if base else None, contents)
                if problem:
                    problems.append({"scope": scope, "reason": problem})
            if scopes:
                category = APP_EXCEPTIONS.get(path, NON_APP_EXCEPTIONS.get(path,
                    "HealthKit integration" if path in HEALTH_SOURCES else "UNAUTHORIZED"))
                item = {"path": path, "classification": category, "scopes": scopes}
                report["changed_files"].append(item)
                if problems:
                    report["violations"].append({"path": path, "problems": problems})
        report["baseline_tracked_files"] = len(original)
        report["protected_existing_app_files"] = sum(path.startswith("Luqma/") and path not in APP_EXCEPTIONS for path in original)
        report["status"] = "passed" if not report["violations"] else "failed"
    except (FreezeError, OSError, UnicodeError, ValueError) as error:
        report["violations"].append({"reason": str(error)})
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, help="Optional JSON receipt; use an ignored output directory or a path outside the repository")
    args = parser.parse_args()
    report = inspect_repository(args.root)
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
