import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
import LumenTokens
import LumenConformance
@_spi(LayoutAudit) @testable import LumenUI

@MainActor
final class LumenExactTextTests: XCTestCase {
    private func smartTextView() -> NSTextView {
        let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.isAutomaticTextReplacementEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = true
        view.smartInsertDeleteEnabled = true
        view.isAutomaticLinkDetectionEnabled = true
        view.isAutomaticDataDetectionEnabled = true
        view.isAutomaticTextCompletionEnabled = true
        return view
    }

    private func flags(_ view: NSTextView) -> [Bool] {
        [view.isAutomaticQuoteSubstitutionEnabled, view.isAutomaticDashSubstitutionEnabled,
         view.isAutomaticTextReplacementEnabled, view.isAutomaticSpellingCorrectionEnabled,
         view.isContinuousSpellCheckingEnabled, view.isGrammarCheckingEnabled,
         view.smartInsertDeleteEnabled, view.isAutomaticLinkDetectionEnabled,
         view.isAutomaticDataDetectionEnabled, view.isAutomaticTextCompletionEnabled]
    }

    private func flagsOff(_ view: NSTextView) -> Bool { !flags(view).contains(true) }

    func testApplyTurnsEveryFlagOffAndRestoreBringsThemBack() {
        let view = smartTextView()
        // Continuous spelling and grammar checking cannot be switched on outside a running app, so
        // restore is checked against what the view held before apply, not against all-true.
        let before = flags(view), wasRich = view.isRichText
        XCTAssertTrue(before.contains(true))
        let snapshot = LumenExactTextPolicy.apply(to: view)
        XCTAssertTrue(flagsOff(view))
        XCTAssertEqual(view.writingToolsBehavior, NSWritingToolsBehavior.none)
        XCTAssertFalse(view.isRichText)
        LumenExactTextPolicy.restore(snapshot, on: view)
        XCTAssertEqual(flags(view), before)
        XCTAssertEqual(view.isRichText, wasRich)
    }

    func testInsertedTextIsPreservedByteForByte() {
        let view = smartTextView()
        _ = LumenExactTextPolicy.apply(to: view)
        let typed = "\"quoted\" -- x  'a' ..."
        view.insertText(typed, replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, typed)
    }

    func testHostedFieldConfiguresSharedEditorAndDoesNotLeak() throws {
        var exact = "", plain = ""
        let root = VStack {
            LumenTextField("exact", text: Binding(get: { exact }, set: { exact = $0 }))
                .frame(width: 300).lumenExactText()
            TextField("plain", text: Binding(get: { plain }, set: { plain = $0 })).frame(width: 120)
        }
        let window = host(AnyView(root), size: CGSize(width: 420, height: 160))
        let fields = descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }
            .filter { $0.isEditable }
            .sorted { $0.frame.width > $1.frame.width }
        XCTAssertGreaterThanOrEqual(fields.count, 2)
        let exactField = fields[0], plainField = fields[fields.count - 1]
        // The field editor is shared, so the plain field's own flags are the baseline.
        XCTAssertTrue(window.makeFirstResponder(plainField))
        settle(window)
        let baseline = flags(try XCTUnwrap(plainField.currentEditor() as? NSTextView))
        XCTAssertTrue(window.makeFirstResponder(exactField))
        settle(window)
        let editor = try XCTUnwrap(exactField.currentEditor() as? NSTextView)
        XCTAssertTrue(flagsOff(editor))
        XCTAssertTrue(window.makeFirstResponder(plainField))
        settle(window)
        let plainEditor = try XCTUnwrap(plainField.currentEditor() as? NSTextView)
        XCTAssertTrue(plainEditor === editor, "the field editor is shared")
        XCTAssertEqual(flags(editor), baseline, "exact mode must not leak into the next field")
    }

    func testDisabledModifierLeavesFieldEditorUntouched() throws {
        var text = "", reference = ""
        let root = VStack {
            TextField("plain", text: Binding(get: { text }, set: { text = $0 })).frame(width: 200)
                .lumenExactText(false)
            TextField("reference", text: Binding(get: { reference }, set: { reference = $0 })).frame(width: 120)
        }
        let window = host(AnyView(root), size: CGSize(width: 300, height: 120))
        XCTAssertTrue(descendants(try XCTUnwrap(window.contentView)).allSatisfy { !($0 is LumenExactTextProbeView) },
                      "false adds no probe")
        let fields = descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }
            .filter { $0.isEditable }
            .sorted { $0.frame.width > $1.frame.width }
        XCTAssertEqual(fields.count, 2)
        XCTAssertTrue(window.makeFirstResponder(fields[1]))
        settle(window)
        let baseline = flags(try XCTUnwrap(fields[1].currentEditor() as? NSTextView))
        XCTAssertTrue(window.makeFirstResponder(fields[0]))
        settle(window)
        XCTAssertEqual(flags(try XCTUnwrap(fields[0].currentEditor() as? NSTextView)), baseline)
    }

    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { descendants($0) } }

    private func host(_ view: AnyView, size: CGSize) -> NSWindow {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        let root = view.lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
            .lumenMetrics(.standard).lumenTextScale(1).lumenChromeStyle(.drawn)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        settle(window)
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<15 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
