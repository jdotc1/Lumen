import AppKit
import SwiftUI
import LumenTokens
import LumenUI

/// No XCTest or Catalog-view dependencies: the page and the focused test use this same harness.
/// Reference sizes and limits match LumenPerformanceBudgetTests.
enum LumenScaleComponent: String, CaseIterable, Identifiable, Codable {
    case hex, listing, variables, log, collection, table
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hex: "Hex dump"
        case .listing: "Code listing"
        case .variables: "Variable tree"
        case .log: "Log console"
        case .collection: "Collection (list)"
        case .table: "Table"
        }
    }
    var referenceSize: Int {
        switch self {
        case .hex: 65_536
        case .listing, .variables, .collection: 1_000
        case .log, .table: 50_000
        }
    }
    var size: Int { referenceSize * 10 }
    var unit: String { self == .hex ? "bytes" : "rows" }
    var budgetMilliseconds: Double? {
        switch self {
        case .hex, .listing: 1_500
        case .variables: 2_000
        case .log: 5_000
        case .table: 1_000
        case .collection: nil
        }
    }
    var budgetOperation: String {
        switch self {
        case .hex: "two scroll steps"
        case .listing, .variables: "first layout"
        case .log: "four filter edits"
        case .table: "three scroll steps"
        case .collection: "No collection budget; size uses the 1,000-row list reference"
        }
    }
    var budgetDescription: String {
        guard let budgetMilliseconds else { return budgetOperation }
        let scaled = budgetMilliseconds * LumenScaleTiming.budgetScale
        return "Reference: \(Int(scaled)) ms / \(referenceSize) \(unit), \(budgetOperation)"
    }
}

struct LumenScaleTimingRecord: Codable {
    let component: LumenScaleComponent
    let size: Int
    let unit: String
    let referenceSize: Int
    let referenceBudgetMilliseconds: Double?
    let budgetScale: Double
    let referenceOperation: String
    let firstLayoutMilliseconds: Double
}

@MainActor
struct LumenScaleSample: Identifiable {
    let id = UUID()
    let record: LumenScaleTimingRecord
    let host: NSHostingView<AnyView>
}

enum LumenScaleTiming {
    static let budgetScale = ProcessInfo.processInfo.environment["LUMEN_PERF_BUDGET_SCALE"]
        .flatMap(Double.init).map { $0.isFinite ? max($0, 1) : 1 } ?? 1
    static let viewport = CGSize(width: 700, height: 800)
    static let method = "One sample: host/window creation through three layout/display passes at 700x800; fixture and theme preparation excluded. Standard dark theme, standard metrics, layout reports off. Reference budgets describe their original operations at 1x size, not thresholds for these 10x samples."

    /// Matches the budget harness's initial settling, without timing assertions or warm-up runs.
    /// The detached host is returned so the page displays the measured instance, not a second build.
    @MainActor
    static func measure(_ component: LumenScaleComponent) -> LumenScaleSample {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                        registry: LumenRegistry(packs: [.core, .code]))
        let root = fixture(component).lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
            .lumenMetrics(.standard).environment(\.colorScheme, .dark)
            .environment(\.lumenReportsLayoutChecks, false)
        let start = DispatchTime.now().uptimeNanoseconds
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: viewport),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<3 {
            RunLoop.current.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            host.display()
            CATransaction.flush()
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        window.contentView = nil
        window.close()
        return LumenScaleSample(record: .init(component: component, size: component.size, unit: component.unit,
            referenceSize: component.referenceSize, referenceBudgetMilliseconds: component.budgetMilliseconds,
            budgetScale: budgetScale, referenceOperation: component.budgetOperation, firstLayoutMilliseconds: elapsed), host: host)
    }

    private static func symbol(_ i: Int) -> String {
        let modules = ["Swift", "Foundation", "SampleCore", "AnalysisCore", "DebuggerCore"]
        return "\(modules[i % 5]).Dictionary<Swift.String, \(modules[(i + 1) % 5]).Array<Swift.Int>>.Index.Storage.symbolicatedValue\(i)"
    }

    @MainActor
    private static func fixture(_ component: LumenScaleComponent) -> AnyView {
        let count = component.size
        switch component {
        case .hex:
            let bytes = (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 7) }
            return AnyView(ScrollView { LumenHexDump(bytes, baseAddress: 0x1_0000_0000, selection: .constant(nil)) })
        case .listing:
            let lines = (0..<count).map { i in
                [LumenCodeRun("    let ", LumenToken.Code.keyword), LumenCodeRun("value\(i)"),
                 LumenCodeRun(" = "), LumenCodeRun("\(i * 7)", LumenToken.Code.number)]
            }
            return AnyView(ScrollView { LumenCodeListing(lines, currentLine: 0) })
        case .variables:
            let variables = (0..<count).map { i in
                LumenVariable(id: "v\(i)", name: "member\(i)", type: "Swift.Array<Thing\(i % 5)>",
                              value: "0x\(String(i * 4096, radix: 16)) \(symbol(i))", disclosure: .collapsed)
            }
            return AnyView(ScrollView { LumenVariableTree([LumenVariableSection("Locals", variables: variables)]) })
        case .log:
            let base = Date(timeIntervalSince1970: 1_800_000_000)
            let entries = (0..<count).map { i in
                LumenLogEntry(date: base.addingTimeInterval(Double(i) * 0.01), source: "source\(i % 12)",
                              level: i % 31 == 0 ? .error : (i % 7 == 0 ? .warning : .log),
                              message: "Processed file \(i) of batch: /Volumes/Data/Files/Group\(i % 200)/Series\(i % 9)/File\(i).bin")
            }
            return AnyView(LumenLogConsole(entries, onClear: {}))
        case .collection:
            let items = (0..<count).map { LumenCollectionItem(id: "item\($0)", title: "Item \($0)", detail: "/Example/Group\($0 % 10)/Item\($0)") }
            return AnyView(ScrollView {
                LumenCollection(items, mode: .list, selection: .constant(nil), sort: .constant(.title)) { _ in }
            })
        case .table:
            let rows = (0..<count).map { ScaleTableRow(id: $0, name: symbol($0)) }
            return AnyView(LumenTable(rows, selection: .constant(nil), height: .minimum(600), columns: [
                .text("Name", monospaced: true, truncationMode: .middle) { $0.name },
                .text("Index", width: 80) { "\($0.id)" },
            ]))
        }
    }
}

private struct ScaleTableRow: Identifiable {
    let id: Int
    let name: String
}
