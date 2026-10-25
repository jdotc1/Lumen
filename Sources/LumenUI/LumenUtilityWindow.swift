import SwiftUI
import LumenTokens

/// The regions a utility's user has requested. Resizing never overwrites this preference.
public struct LumenUtilityPanels: Hashable, Sendable {
    public var sidebar: Bool
    public var inspector: Bool

    public init(sidebar: Bool = true, inspector: Bool = true) {
        self.sidebar = sidebar
        self.inspector = inspector
    }

    public static let allCombinations: [Self] = [false, true].flatMap { sidebar in
        [false, true].map { Self(sidebar: sidebar, inspector: $0) }
    }
}

/// A single-window utility: a native unified top bar, optional source list, content, optional
/// inspector and bottom status. The inspector builder supplies sections; the status builder
/// supplies items. The scaffold owns their Lumen containers. There are no document tabs or decks.
///
/// Pair the root with `.lumenUtilityScene()` and `.lumenPaletteRoot()`:
///
/// ```swift
/// Window("Utility", id: "utility") {
///     LumenUtilityWindow(panels: $panels) {
///         fileTable
///     } sidebar: {
///         sourceList
///     } inspector: {
///         tagSections
///     } statusBar: {
///         Text("Ready")
///     } topLeading: {
///         Text("Files")
///     }
///     .lumenPaletteRoot()
/// }
/// .lumenUtilityScene()
/// ```
public struct LumenUtilityWindow<Leading: View, Center: View, Trailing: View, Sidebar: View,
                                 Content: View, Inspector: View, Status: View>: View {
    @Binding private var panels: LumenUtilityPanels
    private let hasPanelBinding: Bool
    @State private var preferences = LumenUtilityPreferences()
    @State private var availableWidth: CGFloat = 0
    private let minimumSize: CGSize
    private let topLeading: Leading
    private let topCenter: Center
    private let topTrailing: Trailing
    private let sidebar: Sidebar
    private let content: Content
    private let inspector: Inspector
    private let statusBar: Status
    private var sidebarWidthOverride: (min: CGFloat, ideal: CGFloat, max: CGFloat)?
    private var sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        sidebarWidthOverride ?? LumenLayout.sidebarColumn(metrics: metrics)
    }
    private var inspectorWidthOverride: (min: CGFloat, ideal: CGFloat, max: CGFloat)?
    private var inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        inspectorWidthOverride ?? LumenLayout.inspectorColumn(metrics: metrics)
    }
    private var contentMinWidth: CGFloat = 0
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    /// `minimumSize` is the content area's minimum, excluding the native top bar. Choose a
    /// minimum that fits the content, fixed toolbar items and status items. Omitted regions have
    /// neither a column nor a toggle. A supplied binding is explicit host intent. Without one,
    /// regions start automatic; toolbar and menu changes become explicit per-region choices.
    public init(panels: Binding<LumenUtilityPanels>? = nil, minimumSize: CGSize = CGSize(width: 640, height: 400),
                @ViewBuilder content: () -> Content,
                @ViewBuilder sidebar: () -> Sidebar = { EmptyView() },
                @ViewBuilder inspector: () -> Inspector = { EmptyView() },
                @ViewBuilder statusBar: () -> Status = { EmptyView() },
                @ViewBuilder topLeading: () -> Leading,
                @ViewBuilder topCenter: () -> Center = { EmptyView() },
                @ViewBuilder topTrailing: () -> Trailing = { EmptyView() }) {
        _panels = panels ?? .constant(.init())
        hasPanelBinding = panels != nil
        self.minimumSize = CGSize(width: minimumSize.width.isFinite ? max(0, minimumSize.width) : 640,
                                  height: minimumSize.height.isFinite ? max(0, minimumSize.height) : 400)
        self.content = content()
        self.sidebar = sidebar()
        self.inspector = inspector()
        self.statusBar = statusBar()
        self.topLeading = topLeading()
        self.topCenter = topCenter()
        self.topTrailing = topTrailing()
    }

    public func columnWidths(sidebar: (min: CGFloat, ideal: CGFloat, max: CGFloat) = LumenLayout.sidebarColumn,
                             inspector: (min: CGFloat, ideal: CGFloat, max: CGFloat) = LumenLayout.inspectorColumn) -> Self {
        var copy = self
        copy.sidebarWidthOverride = sidebar
        copy.inspectorWidthOverride = inspector
        return copy
    }

    public func contentMinimumWidth(_ width: CGFloat) -> Self {
        var copy = self
        copy.contentMinWidth = width.isFinite ? max(0, width) : 0
        return copy
    }

    private var contentMinimum: CGFloat { max(minimumSize.width, contentMinWidth) }

    private var requested: LumenUtilityPanels { hasPanelBinding ? panels : preferences.requested }
    private var explicit: LumenUtilityPanels { hasPanelBinding ? .init() : preferences.explicit }

    private func visible(at width: CGFloat) -> LumenUtilityPanels {
        LumenUtilityLayout.visiblePanels(requested: requested, explicit: explicit, width: width,
            contentMinimum: contentMinimum,
            sidebarMinimum: hasSidebar ? sidebarWidth.min : nil,
            inspectorMinimum: hasInspector ? inspectorWidth.min : nil)
    }

    private func panelBinding(_ key: WritableKeyPath<LumenUtilityPanels, Bool>) -> Binding<Bool> {
        Binding(get: { visible(at: availableWidth)[keyPath: key] }, set: { value in
            if hasPanelBinding {
                panels[keyPath: key] = value
            } else {
                preferences.set(value, for: key)
            }
        })
    }

    private var hasSidebar: Bool { Sidebar.self != EmptyView.self }
    private var hasInspector: Bool { Inspector.self != EmptyView.self }

    public var body: some View {
        let shown = visible(at: availableWidth)
        VStack(spacing: 0) {
            LumenUtilitySplit(shown: shown, sidebarWidth: sidebarWidth,
                              inspectorWidth: inspectorWidth, contentMinimum: contentMinimum,
                              sidebar: sidebar, content: content, inspector: inspector)
            if Status.self != EmptyView.self {
                LumenUtilityStatus { statusBar }
            }
        }
        // Measure the window's proposal, not the split's current pane minimums. Both
        // bounds let this frame shrink before the visibility policy collapses a pane.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(palette[.bgCanvas])
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .lumenPinnedTopBar(
            LumenTopBar {
                topLeading
            } center: {
                topCenter
            } trailing: {
                HStack(spacing: metrics.spacing.s2) {
                    topTrailing
                    LumenPanelToggles(leading: hasSidebar ? panelBinding(\.sidebar) : nil,
                                      trailing: hasInspector ? panelBinding(\.inspector) : nil,
                                      registersShortcuts: false)
                }
            }, placement: .unified
        )
        .lumenPanelCommands(leading: hasSidebar ? panelBinding(\.sidebar) : nil,
                            trailing: hasInspector ? panelBinding(\.inspector) : nil)
        .frame(minWidth: contentMinimum, minHeight: minimumSize.height)
        .lumenScaffoldMargin(metrics.spacing.s6)
    }
}

private struct LumenUtilityStatus<Content: View>: View {
    let content: Content
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        LumenStatusBar { content }
            .padding(metrics.spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette[.bgCanvas])
            .overlay(alignment: .top) {
                Rectangle().fill(palette[.borderSubtle]).frame(height: metrics.stroke.hairline)
            }
            .lumenColumnContent("Status bar")
    }
}

public extension Scene {
    /// Completes the utility root's native chrome and enforces its declared content minimum.
    func lumenUtilityScene() -> some Scene {
        windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .windowResizability(.contentMinSize)
    }
}

/// Explicit intent is independent of the space-dependent presentation. A nil choice is automatic.
struct LumenUtilityPreferences {
    private var sidebar: Bool?
    private var inspector: Bool?

    var requested: LumenUtilityPanels { .init(sidebar: sidebar ?? true, inspector: inspector ?? true) }
    var explicit: LumenUtilityPanels { .init(sidebar: sidebar != nil, inspector: inspector != nil) }

    mutating func set(_ value: Bool, for key: WritableKeyPath<LumenUtilityPanels, Bool>) {
        if key == \.sidebar { sidebar = value } else { inspector = value }
    }
}

enum LumenUtilityLayout {
    /// Recompute from intent at every width: this restores in reverse collapse order without
    /// ever writing automatic hiding back to the host's binding or an explicit local choice.
    static func visiblePanels(requested: LumenUtilityPanels, explicit: LumenUtilityPanels,
                              width: CGFloat, contentMinimum: CGFloat,
                              sidebarMinimum: CGFloat?, inspectorMinimum: CGFloat?) -> LumenUtilityPanels {
        var shown = LumenUtilityPanels(sidebar: requested.sidebar && sidebarMinimum != nil,
                                       inspector: requested.inspector && inspectorMinimum != nil)
        func requiredWidth() -> CGFloat {
            contentMinimum + (shown.sidebar ? (sidebarMinimum ?? 0) + 1 : 0)
                + (shown.inspector ? (inspectorMinimum ?? 0) + 1 : 0)
        }
        // Explicitly shown regions yield after automatic ones; ties retain inspector-first order.
        let sidebarFirst = explicit.inspector && !explicit.sidebar
        if requiredWidth() > width {
            if sidebarFirst { shown.sidebar = false } else { shown.inspector = false }
        }
        if requiredWidth() > width {
            if sidebarFirst { shown.inspector = false } else { shown.sidebar = false }
        }
        return shown
    }
}

/// Real regions stay in their native split panes; hidden side panes remain mounted at zero width.
private struct LumenUtilitySplit<Sidebar: View, Content: View, Inspector: View>: View {
    let shown: LumenUtilityPanels
    let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat)
    let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat)
    let contentMinimum: CGFloat
    let sidebar: Sidebar
    let content: Content
    let inspector: Inspector

    var body: some View {
        HSplitView {
            if Sidebar.self != EmptyView.self {
                sidebar
                    .lumenSidebarBackground()
                    .lumenWorkspaceRegion("Sidebar", shown: shown.sidebar, width: sidebarWidth)
            }
            content
                .lumenWorkspaceRegion("Content", shown: true)
                .frame(minWidth: contentMinimum)
                .layoutPriority(1)
            if Inspector.self != EmptyView.self {
                LumenInspector { inspector }
                    .lumenWorkspaceRegion("Inspector", shown: shown.inspector, width: inspectorWidth)
            }
        }
    }
}
