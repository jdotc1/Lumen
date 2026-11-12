import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
import LumenTokens
@_spi(LayoutAudit) @testable import LumenUI
@testable import LumenCatalog

/// A Settings host that omits `.lumenSettingsScene()` (only its own palette and tint modifiers)
/// must still get the single unified toolbar row. The window carries the real SwiftUI Settings
/// identity and starts at the style a bare `Settings {}` scene receives.
@MainActor
final class LumenSettingsToolbarGuaranteeTests: XCTestCase {
    private struct Measurement: Encodable {
        var variant = ""
        var startStyle = 0
        var finalStyle = 0
        var band: CGFloat = 0
        var rows = 0
        var sidebarToggleItems = 0
        var historyGroup = CGRect.zero
        var chevronGap: CGFloat = -1
        var historyLeading: CGFloat = 0
        var sidebarColumnWidth: CGFloat = 0
        var sidebarColumn = CGRect.zero
        var toolbarItemFrames: [CGRect] = []
        var trafficLightFrames: [CGRect] = []
        var overflowed = false
        var appKitDirection = 0
    }

    private enum Variant: String { case before, ref }

    private func measure(_ variant: Variant, scheme: ColorScheme, chrome: LumenChromeStyle,
                         rightToLeft: Bool = false, png: URL? = nil) throws -> Measurement {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: scheme),
                                        registry: .core)
        return try LumenThemeStore.withActiveStore(store) {
            try MainActor.assumeIsolated {
                let size = CGSize(width: LumenSettingsSidebarView.windowIdealWidth, height: 640)
                var root: AnyView = AnyView(
                    LumenSettingsSidebarView(Array(CatalogSettings.categories.prefix(4)))
                        .lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
                        .lumenMetrics(.standard).lumenChromeStyle(chrome)
                        .environment(\.colorScheme, scheme).environment(\.displayScale, 2)
                        .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)
                        .environment(\.lumenSettingsSizesWindow, false)
                        .tint(store.resolvedPalette()[.accent]))
                if rightToLeft { root = AnyView(root.environment(\.layoutDirection, .rightToLeft)) }
                if variant == .ref { root = AnyView(root.environment(\.lumenSettingsWindow, true)) }
                let host = NSHostingView(rootView: root)
                host.sizingOptions = [.minSize, .maxSize]
                host.sceneBridgingOptions = [.toolbars, .title]
                let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
                let start: NSWindow.ToolbarStyle = variant == .ref ? .unified : .preference
                window.toolbarStyle = start
                window.contentView = host
                window.setContentSize(size)
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                for _ in 0..<25 {
                    (host.superview ?? host).layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                }
                XCTAssertTrue(LumenNativeWindowChrome.isSettingsWindow(window))
                var m = Measurement()
                m.variant = "\(variant.rawValue)-\(scheme == .dark ? "dark" : "light")-\(chrome.rawValue)"
                m.startStyle = start.rawValue
                m.finalStyle = window.toolbarStyle.rawValue
                m.band = window.frame.height - window.contentLayoutRect.height
                let geometry = LumenWindowGeometry(window: window)
                let centers = (geometry.trafficLights + geometry.toolbarItems).filter { !$0.isEmpty }.map(\.midY).sorted()
                var rows: [CGFloat] = []
                for c in centers where rows.last.map({ abs(c - $0) > 6 }) ?? true { rows.append(c) }
                m.rows = rows.count
                @MainActor func buttons(_ id: String) -> [CGRect] {
                    guard let item = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue.contains(id) }),
                          let view = item.view else { return [] }
                    @MainActor func walk(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(walk) }
                    return walk(view).compactMap { $0 as? NSButton }.filter { !$0.isHidden }
                        .map { $0.convert($0.bounds, to: nil) }.sorted { $0.minX < $1.minX }
                }
                m.sidebarToggleItems = (window.toolbar?.items ?? []).filter {
                    $0.itemIdentifier.rawValue.contains("lumen.settings.sidebar")
                        || $0.itemIdentifier.rawValue.contains("toggleSidebar")
                }.count
                let history = buttons("lumen.settings.history")
                m.historyGroup = history.reduce(CGRect.null) { $0.union($1) }
                if m.historyGroup.isNull { m.historyGroup = .zero }
                if history.count >= 2 { m.chevronGap = history[1].minX - history[0].maxX }
                m.historyLeading = m.historyGroup.minX
                m.appKitDirection = NSApp.userInterfaceLayoutDirection.rawValue
                m.trafficLightFrames = geometry.trafficLights.filter { !$0.isEmpty }
                    .map { window.convertFromScreen($0) }
                m.toolbarItemFrames = ["lumen.settings.history"].compactMap { id in
                    window.toolbar?.visibleItems?.first { $0.itemIdentifier.rawValue.contains(id) }
                        .flatMap { $0.view }.map { $0.convert($0.bounds, to: nil) }
                }
                m.overflowed = m.toolbarItemFrames.count < 1
                if let split = (host.superview ?? host).subviewsDeep().compactMap({ $0 as? NSSplitView }).first,
                   let side = split.arrangedSubviews.first {
                    m.sidebarColumnWidth = side.frame.width
                    m.sidebarColumn = side.convert(side.bounds, to: nil)
                }
                if let png {
                    try LumenHeadlessHost.png(of: window).write(to: png, options: .atomic)
                }
                return m
            }
        }
    }

    /// Proof renders. Set LUMEN_TOOLBAR_PROOF_OUT to a destination and a phase name (before/after).
    func testProofRenders() throws {
        guard let out = ProcessInfo.processInfo.environment["LUMEN_TOOLBAR_PROOF_OUT"], !out.isEmpty,
              let phase = ProcessInfo.processInfo.environment["LUMEN_TOOLBAR_PROOF_PHASE"] else {
            throw XCTSkip("Set LUMEN_TOOLBAR_PROOF_OUT and LUMEN_TOOLBAR_PROOF_PHASE to capture proof renders")
        }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var all: [Measurement] = []
        for variant in phase == "before" ? [Variant.before, .ref] : [.before] {
            for scheme in [ColorScheme.light, .dark] {
                for chrome in [LumenChromeStyle.drawn, .glass] {
                    let name = "\(phase == "after" ? "after" : variant.rawValue)-\(scheme == .dark ? "dark" : "light")-\(chrome.rawValue).png"
                    var m = try measure(variant, scheme: scheme, chrome: chrome, png: dir.appending(path: name))
                    if phase == "after" { m.variant = m.variant.replacingOccurrences(of: "before", with: "after") }
                    all.append(m)
                    print("TOOLBAR_PROOF \(m)")
                }
            }
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(all).write(to: dir.appending(path: "measurements-\(phase).json"), options: .atomic)
    }

    /// Guarantee: no scene modifier, bare-Settings starting style, still one unified row.
    func testSettingsWindowWithoutSceneModifierIsOneUnifiedRow() throws {
        for chrome in [LumenChromeStyle.drawn, .glass] {
            let ref = try measure(.ref, scheme: .dark, chrome: chrome)
            let bare = try measure(.before, scheme: .dark, chrome: chrome)
            let label = "\(chrome.rawValue): \(bare)"
            XCTAssertTrue([NSWindow.ToolbarStyle.unified.rawValue, NSWindow.ToolbarStyle.unifiedCompact.rawValue]
                .contains(bare.finalStyle), label)
            XCTAssertLessThanOrEqual(bare.band, ref.band + 0.5, label)
            XCTAssertEqual(bare.rows, 1, label)
            XCTAssertEqual(bare.sidebarToggleItems, 0, "Settings has no sidebar toggle: \(label)")
            XCTAssertGreaterThanOrEqual(bare.chevronGap, 0, label)
            XCTAssertLessThanOrEqual(bare.chevronGap, 4, label)
            XCTAssertLessThanOrEqual(abs(bare.historyLeading - ref.historyLeading), 1, label)
            XCTAssertLessThanOrEqual(bare.historyGroup.width, ref.historyGroup.width + 1, label)
        }
    }

    /// Real right-to-left: AppKit takes its direction from the process (a launch argument or the
    /// app's language), which cannot change inside a running test process. The test therefore
    /// runs its assertions in a child xctest process launched right-to-left and requires that
    /// child to execute them (a skip counts as a failure here).
    func testAppKitRightToLeftIsOneRowInContentColumn() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LUMEN_RTL_CHILD"] == "1" else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xctest", "-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES",
                                 "-XCTest", "LumenSettingsToolbarGuaranteeTests/testAppKitRightToLeftIsOneRowInContentColumn",
                                 Bundle(for: Self.self).bundlePath]
            var childEnv = env
            childEnv["LUMEN_RTL_CHILD"] = "1"
            process.environment = childEnv
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, output)
            XCTAssertTrue(output.contains("Executed 1 test, with 0 failures"), output)
            XCTAssertFalse(output.contains("skipped"), output)
            return
        }
        for chrome in [LumenChromeStyle.drawn, .glass] {
            let m = try measure(.before, scheme: .light, chrome: chrome, rightToLeft: true)
            let label = "\(chrome.rawValue): \(m)"
            XCTAssertEqual(m.appKitDirection, NSUserInterfaceLayoutDirection.rightToLeft.rawValue, label)
            XCTAssertFalse(m.sidebarColumn.isEmpty, label)
            XCTAssertEqual(m.rows, 1, "one toolbar row: \(label)")
            XCTAssertFalse(m.overflowed, "no overflow chevron: \(label)")
            XCTAssertEqual(m.toolbarItemFrames.count, 1, label)
            XCTAssertEqual(m.sidebarToggleItems, 0, "Settings has no sidebar toggle: \(label)")
            for item in m.toolbarItemFrames {
                XCTAssertFalse(item.intersects(m.sidebarColumn), "toolbar item in the sidebar column: \(label)")
                XCTAssertGreaterThan(item.midX, 0, label)
                XCTAssertLessThan(item.maxX, m.sidebarColumn.minX + 1, label)
            }
            XCTAssertEqual(m.trafficLightFrames.count, 3, label)
            for light in m.trafficLightFrames {
                XCTAssertGreaterThanOrEqual(light.minX, m.sidebarColumn.minX, "traffic lights over the right sidebar: \(label)")
            }
        }
    }

    /// The rendered audit's two-row finding fires on a deliberately two-row Settings window.
    func testAuditFlagsTwoRowSettingsWindow() throws {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark), registry: .core)
        LumenThemeStore.withActiveStore(store) {
            MainActor.assumeIsolated {
                let size = CGSize(width: LumenSettingsSidebarView.windowIdealWidth, height: 640)
                let root = LumenSettingsSidebarView(Array(CatalogSettings.categories.prefix(3)))
                    .lumenPaletteRoot(store: store).lumenDensityRoot(store: store).lumenMetrics(.standard)
                    .environment(\.lumenSettingsSizesWindow, false)
                let host = NSHostingView(rootView: root)
                host.sceneBridgingOptions = [.toolbars, .title]
                let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
                window.contentView = host
                window.setContentSize(size)
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                for _ in 0..<25 {
                    (host.superview ?? host).layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                }
                XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == "window-toolbar-rows" },
                               "normalized window must not be flagged")
                // The bridge re-normalizes asynchronously; audit synchronously after the change.
                window.toolbarStyle = .expanded
                let findings = LumenRenderedAudit.windowChromeFindings(in: window)
                XCTAssertTrue(findings.contains { $0.rule == "window-toolbar-rows" }, "findings: \(findings)")
            }
        }
    }
}

private extension NSView {
    func subviewsDeep() -> [NSView] { [self] + subviews.flatMap { $0.subviewsDeep() } }
}
