import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Whole-window subjects: the native title bar, toolbar, sidebar and pane are recorded together.
/// A borderless snapshot or scaled Catalog tile cannot accept a window-level component.
/// The RTL subject runs itself in a right-to-left child process, so a normal filtered run covers it.
/// Record only the new RTL subject with:
/// `LUMEN_RECORD_SNAPSHOTS=1 swift test --filter LumenSettingsWindowGoldenTests.testTwoCategoriesDrawnLightRTL`
/// Recording fails deliberately, as in `LumenSnapshot.verify`; review the PNGs without
/// repeating an unchanged check solely to turn a recording run green.
@MainActor
final class LumenSettingsWindowGoldenTests: XCTestCase {
    private static let goldens = ProcessInfo.processInfo.environment["LUMEN_GOLDENS_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens", directoryHint: .isDirectory)

    func testFiveCategoriesDrawn() throws { try check(categoryCount: 5, chrome: .drawn) }
    func testTwoCategoriesDrawn() throws { try check(categoryCount: 2, chrome: .drawn) }
    func testFiveCategoriesGlass() throws { try check(categoryCount: 5, chrome: .glass) }
    func testTwoCategoriesGlass() throws { try check(categoryCount: 2, chrome: .glass) }

    func testTwoCategoriesDrawnLight() throws { try check(categoryCount: 2, chrome: .drawn, scheme: .light) }
    func testTwoCategoriesGlassLight() throws { try check(categoryCount: 2, chrome: .glass, scheme: .light) }

    func testTwoCategoriesDrawnLightRTL() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let url = Self.goldens.appending(path: "settings-window-2-drawn-rtl@standard-light.png")
        let recording = ProcessInfo.processInfo.environment["LUMEN_RECORD_SNAPSHOTS"] == "1"
        if recording && FileManager.default.fileExists(atPath: url.path) {
            XCTFail("The RTL golden already exists; recording cannot replace it")
            return
        }
        // AppKit takes its layout direction from the process when NSApplication is created, as it
        // does for an app running in a right-to-left language, and it cannot change afterwards.
        // So the assertions run in a child xctest process launched right-to-left, and the child
        // must execute them (a skip counts as a failure here).
        guard ProcessInfo.processInfo.environment["LUMEN_RTL_CHILD"] == "1" else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xctest", "-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES",
                                 "-XCTest", "LumenSettingsWindowGoldenTests/testTwoCategoriesDrawnLightRTL",
                                 Bundle(for: Self.self).bundlePath]
            var childEnv = ProcessInfo.processInfo.environment
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
        try XCTSkipIf(NSApp != nil && NSApp.userInterfaceLayoutDirection != .rightToLeft,
                      "AppKit is not right-to-left in this child process")
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["NSForceRightToLeftWritingDirection"] = "YES"
        arguments["AppleTextDirection"] = "YES"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let actual = try render(categoryCount: 2, chrome: .drawn, scheme: .light, rightToLeft: true)
        if recording {
            try actual.write(to: url, options: .withoutOverwriting)
            XCTFail("Recorded new RTL Settings golden; review the image without repeating this run")
        } else {
            try verifyWindow(actual, at: url, categoryCount: 2, rightToLeft: true)
        }
    }

    private func check(categoryCount: Int, chrome: LumenChromeStyle, scheme: ColorScheme = .dark) throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let name = "settings-window-\(categoryCount)-\(chrome.rawValue)@standard-\(scheme == .dark ? "dark" : "light").png"
        let actual = try render(categoryCount: categoryCount, chrome: chrome, scheme: scheme)
        let url = Self.goldens.appending(path: name)
        try verifyWindow(actual, at: url, categoryCount: categoryCount, rightToLeft: false)
    }

    /// The whole-window comparison masks the sidebar column and the sidebar is checked structurally.
    /// `cacheDisplay` draws the GPU-composited sidebar blank white, so its pixels carry no information.
    private func verifyWindow(_ actual: Data, at url: URL, categoryCount: Int, rightToLeft: Bool) throws {
        let sidebar = try XCTUnwrap(Self.sidebarObservation, "The sidebar must be observed in the view tree")
        let scale = try XCTUnwrap(LumenHeadlessHost.lastCapture).backingScale
        let column = sidebar.column
        let mask = CGRect(x: column.x * scale, y: column.y * scale, width: column.width * scale, height: column.height * scale)
        try LumenFilterConfinedGolden.verify(actual, at: url, maskingPixels: mask)
        try verifySidebar(sidebar, windowWidth: sidebar.windowWidth, categoryCount: categoryCount, rightToLeft: rightToLeft,
                          golden: url.deletingPathExtension().lastPathComponent.replacingOccurrences(
                            of: "settings-window-", with: "settings-window-sidebar-"))
    }

    // MARK: Sidebar structure

    /// Frames are points, top-left origin, relative to the whole-window frame view, rounded to 0.01.
    struct SidebarObservation: Codable, Equatable {
        struct Rect: Codable, Equatable { var x, y, width, height: Double }
        struct Row: Codable, Equatable { var index: Int; var frame: Rect; var cell: Rect?; var selected: Bool }
        var windowWidth: Double
        var column: Rect
        var search: Rect?
        var rows: [Row]
    }
    private static var sidebarObservation: SidebarObservation?

    private static func observeSidebar(host: NSView, frameView: NSView) throws -> SidebarObservation {
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func name(_ view: NSView) -> String { String(describing: type(of: view)) }
        func rect(_ bounds: CGRect, in view: NSView) -> SidebarObservation.Rect {
            let r = frameView.convert(bounds, from: view)
            let y = frameView.isFlipped ? r.minY - frameView.bounds.minY : frameView.bounds.maxY - r.maxY
            func q(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
            return .init(x: q(r.minX - frameView.bounds.minX), y: q(y), width: q(r.width), height: q(r.height))
        }
        let all = views(host)
        let outline = try XCTUnwrap(all.first { name($0) == "SwiftUIOutlineListView" } as? NSTableView,
                                    "The settings sidebar must contain its outline list")
        let wrapper = try XCTUnwrap(sequence(first: outline as NSView, next: { $0.superview })
            .first { name($0) == "_NSSplitViewItemViewWrapper" }, "The sidebar column wrapper must exist")
        let rows = (0..<outline.numberOfRows).map { row -> SidebarObservation.Row in
            let rowView = outline.rowView(atRow: row, makeIfNecessary: false)
            let cell = rowView.flatMap { views($0).first { name($0) == "ListTableCellView" } }
            return .init(index: row, frame: rect(outline.rect(ofRow: row), in: outline),
                         cell: cell.map { rect($0.bounds, in: $0) }, selected: outline.selectedRowIndexes.contains(row))
        }
        return .init(windowWidth: Double(frameView.bounds.width), column: rect(wrapper.bounds, in: wrapper),
                     search: all.first { name($0) == "AppKitSearchField" }.map { rect($0.bounds, in: $0) }, rows: rows)
    }

    private func verifySidebar(_ sidebar: SidebarObservation, windowWidth: Double, categoryCount: Int,
                               rightToLeft: Bool, golden: String) throws {
        // Invariants that hold with no golden at all.
        XCTAssertEqual(sidebar.rows.count, categoryCount, "One sidebar row per category")
        XCTAssertEqual(sidebar.rows.map(\.selected), (0..<categoryCount).map { $0 == 0 }, "Only the first category is selected")
        XCTAssertEqual(sidebar.column.width, 220, accuracy: 0.5, "The sidebar column keeps its ideal width")
        XCTAssertEqual(sidebar.column.height, 640, accuracy: 0.5)
        if rightToLeft {
            XCTAssertEqual(sidebar.column.x + sidebar.column.width, windowWidth, accuracy: 0.5, "The RTL sidebar is on the trailing side")
        } else {
            XCTAssertEqual(sidebar.column.x, 0, accuracy: 0.5, "The sidebar is on the leading side")
        }
        let minHeight = Double(LumenMetrics.standard.layout.settingsRowHeight)
        for (index, row) in sidebar.rows.enumerated() {
            XCTAssertGreaterThanOrEqual(row.frame.height, minHeight - 0.5, "Row \(index) meets the settings row height")
            XCTAssertEqual(row.frame.x, sidebar.column.x, accuracy: 0.5, "Row \(index) spans the column")
            XCTAssertEqual(row.frame.width, sidebar.column.width, accuracy: 0.5)
            XCTAssertNotNil(row.cell, "Row \(index) draws its label cell")
            if index > 0 {
                XCTAssertEqual(row.frame.y, sidebar.rows[index - 1].frame.y + sidebar.rows[index - 1].frame.height, accuracy: 0.5,
                               "Rows are contiguous")
            }
        }
        let search = try XCTUnwrap(sidebar.search, "The sidebar search field must exist")
        XCTAssertLessThan(search.y, try XCTUnwrap(sidebar.rows.first).frame.y, "Search sits above the rows")
        // Structural golden of the same facts, recorded with LUMEN_RECORD_SIDEBAR=1 (never overwrites).
        let url = Self.goldens.appending(path: golden + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if !FileManager.default.fileExists(atPath: url.path), ProcessInfo.processInfo.environment["LUMEN_RECORD_SIDEBAR"] == "1" {
            try encoder.encode(sidebar).write(to: url, options: .withoutOverwriting)
            print("RECORDED SIDEBAR STRUCTURE: \(url.lastPathComponent)")
            return
        }
        let expected = try JSONDecoder().decode(SidebarObservation.self, from: Data(contentsOf: url))
        XCTAssertEqual(sidebar, expected, "\(golden): sidebar structure changed")
    }

    private func render(categoryCount: Int, chrome: LumenChromeStyle, scheme: ColorScheme,
                        rightToLeft: Bool = false) throws -> Data {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: scheme), registry: .core)
        return try LumenThemeStore.withActiveStore(store) {
            try MainActor.assumeIsolated {
                let size = CGSize(width: LumenSettingsSidebarView.windowIdealWidth, height: 640)
                let root = LumenSettingsSidebarView(Array(Self.categories.prefix(categoryCount)))
                    .lumenPaletteRoot(store: store)
                    .lumenDensityRoot(store: store)
                    .lumenMetrics(.standard)
                    .lumenChromeStyle(chrome)
                    .environment(\.colorScheme, scheme)
                    .environment(\.displayScale, 2)
                    .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)
                    .environment(\.lumenSettingsSizesWindow, false)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                    .tint(store.resolvedPalette()[.accent])
                let host = NSHostingView(rootView: root)
                host.sizingOptions = [.minSize, .maxSize]
                host.sceneBridgingOptions = [.toolbars, .title]
                let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                // AppKit equivalents of `.lumenSettingsScene()`. The Catalog's four launch
                // screenshots separately exercise the actual SwiftUI Settings scene helper.
                window.titleVisibility = .visible
                window.toolbarStyle = .unified
                window.contentView = host
                window.setContentSize(size)
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                defer { window.close() }
                for _ in 0..<20 {
                    (host.superview ?? host).layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                }
                let frameView = try XCTUnwrap(host.superview, "The whole window frame must be captured")
                XCTAssertNotNil(window.toolbar, "A settings golden must include its native toolbar")
                XCTAssertEqual(window.title, "Engine")
                if rightToLeft {
                    XCTAssertEqual(NSApp.userInterfaceLayoutDirection, .rightToLeft, "AppKit must be right-to-left")
                }
                XCTAssertGreaterThan(frameView.bounds.height, window.contentLayoutRect.height,
                                     "The capture must include chrome above the content")
                // Capture the offscreen frame view. A material difference is a golden failure,
                // never permission to show the window or replace the expected image.
                let directory = ProcessInfo.processInfo.environment["LUMEN_CAPTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.goldens.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appending(path: ".build/settings-captures")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appending(path: "golden-\(UUID().uuidString).png")
                try LumenHeadlessHost.png(of: window).write(to: url)
                return try Data(contentsOf: url)
            }
        }
    }

    /// Deterministic settings, with no application preferences, runtime state or network content.
    /// The first two categories reproduce the sparse Engine/Reports shape that exposed the gap.
    private static var categories: [LumenSettingsCategory] {
        [
            LumenSettingsCategory(id: "engine", title: "Engine", systemImage: "cpu", hue: .hueViolet) {
                LumenSettingsPane("Engine", systemImage: "cpu", hue: .hueViolet,
                                  summary: "The local runtime used to analyze your files.", style: .rich) {
                    LumenFormSection("Local runtime") {
                        LumenSettingsGroup {
                            LumenSettingsRow("Bundled runtime", description: "Ready to analyze files on this Mac.") {
                                Button("Check") {}
                            }
                            LumenSettingsRow("Use external runtime", description: "Choose a runtime for development.") {
                                Toggle("Use external runtime", isOn: .constant(false)).toggleStyle(.switch)
                            }
                            LumenFormRow("Runtime executable") {
                                VStack(alignment: .leading, spacing: LumenMetrics.standard.spacing.s3) {
                                    LumenTextField("Bundled runtime", text: .constant(""), monospaced: true)
                                    HStack(spacing: LumenMetrics.standard.spacing.s3) {
                                        Spacer()
                                        Button("Choose…") {}
                                        Button("Reset") {}
                                    }
                                }
                            }
                            Text("The bundled runtime works offline. An external runtime is used only when enabled.")
                                .font(LumenMetrics.standard.typography.caption)
                                .foregroundStyle(.lumen(.fgTertiary))
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("Runtime details") {
                                Text("Analysis runs locally on this Mac.")
                            }
                        }
                    }
                }
            },
            LumenSettingsCategory(id: "reports", title: "Reports", systemImage: "doc.text.fill", hue: .hueBlue) {
                LumenSettingsPane("Reports", systemImage: "doc.text.fill", hue: .hueBlue,
                                  summary: "Choose what appears in exported reports.") {
                    Toggle("Include summaries", isOn: .constant(true))
                }
            },
            LumenSettingsCategory(id: "appearance", title: "Appearance", systemImage: "paintpalette.fill", hue: .huePink) {
                LumenSettingsPane("Appearance", systemImage: "paintpalette.fill", hue: .huePink) { Text("Follow the system appearance") }
            },
            LumenSettingsCategory(id: "shortcuts", title: "Shortcuts", systemImage: "command", hue: .hueTeal) {
                LumenSettingsPane("Shortcuts", systemImage: "command", hue: .hueTeal) { Text("Use standard keyboard shortcuts") }
            },
            LumenSettingsCategory(id: "updates", title: "Updates", systemImage: "arrow.down.circle.fill", hue: .hueOrange) {
                LumenSettingsPane("Updates", systemImage: "arrow.down.circle.fill", hue: .hueOrange) {
                    Toggle("Check for updates", isOn: .constant(true))
                }
            },
        ]
    }
}
