import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSidebarWholeTileTests: XCTestCase {
    private let ids = (0..<10).map { "tool\($0)" }
    private var slot: CGFloat { LumenSidebarSwitcher.tileSlotWidth(tileSize: 28) }

    private func project(_ width: CGFloat, selection: String = "tool0", ids: [String]? = nil) -> LumenSidebarTileProjection {
        .project(visibleIDs: ids ?? self.ids, selection: selection, offeredWidth: width, slotWidth: slot)
    }

    func testTenWholeSlotsFitWithoutMoreButEpsilonRequiresItsOwnSlot() {
        XCTAssertEqual(project(10 * slot).tileIDs, ids, "Reject a fractional last tile")
        XCTAssertTrue(project(10 * slot).menuIDs.isEmpty)
        let narrow = project(10 * slot - 0.001)
        XCTAssertEqual(narrow.tileIDs, Array(ids.prefix(8)), "Reject a lost More reserve")
        XCTAssertEqual(narrow.menuIDs, Array(ids.suffix(2)))
    }

    func testOverflowingSlotsSpanTheOfferedWidthAndAFittingRowStaysTogether() {
        let spacing = LumenSidebarTileProjection.slotSpacing
        // Eight slots (seven tiles and More) in 8.8 slots of width: the last slot ends at the width.
        let gap = spacing(8, true, 8.8 * slot, slot)
        XCTAssertEqual(8 * slot + 7 * gap, 8.8 * slot, accuracy: 0.0001, "Reject a ragged trailing remainder")
        XCTAssertLessThan(7 * gap, slot, "Reject a remainder that would hold another slot")
        XCTAssertEqual(spacing(8, true, 8 * slot, slot), 0, "Reject spacing with no remainder")
        XCTAssertEqual(spacing(8, true, 8 * slot - 1, slot), 0, "Reject negative spacing")
        XCTAssertEqual(spacing(10, false, 12 * slot, slot), 0, "Reject spreading a row that fits")
        XCTAssertEqual(spacing(1, true, 3 * slot, slot), 0, "Reject division by zero for one slot")
        XCTAssertEqual(spacing(8, true, .nan, slot), 0)
        XCTAssertEqual(spacing(8, true, 9 * slot, 0), 0)
    }

    func testEveryBoundaryRejectsFractionalTilesLostReserveAndUpwardRounding() {
        for j in 2...9 {
            let exact = project(CGFloat(j) * slot)
            XCTAssertEqual(exact.tileIDs.count, j - 1, "Reject a lost More reserve at \(j)")
            XCTAssertEqual(exact.tileIDs.count + exact.menuIDs.count, ids.count, "Reject a missing tool")
            let below = project(CGFloat(j) * slot - 0.001)
            if j > 2 {
                XCTAssertEqual(below.tileIDs.count, j - 2, "Reject upward rounding at \(j)")
                XCTAssertLessThanOrEqual(CGFloat(below.tileIDs.count + 1) * slot, CGFloat(j) * slot - 0.001)
            } else {
                XCTAssertEqual(below.tileIDs, [ids[0]])
                XCTAssertTrue(below.menuIDs.isEmpty, "Reject a clipped More control")
            }
        }
    }

    func testShorterListsHaveTheirOwnAllFitThresholds() {
        for n in 8...10 {
            let eligible = Array(ids.prefix(n))
            XCTAssertEqual(project(CGFloat(n) * slot, ids: eligible).tileIDs, eligible)
            XCTAssertTrue(project(CGFloat(n) * slot, ids: eligible).menuIDs.isEmpty)
            XCTAssertEqual(project(CGFloat(n) * slot - 0.001, ids: eligible).tileIDs.count, n - 2,
                           "Reject a fractional tile when fewer tools are eligible")
        }
    }

    func testSelectionPromotionRejectsMissingDuplicatedOrLostTools() {
        let result = project(4 * slot, selection: "tool8")
        XCTAssertEqual(result.tileIDs, ["tool0", "tool1", "tool8"])
        XCTAssertEqual(result.menuIDs, ["tool2", "tool3", "tool4", "tool5", "tool6", "tool7", "tool9"])
        XCTAssertEqual(Set(result.tileIDs + result.menuIDs), Set(ids))
        XCTAssertEqual((result.tileIDs + result.menuIDs).count, ids.count)
    }

    func testSelectionInPrefixKeepsThePrefix() {
        XCTAssertEqual(project(4 * slot, selection: "tool1").tileIDs, Array(ids.prefix(3)),
                       "Reject moving a selection already in the prefix")
    }

    func testCustomOrderHiddenToolsAndPromotionNeverPersistFitDrivenHiding() {
        let raw = "tool9,-tool8,tool7,tool6,tool5,tool4,tool3,tool2,tool1,tool0"
        let layout = LumenToolLayout(encoded: raw, all: ids)
        let eligible = LumenSidebarTileProjection.eligibleIDs(layout: layout, selection: "tool4")
        let result = project(4 * slot, selection: "tool4", ids: eligible)
        XCTAssertEqual(result.tileIDs, ["tool9", "tool7", "tool4"])
        XCTAssertEqual(result.menuIDs, ["tool6", "tool5", "tool3", "tool2", "tool1", "tool0"])
        XCTAssertFalse((result.tileIDs + result.menuIDs).contains("tool8"), "Reject listing a user-hidden tool")
        XCTAssertEqual(layout.encoded, raw, "Reject persisted fit-driven hiding")
        let transient = LumenSidebarTileProjection.eligibleIDs(layout: layout, selection: "tool8")
        XCTAssertEqual(transient[1], "tool8")
        XCTAssertTrue(project(4 * slot, selection: "tool8", ids: transient).tileIDs.contains("tool8"))
        XCTAssertEqual(layout.encoded, raw, "Reject automatic unhide")
        XCTAssertFalse(LumenSidebarTileProjection.eligibleIDs(layout: layout, selection: "tool4").contains("tool8"))
    }

    func testOneToolAndNarrowWidthsRejectClippedMoreAndFakeFit() {
        XCTAssertEqual(project(slot, ids: [ids[0]]).tileIDs, [ids[0]])
        XCTAssertTrue(project(slot, ids: [ids[0]]).menuIDs.isEmpty)
        XCTAssertFalse(project(slot, ids: [ids[0]]).insufficientWidth)
        XCTAssertTrue(project(slot - 0.001, ids: [ids[0]]).insufficientWidth)
        for width: CGFloat in [0, slot - 0.001, slot, 2 * slot - 0.001] {
            let result = project(width, selection: "tool8")
            XCTAssertEqual(result.tileIDs, ["tool8"])
            XCTAssertTrue(result.menuIDs.isEmpty, "Reject a More control below two whole slots")
            XCTAssertEqual(result.insufficientWidth, width < slot)
        }
    }

    func testInvalidMetricsRejectDivisionByZeroAndNonfiniteConversion() {
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            let result = LumenSidebarTileProjection.project(visibleIDs: ids, selection: "tool8",
                                                           offeredWidth: slot * 4, slotWidth: invalid)
            XCTAssertEqual(result.tileIDs, ["tool8"])
            XCTAssertTrue(result.menuIDs.isEmpty)
            XCTAssertTrue(result.insufficientWidth)
        }
        XCTAssertTrue(project(.nan).insufficientWidth)
        XCTAssertTrue(project(-1).insufficientWidth)
        XCTAssertEqual(project(.infinity).tileIDs, ids)
        XCTAssertTrue(project(0, ids: []).tileIDs.isEmpty)
    }

    func testArrangementMovesAcrossOverflowAndPromotionAgainstFullOrder() throws {
        var layout = LumenToolLayout(all: ids)
        let initial = project(4 * slot, selection: "tool8", ids: layout.visible)
        XCTAssertEqual(initial.tileIDs, ["tool0", "tool1", "tool8"])
        layout.move("tool8", by: -1)
        XCTAssertEqual(layout.visible[7], "tool8", "Reject editing the promoted display order")
        layout.move("tool1", by: 2)
        XCTAssertEqual(layout.visible[3], "tool1", "Reject a lost overflow neighbor")
        let change = try XCTUnwrap(LumenReorderMove(ids: layout.visible, sources: ["tool8"],
            destination: .init(position: .before("tool0"))))
        layout.reorder(change)
        XCTAssertEqual(layout.visible.first, "tool8")
        XCTAssertEqual(Set(layout.order), Set(ids), "Reject dropping saved IDs during drag")
    }

    func testHideShowAllResetAndDragPreserveTheFullArrangement() throws {
        var layout = LumenToolLayout(encoded: "tool9,-tool8,tool7,tool6,tool5,tool4,tool3,tool2,tool1,tool0", all: ids)
        let change = try XCTUnwrap(LumenReorderMove(ids: layout.visible, sources: ["tool0"],
            destination: .init(position: .before("tool9"))))
        layout.reorder(change)
        XCTAssertEqual(layout.visible.first, "tool0")
        XCTAssertTrue(layout.hidden.contains("tool8"), "Reject automatic unhide during drag")
        XCTAssertTrue(layout.hide("tool7"))
        XCTAssertEqual(Set(layout.order), Set(ids), "Reject a persisted fit-driven hide or dropped ID")
        layout.showAll()
        XCTAssertEqual(layout.visible.count, ids.count)
        layout.reset()
        XCTAssertEqual(layout.order, ids)
        XCTAssertEqual(layout.encoded, "")
    }
}
