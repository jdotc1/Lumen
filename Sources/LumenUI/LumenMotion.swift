import SwiftUI

/// Named motion shared by views and imperative actions. Existing metrics remain customizable.
public enum LumenMotion {
    public enum Transition: String, CaseIterable, Sendable {
        case inspector, bottomPanel, sidebar, palette, selection, statusGlyph, toast, notice, disclosure
        case hover, control, reorder, progress, scroll, loading, themeHover, toolLayout

        /// The existing curve family; scroll and loading preserve their pre-vocabulary timings.
        public enum Ramp: Sendable { case fast, standard, regular, scroll, loading }
        public var ramp: Ramp {
            switch self {
            case .inspector, .bottomPanel, .sidebar, .selection, .notice, .disclosure, .themeHover: .standard
            case .toast, .progress: .regular
            case .scroll: .scroll
            case .loading: .loading
            default: .fast
            }
        }
        public func duration(in motion: LumenMetrics.Motion) -> Double {
            switch ramp {
            case .fast: motion.fast
            case .standard, .regular: motion.standard
            case .scroll: 0.5
            case .loading: 1.1
            }
        }
        public func animation(in motion: LumenMetrics.Motion, reduceMotion: Bool) -> Animation? {
            guard motion.isEnabled && !reduceMotion else { return nil }
            switch ramp {
            case .fast: return motion.fastCurve
            case .standard: return motion.standardCurve
            case .regular: return motion.regularCurve
            case .scroll: return .snappy
            case .loading: return .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
            }
        }
        enum Effect: Equatable { case none, opacity, bottom, trailing, leading, toast }
        func effect(in motion: LumenMetrics.Motion, reduceMotion: Bool) -> Effect {
            guard motion.isEnabled && !reduceMotion else { return .none }
            switch self {
            case .bottomPanel: return .bottom
            case .inspector, .notice: return .trailing
            case .sidebar: return .leading
            case .toast: return .toast
            default: return .opacity
            }
        }
        /// Reduce Motion and disabled theme motion always use identity and no animation.
        public func transition(in motion: LumenMetrics.Motion, reduceMotion: Bool) -> AnyTransition {
            switch effect(in: motion, reduceMotion: reduceMotion) {
            case .none: .identity
            case .bottom: .move(edge: .bottom)
            case .trailing: .move(edge: .trailing).combined(with: .opacity)
            case .leading: .move(edge: .leading).combined(with: .opacity)
            case .toast: .opacity.combined(with: .move(edge: .bottom))
            case .opacity: .opacity
            }
        }

    }

    /// For actions such as scrollTo that must run inside an animated transaction.
    public static func perform(_ transition: Transition, metrics: LumenMetrics.Motion,
                               reduceMotion: Bool, _ action: () -> Void) {
        withAnimation(transition.animation(in: metrics, reduceMotion: reduceMotion), action)
    }
}

public extension View {
    func lumenAnimation<Value: Equatable>(_ transition: LumenMotion.Transition, value: Value) -> some View {
        modifier(LumenAnimationModifier(transition: transition, value: value))
    }
    func lumenTransition(_ transition: LumenMotion.Transition) -> some View {
        modifier(LumenTransitionModifier(transition: transition))
    }
    func lumenNumericText<Value: Equatable>(value: Value) -> some View {
        modifier(LumenContentMotionModifier(value: value, symbol: false))
    }
    func lumenStatusSymbol<Value: Equatable>(value: Value) -> some View {
        modifier(LumenContentMotionModifier(value: value, symbol: true))
    }
}

private struct LumenAnimationModifier<Value: Equatable>: ViewModifier {
    let transition: LumenMotion.Transition
    let value: Value
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(transition.animation(in: metrics.motion, reduceMotion: reduceMotion), value: value)
    }
}
private struct LumenTransitionModifier: ViewModifier {
    let transition: LumenMotion.Transition
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.transition(transition.transition(in: metrics.motion, reduceMotion: reduceMotion))
    }
}
private struct LumenContentMotionModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let symbol: Bool
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let motionOff = reduceMotion || !metrics.motion.isEnabled
        content
            .contentTransition(motionOff ? .identity : (symbol ? .symbolEffect(.replace) : .numericText()))
            .lumenAnimation(.statusGlyph, value: value)
    }
}
