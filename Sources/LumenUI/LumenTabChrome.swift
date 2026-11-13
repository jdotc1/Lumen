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
    /// The plate sits in a recessed track (a segmented control or pill switcher). `bg.elevated` on
    /// `bg.inset` all but vanishes in dark (#23262F on #21242C in Standard), so the selected plate
    /// takes a control edge and, in dark, a quiet accent tint that lifts it off the track (in light
    /// the white plate already reads, and a tint would pull it toward the gray) (design review 2026-11 #6).
    var onWell = false

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.lumenPaneIsFocused) private var paneIsFocused
    @Environment(\.lumenTabIsActive) private var forcedActivity
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func shape(radius: CGFloat) -> LumenTabChromeShape {
        LumenTabChromeShape(cornerRadius: radius)
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
                if selected, let tint = accent ?? (onWell && colorScheme == .dark ? .accent : nil) {
                    shape.fill(palette[tint].opacity(metrics.layout.hoverOpacity / 4))
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
                    shape.strokeBorder(palette[onWell ? .borderDefault : .borderSubtle].opacity(selected ? 1 : 0),
                                       lineWidth: onWell && contrast == .increased ? metrics.stroke.regular : metrics.stroke.hairline)
                }
            }
            .opacity(active ? 1 : metrics.layout.hoverOpacity)
            .lumenTabChromeReport(strip: strip, selectedRadius: radius, hoverRadius: radius)
            .allowsHitTesting(false)
    }
}

/// The recessed track a segmented control or pill switcher draws its plates in: a field's well
/// with a control's edge, so it reads in light themes too.
struct LumenTabWell: View {
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        let shape = LumenTabChrome.shape(radius: LumenTabChrome.radius(metrics: metrics))
        shape.fill(palette[.bgInset])
            .overlay { shape.strokeBorder(palette[.borderDefault], lineWidth: metrics.stroke.hairline) }
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

/// A continuous rounded rectangle that draws true semicircular ends when its radius reaches half
/// its shorter side. A continuous corner at full radius flattens into a squircle (a vertical stub
/// at each end of a pill track, measured on macOS 27), and a capsule's round end is the point.
struct LumenTabChromeShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, cornerRadius - insetAmount)
        let fullRound = radius >= min(inset.width, inset.height) / 2 - 0.5
        return RoundedRectangle(cornerRadius: radius, style: fullRound ? .circular : .continuous).path(in: inset)
    }

    func inset(by amount: CGFloat) -> LumenTabChromeShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
