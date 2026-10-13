# Luqma iPhone — version 1.9

Native compilation, tests and screenshot review for this update are pending; verified results will be recorded in VALIDATION.md.

Meal analysis estimates calories, protein, carbs and fat for every visible component and the whole meal, with editable weights and estimated servings. An existing iPhone Keychain connection is reused automatically; no model or setup file import is needed. A fresh device needs its own connection under advanced settings. The app uses the simple label “Meal analysis”; no service credential is embedded in the source or IPA. Photos and recipe inputs are sent to Google for analysis when the user starts the feature. Estimates require review and are not measured calorie accuracy.

Analysis now uses a fast stable extraction model, smaller metadata-free photos, a short in-memory cache and at most one backup request for a provider outage or pre-response timeout. Invalid results, quota/authentication errors and cancellation never trigger retries. Featureless images are rejected locally before any request. Benchmarks and failed quality checks are retained honestly; network availability and exact calorie accuracy are not guaranteed.

Kitchen first reads accessible public recipe pages, Recipe JSON-LD and public TikTok/Instagram captions, then analyzes only the captured source text when available. Other public HTTPS links use bounded source retrieval; YouTube video covers the first 10 minutes. Captions are not video transcripts. Private, blocked, missing-caption or incomplete sources need pasted recipe text. Ingredients, quantities, steps, servings and whole-recipe/per-serving nutrition stay organized, with unknown values blocking saving until corrected. Saved recipes retain source and steps through backups.

Search matches Arabic spelling variants, names, brands and aliases in either word order, ranks Best match first, and labels nearby products separately. Explicit online Search preserves source spelling and tries supported brand variants where needed. Local indexes, matching and suggestions run away from the keyboard's main actor; typing is debounced and stale results are discarded. Nearby foods retain their own identities and nutrition. Serving with quantity 1 is the default selection.

Numbers use 123 in both languages. A compact selected-day row sits at the top. Consumed/target macro amounts and progress bars sit directly below the calorie goal; all four meal cards have compact macro strips. Search results each have one themed card. Apple Health integration was removed at the user's request: no connection controls, permissions, background observers or HealthKit entitlements remain. Historical weights and old backup fields stay readable, while legacy activity no longer alters today's goal. Weight tracking and the weight plan remain available manually.

Food catalog: 744 supplied MFP regional foods and 6 OFF starter products, plus live OFF search. All 3,830 declared MFP portions retain source nutrition multipliers; 31 incomplete food records and 94 unknown portions remain unknown. The supplied sample does not contain MFP's complete server database or ranking algorithm. See [food sources and search](FOOD-DATA-AR.md).

SwiftUI styling adapts the Sandow v1.2 dark Community preview by strangehelix.bio, with in-app CC BY 4.0 attribution. Its free nutrition sections are flattened previews; the functional views were rebuilt with real diary data. See `Luqma/Resources/UI-SOURCES.txt` for attribution.

Before updating, export a diary backup and keep the same Apple account and installed identifier, such as `app.luqma.diary.2AV9NV468K`. Personally re-sign the IPA and install over the existing app. See [Arabic instructions](README-AR.md), [analysis and recipes](GEMINI-SETUP-AR.md) and [Health removal](HEALTH-SETUP-AR.md).

Build on macOS/Xcode through `.github/workflows/ios-build.yml`. Default CI runs Core/build-tool tests, compiles the Release device app and captures native SwiftUI screens; historical local vision audits are optional manual checks. To check or regenerate locally:

```text
swift test -j 2
python3 -m unittest discover -s BuildTests -v
python3 Scripts/build_project.py
python3 Scripts/build_ios.py sideload
```

Results and their limits are recorded in [VALIDATION.md](VALIDATION.md). Food-resource rebuild commands are in [FOOD-DATA-AR.md](FOOD-DATA-AR.md).
