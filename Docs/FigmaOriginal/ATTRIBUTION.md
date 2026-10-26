# Reference attribution and artifact scope

Sandow UI Kit: AI Fitness & Nutrition App (Community), creator **strangehelix.bio**.

- User-designated source: https://www.figma.com/file/IfMCdTI3FcvXpNFy79PRUA?type=design
- Community listing recorded in the existing project: https://www.figma.com/community/file/1334779038193346013/sandow-ui-kit-ai-fitness-nutrition-app
- Existing `Luqma/Resources/UI-SOURCES.txt` records an observed Community-page CC BY 4.0 notice: https://creativecommons.org/licenses/by/4.0/

The three `reference/*-original.png` files are the unmodified flattened preview-panel image fills returned by direct Figma extraction on 2026-10-16. The manifest preserves node IDs, board dimensions, actual raster dimensions and file hashes. This evidence package does not represent the paid/full editable kit or grant new rights to any separately licensed material. No reference photograph, panel or icon is added to the application bundle.

`native/*.png` are unmodified Luqma 2.3/build59 Simulator captures from source `b9c0f7cfeb058472f33592ffbb61ed260bceecef`. These are existing implementation evidence, not Figma exports or new native renders.

`baseline/*.png` are explicitly labelled diagnostic derivatives: one recorded search-phone raster crop, a width-normalized native image, a side-by-side view, a 50% overlay and an amplified absolute difference. Their transformations are documented in `baseline/comparison-report.json` and reproducible with `compare_baseline.py`. They are not production resources and do not establish a visual acceptance score.
