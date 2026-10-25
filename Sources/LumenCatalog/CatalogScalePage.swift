import SwiftUI
import LumenUI

struct ScalePage: View {
    @State private var selected = LumenScaleComponent.hex
    @State private var sample: LumenScaleSample?
    @State private var records: [LumenScaleComponent: LumenScaleTimingRecord] = [:]
    @State private var measuring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Scale", summary: "Build one data-heavy component at a time at 10× its reference size. No workload is built until requested.")
            Text("First layout includes three layout/display passes in an unshown 700 × 800 host. Data preparation is excluded. Reference budgets below are for their original sizes and operations; these timings are observations, not pass/fail gates.")
                .font(.caption).lumenWrapsWithoutTruncating()
            Picker("Component", selection: $selected) {
                ForEach(LumenScaleComponent.allCases) { component in
                    Text(component.title).tag(component)
                }
            }
            Button(measuring ? "Measuring…" : "Build and Measure") { measureSelected() }
                .disabled(measuring)
            ScaleResults(records: records)
            if let sample {
                Text("\(sample.record.component.title) — measured instance (preview may resize)")
                ScalePreview(sample: sample).id(sample.id).frame(height: 800)
                Button("Unload Component") { self.sample = nil }
            }
        }
    }

    private func measureSelected() {
        let component = selected
        measuring = true
        sample = nil
        Task { @MainActor in
            // Release the previous preview and let the busy state render before synchronous layout.
            await Task.yield()
            let measured = LumenScaleTiming.measure(component)
            records[component] = measured.record
            sample = measured
            measuring = false
        }
    }
}

private struct ScaleResults: View {
    let records: [LumenScaleComponent: LumenScaleTimingRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(LumenScaleComponent.allCases) { component in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(component.title): \(component.size) \(component.unit)").font(.headline)
                    if let record = records[component] {
                        Text("First layout: \(record.firstLayoutMilliseconds, specifier: "%.2f") ms")
                    } else {
                        Text("Not measured")
                    }
                    Text(component.budgetDescription).font(.caption)
                }
            }
        }
        .lumenWrapsWithoutTruncating()
    }
}

private struct ScalePreview: NSViewRepresentable {
    let sample: LumenScaleSample
    func makeNSView(context: Context) -> NSHostingView<AnyView> { sample.host }
    func updateNSView(_ nsView: NSHostingView<AnyView>, context: Context) {}
}
