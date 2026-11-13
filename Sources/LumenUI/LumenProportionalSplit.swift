import AppKit
import SwiftUI

/// The axis a `LumenProportionalSplit` divides along.
public enum LumenProportionalSplitAxis: Sendable {
    /// The first pane sits above the second and the divider is horizontal (the default).
    case vertical
    /// The first pane sits at the leading edge and the divider is vertical.
    case horizontal
}

/// The pure layout math of `LumenProportionalSplit`, kept free of views so it can be tested directly.
enum LumenProportionalSplitMath {
    /// A stale or non-finite stored ratio becomes 0.5; anything else is clamped into 0...1.
    static func sanitized(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 0.5 }
        return min(max(ratio, 0), 1)
    }

    /// The two pane sizes along the axis for `total` points shared by both panes (the divider's
    /// thickness already removed). The ratio is the first pane's share; the minimums are enforced only
    /// when there is room for both, otherwise the space is split in proportion to the minimums so no
    /// size goes negative. A non-positive or non-finite total gives zero sizes.
    static func sizes(ratio: Double, total: CGFloat, minimumFirst: CGFloat, minimumSecond: CGFloat)
        -> (first: CGFloat, second: CGFloat) {
        guard total.isFinite, total > 0 else { return (0, 0) }
        let minFirst = max(minimumFirst.isFinite ? minimumFirst : 0, 0)
        let minSecond = max(minimumSecond.isFinite ? minimumSecond : 0, 0)
        var first = CGFloat(sanitized(ratio)) * total
        if total >= minFirst + minSecond {
            first = min(max(first, minFirst), total - minSecond)
        } else if minFirst + minSecond > 0 {
            first = total * minFirst / (minFirst + minSecond)
        }
        return (first, total - first)
    }

    /// The ratio that gives the first pane `forFirstSize` points, snapped into the range the minimums
    /// allow. Used by the divider drag; a non-positive total gives 0.5.
    static func ratio(forFirstSize size: CGFloat, total: CGFloat, minimumFirst: CGFloat, minimumSecond: CGFloat) -> Double {
        guard total.isFinite, total > 0, size.isFinite else { return 0.5 }
        let minFirst = max(minimumFirst.isFinite ? minimumFirst : 0, 0)
        let minSecond = max(minimumSecond.isFinite ? minimumSecond : 0, 0)
        var first = size
        if total >= minFirst + minSecond { first = min(max(first, minFirst), total - minSecond) }
        return sanitized(Double(first / total))
    }
}

/// Two panes separated by a draggable divider that keep a ratio, not a fixed size, as the window
/// resizes. The first pane takes `ratio` of the space left after the divider, so growing or shrinking
/// the window scales both panes together; dragging the divider (or pressing the arrow keys on it) updates
/// the ratio. Each pane keeps at least its minimum while there is room for both. Window resizes and
/// clamping never rewrite `ratio`, so the user's chosen split comes back when the window grows again.
///
/// The ratio is a `Binding` so the app owns persistence; keep it in `@AppStorage` or `@SceneStorage`
/// to remember it:
///
///     @AppStorage("editorRatio") private var ratio = 0.6
///     LumenProportionalSplit(ratio: $ratio, minimumFirst: 160, minimumSecond: 100) {
///         EditorView()
///     } second: {
///         ConsoleView()
///     }
///
/// The divider is a keyboard-focusable, VoiceOver-adjustable control that reads its position as a
/// percentage.
public struct LumenProportionalSplit<First: View, Second: View>: View {
    /// The default minimum size of each pane, in points.
    public static var defaultMinimum: CGFloat { 120 }

    @Binding private var ratio: Double
    private let axis: LumenProportionalSplitAxis
    private let minimumFirst: CGFloat
    private let minimumSecond: CGFloat
    private let first: First
    private let second: Second
    private var label: String?

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStart: CGFloat?

    /// - Parameters:
    ///   - ratio: The first pane's share of the space left after the divider, 0...1. A value outside
    ///     that range, or not a number, reads as the nearest valid share.
    ///   - axis: `.vertical` stacks the panes top over bottom (the default); `.horizontal` places them
    ///     side by side.
    ///   - minimumFirst: The smallest the first pane gets along the axis while there is room, in points.
    ///   - minimumSecond: The smallest the second pane gets along the axis while there is room, in points.
    ///   - first: The top (or leading) pane.
    ///   - second: The bottom (or trailing) pane.
    public init(ratio: Binding<Double>,
                axis: LumenProportionalSplitAxis = .vertical,
                minimumFirst: CGFloat = LumenProportionalSplit.defaultMinimum,
                minimumSecond: CGFloat = LumenProportionalSplit.defaultMinimum,
                @ViewBuilder first: () -> First,
                @ViewBuilder second: () -> Second) {
        self._ratio = ratio
        self.axis = axis
        self.minimumFirst = minimumFirst
        self.minimumSecond = minimumSecond
        self.first = first()
        self.second = second()
    }

    /// Sets the divider's accessibility label (default "Resize Panes"). Pass an already localized string.
    public func dividerLabel(_ label: String) -> Self {
        var copy = self
        copy.label = label
        return copy
    }

    private static var step: Double { 0.05 }
    private var isVertical: Bool { axis == .vertical }
    private var hairline: CGFloat { metrics.stroke.hairline }

    public var body: some View {
        GeometryReader { proxy in
            let extent = isVertical ? proxy.size.height : proxy.size.width
            let available = max(extent - hairline, 0)
            let sizes = LumenProportionalSplitMath.sizes(
                ratio: ratio, total: available, minimumFirst: minimumFirst, minimumSecond: minimumSecond)
            if isVertical {
                VStack(spacing: 0) {
                    pane(first).frame(height: sizes.first)
                    divider(available: available, firstSize: sizes.first)
                    pane(second).frame(height: sizes.second)
                }
            } else {
                HStack(spacing: 0) {
                    pane(first).frame(width: sizes.first)
                    divider(available: available, firstSize: sizes.first)
                    pane(second).frame(width: sizes.second)
                }
            }
        }
        .frame(minWidth: isVertical ? nil : minimumFirst + minimumSecond + hairline,
               minHeight: isVertical ? minimumFirst + minimumSecond + hairline : nil)
    }

    private func pane<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private func divider(available: CGFloat, firstSize: CGFloat) -> some View {
        Rectangle()
            .fill(palette[.borderDefault])
            .frame(width: isVertical ? nil : hairline, height: isVertical ? hairline : nil)
            .overlay {
                Color.clear
                    .frame(width: isVertical ? nil : 8, height: isVertical ? 8 : nil)
                    .contentShape(.rect)
                    .modifier(LumenResizeCursor(cursor: isVertical ? .resizeUpDown : .resizeLeftRight,
                                                isDragging: dragStart != nil))
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = dragStart ?? firstSize
                            if dragStart == nil { dragStart = start }
                            var delta = isVertical ? value.translation.height : value.translation.width
                            if !isVertical, layoutDirection == .rightToLeft { delta = -delta }
                            ratio = LumenProportionalSplitMath.ratio(
                                forFirstSize: start + delta, total: available,
                                minimumFirst: minimumFirst, minimumSecond: minimumSecond)
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .focusable()
            .lumenFocusRing()
            .onKeyPress(isVertical ? .upArrow : .leftArrow) { nudge(-1, available: available, firstSize: firstSize) }
            .onKeyPress(isVertical ? .downArrow : .rightArrow) { nudge(1, available: available, firstSize: firstSize) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label ?? lumenLocalized(String(localized: "Resize Panes", bundle: .module, comment: "ProportionalSplit control text.")))
            .accessibilityValue(currentRatio(available: available, firstSize: firstSize).formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                _ = nudge(direction == .increment ? 1 : -1, available: available, firstSize: firstSize, visual: false)
            }
    }

    /// The ratio actually shown, after the minimums clamp the stored one.
    private func currentRatio(available: CGFloat, firstSize: CGFloat) -> Double {
        available > 0 ? LumenProportionalSplitMath.sanitized(Double(firstSize / available)) : LumenProportionalSplitMath.sanitized(ratio)
    }

    /// Moves the divider one step. `direction` is +1 to grow the first pane. With `visual`, +1 means
    /// toward the trailing or bottom edge on screen, which under right-to-left reverses for the
    /// horizontal axis.
    private func nudge(_ direction: Double, available: CGFloat, firstSize: CGFloat, visual: Bool = true) -> KeyPress.Result {
        var sign = direction
        if visual, !isVertical, layoutDirection == .rightToLeft { sign = -sign }
        let base = currentRatio(available: available, firstSize: firstSize)
        let target = CGFloat(base + sign * Self.step) * available
        ratio = LumenProportionalSplitMath.ratio(
            forFirstSize: target, total: available, minimumFirst: minimumFirst, minimumSecond: minimumSecond)
        return .handled
    }
}
