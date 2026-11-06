import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenUI
import LumenConformance
@testable import LumenCatalog

/// PRINCIPLES §6–7 across the whole Catalog: on every page and every page's inspector, no primary
/// label is cut short and no icon tile is under its role's size, at the column's minimum width and
/// at a roomy 1100 pt. The height is generous so nothing is squeezed vertically; only width is under
/// test.
///
/// Findings are allow-listed by exact message. New and stale entries fail independently.
@MainActor
final class LumenCatalogRuleTests: XCTestCase {
    static let tall: CGFloat = 4000

    /// Exact findings, as "<page> page|inspector · <check> · <Finding.description>".
    /// An empty set requires every marked label and tile on every page to pass.
    static let knownFindings: Set<String> = []

    private func page(_ page: CatalogPage) -> some View {
        // As the Catalog's detail column shows it.
        ScrollView {
            CatalogPageView(page: page).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func inspector(_ page: CatalogPage) -> some View {
        LumenInspector { CatalogInspector(page: page, hue: .constant(page.hue)) }
    }

    private func findings<V: View>(_ subject: String, widths: [CGFloat], _ view: () -> V) -> [String] {
        let sizes = widths.map { CGSize(width: $0, height: Self.tall) }
        let truncation = LumenConformance.truncation(sizes: sizes, of: view).map { "\(subject) · truncation · \($0)" }
        let icons = LumenConformance.iconScale(sizes: sizes, of: view).map { "\(subject) · iconScale · \($0)" }
        let clips = LumenConformance.overflow(sizes: sizes, of: view).map { "\(subject) · overflow · \($0)" }
        return truncation + icons + clips
    }

    func testEveryPageAndInspectorKeepsItsLabelsAndIconScale() {
        var all: [String] = []
        for catalogPage in CatalogPage.allCases {
            all += findings("\(catalogPage) page", widths: [CatalogLayout.pageMinWidth, 1100]) { page(catalogPage) }
            all += findings("\(catalogPage) inspector", widths: [LumenLayout.inspectorColumn.min]) { inspector(catalogPage) }
        }
        let found = Set(all)
        let new = found.subtracting(Self.knownFindings).sorted()
        let stale = Self.knownFindings.subtracting(found).sorted()
        XCTAssertEqual(new, [], "new findings:\n" + new.joined(separator: "\n"))
        XCTAssertEqual(stale, [], "allow-listed findings no longer occur; remove them:\n" + stale.joined(separator: "\n"))
    }
}
