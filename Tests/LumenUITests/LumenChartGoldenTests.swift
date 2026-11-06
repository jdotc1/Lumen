import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Charts across the six gallery variants. Recording failures require
/// image review; do not repeat unchanged verification merely to turn that run green.
@MainActor final class LumenChartGoldenTests: XCTestCase {
    func testCharts() {
        let registry = LumenRegistry(packs: [.core, .chart])
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
        let variants = LumenSnapshot.Variant.all(for: registry.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        for variant in variants {
            let outcome = LumenSnapshot.verify(ChartsSubject(), named: "charts",
                size: CGSize(width: 900, height: 850), variant: variant, registry: registry,
                goldenDirectory: directory, renderer: .image)
            if let message = outcome.failureMessage { XCTFail("\(variant.label): \(message)") }
        }
    }
}

private struct ChartsSubject: View {
    @Environment(\.lumenMetrics) private var metrics
    private static let data: [LumenChartDatum] = (1...8).flatMap { series in
        ["Apr", "May", "Jun"].enumerated().map { index, label in
            LumenChartDatum(label: label, value: Double(series * 4 + [0, 3, 1][index]), series: "Series \(series)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            Text("Bars · eight series").font(metrics.typography.headline)
            LumenBarChart(Self.data).frame(height: 220)
            Text("Lines · eight series").font(metrics.typography.headline)
            LumenLineChart(Self.data).frame(height: 220)
            Text("Histogram · raw observations").font(metrics.typography.headline)
            LumenHistogram(values: [0, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8], binCount: 4)
                .frame(height: 220)
        }
        .padding(24)
    }
}
