import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenMetadataRowTests: XCTestCase {
    private let digest = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { self.textField(in: $0) }.first
    }

    private func host<V: View>(_ view: V, width: CGFloat) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func row(_ value: String? = nil, width: CGFloat, scale: CGFloat = 1,
                     direction: LayoutDirection = .leftToRight) -> NSHostingView<some View> {
        host(LumenMetadataRow(label: "SHA-256", value: value ?? digest)
            .lumenTextScale(scale)
            .environment(\.layoutDirection, direction), width: width)
    }

    func testValueIsSelectableCharacterWrappedAndExact() throws {
        let field = try XCTUnwrap(textField(in: row(width: 220)))
        XCTAssertEqual(field.stringValue, digest, "No break hints are inserted, so copy is exact")
        XCTAssertEqual(field.attributedStringValue.string, digest)
        XCTAssertTrue(field.isSelectable)
        XCTAssertFalse(field.isEditable)
        XCTAssertEqual(field.lineBreakMode, .byCharWrapping)
        XCTAssertEqual(field.maximumNumberOfLines, 0)
        XCTAssertEqual(field.toolTip, digest)
    }

    func testHeightGrowsWhenNarrowAndNothingOverflows() throws {
        let narrow = row(width: 160)
        let wide = row(width: 700)
        XCTAssertGreaterThan(narrow.fittingSize.height, wide.fittingSize.height)
        let field = try XCTUnwrap(textField(in: narrow))
        XCTAssertLessThanOrEqual(field.convert(field.bounds, to: narrow).maxX, 160 + 0.5)
        let needed = ceil(try XCTUnwrap(field.cell).cellSize(forBounds: field.bounds).height)
        XCTAssertGreaterThanOrEqual(field.frame.height + 1, needed, "Every wrapped line is given room")
    }

    func testTextScaleGrowsFontAndHeight() throws {
        let small = row(width: 200, scale: 1)
        let large = row(width: 200, scale: 1.5)
        let smallField = try XCTUnwrap(textField(in: small))
        let largeField = try XCTUnwrap(textField(in: large))
        let smallSize = try XCTUnwrap(smallField.font).pointSize
        let largeSize = try XCTUnwrap(largeField.font).pointSize
        XCTAssertGreaterThan(largeSize, smallSize)
        XCTAssertGreaterThan(large.fittingSize.height, small.fittingSize.height)
    }

    func testRightToLeftMirrorsLabelAndValue() throws {
        // Frames are compared in the row's coordinates: the field's own frame is relative to its
        // SwiftUI wrapper.
        let ltrHost = row(width: 400)
        let ltr = try XCTUnwrap(textField(in: ltrHost))
        XCTAssertGreaterThan(ltr.convert(ltr.bounds, to: ltrHost).minX, 40, "Label column leads on the left")
        let rtlHost = row(width: 400, direction: .rightToLeft)
        let rtl = try XCTUnwrap(textField(in: rtlHost))
        XCTAssertLessThan(rtl.convert(rtl.bounds, to: rtlHost).maxX, 400 - 40, "Label column leads on the right")
        XCTAssertEqual(rtl.userInterfaceLayoutDirection, .rightToLeft)
    }

    func testAccessibilityValueHoldsFullString() throws {
        let field = try XCTUnwrap(textField(in: row(width: 200)))
        let spoken = field.accessibilityValue() as? String ?? field.stringValue
        XCTAssertEqual(spoken, digest)
    }

    func testGraphemeClustersSurviveIntact() throws {
        let value = "e\u{301}👩🏽‍💻🇨🇦" + String(repeating: "a\u{308}", count: 40)
        let field = try XCTUnwrap(textField(in: row(value, width: 120)))
        XCTAssertEqual(field.stringValue, value)
        XCTAssertGreaterThan(field.frame.height, 0)
    }

    func testEmptyValueKeepsMinimumHeight() {
        let empty = row("", width: 200)
        XCTAssertGreaterThanOrEqual(empty.fittingSize.height, 24)
    }
}
