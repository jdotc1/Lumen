import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenShortcutsSheetTests: XCTestCase {
    func testGroupsMatchTheDefinitionsInstalledByViewCommands() {
        let commands = LumenViewCommands()
        let groups = commands.shortcutGroups
        XCTAssertEqual(groups.map(\.title), ["View", "Window"])
        let advertised = groups.flatMap(\.shortcuts)
        let installed = commands.commandDefinitions
        XCTAssertEqual(advertised.map(\.id), installed.map(\.id))
        XCTAssertEqual(advertised.map(\.title), installed.map(\.title))
        XCTAssertEqual(advertised.map { LumenKeycap.text(for: $0.shortcut) },
                       installed.compactMap { $0.shortcut.map(LumenKeycap.text(for:)) })
        XCTAssertEqual(advertised.count, 6)
    }

    func testCustomizedAndUnassignedCommandsCannotDrift() {
        var shortcuts = LumenViewShortcuts.standard
        shortcuts.panel = KeyboardShortcut("y", modifiers: [.control, .command])
        shortcuts.inspector = nil
        let commands = LumenViewCommands(shortcuts: shortcuts, commandPalette: false, tabNavigation: false)
        let advertised = commands.shortcutGroups.flatMap(\.shortcuts)
        XCTAssertEqual(advertised.map(\.id), ["navigator", "panel"])
        XCTAssertEqual(advertised.map { LumenKeycap.text(for: $0.shortcut) }, ["⌃⌘S", "⌃⌘Y"])
        XCTAssertEqual(advertised.map(\.id), commands.commandDefinitions.filter { $0.shortcut != nil }.map(\.id))
    }

    func testPaneGroupsUseDisplayedOrderAndOnlyAssignedNumbers() {
        let panes = (1...11).map { "Pane \($0)" }
        let groups = LumenViewCommands().shortcutGroups(panes: panes)
        let entries = groups.flatMap(\.shortcuts).filter { $0.id.hasPrefix("pane-") }
        XCTAssertEqual(entries.count, 9)
        XCTAssertEqual(entries.first?.title, "Show Pane 1")
        XCTAssertEqual(entries.last?.title, "Show Pane 9")
        XCTAssertEqual(entries.map { LumenKeycap.text(for: $0.shortcut) }, (1...9).map { "⌘\($0)" })
    }

    func testSearchFiltersTitlesAndPreservesIdentity() {
        let groups = LumenViewCommands().shortcutGroups
        let filtered = LumenShortcutsSheet.filtered(groups, query: "  TAB  ")
        XCTAssertEqual(filtered.map(\.id), ["Window"])
        XCTAssertEqual(filtered.flatMap(\.shortcuts).map(\.id), ["previousTab", "nextTab"])
        XCTAssertTrue(LumenShortcutsSheet.filtered(groups, query: "unmatched-command").isEmpty)
        XCTAssertEqual(LumenShortcutsSheet.filtered(groups, query: " ").map(\.id), groups.map(\.id))
    }

    func testHelpShortcutHasOneDefinitionAndDoesNotCollide() {
        let help = LumenShortcutsCommands.shortcutGroups.flatMap(\.shortcuts)
        XCTAssertEqual(help.count, 1)
        XCTAssertEqual(LumenKeycap.text(for: help[0].shortcut), "⌘/")
        let registered = LumenShortcuts.all.filter {
            LumenKeycap.text(for: $0.shortcut) == LumenKeycap.text(for: LumenShortcuts.keyboardShortcuts)
        }
        XCTAssertEqual(registered.count, 1)
    }

    func testSparseSheetUsesContentHeightAndLargeGroupsStayBounded() {
        let sparse = [LumenShortcutGroup(title: "View", shortcuts: [
            LumenShortcut(title: "Command Palette", shortcut: .init("k"))
        ])]
        let large = [LumenShortcutGroup(title: "View", shortcuts: (0..<50).map {
            LumenShortcut(title: "Command \($0)", shortcut: .init("k"))
        })]
        let sparseHeight = NSHostingView(rootView: LumenShortcutsSheet(groups: sparse)
            .frame(width: 360).fixedSize(horizontal: false, vertical: true).lumenPaletteRoot()).fittingSize.height
        let largeHeight = NSHostingView(rootView: LumenShortcutsSheet(groups: large)
            .frame(width: 360).fixedSize(horizontal: false, vertical: true).lumenPaletteRoot()).fittingSize.height
        XCTAssertGreaterThan(sparseHeight, 100)
        XCTAssertLessThan(sparseHeight, 400, "One shortcut must not occupy the maximum sheet height")
        XCTAssertLessThanOrEqual(largeHeight, 560)
        XCTAssertGreaterThan(largeHeight, sparseHeight)
    }

    func testSheetFitsItsDeclaredMinimumWidthWithLongTitles() {
        let groups = [LumenShortcutGroup(title: "Long group heading that wraps", shortcuts: [
            LumenShortcut(title: "A long descriptive command title must wrap into complete lines", shortcut: .init("k"))
        ])]
        XCTAssertLessThanOrEqual(LumenLayout.minimumWidth(of: LumenShortcutsSheet(groups: groups)), 320)
    }
}
