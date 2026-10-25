import LumenConformance
import LumenUI
import SwiftUI
import XCTest
@testable import LumenCatalog

@MainActor
final class CatalogConformancePageTests: XCTestCase {
    func testAppChecksAreGroupedByTheirDeclaredOwner() {
        struct Check: LumenCheck {
            let id: String
            var title: String { id }
            let owner: String
            func run(in context: LumenCheckContext) -> [LumenConformance.Finding] { [] }
        }
        let groups = ConformancePage.groups(for: [Check(id: "one", owner: "Zed"), Check(id: "two", owner: "App"),
                                                  Check(id: "three", owner: "Zed")])
        XCTAssertEqual(groups.map(\.owner), ["App", "Zed"])
        XCTAssertEqual(groups.last?.checks.map(\.id), ["one", "three"])
        XCTAssertEqual(ConformancePage.builtIns.count, 13)
        XCTAssertTrue(CatalogPage.allCases.contains(.conformance))
    }

    func testConformancePageFitsTheCatalogColumn() {
        let column = LumenConformance.Column("Conformance", minWidth: CatalogLayout.pageMinWidth) {
            CatalogPageView(page: .conformance)
        }
        XCTAssertEqual(LumenConformance.layout(windowMinWidth: CatalogLayout.pageMinWidth, columns: [column]), [])
        let sizes = [CGSize(width: CatalogLayout.pageMinWidth, height: 1600), CGSize(width: 1100, height: 1600)]
        XCTAssertEqual(LumenConformance.truncation(sizes: sizes) { CatalogPageView(page: .conformance) }, [])
        XCTAssertEqual(LumenConformance.overflow(sizes: sizes) { CatalogPageView(page: .conformance) }, [])
    }
}
