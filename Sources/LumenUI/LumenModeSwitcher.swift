import AppKit
import SwiftUI
import LumenTokens

/// How a mode switcher draws.
public enum LumenModeSwitcherStyle: Sendable, CaseIterable {
    /// Each mode with its glyph in a colored tile; the current one raised on a card. Lumen's
    /// default's editor modes.
    case tiles
    /// A recessed rounded track with the current mode in a native-style selected pill.
    case pill
    /// Compact labels with the same rounded selection as document tabs. The legacy case name is preserved.
    case underline
}

/// Where a mode switcher sits, which decides its ink: the toolbar's (`toolbar.foreground`, dimmed
/// with the toolbar when the window is inactive) or the content's (`fg.primary`/`fg.secondary`, no
/// toolbar dimming), as in a content tab bar, a pane header or a settings row.
public enum LumenModeSwitcherPlacement: Sendable, CaseIterable {
    /// The toolbar inside a toolbar-hosted top bar, and for the `tiles` style; the content elsewhere.
    case automatic
    /// A toolbar or top bar.
    case toolbar
    /// A pane: a content tab bar (`LumenContentTabBar`), a pane header, a settings row.
    case content
}

public extension View {
    /// Tells the mode switchers inside where they sit (`LumenModeSwitcherPlacement`), when
    /// `.automatic` guesses wrong: an `underline` switcher in a top bar under the title bar, say.
    func lumenModeSwitcherPlacement(_ placement: LumenModeSwitcherPlacement) -> some View {
        environment(\.lumenModeSwitcherPlacement, placement)
    }
}

extension EnvironmentValues {
    @Entry var lumenModeSwitcherPlacement: LumenModeSwitcherPlacement = .automatic
    @Entry var lumenTabStripName: String = "mode"
}

/// Switches between a few views of the same content (Disassembly, Pseudocode, Graph, Hex), in a
/// toolbar or top bar: the Lumen replacement for a segmented picker. It takes the same things a
/// `Picker` does (a binding and the options) plus how each option reads, so swapping one in is one
/// line. Labels collapse to glyphs when space is tight; never clipped.
///
/// It's one keyboard stop: ←/→ move between modes. It registers no shortcuts: give modes menu
/// commands (⌃⌘1…, say) so the menu owns them.
public struct LumenModeSwitcher<Mode: Hashable>: View {
    @Binding private var selection: Mode
    private let options: [Mode]
    private let title: (Mode) -> String
    private let systemImage: (Mode) -> String?
    private let hue: (Mode) -> LumenToken?
    private let style: LumenModeSwitcherStyle

    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.lumenModeSwitcherPlacement) private var placement
    @Environment(\.lumenTabStripName) private var tabStripName
    @Environment(\.lumenTopBarHostsInToolbar) private var hostsInToolbar
    @Environment(\.lumenToolbarCompact) private var toolbarCompact
    @FocusState private var focused: Bool
    @State private var hovered: Mode?

    /// - Parameters:
    ///   - title: each mode's name.
    ///   - systemImage: each mode's glyph or SF Symbol, or `nil` for text only.
    ///   - hue: each mode's tile color in the `tiles` style (`nil` uses the accent).
    public init(selection: Binding<Mode>, options: [Mode], style: LumenModeSwitcherStyle = .tiles,
                title: @escaping (Mode) -> String, systemImage: @escaping (Mode) -> String? = { _ in nil },
                hue: @escaping (Mode) -> LumenToken? = { _ in nil }) {
        _selection = selection
        self.options = options
        self.style = style
        self.title = title
        self.systemImage = systemImage
        self.hue = hue
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsLabels: true)
            row(showsLabels: false)
            ScrollView(.horizontal) { row(showsLabels: true) }
                .fixedSize(horizontal: false, vertical: true)
        }
        // Offered its width before flexible neighbors (drag regions, spacers), so labels show
        // whenever the bar has room instead of collapsing to glyphs at any width.
        .layoutPriority(1)
        .lumenSelectionGroup(options, selection: $selection, focused: $focused)
        .lumenDisabledFade(isEnabled)
        .lumenTileBacklight()
        .lumenBacklightContainer("Mode switcher")
        .accessibilityElement(children: .contain)
        .accessibilityValue(title(selection))
    }

    private func row(showsLabels: Bool) -> some View {
        HStack(spacing: metrics.spacing.s1) {
            ForEach(options, id: \.self) { mode in
                segment(mode, showsLabels: showsLabels)
            }
        }
        .padding(style == .pill ? metrics.layout.pillRim : 0)
        .background {
            if style == .pill {
                // The track is a field's well with a control's edge, so it reads in light themes too
                // (at 85% over the panel it all but vanished).
                LumenTabChrome.shape(radius: LumenTabChrome.radius(metrics: metrics)).fill(palette[.bgInset])
                    .overlay { LumenTabChrome.shape(radius: LumenTabChrome.radius(metrics: metrics)).strokeBorder(palette[.borderDefault], lineWidth: metrics.stroke.hairline) }
            }
        }
        .fixedSize()
        .lumenAnimation(.selection, value: selection)
    }

    private func segment(_ mode: Mode, showsLabels: Bool) -> some View {
        let selected = mode == selection
        return Button { selection = mode } label: {
            HStack(spacing: metrics.spacing.s2) {
                if let symbol = systemImage(mode) {
                    if style == .tiles {
                        // Full color: the segment's plate marks the selection.
                        // Without its label the tile is the whole control, so it takes the control size.
                        LumenIconTile(symbol, hue: hue(mode) ?? .accent,
                                      size: showsLabels ? metrics.layout.tileMode : max(metrics.layout.tileMode, metrics.layout.tileTool))
                            .lumenIconRole(showsLabels ? .inline : .control)
                    } else {
                        LumenSymbol(symbol)
                            .font(.system(size: metrics.layout.paneActionGlyph, weight: selected ? .semibold : .regular))
                    }
                }
                if showsLabels || systemImage(mode) == nil {
                    Text(title(mode))
                        // A one-line control's 13 pt in every style: one component, one label size.
                        .font(metrics.typography.body.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .lumenNeverTruncates(title(mode))
                        .fixedSize()
                }
            }
            .foregroundStyle(foreground(selected: selected, hovered: hovered == mode))
            .modifier(LumenTabActivity())
            .padding(.horizontal, metrics.spacing.s3)
            // The pill is `controlHeight` overall, rim included, so it sits level with pop-ups and
            // fields in a settings row.
            .frame(minWidth: style == .pill ? pillSegmentHeight : metrics.layout.toolbarButton,
                   minHeight: style == .pill ? pillSegmentHeight : metrics.layout.toolbarButton)
            .background {
                LumenTabChrome(strip: tabStripName, selected: selected, hovered: hovered == mode)
            }
            .lumenGroupFocusRing(focused && selected, cornerRadius: LumenTabChrome.radius(metrics: metrics))
            .contentShape(.rect)
        }
        .buttonStyle(.lumenBare)
        .focusable(false)
        .onHover { hovered = $0 ? mode : (hovered == mode ? nil : hovered) }
        .help(title(mode))
        .accessibilityLabel(title(mode))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// A pill segment: the control height less the rim above and below.
    private var pillSegmentHeight: CGFloat { metrics.layout.controlHeight - 2 * metrics.layout.pillRim }

    /// Whether it draws in the toolbar's ink (with the toolbar's inactive dimming) or the content's.
    var inToolbar: Bool {
        switch placement {
        case .toolbar: return true
        case .content: return false
        case .automatic: return hostsInToolbar || toolbarCompact || style == .tiles
        }
    }

    private func foreground(selected: Bool, hovered: Bool) -> Color {
        let strong: LumenToken = inToolbar ? .toolbarForeground : .fgPrimary
        if selected {
            return palette[strong]
        }
        return palette[hovered ? strong : .fgSecondary]
    }
}

public extension LumenModeSwitcher where Mode: CaseIterable, Mode.AllCases == [Mode] {
    /// Every case of `Mode`, in declaration order.
    init(selection: Binding<Mode>, style: LumenModeSwitcherStyle = .tiles, title: @escaping (Mode) -> String,
         systemImage: @escaping (Mode) -> String? = { _ in nil }, hue: @escaping (Mode) -> LumenToken? = { _ in nil }) {
        self.init(selection: selection, options: Mode.allCases, style: style, title: title, systemImage: systemImage, hue: hue)
    }
}
