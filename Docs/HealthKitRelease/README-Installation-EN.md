# Luqma 2.9 (120) — HealthKit re-signable preview

This is a real iPhoneOS device build with native read-only HealthKit. Its ADHOC_HASH signature seals local resources; it is not an Apple developer signature. No Apple provisioning profile is included. Direct installation or universal HealthKit compatibility is not implied.

1. Download the IPA and SHA256SUMS from the same release and verify hashes.
2. Export your existing diary using Luqma's backup flow. Do not delete your installed app. A changed Team or bundle ID may create a different app/container and prevent automatic data continuity.
3. Re-sign using a compatible tool, an authorized Apple certificate and a matching profile permitting `com.apple.developer.healthkit` for the final identifier, or build/install the source through Xcode with official Apple signing. Preserve the existing identifier and Team when possible.
4. Inspect the FINAL re-signed IPA on macOS:

```sh
sh Tools/verify-healthkit-signing.sh --ipa FINAL.ipa --output FINAL-report.json
```

Use `--expected-bundle app.luqma.diary` only when that is the actual final identifier. The verifier does not sign, install, or grant access. Exit0 is a static inspection pass only; exit1 a measured failure; exit2 incomplete verification or required Apple signing. Profile VALID means decoded claims matched; it is not independent Apple CMS approval or physical-device verification.

5. Install a legitimately signed build permitted on your iPhone. Open Settings > Apple Health > Connect Apple Health. Choose individual types in Apple's native consent sheet. Luqma never asks for Apple ID credentials.
6. Refresh manually or return to the app; choose 7/30/90 days. Changes while in use are read incrementally. Background delivery is not requested in this version.

No reading means unknown, never invented zero or confirmed denial. Request completion never proves read authorization. Manage access in Health > profile > Apps and Services > Luqma (labels vary by iOS). Stopping Luqma refresh clears its volatile readings; revoke system access in Health.

Physical iPhone installation, real Health records, free-account signing, iLoader, SideStore and AltStore are NOT TESTED for this candidate. Each final tool/account/profile combination must be checked separately.

Source build: use a modern Mac/Xcode with the iOS17+ SDK (build script requires Xcode16+, CI26.6). Xcode14.2 on Monterey12.7.6 cannot build this source. Open Luqma.xcodeproj, scheme Luqma, select your Team/automatic signing/HealthKit and a connected iPhone. Do not change the identifier as a blind signing workaround. Keep private certificates, keys, profiles and credentials out of public releases.
