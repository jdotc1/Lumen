import LumenTokens
import LumenUI
import SwiftUI
import XCTest
@testable import LumenConformance

@MainActor
final class LumenWindowStructureTests: XCTestCase {
    private let size = CGSize(width: 900, height: 560)

    private func window(placement: LumenTopBarPlacement = .unified) -> some View {
        Color.clear
            .lumenTopBar { LumenTopBar { Text("Files") } trailing: { Text("Ready") } }
            .lumenTopBarPlacement(placement)
    }

    func testKindsHaveDistinctCheckIdentitiesAndRequireASubject() {
        let checks: [any LumenCheck] = [LumenConformance.windowStructure(kind: .workspace),
                                      LumenConformance.windowStructure(kind: .utility)]
        XCTAssertEqual(Set([LumenConformance.WindowKind.workspace, .utility]).count, 2)
        XCTAssertEqual(checks.map(\.id), ["lumen.windowStructure.workspace", "lumen.windowStructure.utility"])
        XCTAssertEqual(checks.map(\.owner), ["Lumen", "Lumen"])
        XCTAssertEqual(LumenConformance.run(checks, in: [.init()]), [
            .init(.layout, "Workspace window", "requires a subject"),
            .init(.layout, "Utility window", "requires a subject"),
        ])
    }

    func testUtilityRequiresALumenBarAtEachSize() {
        let findings = LumenConformance.windowStructure(kind: .utility, sizes: [size, CGSize(width: 1440, height: 900)]) {
            Color.clear
        }
        XCTAssertEqual(findings.map(\.description), [
            "layout · 900×560: has no Lumen top bar; use LumenUtilityWindow or .lumenTopBar",
            "layout · 1440×900: has no Lumen top bar; use LumenUtilityWindow or .lumenTopBar",
        ])
    }

    func testUtilityAcceptsTheUnifiedBar() {
        XCTAssertEqual(LumenConformance.windowStructure(kind: .utility, sizes: [size]) { window() }, [])
    }

    func testUtilityRejectsTheLegacyTitleBarPlacement() {
        let findings = LumenConformance.windowStructure(kind: .utility, sizes: [size]) {
            window(placement: .underTitleBar)
        }
        XCTAssertEqual(findings.map(\.message), [
            "the utility top bar must share the window buttons' line; use .unified placement",
        ])
    }

    func testWorkspaceKindRetainsTheLegacyTitleBarPlacement() {
        XCTAssertEqual(LumenConformance.windowStructure(kind: .workspace, sizes: [size]) {
            window(placement: .underTitleBar)
        }, [])
    }

    func testLegacyCheckRetainsItsIdentityAndPanelSubjects() {
        let check = WorkspaceWindowCheck(panels: [
            .init(leading: false, bottom: false, trailing: false),
            .init(leading: true, bottom: true, trailing: true),
        ], window: { _ in AnyView(Color.clear) })
        XCTAssertEqual(check.id, "lumen.workspaceWindow")
        XCTAssertEqual(check.title, "Workspace window")
        XCTAssertEqual(LumenConformance.run([check], in: [.init(sizes: [size])]).map(\.description), [
            "layout · 900×560, no panels: has no Lumen top bar; use LumenWorkspaceWindow or .lumenTopBar",
            "layout · 900×560, sidebar + bottom + inspector: has no Lumen top bar; use LumenWorkspaceWindow or .lumenTopBar",
        ])
    }

    func testRunnerUsesItsSizesAndVariants() {
        let context = LumenCheckContext(sizes: [size, CGSize(width: 1440, height: 900)], variants: [
            .init(themeID: LumenThemes.standardID, colorScheme: .light),
            .init(themeID: LumenThemes.midnightID, colorScheme: .dark),
        ], subject: ("Files", AnyView(Color.clear)))
        let findings = LumenConformance.run([LumenConformance.windowStructure(kind: .utility)], in: [context])
        XCTAssertEqual(findings.map(\.subject), ["900×560", "1440×900", "900×560", "1440×900"])
        XCTAssertTrue(findings.allSatisfy { $0.message == "has no Lumen top bar; use LumenUtilityWindow or .lumenTopBar" })
    }

    func testUtilityReportsTruncationThroughTheSharedCheck() {
        let findings = LumenConformance.windowStructure(kind: .utility, sizes: [size]) {
            Text("Source file description")
                .lineLimit(1)
                .lumenNeverTruncates("Source file description")
                .frame(width: 30)
                .lumenTopBar { LumenTopBar { Text("Files") } trailing: { Text("Ready") } }
        }
        XCTAssertEqual(findings.map(\.message), ["“Source file description” is cut short"])
    }
}
