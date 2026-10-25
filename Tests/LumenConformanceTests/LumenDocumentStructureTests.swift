import LumenTokens
import LumenUI
import SwiftUI
import XCTest
@testable import LumenConformance

@MainActor
final class LumenDocumentStructureTests: XCTestCase {
    private let minimum = CGSize(width: 640, height: 400)
    private let restored = CGSize(width: 1440, height: 900)

    private func window(placement: LumenTopBarPlacement = .unified,
                        chrome: LumenDocumentChromeEntry = .init(hasTitle: true, hasModifiedState: true)) -> some View {
        Color.clear
            .preference(key: LumenDocumentChromeKey.self, value: [chrome])
            .lumenTopBar { LumenTopBar { Text("Notes") } trailing: { Text("Saved") } }
            .lumenTopBarPlacement(placement)
    }

    func testDocumentHasDistinctIdentityAndRequiresASubject() {
        let check = LumenConformance.windowStructure(kind: .document)
        XCTAssertEqual(Set([LumenConformance.WindowKind.workspace, .utility, .library, .document]).count, 4)
        XCTAssertEqual(check.id, "lumen.windowStructure.document")
        XCTAssertEqual(check.owner, "Lumen")
        XCTAssertEqual(LumenConformance.run([check], in: [.init()]), [
            .init(.layout, "Document window", "requires a subject"),
        ])
    }

    func testDocumentRequiresBarTitleAndModifiedStateAtEverySize() {
        let findings = LumenConformance.windowStructure(kind: .document, sizes: [minimum, restored]) {
            Color.clear
        }
        XCTAssertEqual(findings.map(\.description), [
            "layout · 640×400: document title is not reported; use LumenDocumentWindow",
            "layout · 640×400: document modified state is not reported; use LumenDocumentWindow",
            "layout · 640×400: has no Lumen top bar; use LumenDocumentWindow or .lumenTopBar",
            "layout · 1440×900: document title is not reported; use LumenDocumentWindow",
            "layout · 1440×900: document modified state is not reported; use LumenDocumentWindow",
            "layout · 1440×900: has no Lumen top bar; use LumenDocumentWindow or .lumenTopBar",
        ])
    }

    func testDocumentRequiresUnifiedPlacement() {
        XCTAssertEqual(LumenConformance.windowStructure(kind: .document, sizes: [minimum]) {
            window()
        }, [])
        XCTAssertEqual(LumenConformance.windowStructure(kind: .document, sizes: [minimum]) {
            window(placement: .underTitleBar)
        }.map(\.message), ["the document top bar must share the window buttons' line; use .unified placement"])
    }

    func testMissingChromePartsAreReportedIndependently() {
        XCTAssertEqual(WindowStructureCheck.documentChromeMessages([.init(hasTitle: false, hasModifiedState: true)]), [
            "document title is not reported; use LumenDocumentWindow",
        ])
        XCTAssertEqual(WindowStructureCheck.documentChromeMessages([.init(hasTitle: true, hasModifiedState: false)]), [
            "document modified state is not reported; use LumenDocumentWindow",
        ])
        XCTAssertEqual(WindowStructureCheck.documentChromeMessages([
            .init(hasTitle: true, hasModifiedState: true), .init(hasTitle: false, hasModifiedState: false),
        ]).count, 2)
    }

    func testOtherKindsDoNotRequireDocumentChrome() {
        for kind in [LumenConformance.WindowKind.workspace, .utility] {
            XCTAssertEqual(LumenConformance.windowStructure(kind: kind, sizes: [minimum]) {
                window(chrome: .init(hasTitle: false, hasModifiedState: false))
            }, [])
        }
    }

    func testDocumentReportsSharedTruncation() {
        let findings = LumenConformance.windowStructure(kind: .document, sizes: [minimum]) {
            Text("Document description")
                .lineLimit(1)
                .lumenNeverTruncates("Document description")
                .frame(width: 30)
                .preference(key: LumenDocumentChromeKey.self, value: [.init(hasTitle: true, hasModifiedState: true)])
                .lumenTopBar { LumenTopBar { Text("Notes") } trailing: { Text("Saved") } }
        }
        XCTAssertEqual(findings.map(\.message), ["“Document description” is cut short"])
    }

    func testRunnerUsesItsSizesAndVariants() {
        let context = LumenCheckContext(sizes: [minimum, restored], variants: [
            .init(themeID: LumenThemes.standardID, colorScheme: .light),
            .init(themeID: LumenThemes.midnightID, colorScheme: .dark),
        ], subject: ("Notes", AnyView(window(chrome: .init(hasTitle: false, hasModifiedState: true)))))
        let findings = LumenConformance.run([LumenConformance.windowStructure(kind: .document)], in: [context])
        XCTAssertEqual(findings.map(\.subject), ["640×400", "1440×900", "640×400", "1440×900"])
        XCTAssertTrue(findings.allSatisfy { $0.message == "document title is not reported; use LumenDocumentWindow" })
    }

    func testArchetypeConformsAtMinimumAndRestoredSizeInBothModifiedStates() {
        for modified in [false, true] {
            XCTAssertEqual(LumenConformance.windowStructure(kind: .document, sizes: [minimum, restored]) {
                LumenDocumentWindow(title: .constant("Notes"), isModified: modified) {
                    Text("Document contents").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }, [])
        }
    }
}
