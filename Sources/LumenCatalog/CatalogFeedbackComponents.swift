import SwiftUI
import LumenUI

/// Shared with the real Catalog menu and toolbar shortcut registrations.
@MainActor enum CatalogShortcutDefinitions {
    static let newWindow = LumenShortcut(title: "New Window", shortcut: KeyboardShortcut("n"))
    static let goToAddress = LumenShortcut(title: "Go to Address…", shortcut: KeyboardShortcut("g"))
    static let findInProject = LumenShortcut(title: "Find in Project", shortcut: KeyboardShortcut("f", modifiers: [.command, .shift]))
    static let build = LumenShortcut(title: "Build", shortcut: KeyboardShortcut("b"))
    static let run = LumenShortcut(title: "Run", shortcut: KeyboardShortcut("r"))
    static let stop = LumenShortcut(title: "Stop", shortcut: KeyboardShortcut("."))
    static var groups: [LumenShortcutGroup] {
        LumenViewCommands().shortcutGroups + [
            LumenShortcutGroup(title: "File", shortcuts: [newWindow]),
            LumenShortcutGroup(title: "Lumen", shortcuts: [goToAddress, findInProject]),
            LumenShortcutGroup(title: "Tasks", shortcuts: [build, run, stop])
        ] + LumenShortcutsCommands.shortcutGroups
    }
}

struct CatalogToastSection: View {
    @Environment(LumenToastCenter.self) private var center: LumenToastCenter?
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s3) {
            LumenSectionHeader("Toasts")
            Text("Window notices stack at the bottom trailing edge. Hover pauses dismissal; warnings and errors stay until dismissed.")
                .lumenWrapsWithoutTruncating()
            ViewThatFits(in: .horizontal) {
                HStack { toneButtons }
                VStack(alignment: .leading) { toneButtons }
            }
            Button("Post a Stack") {
                center?.post(LumenToast(title: "Earlier notification", message: "Dismiss a visible notice to reveal this one.", duration: nil))
                center?.post(LumenToast(title: "Export complete", message: "Your report is ready.", tone: .success, duration: nil))
                center?.post(LumenToast(title: "Source changed on disk", message: "Review the changes before continuing.", tone: .warning))
                center?.post(LumenToast(title: "Connection interrupted", message: "Your local changes are safe.", tone: .danger,
                                       action: .init("Retry") { center?.post(LumenToast(title: "Reconnecting…")) }))
            }
            .buttonStyle(.bordered)
            LumenSectionHeader("Keyboard shortcuts")
            Text("Help › Keyboard Shortcuts (⌘/) opens the searchable sheet generated from this window’s View, Window, File, Lumen and Tasks commands.")
                .lumenWrapsWithoutTruncating()
        }
    }

    @ViewBuilder private var toneButtons: some View {
        Button("Info") { center?.post(LumenToast(title: "Analysis started", message: "Results will appear as they arrive.")) }
        Button("Success") { center?.post(LumenToast(title: "Saved", message: "All changes were saved.", tone: .success)) }
        Button("Warning") { center?.post(LumenToast(title: "Source changed", message: "Review before continuing.", tone: .warning)) }
        Button("Danger") { center?.post(LumenToast(title: "Unable to connect", message: "Try again when the server is available.", tone: .danger)) }
    }
}
