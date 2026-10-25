import AppKit
import XCTest
import LumenTestSupport
@_spi(LayoutAudit) @testable import LumenUI

@MainActor
final class LumenNativeControlChromeAuditTests: XCTestCase {
    func testNativeSearchChromeAndLumenStrokeHaveDifferentOwners() throws {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        let search = NSSearchField(frame: CGRect(x: 0, y: 60, width: 180, height: 28))
        search.stringValue = "Search words"
        root.addSubview(search)
        let window = LumenHeadlessHost.window(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = root
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        defer { window.close() }
        root.layoutSubtreeIfNeeded()
        let nativeFrame = window.convertToScreen(search.convert(search.bounds, to: nil))
        let native = try LumenRenderedAudit.capture(in: window)
        XCTAssertTrue(native.nativeControlChrome.contains(nativeFrame))
        XCTAssertFalse(native.exclusions.contains(nativeFrame), "Native field text must not enter the OCR exclusions")
        let nativeResult = try LumenRenderedAudit.analyze(native)
        XCTAssertFalse(zip(nativeResult.findings, nativeResult.findingRects).contains {
            $0.0.rule == "rendered-edge" && $0.1.intersects(nativeFrame)
        }, "Measured native search chrome is owned: \(nativeResult.findings)")
        XCTAssertTrue(nativeResult.findings.isEmpty, "Native search chrome and correctly contained text pass: \(nativeResult.findings)")
        XCTAssertTrue(nativeResult.observes("Search words"), "Field glyphs still undergo OCR and text rules")

        search.removeFromSuperview()
        let stroke = ClippedStroke(frame: CGRect(x: 0, y: 60, width: 180, height: 28))
        stroke.clipsToBounds = true
        root.addSubview(stroke)
        let drawn = try LumenRenderedAudit.capture(in: window)
        XCTAssertTrue(drawn.nativeControlChrome.isEmpty)
        let drawnResult = try LumenRenderedAudit.analyze(drawn)
        XCTAssertTrue(zip(drawnResult.findings, drawnResult.findingRects).contains {
            $0.0.rule == "rendered-edge" && $0.1.intersects(nativeFrame)
        }, "A Lumen stroke clipped at exactly the same frame remains ink: \(drawnResult.findings)")
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
        print("NATIVE-CONTROL nativeBezel=\(nativeFrame) nativeFindings=\(nativeResult.findings.count) drawnFindings=\(drawnResult.findings.count)")
    }

    private final class ClippedStroke: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            bounds.fill()
            NSColor.systemRed.setFill()
            CGRect(x: -4, y: 7, width: 28, height: 12).fill()
        }
    }
}
