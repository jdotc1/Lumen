import AppKit
import SwiftUI

/// A bar item's natural size and allocated label/pill geometry, at the current text scale.
public struct LumenBarItemReport: Hashable, Sendable {
    public enum Role: Hashable, Sendable { case label, freeText, pill }
    public enum Mode: Hashable, Sendable { case full, iconOnly, overflow }
    public var bar: String
    public var label: String
    public var role: Role
    public var mode: Mode
    public var ideal: CGSize
    public var frame: CGRect
    public var truncation: Text.TruncationMode
    public var fontSize: CGFloat
    public var textScale: CGFloat
    public var pillFrame: CGRect?

    public init(bar: String, label: String, role: Role, mode: Mode = .full,
                ideal: CGSize, frame: CGRect, truncation: Text.TruncationMode = .tail,
                fontSize: CGFloat = 13, textScale: CGFloat = 1, pillFrame: CGRect? = nil) {
        self.bar = bar; self.label = label; self.role = role; self.mode = mode
        self.ideal = ideal; self.frame = frame; self.truncation = truncation
        self.fontSize = fontSize; self.textScale = textScale; self.pillFrame = pillFrame
    }
}

public struct LumenBarItemKey: PreferenceKey {
    public static let defaultValue: [LumenBarItemReport] = []
    public static func reduce(value: inout [LumenBarItemReport], nextValue: () -> [LumenBarItemReport]) {
        value += nextValue()
    }
}

private struct LumenBarItemWatch: ViewModifier {
    @Environment(\.lumenTextScale) private var scale
    @Environment(\.truncationMode) private var truncation
    @Environment(\.lumenReportsLayoutChecks) private var reports
    let label: String
    let bar: String
    let role: LumenBarItemReport.Role
    let mode: LumenBarItemReport.Mode
    let fontSize: CGFloat
    let pillInsets: CGSize?

    func body(content: Content) -> some View {
        content.background {
            if reports {
                GeometryReader { actual in
                    content.fixedSize().hidden().background {
                        GeometryReader { natural in
                            let frame = actual.frame(in: .global)
                            Color.clear.preference(key: LumenBarItemKey.self, value: [
                                .init(bar: bar, label: label, role: role, mode: mode,
                                      ideal: natural.size, frame: frame, truncation: truncation,
                                      fontSize: fontSize, textScale: scale,
                                      pillFrame: pillInsets.map { frame.insetBy(dx: -$0.width, dy: -$0.height) })
                            ])
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

public extension View {
    /// Apply directly after the label's font, before its enclosing frame. `fontSize` is the
    /// unscaled system font size; natural layout inherits the actual font and text scale.
    /// For a pill, supply the padding used by its background in points at the current scale.
    func lumenBarItem(_ label: String, bar: String, role: LumenBarItemReport.Role,
                      mode: LumenBarItemReport.Mode = .full, fontSize: CGFloat = 13,
                      pillInsets: CGSize? = nil) -> some View {
        modifier(LumenBarItemWatch(label: label, bar: bar, role: role, mode: mode,
                                   fontSize: fontSize, pillInsets: pillInsets))
    }
}
