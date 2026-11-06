import SwiftUI
import XCTest
@testable import LumenUI

final class LumenMotionTests: XCTestCase {
    private func check(_ value: LumenMotion.Transition, _ duration: Double, _ curve: Animation) {
        XCTAssertEqual(value.duration(in: .standard), duration)
        XCTAssertEqual(value.animation(in: .standard, reduceMotion: false), curve)
        XCTAssertNil(value.animation(in: .standard, reduceMotion: true))
        XCTAssertEqual(value.effect(in: .standard, reduceMotion: true), .none)
        var disabled = LumenMetrics.Motion.standard
        disabled.isEnabled = false
        XCTAssertNil(value.animation(in: disabled, reduceMotion: false))
        XCTAssertEqual(value.effect(in: disabled, reduceMotion: false), .none)
    }
    func testInspector() { check(.inspector, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testBottomPanel() { check(.bottomPanel, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testSidebar() { check(.sidebar, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testSelection() { check(.selection, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testNotice() { check(.notice, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testDisclosure() { check(.disclosure, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testThemeHover() { check(.themeHover, 0.22, LumenMetrics.Motion.standard.standardCurve) }
    func testPalette() { check(.palette, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testStatusGlyph() { check(.statusGlyph, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testHover() { check(.hover, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testControl() { check(.control, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testReorder() { check(.reorder, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testToolLayout() { check(.toolLayout, 0.14, LumenMetrics.Motion.standard.fastCurve) }
    func testToast() { check(.toast, 0.22, LumenMetrics.Motion.standard.regularCurve) }
    func testProgress() { check(.progress, 0.22, LumenMetrics.Motion.standard.regularCurve) }
    func testScroll() { check(.scroll, 0.5, .snappy) }
    func testLoading() { check(.loading, 1.1, .easeInOut(duration: 1.1).repeatForever(autoreverses: true)) }
    func testCustomMetricsKeepCallerTiming() {
        var motion = LumenMetrics.Motion(fast: 0.8, standard: 0.9, emphasized: 1.2)
        motion.fastCurve = .linear(duration: 0.8)
        motion.standardCurve = .easeOut(duration: 0.9)
        motion.regularCurve = .easeIn(duration: 0.9)
        for value in LumenMotion.Transition.allCases {
            switch value.ramp {
            case .fast:
                XCTAssertEqual(value.duration(in: motion), 0.8)
                XCTAssertEqual(value.animation(in: motion, reduceMotion: false), motion.fastCurve)
            case .standard:
                XCTAssertEqual(value.duration(in: motion), 0.9)
                XCTAssertEqual(value.animation(in: motion, reduceMotion: false), motion.standardCurve)
            case .regular:
                XCTAssertEqual(value.duration(in: motion), 0.9)
                XCTAssertEqual(value.animation(in: motion, reduceMotion: false), motion.regularCurve)
            case .scroll: XCTAssertEqual(value.duration(in: motion), 0.5)
            case .loading: XCTAssertEqual(value.duration(in: motion), 1.1)
            }
        }
    }
    func testTransitionGeometry() {
        for value in LumenMotion.Transition.allCases {
            let expected: LumenMotion.Transition.Effect
            switch value {
            case .bottomPanel: expected = .bottom
            case .inspector, .notice: expected = .trailing
            case .sidebar: expected = .leading
            case .toast: expected = .toast
            default: expected = .opacity
            }
            XCTAssertEqual(value.effect(in: .standard, reduceMotion: false), expected)
            _ = value.transition(in: .standard, reduceMotion: false)
        }
    }
    @MainActor func testModifierEntryPointsCompileWithoutHosting() {
        for value in LumenMotion.Transition.allCases {
            _ = Text("12").lumenNumericText(value: 12)
                .lumenStatusSymbol(value: "checkmark")
                .lumenTransition(value).lumenAnimation(value, value: true)
        }
        var invoked = false
        LumenMotion.perform(.selection, metrics: .standard, reduceMotion: true) { invoked = true }
        XCTAssertTrue(invoked)
    }
}
