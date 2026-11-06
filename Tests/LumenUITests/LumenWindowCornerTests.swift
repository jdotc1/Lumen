import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenWindowCornerTests: XCTestCase {
    func testMeasuredWindowRadius() {
        XCTAssertEqual(LumenRadius.window, 16)
    }

    private final class Container: NSView {
        override var cornerConfiguration: NSViewCornerConfiguration? {
            .corners(radius: .fixed(16))
        }
    }

    func testAppKitHostsResolveAndUpdateConcentricMasks() throws {
        let container = Container(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let window = LumenHeadlessHost.window(contentRect: container.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        for child in [LumenConcentricTextView(frame: .zero), LumenConcentricGlassView(frame: .zero)] as [NSView] {
            if let text = child as? NSTextView { text.isVerticallyResizable = false }
            child.frame = container.bounds.insetBy(dx: 4, dy: 4)
            container.addSubview(child)
            child.invalidateCornerConfiguration()
            container.layoutSubtreeIfNeeded()
            child.layout()
            let first = try XCTUnwrap(child.effectiveCornerRadii).topLeft
            XCTAssertGreaterThan(first, 0)
            XCTAssertLessThan(first, 16)
            let mask = try XCTUnwrap(child.layer?.mask as? CAShapeLayer)
            let oldPath = try XCTUnwrap(mask.path)
            XCTAssertFalse(oldPath.contains(.zero))
            XCTAssertTrue(oldPath.contains(CGPoint(x: 50, y: 40)))
            child.frame = container.bounds.insetBy(dx: 8, dy: 8)
            child.invalidateCornerConfiguration()
            container.layoutSubtreeIfNeeded()
            child.layout()
            let second = try XCTUnwrap(child.effectiveCornerRadii).topLeft
            XCTAssertLessThan(second, first)
            XCTAssertNotEqual(mask.path, oldPath)
            child.removeFromSuperview()
        }
    }

    func testFloatingStatusFitsItsContent() {
        let view = Color.clear.frame(width: 320, height: 180).lumenFloatingStatus {
            Text("Ready")
        } folded: { Text("1") }
        let host = NSHostingView(rootView: view)
        XCTAssertEqual(host.fittingSize, CGSize(width: 320, height: 180))
    }
}
