import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenFloatingSizingTests: XCTestCase {
    private var commands: [LumenCommand] {
        (0..<30).map { LumenCommand(id: "command-\($0)", "Open configuration \($0)", category: "Workspace", systemImage: "folder") {} }
    }
    private var entries: [LumenMenuEntry] {
        (0..<30).map { .item("Open configuration \($0)", systemImage: "folder") }
    }
    private let large = LumenMetrics.resolving(nil, textScale: 1.3)

    private func measure(_ view: some View, width: CGFloat = 1000, height: CGFloat = 1000) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: height))
    }

    func testPaletteAcceptsHostWidthAndResultHeight() {
        let palette = LumenCommandPalette(commands, recentsKey: nil)
            .lumenCommandPaletteSize(width: 760, maximumListHeight: 180)
        XCTAssertEqual(measure(palette).width, 760, accuracy: 0.5)
        XCTAssertEqual(measure(palette, width: 320).width, 320, accuracy: 0.5)
        XCTAssertLessThan(measure(palette).height, 280)
        XCTAssertLessThanOrEqual(measure(palette, height: 180).height, 180.5)
    }

    func testPaletteDefaultsGrowWithTextButExplicitWidthDoesNot() {
        let palette = LumenCommandPalette(commands, recentsKey: nil)
        XCTAssertEqual(measure(palette).width, 580, accuracy: 0.5)
        XCTAssertEqual(measure(palette.lumenMetrics(large)).width, 754, accuracy: 0.5)
        XCTAssertGreaterThan(measure(palette.lumenMetrics(large)).height, measure(palette).height)
        XCTAssertEqual(measure(palette.lumenCommandPaletteSize(width: 700, maximumListHeight: 200).lumenMetrics(large)).width,
                       700, accuracy: 0.5)
    }

    func testShortPaletteHasWorkingScrollViewport() throws {
        try assertScrollable(LumenCommandPalette(commands, recentsKey: nil)
            .lumenCommandPaletteSize(width: 500, maximumListHeight: 120), size: CGSize(width: 500, height: 220))
    }

    func testInputPaletteAcceptsWidthAndGrowsWithText() {
        let input = LumenInputPalette("Go to line", systemImage: "number", onSubmit: { _ in })
        XCTAssertEqual(measure(input).width, 520, accuracy: 0.5)
        XCTAssertEqual(measure(input.lumenMetrics(large)).width, 676, accuracy: 0.5)
        let explicit = input.lumenInputPaletteSize(width: 740, maximumContentHeight: 160)
        XCTAssertEqual(measure(explicit.lumenMetrics(large)).width, 740, accuracy: 0.5)
        XCTAssertEqual(measure(explicit, width: 300).width, 300, accuracy: 0.5)
    }

    func testLongInputHelpScrollsInShortHost() throws {
        let input = LumenInputPalette("Go to line", systemImage: "number",
                                      help: String(repeating: "Review the configuration before continuing. ", count: 24), onSubmit: { _ in })
            .lumenInputPaletteSize(width: 420, maximumContentHeight: 140)
        XCTAssertLessThanOrEqual(measure(input).height, 140.5)
        XCTAssertLessThanOrEqual(measure(input, height: 100).height, 100.5)
        try assertScrollable(input, size: CGSize(width: 420, height: 100))
    }

    func testMenuPresentationHonorsExplicitWidthAndScalesAutomaticWidth() {
        let automatic = LumenCommandMenuPresentation(entries: entries, width: nil, isPresented: .constant(true))
        let explicit = LumenCommandMenuPresentation(entries: entries, width: 620, isPresented: .constant(true))
        XCTAssertEqual(measure(automatic).width, 336, accuracy: 0.5)
        XCTAssertEqual(measure(automatic.lumenMetrics(large)).width, 432, accuracy: 0.5)
        XCTAssertEqual(measure(explicit.lumenMetrics(large)).width, 636, accuracy: 0.5)
        XCTAssertLessThanOrEqual(measure(explicit, width: 300).width, 300.5)
    }

    func testLongMenusScrollWithinHostAndExplicitMaximum() throws {
        let menu = LumenCommandMenu(entries).lumenCommandMenuMaximumHeight(180)
        XCTAssertLessThanOrEqual(measure(menu).height, 180.5)
        XCTAssertLessThanOrEqual(measure(menu, height: 120).height, 120.5)
        XCTAssertEqual(measure(LumenCommandMenu(entries).lumenMetrics(large)).width, 416, accuracy: 0.5)
        try assertScrollable(menu, size: CGSize(width: 320, height: 120))
        try assertScrollable(LumenCommandMenu(entries, width: 320, placement: .inPlace, onDismiss: {})
            .lumenCommandMenuMaximumHeight(180), size: CGSize(width: 320, height: 160))
    }

    func testSubmenuKeepsResolvedWidthInsideZeroWidthAnchor() {
        let menu = LumenCommandMenu([.submenu("Open", [.item("Configuration")])],
                                    width: 320, highlighted: 0, openSubmenu: 0)
        let submenu = menu.level(1)
        let resolved = measure(submenu).width
        XCTAssertEqual(resolved, 280, accuracy: 0.5)
        // The anchor proposes zero to its child; inspect the child's geometry, not the
        // deliberately zero outer frame. A roomy proposal must not stretch it either.
        for proposal in [CGFloat(0), 900] {
            XCTAssertEqual(measure(submenu, width: proposal).width, resolved, accuracy: 0.5)
        }
        var anchoredWidth: CGFloat = -1
        let anchored = submenu.onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            anchoredWidth = $0
        }.frame(width: 0, alignment: .topLeading)
        let host = NSHostingView(rootView: anchored)
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 200)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(anchoredWidth, resolved, accuracy: 0.5)
    }

    func testToastWidthOverrideStaysInPointsAndYieldsToHost() {
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        center.post(LumenToast(title: "Export complete", message: "Review the configuration.", duration: nil))
        let stack = LumenToastStack(center: center)
        XCTAssertEqual(measure(stack).width, 360, accuracy: 0.5)
        XCTAssertEqual(measure(stack.lumenMetrics(large)).width, 468, accuracy: 0.5)
        let explicit = stack.lumenToastWidth(520).lumenMetrics(large)
        XCTAssertEqual(measure(explicit).width, 520, accuracy: 0.5)
        XCTAssertEqual(measure(explicit, width: 260).width, 260, accuracy: 0.5)
        for width in [nil, 0, -1, .infinity, .nan] as [CGFloat?] {
            XCTAssertEqual(measure(stack.lumenToastWidth(width)).width, 360, accuracy: 0.5)
        }
    }

    func testToolbarIdentityAndActivityFitAtLargeType() {
        let identity = LumenToolbarIdentity("Research Workspace Configuration", subtitle: "Production configuration", systemImage: "folder")
            .environment(\.lumenToolbarCompact, true)
        XCTAssertLessThanOrEqual(measure(identity, width: 180).width, 180.5)
        XCTAssertGreaterThan(measure(identity.lumenMetrics(large)).height, measure(identity).height)
        let activity = LumenActivityStatus(.working("Indexing configuration", progress: 0.5))
        XCTAssertGreaterThanOrEqual(measure(activity.lumenMetrics(large)).height, 31.2)
        XCTAssertGreaterThanOrEqual(measure(activity.lumenMetrics(large), width: 0).width, 182)
    }

    func testPopoverAutomaticWidthScalesAndExplicitWidthIsPreserved() {
        let automatic = LumenPopoverContent("Configuration", systemImage: "gear") { Text("Review destination") }
        let explicit = LumenPopoverContent("Configuration", systemImage: "gear", width: 280) { Text("Review destination") }
        XCTAssertEqual(measure(automatic).width, 280, accuracy: 0.5)
        XCTAssertEqual(measure(automatic.lumenMetrics(large)).width, 364, accuracy: 0.5)
        XCTAssertEqual(measure(automatic.lumenMetrics(large), width: 280).width, 280, accuracy: 0.5)
        XCTAssertEqual(measure(explicit.lumenMetrics(large)).width, 280, accuracy: 0.5)
    }

    func testTextOnlyModesAndPanelActionsHaveNarrowFallbacks() {
        let modes = LumenModeSwitcher(selection: .constant("Configuration"), options: ["Configuration", "Deployments", "Environment"], title: { $0 })
        XCTAssertLessThanOrEqual(measure(modes, width: 160).width, 160.5)
        let panel = LumenPanelBar("Production configuration and destinations", systemImage: "folder", status: "Ready",
                                  secondary: [.init("Review configuration", perform: {})], primary: .init("Deploy environment", perform: {}))
        XCTAssertLessThanOrEqual(measure(panel, width: 180).width, 180.5)
    }

    func testContentTabBarGrowsForTallTrailingContent() {
        let tabs = LumenContentTabBar { Text("Overview") } trailing: {
            Text("Configuration\nProduction\nReady").frame(height: 70)
        }
        XCTAssertGreaterThanOrEqual(measure(tabs, width: 360).height, 70)
    }

    /// Uses an unshown window and the actual native scroll viewport. Moving its clip bounds
    /// demonstrates that overflow is reachable, not merely hidden by a shorter outer frame.
    private func assertScrollable(_ view: some View, size: CGSize, file: StaticString = #filePath, line: UInt = #line) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        let scroll = try XCTUnwrap(scrolls(host).first { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 10 },
                                   "Expected a native viewport with overflowing content", file: file, line: line)
        let document = try XCTUnwrap(scroll.documentView, file: file, line: line)
        let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, file: file, line: line)
        XCTAssertEqual(scroll.contentView.bounds.maxY, document.bounds.height, accuracy: 1, file: file, line: line)
    }
}
