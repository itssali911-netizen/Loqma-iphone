# Recipe details — comfort pass

Visual acceptance is pending the user's review. This pass changes only RecipeDetailView inside KitchenView.swift. The kitchen screen, recipe editor, Core calculations, Services, resources, fonts, navigation destinations and bottom navigation are unchanged.

## Result

- Remove the extra provenance row. Keep the actual recipe name with a 44pt edit icon and one quiet yield/cooked-weight line.
- Use the existing white metric role for calories and the muted per-serving label. Keep approved macro assets and colors.
- Put the preparation checkbox, name/quantity, calories and a neutral 44pt disclosure chevron on one ingredient row. The name area remains tappable; its accessibility label includes the real quantity.
- Display expanded nutrition inside its parent card. Retain the quantity scope caption and actual stored macros; remove the additional nested black card and repeated orange disclosure text.
- Put serving and gram actions in one bottom row with the existing 56pt primary height, 16pt action radius and neutral secondary surface. Accessibility text sizes use a vertical action stack.
- Omit unnecessary decimal zeroes in ingredient/yield metadata only. Stored amounts, serving calculations and cooked-weight formulas are unchanged.

## Tokens and source

Unchanged from VisualDesignTokens.swift: background #111214, card #24262B, surface #393C43, accent #F97316, text #FFFFFF, secondary #B8BBC2, accent text #FDBA74 and divider #545861. Macro colors/assets are the approved DailyCalorieCard protein #EF798E, carbs #E8B34C and fat #8FBE63. Changa-Bold.ttf remains the actual bundled font.

Geometry comes from Common.swift, LuqmaRefinedUI.swift and the approved DiaryView spacing: 16pt outer/card padding; 20pt card radius/section rhythm; 12pt row gaps; 44pt icon hit areas; 56pt primary height. Typography uses existing roles: 22pt title2, 32pt metric, 15pt subheadline, 13pt footnote and 12pt caption. No new app styling framework or dependency was introduced.

## Verification

Application source: 682ec6e7540d7be311217aa7035892e4a4469617. Native workflow:[40969034440](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40969034440). Four actual Simulator captures cover Arabic compact, Arabic expanded ingredients, Arabic large, and English compact. All four captured processes passed their 12-role Changa-Bold and glyph checks. Source token fills and macro colors were also observed in their PNG pixel data.

Native Debug build passed. Core 264 tests and macOS BuildTests 170 checks passed with zero failures/skips. The actual native case testRecipeDetailsIngredientDisclosureAndBothQuantityModes passed (one case, zero failures/skips): recipe save, cooked-weight preservation, ingredient expansion/checklist, serving mode and gram mode. This is scoped evidence, not exhaustive app verification. Recipe values in the screenshots are explicit read-only display examples, not user records or live AI results. No new physical-device, Release or accessibility-size framebuffer verification is claimed. Apple-owned status/Settings/keyboard surfaces retain OS fonts. No merge or release is implied.
