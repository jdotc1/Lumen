import AppKit
import LumenTokens
@_spi(LumenStyleChecks) @testable import LumenUI
import SwiftUI
import XCTest
@testable import LumenConformance

@MainActor
final class LumenTabStyleTests: XCTestCase {
    func testRejectsSquareSelectionAndHoverAndSeparateAccentBar() {
        let entries: Set<LumenTabChromeEntry> = [
            .init(strip: "square", selectedRadius: 0, hoverRadius: 0, separateAccentBar: true),
            .init(strip: "circular", selectedRadius: 6, hoverRadius: 6, continuousCorners: false),
        ]
        XCTAssertEqual(TabStyleCheck.findings(entries, requiring: []).map(\.description), [
            "layout · circular: tab indicators must use continuous corners",
            "layout · square: tab hover indicator must be rounded",
            "layout · square: tab selection indicator must be rounded",
            "layout · square: tab selection must not use a separate accent bar",
        ])
    }

    func testRejectsNonfiniteGeometryAndMissingRequiredStrip() {
        let entries: Set<LumenTabChromeEntry> = [
            .init(strip: "invalid", selectedRadius: .infinity, hoverRadius: -.infinity),
        ]
        let findings = TabStyleCheck.findings(entries, requiring: ["missing"])
        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(findings.last?.message, "tab strip did not report its indicator geometry")
    }

    func testMissingSubjectFailsAndCheckIdentityIsStable() {
        let check = LumenConformance.tabStyle(requiring: ["document"])
        XCTAssertEqual(check.id, "lumen.tabStyle")
        XCTAssertEqual(check.run(in: .init()).map(\.message), ["requires a subject"])
    }

    func testRegistryIsScopedToTheHostedTreeAndReportsInvalidGeometry() {
        let size = CGSize(width: 300, height: 100)
        let findings = LumenConformance.tabStyle(sizes: [size], requiring: ["fixture"]) {
            Rectangle().fill(.gray).frame(width: 100, height: 30)
                .lumenTabChromeReport(strip: "fixture", selectedRadius: 0, hoverRadius: 0,
                                      separateAccentBar: true)
        }
        XCTAssertEqual(findings.count, 3)
        XCTAssertTrue(findings.allSatisfy { $0.subject == "fixture at 300×100" })
        let next = LumenConformance.tabStyle(sizes: [size], requiring: ["fixture"]) { Color.clear }
        XCTAssertEqual(next.map(\.message), ["tab strip did not report its indicator geometry"])
    }

    func testDocumentPanelContentAndOverviewReportSharedChrome() {
        let context = LumenCheckContext(sizes: [CGSize(width: 800, height: 500)], variants: [
            .init(themeID: LumenThemes.standardID, colorScheme: .light),
            .init(themeID: LumenThemes.standardID, colorScheme: .dark),
        ], subject: ("Tab strips", AnyView(VStack(spacing: 12) {
            LumenDocumentTabBar([
                .init(id: "a", title: "Edited.swift", systemImage: "doc", isEdited: true),
                .init(id: "b", title: "Other.swift", systemImage: "doc"),
            ], selection: .constant("a"))
            LumenPanelTabs(selection: .constant("debug"), tabs: [
                .init(id: "debug", title: "Debug Console", systemImage: "ladybug"),
                .init(id: "extension", title: "Extension Console", systemImage: "puzzlepiece"),
            ])
            LumenSidebarSwitcher(selection: .constant("files"), items: [
                .init(id: "files", title: "Files", systemImage: "folder"),
                .init(id: "search", title: "Search", systemImage: "magnifyingglass"),
            ])
            LumenContentTabBar {
                LumenModeSwitcher(selection: .constant("Source"), options: ["Source", "Preview"],
                                  style: .underline, title: { $0 })
            }
            LumenTabOverview([
                LumenOverviewTab(id: "a", title: "Edited.swift", systemImage: "doc") { Color.gray },
                LumenOverviewTab(id: "b", title: "Other.swift", systemImage: "doc") { Color.gray },
            ], selection: "a", thumbnailWidth: 120, onSelect: { _ in })
        }.environment(\.lumenRendersOffscreen, true))))
        XCTAssertEqual(LumenConformance.run([
            LumenConformance.tabStyle(requiring: ["document", "panel", "sidebar", "content", "overview"]),
        ], in: [context]), [])
    }

    func testAllModeStylesAndSegmentedControlReportSharedChrome() {
        for style in LumenModeSwitcherStyle.allCases {
            XCTAssertEqual(LumenConformance.tabStyle(sizes: [CGSize(width: 500, height: 100)], requiring: ["mode"]) {
                LumenModeSwitcher(selection: .constant("Source"), options: ["Source", "Preview"],
                                  style: style, title: { $0 }, systemImage: { _ in "doc" })
                    .environment(\.lumenRendersOffscreen, true)
            }, [], "\(style)")
        }
        XCTAssertEqual(LumenConformance.tabStyle(sizes: [CGSize(width: 500, height: 100)], requiring: ["segmented"]) {
            LumenSegmentedControl(selection: .constant("Source"), options: ["Source", "Preview"], title: { $0 })
        }, [])
    }

    func testConformanceHostNeverBecomesVisibleOrKey() {
        let (window, _) = LumenConformance.offscreenWindow(AnyView(Color.clear), size: CGSize(width: 100, height: 100))
        defer { window.close() }
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(window.isMainWindow)
        XCTAssertLessThan(window.frame.maxX, 0)
        XCTAssertLessThan(window.frame.maxY, 0)
    }

    func testSettingsAndPaletteTabStripsReportSharedChrome() {
        XCTAssertEqual(LumenConformance.tabStyle(sizes: [CGSize(width: 600, height: 100)], requiring: ["outline-depth"]) {
            LumenOutlineControls(mode: .constant(.tree), depth: .constant(2), sortsAlphabetically: .constant(false))
        }, [])

        XCTAssertEqual(LumenConformance.tabStyle(sizes: [CGSize(width: 600, height: 160)], requiring: ["tabbed-box"]) {
            LumenTabbedBox(selection: .constant("General"), tabs: ["General", "Editor"], title: { $0 }) { Text($0) }
        }, [])
        XCTAssertEqual(LumenConformance.tabStyle(sizes: [CGSize(width: 600, height: 300)], requiring: ["palette-scope"]) {
            LumenCommandPalette([], scopes: [
                .init("All", prefix: nil), .init("Files", prefix: "/"),
            ], query: "", recents: [], highlighted: nil)
                .environment(\.lumenRendersOffscreen, true)
        }, [])
    }
}
