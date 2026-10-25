import AppKit
import CoreText
import SwiftUI
import LumenTestSupport
import XCTest
@_spi(LayoutAudit) @testable import LumenUI

@MainActor final class LumenFullBleedBackgroundTests: XCTestCase {
    func testDeclaredFillPreservesGlyphAndStrokeMarginChecks() throws {
        let frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        let fill = CGRect(x: 0, y: 0, width: 60, height: 120)
        func result(declared: Bool, glyph: Bool, stroke: Bool) throws -> LumenRenderedAudit.Result {
            let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 120,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(frame)
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)); context.fill(fill)
            if glyph {
                let text = NSAttributedString(string: "M", attributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
                context.textPosition = CGPoint(x: 3, y: 50)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            if stroke {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 4, y: 25, width: 4, height: 10))
            }
            var capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()),
                frame: frame, usable: frame, chrome: .zero, exclusions: [], elements: [], clips: [],
                drawingBounds: [], margin: 16, scaffoldMargins: [], reports: [])
            if declared { capture.fullBleedBackgrounds = [.init(frame: fill, red: 51, green: 77, blue: 102)] }
            return try LumenRenderedAudit.analyze(capture, recognizedLines: [])
        }
        let declared = try result(declared: true, glyph: false, stroke: false)
        XCTAssertTrue(declared.findings.isEmpty, "Declared hero fill: \(declared.findings)")
        let undeclared = try result(declared: false, glyph: false, stroke: false)
        XCTAssertTrue(undeclared.findings.contains { $0.rule == "rendered-margin" })
        let glyph = try result(declared: true, glyph: true, stroke: false)
        XCTAssertTrue(glyph.findings.contains { $0.rule == "rendered-margin" }, "Glyph on fill: \(glyph.findings)")
        let stroke = try result(declared: true, glyph: false, stroke: true)
        XCTAssertTrue(stroke.findings.contains { $0.rule == "rendered-margin" }, "Stroke on fill: \(stroke.findings)")
        print("FULL-BLEED declared=\(declared.findings.count) undeclared=\(undeclared.findings.count) glyph=\(glyph.findings.count) stroke=\(stroke.findings.count)")
    }

    func testHostedDeclarationMeasuresPigmentWithoutChangingPixels() throws {
        let color = Color(red: 0.2, green: 0.3, blue: 0.4)
        let frame = CGRect(x: 0, y: 0, width: 160, height: 120)
        func capture(declared: Bool) throws -> LumenRenderedAudit.Capture {
            let root = declared ? AnyView(color.lumenFullBleedBackground()) : AnyView(color)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(contentRect: frame,
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            LumenHeadlessHost.prepare(window)
            defer { window.close() }
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertFalse(NSApp.isActive)
            return try LumenRenderedAudit.capture(in: window)
        }
        let plain = try capture(declared: false)
        let declared = try capture(declared: true)
        XCTAssertTrue(plain.fullBleedBackgrounds.isEmpty)
        let fill = try XCTUnwrap(declared.fullBleedBackgrounds.count == 1 ? declared.fullBleedBackgrounds.first : nil)
        XCTAssertEqual(fill.frame, declared.frame)
        let plainData = try XCTUnwrap(plain.image.dataProvider?.data) as Data
        let declaredData = try XCTUnwrap(declared.image.dataProvider?.data) as Data
        XCTAssertEqual(plainData, declaredData, "A declaration cannot change background rendering")
        var bytes = [UInt8](repeating: 0, count: 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(declared.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(rendered)
        for (actual, expected) in zip(bytes.prefix(3).map(Int.init), [fill.red, fill.green, fill.blue]) {
            XCTAssertLessThanOrEqual(abs(actual - expected), 1)
        }
        print("FULL-BLEED-HOST frame=\(fill.frame) pigment=\([fill.red, fill.green, fill.blue]) pixel=\(bytes) unchanged=\(plainData == declaredData)")
    }

}
