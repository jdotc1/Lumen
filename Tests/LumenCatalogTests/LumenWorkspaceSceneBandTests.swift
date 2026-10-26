import AppKit
import LumenTestSupport
import LumenUI
import SwiftUI
import XCTest
@testable import LumenCatalog

@MainActor
final class LumenWorkspaceSceneBandTests: XCTestCase {
    func testProductionWorkspaceSceneBand() throws {
        // Host the production Workspace root with native title/toolbar bridging. Unlike the
        // stress matrix, measure only after content attachment and never inject a toolbar style.
        let host = NSHostingView(rootView: WorkspaceDemo().lumenPaletteRoot()
            .frame(minWidth: 1000, minHeight: 660))
        host.sizingOptions = []
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(.init(width: 1200, height: 800))
        LumenHeadlessHost.order(window)
        defer { window.close() }
        for _ in 0..<40 {
            host.superview?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let items = window.toolbar?.visibleItems ?? []
        let controls = items.compactMap(\.view) + [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        let centers = controls.filter { !$0.isHiddenOrHasHiddenAncestor && !$0.bounds.isEmpty }
            .map { $0.convert($0.bounds, to: nil).midY }.sorted()
        var rows: [CGFloat] = []
        for center in centers where rows.last.map({ abs(center - $0) > 6 }) ?? true { rows.append(center) }
        print("WORKSPACE_SCENE band=\(window.frame.height - window.contentLayoutRect.height) style=\(window.toolbarStyle.rawValue) rows=\(rows.count) items=\(items.map { $0.itemIdentifier.rawValue })")
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
    }
}
