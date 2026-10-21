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
