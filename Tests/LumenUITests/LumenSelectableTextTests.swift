import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSelectableTextTests: XCTestCase {
    private func textView(in view: NSView) -> NSTextView? {
        if let found = view as? NSTextView { return found }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    private func host(_ view: some View, width: CGFloat = 300, height: CGFloat = 200) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func background(_ view: NSTextView, at index: Int) -> NSColor? {
        view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
    }

    func testIsReadOnlyAndSelectableAndHoldsFullString() throws {
        let text = "alpha beta gamma"
        let view = try XCTUnwrap(textView(in: host(LumenSelectableText(text))))
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.isSelectable)
        XCTAssertEqual(view.string, text)
    }

    func testHighlightUsesAccentSubtleOnlyInsideRange() throws {
        let text = "alpha beta gamma"
        let root = host(LumenSelectableText(text, highlights: [LumenTextHighlight(NSRange(location: 6, length: 4), role: .match)]))
        let view = try XCTUnwrap(textView(in: root))
        let expected = NSColor(LumenThemeStore.active.resolvedPalette()[.accentSubtle])
        XCTAssertEqual(background(view, at: 6), expected)
        XCTAssertEqual(background(view, at: 9), expected)
        XCTAssertNil(background(view, at: 5))
        XCTAssertNil(background(view, at: 10))
    }

    func testOutOfRangeAndOverlongHighlightsClampWithoutCrashing() throws {
        let text = "short"
        let highlights = [LumenTextHighlight(NSRange(location: 3, length: 500)),
                          LumenTextHighlight(NSRange(location: 900, length: 4)),
                          LumenTextHighlight(NSRange(location: NSNotFound, length: 1)),
                          LumenTextHighlight(NSRange(location: 1, length: 0))]
        let view = try XCTUnwrap(textView(in: host(LumenSelectableText(text, highlights: highlights))))
        XCTAssertNotNil(background(view, at: 4))
        XCTAssertNil(background(view, at: 1))
        let empty = try XCTUnwrap(textView(in: host(LumenSelectableText("", highlights: highlights))))
        XCTAssertEqual(empty.string, "")
    }

    func testClampingWidensToComposedCharacters() {
        let text = "a👩🏽‍🚀b" as NSString
        // Start in the middle of the emoji sequence: the whole sequence is marked.
        let clipped = LumenSelectableTextRanges.clamped(NSRange(location: 2, length: 1), in: text)
        XCTAssertEqual(clipped, NSRange(location: 1, length: text.length - 2))
        XCTAssertNil(LumenSelectableTextRanges.clamped(NSRange(location: 0, length: 0), in: text))
        XCTAssertNil(LumenSelectableTextRanges.clamped(NSRange(location: text.length + 3, length: 2), in: text))
    }

    func testStringIndexRangeConvertsToUTF16OnEmojiAndCombiningMarks() {
        let text = "e\u{301}😀 target"
        let range = text.range(of: "target")!
        let highlight = LumenTextHighlight(range, in: text)
        XCTAssertEqual((text as NSString).substring(with: highlight.range), "target")
        XCTAssertEqual(highlight.range.location, 5, "é (2) + emoji (2) + space (1) are UTF-16 offsets")
        let reveal = LumenTextReveal(range, in: text, id: 3)
        XCTAssertEqual(reveal.range, highlight.range)
        XCTAssertEqual(reveal.id, 3)
    }

    func testRevealScrollsLateRangeIntoView() throws {
        let text = (0..<50_000).map { "line \($0)" }.joined(separator: "\n")
        let target = (text as NSString).range(of: "line 40000")
        let root = host(LumenSelectableText(text, highlights: [LumenTextHighlight(target)],
                                            reveal: LumenTextReveal(target, id: 1)))
        let view = try XCTUnwrap(textView(in: root))
        let scroll = try XCTUnwrap(view.enclosingScrollView)
        root.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        var rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: target, actualCharacterRange: nil), in: container)
        rect.origin.y += view.textContainerOrigin.y
        XCTAssertTrue(scroll.contentView.bounds.intersects(rect), "The revealed range is within the visible rect")
    }

    func testRerenderWithSameTextKeepsSelection() throws {
        let text = "alpha beta gamma delta"
        let hosting = NSHostingView(rootView: AnyView(LumenSelectableText(text).frame(width: 300, height: 200)))
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        hosting.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(textView(in: hosting))
        view.setSelectedRange(NSRange(location: 6, length: 4))
        hosting.rootView = AnyView(LumenSelectableText(text, highlights: [LumenTextHighlight(NSRange(location: 0, length: 5))])
            .frame(width: 300, height: 200))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 4))
        XCTAssertNotNil(background(view, at: 0))
    }

    func testHighlightMovesWhenHostChangesIt() throws {
        let text = "alpha beta gamma"
        let hosting = NSHostingView(rootView: AnyView(LumenSelectableText(text, highlights: [LumenTextHighlight(NSRange(location: 0, length: 5))])
            .frame(width: 300, height: 200)))
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        hosting.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(textView(in: hosting))
        XCTAssertNotNil(background(view, at: 0))
        hosting.rootView = AnyView(LumenSelectableText(text, highlights: [LumenTextHighlight(NSRange(location: 11, length: 5))])
            .frame(width: 300, height: 200))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNil(background(view, at: 0), "The previous highlight is removed")
        XCTAssertNotNil(background(view, at: 12))
    }

    func testPageOffsets() {
        let pages = ["ab", "cde", "f"]
        XCTAssertEqual(LumenSelectableText.offset(ofPage: 0, in: pages), 0)
        XCTAssertEqual(LumenSelectableText.offset(ofPage: 1, in: pages), 3)
        XCTAssertEqual(LumenSelectableText.offset(ofPage: 2, in: pages), 7)
        XCTAssertEqual(LumenSelectableText.offset(ofPage: 9, in: pages), 8)
        XCTAssertEqual(LumenSelectableText.offset(ofPage: 2, in: pages, separator: "\r\n"), 9)
        XCTAssertEqual(LumenSelectableText.offset(ofPage: -1, in: pages), 0)
        let joined = pages.joined(separator: "\n") as NSString
        XCTAssertEqual(joined.substring(from: LumenSelectableText.offset(ofPage: 2, in: pages)), "f")
    }
}
