import SwiftUI
import XCTest
@testable import LumenUI

final class LumenSettingsHistoryTests: XCTestCase {
    func testBackForwardEndsAndBranching() {
        var history = LumenSettingsHistory()
        XCTAssertNil(history.goBack(from: "engine"))
        XCTAssertNil(history.goForward(from: "engine"))
        history.visit(from: "engine", to: "reports")
        history.visit(from: "reports", to: "appearance")
        XCTAssertEqual(history.goBack(from: "appearance"), "reports")
        XCTAssertEqual(history.goBack(from: "reports"), "engine")
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.goForward(from: "engine"), "reports")
        history.visit(from: "reports", to: "shortcuts")
        XCTAssertFalse(history.canGoForward, "A new visit discards the forward branch")
        XCTAssertEqual(history.goBack(from: "shortcuts"), "reports")
    }

    func testDuplicateVisitsAndRemovedCategories() {
        var history = LumenSettingsHistory()
        history.visit(from: "engine", to: "reports")
        history.visit(from: "reports", to: "reports")
        XCTAssertEqual(history.back, ["engine"])
        history.visit(from: "reports", to: "appearance")
        history.retain(["engine", "appearance"])
        XCTAssertEqual(history.goBack(from: "appearance"), "engine")
        XCTAssertEqual(history.goForward(from: "engine"), "appearance")
    }

    func testRemovingCurrentCategoryDoesNotCreateSelfDestination() {
        var history = LumenSettingsHistory()
        history.visit(from: "engine", to: "reports")
        history.retain(["engine"])
        history.discardCurrent("engine")
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertNil(history.goBack(from: "engine"))
    }

    func testPruningIntermediateCategoryDiscardsCurrentHistoryHead() {
        var history = LumenSettingsHistory()
        history.visit(from: "engine", to: "reports")
        history.visit(from: "reports", to: "engine")
        history.retain(["engine"])
        history.discardCurrent("engine")
        XCTAssertFalse(history.canGoBack)
        XCTAssertNil(history.goBack(from: "engine"))
    }

    func testSearchEmptyStateKeepsReturnHistory() {
        var history = LumenSettingsHistory()
        history.visit(from: "engine", to: nil)
        XCTAssertEqual(history.goBack(from: nil), "engine")
        XCTAssertFalse(history.canGoForward, "An empty search result is not a category")
    }

    @MainActor
    func testInitialSelectionNormalization() {
        let categories = [
            LumenSettingsCategory(id: "engine", title: "Engine", systemImage: "cpu", hue: .hueBlue) { EmptyView() },
            LumenSettingsCategory(id: "reports", title: "Reports", systemImage: "doc", hue: .hueGreen) { EmptyView() }
        ]
        XCTAssertEqual(LumenSettingsSidebarView.validSelection("reports", in: categories), "reports")
        XCTAssertEqual(LumenSettingsSidebarView.validSelection("missing", in: categories), "engine")
        XCTAssertEqual(LumenSettingsSidebarView.validSelection(nil, in: categories), "engine")
        XCTAssertNil(LumenSettingsSidebarView.validSelection("engine", in: []))
    }
}
