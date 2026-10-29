# Implemented native motion — owned Home / Kitchen / Progress / Health surfaces

Historical initial implementation inventory against baseline `9f567b4`. All six source files retained the same static drawing calls. The table below preserves the initial pre-CI verification labels; current native build/capture/functional outcomes are in [VALIDATION-AND-COVERAGE.md](VALIDATION-AND-COVERAGE.md). Physical haptic/frame-pacing limits still require hardware evidence.

| Unit | Actual implementation | Initial pre-CI status (historical) |
|---|---|---|
| DailyCalorieCard | Real nullable numbers use numericText only for available finite values; actual missing dash remains; existing history action press feedback. No card-wide model animation. | Implemented but Not Runtime-Tested |
| CalorieCardBar | Retained native clipped zero-width fill is invisible at zero; real fraction animates width without fill identity resets. Same Capsule track and colors. | Implemented but Not Runtime-Tested |
| DailyMealCard | Existing parent-button press feedback and actual kcal/macro numeric transitions. No image replacement or hero route. | Implemented but Not Runtime-Tested |
| DiaryView | Native sheets/fullscreen/routes untouched; day/category control motion, disclosure expansion, stable-ID entry rows driven by cheap count trigger. | Implemented but Not Runtime-Tested |
| CalorieIntakeDetailView | Actual read-only selected calorie/remaining/macro values animate; Chart data interpolates only from seven actual kcal values. Drag selection remains immediate. | Implemented but Not Runtime-Tested |
| EntryEditor | Native Form/keyboard/dialog/dismiss behavior retained. Shared NutritionView and existing navigation controls receive root-owned motion; no local lost-on-dismiss success counter. | Native behavior retained; shared motion integration owned by root; not runtime-tested on new revision |
| KitchenView | Existing plain actions use press feedback; query-clear appears only on empty-state change. Category and real recipe count change animate rows; no typing debounce or animation keyed to every keystroke. | Implemented but Not Runtime-Tested |
| RecipeDetailView | Native detail/edit/log sheets retained; checkbox color interpolation and actual checked-set selection feedback; real calorie/nutrition values use shared/native numeric motion. | Implemented but Not Runtime-Tested |
| RecipeEditor | Native form/pickers/keyboard/fullscreen retained; bounded ingredient IDs and real byWeight/notes disclosure changes animate locally. No save/dismiss timing changes. | Implemented but Not Runtime-Tested |
| ProgressViewScreen | Latest/average/history weights animate; chart keyed to actual immutable readings; range and adaptive selection feedback; bounded 30-row history transitions. | Implemented but Not Runtime-Tested |
| WeightEditor | Existing native picker/numeric input/form/dismiss preserved and shared controls own microinteraction. No synthetic completion state. | Native behavior retained; shared motion integration owned by root; not runtime-tested on new revision |
| HealthExtendedReadingsView | Actual status opacity transition and historyDays selection motion/feedback; all HealthKit operations, requested data and privacy untouched. | Implemented but Not Runtime-Tested |
| HealthWeightHistoryView | Actual weights interpolate only in chart; combined weight/date text fades as one real record changes, without animating date as a false numeric measurement. | Implemented but Not Runtime-Tested |
| HealthWorkoutListView | Bounded 20-record stable-ID insertion/removal; actual duration numeric motion; all missing states preserved. | Implemented but Not Runtime-Tested |
| HealthDailyHistoryView | Explicit local expanded flag defaults collapsed exactly like original native disclosure; real daily record text fades, bounded day-ID structural updates. No persistence changes. | Implemented but Not Runtime-Tested |
| AppleHealthProgressCard | Existing settings link press feedback plus actual distance/weight numeric transitions; shared real metric rows/child charts used. Card enable/disable branch remains native. | Implemented but Not Runtime-Tested |
| HealthPrimaryButtonStyle | Existing opacity/color/48pt height unchanged; shared pressed transform returns to identity with Reduce Motion support. | Implemented but Not Runtime-Tested |

## Exact modified paths

- `Luqma/Views/DailyCalorieCard.swift`
- `Luqma/Views/DailyMealCard.swift`
- `Luqma/Views/DiaryView.swift`
- `Luqma/Views/KitchenView.swift`
- `Luqma/Views/ProgressView.swift`
- `Luqma/Views/HealthActivityViews.swift`

## Intentionally native / not applicable

- New calorie ring: approved progress uses bars
- Hero meal-to-photo: actual meal card routes to food search; no photo-detail destination
- Replacing native sheets/menus/dialog/pickers: native system transitions retained
- Persistent meal-count animation: approved card has no visible count caption; accessibility count remains immediate
- Artificial success overlay/delayed dismissal: not added
- CalorieMetricLayout and DailyMealCardLayout: pure native layout remains unchanged

## Constraints preserved

No assets, typography, colors, frames, padding, nutritional calculations, data models, services, signing capabilities, request cancellation, navigation destinations or persistence behavior were changed. No view identity reset, artificial timer, display link, fake progress, fake authorization/success, or delayed data operation was introduced. RTL and Reduce Motion policy use the shared root-owned modifiers.
