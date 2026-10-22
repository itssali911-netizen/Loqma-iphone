# Approved 11 screens — performance evidence

**Status:** CI98 provides an audited nine-scenario Simulator baseline. The seven-file performance candidate is prepared; its build, four new Core tests and matched after measurements are pending.
No application-wide functional acceptance, measured improvement, verified 60/120 FPS or battery saving is claimed.

The approved UI remains the visual baseline. This pass changes no approved artwork, font, color, dimensions, nutritional arithmetic or remote-analysis contract.
Excluded Food Swipe Actions remain excluded. Visual verification belongs in [Approved11Integration.md](Approved11Integration.md).

## Selected baseline and history

Selected baseline: **CI98, attempt 1**, revision `67e050686ad0de33c1125ff1e40b937c26b04bba`.
[Run 39861550376](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39861550376) has actual successful native performance artifacts.
`Docs/PerformancePhase.json` selects `optimized`, baseline run `39861550376`, attempt `1`; this is configuration, not an after result.
The separate accessibility follow-up is `16c89615dc8ffd83b13750f15fc72446c1104e57`, parent `67e0506`; its native validation is pending.

| Earlier evidence | Outcome / retained limitation |
| --- | --- |
| [CI94](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39628492866) | 236 Core/68 BuildTests passed; assessment failed. Nine performance cases failed through collector/selector issues. Rejected UI baseline. |
| [CI95](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39637212015) | Nine performance cases passed; assessment failed. Approved Arabic13/English26 collections captured; broader Arabic51 collection failed for identical offscreen dinner/snack frames. Superseded after visual corrections. |
| [CI96](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39674125464) | UI corrections preceded complete asset recovery. Performance job canceled; not the selected final visual-workload comparator. |
| [CI97](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39676292580) | Original assets recovered. Performance failed before app build/test: Simulator boot exit149/error405, followed by recovery-shutdown timeout. No accepted UI measurements. |
| [CI98](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/39861550376) | Same production UI and performance workload as CI97. Bounded infrastructure correction; build, 236 Core, 75 BuildTests and nine performance cases passed. Separate assessment failed. Selected baseline. |

No failed run is substituted for valid measurements. Differences among unchanged earlier Core timings are CI variation, not optimization results.

## Actual CI98 configuration

| Item | Recorded value |
| --- | --- |
| App target | iOS **17.0**; Swift language mode **5**, tools version **5.9** |
| Toolchain | Xcode **26.6**, build **17F113**; Apple Swift **6.3.3** |
| Host / destination | macOS **26.6.2 arm64**, shared runner; fresh **iPhone16ProMax Simulator, iOS26.5** |
| Build / execution | Release **`-O`**, whole-module compilation, no coverage; sequential tests |
| Fixture compilation | Explicit `DEBUG` only for the isolated Simulator fixture hook |
| Fixture identity | `v1\|entries=5000\|days=7\|today=800\|seed=20261021` |
| Persistence | Real diary file seeded once; ordinary production decoding/views on relaunch |
| Recorded day / timezone | **2026-10-22 UTC** |
| Full probe start / finish | **22:01:59–22:39:48 UTC**; includes compilation/setup, not pure app runtime |
| Native performance | **9 passed, 0 failed, 0 skipped**; all required scenario identities present |
| Audit | **59 rows** checked against raw identities, samples, units, mean/median/stddev/min/max |

Archived source, asset, harness and fixture identities remain in `performance-report.json`; frozen harness/fixture hashes match main.
Only generated untracked `CorePerformance/` and `Luqma.xcodeproj/project.xcworkspace/` were recorded at measurement time.
Readiness succeeded on attempt1 with a real Settings PID; no reboot or boot handoff occurred in CI98.

## Nine-scenario baseline

Medians below retain actual XCTest units. Clock σ is population standard deviation.
Launch has **five** recorded samples; every other case has **three**, excluding XCTest's first warm-up.

| Scenario | Clock (s) | Clock σ (s) | App CPU time (s) | Peak physical memory (kB) |
| --- | ---: | ---: | ---: | ---: |
| Terminated-process launch | 8.913445 | 0.338390 | Not collected | Not collected |
| Warm foreground resume | 2.138562 | 0.381390 | 0.965421 | 73,488.576 |
| Four-tab round trip | 10.479581 | 0.168839 | 2.129698 | 94,066.944 |
| Home → food logging → Home | 9.134373 | 0.406236 | 5.490686 | 72,980.672 |
| Food search → quantity | 4.197977 | 0.424179 | 21.168700 | 85,678.272 |
| Home → seven-day calorie details | 2.030606 | 0.229596 | 11.180874 | 75,503.808 |
| Home → profile → assessment entry | 8.947383 | 0.268110 | 14.577171 | 76,044.544 |
| Profile → personalized plan | 3.109723 | 0.020582 | 13.851488 | 74,963.136 |
| Expanded diary, four fast swipes | 18.060578 | 0.801980 | 21.592607 | 113,088.768 |

**System responsive-launch duration is separate:** `ApplicationFirstFramePresentationResponsive.duration` median **5.743439s**, σ **0.312836s**, n=5.
The 8.913445s test-clock window includes synchronization/assertions. Relaunch after warm-up is not reboot-cold or cold-file-cache launch.
System scroll dragging/deceleration duration is **2.583001s** median, σ **0.018020s**, n=3; it is not FPS or a hitch rate.

Clock windows include XCUITest/accessibility overhead and sometimes several actions; they do not measure pure transition latency or critical tap response.
CPU seconds are exactly XCTest-reported app-scoped values, **not CPU%**. Aggregate work/window semantics can differ; no host-core-count explanation is assumed.
Do not derive CPU utilization by dividing the CPU and clock columns. The strongest bounded CPU comparison here is the Core rusage span below.
Peak memory retains raw **kB** units; memory-growth rows, which can be negative, are different metrics.
Sixteen zero-valued cycle/instruction rows are non-informative Simulator counters, not evidence of zero CPU work.

**Hitches, FPS, dropped frames and frame-time distribution: Not Measured.**
None appears in the raw export/result database despite the requested iOS26-gated hitch metric; no attachment or Instruments trace supplies them.
Apple documents that unfiltered metrics export includes all available metrics: [xcresulttool reference](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes).
Thus no additional hitch values are invented from absent rows, screenshots or scroll duration.

## Full-probe Core benchmark

These values belong to the Core benchmark inside the **same full CI98 probe**, not its separate earlier Core-only artifact.
Actual Core sources compile with `swiftc -O`; 5,000 entries/seven days are encoded after one warm-up, with three recorded samples.
Fixture construction, byte checks and invalid-date checks are outside the timed spans.

| Metric | Actual before | Optimized after |
| --- | --- | --- |
| Median wall time | **1.521089708s** | Pending |
| Median process CPU time | **1.486871s** | Pending |
| Wall samples (s) | `1.521089708, 1.558765917, 1.464224708` | Pending |
| CPU samples (s) | `1.498647, 1.486871, 1.430028` | Pending |
| Highest process lifetime peak RSS | **66,060,288 bytes** | Pending |
| Encoded JSON size | **2,016,610 bytes** | Pending equality check |
| Encoded SHA-256 | `05f7611da103a904a7bf36d5f52b52abf73abefad9c4e00741e462d06d88cbca` | Pending equality check |
| Deliberately invalid dates | **2 rejected**, as required | Pending |

Encoded bytes/hash match CI95. RSS is the macOS benchmark process's lifetime high-water value, not per-sample allocations or iPhone memory.
A Core microbenchmark does not establish faster launch, navigation, photo analysis or display FPS.

## Focused implementation

Repeated day keys currently repeat strict formatter/date round trips during snapshot validation.
The candidate reuses successfully validated days **within one validation call**, capped at **512 strings**; uncached/invalid days keep the original check.
Per-record nutrition, quantity and weight checks remain. No shared mutable formatter, persistent date cache or schema change is added.

The benchmark's expanded breakfast exposes **200 eagerly created row buttons**.
The candidate uses `LazyVStack` for those existing rows, preserving stable IDs, spacing, appearance and editing.
The frozen four-swipe scenario will measure the candidate; improvement remains pending.

Selected-photo thumbnail/display preparation and camera JPEG encoding currently perform synchronous MainActor work.
A new actor owns that processing; UI-owned tasks use cancellation/generations to reject stale results after replacement or dismissal.
The **640-pixel preview**, **0.85 JPEG quality**, original image and existing **1280-pixel** remote preprocessing/contract remain unchanged.
Cancellation cannot interrupt a running codec call; its input can remain retained until completion. No permanent image cache is added.

## Exact seven production/test/project files

| Path | Reason |
| --- | --- |
| [Luqma/Core/Backup.swift](../Luqma/Core/Backup.swift) | Bounded reuse of strict day validation per snapshot check. |
| [Luqma/Services/PhotoPreparationWorker.swift](../Luqma/Services/PhotoPreparationWorker.swift) | New actor for thumbnail/display preparation and JPEG encoding, with local diagnostic intervals. |
| [Luqma/Services/Camera.swift](../Luqma/Services/Camera.swift) | Await encoding; cancel/reject stale delegate results during cancellation/teardown. |
| [Luqma/Views/PhotoMealView.swift](../Luqma/Views/PhotoMealView.swift) | Own preview tasks/generations; publish current results and preserve preparation/error behavior. |
| [Luqma/Views/DiaryView.swift](../Luqma/Views/DiaryView.swift) | Lazy expanded-meal rows with unchanged design and identity. |
| [Luqma.xcodeproj/project.pbxproj](../Luqma.xcodeproj/project.pbxproj) | Include the new worker in the actual app build phase. |
| [Tests/BackupValidationSafetyTests.swift](../Tests/BackupValidationSafetyTests.swift) | Four tests: long-history round trip, invalid dates, invalid entry nutrition/quantity and invalid weights. **Native execution pending.** |

This is the performance candidate inventory, not the full approved-UI integration.
Report/phase/checksum bookkeeping is additional non-runtime work. Measurement harness and fixture remain frozen; no new third-party library is added.

## Apple techniques and platform support

| Technique | Applicability / limits |
| --- | --- |
| Swift actors and `Task.checkCancellation()` | Supported by Swift5.9/iOS17. Identified codec work moves off MainActor; a MainActor-inheriting Task alone would not. [Responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness). |
| `UIImage.preparingForDisplay()` | iOS15+; prepares the existing thumbnail, retaining an image fallback. [Apple API](https://developer.apple.com/documentation/uikit/uiimage/preparingfordisplay()). |
| `OSSignposter` | iOS15+; local PreviewPreparation/CameraJPEG spans record no photos/keys/descriptions. Timing comparison pending. [Apple API](https://developer.apple.com/documentation/os/ossignposter). |
| `LazyVStack` | iOS14+; justified by the actual eager row collection, not a blanket rewrite. [Apple API](https://developer.apple.com/documentation/swiftui/lazyvstack). |
| SwiftUI/CPU profiling | Use installed Instruments26 capabilities. [WWDC25 SwiftUI profiling](https://developer.apple.com/videos/play/wwdc2025/306/) and [WWDC26 responsiveness workflow](https://developer.apple.com/videos/play/wwdc2026/268/). No Instruments27-only capability is claimed on this runner. |

No broad Observation migration, unrelated database refactor, speculative rasterization or decorative animation loop is included.
No `CADisplayLink` or `CADisableMinimumFrameDurationOnPhone` is added; ordinary SwiftUI/UIKit/Charts motion stays system managed.
Apple's opt-in/hints cannot guarantee120Hz. No custom renderer justifies a display link; omission of the flag does not prove high-refresh eligibility.
Review [Apple ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays) and [preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange) on physical hardware before accepting frame-rate or energy claims.

## Functional validation and comparison gates

CI98's device build succeeded; **236 Core tests** and **75 BuildTests** passed, including native font checks.
The separate assessment regression failed at **step8 of11 after508.023s**: an actual input could not be fully revealed between header/footer/keyboard.
The runner stopped before its remaining scenarios. Nine passing performance cases do not establish a passing seven-case functional regression.
The four new Core safety tests and optimized-source compilation/regression remain **Pending**.

The separate UI-only follow-up adds `.accessibilityElement(children: .contain)` to activity/food-preference disclosures, preserving child identifiers; native verification is pending.
Frozen benchmarks **never construct those changed activity/food-preference steps**: assessment measurement stops at initial goal entry, while the plan case opens the existing plan directly.
Their controls, measured UI, fixture and calculations remain unchanged; CI98 remains the legitimate baseline for this isolated accessibility follow-up.
Any subsequent measured-screen/fixture/scenario change requires reassessing comparability and, where needed, a fresh pre-optimization baseline.

Strict comparison preserves fixture/harness hashes, scenario identities/iterations, Release settings, toolchain, runtime/model, architecture, timezone and **same UTC calendar day**.
CI98 records **2026-10-22 UTC**. Do not waive this guard: a later-day candidate needs a fresh matched baseline. Shared-host timing noise remains.
Candidate source SHA, after results, percentage changes and regressions are **Pending**.

Physical camera, photo replacement/cancellation/reopening, allocations/retention, battery/thermals and ProMotion behavior remain unverified.
No remote-AI acceleration, photographic accuracy, leak freedom, battery saving or guaranteed frame rate is claimed.

## Evidence

Local artifacts outside Git: `work/approved29-build98-performance-baseline/` contains the report, raw metrics/summary, native log, Core benchmark and complete xcresult.
Functional failure is retained in `work/approved29-build98-interactions/`; corresponding CI98 artifacts retain compilation/Core/BuildTests/IPA evidence.
No screenshot, Simulator model name or elapsed test duration verifies physical60/120FPS.
