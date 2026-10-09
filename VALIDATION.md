# Validation — version 1.1, 2026-10-09

A real iPhoneOS arm64 Release build succeeded with Xcode 26.3 on the GitHub macOS runner. [Build 18](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37945751234) produced `Luqma-Sideload.ipa` from source commit `d9638341078486abb639a55e95847bc8e3fa09e5`.

The IPA uses bundle ID `app.luqma.diary`, version 1.1, build 18, minimum iOS 17, and is 16,322,956 bytes. SHA-256: `5cd8b9ec3c2d7ad0d957517ae8931e0778b6c97c4060ca136342c4436ae63ed6`. The artifact ZIP digest and both ZIP CRC checks match. The Mach-O binary is arm64 for iPhoneOS, not a simulator binary. MLX Metal shaders, the pinned model manifest, food references and third-party notices are packaged; model weights download separately on first use.

## Completed checks

- 17 Foundation XCTest tests and 16 Python build-tool tests passed in the device build. Tests cover six official NIDDK reference scenarios, 60 g nutrition and editing in place, serving conversion, conserved macro calories, recipes/meal prep, backup round trips, daily weights, Health XML units and latest daily weights, profile capability detection, mixed generative output, visible counts, catalog-first nutrition, explicit weighed context, numeric catalog IDs, dish-name/reference matching, tentative plain-flatbread references, stated-count priority, compound-dish/dip separation and contradictory-ID rejection, duplicate/impossible mass rejection, non-food refusal and bounded unknown-food nutrition.
- Both Apple SDK and runtime builds apply verified upstream Qwen3-VL sRGB preprocessing and fused vision-attention backports (PRs 411/455) to the exact pinned mlx-swift-lm 2.30.6 source. The original/patched file hashes are checked; changed dependencies fail closed. Local patch validation confirmed exact application, idempotence and rejection of modified source.
- Native SwiftUI, HealthKit, AVFoundation, Vision, ONNX Runtime and MLX compiled against the actual iPhone device SDK. Local ad-hoc signing and `codesign --verify --deep --strict` passed.
- Packaged vision-model.json, photo-foods.json and LICENSES.txt match the source byte for byte. The current About view contains no subscription phrase or licenses navigation. The optional meal-description field has an empty placeholder.
- Local-model files are pinned to a Hugging Face revision, size and SHA-256. Downloads preserve completed 24 MB chunks and verify integrity before loading. The installed-model loader uses a local directory.

## Vision runtime

The exact VisionAnalyzer service and Core decoder passed the build-18 runtime check on Apple Silicon Metal with a checksum-pinned public-domain USDA photograph, without meal hints. The decoded result contained seven components: grilled chicken, a wrapped pita roll, a chicken pita, red pepper, a green vegetable labelled green beans, a standalone white dip and plain pita bread. The check requires all four major visible categories (prepared wrap, grilled meat, a standalone dip item and plain pita), rejects known absent fries/rice/orange categories, and passed cached inference with downloads disabled on a blank non-food image. The report records `tested: true`, `passed: true`, `cached_without_downloads: true` and `no_food_fixture_rejected: true`. Its 405.16 seconds include initial model download/loading and both image checks; this is not an iPhone inference-speed measurement.

Manual review confirmed that the dip has its own component and estimated mass; a compound chicken dish mentioning a dip cannot satisfy this check. The model still gave an uncertain vegetable identification (green beans rather than reliably identifying the pickled vegetables), and the dip's recipe was not verified. This test demonstrates mixed-food recognition and the local runtime path, not perfect ingredient identification or measured portion accuracy. It does not use the user's original shawarma photograph, which was unavailable as a source image.

A runtime fixture check is not a calorie-accuracy study or a comparison with Cal AI. Food mass, oils, fillings and sauce identity cannot be measured from a single photograph. Weight ranges describe portion uncertainty; they do not cover every possible recipe variation. Unmatched nutrition is explicitly marked as an AI estimate. Advanced inference needs an 8 GB RAM iPhone with Metal and a ~3.1 GB initial model download; CLIP remains the lighter mode.

## Health and signing

The package requests `com.apple.developer.healthkit`, but its local ad-hoc signature is not an Apple account signature. An installed app needs that entitlement in its final Apple provisioning profile and signature. AltStore's signing path may omit it. The app detects a profile without HealthKit before authorization, explains the issue and supports local import of Health's export.xml weight records. Import is a reviewed snapshot, not automatic activity synchronization; existing same-day manual weight readings take priority.

HealthKit is listed for free Apple developer accounts in Apple's supported-capabilities table. A paid membership is not the root cause of this error. Neither an app setting nor a pre-signed local entitlement can grant a capability removed during personal re-signing.

## Remaining physical-iPhone checks

No physical iPhone, user's Apple credentials or final personally signed installation was available to this build environment. Direct Health authorization, XML file selection through Files, camera permission, barcode capture, Dynamic Type, on-device MLX peak memory/latency and offline relaunch still require a device check. Apple Silicon macOS inference is not proof of iPhone runtime performance.

Before installing, export a Luqma JSON backup. Add the new IPA through AltStore using the same Apple account and original bundle ID, without deleting the installed app. Refresh renews a signature; it does not update app code. Free signatures need weekly renewal and Developer Mode must stay enabled while using them.

The project has no Apple account, certificate, cloud-vision API key or automatic App Store/TestFlight submission. No user meal photograph or Health record was uploaded during validation. The image fixture is public-domain USDA material.
