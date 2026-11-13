import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@testable import LumenUI

/// A scrolling sidebar list runs under the titlebar, so it covers the window-button band with a scrim.
@MainActor final class LumenSourceListTopScrimTests: XCTestCase {
    private func fitted(height: CGFloat) -> CGSize {
        let host = NSHostingView(rootView: LumenSourceListTopScrim(height: height, color: .gray).frame(width: 200))
        return host.fittingSize
    }

    func testScrimCoversTheTitlebarBandPlusFade() {
        XCTAssertEqual(fitted(height: 52).height, 52 + LumenSourceListTopScrim.fadeHeight, accuracy: 0.5)
    }

    func testScrimDrawsNothingWithoutAnInset() {
        XCTAssertEqual(fitted(height: 0).height, 0, accuracy: 0.5)
    }

    /// Design review 2026-11 #1: an overlay's content keeps the safe area even when its host ignores
    /// it, so the scrim landed one titlebar-height *below* the titlebar. It hid the first rows
    /// (Overview, Welcome) and left the window-button band uncovered. The scrim must start at the
    /// window's top edge and the first row must start below its solid band.
    func testScrimSitsUnderTheTitlebarNotBelowIt() throws {
        var frames: [LumenMarginElementFrame] = []
        let list = LumenSourceList([.init(id: "a", title: "Overview"), .init(id: "b", title: "Welcome")],
                                   selection: .constant("a"))
        let host = NSHostingView(rootView: list.lumenPaletteRoot()
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 })
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 240, height: 320),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<25 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let inset = host.safeAreaInsets.top
        XCTAssertGreaterThan(inset, 0, "the host must sit under a titlebar for this check")
        let scrim = try XCTUnwrap(frames.first { $0.role == "source-list-top-scrim" })
        let firstRow = try XCTUnwrap(frames.filter { $0.role == "source-list-row" }.min { $0.frame.minY < $1.frame.minY })
        print("TOP-SCRIM inset=\(inset) scrim=\(scrim.frame) firstRow=\(firstRow.frame)")
        XCTAssertEqual(scrim.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(scrim.frame.height, inset + LumenSourceListTopScrim.fadeHeight, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(firstRow.frame.minY, inset - 0.5)
        XCTAssertFalse(window.isVisible)
    }
}
