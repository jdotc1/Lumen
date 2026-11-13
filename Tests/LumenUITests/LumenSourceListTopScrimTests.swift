import AppKit
import SwiftUI
import XCTest
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
}
