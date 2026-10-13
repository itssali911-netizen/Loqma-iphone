# Luqma iPhone — version 1.8

140 Swift tests, 26 Python tests, iPhone Release compilation, independent IPA validation and nine native Simulator screenshots passed. [Build](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/38376076214)

Meal analysis estimates calories, protein, carbs and fat for every visible component and the whole meal, with editable weights and estimated servings. An existing iPhone Keychain connection is reused automatically; no model or setup file import is needed. A fresh device needs its own connection under advanced settings. The app uses the simple label “Meal analysis”; no service credential is embedded in the source or IPA. Photos and recipe inputs are sent to Google for analysis when the user starts the feature. Estimates require review and are not measured calorie accuracy.

Kitchen imports accessible public recipe links or pasted text into organized ingredients, quantities, preparation steps, servings and whole-recipe/per-serving nutrition. YouTube analysis covers the first 10 minutes. Blocked or private pages, including Instagram posts, need pasted recipe text. Missing values remain unknown and block saving until corrected; inferred nutrition is labelled estimated. Saved recipes retain their source and steps through backups.

Search matches Arabic spelling variants, names, brands and aliases in either word order, ranks Best match first, and labels nearby products separately. Explicit online Search preserves source spelling and tries supported brand variants where needed. Local indexes, matching and suggestions run away from the keyboard's main actor; typing is debounced and stale results are discarded. Nearby foods retain their own identities and nutrition. Serving with quantity 1 is the default selection.

Numbers use 123 in both languages. Today displays all four meal cards—breakfast, lunch, dinner and snack—with each meal's calories, protein, carbs and fat from its logged entries. Apple Health syncing reads steps, walking/running distance, active energy, exercise minutes, workouts, weight and height. Extra-activity calorie adjustment is optional and off by default; it requires a goal actually calculated from the saved weight plan and subtracts activity already included in that plan. Manual or imported goals invalidate that association. Physical-device consent and a HealthKit-capable Apple signature are required; a build or Simulator preview does not prove the user's connection works.

Food catalog: 744 supplied MFP regional foods and 6 OFF starter products, plus live OFF search. All 3,830 declared MFP portions retain source nutrition multipliers; 31 incomplete food records and 94 unknown portions remain unknown. The supplied sample does not contain MFP's complete server database or ranking algorithm. See [food sources and search](FOOD-DATA-AR.md).

SwiftUI styling adapts the Sandow v1.2 dark Community preview by strangehelix.bio, with in-app CC BY 4.0 attribution. Its free nutrition sections are flattened previews; the functional views were rebuilt with real diary data. See `Luqma/Resources/UI-SOURCES.txt` for attribution.

Before updating, export a diary backup and keep the same Apple account and installed identifier, such as `app.luqma.diary.2AV9NV468K`. Personally re-sign the IPA, install over the existing app, then allow Health reading on the iPhone. See [Arabic instructions](README-AR.md), [analysis and recipes](GEMINI-SETUP-AR.md) and [Health setup](HEALTH-SETUP-AR.md).

Build on macOS/Xcode through `.github/workflows/ios-build.yml`. Default CI runs Core/build-tool tests, compiles the Release device app and captures native SwiftUI screens; historical local vision audits are optional manual checks. To check or regenerate locally:

```text
swift test -j 2
python3 -m unittest discover -s BuildTests -v
python3 Scripts/build_project.py
python3 Scripts/build_ios.py sideload
```

Results and their limits are recorded in [VALIDATION.md](VALIDATION.md). Food-resource rebuild commands are in [FOOD-DATA-AR.md](FOOD-DATA-AR.md).
