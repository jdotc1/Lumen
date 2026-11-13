import SwiftUI
import LumenUI

/// The same agent panel is shown by the menu bar extra and the inline Catalog page.
struct CatalogMenuBarPanel: View {
    @State private var syncEnabled = true
    @State private var notifications = false

    var body: some View {
        LumenMenuBarPanel("Lumen Agent") {
            CatalogAgentStatus()
            Divider()
            Toggle(isOn: $syncEnabled) {
                Text("Sync files").lumenNeverTruncates("Sync files")
            }
            Toggle(isOn: $notifications) {
                Text("Notify me").lumenNeverTruncates("Notify me")
            }
            .toggleStyle(.lumenCheckbox)
            Divider()
            CatalogAgentRecentItems()
        } accessory: {
            Text("Ready").lumenNeverTruncates("Ready")
                .foregroundStyle(.lumen(.fgSecondary))
        } footer: {
            Text("Synced just now").lumenNeverTruncates("Synced just now")
                .foregroundStyle(.lumen(.fgSecondary))
        }
        .toggleStyle(.lumenCheckbox)
    }
}

private struct CatalogAgentStatus: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CatalogAgentLabel("All files up to date", systemImage: "checkmark.circle")
                .catalogFirstContent("detail-first-status")
            Text("3 folders watched").lumenNeverTruncates("3 folders watched")
                .foregroundStyle(.lumen(.fgSecondary))
        }
    }
}

private struct CatalogAgentRecentItems: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity").bold().lumenNeverTruncates("Recent activity")
            CatalogAgentLabel("Notes.md synced", systemImage: "doc.text")
            CatalogAgentLabel("Sketch.png added", systemImage: "photo")
            CatalogAgentLabel("Report.pdf synced", systemImage: "doc")
        }
    }
}

/// A row label whose icon sits in a fixed 20 pt column, so every title starts at the same x
/// whatever the symbol's own width ("photo" is wider than "doc"; design review 2026-11 #16).
private struct CatalogAgentLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title).lumenNeverTruncates(title)
        } icon: {
            LumenSymbol(systemImage).frame(width: 20)
        }
    }
}

/// The Catalog page: the standard page header over the panel as it appears in the menu bar. The
/// panel itself stays header-free because the MenuBarExtra shows it too.
struct CatalogMenuBarPanelPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Menu Bar Panel", summary: "The agent panel a menu bar extra shows: a title and status, grouped content and a footer with Settings and Quit.")
            CatalogMenuBarPanel()
        }
    }
}
