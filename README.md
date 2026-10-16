# Luqma iPhone — version 2.3

172 Swift tests, 61 macOS Python tests including two native iPhone font probes, iPhone Release compilation, independent IPA validation and twenty visually reviewed native Simulator screenshots passed. [Build](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/38810484062)

Meal analysis estimates calories, protein, carbs and fat for every visible component and the whole meal, with editable weights and estimated servings. An existing iPhone Keychain connection is reused automatically; no model or setup file import is needed. A fresh device needs its own connection under advanced settings. The app uses the simple label “Meal analysis”; no service credential is embedded in the source or IPA. Photos and recipe inputs are sent to Google for analysis when the user starts the feature. Estimates require review and are not measured calorie accuracy.

Analysis now uses a fast stable extraction model, smaller metadata-free photos, a short in-memory cache and at most one backup request for a provider outage or pre-response timeout. Invalid results, quota/authentication errors and cancellation never trigger retries. Featureless images are rejected locally before any request. Benchmarks and failed quality checks are retained honestly; network availability and exact calorie accuracy are not guaranteed.

Kitchen first reads accessible public recipe pages, Recipe JSON-LD and public TikTok/Instagram captions, then analyzes only the captured source text when available. Other public HTTPS links use bounded source retrieval; YouTube video covers the first 10 minutes. Captions are not video transcripts. Private, blocked, missing-caption or incomplete sources need pasted recipe text. Ingredients, quantities, steps, servings and whole-recipe/per-serving nutrition stay organized, with unknown values blocking saving until corrected. Saved recipes retain source and steps through backups.

Search matches Arabic spelling variants, names, brands and aliases in either word order, ranks Best match first, and labels nearby products separately. Explicit online Search preserves source spelling and tries supported brand variants where needed. Local indexes, matching and suggestions run away from the keyboard's main actor; typing is debounced and stale results are discarded. Nearby foods retain their own identities and nutrition. Serving with quantity 1 is the default selection.

Numbers use 123 in both languages. A compact selected-day row sits at the top. Consumed/target macro amounts and progress bars sit directly below the calorie goal; all four meal cards have compact macro strips. Search results each have one themed card. Apple Health integration was removed at the user's request: no connection controls, permissions, background observers or HealthKit entitlements remain. Historical weights and old backup fields stay readable, while legacy activity no longer alters today's goal. Weight tracking and the weight plan remain available manually.

Food catalog: 744 supplied MFP regional foods and 6 OFF starter products, plus live OFF search. All 3,830 declared MFP portions retain source nutrition multipliers; 31 incomplete food records and 94 unknown portions remain unknown. The supplied sample does not contain MFP's complete server database or ranking algorithm. See [food sources and search](FOOD-DATA-AR.md).

Native SwiftUI reconstruction follows the inspected Sandow Community dark file: #111214 background, #24262B cards, #393C43 surfaces and #F97316 orange. Version 2.3 revises the screen composition after another inspection of the actual Figma canvas. Search uses one compact orange heading, a black query field, outlined source chips and dense result rows; barcode and meal-photo tools are compact icons. Suggestions appear when there are no matching or nearby rows, without pushing found foods down the screen. The bottom bar uses icons and the central orange add control while retaining accessible labels. Meal review uses a large source-photo area, a charcoal calorie summary with an orange flame icon, separate macro columns and compact component rows showing estimated weight and calories, with quantity editing and detailed nutrition available. The DEBUG fixture uses a neutral photo placeholder rather than claiming a real meal image. Diary, kitchen and secondary-form composition is adjusted to the observed reference for the existing Luqma functions. Six unchanged official Work Sans weights supply Latin text and 123 digits; five licensed Tajawal weights supply the user-approved Arabic companion. Both full SIL OFL licences ship. Existing 2.1 branding and barcode guidance, real catalog data, quantity units and search ranking logic are preserved. This is a native reconstruction from the visible reference, not a complete downloaded .fig kit or an automated Figma code import. Original reference photographs and all editable screens have not been obtained. No 100-percent pixel, content, exact font-binary, motion or physical-device smoothness match is proved. [Figma](https://www.figma.com/design/IfMCdTI3FcvXpNFy79PRUA?node-id=2-606)

Before updating, export a diary backup and keep the same Apple account and installed identifier, such as `app.luqma.diary.2AV9NV468K`. Personally re-sign the IPA and install over the existing app. See [Arabic instructions](README-AR.md), [analysis and recipes](GEMINI-SETUP-AR.md) and [Health removal](HEALTH-SETUP-AR.md).

Build on macOS/Xcode through `.github/workflows/ios-build.yml`. Default CI runs Core/build-tool tests, compiles the Release device app and captures native SwiftUI screens; historical local vision audits are optional manual checks. To check or regenerate locally:

```text
swift test -j 2
python3 -m unittest discover -s BuildTests -v
python3 Scripts/build_project.py
python3 Scripts/build_ios.py sideload
```

Results and their limits are recorded in [VALIDATION.md](VALIDATION.md). Food-resource rebuild commands are in [FOOD-DATA-AR.md](FOOD-DATA-AR.md).

Previous1.9 verified build evidence: 167 Swift tests, 31 Python tests, iPhone Release compilation, independent IPA validation and eight native Simulator screenshots passed. [Build](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/38452505784)
