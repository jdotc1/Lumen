import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenWizardNavigationTests: XCTestCase {
    func testClampsNegativeOversizedAndShrinkingSelections() {
        var current = Int.min
        let binding = Binding(get: { current }, set: { current = $0 })
        let navigation = LumenWizardNavigation(current: binding, count: 4, canContinue: true, onFinish: {})
        XCTAssertEqual(navigation.index, 0)
        navigation.clamp()
        XCTAssertEqual(current, 0)
        current = Int.max
        navigation.clamp()
        XCTAssertEqual(current, 3)
        let shortened = LumenWizardNavigation(current: binding, count: 2, canContinue: true, onFinish: {})
        shortened.clamp()
        XCTAssertEqual(current, 1)
    }

    func testBackContinueAndFinishUseTheBoundSelection() {
        var current = 0
        var finishes = 0
        let navigation = LumenWizardNavigation(current: Binding(get: { current }, set: { current = $0 }),
            count: 3, canContinue: true, onFinish: { finishes += 1 })
        XCTAssertFalse(navigation.canGoBack)
        navigation.back()
        XCTAssertEqual(current, 0)
        navigation.advance()
        XCTAssertEqual(current, 1)
        XCTAssertTrue(navigation.canGoBack)
        navigation.back()
        XCTAssertEqual(current, 0)
        navigation.advance()
        navigation.advance()
        XCTAssertEqual(current, 2)
        XCTAssertTrue(navigation.isLast)
        XCTAssertEqual(finishes, 0)
        navigation.advance()
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(current, 2)
    }

    func testValidationBlocksBothContinueAndFinishButAllowsBack() {
        var current = 1
        var finishes = 0
        let navigation = LumenWizardNavigation(current: Binding(get: { current }, set: { current = $0 }),
            count: 2, canContinue: false, onFinish: { finishes += 1 })
        XCTAssertFalse(navigation.canAdvance)
        navigation.advance()
        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(current, 1)
        navigation.back()
        navigation.advance()
        XCTAssertEqual(current, 0)
    }

    func testOnlyCompletedPagesCanBeSelected() {
        var current = 2
        let navigation = LumenWizardNavigation(current: Binding(get: { current }, set: { current = $0 }),
            count: 4, canContinue: false, onFinish: {})
        for target in [-1, 2, 3, Int.max] {
            navigation.goBack(to: target)
            XCTAssertEqual(current, 2)
        }
        navigation.goBack(to: 1)
        XCTAssertEqual(current, 1)
        navigation.goBack(to: 2)
        XCTAssertEqual(current, 1)
        navigation.goBack(to: 0)
        XCTAssertEqual(current, 0)
    }

    func testEmptyPagesNeverAdvanceOrFinish() {
        var current = 8
        var finishes = 0
        let navigation = LumenWizardNavigation(current: Binding(get: { current }, set: { current = $0 }),
            count: 0, canContinue: true, onFinish: { finishes += 1 })
        navigation.clamp()
        XCTAssertEqual(current, 0)
        XCTAssertFalse(navigation.canAdvance)
        XCTAssertFalse(navigation.canGoBack)
        XCTAssertFalse(navigation.isLast)
        navigation.advance()
        navigation.back()
        navigation.goBack(to: 0)
        XCTAssertEqual(current, 0)
        XCTAssertEqual(finishes, 0)
    }

    func testSinglePageFinishesImmediately() {
        var finishes = 0
        let navigation = LumenWizardNavigation(current: .constant(0), count: 1,
            canContinue: true, onFinish: { finishes += 1 })
        XCTAssertTrue(navigation.isLast)
        navigation.advance()
        XCTAssertEqual(finishes, 1)
    }
}
