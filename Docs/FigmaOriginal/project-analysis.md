# Phase 2 — current Luqma project audit

Audited read-only on 2026-10-16. Repository: `work/Loqma-iphone`. HEAD: `e48897be8390c8118ea1a62125894d92d129c7de`. Working tree was clean at audit start. `git diff b9c0f7cfeb058472f33592ffbb61ed260bceecef e48897be8390c8118ea1a62125894d92d129c7de -- Luqma` is empty: current app source matches the delivered 2.3/build59 source; intervening commit content is documentation. No app edits, branch changes, commits, builds, external service requests or publishing were performed for this audit.

The latest pasted user task requires direct Figma connection proof before new UI implementation, a new implementation branch and a pull request, and no merge to main. Older reconstruction evidence must not substitute for the new extraction requirement.

## 1. Stack and directories

- Native Swift 5 / SwiftUI iPhone app, iOS 17 minimum. `Package.swift:1` uses Swift tools 5.9 for the portable `LuqmaCore` target; `Scripts/build_project.py:82,98` sets iOS17 and marketing version2.3.
- `Luqma/LuqmaApp.swift`: app startup, store ownership, four tab routes, shared nav, modal routes and DEBUG-only capture fixtures.
- `Luqma/Views`: 12 Swift files containing principal screens, forms, shared components and typography.
- `Luqma/Core`: 24 portable Swift files for nutrition, models, search, validation, recipe extraction/recalculation, estimates, weight model, formatting and legacy health compatibility.
- `Luqma/Services`: 8 Swift files for persistence, food database actor, provider calls, credentials, camera and legacy local vision engines.
- `Luqma/Resources`: food JSON/provenance, eleven font files/two OFL licences, localizations, privacy manifest, app icon and Luqma logo. Assets catalog has no Sandow food photo imagesets.
- `Tests`: Swift core tests and fixtures. `BuildTests`: Python build/font/capture harness tests. `Scripts`: project generation, native build, screenshots and dataset/legacy model tooling.
- `.github/workflows/ios-build.yml:52` selects macOS26/Xcode26.6 and runs the existing native/test/IPA/capture pipeline. This phase did not rerun it.
- Project packages are pinned in `Scripts/build_project.py:72-78`: onnxruntime1.24.2, mlx-swift-lm2.30.6, mlx-swift0.30.6, swift-transformers1.1.6. These remain linked for legacy local vision code; primary current meal UI does not invoke those engines.

## 2. Navigation and screen map of the existing app

| Existing destination | File / entry | Real behavior that must remain |
|---|---|---|
| Today | `Luqma/Views/DiaryView.swift:5` | Selected day/date picker, keyword search, four meal summaries, daily calories/macros/goals, seven-day history, entries and expand/edit actions |
| Food search / product selection | `Luqma/Views/FoodAddView.swift:7` | All/recent/frequent/private food filters, local suggestions and matches, nearby products, explicit remote search/pagination, barcode, photo and manual-food entry |
| Food quantity/manual-food editor | `FoodAddView.swift:346` | Default serving quantity1, source serving/portion choices, g/ml units, nutrition/reference edits, actual meal choice and validation |
| Meal photo input and review | `Luqma/Views/PhotoMealView.swift:5` | Capture/select photo, optional context, analysis/cancel/error, component gram/calorie/macro review, weight edit, delete/add/catalog replacement, meal selection and logging |
| Entry editor | `DiaryView.swift:398` | Resize saved amount, show scaled values, save or delete the existing entry |
| Kitchen | `Luqma/Views/KitchenView.swift:4` | Search/filter actual saved recipes/meals/prep; create, import link, edit, delete and log by serving/cooked grams |
| Recipe editor | `KitchenView.swift:173` | Ingredient selection/deletion, servings/cooked weight, totals, notes, source and preparation steps |
| Link recipe import | `Luqma/Views/RecipeImportView.swift:3` | Link/pasted-text extraction, stages/cancel/errors, review/edit ingredient quantities, source evidence, save actual recipe |
| Progress and weight editor | `Luqma/Views/ProgressView.swift:4,96` | Actual weight/range chart/history, log/delete reading, plan access, adaptive calorie setting and weekly average |
| Weight plan | `Luqma/Views/PlanView.swift:4` | Existing physiological inputs, calculation, trajectory and apply action |
| Goals | `Luqma/Views/GoalEditor.swift:3` | Calorie target and balanced editable macro grams/percentages |
| Settings | `Luqma/Views/SettingsView.swift:11` | Goal/plan access, Arabic/English preference, meal-analysis connection, backup and About/privacy |
| Backup / import confirmation / About | `SettingsView.swift:65,117,93` | Export/import merge, preview counts, preserved original data and source/privacy/design information |
| Analysis connection | `Luqma/Views/GeminiSettingsView.swift` | Keychain connection setup/status, validation, import compatibility and removal |
| Barcode camera | `Luqma/Services/Camera.swift:18,95` | Real camera permission/session, scan guide and matching metadata region, actual barcode result |

`LuqmaApp.swift:78-84` retains `TabView` with four per-tab `NavigationStack`s. Native tab chrome is hidden, and a shared custom icon bar is installed via `safeAreaInset`. Its center add control presents `FoodAddView`. Diary and root logging callbacks commit into the selected day or today respectively. Sheets and pushed settings destinations are already wired; replacing visual composition must preserve these callbacks and dismissal paths. DEBUG fixtures are isolated from normal data and service calls.

## 3. Shared UI and state ownership

- `LuqmaApp.swift:5,18,34-37`: `AppServices` owns one `DiaryStore`; `@StateObject` injects it as an environment object. App environment chooses Arabic RTL/English LTR, locale/calendar and existing dark appearance.
- `Services/DiaryStore.swift:5-13`: `@MainActor ObservableObject` exposes read-only published `DiarySnapshot`, error and adaptive message. Views keep ephemeral interaction state in `@State`; changing the design must not make another persistent store.
- `Views/Common.swift:3-23`: existing theme, card, background and form modifiers. Tokens currently cover a small palette and one card radius, not the complete Figma spacing/radius/shadow/gradient/component system.
- `Common.swift:25-187`: headers, button styles, progress rings, pills, numeric input, nutrition display, food rows and notices.
- `Common.swift:190-230`: custom `sandowNavigation` modifier supplies compact title/back control and optional bottom action; all existing enablement/back/save closures must remain intact.
- `Views/LuqmaTypography.swift:7-120`: Work Sans primary with explicit Tajawal Arabic cascade, cached CTFonts and live Dynamic Type via ScaledMetric. Eleven bundled faces are registered in `Info.plist`; Arabic free companion was explicitly approved earlier. Exact Figma font-file version and all per-style metrics are not established by that fact.

## 4. Data, calories and storage

- `Core/Models.swift:19-26`: `Nutrition` stores kcal/protein/carbs/fat and supports addition and scaling. Default goals are2000kcal/125g protein/225g carbs/66.666…g fat; these are defaults, not Figma sample constants.
- `Models.swift:45-118`: foods retain actual per100 or serving nutrition, source identifiers, declared serving/portion options and units. `Food.total` validates consumed quantity and uses `servings × nutrition` or `amount/100 × nutrition`.
- `Models.swift:120-125`: a `DiaryEntry` snapshots nutrition for the actual eaten amount. Resize scales by `newAmount/oldAmount`; the UI must not multiply nutrition by amount a second time.
- `Core/MealDiarySummary.swift:11`: a single pass groups actual day entries into the four meals and sums their already-scaled nutrition.
- `Models.swift:127-133`: recipe totals sum ingredient nutrition; per serving divides by declared yield; cooked grams use final cooked weight. These models have no recipe/food image or imageURL field.
- `Core/MacroBalance.swift:8-11`: macro editing preserves calorie energy using4/4/9 and balances the remaining macros. `Core/WeightModel.swift:18-35` owns the existing weight simulation/calorie goals. `DiaryStore.swift:88-96` adapts only with a saved plan, enabled setting and at least three weekly readings.
- `DiaryStore.swift:14-37`: user state is one Codable JSON document at Documents/`luqma-diary.json`, written atomically with complete file protection. Load/unlock/recovery guards protect an unreadable original; state changes publish only after successful validation/write.
- `Core/Backup.swift:52-84`: validated encode/decode/merge; import updates matching records without discarding all current data. `Models.swift:138` keeps version2 and legacy fields decodable.
- `Services/GeminiCredentialStore.swift:5-40`: credentials are a nonsynchronizing device Keychain item keyed by bundle identifier, accessible when unlocked on this device; they are not diary/backup fields. Preserve bundle/keychain semantics and do not print or copy a credential.

## 5. Food sources and external services

- `Services/FoodDatabase.swift:7,33-76`: actor-owned local indexes, history and normalized/suggestion/fuzzy matching run away from the keyboard/main actor. It loads six bundled OFF foods plus744 supplied-IPA records, total750; saved/private foods and history remain distinct. Source-specific integrity rules remain in Core search/history/product parsers.
- `FoodDatabase.swift:118-177`: bounded explicit network requests, cache, cancellation and429 backoff. Network search is not sent on every keystroke.
- `FoodDatabase.swift:207-226`: authoritative product details from `world.openfoodfacts.org/api/v3.6/product/{code}.json`, retaining real unit and serving information before logging.
- `FoodDatabase.swift:285-300`: explicit paginated POST search to `search.openfoodfacts.org/search`,50 rows/page; local exact/nearby ranking is not replaced by the presentation.
- `Core/AnalysisModel.swift:8-34`: current configured IDs are `gemini-3.1-flash-lite` and bounded fallback `gemini-3.5-flash-lite`, calling Google `generateContent`. These are facts from current source, not new model availability/performance recommendations. Photo/recipe/video timeouts22/28/40 seconds, backup15.
- `Services/GeminiMealService.swift:33-76`: Keychain load,1280px JPEG preparation, low-signal photo guard, bounded actor request/fallback/cancellation and short-lived four-result cache. `Core/GeminiMeal.swift` defines schema/prompt and parses returned components; no model filename import is required by the current primary route.
- `Core/MealPhotoEstimate.swift:25-120`: estimates validate finite weight/nutrition, uncertainty ranges and plausible mass/energy; weight edits scale once and retain metadata. They cannot prove measured photo calorie accuracy. `PhotoMealView` materializes each validated estimate as one serving; catalog replacements keep real units.
- `Services/RecipeImportService.swift:51-141`: URL/pasted text, source reading, stages and bounded provider retrieval/caching. `Core/RecipeSource.swift:154-227` handles structured page/caption text, public URL restrictions and TikTok oEmbed; Instagram/TikTok may lack accessible complete recipe content. `Core/RecipeImport.swift:222-300` requests source-grounded extraction and checks URL/YouTube source evidence. UI work must preserve explicit inaccessible/partial states instead of fabricating a recipe.
- `Services/Camera.swift:95-190`: queued capture start/stop lifecycle, barcode output types and actual metadata rect; the guide is not only a decorative overlay.
- Apple Health controls, entitlements and permission strings are absent as previously requested. Legacy Core/state fields remain for backup compatibility; `DiaryStore.dailyGoals` returns the saved goals without activity inflation. Do not re-enable Health as a side effect of copying a fitness design.
- Legacy `PhotoAnalyzer` and `VisionAnalyzer` remain in the repository/packages. Current PhotoMealView uses only `PhotoAnalyzer.image` for local image preview, then `GeminiMealService` for analysis; no current screen invokes the legacy local recognition pipeline.

## 6. Specific remaining fidelity gaps at this baseline

These observations compare the existing source and actual build59 captures with previously saved visible Sandow previews. They are an audit of current gaps, not authoritative new node measurements; Phase1 direct extraction must establish any newly accessible specifications before implementation.

1. Original static food photography and custom icons are absent. Optional image names `SandowBreakfast/Lunch/Dinner/Snack/Kitchen` have no local imagesets; routine and kitchen therefore render generic semantic artwork. The exact source assets must replace those fallbacks when available, with their actual crop and slot. Models have no dynamic persisted food-photo field, so a generic image must not silently claim to depict a user's saved recipe.
2. Main Today is a functional adaptation combining nutrition home, calorie goal/progress and My Meals. Figma's saved preview separates nutrition browsing, intake graph and My Meals flows. Component ordering and destination mapping are not yet proven equivalent. The current carousel is72% container width, an earlier visual estimate, not an extracted instance width/constraint.
3. Source contains inline approximations for many point sizes, card heights, padding, radii and gradients. Current tokens are insufficient to demonstrate original Auto Layout/constraint/variant/style equivalence.
4. Current icons use generic SF Symbols. They must be replaced only where the direct extraction supplies actual original assets or deterministic SF Symbol names; no guessed replacement should be called exact.
5. Search is compact and functional, but the current app chips reflect All/Recent/Frequent/private foods, whereas the extracted reference shows generic fitness-wide categories such as Workouts/Meals/Community. A visual chip cannot introduce fake category filtering or discard these required food filters. Sort/filter/best-match controls need explicit screen mapping against available source components.
6. Photo review now puts the selected image before a centered total and gray/orange/blue macro columns, but component ratios, crop, title, annotation/result variants and success presentation remain reconstruction values. The large neutral image in build59 is a DEBUG fixture placeholder, not a successful real image analysis or an imported Figma image.
7. Settings/progress/secondary forms now have compact shared headers, but the shared rectangular back/buttons, grouped row geometry and bottom CTA are not yet traced to extracted per-screen component/variant data. One modifier must not force equivalence between intentionally different original screens.
8. Arabic Tajawal and RTL preserve existing functionality but cannot literally reproduce English Work Sans strings/glyph geometry. Compare both at a defined language/data state; exact original font size/weight/line-height/tracking should become named tokens when available.
9. The delivered capture set has20 original1320×2868 Simulator frames. Those are useful baseline implementation images, not Figma exports or overlays. Historical test records report172 Swift/61 Python tests and Release compilation, but this project-analysis phase ran none of those. It did not perform a visual comparison, physical camera/FPS/keyboard or network/provider test. The later exploratory overlay and pixel difference are documented separately in `baseline/comparison-report.json`; they are not a fidelity acceptance test or SSIM score.

## 7. Change boundaries for the new implementation

Preserve `Core`, service actors, persisted schema, API endpoints/provider policy, normalization/ranking/units, error/cancellation/loading states, Keychain, backup/recovery and barcode lifecycle. Implement the extracted design in existing Views/shared tokens/assets and routing only as required by proven screen mapping. Use the existing actual-data callbacks. Create the required new branch and PR; do not push this audit or UI changes to main and do not merge without the user's approval.
