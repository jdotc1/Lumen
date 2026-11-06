import AppKit
import LumenTestSupport
import LumenUI
import SwiftUI
import XCTest

/// Bounded overflow cell for the window layout guarantee: rigid, fitting, List and stateful panels.
@MainActor
final class LumenBottomPanelOverflowTests: XCTestCase {
    private func settle(_ host: NSView) {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    private func withPanel<Panel: View>(_ panel: Panel, body: (NSHostingView<AnyView>) throws -> Void) rethrows {
        let root = Color.clear.lumenBottomPanel(isPresented: .constant(true), height: .constant(300)) { panel }
        let host = NSHostingView(rootView: AnyView(root.lumenPaletteRoot()))
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 500, height: 700),
                                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        settle(host)
        try body(host)
    }

    func testRigidOverflowLastRowIsReachable() throws {
        try withPanel(VStack(spacing: 0) {
            Color.clear.frame(height: 870)
            LastRowMarker().frame(height: 30)
        }.frame(height: 900)) { host in
            let scroll = try XCTUnwrap(descendants(host, of: NSScrollView.self).first)
            let document = try XCTUnwrap(scroll.documentView)
            let lastRow = try XCTUnwrap(descendants(document, of: MarkerView.self).first)
            XCTAssertGreaterThanOrEqual(document.frame.height, 900)
            XCTAssertEqual(scroll.contentView.bounds.height, 300, accuracy: 0.5)
            let row = document.convert(lastRow.bounds, from: lastRow)
            let end = document.isFlipped ? document.bounds.maxY - scroll.contentView.bounds.height : document.bounds.minY
            scroll.contentView.scroll(to: CGPoint(x: 0, y: end))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(host)
            let visible = document.visibleRect
            XCTAssertGreaterThanOrEqual(row.minY, visible.minY - 0.5)
            XCTAssertLessThanOrEqual(row.maxY, visible.maxY + 0.5)
            XCTAssertEqual(max(0, row.maxY - visible.maxY) + max(0, visible.minY - row.minY), 0, accuracy: 0.5)
        }
    }

    func testFittingContentFillsViewportWithoutScrolling() throws {
        try withPanel(Color.clear.frame(height: 120)) { host in
            let scroll = try XCTUnwrap(descendants(host, of: NSScrollView.self).first)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertEqual(scroll.contentView.bounds.height, 300, accuracy: 0.5)
            XCTAssertEqual(document.frame.height, scroll.contentView.bounds.height, accuracy: 0.5)
        }
    }

    func testListKeepsItsOwnScrollingWithoutOuterOverflow() throws {
        try withPanel(List(0..<80, id: \.self) { Text("Row \($0)") }) { host in
            let scrolls = descendants(host, of: NSScrollView.self)
            XCTAssertEqual(scrolls.count, 2, "Persistent outer viewport and native List")
            let overflowing = scrolls.filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 0.5 }
            XCTAssertEqual(overflowing.count, 1, "Only the List scrolls")
            let outer = try XCTUnwrap(scrolls.first)
            XCTAssertEqual(outer.documentView?.frame.height ?? 0, outer.contentView.bounds.height, accuracy: 0.5)
            let list = try XCTUnwrap(overflowing.first)
            XCTAssertFalse(list === outer)
            let document = try XCTUnwrap(list.documentView)
            let end = document.isFlipped ? document.bounds.maxY - list.contentView.bounds.height : document.bounds.minY
            list.contentView.scroll(to: CGPoint(x: 0, y: end))
            list.reflectScrolledClipView(list.contentView)
            settle(host)
            XCTAssertGreaterThan(document.visibleRect.height, 0)
            XCTAssertTrue(document.visibleRect.intersects(document.bounds))
        }
    }

    func testPanelStateAndPreferencesSurviveFitThreshold() throws {
        let report = CounterReport()
        let model = PanelHeight()
        let root = StatefulRoot(model: model, report: report)
        let host = NSHostingView(rootView: root.lumenPaletteRoot())
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 500, height: 700),
                                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        settle(host)
        let increment = try XCTUnwrap(report.increment)
        increment()
        settle(host)
        XCTAssertEqual(report.value, 1)
        model.height = 400
        settle(host)
        XCTAssertEqual(report.value, 1)
        report.increment?()
        settle(host)
        XCTAssertEqual(report.value, 2)
        model.height = 200
        settle(host)
        XCTAssertEqual(report.value, 2)
        XCTAssertEqual(report.appearances, 1)
    }
}

private final class MarkerView: NSView {}
private struct LastRowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView { MarkerView() }
    func updateNSView(_ nsView: MarkerView, context: Context) {}
}
@MainActor @Observable private final class PanelHeight { var height: CGFloat = 200 }
@MainActor private final class CounterReport {
    var value = -1
    var appearances = 0
    var increment: (() -> Void)?
}
private struct CounterKey: PreferenceKey {
    static let defaultValue = -1
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}
private struct StatefulRoot: View {
    let model: PanelHeight
    let report: CounterReport
    var body: some View {
        Color.clear.lumenBottomPanel(isPresented: .constant(true), height: Binding(get: { model.height }, set: { model.height = $0 })) {
            StatefulPanel(report: report)
        }
        .onPreferenceChange(CounterKey.self) { value in
            MainActor.assumeIsolated { report.value = value }
        }
    }
}
private struct StatefulPanel: View {
    let report: CounterReport
    @State private var count = 0
    var body: some View {
        Text("Counter \(count)").frame(height: 300)
            .preference(key: CounterKey.self, value: count)
            .onAppear {
                report.appearances += 1
                report.increment = { count += 1 }
            }
    }
}
