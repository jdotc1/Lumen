import AppKit
import LumenTestSupport
import LumenTokens
@_spi(LayoutAudit) import LumenUI
import SwiftUI

public extension LumenConformance {
    /// Native chrome to exercise when hosting an application's root view. Each value is explicit:
    /// a hidden title and a full-size content view are separate AppKit configuration choices.
    struct WindowChrome: Sendable {
        public let titleVisibility: NSWindow.TitleVisibility
        public let toolbarStyle: NSWindow.ToolbarStyle
        public let toolbar: Bool
        public let fullSizeContentView: Bool

        public init(titleVisibility: NSWindow.TitleVisibility, toolbarStyle: NSWindow.ToolbarStyle,
                    toolbar: Bool, fullSizeContentView: Bool) {
            self.titleVisibility = titleVisibility
            self.toolbarStyle = toolbarStyle
            self.toolbar = toolbar
            self.fullSizeContentView = fullSizeContentView
        }

        fileprivate var description: String {
            "title=\(titleVisibility.rawValue), style=\(toolbarStyle.rawValue), toolbar=\(toolbar), fullSize=\(fullSizeContentView)"
        }
    }

    /// Audits the window's current layout, including windows without a Lumen palette root.
    /// Call after the application's layout has settled; this does not resize or present the window.
    @MainActor
    static func liveWindow(_ window: NSWindow) -> [Finding] {
        let name = window.title.isEmpty ? "Window \(window.windowNumber)" : window.title
        var violations = LumenLayoutAudit.findings(in: window)
        #if DEBUG
        do {
            violations += try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window)).findings
        } catch {
            violations.append(.init(rule: "rendered-capture", view: name, message: "rendered audit unavailable: \(error)"))
        }
        #endif
        return violations.map {
            Finding(.layout, "\(name) · \($0.view)", "\($0.rule): \($0.message)")
        }
    }

    /// Hosts the supplied root in a real window for each size, native chrome and text scale.
    /// The caller's root is preserved: include `lumenPaletteRoot()` to test its correction, or
    /// omit it to test detection. Native toolbar items are bridged from SwiftUI into AppKit.
    @MainActor
    static func windowLayout<Content: View>(sizes: [CGSize], chrome: [WindowChrome], textScales: [CGFloat],
                                            @ViewBuilder of content: () -> Content) -> [Finding] {
        var findings: [Finding] = []
        for size in sizes {
            for style in chrome {
                for scale in textScales {
                    let subject = "\(size.width)×\(size.height), \(style.description), text=\(scale)"
                    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                          scale.isFinite, scale > 0 else {
                        findings.append(Finding(.layout, subject, "requires finite positive sizes and text scales"))
                        continue
                    }
                    findings += HostedWindowLayout.inspect(content(), size: size, chrome: style,
                                                           scale: scale, subject: subject)
                }
            }
        }
        return findings
    }

    /// A live-window layout check for the runner's subject, sizes and theme variants.
    /// The subject owns its palette-root choice, as in `windowLayout(sizes:chrome:textScales:of:)`.
    static func windowLayout(chrome: [WindowChrome], textScales: [CGFloat]) -> some LumenCheck {
        LiveWindowLayoutCheck(chrome: chrome, textScales: textScales)
    }
}

private struct LiveWindowLayoutCheck: LumenCheck {
    let id = "lumen.windowLayout"
    let title = "Window chrome and layout"
    let chrome: [LumenConformance.WindowChrome]
    let textScales: [CGFloat]

    @MainActor
    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard let subject = context.subject else { return [context.missingSubject(for: id)] }
        return context.variants.flatMap { variant in
            let store = LumenSnapshot.store(for: variant, registry: context.registry, themes: context.themes ?? [])
            return LumenThemeStore.withActiveStore(store) {
                MainActor.assumeIsolated {
                    LumenConformance.windowLayout(sizes: context.sizes, chrome: chrome, textScales: textScales) {
                        subject.view
                            .environment(\.lumenStore, store)
                            .environment(\.lumenPalette, store.resolvedPalette())
                            .environment(\.colorScheme, variant.colorScheme)
                    }.map {
                        LumenConformance.Finding($0.area, "\(subject.name) · \(variant.label) · \($0.subject)", $0.message)
                    }
                }
            }
        }
    }
}

@MainActor
private enum HostedWindowLayout {
    private final class Reports {
        var truncated: Set<String> = []
        var visible: Set<LumenVisibleTextEntry> = []
    }

    static func inspect<Content: View>(_ content: Content, size: CGSize,
                                       chrome: LumenConformance.WindowChrome, scale: CGFloat,
                                       subject: String) -> [LumenConformance.Finding] {
        let reports = Reports()
        let root = content
            .lumenTextScale(Double(scale))
            .environment(\.lumenReportsLayoutChecks, true)
            .onPreferenceChange(LumenTruncationKey.self) { value in
                MainActor.assumeIsolated { reports.truncated = value }
            }
            .onPreferenceChange(LumenVisibleTextKey.self) { value in
                MainActor.assumeIsolated { reports.visible = value }
            }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars, .title]
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if chrome.fullSizeContentView { mask.insert(.fullSizeContentView) }
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size), styleMask: mask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = subject
        window.titleVisibility = chrome.titleVisibility
        window.toolbarStyle = chrome.toolbarStyle
        window.titlebarAppearsTransparent = chrome.titleVisibility == .hidden
        window.contentView = host
        if chrome.toolbar, window.toolbar == nil {
            window.toolbar = NSToolbar(identifier: "LumenConformance.windowLayout")
        }
        window.setContentSize(size)
        // An ordered window produces the same native toolbar and content-layout geometry as an
        // app window. Keep test windows offscreen and do not change the key window.
        LumenHeadlessHost.order(window)
        defer { window.close() }
        for _ in 0..<20 {
            // SwiftUI may bridge a root's toolbar after the first layout. The requested matrix
            // configuration owns whether that toolbar is displayed.
            window.toolbar?.isVisible = chrome.toolbar
            (host.superview ?? host).layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        var violations = LumenLayoutAudit.findings(in: window)
        let smallTruncated = reports.truncated
        let smallVisible = reports.visible
        #if DEBUG
        do {
            let small = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
            violations += small.findings
            // Resize this same root so its state and content identity survive the comparison.
            window.setContentSize(CGSize(width: max(size.width * 3, 1800), height: max(size.height * 2, 1200)))
            for _ in 0..<12 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            let large = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
            violations += LumenRenderedAudit.differential(small, large)
        } catch {
            violations.append(.init(rule: "rendered-capture", view: subject, message: "rendered audit unavailable: \(error)"))
        }
        #endif
        var findings = violations.map { LumenConformance.Finding(.layout, subject, "\($0.rule): \($0.message)") }
        findings += smallTruncated.sorted().map {
            .init(.layout, subject, "truncation: “\($0)” is clipped against its frame")
        }
        findings += LumenConformance.visibleDuplicates(smallVisible).map {
            .init(.layout, subject, "visible-text: \($0)")
        }
        return findings
    }
}
