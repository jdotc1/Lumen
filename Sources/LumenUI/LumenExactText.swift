import AppKit
import SwiftUI

extension View {
    /// Makes every text field inside this view keep exactly the bytes typed or pasted: no smart
    /// quotes or dashes, text replacement, spelling/grammar correction or checking, auto-capitalization,
    /// link/data detection, text completion, inline prediction, Writing Tools rewriting, or smart
    /// insert/delete. For entitlement keys, identifiers, hashes and hex. Whitespace is never trimmed
    /// and nothing is normalized; the binding is neither read nor written.
    ///
    /// macOS has no separate auto-capitalization switch: it is a side effect of automatic text
    /// replacement and correction, which this modifier turns off. Works with SwiftUI `TextField`,
    /// `LumenTextField`, `LumenInlineField` and `LumenFieldRow` content. The window's shared field
    /// editor is configured only while one of these fields is being edited and is restored when
    /// editing ends, so ordinary fields elsewhere are unaffected. `false` leaves the field untouched.
    public func lumenExactText(_ enabled: Bool = true) -> some View {
        modifier(LumenExactTextModifier(enabled: enabled))
    }
}

/// Field-editor flags that exact-text entry turns off, and the testable apply/restore seam.
enum LumenExactTextPolicy {
    /// Previous values of every flag `apply` changed.
    struct Snapshot {
        var quote: Bool
        var dash: Bool
        var textReplacement: Bool
        var spellingCorrection: Bool
        var continuousSpelling: Bool
        var grammar: Bool
        var smartInsertDelete: Bool
        var linkDetection: Bool
        var dataDetection: Bool
        var textCompletion: Bool
        var inlinePrediction: NSTextInputTraitType
        var writingTools: NSWritingToolsBehavior
        var richText: Bool
        var importsGraphics: Bool
    }

    /// Turns every substitution and correction flag off and returns the previous values.
    /// Flags only; text and marked (IME) text are never touched.
    @MainActor static func apply(to textView: NSTextView) -> Snapshot {
        let snapshot = Snapshot(
            quote: textView.isAutomaticQuoteSubstitutionEnabled,
            dash: textView.isAutomaticDashSubstitutionEnabled,
            textReplacement: textView.isAutomaticTextReplacementEnabled,
            spellingCorrection: textView.isAutomaticSpellingCorrectionEnabled,
            continuousSpelling: textView.isContinuousSpellCheckingEnabled,
            grammar: textView.isGrammarCheckingEnabled,
            smartInsertDelete: textView.smartInsertDeleteEnabled,
            linkDetection: textView.isAutomaticLinkDetectionEnabled,
            dataDetection: textView.isAutomaticDataDetectionEnabled,
            textCompletion: textView.isAutomaticTextCompletionEnabled,
            inlinePrediction: textView.inlinePredictionType,
            writingTools: textView.writingToolsBehavior,
            richText: textView.isRichText,
            importsGraphics: textView.importsGraphics)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = NSWritingToolsBehavior.none
        textView.isRichText = false
        textView.importsGraphics = false
        return snapshot
    }

    /// Returns the flags `apply` changed to their previous values.
    @MainActor static func restore(_ snapshot: Snapshot, on textView: NSTextView) {
        textView.isAutomaticQuoteSubstitutionEnabled = snapshot.quote
        textView.isAutomaticDashSubstitutionEnabled = snapshot.dash
        textView.isAutomaticTextReplacementEnabled = snapshot.textReplacement
        textView.isAutomaticSpellingCorrectionEnabled = snapshot.spellingCorrection
        textView.isContinuousSpellCheckingEnabled = snapshot.continuousSpelling
        textView.isGrammarCheckingEnabled = snapshot.grammar
        textView.smartInsertDeleteEnabled = snapshot.smartInsertDelete
        textView.isAutomaticLinkDetectionEnabled = snapshot.linkDetection
        textView.isAutomaticDataDetectionEnabled = snapshot.dataDetection
        textView.isAutomaticTextCompletionEnabled = snapshot.textCompletion
        textView.inlinePredictionType = snapshot.inlinePrediction
        textView.writingToolsBehavior = snapshot.writingTools
        textView.isRichText = snapshot.richText
        textView.importsGraphics = snapshot.importsGraphics
    }
}

private struct LumenExactTextModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.lumenRendersOffscreen) private var rendersOffscreen

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .autocorrectionDisabled(true)
                .writingToolsBehavior(.disabled)
                .background {
                    if !rendersOffscreen {
                        LumenExactTextProbe()
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            content
        }
    }
}

/// Background sibling that fills the modified subtree's footprint. It configures the window's
/// shared field editor while a field inside that footprint is being edited.
private struct LumenExactTextProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> LumenExactTextProbeView { LumenExactTextProbeView() }
    func updateNSView(_ view: LumenExactTextProbeView, context: Context) {}
}

@MainActor final class LumenExactTextProbeView: NSView {
    private struct Active {
        weak var textView: NSTextView?
        let snapshot: LumenExactTextPolicy.Snapshot
    }
    private var active: Active?
    private var observation: NSKeyValueObservation?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        restoreActive()
        observation = nil
        NotificationCenter.default.removeObserver(self)
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        // The responder change fires inside `makeFirstResponder`, before SwiftUI finishes setting up
        // its field editor (and SwiftUI then sets its own flags), so sync again on the next turn.
        observation = newWindow.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.sync()
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.sync() } }
            }
        }
        let center = NotificationCenter.default
        for name in [NSText.didChangeNotification, NSControl.textDidBeginEditingNotification,
                     NSControl.textDidEndEditingNotification] {
            center.addObserver(self, selector: #selector(editingChanged(_:)), name: name, object: nil)
        }
    }

    @objc private func editingChanged(_ note: Notification) { sync() }

    /// Applies the policy while the window's field editor edits a field inside this footprint,
    /// re-applies on every change (Edit > Substitutions can be toggled mid-edit), and restores
    /// as soon as another responder takes over.
    private func sync() {
        guard window != nil else { restoreActive(); return }
        let current = window?.firstResponder as? NSTextView
        if let active, active.textView !== current { restoreActive() }
        if let active {
            if let textView = active.textView { _ = LumenExactTextPolicy.apply(to: textView) }
        } else if let textView = current, textView.isFieldEditor,
                  let field = textView.delegate as? NSTextField, contains(field) {
            active = Active(textView: textView, snapshot: LumenExactTextPolicy.apply(to: textView))
        }
    }

    private func restoreActive() {
        guard let held = active else { return }
        active = nil
        if let textView = held.textView { LumenExactTextPolicy.restore(held.snapshot, on: textView) }
    }

    /// Frames are compared at call time in window coordinates, so scrolling and resizing are covered.
    private func contains(_ field: NSTextField) -> Bool {
        guard field.window === window else { return false }
        let probe = convert(bounds, to: nil).insetBy(dx: -1, dy: -1)
        return probe.contains(field.convert(field.bounds, to: nil))
    }
}
