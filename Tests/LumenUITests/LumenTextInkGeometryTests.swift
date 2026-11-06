import AppKit
import CoreText
import XCTest
@_spi(LayoutAudit) @testable import LumenUI

@MainActor final class LumenTextInkGeometryTests: XCTestCase {
    func testPaddedRecognitionBoxPassesButActualGlyphOverflowFails() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 100,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        let text = NSAttributedString(string: "Alex", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black,
        ])
        let textLine = CTLineCreateWithAttributedString(text)
        let width = ceil(CTLineGetTypographicBounds(textLine, nil, nil, nil))
        context.textPosition = CGPoint(x: 40, y: 40)
        CTLineDraw(textLine, context)
        let image = try XCTUnwrap(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 160, height: 100)
        let recognized = CGRect(x: 35, y: 36, width: width + 10, height: 20)
        let line = LumenRenderedAudit.Line(text: "Alex", frame: recognized,
                                           confidence: 1, inkPixels: 100)
        for overflow in [false, true] {
            // Identical real glyph pixels and recognition; only the owner's layout changes.
            // The narrow owner leaves actual glyphs outside, not merely OCR background.
            let owner = CGRect(x: 40, y: 36, width: width - (overflow ? 6 : 0), height: 20)
            let capture = LumenRenderedAudit.Capture(image: image, frame: frame, usable: frame,
                chrome: .zero, exclusions: [],
                elements: [.init(identity: "value", ancestors: [], frame: owner,
                                 source: "Alex", control: false, clip: nil)],
                clips: [], drawingBounds: [], margin: nil, scaffoldMargins: [], reports: [])
            let result = try LumenRenderedAudit.analyze(capture, recognizedLines: [line])
            let findings = result.findings.filter { $0.rule == "rendered-text-geometry" }
            print("TEXT-INK overflow=\(overflow) owner=\(owner) recognized=\(recognized) findings=\(findings)")
            XCTAssertEqual(findings.count, overflow ? 1 : 0, "\(result.findings)")
            if overflow {
                XCTAssertTrue(findings.first?.message.contains("inkFrame=") == true)
                XCTAssertTrue(findings.first?.message.contains("ownerFrame=") == true)
                XCTAssertTrue(findings.first?.message.contains("recognizedBox=") == true)
            }
        }
    }
}
