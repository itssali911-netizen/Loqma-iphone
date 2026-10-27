# HealthKit signing compatibility

| Route | This release's evidence | Required before claiming success |
|---|---|---|
| Native SwiftUI / HealthKit | Source and SDK compilation; actual results in test report | Apple-authorized installed signature and individual user consent |
| Xcode device installation | NOT TESTED; no attached device/account | Matching Team, final app ID, certificate, profile and iPhone; actual authorization and reading |
| Personal Team / free Apple account | NOT TESTED | Apple must actually issue an appropriate profile. No workaround may grant unauthorized capabilities |
| iLoader | NOT TESTED on a device/account | Check exact tool/version, generated profile and final signed entitlement; preserving a string is insufficient |
| AltStore | NOT TESTED | Same final-IPA and physical-device checks |
| SideStore | NOT TESTED | Same final-IPA and physical-device checks |
| Signature/profile missing HealthKit | Synthetic controller/signing failure coverage; no physical installation | Luqma reports a concrete unavailable state; nutrition remains usable |
| Background delivery | UNSUPPORTED in this configuration | Not requested; foreground fallback is intentional |

Apple capability availability depends on program membership and provisioning configuration. This project does not guarantee every free account or re-signer supports the required workflow. The previously compiled community signer in Support is a separate experimental tool; it was not used to sign this IPA and has no verified physical HealthKit result.

Entitlements examples express requested capabilities. They are not security authorization. Do not copy another application's entitlements or profile. Do not strip HealthKit to make a build appear compatible. A code-signature seal PASS is separate from a valid Apple identity, profile authorization, installation and real data access.

The application reads ten types: steps/count, walking-running distance/metres (display km), active/resting energy/kcal, body mass/kg, height/cm, body fat/percent, heart rate/bpm, recorded workout duration/minutes, and asleep intervals/hours. Daily cumulative statistics are merged by HealthKit rather than summing Watch/iPhone source subtotals. Workout calories are not added a second time. Sleep unions overlapping asleep intervals, excludes awake/in-bed, and uses the local calendar. Workout records retain their HealthKit UUID; distinct duplicate workouts from different writers are not heuristically deleted.

History is bounded to7/30/90days. Anchored UUID upsert/deletion caches for weights/workouts/sleep are memory-only. Full foreground/manual/range/time-zone rereads reconcile history and read revocation; foreground observer events use incremental reads. App restart deliberately rebuilds the private cache. Only refresh preference and history range are persisted in UserDefaults. No Health values are added to diary exports, AI requests, analytics or production logs. Existing manual entries/calorie goals remain independent.

Official references checked for implementation:

- [Authorizing access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [HealthKit queries and Swift concurrency](https://developer.apple.com/documentation/healthkit/queries)
- [Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [Sleep analysis values](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
- [Apple capability overview](https://developer.apple.com/help/account/capabilities/capabilities-overview/)
- [Supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
