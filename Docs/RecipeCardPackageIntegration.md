# Approved recipe card package integration

Reference: `recipe-card-edit-package.zip`, SHA-256
`3780114a49dad1571e17f5acebf91639a7271807077eed9e44789b9dfbf32cb6`.
The package was inspected as data. No embedded script or instruction was executed.
The package's own README states that its four nutrition icons are vector traces
from reference images, rather than the designer's original SVG sources.

The provided JSON, editable SVG and preview PNG agree on the card's 390 × 272
logical size, colors, fonts, RTL order, 20-point padding and 16-point group gaps.
The PNG exports at 2×; its card is `[48, 48, 780, 544]` inside an 876 × 640 image.
Unchanged copies of those references are in `ReviewSupport/RecipeCardReference`.
The original JSON's component tree contains the action geometry as well as the
four major groups. More/chevron/plus assets translate those exact 20-point SVG
paths to their local view boxes. No full-card image is used by the app.

## Native implementation

`RecipeNutritionCard` is a reusable SwiftUI view used by the real saved-recipe
list in `KitchenView`. Its data comes from `Recipe.total` and `Recipe.portions`;
it does not derive the package's calorie example from macro-energy arithmetic.
The default 390-point case places groups at y=20, 88, 130 and 202; bottom padding
is 22 to preserve the reference's 272-point height. Narrow widths redistribute
the three equal macro columns. Long titles grow the header; accessibility text
sizes stack macros. Calorie and serving subgroups retain the exact horizontal
reference case, with vertical alternatives only when large text/values cannot
fit. The whole card is never scaled down.

The card alone uses Changa Regular/Medium/SemiBold/Bold and Work Sans
Medium/SemiBold, with the package's respective sizes and line heights. Changa's
native line box is 1.84 × point size, which exceeds some of the package's line
heights. The local typography modifier adjusts the layout leading without
clipping or resizing the glyphs, including multiline text and Dynamic Type.
Other screens retain their existing global Changa Bold typography.

Three missing static Changa weights were obtained unchanged from the same
official immutable upstream commit as the existing Bold resource. The existing
SIL OFL covers them. Exact SHA-256 hashes and source URLs are recorded in
`Luqma/Resources/Changa-Font-Provenance.txt` and the font tests. Work Sans resources
were already present and registered.

The card's details and more actions use the existing detail/editor/delete flows.
Its single add button opens the existing quantity sheet; that existing screen
does the actual logging. A synchronous guard prevents a second selection while
that sheet is presenting. The existing by-weight action remains in recipe
details, rather than adding a second button to the approved one-button card.
The kitchen header, background photograph/shading, categories, empty state,
navigation and recipe persistence are unchanged.

## Validation

Local Windows check: `python -m unittest BuildTests.test_bundled_fonts -v`
ran seven cases: five passed; two native iPhone font cases were skipped because
macOS/Xcode is unavailable locally. The five cases check pinned font/license
bytes, actual PostScript names, glyph coverage and Xcode resource registration.

The new `RecipeCardInteractionTests` contains five native Simulator cases:

- Arabic 390-point reference dimensions and real displayed macro values;
- 320-point long English title plus the real edit destination;
- real detail and quantity destinations, committing one serving to an isolated
  temporary diary and verifying exactly one entry;
- 320-point long Arabic content at the existing accessibility preview size;
- large nutrition numbers at 320 points, preserving the values and fonts.

The `recipeCard` DEBUG preview route creates its own temporary `DiaryStore`.
Its 588/35.9/26.0/36.5 recipe is explicitly review data and is absent from Release.
Launch variants: `-loqma-recipe-card-320`, `-loqma-recipe-card-long`,
`-loqma-recipe-card-en`, `-loqma-preview-accessibility`,
and `-loqma-recipe-card-large`.
`-loqma-recipe-card-interactions` exposes a clearly named review entry count for
the native UI test only. These tests and actual visual comparisons still require
the native CI run; their existence is not a passing result or a device claim.
