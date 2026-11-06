import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenListRowContextTests: XCTestCase {
    private func render(_ row: AnyView, inSidebar: Bool) throws -> Data {
        let subject: AnyView
        if inSidebar {
            subject = AnyView(LumenStackedSidebar([
                LumenStackedPane(id: "rows", title: "Rows", systemImage: "list.bullet") { row }
            ], collapsed: .constant([])))
        } else {
            subject = AnyView(row.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        }
        return try XCTUnwrap(LumenSnapshot.png(of: subject.environment(\.appearsActive, true),
                                               size: CGSize(width: 320, height: 120),
                                               variant: .init(themeID: LumenThemes.standardID, colorScheme: .light),
                                               registry: .core))
    }

    func testOmittedAndExplicitContextsInsideSidebarForBothInitializers() throws {
        // Both forms must resolve unambiguously at the call site, and the actual sidebar must
        // supply the inferred role. Compare rendered output so fill, typography and inset all count.
        let forms: [(name: String, omitted: AnyView, content: AnyView, sidebar: AnyView, inferred: AnyView)] = [
            ("without trailing",
             AnyView(LumenListRow("Selected row", isSelected: true)),
             AnyView(LumenListRow("Selected row", isSelected: true, context: .content)),
             AnyView(LumenListRow("Selected row", isSelected: true, context: .sidebar)),
             AnyView(LumenListRow("Selected row", isSelected: true, context: nil))),
            ("with trailing",
             AnyView(LumenListRow("Selected row", isSelected: true) { Text("7") }),
             AnyView(LumenListRow("Selected row", isSelected: true, context: .content) { Text("7") }),
             AnyView(LumenListRow("Selected row", isSelected: true, context: .sidebar) { Text("7") }),
             AnyView(LumenListRow("Selected row", isSelected: true, context: nil) { Text("7") }))
        ]
        for form in forms {
            let omitted = try render(form.omitted, inSidebar: true)
            let content = try render(form.content, inSidebar: true)
            let sidebar = try render(form.sidebar, inSidebar: true)
            let inferred = try render(form.inferred, inSidebar: true)
            XCTAssertEqual(LumenSnapshot.compare(omitted, sidebar).differingPixelFraction, 0, form.name)
            XCTAssertEqual(LumenSnapshot.compare(inferred, sidebar).differingPixelFraction, 0, form.name)
            XCTAssertGreaterThan(LumenSnapshot.compare(content, sidebar).differingPixelFraction, 0.001,
                                 "Explicit content must override the sidebar role: \(form.name)")
            let outsideOmitted = try render(form.omitted, inSidebar: false)
            let outsideContent = try render(form.content, inSidebar: false)
            XCTAssertEqual(LumenSnapshot.compare(outsideOmitted, outsideContent).differingPixelFraction, 0,
                           "Omitted context outside a sidebar must remain content: \(form.name)")
        }
    }
}
