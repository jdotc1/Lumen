import SwiftUI
import XCTest
import LumenUI
@testable import LumenConformance

@MainActor
final class LumenMenuBarPanelStructureTests: XCTestCase {
    func testKindIdentityAndMissingScaffold() {
        let check = LumenConformance.windowStructure(kind: .menuBarPanel)
        XCTAssertEqual(check.id, "lumen.windowStructure.menuBarPanel")
        XCTAssertEqual(Set([LumenConformance.WindowKind.workspace, .utility, .library, .menuBarPanel]).count, 4)
        XCTAssertEqual(LumenConformance.windowStructure(kind: .menuBarPanel, sizes: [.init(width: 280, height: 480)]) {
            Color.clear
        }.map(\.message), ["has no menu bar panel geometry; use LumenMenuBarPanel"])
    }

    func testMissingRegionsAndEscapingContentAreReported() {
        typealias Entry = LumenMenuBarPanelLayoutEntry
        let panel = Entry(region: .panel, frame: .init(x: 0, y: 0, width: 280, height: 480), hasHeader: true, hasFooter: true)
        XCTAssertEqual(WindowStructureCheck.menuBarPanelMessages([panel], size: panel.frame.size).count, 3)
        let content = Entry(region: .content, frame: .init(x: 0, y: 0, width: 280, height: 480))
        let scroll = Entry(region: .scrollContent, frame: .init(x: 0, y: 0, width: 300, height: 900))
        let noChrome = Entry(region: .panel, frame: panel.frame)
        XCTAssertEqual(WindowStructureCheck.menuBarPanelMessages([noChrome, content, scroll], size: panel.frame.size),
                       ["the menu bar panel scrolling content exceeds its width"])
        let tallScroll = Entry(region: .scrollContent, frame: .init(x: 0, y: -100, width: 280, height: 900))
        XCTAssertEqual(WindowStructureCheck.menuBarPanelMessages([noChrome, content, tallScroll], size: panel.frame.size), [])
        XCTAssertEqual(WindowStructureCheck.menuBarPanelMessages([noChrome, content], size: .init(width: 200, height: 400)),
                       ["the menu bar panel exceeds its host bounds"])
    }
}
