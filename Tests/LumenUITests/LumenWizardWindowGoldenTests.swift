import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenUI
@testable import LumenCatalog

/// The actual Catalog wizard content with native titled-window chrome: six gallery variants,
/// then Summary at 1.3 text scale and compact density. Record once and review each new PNG.
@MainActor
final class LumenWizardWindowGoldenTests: XCTestCase {
    private let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")

    func testWizardWindow() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let variants = LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        for variant in variants where variant.themeID != LumenThemes.contrastID {
            try verify(variant, suffix: "", scale: 1, density: .regular, current: 2)
        }
        let standard = LumenSnapshot.Variant(themeID: LumenRegistry.core.defaultThemeID, colorScheme: .light)
        try verify(standard, suffix: "-text-1.3", scale: 1.3, density: .regular, current: 3)
        try verify(standard, suffix: "-compact", scale: 1, density: .compact, current: 3)
    }

    func testContrastWizardWindow() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let variants = LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes)
            .filter { $0.themeID == LumenThemes.contrastID }
        XCTAssertEqual(variants.count, 2)
        for variant in variants {
            try verify(variant, suffix: "", scale: 1, density: .regular, current: 2)
        }
    }

    private func verify(_ variant: LumenSnapshot.Variant, suffix: String, scale: Double,
                        density: LumenDensity, current: Int) throws {
        let name = "wizard-window@\(variant.label)\(suffix).png"
        let actual = try render(variant, scale: scale, density: density, current: current, name: name)
        let url = directory.appending(path: name)
        try LumenFilterConfinedGolden.verify(actual, at: url)
    }

    private func render(_ variant: LumenSnapshot.Variant, scale: Double, density: LumenDensity,
                        current: Int, name: String) throws -> Data {
        let store = LumenSnapshot.store(for: variant, registry: .core)
        return try LumenThemeStore.withActiveStore(store) {
            try MainActor.assumeIsolated {
                // The host must include the theme's type scale as well as the app preference.
                // Contrast uses 1.1 even when the app preference is 1; a 640-wide host clips it.
                let metrics = LumenMetrics.resolving(store.theme(for: .window).metrics, textScale: scale)
                let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
                let size = CGSize(width: 640 * growth, height: 460 * growth)
                let root = CatalogWizardWindow(current: current)
                    .lumenPaletteRoot(store: store).lumenTextScale(scale)
                    .lumenChromeStyle(.drawn)
                    .environment(\.lumenDensity, density)
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.displayScale, 2)
                    .environment(\.appearsActive, true)
                    .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)
                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                    styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: variant.colorScheme == .dark ? .darkAqua : .aqua)
                window.title = "Wizard Window"
                window.contentView = host
                window.setContentSize(size)
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                defer { window.close() }
                for _ in 0..<20 {
                    (host.superview ?? host).layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                }
                let frameView = try XCTUnwrap(host.superview)
                XCTAssertGreaterThan(frameView.bounds.height, window.contentLayoutRect.height)
                let captures = directory.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appending(path: ".build/wizard-captures")
                try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
                let captureURL = captures.appending(path: name)
                try LumenHeadlessHost.png(of: window).write(to: captureURL)
                return try Data(contentsOf: captureURL)
            }
        }
    }
}
