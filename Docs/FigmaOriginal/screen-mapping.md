# Phase 3 — evidenced screen mapping and unresolved scope

Date: 2026-10-16. App baseline: `e48897be8390c8118ea1a62125894d92d129c7de`, whose app source matches built source `b9c0f7cfeb058472f33592ffbb61ed260bceecef` (2.3/build59). Mapping is read-only. No app, Figma canvas, branch, PR or published source was changed by this audit.

## Evidence and meaning of the mapping

Direct MCP connection proof is in `connection-proof.json`. The exact target nodes are:

| Figma parent | Actual name | Parent dimensions in Figma | Only exposed image child | Downloaded original image |
|---|---|---|---|---|
| `2:10108` | Diet & Nutrition Management | 5460 × 2119.482421875 | `2:10109` | `reference/nutrition-original.png`, 4096 × 1590 |
| `2:10112` | Search Screen | 2387 × 1292 | `2:10113` | `reference/search-original.png`, 2387 × 1292 |
| `2:10120` | Profile Settings & Help Center | 5899 × 2232.28759765625 | `2:10121` | `reference/settings-original.png`, 4096 × 1550 |

Each target exposes one flattened IMAGE rectangle, not individual original screen/component layers. The labels N01–N12, S01–S05 and P01–P13 below are audit labels for **visible raster regions**, not Figma node IDs or invented original frame names. Region coordinates are approximate pixel bounding boxes `(left, top, right, bottom)` in the downloaded original image. They are only for locating evidence and possible visual comparison; they are **not** original Auto Layout, constraints, component padding, text metrics or implementation geometry. No individual nutrition/search/settings screen can presently be verified as an extracted original subframe.

All three downloaded images were opened and inspected directly for this mapping. Their contents remain usable reference evidence, but a flattened panel cannot supply missing per-element parameters or standalone original photography. Never crop its food pictures into application assets or embed the panel as a replacement app screen.

## A. Visible nutrition regions

| Audit region | Visible screen/content | Approximate original-image region | Existing Luqma mapping | Scope / missing correspondence |
|---|---|---|---|---|
| N01 | Nutrition & Diet introduction with vegetables and Explore | `(96,264,378,878)` | No existing nutrition onboarding destination | Intro artwork/navigation analogue only. Do not invent a profile, onboarding persistence or nutrition recommendation service. |
| N02 | Nutrition home: greeting/search, category chips, Morning Routine, Calorie Goal, AI Suggestion and Browse Meals | `(424,264,708,1396)` | `Views/DiaryView.swift` main Today; selected portions of `KitchenView.swift` | Actual day/meal/goal data can supply relevant metric slots. No current AI recommendation list, ratings, prep-time database, user profile photo or food thumbnails. Do not populate sample meals/ratings/calories as user data. |
| N03 | Calorie Intake: kcal, date/month control, orange line/area graph and macro summary | `(754,264,1038,878)` | `DiaryView` actual intake history / daily totals | Direct metric analogue for calories. `ProgressViewScreen` is a weight-in-kg chart, so sharing this styling is only a visual analogue, not the same screen or data. |
| N04 | My Meals: week strip, Breakfast/Lunch/Dinner selector, photo meal cards and add button | `(1084,264,1368,1094)` | `DiaryView` selected day, `mealList`, entry details and add; `KitchenView` actual saved cards only as a secondary analogue | Strong functional match to the diary. Kitchen's Recipe/Meal/Prep filter has different semantics; do not turn it into a fake day/meal dataset. Existing snack access and recipe import must remain reachable. |
| N05 | Add New Meal: Manual/AI Scan, meal name/type, macro/calorie input sliders, thumbnail, note and Continue | `(1414,264,1698,1224)` | `FoodAddView` mode entry, `FoodPortionView(manual:true)`, `PhotoMealView`, `RecipeEditor` only where actual fields correspond | Can map existing manual and photo entry navigation. Reference suggestions/thumbnail settings have no current stored field/service. Do not replace source serving/unit validation with ungrounded sliders or imply saved thumbnail support. |
| N06 | Calorie Goal: large kcal, orange adjustment, macro tiles, status message and Set Calorie Goal | `(1742,264,2026,878)` | `Views/GoalEditor.swift` | Existing balanced calorie/macros and validation are the functional source. Do not copy sample2500, arbitrary status success or reference macro numbers. |
| N07 | Food Analysis scanning: orange fruit, scan guide, scanning badge and camera tools | `(2072,264,2356,878)` | `PhotoMealView` camera/input/busy state; `Services/Camera.swift` barcode guide only as a separate scanner analogue | Photo uses normal camera/photo picker, not a live ingredient-annotation camera. Barcode is a real product scanner. Do not display fake real-time food recognition or replace its actual barcode region. |
| N08 | Food Analysis identified fruit with floating nutrient/weight labels and bottom selected-food card | `(2402,264,2686,878)` | `PhotoMealView` completed components only as a result analogue | Current primary analysis returns component estimates, not verified spatial annotation boxes over the image. Never place invented bounding labels or measured weights. |
| N09 | Mandarin Orange result: source image, category/weight pills, kcal and three macro columns, Add Meal | `(2730,264,3014,878)` | `PhotoMealView` result summary, quantity editor, meal selection and logging; `FoodPortionView` quantity only as secondary analogue | Strong result-UI analogue with actual image and estimate data. All displayed grams/kcal/macros must remain actual values/estimates; no sample fruit or nutrition substitution. Detailed component rows are app-specific extensions. |
| N10 | Meal recommendation: food hero, title/category, duration/kcal and See Details | `(3060,264,3344,878)` | `KitchenView` actual saved recipe card / route to existing editor | Card/detail visual analogue only. No current recommendation ranking, preparation-time field or creator rating. |
| N11 | Meal detail: food hero, title, tabs, overview, ingredient checklist, gallery, ordered instructions and Add Meal | `(3390,264,3674,1498)` | `RecipeEditor` plus actual `RecipeImportView` review/source steps | Ingredients, real quantities, servings, notes and source steps can map. No gallery/ratings/photo persistence fields; don't fabricate them or hide existing source uncertainty. Editing a recipe and reading a recommendation are distinct interactions. |
| N12 | Food Added success overlay over meal image | `(3720,264,4004,878)` | Existing successful `FoodCommit` / `PhotoFoodCommit` callbacks and dismissal | Only show success after persistence returns true. Current app dismisses on success; any visual success state must not double-log or mask failure. No individual original overlay geometry is exposed. |

## B. Visible search regions

The original Search Screen is **app-wide fitness search**, not a food-product search. It includes Workouts/Meals/Community categories and AI-coach/workout results. Luqma has actual food-source/history/private-food filters, catalog results, best-match and nearby-product logic. Match its visual slots without inventing coaches, communities, categories, dates or match percentages.

| Audit region | Visible state | Approximate original-image region | Existing Luqma mapping | Scope / missing correspondence |
|---|---|---|---|---|
| S01 | Search with orange shared header, query, chips and loading spinner | `(128,353,503,1166)` | `FoodAddView` header + actual `busy/choosingFood/pageLoading` | Preserve current task/cancellation controls and show loading only during real work. |
| S02 | Query suggestions/dropdown with system keyboard | `(568,353,943,1166)` | `FoodAddView` actual local suggestions / history and TextField focus | Use real `FoodSuggestion` values. Keyboard is device-rendered, not a static panel asset. |
| S03 | No result, magnifying-glass illustration and explanatory text | `(1006,353,1381,1166)` | `FoodAddView` true empty state after completed local/remote lookup | Distinguish no results, offline/error, incomplete product and no search yet. Original illustration is visible only inside the panel, not obtained as a standalone asset. |
| S04 | Result count, Match% dropdown, compact icon/text/tag result rows | `(1445,353,1820,1166)` | `FoodAddView.resultsContent`, actual best/nearby result grouping, `Common.FoodRow` | Count can use actual returned rows. Do not invent numeric match percentages, result links to nonexistent fitness features or arbitrary sortable fields. |
| S05 | Filter Search Results sheet: date range, search limit, category, AI toggle and Apply | `(1885,353,2260,1166)` | No exact existing filter sheet; actual All/Recent/Frequent/My foods controls may occupy an explicitly mapped filter surface | Original filter semantics are not backed by current food search. A visual-only control that changes nothing fails functional preservation. Retain existing filters without pretending they implement these unrelated fields. |

## C. Visible profile/settings regions

| Audit region | Visible screen/content | Approximate original-image region | Existing Luqma mapping | Scope / missing correspondence |
|---|---|---|---|---|
| P01 | Profile dashboard with portrait, score and fitness metrics | `(88,244,350,810)` | No user-profile/fitness-score screen; portions of actual Today/Progress are only metric-style analogues | No profile photo, score, steps, heart rate or badge backend. Do not copy sample profile/metrics. |
| P02 | Account Settings grouped rows, security/help, close account and sign out | `(394,244,658,1464)` | `Views/SettingsView.swift` main groups and existing destinations | Strong grouped-row/chrome analogue. Luqma has no account/session/notifications/coach/biometric system; do not add dead rows or fake account actions. |
| P03 | Personal Info form, weight/sex/location/account type and Save | `(698,244,962,988)` | `PlanView` real physiological inputs and `WeightEditor` weight/date as field-style analogues only | Not an original weight-plan/editor frame. Preserve existing model inputs and validation; no fabricated account/person/address/password values. |
| P04 | Notification Settings toggle groups and Save | `(1002,244,1266,1024)` | No corresponding notification settings feature | Do not add nonfunctional switches or notification permission requests merely to match this preview. |
| P05 | Security Settings, authenticator toggles and Save | `(1306,244,1570,930)` | No matching account/security feature | Existing Keychain connection is not an account authenticator. Do not conflate them. |
| P06 | Xiaomi Watch8 connection and tools | `(1610,244,1874,810)` | No active connected-device screen | Apple Health was explicitly removed earlier. No implied watch connection, device metric or Health reactivation. |
| P07 | Language selection plus bilingual feature | `(1914,244,2178,910)` | `SettingsView` actual Arabic/English language preference | Only the two real supported languages can be selectable. A bilingual-feature toggle and six other language choices lack current behavior. |
| P08 | About Us with logo, address/telephone and social links | `(2218,244,2482,810)` | `AboutLuqmaView` real app/version/privacy/data sources/design attribution | Use Luqma branding and true information. Do not copy fictitious Sandow contact/address/social data into Luqma. |
| P09 | Help Center FAQ, search and expand/collapse questions | `(2522,244,2786,914)` | Existing About/privacy/setup guidance only as a potential help-content analogue | No current FAQ search/data screen. Retain real help/analysis connection/backup access; do not populate unrelated fitness claims. |
| P10 | Help Center live-chat introduction and Start Live Chat | `(2826,244,3090,810)` | No live support service | Do not create a dead support affordance or promise a human response. |
| P11 | Live Chat conversation | `(3130,244,3394,810)` | No chat data/service | No fabricated messages or contact. |
| P12 | Referral code/copy/share | `(3434,244,3698,810)` | No referral service | No generated promotional code, reward or sample referrals. |
| P13 | Submit Feedback rating/topic chips and submit | `(3738,244,4002,810)` | No existing feedback transport | Do not show successful submission without a real authorized route. |

## D. Complete existing-screen/function coverage

This checklist includes existing destinations and significant states, even when the retrieved three panels have no direct source screen. “No direct screen” means absent from these retrieved targets; it does not claim that an uninspected page in the14-page file contains none.

| Existing screen / state | Proposed visual source | Verification classification and functions to preserve |
|---|---|---|
| Today normal / populated / empty | N02 + N03 + N04 | Raster analogues only; selected day, actual totals/goals and four meals must remain. Combined screen ordering is unresolved. |
| Date/week picker | Week strip inside N04; no graphical date-picker frame | Week-strip raster analogue; current graphical picker still needed for arbitrary dates. No original picker subframe available. |
| Meal list / expanded entry details | N04 | Raster analogue; actual logged items and P/C/F totals, add/edit/delete access. |
| Saved entry amount editor | N05/P03 field styles only | No direct original screen; scale the stored nutrition once, save/delete and keep date/meal association. |
| Search initial / loading / suggestions / empty / results | S01–S04 | Raster state analogues; real local/remote data, filters, cancellation and error distinctions. |
| Best match / nearby products / pagination | S04 result rows/dropdown only | No exact food-search variants; actual ranking, brand safety and incomplete-product handling remain. |
| Food serving/quantity editor | N05/N09 only | No exact original subframe; Serving1, source portions, g/ml semantics, food/meal selection and validation. |
| Manual food entry | N05 | Raster analogue; actual editable reference nutrition, unit and private-food persistence. |
| Barcode camera guide / permission / manual barcode / barcode-from-photo | N07 camera styling only | No original barcode-specific frame; real rectOfInterest, lifecycle, supported barcode types, failure and dismissal behavior remain. |
| Meal photo select/capture/context | N05 AI Scan entry + N07 | Raster analogue; actual selected image, camera permission, context and explicit analysis action. |
| Meal analysis busy/cancel/error | N07 | No exact native busy/error variants; show actual task status, cancellation and provider errors. |
| Meal result summary / add success | N09 + N12 | Raster analogue; real image and validated estimates, truthful uncertainty, commit succeeds before success UI. |
| Ingredient compact/detail/gram editor / catalog replacement | N09 summary; N11 ingredient section only | App-specific detailed estimate functions have no matching original screen. Preserve weight/kcal/macros/range/quantity edit/delete/add/product matching and complete-total validation. |
| Kitchen all/recipe/meal/prep + search + empty state | N04/N10 cards | Visual analogue, not same day/meal semantics. Real saved data and create/import/edit/delete/log access. |
| Recipe editor / servings / cooked weight / notes | N05 + N11 | Raster analogues only. Ingredients, quantity calculations, notes/source/steps and actual validation. |
| Recipe link import input / stages / error / review | N11 recipe content only | No original URL/social import screen; preserve public-source handling, pasted-text fallback, cancellation, quantities, source evidence and save. |
| Calorie/macro goals | N06 | Raster analogue; actual balanced goals and save/cancel. |
| Weight progress / selected range / history / adaptive toggle | N03 graph + P01 metric styling only | No direct weight-progress source among the retrieved panels. Keep kg, real date ranges/history/delete and saved adaptive behavior. |
| Weight editor | P03 field styling only | No original weight/date editor subframe. Existing one reading/day and validation. |
| Weight plan and calculated result | P03 field styling only | No original physiological-plan/trajectory frame. Preserve inputs, model, apply and error states. |
| Main settings | P02 | Raster analogue; only functional goals/plan/language/connection/backup/About rows. |
| Arabic/English preference | P07 | Raster analogue; actual two-language environment and western digits. |
| Analysis connection settings | None; P02/P03 form chrome only | No original API/connection screen. Existing Keychain configure/status/remove/import compatibility stays reachable. |
| Backup export/import | None | No original backup subframe; preserve actual file operations and validation. |
| Backup import confirmation | None | No original merge-confirmation subframe; actual counts, merge semantics, cancel/confirm. |
| About/privacy/source attribution | P08 | Raster analogue for structure; true Luqma information and existing source/licence/privacy links. |

`Common.swift` shared elements—navigation chrome, button styles, cards, numeric input, nutrition labels, food rows, notices and progress displays—must be mapped to exact extracted instances/variants when those become available. Original Top Nav `2:10015`343×48, Button Primary Icon `2:10013`343×56 and status instance `2:10019`375×44 are verified examples from available editable content, not proof that every flattened advanced screen uses identical metrics.

## E. What is proved, and what is still blocked

- Proved: live MCP access to the correct file;14 page names; three target-panel names/dimensions/image children; original panel image downloads; several actual editable instances, Work Sans styles and original colors; repository and functional audit; all visible regions and existing destinations mapped above.
- Not proved: all-page detailed inventory, all original screen nodes, advanced component instances/variants, per-element constraints/Auto Layout, original standalone food photos/custom icons, complete typography/spacing/effects, every prototype relationship or motion.
- Current access limit: several page inventory responses exceeded the server20480-byte return limit, then Starter MCP quota stopped more reads. No more MCP calls are attempted in this mapping task and no results are invented.
- Current app has20 baseline native Simulator screenshots. They are implementation evidence, not reference exports, screenshot overlays or proof of a fresh visual diff. No new tests or app runtime captures were run for this mapping.
- No pixel-perfect or100% claim is supported. The user's full acceptance criteria are **not complete**. Creating an extraction/baseline PR can make the work reviewable, but must explicitly remain incomplete and must not be merged without user approval.
- The original panels can support a reviewable visual baseline and locating corresponding views. They must not be used as an excuse to invent missing geometry, invent business logic, discard app features, substitute generic original assets or claim that every original screen has been ported.
