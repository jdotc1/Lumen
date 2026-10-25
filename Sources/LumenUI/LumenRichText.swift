import AppKit
import ObjectiveC
import SwiftUI
import LumenTokens

/// A native rich-text field. The host supplies `TextFormattingCommands` in its scene for the
/// standard Format menu. While focused, the editor handles ⌘B/⌘I/⌘U before host menu commands.
public struct LumenRichTextView: View {
    @Binding private var text: AttributedString
    private let maxHeight: CGFloat
    private var showsFormatBar = false
    @State private var focused = false
    @State private var session = LumenRichTextSession()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.lumenMetrics) private var metrics

    /// The text area grows to `maxHeight`, then scrolls. Explicit run formatting is preserved.
    public init(text: Binding<AttributedString>, maxHeight: CGFloat = 180) {
        _text = text
        self.maxHeight = maxHeight
    }

    /// Adds compact formatting buttons. The list button opens AppKit's native list panel,
    /// where the user chooses bullets or numbering.
    public init(text: Binding<AttributedString>, maxHeight: CGFloat = 180, showsFormatBar: Bool) {
        self.init(text: text, maxHeight: maxHeight)
        self.showsFormatBar = showsFormatBar
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsFormatBar {
                HStack(spacing: metrics.spacing.s1) {
                    formatButton("Bold", symbol: "bold") { session.fontTrait(.boldFontMask) }
                    formatButton("Italic", symbol: "italic") { session.fontTrait(.italicFontMask) }
                    formatButton("Underline", symbol: "underline") { session.send(#selector(NSText.underline(_:))) }
                    formatButton("Bulleted List", symbol: "list.bullet") { session.send(#selector(NSTextView.orderFrontListPanel(_:))) }
                    Spacer(minLength: 0)
                }
                .padding(metrics.spacing.s1)
            }
            LumenRichTextBridge(text: $text, maxHeight: maxHeight, session: session,
                                focusChanged: { focused = $0 })
        }
        .lumenChrome(.field, focused: focused && isEnabled)
        .lumenDisabledFade(isEnabled)
    }

    private func formatButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .labelStyle(.iconOnly)
            .buttonStyle(LumenToolbarIconButtonStyle())
            .help(title)
    }
}

/// Each field owns its native target, so the format bar never edits another field's selection.
@MainActor final class LumenRichTextSession {
    weak var editor: LumenRichTextEditor?

    func send(_ action: Selector) {
        guard let editor, editor.isEditable else { return }
        editor.window?.makeFirstResponder(editor)
        NSApp.sendAction(action, to: editor, from: nil)
    }

    func fontTrait(_ trait: NSFontTraitMask) {
        guard let editor, editor.isEditable else { return }
        editor.window?.makeFirstResponder(editor)
        editor.toggleFontTrait(trait)
    }
}

struct LumenRichTextBridge: NSViewRepresentable {
    let text: Binding<AttributedString>
    let maxHeight: CGFloat
    let session: LumenRichTextSession
    let focusChanged: (Bool) -> Void
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(text: text) }

    func makeNSView(context: Context) -> LumenRichTextScrollView {
        let view = LumenRichTextScrollView()
        view.editor.delegate = context.coordinator
        session.editor = view.editor
        return view
    }

    func updateNSView(_ view: LumenRichTextScrollView, context: Context) {
        context.coordinator.text = text
        session.editor = view.editor
        view.editor.focusChanged = focusChanged
        view.maximumHeight = maxHeight
        view.minimumHeight = metrics.layout.controlHeight
        view.editor.textContainerInset = NSSize(width: metrics.layout.fieldInset, height: metrics.spacing.s2)
        let font = metrics.typography.body.resolve(in: fontContext).ctFont as NSFont
        view.apply(text.wrappedValue, font: font, color: NSColor(palette[.fgPrimary]))
        view.editor.insertionPointColor = NSColor(palette[.accent])
        view.editor.selectedTextAttributes = [.backgroundColor: NSColor(palette[.bgSelected]),
                                              .foregroundColor: NSColor(palette[.fgPrimary])]
        view.editor.isEditable = isEnabled
        view.editor.isSelectable = isEnabled
        if !isEnabled, view.window?.firstResponder === view.editor { view.window?.makeFirstResponder(nil) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LumenRichTextScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return nsView.fittingSize(for: width)
    }

    static func dismantleNSView(_ view: LumenRichTextScrollView, coordinator: Coordinator) {
        view.editor.delegate = nil
        view.editor.focusChanged = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<AttributedString>
        init(text: Binding<AttributedString>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView,
                  let scroll = editor.enclosingScrollView as? LumenRichTextScrollView else { return }
            let updated = AttributedString(editor.attributedString())
            scroll.lastValue = updated
            scroll.refreshInk()
            if text.wrappedValue != updated { text.wrappedValue = updated }
            scroll.reflow()
        }
    }
}

/// Layout follows the proposed width. Document height is derived from the text container, never
/// from the scroll view's prior height, so crossing the scrolling threshold cannot feed back.
final class LumenRichTextScrollView: NSScrollView {
    let editor = LumenRichTextEditor(frame: .zero)
    var maximumHeight: CGFloat = 180
    var minimumHeight: CGFloat = 24
    var lastValue: AttributedString?
    private var bodyFont: NSFont?
    private var ink: NSColor?
    private var proposedWidth: CGFloat?
    private var measuredHeight: CGFloat?
    private var reflowScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        documentView = editor
        NotificationCenter.default.addObserver(self, selector: #selector(storageDidChange(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: editor.textStorage)
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ value: AttributedString, font: NSFont, color: NSColor) {
        guard lastValue != value || bodyFont != font || ink != color else { return }
        var normalized = value
        for run in value.runs {
            if let intent = run.inlinePresentationIntent {
                let remaining = intent.subtracting([.stronglyEmphasized, .emphasized])
                normalized[run.range].inlinePresentationIntent = remaining.isEmpty ? nil : remaining
            }
        }
        let content = NSMutableAttributedString(attributedString: NSAttributedString(normalized))
        let whole = NSRange(location: 0, length: content.length)
        // Preserve native font runs. Plain and Markdown semantic runs use the resolved body ramp.
        content.enumerateAttributes(in: whole) { attributes, range, _ in
            var runFont = attributes[.font] as? NSFont
            if runFont == nil { runFont = font }
            if let old = bodyFont, let existing = runFont, existing.familyName == old.familyName,
               existing.pointSize == old.pointSize {
                runFont = NSFontManager.shared.convert(font, toHaveTrait: NSFontManager.shared.traits(of: existing))
            }
            if let runFont { content.addAttribute(.font, value: runFont, range: range) }
        }
        var offset = 0
        for run in value.runs {
            let length = String(value[run.range].characters).utf16.count
            if let intent = run.inlinePresentationIntent, length > 0 {
                let range = NSRange(location: offset, length: length)
                var runFont = content.attribute(.font, at: offset, effectiveRange: nil) as? NSFont ?? font
                if intent.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
                content.addAttribute(.font, value: runFont, range: range)
            }
            offset += length
        }
        let selected = editor.selectedRange()
        editor.textStorage?.setAttributedString(content)
        editor.setSelectedRange(NSRange(location: min(selected.location, content.length),
                                       length: min(selected.length, max(0, content.length - selected.location))))
        editor.typingAttributes[.font] = font
        editor.typingAttributes[.foregroundColor] = color
        // Temporary ink follows the theme without overwriting document color attributes.
        bodyFont = font
        ink = color
        refreshInk()
        lastValue = value
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func refreshInk() {
        guard let ink else { return }
        editor.layoutManager?.addTemporaryAttribute(.foregroundColor, value: ink,
            forCharacterRange: NSRange(location: 0, length: editor.string.utf16.count))
    }

    func fittingSize(for proposedWidth: CGFloat) -> CGSize {
        let width = max(1, proposedWidth)
        self.proposedWidth = width
        // Native font changes may resize the document view. Its width remains the viewport's,
        // while only its height can grow; never let a widened run become a wider document.
        editor.isHorizontallyResizable = false
        editor.minSize = .zero
        editor.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        editor.setFrameSize(NSSize(width: width, height: max(editor.frame.height, minimumHeight)))
        guard let container = editor.textContainer, let layout = editor.layoutManager else {
            return NSSize(width: width, height: minimumHeight)
        }
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        container.size = NSSize(width: max(1, width - 2 * editor.textContainerInset.width),
                                height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lineHeight = bodyFont.map { ceil($0.ascender - $0.descender + $0.leading) } ?? minimumHeight
        let textHeight = max(lineHeight, layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        let natural = ceil(textHeight + 2 * editor.textContainerInset.height)
        let limit = maximumHeight.isFinite ? max(minimumHeight, maximumHeight) : max(minimumHeight, 180)
        let height = min(max(minimumHeight, natural), limit)
        hasVerticalScroller = natural > height
        editor.setFrameSize(NSSize(width: width, height: max(natural, height)))
        measuredHeight = height
        return NSSize(width: width, height: height)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight ?? minimumHeight)
    }

    /// Invalidate a real intrinsic height, so a font-only edit also requests SwiftUI layout.
    func reflow() {
        let width = bounds.width > 0 ? contentView.bounds.width : proposedWidth
        if let width, width > 0 { _ = fittingSize(for: width) }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func storageDidChange(_ notification: Notification) {
        guard !reflowScheduled else { return }
        reflowScheduled = true
        // Layout managers receive the storage edit after this storage notification. Reflow after
        // that notification, including attribute-only changes made by the native Format menu.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reflowScheduled = false
            self.reflow()
        }
    }

    override func layout() {
        super.layout()
        let previousHeight = measuredHeight
        _ = fittingSize(for: contentView.bounds.width)
        if measuredHeight != previousHeight { invalidateIntrinsicContentSize() }
    }
}

// A hosting view can consume its SwiftUI shortcuts before walking its native children.
// The component does not own the host's window subclass, so install one window-entry shim.
// It offers only our focused editor's three formatting equivalents before the normal walk;
// all other events (including disabled/unfocused fields) use the original implementation.
@MainActor private enum LumenRichTextKeyEquivalentRouting {
    static let install: Void = {
        let originalSelector = #selector(NSWindow.performKeyEquivalent(with:))
        let routingSelector = #selector(NSWindow.lumenRichTextPerformKeyEquivalent(with:))
        guard let original = class_getInstanceMethod(NSWindow.self, originalSelector),
              let routing = class_getInstanceMethod(NSWindow.self, routingSelector) else { return }
        // If the method is inherited, add an override instead of changing the superclass.
        if class_addMethod(NSWindow.self, originalSelector, method_getImplementation(routing),
                           method_getTypeEncoding(routing)) {
            class_replaceMethod(NSWindow.self, routingSelector, method_getImplementation(original),
                                method_getTypeEncoding(original))
        } else {
            method_exchangeImplementations(original, routing)
        }
    }()
}

private extension NSWindow {
    @objc dynamic func lumenRichTextPerformKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = firstResponder as? LumenRichTextEditor,
           editor.handleFormattingKeyEquivalent(with: event) { return true }
        // After installation this selector invokes the original window implementation.
        return lumenRichTextPerformKeyEquivalent(with: event)
    }
}

final class LumenRichTextEditor: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { _ = LumenRichTextKeyEquivalentRouting.install }
    }

    func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard isEditable else { return }
        let manager = NSFontManager.shared
        let range = selectedRange()
        let font = (range.length > 0 && range.location < (textStorage?.length ?? 0)
            ? textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : typingAttributes[.font] as? NSFont) ?? self.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        manager.setSelectedFont(font, isMultiple: false)
        // Formatting belongs to this editor even when the host supplies a font-manager target.
        let previousTarget = manager.target
        manager.target = self
        defer { manager.target = previousTarget }
        let sender = NSMenuItem()
        sender.tag = Int(trait.rawValue)
        if manager.traits(of: font).contains(trait) { manager.removeFontTrait(sender) }
        else { manager.addFontTrait(sender) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleFormattingKeyEquivalent(with: event) || super.performKeyEquivalent(with: event)
    }

    fileprivate func handleFormattingKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        guard isEditable, window?.firstResponder === self, event.type == .keyDown,
              modifiers == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggleFontTrait(.boldFontMask)
        case "i": toggleFontTrait(.italicFontMask)
        case "u": underline(nil)
        default: return false
        }
        return true
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.focusChanged?(true) } }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { DispatchQueue.main.async { [weak self] in self?.focusChanged?(false) } }
        return resigned
    }
}
