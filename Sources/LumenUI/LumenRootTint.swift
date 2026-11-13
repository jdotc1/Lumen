import AppKit
import LumenTokens
import SwiftUI

/// Light, dark or follow-the-system for a root that has no theme store (`lumenRoot(tint:appearance:)`).
public enum LumenRootAppearance: Sendable, Hashable {
    /// Follow System Settings (and any appearance set above the root).
    case system
    /// Always light.
    case light
    /// Always dark.
    case dark
}

extension EnvironmentValues {
    /// The root tint set by `lumenRoot(tint:appearance:windowChrome:)`; `nil` means the theme's own
    /// accent (or the system accent when the store follows it). `lumenPaletteRoot` and `lumenSurface`
    /// read it, so an app that uses a theme store can also set it with `.environment(\.lumenRootTint, ...)`
    /// above its root.
    @Entry public var lumenRootTint: LumenColor? = nil
}

extension LumenThemeStore {
    /// `resolvedPalette()` with accent-family roles (accent, filled and subtle accent, selection,
    /// text on accent and the rest) derived from `tint` by the same rules as the macOS system accent,
    /// so contrast holds for any tint in Light, Dark and Increase Contrast. `nil` returns
    /// `resolvedPalette()` unchanged. An explicit tint wins over a store that follows the system accent.
    public func resolvedPalette(tint: LumenColor?) -> LumenResolvedPalette {
        resolvedPalette(drawnOn: nil, tint: tint)
    }
}

private struct LumenRootModifier: ViewModifier {
    let tint: LumenColor?
    let appearance: LumenRootAppearance
    let windowChrome: Bool

    func body(content: Content) -> some View {
        let scheme: ColorScheme? = switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
        // The environment values sit outside the palette root, which reads the scheme it inherits.
        content
            .lumenPaletteRoot(windowChrome: windowChrome)
            .environment(\.lumenRootTint, tint)
            .modifier(LumenRootSchemeModifier(scheme: scheme))
    }
}

private struct LumenRootSchemeModifier: ViewModifier {
    let scheme: ColorScheme?
    @Environment(\.colorScheme) private var inherited

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, scheme ?? inherited)
            .preferredColorScheme(scheme)
    }
}

extension View {
    /// One modifier at the root of an app that does not want a `LumenThemeStore`: sets the Lumen
    /// accent (tint) and appearance (light, dark or system) and installs the palette root, so every
    /// Lumen component picks both up. Uses the core-only fallback store; it installs no persistence,
    /// native title-bar styling or density syncing. Apps with a store keep `lumenPaletteRoot()`.
    ///
    /// Ordering: apply `lumenMetrics(_:)` before (inside) it, never after. A theme that forces its
    /// own scheme (Midnight, Ultraviolet) still wins over `appearance`, since light text on a
    /// dark-only theme would be illegible.
    ///
    /// - Parameters:
    ///   - tint: the accent to derive every accent role from; `nil` keeps the theme's accent.
    ///   - appearance: light, dark, or `.system` (the default) to follow the system.
    ///   - windowChrome: whether to draw the title bar glow; `false` by default for the minimal path.
    public func lumenRoot(tint: LumenColor? = nil,
                          appearance: LumenRootAppearance = .system,
                          windowChrome: Bool = false) -> some View {
        modifier(LumenRootModifier(tint: tint, appearance: appearance, windowChrome: windowChrome))
    }
}
