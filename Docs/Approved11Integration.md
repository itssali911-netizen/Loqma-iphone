# Approved eleven-screen integration — validation pending

This document records the source integration pass, not a completed release or a performance result. Native compilation, fresh application captures, functional validation and performance comparisons remain **PENDING** until corresponding evidence is produced. The previous 2.8 build does not validate these changes.

## Source and recoverable baseline

- User archive: `1-Luqma-Approved-11-Screens-Only-For-Model.zip`.
- Original archive SHA-256: `04e16d971768470ab4eaf42a26eb0eaef3b8b980e131f4dd1b458af6b3339924` (independently re-read from the attached archive).
- Baseline commit: `87c0c2f5c81982b367eb9e42386b884a0d8c3fe1`.
- Recoverable checkpoint tag: `checkpoint/pre-approved11-20261021-87c0c2f`.
- Integration method: compare and reconcile the supplied files with the current source. The supplied patch is a second representation of the same changes and is **not** applied in addition to the source port.
- Read reference: `PROMPT_FOR_MODEL.md` and all eleven PNGs under `Approved_11_Screens/` in the extracted package. No additional Figma MCP reads are used.
- Original design-series Screen 8, Food Swipe Actions, stays excluded. Logged entries retain tap-to-edit and the existing explicit delete confirmation inside the editor.

## Screen-to-component map

The original design-series numbers are retained; the inventory contains eleven screens because number 8 is excluded. Source presence is not proof of successful rendering.

| Approved screen / reference | Actual project component | Source integration / runtime verification |
| --- | --- | --- |
| 1. Goal selection — `after_01_fitness_assessment.png` | `Luqma/Views/FitnessAssessmentView.swift`: `.goal`, `choices`; `Luqma/Core/UserProfileAndOnboarding.swift`: goal artwork/order adapters | Presentation port in source; native/visual verification PENDING |
| 2. Gender illustrations — `after_02_gender_selection.png` | `FitnessAssessmentView.gender`; original `CFAFemaleFitnessIllustration` and `CFAMaleFitnessIllustration` assets | Presentation port in source; native/visual verification PENDING |
| 3. Weight, height and age — `after_03_weight_age_height_selectors.png` | `Luqma/Views/AssessmentNumberPickers.swift`: `AssessmentNumberPicker`, `ageWheel`, `ruler`, direct numeric input; metric/imperial adapters in `UserProfileAndOnboarding.swift` | Presentation port in source over the existing raw-input model; native drag/input/persistence verification PENDING |
| 4. Goal weight — `after_04_goal_customization.png` | `FitnessAssessmentView.targetAndPace`, `targetAdjustment`; `FitnessPace.approvedTitle/approvedSubtitle` | Presentation port in source; native/visual verification PENDING |
| 5. Fitness level / activity arc — `after_05_fitness_profile.png` | `FitnessAssessmentView.activityArc`; `Luqma/Views/AssessmentFlowView.swift`: `SandowFitnessArcSlider` | Presentation port in source; native/visual verification PENDING |
| 6. Personalized calorie target — `after_06_personalized_plan.png` | `Luqma/Views/FitnessProfileView.swift`: `FitnessPlanReviewView`; `ApprovedCalorieUnit` / `ApprovedPlanGoals`; transactional `DiaryStore.applyFitnessPlan(calorieOverride:)` | Calorie-target presentation port in source; native/visual/calculation verification PENDING |
| 7. Food quantity — `after_07_food_quantity.png` | `Luqma/Views/FoodAddView.swift`: `FoodPortionView`, `portionHeader`, `foodNameCard`, `mealSelector`, `quantityTrack`, `referenceCard`, `saveButton` | Presentation port in source; native serving/recalculation/save verification PENDING |
| 9. Home reorganization — `after_09_home_dashboard.png` | `Luqma/Views/DiaryView.swift`: `header`, `compactPersonalizedPlanBadge`, `normalDiaryContent`, `dailySummary` | Presentation port in source; native layout/navigation verification PENDING |
| 10. Seven-day calorie intake — `after_10_calorie_intake.png` | `DiaryView.swift`: `CalorieIntakeDetailView`, `sevenDayItems`, selected chart day, `intakeMacroColumn` | Presentation port in source; chart/date/sheet/RTL verification PENDING |
| 11. Analysis scanner — `after_11_food_analysis_scan.png` | `Luqma/Views/PhotoMealView.swift`: `analysisHeader`, `scanViewfinder`, `cameraControl`, `photoInput`; shared `CFAScanBracketsShape` | Presentation port in source; photo/camera permission/cancellation/native layout verification PENDING |
| 12. Full nutrition results — `after_12_food_analysis_results.png` | `PhotoMealView`: `resultHero`, `resultPanel`, `resultTitle`, `macroColumn`, `macroIcon`, existing component editor and logging | Presentation port in source; actual data/photo/RTL/logging/native layout verification PENDING |

## Original asset provenance

All ten supplied image sets are copied without replacing, resampling or recompressing their artwork. [Approved11Assets.json](Approved11Assets.json) records every original file path and SHA-256, including all `Contents.json` files and the male illustration's original SVG. At this integration snapshot all 21 catalog files match the extracted source bytes.

| Image set under `Luqma/Resources/Assets.xcassets/` | Primary supplied artwork SHA-256 |
| --- | --- |
| `CFAFemaleFitnessIllustration.imageset/illustration.png` | `142499a9dba3ad05d025e50f57ee7bb12c6b2cb4651a1011316b65a94d4c0ee2` |
| `CFAMaleFitnessIllustration.imageset/illustration.png` | `bc1748fa4bfd660d98c238dba7f7f4fedbfd0681c4ec0fa8c1bd6682f03bad6b` |
| `DNMCarbsToastIcon.imageset/artwork.png` | `1871142cd29977c901fb3dd142bcf0c1f31a6900e5013c36b35cbf228b06057e` |
| `DNMFatBoneIcon.imageset/artwork.png` | `038ae924d6fb11619461fab19e0054fb236601c36f7b17edbacf2dcc6ab7b40b` |
| `DNMMandarinPileHero.imageset/artwork.png` | `24100c66396836310b2cb07d6a14f1ae54a854cede50a73b7a4be0378cd7eb14` |
| `DNMMandarinScanHero.imageset/artwork.png` | `4939401d079f196bd43b5270df342eac40cd89a05267050232d37f378b519355` |
| `DNMProteinBlueIcon.imageset/artwork.png` | `cf2de46e22e319717fde22d3894dca521768b87505205fc5056bc1f37f75a728` |
| `DNMVerticalCarbsIcon.imageset/artwork.png` | `4d8b2b6684c72b7d65469c6d7f75fa8616b8b18946ada3dda9d25a49de40f2ee` |
| `DNMVerticalFatIcon.imageset/artwork.png` | `1de108a47ee64a6ccd01a425dafd5d730f13b14289e1001228cc25feebc22558` |
| `DNMVerticalProteinIcon.imageset/artwork.png` | `0851ceddba8be757a26a1e3a4d17af19e1ed8d53e41d0d6f575fca072ab6132a` |

The current bundled Tajawal / Work Sans font files remain in use. SwiftUI has no `Font.Weight.extrabold`; `.heavy` selects the existing `Tajawal-ExtraBold` / `WorkSans-ExtraBold` mapping. This is an API adaptation, not a replacement font.

## Why a literal five-file overwrite is unsafe

The archive targets an older onboarding branch. Its `UserProfileAndOnboarding.swift` and `AssessmentFlowView.swift` use a different persisted onboarding model and store APIs. Current Luqma already has an eleven-page assessment, legacy draft migration, validation, saved raw numeric inputs, transactional plan preview/apply, and personal/food history preservation. Replacing those with the package's older model would discard newer functionality or fail compilation.

The five approved paths are therefore integrated as presentation/adapters, retaining the current models and production service calls. Shared shapes and `Color(hex:)` live in `AssessmentFlowView.swift`; the entry point delegates to the existing assessment flow. Unavailable Theme spacing names are expressed using the approved geometry locally, without changing the app-wide theme.

Additional implementation files are necessary for the current architecture:

| Additional path | Specific reason |
| --- | --- |
| `Luqma/Core/FitnessAssessment.swift` | Reserves six bounded unit/imperial raw metadata keys while retaining the existing 32 unknown-field allowance, so display-unit choices and unfinished input can survive a draft round trip. Estimator formulas are retained. |
| `Luqma/Views/FitnessAssessmentView.swift` | Actual current assessment entry point; applies approved goal/gender/target/activity visuals while preserving saved drafts, validation, safety and navigation. |
| `Luqma/Views/AssessmentNumberPickers.swift` | Actual reusable numeric input component; approved wheel/ruler presentation must still edit the single current raw input and retain direct entry. |
| `Luqma/Views/FitnessProfileView.swift` | Actual current profile and plan review destination; hosts the approved calorie target interface without replacing its current review/apply behavior. |
| `Luqma/Services/DiaryStore.swift` | Required atomic application of an explicitly chosen calorie target with the calculated plan, preserving macro shares and existing nutrition history. |
| `Luqma/LuqmaApp.swift` | DEBUG-only routes for capturing actual approved-screen implementations and explicit synthetic examples; release data is not replaced by fixtures. |
| `Scripts/build_project.py` and generated `Luqma.xcodeproj/project.pbxproj` | Registers new Swift adapters, bundled assets and required test targets in the generated Xcode project. |
| `TestsUI/LuqmaInteractionTests.swift` | Existing functional tests must locate the new approved controls by their real identifiers rather than the previous segmented-control accessibility type. |
| `Docs/Approved11Integration.md`, `Docs/Approved11Assets.json` | Records source provenance, compatibility decisions and pending verification. |

Performance-specific files and changes belong to a separate pass and version-control checkpoint, after the UI integration baseline. Their exact paths and reasons must be reported with real validation; this document does not treat diagnostic scaffolding as measured improvement.

## Supplied source versus supplied PNG discrepancies

The approved PNGs govern the visible layout when the package source conflicts with them. These reconciliations preserve the human request's existing-functionality requirement:

1. Screen 7 source contains four separate nutrient tracks and an additional quantity block. Its approved PNG has three tracks: protein, carbohydrate, and calories with fat in the title, with quantity beside the food name. The port follows the PNG structure. Each track adjusts consumed quantity through the existing reference nutrition; it does not independently invent nutrient values.
2. Screen 12 source includes floating nutrient tags and a separate mini-summary bar associated with another design. These are absent from approved result PNG 12 and are not added.
3. Result screenshot 12 shows `187 kcal` with `51g / 51g / 88g` macros, which is not nutritionally consistent. Production values and arithmetic remain real. The explicit DEBUG mandarin fixture uses a coherent synthetic example and is never a remote AI response or user meal.
4. Source English strings hardcode `Fruit`, `Mandarin Orange`, `Vitamin C`, `mg`, and `Good For Diet`. Production labels use the actual food, components and known units, without asserting an unverified classification or dietary suitability. Unknown gram weights remain unknown rather than being inferred from ml or unidentified servings.
5. The target-weight PNG has no plus/minus buttons and uses gray selected pace cards with white borders; the supplied Swift differs. The current target view follows the PNG and retains direct numeric entry. Age, height and weight still expose synchronized adjustment actions.
6. Supplied source renders static macro fill fractions and SF Symbols although original vertical macro artwork is included. The port uses the supplied `DNMVertical*` assets and bar fractions derived from the actual macro amounts; displayed values remain unchanged.
7. The supplied scan food art is an explicitly illustrative empty state; a chosen/captured photo replaces it. Result artwork uses the actual user photo. `DNMMandarinPileHero` is used only in an explicit DEBUG result fixture, never to represent an unrelated real meal.
8. Package camera buttons bypass some current authorization/settings behavior, and its top-header back button only toggles a disclosure. Current permission recovery, cancellation and actual close navigation are retained.
9. Package search changes outside the approved quantity screen would regress current search/cancel/permission/UI-test behavior. Top-level search is retained. Only the photo tab's duplicate outer header is hidden and a real `onClose` callback returns to search.
10. Package diary reopens an incompatible older onboarding flow. The compact plan pill retains the existing `FitnessProfileView` route. Entries retain tap-to-edit and deletion inside the existing editor; no swipe actions are introduced.
11. Package chart dragging updates the date that anchors its own seven-day window. The port freezes the window separately from the selected day and uses the system chart selection API instead of screen-width gesture math. Date-picker Done and interactive dismissal both commit the chosen window/day. A nil selection falls back to the actual chosen day. A geometry-backed scroll container permits small-screen and large-text overflow without shrinking approved default components; runtime verification remains pending.

### Explicit capture fixtures

- DEBUG argument `-loqma-approved-photo-scan` selects the original `DNMMandarinScanHero` and the approved scanning-bubble text for reference capture. It does not start an AI request or pretend the production `busy` state has changed.
- DEBUG argument `-loqma-approved-photo-results` renders the actual result view with an explicit synthetic mandarin nutrition fixture and original `DNMMandarinPileHero`.
- DEBUG argument `-loqma-approved-capture` suppresses only the inline empty-state illustration caption for a clean reference crop. The comparison report/gallery must label these captures as synthetic UI fixtures. Production keeps the visible illustration explanation, actual busy state and actual meal photographs.
- These flags have no effect in Release builds. They are not benchmarks, live camera feeds, successful remote service responses, or evidence of user meals.

A native screenshot comparison is still required before describing any of these screens as visually verified or pixel accurate. Device chrome, actual data, translated copy and unavailable original font licensing must not be hidden by fabricating a matching screenshot.

## Validation status at this source checkpoint

| Check | Actual status |
| --- | --- |
| Attached ZIP hash and ten asset sets | Original ZIP hash re-read; 21 asset files byte-matched against the extracted inventory. |
| Local `git diff --check` | Passed for the meal UI port snapshot; must be repeated after final integration. |
| Windows `python -m unittest discover -s BuildTests -q` | 68 executed: 64 passed, 2 skipped, 2 failed on POSIX permission-bit expectations in `test_signing.py` (Windows reports `0666` instead of `0600`/`0640`). Tests were not weakened. |
| Fresh macOS BuildTests / Swift core tests | PENDING. The package's expected 66 is not substituted for the actual current suite count. |
| Xcode compilation / IPA | PENDING for the new source. |
| Native assessment, quantity, logging, chart, AI flow and persistence | PENDING on the new source. No live remote AI success is claimed from a UI fixture. |
| Eleven-screen Arabic / English visual regression, safe areas, Dynamic Type | PENDING actual application captures and review. |
| Before/after launch, navigation, FPS/frame times/hitches, CPU, memory, energy | **Not Measured** at this UI source checkpoint. |
| Physical 60 Hz / ProMotion device validation | **Not Measured**. No compatible physical device is attached to this Windows workspace. |
| 120 FPS | Not verified or forced. Simulator screenshots cannot establish physical ProMotion performance. |

No service key, personal connection configuration, paid Apple membership or unrelated application feature is part of this UI integration.

## Actual first integration build (94)

Commit `f4d8cb9813d6fd786b1f7ac497f7fdb6c51700d2` compiled a real iPhoneOS arm64 IPA, version 2.9/build 94/minimum iOS 17. The unsigned artifact requires personal re-signing. Compilation is not functional acceptance.

The isolated native fitness case ran for 191.365 seconds and failed at the early safety message, before exercising the later measurement pages. Its actual accessibility hierarchy puts the alert's bottom at 794.5pt and the safe content clearance at 794pt: the outline exceeds the visible region by half a point. The correction adds 12pt inside the error scroll target. Normal approved layouts and the strict assertions remain unchanged. All seven functional cases must pass on the corrected source before delivery.

The first complete screenshot sets were skipped after that failed test. The workflow now permits independent native rendering capture after a failed interaction scenario, while preserving the failed test/job outcome. A captured image is never treated as a passed functional test.

The approved portion fixture is corrected only in clean reference mode to coherent 30g cereal nutrition and Lunch; the ordinary capture retains its labeled yogurt example. Benchmark instrumentation now computes today's day key once rather than 5000 times during fixture verification. UI performance comparisons must use the corrected fixture on both revisions; build 94 UI timing must not be compared to a different fixture hash. Its separately measured Core encoding baseline remains actual evidence: three wall samples 1.4242641, 1.3210779, 1.3903015 seconds; median 1.3903015s. This is a macOS serialization experiment, not an iOS FPS result.

A fresh corrected UI baseline is required. Performance production changes remain a subsequent, separate source stage.


## Actual native baseline 95 and focused visual corrections

Commit `575f3e8202cf837fa1085caa938cb76ed3393df7`, [run 95](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39637212015): iPhoneOS IPA compiled, 236 Core tests and 68 BuildTests passed. All nine Release/-O performance scenarios passed and produced 59 attributable metric rows. This is a valid measurement run, not a physical FPS result.

Thirteen approved Arabic native captures and 26 English captures completed with runtime font audits. The iPhone 13 mini framebuffer is actually 1080×2340; the original approved references are 1125×2436. Original native PNGs are retained without resampling. Separate age/height references are still absent from the ZIP.

Functional acceptance remains incomplete: the isolated assessment regression stopped at the age step because the native wheel container propagated `assessment.age.slider` over its children. The wheel now explicitly contains its accessibility children. Existing assertions and identifiers are preserved; this requires a fresh native test.

Actual capture comparison found and corrected these presentation defects, without changing nutritional data or the approved artwork bytes:

- Quantity and collapsed reference rows were at least 76pt rather than the approved 52pt; tracks occupied 44pt instead of 22pt. Layout now follows the reference while transparent 44pt gesture targets retain the horizontal-intent guard.
- The original scan raster already contains brackets, a scan beam and an English bubble. It now renders those once, with localized text in place. Real user photos retain the native overlay. The original raster aspect ratio and physical camera-control order are preserved.
- Opaque RGB macro artwork was incorrectly rendered as a template and appeared as solid squares. It now uses the original pixel colors.
- The explicitly synthetic result fixture's supplied raster includes a baked status bar, back button and handle. Its food-only viewport is composed below the live native chrome. Actual user photos are untouched; the source PNG is unchanged.
- Calorie-chart geometry follows the reference's physical direction, and callout overflow is constrained to the chart. The actual selected day's calories and macro totals remain real.
- The activity hint aligns physically left, the calorie-plan hero groups Western digits, the weight readout uses `kg`, and an unanswered numeric prompt uses the bundled font at 22pt instead of clipping at readout size.
- The goal heading includes the reference's Arabic word “الرئيسي”. The phone glyph uses the original existing `AssessmentGoalExplore` SVG rather than an absent asset name.

A remaining supplied-resource gap is explicit: `CFAGoalRobot` is referenced by the approved Swift file but is absent from both its ten image sets and the existing catalog. No unrelated replacement artwork is invented. Exact verification of that glyph requires the original asset. Goal selection itself remains functional.

The regular 51-route capture collected all frames but correctly failed its final uniqueness audit because the dinner/snack carousel was below the visible dashboard. A DEBUG-only vertical scroll now reveals the actual carousel for those two routes; the duplicate-frame guard is unchanged. Approved captures and actual functional tests remain separate evidence.

These corrections establish a new pre-optimization UI baseline. Do not compare a changed quantity-screen geometry directly with run95 as if only performance code changed. Native recapture, interaction rerun and the new baseline measurements are PENDING.


## Original goal artwork recovered from the prior supplied project

The two glyphs absent from the eleven-screen ZIP were found in the user's earlier `Loqmati-Sandow-UI-Integrated/Loqma-iphone` repository. `CFAGoalRobot.imageset` and `CFAGoalPhone.imageset` are restored byte-for-byte, with their original SVG geometry and vector/template catalog settings. `Approved11Assets.json` records the exact source revision and four file hashes separately from the 21 untouched ZIP assets. The source adapter again references the approved `CFAGoalPhone` name. No replacement icon or generated artwork is used.

This supersedes the historical missing-glyph limitation above. Native SVG compilation/capture still requires verification in the new fully restored pre-optimization UI baseline. Commit-scoped workflow concurrency preserves older evidence while that source builds.

## Native-runner failures before application verification (96/97)

Run96 passed all 236 Core tests, but the native bundled-font probe could not finish booting its newly created Simulator on either bounded startup attempt. BuildTests ended with 66 executed tests and one setup error; no app compilation, interaction test or screenshot collection followed. Run97's performance job separately stopped before app compilation: after opening the selected Simulator application, `bootstatus UUID -b` returned CoreSimulator405 / already Booted, then recovery shutdown timed out. Its Core microbenchmark is retained separately; no native application metrics were produced. Run96's performance job and run97's build job were cancelled without a runner or any executed steps. Their GitHub check annotations explicitly report unavailable hosted macOS runner capacity, rather than an application or assertion failure.

These runs do not verify the restored artwork, corrected assessment input or approved layouts. Their failures must remain visible. A fresh fully restored, pre-optimization baseline is required on a working native runner, with the same approved UI, fixture and performance harness.

The startup helper now handles the observed checked-runner exit149 only after independently confirming that exactly the owned, available UUID is Booted. It then monitors that existing boot without `-b`, using the remainder of the original 300-second deadline, and still requires Settings to return a real positive process ID. A timeout, unknown state or failed monitoring is not accepted as readiness and retains the existing bounded reboot/fatal checks. No global Simulator service or other device is modified. Targeted Windows orchestration/font/capture checks executed 44 tests: 42 passed and two native-only cases skipped. Native validation of this infrastructure correction remains pending.

Performance artifacts now include the workflow attempt in their names, preserving failed-attempt evidence when a native runner is retried. The later optimized measurement pins both the successful baseline run and attempt; it cannot silently consume a different retry. This is build infrastructure only and changes no production application behavior or nutritional calculation.

## Actual native checkpoint98 and accessibility follow-up

UI-only revision `67e050686ad0de33c1125ff1e40b937c26b04bba` compiled the real iPhoneOS2.9/build98 IPA and passed236Core tests and75BuildTests, including native font checks. All nine native performance scenarios passed and their59normalized metric rows were independently matched to the raw sample arrays, identifiers, units and statistics. These are measurement results, not functional or visual acceptance.

The isolated functional assessment test proceeded through the real age/height/weight inputs, rapid dragging, invalid raw values, save/resume and back/forward assertions. It then failed after508.023seconds at step8: the opened activity disclosure propagated `assessment.activity.details` over all five visible option buttons and the steps field, so `assessment.activity.light` could not be located. The actual screenshot and hierarchy are retained. This was an assertion failure, not the command deadline.

The follow-up adds an explicit accessibility containment boundary to that disclosure and the identically structured optional food-preference disclosure. Child identifiers, layout, gestures, validation and the strict tests are preserved. Native validation of the correction is pending.

The nine measured performance workloads never construct either changed step: the assessment scenario opens only its initial goal page and immediately returns. It does not advance to activity or food preferences, and its normal fixture has no saved assessment draft. Thus checkpoint98 remains the explicitly identified baseline for those unchanged workloads, provided the frozen harness, fixture, runtime, build settings, device and UTC-day gates match. The accessibility follow-up is a separate functional correction, not a measured performance improvement or a new baseline run.
