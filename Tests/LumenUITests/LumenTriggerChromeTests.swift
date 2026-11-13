import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Design review 2026-11 #12–#14 and #19.
///
/// #12–#14: triggers that sit side by side (the hue picker, a pop-up, a button that opens a popover)
/// were three different controls: a native accent-tinted bezel, a hand-built `border.subtle` box and
/// a gray bezel, at two heights. They now share the pop-up chrome: one fill, one hairline, one height.
///
/// #19: the theme gallery's actions wrapped as a ragged sentence. `LumenFlowLayout(alignsColumns:)`
/// gives every child the widest child's cell, so wrapped lines share their columns.
@MainActor
final class LumenTriggerChromeTests: XCTestCase {
    private enum Hue: String, CaseIterable { case one = "Alpha" }

    func testSiblingTriggersShareFillHairlineAndHeight() throws {
        let metrics = LumenMetrics.standard
        for dark in [false, true] {
            let picker = try render(AnyView(LumenHuePickerButton(selection: .constant(.hueViolet))), dark: dark)
            let popUp = try render(AnyView(LumenPopUp(selection: .constant(Hue.one), options: Hue.allCases, title: { $0.rawValue })), dark: dark)
            let button = try render(AnyView(Button("Share Theme…") {}.buttonStyle(.lumenBordered)), dark: dark)
            for (name, sample) in [("hue picker", picker), ("bordered button", button)] {
                XCTAssertEqual(sample.height, popUp.height, accuracy: 0.5, "\(name) height vs pop-up (dark=\(dark))")
                XCTAssertTrue(close(sample.fill, popUp.fill), "\(name) fill \(sample.fill) vs pop-up \(popUp.fill) (dark=\(dark))")
                XCTAssertTrue(close(sample.edge, popUp.edge), "\(name) hairline \(sample.edge) vs pop-up \(popUp.edge) (dark=\(dark))")
            }
            XCTAssertEqual(popUp.height, metrics.layout.controlHeight, accuracy: 0.5)
        }
    }

    func testAlignedFlowSharesColumnsAcrossWrappedLines() throws {
        let widths: [CGFloat] = [40, 90, 60, 50, 70, 30]
        let box = FrameBox()
        let flow = LumenFlowLayout(spacing: 10, lineSpacing: 6, alignsColumns: true) {
            ForEach(widths.indices, id: \.self) { index in
                Color.gray.frame(width: widths[index], height: 20)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: FrameKey.self, value: [index: proxy.frame(in: .named("flow"))])
                    })
            }
        }
        .coordinateSpace(.named("flow"))
        .onPreferenceChange(FrameKey.self) { box.frames = $0 }
        .frame(width: 310, alignment: .topLeading)
        try layOut(AnyView(flow), size: CGSize(width: 310, height: 120))

        let frames = box.frames
        XCTAssertEqual(frames.count, widths.count)
        // The cell is the widest child (90): three cells per 310 pt line (90 + 10 + 90 + 10 + 90).
        let rows = Dictionary(grouping: frames.values, by: { Int($0.minY.rounded()) }).sorted { $0.key < $1.key }
        XCTAssertEqual(rows.count, 2, "Six children in three shared columns make two lines: \(frames)")
        let columns = rows.map { $0.value.map { Int($0.minX.rounded()) }.sorted() }
        XCTAssertEqual(columns.first, columns.last, "Wrapped lines start their children at the same columns")
        XCTAssertEqual(columns.first, [0, 100, 200])

        // The default stays a ragged sentence: each child advances by its own width.
        let ragged = FrameBox()
        let sentence = LumenFlowLayout(spacing: 10, lineSpacing: 6) {
            ForEach(widths.indices, id: \.self) { index in
                Color.gray.frame(width: widths[index], height: 20)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: FrameKey.self, value: [index: proxy.frame(in: .named("flow"))])
                    })
            }
        }
        .coordinateSpace(.named("flow"))
        .onPreferenceChange(FrameKey.self) { ragged.frames = $0 }
        .frame(width: 310, alignment: .topLeading)
        try layOut(AnyView(sentence), size: CGSize(width: 310, height: 120))
        XCTAssertEqual(ragged.frames[1].map { Int($0.minX.rounded()) }, 50)
    }

    // MARK: Helpers

    private final class FrameBox { var frames: [Int: CGRect] = [:] }

    private struct FrameKey: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    private struct Sample { let height: CGFloat; let fill: NSColor; let edge: NSColor }

    private func environment(_ view: AnyView, dark: Bool) -> AnyView {
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: dark ? .dark : .light)
        let store = LumenSnapshot.store(for: variant, registry: .core)
        return AnyView(view
            .environment(\.lumenPalette, store.resolvedPalette())
            .environment(\.lumenStore, store)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.appearsActive, true)
            .environment(\.lumenRendersOffscreen, true))
    }

    /// The control alone on the window ground: its height, the fill 3 pt in from the leading edge at
    /// mid-height, and the hairline at the top edge's midpoint.
    private func render(_ control: AnyView, dark: Bool) throws -> Sample {
        let host = NSHostingView(rootView: environment(AnyView(control.fixedSize()), dark: dark))
        let size = host.fittingSize
        host.sizingOptions = []
        let window = offscreenWindow(size: size, dark: dark)
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        settle(host)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let fill = try XCTUnwrap(bitmap.colorAt(x: Int(3 * scale), y: Int(size.height / 2 * scale))?.usingColorSpace(.sRGB))
        let edge = try XCTUnwrap(bitmap.colorAt(x: Int(size.width / 2 * scale), y: 0)?.usingColorSpace(.sRGB))
        return Sample(height: size.height, fill: fill, edge: edge)
    }

    private func layOut(_ view: AnyView, size: CGSize) throws {
        let host = NSHostingView(rootView: environment(view, dark: false))
        host.sizingOptions = []
        let window = offscreenWindow(size: size, dark: false)
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        settle(host)
    }

    private func offscreenWindow(size: CGSize, dark: Bool) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return window
    }

    private func settle(_ host: NSView) {
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func close(_ a: NSColor, _ b: NSColor, tolerance: CGFloat = 0.02) -> Bool {
        abs(a.redComponent - b.redComponent) <= tolerance && abs(a.greenComponent - b.greenComponent) <= tolerance
            && abs(a.blueComponent - b.blueComponent) <= tolerance
    }
}
