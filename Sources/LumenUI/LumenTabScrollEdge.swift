import SwiftUI

/// Only edge visibility is state: scrolling within the middle does not invalidate the strip.
struct LumenTabHiddenEdges: Equatable {
    var leading = false
    var trailing = false

    init(contentMinX: CGFloat = 0, contentMaxX: CGFloat = 0, viewport: CGFloat = 0) {
        leading = contentMinX < -0.01
        trailing = contentMaxX > viewport + 0.01
    }
}

extension EnvironmentValues {
    /// Negative-control seam for the hidden-truncation audit. Shipping views always apply the mask.
    @Entry var lumenTabScrollEdgeFadeEnabled = true
}

/// One edge of the viewport alpha mask. The fixed menu is its sibling.
/// 24 pt is the requested soft transition; the saved native reference has no measurable overflow.
struct LumenTabScrollEdge: View {
    nonisolated static let width: CGFloat = 24
    let leading: Bool
    @Environment(\.lumenTabScrollEdgeFadeEnabled) private var enabled
    @Environment(\.lumenReportsLayoutChecks) private var reports

    var body: some View {
        let colors: [Color] = enabled ? [.clear, .black] : [.black, .black]
        LinearGradient(colors: colors,
                       startPoint: leading ? .leading : .trailing,
                       endPoint: leading ? .trailing : .leading)
            .background {
                GeometryReader { geometry in
                    // A scroll route or menu alone is not a visual truncation cue. Feed the same
                    // hidden-content rule into truncation, overflow and window layout audits.
                    Color.clear.preference(key: LumenColumnOverflowKey.self, value:
                        reports && !enabled && geometry.size.width > 0.01
                            ? ["Document tab content is hard-clipped at the \(leading ? "leading" : "trailing") scroll edge without a fade"] : [])
                }
            }
            .allowsHitTesting(false)
    }
}

struct LumenTabScrollEdgeMask: ViewModifier {
    @State private var hidden = LumenTabHiddenEdges()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: LumenTabHiddenEdges.self) { geometry in
                LumenTabHiddenEdges(contentMinX: -geometry.visibleRect.minX,
                                    contentMaxX: geometry.contentSize.width - geometry.visibleRect.minX,
                                    viewport: geometry.visibleRect.width)
            } action: { _, edges in hidden = edges }
            .mask { LumenTabViewportMask(hidden: hidden) }
    }
}

/// Use a normal alpha mask around the live scroll host, preserving its native-backed content.
/// The cached layout draws an equivalent mask from its synchronous placement measurement.
struct LumenTabViewportMask: View {
    let hidden: LumenTabHiddenEdges

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                LumenTabScrollEdge(leading: true)
                    .frame(width: hidden.leading ? min(LumenTabScrollEdge.width, geometry.size.width / 2) : 0)
                Rectangle().fill(.black)
                LumenTabScrollEdge(leading: false)
                    .frame(width: hidden.trailing ? min(LumenTabScrollEdge.width, geometry.size.width / 2) : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Layout records before drawing; Canvas consumes the measurement without a state round trip, so
/// single-pass ImageRenderer and AppKit cacheDisplay use the same actual tab extents. Only this
/// alpha mask is rasterized, preserving native-backed dots, symbols and text in the tab content.
struct LumenTabRecordedMask: View {
    let placement: LumenDocumentTabPlacement
    @Environment(\.lumenTabScrollEdgeFadeEnabled) private var enabled

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            guard enabled, let measurement = placement.measurement else { return }
            let hidden = LumenTabHiddenEdges(contentMinX: measurement.frames.first?.minX ?? 0,
                                            contentMaxX: measurement.frames.last?.maxX ?? 0,
                                            viewport: measurement.width)
            let width = min(LumenTabScrollEdge.width, size.width / 2)
            context.blendMode = .destinationOut
            for leading in [true, false] where leading ? hidden.leading : hidden.trailing {
                let x = leading ? 0 : size.width - width
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [.black, .clear]),
                    startPoint: CGPoint(x: leading ? rect.minX : rect.maxX, y: 0),
                    endPoint: CGPoint(x: leading ? rect.maxX : rect.minX, y: 0)))
            }
        }
    }
}
