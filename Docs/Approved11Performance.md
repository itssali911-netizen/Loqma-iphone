# Approved 11 screens — measured performance and limits

## Current evidence

The isolated performance commit is `32d204114a9a51bb95d6fc87ef933beafed9b6f0`.
[CI99, attempt1](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39867846285) compiled the actual iPhoneOS arm64 2.9/build99 IPA (minimum iOS17), passed **240 Core tests**, **75 BuildTests** and **all nine native performance scenarios**. Compilation and performance success do not establish functional or visual acceptance.

The same-day comparator is [CI98, attempt1](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39861550376), revision `67e050686ad0de33c1125ff1e40b937c26b04bba`. All **59 metric rows** and all comparison rows were independently checked against raw xcresult samples, identifiers, units and statistics. The separate AX containment follow-up `16c8961` does not appear in any of the nine timed routes: the assessment case stops at its first goal screen.

Verification revision `e378e449b68dbd81f7e4551d55ef0d963c5f7962` compiled the actual2.9/build100 IPA and passed240Core/75BuildTests. It corrects test scrolling, the approved calorie-footer color and DEBUG capture composition/data. Full native acceptance remains pending: its fitness case failed a five-second empty-age message expectation after175.783seconds, although the retained final native image/hierarchy shows the entire message above Continue. The test-only follow-up inspects one public accessibility snapshot, keeping the deadline and exact visibility assertion. No runtime or frozen performance source changes in that follow-up.

`PerformancePhase.json` starts a **new baseline** because CI100 runs on another UTC day. This neither removes nor replaces the accepted98→99 comparison. No later-day result will be compared to98 by waiving the day/hash guard. CI100's new native performance collection is still running at this documentation checkpoint.

## Actual comparable configuration

- Xcode26.6 (17F113), Swift6.3.3, macOS26.6.2 arm64; different shared CI hosts.
- Fresh iPhone16ProMax Simulator, iOS26.5; Release `-O`, whole-module compilation, sequential tests, no coverage.
- Explicit DEBUG compilation only enables the isolated synthetic fixture. Shipped Release has no fixture flag.
- Fixture `v1|entries=5000|days=7|today=800|seed=20261021`: normal protected diary file seeded once, then ordinary production decoding/views.
- Frozen benchmark/fixture hashes, scenario identities, sample counts, runtime, build settings, architecture and **2026-10-22 UTC** match.
- Launch: five recorded samples. Other scenarios: three, after a discarded warm-up.

## Actual before/after medians

Clock windows include XCUITest/accessibility synchronization and multiple actions. They are **not pure tap/transition latency**. CPU is exactly XCTest-reported process CPU seconds, **not utilization**; do not divide CPU by clock. Peak memory is physical kB, distinct from memory growth.

| Scenario | Clock before→after (s) | CPU before→after (s) | Peak memory before→after (kB) |
| --- | ---: | ---: | ---: |
| Process launch | 8.913445 → 7.319005 | Not Measured | Not Measured |
| Foreground resume | 2.138562 → 1.900572 | 0.965421 → 0.772676 | 73,488.576 → 77,076.608 |
| Four-tab round trip | 10.479581 → 10.243052 | 2.129698 → 1.968469 | 94,066.944 → 93,411.520 |
| Food logging round trip | 9.134373 → 8.622484 | 5.490686 → 5.273579 | 72,980.672 → 85,072.128 |
| Personal search → quantity | 4.197977 → 2.782742 | 21.168700 → 18.619755 | 85,678.272 → 85,678.336 |
| Seven-day calorie details | 2.030606 → 2.102880 | 11.180874 → 8.641269 | 75,503.808 → 76,536.000 |
| Profile → assessment entry | 8.947383 → 8.037260 | 14.577171 → 11.293384 | 76,044.544 → 76,961.984 |
| Profile → personalized plan | 3.109723 → 3.002412 | 13.851488 → 9.851743 | 74,963.136 → 76,241.088 |
| Expanded diary / four swipes | 18.060578 → 11.979547 | 21.592607 → 12.716939 | 113,088.768 → 81,795.200 |

System responsive-launch duration is separate from the launch test-clock window: **5.743439→3.982745s**, 30.66% lower (five samples). This is terminated-process launch after warm-up, **not reboot-cold/file-cache-cold launch**.

Expanded diary: clock **33.67% lower**, CPU seconds **41.11% lower**, peak memory **27.67% lower**. This supports the targeted lazy-row change in that workload. Search→quantity clock was33.71% lower. Shared-host scheduling remains a limitation; these are observations, not universal speed guarantees.

**Regressions are retained:** calorie-details clock **+3.56%**; food-logging peak memory **+16.57%**; foreground-resume peak **+4.88%**; assessment, plan and calorie peaks rose roughly1–2%. Therefore no application-wide memory reduction or blanket improvement is claimed. See the retained raw report/audit for sample dispersion and all59rows.

System scroll drag/deceleration duration was2.583001→2.582740s, essentially unchanged; it is not FPS. Sixteen zero-valued cycle/instruction rows are unavailable Simulator counters, not zero CPU work.

| Requested metric | Result |
| --- | --- |
| Reboot-cold launch / exact transition latency | Not Measured |
| Observed FPS /60Hz/120Hz / dropped frames / frame-time distribution | Not Measured |
| Animation hitches / main-thread hang trace | Not Measured |
| CPU utilization percentage | Not Measured; process CPU seconds above |
| Battery / energy / thermal impact / leak freedom | Not Measured |
| Physical ProMotion / physical camera / remote AI acceleration | Not Measured |

No hitch/frame data is present in the unfiltered metrics export, result database or attachments. Do not infer it from screenshots or elapsed duration. Apple's [xcresult export documentation](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes) says unfiltered metrics include all available metrics.

## Matched full-probe Core microbenchmark

This is actual macOS Core serialization, **not iOS UI/FPS**. Actual `Backup.encode` is compiled `swiftc -O` over5000 entries/seven days, one warm-up and three samples. Fixture construction, equality checks and invalid-date checks are outside timing.

| Metric | CI98 | CI99 | Reduction |
| --- | ---: | ---: | ---: |
| Median wall seconds |1.521089708|0.040115333|97.36%|
| Median process CPU seconds |1.486871|0.039154|97.37%|
| Process-lifetime peak RSS bytes |66,060,288|29,622,272|55.16%|
| Encoded JSON bytes |2,016,610|2,016,610|Identical|
| Strict invalid-day checks |2 rejected|2 rejected|Unchanged|

Encoded SHA-256 on both: `05f7611da103a904a7bf36d5f52b52abf73abefad9c4e00741e462d06d88cbca`.
RSS is process lifetime high-water memory, not per-sample allocations or iPhone memory. The separate early Core-only98→99 run observed95.80% wall reduction; it is retained independently and is not mixed into this full-probe table.

## Focused production changes, isolated in32d2041

| Exact path | Purpose / compatibility |
| --- | --- |
| `Luqma/Core/Backup.swift` | Reuse successfully strict-validated day strings within one snapshot check, cap512; retain all per-record nutrition/amount/weight checks, schema and invalid-day parsing. No shared mutable formatter. |
| `Luqma/Services/PhotoPreparationWorker.swift` | Serial actor for the same640px ImageIO thumbnail/display preparation and JPEG0.85 encoding; cancellation checks and local privacy-safe signposts. No persistent image cache. |
| `Luqma/Services/Camera.swift` | Await encoding with owned task/generation and weak coordinator; reject stale results on teardown/cancel. |
| `Luqma/Views/PhotoMealView.swift` | Owned preview task/generation, asynchronous publication, cancellation/reopening/error handling; preserve original photo and1280px remote preprocessing/API/model. |
| `Luqma/Views/DiaryView.swift` | Eager expanded-meal rows → `LazyVStack`; stable UUIDs/order/spacing/tap-edit unchanged. Baseline exposes200eager rows. |
| `Luqma.xcodeproj/project.pbxproj` | Register worker in the real application build phase; no target/flag change. |
| `Tests/BackupValidationSafetyTests.swift` | Four native-passed tests: long history/round trip, invalid day, amount/nutrition and weight validation despite repeated keys. |

Report/phase/checksum files are additional non-runtime bookkeeping. No third-party performance library, database schema change or unrelated refactor. Codec cancellation cannot interrupt a running codec; input may remain retained until it returns. Remote AI speed and physical camera responsiveness remain unverified.

## Current Apple techniques and deployment support

- Swift actors/structured cancellation: supported by Swift5.9/iOS17; a MainActor-inheriting task alone would not move codec work away. [Apple responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- `UIImage.preparingForDisplay()` (iOS15+) prepares the existing thumbnail with fallback. [API](https://developer.apple.com/documentation/uikit/uiimage/preparingfordisplay()).
- `OSSignposter` (iOS15+) records PreviewPreparation/CameraJPEG intervals without photos, descriptions or credentials. [API](https://developer.apple.com/documentation/os/ossignposter).
- `LazyVStack` (iOS14+) targets the measured eager rows. [API](https://developer.apple.com/documentation/swiftui/lazyvstack).
- [WWDC25 SwiftUI profiling](https://developer.apple.com/videos/play/wwdc2025/306/) and [WWDC26 responsiveness](https://developer.apple.com/videos/play/wwdc2026/268/) inform the pass; no Instruments27-only capability is claimed on installed Xcode26.6.

Standard SwiftUI/UIKit/Charts retain system-managed frame pacing. No custom synchronized renderer justifies `CADisplayLink`, `preferredFrameRateRange` or `CADisableMinimumFrameDurationOnPhone` here. No flag, continuous timer or artificial loop was added. Apple's [ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays) and [frame-range API](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange) do not guarantee120Hz: hardware, Low Power Mode, thermals and scheduling control it. Energy and refresh must be checked on actual hardware.

## Functional/capture outcomes are independent

CI99's assessment case passed the input/rapid-drag/invalid-value/save-resume/back-forward stages, review/application/deletion and relaunch, then failed revealing the saved breakfast entry. Its helper swiped only upward even though the row was above the pinned header. The pending test-only correction retains eight bounded real gestures, foreground scope, exact existence/hittability assertions and actual taps; direction follows the target's live frame. No assertion is removed.

CI99 approved Arabic captures completed **13/13**, including all11 reference screens plus age/height, with actual runtime font audits. All26English captures completed. Regular capture completed4/51 before `simctl screenshot` exceeded90seconds. Its leftover fifth PNG is diagnostic only; no crash/main-thread app hang was established. The failure remains visible, and fresh capture is required.

CI98's earlier activity-disclosure ID propagation was corrected separately in16c8961 and progressed past in99. All25 supplied/recovered asset files remain byte-identical. Excluded design-series Screen8 Food Swipe Actions remains excluded. No physical FPS or total functional acceptance is inferred from screenshots.

## Retained evidence and history

Local immutable evidence: `work/approved29-build98-performance-baseline/`, `work/approved29-build99-performance-optimized/` (report/rawxcresult/normalized59rows/audit), corresponding `-ipa`, `-interactions`, `-approved`, `-reference`, `-ui` artifact directories. Original failed evidence is never overwritten.

CI94/95 compiled but failed assessment assertions;95performance is historical because corrected96UI changed its workload. CI96/97 native readiness failed before application validation, and other jobs were cancelled for unavailable hosted macOS capacity. CI98 is the first fully restored, measured pre-optimization baseline; its functional failure is not concealed by the successful performance job. Full integration/file inventory and visual limits are documented in [Approved11Integration.md](Approved11Integration.md).
