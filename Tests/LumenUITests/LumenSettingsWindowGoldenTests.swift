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
            try LumenFilterConfinedGolden.verify(actual, at: url)
        }
    }

    private func check(categoryCount: Int, chrome: LumenChromeStyle, scheme: ColorScheme = .dark) throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let name = "settings-window-\(categoryCount)-\(chrome.rawValue)@standard-\(scheme == .dark ? "dark" : "light").png"
        let actual = try render(categoryCount: categoryCount, chrome: chrome, scheme: scheme)
        let url = Self.goldens.appending(path: name)
        try LumenFilterConfinedGolden.verify(actual, at: url)
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
