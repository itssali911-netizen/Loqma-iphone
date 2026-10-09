# Validation — 2026-10-09

The delivered code is a native SwiftUI iPhone source project. **An iOS app binary was not built or signed in this Linux environment.** No TestFlight upload or App Store submission was made.

## Completed checks

- Swift 6.1.2 on Ubuntu, Swift 5 language mode: Foundation core compiled and ran **11 XCTest tests with 0 failures**. The NIDDK test includes six official reference scenarios, checking calories within 0.1 kcal, maintenance within 0.1 kcal and end weight within 0.001 kg.
- Tests cover 60 g versus 100 g nutrition, resizing the same diary entry, serving and incompatible-unit handling, balanced grams/percent macro targets, cooked-weight meal prep, native backup round trip and invalid-data rejection, website v1 backup migration, weekly weight averages, unsupported plan inputs, shawarma with separate garlic/tahini sauce descriptions, description negation and ambiguous dip confirmation.
- Foundation core plus `FoodDatabase.swift`: Swift compiler type check passed. This checks the networking/food-parsing code without Apple UI frameworks.
- Swift compiler syntax parsing passed for all 20 Swift files. **Syntax parsing is not iOS SDK type checking.**
- Xcode OpenStep project parsed successfully; object references resolve and all 20 Swift source files are included in the source build phase. Shared scheme XML, Info.plist, HealthKit entitlement and privacy manifest parsed successfully.
- Arabic/English permission descriptions are bundled. The app icon is opaque RGB, 1024 × 1024 pixels.
- Both CLIP label sets have 512-dimensional vectors. Pinned model URLs were checked against Hugging Face metadata. Download integrity uses the actual LFS file SHA-256 (`x-linked-etag`), not the distinct Xet storage-object hash.
- Microsoft ONNX Runtime SPM 1.24.2 package manifest was fetched from the official repository; product `onnxruntime` and module `OnnxRuntimeBindings` match the project dependency/import.

`Tests/niddk-weight-golden.json` records the official NIDDK script source URLs and hashes used for the reference cases. `TEST-RESULTS.txt` includes the actual XCTest results from this environment.

## Remaining iOS validation

`bash Scripts/verify.sh` runs the core tests and build-tool tests. On a Mac it calls `Scripts/build_ios.py check`, building both iPhone Simulator Debug and iOS device Release targets without signing. These Apple SDK builds have **not** been run here. They will check SwiftUI/HealthKit/AVFoundation/Vision and ONNX Runtime against Apple's SDK.

## Cloud build continuation

The source includes a GitHub Actions workflow on `macos-15`, selecting Xcode 26.3. Official checkout/upload actions are pinned to verified commit hashes. Source pushes to `main` trigger `sideload`; manual runs also allow `check`, `sideload`, `ad-hoc` and `app-store`. The default manual `check` mode requires no Apple credentials and produces a simulator archive plus SDK diagnostics, **not an installable IPA**. The `sideload` mode builds for iPhoneOS, locally ad-hoc signs the app/framework hashes without an Apple identity, and packages `Payload/Luqma.app` as `Luqma-Sideload.ipa`. This is **not Apple account signing**: AltStore must re-sign it for the user's device before installation. Apple-signed modes validate an explicit iOS profile with HealthKit, matching team/bundle, expiration, distribution mode and a valid matching certificate/private key. Apple signing secrets are read only by the signing helper and are stripped from test/build subprocess environments. Temporary signing material is cleaned up and pre-existing profile files/search paths restored.

The 16 Python tests in `BuildTests` pass with synthetic profile data and mocked `security`/build commands. These check profile/identity validation, cleanup on failure, both unsigned SDK command paths, signed-export metadata, avoiding overwrite and accidental uploads, credential-free device IPA packaging, and rejection of a simulator app for iPhone sideloading. They check logic and orchestration only, **not Apple's signing service, SDK behavior or real codesign execution**. The workflow passes `actionlint`. The actual test results are in `BUILD-TEST-RESULTS.txt`. GitHub access to the private `itssali911-netizen/Loqma-iphone` repository is confirmed. The first Apple SDK cloud build is pending when this source is initially uploaded; consult Actions for its outcome. No TestFlight upload or App Store submission has been performed. Windows upload instructions and a PowerShell helper are included; the PowerShell helper has not been executed on Windows. Free-account AltStore installation, renewal and HealthKit availability require physical-device verification.

Before distributing a signed build, run it on a physical iPhone and verify these app flows:

1. Import a website JSON backup, add/edit a food portion and a recipe, close/reopen the app, then repeat with airplane mode enabled.
2. Allow and deny camera access; scan a known product, read a barcode image, and try an unlisted barcode. Confirm that missing products are distinct from connection failures.
3. Allow and deny Health read access; refresh weights and confirm same-day manual entries are retained. Empty Health data must not be reported as proof that permission was granted.
4. Analyze a meal photograph, confirm multiple components and sauces, edit weights, and save. Verify actual native image preprocessing/model outputs and memory behavior. Download models once, close/reopen, then retry in airplane mode. Interrupt a download and retry.
5. Switch Arabic/English, edit grams and percentage macro targets, and inspect Dynamic Type, keyboard behavior, charts and right-to-left layout.

Local-model image recognition and native UI behavior remain **unverified on iPhone**. A single photograph cannot measure food weight or hidden ingredients; model ranking and reference portions must not be presented as measured accuracy.
