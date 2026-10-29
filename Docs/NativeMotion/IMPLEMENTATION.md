# LUQMA native motion review

Baseline: `9f567b449579d78c22833b06d9d0836bb37b833d`, version 2.9.
That exact source compiled for iPhone Release and Simulator Debug in
[run 40749563514](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40749563514).
Core: 264 passed; BuildTests: 169 passed. The baseline native UI run had five
failures (keyboard accessory-toolbar occlusion and the test's scroll gestures).
Both real notification choices passed on independent Simulators. This is not a
claim that the baseline passed all functional tests.

## Implementation

- Existing native SwiftUI app, iOS 17 minimum; existing navigation stacks,
  sheet/full-screen presentations and system keyboard transitions retained.
- `LuqmaMotion.swift`: five finite motion presets, scoped value updates,
  read-only numeric transitions, press transforms, conditional native sensory
  feedback, opacity transitions, an operation-only loading-glyph pulse and a
  scan sweep on the existing beam only while processing a real photo.
- The existing 96pt launch mark fades over the actual first frame in 200ms.
  The overlay accepts no input and adds no loading wait or network dependency.
- Home retains its approved **bar**, photographs, colors and layout. A ring was
  not substituted. Existing ring components elsewhere animate their own values.
- Search requests, debounce and cancellation are unchanged. No animation delay
  is introduced before search, camera capture, persistence or dismissal.
- Camera and barcode capture remain the existing real native implementations.
  The barcode guide is not moved independently from its actual scan region.
- No shared-image hero transition is added where a card opens search rather
  than a matching image destination. No new navigation route is invented.
- Reduce Motion disables custom spatial/numeric animation and continuous
  loading motion. Background/inactive scenes stop the custom loading animator.
- Feedback is triggered by real state changes; success conditions exclude
  resets, empty Health results and mere completion of Health authorization.
  New diary entries trigger success at the stable root after the real count
  increases. Food/photo/import errors use their stable operation parents.
- Changa Bold, all resources, theme, Core models, services, entitlements,
  bundle identifier and production signing settings are preserved.

## Validation and limits

`Scripts/motion_review.py freeze` checks scope and the exact original drawing
calls (font, frame, padding, colors, gradients, stacks and corners). This is a
source check and does not substitute for screenshot comparison.

The dedicated workflow builds both SDKs, runs the Core and BuildTests suites,
real diary/quantity/assessment UI tests, two new normal/Reduce Motion navigation
scenarios, independent native notification choices, actual screenshots and a
Simulator screen recording. The Reduce Motion scenario uses the actual
Simulator Settings UI to enable the system preference, then verifies the
rendered SwiftUI environment. No read-only Apple key or private preference is
overridden. This does not claim physical-iPhone or haptic-motor verification.

The performance jobs use the existing Release/-O fixture and XCTest metrics on
both revisions. Their raw reports must be inspected before reporting numbers.
Simulator wall time, CPU, memory and hitches must not be presented as physical
60/120Hz, battery, thermal, remote AI latency or camera performance.

Actual validation of production source `ef485cb` passed iPhone Release and
Simulator Debug builds, 264 Core tests, 170 BuildTests, 51 actual Arabic
Reduce Motion screen captures, four English captures and two compact captures.
All 51 same-state Arabic pairs were visually reviewed against `9f567b4`; no
new visible static regression was found in these captured states. Existing
assessment caption/large-text viewport limitations remain documented.

The first functional run passed seven card and six legacy cases, failed one
quantity automation replacement, and failed two new motion cases at an
incorrect Back locator. Those original failures remain recorded. In the
SHA-verified [follow-up 40820331550](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40820331550),
**both complete motion cases passed**, including the actual system Reduce
Motion setting, Health access guide and Back to Settings. The native XCTest
suite ran two cases with zero failures. Its actual, nonsynthetic Simulator
framebuffer movie is 67,728,195 bytes; it does not measure FPS.

The same follow-up's overall report **failed**: its seven-case legacy command
exceeded a 1,500-second budget that included cold app/test compilation. Two
legacy cases completed successfully before interruption during the quantity
case; this was not a new numeric assertion failure or a completed quantity
pass. The newer test/CI-only revision
`2fbcc4854694e4bcdbcdaeae792089978d0ffa7f` retains the identical `ef485cb`
production tree. [Focused run 40823655253](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40823655253)
passed the full grams/serving case plus both motion cases (3/3),
with 2,700 seconds available for the legacy command/cold compilation.
The other six legacy cases already passed against this same production
source. The evidence contains 18 unique passed UI cases across runs, not one
18-case suite: seven card, seven legacy, two motion, independent notification
denial and the system-Reduce-Motion setup case.

The earlier two nine-scenario performance runs completed on different CI Macs
with mixed outcomes; they do not establish a general speedup. The independent
[sequential same-Mac job 123271101508](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/40820331550/job/123271101508)
completed both nine-case variants, with identical resolved packages. Its
results remain mixed: responsive launch median 4.9421 to 3.7045 seconds,
four-tab clock 10.6432 to 9.4892 seconds, but expanded-scroll clock 12.7598 to
16.1849 seconds with high after variability (standard deviation 5.5335 seconds).
Scroll CPU and peak-memory medians were lower, but no FPS/hitch count was
exported. None of these short Simulator samples establishes general smoother
operation or a causal speedup. See `VALIDATION-AND-COVERAGE.md` for actual evidence,
recording and gallery paths, all 24 View-file coverage and remaining limits.
A render, source audit, still image or a passed UI scenario is not a measured
frame-pacing pass.

Physical camera/Health data/haptics/ProMotion testing requires appropriate
hardware and authorized signing. No IPA is exported; no merge is performed.
The review remains on a separate branch pending the user's approval.

See the adjacent screen inventories for every discovered View and its states.
Source-audited coverage is distinguished from runtime-tested coverage.
