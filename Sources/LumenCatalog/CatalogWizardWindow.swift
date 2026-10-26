import SwiftUI
import LumenUI

struct WizardWindowPage: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s5) {
            PageHeader(title: "Wizard Window", summary: "A first-run window with ordered steps, a focused page and Back, Continue and Done actions. Completed steps remain available for review.")
            Button("Open Wizard Window", systemImage: "macwindow") { openWindow(id: "wizard") }
                .buttonStyle(.lumenPrimary)
            CatalogWizardPreview()
            Text("This setup uses sample folders and keeps its choices in this window.")
                .foregroundStyle(.lumen(.fgSecondary))
                .lumenWrapsWithoutTruncating()
        }
    }
}

/// Scale the complete inline wizard to its column without changing the real scene's sizing.
struct CatalogWizardPreview: View {
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
        CatalogScaledPreview(width: 640 * growth, height: 460 * growth, maxScale: 1) {
            CatalogWizardWindow()
        }
    }
}

/// Shared by the real first-run scene, the inline page and the wizard's golden fixtures.
struct CatalogWizardWindow: View {
    static let pages = [
        LumenWizardPage(id: "welcome", title: "Welcome", systemImage: "hand.wave"),
        LumenWizardPage(id: "folder", title: "Choose a Folder", systemImage: "folder"),
        LumenWizardPage(id: "options", title: "Options", systemImage: "slider.horizontal.3"),
        LumenWizardPage(id: "summary", title: "Summary", systemImage: "checkmark.circle"),
    ]

    @State private var current: Int
    @State private var folder = "Example Project"
    @State private var includesSubfolders = true
    @State private var showsNotifications = false
    @State private var completed = false
    private let dismissOnCompletion: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.lumenMetrics) private var metrics

    init(current: Int = 0, dismissOnCompletion: Bool = false) {
        _current = State(initialValue: current)
        self.dismissOnCompletion = dismissOnCompletion
    }

    var body: some View {
        LumenWizardWindow(pages: Self.pages, current: $current,
                          onCancel: cancel, onFinish: finish) { page in
            VStack(alignment: .leading, spacing: metrics.spacing.s5) {
                switch page.id {
                case "welcome":
                    Text(completed ? "Your sample setup is complete." : "Make yourself at home.")
                        .font(metrics.typography.headline)
                        .catalogFirstContent("detail-first-text")
                        .lumenWrapsWithoutTruncating()
                    Text("Choose a folder, adjust a few preferences, and review your choices before you begin.")
                        .foregroundStyle(.lumen(.fgSecondary))
                        .lumenWrapsWithoutTruncating()
                case "folder":
                    Text("Choose the sample folder to include in your library.")
                        .foregroundStyle(.lumen(.fgSecondary))
                        .lumenWrapsWithoutTruncating()
                    LumenPopUp(selection: $folder, options: ["Example Project", "Sample Library"], title: { $0 })
                case "options":
                    Text("Set the preferences for this folder.")
                        .foregroundStyle(.lumen(.fgSecondary))
                        .lumenWrapsWithoutTruncating()
                    LumenSettingsCard {
                        Toggle("Include subfolders", isOn: $includesSubfolders)
                        Toggle("Show notifications", isOn: $showsNotifications)
                    }
                    .toggleStyle(.lumenCheckbox)
                default:
                    Text("Review your choices. Go back to any completed step to make a change.")
                        .foregroundStyle(.lumen(.fgSecondary))
                        .lumenWrapsWithoutTruncating()
                    LumenWizardSummary([
                        (label: "Folder", value: folder),
                        (label: "Subfolders", value: includesSubfolders ? "Included" : "Excluded"),
                        (label: "Notifications", value: showsNotifications ? "On" : "Off"),
                    ])
                }
            }
        }
    }

    private func cancel() {
        if dismissOnCompletion {
            dismissWindow(id: "wizard")
        } else {
            completed = false
            current = 0
        }
    }

    private func finish() {
        if dismissOnCompletion {
            dismissWindow(id: "wizard")
        } else {
            completed = true
            current = 0
        }
    }
}
