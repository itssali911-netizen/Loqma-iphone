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
  feedback, opacity transitions and an operation-only loading-glyph pulse.
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

At this source commit the new native build/runtime results are **pending**.
Physical camera/Health data/haptics/ProMotion testing requires appropriate
hardware and authorized signing. No IPA is exported; no merge is performed.
The review remains on a separate branch pending the user's approval.

See the adjacent screen inventories for every discovered View and its states.
Source-audited coverage is distinguished from runtime-tested coverage.
