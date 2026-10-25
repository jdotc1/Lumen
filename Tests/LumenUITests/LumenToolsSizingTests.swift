import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenToolsSizingTests: XCTestCase {
    private func measured(_ view: some View, width: CGFloat, scale: Double = 1) -> CGSize {
        NSHostingController(rootView: view.lumenMetrics(.resolving(nil, textScale: scale)))
            .sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    func testCollectionLongTitleHonorsHostAndStacksWhenNarrow() {
        let collection = LumenCollection([
            LumenCollectionItem(id: "long", title: "Deployment configuration and production environment settings",
                                detail: "~/Projects/Production", date: Date(timeIntervalSince1970: 0)),
        ], mode: .list, selection: .constant(nil), sort: .constant(.date)) { _ in }
        let wide = measured(collection, width: 620)
        let narrow = measured(collection, width: 220)
        let scaled = measured(collection, width: 220, scale: 1.3)
        XCTAssertLessThanOrEqual(narrow.width, 220.5)
        XCTAssertLessThanOrEqual(scaled.width, 220.5)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertGreaterThan(scaled.height, narrow.height)
    }

    func testRecorderAutomaticWidthGrowsWhileExplicitWidthIsPreserved() {
        let automatic = LumenShortcutRecorder(shortcut: .constant(KeyboardShortcut("k", modifiers: [.command, .shift])))
        let base = measured(automatic, width: 600)
        let scaled = measured(automatic, width: 600, scale: 1.3)
        XCTAssertGreaterThan(scaled.width, base.width)
        let explicit = LumenShortcutRecorder(shortcut: .constant(nil), width: 170)
        XCTAssertEqual(measured(explicit, width: 600, scale: 1.3).width, 170, accuracy: 0.5)
    }
}
