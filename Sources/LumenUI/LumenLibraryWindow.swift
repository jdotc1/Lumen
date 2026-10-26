import SwiftUI
import LumenTokens

/// The regions a library's user has requested. Resizing never overwrites this preference.
public struct LumenLibraryPanels: Hashable, Sendable {
    public var sourceList: Bool
    public var detail: Bool

    public init(sourceList: Bool = true, detail: Bool = true) {
        self.sourceList = sourceList
        self.detail = detail
    }

    public static let allCombinations: [Self] = [false, true].flatMap { sourceList in
        [false, true].map { Self(sourceList: sourceList, detail: $0) }
    }
}

/// A library/browser window with a native unified top bar, optional source list, filter chips,
/// collection content, trailing detail and optional status items. Supply `LumenCollection` in
/// `content`, a `LumenDetailHeader` followed by metadata in `detail`, and search/filter controls
/// in the top-bar builders. The scaffold owns scrolling for detail, and the status container.
/// Put a collection in a `ScrollView` when it can exceed the content height.
/// Pair this root with `.lumenLibraryScene()` and `.lumenPaletteRoot()`.
public struct LumenLibraryWindow<Leading: View, Center: View, Trailing: View, SourceList: View,
                                 Content: View, Detail: View, Filters: View, Status: View>: View {
    @Binding private var panels: LumenLibraryPanels
    private let hasPanelBinding: Bool
    @State private var preferences = LumenLibraryPreferences()
    @State private var availableWidth: CGFloat = 0
    private let minimumSize: CGSize
    private let topLeading: Leading
    private let topCenter: Center
    private let topTrailing: Trailing
    private let sourceList: SourceList
    private let content: Content
    private let detail: Detail
    private let statusBar: Status
    private let filterChips: Filters
    private var sourceListWidthOverride: (min: CGFloat, ideal: CGFloat, max: CGFloat)?
    private var sourceListWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        sourceListWidthOverride ?? LumenLayout.sidebarColumn(metrics: metrics)
    }
    private var detailWidthOverride: (min: CGFloat, ideal: CGFloat, max: CGFloat)?
    private var detailWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        detailWidthOverride ?? LumenLayout.inspectorColumn(metrics: metrics)
    }
    private var contentMinWidth: CGFloat = 0
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    /// `minimumSize` is the content area's minimum, excluding the native top bar. Choose a
    /// minimum that fits the content, fixed toolbar items and status items. Omitted regions have
    /// neither a column nor a toggle. A supplied binding is explicit host intent. Without one,
    /// regions start automatic; toolbar and menu changes become explicit per-region choices.
    public init(panels: Binding<LumenLibraryPanels>? = nil, minimumSize: CGSize = CGSize(width: 640, height: 400),
                @ViewBuilder content: () -> Content,
                @ViewBuilder sourceList: () -> SourceList = { EmptyView() },
                @ViewBuilder detail: () -> Detail = { EmptyView() },
                @ViewBuilder filterChips: () -> Filters = { EmptyView() },
                @ViewBuilder statusBar: () -> Status = { EmptyView() },
                @ViewBuilder topLeading: () -> Leading,
                @ViewBuilder topCenter: () -> Center = { EmptyView() },
                @ViewBuilder topTrailing: () -> Trailing = { EmptyView() }) {
        _panels = panels ?? .constant(.init())
        hasPanelBinding = panels != nil
        self.minimumSize = CGSize(width: minimumSize.width.isFinite ? max(0, minimumSize.width) : 640,
                                  height: minimumSize.height.isFinite ? max(0, minimumSize.height) : 400)
        self.content = content()
        self.sourceList = sourceList()
        self.detail = detail()
        self.statusBar = statusBar()
        self.filterChips = filterChips()
        self.topLeading = topLeading()
        self.topCenter = topCenter()
        self.topTrailing = topTrailing()
    }

    public func columnWidths(sourceList: (min: CGFloat, ideal: CGFloat, max: CGFloat) = LumenLayout.sidebarColumn,
                             detail: (min: CGFloat, ideal: CGFloat, max: CGFloat) = LumenLayout.inspectorColumn) -> Self {
        var copy = self
        copy.sourceListWidthOverride = sourceList
        copy.detailWidthOverride = detail
        return copy
    }

    public func contentMinimumWidth(_ width: CGFloat) -> Self {
        var copy = self
        copy.contentMinWidth = width.isFinite ? max(0, width) : 0
        return copy
    }

    private var contentMinimum: CGFloat { max(minimumSize.width, contentMinWidth) }

    private var requested: LumenLibraryPanels { hasPanelBinding ? panels : preferences.requested }
    private var explicit: LumenLibraryPanels { hasPanelBinding ? .init() : preferences.explicit }

    private func visible(at width: CGFloat) -> LumenLibraryPanels {
        LumenLibraryLayout.visiblePanels(requested: requested, explicit: explicit, width: width,
            contentMinimum: contentMinimum,
            sourceListMinimum: hasSourceList ? sourceListWidth.min : nil,
            detailMinimum: hasDetail ? detailWidth.min : nil)
    }

    private func panelBinding(_ key: WritableKeyPath<LumenLibraryPanels, Bool>) -> Binding<Bool> {
        Binding(get: { visible(at: availableWidth)[keyPath: key] }, set: { value in
            if hasPanelBinding {
                panels[keyPath: key] = value
            } else {
                preferences.set(value, for: key)
            }
        })
    }

    private var hasSourceList: Bool { SourceList.self != EmptyView.self }
    private var hasDetail: Bool { Detail.self != EmptyView.self }

    public var body: some View {
        let shown = visible(at: availableWidth)
        VStack(spacing: 0) {
            LumenLibrarySplit(shown: shown, sourceListWidth: sourceListWidth,
                              detailWidth: detailWidth, contentMinimum: contentMinimum,
                              sourceList: sourceList, content: LumenLibraryContent(filters: filterChips, content: content), detail: detail)
            if Status.self != EmptyView.self {
                LumenLibraryStatus { statusBar }
            }
        }
        // Measure the window's proposal, not the split's current pane minimums. Both
        // bounds let this frame shrink before the visibility policy collapses a pane.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(palette[.bgCanvas])
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .preference(key: LumenLibraryLayoutKey.self, value: [LumenLibraryLayoutEntry(
            requested: requested, explicit: explicit, shown: shown, availableWidth: availableWidth,
            contentMinimum: contentMinimum, sourceListMinimum: hasSourceList ? sourceListWidth.min : nil,
            detailMinimum: hasDetail ? detailWidth.min : nil)])
        .lumenPinnedTopBar(
            LumenTopBar {
                topLeading
            } center: {
                topCenter
            } trailing: {
                HStack(spacing: metrics.spacing.s2) {
                    topTrailing
                    LumenPanelToggles(leading: hasSourceList ? panelBinding(\.sourceList) : nil,
                                      trailing: hasDetail ? panelBinding(\.detail) : nil,
                                      registersShortcuts: false)
                }
            }, placement: .unified
        )
        .lumenPanelCommands(leading: hasSourceList ? panelBinding(\.sourceList) : nil,
                            trailing: hasDetail ? panelBinding(\.detail) : nil)
        .frame(minWidth: contentMinimum, minHeight: minimumSize.height)
        .lumenScaffoldMargin(metrics.spacing.s6)
    }
}

private struct LumenLibraryStatus<Content: View>: View {
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
    /// Completes the library root's native chrome and enforces its declared content minimum.
    func lumenLibraryScene() -> some Scene {
        windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .windowResizability(.contentMinSize)
    }
}

/// Real regions stay in their native split panes; hidden side panes remain mounted at zero width.
private struct LumenLibrarySplit<SourceList: View, Content: View, Detail: View>: View {
    let shown: LumenLibraryPanels
    let sourceListWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat)
    let detailWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat)
    let contentMinimum: CGFloat
    let sourceList: SourceList
    let content: Content
    let detail: Detail

    var body: some View {
        HSplitView {
            if SourceList.self != EmptyView.self {
                sourceList
                    .lumenSidebarBackground()
                    .lumenWorkspaceRegion("Source list", shown: shown.sourceList, width: sourceListWidth)
                    .lumenSidebarBand()
            }
            content
                .lumenWorkspaceRegion("Content", shown: true)
                .frame(minWidth: contentMinimum)
                .layoutPriority(1)
            if Detail.self != EmptyView.self {
                LumenLibraryDetail(content: detail)
                    .lumenWorkspaceRegion("Detail", shown: shown.detail, width: detailWidth)
            }
        }
    }
}

private struct LumenLibraryContent<Filters: View, Content: View>: View {
    let filters: Filters
    let content: Content
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if Filters.self != EmptyView.self {
                filters
                    .padding(metrics.spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette[.borderSubtle]).frame(height: metrics.stroke.hairline)
                    }
            }
            content.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }
}

private struct LumenLibraryDetail<Content: View>: View {
    let content: Content
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.s5) { content }
                .padding(metrics.spacing.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lumenColumnContent("Detail content")
        }
        .background(palette[.bgCanvas])
    }
}

extension LumenLibraryPanels {
    var utility: LumenUtilityPanels { .init(sidebar: sourceList, inspector: detail) }
    init(_ utility: LumenUtilityPanels) { self.init(sourceList: utility.sidebar, detail: utility.inspector) }
}

/// Reuses utility intent and collapse policy without changing its behavior.
struct LumenLibraryPreferences {
    private var utility = LumenUtilityPreferences()
    var requested: LumenLibraryPanels { .init(utility.requested) }
    var explicit: LumenLibraryPanels { .init(utility.explicit) }

    mutating func set(_ value: Bool, for key: WritableKeyPath<LumenLibraryPanels, Bool>) {
        utility.set(value, for: key == \.sourceList ? \.sidebar : \.inspector)
    }
}

enum LumenLibraryLayout {
    static func visiblePanels(requested: LumenLibraryPanels, explicit: LumenLibraryPanels,
                              width: CGFloat, contentMinimum: CGFloat,
                              sourceListMinimum: CGFloat?, detailMinimum: CGFloat?) -> LumenLibraryPanels {
        .init(LumenUtilityLayout.visiblePanels(requested: requested.utility, explicit: explicit.utility,
            width: width, contentMinimum: contentMinimum,
            sidebarMinimum: sourceListMinimum, inspectorMinimum: detailMinimum))
    }
}

/// The library's resolved region intent and presentation, reported for window conformance.
public struct LumenLibraryLayoutEntry: Hashable, Sendable {
    public let requested: LumenLibraryPanels
    public let explicit: LumenLibraryPanels
    public let shown: LumenLibraryPanels
    public let availableWidth: CGFloat
    public let contentMinimum: CGFloat
    public let sourceListMinimum: CGFloat?
    public let detailMinimum: CGFloat?

    public init(requested: LumenLibraryPanels, explicit: LumenLibraryPanels, shown: LumenLibraryPanels,
                availableWidth: CGFloat, contentMinimum: CGFloat,
                sourceListMinimum: CGFloat?, detailMinimum: CGFloat?) {
        self.requested = requested
        self.explicit = explicit
        self.shown = shown
        self.availableWidth = availableWidth
        self.contentMinimum = contentMinimum
        self.sourceListMinimum = sourceListMinimum
        self.detailMinimum = detailMinimum
    }
}

/// Library presentation reports consumed by `windowStructure(kind: .library)`.
public struct LumenLibraryLayoutKey: PreferenceKey {
    public static let defaultValue: [LumenLibraryLayoutEntry] = []
    public static func reduce(value: inout [LumenLibraryLayoutEntry], nextValue: () -> [LumenLibraryLayoutEntry]) {
        value.append(contentsOf: nextValue())
    }
}
