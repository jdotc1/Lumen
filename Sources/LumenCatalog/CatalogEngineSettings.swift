import SwiftUI
import UniformTypeIdentifiers
import LumenTokens
import LumenUI

/// A runtime pane built from the public adaptive settings rows and grouped controls.
struct CatalogEngineSettings: View {
    @State private var usesExternalEngine = false
    @State private var enginePath = ""
    @State private var status = "Ready to use."
    @State private var choosesEngine = false
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        LumenSettingsPane("Engine", systemImage: "cpu", hue: .hueViolet,
                          summary: "Choose the engine used for local analysis.", style: .rich) {
            LumenSettingsGroup {
                LumenFormSection("Analysis engine") {
                    LumenSettingsRow("Bundled runtime", description: status) {
                        Button("Check") { status = "Bundled runtime is available." }
                            .modifier(CatalogEngineControlMeasure(name: "Check"))
                    }
                    LumenSettingsRow("Use external engine", description: "Run analysis with a runtime you select.") {
                        Toggle("Use external engine", isOn: $usesExternalEngine)
                            .toggleStyle(.switch)
                            .modifier(CatalogEngineControlMeasure(name: "Toggle"))
                    }
                    VStack(alignment: .leading, spacing: metrics.spacing.s4) {
                        Text("Runtime executable")
                            .font(metrics.typography.body.weight(.medium))
                        LumenTextField("Bundled runtime", text: $enginePath, monospaced: true)
                        HStack(spacing: metrics.spacing.s4) {
                            Spacer(minLength: metrics.spacing.s0)
                            Button("Choose…") { choosesEngine = true }
                            Button("Reset") { enginePath = "" }
                                .modifier(CatalogEngineControlMeasure(name: "Reset"))
                        }
                    }
                    .disabled(!usesExternalEngine)
                    Text("The bundled runtime works offline. An external runtime is used only when enabled and an executable is selected.")
                        .font(metrics.typography.caption)
                        .foregroundStyle(.lumen(.fgTertiary))
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Engine details") {
                        LumenSettingsRow("Processing", description: "Analysis runs on this Mac.") {
                            Text("Local")
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $choosesEngine, allowedContentTypes: [.executable]) { result in
            if case .success(let url) = result {
                enginePath = url.path
            }
        }
    }
}

struct CatalogReportSettings: View {
    @State private var includesSummary = true
    @State private var includesDiagnostics = false

    var body: some View {
        LumenSettingsPane("Reports", systemImage: "doc.text", hue: .hueBlue,
                          summary: "Choose what to include in exported reports.", style: .rich) {
            LumenFormSection("Report contents") {
                LumenSettingsRow("Include summary", description: "Begin with the analysis findings.") {
                    Toggle("Include summary", isOn: $includesSummary).toggleStyle(.switch)
                }
                LumenSettingsRow("Include diagnostics", description: "Append engine details to the report.") {
                    Toggle("Include diagnostics", isOn: $includesDiagnostics).toggleStyle(.switch)
                }
            }
        }
    }
}

/// Enough independent settings to demonstrate the screen-height cap and the scroll bottom inset.
struct CatalogAutomationSettings: View {
    @State private var enabledRules: Set<String> = ["validate-input", "save-summary", "completion"]

    var body: some View {
        LumenSettingsPane("Automation", systemImage: "gearshape.2", hue: .hueTeal,
                          summary: "Choose the steps performed before, during and after local analysis.", style: .rich) {
            ForEach(CatalogAutomationSection.samples) { section in
                LumenFormSection(section.title) {
                    ForEach(section.rules) { rule in
                        LumenSettingsRow(rule.title, description: rule.summary) {
                            Toggle(rule.title, isOn: Binding(
                                get: { enabledRules.contains(rule.id) },
                                set: { enabled in
                                    if enabled { enabledRules.insert(rule.id) }
                                    else { enabledRules.remove(rule.id) }
                                }))
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
        }
    }
}

private struct CatalogAutomationRule: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
}

private struct CatalogAutomationSection: Identifiable, Sendable {
    let id: String
    let title: String
    let rules: [CatalogAutomationRule]

    static let samples: [Self] = [
        Self(id: "prepare", title: "Before analysis", rules: [
            .init(id: "validate-input", title: "Validate input", summary: "Check that the selected files can be read."),
            .init(id: "check-runtime", title: "Check runtime", summary: "Confirm the selected runtime is available."),
            .init(id: "restore-options", title: "Restore options", summary: "Use the options from the previous analysis."),
            .init(id: "collect-metadata", title: "Collect metadata", summary: "Include local file details in the working record."),
            .init(id: "estimate-size", title: "Estimate output size", summary: "Show the expected space needed for results.")
        ]),
        Self(id: "process", title: "During analysis", rules: [
            .init(id: "show-progress", title: "Show progress", summary: "Keep a progress indicator in the workspace."),
            .init(id: "save-checkpoints", title: "Save checkpoints", summary: "Retain intermediate work for later continuation."),
            .init(id: "collect-diagnostics", title: "Collect diagnostics", summary: "Record runtime messages with the analysis."),
            .init(id: "pause-on-battery", title: "Pause on battery", summary: "Continue longer tasks when power is connected."),
            .init(id: "queue-files", title: "Queue new files", summary: "Add newly selected files to the current queue.")
        ]),
        Self(id: "complete", title: "After analysis", rules: [
            .init(id: "save-summary", title: "Save summary", summary: "Write a short summary beside the results."),
            .init(id: "open-report", title: "Open report", summary: "Display the report when analysis completes."),
            .init(id: "completion", title: "Completion notification", summary: "Notify when all queued files have finished."),
            .init(id: "archive-log", title: "Archive log", summary: "Keep the diagnostic log with the output."),
            .init(id: "reveal-results", title: "Reveal results", summary: "Show the output folder after the final task.")
        ])
    ]
}

/// Layout measurements shared by window tests and the optional preview metrics export.
private struct CatalogEngineControlMeasurementKey: EnvironmentKey {
    static let defaultValue = ProcessInfo.processInfo.environment["LUMEN_CATALOG_SETTINGS_METRICS"] != nil
}

extension EnvironmentValues {
    var measuresCatalogEngineControls: Bool {
        get { self[CatalogEngineControlMeasurementKey.self] }
        set { self[CatalogEngineControlMeasurementKey.self] = newValue }
    }
}

private struct CatalogEngineControlMeasure: ViewModifier {
    let name: String
    @Environment(\.measuresCatalogEngineControls) private var measuresControls

    func body(content: Content) -> some View {
        content.background {
            if measuresControls {
                Color.clear.onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global)
                } action: { frame in
                    guard frame.width > 0, frame.height > 0 else { return }
                    CatalogSettingsWindowMetrics.engineControlFrames[name] = frame
                }
            }
        }
    }
}
