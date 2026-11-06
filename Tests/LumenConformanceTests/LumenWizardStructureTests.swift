import SwiftUI
import XCTest
import LumenUI
@testable import LumenConformance

@MainActor
final class LumenWizardStructureTests: XCTestCase {
    private typealias Entry = LumenWizardLayoutEntry
    private let size = CGSize(width: 640, height: 460)

    private var valid: [Entry] {
        [
            .init(region: .window, frame: .init(origin: .zero, size: size), pageCount: 4),
            .init(region: .stepList, frame: .init(x: 0, y: 0, width: 180, height: 400)),
            .init(region: .currentPage, frame: .init(x: 181, y: 0, width: 459, height: 400)),
            .init(region: .bottomBar, frame: .init(x: 0, y: 400, width: 640, height: 60)),
            .init(region: .cancelButton, frame: .init(x: 20, y: 418, width: 80, height: 24)),
            .init(region: .backButton, frame: .init(x: 428, y: 418, width: 80, height: 24)),
            .init(region: .continueButton, frame: .init(x: 520, y: 418, width: 100, height: 24), isDefaultAction: true),
        ]
    }

    func testKindIdentityAndMissingScaffold() {
        let check = LumenConformance.windowStructure(kind: .wizard)
        XCTAssertEqual(check.id, "lumen.windowStructure.wizard")
        XCTAssertEqual(Set([LumenConformance.WindowKind.workspace, .utility, .library, .document, .menuBarPanel, .wizard]).count, 6)
        XCTAssertEqual(LumenConformance.run([check], in: [.init()]), [
            .init(.layout, "Wizard window", "requires a subject"),
        ])
        XCTAssertEqual(LumenConformance.windowStructure(kind: .wizard, sizes: [size]) {
            Color.clear
        }.map(\.message), ["has no wizard geometry; use LumenWizardWindow"])
    }

    func testValidGeometryAndEmptyStatePass() {
        XCTAssertEqual(WindowStructureCheck.wizardMessages(valid, size: size), [])
        var empty = valid
        empty[0] = .init(region: .window, frame: empty[0].frame)
        empty[2] = .init(region: .emptyState, frame: empty[2].frame)
        XCTAssertEqual(WindowStructureCheck.wizardMessages(empty, size: size), [])
    }

    func testMissingAndDuplicateCurrentPagesFail() {
        let missing = valid.filter { $0.region != .currentPage }
        XCTAssertTrue(WindowStructureCheck.wizardMessages(missing, size: size).contains {
            $0.contains("exactly one current page")
        })
        XCTAssertTrue(WindowStructureCheck.wizardMessages(valid + [valid[2]], size: size).contains {
            $0.contains("exactly one current page")
        })
        var emptyWithPage = valid
        emptyWithPage[0] = .init(region: .window, frame: emptyWithPage[0].frame)
        XCTAssertTrue(WindowStructureCheck.wizardMessages(emptyWithPage, size: size).contains {
            $0.contains("none when empty")
        })
    }

    func testMissingStepListAndBarWidthFail() {
        let missing = valid.filter { $0.region != .stepList }
        XCTAssertTrue(WindowStructureCheck.wizardMessages(missing, size: size).contains {
            $0 == "the wizard stepList is missing or duplicated"
        })
        var insetBar = valid
        insetBar[3] = .init(region: .bottomBar, frame: .init(x: 10, y: 400, width: 620, height: 60))
        XCTAssertTrue(WindowStructureCheck.wizardMessages(insetBar, size: size).contains {
            $0 == "the wizard bottom bar must span the full window width"
        })
    }

    func testContinueMustBeTheOnlyTrailingDefaultAction() {
        var wrongDefault = valid
        wrongDefault[6] = .init(region: .continueButton, frame: wrongDefault[6].frame)
        XCTAssertEqual(WindowStructureCheck.wizardMessages(wrongDefault, size: size), [
            "Continue must be the wizard's only default action",
        ])
        var twoDefaults = valid
        twoDefaults[5] = .init(region: .backButton, frame: twoDefaults[5].frame, isDefaultAction: true)
        XCTAssertEqual(WindowStructureCheck.wizardMessages(twoDefaults, size: size), [
            "Continue must be the wizard's only default action",
        ])
        var leadingContinue = valid
        leadingContinue[4] = .init(region: .cancelButton, frame: valid[6].frame)
        leadingContinue[6] = .init(region: .continueButton, frame: valid[4].frame, isDefaultAction: true)
        XCTAssertEqual(WindowStructureCheck.wizardMessages(leadingContinue, size: size), [
            "Continue must be the wizard's trailing button",
        ])
    }

    func testOverlapsAndOutOfBoundsFail() {
        var overlap = valid
        overlap[2] = .init(region: .currentPage, frame: .init(x: 170, y: 0, width: 470, height: 420))
        let messages = WindowStructureCheck.wizardMessages(overlap, size: size)
        XCTAssertTrue(messages.contains("the wizard stepList overlaps its currentPage"))
        XCTAssertTrue(messages.contains("the wizard currentPage overlaps its bottomBar"))
        var escaping = valid
        escaping[6] = .init(region: .continueButton, frame: .init(x: 600, y: 418, width: 100, height: 24), isDefaultAction: true)
        let escapingMessages = WindowStructureCheck.wizardMessages(escaping, size: size)
        XCTAssertTrue(escapingMessages.contains("the wizard continueButton exceeds the window bounds"))
        XCTAssertTrue(escapingMessages.contains("the wizard continueButton exceeds the bottom bar bounds"))
        XCTAssertTrue(WindowStructureCheck.wizardMessages(valid, size: .init(width: 600, height: 440)).contains {
            $0 == "the wizard exceeds its host bounds"
        })
    }

    func testSeededBrokenLayoutReportsStructureAndSharedTruncation() {
        let seeded = valid.filter { $0.region != .stepList }
        let messages = LumenConformance.windowStructure(kind: .wizard, sizes: [size]) {
            Text("Wizard description that must remain visible")
                .lineLimit(1)
                .lumenNeverTruncates("Wizard description that must remain visible")
                .frame(width: 30)
                .preference(key: LumenWizardLayoutKey.self, value: seeded)
        }.map(\.message)
        XCTAssertTrue(messages.contains("the wizard stepList is missing or duplicated"))
        XCTAssertTrue(messages.contains("“Wizard description that must remain visible” is cut short"))
        XCTAssertFalse(messages.contains { $0.contains("top bar") })
    }

    func testStructureCheckIncludesNarrowSizing() {
        let messages = LumenConformance.windowStructure(kind: .wizard, sizes: [size]) {
            Text(String(repeating: "A wizard page must keep its text readable. ", count: 8))
                .fixedSize(horizontal: false, vertical: true)
                .preference(key: LumenWizardLayoutKey.self, value: valid)
        }.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("measured 1 pt wide") })
    }
}
