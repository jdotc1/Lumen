import SwiftUI

/// How Lumen draws the navigation layer's chrome (PRINCIPLES §11, Docs/GLASS.md).
///
/// `.drawn` is the default: Lumen paints every ground. `.glass` lets the navigation layer (the
/// toolbar's platter, the unified top bar's band, the command palette) use system glass on macOS 27 and later. Tokens, metrics, keyboard behavior, focus and selection are the same in both.
public enum LumenChromeStyle: String, CaseIterable, Identifiable, Sendable {
    /// Lumen paints every ground: the title bar's glow, opaque palettes. The reference look.
    case drawn
    /// The navigation layer uses system glass on macOS 27 and later; drawn under
    /// Reduce Transparency and in offscreen renders.
    case glass

    public var id: Self { self }

    public var label: String {
        switch self {
        case .drawn: "Drawn"
        case .glass: "Glass"
        }
    }

    /// The style a saved raw value names; `.drawn` for anything else.
    public static func resolve(_ raw: String?) -> LumenChromeStyle {
        raw.flatMap(LumenChromeStyle.init(rawValue:)) ?? .drawn
    }

    /// Whether this Mac can draw `.glass`; true on every supported system.
    public static var systemSupportsGlass: Bool {
        true
    }

    /// What a requested style draws as, given the conditions under which glass degrades.
    public static func resolved(_ requested: LumenChromeStyle, reduceTransparency: Bool, rendersOffscreen: Bool) -> LumenChromeStyle {
        guard requested == .glass, !reduceTransparency, !rendersOffscreen else { return .drawn }
        return .glass
    }
}

extension EnvironmentValues {
    /// A subtree's override, set by `.lumenChromeStyle(_:)`.
    @Entry var lumenChromeStyleOverride: LumenChromeStyle? = nil

    /// The chrome style asked for: the nearest `.lumenChromeStyle(_:)`, else the store's
    /// configuration.
    public var lumenChromeStyle: LumenChromeStyle {
        lumenChromeStyleOverride ?? lumenStore.configuration.chromeStyle
    }

    /// The chrome style that draws: `.glass` only when it was asked for, Reduce Transparency is off and the view renders in a window. Navigation-layer surfaces
    /// read this to pick their ground.
    public var lumenResolvedChromeStyle: LumenChromeStyle {
        LumenChromeStyle.resolved(lumenChromeStyle, reduceTransparency: accessibilityReduceTransparency,
                                  rendersOffscreen: lumenRendersOffscreen)
    }
}

public extension View {
    /// Draws this subtree's navigation chrome in `style`, overriding the store's
    /// `LumenStoreConfiguration.chromeStyle`. Apply at a window's root (or a preview's).
    func lumenChromeStyle(_ style: LumenChromeStyle) -> some View {
        environment(\.lumenChromeStyleOverride, style)
    }
}

public extension ToolbarContent {
    /// The system platter rule for native toolbar items (Docs/GLASS.md › What each surface draws):
    /// hidden in `.drawn`, so items sit bare on the title bar's band, and the system's own under
    /// `.glass`. Pass `@Environment(\.lumenResolvedChromeStyle)`.
    @ToolbarContentBuilder
    func lumenToolbarPlatter(_ style: LumenChromeStyle) -> some ToolbarContent {
        sharedBackgroundVisibility(style == .glass ? .automatic : .hidden)
    }
}

public extension ToolbarItem where Content == LumenToolbarIdentity {
    /// A window identity is a title, not a control. Keep its two lines bare in either style.
    /// This overload applies automatically to an item directly containing a Lumen toolbar identity.
    @ToolbarContentBuilder
    func lumenToolbarPlatter(_ style: LumenChromeStyle) -> some ToolbarContent {
        sharedBackgroundVisibility(.hidden)
    }
}
