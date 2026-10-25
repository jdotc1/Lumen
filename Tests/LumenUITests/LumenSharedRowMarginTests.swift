import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@testable import LumenUI

@MainActor final class LumenSharedRowMarginTests: XCTestCase {
    func testSectionHeadingConsumesMeasuredNativeInset() throws {
        try withFrames(LumenSourceList(sections: [.init("Source Files", items: [
            .init(id: "file", title: "Example")
        ])], selection: .constant("file")), size: .init(width: 240, height: 160)) { frames in
            let heading = try XCTUnwrap(frames.first { $0.role == "source-list-heading-ink" })
            let row = try XCTUnwrap(frames.first { $0.role == "source-list-row" })
            let plate = try XCTUnwrap(frames.first { $0.role == "list-row-plate" })
            let nativeInset = plate.frame.minX - row.frame.minX
            print("HEADING-MARGIN heading=\(heading.frame) row=\(row.frame) nativePlate=\(plate.frame)")
            XCTAssertGreaterThan(nativeInset, 0)
            XCTAssertEqual(heading.frame.minX - row.frame.minX, nativeInset, accuracy: 0.01)
        }
    }

    func testWelcomeRecentsConsumeDeclaredMargin() throws {
        let welcome = LumenWelcomeView(appName: "Lumen", tagline: "Open a project", markSymbol: "folder",
            actions: [], recents: [.init(title: "Example", detail: "Project", date: Date(timeIntervalSince1970: 0))], seed: 1)
        try withFrames(welcome.lumenScaffoldMargin(20), size: .init(width: 760, height: 540)) { frames in
            let rows = try XCTUnwrap(frames.first { $0.role == "welcome-recent-rows" })
            let content = try XCTUnwrap(frames.first { $0.role == "welcome-recent-content" })
            print("RECENT-MARGIN rows=\(rows.frame) content=\(content.frame)")
            XCTAssertEqual(content.frame.minX - rows.frame.minX, 20, accuracy: 0.01)
            XCTAssertEqual(rows.frame.maxX - content.frame.maxX, 20, accuracy: 0.01)
        }
    }

    private func withFrames<V: View>(_ view: V, size: CGSize,
                                    inspect: ([LumenMarginElementFrame]) throws -> Void) throws {
        var frames: [LumenMarginElementFrame] = []
        let host = NSHostingView(rootView: view.lumenPaletteRoot()
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 })
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<25 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        try inspect(frames)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }
}
