import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenConformance
@testable import LumenUI

/// Design review 2026-11 #6: a segmented control's track and its selected plate both filled
/// `bg.elevated`, so in dark the selection showed only as a hairline. The selected segment must
/// read against an unselected one in every built-in theme, both appearances, on the window and on
/// a card (raised palette).
@MainActor
final class LumenSegmentedSelectionTests: XCTestCase {
    private enum Option: String, CaseIterable { case first = "Alpha", second = "Bravo", third = "Gamma" }

    func testSelectedSegmentReadsAgainstItsTrack() throws {
        for theme in [LumenThemes.standardID, LumenThemes.midnightID, LumenThemes.ultravioletID] {
            for dark in [false, true] {
                for raised in [false, true] {
                    let (selected, unselected) = try sample(theme: theme, dark: dark, raised: raised,
                                                            control: AnyView(segmented))
                    let ratio = contrast(selected, unselected)
                    XCTAssertGreaterThanOrEqual(ratio, 1.08,
                        "Segmented selection vs track: \(theme) dark=\(dark) raised=\(raised) ratio=\(ratio)")
                    let (pillSelected, pillUnselected) = try sample(theme: theme, dark: dark, raised: raised,
                                                                    control: AnyView(pill))
                    let pillRatio = contrast(pillSelected, pillUnselected)
                    XCTAssertGreaterThanOrEqual(pillRatio, 1.08,
                        "Pill switcher selection vs track: \(theme) dark=\(dark) raised=\(raised) ratio=\(pillRatio)")
                }
            }
        }
    }

    private var segmented: some View {
        LumenSegmentedControl(selection: .constant(Option.first), options: Option.allCases, title: { $0.rawValue })
    }

    private var pill: some View {
        LumenModeSwitcher(selection: .constant(Option.first), options: Option.allCases, style: .pill,
                          title: { $0.rawValue })
    }

    /// The plate fill a few points below the top of the first (selected) and last segments, clear
    /// of their labels.
    private func sample(theme: String, dark: Bool, raised: Bool, control: AnyView) throws -> (NSColor, NSColor) {
        let variant = LumenSnapshot.Variant(themeID: theme, colorScheme: dark ? .dark : .light)
        let store = LumenSnapshot.store(for: variant, registry: .core)
        let palette = raised ? store.resolvedPalette().raised() : store.resolvedPalette()
        let ground = raised ? palette[.bgElevated] : palette[.bgWindow]
        let content = control
            .fixedSize()
            .padding(8)
            .background(ground)
            .environment(\.lumenPalette, palette)
            .environment(\.lumenStore, store)
            // An always-dark theme (Ultraviolet) forces dark, as `lumenPaletteRoot` does.
            .environment(\.colorScheme, store.forcedAppearance(for: .window) ?? variant.colorScheme)
            .environment(\.appearsActive, true)
            .environment(\.lumenTabIsActive, true)
            .environment(\.lumenPaneIsFocused, true)
            .environment(\.lumenRendersOffscreen, true)
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let width = host.bounds.width - 16
        // 8 pt padding, 2 pt rim, then 3 pt into the plate: above the label's ascenders.
        let y = Int((8 + 2 + 3) * scale)
        let first = Int((8 + width / 6) * scale), last = Int((8 + width * 5 / 6) * scale)
        let a = try XCTUnwrap(bitmap.colorAt(x: first, y: y)?.usingColorSpace(.sRGB))
        let b = try XCTUnwrap(bitmap.colorAt(x: last, y: y)?.usingColorSpace(.sRGB))
        return (a, b)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func lum(_ c: NSColor) -> Double {
            0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        }
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
