import SwiftUI
import LumenUI

/// A complete grouped form for the Catalog's native Settings window.
struct CatalogModelServerSettings: View {
    @State private var sampling = "Balanced"
    @State private var endpoint = "http://127.0.0.1:8080"
    @State private var timeout = 900_000
    @State private var context = 32_768
    @State private var applied = false
    @State private var refreshed = false
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        Form {
            Section {
                LumenSettingsRow("Provider") { Text("Local service") }
                LumenSettingsRow("Sampling") {
                    Picker("Sampling", selection: $sampling) {
                        Text("Precise").tag("Precise")
                        Text("Balanced").tag("Balanced")
                        Text("Creative").tag("Creative")
                    }
                }
                LumenSettingsTextRow("Loopback endpoint", text: $endpoint, monospaced: true)
                LumenSettingsNumberRow("Request timeout", value: $timeout, in: 1_000...9_999_999, unit: "ms", step: 1_000)
                LumenSettingsNumberRow("Context length", value: $context, in: 1_024...9_999_999, unit: "tokens", step: 1_024)
                LumenSettingsButtonRow {
                    Button("Apply") { applied = true }
                    Button("Refresh") { refreshed = true }
                }
            } header: {
                LumenSettingsHeader("Model server", systemImage: "cpu", hue: .hueViolet,
                                    summary: "Configure a local model service and inspect its availability.")
            }
            Section("Service status") {
                LumenSettingsStatusRow("Configuration", detail: applied ? "Current settings applied to this preview." : "Changes have not been applied.",
                                       tone: applied ? .success : .info)
                LumenSettingsStatusRow("Connection", detail: refreshed ? "Preview refreshed. No service is connected." : "No connection has been requested.", tone: .info)
            }
            Section {
                LumenSettingsEmptyRow("No models discovered", detail: "Start a model service, then refresh to discover available models.")
            } header: {
                Text("Discovered models")
            } footer: {
                Text("This Catalog preview does not connect to a network service.")
                    .font(metrics.typography.caption)
                    .foregroundStyle(palette[.fgSecondary])
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, metrics.spacing.s9, for: .scrollContent)
        .background(palette[.panelBackground])
    }
}
