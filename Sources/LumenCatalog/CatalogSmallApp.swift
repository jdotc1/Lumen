import SwiftUI
import LumenUI

/// Registered separately so this workspace example is independent of the other Catalog pages.
struct CatalogSmallAppScene: Scene {
    let store: LumenThemeStore
    var body: some Scene {
        Window("Small app", id: "small-app") {
            CatalogSmallApp()
                .lumenPaletteRoot(store: store)
                .lumenDensityRoot(store: store)
                .modifier(CatalogTextScaleRoot())
                .modifier(CatalogChromeRoot())
        }
        .defaultSize(width: 1000, height: 660)
    }
}

/// Nine destinations across two workspaces, with independent remembered selections.
struct CatalogSmallApp: View {
    @State private var workspace = "library"
    @State private var librarySelection: String? = "library.overview"
    @State private var reviewSelection: String? = "review.inbox"
    @State private var isBusy = true
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    static let library = [
        LumenSourceListItem(id: "library.overview", title: "Overview", systemImage: "square.grid.2x2"),
        LumenSourceListItem(id: "library.files", title: "Files", systemImage: "folder"),
        LumenSourceListItem(id: "library.collections", title: "Collections", systemImage: "square.stack"),
        LumenSourceListItem(id: "library.favorites", title: "Favorites", systemImage: "star"),
        LumenSourceListItem(id: "library.archive", title: "Archive", systemImage: "archivebox"),
    ]
    static let review = [
        LumenSourceListItem(id: "review.inbox", title: "Inbox", systemImage: "tray"),
        LumenSourceListItem(id: "review.assigned", title: "Assigned", systemImage: "person"),
        LumenSourceListItem(id: "review.completed", title: "Completed", systemImage: "checkmark.circle"),
        LumenSourceListItem(id: "review.reports", title: "Reports", systemImage: "chart.bar"),
    ]

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                LumenSidebarSection("Workspace") {
                    LumenSidebarSwitcher(selection: $workspace, items: [
                        .init(id: "library", title: "Library", systemImage: "books.vertical"),
                        .init(id: "review", title: "Review", systemImage: "checklist"),
                    ], shortcuts: false)
                }
                if workspace == "library" {
                    LumenSourceList(sections: [.init("Library", items: Self.library)], selection: $librarySelection)
                } else {
                    LumenSourceList(sections: [.init("Review", items: Self.review)], selection: $reviewSelection)
                }
            }
            .lumenSidebarColumn()
            CatalogSmallAppContent(title: selectedTitle, isBusy: $isBusy)
                .padding(metrics.spacing.s6)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .background(palette[.bgCanvas])
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var selectedTitle: String {
        let items = workspace == "library" ? Self.library : Self.review
        let selection = workspace == "library" ? librarySelection : reviewSelection
        return items.first { $0.id == selection }?.title ?? "Workspace"
    }
}

private struct CatalogSmallAppContent: View {
    let title: String
    @Binding var isBusy: Bool
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s6) {
            LumenPageHeader(title, subtitle: "Your files and review work in one place.", systemImage: "square.grid.2x2") {
                Button("Refresh") { isBusy = true }.disabled(isBusy)
            }
            LumenEmptyState(systemImage: "folder", title: "No files yet",
                            message: "Choose a destination in the sidebar to organize your work.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CatalogSmallAppStatus(isBusy: $isBusy)
        }
    }
}

/// The existing status bar content slot accepts native progress and cancellation controls.
struct CatalogSmallAppStatus: View {
    @Binding var isBusy: Bool
    var body: some View {
        LumenStatusBar {
            if isBusy {
                ProgressView().controlSize(.small)
                Text("Refreshing library…").lumenNeverTruncates("Refreshing library…")
                Spacer(minLength: 0)
                Button("Cancel") { isBusy = false }.controlSize(.small)
            } else {
                Text("Ready")
                Spacer(minLength: 0)
                Text("9 destinations · 2 workspaces")
            }
        }
    }
}
