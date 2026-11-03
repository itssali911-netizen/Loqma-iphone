#!/usr/bin/env python3
"""Focused real-Simulator evidence for the approved recipe/macro/home changes.

Uses the existing SDK build, framebuffer/font-audit and XCUITest runners.
Review-only card fixtures are explicitly labeled and never presented as live
user recipes, remote API results, physical-device tests or performance metrics.
No IPA, signing credentials or production server deployment is produced here.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

from build_ios import BuildError, build, require_mac
from ui_interactions import run_scenario
import ui_preview
from vision_compat import apply_vision_compat

ROOT = Path(__file__).resolve().parents[1]
PRODUCT_SCREENS = ("today", "daily-overview", "meal-macros", "food-portion",
                   "recipe-editor", "recipe-details")
CARD_TESTS = ("testArabicReference390GeometryAndMacroValues",
              "testNarrow320LongEnglishContentAndActions",
              "testDetailsAndSingleServingUseRealTemporaryDiary",
              "testAccessibilityArabicKeepsControlsInsideCard",
              "testLargeValuesStayInsideNarrowCardWithoutShrinking")
PRODUCT_TESTS = ("testHomeKeepsMealLoggingWithoutSupplementarySections",
                 "testGramAndServingQuantityRecalculateStoredFood",
                 "testRecipeDetailsIngredientDisclosureAndBothQuantityModes",
                 "testRecipeDraftSurvivesIngredientSearch")


def revision() -> str:
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def new_report(output: Path, mode: str) -> dict:
    if output.exists():
        raise BuildError("Use a fresh review output directory; retain earlier evidence.")
    output.mkdir(parents=True)
    return dict(status="running", mode=mode, source_commit=revision(),
                started_at=datetime.now(timezone.utc).isoformat(),
                physical_device_verified=False, real_health_access_verified=False,
                remote_food_service_verified=False, full_off_import_verified=False,
                visual_match_verified=False, fps_measured=False, ipa_produced=False,
                reviews=[])


def save_report(output: Path, report: dict) -> None:
    report["completed_at"] = datetime.now(timezone.utc).isoformat()
    (output / "review-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")


def card_cases(language: str) -> list[dict]:
    """Exercise the actual production card through the DEBUG temporary diary host."""
    cases = []
    variants = (("390", ()),
                ("320", ("-loqma-recipe-card-320",)),
                ("390-long", ("-loqma-recipe-card-long",)),
                ("320-long", ("-loqma-recipe-card-320", "-loqma-recipe-card-long")),
                ("320-accessibility", ("-loqma-recipe-card-320", "-loqma-recipe-card-long",
                                       "-loqma-preview-accessibility")),
                ("320-large-values", ("-loqma-recipe-card-320", "-loqma-recipe-card-large")))
    for name, flags in variants:
        args = ["-loqma-preview-template", "recipeCard", *flags]
        if language == "en":
            # The isolated review host owns a separate temporary DiaryStore.
            args.append("-loqma-recipe-card-en")
        cases.append(dict(tab=None, screen="recipe-card-" + name, arguments=args,
                          synthetic_fixture=True, template_route="recipeCard",
                          read_only_preview=False, temporary_review_diary=True,
                          **({"dynamic_type_override": "accessibility3"}
                             if "-loqma-preview-accessibility" in flags else {})))
    return cases


@contextmanager
def review_routes(cases: list[dict]):
    """Select explicit review launches without changing the app or pixel pipeline.

    Only this process's route inventory is scoped. ui_preview.capture still
    installs/launches the real .app, verifies the process/font audits, reads the
    native framebuffer, rejects empty/duplicate frames and cleans its own device.
    No native command, screenshot, test outcome or health/API response is mocked.
    """
    original = ui_preview.preview_cases
    try:
        ui_preview.preview_cases = lambda: [dict(case) for case in cases]
        yield
    finally:
        ui_preview.preview_cases = original


def screenshots(output: Path, packages: Path, app: Path) -> None:
    require_mac(26)
    report = new_report(output, "native-screenshots")
    failures = []
    try:
        ordinary = [case for case in ui_preview.preview_cases() if case["screen"] in PRODUCT_SCREENS]
        if {case["screen"] for case in ordinary} != set(PRODUCT_SCREENS):
            raise BuildError("A required current native product route is missing.")
        groups = [("Product-AR", "ar", ui_preview.DEVICE_TYPE, ordinary),
                  ("Product-EN", "en", ui_preview.DEVICE_TYPE, ordinary),
                  ("Product-Compact-AR", "ar", ui_preview.REFERENCE_DEVICE_TYPE,
                   [case for case in ordinary if case["screen"] in {"today", "food-portion", "recipe-details"}]),
                  ("Card-AR", "ar", ui_preview.DEVICE_TYPE, card_cases("ar")),
                  ("Card-EN", "en", ui_preview.DEVICE_TYPE, card_cases("en"))]
        for name, language, device_type, cases in groups:
            item = dict(name=name, status="running", language=language,
                        device_type=device_type, cases=cases,
                        output=name, native_capture_report=name + "/ui-preview.json")
            report["reviews"].append(item)
            save_report(output, report)
            try:
                with review_routes(cases):
                    ui_preview.capture(output / name, packages, app, "app.luqma.diary", 6.0,
                                       device_type=device_type, language=language,
                                       screens=[case["screen"] for case in cases],
                                       approved_capture=False, expanded_recipe=False)
                evidence = json.loads((output / name / "ui-preview.json").read_text("utf8"))
                if evidence.get("status") != "captured" or not evidence.get("runtime_fonts_verified"):
                    raise BuildError("Native screen/font audit did not finish successfully.")
                item.update(status="captured", screenshot_count=evidence["screenshot_count"])
            except (BuildError, OSError, ValueError) as error:
                item.update(status="failed", error=str(error))
                failures.append(name)
            save_report(output, report)
        if failures:
            raise BuildError("Native screenshot groups failed: " + ", ".join(failures))
        report["status"] = "captured"
        report["screenshot_count"] = sum(item["screenshot_count"] for item in report["reviews"])
    except BaseException as error:
        report.update(status="cancelled" if isinstance(error, (SystemExit, KeyboardInterrupt)) else "failed", error=str(error))
        raise
    finally:
        save_report(output, report)


def controls(output: Path, packages: Path, derived: Path) -> None:
    require_mac(26)
    report = new_report(output, "native-controls")
    failures = []
    try:
        number = os.environ.get("BUILD_NUMBER", "125")
        if not re.fullmatch(r"[1-9][0-9]{0,8}", number):
            raise BuildError("BUILD_NUMBER must be a positive integer.")
        apply_vision_compat(packages)
        inventory = json.loads(ui_preview.command(["xcrun", "simctl", "list", "--json"], output, "inventory"))
        runtime = ui_preview.select_runtime(inventory)
        for name, test_class, methods in (("card", "RecipeCardInteractionTests", CARD_TESTS),
                                           ("production-flows", "LuqmaInteractionTests", PRODUCT_TESTS)):
            item = dict(name=name, status="running", test_class=test_class,
                        required_cases=list(methods), temporary_review_recipe_fixture=name == "card",
                        real_diary_controls=True, injected_remote_responses=False)
            report["reviews"].append(item)
            save_report(output, report)
            try:
                run_scenario(output / name, packages, derived, runtime, methods, item, number,
                             signing_settings=["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"],
                             test_class=test_class, timeout_seconds=2700)
                if item.get("passed_cases") != list(methods):
                    raise BuildError("Not all exact required native cases were reported as passed.")
            except (BuildError, OSError, ValueError) as error:
                item.update(status="failed", error=str(error))
                failures.append(name)
            save_report(output, report)
        if failures:
            raise BuildError("Native interaction groups failed: " + ", ".join(failures))
        report["status"] = "passed"
        report["passed_test_count"] = sum(len(item["passed_cases"]) for item in report["reviews"])
    except BaseException as error:
        report.update(status="cancelled" if isinstance(error, (SystemExit, KeyboardInterrupt)) else "failed", error=str(error))
        raise
    finally:
        save_report(output, report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "screenshots", "controls"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--packages", type=Path, default=ROOT / "BuildOutput/Packages")
    parser.add_argument("--app", type=Path, default=ROOT / "BuildOutput/simulator-derived/Build/Products/Debug-iphonesimulator/Luqma.app")
    parser.add_argument("--derived", type=Path, default=ROOT / "BuildOutput/simulator-derived")
    args = parser.parse_args()
    defaults = {"check": "BuildOutput", "screenshots": "Recipe-Review-Screens", "controls": "Recipe-Review-Controls"}
    output = (args.output or ROOT / defaults[args.mode]).resolve()
    signal.signal(signal.SIGTERM, lambda signum, _: sys.exit(128 + signum))
    try:
        if args.mode == "check":
            # Includes actual Swift Core + BuildTests and both native SDK builds.
            build("check", output)
        elif args.mode == "screenshots":
            screenshots(output, args.packages.resolve(), args.app.resolve())
        else:
            controls(output, args.packages.resolve(), args.derived.resolve())
    except (BuildError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Luqma recipe review:", str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
