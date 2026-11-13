import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

/// Design review 2026-11 #22: in right-to-left layout an expanded inspector section's chevron
/// pointed up. `chevron.left` is itself mirrored in RTL, so the hand-flipped name plus a negated
/// angle turned it the wrong way. A disclosure chevron points toward the trailing edge while
/// collapsed and down while expanded, in both layout directions. Rendered and read back from pixels.
@MainActor
final class LumenDisclosureChevronTests: XCTestCase {
    private enum Direction: String { case left, right, up, down }

    func testChevronPointsTrailingCollapsedAndDownExpanded() throws {
        let cases: [(LayoutDirection, Bool, Direction)] = [
            (.leftToRight, false, .right), (.leftToRight, true, .down),
            (.rightToLeft, false, .left), (.rightToLeft, true, .down),
        ]
        for (direction, expanded, expected) in cases {
            let found = try pointing(LumenDisclosureChevron(isExpanded: expanded, size: 40), direction: direction)
            XCTAssertEqual(found, expected, "Chevron in \(direction), expanded=\(expanded)")
        }
    }

    /// Every disclosure in LumenUI draws through the shared chevron, so no call site can hand-flip
    /// a mirrored glyph again.
    func testNoHandFlippedDisclosureChevrons() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LumenUI")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated()
            where line.contains("rightToLeft ? -90") || line.contains("rightToLeft ? 90") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "Use LumenDisclosureChevron instead of a hand-flipped rotation")
    }

    private func pointing(_ chevron: some View, direction: LayoutDirection) throws -> Direction {
        let content = chevron
            .foregroundStyle(.black)
            .frame(width: 80, height: 80)
            .background(.white)
            .environment(\.layoutDirection, direction)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let size = CGSize(width: 80, height: 80)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var ink: [(Int, Int)] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.brightnessComponent < 0.5 {
                    ink.append((x, y))
                }
            }
        }
        XCTAssertFalse(ink.isEmpty, "The chevron drew nothing")
        let xs = ink.map(\.0), ys = ink.map(\.1)
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let cx = Double(minX + maxX) / 2, cy = Double(minY + maxY) / 2
        let w = Double(max(1, maxX - minX)), h = Double(max(1, maxY - minY))
        // Through the middle row a ">" is inked only at its tip; through the middle column a "v" is
        // inked only at its tip. The line that meets ink off-centre names the direction.
        let rowY = Int(cy.rounded()), colX = Int(cx.rounded())
        let rowXs = ink.filter { abs($0.1 - rowY) <= 1 }.map { Double($0.0) }
        let colYs = ink.filter { abs($0.0 - colX) <= 1 }.map { Double($0.1) }
        let dx = rowXs.isEmpty ? 0 : (rowXs.reduce(0, +) / Double(rowXs.count) - cx) / w
        let dy = colYs.isEmpty ? 0 : (colYs.reduce(0, +) / Double(colYs.count) - cy) / h
        print("CHEVRON dx=\(dx) dy=\(dy)")
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }
}
