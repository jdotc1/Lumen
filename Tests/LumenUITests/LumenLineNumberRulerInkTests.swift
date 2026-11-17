import AppKit
import XCTest
import LumenTestSupport
@testable import LumenUI

@MainActor
final class LumenLineNumberRulerInkTests: XCTestCase {
    private final class Canvas: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.textBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }

    func testTextInkInAqua() throws { try assertTextInk(in: .aqua) }
    func testTextInkInDarkAqua() throws { try assertTextInk(in: .darkAqua) }

    private func assertTextInk(in name: NSAppearance.Name) throws {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        // Independent fixtures keep the no-ruler control free of ruler installation effects.
        for hasRuler in [false, true] {
            let frame = NSRect(x: 0, y: 0, width: 640, height: 320)
            let canvas = Canvas(frame: frame)
            let scroll = NSScrollView(frame: frame)
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let text = NSTextView(frame: frame)
            text.isHorizontallyResizable = true
            text.isVerticallyResizable = true
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 12, height: 8)
            text.textStorage?.setAttributedString(NSAttributedString(
                string: "alpha() {\n  let beta = 1;\n  let gamma = 2;\n  beta += gamma;\n  return beta;\n}",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .foregroundColor: NSColor.textColor]))
            scroll.documentView = text
            let ruler = hasRuler
                ? LumenLineNumberRuler.install(on: text, palette: TestPack.store().resolvedPalette())
                : nil
            canvas.addSubview(scroll)
            let window = LumenHeadlessHost.window(contentRect: frame, styleMask: .borderless,
                                                  backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            defer { window.contentView = nil; window.close() }
            window.appearance = appearance
            window.contentView = canvas
            canvas.layoutSubtreeIfNeeded()
            let manager = try XCTUnwrap(text.layoutManager)
            let container = try XCTUnwrap(text.textContainer)
            manager.ensureLayout(for: container)
            let viewport = canvas.convert(scroll.contentView.bounds, from: scroll.contentView)
            var textRects: [NSRect] = []
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, _, _ in
                let rect = canvas.convert(used.offsetBy(dx: text.textContainerOrigin.x,
                                                       dy: text.textContainerOrigin.y), from: text)
                    .intersection(viewport)
                if !rect.isEmpty && !rect.isNull { textRects.append(rect) }
            }
            XCTAssertFalse(textRects.isEmpty, "The fixture must lay out visible text")
            let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            appearance.performAsCurrentDrawingAppearance {
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            }
            let gutter = ruler.map { canvas.convert($0.bounds, from: $0).insetBy(dx: 2, dy: 2) }
            var textPixels: [CGFloat] = []
            var surroundingPixels: [CGFloat] = []
            var gutterPixels: [CGFloat] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let point = NSPoint(x: (CGFloat(x) + 0.5) * frame.width / CGFloat(bitmap.pixelsWide),
                                        y: (CGFloat(y) + 0.5) * frame.height / CGFloat(bitmap.pixelsHigh))
                    let inText = textRects.contains { $0.contains(point) }
                    let inRing = viewport.contains(point) && !inText
                        && textRects.contains { $0.insetBy(dx: -3, dy: -3).contains(point) }
                    let inGutter = gutter?.contains(point) == true
                    guard inText || inRing || inGutter else { continue }
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent].map {
                        $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                    }
                    let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
                    if inText { textPixels.append(luminance) }
                    if inRing { surroundingPixels.append(luminance) }
                    if inGutter { gutterPixels.append(luminance) }
                }
            }
            XCTAssertFalse(surroundingPixels.isEmpty)
            let background = median(surroundingPixels)
            let ink = textPixels.filter { abs($0 - background) > 0.25 }.count
            let gutterBackground = median(gutterPixels)
            let numberInk = gutterPixels.filter { abs($0 - gutterBackground) > 0.25 }.count
            print("RULER-INK appearance=\(name.rawValue) ruler=\(hasRuler) text=\(ink) gutter=\(numberInk) clip=\(scroll.contentView.bounds) rulerFrame=\(ruler?.frame ?? .zero)")
            XCTAssertGreaterThan(ink, 0, "Text-area ink must survive ruler installation in \(name.rawValue); ruler=\(hasRuler)")
            if let ruler {
                XCTAssertGreaterThan(numberInk, 0, "Line numbers must remain visible")
                let rulerFrame = canvas.convert(ruler.bounds, from: ruler)
                let documentOrigin = canvas.convert(NSPoint.zero, from: text)
                XCTAssertEqual(documentOrigin.x, rulerFrame.maxX, accuracy: 0.5,
                               "The clip origin must place the document after the gutter")
            }
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
        }
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
