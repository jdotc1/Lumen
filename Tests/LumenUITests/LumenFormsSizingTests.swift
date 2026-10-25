import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenFormsSizingTests: XCTestCase {
    private func intrinsicWidth(of view: some View, scale: Double) -> CGFloat {
        NSHostingView(rootView: view
            .lumenMetrics(.resolving(nil, textScale: scale))
            .environment(\.lumenRendersOffscreen, true)
            .fixedSize()).fittingSize.width
    }

    func testAutomaticNumberFieldFitsTheRangeAndGrowsWithText() {
        let small = LumenNumberField(value: .constant(1), in: 0...9)
        let large = LumenNumberField(value: .constant(99_999), in: -99_999...99_999)
        XCTAssertGreaterThan(intrinsicWidth(of: large, scale: 1), intrinsicWidth(of: small, scale: 1))
        XCTAssertGreaterThan(intrinsicWidth(of: large, scale: 1.3), intrinsicWidth(of: large, scale: 1))
    }

    func testExplicitNumberWidthRemainsExactAtLargerText() {
        let field = LumenNumberField(value: .constant(99_999), in: 0...99_999, width: 80)
        let standard = LumenMetrics.standard
        let scaled = LumenMetrics.resolving(nil, textScale: 1.3)
        XCTAssertEqual(intrinsicWidth(of: field, scale: 1), 80 + LumenNumberField.stepperWidth + standard.spacing.s1, accuracy: 0.5)
        XCTAssertEqual(intrinsicWidth(of: field, scale: 1.3), 80 + LumenNumberField.stepperWidth + scaled.spacing.s1, accuracy: 0.5)
    }

    func testNumberFieldStacksUnitInsideAnEightyPointHost() {
        let field = LumenNumberField(value: .constant(99_999), in: 0...99_999, unit: "files")
        let host = NSHostingController(rootView: field.lumenMetrics(.standard))
        let narrow = host.sizeThatFits(in: CGSize(width: 80, height: 60))
        let wide = host.sizeThatFits(in: CGSize(width: 200, height: 60))
        XCTAssertLessThanOrEqual(narrow.width, 80)
        XCTAssertLessThanOrEqual(narrow.height, 60)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    /// Compare rendered ink from identical digits, independently of the exported alignment guides.
    /// The label is shared with the extras font row; both live TextField and offscreen Text
    /// must share its baseline, including when the unit occupies a second row.
    func testNumberTextBaselineMatchesPickerAcrossThemesScalesAndUnitLayouts() throws {
        let store = TestPack.store()
        let palette = LumenResolvedPalette(key: store.resolvedPalette().key, colors: [.fgPrimary: .red])
        for theme in [LumenThemes.standard, LumenThemes.contrast] {
            for scale in [1.0, 1.3] {
                let metrics = LumenMetrics.resolving(theme.metrics, textScale: scale)
                for stacked in [false, true] {
                    for live in [false, true] {
                        let name = "\(theme.name)-\(scale)-\(stacked ? "stacked" : "inline")-\(live ? "live" : "image")"
                        let view = HStack(alignment: .firstTextBaseline, spacing: 20) {
                            LumenMenuButton { Button("13") {} } label: {
                                LumenFontPickerLabel("13", font: metrics.typography.body, minWidth: 100, maxWidth: 100)
                            }
                            LumenNumberField(value: .constant(13), in: 0...99, unit: "points", width: 52)
                                .frame(width: stacked ? 80 : 220, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                        .lumenMetrics(metrics)
                        .environment(\.lumenPalette, palette)
                        let png = try XCTUnwrap(LumenSnapshot.png(of: view, size: CGSize(width: 380, height: 100),
                            variant: .init(themeID: theme.id, colorScheme: .light), registry: .core,
                            scale: 2, renderer: live ? .window : .image), name)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png), name)
                        let image = try XCTUnwrap(bitmap.cgImage, name)
                        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), name)
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                        // Only primary text is red; borders, chevrons and the unit cannot enter the measurement.
                        func inkBottom(in columns: Range<Int>) throws -> CGFloat {
                            var rows: [Int] = []
                            for y in 0..<bitmap.pixelsHigh {
                                for x in columns {
                                    let offset = (y * image.width + x) * 4
                                    if pixels[offset] > 153, pixels[offset + 1] < 77, pixels[offset + 2] < 77 {
                                        rows.append(y)
                                    }
                                }
                            }
                            return CGFloat(try XCTUnwrap(rows.max(), name)) / 2
                        }
                        let picker = try inkBottom(in: 20..<220)
                        let number = try inkBottom(in: 260..<364)
                        XCTAssertEqual(number, picker, accuracy: 0.5, name)
                        print("Number baseline \(name): delta=\(number - picker) pt")
                        let directory = URL(fileURLWithPath: ".build/number-baselines", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try png.write(to: directory.appending(path: name + ".png"))
                    }
                }
            }
        }
    }

    func testOversizedSentencePhraseWrapsInsideHost() {
        let row = LumenSentenceRow {
            LumenSentenceText("Only upload the project after all background indexing has completed")
        }
        let host = NSHostingController(rootView: row.lumenMetrics(.standard))
        let narrow = host.sizeThatFits(in: CGSize(width: 160, height: 600))
        let wide = host.sizeThatFits(in: CGSize(width: 600, height: 600))
        XCTAssertLessThanOrEqual(narrow.width, 160)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    func testIntegrationIdentityStacksBeforeItTruncates() {
        let row = LumenIntegrationRow(isOn: .constant(true), name: "Project Language Integration",
                                     detail: "A language service for this project", status: .running,
                                     onRefresh: {}, onInfo: {})
        let host = NSHostingController(rootView: row.lumenMetrics(.standard))
        let narrow = host.sizeThatFits(in: CGSize(width: 220, height: 600))
        let wide = host.sizeThatFits(in: CGSize(width: 600, height: 600))
        XCTAssertLessThanOrEqual(narrow.width, 220)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }
}
