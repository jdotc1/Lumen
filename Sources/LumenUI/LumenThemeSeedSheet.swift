import LumenTokens
import SwiftUI

/// The sheet gathers inputs; the token library owns all derivation and repair decisions.
struct LumenThemeSeedSheet: View {
    let store: LumenThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @State private var hue = 260.0
    @State private var ground = LumenSeedGround.paperGraphite
    @State private var name = lumenLocalized(String(localized: "My Violet Theme", bundle: .module, comment: "ThemeSeedSheet display text."))
    @State private var generated: LumenTheme?
    @State private var isGenerating = false
    @State private var isApplied = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s5) {
            Text(lumenLocalized(String(localized: "New from seed", bundle: .module, comment: "ThemeSeedSheet control text."))).font(metrics.typography.headline)
            Text(lumenLocalized(String(localized: "Choose an accent and paired light / dark grounds. Lumen derives every core color, repairs supported findings, then checks all four appearances.", bundle: .module, comment: "ThemeSeedSheet control text.")))
                .font(metrics.typography.callout)
                .foregroundStyle(palette[.fgSecondary])
                .lumenWrapsWithoutTruncating()
            TextField(lumenLocalized(String(localized: "Theme name", bundle: .module, comment: "ThemeSeedSheet control text.")), text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Text(lumenLocalized(String(localized: "Accent hue", bundle: .module, comment: "ThemeSeedSheet control text."))).font(metrics.typography.body)
                Spacer()
                LumenSlider(value: $hue, in: 0...360, step: 1, showsField: true, unit: "°", width: 180)
            }
            HStack {
                Text(lumenLocalized(String(localized: "Grounds", bundle: .module, comment: "ThemeSeedSheet control text."))).font(metrics.typography.body)
                Spacer()
                LumenMenuButton {
                    ForEach(LumenSeedGround.allCases, id: \.self) { option in
                        Button(option.name) { ground = option }
                    }
                } label: { LumenPopUpLabel(ground.name) }
            }
            Text(ground.summary).font(metrics.typography.caption).foregroundStyle(palette[.fgSecondary])
                .lumenWrapsWithoutTruncating()
            if let generated {
                // Show accent roles here; the gallery still previews the host's syntax colors.
                HStack(spacing: metrics.spacing.s5) {
                    LumenThemeMiniature(theme: generated, registry: .core, appearance: .light)
                    LumenThemeMiniature(theme: generated, registry: .core, appearance: .dark)
                }
                Text(isApplied ? lumenLocalized(String(localized: "Saved and applied · all four appearances pass", bundle: .module, comment: "ThemeSeedSheet display text.")) : lumenLocalized(String(localized: "Ready · all four appearances pass", bundle: .module, comment: "ThemeSeedSheet display text.")))
                    .font(metrics.typography.callout)
                    .foregroundStyle(palette[.statusSuccess])
            } else if isGenerating {
                ProgressView(lumenLocalized(String(localized: "Deriving and checking theme…", bundle: .module, comment: "ThemeSeedSheet control text.")))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Text(lumenLocalized(String(localized: "Violet is the starting accent. Generate to preview your light and dark palettes.", bundle: .module, comment: "ThemeSeedSheet control text.")))
                    .font(metrics.typography.callout)
                    .foregroundStyle(palette[.fgTertiary])
                    .lumenWrapsWithoutTruncating()
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
            if let problem {
                ScrollView {
                    Text(problem).font(metrics.typography.caption).foregroundStyle(palette[.statusDanger])
                        .lumenWrapsWithoutTruncating()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
            HStack {
                Button(isApplied ? lumenLocalized(String(localized: "Close", bundle: .module, comment: "ThemeSeedSheet display text.")) : lumenLocalized(String(localized: "Cancel", bundle: .module, comment: "ThemeSeedSheet display text.")), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(lumenLocalized(String(localized: "Generate", bundle: .module, comment: "ThemeSeedSheet control text."))) { generate() }.disabled(isGenerating)
                Button(lumenLocalized(String(localized: "Save and Apply", bundle: .module, comment: "ThemeSeedSheet control text."))) { apply() }
                    .disabled(generated == nil || isApplied || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(metrics.spacing.s6)
        .frame(minWidth: 580, idealWidth: 620)
        .lumenColumnContent("theme seed sheet")
        .onChange(of: hue) { invalidate() }
        .onChange(of: ground) { invalidate() }
    }

    private func invalidate() {
        generated = nil
        isApplied = false
        problem = nil
    }

    private func generate() {
        let hue = hue, ground = ground, registry = store.registry
        isGenerating = true
        problem = nil
        generated = nil
        isApplied = false
        Task {
            do {
                let result = try await Task.detached {
                    let theme = try LumenTheme.seeded(accentHue: hue, ground: ground, in: registry)
                    let issues = LumenValidator.issues(for: theme, in: registry)
                    guard issues.isEmpty else {
                        throw SeedProblem(message: lumenLocalized(String(localized: "This app’s packs need additional changes: %@", defaultValue: "This app’s packs need additional changes: \(issues.map(\.message).joined(separator: "; "))", bundle: .module, comment: "Theme generation failure with validation details.")))
                    }
                    return theme
                }.value
                if self.hue == hue && self.ground == ground { generated = result }
            } catch {
                if self.hue == hue && self.ground == ground { problem = error.localizedDescription }
            }
            isGenerating = false
        }
    }

    private func apply() {
        guard let generated else { return }
        do {
            try store.saveUserTheme(name: name, inheriting: generated, overrides: [:], highContrastOverrides: [:], metrics: nil)
            isApplied = true
        } catch { problem = error.localizedDescription }
    }

    private struct SeedProblem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
