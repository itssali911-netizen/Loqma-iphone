# Native motion inventory: assessment, plans, settings and Health

Historical initial read-only source audit, recorded before the baseline build passed and implementation began. The later implementation and cross-review notes below preserve that chronology. Current validation status is in [VALIDATION-AND-COVERAGE.md](VALIDATION-AND-COVERAGE.md).

- Source checkpoint: `9f567b4`.
- Review branch: `feature/native-motion-review-20261028`.
- Scope: 10 Swift source files, 22 declared SwiftUI View types, plus their existing helper shapes/button style.
- Preserve all current fonts, colors, icons, assets, geometry, navigation, nutrition equations, validation, persistence, HealthKit authorization and signing.
- Shared motion API is owned by the parent. No independent animation engine, dependency, timer or display link will be added here.

## Shared integration API

- `Text.luqmaNumericMotion(value: Double)` for read-only numerical displays only.
- `.luqmaMotion(.selection/.content/.progress/.success, value: Equatable)` on the smallest relevant subtree.
- `.luqmaFeedback(.selection/.success/.error, trigger: Equatable)` on actual changes, never appearance or fake success.
- `.buttonStyle(LuqmaPressStyle())` replaces plain style without replacing the original label/layout.
- `.luqmaMotionTransition()` is opacity-only and accessibility-aware.
- `LuqmaMotion.animation(.content, reduceMotion: Bool) -> Animation?` for narrowly scoped explicit transactions when needed.
- Keep native navigation, sheets, alerts, dialogs, date pickers, toggles and keyboard transitions system-managed. Do not layer competing sheet transitions over them.
- Avoid duplicate haptics for native switches or continuously dragged sliders/rulers.

## 1. AssessmentFlowView.swift

Declared Views: `AssessmentFlowView`, `CFARadioIndicator`, `SandowFitnessArcSlider`.
Other declared UI helpers: `ApprovedAssessmentButtonStyle`, `CFACrescentChevron`, `CFAScanBracketsShape`.

- AssessmentFlowView delegates to the existing FitnessAssessmentView. It must not create a parallel flow or duplicate entry animation.
- CFARadioIndicator has an existing conditional selected-square layer. Suitable: scoped selection transition. Its final square geometry and stroke stay unchanged.
- ApprovedAssessmentButtonStyle already has a Reduce Motion-aware pressed scale of 0.985. Suitable: central press timing; retain its exact existing font, fill, corner radius, minimum height and enabled opacity. Do not wrap it in another competing press style.
- SandowFitnessArcSlider uses an existing 5-level arc, quadratic track, ticks, thumb and large numeric activity label. The initial audit considered thumb settling; cross-review removed it so the actual thumb follows the gesture immediately. Read-only numeric text motion remains, without continuous gesture haptics.
- Arc interactions: high-priority drag, clamping, adjustable accessibility action, hasSelection flag, onChanged and onInteractionChanged. Do not alter the gesture, track mapping, selected value or interaction callbacks.
- Shapes remain static render primitives. Do not animate them independently or redraw them with replacements.

## 2. AssessmentNumberPickers.swift

Declared View: `AssessmentNumberPicker`; static `ApprovedRulerTicks` shape.

Existing states and controls:

- Age wheel with typed central TextField and neighbor rows/buttons.
- Height/weight typed readout, ruler drag, neighbor decrease/increase buttons.
- Metric/imperial segmented controls and raw/alternate input bindings.
- Missing-answer helper, invalid raw text retained for correction, clamped/quantized gesture values.
- FocusState, dragStart, onInteractionChanged and adjustable accessibility action.

Suitable motion:

- Unit-selection press/selection response and neighbor-button press feedback.
- Read-only neighbor labels may use numeric text transitions on deliberate value changes when useful.
- Keep typed TextField text and the raw input binding immediate; no numeric transition on editable fields.
- Do not animate every drag frame, persist on drag, animate the parent scroll view or add continuous haptic feedback.
- Do not change gesture priorities, drag distances, focus behavior or ruler tick geometry.

## 3. FitnessAssessmentView.swift

Declared Views: `FitnessAssessmentView`, `FitnessNumberField`.

Eleven existing pages:

1. goal
2. suitability
3. sex
4. age
5. height
6. weight
7. targetPace
8. activity
9. training
10. details
11. review

Nested existing UI:

- Fixed header with Back/close-save action and numeric step indicator.
- Page question and `pageContent.id(page.rawValue)`.
- Goal/safety/experience option rows; gender illustration options; target/pace options.
- Activity arc plus optional activity/step detail disclosure.
- Optional training days/minutes, sleep hours, food preferences/diet/meals/notes.
- Review rows with edit-page actions and legacy-answer disclosure.
- Inline validation alert, ScrollViewReader targets, actionBusy spinner and disabled state.
- Continue/preview, skip, save-and-finish-later, Done keyboard action.
- Existing FitnessPlanReviewView navigationDestination.
- Existing async draft save, double-action guard, interactive dismissal guard and preview-only mode.

Suitable motion:

- Opacity-only pageContent replacement scoped to the page identifier; question/step count updates.
- Selection animation on the actual option row/indicator, not on all answers or inputs.
- Validation appearance and real validation error feedback through shared state component behavior.
- Existing busy spinner stays tied to actual actionBusy.

Constraints:

- Do not animate answers/inputs as broad dependencies; typing and ruler drags must remain immediate.
- Preserve `.id` ownership and answer retention; no parallel transition state or timing-gated navigation.
- Preserve existing scroll-to-validation clearance and scrollDisabled(pickerInteraction).
- Do not change suitability rejection, optional page rules, draft writes or anti-double-tap behavior.

## 4. FitnessProfileView.swift

Declared Views: `FitnessProfileView`, `FitnessPlanReviewView`, `FitnessDetailRow`.

FitnessProfileView existing branches:

- Profile summary, plan status (none/active/manual), calculation inputs.
- Activity/training, recovery/sleep and nutrition/preferences disclosures.
- Empty profile, saved draft notice, deferred assessment action, deleted confirmation, diary error.
- Fitness assessment sheet and native destructive delete confirmation alert.
- Proposed/applied plan NavigationLink to FitnessPlanReviewView.

Suitable: scoped profile/empty/deleted transitions, press feedback on existing actions, explicit disclosure-state changes if a binding is needed solely for motion. Native alert/sheet/push remain native.

FitnessPlanReviewView existing branches and controls:

- Proposed or applied plan; missing-plan fallback.
- Calorie unit kcal/kJ selector, calorie override and plus/minus actions.
- True calculated calorie/macronutrient target displays.
- Existing applyBusy guard; applied confirmation only after successful actual apply.
- Plan assumptions disclosure and unchanged summary detail rows.

Suitable: numeric transitions on read-only calorie/macro output; unit/override selection animation; success feedback only when applied changes to true. Do not move computation, mutate the approved plan model or repeat success on screen appearance.

## 5. PlanView.swift

Declared View: `PlanView`.

Existing controls/states:

- Sex picker; age/height/current/goal weight NumericInput.
- Start/target date pickers, PAL, activity-change slider.
- Advanced measurements disclosure, body-fat/resting-energy toggles and conditional fields.
- Medical/special-case toggle.
- Calculate button with actual calculating spinner; optional result, actual Chart, low-calorie warning and Apply button/applied state.
- Existing detached WeightModel calculation and input-equality guard.

Suitable: result insertion/removal opacity; actual calculated read-only metrics; applied confirmation feedback. Scope conditional advanced-field transitions to the respective boolean. Leave native picker/toggle/slider interaction animation to iOS.

Constraints: never animate the entire plan value on each keypress; do not change task ownership, computation or stale-result guard. No invented loading delay.

## 6. SettingsView.swift

Declared Views: `SettingsView`, `LuqmaLanguageView`, `BackupSettingsView`, `AboutLuqmaView`, `ImportPreview`.
Other helper: `BackupDocument` FileDocument (not a View).

SettingsView destinations:

- FitnessProfileView, PlanView, NotificationsView, RemindersView, HealthSettingsView.
- Language, BackupSettingsView, AboutLuqmaView.
- GoalEditor and GeminiSettingsView sheets.
- Existing custom navigation back action when supplied.

Suitable: existing row/button press feedback, same native destination and modal presentation. No list restructuring or changed row geometry.

LuqmaLanguageView:

- Selected language card and other language choices.
- Selection updates existing DiaryStore language and RTL.
- Suitable: scoped selection response; do not reset root/navigation identity or flip non-directional icons.

BackupSettingsView:

- Native fileExporter and fileImporter.
- Actual importingBusy indicator, security-scoped file decode, pending snapshot.
- Existing ImportPreview sheet with merge confirmation and dismissal.
- Suitable: busy/content state transition, press response. No I/O or backup-schema edits.

AboutLuqmaView:

- Static privacy/design/font/food-source cards and external links.
- Native navigation/press feedback only; no autonomous animation.

ImportPreview:

- Real counts for entries, recipes, weights and products.
- Native cancel/confirm controls through sandowNavigation; merge only on actual apply success.
- Suitable: read-only count presentation; preserve immediate native dismissal and actual merge outcome.

## 7. AppleHealthView.swift

Declared Views: `HealthSettingsView`, `HealthMetricRow`; static `HealthCopy` helper.

Existing controls/states:

- Native connect, refresh, cancel-refresh, stop-refresh/clear, manage-access sheet.
- availabilityIssue/issue, isWorking/isAuthorizing/isRefreshing/refreshEnabled.
- Core available readings (steps, active energy, latest weight/height), timestamps and previous-check notice.
- Valid value, noData and query-failed HealthReadField branches.
- Privacy-sensitive read-only data and localized permission-management explanation.
- Includes `HealthExtendedReadingsView()` from another source file; parent must assign that file separately.

Suitable:

- Press feedback on existing actions.
- Scoped real working/error/readings transitions and numeric animation only for available actual measurements.
- Never animate a missing result from zero or emit a success solely because authorization completed.
- Do not change HealthKit authorization, entitlements, queries, refresh scheduling, stored health data or permission interpretation.
- Native Apple authorization dialog remains system-owned. Manage-access sheet remains native.

## 8. GoalEditor.swift

Declared View: `GoalEditor`; nested computed calorieEditor and macroEditor sheets.

Existing controls/states:

- Calorie readout button, slider, macro tiles and goal-status label.
- Goal-details disclosure, Save button and real validation.
- Numeric calorie editor and macro editor with grams/percentage segmented picker.
- Existing balanced macro calculations and settings persistence.

Suitable: numeric text on read-only calorie/macro displays; press feedback; scoped valid/invalid status change; native sheet/segmented-picker transitions. Do not animate editable NumericInput bindings or the whole goals object while dragging/typing; no changes to balancing equations or allowed range.

## 9. NotificationsView.swift

Declared Views: `RemindersView`, private `ReminderTimeEditor`, `NotificationsView`.

RemindersView:

- Real notification permission states notDetermined/allowed/quiet/denied/unavailable.
- Genuine request-permission or open-system-settings actions.
- Five reminder toggles and edit-time buttons.
- Actual pending count, saved confirmation, errors, isWorking operation state.
- ReminderTimeEditor sheet and native reset-recovery confirmationDialog.
- Preserve scheduling, permission semantics and background task behavior.
- Suitable: pending-count numeric transition, actual saved/error/working state presentation, press response; no duplicate haptics on native toggles.

ReminderTimeEditor:

- Native hour/minute DatePicker wheel, reminder title, real service error, existing cancel/save navigation actions.
- Native wheel/keyboard/modal transitions remain system-owned; save/dismiss stays tied to service success.

NotificationsView:

- Today/Past segmented period filter.
- Delivered-notification count, real delivered list, existing item action/removal.
- Empty state plus RemindersView link.
- Native clear confirmationDialog and pull-to-refresh.
- Suitable: count numeric transitions, filtered list/empty opacity transitions, actual insertion/removal via stable notification IDs; no staggered timing that delays interactivity.
- Permission allow and deny tests must use separate fresh Simulators; motion must not replace this requirement.

## 10. GeminiSettingsView.swift

Declared View: `GeminiSettingsView`.

Existing states/controls:

- configured/unconfigured status label.
- Advanced settings DisclosureGroup.
- Private SecureField, activate button, official create-key link.
- Success/error message from actual credential save.
- Native reset confirmationDialog and actual credential clearing.

Suitable: configured/message/disclosure state changes and existing button press feedback. Success must follow actual credential-store operation. Do not log/capture secure field content, alter credentials, create model/network placeholders or change integration contracts.

## Cross-file safety and verification

- Root owns the central motion layer, Common/StateComponents/root and final test inventory.
- Runtime frame comparison must be after animations settle, plus Reduce Motion comparison; identical final-state geometry/colors/fonts are required.
- Keep empty/error/success components delegated to shared layer to avoid duplicate transitions/haptic triggers.
- Preserve semantic Arabic RTL and accessibility identifiers throughout.
- No performance claim, physical haptic verification or 60/120FPS result is established by this read-only audit.

## Implementation status after baseline approval

- Parent confirmed checkpoint 9f567b4 passed actual iPhone Release, Simulator Debug, 264 Core tests and 169 BuildTests in run 40749563514 before production edits began.
- All 10 owned production view files now integrate the agreed shared native motion APIs. Existing plain buttons use the shared press style; the existing approved assessment style retains its 0.985 pressed scale with central press timing.
- Added scoped assessment-page/selection transitions, native numeric text for read-only step/arc/calorie/macro/count/Health readings, and real conditional content transitions. Editable fields and continuous drag bindings remain immediate.
- Custom activity-choice haptics are explicitly suppressed while pickerInteraction is active, so dragging the arc with an expanded activity disclosure cannot produce duplicate selection haptics.
- Success feedback is conditional on actual apply/delete/credential/reminder outcomes. Health success observes the existing lastSuccessfulSync timestamp and requires snapshot.hasReadableData; empty authorization completion does not trigger success. Health cancellation does not trigger error feedback.
- No service/core/signing, calculations, persistence, colors, fonts, assets, static dimensions, navigation routes or existing delays were changed by this worker.
- Local git diff whitespace check passed. Source invariant comparison against 9f567b4 confirms identical string literals, color literals and luqmaFont calls in all 10 files. This is source evidence, not proof of runtime pixel equality.
- At this initial implementation checkpoint, native validation had not run. Subsequent SDK, screenshot and functional results, plus the remaining physical-device limits, are in VALIDATION-AND-COVERAGE.md.

## Cross-review refinements

- Removed the activity thumb position animation entirely: the existing drag-to-position mapping now remains immediate with no extra drag state. Read-only activity number motion and button feedback remain.
- Notification-list animation no longer constructs a mapped ID array in body. Its bounded semantic triggers are the selected period and delivered-notification count. Same-count content replacements update immediately without an extra full-list animation key.
