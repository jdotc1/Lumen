import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenCardSizingTests: XCTestCase {
    private var notice: LumenNotice {
        LumenNotice(title: "Repository discovery complete", message: "Review the configuration and destination before continuing.",
                    primary: .init("Review the complete workspace configuration", perform: {}),
                    secondary: .init("Remind me after the current operation", perform: {}))
    }

    private func size(_ view: some View, width: CGFloat, scale: Double = 1) -> CGSize {
        NSHostingController(rootView: view.lumenMetrics(.resolving(nil, textScale: scale)))
            .sizeThatFits(in: CGSize(width: width, height: 2000))
    }

    func testNoticeHonorsHostWidthAndActionsGrowInsteadOfOverflowing() {
        let card = LumenNoticeCard(notice, onDismiss: {})
        let narrow = size(card, width: 240)
        let wide = size(card, width: 620)
        XCTAssertEqual(narrow.width, 240, accuracy: 1)
        XCTAssertEqual(wide.width, 620, accuracy: 1)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertGreaterThan(size(card, width: 240, scale: 1.3).height, narrow.height)
    }

    func testItemCardKeepsTitleAndStacksActionWithinHostProposal() {
        let card = LumenItemCard("Source Control Integration", author: "Workspace Tools",
                                 summary: "Review the configuration and destination before continuing.",
                                 systemImage: "shippingbox", state: .available)
        let narrow = size(card, width: 240)
        let wide = size(card, width: 620)
        XCTAssertEqual(narrow.width, 240, accuracy: 1)
        XCTAssertEqual(wide.width, 620, accuracy: 1)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertGreaterThan(size(card, width: 240, scale: 1.3).height, narrow.height)
    }

    func testNoticeQueueScrollsInsideShortHost() throws {
        let notices = (0..<8).map { LumenNotice(id: String($0), title: "Configuration \($0)", message: notice.message) }
        try checkNoticeViewport(Color.clear.lumenNotices(.constant(notices)))
        try checkNoticeViewport(Color.clear.lumenNotices(.constant(notices), maximumWidth: 420, maximumVisible: 2))
    }

    private func checkNoticeViewport(_ view: some View) throws {
        let root = view.lumenMetrics(.resolving(nil, textScale: 1.3))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 280, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(CGSize(width: 280, height: 180))
        defer { window.close() }
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        let scroll = try XCTUnwrap(findScroll(host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
        XCTAssertGreaterThan(document.visibleRect.height, 0, "Short queues must have visible content inside their viewport")
        let viewport = scroll.convert(scroll.bounds, to: host)
        XCTAssertGreaterThanOrEqual(viewport.minY, 0)
        XCTAssertLessThanOrEqual(viewport.maxY, host.bounds.height + 1)
        XCTAssertLessThanOrEqual(viewport.maxX, host.bounds.width + 1)
        let destination = max(0, document.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: destination))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "The queue document must be reachable beyond its first viewport")
    }
}
