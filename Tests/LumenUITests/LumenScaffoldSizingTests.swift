import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenScaffoldSizingTests: XCTestCase {
    private var wizard: some View {
        LumenWizardWindow(pages: [.init(id: "one", title: "Configuration")], current: .constant(0),
                          onCancel: {}, onFinish: {}) { _ in
            VStack { ForEach(0..<30) { Text("Configuration value \($0)") } }
        }
    }

    func testWizardHonorsHostAndScaledMinimumAndPreferredOpeningSize() {
        let host = NSHostingController(rootView: wizard.lumenMetrics(.standard))
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 1000, height: 750)), CGSize(width: 1000, height: 750))
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 1, height: 1)), CGSize(width: 640, height: 460))
        let scaled = NSHostingController(rootView: wizard.lumenMetrics(.resolving(nil, textScale: 1.3)))
        let minimum = scaled.sizeThatFits(in: CGSize(width: 1, height: 1))
        XCTAssertEqual(minimum.width, 832, accuracy: 0.1)
        XCTAssertEqual(minimum.height, 598, accuracy: 0.1)
        let preferred = NSHostingView(rootView: wizard.lumenWizardPreferredSize(CGSize(width: 940, height: 680))
            .lumenMetrics(.standard).fixedSize())
        XCTAssertEqual(preferred.fittingSize, CGSize(width: 940, height: 680))
    }

    func testWizardColumnsGrowAndLongPageScrolls() throws {
        var regions: [LumenWizardLayoutEntry] = []
        let view = wizard.lumenMetrics(.standard).onPreferenceChange(LumenWizardLayoutKey.self) { regions = $0 }
        try withHost(view, size: CGSize(width: 1000, height: 600)) { host in
            let steps = try XCTUnwrap(regions.first { $0.region == .stepList })
            let page = try XCTUnwrap(regions.first { $0.region == .currentPage })
            XCTAssertGreaterThan(steps.frame.width, 180)
            XCTAssertGreaterThan(page.frame.width, 459)
            XCTAssertTrue(scrollViews(in: host).contains {
                ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1
            })
        }
    }

    private var shortcuts: some View {
        LumenShortcutsSheet(groups: [.init(title: "Workspace", shortcuts: (0..<40).map {
            .init(title: "Open configuration \($0)", shortcut: .init("o"))
        })])
    }

    func testShortcutsHonorLargerHostAndPreferredEnvelope() {
        let host = NSHostingController(rootView: shortcuts.lumenMetrics(.standard))
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 1000, height: 800)), CGSize(width: 1000, height: 800))
        let unbounded = host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        XCTAssertTrue(unbounded.width.isFinite && unbounded.height.isFinite)
        let preferred = NSHostingView(rootView: shortcuts.lumenShortcutsPreferredSize(CGSize(width: 900, height: 700))
            .lumenMetrics(.standard).fixedSize())
        XCTAssertEqual(preferred.fittingSize, CGSize(width: 900, height: 700))
        let scaled = NSHostingController(rootView: shortcuts.lumenMetrics(.resolving(nil, textScale: 1.3)))
        XCTAssertEqual(scaled.sizeThatFits(in: CGSize(width: 1, height: 400)).width, 416, accuracy: 0.1)
    }

    func testShortcutsScrollInsideShortHostAtLargerText() throws {
        try withHost(shortcuts.lumenMetrics(.resolving(nil, textScale: 1.3)), size: CGSize(width: 500, height: 300)) { host in
            let scroll = try XCTUnwrap(scrollViews(in: host).first)
            XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).bounds.height, scroll.contentView.bounds.height)
            XCTAssertGreaterThan(scroll.contentView.bounds.height, 0)
            XCTAssertLessThan(scroll.frame.height, 300, "Header and Done retain space outside the viewport")
        }
    }

    func testThemeEditorHonorsHostInspectorWidthBeyondOldCap() throws {
        let store = TestPack.store(registry: .core)
        let editor = LumenThemeEditor(base: store.theme(), store: store)
            .lumenThemeEditorInspectorWidth(min: 500, ideal: 500, max: 500)
            .lumenMetrics(.resolving(nil, textScale: 1.3))
        try withHost(editor, size: CGSize(width: 1100, height: 700)) { host in
            let split = try XCTUnwrap(descendants(in: host).compactMap { $0 as? NSSplitView }.first)
            let inspector = try XCTUnwrap(split.arrangedSubviews.last)
            XCTAssertEqual(inspector.frame.width, 500, accuracy: 1)
            XCTAssertGreaterThan(split.arrangedSubviews.first?.frame.width ?? 0, 360)
        }
    }

    private func withHost<V: View>(_ view: V, size: CGSize, inspect: (NSView) throws -> Void) rethrows {
        let host = NSHostingView(rootView: view.lumenRendersOffscreen())
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            window.update()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        try inspect(host)
    }

    private func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        descendants(in: view).compactMap { $0 as? NSScrollView }
    }
}
