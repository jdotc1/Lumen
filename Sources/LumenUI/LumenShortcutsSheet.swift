import SwiftUI
import LumenTokens

/// One command and its key equivalent, shared by an app's menus and shortcut reference.
public struct LumenShortcut: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let shortcut: KeyboardShortcut

    /// Pass an explicit stable ID when titles can change while the sheet is open.
    public init(id: String? = nil, title: String, shortcut: KeyboardShortcut) {
        self.id = id ?? title
        self.title = title
        self.shortcut = shortcut
    }
}

/// A named menu or task family in the keyboard reference.
public struct LumenShortcutGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let shortcuts: [LumenShortcut]

    public init(id: String? = nil, title: String, shortcuts: [LumenShortcut]) {
        self.id = id ?? title
        self.title = title
        self.shortcuts = shortcuts
    }
}

/// A searchable keyboard reference for a sheet or utility window. Groups reflow into columns;
/// long command titles wrap and large command sets scroll. Sheets remain opaque in glass chrome.
public struct LumenShortcutsSheet: View {
    private let groups: [LumenShortcutGroup]
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    @Environment(\.lumenShortcutsPreferredSize) private var preferredSize

    public init(groups: [LumenShortcutGroup]) { self.groups = groups }

    public var body: some View {
        let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
        LumenShortcutsSizingLayout(preferred: preferredSize ?? CGSize(width: (groups.count > 1 ? 640 : 360) * growth, height: 560 * growth), minimumWidth: 320 * growth) {
            VStack(alignment: .leading, spacing: metrics.spacing.s4) {
                HStack(spacing: metrics.spacing.s3) {
                    LumenIconTile("keyboard", hue: .hueBlue, size: metrics.layout.tileHeader)
                    Text("Keyboard Shortcuts")
                        .font(metrics.typography.headline)
                        .foregroundStyle(palette[.fgPrimary])
                        .lumenWrapsWithoutTruncating()
                    Spacer(minLength: 0)
                }
                LumenTextField("Search shortcuts", text: $query)
                ViewThatFits(in: .vertical) {
                    shortcutColumns.fixedSize(horizontal: false, vertical: true)
                    ScrollView { shortcutColumns }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { dismiss() }
                        .buttonStyle(.lumenPrimary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(metrics.spacing.s4)
            .lumenColumnContent("Keyboard Shortcuts sheet")
        }
        .lumenRaisedGround()
        .background(palette[.bgElevated])
        .lumenWindowCornerClip()
    }

    private var shortcutColumns: some View {
        let filtered = Self.filtered(groups, query: query)
        return VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            if filtered.isEmpty {
                Text("No matching shortcuts")
                    .font(metrics.typography.body)
                    .foregroundStyle(palette[.fgSecondary])
                    .lumenWrapsWithoutTruncating()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260 * max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)), spacing: metrics.spacing.s5, alignment: .top)],
                      alignment: .leading, spacing: metrics.spacing.s5) {
                ForEach(filtered) { group in
                    LumenShortcutGroupColumn(group: group)
                }
            }
        }
        .lumenColumnContent("Keyboard Shortcut groups")
    }

    static func filtered(_ groups: [LumenShortcutGroup], query: String) -> [LumenShortcutGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.shortcuts.filter { $0.title.localizedStandardContains(query) }
            return matches.isEmpty ? nil : LumenShortcutGroup(id: group.id, title: group.title, shortcuts: matches)
        }
    }
}

private struct LumenShortcutGroupColumn: View {
    let group: LumenShortcutGroup
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s3) {
            Text(group.title).lumenSectionLabel().lumenWrapsWithoutTruncating()
            ForEach(group.shortcuts) { shortcut in
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.s3) {
                    Text(shortcut.title)
                        .font(metrics.typography.body)
                        .foregroundStyle(palette[.fgPrimary])
                        .lumenWrapsWithoutTruncating()
                    Spacer(minLength: metrics.spacing.s2)
                    LumenKeycap(shortcut.shortcut).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

public extension FocusedValues {
    /// The focused window's keyboard-reference presentation binding.
    @Entry var lumenShortcutsSheet: Binding<Bool>?
}

/// Installs Help › Keyboard Shortcuts (⌘/). Add it once beside `LumenViewCommands`, and attach
/// `.lumenShortcutsSheet(groups:)` to each participating window's root.
public struct LumenShortcutsCommands: Commands {
    @FocusedValue(\.lumenShortcutsSheet) private var isPresented

    public init() {}

    public static var shortcutGroups: [LumenShortcutGroup] {
        [LumenShortcutGroup(title: "Help", shortcuts: [
            LumenShortcut(title: "Keyboard Shortcuts", shortcut: LumenShortcuts.keyboardShortcuts)
        ])]
    }

    public var body: some Commands {
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { isPresented?.wrappedValue = true }
                .keyboardShortcut(LumenShortcuts.keyboardShortcuts)
                .disabled(isPresented == nil)
        }
    }
}

public extension View {
    /// Owns keyboard-reference presentation for this window. The menu command is the only owner
    /// of ⌘/; the host publishes only a focused binding and adds no competing keyboard shortcut.
    func lumenShortcutsSheet(groups: [LumenShortcutGroup]) -> some View {
        modifier(LumenShortcutsSheetHost(groups: groups))
    }
}

private struct LumenShortcutsSheetHost: ViewModifier {
    let groups: [LumenShortcutGroup]
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.lumenShortcutsSheet, $isPresented)
            .sheet(isPresented: $isPresented) {
                LumenShortcutsSheet(groups: groups)
            }
    }
}

extension EnvironmentValues {
    @Entry var lumenShortcutsPreferredSize: CGSize? = nil
}

public extension View {
    /// Sets the keyboard reference's preferred opening envelope. A host's proposed size
    /// takes precedence; long content scrolls within the available height.
    func lumenShortcutsPreferredSize(_ size: CGSize) -> some View {
        environment(\.lumenShortcutsPreferredSize, size)
    }
}

/// Supply an opening height only when the host has not proposed one. Unlike a maximum frame,
/// this lets a resizable host expand the viewport while sparse sheets keep their natural height.
struct LumenShortcutsSizingLayout: Layout {
    var preferred: CGSize
    var minimumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        let width = max(minimumWidth, proposedWidth ?? (preferred.width.isFinite ? preferred.width : minimumWidth))
        let height = max(0, proposedHeight ?? (preferred.height.isFinite ? preferred.height : 560))
        let natural = child.sizeThatFits(ProposedViewSize(width: width, height: height))
        return CGSize(width: width, height: proposedHeight ?? min(height, natural.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
