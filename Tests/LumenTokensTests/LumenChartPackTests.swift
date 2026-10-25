import XCTest
@testable import LumenTokens

final class LumenChartPackTests: XCTestCase {
    private let registry = LumenRegistry(packs: [.core, .chart])

    func testEverySeriesDeclaresCanvasContrastAndRejectsInvisibleInk() throws {
        for token in LumenToken.Chart.series {
            let pairs = try XCTUnwrap(registry.spec(for: token)).contrast
            let pair = try XCTUnwrap(pairs.first { $0.ground == .bgCanvas })
            XCTAssertEqual(pair.minimum, 3)
            var theme = try XCTUnwrap(registry.theme(id: LumenThemes.standardID))
            let appearance = LumenAppearance(isDark: false)
            let canvas = theme.color(.bgCanvas, for: appearance, in: registry)
            theme.light = LumenPalette(colors: [token.rawValue: canvas, LumenToken.bgCanvas.rawValue: canvas])
            XCTAssertNotNil(LumenValidator.contrastIssue(token, pair, in: theme, appearance: appearance, registry: registry))
        }
    }

    func testSeriesContrastInEveryBuiltInTheme() {
        for theme in registry.builtInThemes {
            for appearance in appearances(theme) {
                let ratios = LumenToken.Chart.series.map { token in
                    LumenValidator.measuredContrast(theme.color(token, for: appearance, in: registry),
                        on: LumenValidator.opaqueGrounds(.bgCanvas, in: theme, appearance: appearance, registry: registry),
                        space: theme.colorSpace)
                }
                print("Chart contrast \(theme.id) \(appearance): \(ratios.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
                for token in LumenToken.Chart.series {
                    if let issue = LumenValidator.contrastIssue(token, .graphic(on: .bgCanvas), in: theme, appearance: appearance, registry: registry) {
                        XCTFail("\(theme.id): \(issue.message)")
                    }
                }
            }
        }
    }

    func testDistinctSeriesInEveryBuiltInTheme() throws {
        let rule = try XCTUnwrap(LumenPack.chart.rules.compactMap { $0 as? LumenDistinctRule }.first)
        XCTAssertEqual(rule.tokens, LumenToken.Chart.series)
        XCTAssertEqual(rule.minimumDistance, 0.08)
        for theme in registry.builtInThemes {
            for appearance in appearances(theme) {
                let issues = rule.issues(in: theme, appearance: appearance, registry: registry)
                print("Chart distinct \(theme.id) \(appearance): \(issues.count) findings (28 pairs)")
                XCTAssertTrue(issues.isEmpty, "\(theme.id) \(appearance): \(issues.map(\.message))")
            }
        }
    }

    private func appearances(_ theme: LumenTheme) -> [LumenAppearance] {
        theme.supportedAppearances.flatMap { dark in
            let highContrast = (dark ? theme.darkHighContrast : theme.lightHighContrast) != nil
            return (highContrast ? [false, true] : [false]).map { LumenAppearance(isDark: dark, isHighContrast: $0) }
        }
    }
}
