import Charts
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor final class LumenChartTests: XCTestCase {
    func testStyleResolvesEveryThemeAndTypeRamp() {
        let registry = LumenRegistry(packs: [.core, .chart])
        for variant in LumenSnapshot.Variant.all(for: registry.builtInThemes) {
            let store = LumenSnapshot.store(for: variant, registry: registry)
            let palette = store.resolvedPalette()
            var metrics = LumenMetrics.standard
            metrics.typography.caption = .system(size: 19)
            metrics.stroke = .init(hairline: 2, regular: 3, focus: 4)
            let style = LumenChartStyle(palette: palette, metrics: metrics)
            XCTAssertEqual(style.series, LumenToken.Chart.series.map { palette[$0] })
            XCTAssertEqual(style.grid, palette[LumenToken.Chart.grid])
            XCTAssertEqual(style.axis, palette[LumenToken.Chart.axis])
            XCTAssertEqual(style.label, palette[LumenToken.Chart.label])
            XCTAssertEqual(style.canvas, palette[.bgCanvas])
            XCTAssertEqual(style.axisLabelFont, metrics.typography.caption)
            XCTAssertEqual(style.gridStroke.lineWidth, 2)
            XCTAssertEqual(style.axisStroke.lineWidth, 3)
            var environment = EnvironmentValues()
            environment.lumenPalette = palette
            environment.lumenMetrics = metrics
            XCTAssertEqual(environment.lumenChartStyle.series, style.series)
            XCTAssertEqual(environment.lumenChartStyle.axisLabelFont, style.axisLabelFont)
        }
    }

    func testEmptyStateSwitchUsesFiniteObservations() {
        XCTAssertTrue(LumenChartPresentation([]).isEmpty)
        XCTAssertTrue(LumenChartPresentation([.init(label: "Missing", value: .nan), .init(label: "Overflow", value: .infinity)]).isEmpty)
        XCTAssertFalse(LumenChartPresentation([.init(label: "Zero", value: 0)]).isEmpty)
        XCTAssertFalse(LumenChartPresentation([.init(label: "Negative", value: -2)]).isEmpty)
    }

    func testLegendOnlyForMultipleSeriesInFirstAppearanceOrder() {
        XCTAssertFalse(LumenChartPresentation([]).showsLegend)
        XCTAssertFalse(LumenChartPresentation([.init(label: "A", value: 1), .init(label: "B", value: 2)]).showsLegend)
        XCTAssertFalse(LumenChartPresentation([.init(label: "A", value: 1, series: "One")]).showsLegend)
        let presentation = LumenChartPresentation([
            .init(label: "A", value: 1, series: "Second"), .init(label: "B", value: 2, series: "First"),
            .init(label: "C", value: 3, series: "Second"), .init(label: "D", value: .nan, series: "Missing")])
        XCTAssertTrue(presentation.showsLegend)
        XCTAssertEqual(presentation.seriesLabels, ["Second", "First"])
        let unnamed = LumenChartPresentation([.init(label: "A", value: 1), .init(label: "A", value: 2, series: "Value")])
        XCTAssertEqual(Set(unnamed.series).count, 2, "A named Value series must not merge with an unnamed series")
    }
    func testHistogramKnownFixtureCountsBoundariesAndDropsNonfiniteValues() {
        let histogram = LumenHistogramPresentation(values: [0, 1, 1, 2, 3, 4, .nan, .infinity, -.infinity], binCount: 2)
        XCTAssertFalse(histogram.isEmpty)
        XCTAssertEqual(histogram.bins.map(\.count), [3, 3])
        XCTAssertEqual(histogram.bins.map { $0.range.lowerBound }, [0, 2])
        XCTAssertEqual(histogram.bins.map { $0.range.upperBound }, [2, 4])
        XCTAssertFalse(histogram.bins[0].range.contains(2))
        XCTAssertTrue(histogram.bins[1].range.contains(4))
    }

    func testHistogramEmptyAndAllNonfiniteInput() {
        let inputs: [[Double]] = [[], [.nan, .infinity, -.infinity]]
        let choices: [Int?] = [nil, 4]
        for values in inputs {
            for count in choices {
                let histogram = LumenHistogramPresentation(values: values, binCount: count)
                XCTAssertTrue(histogram.isEmpty)
                XCTAssertTrue(histogram.bins.isEmpty)
            }
        }
    }

    func testHistogramAutomaticBinsAndConstantObservations() {
        let values: [Double] = [-3, -2, -1, 0, 0, 1, 2, 3]
        let automatic = NumberBins(data: values)
        let histogram = LumenHistogramPresentation(values: values)
        XCTAssertEqual(histogram.bins.map { $0.range.lowerBound }, automatic.map(\.lowerBound))
        XCTAssertEqual(histogram.bins.map { $0.range.upperBound }, automatic.map(\.upperBound))
        XCTAssertEqual(histogram.bins.reduce(0) { $0 + $1.count }, values.count)
        let choices: [Int?] = [nil, 3]
        for count in choices {
            let constant = LumenHistogramPresentation(values: [5, 5, 5], binCount: count)
            XCTAssertFalse(constant.isEmpty)
            XCTAssertEqual(constant.bins.reduce(0) { $0 + $1.count }, 3)
            XCTAssertTrue(constant.bins.allSatisfy { $0.range.lowerBound < $0.range.upperBound })
            if let count { XCTAssertEqual(constant.bins.count, count) }
        }
    }

    func testHistogramNonpositiveBinCountUsesOneBin() {
        for count in [0, -2] {
            let histogram = LumenHistogramPresentation(values: [-1, 0, 1], binCount: count)
            XCTAssertEqual(histogram.bins.map(\.count), [3])
        }
    }

}
