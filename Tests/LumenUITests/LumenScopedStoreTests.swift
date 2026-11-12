import AppKit
import LumenTestSupport
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

    /// The menu bar panel's text color comes from the environment's palette, not the active store.
    func testMenuBarPanelDrawsTheEnvironmentStore() throws {
        let ultraviolet = store(LumenThemes.ultravioletID)
        let panel = LumenMenuBarPanel("Status", showsFooter: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<12, id: \.self) { _ in Text("WWWWWWWWWWWWWWWWWWWWWWWWWWWW") }
            }
        }
        let panelSize = CGSize(width: 340, height: 300)
        let scoped = try XCTUnwrap(LumenSnapshot.png(of: panel, size: panelSize, store: ultraviolet, colorScheme: .dark))
        let active = try XCTUnwrap(LumenSnapshot.png(of: panel, size: panelSize,
                                                     variant: .init(themeID: LumenThemes.ultravioletID, colorScheme: .dark),
                                                     registry: .core))
        let difference = LumenSnapshot.compare(scoped, active)
        XCTAssertLessThanOrEqual(difference.differingPixelFraction, 0.005, "\(difference)")
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

    // MARK: - Environment density root and environment editor (P2-6)

    /// A store that persists into its own defaults suite, so its density key is its own.
    private func persistingStore(_ name: String, density: LumenDensity?) -> LumenThemeStore {
        let suite = "LumenScopedStoreTests.\(name).\(UUID().uuidString)"
        let configuration = LumenStoreConfiguration(appName: name,
                                                    themesDirectory: URL(fileURLWithPath: "/dev/null/lumen-scoped"),
                                                    defaultThemeID: LumenThemes.standardID, defaultsSuiteName: suite)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        if let density { configuration.defaults.set(density.rawValue, forKey: configuration.densityDefaultsKey) }
        return LumenThemeStore(registry: .core, configuration: configuration, themes: LumenRegistry.core.galleryThemes,
                               persistsSelection: true)
    }

    private func densityRead<V: View>(_ content: (DensityProbe) -> V) -> LumenDensity? {
        let probe = DensityProbe()
        let renderer = ImageRenderer(content: content(probe))
        _ = renderer.cgImage
        return probe.box.density
    }

    func testT0EnvironmentStoreDefaultIsTheActiveStoreAtEachLookup() {
        let first = store(LumenThemes.standardID), second = store(LumenThemes.ultravioletID)
        func lookup() -> LumenThemeStore? {
            let probe = StoreProbe()
            let renderer = ImageRenderer(content: probe)
            _ = renderer.cgImage
            return probe.box.store
        }
        XCTAssertTrue(LumenThemeStore.withActiveStore(first) { lookup() } === first)
        XCTAssertTrue(LumenThemeStore.withActiveStore(second) { lookup() } === second)
    }

    func testT1EnvironmentDensityRootFollowsTheEnvironmentStore() {
        let scoped = persistingStore("T1Scoped", density: .compact)
        let outer = persistingStore("T1Outer", density: .comfortable)
        let read = LumenThemeStore.withActiveStore(outer) {
            densityRead { $0.lumenEnvironmentDensityRoot().environment(\.lumenStore, scoped) }
        }
        XCTAssertEqual(read, .compact)
    }

    func testT2EnvironmentDensityRootInsideAPaletteRoot() {
        let scoped = persistingStore("T2Scoped", density: .comfortable)
        let outer = persistingStore("T2Outer", density: .compact)
        let read = LumenThemeStore.withActiveStore(outer) {
            densityRead { $0.lumenEnvironmentDensityRoot().lumenPaletteRoot(store: scoped, windowChrome: false) }
        }
        XCTAssertEqual(read, .comfortable)
    }

    func testT2bReadmeChainFollowsTheScopedStore() {
        let scoped = persistingStore("T2bScoped", density: .compact)
        let outer = persistingStore("T2bOuter", density: .comfortable)
        let read = LumenThemeStore.withActiveStore(outer) {
            densityRead { probe in
                probe.lumenEnvironmentDensityRoot()
                    .lumenMetrics(.standard)
                    .lumenPaletteRoot(store: scoped, windowChrome: true)
            }
        }
        XCTAssertEqual(read, .compact)
    }

    func testT3ReversedOrderReadsTheActiveStore() {
        let scoped = persistingStore("T3Scoped", density: .compact)
        let outer = persistingStore("T3Outer", density: .comfortable)
        let read = LumenThemeStore.withActiveStore(outer) {
            densityRead { $0.environment(\.lumenStore, scoped).lumenEnvironmentDensityRoot() }
        }
        XCTAssertEqual(read, .comfortable, "The root reads only what is above it")
    }

    func testT4NonPersistingScopedStoreGivesRegular() {
        let scoped = store(LumenThemes.standardID)
        let outer = persistingStore("T4Outer", density: .comfortable)
        let read = LumenThemeStore.withActiveStore(outer) {
            densityRead { $0.lumenEnvironmentDensityRoot().environment(\.lumenStore, scoped) }
        }
        XCTAssertEqual(read, .regular)
    }

    func testT5EditorBasedOnEditsTheEnvironmentStore() throws {
        let scoped = store(LumenThemes.standardID), outer = store(LumenThemes.ultravioletID)
        let base = LumenThemes.midnight
        try LumenThemeStore.withActiveStore(outer) {
            try hosted(LumenThemeEditor(basedOn: base).environment(\.lumenStore, scoped), size: CGSize(width: 900, height: 640)) {
                XCTAssertEqual(scoped.theme().id, "user.draft", "Preview begins in the environment store")
                XCTAssertNotEqual(outer.theme().id, "user.draft", "The active store is untouched")
            }
            XCTAssertNotEqual(scoped.theme().id, "user.draft", "Preview ends when the editor goes away")
            // An explicit store beats the environment.
            try hosted(LumenThemeEditor(base: base, store: outer).environment(\.lumenStore, scoped), size: CGSize(width: 900, height: 640)) {
                XCTAssertEqual(outer.theme().id, "user.draft")
                XCTAssertNotEqual(scoped.theme().id, "user.draft")
            }
        }
    }

    func testT6StoreSwapMovesDensityAndRebuildsTheEditor() throws {
        let first = persistingStore("T6First", density: .compact)
        let second = persistingStore("T6Second", density: .comfortable)
        let probe = DensityProbe()
        func root(_ store: LumenThemeStore) -> some View {
            VStack {
                probe
                LumenThemeEditor(basedOn: LumenThemes.midnight)
            }
            .lumenEnvironmentDensityRoot()
            .environment(\.lumenStore, store)
        }
        let host = NSHostingView(rootView: root(first))
        host.sizingOptions = []
        let size = CGSize(width: 900, height: 700)
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        func settle() {
            for _ in 0..<12 {
                host.layoutSubtreeIfNeeded()
                window.update()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        settle()
        XCTAssertEqual(probe.box.density, .compact)
        XCTAssertEqual(first.theme().id, "user.draft")
        host.rootView = root(second)
        settle()
        XCTAssertEqual(probe.box.density, .comfortable, "Density follows the store swap")
        XCTAssertEqual(second.theme().id, "user.draft", "The editor session was rebuilt on the new store")
        XCTAssertNotEqual(first.theme().id, "user.draft", "The old session ended its preview")
    }

    /// T7: the shipped spellings still compile and bind to the shipped initializers.
    func testT7ShippedSpellingsStillResolve() {
        let s = store(LumenThemes.standardID), t = LumenThemes.midnight
        _ = Color.clear.lumenDensityRoot()
        _ = Color.clear.lumenDensityRoot(store: s)
        _ = LumenThemeEditor(base: t)
        _ = LumenThemeEditor(base: t, store: s)
        _ = LumenThemeEditor(base: t, editsInPlace: true)
        _ = LumenThemeEditor(base: t, store: s, editsInPlace: false)
        _ = LumenThemeEditor(basedOn: t)
    }

    private func hosted<V: View>(_ view: V, size: CGSize, inspect: () throws -> Void) throws {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            window.update()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        defer {
            window.contentView = nil
            window.close()
            for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        try inspect()
    }
}

private final class DensityBox: @unchecked Sendable { var density: LumenDensity? }

private struct DensityProbe: View {
    let box = DensityBox()
    @Environment(\.lumenDensity) private var density

    var body: some View {
        box.density = density
        return Color.clear.frame(width: 4, height: 4)
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
