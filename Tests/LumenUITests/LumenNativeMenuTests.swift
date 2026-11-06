import AppKit
import XCTest
@testable import LumenUI

@MainActor
final class LumenNativeMenuTests: XCTestCase {
    func testOrdinaryItemKeepsSystemImagePolicy() throws {
        let item = LumenMenuLabel("Open", systemImage: "folder.fill", hue: .hueBlue).makeMenuItem()
        XCTAssertEqual(item.title, "Open")
        XCTAssertFalse(try XCTUnwrap(item.image).isTemplate)
        XCTAssertNil(item.action)
        XCTAssertEqual(item.preferredImageVisibility, .automatic)
    }

    func testMeaningfulGlyphOptsIntoVisibility() throws {
        let item = LumenMenuLabel("Healthy", systemImage: "circle.fill", hue: .hueGreen)
            .makeMenuItem(imageCarriesMeaning: true, colorScheme: .dark)
        XCTAssertNotNil(item.image)
        XCTAssertEqual(item.preferredImageVisibility, .visible)
    }
}
