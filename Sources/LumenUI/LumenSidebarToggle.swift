import SwiftUI

public extension View {
    /// Apply to the sidebar content of a `NavigationSplitView`, passing its column-visibility
    /// binding. Drawn chrome uses a bare Lumen toggle; glass keeps the system toggle. The native
    /// Toggle Sidebar menu action continues to target the split view in either style.
    func lumenSidebarToggle(columnVisibility: Binding<NavigationSplitViewVisibility>) -> some View {
        modifier(LumenSidebarToggleModifier(columnVisibility: columnVisibility))
    }
}

private struct LumenSidebarToggleModifier: ViewModifier {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.lumenResolvedChromeStyle) private var chromeStyle

    private var sidebarShown: Binding<Bool> {
        Binding(get: { columnVisibility != .detailOnly && columnVisibility != .doubleColumn },
                set: { columnVisibility = $0 ? .all : .detailOnly })
    }

    func body(content: Content) -> some View {
        content
            // nil restores the native item without replacing the split view's subtree.
            .toolbar(removing: chromeStyle == .drawn ? .sidebarToggle : nil)
            .toolbar {
                if chromeStyle == .drawn {
                    ToolbarSpacer(.flexible, placement: .automatic)
                    // Automatic placement belongs to this sidebar column; navigation placement
                    // would join the identity after the tracking separator.
                    ToolbarItem(id: "lumen.sidebarToggle", placement: .automatic) {
                        Button(sidebarShown.wrappedValue ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left") {
                            sidebarShown.wrappedValue.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(LumenToolbarIconButtonStyle())
                        .lumenIconOnlyControl("Sidebar")
                        .lumenFocusRing()
                        .help(sidebarShown.wrappedValue ? "Hide Sidebar" : "Show Sidebar")
                    }
                    .lumenToolbarPlatter(chromeStyle)
                }
            }
    }
}
