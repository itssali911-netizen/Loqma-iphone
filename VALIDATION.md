# Validation — version 1.2, 2026-10-09

## Delivery status

Automatic Apple Health sync is implemented and committed. The latest app-source commit is `242d1460c35384a4d055e5e20047e79f3667da03`. [Build 21](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37968869599) failed before any workflow step started: the job has no steps, downloadable log or app output. Build 20 and one retry stopped in the same way. The connector did not expose the startup failure reason. No claim is made that billing, quota or a particular runner issue is confirmed. The run's Annotations must be inspected before another retry. The latest source is not a verified final IPA.

## Verified iPhone build

[Build 19](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37965633305) successfully compiled an iPhoneOS arm64 Release app with Xcode 26.3 from source `ba5b8a78b95ca325f10142329c3b5c33cb740309`. It produced `Luqma-Sideload.ipa`, bundle `app.luqma.diary`, version 1.2, build 19, minimum iOS 17, 16,384,899 bytes. SHA-256: `02da11bb06d30f9174cd1fc9775f1361b7910e74fd923b573a5afd618c052e13`. Artifact ZIP digest and both ZIP CRC checks match. The Mach-O binary is arm64 for iPhoneOS, not a simulator. Local ad-hoc signing and `codesign --verify --deep --strict` succeeded. Both `com.apple.developer.healthkit` and `com.apple.developer.healthkit.background-delivery` are present in the binary's requested entitlements. There is no Apple provisioning profile or personal Apple account signature in this package.

This earlier IPA predates the final SwiftUI scene-phase correction. The full workflow failed its vision-category assertion and is not reported as a fully passing release. It is retained as a validation record, not promoted as the final installation.

## Completed checks in build 19

- 20 Foundation XCTest tests passed with zero failures. These cover the existing nutrition, servings, macros, recipes, NIDDK reference scenarios, backups, photo decoding and Health XML, plus live Health weight addition/deletion, latest-daily fallback, manual-entry priority, invalid/future/empty reads, same-batch deletion priority, backward-compatible cache decoding and device-cursor isolation on backup merge.
- 16 Python build-tool tests passed. The signing validator rejects an Apple export profile missing either required Health entitlement, with synthetic profile tests; this is not an account-signed installation test.
- Native SwiftUI, HealthKit, AVFoundation, Vision, ONNX Runtime and MLX compiled against the real device SDK. MLX Metal shaders, pinned model manifest, food references and notices are packaged. Resource bytes match source. Model weights download separately.
- Both SDK and runtime builds apply checksum-verified Qwen3-VL sRGB preprocessing and fused-attention backports to pinned mlx-swift-lm 2.30.6. Changed dependency sources fail closed.
- The About screen has no ChatGPT-subscription phrase or licenses navigation. The optional meal-description placeholder is empty.

## Automatic Health implementation

Observers for body mass, height, steps and active energy register synchronously in `didFinishLaunchingWithOptions`, including HealthKit background launches. Weight additions and explicit deletions use a paged anchored query. UUID records and the cursor are persisted atomically with the diary; empty/denied reads do not purge weight history. Manual readings remain authoritative for their day. Concurrent events are queued and their completion handlers called once after processing. Cumulative HealthKit statistics avoid summing overlapping phone/watch samples manually. Cached activity is shown in the diary. Activity calories remain informational and are not added twice to a weight plan.

The final source uses SwiftUI `scenePhase`, including its initial value, to refresh fully on foreground activation and stop the 30-second activity safety refresh when backgrounded. It does not rely on legacy UIApplicationDelegate foreground callbacks in a scene-based app. This final lifecycle correction was reviewed against Apple's SwiftUI lifecycle documentation but has not been Xcode-compiled because build 21 did not start.

Background delivery requests `.immediate` and reports actual registration acceptance, partial acceptance or unavailability. iOS still caps background step-count updates at hourly and decides when delivery occurs. The diary retains complete file protection; locked reads/writes defer to unlock without overwriting existing data. Disconnect removes observers, stops polling and disables background delivery, while retaining history. None of these background behaviors has been tested on a physical iPhone in this environment.

## Health signing path

An installed app needs HealthKit and HealthKit Background Delivery in its final Apple provisioning profile and signature. A locally requested entitlement alone does not grant them. HealthKit is listed for free Apple developer accounts; a paid membership is not established as the cause of the previous missing-entitlement error. An AltStore path that removes Health permissions will still fail regardless of user permission settings.

Impactor 2.6.5 was reviewed at its release tag. Its signer reads binary entitlements, requests matching capabilities through Apple's developer service, obtains an Apple provisioning profile and signs with the profile. The free-account blocked-capability list does not include HealthKit. Its optional Identifier field can preserve the exact installed bundle ID; otherwise it appends the team ID. This is a source-reviewed proposed free Windows path, not proof that Apple approved the user's final profile. See [HEALTH-SETUP-AR.md](HEALTH-SETUP-AR.md) for backup, identifier preservation, installation and device checks.

The app detects a known missing Health entitlement before authorization. Apple intentionally conceals read denial, so completing the permission request is not evidence that readings were granted. Local export.xml import remains a reviewed snapshot fallback and is not presented as automatic synchronization.

## Vision runtime result

Build 19 ran the exact VisionAnalyzer and Core decoder on Apple Silicon Metal with a checksum-pinned public-domain USDA photograph and no meal hints. It produced seven components: chicken breast slices, a vegetable pita wrap, chicken-topped flatbread, a standalone white yogurt-like dip, red pepper, green pickles and plain pita. The test failed because its standalone-meat predicate required “chicken strips” or a “grilled” label; “chicken breast slices” was not accepted. The checker now accepts standalone breast/slice synonyms while excluding bread/wrap/sandwich toppings, retaining the independent dip/plain-bread checks and known-absent-side rejection. It records category flags to explain future failures. This corrected checker has not run on Metal because builds 20/21 did not start. No pass is fabricated.

The unchanged vision service previously passed build 18's mixed-food check and cached, download-disabled blank-image refusal in 405.16 seconds including initial downloads/loading. Build 19 did not reach that cached blank-image check after its assertion failed. Neither run is an iPhone performance measurement, a calorie-accuracy study or a comparison with Cal AI. The vegetable and dip recipe labels remain uncertain; the user's original shawarma source photo was unavailable. A photograph cannot measure hidden oils or exact mass. Advanced mode requires an 8 GB RAM iPhone and ~3.1 GB initial download; CLIP remains the lighter mode.

## Remaining physical-iPhone checks

No physical iPhone, Apple account credentials or final personally signed profile was available. One-time authorization, a new Health weight appearing in the chart, addition/deletion while suspended, protected-data recovery, camera/barcodes, MLX memory/latency and offline relaunch require device checks. No user Health record or meal photograph was uploaded during verification. The image fixture is public-domain USDA material.

Before a final update, export a JSON backup and preserve the Apple account and exact installed identifier. Do not delete the previous app to resolve a signing error. Personal free signing requires weekly renewal and Developer Mode; the computer is needed for signing/renewal, not for Health synchronization. The project has no embedded certificate, Apple credentials or cloud-vision API key and performs no automatic App Store/TestFlight submission.
