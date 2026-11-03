import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Native iOS 17 motion. No timers, display links, delayed actions or shadow state
/// for model values. A new value immediately remains the source of truth.
enum LuqmaMotion {
    enum Kind: String, CaseIterable {
        case press, release, selection, tab, content, progress, success, searchOpen, searchClose, toast
        var duration: Double {
            switch self {
            case .press: return 0.14
            case .release: return 0.16
            case .selection: return 0.20
            case .tab: return 0.28
            case .content: return 0.24
            case .progress: return 0.30
            case .success: return 0.34
            case .searchOpen: return 0.31
            case .searchClose: return 0.25
            case .toast: return 0.24
            }
        }
    }
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .press, .release, .selection: return .snappy(duration: kind.duration, extraBounce: 0)
        case .searchOpen, .searchClose: return .spring(duration: kind.duration, bounce: 0.08)
        case .tab, .content, .progress, .success, .toast: return .smooth(duration: kind.duration, extraBounce: 0)
        }
    }
    static func pressScale(isPressed: Bool, reduceMotion: Bool, enabled: Bool = true, scale:CGFloat=0.98) -> CGFloat {
        isPressed && enabled && !reduceMotion ? scale : 1
    }
    static func permitsContinuousMotion(active: Bool, reduceMotion: Bool, sceneIsActive: Bool) -> Bool {
        active && !reduceMotion && sceneIsActive
    }
    static func shouldPlayFeedback<Value: Equatable>(old: Value, new: Value, enabled: Bool,
                                                     sceneIsActive: Bool, condition: (Value, Value) -> Bool) -> Bool {
        enabled && old != new && sceneIsActive && condition(old, new)
    }
    enum Feedback: Equatable {
        case light, selection, toggle, adjustment, success, warning, error, achievement
    }
}

/// One native feedback pathway. iOS decides whether a physical pulse is available.
@MainActor enum LuqmaHapticManager {
    nonisolated static let preferenceKey = "luqma.interactionHaptics"
    #if canImport(UIKit)
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static var lastTap: TimeInterval = -.infinity
    #endif
    static func play(_ feedback: LuqmaMotion.Feedback) {
        #if canImport(UIKit)
        guard UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true,
              UIApplication.shared.applicationState == .active else { return }
        switch feedback {
        case .light, .selection, .toggle, .adjustment:
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastTap >= 0.075 else { return }
            lastTap = now
            if feedback == .light { impact.impactOccurred(intensity: 0.5) }
            else { selection.selectionChanged() }
        case .success, .achievement: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .error: notification.notificationOccurred(.error)
        }
        #endif
    }
}

/// Consumed only by the active request's committed outcome. A retry replaces
/// the token, so an old or repeated callback cannot emit feedback.
struct LuqmaOperationFeedback {
    private var active: UUID?
    mutating func begin(_ id: UUID) { active = id }
    mutating func cancel() { active = nil }
    mutating func finish(_ id: UUID) -> Bool {
        guard active == id else { return false }
        active = nil
        return true
    }
}

struct LuqmaActionFeedbackStyle<Appearance: ButtonStyle>: PrimitiveButtonStyle {
    let appearance: Appearance
    var feedback: LuqmaMotion.Feedback? = .light
    @Environment(\.isEnabled) private var enabled
    init(appearance:Appearance,feedback:LuqmaMotion.Feedback? = .light) {
        self.appearance=appearance
        self.feedback=feedback
    }
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            guard enabled else { return }
            if let feedback { LuqmaHapticManager.play(feedback) }
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(appearance)
    }
}

/// Replaces only existing plain styles; does not add padding, chrome or color.
struct LuqmaPressStyle: PrimitiveButtonStyle {
    var feedback: LuqmaMotion.Feedback? = .light
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        LuqmaActionFeedbackStyle(appearance: LuqmaPressAppearance(scale: scale), feedback: feedback)
            .makeBody(configuration: configuration)
    }
}

private struct LuqmaPressAppearance: ButtonStyle {
    let scale: CGFloat
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && enabled ? 0.84 : 1)
            .modifier(LuqmaPressFeedback(pressed: configuration.isPressed, scale: scale))
    }
}

private struct LuqmaPressFeedback: ViewModifier {
    let pressed: Bool
    var scale: CGFloat = 0.98
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.animation(LuqmaMotion.animation(pressed ? .press : .release, reduceMotion: reduceMotion)) { view in
            view.scaleEffect(LuqmaMotion.pressScale(isPressed:pressed,reduceMotion:reduceMotion,enabled:enabled,scale:scale))
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
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.onChange(of: trigger) { old, new in
            if LuqmaMotion.shouldPlayFeedback(old: old, new: new, enabled: true,
                                              sceneIsActive: phase == .active, condition: condition) {
                LuqmaHapticManager.play(kind)
            }
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
            content.phaseAnimator([CGFloat(-1), 1]) { view, position in
                view.offset(y: position * max(0, travel.isFinite ? travel : 0))
            } animation: { _ in .easeInOut(duration: 1.15) }
        } else { content }
    }
}

private struct LuqmaShimmer: ViewModifier {
    let active:Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content:Content)->some View {
        if LuqmaMotion.permitsContinuousMotion(active:active,reduceMotion:reduceMotion,sceneIsActive:phase == .active) {
            content.overlay {
                GeometryReader { proxy in
                    let band=max(1,proxy.size.width*0.45)
                    LinearGradient(colors:[.clear,.white.opacity(0.055),.clear],startPoint:.leading,endPoint:.trailing)
                        .frame(width:band)
                        .phaseAnimator([false,true]) { view, end in
                            view.offset(x:end ? proxy.size.width : -band)
                        } animation:{_ in .linear(duration:1.25)}
                }.clipped().mask(content).allowsHitTesting(false).accessibilityHidden(true)
            }
        } else { content }
    }
}

private struct LuqmaTabIconMotion:ViewModifier {
    let selected:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse=0
    func body(content:Content)->some View {
        Group {
            if reduceMotion { content }
            else {
                content.phaseAnimator([CGFloat(1),0.96,1],trigger:pulse){view,scale in
                    view.scaleEffect(scale)
                } animation:{_ in .easeOut(duration:0.08)}
            }
        }.onChange(of:selected){_,value in if value && !reduceMotion { pulse &+= 1 }}
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
    func luqmaShimmer(active:Bool=true)->some View { modifier(LuqmaShimmer(active:active)) }
    func luqmaTabIconMotion(selected:Bool)->some View { modifier(LuqmaTabIconMotion(selected:selected)) }
}

