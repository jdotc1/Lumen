import AppKit
import SwiftUI
import LumenTokens

// Settings, the Mac way: a separate window (⌘,), tabbed categories for a few panes or a sidebar
// with search for many, native grouped forms and native controls, and every change applied at once
// (no Save button). Lumen's part is the visual language: colored category tiles, pane headers, and
// panel colors from the theme. Window roots also own their navigation chrome and stable frame.

/// A settings pane: a header (tile, title, one-sentence summary) above a native grouped form.
public struct LumenSettingsPane<Content: View>: View {
    private let title: String
    private let summary: String?
    private let systemImage: String
    private let hue: LumenToken
    private let content: Content

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    private let style: LumenSettingsPaneStyle

    public init(_ title: String, systemImage: String, hue: LumenToken, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, hue: hue, summary: summary, style: .grouped, content: content)
    }

    /// - Parameter style: `.rich` for `LumenSettingsRow`s in `LumenFormSection`s under the header;
    /// `.grouped` for a native grouped form.
    public init(_ title: String, systemImage: String, hue: LumenToken, summary: String? = nil,
                style: LumenSettingsPaneStyle, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.hue = hue
        self.style = style
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let widthClass = LumenSettingsWidthClass(width: geometry.size.width)
            Group {
                switch style {
                case .grouped: grouped(widthClass)
                case .rich: rich(widthClass)
                }
            }
            .environment(\.lumenSettingsWidthClass, widthClass)
            .environment(\.lumenSettingsPaneOwnsMeasure, true)
        }
        .background(palette[.panelBackground])
    }

    private func rich(_ widthClass: LumenSettingsWidthClass) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: widthClass.sectionSpacing(metrics)) {
                LumenSettingsHeader(title, systemImage: systemImage, hue: hue, summary: summary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, widthClass.horizontalPadding(metrics))
            .padding(.top, widthClass.horizontalPadding(metrics))
            .padding(.bottom, metrics.spacing.s9)
            .frame(maxWidth: 640, alignment: .leading)
            .modifier(LumenSettingsNaturalHeight())
            .frame(maxWidth: .infinity, alignment: widthClass == .wide ? .center : .leading)
        }
    }

    private func grouped(_ widthClass: LumenSettingsWidthClass) -> some View {
        Form {
            Section {
                content
            } header: {
                LumenSettingsHeader(title, systemImage: systemImage, hue: hue, summary: summary)
                    .padding(.bottom, widthClass.sectionSpacing(metrics))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, widthClass.horizontalPadding(metrics), for: .scrollContent)
        .contentMargins(.bottom, metrics.spacing.s9, for: .scrollContent)
        .modifier(LumenSettingsFormMeasure())
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: widthClass == .wide ? .center : .leading)
    }
}

/// How a `LumenSettingsPane` lays out its settings.
public enum LumenSettingsPaneStyle: Sendable, CaseIterable {
    /// A native grouped form.
    case grouped
    /// Rows with a one-line explanation under each name and the control at the trailing edge, in
    /// titled sections.
    case rich
}

/// One setting in a rich pane: its name, a one-line explanation under
/// it, and the control at the trailing edge (a native `Toggle`, a pop-up `Picker`, or a
/// `LumenModeSwitcher(style: .pill)` for two to four choices). When the pane is narrow, the control
/// moves under the text rather than clipping.
public struct LumenSettingsRow<Control: View>: View {
    private let title: String
    private let description: String?
    private let control: Control
    private var badge: (systemImage: String, help: String)?

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenSettingsPaneOwnsMeasure) private var paneOwnsMeasure
    @Environment(\.lumenSettingsQuery) private var query
    @Environment(\.lumenDensity) private var density

    public init(_ title: String, description: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    /// - Parameter badge: a small glyph after the title saying where the value comes from, with its
    ///   help ("checkmark.seal", "Set by .editorconfig").
    public init(_ title: String, description: String? = nil, badge: (systemImage: String, help: String),
                @ViewBuilder control: () -> Control) {
        self.init(title, description: description, control: control)
        self.badge = badge
    }

    public var body: some View {
        LumenSettingsRowLayout(spacing: metrics.spacing.s4) {
            text
            control.labelsHidden()
        }
        // A pane supplies the shared proposal for settings rows, public form rows and prose.
        // Keep the standalone row's compact measure without introducing a second edge in a pane.
        .frame(maxWidth: paneOwnsMeasure ? .infinity : 480, alignment: .leading)
        .padding(.vertical, density.rowVerticalPadding(detailed: description != nil, in: metrics.layout))
        .frame(minHeight: description == nil ? density.rowHeight(in: metrics.layout) : density.detailedRowHeight(in: metrics.layout))
        // The match band reaches out past the row, so the title keeps the column's leading edge.
        .background {
            RoundedRectangle(cornerRadius: metrics.radius.sm).fill(matchesSearch ? palette[.accentSubtle] : .clear)
                .padding(.horizontal, -metrics.spacing.s2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
    }

    private var matchesSearch: Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return !needle.isEmpty && title.localizedCaseInsensitiveContains(needle)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s1) {
            HStack(spacing: metrics.spacing.s2) {
                // Inside the match band the letters are marked by emphasis, not a second accent tint
                // (the marker's own tint vanished into the band).
                LumenHighlightedText(title, matching: matchesSearch ? query.trimmingCharacters(in: .whitespaces) : "", style: .emphasis)
                    .font(metrics.typography.body).foregroundStyle(palette[.fgPrimary])
                if let badge {
                    LumenSymbol(badge.systemImage).font(.system(size: metrics.iconSize.small, weight: .semibold)).foregroundStyle(palette[.accent])
                        .help(badge.help)
                        .accessibilityLabel(badge.help)
                }
            }
            if let description {
                Text(description).font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])
                    .lumenWrapsWithoutTruncating()
            }
        }
    }
}

/// The header at the top of a settings pane, also usable on its own.
public struct LumenSettingsHeader: View {
    private let title: String
    private let summary: String?
    private let systemImage: String
    private let hue: LumenToken

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    public init(_ title: String, systemImage: String, hue: LumenToken, summary: String? = nil) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.hue = hue
    }

    public var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.s5) {
            LumenIconTile(systemImage, hue: hue, size: metrics.layout.tilePaneHeader)
            VStack(alignment: .leading, spacing: metrics.spacing.s1) {
                Text(title).font(metrics.typography.title3).foregroundStyle(palette[.fgPrimary])
                if let summary {
                    Text(summary).font(metrics.typography.callout).foregroundStyle(palette[.fgSecondary])
                        .lumenWrapsWithoutTruncating()
                }
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension View {
    /// Makes this view a tab of a Settings `TabView` with a colored category tile, as in System
    /// Settings' preference panes. Use it inside `Settings { TabView { … } }`.
    func lumenSettingsTab(_ title: String, systemImage: String, hue: LumenToken) -> some View {
        modifier(LumenSettingsTabModifier(title: title, systemImage: systemImage, hue: hue))
    }
}

private struct LumenSettingsTabModifier: ViewModifier {
    let title: String
    let systemImage: String
    let hue: LumenToken
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.tabItem {
            Label {
                Text(title)
            } icon: {
                if let image = LumenIconTile.image(systemImage, hue: hue, size: 22, colorScheme: colorScheme) {
                    Image(nsImage: image)
                } else {
                    LumenSymbol(systemImage)
                }
            }
        }
    }
}

// MARK: Sidebar layout

/// One category in a sidebar-style settings window.
public struct LumenSettingsCategory: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let hue: LumenToken
    /// Extra words the search field matches, such as the names of the settings inside.
    public let keywords: [String]
    /// The names of the settings in the pane, as their rows title them. A search lists the ones that
    /// match under the category, and the pane marks those rows.
    public var settings: [String] = []
    public let content: () -> AnyView

    public init<Content: View>(id: String, title: String, systemImage: String, hue: LumenToken, keywords: [String] = [],
                               @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.hue = hue
        self.keywords = keywords
        self.content = { AnyView(content()) }
    }

    public init<Content: View>(id: String, title: String, systemImage: String, hue: LumenToken, keywords: [String] = [],
                               settings: [String], @ViewBuilder content: @escaping () -> Content) {
        self.init(id: id, title: title, systemImage: systemImage, hue: hue, keywords: keywords, content: content)
        self.settings = settings
    }

    /// Whether `query` matches the title, a keyword or a setting (case-insensitive; empty matches all).
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty || ([title] + keywords + settings).contains { $0.lowercased().contains(needle) }
    }

    /// The settings whose names contain `query`, in order.
    public func matchingSettings(_ query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return settings.filter { $0.lowercased().contains(needle) }
    }
}

extension EnvironmentValues {
    /// The Settings search, so rows whose titles match can mark themselves.
    @Entry var lumenSettingsQuery = ""
}

/// A complete settings window for two or many categories. Use with
/// `Settings { LumenSettingsSidebarView(categories) }.lumenSettingsScene()`.
/// Owns sidebar surfaces, search, selection history, navigation chrome, tint and content sizing.
/// Keep the pane's header; do not add a second toolbar title or rebuild this root from its parts.
public struct LumenSettingsSidebarView: View {
    private let categories: [LumenSettingsCategory]
    private var externalSelection: Binding<String?>?
    @State private var selection: String?
    @State private var query = ""
    @FocusState private var sidebarFocused: Bool
    @State private var history = LumenSettingsHistory()
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var measuredHeights: [String: CGFloat] = [:]
    @State private var fallbackHeights: [String: CGFloat] = [:]
    private var sizingHeights: [String: CGFloat] {
        fallbackHeights.merging(measuredHeights, uniquingKeysWith: { _, natural in natural })
    }
    private var initialIdealSize: CGSize {
        LumenSettingsSizing.idealSize(heights: Array(sizingHeights.values), preferred: preferredSize, visibleHeight: nil)
    }
    @Environment(\.lumenSettingsPreferredSize) private var preferredSize
    @Environment(\.lumenSettingsSizesWindow) private var sizesWindow

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenResolvedChromeStyle) private var chrome
    @Environment(\.controlActiveState) private var activeState

    public static let sidebarMinWidth: CGFloat = 200
    public static let detailMinWidth: CGFloat = 360
    /// Minimum width accommodates the sidebar, pane and native navigation controls.
    public static let windowMinWidth: CGFloat = 680
    public static let windowIdealWidth: CGFloat = 820
    /// Retained for source compatibility; initial height now follows pane content.
    @available(*, deprecated, message: "Settings now measures pane content with a 480 pt floor. Use lumenSettingsPreferredSize(_:) for a host preference.")
    public static let stableContentHeight: CGFloat = 320
    @available(*, deprecated, message: "The initial height cap follows the visible screen; users can resize the window.")
    public static let windowMaxHeight: CGFloat = 720

    /// `selection` is the initial category ID. Unknown IDs fall back to the first category.
    public init(_ categories: [LumenSettingsCategory], selection: String? = nil) {
        self.categories = categories
        _selection = State(initialValue: Self.validSelection(selection, in: categories))
    }

    /// Programmatic selection shares the sidebar's navigation history. Unknown or removed IDs
    /// fall back to the first category; an empty category collection shows the empty state.
    public init(_ categories: [LumenSettingsCategory], selection: Binding<String?>) {
        self.init(categories, selection: selection.wrappedValue)
        externalSelection = selection
    }

    /// Explicit initial-selection spelling for hosts that also use binding-based selection.
    public init(_ categories: [LumenSettingsCategory], initialSelection: String?) {
        self.init(categories, selection: initialSelection)
    }

    static func validSelection(_ id: String?, in categories: [LumenSettingsCategory]) -> String? {
        categories.first(where: { $0.id == id })?.id ?? categories.first?.id
    }

    private var categorySelection: Binding<String?> {
        Binding(get: { selection }, set: { visit($0) })
    }

    private func visit(_ next: String?) {
        guard next != selection else { return }
        history.visit(from: categories.contains(where: { $0.id == selection }) ? selection : nil, to: next)
        selection = next
    }

    private func move(backward: Bool) {
        let next = backward ? history.goBack(from: selection) : history.goForward(from: selection)
        guard let next else { return }
        // A historical category remains reachable even when the current query hides it.
        if categories.first(where: { $0.id == next })?.matches(query) == false { query = "" }
        selection = next
    }

    public var body: some View {
        let shown = categories.filter { $0.matches(query) }
        NavigationSplitView(columnVisibility: $visibility) {
            List(shown, selection: categorySelection) { category in
                Label {
                    VStack(alignment: .leading, spacing: metrics.spacing.s1) {
                        Text(category.title).font(metrics.typography.body).fontWeight(.regular)
                        let found = category.matchingSettings(query)
                        if !found.isEmpty {
                            Text(found.joined(separator: " · ")).font(metrics.typography.caption)
                                .foregroundStyle(palette[selection == category.id && activeState == .key
                                    ? .accentFilledForeground : .sidebarSecondaryForeground]).lineLimit(2)
                                .help(found.joined(separator: " · "))
                        }
                    }
                } icon: {
                    LumenIconTile(category.systemImage, hue: category.hue, size: metrics.layout.tileRow)
                }
                .foregroundStyle(palette[selection == category.id && activeState == .key
                    ? .accentFilledForeground : .sidebarForeground])
                .frame(minHeight: metrics.layout.settingsRowHeight)
                .listRowInsets(EdgeInsets(top: 0, leading: metrics.spacing.s5,
                                          bottom: 0, trailing: metrics.spacing.s5))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: metrics.radius.sm, style: .continuous)
                        .fill(selection == category.id
                              ? palette[activeState == .key ? .accentFilled : .settingsRowSelectedInactive]
                              : .clear)
                        .padding(.horizontal, (metrics.spacing.s4 + metrics.spacing.s5) / 2)
                )
                .tag(category.id)
            }
            .listStyle(.sidebar)
            .focused($sidebarFocused)
            .environment(\.defaultMinListRowHeight, metrics.layout.settingsRowHeight)
            .scrollContentBackground(.automatic)
            .searchable(text: $query, placement: .sidebar, prompt: "Search Settings")
            .onChange(of: query) { _, text in
                let matching = categories.filter { $0.matches(text) }
                if !matching.contains(where: { $0.id == selection }) { visit(matching.first?.id) }
            }
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(id: "lumen.settings.sidebar", placement: .navigation) {
                    Button {
                        visibility = visibility == .detailOnly ? .all : .detailOnly
                    } label: {
                        navigationLabel("Sidebar", systemImage: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                    .help("Show or hide sidebar")
                }
                .lumenToolbarPlatter(chrome)
            }
            .navigationSplitViewColumnWidth(min: Self.sidebarMinWidth, ideal: 220, max: 280)
        } detail: {
            ZStack(alignment: .topLeading) {
                // Keep each category mounted once: every natural height is measured at the same
                // detail width, without duplicate onAppear/task side effects when navigating.
                ForEach(categories) { category in
                    category.content()
                        .modifier(LumenSettingsNaturalHeight(isFallback: true))
                        .environment(\.lumenSettingsMeasurementID, category.id)
                        .lumenSettingsQuery(query)
                        .opacity(category.id == selection && category.matches(query) ? 1 : 0)
                        .allowsHitTesting(category.id == selection && category.matches(query))
                        .accessibilityHidden(category.id != selection || !category.matches(query))
                }
                if !shown.contains(where: { $0.id == selection }) {
                    LumenEmptyState(systemImage: "magnifyingglass", title: "No matching settings",
                                    message: "Try a different word, or clear the search.", actionTitle: "Clear search") { query = "" }
                }
            }
            .frame(minWidth: Self.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            .background(palette[.panelBackground])
            .navigationSplitViewColumnWidth(min: Self.detailMinWidth, ideal: Self.detailMinWidth + 120)
        }
        .navigationSplitViewStyle(.balanced)
        .defaultFocus($sidebarFocused, true, priority: .userInitiated)
        .toolbar {
            ToolbarItem(id: "lumen.settings.history", placement: .navigation) {
                HStack(spacing: 0) {
                    Button { move(backward: true) } label: {
                        navigationLabel("Back", systemImage: "chevron.backward")
                    }
                    .disabled(!history.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")
                    Button { move(backward: false) } label: {
                        navigationLabel("Forward", systemImage: "chevron.forward")
                    }
                    .disabled(!history.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Forward")
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
            }
            .lumenToolbarPlatter(chrome)
        }
        .environment(\.lumenSettingsWindow, true)
        .preference(key: LumenSettingsRootKey.self, value: true)
        .lumenWindowChrome()
        .background(LumenSettingsNativeChrome(heights: sizingHeights, categoryIDs: categories.map(\.id),
                                               preferred: preferredSize, sizesWindow: sizesWindow))
        .navigationTitle(categories.first(where: { $0.id == selection })?.title ?? "Settings")
        .frame(minWidth: Self.windowMinWidth, idealWidth: initialIdealSize.width,
               minHeight: LumenSettingsSizing.minimumHeight,
               idealHeight: initialIdealSize.height)
        .lumenOwnsWindowTop()
        .lumenScaffoldMargin(metrics.spacing.s6)
        .onPreferenceChange(LumenSettingsNaturalHeightKey.self) { measuredHeights = $0 }
        .onPreferenceChange(LumenSettingsFallbackHeightKey.self) { fallbackHeights = $0 }
        .tint(palette[.accent])
        .onAppear {
            sidebarFocused = true
            synchronizeSelection()
        }
        .onChange(of: selection) { _, _ in
            sidebarFocused = true
            synchronizeSelection()
        }
        .onChange(of: externalSelection?.wrappedValue) { _, next in
            guard externalSelection != nil, next != selection else { return }
            let valid = Self.validSelection(next, in: categories)
            if categories.first(where: { $0.id == valid })?.matches(query) == false { query = "" }
            visit(valid)
            synchronizeSelection()
        }
        .onChange(of: categories.map(\.id)) { _, ids in
            history.retain(ids)
            if !ids.contains(selection ?? "") {
                visit(categories.first(where: { $0.matches(query) })?.id)
            }
            history.discardCurrent(selection)
        }
    }

    private func synchronizeSelection() {
        if let externalSelection, externalSelection.wrappedValue != selection {
            externalSelection.wrappedValue = selection
        }
    }

    private func navigationLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
    }
}

public extension View {
    /// Supplies a search query to settings rows in a custom embedded pane. A stock settings
    /// window propagates its search automatically; hosts need not rebuild its sidebar.
    func lumenSettingsQuery(_ query: String) -> some View {
        environment(\.lumenSettingsQuery, query)
    }
}

public extension Scene {
    /// Completes the stock settings root's window contract. The native compact toolbar puts the
    /// category navigation title beside Back/Forward. The root owns its palette-derived tint,
    /// because Settings does not inherit the main window's view environment.
    func lumenSettingsScene() -> some Scene {
        windowStyle(.titleBar)
            .environment(\.lumenSettingsWindow, true)
            .windowToolbarStyle(.unified)
            .defaultSize(width: LumenSettingsSidebarView.windowIdealWidth,
                         height: LumenSettingsSizing.minimumHeight)
            .windowResizability(.contentMinSize)
    }
}

/// Owns the settings content size and sidebar selection appearance. Native toolbar style
/// belongs to the shared palette-root bridge, including for app-built Settings roots.
private struct LumenSettingsNativeChrome: NSViewRepresentable {
    let heights: [String: CGFloat]
    let categoryIDs: [String]
    let preferred: CGSize?
    let sizesWindow: Bool
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.updateSizing(heights: heights, categoryIDs: categoryIDs, preferred: preferred, enabled: sizesWindow)
        nsView.scheduleConfiguration()
    }
    static func dismantleNSView(_ nsView: ChromeView, coordinator: ()) { nsView.detach(removingFromHierarchy: true) }

    final class ChromeView: NSView, LumenOwnedInkSource {
        // This bridge configures native chrome and sizing; its transparent frame paints no ink.
        var ownedInkRects: [CGRect] { [] }
        private weak var ownedWindow: NSWindow?
        private var scheduled = false
        private weak var sidebarTable: NSTableView?
        private var originalSelectionStyle: NSTableView.SelectionHighlightStyle?
        private var heights: [String: CGFloat] = [:]
        private var categoryIDs: [String] = []
        private var preferred: CGSize?
        private var sizesWindow = true
        private var sizedWindow = false
        private var pendingSize: DispatchWorkItem?

        func updateSizing(heights: [String: CGFloat], categoryIDs: [String], preferred: CGSize?, enabled: Bool) {
            guard self.heights != heights || self.categoryIDs != categoryIDs || self.preferred != preferred || sizesWindow != enabled else { return }
            self.heights = heights
            self.categoryIDs = categoryIDs
            self.preferred = preferred
            sizesWindow = enabled
            // updateNSView only copies inputs; native geometry changes run on the next turn.
            scheduleConfiguration()
        }

        private func scheduleInitialSize() {
            pendingSize?.cancel()
            guard sizesWindow, !sizedWindow, let window = ownedWindow else { return }
            // Resolve a host's width before measuring wrapped pane content.
            let width = LumenSettingsSizing.idealSize(heights: [], preferred: preferred, visibleHeight: nil).width
            if preferred != nil, abs(window.contentLayoutRect.width - width) > 0.5 {
                var frame = window.frame
                frame.size.width = width
                window.setFrame(frame, display: false)
            }
            guard categoryIDs.allSatisfy({ (heights[$0] ?? 0) > 0 }) else { return }
            let work = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window, window === self.ownedWindow, !window.inLiveResize,
                      self.sizesWindow, !self.sizedWindow else { return }
                self.sizedWindow = true
                let band = window.frame.height - window.contentLayoutRect.height
                let size = LumenSettingsSizing.idealSize(heights: Array(self.heights.values), preferred: self.preferred,
                                                       visibleHeight: window.screen?.visibleFrame.height, toolbarHeight: band)
                var frame = window.frame
                frame.origin.y += frame.height - size.height - band
                frame.size = CGSize(width: size.width, height: size.height + band)
                if let screen = window.screen {
                    frame.origin.y = max(screen.visibleFrame.minY, min(frame.origin.y, screen.visibleFrame.maxY - frame.height))
                }
                window.setFrame(frame, display: false)
            }
            pendingSize = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== ownedWindow else { return }
            detach()
            guard let window else { return }
            ownedWindow = window
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard let window = self.ownedWindow, window === self.window else { return }
                self.configureSidebar(in: window.contentView)
                self.scheduleInitialSize()
            }
        }

        private func sourceList(in view: NSView?) -> NSTableView? {
            guard let view else { return nil }
            if let table = view as? NSTableView, table.effectiveStyle == .sourceList { return table }
            return view.subviews.lazy.compactMap { self.sourceList(in: $0) }.first
        }

        private func configureSidebar(in view: NSView?) {
            guard let table = sourceList(in: view) else { return }
            if table !== sidebarTable {
                restoreSelectionStyle()
                sidebarTable = table
                originalSelectionStyle = table.selectionHighlightStyle
                // The native table attaches after SwiftUI evaluates default focus. Establish the
                // same initial target once, after the detail fields have joined the window.
                ownedWindow?.initialFirstResponder = table
                ownedWindow?.makeFirstResponder(table)
            }
            // Keep native selection, keyboard navigation and table semantics. Only the fill
            // comes from the row's palette role instead of AppKit's grey selection material.
            table.selectionHighlightStyle = .none
        }

        private func restoreSelectionStyle(removingFromHierarchy: Bool = false) {
            defer {
                sidebarTable = nil
                originalSelectionStyle = nil
            }
            // A selection-style assignment reloads AppKit's rows. During dismantle that can
            // reenter SwiftUI's already-invalidating row graph, even before window becomes nil.
            guard !removingFromHierarchy, let table = sidebarTable, let originalSelectionStyle,
                  let window = table.window, window === ownedWindow,
                  let parent = table.superview, let content = window.contentView,
                  table.isDescendant(of: content), table.selectionHighlightStyle == .none else { return }
            DispatchQueue.main.async { [weak self, weak table, weak window, weak parent] in
                guard let self, let table, let window, let parent,
                      self.ownedWindow === window, self.window === window,
                      self.sidebarTable !== table, table.window === window,
                      table.superview === parent, let content = window.contentView,
                      table.isDescendant(of: content), table.selectionHighlightStyle == .none else { return }
                table.selectionHighlightStyle = originalSelectionStyle
            }
        }

        func detach(removingFromHierarchy: Bool = false) {
            pendingSize?.cancel()
            pendingSize = nil
            sizedWindow = false
            restoreSelectionStyle(removingFromHierarchy: removingFromHierarchy || window !== ownedWindow)
            ownedWindow = nil
        }
    }
}

/// Value history tracks category destinations independently of the host binding.
struct LumenSettingsHistory {
    private(set) var back: [String] = []
    private(set) var forward: [String] = []
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    mutating func visit(from current: String?, to next: String?) {
        guard current != next else { return }
        if let current { back.append(current) }
        forward.removeAll()
    }
    mutating func goBack(from current: String?) -> String? {
        while back.last == current, !back.isEmpty { back.removeLast() }
        guard let previous = back.popLast() else { return nil }
        if let current { forward.append(current) }
        return previous
    }
    mutating func goForward(from current: String?) -> String? {
        while forward.last == current, !forward.isEmpty { forward.removeLast() }
        guard let next = forward.popLast() else { return nil }
        if let current { back.append(current) }
        return next
    }
    mutating func discardCurrent(_ current: String?) {
        while back.last == current, !back.isEmpty { back.removeLast() }
        while forward.last == current, !forward.isEmpty { forward.removeLast() }
    }
    mutating func retain(_ ids: [String]) {
        let valid = Set(ids)
        back.removeAll { !valid.contains($0) }
        forward.removeAll { !valid.contains($0) }
    }
}

/// A ready-made Appearance pane: row density, the system accent switch and the theme gallery,
/// each applied at once and saved through the store (density and accent persist only in a store
/// that persists its selection). Pair it with `.lumenDensityRoot(store:)` on the app's windows.
public struct LumenAppearanceSettings: View {
    /// The store passed to `init(store:showsGallery:)`; `nil` uses the window's (`\.lumenStore`).
    private let explicitStore: LumenThemeStore?
    private let showsGallery: Bool
    private var textScale: Binding<Double>? = nil
    private var textScaleSteps: [Double] = []
    @Environment(\.lumenStore) private var environmentStore

    /// Settings for the store of the window they appear in: the one `.lumenPaletteRoot(store:)`
    /// injected.
    /// - Parameter showsGallery: `false` for apps that show the gallery in a pane of its own.
    public init(showsGallery: Bool = true) {
        explicitStore = nil
        self.showsGallery = showsGallery
    }

    /// Settings for `store`. Without a store argument, `init(showsGallery:)` (the window's store)
    /// is chosen.
    /// - Parameter showsGallery: `false` for apps that show the gallery in a pane of its own.
    public init(store: LumenThemeStore = .active, showsGallery: Bool = true) {
        explicitStore = store
        self.showsGallery = showsGallery
    }

    /// Settings for the window's store, with an app-owned text-scale preference.
    /// Apply the preference with `.lumenTextScale(_:)` at each window root.
    /// - Parameter textScaleSteps: Distinct scale choices, in display order.
    public init(textScale: Binding<Double>, textScaleSteps: [Double] = [1, 1.15, 1.3],
                showsGallery: Bool = true) {
        explicitStore = nil
        self.showsGallery = showsGallery
        self.textScale = textScale
        self.textScaleSteps = textScaleSteps
    }

    /// Settings for `store`, with an app-owned text-scale preference.
    /// Apply the preference with `.lumenTextScale(_:)` at each window root.
    /// - Parameter textScaleSteps: Distinct scale choices, in display order.
    public init(store: LumenThemeStore, textScale: Binding<Double>,
                textScaleSteps: [Double] = [1, 1.15, 1.3], showsGallery: Bool = true) {
        explicitStore = store
        self.showsGallery = showsGallery
        self.textScale = textScale
        self.textScaleSteps = textScaleSteps
    }

    public var body: some View {
        let store = explicitStore ?? environmentStore
        // Keyed by the store, so the density storage follows a store swapped in the environment.
        LumenAppearanceSettingsForm(store: store, showsGallery: showsGallery,
                                    textScale: textScale, textScaleSteps: textScaleSteps)
            .id(ObjectIdentifier(store))
    }
}

private struct LumenAppearanceSettingsForm: View {
    let store: LumenThemeStore
    let showsGallery: Bool
    let textScale: Binding<Double>?
    let textScaleSteps: [Double]
    @AppStorage private var densityRaw: String

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    init(store: LumenThemeStore, showsGallery: Bool, textScale: Binding<Double>?, textScaleSteps: [Double]) {
        self.store = store
        self.showsGallery = showsGallery
        self.textScale = textScale
        self.textScaleSteps = textScaleSteps
        _densityRaw = AppStorage(wrappedValue: LumenDensity.regular.rawValue, store.configuration.densityDefaultsKey,
                                 store: store.configuration.defaults)
    }

    var body: some View {
        Form {
            Section {
                if let textScale {
                    LabeledContent("Text scale") {
                        LumenModeSwitcher(selection: textScale, options: textScaleSteps, style: .pill,
                                          title: { "\($0)×" })
                            .lumenModeSwitcherPlacement(.content)
                    }
                }
                // Lumen's own controls in Lumen's own settings: the pill switcher and the themed checkbox.
                LabeledContent("Density") {
                    LumenModeSwitcher(selection: $densityRaw, options: LumenDensity.allCases.map(\.rawValue), style: .pill,
                                      title: { LumenDensity(rawValue: $0)?.label ?? $0 })
                        .lumenModeSwitcherPlacement(.content)
                }
                .disabled(!store.persistsSelection)
                Toggle("Use the system accent color", isOn: Binding(get: { store.usesSystemAccent }, set: { store.setUsesSystemAccent($0) }))
                    .toggleStyle(.lumenCheckbox)
            } header: {
                LumenSettingsHeader("Appearance", systemImage: "paintpalette.fill", hue: .hueViolet,
                                    summary: "Theme, accent and how tightly rows are packed.")
                    .padding(.bottom, metrics.spacing.s3)
            }
            if showsGallery {
                Section("Theme") { LumenThemeGallery(store: store) }
            }
        }
        .formStyle(.grouped)
        .contentMargins(.bottom, metrics.spacing.s9, for: .scrollContent)
        .modifier(LumenSettingsFormMeasure())
        .scrollContentBackground(.hidden)
        .background(palette[.panelBackground])
    }
}

extension EnvironmentValues {
    @Entry var lumenSettingsPaneOwnsMeasure = false
}
