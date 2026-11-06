import SwiftUI
import LumenUI

/// Static on arrival; each motion starts explicitly.
struct MotionPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Motion", summary: "Named transitions for panels, selections and small state changes. Trigger each sample to review its timing.")
            Text("Reduce Motion: \(reduceMotion ? "On — changes happen immediately" : "Off")")
                .font(.headline)
            Text("Theme motion: \(metrics.motion.isEnabled ? "Enabled" : "Disabled")")
                .font(.caption)
            ForEach(LumenMotion.Transition.allCases, id: \.rawValue) { transition in
                MotionSampleRow(transition: transition)
            }
            MotionContentSamples()
        }
    }
}

private struct MotionSampleRow: View {
    let transition: LumenMotion.Transition
    @State private var active = false
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transition.rawValue).font(.headline)
                Spacer(minLength: 8)
                Text("\(transition.duration(in: metrics.motion), specifier: "%.2f") s")
                    .font(.caption.monospacedDigit())
                Button(active ? "Reset" : "Trigger") { active.toggle() }
            }
            MotionSample(transition: transition, active: active)
                .frame(height: 32)
                .clipped()
            Divider()
        }
    }
}

private struct MotionSample: View {
    let transition: LumenMotion.Transition
    let active: Bool

    var body: some View {
        if transition == .loading {
            // The component owns its repeating transaction; removing it stops the sample.
            if active { LumenProgressBar(nil).frame(height: 4) }
        } else if transition == .selection || transition == .scroll || transition == .reorder {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tint)
                    .frame(width: 28, height: 24)
                    .offset(x: active ? 80 : 0)
                Spacer(minLength: 0)
            }
            .lumenAnimation(transition, value: active)
        } else {
            ZStack(alignment: .leading) {
                Color.clear
                if active {
                    Text("Sample")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: .rect(cornerRadius: 6))
                        .lumenTransition(transition)
                }
            }
            .lumenAnimation(transition, value: active)
        }
    }
}

private struct MotionContentSamples: View {
    @State private var count = 12
    @State private var succeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Counts and status glyphs").font(.headline)
            HStack(spacing: 16) {
                Text(count, format: .number)
                    .monospacedDigit()
                    .lumenNumericText(value: count)
                Button("Increment") { count += 1 }
                LumenSymbol(succeeded ? "checkmark.circle.fill" : "circle")
                    .lumenStatusSymbol(value: succeeded)
                Button("Change Status") { succeeded.toggle() }
            }
        }
    }
}
