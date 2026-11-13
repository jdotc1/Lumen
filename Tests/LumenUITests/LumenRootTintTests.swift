import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor final class LumenRootTintTests: XCTestCase {
    private let tint: LumenColor = "#2F6FEB"

    func testTintedAccentDiffersFromUntintedInBothAppearances() throws {
        let store = TestPack.store()
        let plain = store.resolvedPalette()
        let tinted = store.resolvedPalette(tint: tint)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            for token in [LumenToken.accent, .accentFilled] {
                let a = try hex(NSColor(tinted[token]), in: name)
                let b = try hex(NSColor(plain[token]), in: name)
                XCTAssertNotEqual(a, b, "\(token) in \(name)")
            }
        }
        XCTAssertEqual(tinted.key.tint, tint)
        XCTAssertNotEqual(tinted, plain)
    }

    func testNilTintMatchesPlainPalette() throws {
        let store = TestPack.store()
        let plain = store.resolvedPalette()
        let nilTint = store.resolvedPalette(tint: nil)
        XCTAssertNil(nilTint.key.tint)
        XCTAssertEqual(nilTint.key, plain.key)
        for token in [LumenToken.accent, .bgCanvas, .fgPrimary] {
            XCTAssertEqual(try hex(NSColor(nilTint[token]), in: .aqua), try hex(NSColor(plain[token]), in: .aqua))
        }
    }

    func testRootSetsSchemeAndTint() {
        let dark = capture { $0.lumenRoot(tint: self.tint, appearance: .dark) }
        XCTAssertEqual(dark.scheme, .dark)
        XCTAssertEqual(dark.palette?.key.tint, tint)
        XCTAssertEqual(capture { $0.lumenRoot(appearance: .light) }.scheme, .light)
        let system = capture { $0.lumenRoot() }
        XCTAssertNil(system.palette?.key.tint)
    }

    func testTintWinsOverSystemAccent() {
        let store = TestPack.store()
        store.setUsesSystemAccent(true)
        let palette = store.resolvedPalette(tint: tint)
        XCTAssertEqual(palette.key.tint, tint)
        XCTAssertNotEqual(palette, store.resolvedPalette())
    }

    func testAdoptionExampleRenders() {
        let host = NSHostingView(rootView: ExampleMinimalTintRoot())
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    private struct Captured { var scheme: ColorScheme?; var palette: LumenResolvedPalette? }

    private final class Box { var value = Captured() }

    private struct Probe: View {
        let box: Box
        @Environment(\.colorScheme) private var scheme
        @Environment(\.lumenPalette) private var palette
        var body: some View {
            box.value = Captured(scheme: scheme, palette: palette)
            return Color.clear.frame(width: 10, height: 10)
        }
    }

    private func capture<V: View>(_ wrap: (Probe) -> V) -> Captured {
        let box = Box()
        let host = NSHostingView(rootView: wrap(Probe(box: box)))
        host.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        host.layoutSubtreeIfNeeded()
        return box.value
    }
}
