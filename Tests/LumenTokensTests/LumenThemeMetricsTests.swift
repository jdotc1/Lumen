import Foundation
import XCTest
@testable import LumenTokens

final class LumenThemeMetricsTests: XCTestCase {
    private func theme(_ metrics: LumenThemeMetrics? = nil) -> LumenTheme {
        var theme = LumenTheme(id: "test.metrics", name: "Metrics", light: [:], dark: [:])
        theme.metrics = metrics
        return theme
    }

    func testPaletteOnlyThemesKeepSchemaOneAndOmitMetrics() throws {
        let original = theme()
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(original.schemaVersion, 1)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNil(object["metrics"])
        let implicitVersion = Data(#"{"id":"v1","name":"V1","light":{}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(LumenTheme.self, from: implicitVersion).schemaVersion, 1)
    }

    func testMetricsRoundTripInSchemaTwo() throws {
        for profile in [LumenThemeMetrics.RadiusProfile.standard, .rounded, .uniform(7.5)] {
            let original = theme(LumenThemeMetrics(radiusProfile: profile, typeScale: 1.1,
                                                  spacingScale: 1.25, motion: .reduced))
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(LumenTheme.self, from: encoded)
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(decoded.schemaVersion, 2)
            XCTAssertEqual(decoded.metrics?.radiusProfile, profile)
            XCTAssertTrue(LumenTheme.unknownTopLevelKeys(in: encoded).isEmpty)
        }
    }

    func testMetricsInitializerPromotesAndEncodingCannotMislabelMetricsAsV1() throws {
        var original = LumenTheme(id: "metrics", name: "Metrics", light: [:], dark: nil,
                                  metrics: LumenThemeMetrics(typeScale: 1.1))
        XCTAssertEqual(original.schemaVersion, 2)
        original.schemaVersion = 1
        let decoded = try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.schemaVersion, 2)
        original.metrics = nil
        original.schemaVersion = 2
        XCTAssertEqual(try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(original)).schemaVersion, 2)
    }

    func testFutureMetricsReachTheNewerSchemaPath() throws {
        let encoded = Data(#"{"schemaVersion":3,"id":"future","name":"Future","metrics":{"radiusProfile":{"future":true}}}"#.utf8)
        let decoded = try JSONDecoder().decode(LumenTheme.self, from: encoded)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertGreaterThan(decoded.schemaVersion, LumenTheme.currentSchemaVersion)
    }

    func testMetricsInheritPerMemberAndExplicitNeutralValuesOverride() throws {
        var parent = theme(LumenThemeMetrics(radiusProfile: .rounded, typeScale: 1.2,
                                             spacingScale: 1.25, motion: .reduced))
        parent.id = "parent"
        var child = LumenTheme(id: "child", name: "Child", inherits: parent.id, light: nil, dark: nil)
        child.metrics = LumenThemeMetrics(typeScale: 1, motion: .standard)
        let flattened = try child.flattened { $0 == parent.id ? parent : nil }
        XCTAssertEqual(flattened.metrics, LumenThemeMetrics(radiusProfile: .rounded, typeScale: 1,
                                                          spacingScale: 1.25, motion: .standard))
        XCTAssertEqual(flattened.schemaVersion, 2)
        var grandchild = LumenTheme(id: "grandchild", name: "Grandchild", inherits: "child", light: nil, dark: nil)
        grandchild.metrics = LumenThemeMetrics()
        let inherited = try grandchild.flattened { ["parent": parent, "child": child][$0] }
        XCTAssertEqual(inherited.metrics, flattened.metrics)
    }

    func testAbsentMetricsStayAbsentThroughInheritance() throws {
        let parent = theme()
        let child = LumenTheme(id: "child", name: "Child", inherits: parent.id, light: nil, dark: nil)
        let flattened = try child.flattened { $0 == parent.id ? parent : nil }
        XCTAssertNil(flattened.metrics)
        XCTAssertEqual(flattened.schemaVersion, 1)
    }

    func testMetricBoundsIncludeTheirEndpoints() {
        for scale in [0.9, 1.0, 1.3] {
            XCTAssertTrue(LumenValidator.metricIssues(in: theme(LumenThemeMetrics(typeScale: scale)), registry: .core).isEmpty)
        }
        for scale in [1.0, 1.25] {
            XCTAssertTrue(LumenValidator.metricIssues(in: theme(LumenThemeMetrics(spacingScale: scale)), registry: .core).isEmpty)
        }
        for radius in [0.0, 12.0] {
            XCTAssertTrue(LumenValidator.metricIssues(in: theme(LumenThemeMetrics(radiusProfile: .uniform(radius))), registry: .core).isEmpty)
        }
    }

    func testMetricBoundsRejectInvalidAndNonfiniteValues() {
        let invalid: [LumenThemeMetrics] = [
            .init(typeScale: 1.4), .init(typeScale: 0.89), .init(typeScale: .nan), .init(typeScale: .infinity),
            .init(spacingScale: 0.99), .init(spacingScale: 1.26), .init(spacingScale: .nan),
            .init(radiusProfile: .uniform(12.01)), .init(radiusProfile: .uniform(-1)), .init(radiusProfile: .uniform(.infinity)),
        ]
        for metrics in invalid {
            let issues = LumenValidator.metricIssues(in: theme(metrics), registry: .core)
            XCTAssertEqual(issues.count, 1, "\(metrics)")
            XCTAssertEqual(issues.first?.severity, .error)
        }
    }

    func testMetricIssuesAreReportedOnceAcrossAppearances() {
        var invalid = theme(LumenThemeMetrics(typeScale: 1.4))
        invalid.lightHighContrast = [:]
        invalid.darkHighContrast = [:]
        let registry = LumenRegistry(packs: [])
        let issues = LumenValidator.issues(for: invalid, in: registry)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("metrics.typeScale"))
    }

    func testPackLocksUnionAndRejectInheritedAndNeutralValues() throws {
        var first = LumenPack(id: "first")
        first.lockedMetrics = [.typeScale, .motion]
        var second = LumenPack(id: "second")
        second.lockedMetrics = [.spacingScale, .radiusProfile, .motion, .depth]
        let registry = LumenRegistry(packs: [first, second])
        XCTAssertEqual(registry.lockedMetrics, Set(LumenThemeMetrics.Key.allCases))
        let parent = theme(LumenThemeMetrics(radiusProfile: .standard, typeScale: 1, spacingScale: 1, motion: .standard, depth: .init()))
        let child = LumenTheme(id: "child", name: "Child", inherits: parent.id, light: nil, dark: nil)
        let inherited = try child.flattened { $0 == parent.id ? parent : nil }
        let issues = LumenValidator.metricIssues(in: inherited, registry: registry)
        XCTAssertEqual(issues.count, 5)
        XCTAssertTrue(issues.allSatisfy { $0.severity == .error && $0.message.contains("locked") })
        XCTAssertTrue(LumenValidator.metricIssues(in: theme(), registry: registry).isEmpty)
    }
}
