import AppKit
import XCTest
@testable import LumenUI

@MainActor
final class LumenStatusGlyphTests: XCTestCase {
    func testSymbolsAndLumenGlyphsProduceTemplatesWithDistinctMarks() throws {
        for name in ["bolt", "lumen.lens", "lumen.token"] {
            let plain = try XCTUnwrap(LumenStatusGlyph(name).templateImage())
            let badge = try XCTUnwrap(LumenStatusGlyph(name, attention: .badge).templateImage())
            let attention = try XCTUnwrap(LumenStatusGlyph(name, attention: .attention).templateImage())
            XCTAssertTrue([plain, badge, attention].allSatisfy(\.isTemplate))
            XCTAssertEqual(plain.size, CGSize(width: 18, height: 18))
            XCTAssertEqual(badge.size, CGSize(width: 24, height: 18))
            XCTAssertEqual(attention.size, badge.size)
            XCTAssertNotEqual(badge.tiffRepresentation, attention.tiffRepresentation)
            for image in [plain, badge, attention] {
                let data = try XCTUnwrap(image.tiffRepresentation)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                var ink = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { ink += 1 }
                    }
                }
                XCTAssertGreaterThan(ink, 10)
                XCTAssertLessThan(ink, bitmap.pixelsHigh * bitmap.pixelsWide)
            }
        }
    }

    func testUnknownSymbolReturnsNilAndAttentionIsPartOfIdentity() {
        XCTAssertNil(LumenStatusGlyph("not.a.real.symbol.lumen-test").templateImage())
        XCTAssertEqual(Set([LumenStatusGlyph("bolt"), .init("bolt", attention: .badge),
                            .init("bolt", attention: .attention)]).count, 3)
    }

    func testRegisteredDrawingProducesATemplate() throws {
        LumenGlyph.register([LumenGlyph(id: "menuBarTest", title: "Test", family: "Tests") { drawing in
            drawing.fill.addRect(CGRect(x: 6, y: 6, width: 12, height: 12))
        }])
        XCTAssertTrue(try XCTUnwrap(LumenStatusGlyph("lumen.menuBarTest").templateImage()).isTemplate)
    }
}
