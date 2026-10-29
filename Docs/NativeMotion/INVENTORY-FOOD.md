# Food, analysis and recipe motion audit

Status: historical initial read-only inventory and plan, recorded before baseline approval. The motion pass was subsequently implemented; the implementation notes below preserve that sequence. Current build, capture and functional outcomes are in [VALIDATION-AND-COVERAGE.md](VALIDATION-AND-COVERAGE.md).

## Source baseline

Commit: `9f567b449579d78c22833b06d9d0836bb37b833d`

- `Luqma/Views/FoodAddView.swift` SHA256 `9b5d2567984c912e4aa9697ac6134c2082fe988f25efb6039786289feb90a5a5`
- `Luqma/Views/PhotoMealView.swift` SHA256 `e21354248b107fc0550b253c7346743d2a35ca04e27bfa637f18007bce726168`
- `Luqma/Views/RecipeImportView.swift` SHA256 `c3f03a56cda2d9d170ab72ca0616eca6f29c3d964a915458b5586038f937b5f9`
- `Luqma/Services/Camera.swift` SHA256 `273c1e9b03cb67df47f39c888ac6b1e84e553c630a10f9a17ced4afa4c3ce6f9`

## Screen and interaction inventory

### FoodAddView.swift

- Main NavigationStack: search, barcode, existing embedded PhotoMealView tab. Product selection mode intentionally omits analysis.
- Search: empty-query history, recent/frequent/personal filters, query input and clear control, suggestion list, best match, nearby matches, ordinary results, result counts, pagination and source-window continuation.
- Loading: local/catalog refresh, remote search, product detail resolution, pagination, barcode photo loading and lookup. Existing SandowOperationState supports real cancellation.
- Error/empty: SearchNotice with warning/error and optional Settings action; native empty-results illustration and explanation; no cached result; invalid barcode; unavailable/denied camera.
- Presentations: selected-food sheet, manual-food sheet, BarcodeCamera sheet with native navigation. Barcode PhotosPicker is a native presentation.
- Request lifecycle: query token, 280ms debounce, task cancellation, local history worker and all service calls must remain unchanged. No animations tied to every text change and no delayed service execution.

### FoodPortionView (inside FoodAddView.swift)

- Manual entry and existing analysis mode callback; name and calorie/macronutrient inputs; read-only catalog nutrition.
- Meal Menu and optional category controls; quantity chip; native quantity editor sheet with grams/ml/servings, source portion Picker, explicit serving-weight field and quantity summary.
- Additional-options disclosure; nutritional editing mode; invalid/empty quantity and nutrition; duplicate-save guard; synchronous real commit and dismissal.
- Existing custom animation: Additional Options uses Reduce Motion-aware easeInOut160ms. Other selection and numeric states have no custom animation.
- Existing FocusState and simultaneous native tap focus must remain intact. Do not animate TextFields, their editing buffers, cursor movement or source-reference conversion.

### PhotoMealView.swift

- Initial analysis header, service settings, library PhotosPicker and native real camera.
- Scan viewfinder: approved illustrative artwork when no real photo exists; otherwise actual prepared photo with existing native brackets/beam/gradient.
- Loading: actual image import, image preparation, analysis request; each task has cancellation/generation ownership. No fake progress, delayed analysis, or analysis inferred from animation ending.
- Errors: image open/prepare failure, service failure, missing service setup, camera permission/unavailability, foreground cancellation, memory-warning cancellation.
- Results: real hero image, meal title/known weight, calorie estimate/range/share of target, macro columns or accessibility progress layout, log-meal button.
- Component list: compact/detailed mode, known/missing nutrition, weight/calories, add/remove, estimated weight editor and catalog matching.
- Presentations: CameraPhoto sheet, GeminiSettingsView sheet, PhotoEstimateEditor sheet, full-screen FoodAddView product selection.
- PhotoEstimateEditor: native Form/NavigationStack; weight NumericInput; recalculated actual estimate; validation; Save/Cancel.
- No custom repeat loops or explicit animation currently present.

### RecipeImportView.swift

- Native NavigationStack; URL input and paste-text DisclosureGroup; source/privacy explanation.
- Initial extraction readingSource/calculating stages, real cancellable loading, errors with external source action, fallback to paste text.
- Draft review: title, servings, total/per-serving nutrition, recalculate, ingredients, preparation steps, estimate notes and source link, save action.
- Ingredient row: known/missing amount/nutrition, assumption, Edit Ingredient DisclosureGroup, unit Picker, quantity NumericInput, nutrient input buffers, local validation, apply/discard pending edits, removal.
- Pending ingredient edits prevent recalculation/save; real save can dismiss immediately.
- Existing preview-only fixture remains explicit. No custom animation currently present.

### Services/Camera.swift (audit only; no edits)

- CameraPhoto: genuine UIImagePickerController rear camera, native shutter/UI, asynchronous JPEG preparation and cancellation.
- BarcodeCamera: genuine AVCaptureSession and AVCaptureVideoPreviewLayer; camera queue, lifecycle lock, visible/foreground/interrupted/disposed/delivered guards.
- BarcodeScanGuideView: actual UIView/CAShapeLayer geometry and metadata region of interest; layout deliberately disables implicit Core Animation actions.
- Do not animate guide geometry: visible target and metadata ROI must remain aligned. Do not replace/delay native live camera, add timers/display links or change permissions/session lifecycle.

## Implementation plan against central LuqmaMotion.swift

Approved central APIs:

- `.luqmaNumericMotion(value: Double)` only on read-only Text values.
- `.luqmaMotion(.selection/.content/.progress/.success, value: Equatable)` on narrow UI subtrees with small semantic state.
- `.luqmaFeedback(.selection/.success/.error, trigger: Equatable)` only after an actual selection, completed save or actual error.
- `.luqmaLoadingPulse(active: Bool)` only on an existing glyph, with lifecycle/Reduce Motion gating owned centrally.
- `.buttonStyle(LuqmaPressStyle())` in place of existing `.plain`, retaining exact resting appearance. Existing primary/secondary styles are owned centrally.
- `.luqmaMotionTransition()` is opacity-only, for existing conditional states.

### Food search pass

1. Replace plain Button styles in this file with central press feedback; do not modify FoodRow elsewhere.
2. Clear icon and existing search state symbols may receive opacity transition only; focus/input remains native and immediate.
3. Apply narrow `.selection` to selected source/category visual state.
4. Existing loading/notice/empty-state containers may use `.content` and opacity transition based on busy/choosingFood/notice-presence or a small result batch flag.
5. Do not bind animation to entire potentially-large result-ID arrays. If a bounded visual batch is justified, cap inspected row identities (e.g. first visible small prefix); no artificial stagger/task delays and no new request timing/state ownership.

### Food quantity pass

1. Read-only calorie/macronutrient Text values and quantity-chip number may use numeric transition; actual TextFields and their bindings are excluded.
2. Selection visual state can animate on unit/meal/editingNutrition changes without wrapping loadBase or calculation operations.
3. Replace the current Additional Options160ms animation with central `.content` on the disclosure region, respecting exact final layout.
4. Press feedback for native buttons; leave Menu/Picker/sheet presentation system-managed.
5. Success feedback only after onCommit returns true; no sleep, delayed dismiss, fake saved state or changed commit contract. If immediate native dismissal prevents a local animation, rely on the real destination diary state update.

### Photo analysis pass

1. Existing PhotosPicker/buttons receive central press feedback without modifying camera service/system controls.
2. Scoped loading/error/result transitions derive from actual busy/loadingPhoto/error/parts-existence state, never from elapsed time.
3. Loading pulse may target only an existing SF glyph and be active only during actual processing; avoid animating the supplied raster illustration, inventing a scan line, adding duplicates or changing artwork.
4. Actual result Text calories, amounts and macro totals use numeric motion; existing bars use `.progress` on their numeric fraction/amount.
5. Compact/detailed selection and component rows can use `.selection`/`.content`; row identity remains PhotoPart UUID.
6. Native editor/product sheets and interactive dismissal remain unchanged; successful logging keeps existing immediate commit/reset path.

### Recipe import pass

1. Existing native buttons use press feedback; common button styles remain centrally owned.
2. Existing loading/error/draft containers use narrow content/opacity transitions keyed by busy, stage or draft existence.
3. Per-serving/total/ingredient read-only numbers may animate; TextEditor, TextField, NumericInput bindings remain untouched.
4. Ingredient disclosure and removal may use scoped content motion with stable UUID identity; pending edits and validation rules stay intact.
5. No animation loop on idle content, no synthetic extraction progress and no changes to source reading/calculation/retry/cancellation timing.

## Static visual safety

All effects must settle at identity transform, original opacity and original geometry. No fonts, colours, spacing, icons, images, card sizes or data calculations are changed. Reduce Motion, background/disappearance and Low Power handling live in the central layer. Native system navigation, keyboard, camera, menu, picker and sheet behaviour remains owned by iOS.

## Historical verification plan before implementation

- Source-scope and calculation/cancellation diffs.
- Existing Core/BuildTests and SDK builds.
- Native food-entry typing, grams/servings recalculation, all four meal routes, source preview screenshots and real CRUD persistence.
- Static before/after same-frame screenshots with animations settled or disabled for capture.
- Motion lifecycle/Reduce Motion checks and real loading-cancel paths.
- No claims of physical-camera/remote AI speed or hardware FPS from Simulator artifacts.

## Initial implemented native motion pass (recorded before native CI)

Production changes limited to FoodAddView.swift, PhotoMealView.swift and RecipeImportView.swift. Explicit plain button styles now use the central identity-at-rest press style. Read-only numeric text/chips and existing progress fills use numeric/progress motion. Existing conditional/loading/error/disclosure state regions use small Boolean/count-driven content motion; no large result-ID arrays or request staggering. Existing camera glyph pulses only during the actual busy analysis state; camera service unchanged. Recipe success feedback uses its existing saved flag set only after a true repository save. No artificial confirmation delay.

Source safety verification: critical request/action/calculation methods are unchanged; colour literals and typography calls unchanged; Camera.swift unchanged. Detailed checks in food-motion-source-safety.json.

### Confirmed native UI test obstruction

Baseline run40749563514 native hierarchy proves the protein field y584.7...625.7 was covered by a separate full-width keyboard accessory Toolbar y590...638, while Keyboard itself began at y655. The old focus test helpers excluded only Keyboard, so they tapped the toolbar's transparent hit region and mistook the still-open kcal keyboard for protein focus. LuqmaInteractionTests.portionVisibleArea now excludes the actual visible bottom toolbar bounds before scrolling/tapping. This does not weaken any numerical, persistence or keyboard-visibility assertion. Parent owns the analogous CalorieCardInteractionTests helper fix. This records the initial obstruction, not a current five-failure count. Later native outcomes and the outstanding follow-up are documented in VALIDATION-AND-COVERAGE.md.
