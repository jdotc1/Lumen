import SwiftUI
import LumenTokens
import OSLog

/// The drag container must identify the returned item by its collection ID, not its wire text.
/// A String proxy preserves the existing external docking representation byte for byte.
struct LumenReorderDragItem: Identifiable, Transferable {
    let id: String
    let payload: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.payload)
    }
}

/// One native placeholder and motion policy for the tab strip and sidebar collections.
/// Exported strings retain the existing docking protocol; local moves never use that protocol.
struct LumenReorderBehavior<Item: Identifiable>: ViewModifier where Item.ID == String {
    typealias Destination = ReorderDifference<String, ReorderableSingleCollectionIdentifier>.Destination

    let items: [Item]
    let isEnabled: Bool
    let payload: (String) -> String
    let move: (LumenReorderMove) -> Void
    var externalDrop: (([String], Destination?) -> Void)?

    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lumenRendersOffscreen) private var rendersOffscreen

    func body(content: Content) -> some View {
        if rendersOffscreen {
            content
        } else {
            content
                .reorderContainer(for: Item.self, isEnabled: isEnabled) { difference in
                    LumenMotion.perform(.reorder, metrics: metrics.motion, reduceMotion: reduceMotion) {
                        _ = LumenReorderMove.apply(ids: items.map(\.id), sources: difference.sources,
                                                   destination: difference.destination, move: move)
                    }
                }
                .dragContainer(for: LumenReorderDragItem.self) { (ids: [String]) in dragItems(for: ids) }
                .dropDestination(for: String.self, isEnabled: externalDrop != nil) { strings, session in
                    externalDrop?(strings, session.reorderDestination(for: Item.self))
                }
        }
    }

    func dragItems(for ids: [String]) -> [LumenReorderDragItem] {
        ids.map { LumenReorderDragItem(id: $0, payload: payload($0)) }
    }
}

/// Resolves IDs against the current collection and uses SwiftUI's pre-removal destination offset.
/// Callback steps translate a multi-item move into the existing single-item callback contract.
struct LumenReorderMove {
    typealias Destination = ReorderDifference<String, ReorderableSingleCollectionIdentifier>.Destination
    struct Step: Equatable {
        let id: String
        let offset: Int
    }

    let offsets: IndexSet
    let destination: Int
    let result: [String]
    let steps: [Step]

    enum Rejection: String {
        case duplicateIDs, emptySources, unknownSources, unknownDestination, destinationInSources, unchangedOrder
    }

    #if DEBUG
    private static let log = Logger(subsystem: "LumenUI", category: "reorder")
    #endif

    /// The native handler and headless tests use the same validation and callback path.
    @discardableResult
    static func apply(ids: [String], sources: [String], destination: Destination,
                      move: (LumenReorderMove) -> Void) -> Bool {
        #if DEBUG
        let detail = "sources=\(String(reflecting: sources)) destination=\(String(reflecting: destination)) ids=\(String(reflecting: ids))"
        log.info("received \(detail, privacy: .public)")
        #endif
        guard let change = LumenReorderMove(ids: ids, sources: sources, destination: destination, onReject: { reason in
            #if DEBUG
            log.info("rejected reason=\(reason.rawValue, privacy: .public) \(detail, privacy: .public)")
            #endif
        }) else { return false }
        move(change)
        #if DEBUG
        log.info("applied reason=moveCallbackCompleted \(detail, privacy: .public) result=\(String(reflecting: change.result), privacy: .public)")
        #endif
        return true
    }

    init?(ids: [String], sources: [String], destination: Destination, onReject: (Rejection) -> Void = { _ in }) {
        guard Set(ids).count == ids.count else { onReject(.duplicateIDs); return nil }
        guard !sources.isEmpty else { onReject(.emptySources); return nil }
        guard Set(sources).isSubset(of: Set(ids)) else { onReject(.unknownSources); return nil }
        let sourceSet = Set(sources)
        offsets = IndexSet(ids.indices.filter { sourceSet.contains(ids[$0]) })
        let anchor: String?
        switch destination.position {
        case .before(let id):
            guard let offset = ids.firstIndex(of: id) else { onReject(.unknownDestination); return nil }
            self.destination = offset
            // A drop on any member of the moving selection is a no-op.
            guard !sourceSet.contains(id) else { onReject(.destinationInSources); return nil }
            anchor = id
        case .end:
            self.destination = ids.count
            anchor = nil
        }
        var next = ids
        next.move(fromOffsets: offsets, toOffset: self.destination)
        guard next != ids else { onReject(.unchangedOrder); return nil }
        result = next
        var working = ids
        var callbacks: [Step] = []
        for id in ids where sourceSet.contains(id) {
            let offset = anchor.flatMap { working.firstIndex(of: $0) } ?? working.count
            callbacks.append(Step(id: id, offset: offset))
            working.removeAll { $0 == id }
            working.insert(id, at: anchor.flatMap { working.firstIndex(of: $0) } ?? working.count)
        }
        steps = callbacks
    }
}
