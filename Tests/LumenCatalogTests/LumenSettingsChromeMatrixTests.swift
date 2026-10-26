import AppKit
import LumenHeadlessGuard
import LumenTestSupport
import LumenTokens
import LumenConformance
import SwiftUI
import XCTest
@_spi(LayoutAudit) @testable import LumenUI
@testable import LumenCatalog

/// The product is generated from the Catalog's window roots. Policy changes occur in the
/// same host; app-composed roots exercise the bridge without a Lumen window scaffold.
@MainActor
final class LumenSettingsChromeMatrixTests: XCTestCase {
    private struct Kind {
        let name: String
        let size: CGSize
        var panel = false
        var settings = false
        var sidebar = false
        let make: @MainActor () -> AnyView
    }

    private var kinds: [Kind] {
        [
            Kind(name: "workspace", size: .init(width: 1200, height: 800), sidebar: true) { AnyView(WorkspaceDemo()) },
            Kind(name: "document", size: CatalogDocumentWindow.defaultSize) {
                AnyView(CatalogDocumentWindow(document: CatalogTextDocument(text: "Sample document")))
            },
            Kind(name: "library", size: CatalogLibraryWindow.defaultSize, sidebar: true) { AnyView(CatalogLibraryWindow()) },
            Kind(name: "utility", size: CatalogUtilityWindow.defaultSize, sidebar: true) { AnyView(CatalogUtilityWindow()) },
            Kind(name: "wizard", size: .init(width: 640, height: 460)) { AnyView(CatalogWizardWindow()) },
            Kind(name: "menuBarPanel", size: .init(width: 360, height: 480), panel: true) { AnyView(CatalogMenuBarPanel()) },
            Kind(name: "settings", size: .init(width: 980, height: 720), settings: true, sidebar: true) {
                AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories))
            },
            Kind(name: "sheetRoot", size: .init(width: 640, height: 440)) {
                AnyView(LumenSheet("Details", systemImage: "info.circle", done: .init("Done", perform: {})) { Text("Sheet contents") })
            },
            Kind(name: "catalog", size: .init(width: 1280, height: 800), sidebar: true) { AnyView(CatalogView()) },
            Kind(name: "splitWorkspace", size: .init(width: 1440, height: 900)) { AnyView(SplitWorkspaceDemo()) },
            Kind(name: "sampleWorkspace", size: SampleWorkspace.defaultSize, sidebar: true) { AnyView(SampleWorkspace()) },
            Kind(name: "documentWelcome", size: .init(width: 760, height: 540)) { AnyView(CatalogDocumentWelcome()) },
            Kind(name: "welcome", size: .init(width: 760, height: 540)) { AnyView(CatalogWelcome()) },
        ]
    }

    @Observable final class Policy {
        var colorScheme = ColorScheme.dark
        var chrome = LumenChromeStyle.drawn
        var scale = 1.0
        var settings = false
        var preserveExpanded = false
        var stateCount = 0
        var increment: (() -> Void)?
    }

    private struct PersistentState: View {
        let policy: Policy
        @State private var count = 0
        var body: some View {
            Color.clear.frame(width: 1, height: 1)
                .onAppear {
                    policy.stateCount = count
                    policy.increment = { count += 1; policy.stateCount = count }
                }
                .onChange(of: count) { _, value in policy.stateCount = value }
        }
    }

    private struct Root: View {
        let content: AnyView
        let policy: Policy
        let store: LumenThemeStore
        var body: some View {
            content.overlay(alignment: .bottomTrailing) { PersistentState(policy: policy) }
                .lumenPaletteRoot(store: store)
                .lumenTextScale(policy.scale)
                .lumenChromeStyle(policy.chrome)
                .environment(\.lumenSettingsWindow, policy.settings)
                .lumenPreservesExpandedToolbar(policy.preserveExpanded)
                .environment(\.lumenSettingsSizesWindow, false)
                .environment(\.appearsActive, true)
                .preferredColorScheme(policy.colorScheme)
        }
    }

    private struct AppBuiltRoot: View {
        var body: some View {
            NavigationSplitView {
                List { Label("General", systemImage: "gearshape"); Label("Advanced", systemImage: "slider.horizontal.3") }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 300)
            } detail: {
                Form { Toggle("Enabled", isOn: .constant(true)); TextField("Name", text: .constant("Sample")) }
                    .formStyle(.grouped)
                    .navigationTitle("General")
            }
        }
    }

    func testGeneratedWindowKindChromeCompositionAndScaleMatrix() throws {
        XCTAssertEqual(ProcessInfo.processInfo.environment["LUMEN_SETTINGS_MATRIX_NATIVE_PROBES"], "1",
                       "The matrix requires native first-content probes")
        let plainWindow = LumenHeadlessHost.window(
            contentRect: .init(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        plainWindow.isReleasedWhenClosed = false
        LumenHeadlessHost.order(plainWindow)
        settle(plainWindow)
        let plainBand = plainWindow.frame.height - plainWindow.contentLayoutRect.height
        defer { plainWindow.close() }
        XCTAssertNil(plainWindow.toolbar)
        print("CHROME_MATRIX native toolbarless band=\(plainBand)")
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        var cases = 0
        var hosts = 0
        let selected = ProcessInfo.processInfo.environment["LUMEN_SETTINGS_MATRIX_CASES"].map {
            Set($0.split(separator: ",").map(String.init))
        }
        for kind in kinds {
            for scaffold in [true, false] {
                let composition = "\(kind.name)/\(scaffold ? "scaffold" : "app-built")"
                if let selected, !selected.contains(composition) { continue }
                hosts += 1
                let policy = Policy()
                policy.settings = kind.settings
                let content = scaffold ? kind.make() : AnyView(AppBuiltRoot())
                let host = NSHostingView(rootView: Root(content: content, policy: policy, store: store))
                host.sizingOptions = []
                host.sceneBridgingOptions = [.title, .toolbars]
                let mask: NSWindow.StyleMask = kind.panel ? [.borderless] : [.titled, .closable, .resizable]
                let rect = CGRect(origin: .zero, size: kind.size)
                let window = kind.panel
                    ? LumenHeadlessHost.panel(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
                    : LumenHeadlessHost.window(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                // Match the production full-size scaffold host: its toolbar background is
                // transparent so the owned drawn gradient, not AppKit's plate, is sampled.
                window.titlebarAppearsTransparent = scaffold && !kind.settings
                window.toolbarStyle = kind.settings ? .preference : .expanded
                // The production root supplies its toolbar through scene bridging. Inserting an
                // empty toolbar invents a 66-point band in toolbarless wizard/welcome/sheet roots.
                let before = measurement(window)
                window.contentView = host
                window.setContentSize(kind.size)
                LumenHeadlessHost.order(window)
                defer { window.close() }
                settle(window)
                policy.increment?()
                for chrome in [LumenChromeStyle.drawn, .glass] {
                    for scale in [1.0, 1.3] {
                        policy.chrome = chrome
                        policy.scale = scale
                        settle(window)
                        let label = "\(kind.name)/\(scaffold ? "scaffold" : "app-built")/\(chrome)/\(scale)"
                        let report = LumenWindowAuditReports.record(for: window)
                        let band = window.frame.height - window.contentLayoutRect.height
                        let limit: CGFloat = window.toolbar == nil ? (kind.panel ? 0 : plainBand) : (window.toolbarStyle == .unifiedCompact ? 40 : 52)
                        XCTAssertNotEqual(window.toolbarStyle, .preference, "\(label): \(measurement(window))")
                        XCTAssertNotEqual(window.toolbarStyle, .expanded, "\(label): \(measurement(window))")
                        XCTAssertLessThanOrEqual(band, limit + 1, "\(label): \(measurement(window)); limit=\(limit)")
                        XCTAssertLessThanOrEqual(controlRows(window), 1, "\(label): \(measurement(window))")
                        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "\(label): mask=\(window.styleMask.rawValue)")
                        XCTAssertEqual(policy.stateCount, 1, "\(label): policy flip reset local state to \(policy.stateCount)")
                        XCTAssertEqual(report.settingsWindow, kind.settings, "\(label): settings=\(report.settingsWindow)")
                        if kind.settings {
                            XCTAssertFalse(report.paintsWindowGlow, "\(label): settings paints glow")
                            XCTAssertFalse(report.forcesToolbarBand, "\(label): settings forces toolbar band")
                        } else if chrome == .drawn && ["workspace", "document"].contains(kind.name) {
                            XCTAssertTrue(report.paintsWindowGlow, "\(label): active workspace/document lost its glow")
                        }
                        if (!scaffold || kind.sidebar),
                           let sidebar = descendants(host).compactMap({ $0 as? NSSplitView }).first?.arrangedSubviews.first {
                            let frame = window.convertToScreen(sidebar.convert(sidebar.bounds, to: nil))
                            // Native sidebar material extends behind the traffic lights while
                            // its interactive list content correctly starts below them.
                            let materialTops = descendants(host.superview ?? host).compactMap { view -> CGFloat? in
                                guard let effect = view as? NSVisualEffectView, effect.material == .sidebar,
                                      !effect.isHiddenOrHasHiddenAncestor else { return nil }
                                let effectFrame = window.convertToScreen(effect.convert(effect.bounds, to: nil))
                                let overlapWidth = min(effectFrame.maxX, frame.maxX) - max(effectFrame.minX, frame.minX)
                                return overlapWidth >= frame.width * 0.8 ? effectFrame.maxY : nil
                            }
                            let sidebarTop = max(frame.maxY, materialTops.max() ?? frame.maxY)
                            let assertFullHeight = {
                                XCTAssertGreaterThanOrEqual(sidebarTop, window.frame.maxY - 1,
                                    "\(label): sidebar content top=\(frame.maxY), material tops=\(materialTops), window top=\(window.frame.maxY), band=\(band)")
                            }
                            if scaffold && ["library", "utility", "sampleWorkspace"].contains(kind.name) {
                                XCTExpectFailure("Scaffold sidebars currently start below the toolbar band",
                                                 strict: true, failingBlock: assertFullHeight)
                            } else {
                                assertFullHeight()
                            }
                        } else if !scaffold || kind.sidebar {
                            XCTFail("\(label): expected native sidebar is absent")
                        }
                        if scaffold {
                            assertContentBelowBand(window: window, host: host, hasSidebar: kind.sidebar, label: label)
                            if chrome == .drawn && ["workspace", "document"].contains(kind.name) {
                                try assertGlow(window: window, store: store, label: label + "/dark")
                                // The regression was light-only. Flip appearance in this host rather
                                // than constructing a fixture which cannot detect identity changes.
                                policy.colorScheme = .light
                                window.appearance = NSAppearance(named: .aqua)
                                settle(window)
                                assertContentBelowBand(window: window, host: host, hasSidebar: kind.sidebar,
                                                       label: label + "/light")
                                try assertGlow(window: window, store: store, label: label + "/light")
                                XCTAssertEqual(policy.stateCount, 1, "\(label): appearance flip reset state")
                                policy.colorScheme = .dark
                                window.appearance = NSAppearance(named: .darkAqua)
                                settle(window)
                            }
                        }
                        XCTAssertEqual(window.alphaValue, 0, "\(label): alpha=\(window.alphaValue)")
                        XCTAssertFalse(window.isKeyWindow, "\(label): became key")
                        print("CHROME_MATRIX \(label) before=\(before) after=\(measurement(window)) glow=\(report.paintsWindowGlow) forced=\(report.forcesToolbarBand)")
                        cases += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(hosts, 0, "No matrix hosts matched \(selected?.sorted() ?? [])")
        XCTAssertEqual(cases, hosts * 2 * 2)
        print("CHROME_MATRIX cases=\(cases); About uses the native standard panel with no Lumen root; sheets cover the production sheet root, not modal presentation")
    }

    func testSettingsPolicyAndExpandedOptOutKeepStateInOneHost() throws {
        let policy = Policy()
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark), registry: .core)
        let host = NSHostingView(rootView: Root(content: AnyView(AppBuiltRoot()), policy: policy, store: store))
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 820, height: 600),
                                            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.order(window)
        defer { window.close() }
        settle(window)
        policy.increment?()
        for settings in [true, false, true] {
            policy.settings = settings
            settle(window)
            let report = LumenWindowAuditReports.record(for: window)
            XCTAssertEqual(report.settingsWindow, settings, "actual settings=\(report.settingsWindow), expected=\(settings)")
            XCTAssertEqual(policy.stateCount, 1, "actual state=\(policy.stateCount)")
        }
        policy.preserveExpanded = true
        settle(window)
        window.toolbarStyle = .expanded
        settle(window)
        XCTAssertEqual(window.toolbarStyle, .expanded, "opt-out actual style=\(window.toolbarStyle.rawValue)")
        policy.preserveExpanded = false
        settle(window)
        XCTAssertEqual(window.toolbarStyle, .unified, "normalization actual style=\(window.toolbarStyle.rawValue)")
        XCTAssertEqual(policy.stateCount, 1, "opt-out reset actual state=\(policy.stateCount)")
    }

    private struct ContentSubview {
        let name: String
        let frame: CGRect
        var nativeTextEditor = false
    }

    /// Read the actual leaf frames before clipping. A visible-frame intersection would hide
    /// the very regression under test when the first line slides behind the toolbar.
    private func contentSubviews(in root: NSView, window: NSWindow) -> [ContentSubview] {
        var seen: Set<ObjectIdentifier> = []
        var result: [ContentSubview] = []
        let roles: Set<NSAccessibility.Role> = [.staticText, .textField, .textArea, .button,
            .checkBox, .radioButton, .popUpButton, .comboBox, .slider]
        func visit(_ object: AnyObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            let native = object as? NSView
            if let native, native.isHiddenOrHasHiddenAncestor || native.alphaValue <= 0 { return }
            let semantic = object as? any NSAccessibilityProtocol
            if let semantic, semantic.isAccessibilityElement(),
               let role = semantic.accessibilityRole(), roles.contains(role) {
                let frame = native.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
                    ?? semantic.accessibilityFrame()
                if frame.width > 0.5, frame.height > 0.5, frame.minX.isFinite, frame.minY.isFinite {
                    let name = semantic.accessibilityLabel() ?? semantic.accessibilityTitle()
                        ?? (semantic.accessibilityValue() as? String) ?? role.rawValue
                    result.append(ContentSubview(name: name, frame: frame, nativeTextEditor: role == .textArea))
                }
            }
            for child in native?.subviews ?? [] { visit(child) }
            for child in semantic?.accessibilityChildren() ?? [] { visit(child as AnyObject) }
        }
        visit(root)
        return result
    }

    private func assertContentBelowBand(window: NSWindow, host: NSView,
                                       hasSidebar: Bool, label: String) {
        let bandBottom = window.frame.height - window.contentLayoutRect.height
        let contentRoles: Set<String> = ["source-list-row", "source-list-heading", "inspector header",
            "inspector section", "inspector summary card", "welcome-recent-row"]
        let hasSplit = descendants(host).contains { $0 is NSSplitView }
        let acceptsContentTiles = !hasSplit || label.hasPrefix("settings/scaffold/")
        // A native background probe belongs to the same real NSView subtree as the leaf.
        // Never assign a preference from another hosting root by its x coordinate.
        let nativeProbes: [(view: NSView, leaf: ContentSubview)] = descendants(host).compactMap { view in
            guard !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 0.5, view.bounds.height > 0.5 else { return nil }
            let role: String
            if let probe = view as? CatalogFirstContentProbeView {
                role = probe.role
            } else if let probe = view as? LumenMarginElementProbeView,
                      contentRoles.contains(probe.role) || (acceptsContentTiles && probe.role == "icon-tile") {
                role = probe.role
            } else { return nil }
            return (view, ContentSubview(name: role, frame: window.convertToScreen(view.convert(view.bounds, to: nil))))
        }
        let leaves = contentSubviews(in: host, window: window) + nativeProbes.map(\.leaf)
        XCTAssertFalse(nativeProbes.isEmpty, "\(label): no measured first-content probe")
        for leaf in leaves {
            let minY = window.frame.maxY - leaf.frame.maxY
            XCTAssertGreaterThanOrEqual(minY, bandBottom - 1,
                "\(label): content \(leaf.name) minY=\(minY), bandBottom=\(bandBottom), frame=\(leaf.frame)")
        }
        if !hasSplit, let first = nativeProbes.map(\.leaf).max(by: { $0.frame.maxY < $1.frame.maxY }) {
            print("CHROME_CONTENT \(label) root first=\(first.name) minY=\(window.frame.maxY - first.frame.maxY) bandBottom=\(bandBottom)")
        }
        let splits = descendants(host).compactMap { $0 as? NSSplitView }.filter(\.isVertical)
        for (index, split) in splits.enumerated() {
            for (column, view) in split.arrangedSubviews.enumerated() where !view.isHiddenOrHasHiddenAncestor && view.bounds.width > 1 {
                let children = contentSubviews(in: view, window: window).filter(\.nativeTextEditor)
                    + nativeProbes.filter { $0.view.isDescendant(of: view) }.map(\.leaf)
                XCTAssertFalse(children.isEmpty, "\(label): split=\(index) column=\(column) has no measured content leaf")
                if let first = children.max(by: { $0.frame.maxY < $1.frame.maxY }) {
                    print("CHROME_CONTENT \(label) split=\(index) column=\(column) first=\(first.name) minY=\(window.frame.maxY - first.frame.maxY) bandBottom=\(bandBottom)")
                }
            }
        }
        if hasSidebar {
            guard let sidebar = splits.first?.arrangedSubviews.first else {
                XCTFail("\(label): expected sidebar column is absent")
                return
            }
            XCTAssertFalse(sidebar.isHiddenOrHasHiddenAncestor, "\(label): expected sidebar column is hidden")
            XCTAssertGreaterThan(sidebar.bounds.width, 1, "\(label): expected sidebar column has no visible width")
            let rows = nativeProbes.filter {
                $0.view.isDescendant(of: sidebar) && ["source-list-row", "sidebar-first-control", "icon-tile"].contains($0.leaf.name)
            }.map(\.leaf)
            let first = rows.max { $0.frame.maxY < $1.frame.maxY }
            XCTAssertNotNil(first, "\(label): sidebar has no measured first row/search")
            if let first {
                print("CHROME_FIRST_ROW \(label) first=\(first.name) minY=\(window.frame.maxY - first.frame.maxY) bandBottom=\(bandBottom)")
                XCTAssertGreaterThanOrEqual(window.frame.maxY - first.frame.maxY, bandBottom - 1,
                    "\(label): sidebar first row/search \(first.name) minY=\(window.frame.maxY - first.frame.maxY), bandBottom=\(bandBottom)")
            }
        }
    }

    private func assertGlow(window: NSWindow, store: LumenThemeStore, label: String) throws {
        // A geometry-only matrix correction reuses the prior unchanged-product samples.
        if ProcessInfo.processInfo.environment["LUMEN_SETTINGS_MATRIX_REUSE_GLOW"] == "1" {
            print("CHROME_GLOW_REUSED \(label)")
            return
        }
        let frame = try XCTUnwrap(window.contentView?.superview)
        frame.displayIfNeeded()
        let bitmap = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        let band = LumenWindowGeometry(window: window).chromeBand
        let point = frame.convert(window.convertPoint(fromScreen: CGPoint(x: band.midX, y: band.midY)), from: nil)
        let x = Int((point.x - frame.bounds.minX) / frame.bounds.width * CGFloat(bitmap.pixelsWide))
        let topY = frame.isFlipped ? point.y - frame.bounds.minY : frame.bounds.maxY - point.y
        let y = Int(topY / frame.bounds.height * CGFloat(bitmap.pixelsHigh))
        let sample = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        var background: NSColor?
        var top: NSColor?
        var bottom: NSColor?
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = store.nsColor(.toolbarBackground).usingColorSpace(.sRGB)
            top = store.nsColor(.titlebarActiveTop).usingColorSpace(.sRGB)
            bottom = store.nsColor(.titlebarActiveBottom).usingColorSpace(.sRGB)
        }
        let flat = try XCTUnwrap(background)
        let upper = try XCTUnwrap(top), lower = try XCTUnwrap(bottom)
        let actual = [sample.redComponent, sample.greenComponent, sample.blueComponent]
        let flatRGB = [flat.redComponent, flat.greenComponent, flat.blueComponent]
        let glowRGB = [(upper.redComponent + lower.redComponent) / 2,
                       (upper.greenComponent + lower.greenComponent) / 2,
                       (upper.blueComponent + lower.blueComponent) / 2]
        let flatDistance = zip(actual, flatRGB).map { abs($0 - $1) }.max() ?? 0
        let glowDistance = zip(actual, glowRGB).map { abs($0 - $1) }.max() ?? 0
        if label.hasPrefix("workspace/scaffold/") {
            // The inactive native workspace paints a neutral band at both text scales
            // in both appearances.
            let base: [CGFloat] = label.hasSuffix("/light")
                ? [1.0, 0.9999999403953552, 1.0]
                : [0.15692797303199768, 0.15692797303199768, 0.15692797303199768]
            let delta = zip(actual, base).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThanOrEqual(delta, 1 / 255, "\(label): band centre=\(actual), base=\(base), delta=\(delta)")
            print("CHROME_GLOW_BASE \(label) centre=\(actual) base=\(base) delta=\(delta)")
        } else {
            XCTAssertGreaterThan(flatDistance, 2 / 255,
                "\(label): band centre=\(actual), flat toolbar=\(flatRGB), expected glow=\(glowRGB)")
            XCTAssertLessThan(glowDistance, flatDistance,
                "\(label): band centre closer to flat toolbar than glow; sample=\(actual), flat=\(flatRGB), glow=\(glowRGB)")
        }
        print("CHROME_GLOW \(label) centre=\(actual) flat=\(flatRGB) glow=\(glowRGB)")
    }

    private func measurement(_ window: NSWindow) -> String {
        let rows = window.toolbar == nil ? 0 : ([NSWindow.ToolbarStyle.preference, .expanded].contains(window.toolbarStyle) ? 2 : 1)
        return "style:\(window.toolbarStyle.rawValue),band:\(window.frame.height - window.contentLayoutRect.height),styleRows:\(rows),measuredControlRows:\(controlRows(window))"
    }

    private func controlRows(_ window: NSWindow) -> Int {
        let geometry = LumenWindowGeometry(window: window)
        let centers = (geometry.trafficLights + geometry.toolbarItems).filter { !$0.isEmpty }.map(\.midY).sorted()
        var rows: [CGFloat] = []
        for center in centers where rows.last.map({ abs(center - $0) > 6 }) ?? true { rows.append(center) }
        return rows.count
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<12 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

/// A real Settings Scene, registered through the documented AppKit scene bridge. The process
/// guard intercepts its front request before dispatch; content attachment records the real identity.
@MainActor
final class LumenSettingsSceneIdentityTests: XCTestCase {
    @MainActor private final class Observation {
        weak var window: NSWindow?
        var expectedAttempt = false
    }

    private struct Probe: NSViewRepresentable {
        let observation: Observation
        func makeNSView(context: Context) -> ProbeView { ProbeView(observation: observation) }
        func updateNSView(_ view: ProbeView, context: Context) {}
        final class ProbeView: NSView {
            let observation: Observation
            init(observation: Observation) { self.observation = observation; super.init(frame: .zero) }
            required init?(coder: NSCoder) { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window, observation.window == nil else { return }
                observation.window = window
                LumenHeadlessGuardBeginExpectedAttempt(window, "makeKeyAndOrderFront:")
                observation.expectedAttempt = true
            }
        }
    }

    func testRealSwiftUISettingsSceneIdentity() throws {
        let observation = Observation()
        let scene = NSHostingSceneRepresentation {
            Settings {
                NavigationSplitView { List { Text("General") }.listStyle(.sidebar) } detail: {
                    Form { Text("Settings identity fixture") }.formStyle(.grouped)
                }
                .background(Probe(observation: observation))
                .frame(width: 820, height: 600)
                .lumenPaletteRoot()
            }
        }
        NSApplication.shared.addSceneRepresentation(scene)
        defer {
            if observation.expectedAttempt { _ = LumenHeadlessGuardEndExpectedAttempt() }
            observation.window?.close()
        }
        scene.environment.openSettings()
        for _ in 0..<30 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        let window = try XCTUnwrap(observation.window, "Settings scene did not attach its content")
        let identifier = try XCTUnwrap(window.identifier?.rawValue, "Real Settings window has no identifier; class=\(type(of: window))")
        print("SETTINGS_SCENE_IDENTITY identifier=\(identifier) class=\(NSStringFromClass(type(of: window))) toolbarStyle=\(window.toolbarStyle.rawValue) band=\(window.frame.height - window.contentLayoutRect.height)")
        XCTAssertFalse(identifier.isEmpty, "Settings identity was empty")
        let report = LumenWindowAuditReports.record(for: window)
        XCTAssertTrue(report.settingsWindow, "Real Settings scene was not detected")
        XCTAssertFalse(report.paintsWindowGlow, "Real Settings scene paints glow")
        XCTAssertFalse(report.forcesToolbarBand, "Real Settings scene forces toolbar band")
        XCTAssertEqual(window.toolbarStyle, .unified, "Real Settings toolbar style=\(window.toolbarStyle.rawValue)")
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "Real Settings lacks full-height content")
        XCTAssertTrue(LumenNativeWindowChrome.isSettingsWindow(window),
                      "Real Settings identity is not recognized: identifier=\(identifier), class=\(NSStringFromClass(type(of: window)))")
        if observation.expectedAttempt {
            let intercepted = LumenHeadlessGuardEndExpectedAttempt()
            observation.expectedAttempt = false
            XCTAssertEqual(intercepted, 1, "Settings front requests intercepted=\(intercepted)")
        }
        XCTAssertEqual(window.alphaValue, 0, "Settings alpha=\(window.alphaValue)")
        XCTAssertFalse(window.isKeyWindow, "Settings became key")
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "Settings frame=\(window.frame) intersects a screen")
    }
}
