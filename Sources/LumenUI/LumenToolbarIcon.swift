import SwiftUI
import LumenTokens

/// The proportions of a toolbar icon, as fractions of its canvas (the `toolbarButton` frame, 28 pt
/// by default) and of its face. One `side` drives every number, so an icon scales as one vector unit.
public enum LumenToolbarIconGeometry {
    /// The face's side as a share of the canvas: 26 pt on the 28 pt button, leaving one point each
    /// side for the resting shadow. (A Dock icon's face is 824/1024 of its canvas; at toolbar size
    /// that would leave an 11 pt glyph, too small to read, so the toolbar keeps the face large and
    /// the glyph at the app-icon share of the face.)
    public static let faceRatio: CGFloat = 26.0 / 28.0
    /// The face's corner radius as a share of its side, measured from macOS 27 system app icons
    /// (Notes, Calculator; 0.2286 within 0.0025) and drawn with continuous corners.
    public static let cornerRatio: CGFloat = 0.2286
    /// The glyph's longer side as a share of the face: the inner keyline of Apple's app-icon grid
    /// (the 512 pt square around the template's center circle on its 1024 pt canvas).
    public static let glyphRatio: CGFloat = 0.5
    /// How far a pressed icon settles toward the bar, as a share of the face.
    public static let pressRatio: CGFloat = 0.019
}

/// A toolbar button drawn as an app icon (design review 2026-11, note 24; design review 2026-11-13): the
/// glyph centered on a continuous-corner rounded square, in the proportions of a macOS 27 app icon,
/// drawn as one vector unit in a single `Canvas`. The rounded square is the icon itself, not a key or
/// plate behind it: face, edge light, ring, elevation shadow and glyph come from one drawing, sized
/// from one number, so the icon scales cleanly to any size and display.
///
/// - The face is a gentle top-to-bottom gradient (Apple's System Light or System Dark icon ground),
///   with a fine bright rim at the top, a softer one at the foot and a hairline ring for edge
///   definition, as macOS 27 app icons show at small sizes.
/// - A short two-layer shadow lifts it off the bar. Hover raises it a little (a longer, softer
///   shadow); pressed settles it toward the bar (the shadow tightens, the face dims slightly).
/// - It adapts like an app icon: light and dark follow the window, the system's Clear and Tinted icon
///   appearances give a translucent or accent-tinted face, and Increase Contrast firms the ring and
///   rim. A selected icon (a panel that is shown) takes a faint accent face.
/// - Never `glassEffect`, a material, a capsule or the system's shared toolbar platter.
///
/// The glyph is any view: an SF Symbol or a Lumen-drawn glyph. Its longer side is fitted to half the
/// face and centered by its frame; give a glyph with off-center visual mass its own small offset.
public struct LumenToolbarIcon<Glyph: View>: View {
    var isHovered: Bool
    var isPressed: Bool
    var isSelected: Bool
    var side: CGFloat?
    let glyph: Glyph

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenIconAppearance) private var iconAppearance
    @Environment(\.lumenToolbarIconFaceRatio) private var faceRatio
    @Environment(\.lumenToolbarIconFaceColor) private var faceColor

    /// - Parameters:
    ///   - isHovered: raises the icon a little.
    ///   - isPressed: settles the icon toward the bar.
    ///   - isSelected: a faint accent face, for a toggle that is on.
    ///   - side: the icon's canvas; `nil` uses the `toolbarButton` metric (28 pt by default).
    public init(isHovered: Bool = false, isPressed: Bool = false, isSelected: Bool = false, side: CGFloat? = nil,
                @ViewBuilder glyph: () -> Glyph) {
        self.isHovered = isHovered
        self.isPressed = isPressed
        self.isSelected = isSelected
        self.side = side
        self.glyph = glyph()
    }

    public var body: some View {
        let canvas = side ?? metrics.layout.toolbarButton
        // The drawing may reach past the canvas by the hover shadow's length; layout keeps the canvas.
        let bleed = (canvas * 0.25).rounded(.up)
        let look = LumenToolbarIconLook(
            dark: colorScheme == .dark,
            style: Self.style(for: iconAppearance ?? LumenSystemIconAppearance.shared.appearance),
            increasedContrast: contrast == .increased,
            isHovered: isHovered, isPressed: isPressed,
            accent: isSelected || Self.style(for: iconAppearance ?? LumenSystemIconAppearance.shared.appearance) == .tinted ? palette[.accent] : nil,
            selected: isSelected, faceColor: faceColor,
            pixel: 1 / max(displayScale, 1))
        let face = canvas * faceRatio
        Canvas { context, size in
            look.draw(in: &context, size: size, face: face, glyph: context.resolveSymbol(id: 0))
        } symbols: {
            glyph.tag(0)
        }
        .frame(width: canvas + 2 * bleed, height: canvas + 2 * bleed)
        .padding(-bleed)
        .frame(width: canvas, height: canvas)
        .accessibilityRepresentation { glyph }
    }

    static func style(for appearance: LumenIconAppearance) -> LumenToolbarIconLook.Style {
        switch appearance.style {
        case .clear: .clear
        case .tinted: .tinted
        case .regular, .dark: .regular
        }
    }
}

extension EnvironmentValues {
    /// The face's share of the canvas; a decision render may override it.
    @Entry var lumenToolbarIconFaceRatio: CGFloat = LumenToolbarIconGeometry.faceRatio
    /// A colored face in place of the neutral ground; a decision render may set it.
    @Entry var lumenToolbarIconFaceColor: Color? = nil
}

/// The colors, light and shadows of one toolbar icon in one state, and the drawing itself.
struct LumenToolbarIconLook {
    enum Style { case regular, clear, tinted }

    let dark: Bool
    let style: Style
    let increasedContrast: Bool
    let isHovered: Bool
    let isPressed: Bool
    /// The accent mixed into a selected or tinted face.
    let accent: Color?
    let selected: Bool
    let faceColor: Color?
    /// One device pixel, in points: the thinnest line that still draws.
    let pixel: CGFloat

    func draw(in context: inout GraphicsContext, size: CGSize, face side: CGFloat, glyph: GraphicsContext.ResolvedSymbol?) {
        let G = LumenToolbarIconGeometry.self
        let drop = isPressed ? side * G.pressRatio : 0
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2 + drop, width: side, height: side)
        let radius = side * G.cornerRatio
        let face = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let foot = CGPoint(x: rect.midX, y: rect.maxY)

        // Elevation: a tight contact shadow and a longer ambient one, cast by a solid copy of the face.
        for layer in shadows(side) {
            var shadow = context
            shadow.addFilter(.shadow(color: .black.opacity(layer.opacity), radius: layer.radius, x: 0, y: layer.y, options: .shadowOnly))
            shadow.fill(face, with: .color(.black))
        }

        // The face: its ground, then any accent or color, then a faint sheen over the upper half.
        context.fill(face, with: .linearGradient(Gradient(colors: groundStops), startPoint: top, endPoint: foot))
        if let faceColor {
            context.fill(face, with: .linearGradient(Gradient(colors: [faceColor.mix(with: .white, by: 0.10), faceColor.mix(with: .black, by: 0.08)]),
                                                     startPoint: top, endPoint: foot))
        } else if let accent {
            let share = selected ? (dark ? 0.34 : 0.20) : (dark ? 0.26 : 0.14)
            context.fill(face, with: .color(accent.opacity(share)))
        }
        if !increasedContrast {
            let sheen = (dark ? 0.09 : 0.14) * (isPressed ? 0.5 : 1)
            context.fill(face, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(sheen), location: 0),
                                                                      .init(color: .white.opacity(0), location: 1)]),
                                                     startPoint: top, endPoint: CGPoint(x: rect.midX, y: rect.minY + side * 0.5)))
        }

        // The rim: a fine bright line inside the edge, strongest at the top, softer at the foot.
        let rimWidth = max(pixel, side * 0.0098) * (increasedContrast ? 2 : 1)
        let rim = RoundedRectangle(cornerRadius: max(0, radius - rimWidth / 2), style: .continuous)
            .path(in: rect.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
        context.stroke(rim, with: .linearGradient(Gradient(stops: rimStops), startPoint: top, endPoint: foot), lineWidth: rimWidth)

        // The ring: a hairline on the edge that separates the icon from the bar.
        context.stroke(face, with: .color(ringColor), lineWidth: pixel * (increasedContrast ? 2 : 1))

        // The glyph, its longer side fitted to half the face and centered on it.
        if let glyph, glyph.size.width > 0, glyph.size.height > 0 {
            let scale = side * G.glyphRatio / max(glyph.size.width, glyph.size.height)
            var ink = context
            ink.translateBy(x: rect.midX, y: rect.midY)
            ink.scaleBy(x: scale, y: scale)
            ink.draw(glyph, at: .zero, anchor: .center)
        }
    }

    struct Shadow { let opacity: Double; let y: CGFloat; let radius: CGFloat }

    func shadows(_ side: CGFloat) -> [Shadow] {
        let weight = dark ? 1.6 : 1
        if isPressed { return [Shadow(opacity: 0.12 * weight, y: side * 0.010, radius: side * 0.019)] }
        let contact = Shadow(opacity: 0.22 * weight, y: side * 0.019, radius: side * 0.019)
        let ambient = isHovered ? Shadow(opacity: 0.18 * (dark ? 1.55 : 1), y: side * 0.058, radius: side * 0.115)
                                : Shadow(opacity: 0.14 * (dark ? 2 : 1), y: side * 0.038, radius: side * 0.077)
        return [contact, ambient]
    }

    /// Apple's System Light and System Dark icon grounds, lifted on hover and dimmed when pressed.
    var groundStops: [Color] {
        let lift = isHovered && !isPressed ? (dark ? 0.04 : 0.02) : 0
        let dim = isPressed ? (dark ? 0.03 : 0.05) : 0
        switch style {
        case .clear:
            return dark ? [Color(white: 1, opacity: 0.16 + lift - dim), Color(white: 1, opacity: 0.08 + lift - dim)]
                        : [Color(white: 1, opacity: 0.62 + lift - dim), Color(white: 1, opacity: 0.42 + lift - dim)]
        case .regular, .tinted:
            return dark ? [Color(white: 0.33 + lift - dim), Color(white: 0.24 + lift - dim)]
                        : [Color(white: 1 - dim), Color(white: 0.93 + lift - dim)]
        }
    }

    var rimStops: [Gradient.Stop] {
        let boost = increasedContrast ? 1.5 : 1
        if isPressed {
            return [.init(color: .black.opacity(dark ? 0.22 : 0.06), location: 0),
                    .init(color: .white.opacity(0.02), location: 0.5),
                    .init(color: .white.opacity((dark ? 0.10 : 0.30) * boost), location: 1)]
        }
        // Clear icons light their rim evenly, top and foot, as Apple's Clear appearance does.
        let topLight = dark ? 0.45 : 0.60, footLight = style == .clear ? topLight : (dark ? 0.14 : 0.22)
        return [.init(color: .white.opacity(min(1, topLight * boost)), location: 0),
                .init(color: .white.opacity(dark ? 0.03 : 0.04), location: 0.5),
                .init(color: .white.opacity(min(1, footLight * boost)), location: 1)]
    }

    var ringColor: Color {
        let base = dark ? 0.55 : 0.11
        return .black.opacity(increasedContrast ? min(1, base * 2.4) : base)
    }
}

/// The button style for top-bar buttons that draw their own glyph (the panel toggles, New Tab): a
/// borderless hit area whose label is drawn as a toolbar icon (`LumenToolbarIcon`). The caller
/// tracks hover, since a style can't own state across presses.
struct LumenToolbarIconGlyphButtonStyle: ButtonStyle {
    var isHovered: Bool
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, isHovered: isHovered, isSelected: isSelected)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let isHovered: Bool
        let isSelected: Bool
        @Environment(\.lumenMetrics) private var metrics
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            LumenToolbarIcon(isHovered: isEnabled && isHovered, isPressed: isEnabled && configuration.isPressed, isSelected: isSelected) {
                configuration.label
            }
            .lumenDisabledFade(isEnabled)
            .frame(minWidth: metrics.layout.minimumHitTarget, minHeight: metrics.layout.minimumHitTarget)
            .contentShape(.rect)
        }
    }
}
