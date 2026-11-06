import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenPanelSizingTests: XCTestCase {
    private func fitted(_ view: some View, width: CGFloat, scale: Double = 1) -> CGSize {
        NSHostingController(rootView: view.lumenMetrics(.resolving(nil, textScale: scale)))
            .sizeThatFits(in: CGSize(width: width, height: 1_000))
    }

    func testLogFiltersStackWithinANarrowHost() {
        let source = "Workspace configuration service with a long source name"
        let bar = LumenLogFilterBar(sources: [source], source: .constant(source), query: .constant(""),
                                    filter: .constant(.all), onClear: {})
        let regular = fitted(bar, width: 220)
        let scaled = fitted(bar, width: 220, scale: 1.3)
        XCTAssertLessThanOrEqual(regular.width, 220.5)
        XCTAssertLessThanOrEqual(scaled.width, 220.5)
        XCTAssertGreaterThan(regular.height, LumenMetrics.standard.layout.controlHeight * 2)
        XCTAssertGreaterThan(scaled.height, regular.height)
    }

    func testFilterChipsAndStatusContentRespectTheViewport() {
        let options = ["All Messages", "Configuration Changes", "Warnings and Errors"]
        let chips = LumenFilterChips(selection: .constant(options[0]), options: options, title: { $0 })
        XCTAssertLessThanOrEqual(fitted(chips, width: 180).width, 180.5)
        let bar = LumenStatusBar {
            Text("A status value much wider than the available viewport").fixedSize()
            Color.clear.frame(width: 20, height: 60)
        }
        let size = fitted(bar, width: 180)
        XCTAssertLessThanOrEqual(size.width, 180.5)
        XCTAssertGreaterThanOrEqual(size.height, 60)
        XCTAssertLessThan(size.height, 100, "Horizontal scrolling must not consume the offered vertical space")
    }

    func testSidebarHeaderWrapsAndMovesActionsBelowItsTitle() {
        let section = LumenSidebarSection("Deployment configuration and environment settings") {
            Text("Actions").fixedSize()
        } content: {
            Color.clear.frame(height: 1)
        }
        let wide = fitted(section, width: 700)
        let narrow = fitted(section, width: 180)
        XCTAssertLessThanOrEqual(narrow.width, 180.5)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    func testWideStatusBarFillsHostAndSpacerPlacesTrailingItemAtEdge() throws {
        var barFrame: CGRect = .zero
        var leadingFrame: CGRect = .zero
        var trailingFrame: CGRect = .zero
        let metrics = LumenMetrics.standard
        let bar = LumenStatusBar {
            Text("12 items")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { leadingFrame = $0 }
            Spacer()
            Text("Ready")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trailingFrame = $0 }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { barFrame = $0 }
        .lumenMetrics(metrics)
        let host = NSHostingView(rootView: bar)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 700, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(CGSize(width: 700, height: 60))
        defer { window.close() }
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertGreaterThan(trailingFrame.width, 0)
        XCTAssertEqual(barFrame.width, host.bounds.width, accuracy: 0.5)
        XCTAssertEqual(leadingFrame.minX, barFrame.minX + metrics.spacing.s4, accuracy: 0.5)
        XCTAssertEqual(trailingFrame.maxX, barFrame.maxX - metrics.spacing.s4, accuracy: 0.5)
        XCTAssertGreaterThan(trailingFrame.minX - leadingFrame.maxX, 500)
    }
}
