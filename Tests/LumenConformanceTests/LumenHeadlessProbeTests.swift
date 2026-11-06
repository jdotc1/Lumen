import AppKit
import LumenHeadlessGuard
import LumenTestSupport
import XCTest

@MainActor
final class LumenHeadlessProbeTests: XCTestCase {
    /// The process guard prevents presentation and activation of a test window.
    func testGuardedHostNeverShowsOrActivates() {
        XCTAssertTrue(LumenHeadlessGuardInstalled(), "Every test bundle must load the process guard")
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        XCTAssertNotNil(before)
        XCTAssertNotEqual(before, ProcessInfo.processInfo.processIdentifier)
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 160, height: 90),
                                             styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.close() }
        window.title = "Headless safety probe"
        window.contentView = NSView(frame: .init(x: 0, y: 0, width: 160, height: 90))
        LumenHeadlessHost.order(window)
        LumenHeadlessGuardBeginExpectedAttempt(window, "makeKeyAndOrderFront:")
        window.makeKeyAndOrderFront(nil)
        XCTAssertEqual(LumenHeadlessGuardEndExpectedAttempt(), 1, "Guard must catch before AppKit dispatch")
        window.setContentSize(.init(width: 310, height: 170))
        window.contentView?.layoutSubtreeIfNeeded()
        window.update()
        XCTAssertEqual(window.constrainFrameRect(window.frame, to: NSScreen.main), window.frame)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        LumenHeadlessGuardCheck()
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        XCTAssertEqual(before, after)
        XCTAssertFalse(NSApp.isActive)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(window.isMainWindow)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
        let snapshot = LumenHeadlessGuardSnapshot()
        XCTAssertEqual(snapshot["violations"] as? Int, 0)
        XCTAssertEqual(snapshot["visible"] as? Int, 0)
        XCTAssertEqual(snapshot["intersecting"] as? Int, 0)
        XCTAssertEqual(snapshot["frontmostChanges"] as? Int, 0)
        print("HEADLESS PROBE: frontmostBefore=\(String(describing: before)); frontmostAfter=\(String(describing: after)); process=\(ProcessInfo.processInfo.processIdentifier); \(snapshot)")
    }
}
