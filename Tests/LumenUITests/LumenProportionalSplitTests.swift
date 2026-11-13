import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

/// `LumenProportionalSplit`: panes keep a ratio as the window resizes, minimums hold while there is
/// room, and bad ratios or measuring-pass sizes never crash.
@MainActor final class LumenProportionalSplitTests: XCTestCase {
    private typealias Math = LumenProportionalSplitMath

    func testRatioIsPreservedAcrossTotals() {
        for total: CGFloat in [400, 800, 1200] {
            let s = Math.sizes(ratio: 0.25, total: total, minimumFirst: 50, minimumSecond: 50)
            XCTAssertEqual(s.first, 0.25 * total, accuracy: 0.001)
            XCTAssertEqual(s.first + s.second, total, accuracy: 0.001)
        }
    }

    func testMinimumsAreHonoredAtExtremeRatios() {
        let low = Math.sizes(ratio: 0.05, total: 500, minimumFirst: 120, minimumSecond: 120)
        XCTAssertEqual(low.first, 120, accuracy: 0.001)
        let high = Math.sizes(ratio: 0.95, total: 500, minimumFirst: 120, minimumSecond: 120)
        XCTAssertEqual(high.second, 120, accuracy: 0.001)
    }

    func testInsufficientRoomSplitsByMinimumsWithoutNegatives() {
        let s = Math.sizes(ratio: 0.9, total: 100, minimumFirst: 120, minimumSecond: 60)
        XCTAssertEqual(s.first, 100 * 120 / 180, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(s.second, 0)
        XCTAssertEqual(s.first + s.second, 100, accuracy: 0.001)
    }

    func testBadRatiosAreSanitized() {
        XCTAssertEqual(Math.sizes(ratio: .nan, total: 400, minimumFirst: 0, minimumSecond: 0).first, 200, accuracy: 0.001)
        XCTAssertEqual(Math.sizes(ratio: -3, total: 400, minimumFirst: 0, minimumSecond: 0).first, 0, accuracy: 0.001)
        XCTAssertEqual(Math.sizes(ratio: 7, total: 400, minimumFirst: 0, minimumSecond: 0).first, 400, accuracy: 0.001)
        XCTAssertEqual(Math.sanitized(.infinity), 0.5)
    }

    func testZeroOrInvalidTotalGivesZeroSizes() {
        for total: CGFloat in [0, -5, .nan] {
            let s = Math.sizes(ratio: 0.5, total: total, minimumFirst: 120, minimumSecond: 120)
            XCTAssertEqual(s.first, 0)
            XCTAssertEqual(s.second, 0)
        }
        XCTAssertEqual(Math.ratio(forFirstSize: 10, total: 0, minimumFirst: 0, minimumSecond: 0), 0.5)
    }

    func testRatioForFirstSizeSnapsIntoMinimums() {
        XCTAssertEqual(Math.ratio(forFirstSize: 300, total: 600, minimumFirst: 100, minimumSecond: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Math.ratio(forFirstSize: 10, total: 600, minimumFirst: 100, minimumSecond: 100), 100.0 / 600, accuracy: 0.0001)
        XCTAssertEqual(Math.ratio(forFirstSize: 590, total: 600, minimumFirst: 100, minimumSecond: 100), 500.0 / 600, accuracy: 0.0001)
    }

    @MainActor private final class Probe { var firstHeight: CGFloat = -1 }

    private func host<V: View>(_ view: V, size: CGSize) -> (NSHostingView<some View>, NSWindow) {
        let host = NSHostingView(rootView: view.lumenPaletteRoot().environment(\.lumenRendersOffscreen, true))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return (host, window)
    }

    func testHostedFirstPaneKeepsRatioAtTwoHeights() {
        let hairline = LumenMetrics.standard.stroke.hairline
        for height: CGFloat in [400, 800] {
            let probe = Probe()
            let view = LumenProportionalSplit(ratio: .constant(0.25), minimumFirst: 20, minimumSecond: 20) {
                Color.red.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { probe.firstHeight = $0 }
            } second: {
                Color.blue
            }
            .frame(width: 300, height: height)
            let (_, window) = host(view, size: CGSize(width: 300, height: height))
            defer { window.close() }
            XCTAssertEqual(probe.firstHeight, 0.25 * (height - hairline), accuracy: 0.5)
        }
    }

    func testMeasuringPassAtOnePointStaysSmallAndPositive() {
        let view = LumenProportionalSplit(ratio: .constant(0.5)) { Color.red } second: { Color.blue }
            .lumenPaletteRoot()
        let host = NSHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: 1, height: 1))
        XCTAssertTrue(size.width.isFinite && size.height.isFinite)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThan(size.width, 1000)
    }
}
