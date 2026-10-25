import Foundation
import XCTest
@testable import LumenTokens

final class LumenThemeDepthTests: XCTestCase {
    private func theme(_ depth: LumenThemeDepth) -> LumenTheme {
        LumenTheme(id: "test.depth", name: "Depth", light: [:], dark: [:],
                   metrics: LumenThemeMetrics(depth: depth))
    }

    private func issues(_ depth: LumenThemeDepth) -> [LumenIssue] {
        LumenValidator.metricIssues(in: theme(depth), registry: .core)
    }

    func testDepthLockRejectsEveryExplicitAndInheritedLeaf() throws {
        let declarations = [
            "{}", #"{"menu":{}}"#, #"{"menu":{"opacity":{"light":0.12}}}"#,
            #"{"menu":{"opacity":{"dark":0.4}}}"#, #"{"menu":{"radius":10}}"#,
            #"{"menu":{"y":0}}"#, #"{"popover":{"opacity":{"light":0.14}}}"#,
            #"{"popover":{"opacity":{"dark":0.45}}}"#, #"{"popover":{"radius":16}}"#,
            #"{"popover":{"y":0}}"#, #"{"glow":{"hero":{"opacity":0.4}}}"#,
            #"{"glow":{"hero":{"radius":20}}}"#, #"{"glow":{"hero":{"y":0}}}"#,
            #"{"glow":{"selection":{"opacity":0.45}}}"#, #"{"glow":{"selection":{"radius":8}}}"#,
            #"{"glow":{"selection":{"y":0}}}"#,
        ]
        var pack = LumenPack(id: "test.depth-lock")
        pack.lockedMetrics = [.depth]
        let registry = LumenRegistry(packs: [.core, pack])
        XCTAssertFalse(LumenThemeMetrics().keys.contains(.depth))
        for declaration in declarations {
            let depth = try JSONDecoder().decode(LumenThemeDepth.self, from: Data(declaration.utf8))
            let parent = theme(depth)
            XCTAssertEqual(parent.metrics?.keys, [.depth])
            for metrics in [LumenThemeMetrics?.none, .some(.init(depth: .init()))] {
                var child = LumenTheme(id: "test.child", name: "Child", inherits: parent.id, light: nil, dark: nil)
                child.metrics = metrics
                let inherited = try child.flattened { $0 == parent.id ? parent : nil }
                for candidate in [parent, inherited] {
                    let found = LumenValidator.metricIssues(in: candidate, registry: registry)
                    XCTAssertEqual(found.count, 1, declaration)
                    XCTAssertEqual(found.first?.severity, .error)
                    XCTAssertEqual(found.first?.message,
                                   "metrics.depth is locked by this app's packs and cannot be set by a theme")
                }
            }
        }
        XCTAssertTrue(LumenValidator.metricIssues(in: LumenThemes.standard, registry: registry).isEmpty)
    }

    func testDefaultsExactlyMatchOriginalShadowAndGlowConstants() {
        let depth = LumenDepth.standard
        XCTAssertEqual(depth.menu, .init(opacity: .init(light: 0.12, dark: 0.40), radius: 10, y: 4))
        XCTAssertEqual(depth.popover, .init(opacity: .init(light: 0.14, dark: 0.45), radius: 16, y: 6))
        XCTAssertEqual(depth.glow.hero, .init(opacity: 0.4, radius: 20, y: 4))
        XCTAssertEqual(depth.glow.selection, .init(opacity: 0.45, radius: 8, y: 0))
        XCTAssertEqual(LumenDepth.resolving(nil), depth)
        XCTAssertEqual(LumenDepth.resolving(.init()), depth)
        XCTAssertEqual(LumenDepth.resolving(.init(menu: .init(opacity: .init()), popover: .init(),
                                                glow: .init(hero: .init(), selection: .init()))), depth)
    }

    func testEveryLeafInheritsAndExplicitZerosOverride() throws {
        var parent = theme(.init(menu: .init(opacity: .init(light: 0.2, dark: 0.5), radius: 14, y: 5),
                                 popover: .init(opacity: .init(light: 0.3, dark: 0.6), radius: 24, y: 8),
                                 glow: .init(hero: .init(opacity: 0.5, radius: 25, y: 6),
                                             selection: .init(opacity: 0.6, radius: 12, y: 3))))
        parent.id = "parent"
        var child = LumenTheme(id: "child", name: "Child", inherits: parent.id, light: nil, dark: nil)
        child.metrics = .init(depth: .init(menu: .init(opacity: .init(light: 0), y: 0),
                                          popover: .init(opacity: .init(dark: 0), radius: 0),
                                          glow: .init(hero: .init(radius: 0), selection: .init(opacity: 0, y: 0))))
        let flattened = try child.flattened { $0 == parent.id ? parent : nil }
        XCTAssertEqual(flattened.metrics?.depth,
                       .init(menu: .init(opacity: .init(light: 0, dark: 0.5), radius: 14, y: 0),
                             popover: .init(opacity: .init(light: 0.3, dark: 0), radius: 0, y: 8),
                             glow: .init(hero: .init(opacity: 0.5, radius: 0, y: 6),
                                         selection: .init(opacity: 0, radius: 12, y: 0))))
        var grandchild = LumenTheme(id: "grandchild", name: "Grandchild", inherits: child.id, light: nil, dark: nil)
        grandchild.metrics = .init(depth: .init(menu: .init(opacity: .init()), popover: .init(),
                                               glow: .init(hero: .init(), selection: .init())))
        XCTAssertEqual(try grandchild.flattened { [parent.id: parent, child.id: child][$0] }.metrics,
                       flattened.metrics)
        XCTAssertEqual(flattened.schemaVersion, 2)
    }

    func testSparseDepthJSONRoundTripsWithoutMaterializingDefaults() throws {
        let data = Data(#"{"schemaVersion":2,"id":"test.depth","name":"Depth","inherits":"lumen.standard","metrics":{"depth":{"menu":{"opacity":{"dark":0}},"glow":{"selection":{"y":0}}}}}"#.utf8)
        let decoded = try JSONDecoder().decode(LumenTheme.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(try JSONDecoder().decode(LumenTheme.self, from: encoded), decoded)
        XCTAssertNil(decoded.metrics?.depth?.menu?.opacity?.light)
        XCTAssertNil(decoded.metrics?.depth?.popover)
        XCTAssertNil(decoded.metrics?.depth?.glow?.hero)
        let resolved = LumenDepth.resolving(decoded.metrics?.depth)
        XCTAssertEqual(resolved.menu.opacity.dark, 0)
        XCTAssertEqual(resolved.menu.opacity.light, 0.12)
        XCTAssertEqual(resolved.popover, LumenDepth.standard.popover)
    }

    func testBoundsIncludeZeroAndUpperEndpointsForEveryRole() {
        for value in [0.0, 0.6] {
            for radius in [0.0, 32.0] {
                for y in [0.0, radius] {
                    let shadow = LumenThemeDepth.Shadow(opacity: .init(light: value, dark: value), radius: radius, y: y)
                    let halo = LumenThemeDepth.Halo(opacity: value, radius: radius, y: y)
                    XCTAssertTrue(issues(.init(menu: shadow, popover: shadow,
                                              glow: .init(hero: halo, selection: halo))).isEmpty)
                }
            }
        }
    }

    func testEveryOpacityRejectsOutOfBoundsAndNonfiniteValues() {
        let paths = ["menu.opacity.light", "menu.opacity.dark", "popover.opacity.light", "popover.opacity.dark",
                     "glow.hero.opacity", "glow.selection.opacity"]
        for value in [-0.01, 0.61, Double.nan, Double.infinity, -Double.infinity] {
            let shadow = LumenThemeDepth.Shadow(opacity: .init(light: value, dark: value))
            let halo = LumenThemeDepth.Halo(opacity: value)
            let found = issues(.init(menu: shadow, popover: shadow, glow: .init(hero: halo, selection: halo)))
            XCTAssertEqual(found.count, paths.count)
            for path in paths {
                XCTAssertTrue(found.contains { $0.severity == .error && $0.message.hasPrefix("metrics.depth.\(path) must be finite") }, path)
            }
        }
    }

    func testEveryRadiusRejectsOutOfBoundsAndNonfiniteValues() {
        for value in [-0.01, 32.01, Double.nan, Double.infinity, -Double.infinity] {
            let shadow = LumenThemeDepth.Shadow(radius: value, y: 0)
            let halo = LumenThemeDepth.Halo(radius: value, y: 0)
            let found = issues(.init(menu: shadow, popover: shadow, glow: .init(hero: halo, selection: halo)))
            for path in ["menu", "popover", "glow.hero", "glow.selection"] {
                XCTAssertTrue(found.contains { $0.severity == .error && $0.message.hasPrefix("metrics.depth.\(path).radius must be finite") }, path)
            }
        }
    }

    func testEveryOffsetRejectsNegativeAboveRadiusAndNonfiniteValues() {
        for value in [-0.01, 8.01, Double.nan, Double.infinity, -Double.infinity] {
            let shadow = LumenThemeDepth.Shadow(radius: 8, y: value)
            let halo = LumenThemeDepth.Halo(radius: 8, y: value)
            let found = issues(.init(menu: shadow, popover: shadow, glow: .init(hero: halo, selection: halo)))
            XCTAssertEqual(found.count, 4)
            for path in ["menu", "popover", "glow.hero", "glow.selection"] {
                XCTAssertTrue(found.contains { $0.severity == .error && $0.message.hasPrefix("metrics.depth.\(path).y must be finite") }, path)
            }
        }
    }

    func testPopoverCannotBeShallowerInEitherAppearanceOrRadius() {
        let cases: [(LumenThemeDepth, String)] = [
            (.init(popover: .init(opacity: .init(light: 0.11))), "opacity.light"),
            (.init(popover: .init(opacity: .init(dark: 0.39))), "opacity.dark"),
            (.init(popover: .init(radius: 9)), "radius"),
            (.init(menu: .init(opacity: .init(light: 0.15))), "opacity.light"),
            (.init(menu: .init(opacity: .init(dark: 0.46))), "opacity.dark"),
            (.init(menu: .init(radius: 17)), "radius"),
        ]
        for (depth, path) in cases {
            let found = issues(depth)
            XCTAssertEqual(found.count, 1)
            XCTAssertEqual(found.first?.message, "metrics.depth.popover.\(path) must be at least metrics.depth.menu.\(path)")
        }
    }

    func testDepthDiagnosticsAreReportedOnceAcrossAppearances() {
        var invalid = theme(.init(glow: .init(hero: .init(opacity: 0.7))))
        invalid.lightHighContrast = [:]
        invalid.darkHighContrast = [:]
        let found = LumenValidator.issues(for: invalid, in: LumenRegistry(packs: []))
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found[0].message.contains("metrics.depth.glow.hero.opacity"))
    }
}
