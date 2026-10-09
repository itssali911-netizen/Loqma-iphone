# Luqma Native iOS

Open `Luqma.xcodeproj` in Xcode 26.3+; iPhone / iOS 17+. Complete Arabic setup and migration instructions: **README-AR.md**.

**The iPhone build succeeded:** [build 3 and IPA download](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/37903825640). Download the `Luqma-sideload-3` artifact, unzip it and save `Luqma-Sideload.ipa` in iPhone Files. In AltStore Classic, open **My Apps → +** and select the IPA while AltServer is running on your connected computer. See **BUILD-WINDOWS-AR.md** for Arabic installation and renewal instructions.

The GitHub Actions workflow uses macOS and Xcode 26.3. Source pushes to `main` start a `sideload` device build for personal re-signing with AltStore; this mode needs no Apple distribution certificate. Manual `check` builds both simulator and device SDK targets without signing; `ad-hoc` / `app-store` export an Apple-signed IPA only after valid signing inputs are configured.

This is a native SwiftUI app using HealthKit, AVFoundation, Vision, Swift Charts and on-device ONNX Runtime. The built `Luqma-Sideload.ipa` must be re-signed by AltStore using the user's Apple account before installation. Free-account signatures expire after seven days; keep Developer Mode enabled while using these apps. No Apple account, signing certificate, API key or ChatGPT subscription is embedded. Camera, Health access and model inference still need physical-iPhone verification.

```sh
bash Scripts/verify.sh
```

Core tests are a standalone Swift package. The cloud build passed 11 core tests, 16 build-tool tests, iPhoneOS Release compilation and local signature verification. See **VALIDATION.md** for the verified build commit, IPA checksum and remaining physical-device checks.

## Version 1.1 changes

Advanced local vision uses pinned Qwen3-VL-2B-Instruct MLX 4-bit weights (~1.8 GB download), inspects a full meal and performs a second review. Food counts, estimated weights, plausible ranges, catalog nutrition and explicitly marked estimates for unmatched foods replace single-label-only recognition in this mode. Requires an 8 GB RAM iPhone with Metal. CLIP remains the lightweight mode. Optional meal context is empty by default. Interrupted downloads preserve completed chunks; installed model inference is local and supports offline operation. This is not a claim of measured calorie accuracy or superiority to competitors.

An installed signing profile without HealthKit is now detected and explained. Direct reading still requires HealthKit in the final Apple signing profile. Health weight import from the on-device export.xml works without HealthKit entitlement and keeps same-day manual records. Export Health data, unzip in Files, select export.xml, review and confirm. Import is a snapshot and does not provide automatic step/activity synchronization.

About removes the ChatGPT-subscription phrase and licenses navigation row. Bundled third-party notices remain in resources. This version is undergoing a fresh Xcode device build; see the latest workflow and VALIDATION.md for verified results.
