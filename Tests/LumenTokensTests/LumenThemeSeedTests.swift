import Foundation
import XCTest
@testable import LumenTokens

final class LumenThemeSeedTests: XCTestCase {
    /// Twelve hues × two ground preferences = 24 themes, 96 appearances.
    /// Validate the actual saved colors, not merely the unrounded derivation in memory.
    func testSeedExitGridPreservesHueAndChromaWithEveryCoreTokenAndZeroIssues() throws {
        let registry = LumenRegistry.core
        let expectedTokens = Set(registry.tokens.map(\.rawValue))
        let appearances: [LumenAppearance] = [
            .light, .dark, .init(isDark: false, isHighContrast: true), .init(isDark: true, isHighContrast: true),
        ]
        var themeCount = 0
        for ground in LumenSeedGround.allCases {
            for hue in stride(from: 0, to: 360, by: 30) {
                let identity = "seed.\(ground.rawValue).\(hue)"
                var foundation = LumenThemes.standard
                if ground == .paperGraphite { foundation.light?[.bgCanvas] = "#FBFAF7" }
                else { foundation.dark = LumenThemes.contrastDark }
                let beforeFix = try foundation.seedDerived(accentHue: Double(hue), in: registry)
                let theme: LumenTheme
                do { theme = try LumenTheme.seeded(accentHue: Double(hue), ground: ground, id: identity, name: identity) }
                catch { XCTFail("\(identity): \(error)"); continue }
                XCTAssertEqual(theme.id, identity)
                XCTAssertEqual(theme.name, identity)
                XCTAssertNil(theme.inherits)
                XCTAssertNil(theme.metrics)
                XCTAssertEqual(theme.schemaVersion, 1)
                XCTAssertNotNil(theme.lightHighContrast)
                XCTAssertNotNil(theme.darkHighContrast)
                for appearance in appearances {
                    XCTAssertEqual(Set(theme.palette(for: appearance).colors.keys), expectedTokens,
                                   "\(identity), \(appearance)")
                    try assertAccent(theme, baseline: beforeFix, hue: Double(hue), appearance: appearance, registry: registry)
                    for token in LumenToken.hues {
                        let expected = ground == .brightDeep && appearance.isDark
                            ? LumenThemes.contrastDark[token]
                            : LumenThemes.standard.color(token, for: appearance, in: registry)
                        XCTAssertEqual(theme.color(token, for: appearance, in: registry), expected,
                                       "Category hues retain the existing tile-color rules")
                    }
                }
                let saved = try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(theme))
                let issues = LumenValidator.issues(for: saved, in: registry)
                XCTAssertEqual(issues.map { "\($0.appearance): \($0.message)" }, [], identity)
                themeCount += 1
            }
        }
        XCTAssertEqual(themeCount, 12 * LumenSeedGround.allCases.count)
    }

    func testCatalogDefaultSeedSeparatesCurrentLineWithoutChangingSemanticColors() throws {
        let registry = LumenRegistry(packs: [.core, .code])
        let theme = try LumenTheme.seeded(accentHue: 260, ground: .paperGraphite,
                                         id: "seed.catalog", in: registry)
        let saved = try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(theme))
        XCTAssertEqual(LumenValidator.issues(for: saved, in: registry).map { "\($0.appearance): \($0.message)" }, [])
        let standard = try XCTUnwrap(registry.theme(id: LumenThemes.standardID))
        let appearances: [LumenAppearance] = [
            .light, .dark, .init(isDark: false, isHighContrast: true), .init(isDark: true, isHighContrast: true),
        ]
        var foundation = standard
        foundation.light?[.bgCanvas] = "#FBFAF7"
        let beforeFix = try foundation.seedDerived(accentHue: 260, in: registry)
        var adaptedBandCount = 0
        for appearance in appearances {
            XCTAssertEqual(Set(saved.palette(for: appearance).colors.keys), Set(registry.tokens.map(\.rawValue)))
            try assertAccent(saved, baseline: beforeFix, hue: 260, appearance: appearance, registry: registry)
            let band = saved.color(LumenToken.Code.currentLine, for: appearance, in: registry)
            if band != standard.color(LumenToken.Code.currentLine, for: appearance, in: registry) { adaptedBandCount += 1 }
            for token in LumenToken.hues + [.statusSuccess, .statusWarning, .statusDanger] {
                XCTAssertEqual(saved.color(token, for: appearance, in: registry),
                               standard.color(token, for: appearance, in: registry), "\(appearance), \(token)")
            }
        }
        XCTAssertGreaterThan(adaptedBandCount, 0, "The Catalog's current-line collision must be repaired")
    }

    private func assertAccent(_ theme: LumenTheme, baseline: LumenTheme, hue: Double,
                              appearance: LumenAppearance, registry: LumenRegistry) throws {
        // Convert the documented HSV input to OKLab independently of the seed implementation.
        let sector = hue / 60, c = 0.85 * 0.72, m = 0.85 - c
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let channels: [(Double, Double, Double)] = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
        let rgb = channels[Int(sector) % 6]
        let seed = LumenColor(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m).oklab
        let expectedHue = atan2(seed.b, seed.a) * 180 / .pi
        let required: Set<LumenToken> = [.accent, .accentFilled, .accentSubtle, .accentSoft, .bgSelected,
            .borderFocus, .fgLink, .menuHighlight, .chipSelectedBackground, .sidebarAccent,
            .sidebarRowSelected, .tabAccentBar, .layoutToggleOn, .welcomeGlow, .fieldBackground]
        XCTAssertTrue(required.isSubset(of: Set(registry.seedAccentTokens)))
        let saved = try JSONDecoder().decode(LumenTheme.self, from: JSONEncoder().encode(theme))
        for token in registry.seedAccentTokens {
            let original = baseline.color(token, for: appearance, in: registry).oklab
            let actual = saved.color(token, for: appearance, in: registry).oklab
            let delta = abs(atan2(actual.b, actual.a) * 180 / .pi - expectedHue).truncatingRemainder(dividingBy: 360)
            let label = "hue \(hue), \(appearance), \(token.rawValue)"
            XCTAssertLessThanOrEqual(min(delta, 360 - delta), 20, label)
            // Half the ORIGINAL pre-Fix role chroma allows saved RGB quantization and bounded
            // gamut accommodation, but never a desaturated retry baseline. The independent
            // absolute floor prevents a nearly gray baseline from making this check vacuous.
            XCTAssertGreaterThanOrEqual(hypot(original.a, original.b), 0.023, label)
            XCTAssertGreaterThanOrEqual(hypot(actual.a, actual.b), max(0.0125, 0.5 * hypot(original.a, original.b)), label)
        }
    }

    func testSeedRejectsNonfiniteAndOutOfRangeHue() {
        for hue in [-1, 361, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try LumenTheme.seeded(accentHue: hue)) { error in
                guard case LumenThemeSeedError.invalidHue = error else {
                    return XCTFail("Expected invalidHue, got \(error)")
                }
            }
        }
    }
}
