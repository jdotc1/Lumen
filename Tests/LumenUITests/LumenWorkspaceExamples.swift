import SwiftUI
import LumenUI

// Compiled documentation examples. Add @main to ExampleSmallApp in a consuming app target.
// BEGIN SMALL APP
struct ExampleSmallApp: App {
    init() {
        LumenThemeStore.install(LumenThemeStore(
            registry: .core,
            configuration: .init(appName: "SmallApp")
        ))
    }

    var body: some Scene {
        WindowGroup("Small app") {
            ExampleWorkspace()
                .lumenPaletteRoot()
                .lumenDensityRoot()
        }
        .defaultSize(width: 1000, height: 660)

        Settings {
            LumenSettingsSidebarView([
                LumenSettingsCategory(id: "appearance", title: "Appearance",
                                      systemImage: "paintpalette", hue: .hueViolet) {
                    LumenAppearanceSettings()
                }
            ])
            .lumenPaletteRoot()
            .lumenDensityRoot()
        }
        .lumenSettingsScene()
    }
}

struct ExampleWorkspace: View {
    @State private var workspace = "library"
    @State private var librarySelection: String? = "library.documents"
    @State private var reviewSelection: String? = "review.inbox"
    @State private var busy = false
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ExampleSidebar(workspace: $workspace,
                                librarySelection: $librarySelection,
                                reviewSelection: $reviewSelection)
                    .lumenSidebarColumn()
                ExampleContent(title: selectedTitle, busy: $busy)
                    .lumenColumn(min: 320)
            }
            LumenStatusBar {
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Refreshing").lumenNeverTruncates("Refreshing")
                    Button("Cancel") { busy = false }
                } else {
                    Text("Ready").lumenNeverTruncates("Ready")
                }
                Spacer(minLength: metrics.spacing.s4)
                Text(workspace == "library" ? "Library" : "Review")
            }
            .padding(metrics.spacing.s4)
        }
        .background(palette[.bgCanvas])
    }

    private var selectedTitle: String {
        let items = workspace == "library" ? ExampleSidebar.libraryItems : ExampleSidebar.reviewItems
        let selected = workspace == "library" ? librarySelection : reviewSelection
        return items.first(where: { $0.id == selected })?.title ?? "Select a destination"
    }
}

struct ExampleContent: View {
    let title: String
    @Binding var busy: Bool
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s6) {
            LumenPageHeader(title, subtitle: "Your current workspace", systemImage: "folder") {
                Button("Refresh") { busy = true }
                    .disabled(busy)
            }
            LumenEmptyState(systemImage: "doc", title: "No documents",
                            message: "Import a document to get started.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(metrics.spacing.s6)
    }
}
// END SMALL APP

// BEGIN SIDEBAR
struct ExampleSidebar: View {
    @Binding var workspace: String
    @Binding var librarySelection: String?
    @Binding var reviewSelection: String?

    static let libraryItems: [LumenSourceListItem] = [
        .init(id: "library.documents", title: "Documents", systemImage: "doc"),
        .init(id: "library.recent", title: "Recent", systemImage: "clock"),
        .init(id: "library.favorites", title: "Favorites", systemImage: "star"),
        .init(id: "library.collections", title: "Collections", systemImage: "folder"),
        .init(id: "library.archive", title: "Archive", systemImage: "archivebox")
    ]
    static let reviewItems: [LumenSourceListItem] = [
        .init(id: "review.inbox", title: "Inbox", systemImage: "tray"),
        .init(id: "review.assigned", title: "Assigned", systemImage: "person"),
        .init(id: "review.completed", title: "Completed", systemImage: "checkmark.circle"),
        .init(id: "review.reports", title: "Reports", systemImage: "chart.bar")
    ]

    var body: some View {
        VStack(spacing: 0) {
            LumenSidebarSection("Workspace") {
                LumenSidebarSwitcher(selection: $workspace, items: [
                    .init(id: "library", title: "Library", systemImage: "books.vertical"),
                    .init(id: "review", title: "Review", systemImage: "checklist")
                ], shortcuts: false)
            }
            if workspace == "library" {
                LumenSidebarSection("Library") {
                    LumenSourceList(Self.libraryItems, selection: $librarySelection)
                }
            } else {
                LumenSidebarSection("Review") {
                    LumenSourceList(Self.reviewItems, selection: $reviewSelection)
                }
            }
        }
    }
}
// END SIDEBAR

// BEGIN MINIMAL PALETTE
struct ExampleMinimalRoot: View {
    var body: some View {
        ExampleMinimalContent().lumenMetrics(.standard)
    }
}

struct ExampleMinimalContent: View {
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s2) {
            Text("Documents")
                .font(metrics.typography.title2)
                .foregroundStyle(palette[.fgPrimary])
            Text("No documents yet")
                .font(metrics.typography.body)
                .foregroundStyle(palette[.fgSecondary])
        }
        .padding(metrics.spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette[.bgCanvas])
    }
}
// END MINIMAL PALETTE
