import AppKit
import SwiftUI
import XCTest
import LumenConformance
@testable import LumenUI

/// Design review 2026-11 #4: in a two-pane split at the Catalog's 420 pt column, the pane bar's
/// three split buttons left the tab strip ~70 pt and "Listing.swift" read "Li…ft". A narrow pane
/// folds those buttons into one menu so its selected tab keeps a readable title.
@MainActor final class LumenSplitEditorNarrowPaneTests: XCTestCase {
    private func editor(width: CGFloat) -> some View {
        let layout = LumenEditorLayout(panes: [
            LumenEditorPane(id: "L", tabs: [
                LumenDocumentTab(id: "pkg", title: "Package.swift", systemImage: "shippingbox", hue: .hueOrange, isPinned: true),
                LumenDocumentTab(id: "listing", title: "Listing.swift", systemImage: "swift", hue: .hueOrange, isEdited: true),
            ], selection: "listing"),
            LumenEditorPane(id: "R", tabs: [LumenDocumentTab(id: "zsh", title: "zsh", systemImage: "terminal", hue: .hueTeal)]),
        ], focusedPaneID: "L")
        return LumenSplitEditor(layout: .constant(layout), minimumPaneWidth: 160) { _ in Color.clear }
            .frame(width: width, height: 170)
    }

    func testNarrowPaneKeepsItsTabTitleReadable() throws {
        let m = LumenMetrics.standard
        let titles = LumenDocumentTabTitles()
        let size = CGSize(width: 420, height: 170)
        let host = NSHostingView(rootView: editor(width: size.width).lumenPaletteRoot()
            .environment(\.lumenRendersOffscreen, true)
            .environment(\.lumenDocumentTabTitles, titles))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        print("SPLIT-NARROW threshold-parts minTab=\(LumenDocumentTabBar.minimumTabWidth(m)) truncations=\(titles.truncations) receipts=\(titles.values)")
        XCTAssertEqual(titles.truncations["listing"], false, "the selected tab's title must not truncate")
        XCTAssertFalse(window.isVisible)
    }
}
