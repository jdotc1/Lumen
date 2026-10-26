import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenPolishWorkspaceSizingTests: XCTestCase {
    func testRecentIdentityAndDateGrowAtNarrowWidth() throws {
        for scale in [1.0, 1.3] {
            let row = LumenWelcomeRecentRow(item: LumenRecentItem(
                title: "Research workspace containing longitudinal imaging and configuration reports",
                detail: "~/Projects/Research/Longitudinal imaging/Configuration and analysis reports",
                date: Date(timeIntervalSince1970: 0)))
            let narrow = try fittedSize(row, width: 220, scale: scale)
            let wide = try fittedSize(row, width: 1000, scale: scale)
            XCTAssertLessThanOrEqual(narrow.width, 221)
            XCTAssertGreaterThan(narrow.height, wide.height + 20, "Recent identity and date must reflow at scale \(scale)")
        }
    }

    func testBreadcrumbActivityWrapsInFinalFallback() throws {
        for scale in [1.0, 1.3] {
            let row = LumenToolbarBreadcrumb(["Workspace", "Sources"], systemImage: "folder",
                activity: .working("Indexing every configuration and dependency in the research workspace", progress: 0.5),
                onCancel: {})
            let narrow = try fittedSize(row, width: 240, scale: scale)
            let wide = try fittedSize(row, width: 1000, scale: scale)
            XCTAssertLessThanOrEqual(narrow.width, 241)
            XCTAssertGreaterThan(narrow.height, wide.height + 10)
        }
    }

    func testSidebarHeaderWrapsAndScrollHasBottomInset() throws {
        for scale in [1.0, 1.3] {
            let title = "Repository configuration and analysis resources requiring review"
            let sidebar = LumenStackedSidebar([
                LumenStackedPane(id: "resources", title: title, systemImage: "folder", count: 12) {
                    Color.clear.frame(height: 1000)
                }
            ], collapsed: .constant([]))
            try withHost(sidebar, size: CGSize(width: 220, height: 500), scale: scale) { host in
                let scroll = try XCTUnwrap(scrollViews(in: host).first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThanOrEqual(document.bounds.height, 1000 + LumenMetrics.standard.spacing.s2 - 1,
                                            "The final content needs breathing room before the clipped edge")
                XCTAssertLessThan(scroll.contentView.bounds.height, 500 - LumenMetrics.resolving(nil, textScale: scale).layout.paneHeaderHeight - 10,
                                  "Wrapped headers must reserve their measured height before allocating pane content")
                XCTAssertLessThanOrEqual(scroll.convert(scroll.bounds, to: host).maxX, 221)
            }
        }
    }

    func testSelectionIdentityAndStatisticsReflow() throws {
        for scale in [1.0, 1.3] {
            let card = LumenInspectorSummary(kind: "Function", title: "Analysis configuration for longitudinal research",
                stats: [LumenStat("Successfully inspected resources", value: "124,500"),
                        LumenStat("Resources waiting for review", value: "230,450")])
            let narrow = try fittedSize(card, width: 240, scale: scale)
            let wide = try fittedSize(card, width: 1000, scale: scale)
            XCTAssertLessThanOrEqual(narrow.width, 241)
            XCTAssertGreaterThan(narrow.height, wide.height + 40)
        }
    }

    func testReferenceKindWrapsWithoutConsumingLocation() throws {
        for scale in [1.0, 1.3] {
            let row = LumenReferenceRow("analysis_configuration", kind: "Indirect reference through the research workspace dependency graph") {}
            let narrow = try fittedSize(row, width: 220, scale: scale)
            let wide = try fittedSize(row, width: 1000, scale: scale)
            XCTAssertLessThanOrEqual(narrow.width, 221)
            XCTAssertGreaterThan(narrow.height, wide.height + 15)
        }
    }

    private func fittedSize(_ view: some View, width: CGFloat, scale: Double) throws -> CGSize {
        let controller = NSHostingController(rootView: view
            .lumenMetrics(.resolving(nil, textScale: scale)).lumenRendersOffscreen())
        let size = controller.sizeThatFits(in: CGSize(width: width, height: 10_000))
        try withHost(view, size: size, scale: scale) { _ in }
        return size
    }

    private func withHost(_ view: some View, size: CGSize, scale: Double,
                          inspect: (NSView) throws -> Void) throws {
        let host = NSHostingView(rootView: view
            .lumenMetrics(.resolving(nil, textScale: scale)).lumenRendersOffscreen())
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        try inspect(host)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }
}
