import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenThemeMetricsResolutionTests: XCTestCase {
    private final class Capture {
        var metrics: LumenMetrics?
    }

    private struct Probe: View {
        @Environment(\.lumenMetrics) private var metrics
        let capture: Capture
        var body: some View {
            capture.metrics = metrics
            return Color.clear.frame(width: 10, height: 10)
        }
    }

    private func capture(_ build: (Probe) -> some View) throws -> LumenMetrics {
        let result = Capture()
        let renderer = ImageRenderer(content: build(Probe(capture: result)))
        _ = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(result.metrics)
    }

    func testPaletteRootsResolvePerStoreAndReactToSelection() throws {
        let first = TestPack.store(), second = TestPack.store()
        first.select(LumenThemes.contrastID)
        let contrast = try capture { $0.lumenPaletteRoot(store: first, windowChrome: false) }
        let standard = try capture { $0.lumenPaletteRoot(store: second, windowChrome: false) }
        XCTAssertEqual(contrast.layout.controlHeight, 26.4, accuracy: 0.001)
        XCTAssertEqual(standard, .standard)
        first.select(LumenThemes.standardID)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: first, windowChrome: false) }, .standard)
    }

    func testAppOverrideWinsInEitherModifierOrderIncludingStandard() throws {
        let store = TestPack.store()
        store.select(LumenThemes.contrastID)
        var app = LumenMetrics.standard
        app.layout.controlHeight = 37
        app.radius = .uniform(3)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: store, windowChrome: false).lumenMetrics(app) }, app)
        XCTAssertEqual(try capture { $0.lumenMetrics(app).lumenPaletteRoot(store: store, windowChrome: false) }, app)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: store, windowChrome: false).lumenMetrics(.standard) }, .standard)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: store, windowChrome: false).environment(\.lumenMetrics, app) }, app)
    }

    func testNestedRootsUseTheirOwnStoreWithoutCompoundingScale() throws {
        let outer = TestPack.store(), inner = TestPack.store()
        outer.select(LumenThemes.contrastID)
        XCTAssertEqual(try capture {
            $0.lumenPaletteRoot(store: inner, windowChrome: false).lumenPaletteRoot(store: outer, windowChrome: false)
        }, .standard)
        XCTAssertEqual(try capture {
            $0.lumenPaletteRoot(windowChrome: false).lumenPaletteRoot(store: outer, windowChrome: false)
        }, outer.resolvedMetrics())
    }

    func testAllTypographyRolesScaleAndControlBoxesNeverShrink() {
        let base = LumenMetrics.standard
        for scale in [0.9, 1.1, 1.3] {
            let scaled = LumenMetrics.resolving(LumenThemeMetrics(typeScale: scale))
            for path in [\LumenMetrics.Typography.title2, \.title3, \.headline, \.body, \.bodyEmphasized,
                         \.callout, \.subheadline, \.footnote, \.caption, \.captionEmphasized,
                         \.sectionLabel, \.monoCaption, \.monoSmall, \.display, \.stat] {
                XCTAssertEqual(scaled.typography[keyPath: path], base.typography[keyPath: path].scaled(by: scale))
            }
            XCTAssertEqual(scaled.layout.controlHeight, 24 * max(1, scale), accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(scaled.layout.minimumHitTarget, 24)
            XCTAssertGreaterThanOrEqual(scaled.layout.rowHeightCompact, base.layout.rowHeightCompact)
            let text = ImageRenderer(content: Text("AgjÅ").font(scaled.typography.body))
            text.scale = 1
            XCTAssertLessThanOrEqual(CGFloat(text.cgImage?.height ?? Int.max), scaled.layout.controlHeight,
                                     "One line must fit the enlarged control")
        }
    }

    func testSpacingRadiusAndMotionResolveWithoutChangingAbsentDefaults() {
        XCTAssertEqual(LumenMetrics.resolving(nil), .standard)
        XCTAssertEqual(LumenMetrics.resolving(LumenThemeMetrics()), .standard)
        let resolved = LumenMetrics.resolving(LumenThemeMetrics(radiusProfile: .rounded, spacingScale: 1.25, motion: .reduced))
        XCTAssertEqual(resolved.spacing.s11, 60)
        XCTAssertEqual(resolved.radius.xs, 6)
        XCTAssertEqual(resolved.radius.xl, 12)
        XCTAssertEqual(resolved.radius.pill, 12)
        XCTAssertLessThan(resolved.motion.emphasized, LumenMetrics.standard.motion.emphasized)
        XCTAssertNil(resolved.motion.animation(resolved.motion.standardCurve, reduceMotion: true))
        let none = LumenMetrics.resolving(LumenThemeMetrics(motion: LumenThemeMetrics.Motion.none)).motion
        XCTAssertEqual(none.standard, 0)
        XCTAssertNil(none.animation(.default, reduceMotion: false))
        let uniform = LumenMetrics.resolving(LumenThemeMetrics(radiusProfile: .uniform(5))).radius
        XCTAssertEqual([uniform.xs, uniform.sm, uniform.md, uniform.lg, uniform.xl, uniform.pill], [5, 5, 5, 5, 5, 5])
    }

    func testLockedMetricsCannotBeSelectedEvenForBuiltInsOrExplicitThemes() {
        var pack = LumenPack(id: "app.fixed")
        pack.lockedMetrics = [.typeScale]
        let registry = LumenRegistry(packs: [.core, pack])
        let store = TestPack.store(registry: registry)
        XCTAssertFalse(store.themes.contains { $0.id == LumenThemes.contrastID })
        XCTAssertTrue(store.themeFileProblems.contains { $0.reason.contains("typeScale") })
        store.select(LumenThemes.contrastID)
        XCTAssertEqual(store.theme().id, LumenThemes.standardID)
        XCTAssertEqual(store.resolvedMetrics(), .standard)
        let explicit = TestPack.store(registry: registry, themes: [LumenThemes.contrast])
        XCTAssertTrue(explicit.themes.isEmpty)
        XCTAssertEqual(explicit.resolvedMetrics(), .standard)
    }

    func testDepthLockRefusesBuiltInInheritedAndExplicitThemes() {
        var parent = LumenTheme(id: "test.deep", name: "Deep", inherits: LumenThemes.midnightID,
                                light: nil, dark: nil)
        parent.metrics = .init(depth: .init(popover: .init(radius: 20)))
        let child = LumenTheme(id: "test.child", name: "Child", inherits: parent.id, light: nil, dark: nil)
        var pack = LumenPack(id: "test.depth-lock", themes: [parent, child])
        pack.lockedMetrics = [.depth]
        let registry = LumenRegistry(packs: [.core, pack])
        let store = TestPack.store(registry: registry)
        for id in [parent.id, child.id] {
            XCTAssertFalse(store.themes.contains { $0.id == id })
            store.select(id)
            XCTAssertEqual(store.theme().id, LumenThemes.standardID)
            XCTAssertEqual(store.resolvedMetrics(), .standard)
        }
        XCTAssertTrue(store.themeFileProblems.contains { $0.reason.contains("metrics.depth is locked") })
        let explicit = TestPack.store(registry: registry, themes: [parent, child])
        XCTAssertTrue(explicit.themes.isEmpty)
        XCTAssertEqual(explicit.resolvedMetrics(), .standard)
        store.reloadUserThemes()
        XCTAssertFalse(store.themes.contains { $0.id == parent.id || $0.id == child.id })
    }

    func testEmptyOfferListKeepsAValidRegistryDefault() {
        let registry = LumenRegistry(packs: [.core], defaultThemeID: LumenThemes.midnightID)
        let store = TestPack.store(registry: registry, themes: [])
        XCTAssertEqual(store.theme().id, LumenThemes.midnightID)
        XCTAssertEqual(store.resolvedMetrics(), .standard)
    }

    func testReloadKeepsBuiltInLockDiagnostics() {
        var pack = LumenPack(id: "app.fixed")
        pack.lockedMetrics = [.typeScale]
        let registry = LumenRegistry(packs: [.core, pack])
        let store = TestPack.store(registry: registry)
        let problems = store.themeFileProblems
        XCTAssertFalse(problems.isEmpty)
        store.reloadUserThemes()
        XCTAssertEqual(store.themeFileProblems, problems)
        XCTAssertFalse(store.themes.contains { $0.id == LumenThemes.contrastID })
    }

    func testSnapshotsUseThemeMetricsAndHonorAnExplicitStandardOverride() throws {
        let store = TestPack.store()
        store.select(LumenThemes.contrastID)
        let result = Capture()
        _ = try XCTUnwrap(LumenSnapshot.png(of: Probe(capture: result), size: CGSize(width: 40, height: 40),
                                           store: store, colorScheme: .light))
        XCTAssertEqual(result.metrics, store.resolvedMetrics())
        _ = try XCTUnwrap(LumenSnapshot.png(of: Probe(capture: result).lumenMetrics(.standard),
                                           size: CGSize(width: 40, height: 40), store: store, colorScheme: .light))
        XCTAssertEqual(result.metrics, .standard)
    }

    private func depthTheme() throws -> LumenTheme {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/midnight-deep.json")
        return try LumenThemeLibrary.decodeTheme(Data(contentsOf: fixture)).flattened { LumenRegistry.core.theme(id: $0) }
    }

    func testDepthResolvesPerStoreAndAppOverridesWinInBothModifierOrders() throws {
        let theme = try depthTheme()
        let deep = TestPack.store(registry: .core, themes: [theme])
        deep.select(theme.id)
        let standard = TestPack.store(registry: .core)
        let expected = LumenMetrics.resolving(theme.metrics)
        XCTAssertEqual(deep.resolvedMetrics(), expected)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: deep, windowChrome: false) }, expected)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: standard, windowChrome: false) }.depth, .standard)
        var app = LumenMetrics.standard
        app.depth.menu.radius = 7
        app.depth.glow.hero.opacity = 0.2
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: deep, windowChrome: false).lumenMetrics(app) }, app)
        XCTAssertEqual(try capture { $0.lumenMetrics(app).lumenPaletteRoot(store: deep, windowChrome: false) }, app)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: deep, windowChrome: false).lumenMetrics(.standard) }, .standard)
        XCTAssertEqual(try capture {
            $0.lumenPaletteRoot(store: standard, windowChrome: false).lumenPaletteRoot(store: deep, windowChrome: false)
        }, .standard)
    }

    func testElevationAndGlowRenderThemeDepthAndExplicitAppOverride() throws {
        var theme = try depthTheme()
        theme.metrics?.depth?.glow = .init(hero: .init(opacity: 0.6, radius: 30, y: 10),
                                          selection: .init(opacity: 0.6, radius: 20, y: 5))
        let deep = TestPack.store(registry: .core, themes: [theme])
        deep.select(theme.id)
        let standard = TestPack.store(registry: .core)
        standard.select(LumenThemes.midnightID)
        let size = CGSize(width: 120, height: 120)
        for scheme in [ColorScheme.light, .dark] {
            for elevation in [LumenElevation.menu, .popover] {
                let view = Color.white.frame(width: 40, height: 40).lumenElevation(elevation)
                let baseline = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, store: standard, colorScheme: scheme))
                let themed = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, store: deep, colorScheme: scheme))
                let app = try XCTUnwrap(LumenSnapshot.png(of: view.lumenMetrics(.standard), size: size, store: deep, colorScheme: scheme))
                XCTAssertNotEqual(themed, baseline)
                XCTAssertEqual(app, baseline)
            }
            for glow in [LumenGlow.hero, .selection] {
                let view = Color.white.frame(width: 40, height: 40).lumenGlow(glow, color: .red)
                let baseline = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, store: standard, colorScheme: scheme))
                let themed = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, store: deep, colorScheme: scheme))
                let app = try XCTUnwrap(LumenSnapshot.png(of: view.lumenMetrics(.standard), size: size, store: deep, colorScheme: scheme))
                XCTAssertNotEqual(themed, baseline)
                XCTAssertEqual(app, baseline)
            }
        }
    }
}
