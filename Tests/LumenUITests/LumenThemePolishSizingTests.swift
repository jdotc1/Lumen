import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenThemePolishSizingTests: XCTestCase {
    /// This host is never ordered in or made key. Bitmap capture reads only its backing view.
    private func withHost<V: View>(_ view: V, width: CGFloat, scale: Double,
                                   inspect: (NSHostingView<AnyView>, CGSize) throws -> Void) throws {
        let root = AnyView(view.lumenMetrics(.resolving(nil, textScale: scale))
            .environment(\.lumenRendersOffscreen, true))
        let measured = NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: width, height: 4000))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: width,
                                                  height: max(1, measured.height)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(CGSize(width: width, height: max(1, measured.height)))
        defer { window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        try inspect(host, measured)
    }

    func testTokenIdentityRemainsBesideItsSwatchAtNarrowAndWideWidths() throws {
        for scale in [1.0, 1.3] {
            for width: CGFloat in [220, 600] {
                let control = LumenThemeColorControl(
                    name: "component.workspace.sidebar.selection.background", selection: .constant(.green),
                    supportsOpacity: false, value: "#00FF00", isOverridden: false)
                    .foregroundStyle(.red)
                try withHost(control, width: width, scale: scale) { host, size in
                    XCTAssertLessThanOrEqual(size.width, width + 0.5)
                    @MainActor func wells(in view: NSView) -> [NSColorWell] {
                        if let well = view as? NSColorWell { return [well] }
                        return view.subviews.flatMap { wells(in: $0) }
                    }
                    let well = try XCTUnwrap(wells(in: host).first)
                    let wellFrame = well.convert(well.bounds, to: host)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    var ink: [CGPoint] = []
                    let ratio = CGFloat(bitmap.pixelsWide) / width
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                            if color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.3 {
                                ink.append(CGPoint(x: CGFloat(x) / ratio, y: CGFloat(y) / ratio))
                            }
                        }
                    }
                    XCTAssertFalse(ink.isEmpty)
                    XCTAssertGreaterThan(try XCTUnwrap(ink.map(\.x).min()), wellFrame.maxX,
                                         "The token name must remain beside the swatch, never below it")
                    XCTAssertLessThan(try XCTUnwrap(ink.map(\.y).min()), wellFrame.height,
                                      "The name's first line must start alongside its own swatch")
                }
            }
        }
    }

    func testThemeSummaryUsesAllRequiredLinesAtBothTextScales() throws {
        for scale in [1.0, 1.3] {
            var theme = LumenThemes.standard
            theme.summary = String(repeating: "A complete description of this custom theme. ", count: 8)
            let card = LumenThemeCard(theme: theme, registry: .core, appearance: .light,
                                      isSelected: false, action: {})
            var narrowHeight: CGFloat = 0
            try withHost(card, width: 240, scale: scale) { _, size in
                XCTAssertLessThanOrEqual(size.width, 240.5)
                narrowHeight = size.height
            }
            try withHost(card, width: 600, scale: scale) { _, size in
                XCTAssertGreaterThan(narrowHeight, size.height + 50,
                                     "A summary must grow beyond the former two-line cap")
            }
        }
    }

    func testThemeGridUsesFewerColumnsWhenTypographyNeedsMoreRoom() throws {
        let store = TestPack.store(registry: .core, themes: [LumenThemes.standard, LumenThemes.midnight])
        let gallery = LumenThemeGallery(store: store)
        var standardHeight: CGFloat = 0
        try withHost(gallery, width: 480, scale: 1) { _, size in
            XCTAssertLessThanOrEqual(size.width, 480.5)
            standardHeight = size.height
        }
        try withHost(gallery, width: 480, scale: 1.3) { _, size in
            XCTAssertLessThanOrEqual(size.width, 480.5)
            XCTAssertGreaterThan(size.height, standardHeight + 100,
                                 "The enlarged card measure must move the second miniature to a new row")
        }
        for scale in [1.0, 1.3] {
            try withHost(gallery, width: 220, scale: scale) { _, size in
                XCTAssertLessThanOrEqual(size.width, 220.5, "A single card must yield to its host")
            }
        }
    }

    func testOversizedThemeActionsWrapWithinTheirFlowRow() throws {
        let name = String(repeating: "Custom workspace appearance ", count: 4)
        for scale in [1.0, 1.3] {
            let actions = LumenFlowLayout {
                Button {} label: {
                    LumenThemeActionLabel("Customize \(name)…", systemImage: "paintpalette")
                }
                Button {} label: {
                    LumenThemeActionLabel("Duplicate \(name)", systemImage: "plus.square.on.square")
                }
            }
            .buttonStyle(.lumenBare)
            // An enclosing form's one-line default must not truncate either action.
            .lineLimit(1)
            var narrowHeight: CGFloat = 0
            try withHost(actions, width: 240, scale: scale) { _, size in
                XCTAssertLessThanOrEqual(size.width, 240.5)
                narrowHeight = size.height
            }
            try withHost(actions, width: 800, scale: scale) { _, size in
                XCTAssertGreaterThan(narrowHeight, size.height + 40)
            }
        }
    }
}
