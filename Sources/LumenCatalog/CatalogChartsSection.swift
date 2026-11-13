import SwiftUI
import LumenUI

/// Chart examples live at the top of the existing Data page.
struct CatalogChartsSection: View {
    @Environment(\.lumenMetrics) private var metrics
    /// Fixed ids keep each bar and point the same mark across "Randomize data", so values animate.
    @State private var observations = CatalogChartsSection.seed
    @State private var histogramValues: [Double] = CatalogChartsSection.seedHistogram
    private static let seedHistogram: [Double] = [2, 3, 3, 4, 4, 4, 5, 5, 6, 7, 8, 10]
    private static let seed = [
        LumenChartDatum(label: "Apr", value: 12, series: "Current"),
        LumenChartDatum(label: "May", value: 18, series: "Current"),
        LumenChartDatum(label: "Jun", value: 15, series: "Current"),
        LumenChartDatum(label: "Apr", value: 9, series: "Previous"),
        LumenChartDatum(label: "May", value: 14, series: "Previous"),
        LumenChartDatum(label: "Jun", value: 11, series: "Previous"),
        LumenChartDatum(label: "Apr", value: 7, series: "Baseline"),
        LumenChartDatum(label: "May", value: 10, series: "Baseline"),
        LumenChartDatum(label: "Jun", value: 8, series: "Baseline"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            LumenSectionHeader("Data & Charts")
            Text("Charts follow the active theme’s chart pack. Bars and lines compare three series; the histogram bins raw observations. Each matching empty chart uses the shared empty state.")
                .font(metrics.typography.caption).foregroundStyle(.lumen(.fgSecondary))
                .lumenWrapsWithoutTruncating()
            Button("Randomize data") { randomize() }
                .accessibilityIdentifier("catalog.charts.randomize")
                .accessibilityLabel("Randomize data")
                .accessibilityHint("Replaces the chart values so the charts animate.")
            row("Bars") {
                LumenBarChart(observations)
            } empty: {
                LumenBarChart([])
            }
            row("Histogram") {
                LumenHistogram(values: histogramValues, binCount: 4)
            } empty: {
                LumenHistogram(values: [])
            }
            row("Lines") {
                LumenLineChart(observations)
            } empty: {
                LumenLineChart([])
            }
        }
    }

    /// New values for the same marks; every bar and point always changes.
    func randomize() {
        withAnimation {
            observations = observations.map { datum in
                var next = datum
                repeat { next.value = Double(Int.random(in: 3...20)) } while next.value == datum.value
                return next
            }
            histogramValues = (0..<12).map { _ in Double(Int.random(in: 1...12)) }
        }
    }

    private func row(_ title: String, @ViewBuilder populated: () -> some View,
                     @ViewBuilder empty: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s2) {
            Text(title).font(metrics.typography.headline)
            HStack(alignment: .top, spacing: metrics.spacing.s4) {
                populated().frame(maxWidth: .infinity).frame(height: 170)
                empty().frame(width: 200, height: 170)
            }
        }
    }
}
