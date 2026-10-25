import AppKit
import CoreText
import XCTest
@_spi(LayoutAudit) @testable import LumenUI

@MainActor final class LumenTextInkOverlapTests: XCTestCase {
    func testPaddedBoxesBetweenSeparateBaselinesPassButOverlappingStringsFail() throws {
        for overlapping in [false, true] {
            let scale: CGFloat = 2
            let frame = CGRect(x: 0, y: 0, width: 160, height: 100)
            let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 200,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(frame)
            let first = CTLineCreateWithAttributedString(NSAttributedString(string: "BASELINE", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black,
            ]))
            let second = CTLineCreateWithAttributedString(NSAttributedString(string: "SECOND", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black,
            ]))
            let firstBounds = CTLineGetImageBounds(first, context)
            let secondBounds = CTLineGetImageBounds(second, context)
            let firstOrigin = CGPoint(x: 40, y: 40)
            // Four points of clear background separate the glyph baselines' visible ink.
            let secondOrigin = CGPoint(x: 40, y: overlapping ? 44 : 40 + firstBounds.maxY - secondBounds.minY + 4)
            context.textPosition = firstOrigin
            CTLineDraw(first, context)
            context.textPosition = secondOrigin
            CTLineDraw(second, context)
            let firstInk = firstBounds.offsetBy(dx: firstOrigin.x, dy: firstOrigin.y)
            let secondInk = secondBounds.offsetBy(dx: secondOrigin.x, dy: secondOrigin.y)
            let boxes = [firstInk.insetBy(dx: -2, dy: -3), secondInk.insetBy(dx: -2, dy: -3)]
            XCTAssertGreaterThan(boxes[0].intersection(boxes[1]).height, 1)
            let lines = zip(["BASELINE", "SECOND"], boxes).map {
                LumenRenderedAudit.Line(text: $0.0, frame: $0.1, confidence: 1, inkPixels: 100)
            }
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()),
                frame: frame, usable: frame, chrome: .zero, exclusions: [], elements: [],
                clips: [], drawingBounds: [], margin: nil, scaffoldMargins: [], reports: [])
            let result = try LumenRenderedAudit.analyze(capture, recognizedLines: lines)
            let findings = result.findings.filter { $0.rule == "rendered-text-geometry" }
            print("TEXT-OVERLAP overlap=\(overlapping) glyphs=\(firstInk),\(secondInk) OCR=\(boxes) findings=\(findings)")
            XCTAssertEqual(findings.count, overlapping ? 1 : 0, "\(result.findings)")
        }
    }
}
