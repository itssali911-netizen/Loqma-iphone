# Luqma Native iOS

Build through `Scripts/build_ios.py` on Xcode 26.3+; iPhone / iOS 17+. Complete Arabic setup and migration instructions: **README-AR.md**.

**The iPhone build succeeded:** [version 1.1, build 18 and IPA download](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37945751234). Download the `Luqma-sideload-18` artifact, unzip it and save `Luqma-Sideload.ipa` in iPhone Files. In AltStore Classic, open **My Apps → +** and select the IPA while AltServer is running on your connected computer. See **BUILD-WINDOWS-AR.md** for Arabic installation and renewal instructions.

The GitHub Actions workflow uses macOS and Xcode 26.3. Source pushes to `main` start a `sideload` device build for personal re-signing with AltStore; this mode needs no Apple distribution certificate. Manual `check` builds both simulator and device SDK targets without signing; `ad-hoc` / `app-store` export an Apple-signed IPA only after valid signing inputs are configured.

This is a native SwiftUI app using HealthKit, AVFoundation, Vision, Swift Charts on-device ONNX Runtime and MLX vision inference. The built `Luqma-Sideload.ipa` must be re-signed by AltStore using the user's Apple account before installation. Free-account signatures expire after seven days; keep Developer Mode enabled while using these apps. No Apple account, signing certificate, API key or ChatGPT subscription is embedded. Camera, Health access and model inference still need physical-iPhone verification.

```sh
bash Scripts/verify.sh
```

Core tests are a standalone Swift package. The cloud build passed 17 core tests, 16 build-tool tests, iPhoneOS Release compilation and local signature verification. The same vision service also passed a mixed-food check with a separate dip component, followed by cached, download-disabled inference rejecting a blank image on Apple Silicon Metal. See **VALIDATION.md** for the verified build commit, IPA checksum, recognition limitations and remaining physical-device checks.

## Version 1.1 changes

The build scripts apply checksum-verified upstream Qwen3-VL fixes for sRGB image preprocessing and fused attention, reducing avoidable vision memory use. Direct Xcode builds must apply the same patch to their mlx-swift-lm checkout; an unpatched upstream 2.30.6 checkout does not include these fixes.

Advanced local vision uses pinned Qwen3-VL-4B-Instruct MLX 4-bit weights (~3.1 GB download), first describes the image without a menu, then estimates dish names and portions and performs a second review. The app matches names to reference foods locally and rejects contradictory generated IDs. Factual meal context refines generic wraps and dip containers without duplicating their estimated mass; explicit piece counts override model guesses. Plain flatbread uses a marked tentative pita reference rather than arbitrary generated nutrition. AI calorie estimates are calculated consistently from their macros. Separate dip containers are requested individually; a meat dish mentioning a sauce cannot be refined into an all-sauce component. Food counts, estimated weights, plausible ranges, catalog nutrition and explicitly marked estimates for unmatched foods replace single-label-only recognition in this mode. Requires an 8 GB RAM iPhone with Metal. CLIP remains the lightweight mode. Optional meal context is empty by default. Interrupted downloads preserve completed chunks; installed model inference is local and supports offline operation. This is not a claim of measured calorie accuracy or superiority to competitors.

An installed signing profile without HealthKit is now detected and explained. Direct reading still requires HealthKit in the final Apple signing profile. Health weight import from the on-device export.xml works without HealthKit entitlement and keeps same-day manual records. Export Health data, unzip in Files, select export.xml, review and confirm. Import is a snapshot and does not provide automatic step/activity synchronization.

About removes the ChatGPT-subscription phrase and licenses navigation row. Bundled third-party notices remain in resources. The version 1.1 device build succeeded. See VALIDATION.md for runtime results and remaining physical-device checks.
