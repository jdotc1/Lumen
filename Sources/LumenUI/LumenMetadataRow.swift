import AppKit
import SwiftUI

/// A label and a selectable value whose text wraps at any character and is never truncated.
///
/// Use it for long opaque tokens (hashes, file paths, bundle identifiers, long hex) where
/// `LumenPropertyRow`'s word-boundary wrapping and line limit would shorten or cut the value. The
/// value keeps its original characters (no inserted break hints), so selecting and copying are
/// exact. The row follows Lumen text scale and the layout direction, and shares `LumenPropertyRow`'s
/// label column so the two align in one inspector.
public struct LumenMetadataRow: View {
    let label: String
    let value: String
    var monospaced: Bool
    var labelWidth: CGFloat?
    var showsCopyButton: Bool
    @State private var isHovered = false
    @FocusState private var copyFocused: Bool
    @Environment(\.lumenCodeFont) private var codeFont
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.fontResolutionContext) private var fontContext

    /// - Parameters:
    ///   - label: the short name of the value.
    ///   - value: the text to show; it wraps at any character and is selectable.
    ///   - monospaced: whether the value uses the code font (the default for identifiers).
    ///   - labelWidth: an exact label column; `nil` scales `propertyLabelWidth` with typography.
    ///   - showsCopyButton: whether a Copy button appears on hover and keyboard focus.
    public init(label: String, value: String, monospaced: Bool = true,
                labelWidth: CGFloat? = nil, showsCopyButton: Bool = true) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
        self.labelWidth = labelWidth
        self.showsCopyButton = showsCopyButton
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var valueFont: NSFont {
        if monospaced {
            if let codeFont { return codeFont.nsFont(sizeDelta: -1) }
            return metrics.typography.monoCaption.resolve(in: fontContext).ctFont as NSFont
        }
        return metrics.typography.caption.resolve(in: fontContext).ctFont as NSFont
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.s4) {
            LumenPropertyLabel(width: labelWidth) {
                Text(label)
                    .font(metrics.typography.caption)
                    .foregroundStyle(palette[.fgSecondary])
            }
            LumenCharacterWrappedValue(value: value, font: valueFont, color: palette[.fgPrimary])
                .frame(maxWidth: .infinity, alignment: .leading)
                .lumenReportsMarginElement("property-value:\(value)")
                .accessibilityLabel(label)
                .accessibilityValue(value)
            if showsCopyButton {
                Button(action: copy) {
                    Label(lumenLocalized(String(localized: "Copy %@", defaultValue: "Copy \(label)", bundle: .module, comment: "Components label. Values identify the item or count described.")), systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(width: metrics.layout.minimumHitTarget, height: metrics.layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.lumenPlain)
                .lumenIconOnlyControl(lumenLocalized(String(localized: "Copy", bundle: .module, comment: "Components label.")))
                .foregroundStyle(palette[.fgTertiary])
                .focused($copyFocused)
                .lumenGroupFocusRing(copyFocused, cornerRadius: metrics.radius.sm)
                .help(lumenLocalized(String(localized: "Copy %@", defaultValue: "Copy \(label)", bundle: .module, comment: "Components help text. Values identify the item or count described.")))
                .opacity(isHovered || copyFocused ? 1 : 0)
                .accessibilityHidden(!isHovered)
            }
        }
        .frame(minHeight: metrics.layout.minimumHitTarget)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
    }
}

/// A selectable, non-editable text field that breaks lines at any character. The string it holds is
/// always the original value; there is no line limit and no truncation.
struct LumenCharacterWrappedValue: NSViewRepresentable {
    let value: String
    let font: NSFont
    let color: Color

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.isSelectable = true
        field.isEditable = false
        field.drawsBackground = false
        field.isBezeled = false
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byCharWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.truncatesLastVisibleLine = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        paragraph.alignment = .natural
        paragraph.usesDefaultHyphenation = false
        paragraph.hyphenationFactor = 0
        paragraph.lineBreakStrategy = []
        paragraph.lineBreakMode = .byCharWrapping
        field.userInterfaceLayoutDirection = context.environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        field.font = font
        field.textColor = NSColor(color)
        field.attributedStringValue = NSAttributedString(string: value, attributes: [
            .font: font, .foregroundColor: NSColor(color), .paragraphStyle: paragraph
        ])
        field.lineBreakMode = .byCharWrapping
        field.maximumNumberOfLines = 0
        field.toolTip = value
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let minimum = ceil(font.ascender - font.descender + font.leading)
        let finite = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil }
        guard let cell = nsView.cell else { return nil }
        // Unproposed or unbounded: the natural, unwrapped size.
        let bounds = NSRect(x: 0, y: 0, width: finite ?? 100_000, height: 100_000)
        if let finite { nsView.preferredMaxLayoutWidth = finite }
        let size = cell.cellSize(forBounds: bounds)
        return CGSize(width: finite ?? ceil(size.width), height: max(minimum, ceil(size.height)))
    }
}
