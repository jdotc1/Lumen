import AppKit
import SwiftUI

/// A range of text to mark in a ``LumenSelectableText``, and how it is marked.
public struct LumenTextHighlight: Hashable, Sendable {
    /// How a highlight is drawn.
    public enum Role: Sendable, Hashable {
        /// A find match: the accent-subtle marker ground.
        case match
        /// The current match: the marker ground plus an accent underline, drawn above matches.
        case current
    }

    /// UTF-16 offsets into the text, the unit `NSTextView` uses. Out-of-bounds ranges are clamped;
    /// ranges that become empty are ignored; ranges never split a composed character.
    public var range: NSRange
    public var role: Role

    public init(_ range: NSRange, role: Role = .current) {
        self.range = range
        self.role = role
    }

    /// Marks a `String.Index` range of `text`. Indices must belong to `text`.
    public init(_ range: Range<String.Index>, in text: String, role: Role = .current) {
        self.init(NSRange(range, in: text), role: role)
    }
}

/// A request to scroll a range into view. Pass a new value, or bump `id`, to reveal again.
public struct LumenTextReveal: Equatable, Sendable {
    /// UTF-16 offsets into the text. Clamped to the text.
    public var range: NSRange
    /// Change this to reveal the same range again (after the person scrolls away, say).
    public var id: Int

    public init(_ range: NSRange, id: Int = 0) {
        self.range = range
        self.id = id
    }

    /// Reveals a `String.Index` range of `text`. Indices must belong to `text`.
    public init(_ range: Range<String.Index>, in text: String, id: Int = 0) {
        self.init(NSRange(range, in: text), id: id)
    }
}

/// Read-only, selectable text for large content such as reports and dumps, backed by `NSTextView`
/// in an `NSScrollView` with non-contiguous layout so very large strings stay responsive.
///
/// The host can mark exact character ranges with ``LumenTextHighlight`` (drawn with Lumen's find
/// highlight token, without editing the text) and scroll a range into view with
/// ``LumenTextReveal``. Selection, copy (Command-C), Select All and Find (Command-F) work natively.
/// The view fills the space it is given; frame it from the host.
public struct LumenSelectableText: View {
    private let text: String
    private let highlights: [LumenTextHighlight]
    private let reveal: LumenTextReveal?
    private let selection: Binding<NSRange>?
    private let accessibilityLabel: String?
    @Environment(\.lumenRendersOffscreen) private var rendersOffscreen
    @Environment(\.lumenCodeFont) private var codeFont
    @Environment(\.lumenPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - text: The full text. Replacing it with an equal string does not reset selection or scroll.
    ///   - highlights: Ranges to mark, in UTF-16 offsets.
    ///   - reveal: A range to scroll into view when it changes.
    ///   - selection: Optional two-way selection (UTF-16 location and length).
    ///   - accessibilityLabel: A localized label for the text area; AppKit's default when `nil`.
    public init(_ text: String,
                highlights: [LumenTextHighlight] = [],
                reveal: LumenTextReveal? = nil,
                selection: Binding<NSRange>? = nil,
                accessibilityLabel: String? = nil) {
        self.text = text
        self.highlights = highlights
        self.reveal = reveal
        self.selection = selection
        self.accessibilityLabel = accessibilityLabel
    }

    /// Joins `pages` with `separator` into one text. Highlight, reveal and selection ranges are
    /// offsets into the joined string; use ``offset(ofPage:in:separator:)`` to map page-local ranges.
    /// The pages are joined on each evaluation of the host's body, so keep the page array stable.
    public init(pages: [String],
                separator: String = "\n",
                highlights: [LumenTextHighlight] = [],
                reveal: LumenTextReveal? = nil,
                selection: Binding<NSRange>? = nil,
                accessibilityLabel: String? = nil) {
        self.init(pages.joined(separator: separator), highlights: highlights, reveal: reveal,
                  selection: selection, accessibilityLabel: accessibilityLabel)
    }

    /// The UTF-16 offset at which `page` starts in the text joined from `pages` with `separator`.
    /// A page below zero maps to 0; a page past the end maps to the joined length.
    public static func offset(ofPage page: Int, in pages: [String], separator: String = "\n") -> Int {
        guard page > 0 else { return 0 }
        let separatorLength = separator.utf16.count
        var offset = 0
        for index in 0..<min(page, pages.count) {
            offset += pages[index].utf16.count
            if index < pages.count - 1 { offset += separatorLength }
        }
        return offset
    }

    public var body: some View {
        Group {
            if rendersOffscreen {
                // Snapshot and audit renders avoid instantiating an NSScrollView.
                Text(String(text.prefix(4_000)))
                    .font(codeFont?.font() ?? LumenCodeFont.standard.font())
                    .foregroundStyle(palette[.fgPrimary])
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            } else {
                LumenSelectableTextBridge(text: text, highlights: highlights, reveal: reveal,
                                          selection: selection, accessibilityLabel: accessibilityLabel,
                                          font: (codeFont ?? .standard).nsFont())
                    .opacity(isEnabled ? 1 : 0.55)
            }
        }
    }
}

// MARK: Range helpers

enum LumenSelectableTextRanges {
    /// The range clipped to the text and widened to whole composed characters; `nil` when it
    /// is invalid or empty after clipping.
    static func clamped(_ range: NSRange, in text: NSString) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0 else { return nil }
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clipped.length > 0 else { return nil }
        return text.rangeOfComposedCharacterSequences(for: clipped)
    }

    /// Like `clamped`, but an empty range is a caret position and stays valid.
    static func clampedForReveal(_ range: NSRange, in text: NSString) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else { return nil }
        if range.length == 0 {
            return NSRange(location: min(range.location, text.length), length: 0)
        }
        return clamped(range, in: text) ?? NSRange(location: text.length, length: 0)
    }
}

// MARK: AppKit bridge

private struct LumenSelectableTextBridge: NSViewRepresentable {
    let text: String
    let highlights: [LumenTextHighlight]
    let reveal: LumenTextReveal?
    let selection: Binding<NSRange>?
    let accessibilityLabel: String?
    let font: NSFont
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LumenSelectableTextScrollView {
        let view = LumenSelectableTextScrollView()
        view.textView.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: LumenSelectableTextScrollView, context: Context) {
        let coordinator = context.coordinator
        let textView = view.textView
        coordinator.selection = selection
        coordinator.view = view
        let ink = NSColor(palette[.fgPrimary])

        textView.textContainerInset = NSSize(width: metrics.layout.fieldInset, height: metrics.spacing.s2)
        textView.textContainer?.lineFragmentPadding = metrics.layout.fieldInset
        textView.selectedTextAttributes = [.backgroundColor: NSColor(palette[.bgSelected]),
                                           .foregroundColor: ink]

        // Reassigning the string resets selection and scroll, so only do it when the text changed.
        let textChanged = coordinator.text != text
        if textChanged || coordinator.font != font || coordinator.ink != ink {
            if textChanged {
                coordinator.text = text
                coordinator.nsText = text as NSString
                textView.textStorage?.setAttributedString(NSAttributedString(string: text,
                    attributes: [.font: font, .foregroundColor: ink]))
            } else if let storage = textView.textStorage {
                storage.addAttributes([.font: font, .foregroundColor: ink],
                                      range: NSRange(location: 0, length: storage.length))
            }
            textView.font = font
            textView.textColor = ink
            coordinator.font = font
            coordinator.ink = ink
        }
        if let accessibilityLabel { textView.setAccessibilityLabel(accessibilityLabel) }

        applyHighlights(to: textView, coordinator: coordinator, textChanged: textChanged)
        applySelection(to: textView, coordinator: coordinator)

        if let reveal, coordinator.lastReveal != reveal {
            coordinator.lastReveal = reveal
            coordinator.pendingReveal = reveal
        } else if reveal == nil {
            coordinator.lastReveal = nil
            coordinator.pendingReveal = nil
        }
        coordinator.flushReveal()
        view.onLayout = { [weak coordinator] in coordinator?.flushReveal() }
    }

    private func applyHighlights(to textView: NSTextView, coordinator: Coordinator, textChanged: Bool) {
        guard let layout = textView.layoutManager else { return }
        let source = coordinator.nsText
        let whole = NSRange(location: 0, length: source.length)
        if textChanged {
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
            layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
        } else {
            for range in coordinator.appliedRanges {
                guard let clipped = LumenSelectableTextRanges.clamped(range, in: source) else { continue }
                layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clipped)
                layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: clipped)
                layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: clipped)
            }
        }
        var applied: [NSRange] = []
        let ground = NSColor(palette[.accentSubtle])
        let accent = NSColor(palette[.accent])
        // Matches first so the current highlight is drawn on top where they overlap.
        for role in [LumenTextHighlight.Role.match, .current] {
            for highlight in highlights where highlight.role == role {
                guard let range = LumenSelectableTextRanges.clamped(highlight.range, in: source) else { continue }
                layout.addTemporaryAttribute(.backgroundColor, value: ground, forCharacterRange: range)
                if role == .current {
                    layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                                 forCharacterRange: range)
                    layout.addTemporaryAttribute(.underlineColor, value: accent, forCharacterRange: range)
                }
                applied.append(range)
            }
        }
        coordinator.appliedRanges = applied
        textView.needsDisplay = true
    }

    private func applySelection(to textView: NSTextView, coordinator: Coordinator) {
        guard let selection else { return }
        let wanted = selection.wrappedValue
        guard wanted != coordinator.lastReportedSelection, wanted != textView.selectedRange() else { return }
        let length = coordinator.nsText.length
        guard wanted.location != NSNotFound, wanted.location >= 0, wanted.length >= 0, wanted.location <= length else { return }
        let clipped = NSIntersectionRange(wanted, NSRange(location: 0, length: length))
        let range = NSRange(location: wanted.location, length: clipped.length)
        coordinator.lastReportedSelection = range
        textView.setSelectedRange(range)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LumenSelectableTextScrollView, context: Context) -> CGSize? {
        // Scrollable content: fill whatever the host proposes.
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 200)
    }

    static func dismantleNSView(_ view: LumenSelectableTextScrollView, coordinator: Coordinator) {
        view.textView.delegate = nil
        view.onLayout = nil
        coordinator.view = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: String?
        var nsText: NSString = ""
        var font: NSFont?
        var ink: NSColor?
        var appliedRanges: [NSRange] = []
        var lastReveal: LumenTextReveal?
        var pendingReveal: LumenTextReveal?
        var selection: Binding<NSRange>?
        var lastReportedSelection: NSRange?
        weak var view: LumenSelectableTextScrollView?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let selection else { return }
            let range = textView.selectedRange()
            guard range != lastReportedSelection, range != selection.wrappedValue else { return }
            lastReportedSelection = range
            // Never write state while SwiftUI is updating the view.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.selection?.wrappedValue = range }
            }
        }

        /// Scrolls the pending reveal into view once the view has a size.
        func flushReveal() {
            guard let reveal = pendingReveal, let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            pendingReveal = nil
            guard let range = LumenSelectableTextRanges.clampedForReveal(reveal.range, in: nsText) else { return }
            view.scroll(to: range)
        }
    }
}

/// An `NSScrollView` holding a read-only TextKit 1 text view with non-contiguous layout.
final class LumenSelectableTextScrollView: NSScrollView {
    let textView: NSTextView
    var onLayout: (() -> Void)?

    override init(frame frameRect: NSRect) {
        textView = NSTextView(usingTextLayoutManager: false)
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.layoutManager?.allowsNonContiguousLayout = true
        documentView = textView
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        onLayout?()
    }

    /// Lays out only the target range, then scrolls so it sits near the middle of the view.
    func scroll(to range: NSRange) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let length = (textView.string as NSString).length
        let target = NSRange(location: min(range.location, length), length: min(range.length, max(0, length - range.location)))
        let glyphs = layoutManager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        layoutManager.ensureLayout(forCharacterRange: target)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        if rect.isEmpty { rect.size = NSSize(width: 1, height: max(rect.height, 1)) }
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        // Non-contiguous layout may not have grown the document to the target yet.
        let needed = rect.maxY + textView.textContainerInset.height
        if textView.frame.height < needed {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: needed))
        }
        let visibleHeight = contentView.bounds.height
        if visibleHeight > rect.height {
            let pad = (visibleHeight - rect.height) / 2
            rect = rect.insetBy(dx: 0, dy: -pad)
        }
        textView.scrollToVisible(rect)
        reflectScrolledClipView(contentView)
        // The indicator is an overlay window of its own: show it only where someone can see it.
        if target.length > 0, let window, window.isVisible, window.occlusionState.contains(.visible) {
            textView.showFindIndicator(for: target)
        }
    }
}
