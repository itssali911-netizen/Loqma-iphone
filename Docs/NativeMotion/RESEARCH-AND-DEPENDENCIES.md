# Sources and dependency decision

No animation package, JavaScript, WebView, new artwork or third-party runtime
dependency was added. SwiftUI and its native sensory feedback cover the actual
existing controls. Existing project dependencies are unchanged. No code/assets
were copied from the optional galleries, so no new third-party asset license
or attribution obligation is introduced by this motion pass.

Official documentation checked against the project's iOS 17 deployment target:

- [SwiftUI animations](https://developer.apple.com/documentation/swiftui/animations):
  value-specific updates instead of an animation attached to the entire store.
- [Explore SwiftUI animation, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10156/):
  built-in transforms and narrowly scoped transactions avoid custom per-frame
  layout work and accidental descendant animation.
- [Motion HIG](https://developer.apple.com/design/human-interface-guidelines/motion):
  brief, interruptible feedback; retain useful native motion and accessibility.
- [Scoped animation](https://developer.apple.com/documentation/swiftui/view/animation(_:body:)):
  isolate the button's press transform from its child layout and model updates.
- [Numeric content transition](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:)):
  apply only to read-only numbers, never the user's editable input buffer.
- [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion):
  custom motion is disabled in the actual rendered SwiftUI environment.
- [Sensory feedback](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)):
  native, conditional, foreground-only feedback. No vibration per slider sample.
- [Phase animator](https://developer.apple.com/documentation/swiftui/view/phaseanimator(_:content:animation:)):
  only the existing loading glyph cycles while an actual operation is visible;
  cancellation, disappearance, Reduce Motion and scene state stop it.

The native APIs above are compatible with iOS 17; current Apple symbol
availability was checked. No custom display link or forced refresh-rate loop
was introduced. Existing ProMotion configuration is not treated as an FPS test.

Web reference review (ideas only; no runtime code/assets reused):
[Animate UI](https://animate-ui.com/docs/primitives),
[Magic UI](https://magicui.design/docs/components),
[Lucide Animated](https://lucide-animated.com/) and
[React Bits](https://reactbits.dev/) illustrate fades, number changes, collapsible
content and press feedback. Their web components do not belong in this native
app. Motion Primitives returned HTTP 403 during inspection; its effects were
not claimed as inspected or adopted.

Pow, navigation-transition packages, Shimmer, Lottie, PopupView, AnimatedTabBar,
Hero, ActivityIndicatorView and the additional galleries are **not installed**.
The app's existing geometry and system navigation are served by the native
implementation; adding those packages was not technically justified. No paid
animation or licensed external animation file was used.
