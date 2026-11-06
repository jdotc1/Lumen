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
                Text(lumenLocalized(String(localized: "Unspecified metrics inherit from the parent theme, then the app. Reset removes your override.", bundle: .module, comment: "ThemeMetricControls control text.")))
                    .font(metrics.typography.caption)
                    .foregroundStyle(palette[.fgSecondary])
                    .lumenWrapsWithoutTruncating()
                LumenThemeMetricRow(title: lumenLocalized(String(localized: "Radius profile", bundle: .module, comment: "ThemeMetricControls display text.")), key: .radiusProfile, session: session) {
                    LumenMenuButton {
                        Button(lumenLocalized(String(localized: "Standard", bundle: .module, comment: "ThemeMetricControls control text."))) { session.setRadiusProfile(.standard) }
                        Button(lumenLocalized(String(localized: "Rounded", bundle: .module, comment: "ThemeMetricControls control text."))) { session.setRadiusProfile(.rounded) }
                        Button(lumenLocalized(String(localized: "Uniform", bundle: .module, comment: "ThemeMetricControls control text."))) { session.setRadiusProfile(.uniform(6)) }
                    } label: { LumenPopUpLabel(radiusTitle) }
                    if case .uniform(let radius)? = session.draft.metrics?.radiusProfile {
                        LumenSlider(value: Binding(get: { radius }, set: { session.setRadiusProfile(.uniform($0)) }),
                                    in: 0...12, step: 0.5, showsField: true, unit: lumenLocalized(String(localized: "pt", bundle: .module, comment: "ThemeMetricControls display text.")), width: 160)
                    }
                }
                LumenThemeMetricRow(title: lumenLocalized(String(localized: "Type scale", bundle: .module, comment: "ThemeMetricControls display text.")), key: .typeScale, session: session) {
                    LumenSlider(value: Binding(get: { session.draft.metrics?.typeScale ?? 1 }, set: { session.setTypeScale($0) }),
                                in: 0.9...1.3, step: 0.01, showsField: true, unit: "×", width: 160)
                    Text("0.90–1.30 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])
                }
                LumenThemeMetricRow(title: lumenLocalized(String(localized: "Spacing scale", bundle: .module, comment: "ThemeMetricControls display text.")), key: .spacingScale, session: session) {
                    LumenSlider(value: Binding(get: { session.draft.metrics?.spacingScale ?? 1 }, set: { session.setSpacingScale($0) }),
                                in: 1...1.25, step: 0.01, showsField: true, unit: "×", width: 160)
                    Text("1.00–1.25 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])
                }
                LumenThemeMetricRow(title: lumenLocalized(String(localized: "Motion", bundle: .module, comment: "ThemeMetricControls display text.")), key: .motion, session: session) {
                    LumenMenuButton {
                        ForEach(LumenThemeMetrics.Motion.allCases, id: \.self) { motion in
                            Button(motionTitle(motion)) { session.setMotion(motion) }
                        }
                    } label: { LumenPopUpLabel(session.draft.metrics?.motion.map(motionTitle) ?? lumenLocalized(String(localized: "App default", bundle: .module, comment: "ThemeMetricControls display text."))) }
                }
            }
            .padding(metrics.spacing.s5)
            .lumenColumnContent("theme editor metrics")
        }
    }

    private func motionTitle(_ motion: LumenThemeMetrics.Motion) -> String {
        switch motion {
        case .standard: lumenLocalized(String(localized: "Standard", bundle: .module, comment: "Theme motion setting."))
        case .reduced: lumenLocalized(String(localized: "Reduced", bundle: .module, comment: "Theme motion setting."))
        case .none: lumenLocalized(String(localized: "None", bundle: .module, comment: "Theme motion setting."))
        }
    }

    private var radiusTitle: String {
        switch session.draft.metrics?.radiusProfile {
        case .standard?: lumenLocalized(String(localized: "Standard", bundle: .module, comment: "ThemeMetricControls display text."))
        case .rounded?: lumenLocalized(String(localized: "Rounded", bundle: .module, comment: "ThemeMetricControls display text."))
        case .uniform?: lumenLocalized(String(localized: "Uniform", bundle: .module, comment: "ThemeMetricControls display text."))
        case nil: lumenLocalized(String(localized: "App default", bundle: .module, comment: "ThemeMetricControls display text."))
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
                    Label(lumenLocalized(String(localized: "Locked", bundle: .module, comment: "ThemeMetricControls control text.")), systemImage: "lock.fill")
                        .font(metrics.typography.caption)
                        .foregroundStyle(palette[.fgTertiary])
                } else {
                    Text(session.isMetricOverridden(key) ? lumenLocalized(String(localized: "Override", bundle: .module, comment: "ThemeMetricControls display text.")) : lumenLocalized(String(localized: "Inherited", bundle: .module, comment: "ThemeMetricControls display text.")))
                        .font(metrics.typography.caption)
                        .foregroundStyle(palette[.fgTertiary])
                    Button(lumenLocalized(String(localized: "Reset", bundle: .module, comment: "ThemeMetricControls control text."))) { session.resetMetric(key) }
                        .disabled(!session.isMetricOverridden(key))
                        .font(metrics.typography.caption)
                }
            }
            content.disabled(session.isMetricLocked(key))
        }
    }
}
