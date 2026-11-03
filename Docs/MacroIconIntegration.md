# Approved macro artwork integration — 2026-11-03

Source: the supplied `recipe-card-edit-package.zip`, SHA-256
`3780114a49dad1571e17f5acebf91639a7271807077eed9e44789b9dfbf32cb6`.
The README identifies its SVGs as vectors derived from reference images; these
are not described as original designer/Figma vector exports.

The existing iOS asset catalog already uses native SVG assets with
`preserves-vector-representation`. The three `CalorieCard…` assets now contain
byte-for-byte copies of `icons/protein.svg`, `icons/carbs.svg`, `icons/fat.svg`,
including their viewBoxes, whitespace and paths. `RecipeCardCalories` is a new
isolated byte-for-byte copy of `icons/calories.svg`, for the new recipe card only.
No raster conversion, path approximation, SVG runtime dependency, or application
deployment/toolchain change was introduced.

`LuqmaMacroStyle` and `LuqmaMacroIcon` in `Common.swift` centralize semantic tint
and native glyph rendering. Protein is `#EF798E`, carbs `#E8B34C`, fat `#8FBE63`.
Each screen retains its own existing icon dimensions. Existing unrelated bar,
card and chart surface colors are retained. Text-only nutrient fields remain
text-only, without new icons or layout changes. The old raster/vector assets
remain in the catalog for recoverability but have no active Swift view references.
Calories elsewhere retain their original artwork/tints.

Covered pictogram sites: daily summary, daily meal cards, food amount editor,
seven-day calorie summary, meal analysis columns/results, shared nutrition
components, recipe card/details/editing via shared components, and macro-goal
editing. Fitness profile and assessment nutrient text rows contain no existing
macro pictograms to replace.

`BuildTests/test_macro_asset_integrity.py` checks exact approved source hashes,
well-formed vector paths, catalog metadata, and absence of live legacy artwork
references. These static checks do not establish successful asset compilation,
SwiftUI layout, VoiceOver behavior or real-device rendering; native Xcode builds
and screenshots are reported separately by the overall task.
