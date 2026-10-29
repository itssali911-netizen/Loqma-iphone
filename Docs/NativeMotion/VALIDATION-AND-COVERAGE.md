# Native motion: validation and coverage

Evidence checkpoint: 2026-10-29 (Asia/Riyadh). **Review implementation; not approved for merge or a final IPA.**

This document is the current evidence summary. The adjacent inventories preserve the initial source audit and implementation decisions; their historical pending/not-tested labels are not a substitute for the results below.

## Final verified outcome

The focused [run 40823655253](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40823655253) **passed all three required cases**: the complete grams/serving/recalculation/persistence case, normal-motion navigation and actual-system-Reduce-Motion navigation. Its report confirms no changed production inputs relative to the successfully built `ef485cb`; the application source tree is `625ce2277223328b7eecadab1b49a0bf6cc73555`.

Across the documented same-production-source runs, **18 unique native UI cases passed**: seven calorie-card cases, seven legacy functional cases, two motion cases, independent notification denial, and the system-Reduce-Motion setup case. This is an aggregate of real cases from multiple runs, not one 18-case suite. Core 264/264 and BuildTests 170/170 passed on macOS; both device Release and Simulator Debug compiled. Earlier failed/interrupted runs remain recorded below and are not rewritten as passes.

Both nine-scenario same-Mac performance variants also completed. Their outcomes are mixed and do **not** establish general faster/smoother operation, hardware frame pacing, zero hitches or release acceptance. User visual approval and physical-device validation remain outstanding.

## Revisions and evidence

| Item | Verified revision / run | Result |
|---|---|---|
| Compiled pre-motion review baseline | `9f567b449579d78c22833b06d9d0836bb37b833d`; [baseline build 40749563514](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40749563514) | iPhone Release and Simulator Debug compiled; 264 Core and 169 BuildTests passed. Baseline functional UI failures were recorded separately; this is not an all-tests-passed baseline or a claim of user approval. |
| Original before screenshots | `9f567b449579d78c22833b06d9d0836bb37b833d`; [before capture 40778353065](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40778353065) | 51 original Arabic Simulator screenshots retained with manifests and font audits. |
| Implemented production motion source | `ef485cbae17c519809a6d8dde6ef790f4d7931bd`; [validation 40780795084](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40780795084) | Real iPhone Release and Simulator Debug builds passed; Core 264/264; BuildTests 170/170. Screenshot capture passed. Overall UI validation failed as detailed below. |
| Corrected UI automation and follow-up harness | `88d54e6f1cfff74462b7d7c354c9b83dec22ca63`; [follow-up 40820331550](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40820331550) | **Both normal and actual-system-Reduce-Motion cases passed.** The overall follow-up report failed because the seven-case legacy command exhausted its 1,500-second budget, including a cold app/test compilation. Its log records two completed legacy passes, then interruption in the quantity case; no new numeric assertion failure was recorded. Production source equality to `ef485cb` was verified. |
| Focused quantity and motion recheck | `2fbcc4854694e4bcdbcdaeae792089978d0ffa7f`; [focused follow-up 40823655253](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40823655253) | **3/3 passed.** Complete grams/serving case and both motion cases, with a 2,700-second legacy command budget accommodating cold compilation. This revision changes test/CI budgets, not the production tree. The other six legacy cases already passed against the same `ef485cb` production source; they are not relabeled as new-run passes. |

The production application remains SwiftUI with an iOS 17 minimum. The native evidence above used Xcode 26.6 and iOS Simulator 26.5. Build metadata identifies version 2.9, build 123, bundle `app.luqma.diary`, and arm64. The device Release build is not a distributable Apple-provisioned signed IPA. No new IPA or merge is recorded by this motion review.

## What was actually tested

Run 40780795084 has these independent outcomes:

| Suite / operation | Actual result | Scope |
|---|---|---|
| Core | 264 passed, 0 failed | Real Swift Core test execution, including existing model/calculation contracts; no physical Health records. |
| BuildTests | 170 passed | Real native Mac/SDK/resource checks, including the compiled SwiftUI motion-policy probe; not a test of an iPhone haptic motor. |
| Dedicated calorie-card UI | 7 passed, 0 failed | Real diary add/edit/delete and relaunch persistence, Arabic/English card, goal editor, separate component boundary/extreme-value host, all four real meal-add routes. |
| Main legacy UI on its fresh Simulator | 6 passed, 1 failed | Assessment draft/apply/delete and saved diary, food add/resize/delete, language persistence, allowed notifications/reminder persistence, recipe draft preservation, and tabs/goals passed. The grams/serving case failed during automated text replacement before completing its remaining assertions. |
| Native notification denial | 1 passed on a separate fresh Simulator | Genuine first-run iOS denial and no false delivery claim. Never combined with the allowed-permission case on the same device. |
| New normal-motion navigation case | Failed at final Health Back locator | Repeated actual tab switches and typing `milk`/`rice`, real search dismissal, Health screen, and opening/closing its access guide completed before the failing Back lookup. This original run remains failed; see the passed follow-up below. |
| New system-Reduce-Motion navigation case | Failed at the same final Health Back locator | The helper enabled the genuine iOS setting through Settings UI. The preceding actual interactions completed, but this does not turn the whole failed case into a pass. |

The original run's aggregate JSON lists `passed_tests: []` because its command raised before success parsing. The original XCTest log explicitly records the seven card and six main legacy passes above. The report's overall failure is preserved; no missing success result is inferred or fabricated.

### Recorded UI failures and test-only corrections

1. `testGramAndServingQuantityRecalculateStoredFood`: replacing a centered quantity `0` with `50` left the caret before the original zero, producing `500`. The exact-value assertion correctly failed. The corrected automation uses native selection of that one-digit quantity, including the system Select All action when available; the quantity and nutrition assertions remain unchanged. No calculation or production input logic was altered.
2. Both motion cases: the actual Health header exposed a visible, enabled `Back` button whose accessibility identifier was inherited as `health.screen`. The test incorrectly required `navigation.back`. Corrected automation uses the genuine visible Back action and requires a hittable Settings Health row after the pop, rather than merely accepting an offscreen element.

These are changes to the test interaction paths, not changes to the app source or nutritional calculations. The first failures remain historical results of run 40780795084. The actual follow-up evidence below verifies the corrected Health Back path; the full grams/serving case still requires its focused completion result.

### Follow-up results actually inspected

The downloaded SHA-verified `work/Motion-Followup-40820331550/report.json`, `native-motion/scenario-report.json` and native XCTest logs record:

| Operation | Actual result | Scope |
|---|---|---|
| Normal-motion navigation | **Passed** (`testNativeTabsSearchAndDismissal`, 85.976 seconds) | Actual repeated tab switches, search typing/dismissal, Health screen, access guide and Back to Settings; real native controls. |
| System-Reduce-Motion navigation | **Passed** (`testReduceMotionTabsSearchAndDismissal`, 78.396 seconds) | The genuine Settings preference was enabled through native UI, then the same complete navigation/Health-guide/Back flow passed. No simulated permission or fake health measurement. |
| Native-motion suite | **2 passed, 0 failed** | Actual XCTest total 164.372 seconds. This confirms these defined interactions, not FPS, smoothness on a physical device or every animation. |
| Seven-case legacy command | **Timed out after 1,500 seconds** | The budget included cold app/test compilation. The log records assessment passing (726.940 seconds) and food CRUD passing (196.153 seconds), then the quantity case was interrupted. This is not a completed quantity pass or a new numeric assertion failure. Remaining cases in that command were not verified by the timed-out attempt. |
| Overall follow-up report | **Failed** | The native-motion scenario continued independently after the legacy timeout and passed. A successful child scenario does not make the parent report successful. |

The report verifies `identical_production_inputs: true`, no production input changes, and production source tree `625ce2277223328b7eecadab1b49a0bf6cc73555` for the `ef485cb` application. Latest revision `2fbcc4854694e4bcdbcdaeae792089978d0ffa7f` retains that production source; only test/CI scope and timeout handling changed. The narrow quantity helper change applies only to replacing `portion.amount` equal to `0`; exact amount and nutrition assertions are retained.

Run 40823655253 passed the **full grams/serving case plus the two motion cases**; it did not rerun all seven legacy cases. The independent sequential same-Mac performance job from run 40820331550 ([job 123271101508](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40820331550/job/123271101508)) also completed successfully. Separate concurrency groups preserved that measurement while the functional runner was corrected.

The actual successful motion framebuffer movie is **67,728,195 bytes**, recorded by `simctl io recordVideo`; it is not synthetic and is not an FPS measurement. Its review preview is:

`C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/outputs/LUQMA-Passed-Motion-Preview-40820331550/motion-recording/index.html`

The main 51-pair static gallery remains the earlier accurate `ef485cb` capture set, not an invented replacement from the follow-up.

## Native screenshots and static comparison

The verified gallery contains:

- 51 Arabic before screenshots and 51 Arabic after screenshots at original resolution, paired by route/language/size.
- Four additional English after screenshots: Home, Settings, Add Food, assessment age.
- Two additional compact-iPhone Arabic after screenshots: Home and Add Food.
- Original image bytes, SHA-256 manifests, native font audits, derived contact sheets, and explicitly labeled derived difference images.
- 51 before/after RGB comparisons. **25 pairs have zero RGB difference.** This describes those captured frames only; it is not a design-approval percentage or proof of motion smoothness.
- Actual Arabic after-capture SwiftUI audits report `accessibilityReduceMotion == true` with custom progress animation disabled. This came from the actual Simulator Settings UI, not an injected read-only Apple environment key or private preference.
- All captured font audits verified the actual Changa-Bold registration and shaped text runs. English and compact after-only profiles report the ordinary system motion state; their missing before counterparts are not fabricated.

Local review gallery (outside the source repository):

`C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/outputs/LUQMA-Native-Motion-Review-20261029/index.html`

Machine-readable comparison and image provenance:

`C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/outputs/LUQMA-Native-Motion-Review-20261029/comparison-report.json`

Raw build/UI evidence:

`C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/work/Motion-After-40780795084/`

No image alignment, shifting, content masks or rescaling was applied to the pixel comparisons. Status bars, dates and actual changing text remain visible. Screenshots and a screen recording can support visual review, but cannot establish FPS, hitches or a successful interactive flow by themselves.

### Complete 51-pair visual review

The independent visual review recorded in `work/native-motion/visual-review-40780795084.md` and `.json` individually inspected **all 51 comparable Arabic before/after pairs**. Its method used 26 labeled derived QA pages, proportional 360px-wide full frames with no crop, additional Home/Add Food/Assessment Age/Settings contact sheets, and selected original-resolution frames and diagnostic crops. The original PNGs and native audits were not edited. The per-screen JSON records each route, reviewed state, QA-page reference and before/after source hashes.

No new visually apparent static card placement, artwork, font-family, color-system or RTL regression was found in those captured pairs. Dates changed from October 28 to 29; Home also retains the actual return-to-Settings status indicator difference. Weight-plan dates moved accordingly. Photo-component numbers/text and Safety glyph edges have visible pixel differences without an apparent new structural layout shift. These are still-frame findings, not pixel-perfect approval or evidence of smooth animation, touch response or a successful complete flow. The gallery's original `needsVisualReview` flag is preserved as capture-time provenance; this later recorded review does not rewrite that original report or its metrics.

Review records (outside the repository):

- `C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/work/native-motion/visual-review-40780795084.md`
- `C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/work/native-motion/visual-review-40780795084.json`
- `C:/Users/super/Documents/Codex/2026-10-10/https-chatgpt-com-share-6ac9be62-d7a4/work/native-motion/qa-pages-40780795084/pages-provenance.json`

### Retained baseline and viewport limitations

| Captured presentation | Actual visual finding | Verification boundary |
|---|---|---|
| Normal `assessment-age` | The short DEBUG fixture-description line immediately below the fixed assessment header is clipped in both before and after; the selected age and wheel otherwise retain their appearance. That pair has zero RGB difference. | Existing controlled-preview clipping was not repaired by changing the locked layout during motion work. It does not establish that every production assessment state is free of clipping. |
| Normal `assessment-target` | The DEBUG fixture-description line is almost entirely hidden below the fixed header in both captures; only small glyph dots remain visible. The goal field and options otherwise retain their appearance. | Retained baseline/fixture issue; no app-layout repair was made in this motion-only scope. |
| `accessibility-assessment-age` | The initial viewport partly places the lower part of selected `30` behind the fixed Continue footer, in both captures. | A still image does **not** show whether scrolling exposes the value. Runtime scrolling, reachability and keyboard access for this exact large-text state remain unverified. |
| `accessibility-assessment-goal` and `accessibility-assessment-safety` | Lower large-text options extend below the initial viewport/fixed footer in both before and after. | This is not proof that the choices are permanently unreachable. Scrolling and actual touch access require separate runtime validation. |
| Other forms and lists | Several controls/content regions extend below the captured viewport, as expected for scrollable content. | A rendered initial viewport alone does not verify all offscreen controls, keyboard access or touch targets. |
| Barcode, analysis and result fixtures | Barcode is explicitly the camera-off guide preview; analysis/result/component frames use labeled controlled inputs. | No still frame proves live camera operation, real remote extraction/AI success or real user nutrition results. |

The visual-review agent changed no application source, design, asset, original screenshot or audit. All issues above remain documented without unrelated layout edits. Visual review does not erase the original UI-run failures or the later legacy timeout; the separately verified final three-case success is reported above.

## Complete View-file coverage

All 24 Swift files in `Luqma/Views`, plus the application root, were included in discovery. “Rendered” means actual native SwiftUI execution; it does not imply a real user meal, real remote analysis or real Health data. “Controlled fixture” means explicitly labeled preview inputs, separate from functional test data entered through production controls.

| Source file / nested units | Implemented or preserved behavior | Evidence and remaining limits |
|---|---|---|
| `Luqma/LuqmaApp.swift` — App, RootView, launch continuation, native preview audit | Stable existing tabs/navigation, selected icon/underline motion, press feedback, actual system Reduce Motion, original 96pt mark continuation; original routes/commit closures retained | Home/tab screenshots; actual tab/search/Health-guide/Back flows passed in both normal and actual-system-Reduce-Motion follow-up cases. No physical launch/frame budget verified. |
| `AppleHealthView.swift` — HealthSettingsView, HealthMetricRow | Existing connect/refresh/cancel/disconnect/access guide retained; actual available numbers animate; success requires an existing successful-sync timestamp and readable data | Real no-data Health UI, access guide open/close and Back to Settings passed in both follow-up motion cases. No native authorization grant or real record query verified here. |
| `AssessmentFlowView.swift` — AssessmentFlowView, CFARadioIndicator, approved button style, activity arc and shapes | Native selection/press/number motion; activity thumb follows drag immediately; helper shapes/dimensions retained | Goal/gender/activity previews rendered; full assessment flow passed via existing controls. Static arc rendering is not an independent proof of every arc-drag path. |
| `AssessmentNumberPickers.swift` — age wheel, height/weight ruler, unit selection, raw input and neighbor controls | Unit/button motion only; editable buffers, clamping, gesture mapping and persistence remain immediate | Real assessment test exercised manual values, invalid values, ruler/wheel drags, back/next, draft save/relaunch/resume; passed. Controlled age/height/weight/target and accessibility previews also rendered. |
| `Common.swift` — headers, button styles, rings, pills, NumericInput, NutritionView, FoodRow, Notice, SandowNavigationChrome | Shared press/progress/read-only-number motion; original fonts/frames/colors and native keyboard/menu/sheet behavior retained | Shared components rendered across the gallery and exercised in real diary/goal/assessment flows. Every possible menu option or transient combination is not separately proven. |
| `DailyCalorieCard.swift` — native card, progress bars and layout | Real nullable values, zero-width zero progress, numeric/bar animation; same approved card rather than a replacement ring | Seven dedicated card UI cases passed, plus 18 separate native component presentation cases. Fixtures are not live diary data. |
| `DailyMealCard.swift` — four category cards and layout | Actual saved kcal/macros, existing artwork and add route; press/numeric motion with immediate accessibility data | All four genuine meal routes passed and native screenshots retained. Category artwork is not represented as the user's photographed meal. |
| `DiaryView.swift` — DiaryView, CalorieIntakeDetailView, EntryEditor | Day/category/disclosure/count changes, actual seven-day chart values, native editing/deletion and stable row identity | Actual add/edit/delete/relaunch and calorie-history route passed. Same-source complete grams/serving recalculation and stored-entry preservation passed in focused run 40823655253; the original failed/interrupted automation remains recorded above. |
| `EditorialImagery.swift` — EditorialArtwork, EditorialFill, EditorialPanel | Source/resources unchanged; no autonomous decorative image motion | Existing assets rendered; this static file does not need a new animation loop. |
| `FitnessAssessmentView.swift` — eleven pages, FitnessNumberField, review/edit actions | Scoped page/selection transitions, true validation feedback; editable text, save/resume, suitability rejection and double-action guards unchanged | Full actual draft/apply/delete/preserved-diary assessment case passed. Controlled page fixtures and larger-text views rendered; not every cross-product of answers was UI-tested. |
| `FitnessProfileView.swift` — profile, FitnessPlanReviewView, FitnessDetailRow | Existing empty/draft/applied/manual/deleted states, real target numbers, disclosure and successful-apply feedback | Actual profile apply, relaunch, delete confirmation and preserved diary/targets passed; controlled profile/review/plan frames rendered. |
| `FoodAddView.swift` — search and FoodPortionView, quantity sheet, serving options | Press, small semantic selection/content changes, readonly nutrition motion; search debounce/cancellation, native inputs and save contracts unchanged | Real food CRUD and four category routes passed. Dedicated full grams/servings case passed in focused run 40823655253, including exact nutrition and preserved original entry. Search typing/dismissal and subsequent navigation passed in both follow-up motion cases; no broad online product-catalog accuracy claim. |
| `GeminiSettingsView.swift` — secure setup, advanced disclosure, reset dialog | Actual configured/message changes and conditional feedback; credential operations and privacy unchanged | Native connection-settings presentation rendered using controlled state. No private key creation, external activation request or real remote model run verified. |
| `GoalEditor.swift` — hero, sliders, macro tiles, calorie and macro editor sheets | Actual readonly targets animate; editable NumericInput, balancing rules and native sheets unchanged | Actual calorie edit/save/relaunch and diary target update passed. Main goal screen rendered; every grams/percent macro-editor input combination is not separately UI-verified. |
| `HealthActivityViews.swift` — extended readings, weight history, workouts, daily history, progress card, Health button style | Existing real-data/missing states, bounded history/list motion, native settings link retained; no query or entitlement changes | No-data progress/Health presentations and settings navigation reached. Real Health history, workouts, permission flow, observer updates and physical readings unverified. |
| `KitchenView.swift` — KitchenView, RecipeDetailView, RecipeEditor | Existing categories/lists/notes/ingredients/checkboxes and native detail/editor presentations with scoped motion | Kitchen, recipe-editor and detail frames rendered; actual recipe draft preserved across ingredient-search dismissal passed. Complete recipe creation/edit/delete permutations not independently verified. |
| `LuqmaMotion.swift` — central presets, press/value/numeric/feedback/transition/loading/scan modifiers | iOS 17-native finite animation, actual-value source, conditional feedback and foreground/Reduce Motion gating; no timers or new motion library | Actual SwiftUI source compiled for SDK targets and native Mac policy probe passed within BuildTests. Still images do not verify physical haptics or continuous-frame smoothness. |
| `LuqmaTypography.swift` — typography/cache/modifier/font audit | Unchanged Changa Bold resources, role sizes and shaping | Actual native font audits verified registration and Arabic/English/digit runs. No font substitution made by motion work. |
| `NotificationsView.swift` — NotificationsView, RemindersView, ReminderTimeEditor | Real delivered/pending counts, bounded period/count list motion, true saved feedback; native time picker, reset/clear dialogs, permissions retained | Allowed-permission/reminder persistence and independent denied-permission case passed. No proof of physical notification arrival, Focus/Scheduled Summary behavior or device haptic output. |
| `PhotoMealView.swift` — analysis/camera presentation, result/components, PhotoEstimateEditor | Actual processing-scoped scan/loading motion, read-only estimate changes and native editors; no fake progress or completion | Controlled scan/result/components and initial photo UI rendered. Physical camera, fresh AI analysis, live accuracy, remote latency and all editor/logging paths unverified here. |
| `PlanView.swift` — weight-plan form, optional measurements, calculation result/chart | Original model/task/stale-result guard retained; actual result/read-only metric changes and real apply feedback | Weight-plan presentation rendered. Existing Core calculations passed; this is not a complete native UI test of weight-plan calculation/apply variants. |
| `ProgressView.swift` — ProgressViewScreen, WeightEditor | Actual numeric/history/chart/range motion; original native entry/edit form retained | Progress, weight editor and weight-plan frames rendered. Real tab navigation completed; complete manual weight CRUD, chart dragging and large-history device performance unverified. |
| `RecipeImportView.swift` — source input, draft, ingredient editors, notes/steps | Actual extraction-stage/draft/saved motion; pending-edit validation and service request/cancel contracts retained | Initial import presentation and controlled recipe examples rendered. Actual Instagram/TikTok/YouTube extraction, remote network success/failure, cancellation timing and full import save unverified here. |
| `SettingsView.swift` — SettingsView, LuqmaLanguageView, BackupSettingsView, AboutLuqmaView, ImportPreview/BackupDocument | Existing destinations/sheets, file panels, selected language, busy state and count motion; native merge/export semantics retained | Settings/language/backup/about frames rendered; actual language and goal persistence passed. Backup import/export round trip and every destination not independently tested in this run. |
| `StateComponents.swift` — operation, error, empty, saved confirmation | Existing text/artwork/actions with opacity transition; operation-only glyph motion; no invented success or delay | Controlled state-error/loading/empty/success frames rendered. These do not prove that a real server, camera, save or Health action succeeded. |

### Native and external surfaces outside the 24 View files

- Existing `Services/Camera.swift` UIKit camera/photo picker, AVCapture barcode preview, scanner controller/guide and actual scan region were inspected and preserved. Native view compilation or a barcode-guide screenshot is not a hardware camera test.
- Existing sheet/full-screen, navigation, alert/dialog, date/time picker, menu, segmented control, toggle, slider, file importer/exporter and keyboard presentations remain native iOS behavior. The motion pass does not replace them with custom fake controls.
- Pure shapes and layout utilities remain measurement/drawing helpers. No independent loop is added to static artwork, typography or idle screens.
- HealthKit entitlements, provisioning, signing identity, bundle identity and privacy/data-transfer policy were not changed by the motion pass. Missing or denied data is not converted to fake measurements.

## Performance and remaining validation

No FPS, device frame-time distribution, physical haptic output, battery/energy, thermal impact or physical ProMotion result is established by this gallery. The available native recording is genuine framebuffer video, not a measured FPS indicator or proof of a hitch-free application.

The same-Mac job measured baseline `9f567b4` then motion `88d54e6`, on one CI Mac, with identical package resolution, fixture, harness, runtime and tools. Production code in the final functional revision is identical to that measured motion revision. All nine cases passed on both variants; there are 59 normalized metric rows. Three samples were taken per scenario, five for responsive process launch. This is a small sequential sample, subject to cache, order and shared-host scheduling effects.

| Actual metric | Before median | After median | Unit / interpretation |
|---|---:|---:|---|
| ApplicationFirstFramePresentationResponsive | 4.9421 | 3.7045 | seconds; terminated-process launch after cache warm-up, not reboot-cold launch |
| Four-tab round trip, clock | 10.6432 | 9.4892 | seconds; includes UI automation overhead, not single-tap latency |
| Search to quantity, clock | 4.7543 | 4.7062 | seconds; includes automation overhead |
| Expanded diary scroll scenario, clock | 12.7598 | 16.1849 | seconds; **higher after motion** |
| Scroll_DraggingAndDeceleration duration | 2.6016 | 2.5826 | seconds; duration is not FPS or hitch count |
| Expanded diary process CPU time | 15.8218 | 14.2655 | CPU seconds, not CPU-utilization percentage |
| Expanded diary peak physical memory | 86612.608 | 79124.992 | kB; observed medians, not proof of leak freedom |

The after-scroll clock samples were **25.4582, 12.2604, 16.1849 seconds**, versus **13.1117, 12.7598, 12.6258** before. After population standard deviation was 5.5335 seconds (before 0.2049). All samples are preserved; no outlier was discarded to claim improvement. The mixed wall-clock/CPU/memory findings do not identify a causal rendering bottleneck or establish smoother scrolling. The earlier different-host run also had mixed results, reinforcing the need for physical profiling before a performance acceptance claim.

No hitch metric was exported. Zero-valued Simulator CPU-cycle and retired-instruction counters are not evidence of zero CPU work. FPS, frame-time distribution, energy, thermal impact, leak freedom and physical ProMotion remain **Not Measured**. Minimum-target iOS 17 runtime rendering was not independently exercised; the native runtime used was iOS 26.5.

Remaining acceptance work:

1. Functional review evidence is complete for the defined 18 unique cases across runs; preserve every original failure/timeout alongside the final passed focused result. Performance acceptance remains unverified: investigate the noisy slower scroll clock on real hardware before claiming smoother scrolling.
2. Obtain visual acceptance using the completed 51-pair review and review the actual motion recording. Still-frame review and the 25 exact RGB pairs do not independently approve interactive motion; retain the baseline/viewport limitations above until separately validated.
3. Verify physical camera/barcode, Health authorization and real readable records using a legitimately authorized signature/device when available.
4. Verify physical haptic behavior, Reduce Motion changes during use, meaningful device frame pacing and resource impact where equipment permits.
5. Obtain the user's visual approval before merging or issuing a final IPA/release.

No hardware/remote scenario above is labeled passed from a mock, screenshot fixture, Simulator-only success or completed animation.

Final passed recording and excerpts: `outputs/LUQMA-Native-Motion-Review-20261029/motion-recording/index.html`, source run 40823655253. Its complete three-case parent report passed. The earlier preview from 40820331550 is retained separately and still discloses its unrelated legacy timeout.
