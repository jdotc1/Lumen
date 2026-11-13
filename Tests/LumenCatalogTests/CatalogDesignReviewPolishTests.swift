import Foundation
import XCTest

/// Design review 2026-11, S3 polish on Catalog pages (#15, #16, #17, #20, #21). The page sources are
/// read back so a later edit cannot quietly bring a defect back; the rendered layout audits and
/// goldens cover how the pages look.
final class CatalogDesignReviewPolishTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LumenCatalog/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// #15: an ungrouped first item floated above the first group header with no header of its own.
    func testEveryBrowseItemBelongsToAGroup() throws {
        let text = try source("CatalogBrowsePage.swift")
        let items = text.components(separatedBy: "LumenCollectionItem(id:").dropFirst()
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let call = item.components(separatedBy: "),\n").first ?? item
            XCTAssertTrue(call.contains("group:"), "Browse item without a group: \(call.prefix(80))")
        }
    }

    /// #16: the Menu Bar Panel page was the only page without a page header, and its row icons had
    /// no fixed column.
    func testMenuBarPanelPageHasHeaderAndIconColumn() throws {
        let app = try source("LumenCatalogApp.swift")
        XCTAssertTrue(app.contains("case .menuBar: CatalogMenuBarPanelPage()"))
        let panel = try source("CatalogMenuBarPanel.swift")
        XCTAssertTrue(panel.contains("PageHeader(title: \"Menu Bar Panel\""))
        XCTAssertFalse(panel.contains("icon: { Image(systemName:"), "Row icons go through the fixed-width label")
    }

    /// #17: the debugger deck's panes each picked a fixed width, so one column held three widths.
    func testDebuggerPanesShareTheColumn() throws {
        let text = try source("CatalogInspectorPages.swift")
        let debugger = text.components(separatedBy: "struct DebuggerPage").dropFirst().first ?? ""
        let page = debugger.components(separatedBy: "\nstruct ").first ?? debugger
        XCTAssertFalse(page.contains(".frame(width: 3"), "A debugger pane has a fixed width")
        XCTAssertFalse(page.contains(".frame(maxWidth: 380)"))
    }

    /// #20: the Conformance page was a bare text list, unlike every other page.
    func testConformanceEntriesAreRowsInACard() throws {
        let text = try source("CatalogConformancePage.swift")
        XCTAssertTrue(text.contains("LumenListRow(check.title"))
        XCTAssertTrue(text.contains(".lumenCard(padding: 0)"))
    }

    /// #21: page-level explanations on Motion and Scale were set in caption type, smaller than every
    /// other page's description, and the motion samples sat in a fixed empty band.
    func testMotionAndScaleUsePageDescriptionType() throws {
        let motion = try source("CatalogMotionPage.swift")
        XCTAssertFalse(motion.contains(".frame(height: 32)"))
        let themeLine = motion.components(separatedBy: "Text(\"Theme motion:").dropFirst().first ?? ""
        XCTAssertFalse(themeLine.prefix(160).contains(".font(.caption)"))
        let scale = try source("CatalogScalePage.swift")
        let budget = scale.components(separatedBy: "Text(\"First layout includes").dropFirst().first ?? ""
        XCTAssertFalse(budget.prefix(400).contains(".font(.caption)"))
    }
}
