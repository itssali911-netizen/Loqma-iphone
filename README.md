# Luqma Native iOS

Open `Luqma.xcodeproj` in Xcode 16+; iPhone / iOS 17+. Complete Arabic setup and migration instructions: **README-AR.md**.

Windows / cloud builds: **BUILD-WINDOWS-AR.md**. The included GitHub Actions workflow uses macOS and Xcode 26.3. Source pushes to `main` start a `sideload` device build for personal re-signing with AltStore; this mode needs no Apple distribution certificate. Manual `check` builds both simulator and device SDK targets without signing; `ad-hoc` / `app-store` export an Apple-signed IPA only after valid signing inputs are configured. Check this repository's **Actions** page for the actual build result and downloadable artifacts. A configured workflow alone does not prove that a build succeeded.

This is a real SwiftUI app using HealthKit, AVFoundation, Vision, Swift Charts and on-device ONNX Runtime. It is a source project, not a built IPA. A future `Luqma-Sideload.ipa` must be re-signed by AltStore using the user's Apple account before installation. Free-account signatures expire after seven days. No Apple account, signing certificate, API key or ChatGPT subscription is embedded.

```sh
bash Scripts/verify.sh
```

Core tests are a standalone Swift package. iOS framework compilation and physical-device validation require macOS/Xcode. See **VALIDATION.md** for exactly what has and has not been verified.
