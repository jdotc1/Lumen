import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@_spi(LayoutAudit) @testable import LumenUI

@MainActor
final class LumenNativeSplitDividerAuditTests: XCTestCase {
    func testHostedInspectorExcludesOnlyItsNativeDivider() throws {
        let root = Color.white
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: .constant(true)) {
                Color.white.inspectorColumnWidth(220)
            }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 720, height: 360),
                                             styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        defer { window.close() }
        for _ in 0..<15 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let split = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSplitView }.first)
        let pane = try XCTUnwrap(split.arrangedSubviews.last)
        // Read the native separator independently. An overlay inspector's first pane
        // spans the whole split, so subtracting arranged-pane frames is not valid.
        let nativeSeparator = try XCTUnwrap(split.subviews.first { child in
            !split.arrangedSubviews.contains(where: { $0 === child })
                && child.frame.size.width > 0 && child.frame.size.width <= split.dividerThickness
                && child.frame.minX == pane.frame.minX
                && child.frame.minY == split.bounds.minY && child.frame.maxY == split.bounds.maxY
        })
        let expectedDivider = window.convertToScreen(nativeSeparator.convert(nativeSeparator.bounds, to: nil))
        let clipped = ClippedInk(frame: CGRect(x: 80, y: 80, width: 70, height: 40))
        clipped.clipsToBounds = true
        pane.addSubview(clipped)
        let boundary = window.convertToScreen(clipped.convert(clipped.bounds, to: nil))
        let dividers = LumenNativeSplitDividers.frames(in: window)
        XCTAssertEqual(dividers, [expectedDivider],
                       "Exclude only the actual native separator frame, never the overlapping inspector pane")
        let inspectorInterior = window.convertToScreen(pane.convert(
            pane.bounds.insetBy(dx: split.dividerThickness, dy: split.dividerThickness), to: nil))
        XCTAssertFalse(dividers.contains { $0.intersects(inspectorInterior) })
        XCTAssertTrue(dividers.allSatisfy { !$0.intersects(boundary) })
        let capture = try LumenRenderedAudit.capture(in: window)
        // This assertion fails on the base: native split dividers were not capture exclusions.
        XCTAssertTrue(dividers.allSatisfy { capture.exclusions.contains($0) })
        let result = try LumenRenderedAudit.analyze(capture)
        let edgeRects = zip(result.findings, result.findingRects).compactMap { finding, rect in
            finding.rule == "rendered-edge" ? rect : nil
        }
        print("NATIVE-DIVIDER actualNativeFrame=\(expectedDivider) frames=\(dividers); clippedBoundary=\(boundary); edgeFindings=\(edgeRects)")
        XCTAssertFalse(edgeRects.contains { edge in dividers.contains { $0.intersects(edge) } },
                       "AppKit owns the measured divider: \(result.findings)")
        XCTAssertTrue(edgeRects.contains { $0.intersects(boundary) },
                      "Clipped foreground at an unrelated boundary must remain detected: \(result.findings)")
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }

    private final class ClippedInk: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            bounds.fill()
            NSColor.systemRed.setFill()
            CGRect(x: bounds.maxX - 20, y: 8, width: 40, height: 24).fill()
        }
    }
}
