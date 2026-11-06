import SwiftUI
import LumenUI

/// Chart examples live at the top of the existing Data page.
struct CatalogChartsSection: View {
    @Environment(\.lumenMetrics) private var metrics
    private static let observations = [
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
            row("Bars") {
                LumenBarChart(Self.observations)
            } empty: {
                LumenBarChart([])
            }
            row("Histogram") {
                LumenHistogram(values: [2, 3, 3, 4, 4, 4, 5, 5, 6, 7, 8, 10], binCount: 4)
            } empty: {
                LumenHistogram(values: [])
            }
            row("Lines") {
                LumenLineChart(Self.observations)
            } empty: {
                LumenLineChart([])
            }
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
