import Foundation
import XCTest
import LumenTokens
import LumenUI
@testable import InspectorPack

/// Plans A2: the snapshot Inspector sends its plug-ins over XPC (`PluginThemeSnapshot`: the 110
/// role colors plus spacing and radius) produced from a store that isn't the shared one. Two such
/// stores live side by side, each with its own theme.
@MainActor
final class InspectorPackScopedStoreTests: XCTestCase {
    struct Expected: Decodable {
        let colors: [String: [String: [String: String]]]
        let order: [String]
    }

    /// The snapshot's shape: role key → hex, and metric name → points.
    struct Snapshot {
        var colors: [String: String] = [:]
        var spacing: [String: Double] = [:]
        var radius: [String: Double] = [:]
    }

    static func snapshot(of store: LumenThemeStore, roles: [String], appearance: LumenAppearance,
                         metrics: LumenMetrics = .standard) -> Snapshot {
        var snapshot = Snapshot()
        for role in roles { snapshot.colors[role] = store.resolvedColor(LumenToken(role), for: appearance).hexString }
        let s = metrics.spacing
        for (name, value) in [("s1", s.s1), ("s2", s.s2), ("s3", s.s3), ("s4", s.s4), ("s5", s.s5), ("s6", s.s6),
                              ("s7", s.s7), ("s8", s.s8), ("s9", s.s9), ("s10", s.s10), ("s11", s.s11)] {
            snapshot.spacing[name] = Double(value)
        }
        let r = metrics.radius
        for (name, value) in [("xs", r.xs), ("sm", r.sm), ("md", r.md), ("lg", r.lg), ("xl", r.xl), ("pill", r.pill)] {
            snapshot.radius[name] = Double(value)
        }
        return snapshot
    }

    private func store(_ themeID: String) -> LumenThemeStore {
        LumenThemeStore(configuration: LumenStoreConfiguration(appName: "InspectorPluginHost",
                                                               themesDirectory: URL(fileURLWithPath: "/dev/null/inspector-plugin"),
                                                               defaultThemeID: themeID),
                        registry: .inspectorPack, themes: LumenRegistry.inspectorPack.galleryThemes)
    }

    func testXPCSnapshotFromNonGlobalStores() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "inspector-expected", withExtension: "json"))
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url))
        let shared = LumenThemeStore.shared
        let sharedTheme = shared.theme().id

        let midnight = store("com.inspector.theme.midnight"), scope = store("com.inspector.theme.scope")
        XCTAssertFalse(LumenThemeStore.active === midnight || LumenThemeStore.active === scope, "Neither store is installed")

        var checked = 0
        for (store, appearances) in [(midnight, ["dark", "dark+contrast"]), (scope, ["light", "dark"])] {
            let themeID = store.theme().id
            for key in appearances {
                let appearance = LumenAppearance(isDark: key.hasPrefix("dark"), isHighContrast: key.hasSuffix("+contrast"))
                let snapshot = Self.snapshot(of: store, roles: expected.order, appearance: appearance)
                XCTAssertEqual(snapshot.colors.count, 110, "\(themeID) \(key)")
                XCTAssertEqual(snapshot.spacing.count, 11)
                XCTAssertEqual(snapshot.radius.count, 6)
                let want = try XCTUnwrap(expected.colors[themeID]?[key], "\(themeID) \(key)")
                XCTAssertEqual(snapshot.colors, want, "\(themeID) \(key)")
                checked += snapshot.colors.count
            }
        }
        XCTAssertEqual(checked, 110 * 4)
        // The two stores' snapshots differ: each carries its own theme.
        let dark = LumenAppearance(isDark: true, isHighContrast: false)
        XCTAssertNotEqual(Self.snapshot(of: midnight, roles: expected.order, appearance: dark).colors,
                          Self.snapshot(of: scope, roles: expected.order, appearance: dark).colors)
        XCTAssertTrue(LumenThemeStore.shared === shared)
        XCTAssertEqual(shared.theme().id, sharedTheme, "The shared store is untouched")
    }
}
