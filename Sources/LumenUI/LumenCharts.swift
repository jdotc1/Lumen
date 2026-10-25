import Charts
import SwiftUI
import LumenTokens

/// One labeled chart value. Keep its identity when updating values. Labels retain input order on
/// categorical axes; `nil` series is an independent, unnamed series.
public struct LumenChartDatum: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var label: String
    public var value: Double
    public var series: String?

    public init(id: UUID = UUID(), label: String, value: Double, series: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.series = series
    }

    var seriesKey: String { series.map { "series:\($0)" } ?? "unnamed" }
}

/// The chart pack resolved through the active palette and type ramp. Register `.chart` alongside
/// `.core` in the store's registry. Eight series colors are assigned in pack order, then repeat.
public struct LumenChartStyle: Sendable {
    public let series: [Color]
    public let grid: Color
    public let axis: Color
    public let label: Color
    public let canvas: Color
    public let axisLabelFont: Font
    public let gridStroke: StrokeStyle
    public let axisStroke: StrokeStyle

    public init(palette: LumenResolvedPalette, metrics: LumenMetrics) {
        series = LumenToken.Chart.series.map { palette[$0] }
        grid = palette[LumenToken.Chart.grid]
        axis = palette[LumenToken.Chart.axis]
        label = palette[LumenToken.Chart.label]
        canvas = palette[.bgCanvas]
        axisLabelFont = metrics.typography.caption
        gridStroke = StrokeStyle(lineWidth: metrics.stroke.hairline)
        axisStroke = StrokeStyle(lineWidth: metrics.stroke.regular)
    }
}

public extension EnvironmentValues {
    /// Always follows this subtree's active palette and metrics, including theme changes.
    var lumenChartStyle: LumenChartStyle { LumenChartStyle(palette: lumenPalette, metrics: lumenMetrics) }
}

public extension View {
    /// Apply the chart pack to any Swift Chart. Pass series names in assignment order when
    /// using `foregroundStyle(by:)`. Swift Charts remains available for custom marks and scales.
    func lumenChartStyle(series: [String] = []) -> some View {
        modifier(LumenChartStyleModifier(series: series))
    }
}

private struct LumenChartStyleModifier: ViewModifier {
    let series: [String]
    @Environment(\.lumenChartStyle) private var style

    @ViewBuilder private func scaled(_ content: Content) -> some View {
        if series.isEmpty {
            content.chartForegroundStyleScale(range: style.series)
        } else {
            content.chartForegroundStyleScale(domain: series, range: series.indices.map { style.series[$0 % style.series.count] })
        }
    }

    func body(content: Content) -> some View {
        scaled(content)
            .foregroundStyle(style.series[0])
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: style.gridStroke).foregroundStyle(style.grid)
                    AxisTick(stroke: style.axisStroke).foregroundStyle(style.axis)
                    AxisValueLabel().font(style.axisLabelFont).foregroundStyle(style.label)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: style.gridStroke).foregroundStyle(style.grid)
                    AxisTick(stroke: style.axisStroke).foregroundStyle(style.axis)
                    AxisValueLabel().font(style.axisLabelFont).foregroundStyle(style.label)
                }
            }
            .background(style.canvas)
    }
}

/// Shared decisions used by every chart, including the empty and legend branches.
struct LumenChartPresentation {
    let data: [LumenChartDatum]
    let series: [String]
    let seriesLabels: [String]
    var isEmpty: Bool { data.isEmpty }
    var showsLegend: Bool { series.count > 1 }

    init(_ values: [LumenChartDatum]) {
        data = values.filter { $0.value.isFinite }
        var seen: Set<String> = []
        let first = data.filter { seen.insert($0.seriesKey).inserted }
        series = first.map(\.seriesKey)
        seriesLabels = first.map { $0.series ?? "Value" }
    }
}

private struct LumenChartFrame<Plot: View>: View {
    let isEmpty: Bool
    let series: [String]
    let seriesLabels: [String]
    let plot: Plot
    @Environment(\.lumenChartStyle) private var style
    @Environment(\.lumenMetrics) private var metrics

    init(_ presentation: LumenChartPresentation, @ViewBuilder plot: () -> Plot) {
        isEmpty = presentation.isEmpty
        series = presentation.series
        seriesLabels = presentation.seriesLabels
        self.plot = plot()
    }

    init(isEmpty: Bool, @ViewBuilder plot: () -> Plot) {
        self.isEmpty = isEmpty
        series = []
        seriesLabels = []
        self.plot = plot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s3) {
            if isEmpty {
                LumenEmptyState("No chart data", message: "Add observations to see this chart.", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                plot.lumenChartStyle(series: series).chartLegend(.hidden)
                if series.count > 1 {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: metrics.spacing.s4) { legendEntries }
                        VStack(alignment: .leading, spacing: metrics.spacing.s2) { legendEntries }
                    }
                }
            }
        }
        .background(style.canvas)
    }

    private var legendEntries: some View {
        ForEach(series.enumerated(), id: \.element) { index, _ in
            HStack(spacing: metrics.spacing.s2) {
                LumenSwatchStrip([style.series[index % style.series.count]])
                Text(seriesLabels[index])
                    .font(style.axisLabelFont).foregroundStyle(style.label)
                    .lumenWrapsWithoutTruncating()
            }
        }
    }
}

/// Grouped bars with category labels in input order. Nonfinite values are omitted.
public struct LumenBarChart: View {
    private let presentation: LumenChartPresentation

    public init(_ data: [LumenChartDatum]) { presentation = LumenChartPresentation(data) }

    public var body: some View {
        LumenChartFrame(presentation) {
            Chart(presentation.data) { datum in
                BarMark(x: .value("Label", datum.label), y: .value("Value", datum.value))
                    .foregroundStyle(by: .value("Series", datum.seriesKey))
                    .position(by: .value("Series", datum.seriesKey))
            }
            .lumenNumericText(value: presentation.data)
        }
    }
}

/// Lines connecting category labels in input order, with points so a lone observation is visible.
/// Use Swift Charts directly for continuous dates, numeric x axes, or other interpolation.
public struct LumenLineChart: View {
    private let presentation: LumenChartPresentation

    public init(_ data: [LumenChartDatum]) { presentation = LumenChartPresentation(data) }

    public var body: some View {
        LumenChartFrame(presentation) {
            Chart(presentation.data) { datum in
                LineMark(x: .value("Label", datum.label), y: .value("Value", datum.value))
                    .foregroundStyle(by: .value("Series", datum.seriesKey))
                PointMark(x: .value("Label", datum.label), y: .value("Value", datum.value))
                    .foregroundStyle(by: .value("Series", datum.seriesKey))
            }
            .lumenNumericText(value: presentation.data)
        }
    }
}

/// A single-series histogram of raw observations, binned and counted by Lumen.
/// Already-binned counts belong in `LumenBarChart`, with a label for each bin.
/// Nonfinite values are dropped; empty or all-nonfinite input shows `LumenEmptyState`.
public struct LumenHistogram: View {
    private let presentation: LumenHistogramPresentation

    /// Omit `binCount` for Swift Charts' automatic `NumberBins` choice. A positive count
    /// creates that many equal-width bins over the observed range. Nonpositive counts use one.
    /// Constant observations get a padded range (one bin by default) so their bar has visible width.
    public init(values: [Double], binCount: Int? = nil) {
        presentation = LumenHistogramPresentation(values: values, binCount: binCount)
    }

    public var body: some View {
        LumenChartFrame(isEmpty: presentation.isEmpty) {
            Chart(presentation.bins) { bin in
                BarMark(x: .value("Value", bin.range), y: .value("Count", bin.count))
            }
            .lumenNumericText(value: presentation.bins.map(\.count))
        }
    }
}

struct LumenHistogramPresentation {
    struct Bin: Identifiable {
        let range: ChartBinRange<Double>
        let count: Int
        var id: Double { range.lowerBound }
    }

    let bins: [Bin]
    var isEmpty: Bool { bins.isEmpty }

    init(values: [Double], binCount: Int? = nil) {
        let finite = values.filter(\.isFinite)
        guard let minimum = finite.min(), let maximum = finite.max() else {
            bins = []
            return
        }
        let ranges: NumberBins<Double>
        if minimum == maximum {
            // NumberBins(data:) can return no bins for a constant sample. Supply a nonzero
            // range before counting; relative padding also stays visible at large magnitudes.
            let padding = max(0.5, abs(minimum) * 0.05)
            let lower = max(-Double.greatestFiniteMagnitude, minimum - padding)
            let upper = min(Double.greatestFiniteMagnitude, maximum + padding)
            ranges = NumberBins(range: lower...upper, count: max(1, binCount ?? 1))
        } else if let binCount {
            ranges = NumberBins(range: minimum...maximum, count: max(1, binCount))
        } else {
            ranges = NumberBins(data: finite)
        }
        var counts = [Int](repeating: 0, count: ranges.count)
        for value in finite {
            // index(for:) returns endIndex at the final threshold, although the last
            // ChartBinRange includes that endpoint. Count it in the final bin.
            let index = min(ranges.index(for: value), ranges.endIndex - 1)
            counts[index] += 1
        }
        bins = ranges.indices.map { Bin(range: ranges[$0], count: counts[$0]) }
    }
}
