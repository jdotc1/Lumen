import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenEditorSizingTests: XCTestCase {
    private func size(of view: some View, width: CGFloat = 1000, scale: Double = 1) -> CGSize {
        NSHostingController(rootView: view
            .environment(\.lumenRendersOffscreen, true)
            .lumenMetrics(.resolving(nil, textScale: scale)))
            .sizeThatFits(in: CGSize(width: width, height: 1000))
    }

    func testSliderValueMeasureIncludesFormattedEndpointsAndGrowsWithText() {
        let short = LumenSlider(value: .constant(1), in: 0...9, showsField: true).fixedSize()
        let long = LumenSlider(value: .constant(1), in: -100_000...100_000, showsField: true).fixedSize()
        let shortSize = size(of: short)
        let longSize = size(of: long)
        XCTAssertGreaterThan(longSize.width, shortSize.width,
                             "An endpoint with separators must reserve more room even when the current value is short")
        XCTAssertGreaterThan(size(of: long, scale: 1.3).width, longSize.width)
    }

    func testSliderStacksItsValueBelowTheExplicitTrackInANarrowHost() {
        let slider = LumenSlider(value: .constant(10_000), in: 0...10_000, showsField: true, unit: "ms", width: 160)
        let wide = size(of: slider, width: 400)
        let narrow = size(of: slider, width: 200)
        XCTAssertLessThanOrEqual(narrow.width, 200.5)
        XCTAssertGreaterThanOrEqual(narrow.width, 160, "The caller's explicit track width remains intact")
        XCTAssertGreaterThan(narrow.height, wide.height, "The value and unit must move below the track")
        XCTAssertLessThanOrEqual(size(of: slider, width: 200, scale: 1.3).width, 200.5)
    }

    func testBoundedPopupWrapsTheSelectionWithinTheHostProposal() {
        let title = "A long selected deployment configuration"
        let popup = LumenPopUp(selection: .constant(title), options: [title], title: { $0 }).maximumWidth(300)
        let wide = size(of: popup, width: 300)
        let narrow = size(of: popup, width: 140)
        XCTAssertLessThanOrEqual(narrow.width, 140.5)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertGreaterThan(size(of: popup, width: 140, scale: 1.3).height, narrow.height)
    }

    func testRuleRowsStackWhenThePickersAndValueCannotShareARow() {
        let rule = LumenRuleEditor(match: .constant(.all),
            conditions: .constant([LumenRuleCondition(field: "Deployment configuration", comparison: "contains", value: "Release")]),
            fields: ["Deployment configuration"], comparisons: { _ in ["contains", "does not contain"] })
        let wide = size(of: rule, width: 700)
        let narrow = size(of: rule, width: 240)
        XCTAssertLessThanOrEqual(narrow.width, 240.5)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }
}
