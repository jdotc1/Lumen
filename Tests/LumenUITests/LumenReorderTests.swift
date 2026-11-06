import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenReorderTests: XCTestCase {
    private typealias Destination = LumenReorderMove.Destination
    private let ids = ["a", "b", "c", "d"]

    func testTabDragContainerIdentityAppliesMoveAndPreservesSourcePane() throws {
        var received: [String] = []
        var actions = LumenTabActions()
        actions.moveTab = { id, pane, offset in received = [id, pane ?? "", String(offset)] }
        let behavior = LumenReorderBehavior(items: ids.map { LumenDocumentTab(id: $0, title: $0, systemImage: "doc") },
                                           isEnabled: true, payload: { lumenTabDragPayload($0, pane: "right") },
                                           move: { LumenDocumentTabBar.apply($0, actions: actions, pane: "right") })
        let dragged = behavior.dragItems(for: ["a"])
        XCTAssertEqual(dragged.map(\.id), ["a"])
        XCTAssertEqual(dragged.map(\.payload), [lumenTabDragPayload("a", pane: "right")])
        XCTAssertTrue(LumenReorderMove.apply(ids: ids, sources: dragged.map(\.id),
                                            destination: Destination(position: .end), move: behavior.move))
        XCTAssertEqual(received, ["a", "right", "4"])
    }

    func testPaneDragContainerIdentityAppliesMultiItemMove() {
        var layout = LumenToolLayout(encoded: "a,-b,c,d", all: ids)
        let behavior = LumenReorderBehavior(items: ids.map { LumenSidebarItem(id: $0, title: $0, systemImage: "folder") },
                                           isEnabled: true, payload: { lumenPaneDragPrefix + $0 },
                                           move: { layout.reorder($0) })
        let dragged = behavior.dragItems(for: ["d", "b"])
        XCTAssertEqual(dragged.map(\.id), ["d", "b"])
        XCTAssertEqual(dragged.map(\.payload), ["lumen.pane:d", "lumen.pane:b"])
        XCTAssertTrue(LumenReorderMove.apply(ids: layout.order, sources: dragged.map(\.id),
                                            destination: Destination(position: .before("a")), move: behavior.move))
        XCTAssertEqual(layout.encoded, "-b,d,a,c")
    }

    func testDragItemExportsUnchangedDockingStrings() async throws {
        XCTAssertEqual(LumenReorderDragItem.exportedContentTypes(), String.exportedContentTypes())
        for payload in [lumenTabDragPayload("a", pane: nil), lumenTabDragPayload("a", pane: "right"), lumenPaneDragPrefix + "a"] {
            let item = LumenReorderDragItem(id: "a", payload: payload)
            for type in String.exportedContentTypes() {
                let actual = try await item.exported(as: type)
                let expected = try await payload.exported(as: type)
                XCTAssertEqual(actual, expected)
                let imported = try await String(importing: actual, contentType: type)
                XCTAssertEqual(imported, payload)
            }
        }
    }

    func testOldStringPayloadIdentifiersAreRejectedWithoutCallbacks() {
        for source in [lumenTabDragPayload("a", pane: nil), lumenTabDragPayload("a", pane: "right"), lumenPaneDragPrefix + "a"] {
            XCTAssertFalse(LumenReorderMove.apply(ids: ids, sources: [source], destination: Destination(position: .end)) { _ in
                XCTFail("Wire payloads must not be used as collection identifiers")
            })
        }
    }

    func testRejectionReasonsDistinguishInvalidAndUnchangedDifferences() {
        let cases: [([String], [String], Destination.Position, LumenReorderMove.Rejection)] = [
            (["a", "a"], ["a"], .end, .duplicateIDs),
            (ids, [], .end, .emptySources),
            (ids, ["gone"], .end, .unknownSources),
            (ids, ["a"], .before("gone"), .unknownDestination),
            (ids, ["a"], .before("a"), .destinationInSources),
            (ids, ["a"], .before("b"), .unchangedOrder)
        ]
        for (collection, sources, position, expected) in cases {
            var reasons: [LumenReorderMove.Rejection] = []
            XCTAssertNil(LumenReorderMove(ids: collection, sources: sources, destination: Destination(position: position),
                                         onReject: { reasons.append($0) }))
            XCTAssertEqual(reasons, [expected])
        }
    }

    func testFirstToLast() throws {
        let move = try XCTUnwrap(LumenReorderMove(ids: ids, sources: ["a"], destination: Destination(position: .end)))
        XCTAssertEqual(move.result, ["b", "c", "d", "a"])
        XCTAssertEqual(move.offsets, IndexSet(integer: 0))
        XCTAssertEqual(move.destination, 4)
        XCTAssertEqual(move.steps, [.init(id: "a", offset: 4)])
    }

    func testLastToFirst() throws {
        let move = try XCTUnwrap(LumenReorderMove(ids: ids, sources: ["d"], destination: Destination(position: .before("a"))))
        XCTAssertEqual(move.result, ["d", "a", "b", "c"])
        XCTAssertEqual(move.steps, [.init(id: "d", offset: 0)])
    }

    func testSelfAndAdjacentDropsAreNoOps() {
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["b"], destination: Destination(position: .before("b"))))
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["b"], destination: Destination(position: .before("c"))))
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["d"], destination: Destination(position: .end)))
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["a", "b"], destination: Destination(position: .before("b"))))
    }

    func testMultiItemCallbackTranslationMatchesArrayMove() throws {
        for (sources, position) in [(["c", "a"], Destination.Position.end),
                                    (["b", "d"], .before("a")), (["a", "d"], .before("c"))] {
            let move = try XCTUnwrap(LumenReorderMove(ids: ids, sources: sources, destination: Destination(position: position)))
            var actual = ids
            let actions = LumenTabActions(dropTab: { id, offset in
                let anchor = offset < actual.count ? actual[offset] : nil
                actual.removeAll { $0 == id }
                actual.insert(id, at: anchor.flatMap { actual.firstIndex(of: $0) } ?? actual.count)
            })
            LumenDocumentTabBar.apply(move, actions: actions, pane: nil)
            XCTAssertEqual(actual, move.result)
        }
    }

    func testMoveCallbackRetainsSourcePaneAndTakesPrecedence() throws {
        let move = try XCTUnwrap(LumenReorderMove(ids: ids, sources: ["a"], destination: Destination(position: .end)))
        var received: [String] = []
        var actions = LumenTabActions(dropTab: { _, _ in XCTFail("Internal pane-aware callback takes precedence") })
        actions.moveTab = { id, pane, offset in received = [id, pane ?? "", String(offset)] }
        LumenDocumentTabBar.apply(move, actions: actions, pane: "right")
        XCTAssertEqual(received, ["a", "right", "4"])
    }

    func testStaleOrInvalidIDsDoNotMutate() {
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["gone"], destination: Destination(position: .end)))
        XCTAssertNil(LumenReorderMove(ids: ids, sources: ["a"], destination: Destination(position: .before("gone"))))
        XCTAssertNil(LumenReorderMove(ids: ids, sources: [], destination: Destination(position: .end)))
        XCTAssertNil(LumenReorderMove(ids: ["a", "a"], sources: ["a"], destination: Destination(position: .end)))
    }

    func testGridReorderPreservesHiddenPanesAndEncodedBinding() throws {
        var layout = LumenToolLayout(encoded: "a,-b,c,d", all: ids)
        let move = try XCTUnwrap(LumenReorderMove(ids: layout.order, sources: ["d", "b"], destination: Destination(position: .before("a"))))
        layout.reorder(move)
        XCTAssertEqual(layout.order, ["b", "d", "a", "c"])
        XCTAssertEqual(layout.hidden, ["b"])
        XCTAssertEqual(layout.encoded, "-b,d,a,c")
    }

    func testDockReorderKeepsHiddenSlots() throws {
        var layout = LumenToolLayout(encoded: "a,-b,c,d", all: ids)
        let move = try XCTUnwrap(LumenReorderMove(ids: layout.visible, sources: ["d"], destination: Destination(position: .before("a"))))
        layout.reorder(move)
        XCTAssertEqual(layout.order, ["d", "b", "a", "c"])
        XCTAssertEqual(layout.visible, ["d", "a", "c"])
        XCTAssertEqual(layout.hidden, ["b"])
    }
}
