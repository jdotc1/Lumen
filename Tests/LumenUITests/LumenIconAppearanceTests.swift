import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenIconAppearanceTests: XCTestCase {
    func testBackgroundDefaultsBurstRefreshesOnMainAndIgnoresOtherSuites() async throws {
        var reads = 0
        let refreshed = expectation(description: "Coalesced refresh on main")
        let observer = LumenSystemIconAppearance(readAppearance: {
            XCTAssertTrue(Thread.isMainThread)
            MainActor.assertIsolated()
            reads += 1
            if reads == 2 { refreshed.fulfill() }
            return reads == 1 ? "RegularLight" : "RegularDark"
        })
        await Task.detached {
            let unrelated = UserDefaults(suiteName: "LumenIconAppearanceTests.unrelated")
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: unrelated)
        }.value
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(reads, 1, "Other defaults suites must not schedule refresh")
        await Task.detached {
            for _ in 0..<20 {
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            }
        }.value
        await fulfillment(of: [refreshed], timeout: 2)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(reads, 2, "A burst must result in one refresh")
        XCTAssertEqual(observer.appearance, LumenIconAppearance("RegularDark"))
    }

    func testSystemIconAppearanceParsesEveryStyleAndMode() {
        for style in LumenIconAppearance.Style.allCases {
            for mode in LumenIconAppearance.Mode.allCases {
                let raw = style.rawValue.capitalized + mode.rawValue.capitalized
                let appearance = LumenIconAppearance(raw)
                XCTAssertEqual(appearance.style, style, "Observed \(appearance) for \(raw)")
                XCTAssertEqual(appearance.mode, mode, "Observed \(appearance) for \(raw)")
            }
        }
        for raw in [nil, "", "FutureAutomatic", "Regular", "RegularDarkTrailing"] {
            XCTAssertEqual(LumenIconAppearance(raw), LumenIconAppearance("RegularAutomatic"), "Unknown value \(raw ?? "nil")")
        }
        XCTAssertFalse(LumenIconAppearance("RegularLight").isDark(in: .dark))
        XCTAssertTrue(LumenIconAppearance("RegularDark").isDark(in: .light))
        XCTAssertTrue(LumenIconAppearance("DarkAutomatic").isDark(in: .light))
        XCTAssertFalse(LumenIconAppearance("RegularAutomatic").isDark(in: .light))
        XCTAssertTrue(LumenIconAppearance("RegularAutomatic").isDark(in: .dark))
        for style in ["Clear", "Tinted"] {
            for mode in ["Automatic", "Light", "Dark"] {
                XCTAssertTrue(LumenIconAppearance(style + mode).isDark(in: .light), "\(style + mode) uses documented dark fallback")
            }
        }
    }

    func testDarkGroundMatchesSystemReferenceWithoutPastelLift() {
        let store = TestPack.store(registry: .core)
        let appearance = LumenAppearance(isDark: true, isHighContrast: false)
        for hue in LumenToken.hues {
            let colors = LumenTileColors(hue: hue, appearance: appearance, store: store)
            XCTAssertEqual(colors.baseValue, LumenColor(red: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255), "Observed ground for \(hue)")
            let base = store.resolvedColor(hue, for: appearance)
            if base.contrastRatio(against: colors.baseValue) >= 3 {
                XCTAssertEqual(colors.glyphValue, base, "\(hue) lifted despite adequate contrast")
            }
            XCTAssertGreaterThanOrEqual(colors.glyphValue.contrastRatio(against: colors.baseValue), 3, "\(hue): \(colors.glyphValue)")
        }
    }

    func testLightIconsHaveWhiteGlyphOnSolidHue() {
        let store = TestPack.store(registry: .core)
        for hue in LumenToken.hues {
            let colors = LumenTileColors(hue: hue, appearance: .init(isDark: false, isHighContrast: false), store: store)
            XCTAssertEqual(colors.glyphValue, LumenColor(red: 1, green: 1, blue: 1), "\(hue): \(colors.glyphValue)")
            XCTAssertEqual(colors.top, colors.bottom, "\(hue) must have a solid ground")
            XCTAssertGreaterThanOrEqual(colors.glyphValue.contrastRatio(against: colors.baseValue), 3, "\(hue): \(colors.baseValue)")
        }
    }

    func testMeasuredPerimeterSeparatesNativeSymbolsFromFrames() {
        let native = ["wifi", "gearshape", "accessibility", "battery.100percent", "desktopcomputer",
                      "sun.max", "magnifyingglass", "bell.badge", "speaker.wave.3", "moon", "hourglass",
                      "lock", "hand.raised", "touchid", "person.2", "doc.text", "doc.fill", "doc.text.fill",
                      "folder.fill", "square.fill", LumenIconTile.placeholderSymbol]
        for symbol in native {
            let measurement = LumenTileSymbolFrame.measurement(for: symbol)
            print("TILE_CALIBRATION \(symbol) edges=\(measurement.edges) innerInk=\(measurement.innerBandInk) framed=\(measurement.isFramed)")
            XCTAssertFalse(measurement.isFramed, "\(symbol): \(measurement)")
        }
        for symbol in ["server.rack", "rectangle", "square"] {
            let measurement = LumenTileSymbolFrame.measurement(for: symbol)
            print("TILE_CALIBRATION \(symbol) edges=\(measurement.edges) innerInk=\(measurement.innerBandInk) framed=\(measurement.isFramed)")
            XCTAssertTrue(measurement.isFramed, "\(symbol): \(measurement)")
        }
        XCTAssertLessThan(LumenTileSymbolFrame.reducedShare, LumenIconTile.symbolShare)
    }

    func testIconPolicyFlipsInOneHostWithoutResettingState() throws {
        let probe = IconAppearanceProbe()
        let host = NSHostingView(rootView: IconAppearanceCounter(probe: probe)
            .environment(\.lumenIconAppearance, LumenIconAppearance("RegularDark")))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func render() throws -> Data {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertFalse(window.isVisible, "Icon policy host became visible")
            return try XCTUnwrap(bitmap.tiffRepresentation)
        }
        _ = try render()
        try XCTUnwrap(probe.increment)()
        let dark = try render()
        XCTAssertEqual(probe.value, 1)
        host.rootView = IconAppearanceCounter(probe: probe)
            .environment(\.lumenIconAppearance, LumenIconAppearance("RegularLight"))
        let light = try render()
        XCTAssertEqual(probe.value, 1, "State reset on Light icons")
        XCTAssertNotEqual(light, dark, "Appearance changed but raster did not")
        host.rootView = IconAppearanceCounter(probe: probe)
            .environment(\.lumenIconAppearance, LumenIconAppearance("RegularDark"))
        _ = try render()
        XCTAssertEqual(probe.value, 1, "State reset on Dark icons")
    }
}

@MainActor
private final class IconAppearanceProbe {
    var value: Int?
    var increment: (() -> Void)?
}

private struct IconAppearanceCounter: View {
    let probe: IconAppearanceProbe
    @State private var count = 0
    var body: some View {
        VStack {
            LumenIconTile("wifi", hue: .hueBlue, size: 40)
            Text("\(count)")
        }
        .background(IconAppearanceBridge(count: $count, probe: probe))
    }
}

private struct IconAppearanceBridge: NSViewRepresentable {
    @Binding var count: Int
    let probe: IconAppearanceProbe
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        probe.value = count
        probe.increment = { count += 1 }
    }
}
