import AppKit
import CoreText
import XCTest
import SwiftUI
import LumenTestSupport
@_spi(LayoutAudit) @testable import LumenUI

@MainActor final class LumenCompositeTextOwnerTests: XCTestCase {
    func testPrefixAndDigitsUseCompositeBoundaryWithoutHidingOverflow() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 180, height: 90,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 90))
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        func draw(_ string: String, x: CGFloat) -> CGFloat {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: NSColor.black,
            ]))
            context.textPosition = CGPoint(x: x, y: 40)
            CTLineDraw(line, context)
            return ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        let prefixWidth = draw("0x", x: 30)
        let digitsX = 30 + prefixWidth
        let digitsWidth = draw("100003f0c", x: digitsX)
        let image = try XCTUnwrap(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 180, height: 90)
        let recognized = CGRect(x: 28, y: 36, width: prefixWidth + digitsWidth + 4, height: 20)
        let observation = LumenRenderedAudit.Line(text: "0x100003f0c", frame: recognized,
                                                  confidence: 1, inkPixels: 200)
        for overflow in [false, true] {
            let composite = CGRect(x: 26, y: 34, width: prefixWidth + digitsWidth + 8 - (overflow ? 12 : 0), height: 24)
            let elements: [LumenRenderedAudit.Element] = [
                .init(identity: "root", ancestors: [], frame: frame, source: "", control: false, clip: nil),
                .init(identity: "address", ancestors: ["root"], frame: composite, source: "", control: false, clip: nil),
                .init(identity: "prefix", ancestors: ["root", "address"],
                      frame: CGRect(x: 30, y: 36, width: prefixWidth, height: 20), source: "0x", control: false, clip: nil),
                .init(identity: "digits", ancestors: ["root", "address"],
                      frame: CGRect(x: digitsX, y: 36, width: digitsWidth, height: 20), source: "100003f0c", control: true, clip: nil),
            ]
            let capture = LumenRenderedAudit.Capture(image: image, frame: frame, usable: frame,
                chrome: .zero, exclusions: [], elements: elements, clips: [], drawingBounds: [],
                margin: nil, scaffoldMargins: [], reports: [])
            let result = try LumenRenderedAudit.analyze(capture, recognizedLines: [observation])
            let findings = result.findings.filter { $0.rule == "rendered-text-geometry" }
            print("COMPOSITE-TEXT overflow=\(overflow) boundary=\(composite) findings=\(findings)")
            XCTAssertEqual(findings.count, overflow ? 1 : 0, "\(result.findings)")
            if overflow { XCTAssertTrue(findings.first?.message.contains("owner=address") == true) }
        }
    }

    func testHostedDeclaredAddressCompositeKeepsItsOverflowBoundary() throws {
        let root = LumenAddressField(text: .constant("100003f0c")) { _ in }
            .padding(20).lumenPaletteRoot()
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.order(window)
        defer { window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        var capture = try LumenRenderedAudit.capture(in: window)
        let digits = try XCTUnwrap(capture.elements.first { $0.source == "100003f0c" })
        let composite = try XCTUnwrap(capture.compositeOwners.filter {
            $0.identity.hasPrefix("lumen-composite:") && digits.ancestors.contains($0.identity)
        }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        print("HOSTED-COMPOSITE digits=\(digits.frame) owner=\(composite.frame)")
        XCTAssertTrue(composite.frame.contains(digits.frame))
        XCTAssertLessThan(composite.frame.width, capture.usable.width, "Composite must not fall back to the whole window")
        let recognized = CGRect(x: composite.frame.minX + 6, y: digits.frame.minY,
            width: digits.frame.maxX - composite.frame.minX - 6, height: digits.frame.height)
        let line = LumenRenderedAudit.Line(text: "0x100003f0c", frame: recognized,
                                          confidence: 1, inkPixels: 100)
        let valid = try LumenRenderedAudit.analyze(capture, recognizedLines: [line])
        XCTAssertFalse(valid.findings.contains { $0.rule == "rendered-text-geometry" && $0.view == line.text },
                       "\(valid.findings)")
        // Preserve the sole hosted bitmap and observation; move only the declared ownership
        // boundary across the actual prefix glyphs. The text must not escape to a wider owner.
        let narrowed = CGRect(x: digits.frame.minX, y: composite.frame.minY,
            width: composite.frame.maxX - digits.frame.minX, height: composite.frame.height)
        capture.compositeOwners = capture.compositeOwners.map { owner in
            guard owner.identity == composite.identity else { return owner }
            return .init(identity: owner.identity, ancestors: owner.ancestors, frame: narrowed,
                         source: owner.source, control: owner.control, clip: owner.clip)
        }
        let overflow = try LumenRenderedAudit.analyze(capture, recognizedLines: [line])
        XCTAssertTrue(overflow.findings.contains {
            $0.rule == "rendered-text-geometry" && $0.view == line.text && $0.message.contains("owner=lumen-composite:")
        }, "\(overflow.findings)")
        print("HOSTED-COMPOSITE overflowBoundary=\(narrowed) valid=\(valid.findings) overflow=\(overflow.findings)")
    }

    func testSiblingDeclarationsChooseNearestCommonComposite() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 180, height: 90,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 90))
        let text = CTLineCreateWithAttributedString(NSAttributedString(string: "0x100003f0c", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.black,
        ]))
        context.textPosition = CGPoint(x: 30, y: 40)
        CTLineDraw(text, context)
        let image = try XCTUnwrap(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 180, height: 90)
        let ancestor = "lumen-composite:outer", grandparent = "lumen-composite:root"
        let prefix = CGRect(x: 30, y: 36, width: 16, height: 20)
        let digits = CGRect(x: 46, y: 36, width: 76, height: 20)
        let elements: [LumenRenderedAudit.Element] = [
            .init(identity: "prefix", ancestors: [ancestor, grandparent, "lumen-composite:prefix"],
                  frame: prefix, source: "0x", control: false, clip: nil),
            .init(identity: "digits", ancestors: [ancestor, grandparent, "lumen-composite:digits"],
                  frame: digits, source: "100003f0c", control: false, clip: nil),
        ]
        let line = LumenRenderedAudit.Line(text: "0x100003f0c", frame: CGRect(x: 28, y: 35, width: 96, height: 21),
                                          confidence: 1, inkPixels: 100)
        var capture = LumenRenderedAudit.Capture(image: image, frame: frame, usable: frame,
            chrome: .zero, exclusions: [], elements: elements, clips: [], drawingBounds: [],
            margin: nil, scaffoldMargins: [], reports: [])
        for overflow in [false, true] {
            capture.compositeOwners = [
                .init(identity: grandparent, ancestors: [], frame: frame, source: "", control: false, clip: nil),
                .init(identity: ancestor, ancestors: [grandparent],
                      frame: CGRect(x: 26, y: 34, width: overflow ? 80 : 100, height: 24), source: "", control: false, clip: nil),
                .init(identity: "lumen-composite:prefix", ancestors: [ancestor, grandparent], frame: prefix,
                      source: "", control: false, clip: nil),
                .init(identity: "lumen-composite:digits", ancestors: [ancestor, grandparent], frame: digits,
                      source: "", control: false, clip: nil),
            ]
            let result = try LumenRenderedAudit.analyze(capture, recognizedLines: [line])
            let findings = result.findings.filter { $0.rule == "rendered-text-geometry" }
            XCTAssertEqual(findings.count, overflow ? 1 : 0, "\(result.findings)")
            if overflow { XCTAssertTrue(findings.first?.message.contains("owner=\(ancestor) ") == true) }
            print("SIBLING-COMPOSITES overflow=\(overflow) findings=\(findings)")
        }
    }

}
