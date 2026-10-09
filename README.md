# Luqma Native iOS

Build through `Scripts/build_ios.py` on Xcode 26.3+; iPhone / iOS 17+. Complete Arabic setup and migration instructions: **README-AR.md**.

**Version 1.2 automatic Health sync is implemented in source.** The latest source verification, [build 21](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37968869599), failed before any build step started and has no logs or IPA. Its startup failure reason was not available through the repository connector; check the run's Annotations before rerunning. Do not treat this as a verified final installation.

The earlier [build 19](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37965633305) did compile the iPhoneOS app and produce a version 1.2 IPA, but it predates the final SwiftUI foreground-lifecycle correction and its full workflow did not pass the vision fixture check. It is retained as a build record, not promoted as the final update. **VALIDATION.md** identifies exactly what was verified.

The proposed free Windows path for automatic Apple Health is Impactor 2.6.5, using the same Apple account and installed bundle identifier; follow **HEALTH-SETUP-AR.md** after a final IPA is built. **BUILD-WINDOWS-AR.md** covers general installation and renewal.

The GitHub Actions workflow uses macOS and Xcode 26.3. Source pushes to `main` start a `sideload` device build for personal re-signing with AltStore; this mode needs no Apple distribution certificate. Manual `check` builds both simulator and device SDK targets without signing; `ad-hoc` / `app-store` export an Apple-signed IPA only after valid signing inputs are configured.

This is a native SwiftUI app using HealthKit, AVFoundation, Vision, Swift Charts, on-device ONNX Runtime and MLX vision inference. The built IPA needs personal re-signing before installation. Automatic Health requires both HealthKit and HealthKit Background Delivery in the final Apple profile/signature. Free-account signatures expire after seven days; keep Developer Mode enabled while using these apps. No Apple account, signing certificate, API key or ChatGPT subscription is embedded. Camera, Health access and model inference still need physical-iPhone verification.

```sh
bash Scripts/verify.sh
```

Core tests are a standalone Swift package. Build 19 passed 20 core tests, 16 build-tool tests, iPhoneOS Release compilation and local signature verification. The later source-only lifecycle correction has not yet been compiled by Xcode because the hosted job did not start. See **VALIDATION.md** for the verified build commit, IPA checksum, vision runtime results and remaining physical-device checks.

## Version 1.2: automatic Apple Health

Observer queries are installed synchronously in the application delegate at launch, including a HealthKit background launch. Weight changes use an anchored query: additions/deletions update the daily chart while preserving manual readings. The cursor and records are saved atomically with the diary, and an empty/denied read never erases history. Events arriving during a read are queued and acknowledged once after processing. Height and today's HealthKit cumulative steps/active energy update automatically. Cached activity appears in the diary; a foreground 30-second safety refresh handles delayed notifications and midnight. Opening the app triggers a full refresh.

Both requested Health entitlements are embedded in the local package. Background delivery requests `.immediate`, but iOS controls delivery and throttles background step-count notifications to at most hourly. The panel reports whether registration succeeded; a signature that only allows foreground reads does not pretend background is enabled. Locked protected data is left intact and retried after unlocking. Disconnect stops observers, polling and background delivery. Activity calories are informational and never added twice to the weight plan.

Impactor 2.6.5 source was checked for entitlement-to-capability requests and profile-based signing. It is the proposed free Windows installation path, with weekly renewal. Apple's acceptance of a particular account/profile and actual background updates have not been tested on a physical iPhone here. The one-time Health permission dialog still needs user consent. **HEALTH-SETUP-AR.md** includes installation, identifier preservation and an on-device verification checklist.

## Version 1.1 changes

The build scripts apply checksum-verified upstream Qwen3-VL fixes for sRGB image preprocessing and fused attention, reducing avoidable vision memory use. Direct Xcode builds must apply the same patch to their mlx-swift-lm checkout; an unpatched upstream 2.30.6 checkout does not include these fixes.

Advanced local vision uses pinned Qwen3-VL-4B-Instruct MLX 4-bit weights (~3.1 GB download), first describes the image without a menu, then estimates dish names and portions and performs a second review. The app matches names to reference foods locally and rejects contradictory generated IDs. Factual meal context refines generic wraps and dip containers without duplicating their estimated mass; explicit piece counts override model guesses. Plain flatbread uses a marked tentative pita reference rather than arbitrary generated nutrition. AI calorie estimates are calculated consistently from their macros. Separate dip containers are requested individually; a meat dish mentioning a sauce cannot be refined into an all-sauce component. Food counts, estimated weights, plausible ranges, catalog nutrition and explicitly marked estimates for unmatched foods replace single-label-only recognition in this mode. Requires an 8 GB RAM iPhone with Metal. CLIP remains the lightweight mode. Optional meal context is empty by default. Interrupted downloads preserve completed chunks; installed model inference is local and supports offline operation. This is not a claim of measured calorie accuracy or superiority to competitors.

An installed signing profile without HealthKit is now detected and explained. Direct reading still requires HealthKit in the final Apple signing profile. Health weight import from the on-device export.xml works without HealthKit entitlement and keeps same-day manual records. Export Health data, unzip in Files, select export.xml, review and confirm. Import is a snapshot and does not provide automatic step/activity synchronization.

About removes the ChatGPT-subscription phrase and licenses navigation row. Bundled third-party notices remain in resources. The version 1.1 device build succeeded. See VALIDATION.md for runtime results and remaining physical-device checks.
