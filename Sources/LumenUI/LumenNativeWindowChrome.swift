import AppKit
import SwiftUI

/// Deliberate escape hatch for windows whose application requires a two-row toolbar.
/// Apply outside the palette root. Full-height content remains enabled.
public extension View {
    func lumenPreservesExpandedToolbar(_ preserves: Bool) -> some View {
        environment(\.lumenPreservesExpandedToolbar, preserves)
    }
}

extension EnvironmentValues {
    @Entry var lumenPreservesExpandedToolbar = false
    @Entry var lumenSettingsWindow = false
    @Entry var lumenIsSettingsWindow = false
    @Entry var lumenHasNativeSidebar = false
}

struct LumenSettingsRootKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct LumenWindowPaint: Equatable {
    var glow = false
    var forcedBand = false
}

struct LumenWindowPaintKey: PreferenceKey {
    static let defaultValue = LumenWindowPaint()
    static func reduce(value: inout LumenWindowPaint, nextValue: () -> LumenWindowPaint) {
        let next = nextValue()
        value.glow = value.glow || next.glow
        value.forcedBand = value.forcedBand || next.forcedBand
    }
}

/// Single native style owner for every palette-rooted window, including app-built roots.
@MainActor
final class LumenNativeWindowChrome {
    private weak var window: NSWindow?
    private var originalStyle: NSWindow.ToolbarStyle?
    private var installedStyle: NSWindow.ToolbarStyle?
    private var addedFullSize = false
    private var originalTitlebarTransparency: Bool?
    private var hasNativeSidebar = false
    private var observation: NSKeyValueObservation?
    private var transparencyObservation: NSKeyValueObservation?
    private var styleMaskObservation: NSKeyValueObservation?
    private var pending = false
    private var normalizing = false
    private var preservedHeight: CGFloat?
    private var preservesExpanded = false

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        // The hosted Settings scene test records this identity on the target SDK.
        window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
    }

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        originalStyle = window.toolbarStyle
        originalTitlebarTransparency = window.titlebarAppearsTransparent
        addedFullSize = !window.styleMask.contains(.fullSizeContentView)
        observation = window.observe(\.toolbarStyle, options: [.prior, .new]) { [weak self] window, change in
            MainActor.assumeIsolated {
                guard let self, !self.normalizing else { return }
                if change.isPrior {
                    if window.toolbarStyle != .expanded && window.toolbarStyle != .preference {
                        self.preservedHeight = window.contentLayoutRect.height
                    }
                } else { self.schedule() }
            }
        }
        transparencyObservation = window.observe(\.titlebarAppearsTransparent, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        styleMaskObservation = window.observe(\.styleMask, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        schedule()
    }

    func update(preservesExpanded: Bool, hasNativeSidebar: Bool) {
        self.preservesExpanded = preservesExpanded
        self.hasNativeSidebar = hasNativeSidebar
        schedule()
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            self.apply()
        }
    }

    private func apply() {
        guard let window else { return }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        let transparent = hasNativeSidebar || (originalTitlebarTransparency ?? false)
        if window.titlebarAppearsTransparent != transparent {
            window.titlebarAppearsTransparent = transparent
        }
        // Native sidebar material must own the band even in Settings scenes and
        // when an application requests an expanded toolbar for other window kinds.
        if preservesExpanded && !hasNativeSidebar {
            if let installedStyle, window.toolbarStyle == installedStyle, let originalStyle {
                changeStyle(originalStyle, in: window)
                self.installedStyle = nil
            }
            preservedHeight = nil
            return
        }
        guard window.toolbarStyle == .preference || window.toolbarStyle == .expanded else {
            preservedHeight = nil
            return
        }
        changeStyle(.unified, in: window)
        installedStyle = .unified
    }

    private func changeStyle(_ style: NSWindow.ToolbarStyle, in window: NSWindow) {
        let contentHeight = preservedHeight ?? window.contentLayoutRect.height
        preservedHeight = nil
        normalizing = true
        window.toolbarStyle = style
        let excess = window.contentLayoutRect.height - contentHeight
        var frame = window.frame
        frame.origin.y += excess
        frame.size.height -= excess
        window.setFrame(frame, display: false)
        normalizing = false
    }

    func detach() {
        observation = nil
        transparencyObservation = nil
        styleMaskObservation = nil
        if let window {
            if let installedStyle, let originalStyle, window.toolbarStyle == installedStyle {
                changeStyle(originalStyle, in: window)
            }
            if addedFullSize { window.styleMask.remove(.fullSizeContentView) }
            if let originalTitlebarTransparency { window.titlebarAppearsTransparent = originalTitlebarTransparency }
        }
        window = nil
        originalStyle = nil
        originalTitlebarTransparency = nil
        hasNativeSidebar = false
        installedStyle = nil
        preservedHeight = nil
        addedFullSize = false
    }
}
