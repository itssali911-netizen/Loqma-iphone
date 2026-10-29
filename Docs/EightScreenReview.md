# LUQMA eight-screen source implementation — awaiting native and visual approval

Status: published review branch. The actual Simulator Debug build and 32 native captures passed. iPhone Release, 264 Core cases, 170 build/font checks and four real native interaction cases passed. Final visual approval is pending the user. Nothing has been merged or released.

## Source and scope

Repository: `itssali911-netizen/Loqma-iphone`.

Baseline: `798a0f4f45aad23fdeac235a417d345988cf5c34`, the tip of `feature/native-motion-review-20261028` when inspected. This is newer than `main` and already includes the approved Changa Bold, HealthKit, food camera, home-card and native-motion work. Review branch: `review/premium-eight-screens-20261029`.

The eight supplied photographs of existing screens and the two overview boards were inspected. They are raster references, not editable design sources. Their small labels and photographed display colors cannot establish exact component specifications. This change uses existing source tokens and component dimensions, and explicitly identifies derived geometry below. No image generation or simulated application was used.

## Design tokens and provenance

These are source-verified implementation values, not newly measured values from the attached master raster or a fresh Figma inspection.

| Role | Value | Source |
|---|---|---|
| Background | `#111214` | `Luqma/Core/VisualDesignTokens.swift`, via `Theme.background` |
| Card | `#24262B` | Same, via `Theme.card` |
| Secondary surface | `#393C43` | Same, via `Theme.surface` |
| Primary action | `#F97316` | Same, via `Theme.accent` |
| Primary-action text | `#111214` | `onAccent = background` in the same source |
| Text | `#FFFFFF` | Same, `text` |
| Secondary text | `#B8BBC2` | Same, `textSecondary` |
| Accent text on dark surfaces | `#FDBA74` | Same, `accentText`; kept distinct from the action fill for contrast |
| Dividers / unfocused input outline | `#545861` | Same, `divider` |
| Secondary accent | `#2563EB` | Same; retained in the existing theme, not used as the new recipe-page surface |
| Success | `#86EFAC` | Same, `success` |
| Warning | `#FDE68A` | Same, `warning` |
| Error text / background / border | `#FCA5A5` / `#450A0A` / `#EF4444` | Same, existing alert roles |
| Protein | `#EF798E` | Approved `DailyCalorieCard.swift`, reused by the scoped macro component |
| Carbohydrate | `#E8B34C` | Same |
| Fat | `#8FBE63` | Same |

The historic V5 palette (`#111416`, `#22282B`, `#D78957`) differs from this baseline's documented Sandow source. Existing `UI-SOURCES.txt` records the dark Figma source `IfMCdTI3FcvXpNFy79PRUA`, page `2:606`, with `#111214`, `#24262B`, `#393C43`, and `#F97316`. The existing source-backed theme has been retained without a global palette change.

Already-approved home and food-portion components also contain local color variations, including home accent `#FF7515` and portion accent `#F97318`. Those files were deliberately left byte-for-byte unchanged. This review does not claim those historic discrepancies have been eliminated across the entire application.

| Geometry / type role | Value | Source |
|---|---|---|
| Card radius | 20 pt | Existing `Theme.cardRadius` in `Common.swift` |
| Navigation minimum height | 48 pt | Existing `Theme.navigationHeight` |
| Primary / secondary button minimum height | 56 / 48 pt | Existing shared button styles |
| Shared button radius | 16 pt | Existing shared button styles |
| Horizontal margin / section gap / card padding | 16 pt | Existing screen and card padding |
| Row gap / input radius | 12 pt | Existing shared/screen control geometry |
| Compact hit target | At least 44 pt | Existing controls; selector items now use that minimum |
| Selector track / selected-item radius | 14 / 10 pt | Existing kitchen category component |
| New shutter | 56 pt inner, 72 pt outer, 3 pt outline | Derived from the existing 56 pt primary control and 16 pt spacing; not asserted to be master-source measurements |
| Metric / prominent entry | 32 / 36 pt, Dynamic Type scaled | Existing `LTypography.Descriptor.metric` / `.display` |
| Section / main label / supporting text | 17 / 16 / 13 pt | Existing section header and typography descriptors |
| Compact labels | 12 pt minimum, Dynamic Type scaled | Existing caption policy in `LuqmaTypography.swift` |
| Press / selection / content / numeric motion | 0.14 / 0.20 / 0.24 / 0.30 s | Existing `LuqmaMotion.swift` |

Existing `Changa-Bold.ttf` is reused for Arabic, Latin, digits, units and punctuation. Its declared PostScript name is `Changa-Bold`, weight class 700; SHA-256 is `d2015fb807cdd2cdc4d2f539db75117f7f009e407fe9d4b3e7555d94c4ff2c9f`. The unchanged provenance file pins the official `googlefonts/changa-vf` commit `fb3207d4fe7234f610d0d4ef77dce01cfda57027`; the unchanged `Info.plist` and project copy phase register and bundle it. SF Symbols retain their symbol font. Apple-controlled keyboards, permission dialogs, and native picker internals are not claimed to use a custom font.

## Changes to each screen

| Screen | Implemented source changes |
|---|---|
| 01 — My Kitchen | Compact dark header; charcoal search; shared equal-width selectors; clear create/import actions; smaller existing kitchen art; removed duplicated empty-state create button. Search, filters, creation, import, menus and existing tabs remain connected. |
| 02 — Progress | Pinned compact title; concise no-data summary; real latest weight and existing validated weekly average; shared period selector; explicit Changa chart labels; compact plan navigation; real history and HealthKit card retained. |
| 03 — Weight Plan | Five clear sections; visible editable inputs; no preselected sex for a new plan; blank missing measurements; activity presets alongside custom PAL; existing activity slider range; one persistent calculate/apply action; result scroll; advanced inputs never masquerade as measured values. Existing model validation and Hall calculations remain unchanged. |
| 04 — Recipe Details | Readable name; one primary calorie summary; approved macro vectors and colors; neutral edit action; compact ingredient card; existing serving/gram actions, checkboxes, instructions, source and uncertainty notes retained. The model has no recipe-image field; no image or schema was fabricated. |
| 05 — Save to My Kitchen | Clear multiline name; shared type selector; numeric serving/cooked-weight controls; consistent macro summary and section labels; keyboard-dismiss control; invalid serving/cooked weights disable save. Existing ingredient deletion, ingredient search, metadata, draft preservation and storage formulas remain connected. |
| 06 — Detailed Meal Analysis | Shared compact/detailed selector; smaller calorie labels; matching macro icons; quantities, edit/remove actions, database matching, uncertainty ranges and assumptions retained. |
| 07 — AI Meal Analysis | Real inline AVFoundation preview when camera access and hardware are available; recognizable shutter; album import; explicit unavailable/permission/retry states; optional description/privacy disclosure; actual-analysis-only scan sweep; source-token nutrition summary. Capturing calls the existing service when configured; an unconfigured service opens setup. No successful service response is simulated in production. |
| 08 — Weight Entry | Prominent editable weight; compact date picker; numeric keyboard and dismiss action; bottom-safe-area save; finite 35–300 kg validation; existing date restrictions and one-reading-per-day persistence retained. Save success follows the actual store result. |

The new camera is view-layer capture plumbing for screen 07. It leaves `Camera.swift`, service endpoints, analysis response parsing, database schema and nutrition logic unchanged. Capture configuration/start/stop are confined to a serial queue; requested visibility is locked; capture results are delivered to the main queue. Physical capture and lifecycle still need native testing.

## Files

Application changes:

- `Luqma/Views/KitchenView.swift` — kitchen, recipe details and recipe editor.
- `Luqma/Views/ProgressView.swift` — progress and weight entry.
- `Luqma/Views/PlanView.swift` — weight-plan configuration.
- `Luqma/Views/PhotoMealView.swift` — analysis input and detailed components.
- `Luqma/Views/LuqmaRefinedUI.swift` — scoped shared components.
- `Luqma/Views/LuqmaMealCamera.swift` — real inline capture surface.
- `Luqma.xcodeproj/project.pbxproj` — membership for the two new sources and new native test file only.

Review support:

- `TestsUI/EightScreenReviewTests.swift` — native validation, same-day weight replacement/relaunch, Arabic recipe draft return.
- `Scripts/eight_screen_native_tests.py` — run new and existing interaction cases on disposable Simulators.
- `.github/workflows/eight-screen-review.yml` — published before/after native build and capture job.
- `.github/workflows/eight-screen-functional.yml` — native functional follow-up with identical-application source guard and reused Debug build.
- `Scripts/eight_screen_source_audit.py` — baseline scope and font identity audit.
- `Docs/EightScreenReviewAudit.json`, `Docs/EightScreenNativeEvidence.json`, `Docs/EightScreenReview.md` — source audit, native evidence and this report.

## Verification and limitations

| Check | Actual status |
|---|---|
| Core model/data suite on macOS | 264 passed; zero failures |
| Build/font/SDK suite on macOS | 170 passed; zero skipped; zero failures |
| Earlier local Python validation | 148 passed; 22 native checks skipped on Linux |
| Swift syntax parsing | 27 view/test files parsed using Tree-sitter Swift; no syntax errors; this is not Swift type checking |
| Whitespace/diff validation | `git diff --check` passed |
| Project generation | Generated by the existing project generator; source and native-test membership included |
| Font binary identity, registration declarations, glyph coverage, copy-phase membership | Existing local font checks passed |
| Models, services, HealthKit, typography, existing assets, approved home/portion files, bottom navigation | Byte-for-byte baseline comparison; see audit JSON |
| Xcode Simulator Debug build | Passed on the real GitHub macOS runner with Xcode 26.6 |
| iPhone Release build | Passed, Release iPhoneOS target, unsigned for this review |
| Actual runtime Changa rendering / shaping | Passed on all 32 capture processes; 12 representative font roles per process; only Changa-Bold for the tested Arabic/Latin/digit runs; zero missing glyphs |
| RTL, English, wrapping and safe areas | 32 actual frames inspected: Arabic on iPhone 13 mini and iPhone 16 Pro Max, English on iPhone 13 mini. These are viewport captures, not proof of all scrolled or keyboard states |
| Picker interaction, keyboard avoidance and persistence | Four native interaction cases passed on the identical application source; they exercise input, save, dismiss, relaunch and draft return. Apple-controlled picker internals retain system rendering |
| Navigation and persistence | Passed: persisted-weight validation/same-day replacement/relaunch, Arabic recipe-name draft return, existing cooked-weight draft return, and tab navigation/goal persistence |
| Reduce Motion | Existing policy reused; actual native environment validation pending |
| Before/after native screenshots | Captured: eight before + eight after in Arabic at 1125 × 2436. Also eight Arabic large-iPhone and eight English compact-iPhone after captures. iOS 26.5 runtime |
| Camera and AI | No real-device camera test or live AI request performed; no personal API credentials requested or used |
| Visual approval | Pending the user's review of actual native outputs |

The user explicitly authorized publishing the isolated review branch and workflow. The source was published as commit `bd661d731ccb7e1e089c251f5c4083699751c8e7` and built by [native review run 40875601612](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40875601612). The baseline remains `798a0f4f45aad23fdeac235a417d345988cf5c34`.

The actual capture reports and their per-process font audits are preserved in the workflow artifacts. Eight before/after comparison panels were composed outside the phone frames without modifying screenshot contents. Original frames, comparison panels, and runtime audit JSON are provided in [the screenshot archive](https://chatgpt.com/library?file_id=libfile_5f20d965bd048191aa839eabec75f5d9&account_id=personal).

## Native review outputs

The published workflow is scoped to the isolated review branch:

1. Before: eight actual Arabic screenshots from baseline `798a0f4`, on iPhone 13 mini.
2. After: the same eight on iPhone 13 mini, Arabic.
3. After: the same eight on iPhone 16 Pro Max, Arabic.
4. After: the same eight on iPhone 13 mini, English.
5. Per-process UIKit/CoreText font audits, source revision and build logs.
6. Unchanged Core tests, native font/build checks and four actual interaction tests — passed in the corrected functional follow-up.

Capture routes are `kitchen`, `progress`, `weight-plan`, `recipe-details`, `recipe-editor`, `photo-components`, `approved-scan`, and `weight-editor`. Recipe and analysis data in the existing DEBUG preview routes are explicitly synthetic fixtures; they are not user records or live AI success. Camera-unavailable Simulator output cannot verify physical live capture. The 32 available native frames were visually inspected and the eight comparison panels were prepared for the user. No claim is made that every keyboard, scrolled, error, Reduce Motion or physical-device state has passed. The corrected native functional follow-up passed all four selected cases; its source guard verified application files are identical to the captured revision. The further repeat with an explicit caret-position assertion also passed all four native cases in run 40883328892, on identical application source. Passing compilation alone does not mark this review approved.

## Final native verification evidence

[Functional run 40882626673](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40882626673) passed all four selected cases. The runner verified that `Luqma/` and `Luqma.xcodeproj/` match captured application commit `bd661d731ccb7e1e089c251f5c4083699751c8e7` exactly. Its two real XCTest scenario reports each list two passing cases.

The first UI harness failed because it compared the restored string `82.60` with `82.6`; the stored numeric weight was correct. The corrected test compares the numeric result. The application's code and rendered screenshots did not change for that correction. The additional caret-position assertion run 40883328892 also passed; it is recorded separately in the native evidence JSON.

The original visual run passed the real iPhone Release build, the real Debug Simulator build, all 32 screenshot/font captures, 264 Core tests and 170 build/font checks. Its overall result is red because of that initial UI-test string mismatch; it must not be represented as an entirely passing run.
