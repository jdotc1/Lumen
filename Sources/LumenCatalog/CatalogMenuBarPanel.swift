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
            Label {
                Text("All files up to date").lumenNeverTruncates("All files up to date")
            } icon: { Image(systemName: "checkmark.circle") }
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
            Label {
                Text("Notes.md synced").lumenNeverTruncates("Notes.md synced")
            } icon: { Image(systemName: "doc.text") }
            Label {
                Text("Sketch.png added").lumenNeverTruncates("Sketch.png added")
            } icon: { Image(systemName: "photo") }
            Label {
                Text("Report.pdf synced").lumenNeverTruncates("Report.pdf synced")
            } icon: { Image(systemName: "doc") }
        }
    }
}
