import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI
import LumenConformance

/// PRINCIPLES §11 and Docs/GLASS.md: the chrome style's defaults and resolution, and the
/// `backlight` and `surfaceSteps` checks on glass navigation surfaces.
@MainActor
final class LumenChromeStyleTests: XCTestCase {
    func testDrawnIsTheDefault() {
        XCTAssertEqual(LumenStoreConfiguration(appName: "Test").chromeStyle, .drawn)
        XCTAssertEqual(LumenStoreConfiguration(appName: "Test", chromeStyle: .glass).chromeStyle, .glass)
        XCTAssertEqual(LumenChromeStyle.resolve(nil), .drawn)
        XCTAssertEqual(LumenChromeStyle.resolve("frosted"), .drawn)
        XCTAssertEqual(LumenChromeStyle.resolve("glass"), .glass)
    }

    func testGlassDegradesToDrawn() {
        XCTAssertEqual(LumenChromeStyle.resolved(.drawn, reduceTransparency: false, rendersOffscreen: false), .drawn)
        XCTAssertEqual(LumenChromeStyle.resolved(.glass, reduceTransparency: true, rendersOffscreen: false), .drawn)
        XCTAssertEqual(LumenChromeStyle.resolved(.glass, reduceTransparency: false, rendersOffscreen: true), .drawn)
        XCTAssertEqual(LumenChromeStyle.resolved(.glass, reduceTransparency: false, rendersOffscreen: false),
                       .glass)
    }

    private static let commands: [LumenCommand] = [
        LumenCommand(id: "go.overview", "Go to Overview", category: "Go", systemImage: "sparkles", hue: .hueViolet) {},
        LumenCommand(id: "view.panel", "Show Panel", category: "View", systemImage: "rectangle.bottomthird.inset.filled",
                     hue: .hueBlue, shortcut: KeyboardShortcut("j", modifiers: [.command])) {},
        LumenCommand(id: "task.build", "Build", category: "Tasks", systemImage: "hammer.fill", hue: .hueOrange,
                     shortcut: KeyboardShortcut("b", modifiers: [.command])) {},
    ]

    /// The palette at its own width, so its outer edge isn't scanned as a step.
    private func palette(_ style: LumenChromeStyle) -> some View {
        LumenCommandPalette(Self.commands, query: "", recents: [], highlighted: "view.panel")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .lumenChromeStyle(style)
    }

    private func topBar(_ style: LumenChromeStyle) -> some View {
        HStack(spacing: 8) {
            LumenToolbarIdentity("libsystem_kernel.dylib", subtitle: "arm64e · Mach-O dylib", systemImage: "lumen.binaryFile", hue: .hueOrange)
            LumenToolbarStatus(.working("Analyzing", progress: 0.42), width: 260)
            Spacer(minLength: 8)
            LumenPanelToggles(leading: .constant(true), bottom: .constant(true), trailing: .constant(true), registersShortcuts: false)
        }
        .environment(\.lumenToolbarCompact, true)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumenTitlebarBackground())
        .lumenChromeStyle(style)
    }

    func testGlassSurfacesKeepTheirBacklights() {
        XCTAssertEqual(LumenConformance.backlight(sizes: [CGSize(width: 580, height: 420)]) { palette(.glass) }.map(\.description), [])
        XCTAssertEqual(LumenConformance.backlight(sizes: [CGSize(width: 1000, height: 40)]) { topBar(.glass) }.map(\.description), [])
    }

    /// No surface steps in `.glass`. The top bar is scanned in `.glass` as drawn. The palette is
    /// scanned on its opaque fallback (`.drawn`), the ground GLASS.md rule 3 measures against: the
    /// window capture draws no system glass, so a `.glass` scan would see its rows on the bare
    /// window background and report steps no one sees (two short ones at the keycaps and footer).
    func testGlassSurfacesHaveNoSurfaceSteps() throws {
        for variant in [LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: .dark),
                        LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: .light)] {
            XCTAssertEqual(LumenConformance.surfaceSteps(sizes: [CGSize(width: 1000, height: 40)], variant: variant) { topBar(.glass) }
                .map(\.description), [], "top bar @ \(variant.label)")
            XCTAssertEqual(LumenConformance.surfaceSteps(sizes: [CGSize(width: 580, height: 420)], variant: variant) { palette(.drawn) }
                .map(\.description), [], "command palette fallback @ \(variant.label)")
        }
    }
}
