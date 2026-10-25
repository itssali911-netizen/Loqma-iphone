# Nutrition exact reference — actual SwiftUI Home

**Historical implementation report.** The user's subsequent Sandow v1.2 component-board request supersedes the palette/typeface choices below. See `Docs/SandowComponentSystem/README-AR.md` for the current pass. The earlier ZIP remains an unchanged recovery snapshot.

Local implementation, 25 October 2026. Branch: `feature/nutrition-exact-home`.
Base: `7007dfc72ddb622bb5bb0b4ea5ba6643b9494d39`.
Recovery tag: `checkpoint/pre-nutrition-exact-home-20261025`.
No commit, push, deployment, credentials change or production-data migration was performed.

## What changed

The default `RootView → DiaryView` now renders `NutritionHomeView`, not a React/WebView mockup. It uses **only exactReferenceTheme** for Home and its new dialogs. No Studio header, preview toggles, explanatory text, device frame or 345-point phone border is installed in the app.

The native layout preserves the grey header/search, horizontal blue category selection, horizontal morning cards, orange calorie card, **Meals** hero, browse rows and the 54×44 orange add action. The main content uses 16-point insets/section gaps. The 345-point reference is a validation size, not a hardcoded native viewport. Arabic uses the existing licensed Tajawal family; English and isolated numeric islands use native SF. Sizes below 12 points are scoped to these views; the rest of the app's typography has not been changed. Dynamic Type and Reduce Motion are respected.

### Real actions and data

| Control | Application behavior |
|---|---|
| Header/date/avatar/bell | Actual selected date, daily consumption and delivered-notification count; existing date chooser, fitness profile and notification routes |
| Search | Debounced, cancellable matching of the local meal list; submit/magnifier opens the existing complete food search with the query |
| Categories | Actual name-based Arabic/English filtering, all query words required; **Meals** / See All restores all saved meal rows |
| Morning/Meals cards | Selected-day breakfast entries, saved recipes and foods; original reference examples only where that source is empty |
| Add food/meal | Existing portion editor for known foods; new complete manual serving form for custom meals; existing catalog/camera/barcode/search remain available |
| Remove/details/quantity | Selected-day entry matching; confirmation before removal; context menu and detail action open existing quantity editor |
| Calorie goal | Draft until Confirm; existing `DiaryStore.setGoals`, balanced macro goals and persistence; full original goal editor remains linked |
| Progress | Actual consumed / target; it does not add the reference's fictional base 251 kcal or independent 64% value |
| History/navigation | Existing seven-day calorie view, all four tabs, assessment, recipes, reminders and other routes retained |
| Detailed daily diary | Linked below browse to retain the original per-meal macro summaries, disclosure/edit controls and other daily functions |

Totals sum the already scaled `DiaryEntry.nutrition` once. Cards and saved recipe suggestions do not add anything until an actual entry is saved. Repeated taps are guarded during saving. New custom food requires calories, protein, carbs and fat: absent macros are never converted to zero. Examples cannot become a `Food` until complete values are entered. Real foods do not acquire invented ratings, preparation times or a “healthy” verdict; unavailable metadata is an em dash. Existing storage schema, nutritional conversion functions, API contracts and AI integration are unchanged.

The search index is prepared on diary/date changes, not per keypress. Only normalized strings/IDs pass to a detached cancellable filter task after 150 ms debounce. Browse uses stable entry IDs and `LazyVStack`; morning uses `LazyHStack`. No new display link, timer loop, backend or third-party native runtime was added. These are implementation facts, **not measured speed/FPS claims**.

## Source inspection and explicit conflicts

All six supplied files were inspected: README, DESIGN_SYSTEM_SPEC, JSON tokens, variables.css, tailwind.config.js, App.jsx.
ZIP SHA-256: `13f069469a930e2c1bb790840a699e65b4a3f9570bd48bb7e876f5720e5d137b`.

The supplied `App.jsx` is syntactically damaged at its initial `BROWSE_MEALS_LIST` image string: an unterminated string runs into the phone root JSX. The component/state/data prefix and `renderExactScreen` declaration are missing. The retained screen JSX is usable, but the original file **does not build**. The original six files were not edited. A separate browser harness reconstructs the missing prefix/data from specification section 6, mounts only the retained exact-screen body, and records every repair. Its handlers are reconstructed behavior, not recovered original application logic. The supplied package has no package.json or image/font binaries.

The repaired reference was actually built and run in the browser at width 345. Where CSS and written values conflict, rendered JSX/CSS guides the native implementation:

| Property | Written spec/token | Rendered retained JSX/CSS used |
|---|---|---|
| Greeting | 20/800, line height 1.2 | 20/800, `leading-tight` = 25 / 1.25; tracking −0.5 |
| Section headings | tracking −0.015 em | `tracking-tight` = −0.025 em = −0.35 at 14; 21 line height |
| Search | spec line height 1.4 | 13/500, Tailwind normal 19.5 / 1.5 |
| Hero title | line height 1.35 | `leading-snug` = 22 / 1.375 at 16 |
| Browse title | token 1.35 | `leading-snug` = 1.375 |
| Badge/metadata | some written compact values | Tailwind normal 1.5; badge includes 4+4 padding |
| RTL decorative plate | JSX physical `right:0` | Spec explicitly says left in Arabic; harness/native use logical trailing without mirroring the bitmap |
| Browse border | 12 padding plus 1 border | Native 12 padding plus 1 border allowance, not an arbitrary reduced row size |

Text tracking is applied to `Text` **before** the opaque custom font modifier, per [Apple's Text.tracking API](https://developer.apple.com/documentation/swiftui/text/tracking(_:)). Native font rasterization/line metrics and shadows still need an actual iPhone comparison.

## Assets and remaining differences

The package points at `/assets/food-placeholder.jpg`, which is not supplied. Matching avatar/food photographs cannot be recovered from those paths.

| Asset | Actual source / status |
|---|---|
| 22 `NutritionExact*.imageset` SVGs | Official `lucide-react` 1.61.0 vectors, matching source stroke/fill variants; MIT license copied to `Luqma/Resources/Lucide-LICENSE.txt` |
| Breakfast/lunch/dinner/snack imagery | Existing `Assets.xcassets/Editorial/LuqmaEditorial{Breakfast,Lunch,Dinner,Snack}`; previously generated for this project, provenance retained in `Docs/PremiumImagery/asset-manifest.json`; **temporary substitutes, not matching reference meals or actual user photos** |
| Avatar | Existing `LuqmaMark`; no real user avatar/name exists in the persisted profile. Generic greeting replaces fictitious Makise |
| Arabic font | Existing Tajawal Regular/Medium/Bold/ExtraBold binaries and OFL; allowed by the supplied spec, no font download/replacement |
| English font | Native SF, an allowed family; the Windows browser harness uses Tajawal because Apple SF is not installed there |

Illustrations are visibly labelled in the native cards and described as substitutes in details. Examples are visibly marked. These notices can change text/height versus the fictional reference, particularly with Dynamic Type. They prevent a decorative image or an incomplete example from masquerading as a real logged meal.

Other deliberate functional/platform adaptations:

- The retained source's morning See All opens its first card, and Meals See All cycles featured meals; native uses those same actions.
- The original filter predicate was missing. Native category filtering is functional; the repaired React harness retains query-only filtering and demonstrates category selection styling. Its fourth category id says seafood while its visible label says Meals; native maps the visible Meals category to all saved meals.
- Reference “Hungry/Satisfied,” popularity, health tags, ratings/time, notification 8, fixed date/user and base calories are examples. Native uses truthful available data, “logged/not logged,” saved-meal wording and unknown placeholders as appropriate.
- Existing bottom tab destinations stay reachable around the new add button; the reference only contains a floating plus. The native plus stays completely within Safe Area instead of being clipped at bottom −12.
- Dialogs use native SwiftUI sheets with the supplied modal surface/border/radii/spacing, keyboard handling and close actions. Reference add/goal dialogs are centered HTML overlays. Native adds required macro fields, meal selection and links to complete existing editors. Details expose actual nutrition; these are not a pixel-identical modal composition.
- The complete old diary is retained as a secondary route; its existing style remains unchanged. All screens outside this Home scope retain their original design.

These differences are explicit; no claim of 100% visual equivalence is made.

## Validation — actual results

| Check | Result |
|---|---|
| Reference build | Passed with repaired prefix, React 19.3.1, esbuild 0.28.2, Tailwind 3.4.17; not an iOS build |
| Reference browser | Arabic/English 345-point captures; all seven displayed images loaded after avatar repair; add/remove 251→502→251, query filtering, goal change, meal details and custom fixture addition observed |
| Xcode project generation | Passed: 63 app Swift files, 29 resource entries; four new app files and Lucide license registered |
| Existing Python BuildTests, baseline/new | Both 77 total: 73 passed, 2 skipped (native font probes), 2 failed (existing POSIX 0600/0640 expectations on Windows); no new failure |
| Swift grammar differential | 95 files inspected versus 90 baseline; no new diagnostics. The two existing tree-sitter limitations (`MacroBalance.swift` semicolon, `PhotoMeal.swift` `$1`) persist. **Not type checking** |
| New core tests | 12 XCTest cases written for totals, serving scaling, date isolation, deduplication, real recipe matching, unknown nutrition and Arabic search/category behavior; **not executed** |
| Native interaction tests | Existing seven routes adapted; one new case checks incomplete macros, custom serving save and goal cancellation. Eight cases registered. **Not executed** |
| Native performance scenarios | Nine existing selectors retained; Home logging/search routes adapted. Browse scrolling replaces the old disclosure scenario and needs a fresh baseline; no comparison claimed |
| Native build attempt | Stops at the existing macOS/Xcode environment guard. No Swift compiler, xcodebuild or xcrun is present on this Windows host |
| App screenshots / UI comparison | **Unavailable for this implementation**; included JPEGs are the repaired React reference, never labelled as SwiftUI output |
| Multiple iPhone sizes, keyboard, native RTL/AX/Dynamic Type, navigation, persistence | Implemented in code and covered in prepared tests, but actual native runtime validation remains required |
| Device FPS, memory, energy | Not measured; no ProMotion/device claims |

## Modified paths and reproducibility

New app sources: `Luqma/Core/NutritionHomeData.swift`, `Luqma/Views/NutritionExactTheme.swift`, `Luqma/Views/NutritionHomeView.swift`, `Luqma/Views/NutritionHomeSheets.swift`.
Existing sources changed: `Luqma/LuqmaApp.swift`, `Luqma/Views/DiaryView.swift`.
Tests/runner: `Tests/NutritionHomeDataTests.swift`, `TestsUI/LuqmaInteractionTests.swift`, `TestsUI/LuqmaPerformanceTests.swift`, `Scripts/ui_interactions.py`.
Project: `Luqma.xcodeproj/project.pbxproj` regenerated by the unchanged project generator.
Assets/license: 22 `Luqma/Resources/Assets.xcassets/NutritionExact*.imageset/{Contents.json,icon.svg}`, `Luqma/Resources/Lucide-LICENSE.txt`.
This report and `Docs/NutritionExactHome-manifest.json` list/prove the integration. The manifest enumerates exact modified paths and SHA-256 values.

On a Mac with Xcode: run `swift test`, `python3 -B -m unittest discover -s BuildTests -v`, `python3 Scripts/build_ios.py check --output BuildOutput/NutritionExactCheck`, and `python3 Scripts/ui_interactions.py --help` for the existing actual-simulator runner. Use fresh output directories and run all eight actual controls tests before distributing a build. Capture the new Home from the app itself in Arabic/English at 345-equivalent, small and large phone sizes and accessibility text sizes before making visual-fidelity or release-readiness claims.
