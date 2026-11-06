import LumenTestSupport
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor final class LumenSortableTableTests: XCTestCase {
    private struct Row: Identifiable { let id: Int; let name: String }
    private final class State {
        var order: [LumenTableSort] = []
        var widths: [String: CGFloat] = [:]
        var selection: Int?
    }

    private let rows = [Row(id: 2, name: "Beta"), Row(id: 1, name: "Alpha")]
    private var columns: [LumenTableColumn<Row>] {
        [LumenTableColumn("Name") { LumenTableText($0.name) }.minWidth(80).sortable(),
         LumenTableColumn("ID", width: 60) { LumenTableText(String($0.id)) }.minWidth(40).sortable(),
         LumenTableColumn("Notes") { _ in LumenTableText("Read only") }.minWidth(90)]
    }

    private func table(_ state: State) -> LumenTable<Row> {
        LumenTable(rows, selection: Binding(get: { state.selection }, set: { state.selection = $0 }),
                   sortOrder: Binding(get: { state.order }, set: { state.order = $0 }),
                   columnWidths: Binding(get: { state.widths }, set: { state.widths = $0 }),
                   height: .fitRows(maxVisible: 3), columns: columns)
    }

    func testHeaderClickStartsAscendingThenFlipsPrimary() {
        let state = State()
        let bound = table(state)
        bound.selectSortColumn("Name")
        XCTAssertEqual(state.order, [LumenTableSort(column: "Name", ascending: true)])
        bound.selectSortColumn("Name")
        XCTAssertEqual(state.order, [LumenTableSort(column: "Name", ascending: false)])
        bound.selectSortColumn("Name")
        XCTAssertEqual(state.order, [LumenTableSort(column: "Name", ascending: true)])
        // The view owns no comparator and receives the caller's row order unchanged.
        XCTAssertEqual(rows.map(\.id), [2, 1])
    }

    func testAnotherHeaderBecomesAscendingPrimaryAndRetainsSecondaryKeys() {
        let state = State()
        state.order = [LumenTableSort(column: "Name", ascending: false), LumenTableSort(column: "ID", ascending: false)]
        table(state).selectSortColumn("ID")
        XCTAssertEqual(state.order, [LumenTableSort(column: "ID"), LumenTableSort(column: "Name", ascending: false)])
    }

    func testUnsortableAndUnknownHeadersIgnoreClicks() {
        let state = State()
        state.order = [LumenTableSort(column: "Name")]
        let view = table(state)
        view.selectSortColumn("Notes")
        view.selectSortColumn("missing")
        XCTAssertEqual(state.order, [LumenTableSort(column: "Name")])
    }

    func testDividerDragClampsToMinimumAndViewport() {
        let state = State(), viewState = State()
        let view = table(state)
        view.resizeColumn("Name", to: 2, tableWidth: 300)
        XCTAssertEqual(state.widths["Name"], 80)
        view.resizeColumn("Name", to: 900, tableWidth: 300)
        XCTAssertEqual(state.widths["Name"], 300)
        view.resizeColumn("Name", to: .infinity, tableWidth: 300)
        XCTAssertEqual(state.widths["Name"], 300)
        view.resizeColumn("missing", to: 100, tableWidth: 300)
        XCTAssertNil(state.widths["missing"])
        table(viewState).resizeColumn("Name", to: 20, tableWidth: 50)
        XCTAssertEqual(viewState.widths["Name"], 80, "An oversized minimum is preserved inside horizontal overflow")
    }

    func testDoubleClickRestoresMeasuredNaturalWidthIncludingFixedColumns() {
        let state = State()
        state.widths = ["Name": 300, "ID": 220]
        let view = table(state)
        view.resetColumnWidth("Name", naturalWidth: 130)
        view.resetColumnWidth("ID", naturalWidth: 48)
        XCTAssertEqual(state.widths, ["Name": 130, "ID": 48])
        view.resetColumnWidth("Name", naturalWidth: 20)
        XCTAssertEqual(state.widths["Name"], 80)
    }

    func testOverflowPreservesExplicitWidthsAndOtherColumnMinimums() {
        let state = State()
        state.widths = ["Name": 240]
        let view = table(state)
        let widths = view.resizableWidths(available: 180, natural: ["Name": 120, "ID": 32, "Notes": 70])
        XCTAssertEqual(widths, [240, 60, 90])
        XCTAssertGreaterThan(widths.reduce(0, +), 180)
        XCTAssertEqual(state.widths, ["Name": 240], "Measuring a narrower viewport never rewrites user state")
    }

    func testUnboundColumnsShareSurplusWithoutChangingExplicitWidth() {
        let state = State()
        state.widths = ["Name": 120]
        XCTAssertEqual(table(state).resizableWidths(available: 400, natural: ["Name": 200, "Notes": 100]), [120, 60, 220])
    }

    private struct FramesKey: PreferenceKey {
        static let defaultValue: [String: CGFloat] = [:]
        static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    private struct WidthProbe: View {
        let id: String
        @Environment(\.lumenTableMeasuring) private var measuring
        var body: some View {
            Text(id).frame(maxWidth: .infinity).background {
                if !measuring {
                    GeometryReader { proxy in
                        Color.clear.preference(key: FramesKey.self, value: [id: proxy.size.width])
                    }
                }
            }
        }
    }

    private final class WidthRecorder { var widths: [String: CGFloat] = [:] }

    func testShrinkingViewportPreservesBoundWidthsWithoutMeasurementFeedback() {
        let state = State(), recorder = WidthRecorder()
        state.widths = ["Name": 240]
        let view = LumenTable(rows, selection: .constant(nil),
                              columnWidths: Binding(get: { state.widths }, set: { state.widths = $0 }),
                              height: .fitRows(maxVisible: 3), columns: [
                                LumenTableColumn("Name") { LumenTableText($0.name) }
                                    .header { WidthProbe(id: "Name") }.minWidth(80),
                                LumenTableColumn("Notes") { _ in LumenTableText("Read only") }
                                    .header { WidthProbe(id: "Notes") }.minWidth(90),
                              ])
            .onPreferenceChange(FramesKey.self) { widths in
                MainActor.assumeIsolated { recorder.widths = widths }
            }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 440, height: 200),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for width in [CGFloat(440), CGFloat(180)] {
            window.setContentSize(CGSize(width: width, height: 200))
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            XCTAssertEqual(host.bounds.width, width, accuracy: 0.5)
            XCTAssertEqual(recorder.widths["Name"] ?? -1, 240, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(recorder.widths["Notes"] ?? -1, 90)
            XCTAssertEqual(state.widths, ["Name": 240])
        }
    }

    func testResizableFitRowsHugsPopulatedAndEmptyTablesInsideAForm() {
        let metrics = LumenMetrics.standard
        let rowHeight = LumenDensity.regular.rowHeight(in: metrics.layout)
        for sample in [rows, []] {
            let recorder = WidthRecorder()
            let table = LumenTable(sample, selection: .constant(nil), columnWidths: .constant(["Name": 200]),
                                   height: .fitRows(maxVisible: 3), columns: columns)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: FramesKey.self, value: ["table-height": proxy.size.height])
                    }
                }
            let root = VStack(spacing: 0) { table; Spacer(minLength: 0) }
                .lumenMetrics(metrics)
                .onPreferenceChange(FramesKey.self) { widths in
                    MainActor.assumeIsolated { recorder.widths = widths }
                }
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 440, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let expected = sample.isEmpty
                ? 3 * rowHeight + metrics.stroke.hairline
                : rowHeight + CGFloat(sample.count) * (rowHeight + metrics.stroke.hairline)
            XCTAssertEqual(recorder.widths["table-height"] ?? -1, expected, accuracy: 2)
            window.close()
        }
    }

    func testAbsentBindingsLeaveLegacyBehaviorAndIgnoreHeaderActions() {
        let state = State()
        let selection = Binding(get: { state.selection }, set: { state.selection = $0 })
        let legacy = LumenTable(rows, selection: selection, height: .fitRows(maxVisible: 3), columns: columns)
        legacy.selectSortColumn("Name")
        legacy.resizeColumn("Name", to: 200, tableWidth: 300)
        legacy.resetColumnWidth("Name", naturalWidth: 100)
        XCTAssertTrue(state.order.isEmpty)
        XCTAssertTrue(state.widths.isEmpty)
        XCTAssertEqual(LumenTableLayout.widths(natural: [150, 100], minimums: [80, 90],
                                              priorities: [0, 0], available: 85), [40, 45])
    }
}
