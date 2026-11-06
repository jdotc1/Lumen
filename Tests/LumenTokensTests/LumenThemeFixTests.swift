import Foundation
import XCTest
@testable import LumenTokens

final class LumenThemeFixTests: XCTestCase {
    private let ink: LumenToken = "test.ink"
    private let ground: LumenToken = "test.ground"
    private let other: LumenToken = "test.other"

    private func registry(minimum: Double = 4.5, secondGround: Bool = false) -> LumenRegistry {
        var requirements = [LumenContrast(on: ground, minimum: minimum)]
        if secondGround { requirements.append(LumenContrast(on: other, minimum: minimum)) }
        return LumenRegistry(packs: [LumenPack(id: "test.fix", tokens: [
            LumenTokenSpec(ink, group: "Test", contrast: requirements),
            LumenTokenSpec(ground, group: "Test"), LumenTokenSpec(other, group: "Test"),
        ])])
    }

    private func theme(ink color: LumenColor = "#AA88AA", ground backdrop: LumenColor = "#FFFFFF",
                       other second: LumenColor = "#000000") -> LumenTheme {
        LumenTheme(id: "test.fix", name: "Fix", light: [ink: color, ground: backdrop, other: second], dark: nil)
    }

    func testContrastFixOnlyMovesForegroundAndPreservesChromaAndHue() throws {
        let registry = registry(), original = theme()
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first { $0.fix != nil })
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
        XCTAssertEqual(fixed.light?[ground], original.light?[ground])
        XCTAssertEqual(fixed.light?[other], original.light?[other])
        let before = try XCTUnwrap(original.light?[ink]).oklab
        let after = try XCTUnwrap(fixed.light?[ink]).oklab
        XCTAssertEqual(before.a, after.a, accuracy: 0.000001)
        XCTAssertEqual(before.b, after.b, accuracy: 0.000001)
        XCTAssertLessThan(after.l, before.l)
        let saved = try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(fixed))
        XCTAssertTrue(LumenValidator.issues(for: saved, in: registry).isEmpty, "Hex rounding must not reintroduce the finding")
    }

    func testNarrowPassingIntervalIsFoundWithoutReducingChroma() throws {
        // A 4.58 ratio against both black and white leaves only about .00026 luminance.
        // This fixture has a colored, byte-representable solution even inside that narrow band.
        let registry = registry(minimum: 4.58, secondGround: true)
        let original = theme(ink: LumenColor(red: 0.5836348599983545, green: 0.5754613847821999, blue: 0.5713761361125822))
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
        XCTAssertEqual(try XCTUnwrap(fixed.light?[ink]).oklab.a, try XCTUnwrap(original.light?[ink]).oklab.a, accuracy: 0.000001)
    }

    func testImpossibleContrastReportsWithoutMutatingInput() throws {
        let registry = registry(minimum: 7, secondGround: true), original = theme()
        let snapshot = original
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: registry)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No lightness"))
        }
        XCTAssertEqual(original, snapshot)
    }

    func testContrastReducesChromaOnlyWhenGamutRequiresIt() throws {
        let registry = registry(), original = theme(ink: "#FF0000")
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        let before = try XCTUnwrap(original.light?[ink]).oklab
        let after = try XCTUnwrap(fixed.light?[ink]).oklab
        XCTAssertLessThan(hypot(after.a, after.b), hypot(before.a, before.b))
        XCTAssertEqual(atan2(after.b, after.a), atan2(before.b, before.a), accuracy: 0.00001)
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testAccentFillAsRuleForegroundNeverDesaturates() throws {
        let registry = LumenRegistry(packs: [LumenPack(id: "test.accent", tokens: [
            LumenTokenSpec(.accentFilled, group: "Test", contrast: [.init(on: ground, minimum: 21)], followsSystemAccent: true),
            LumenTokenSpec(ground, group: "Test"),
        ])])
        let original = LumenTheme(id: "test", name: "Test", light: [.accentFilled: "#7040B0", ground: "#FFFFFF"], dark: nil)
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: registry),
                             "A rule naming a fill as foreground must not turn it black to reach 21:1")
    }

    func testInkFixPreservesAccentFill() throws {
        let registry = LumenRegistry(packs: [LumenPack(id: "test.fillInk", tokens: [
            LumenTokenSpec(.accentFilled, group: "Test", followsSystemAccent: true),
            LumenTokenSpec(.accentFilledForeground, group: "Test", contrast: [.text(on: .accentFilled)]),
        ])])
        let original = LumenTheme(id: "test", name: "Test", light: [
            .accentFilled: "#7040B0", .accentFilledForeground: "#806090",
        ], dark: nil)
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertEqual(fixed.light?[.accentFilled], original.light?[.accentFilled])
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testOpacityFixKeepsRGBAndMakesTokenOpaque() throws {
        let registry = registry(), original = theme(ink: "#11001180")
        let issue = try XCTUnwrap(LumenValidator.opacityIssue(ink, in: original, appearance: .light, registry: registry))
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertEqual(fixed.light?[ink], LumenColor(hex: "#110011"))
        XCTAssertEqual(fixed.light?[ground], original.light?[ground])
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testEachNumericMetricClampsAndLockedMetricRefuses() throws {
        let registry = registry()
        var original = theme()
        original.metrics = LumenThemeMetrics(radiusProfile: .uniform(-4), typeScale: 2, spacingScale: 0.5)
        var fixed = original
        for issue in LumenValidator.metricIssues(in: original, registry: registry) {
            fixed = try LumenValidator.fix(issue, in: fixed, registry: registry)
        }
        XCTAssertEqual(fixed.metrics, LumenThemeMetrics(radiusProfile: .uniform(0), typeScale: 1.3, spacingScale: 1))
        XCTAssertTrue(LumenValidator.metricIssues(in: fixed, registry: registry).isEmpty)
        var lock = LumenPack(id: "test.lock"); lock.lockedMetrics = [.typeScale]
        let locked = LumenRegistry(packs: registry.packs + [lock])
        let issue = try XCTUnwrap(LumenValidator.metricIssues(in: original, registry: registry).first { $0.fix == .metric(key: .typeScale, minimum: 0.9, maximum: 1.3) })
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: locked))
    }

    func testNaNMetricReportsAndInfiniteMetricClamps() throws {
        let registry = registry()
        var original = theme()
        original.metrics = LumenThemeMetrics(typeScale: .nan)
        let issue = try XCTUnwrap(LumenValidator.metricIssues(in: original, registry: registry).first)
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: registry))
        original.metrics = LumenThemeMetrics(typeScale: .infinity)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertEqual(fixed.metrics?.typeScale, 1.3)
    }

    func testDisplayP3WhiteCanMoveToPassingLightness() throws {
        let registry = registry()
        var original = theme(ink: "#FFFFFF")
        original.colorSpace = .displayP3
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testHighContrastFixLeavesBasePaletteAlone() throws {
        let registry = registry()
        var original = theme(ink: "#110011")
        original.lightHighContrast = [ink: "#AA88AA"]
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        XCTAssertTrue(issue.appearance.isHighContrast)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertEqual(fixed.light, original.light)
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testForegroundGroundDependencyIsReportedInsteadOfMovingGround() throws {
        let registry = LumenRegistry(packs: [LumenPack(id: "test.dependency", tokens: [
            LumenTokenSpec(ink, group: "Test", contrast: [.text(on: ground)]),
            LumenTokenSpec(ground, group: "Test", fallback: .token(ink)),
        ])])
        let original = LumenTheme(id: "test", name: "Test", light: [ink: "#777777"], dark: nil)
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: registry))
    }
    func testRaisedContrastFixMovesTheSubstitutedForegroundOnly() throws {
        let registry = LumenRegistry(packs: [LumenPack(id: "test.raised", tokens: [
            LumenTokenSpec(.bgInset, group: "Test", contrast: [.text(on: .bgCanvas)]),
            LumenTokenSpec(.bgInsetRaised, group: "Test"), LumenTokenSpec(.bgCanvas, group: "Test"),
        ])])
        let original = LumenTheme(id: "test", name: "Test", light: [
            .bgInset: "#111111", .bgInsetRaised: "#AAAAAA", .bgCanvas: "#FFFFFF",
        ], dark: nil)
        let issue = try XCTUnwrap(LumenValidator.issues(for: original, in: registry).first)
        let fixed = try LumenValidator.fix(issue, in: original, registry: registry)
        XCTAssertEqual(fixed.light?[.bgInset], original.light?[.bgInset])
        XCTAssertEqual(fixed.light?[.bgCanvas], original.light?[.bgCanvas])
        XCTAssertNotEqual(fixed.light?[.bgInsetRaised], original.light?[.bgInsetRaised])
        XCTAssertTrue(LumenValidator.issues(for: fixed, in: registry).isEmpty)
    }

    func testContrastFixDoesNotSilentlyChangeAlpha() throws {
        let registry = registry(), original = theme(ink: "#AAAAAA80")
        let issue = try XCTUnwrap(LumenValidator.contrastIssue(ink, .text(on: ground), in: original,
                                                            appearance: .light, registry: registry))
        XCTAssertThrowsError(try LumenValidator.fix(issue, in: original, registry: registry))
        XCTAssertEqual(original.light?[ink]?.alpha, Double(128) / 255)
    }

}
