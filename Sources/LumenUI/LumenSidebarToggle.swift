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
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.lumenResolvedChromeStyle) private var chromeStyle

    private var sidebarShown: Binding<Bool> {
        Binding(get: { columnVisibility != .detailOnly && columnVisibility != .doubleColumn },
                set: { columnVisibility = $0 ? .all : .detailOnly })
    }

    func body(content: Content) -> some View {
        content
            // The system toggle sits in a glass bubble; Lumen's bare button replaces it in both styles.
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                do {
                    ToolbarSpacer(.flexible, placement: .automatic)
                    // Automatic placement belongs to this sidebar column; navigation placement
                    // would join the identity after the tracking separator.
                    ToolbarItem(id: "lumen.sidebarToggle", placement: .automatic) {
                        Button(sidebarShown.wrappedValue ? lumenLocalized(String(localized: "Hide Sidebar", bundle: .module, comment: "SidebarToggle display text.")) : lumenLocalized(String(localized: "Show Sidebar", bundle: .module, comment: "SidebarToggle display text.")), systemImage: layoutDirection == .rightToLeft ? "sidebar.right" : "sidebar.left") {
                            sidebarShown.wrappedValue.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(LumenToolbarIconButtonStyle())
                        .lumenIconOnlyControl(lumenLocalized(String(localized: "Sidebar", bundle: .module, comment: "SidebarToggle control text.")))
                        .lumenFocusRing()
                        .help(sidebarShown.wrappedValue ? lumenLocalized(String(localized: "Hide Sidebar", bundle: .module, comment: "SidebarToggle display text.")) : lumenLocalized(String(localized: "Show Sidebar", bundle: .module, comment: "SidebarToggle display text.")))
                    }
                    .lumenToolbarPlatter(chromeStyle)
                }
            }
    }
}
