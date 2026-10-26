import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI
import LumenConformance
@testable import LumenCatalog

/// The stock settings scaffold in a real AppKit window, including SwiftUI's bridged toolbar.
/// These checks deliberately inspect native table style, drawn pixels and toolbar geometry;
/// a scaled Catalog tile cannot establish any of those window-level properties.
@MainActor
final class LumenSettingsLiveWindowTests: XCTestCase {
    private enum Violation: String, CaseIterable, Sendable {
        case sourceList, sidebarMaterial, detailPalette, historyGroup, controlHeights, navigationTitle, toggleCount, bandHeight, selectionPalette
    }

    private struct Observation: Sendable {
        var violations: Set<Violation> = []
        var details: [String] = []
        var description: String { details.joined(separator: "; ") }
    }

    func testModelServerOpensAndChangesPanesWithSidebarFocus() throws {
        let selection = SettingsSelectionBox()
        selection.value = "model-server"
        let panes = [
            LumenSettingsCategory(id: "model-server", title: "Model server", systemImage: "cpu", hue: .hueViolet) {
                CatalogModelServerSettings()
            },
            LumenSettingsCategory(id: "other", title: "Other", systemImage: "gearshape", hue: .hueBlue) {
                Form { TextField("Other endpoint", text: .constant("example")) }
            }
        ]
        try withWindow(BoundSettingsHost(categories: panes, selection: selection), compact: true,
                       size: CGSize(width: 1000, height: 760)) { window, host, _ in
            @MainActor func assertSidebarFocus() throws {
                let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }
                    .first { $0.effectiveStyle == .sourceList })
                XCTAssertNotNil(window.firstResponder, "Focus must have an explicit owner")
                XCTAssertFalse(window.firstResponder is NSText)
                XCTAssertFalse(window.firstResponder is NSTextField)
                XCTAssertTrue(window.firstResponder === table, "Initial and selection focus belongs to the sidebar: \(String(describing: window.firstResponder))")
                XCTAssertFalse(window.isKeyWindow)
            }
            XCTAssertEqual(selection.value, "model-server")
            try assertSidebarFocus()
            selection.value = "other"
            settle(window: window, host: host)
            try assertSidebarFocus()
            selection.value = "model-server"
            settle(window: window, host: host)
            try assertSidebarFocus()

        }
    }

    func testFiveCategoryDrawnSettingsWindow() throws {
        try assertStock(categoryCount: 5, chrome: .drawn)
    }

    func testFiveCategorySettingsRootClosesAndReopensWithoutReentrantRows() throws {
        for cycle in 1...2 {
            try autoreleasepool {
                try withWindow(LumenSettingsSidebarView(categories(5)).lumenChromeStyle(.drawn),
                               compact: true) { window, view, _ in
                    let host = try XCTUnwrap(view as? NSHostingView<AnyView>)
                    let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }
                        .first { $0.effectiveStyle == .sourceList })
                    XCTAssertGreaterThanOrEqual(table.numberOfRows, 5, "Cycle \(cycle) must instantiate all five categories")
                    XCTAssertEqual(table.selectionHighlightStyle, .none)
                    window.close()
                    // Invalidate the graph while the closed window still owns its content.
                    // AppKit may still report table.window here; dismantle must not reload rows.
                    host.rootView = AnyView(EmptyView())
                    host.layoutSubtreeIfNeeded()
                    window.contentView = nil
                    for _ in 0..<3 {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                    }
                    XCTAssertNil(table.window, "Cycle \(cycle) must detach the native rows")
                }
            }
        }
    }

    func testTwoCategoryDrawnSettingsWindow() throws {
        try assertStock(categoryCount: 2, chrome: .drawn)
    }

    func testFiveCategoryGlassSettingsWindow() throws {
        try assertStock(categoryCount: 5, chrome: .glass)
    }

    func testTwoCategoryGlassSettingsWindow() throws {
        try assertStock(categoryCount: 2, chrome: .glass)
    }

    /// A deliberately bare host exposes a flat system-grey list,
    /// automatic sidebar toggle, automatic toolbar style and a category title without history.
    /// Every invariant must reject it. Keeping this fixture prevents a permissive probe (or a
    /// missing toolbar/table silently interpreted as success) from blessing the old composition.
    func testBareSettingsHostFailsEveryWindowInvariant() throws {
        let result = try observe(BareSettingsHost(categories: categories(2)), compact: false)
        XCTAssertTrue(result.violations.isSuperset(of: [.sourceList, .historyGroup, .controlHeights, .navigationTitle]), result.description)
        print("BARE_HOST: \(result.description)")
    }

    func testBoundSelectionAndNativeHistoryKeepWindowSizeStable() throws {
        let selection = SettingsSelectionBox()
        let root = BoundSettingsHost(categories: categories(2), selection: selection)
        try withWindow(root, compact: true, sizing: [.minSize, .maxSize]) { window, host, _ in
            let frameSize = window.frame.size
            let contentSize = window.contentLayoutRect.size
            let hostSize = host.frame.size

            @MainActor func buttons() throws -> (back: NSButton, forward: NSButton) {
                let history = try XCTUnwrap(window.toolbar?.items.first {
                    $0.itemIdentifier.rawValue.contains("lumen.settings.history")
                })
                let root = try XCTUnwrap(history.view)
                let controls = descendants(root).compactMap { $0 as? NSButton }.sorted {
                    $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
                }
                XCTAssertEqual(controls.count, 2, "History must expose its two native action buttons")
                return (try XCTUnwrap(controls.first), try XCTUnwrap(controls.dropFirst().first))
            }

            @MainActor func assertState(_ id: String, title: String, back: Bool, forward: Bool) throws {
                let controls = try buttons()
                XCTAssertEqual(selection.value, id, "Navigation must write back to the public binding")
                XCTAssertEqual(window.title, title, "The live navigation title must follow the selected pane")
                XCTAssertEqual(controls.back.isEnabled, back)
                XCTAssertEqual(controls.forward.isEnabled, forward)
                XCTAssertEqual(window.frame.size, frameSize, "Changing panes must not resize the window")
                XCTAssertEqual(window.contentLayoutRect.size, contentSize, "Changing panes must not resize its content")
                XCTAssertEqual(host.frame.size, hostSize, "The scaffold must retain its content frame")
            }

            try assertState("engine", title: "Engine", back: false, forward: false)
            selection.value = "missing"
            settle(window: window, host: host)
            try assertState("engine", title: "Engine", back: false, forward: false)
            selection.value = nil
            settle(window: window, host: host)
            try assertState("engine", title: "Engine", back: false, forward: false)
            selection.value = "reports"
            settle(window: window, host: host)
            try assertState("reports", title: "Reports", back: true, forward: false)
            try buttons().back.performClick(nil)
            settle(window: window, host: host)
            try assertState("engine", title: "Engine", back: false, forward: true)
            try buttons().forward.performClick(nil)
            settle(window: window, host: host)
            try assertState("reports", title: "Reports", back: true, forward: false)
        }
    }

    func testTrailingControlStaysWithinBoundedRowMeasure() throws {
        let measure = SettingsRowMeasure()
        let row = LumenSettingsRow("Availability", description: "Bundled engine is ready.") {
            Button("Recheck Paths") {}
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: SettingsRowControlFrameKey.self,
                                           value: geometry.frame(in: .named("settingsRow")))
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: "settingsRow")
        .onPreferenceChange(SettingsRowControlFrameKey.self) { value in
            MainActor.assumeIsolated { measure.frame = value }
        }
        try withWindow(row, compact: true) { _, host, _ in
            XCTAssertLessThanOrEqual(measure.frame.maxX, 480.5, "A trailing control must not float to the wide window edge")
            XCTAssertGreaterThan(measure.frame.height, 0)
            print("ROW_MEASURE: control \(measure.frame); host \(host.bounds)")
        }
    }

    func testEngineSampleControlsSharePaneTrailingEdge() throws {
        CatalogSettingsWindowMetrics.engineControlFrames = [:]
        defer { CatalogSettingsWindowMetrics.engineControlFrames = [:] }
        let root = LumenSettingsSidebarView(categories(2))
            .environment(\.measuresCatalogEngineControls, true)
        try withWindow(root, compact: true, size: CGSize(width: 1000, height: 640)) { _, _, _ in
            let frames = CatalogSettingsWindowMetrics.engineControlFrames
            let edges = try ["Check", "Toggle", "Reset"].map { name in
                let frame = try XCTUnwrap(frames[name], "Missing live sample control: \(name)")
                XCTAssertGreaterThan(frame.width, 0)
                return frame.maxX
            }
            XCTAssertLessThanOrEqual(try XCTUnwrap(edges.max()) - XCTUnwrap(edges.min()), 1,
                                     "Check, toggle and Reset must share the pane's trailing edge")
            print("ENGINE_TRAILING_EDGES: Check \(edges[0]), Toggle \(edges[1]), Reset \(edges[2]) pt")
        }
    }

    func testLightSurfacesInBothChromeStyles() throws {
        try assertStock(categoryCount: 2, chrome: .drawn, scheme: .light)
        try assertStock(categoryCount: 2, chrome: .glass, scheme: .light)
    }

    func testStockRootOverridesSettingsPreferenceToolbar() throws {
        try withWindow(LumenSettingsSidebarView(categories(2)), compact: false, sizing: [.minSize, .maxSize], initialStyle: .preference) { window, host, _ in
            XCTAssertEqual(window.toolbarStyle, .unified, "Observed style: \(window.toolbarStyle.rawValue)")
            XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, 480)
            let originalFrame = window.frame
            // Reproduce the real Settings scene overriding the declarative Scene style.
            window.toolbarStyle = .preference
            settle(window: window, host: host)
            XCTAssertEqual(window.toolbarStyle, .unified, "Observed style: \(window.toolbarStyle.rawValue)")
            XCTAssertEqual(window.frame, originalFrame, "Later scene updates must not shrink the window again")
            let height = window.frame.height - window.contentLayoutRect.height
            XCTAssertLessThanOrEqual(height, standardUnifiedBandHeight())
            print("SETTINGS_SCENE_OVERRIDE: style \(window.toolbarStyle.rawValue), band \(height)")
        }
    }

    func testSidebarRemovalScopeInNativeToolbars() throws {
        for scope in RemovalScope.allCases {
            try withWindow(RemovalScopeHost(scope: scope), compact: true) { window, _, _ in
                let identifiers = window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
                let defaults = identifiers.filter { $0.contains("toggleSidebar") }
                print("REMOVAL_SCOPE \(scope): \(identifiers)")
                XCTAssertEqual(defaults.count, scope == .sidebar ? 0 : 1, "Removal must be scoped to the owning sidebar column")
            }
        }
    }

    private func assertStock(categoryCount: Int, chrome: LumenChromeStyle, scheme: ColorScheme = .dark) throws {
        let result = try observe(
            LumenSettingsSidebarView(categories(categoryCount), selection: "engine")
                .lumenChromeStyle(chrome),
            compact: true, scheme: scheme
        )
        print("STOCK \(categoryCount) \(chrome) \(scheme): \(result.description)")
        XCTAssertTrue(result.violations.isEmpty,
                      "\(categoryCount) categories, \(chrome): \(result.violations.map(\.rawValue).sorted()); \(result.description)")
    }

    private func categories(_ count: Int) -> [LumenSettingsCategory] {
        // Exercise the actual public-row Catalog example, not a simplified surrogate pane.
        Array(CatalogSettings.categories.prefix(count))
    }

    private func observe<V: View>(_ view: V, compact: Bool, scheme: ColorScheme = .dark) throws -> Observation {
        try withWindow(view, compact: compact, scheme: scheme) { window, host, store in
            try inspect(window: window, host: host, store: store, scheme: scheme)
        }
    }

    private func withWindow<V: View, Result: Sendable>(_ view: V, compact: Bool, scheme: ColorScheme = .dark, sizing: NSHostingSizingOptions = [], initialStyle: NSWindow.ToolbarStyle? = nil, size: CGSize = CGSize(width: 820, height: 480),
                                            inspect: @MainActor (NSWindow, NSView, LumenThemeStore) throws -> Result) throws -> Result {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: scheme), registry: .core)
        return try LumenThemeStore.withActiveStore(store) {
            try MainActor.assumeIsolated {
                let root = view.lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
                    .lumenMetrics(.standard).preferredColorScheme(scheme)
                    .environment(\.controlActiveState, .active)
                    .environment(\.lumenSettingsSizesWindow, false)
                let host = NSHostingView(rootView: AnyView(root))
                host.sizingOptions = sizing
                host.sceneBridgingOptions = [.toolbars, .title]
                let window = LumenHeadlessHost.window(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                // NSHostingView does not instantiate a SwiftUI Scene. Mirror the public
                // .lumenSettingsScene() scene contract here; all toolbar content remains stock.
                window.toolbarStyle = initialStyle ?? (compact ? .unified : .automatic)
                window.titleVisibility = compact ? .visible : .hidden
                window.contentView = host
                window.setContentSize(size)
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                defer { window.close() }
                settle(window: window, host: host)
                return try inspect(window, host, store)
            }
        }
    }

    private func settle(window: NSWindow, host: NSView) {
        for _ in 0..<20 {
            (host.superview ?? host).layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func inspect(window: NSWindow, host: NSView, store: LumenThemeStore, scheme: ColorScheme) throws -> Observation {
        var result = Observation()
        let contentViews = descendants(host)
        let table = contentViews.compactMap { $0 as? NSTableView }.min {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }
        if table?.effectiveStyle != .sourceList { result.violations.insert(.sourceList) }
        result.details.append("table style: \(String(describing: table?.effectiveStyle.rawValue))")
        if table?.selectionHighlightStyle != NSTableView.SelectionHighlightStyle.none { result.violations.insert(.selectionPalette) }
        result.details.append("native selection fill: \(String(describing: table?.selectionHighlightStyle.rawValue))")

        let frameView = try XCTUnwrap(host.superview, "A live window must have its native frame")
        // cacheDisplay retains the detail-pane pixel check. GPU-backed sidebar pixels are a
        // live-check gap; its actual fill is checked structurally below, with no screen capture.
        let directory = ProcessInfo.processInfo.environment["LUMEN_SETTINGS_CAPTURES_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/settings-captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appending(path: "live-\(UUID().uuidString).png")
        try LumenHeadlessHost.png(of: window).write(to: imageURL)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: imageURL)))
        result.details.append("capture: \(imageURL.path)")
        let split = contentViews.compactMap { $0 as? NSSplitView }
            .first { $0.arrangedSubviews.filter { !$0.isHidden }.count >= 2 }
        if let sidebar = split?.arrangedSubviews.first {
            let sidebarFrame = sidebar.convert(sidebar.bounds, to: frameView)
            let effects = descendants(frameView).compactMap { $0 as? NSVisualEffectView }
            let sidebarEffect = effects.contains { effect in
                let frame = effect.convert(effect.bounds, to: frameView)
                let overlap = frame.intersection(sidebarFrame)
                return !effect.isHiddenOrHasHiddenAncestor && effect.material == .sidebar
                    && overlap.width >= sidebarFrame.width * 0.8
                    && overlap.height >= sidebarFrame.height * 0.8
            }
            // macOS 27's native sidebar glass is composited as a filtered layer rather than
            // an NSVisualEffectView(.sidebar). Reuse the sole capture's layer evidence.
            let filteredSidebar = (LumenHeadlessHost.lastCapture?.filteredLayers ?? []).contains { layer in
                let frame = layer.frameInRoot
                return abs(frame.width - sidebarFrame.width) <= 4
                    && abs(frame.minX - sidebarFrame.minX) <= 4
                    && frame.height >= sidebarFrame.height * 0.8
            }
            let nativeSidebar = sidebarEffect || filteredSidebar
            let opaqueOverride = descendants(sidebar).contains { $0 is LumenSidebarPaletteReportView }
            if !nativeSidebar || opaqueOverride { result.violations.insert(.sidebarMaterial) }
            let descriptions = effects.map {
                "material=\($0.material.rawValue), blending=\($0.blendingMode.rawValue), frame=\($0.convert($0.bounds, to: frameView))"
            }
            result.details.append("native sidebar material=\(nativeSidebar); filtered sidebar=\(filteredSidebar); opaque override=\(opaqueOverride); effects: \(descriptions)")
        } else {
            result.violations.insert(.sidebarMaterial)
            result.details.append("native sidebar material unavailable: no sidebar")
        }

        // The pane's leading page margin is empty ground at each sample height, away from the
        // divider and the trailing scroll indicator. Keep this rendered-color evidence separate
        // from the sidebar's structural evidence.
        if let split, let sidebar = split.arrangedSubviews.first, let detail = split.arrangedSubviews.last {
            let sidebarFrame = sidebar.frame
            let detailFrame = detail.frame
            result.details.append("column frames: sidebar=\(sidebarFrame), detail=\(detailFrame)")
            let panel = store.resolvedColor(.panelBackground, for: scheme == .dark ? .dark : .light)
            var opaqueSamples = 0
            let differences = [0.25, 0.5, 0.75].compactMap { fraction -> Double? in
                let columnPoint = NSPoint(x: sidebarFrame.maxX + LumenMetrics.standard.spacing.s2,
                    y: detailFrame.minY + detailFrame.height * fraction)
                let point = frameView.convert(columnPoint, from: split)
                let x = Int(((point.x - frameView.bounds.minX) / frameView.bounds.width * CGFloat(bitmap.pixelsWide)).rounded(.down))
                let yInFrame = frameView.isFlipped ? point.y - frameView.bounds.minY : frameView.bounds.maxY - point.y
                let y = Int((yInFrame / frameView.bounds.height * CGFloat(bitmap.pixelsHigh)).rounded(.down))
                guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh,
                      let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    result.details.append("detail sample: column=\(columnPoint), frame=\(point), pixel=(\(x),\(y)), RGBA=unavailable")
                    return nil
                }
                result.details.append("detail sample: column=\(columnPoint), frame=\(point), pixel=(\(x),\(y)), RGBA=(\(color.redComponent),\(color.greenComponent),\(color.blueComponent),\(color.alphaComponent))")
                if color.alphaComponent >= 0.98 { opaqueSamples += 1 }
                return max(abs(Double(color.redComponent) - panel.red),
                           abs(Double(color.greenComponent) - panel.green),
                           abs(Double(color.blueComponent) - panel.blue))
            }
            if differences.count != 3 || opaqueSamples != 3 || differences.contains(where: { $0 > 0.045 }) {
                result.violations.insert(.detailPalette)
            }
            result.details.append("detail RGB distances: \(differences); opaque samples: \(opaqueSamples)")
        } else {
            result.violations.insert(.detailPalette)
            result.details.append("detail pixel samples unavailable")
        }

        let items = window.toolbar?.items ?? []
        let sidebarItem = items.first { $0.itemIdentifier.rawValue.contains("lumen.settings.sidebar") }
        let historyItem = items.first { $0.itemIdentifier.rawValue.contains("lumen.settings.history") }
        let historyControls = historyItem.map(controlFrames) ?? []
        let sidebarControls = sidebarItem.map(controlFrames) ?? []
        let toggleItems = items.filter {
            $0.itemIdentifier.rawValue.contains("toggleSidebar") ||
            $0.itemIdentifier.rawValue.contains("lumen.settings.sidebar")
        }
        let duplicateToggle = toggleItems.count != 1
        if duplicateToggle { result.violations.insert(.toggleCount) }
        let band = window.frame.height - window.contentLayoutRect.height
        let standardBand = standardUnifiedBandHeight()
        if band > standardBand + 0.5 { result.violations.insert(.bandHeight) }
        result.details.append("toggle count: \(toggleItems.count); band: \(band) pt; unified standard: \(standardBand) pt; content: \(window.contentLayoutRect.size)")
        let historyPresent = historyItem?.isNavigational == true && historyControls.count >= 2
        if !historyPresent { result.violations.insert(.historyGroup) }
        if let toggle = sidebarControls.first, historyControls.count >= 2,
           toggle.height > 0, !duplicateToggle,
           historyControls.allSatisfy({ abs($0.height - toggle.height) <= 0.5 }) {
            // All three rendered controls share the same native height.
        } else {
            result.violations.insert(.controlHeights)
        }
        result.details.append("toolbar: \(items.map { $0.itemIdentifier.rawValue })")
        result.details.append("sidebar controls: \(sidebarControls); history controls: \(historyControls)")
        result.details.append("invalid sidebar-toggle count: \(duplicateToggle)")

        // A navigation title is permitted once beside the navigation group. It is never a
        // principal/standalone category label, and the pane header is outside the toolbar.
        let titleItems = items.filter { item in
            item.label == "Engine" || item.title == "Engine" ||
            item.view.map { descendants($0).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Engine" } } == true
        }
        let settingsTitle = items.contains { item in
            item.label == "Settings" || item.title == "Settings" ||
            item.view.map { descendants($0).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Settings" } } == true
        }
        let labeledButtons = items.flatMap { $0.view.map(descendants) ?? [] }.compactMap { $0 as? NSButton }
            .contains { $0.imagePosition != .imageOnly && ["Sidebar", "Back", "Forward"].contains($0.title) }
        let extraTitleItems = titleItems.filter { !$0.itemIdentifier.rawValue.localizedCaseInsensitiveContains("title") }
        if settingsTitle || labeledButtons || window.title != "Engine" || !historyPresent || titleItems.count > 1 || !extraTitleItems.isEmpty {
            result.violations.insert(.navigationTitle)
        }
        result.details.append("window title: \(window.title); title items: \(titleItems.map { $0.itemIdentifier.rawValue })")
        if !result.violations.isEmpty,
           let path = ProcessInfo.processInfo.environment["LUMEN_SETTINGS_DIAGNOSTICS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let imageURL = directory.appendingPathComponent("settings-\(UUID().uuidString).png")
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: imageURL)
            result.details.append("diagnostic PNG: \(imageURL.path)")
        }
        return result
    }

    private static var measuredUnifiedBand: CGFloat?

    private func standardUnifiedBandHeight() -> CGFloat {
        if let measured = Self.measuredUnifiedBand { return measured }
        let root = Text("Standard window").frame(width: 400, height: 200)
            .toolbar { ToolbarItem(placement: .navigation) { Button("Back", systemImage: "chevron.backward") {} } }
        let host = NSHostingView(rootView: root)
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentView = host
        settle(window: window, host: host)
        let height = window.frame.height - window.contentLayoutRect.height
        Self.measuredUnifiedBand = height
        window.close()
        return height
    }

    /// Native toolbar controls, not symbol ink bounds. A ControlGroup may bridge as either
    /// individual buttons or a segmented control; both expose the same rendered segment height.
    private func controlFrames(_ item: NSToolbarItem) -> [CGRect] {
        if let group = item as? NSToolbarItemGroup, !group.subitems.isEmpty {
            let frames = group.subitems.flatMap(controlFrames)
            if !frames.isEmpty { return frames }
        }
        guard let root = item.view else { return [] }
        let controls = descendants(root).compactMap { $0 as? NSControl }.filter { !$0.isHidden }
        let segments = controls.compactMap { $0 as? NSSegmentedControl }
        if let segmented = segments.first {
            let frame = segmented.convert(segmented.bounds, to: nil)
            return Array(repeating: frame, count: segmented.segmentCount)
        }
        let buttons = controls.compactMap { $0 as? NSButton }
        return buttons.map { $0.convert($0.bounds, to: nil) }
    }

    private func descendants(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }
}

@MainActor
private final class SettingsSelectionBox: ObservableObject {
    @Published var value: String? = "engine"
}

private struct BoundSettingsHost: View {
    let categories: [LumenSettingsCategory]
    @ObservedObject var selection: SettingsSelectionBox

    var body: some View {
        LumenSettingsSidebarView(categories, selection: $selection.value)
    }
}

/// This fixture intentionally omits the stock scaffold. Explicit plain/system-grey styling makes
/// the unthemed list appearance deterministic across macOS's changing automatic List defaults.
private struct BareSettingsHost: View {
    let categories: [LumenSettingsCategory]
    @State private var selection: String? = "engine"
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(categories, selection: $selection) { category in
                Label(category.title, systemImage: category.systemImage).tag(category.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            categories[0].content().navigationTitle(categories[0].title)
        }
    }
}

private enum RemovalScope: CaseIterable { case none, split, sidebar }

private struct RemovalScopeHost: View {
    let scope: RemovalScope
    var body: some View {
        NavigationSplitView {
            List { Text("Engine") }
                .toolbar(removing: scope == .sidebar ? .sidebarToggle : nil)
        } detail: {
            Text("Engine details")
        }
        .toolbar(removing: scope == .split ? .sidebarToggle : nil)
    }
}

@MainActor private final class SettingsRowMeasure { var frame: CGRect = .zero }
private struct SettingsRowControlFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // ViewThatFits also evaluates the fallback; its unplaced zero frame must not erase
        // the visible candidate's actual control frame.
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}
