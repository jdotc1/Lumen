import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor final class LumenRichTextTests: XCTestCase {
    func testNativeBindingRoundTripPreservesBoldItalicAndUnderline() throws {
        let font = NSFont.systemFont(ofSize: 13)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        let native = NSMutableAttributedString(string: "Bold italic plain", attributes: [.font: font])
        native.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 4))
        native.addAttributes([.font: italic, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 5, length: 6))
        var value = AttributedString(native)
        let binding = Binding(get: { value }, set: { value = $0 })
        let coordinator = LumenRichTextBridge.Coordinator(text: binding)
        let view = LumenRichTextScrollView()
        view.apply(value, font: font, color: .labelColor)
        view.editor.delegate = coordinator
        view.editor.textStorage?.append(NSAttributedString(string: "!", attributes: [.font: italic]))
        view.editor.didChangeText()
        XCTAssertEqual(String(value.characters), "Bold italic plain!")
        let output = NSAttributedString(value)
        let firstFont = try XCTUnwrap(output.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let secondFont = try XCTUnwrap(output.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: firstFont).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: secondFont).contains(.italicFontMask))
        XCTAssertEqual(output.attribute(.underlineStyle, at: 5, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        // A host-side replacement updates the same native editor too.
        value = AttributedString("Replacement")
        view.apply(value, font: font, color: .labelColor)
        XCTAssertEqual(view.editor.string, "Replacement")
    }

    func testSemanticBoldAndItalicUseBodyFontAndSurviveEditing() throws {
        var bold = AttributedString("Bold")
        bold.inlinePresentationIntent = .stronglyEmphasized
        var italic = AttributedString("Italic")
        italic.inlinePresentationIntent = .emphasized
        var value = bold + AttributedString(" ") + italic
        let view = LumenRichTextScrollView()
        let font = NSFont.systemFont(ofSize: 17)
        view.apply(value, font: font, color: .white)
        let coordinator = LumenRichTextBridge.Coordinator(text: Binding(get: { value }, set: { value = $0 }))
        view.editor.delegate = coordinator
        view.editor.didChangeText()
        let result = NSAttributedString(value)
        let first = try XCTUnwrap(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let last = try XCTUnwrap(result.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(first.pointSize, 17)
        XCTAssertTrue(NSFontManager.shared.traits(of: first).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: last).contains(.italicFontMask))
    }

    func testTextGrowsToMaximumThenScrollsAndShrinksAgain() {
        let view = LumenRichTextScrollView()
        view.maximumHeight = 90
        let font = NSFont.systemFont(ofSize: 13)
        view.apply(AttributedString("Short"), font: font, color: .labelColor)
        let short = view.fittingSize(for: 300)
        XCTAssertLessThan(short.height, 90)
        XCTAssertFalse(view.hasVerticalScroller)
        view.apply(AttributedString(Array(repeating: "A paragraph with text to wrap.", count: 30).joined(separator: "\n")),
                   font: font, color: .labelColor)
        let long = view.fittingSize(for: 300)
        XCTAssertEqual(long.height, 90)
        XCTAssertTrue(view.hasVerticalScroller)
        XCTAssertGreaterThan(view.editor.frame.height, long.height)
        view.apply(AttributedString("Short again"), font: font, color: .labelColor)
        XCTAssertLessThan(view.fittingSize(for: 300).height, 90)
        XCTAssertFalse(view.hasVerticalScroller)
    }

    func testPastedColorsKeepDocumentAttributesButUsePaletteInk() {
        var value = AttributedString("Plain ")
        let view = LumenRichTextScrollView()
        let coordinator = LumenRichTextBridge.Coordinator(text: Binding(get: { value }, set: { value = $0 }))
        view.editor.delegate = coordinator
        view.apply(value, font: .systemFont(ofSize: 13), color: .white)
        view.editor.textStorage?.append(NSAttributedString(string: "Pasted", attributes: [.foregroundColor: NSColor.red]))
        view.editor.didChangeText()
        XCTAssertEqual(NSAttributedString(value).attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor, .red)
        XCTAssertEqual(view.editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 6, effectiveRange: nil) as? NSColor, .white)
    }

    func testProposedWidthControlsWrappingWithoutChangingContent() {
        let view = LumenRichTextScrollView()
        let value = AttributedString("A longer sentence that wraps as the field becomes narrower and grows with its text.")
        view.apply(value, font: .systemFont(ofSize: 13), color: .labelColor)
        let wide = view.fittingSize(for: 500)
        let narrow = view.fittingSize(for: 160)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertEqual(view.editor.string, String(value.characters))
        XCTAssertEqual(view.fittingSize(for: 500), wide)
    }

    private final class FieldState: ObservableObject {
        @Published var text: AttributedString
        init(_ text: AttributedString) { self.text = text }
    }

    private struct HostedField: View {
        @ObservedObject var state: FieldState
        let maximumHeight: CGFloat
        var body: some View {
            VStack(spacing: 0) {
                LumenRichTextView(text: $state.text, maxHeight: maximumHeight)
                Spacer(minLength: 0)
            }
        }
    }

    private func settle(_ host: NSView) {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func field(in view: NSView) -> LumenRichTextScrollView? {
        if let field = view as? LumenRichTextScrollView { return field }
        return view.subviews.lazy.compactMap { self.field(in: $0) }.first
    }

    private func host(_ text: AttributedString, width: CGFloat = 320, maximumHeight: CGFloat = 180) throws
        -> (NSWindow, NSView, FieldState, LumenRichTextScrollView) {
        let state = FieldState(text)
        let host = NSHostingView(rootView: HostedField(state: state, maximumHeight: maximumHeight))
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: NSRect(x: 0, y: 0, width: width, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        settle(host)
        let field = try XCTUnwrap(field(in: host))
        XCTAssertTrue(window.makeFirstResponder(field.editor))
        return (window, host, state, field)
    }

    private func key(_ character: String, window: NSWindow, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        let codes: [String: UInt16] = ["b": 11, "i": 34, "u": 32, "k": 40]
        return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: codes[character] ?? 0))
    }

    private final class HostCommands: NSObject {
        var calls = 0
        @objc func build(_ sender: Any?) { calls += 1 }
    }

    private enum ShortcutHost {
        case toolbar, button, mainMenu
    }

    private struct ConflictingShortcutHost: View {
        @ObservedObject var state: FieldState
        let kind: ShortcutHost
        let commands: HostCommands

        var body: some View {
            VStack {
                if kind == .button {
                    Button("Build") { commands.build(nil) }.keyboardShortcut("b")
                }
                LumenRichTextView(text: $state.text)
                Spacer()
            }
            .toolbar {
                if kind == .toolbar {
                    ToolbarItem {
                        LumenTaskCluster([
                            LumenTaskAction("Build", systemImage: "hammer.fill", shortcut: KeyboardShortcut("b")) {
                                commands.build(nil)
                            }
                        ], activity: .idle())
                    }
                }
            }
        }
    }

    private func assertWindowShortcutOwnership(_ kind: ShortcutHost,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        let state = FieldState(AttributedString("Selected text"))
        let commands = HostCommands()
        let controller = NSHostingController(rootView: ConflictingShortcutHost(state: state, kind: kind, commands: commands))
        let window = LumenHeadlessHost.window(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 360, height: 240))
        defer {
            window.close()
            application.mainMenu = previousMenu
        }
        let menu = NSMenu(title: "Main")
        let hostMenu = NSMenu(title: "Host")
        hostMenu.autoenablesItems = false
        let parent = NSMenuItem(title: "Host", action: nil, keyEquivalent: "")
        parent.submenu = hostMenu
        menu.addItem(parent)
        for character in kind == .mainMenu ? ["b", "i", "u", "k"] : ["k"] {
            let item = NSMenuItem(title: "Host command", action: #selector(HostCommands.build(_:)), keyEquivalent: character)
            item.target = commands
            item.keyEquivalentModifierMask = .command
            hostMenu.addItem(item)
        }
        application.mainMenu = menu
        // Window-level dispatch needs a first responder, not application activation. Keep
        // this fixture offscreen and never make it key so it cannot take the user's focus.
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        settle(controller.view)
        let field = try XCTUnwrap(field(in: controller.view), file: file, line: line)
        XCTAssertTrue(window.makeFirstResponder(field.editor), file: file, line: line)
        XCTAssertTrue(window.firstResponder === field.editor, file: file, line: line)

        field.editor.selectAll(nil)
        let event = try key("b", window: window)
        // Start at the real window; never call editor.performKeyEquivalent here. The installed
        // menu is offered only an unhandled event, matching the window-then-menu boundary.
        let handled = window.performKeyEquivalent(with: event)
        if !handled { _ = menu.performKeyEquivalent(with: event) }
        settle(controller.view)
        let font = try XCTUnwrap(field.editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                                 file: file, line: line)
        let bold = NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        print("Shortcut host=\(kind) dispatch=window handled=\(handled) bold=\(bold) hostCalls=\(commands.calls)")
        XCTAssertTrue(handled, "The window must route Command-B to the editor", file: file, line: line)
        XCTAssertTrue(bold, "Command-B must bold the selection", file: file, line: line)
        XCTAssertEqual(commands.calls, 0, "Command-B must not start Build", file: file, line: line)

        XCTAssertTrue(window.makeFirstResponder(nil), file: file, line: line)
        let before = commands.calls
        let unfocused = try key("b", window: window)
        if !window.performKeyEquivalent(with: unfocused) { _ = menu.performKeyEquivalent(with: unfocused) }
        settle(controller.view)
        XCTAssertEqual(commands.calls, before + 1, "The unfocused host shortcut must remain available", file: file, line: line)
        XCTAssertTrue(window.makeFirstResponder(field.editor), file: file, line: line)
        let other = try key("k", window: window)
        if !window.performKeyEquivalent(with: other) { _ = menu.performKeyEquivalent(with: other) }
        XCTAssertEqual(commands.calls, before + 2, "Other host shortcuts must remain available", file: file, line: line)

        field.editor.isEditable = false
        let disabled = try key("b", window: window)
        if !window.performKeyEquivalent(with: disabled) { _ = menu.performKeyEquivalent(with: disabled) }
        settle(controller.view)
        XCTAssertEqual(commands.calls, before + 3, "A noneditable editor must not intercept Build", file: file, line: line)
        field.editor.isEditable = true
        let modified = try key("b", window: window, modifiers: [.command, .shift])
        let beforeModified = NSAttributedString(attributedString: field.editor.attributedString())
        // The host may consume a modified equivalent. Only formatting belongs to this guard.
        _ = window.performKeyEquivalent(with: modified)
        XCTAssertEqual(field.editor.attributedString(), beforeModified,
                       "Modified shortcuts must not toggle formatting", file: file, line: line)
    }

    func testWindowDispatchWithToolbarBuildShortcut() throws {
        try assertWindowShortcutOwnership(.toolbar)
    }

    func testWindowDispatchWithPlainButtonBuildShortcut() throws {
        try assertWindowShortcutOwnership(.button)
    }

    func testWindowDispatchWithInstalledMainMenuShortcut() throws {
        try assertWindowShortcutOwnership(.mainMenu)
    }

    func testFormattingKeyEquivalentsWinOverConflictingHostCommands() throws {
        let (window, _, state, field) = try host(AttributedString("Selected text"))
        defer { window.close() }
        field.editor.selectAll(nil)
        let commands = HostCommands()
        let menu = NSMenu(title: "Host")
        for character in ["b", "i", "u", "k"] {
            let item = NSMenuItem(title: "Host command", action: #selector(HostCommands.build(_:)), keyEquivalent: character)
            item.keyEquivalentModifierMask = .command
            item.target = commands
            menu.addItem(item)
        }
        for character in ["b", "i", "u"] {
            let event = try key(character, window: window)
            // Exercise the window's key-equivalent entry point without requiring XCTest to
            // activate an application. Only unhandled equivalents are offered to the host menu.
            let handled = window.performKeyEquivalent(with: event)
            if !handled { _ = menu.performKeyEquivalent(with: event) }
            XCTAssertTrue(handled, "The focused field must own command-\(character)")
        }
        XCTAssertEqual(commands.calls, 0)
        let result = NSAttributedString(state.text)
        let font = try XCTUnwrap(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
        XCTAssertEqual(result.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let other = try key("k", window: window)
        XCTAssertFalse(window.performKeyEquivalent(with: other))
        XCTAssertTrue(menu.performKeyEquivalent(with: other))
        XCTAssertEqual(commands.calls, 1, "Other host menu shortcuts must still work")
    }

    func testCaretFormattingTogglesTypingAttributesAndLeavesOtherShortcutsAlone() throws {
        let (window, _, _, field) = try host(AttributedString("Caret"))
        defer { window.close() }
        field.editor.setSelectedRange(NSRange(location: 2, length: 0))
        let otherTarget = HostCommands()
        let previousTarget = NSFontManager.shared.target
        NSFontManager.shared.target = otherTarget
        defer { NSFontManager.shared.target = previousTarget }
        for (character, trait) in [("b", NSFontTraitMask.boldFontMask), ("i", .italicFontMask)] {
            let event = try key(character, window: window)
            XCTAssertTrue(field.editor.performKeyEquivalent(with: event))
            XCTAssertTrue(NSFontManager.shared.target as AnyObject? === otherTarget)
            let on = try XCTUnwrap(field.editor.typingAttributes[.font] as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: on).contains(trait))
            XCTAssertTrue(field.editor.performKeyEquivalent(with: event))
            let off = try XCTUnwrap(field.editor.typingAttributes[.font] as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: off).contains(trait))
        }
        let underline = try key("u", window: window)
        XCTAssertTrue(field.editor.performKeyEquivalent(with: underline))
        XCTAssertEqual(field.editor.typingAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertTrue(field.editor.performKeyEquivalent(with: underline))
        XCTAssertEqual(field.editor.typingAttributes[.underlineStyle] as? Int ?? 0, 0)
        XCTAssertFalse(field.editor.performKeyEquivalent(with: try key("k", window: window)))
        XCTAssertFalse(field.editor.performKeyEquivalent(with: try key("b", window: window, modifiers: [.command, .shift])))
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(field.editor.performKeyEquivalent(with: try key("b", window: window)))
        XCTAssertTrue(window.makeFirstResponder(field.editor))
        field.editor.isEditable = false
        XCTAssertFalse(field.editor.performKeyEquivalent(with: try key("b", window: window)))
    }

    private func fragments(in editor: NSTextView) throws -> [NSRect] {
        let container = try XCTUnwrap(editor.textContainer)
        let manager = try XCTUnwrap(editor.layoutManager)
        manager.ensureLayout(for: container)
        var fragments: [NSRect] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, _, _ in
            fragments.append(used)
        }
        return fragments
    }

    func testNativeBoldRewrapsAndGrowsHostedFieldWithoutForcedMeasurement() throws {
        let sentence = "The third line becomes wider when its words are bold."
        let font = NSFont.systemFont(ofSize: 13)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let plainWidth = (sentence as NSString).size(withAttributes: [.font: font]).width
        let boldWidth = (sentence as NSString).size(withAttributes: [.font: bold]).width
        XCTAssertGreaterThan(boldWidth, plainWidth)
        let width = (plainWidth + boldWidth) / 2 + 2 * (LumenMetrics.standard.layout.fieldInset + 5)
        let text = AttributedString(NSAttributedString(string: sentence, attributes: [.font: font]))
        let (window, host, state, field) = try host(text, width: width)
        defer { window.close() }
        let initialFragments = try fragments(in: field.editor)
        XCTAssertEqual(initialFragments.count, 1)
        let initialHeight = field.bounds.height
        field.editor.selectAll(nil)
        let session = LumenRichTextSession()
        session.editor = field.editor
        session.fontTrait(.boldFontMask)
        settle(host)
        let wrapped = try fragments(in: field.editor)
        XCTAssertGreaterThan(wrapped.count, initialFragments.count)
        XCTAssertGreaterThan(field.bounds.height, initialHeight, "Font-only changes must grow the hosted field")
        let container = try XCTUnwrap(field.editor.textContainer)
        XCTAssertTrue(container.widthTracksTextView)
        XCTAssertFalse(field.editor.isHorizontallyResizable)
        XCTAssertEqual(container.maximumNumberOfLines, 0)
        XCTAssertEqual(container.lineBreakMode, .byWordWrapping)
        XCTAssertLessThanOrEqual(field.editor.frame.width, field.contentView.bounds.width + 0.5)
        XCTAssertLessThanOrEqual(container.size.width, field.contentView.bounds.width - 2 * field.editor.textContainerInset.width + 0.5)
        for fragment in wrapped { XCTAssertLessThanOrEqual(fragment.maxX, container.size.width + 0.5) }
        XCTAssertLessThanOrEqual((wrapped.last?.maxY ?? 0) + 2 * field.editor.textContainerInset.height,
                                 field.contentView.bounds.height + 0.5)
        let output = NSAttributedString(state.text)
        let outputFont = try XCTUnwrap(output.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: outputFont).contains(.boldFontMask))
        XCTAssertEqual(output.string, sentence)
    }

    func testAttributeOnlyStorageEditRewrapsAndEnablesScrollingAtMaximumHeight() throws {
        let text = AttributedString("A line whose larger font needs several wrapped rows inside this field.")
        let (window, host, _, field) = try host(text, width: 260, maximumHeight: 60)
        defer { window.close() }
        let initialHeight = field.bounds.height
        field.editor.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 28, weight: .bold),
            range: NSRange(location: 0, length: field.editor.string.utf16.count))
        // No didChangeText call or manual measurement: attribute notifications must invalidate size.
        settle(host)
        XCTAssertGreaterThan(field.bounds.height, initialHeight)
        XCTAssertEqual(field.bounds.height, 60, accuracy: 0.5)
        XCTAssertTrue(field.hasVerticalScroller)
        XCTAssertGreaterThan(field.editor.frame.height, field.contentView.bounds.height)
        let container = try XCTUnwrap(field.editor.textContainer)
        for fragment in try fragments(in: field.editor) {
            XCTAssertLessThanOrEqual(fragment.maxX, container.size.width + 0.5)
        }
    }

}
