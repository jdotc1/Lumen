import AppKit
import LumenTokens
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenFieldChromeTests: XCTestCase {
    private struct AccentReference: View {
        @Environment(\.lumenPalette) private var palette
        var body: some View { palette[.accent] }
    }

    func testFocusedFieldRingUsesAccentRatherThanIndependentBorderToken() throws {
        // Ultraviolet deliberately gives border.focus and accent.default different values.
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.ultravioletID, colorScheme: .dark)
        let ring = try bitmap(Color.clear.lumenChrome(.field, focused: true), variant: variant)
        let reference = try bitmap(AccentReference(), variant: variant)
        try assertColor(ring.colorAt(x: ring.pixelsWide / 2, y: 0),
                        equals: reference.colorAt(x: reference.pixelsWide / 2, y: 0))
        XCTAssertEqual(LumenFieldChrome.focusToken, .accent,
                       "Text, number, search and address field outlines must use the caret accent")
    }

    func testSettingsFieldsUseNativeTextWellInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let variant = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: scheme)
            let field = try bitmap(Color.clear.lumenChrome(.field)
                .environment(\.lumenSettingsWindow, true), variant: variant)
            let reference = try bitmap(Color(nsColor: .textBackgroundColor), variant: variant)
            try assertColor(field.colorAt(x: field.pixelsWide / 2, y: field.pixelsHigh / 2),
                            equals: reference.colorAt(x: reference.pixelsWide / 2, y: reference.pixelsHigh / 2))
        }
    }

    private func bitmap<V: View>(_ view: V, variant: LumenSnapshot.Variant) throws -> NSBitmapImageRep {
        let data = try XCTUnwrap(LumenSnapshot.png(of: view, size: CGSize(width: 160, height: 32),
                                                  variant: variant, registry: .core))
        return try XCTUnwrap(NSBitmapImageRep(data: data))
    }

    private func assertColor(_ actual: NSColor?, equals expected: NSColor?,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual?.usingColorSpace(.sRGB), file: file, line: line)
        let expected = try XCTUnwrap(expected?.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 1 / 255, file: file, line: line)
    }
}
