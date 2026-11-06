import SwiftUI
import XCTest
import LumenConformance
@testable import LumenUI

@MainActor final class LumenToastTests: XCTestCase {
    func testToneDefaultsAndExplicitPersistence() {
        XCTAssertEqual(LumenToast(title: "Info").duration, 4)
        XCTAssertEqual(LumenToast(title: "Done", tone: .success).duration, 4)
        XCTAssertNil(LumenToast(title: "Warning", tone: .warning).duration)
        XCTAssertNil(LumenToast(title: "Error", tone: .danger).duration)
        XCTAssertNil(LumenToast(title: "Info", duration: nil).duration)
        XCTAssertEqual(LumenToast(title: "Warning", tone: .warning, duration: 2).duration, 2)
    }

    func testHoverPausesRemainingTimeInsteadOfRestarting() {
        var now = 0.0
        let center = LumenToastCenter(now: { now }, schedulesTimers: false)
        let id = center.post(LumenToast(title: "Export complete"))
        now = 1
        center.setHovered(true, id: id)
        now = 100
        center.expireDueToasts()
        XCTAssertEqual(center.visibleToasts.map(\.id), [id])
        center.setHovered(false, id: id)
        now = 102.9
        center.expireDueToasts()
        XCTAssertEqual(center.visibleToasts.count, 1)
        now = 103.1
        center.expireDueToasts()
        XCTAssertTrue(center.visibleToasts.isEmpty)
    }

    func testOnlyNewestThreeVisibleAndDismissRevealsOlder() {
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        let ids = (0..<5).map { center.post(LumenToast(title: "Notice \($0)", duration: nil)) }
        XCTAssertEqual(center.visibleToasts.map(\.id), Array(ids.suffix(3)))
        XCTAssertEqual(center.collapsedCount, 2)
        center.dismiss(id: ids[4])
        XCTAssertEqual(center.visibleToasts.map(\.id), Array(ids[1...3]))
        XCTAssertEqual(center.collapsedCount, 1)
    }

    func testCollapsedTimersResumeOnlyWhenVisible() {
        var now = 0.0
        let center = LumenToastCenter(now: { now }, schedulesTimers: false)
        let first = center.post(LumenToast(title: "First"))
        now = 1
        let others = (0..<3).map { center.post(LumenToast(title: "Persistent \($0)", duration: nil)) }
        now = 40
        center.expireDueToasts()
        XCTAssertEqual(center.collapsedCount, 1)
        center.dismiss(id: others[0])
        XCTAssertEqual(center.visibleToasts.first?.id, first)
        now = 42.9
        center.expireDueToasts()
        XCTAssertEqual(center.visibleToasts.count, 3)
        now = 43.1
        center.expireDueToasts()
        XCTAssertEqual(center.visibleToasts.count, 2)
    }

    func testCentersAreIndependentAndRepostingDoesNotDuplicate() {
        let first = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        let second = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        let toast = LumenToast(title: "Notice", duration: nil)
        first.post(toast)
        first.post(toast)
        XCTAssertEqual(first.visibleToasts.count, 1)
        XCTAssertTrue(second.visibleToasts.isEmpty)
        first.dismiss(id: UUID())
        XCTAssertEqual(first.visibleToasts.count, 1)
    }

    func testPersistentHoveredNoticeCanBeDismissed() {
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        let id = center.post(LumenToast(title: "Warning", tone: .warning))
        center.setHovered(true, id: id)
        center.dismiss(id: id)
        XCTAssertTrue(center.visibleToasts.isEmpty)
    }

    func testLongToastWrapsAtNarrowWidth() {
        let toast = LumenToast(title: "A deliberately long notification title that must wrap across multiple lines",
                               message: "The full message stays available at the narrow window width.", duration: nil)
        let view = { LumenToastCard(toast: toast, dismiss: {}).frame(width: 280) }
        XCTAssertEqual(LumenConformance.truncation(sizes: [CGSize(width: 280, height: 280)], of: view).map(\.description), [])
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: view()), 280)
    }
}
