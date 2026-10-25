import SwiftUI
import LumenTokens

/// The shared macOS tab plate. A tab's identity color belongs in this plate, never in a separate bar.
struct LumenTabChrome: View {
    let strip: String
    let selected: Bool
    let hovered: Bool
    var focused = true
    var accent: LumenToken? = nil
    var radius: CGFloat? = nil

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.lumenPaneIsFocused) private var paneIsFocused
    @Environment(\.lumenTabIsActive) private var forcedActivity
    @Environment(\.colorSchemeContrast) private var contrast

    nonisolated static func shape(radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func radius(metrics: LumenMetrics, base: CGFloat? = nil) -> CGFloat {
        max(base ?? min(metrics.radius.pill, LumenMetrics.standard.layout.controlHeight / 2), metrics.stroke.regular)
            * metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight
    }

    var body: some View {
        let radius = Self.radius(metrics: metrics, base: radius)
        let shape = Self.shape(radius: radius)
        let active = (forcedActivity ?? (activeState != .inactive)) && paneIsFocused && focused
        let document = strip == "document"
        // Document strips have no inset track: give their full-width plates a visible edge.
        let hoverFill = document ? palette[.bgInset] : palette.hoverFill(metrics)
        shape.fill(selected ? palette[.bgElevated] : hoverFill.opacity(hovered ? 1 : 0))
            .overlay {
                if selected, let accent {
                    shape.fill(palette[accent].opacity(metrics.layout.hoverOpacity / 4))
                }
            }
            .overlay {
                if document {
                    // AppKit's cached rounded-rectangle stroke adds vertical end ticks at capsule
                    // radii. Fill the region between the same continuous paths instead of stroking.
                    LumenTabBorder(radius: radius,
                                   width: contrast == .increased ? metrics.stroke.regular : metrics.stroke.hairline)
                        .fill(palette[.borderDefault].opacity(selected || hovered ? 1 : 0),
                              style: FillStyle(eoFill: true))
                } else {
                    shape.strokeBorder(palette[.borderSubtle].opacity(selected ? 1 : 0),
                                       lineWidth: metrics.stroke.hairline)
                }
            }
            .opacity(active ? 1 : metrics.layout.hoverOpacity)
            .lumenTabChromeReport(strip: strip, selectedRadius: radius, hoverRadius: radius)
            .allowsHitTesting(false)
    }
}

private struct LumenTabBorder: Shape {
    let radius: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        let shape = LumenTabChrome.shape(radius: radius)
        return Path { path in
            path.addPath(shape.path(in: rect))
            path.addPath(shape.inset(by: width).path(in: rect))
        }
    }
}

/// Foreground activity is separate from the plate so overlapping fills do not compound the fade.
struct LumenTabActivity: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.lumenPaneIsFocused) private var paneIsFocused
    @Environment(\.lumenTabIsActive) private var forcedActivity
    @Environment(\.lumenMetrics) private var metrics

    func body(content: Content) -> some View {
        content.opacity((forcedActivity ?? (activeState != .inactive)) && paneIsFocused
                        ? 1 : metrics.layout.pressedOpacity)
    }
}

extension EnvironmentValues {
    /// Offscreen fixtures can draw one hover and an edited neighbour without moving the pointer.
    @Entry var lumenTabHoveredID: String? = nil
    /// Rendering seam only; never changes the real window's key or main state.
    @Entry var lumenTabIsActive: Bool? = nil
}
