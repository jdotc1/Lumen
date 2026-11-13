# One sidebar, several workspaces

The existing API expresses this without another public helper: compose `LumenSidebarSection`,
`LumenSidebarSwitcher` and `LumenSourceList`. The switcher chooses a workspace; the section below
it shows that workspace's destinations. Five Library destinations plus four Review destinations
make nine total, while only one sidebar occupies the window.

The following complete view is compiled in `Tests/LumenUITests/LumenWorkspaceExamples.swift`.
Its three bindings come from the window root in `small-app.md`; that complete app shows detail
routing, palette setup and `.lumenSidebarColumn()` at the hosting boundary.

```swift
import SwiftUI
import LumenUI

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
```

Keep the workspace selection distinct from destination selection. Namespace destination IDs
(`library.documents`, `review.inbox`) so equal visible names in different workspaces cannot
collide. Retain one destination selection per workspace at the window root; do not put it in
conditional child-local `@State`, which is discarded when that branch leaves the hierarchy.
The app derives the detail title and content from the active workspace's selection.

For data-driven workspaces, use stable IDs and an app-owned dictionary of selections. When a
selected item disappears, reconcile to a valid destination or nil in the model; do not mutate
selection from `body`. An empty workspace should show `LumenEmptyState`, while an unselected
workspace should show an explicit selection prompt. The sample uses fixed lists and valid
initial selections, so it needs no reconciliation machinery.

The switcher uses existing icon treatment and disables its optional numeric shortcuts here.
No custom keyboard behavior is added. Use the shared sidebar column sizing rather than another
hard-coded width, and keep ordinary destination rows inside the existing source list.
