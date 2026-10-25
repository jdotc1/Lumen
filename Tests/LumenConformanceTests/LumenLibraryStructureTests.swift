import LumenTokens
import LumenUI
import SwiftUI
import XCTest
@testable import LumenConformance

@MainActor
final class LumenLibraryStructureTests: XCTestCase {
    private let size = CGSize(width: 900, height: 560)

    private func entry(requested: LumenLibraryPanels = .init(),
                       explicit: LumenLibraryPanels = .init(sourceList: false, detail: false),
                       shown: LumenLibraryPanels = .init(),
                       sourceListMinimum: CGFloat? = 180,
                       detailMinimum: CGFloat? = 220) -> LumenLibraryLayoutEntry {
        .init(requested: requested, explicit: explicit, shown: shown,
              availableWidth: size.width, contentMinimum: 640,
              sourceListMinimum: sourceListMinimum, detailMinimum: detailMinimum)
    }

    private func window(placement: LumenTopBarPlacement = .unified,
                        layout: LumenLibraryLayoutEntry) -> some View {
        Color.clear
            .preference(key: LumenLibraryLayoutKey.self, value: [layout])
            .lumenTopBar { LumenTopBar { Text("Library") } trailing: { Text("Ready") } }
            .lumenTopBarPlacement(placement)
    }

    func testLibraryHasDistinctIdentityAndRequiresASubject() {
        let check = LumenConformance.windowStructure(kind: .library)
        XCTAssertEqual(Set([LumenConformance.WindowKind.workspace, .utility, .library]).count, 3)
        XCTAssertEqual(check.id, "lumen.windowStructure.library")
        XCTAssertEqual(check.owner, "Lumen")
        XCTAssertEqual(LumenConformance.run([check], in: [.init()]), [
            .init(.layout, "Library window", "requires a subject"),
        ])
    }

    func testLibraryRequiresBarAndCollapseReportingAtEverySize() {
        let findings = LumenConformance.windowStructure(kind: .library,
                                                       sizes: [size, CGSize(width: 1440, height: 900)]) {
            Color.clear
        }
        XCTAssertEqual(findings.map(\.description), [
            "layout · 900×560: library collapse order is not reported; use LumenLibraryWindow",
            "layout · 900×560: has no Lumen top bar; use LumenLibraryWindow or .lumenTopBar",
            "layout · 1440×900: library collapse order is not reported; use LumenLibraryWindow",
            "layout · 1440×900: has no Lumen top bar; use LumenLibraryWindow or .lumenTopBar",
        ])
    }

    func testLibraryAcceptsUnifiedBarAndReportsLegacyPlacement() {
        XCTAssertEqual(LumenConformance.windowStructure(kind: .library, sizes: [size]) {
            window(layout: entry())
        }, [])
        XCTAssertEqual(LumenConformance.windowStructure(kind: .library, sizes: [size]) {
            window(placement: .underTitleBar, layout: entry())
        }.map(\.message), ["the library top bar must share the window buttons' line; use .unified placement"])
    }

    func testLibraryReportsSourceCollapsingBeforeDetail() {
        let incorrect = entry(shown: .init(sourceList: false, detail: true))
        XCTAssertEqual(LumenConformance.windowStructure(kind: .library, sizes: [size]) {
            window(layout: incorrect)
        }.map(\.message), ["the detail pane must collapse before the source list at equal priority"])
        let bound = entry(explicit: .init(), shown: .init(sourceList: false, detail: true))
        XCTAssertEqual(WindowStructureCheck.libraryCollapseMessages([bound]), [
            "the detail pane must collapse before the source list at equal priority",
        ])
    }

    func testLibraryHonorsExplicitDetailPriorityAndHiddenOrAbsentSource() {
        let detailOnly = LumenLibraryPanels(sourceList: false, detail: true)
        let entries = [
            entry(explicit: detailOnly, shown: detailOnly),
            entry(requested: detailOnly, shown: detailOnly),
            entry(shown: detailOnly, sourceListMinimum: nil),
            entry(shown: .init(sourceList: true, detail: false)),
            entry(shown: .init(sourceList: false, detail: false)),
        ]
        for layout in entries {
            XCTAssertEqual(WindowStructureCheck.libraryCollapseMessages([layout]), [])
        }
    }

    func testOtherKindsIgnoreLibraryCollapseReports() {
        let incorrect = entry(shown: .init(sourceList: false, detail: true))
        for kind in [LumenConformance.WindowKind.workspace, .utility] {
            XCTAssertEqual(LumenConformance.windowStructure(kind: kind, sizes: [size]) {
                window(layout: incorrect)
            }, [])
        }
    }

    func testLibraryReportsTruncationThroughTheSharedCheck() {
        let findings = LumenConformance.windowStructure(kind: .library, sizes: [size]) {
            Text("Collection description")
                .lineLimit(1)
                .lumenNeverTruncates("Collection description")
                .frame(width: 30)
                .preference(key: LumenLibraryLayoutKey.self, value: [entry()])
                .lumenTopBar { LumenTopBar { Text("Library") } trailing: { Text("Ready") } }
        }
        XCTAssertEqual(findings.map(\.message), ["“Collection description” is cut short"])
    }

    func testRunnerUsesLibrarySizesAndVariants() {
        let subject = AnyView(window(layout: entry(shown: .init(sourceList: false, detail: true))))
        let context = LumenCheckContext(sizes: [size, CGSize(width: 1440, height: 900)], variants: [
            .init(themeID: LumenThemes.standardID, colorScheme: .light),
            .init(themeID: LumenThemes.midnightID, colorScheme: .dark),
        ], subject: ("Library", subject))
        let findings = LumenConformance.run([LumenConformance.windowStructure(kind: .library)], in: [context])
        XCTAssertEqual(findings.map(\.subject), ["900×560", "1440×900", "900×560", "1440×900"])
        XCTAssertTrue(findings.allSatisfy {
            $0.message == "the detail pane must collapse before the source list at equal priority"
        })
    }

    func testLibraryScaffoldStructureAtMinimumAndLargeSize() {
        for panels in LumenLibraryPanels.allCombinations {
            let findings = LumenConformance.windowStructure(kind: .library,
                                                           sizes: [CGSize(width: 640, height: 400),
                                                                   CGSize(width: 1440, height: 900)]) {
                LumenLibraryWindow(panels: .constant(panels)) {
                    Text("Items").frame(maxWidth: .infinity, maxHeight: .infinity)
                } sourceList: {
                    Text("Collections")
                } detail: {
                    Text("Metadata")
                } topLeading: {
                    Text("Library")
                }
            }
            XCTAssertEqual(findings, [], "Requested panels: \(panels)")
        }
    }
}
