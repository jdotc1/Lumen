import LumenTokens
import SwiftUI

/// Metric controls use the same session as color wells, including pack locks and undo.
struct LumenThemeMetricControls: View {
    let session: LumenThemeEditorSession
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.s7) {
                Text("Unspecified metrics inherit from the parent theme, then the app. Reset removes your override.")
                    .font(metrics.typography.caption)
                    .foregroundStyle(palette[.fgSecondary])
                    .lumenWrapsWithoutTruncating()
                LumenThemeMetricRow(title: "Radius profile", key: .radiusProfile, session: session) {
                    LumenMenuButton {
                        Button("Standard") { session.setRadiusProfile(.standard) }
                        Button("Rounded") { session.setRadiusProfile(.rounded) }
                        Button("Uniform") { session.setRadiusProfile(.uniform(6)) }
                    } label: { LumenPopUpLabel(radiusTitle) }
                    if case .uniform(let radius)? = session.draft.metrics?.radiusProfile {
                        LumenSlider(value: Binding(get: { radius }, set: { session.setRadiusProfile(.uniform($0)) }),
                                    in: 0...12, step: 0.5, showsField: true, unit: "pt", width: 160)
                    }
                }
                LumenThemeMetricRow(title: "Type scale", key: .typeScale, session: session) {
                    LumenSlider(value: Binding(get: { session.draft.metrics?.typeScale ?? 1 }, set: { session.setTypeScale($0) }),
                                in: 0.9...1.3, step: 0.01, showsField: true, unit: "×", width: 160)
                    Text("0.90–1.30 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])
                }
                LumenThemeMetricRow(title: "Spacing scale", key: .spacingScale, session: session) {
                    LumenSlider(value: Binding(get: { session.draft.metrics?.spacingScale ?? 1 }, set: { session.setSpacingScale($0) }),
                                in: 1...1.25, step: 0.01, showsField: true, unit: "×", width: 160)
                    Text("1.00–1.25 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])
                }
                LumenThemeMetricRow(title: "Motion", key: .motion, session: session) {
                    LumenMenuButton {
                        ForEach(LumenThemeMetrics.Motion.allCases, id: \.self) { motion in
                            Button(motion.rawValue.capitalized) { session.setMotion(motion) }
                        }
                    } label: { LumenPopUpLabel(session.draft.metrics?.motion?.rawValue.capitalized ?? "App default") }
                }
            }
            .padding(metrics.spacing.s5)
            .lumenColumnContent("theme editor metrics")
        }
    }

    private var radiusTitle: String {
        switch session.draft.metrics?.radiusProfile {
        case .standard?: "Standard"
        case .rounded?: "Rounded"
        case .uniform?: "Uniform"
        case nil: "App default"
        }
    }
}

private struct LumenThemeMetricRow<Content: View>: View {
    let title: String
    let key: LumenThemeMetrics.Key
    let session: LumenThemeEditorSession
    @ViewBuilder let content: Content
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s3) {
            HStack {
                Text(title).font(metrics.typography.bodyEmphasized)
                Spacer()
                if session.isMetricLocked(key) {
                    Label("Locked", systemImage: "lock.fill")
                        .font(metrics.typography.caption)
                        .foregroundStyle(palette[.fgTertiary])
                } else {
                    Text(session.isMetricOverridden(key) ? "Override" : "Inherited")
                        .font(metrics.typography.caption)
                        .foregroundStyle(palette[.fgTertiary])
                    Button("Reset") { session.resetMetric(key) }
                        .disabled(!session.isMetricOverridden(key))
                        .font(metrics.typography.caption)
                }
            }
            content.disabled(session.isMetricLocked(key))
        }
    }
}
