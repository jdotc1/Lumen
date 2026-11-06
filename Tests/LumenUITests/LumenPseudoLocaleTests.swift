import Foundation
import XCTest
@_spi(LumenLocalizationChecks) @testable import LumenUI

@MainActor
final class LumenPseudoLocaleTests: XCTestCase {
    func testPseudoLocaleExpandsOnlyWithinItsScope() {
        let source = "Settings for Document.swift"
        XCTAssertEqual(lumenLocalized(source), source)
        LumenLocalization.withPseudoLocale(true) {
            let expanded = lumenLocalized(source)
            XCTAssertTrue(expanded.contains(source))
            XCTAssertTrue(expanded.hasPrefix("["))
            XCTAssertTrue(expanded.hasSuffix("]"))
            XCTAssertTrue(expanded.contains("é"))
            XCTAssertGreaterThanOrEqual(expanded.count, Int(ceil(Double(source.count) * 1.3)))
            XCTAssertEqual(lumenLocalized(""), "")
            LumenLocalization.withPseudoLocale(false) {
                XCTAssertEqual(lumenLocalized(source), source)
            }
            XCTAssertEqual(lumenLocalized(source), expanded)
        }
        XCTAssertEqual(lumenLocalized(source), source)
    }

    func testPseudoLocaleRestoresAfterThrowing() {
        enum SampleError: Error { case expected }
        XCTAssertThrowsError(try LumenLocalization.withPseudoLocale(true) { throw SampleError.expected })
        XCTAssertEqual(lumenLocalized("Settings"), "Settings")
    }
}
