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
    private var observation: NSKeyValueObservation?
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
        schedule()
    }

    func update(preservesExpanded: Bool) {
        self.preservesExpanded = preservesExpanded
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
        if preservesExpanded {
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
        if let window {
            if let installedStyle, let originalStyle, window.toolbarStyle == installedStyle {
                changeStyle(originalStyle, in: window)
            }
            if addedFullSize { window.styleMask.remove(.fullSizeContentView) }
        }
        window = nil
        originalStyle = nil
        installedStyle = nil
        preservedHeight = nil
        addedFullSize = false
    }
}
