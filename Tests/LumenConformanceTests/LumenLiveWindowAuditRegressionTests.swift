import LumenTestSupport
import AppKit
import XCTest
@testable import LumenConformance

@MainActor
final class LumenLiveWindowAuditRegressionTests: XCTestCase {
    @MainActor private final class ToolbarFixture: NSObject, NSToolbarDelegate {
        let item: NSToolbarItem

        override init() {
            item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("fixture"))
            super.init()
            item.label = "Toolbar control"
            item.view = NSButton(title: "Toolbar control", target: nil, action: nil)
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
    }

    func testContentControlAtToolbarItemFrameIsNotExempted() throws {
        let window = makeWindow()
        defer { window.close() }
        let fixture = ToolbarFixture()
        let toolbar = NSToolbar(identifier: "live-audit-toolbar")
        toolbar.delegate = fixture
        window.toolbar = toolbar
        LumenHeadlessHost.order(window)
        settle(window)
        let content = try XCTUnwrap(window.contentView)
        let itemView = try XCTUnwrap(fixture.item.view)
        XCTAssertTrue(itemView.window === window, "The fixture must have a real native toolbar item")
        let collision = NSButton(title: "Content collision", target: nil, action: nil)
        collision.frame = content.convert(itemView.bounds, from: itemView)
        content.addSubview(collision)
        settle(window)
        let findings = LumenConformance.liveWindow(window)
        XCTAssertTrue(findings.contains { $0.subject.contains("Content collision") && $0.message.hasPrefix("chrome:") },
                      "A content control sharing toolbar pixels is not a toolbar descendant: \(findings)")
        withExtendedLifetime(fixture) {}
    }

    func testScrollChildClippedByNonScrollAncestorIsReported() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let scroll = NSScrollView(frame: .init(x: 30, y: 30, width: 260, height: 200))
        let document = NSView(frame: .init(x: 0, y: 0, width: 260, height: 200))
        let clipping = NSView(frame: .init(x: 20, y: 20, width: 80, height: 50))
        clipping.clipsToBounds = true
        let button = NSButton(title: "Clipped inside scroll", target: nil, action: nil)
        button.frame = .init(x: 40, y: 10, width: 140, height: 24)
        clipping.addSubview(button)
        document.addSubview(clipping)
        scroll.documentView = document
        content.addSubview(scroll)
        LumenHeadlessHost.order(window)
        settle(window)
        let findings = LumenConformance.liveWindow(window)
        XCTAssertTrue(findings.contains { $0.subject.contains("Clipped inside scroll") && $0.message.hasPrefix("ancestor-clip:") },
                      "A scroll ancestor cannot hide an unrelated clip: \(findings)")
    }

    func testOffViewportRowsDoNotReportIntentionalScrollClipping() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let scroll = NSScrollView(frame: .init(x: 30, y: 30, width: 260, height: 200))
        let document = NSView(frame: .init(x: 0, y: 0, width: 260, height: 800))
        scroll.documentView = document
        content.addSubview(scroll)
        LumenHeadlessHost.order(window)
        settle(window)
        let viewport = scroll.contentView.bounds
        let offscreen = NSButton(title: "Off-viewport row", target: nil, action: nil)
        let y = viewport.maxY + 50 < document.bounds.maxY ? viewport.maxY + 30 : viewport.minY - 50
        offscreen.frame = .init(x: 20, y: y, width: 160, height: 24)
        document.addSubview(offscreen)
        let visible = NSButton(title: "Visible row", target: nil, action: nil)
        visible.frame = .init(x: 20, y: viewport.midY, width: 160, height: 24)
        document.addSubview(visible)
        settle(window)
        XCTAssertFalse(scroll.contentView.bounds.intersects(offscreen.frame), "The negative control must be outside the viewport")
        let findings = LumenConformance.liveWindow(window)
        XCTAssertFalse(findings.contains { $0.subject.contains("Off-viewport row") &&
            ($0.message.hasPrefix("content-bounds:") || $0.message.hasPrefix("ancestor-clip:")) },
                       "Ordinary offscreen document rows remain reachable by scrolling: \(findings)")
    }

    func testSharedSearchControlOwnerDoesNotHideIndependentCoincidentButtons() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let search = NSSearchField(frame: .init(x: 60, y: 220, width: 300, height: 28))
        search.stringValue = "Editable search fixture"
        content.addSubview(search)
        // Identical labels and frames are deliberate: geometry/name deduplication must not merge
        // two separate controls while suppressing a field editor and cells of the same control.
        let first = NSButton(title: "Independent control", target: nil, action: nil)
        let second = NSButton(title: "Independent control", target: nil, action: nil)
        first.frame = .init(x: 60, y: 60, width: 200, height: 28)
        second.frame = first.frame
        content.addSubview(first)
        content.addSubview(second)
        LumenHeadlessHost.order(window)
        XCTAssertTrue(window.makeFirstResponder(search))
        search.selectText(nil)
        settle(window)
        let editor = try XCTUnwrap(search.currentEditor(), "The shared field-editor ownership path must be active")
        let editorFrame = window.convertToScreen(editor.convert(editor.bounds, to: nil))
        let searchFrame = window.convertToScreen(search.convert(search.bounds, to: nil))
        XCTAssertTrue(editorFrame.intersects(searchFrame), "The editor must overlap the control it edits")
        XCTAssertNotNil((search.cell as? NSSearchFieldCell)?.searchButtonCell,
                        "The fixture must include the search control's native icon cell")
        let overlaps = LumenConformance.liveWindow(window).filter { $0.message.hasPrefix("control-overlap:") }
        XCTAssertEqual(overlaps.count, 1, "Only the two independent controls should collide: \(overlaps)")
        XCTAssertTrue(overlaps.contains { $0.subject.contains("Independent control") &&
            $0.message.contains("overlaps interactive control “Independent control”") },
                      "A proven shared owner exemption must not hide separate coincident controls: \(overlaps)")
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 640, height: 400),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Live audit regression"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<12 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
