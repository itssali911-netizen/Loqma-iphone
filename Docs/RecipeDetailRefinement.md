# Recipe details refinement — visual approval pending

This follow-up responds to the supplied IMG_8145.jpeg. It changes RecipeDetailView only visually. The recipe editor and seven other reviewed screens retain their prior layouts.

- A compact leading-aligned recipe identity replaces the oversized centered name and full-width edit button. The edit action, actual yield and cooked weight remain visible.
- A compact nutrition summary distinguishes **per-serving** calories/macros from the ingredient quantities for the **whole recipe**.
- Each ingredient has a preparation checkbox, actual amount/source unit, a separate calorie column and an accessible nutrition disclosure. The disclosure uses the real stored ingredient macros for the displayed amount, with existing approved macro assets/colors.
- Source steps, source links, estimation notices, assumptions and notes are retained. Notes follow the ingredient list.
- The safe-area action area retains a primary serving action and a lighter 44pt gram action; content continues to scroll above it.
- The gram action exposed an existing issue: FoodPortionView always initialized to serving. A new optional `initialUnit` is passed only by RecipeDetailView; every other caller retains its original default. No nutrient calculations or stored quantities change.

## Authority

Tokens are unchanged from `Luqma/Core/VisualDesignTokens.swift`: background #111214; card #24262B; surface #393C43; accent #F97316; accent text #FDBA74; white #FFFFFF; secondary text #B8BBC2; divider #545861. The approved DailyCalorieCard macro colors/assets remain protein #EF798E, carbohydrates #E8B34C and fat #8FBE63. Changa-Bold.ttf is unchanged.

Geometry reuses Common.swift and LuqmaRefinedUI.swift: card radius20, card padding16, outer margin16, control hit height44, primary action height56. The recipe title uses the existing22pt title2, calorie value32pt metric, ingredient15pt subheadline and metadata12pt caption. The section gap20 reuses the approved DiaryView section spacing (lines90,99,105); it is not an extracted raster measurement.

## Native evidence

Dedicated macOS workflow: `.github/workflows/recipe-detail-review.yml`. It builds the real application, captures compact Arabic, expanded ingredient details, large Arabic and compact English with per-process Changa audits, runs Core/build suites and native UI checks. Read-only DEBUG capture data remain explicitly synthetic; the interaction case instead creates its recipe through real controls on a fresh disposable Simulator. It checks ingredient disclosure, checklist, and both logging entry modes.

Native Debug builds passed. Four accepted actual framebuffers cover Arabic iPhone13mini, Arabic expanded ingredient details, Arabic iPhone16ProMax and English iPhone13mini. All four passed their 12-role Changa-Bold and glyph audits. Exact source token colors were also found in the PNG pixel data. Core264 and macOS build/font170 checks passed with zero failures/skips. The real native interaction case passed in [run40952995187](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40952995187), including recipe save, cooked-weight preservation, ingredient disclosure/checklist and both quantity modes. The Arabic draft-return case separately passed in run40942555850. That earlier combined workflow failed during preparation of the new interaction case; the keyboard focus/scroll setup was corrected without app changes. [RecipeDetailNativeEvidence.json](RecipeDetailNativeEvidence.json) records exact per-image and test revisions. The corrected expanded fixture changed only DEBUG preview expansion, because regenerated preview UUIDs invalidated the original state seed. It did not alter normal recipe behavior. The duplicate test-only wait-expectation rerun also passed in [run40953130975](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40953130975) at a3fe04e929372e50f9a826d91ad0f7a41f69442c; its application files are identical. Earlier eight-screen evidence remains historical and is not proof of the new follow-up appearance.

No new iPhoneOS Release build, physical-device or accessibility-size screenshot check is claimed for this follow-up. Apple-owned status/Settings/keyboard surfaces use their OS fonts. Recipe photos were not invented; the current model/reference fixture supplies no approved image. See the evidence for exact tested routes; these checks are not exhaustive verification of every application interaction. Final visual acceptance requires the user's review; no merge, release or approval is implied.
