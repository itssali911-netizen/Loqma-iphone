import SwiftUI

/// Native iOS 17 motion. No timers, display links, delayed actions or shadow state
/// for model values. A new value immediately remains the source of truth.
enum LuqmaMotion {
    enum Kind: String, CaseIterable {
        case press, selection, content, progress, success
        var duration: Double {
            switch self {
            case .press: return 0.14
            case .selection: return 0.20
            case .content: return 0.24
            case .progress: return 0.30
            case .success: return 0.34
            }
        }
    }
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .press, .selection: return .snappy(duration: kind.duration, extraBounce: 0)
        case .content, .progress, .success: return .smooth(duration: kind.duration, extraBounce: 0)
        }
    }
    static func pressScale(isPressed: Bool, reduceMotion: Bool, enabled: Bool = true) -> CGFloat {
        isPressed && enabled && !reduceMotion ? 0.98 : 1
    }
    static func permitsContinuousMotion(active: Bool, reduceMotion: Bool, sceneIsActive: Bool) -> Bool {
        active && !reduceMotion && sceneIsActive
    }
    static func shouldPlayFeedback<Value: Equatable>(old: Value, new: Value, reduceMotion: Bool,
                                                     sceneIsActive: Bool, condition: (Value, Value) -> Bool) -> Bool {
        old != new && condition(old, new) && !reduceMotion && sceneIsActive
    }
    enum Feedback {
        case selection, success, error, light
        var native: SensoryFeedback {
            switch self {
            case .selection: return .selection
            case .success: return .success
            case .error: return .error
            case .light: return .impact(weight: .light, intensity: 0.5)
            }
        }
    }
}

/// Replaces only existing plain styles; does not add padding, chrome or color.
struct LuqmaPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && enabled ? 0.84 : 1)
            .luqmaPressFeedback(configuration.isPressed)
    }
}

private struct LuqmaPressFeedback: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.animation(LuqmaMotion.animation(.press, reduceMotion: reduceMotion)) { view in
            view.scaleEffect(LuqmaMotion.pressScale(isPressed: pressed, reduceMotion: reduceMotion, enabled: enabled))
        }
    }
}

private struct LuqmaValueMotion<Value: Equatable>: ViewModifier {
    let kind: LuqmaMotion.Kind
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(LuqmaMotion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}

private struct LuqmaNumericMotion: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var finiteValue: Double { value.isFinite ? value : 0 }
    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion || !value.isFinite ? .identity : .numericText(value: finiteValue))
            .animation(LuqmaMotion.animation(.progress, reduceMotion: reduceMotion), value: finiteValue)
    }
}

private struct LuqmaFeedback<Value: Equatable>: ViewModifier {
    let kind: LuqmaMotion.Feedback
    let trigger: Value
    let condition: (Value, Value) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.sensoryFeedback(kind.native, trigger: trigger) { old, new in
            LuqmaMotion.shouldPlayFeedback(old: old, new: new, reduceMotion: reduceMotion,
                                         sceneIsActive: phase == .active, condition: condition)
        }
    }
}

private struct LuqmaMotionTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View { content.transition(reduceMotion ? .identity : .opacity) }
}

/// Used only on a visible, existing glyph for an actual operation. Removing it,
/// backgrounding, cancellation or Reduce Motion immediately stops the animator.
private struct LuqmaLoadingPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        if LuqmaMotion.permitsContinuousMotion(active: active, reduceMotion: reduceMotion, sceneIsActive: phase == .active) {
            content.phaseAnimator([true, false]) { view, bright in
                view.opacity(bright ? 1 : 0.60)
            } animation: { _ in .easeInOut(duration: 0.85) }
        } else { content }
    }
}

/// Moves the existing scan beam only while processing a real meal photo. The
/// idle, cancelled and reduced-motion branches render the exact original beam.
private struct LuqmaScanSweep: ViewModifier {
    let active: Bool
    let travel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        if LuqmaMotion.permitsContinuousMotion(active: active, reduceMotion: reduceMotion, sceneIsActive: phase == .active) {
            content.phaseAnimator([CGFloat(0), -1, 1, 0]) { view, position in
                view.offset(y: position * max(0, travel.isFinite ? travel : 0))
            } animation: { _ in .easeInOut(duration: 0.65) }
        } else { content }
    }
}

extension View {
    func luqmaPressFeedback(_ pressed: Bool) -> some View { modifier(LuqmaPressFeedback(pressed: pressed)) }
    func luqmaMotion<Value: Equatable>(_ kind: LuqmaMotion.Kind = .content, value: Value) -> some View {
        modifier(LuqmaValueMotion(kind: kind, value: value))
    }
    /// Apply to read-only numeric Text, never an editable field or its binding.
    func luqmaNumericMotion(value: Double) -> some View { modifier(LuqmaNumericMotion(value: value)) }
    func luqmaFeedback<Value: Equatable>(_ kind: LuqmaMotion.Feedback, trigger: Value,
                                        condition: @escaping (Value, Value) -> Bool = { $0 != $1 }) -> some View {
        modifier(LuqmaFeedback(kind: kind, trigger: trigger, condition: condition))
    }
    func luqmaMotionTransition() -> some View { modifier(LuqmaMotionTransition()) }
    func luqmaLoadingPulse(active: Bool = true) -> some View { modifier(LuqmaLoadingPulse(active: active)) }
    func luqmaScanSweep(active: Bool, travel: CGFloat) -> some View { modifier(LuqmaScanSweep(active: active, travel: travel)) }
}

