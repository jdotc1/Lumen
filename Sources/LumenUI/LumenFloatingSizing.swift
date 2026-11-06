import SwiftUI

/// Local surface defaults use the existing text-aware control height. This does not
/// change shared metrics or the sizing of components outside floating surfaces.
extension LumenMetrics {
    var floatingTextGrowth: CGFloat { max(1, layout.controlHeight / LumenMetrics.standard.layout.controlHeight) }
}

struct LumenFloatingSize: Equatable {
    var width: CGFloat?
    var maximumHeight: CGFloat?

    init(width: CGFloat?, maximumHeight: CGFloat?) {
        self.width = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.maximumHeight = maximumHeight.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

extension EnvironmentValues {
    @Entry var lumenCommandPaletteSize = LumenFloatingSize(width: nil, maximumHeight: nil)
    @Entry var lumenInputPaletteSize = LumenFloatingSize(width: nil, maximumHeight: nil)
    @Entry var lumenCommandMenuMaximumHeight: CGFloat? = nil
}

public extension View {
    /// Sets the command palette's preferred maximum width and result viewport height, in points.
    /// Apply after `lumenCommandPalette` or directly to `LumenCommandPalette`. A nil value uses
    /// the text-scaled default (580 pt wide, 380 pt results at standard type). Smaller host
    /// proposals take precedence; explicit values are not multiplied by text scale.
    func lumenCommandPaletteSize(width: CGFloat?, maximumListHeight: CGFloat?) -> some View {
        environment(\.lumenCommandPaletteSize, LumenFloatingSize(width: width, maximumHeight: maximumListHeight))
    }

    /// Sets the input palette's preferred maximum width and scrollable content height.
    /// Apply after `lumenInputPalette` or directly to `LumenInputPalette`. Nil uses the
    /// text-scaled default (520 × 380 pt); smaller host proposals take precedence.
    func lumenInputPaletteSize(width: CGFloat?, maximumContentHeight: CGFloat?) -> some View {
        environment(\.lumenInputPaletteSize, LumenFloatingSize(width: width, maximumHeight: maximumContentHeight))
    }

    /// Bounds a command menu's entries; overflow scrolls. Nil restores the text-scaled 480 pt default.
    func lumenCommandMenuMaximumHeight(_ height: CGFloat?) -> some View {
        environment(\.lumenCommandMenuMaximumHeight, LumenFloatingSize(width: nil, maximumHeight: height).maximumHeight)
    }
}

/// Natural height when content fits, a scroll viewport when the host or policy is shorter.
/// Measures only the proposal and child ideals; no measured size is fed back into state.
struct LumenFloatingViewport<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        LumenCappedHeight(maximum: maximumHeight) {
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                ScrollView { content }
            }
        }
    }
}

/// Keeps the familiar top offset in roomy hosts, while yielding it in short windows.
struct LumenFloatingPlacement: ViewModifier {
    @Environment(\.lumenMetrics) private var metrics

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .padding(.horizontal, metrics.spacing.s8)
                .padding(.top, min(64 * metrics.floatingTextGrowth, max(0, proxy.size.height * 0.15)))
                .padding(.bottom, metrics.spacing.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
