import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenToolbarStatusSizingTests: XCTestCase {
    @Observable final class Model {
        var label = "Analyzing libsystem_kernel.dylib"
        var peerWidth: CGFloat = 60
        var progress: Double = 0.42
    }

    private struct Subject: View {
        @Bindable var model: Model
        var body: some View {
            Color.clear.frame(minWidth: 100, minHeight: 100)
                .toolbar {
                    ToolbarItem(id: "identity", placement: .navigation) { Text("Project").frame(width: 100) }
                    ToolbarItem(id: "status", placement: .navigation) {
                        LumenToolbarStatus(.working(model.label, progress: model.progress), minWidth: 140)
                    }
                    ToolbarItem(id: "middle", placement: .navigation) { Text("Mode").frame(width: 40) }
                    ToolbarItem(id: "peer", placement: .primaryAction) { Text("Tasks").frame(width: model.peerWidth) }
                }
        }
    }

    func testPreferredWidthRemainsEqualAcrossPercentageDigitCounts() throws {
        let model = Model()
        let host = NSHostingView(rootView: Subject(model: model))
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: -10000, y: -10000, width: 1200, height: 200),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentView = host
        LumenHeadlessHost.order(window)
        defer { window.close() }

        var widths: [CGFloat] = []
        for progress in [0.05, 0.42, 1.0] {
            model.progress = progress
            for _ in 0..<20 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                window.update()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let toolbar = try XCTUnwrap(window.toolbar)
            let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "status" })
            XCTAssertTrue((toolbar.visibleItems ?? []).contains { $0.itemIdentifier == item.itemIdentifier })
            widths.append(try XCTUnwrap(item.view).bounds.width)
        }
        XCTAssertGreaterThan(widths[0], 250, "ample toolbar room must expose the preferred width")
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.1)
        XCTAssertEqual(widths[1], widths[2], accuracy: 0.1)
    }

    func testNativeRoomTracksWindowAndPeerWidthsBeforeOverflow() throws {
        let model = Model()
        let host = NSHostingView(rootView: Subject(model: model))
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: -10000, y: -10000, width: 800, height: 200),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentView = host
        LumenHeadlessHost.order(window)
        defer { window.close() }

        func status() throws -> CGFloat {
            for _ in 0..<20 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                // XCTest pumps RunLoop directly, outside NSApplication's event loop. Supply its
                // normal per-window update phase (which posts NSWindow.didUpdateNotification).
                window.update()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let toolbar = try XCTUnwrap(window.toolbar)
            let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
            for item in toolbar.items where item.view != nil {
                XCTAssertTrue(visible.contains(item.itemIdentifier), "\(item.itemIdentifier) overflowed")
            }
            let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "status" })
            return try XCTUnwrap(item.view).bounds.width
        }
        let natural = try status()
        XCTAssertGreaterThan(natural, 250)
        window.setContentSize(CGSize(width: 500, height: 200))
        let narrow = try status()
        XCTAssertLessThan(narrow, natural - 10, "the status yields before the task item overflows")
        XCTAssertGreaterThanOrEqual(narrow, 140)
        window.setContentSize(CGSize(width: 800, height: 200))
        XCTAssertEqual(try status(), natural, accuracy: 1)
        model.peerWidth = 350
        XCTAssertLessThan(try status(), natural - 10, "a wider peer reduces room without a window resize")
        model.peerWidth = 60
        model.label = "Indexing"
        XCTAssertLessThan(try status(), natural - 40, "shorter content must release its width")
    }
}
