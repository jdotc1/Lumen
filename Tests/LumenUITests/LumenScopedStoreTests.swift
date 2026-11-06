import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Two stores in one process, each drawing its own theme through the environment,
/// with the shared store untouched. Goldens: `scoped-store-showcase@<variant>.png`.
@MainActor
final class LumenScopedStoreTests: XCTestCase {
    let size = CGSize(width: 560, height: 340)

    private func store(_ themeID: String) -> LumenThemeStore {
        LumenThemeStore(configuration: LumenStoreConfiguration(appName: "LumenScopedStoreTests",
                                                               themesDirectory: URL(fileURLWithPath: "/dev/null/lumen-scoped"),
                                                               defaultThemeID: themeID),
                        registry: .core, themes: LumenRegistry.core.galleryThemes)
    }

    func testTwoWindowsInOneProcessDrawTheirOwnStores() throws {
        try XCTSkipIf(LumenGoldenTests.skipsGoldens, "Golden images are checked on the recording Mac")
        let shared = LumenThemeStore.shared
        let sharedTheme = shared.theme().id
        let standard = store(LumenThemes.standardID), ultraviolet = store(LumenThemes.ultravioletID)
        XCTAssertFalse(standard.persistsSelection, "A second store persists nothing unless asked")
        XCTAssertEqual(LumenSnapshot.variant(of: ultraviolet, colorScheme: .dark).label, "ultraviolet-dark")

        // Two real windows, each given only its store through the environment; neither is made active.
        let first = try XCTUnwrap(LumenSnapshot.png(of: LumenShowcase(), size: size, store: standard, colorScheme: .dark,
                                                    renderer: .window))
        let second = try XCTUnwrap(LumenSnapshot.png(of: LumenShowcase(), size: size, store: ultraviolet, colorScheme: .dark,
                                                     renderer: .window))
        let between = LumenSnapshot.compare(first, second)
        XCTAssertGreaterThan(between.differingPixelFraction, 0.2, "The two windows draw different themes: \(between)")

        // Each matches the render with its store made active: nothing in the view reads the shared store.
        for (png, themeID) in [(first, LumenThemes.standardID), (second, LumenThemes.ultravioletID)] {
            let scoped = try XCTUnwrap(LumenSnapshot.png(of: LumenShowcase(), size: size,
                                                         variant: .init(themeID: themeID, colorScheme: .dark),
                                                         registry: .core, renderer: .window))
            let difference = LumenSnapshot.compare(png, scoped)
            XCTAssertLessThanOrEqual(difference.differingPixelFraction, 0.005, "\(themeID): \(difference)")
        }

        // The goldens, by store.
        for store in [standard, ultraviolet] {
            let outcome = LumenSnapshot.verify(LumenShowcase(), named: "scoped-store-showcase", size: size, store: store,
                                               colorScheme: .dark, goldenDirectory: LumenGoldenTests.goldens, renderer: .window)
            if let message = outcome.failureMessage { XCTFail(message) }
        }

        XCTAssertTrue(LumenThemeStore.shared === shared)
        XCTAssertTrue(LumenThemeStore.active === shared, "No render installed a store")
        XCTAssertEqual(shared.theme().id, sharedTheme, "The shared store's selection is untouched")
    }

    func testPaletteRootInheritsTheEnvironmentStore() {
        // `.lumenPaletteRoot()` with no store, under a root that set one, keeps that store.
        let ultraviolet = store(LumenThemes.ultravioletID)
        let probe = StoreProbe()
        let renderer = ImageRenderer(content: probe.lumenPaletteRoot(windowChrome: false)
            .lumenPaletteRoot(store: ultraviolet, windowChrome: false))
        _ = renderer.cgImage
        XCTAssertTrue(probe.box.store === ultraviolet)
    }
}

private final class StoreBox: @unchecked Sendable { var store: LumenThemeStore? }

private struct StoreProbe: View {
    let box = StoreBox()
    @Environment(\.lumenStore) private var store

    var body: some View {
        box.store = store
        return Color.clear.frame(width: 4, height: 4)
    }
}
