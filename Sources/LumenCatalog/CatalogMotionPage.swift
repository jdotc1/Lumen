import SwiftUI
import LumenTokens
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
            CatalogMotionPreferenceControl()
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

/// The Catalog's own motion preference: on (the theme's motion), reduced, or off. It applies to every
/// Catalog page through `catalogMotionPreference()`, so a background AX client can set it without
/// opening the theme editor's pop-up.
enum CatalogMotionPreference: String, CaseIterable, Hashable {
    case on, reduced, off

    static let storageKey = "catalog.motionPreference"

    var title: String {
        switch self {
        case .on: "On"
        case .reduced: "Reduced"
        case .off: "Off"
        }
    }

    /// `nil` keeps the theme's own motion.
    var themeMotion: LumenThemeMetrics.Motion? {
        switch self {
        case .on: nil
        case .reduced: .reduced
        case .off: LumenThemeMetrics.Motion.none
        }
    }

    /// Motion as this preference leaves it, starting from the metrics the page would otherwise use.
    func applying(to metrics: LumenMetrics) -> LumenMetrics {
        guard let themeMotion else { return metrics }
        var result = metrics
        result.motion = LumenMetrics.resolving(LumenThemeMetrics(motion: themeMotion)).motion
        return result
    }
}

private struct CatalogMotionPreferenceModifier: ViewModifier {
    @AppStorage(CatalogMotionPreference.storageKey) private var raw = CatalogMotionPreference.on.rawValue
    @Environment(\.lumenMetrics) private var metrics

    func body(content: Content) -> some View {
        let preference = CatalogMotionPreference(rawValue: raw) ?? .on
        content.lumenMetrics(preference.applying(to: metrics))
    }
}

extension View {
    func catalogMotionPreference() -> some View { modifier(CatalogMotionPreferenceModifier()) }
}

private struct CatalogMotionPreferenceControl: View {
    @AppStorage(CatalogMotionPreference.storageKey) private var raw = CatalogMotionPreference.on.rawValue

    var body: some View {
        let selection = Binding(get: { CatalogMotionPreference(rawValue: raw) ?? .on }, set: { raw = $0.rawValue })
        VStack(alignment: .leading, spacing: 6) {
            Text("Motion preference").font(.headline)
            LumenSegmentedControl(selection: selection, options: CatalogMotionPreference.allCases,
                                  title: { $0.title })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("catalog.motion.preference")
                .accessibilityLabel("Motion preference")
            HStack(spacing: 8) {
                ForEach(CatalogMotionPreference.allCases, id: \.self) { option in
                    Button(option.title) { raw = option.rawValue }
                        .accessibilityIdentifier("catalog.motion.preference.\(option.rawValue)")
                        .accessibilityLabel("Set motion \(option.title)")
                        .accessibilityValue(selection.wrappedValue == option ? "selected" : "not selected")
                }
            }
        }
    }
}
