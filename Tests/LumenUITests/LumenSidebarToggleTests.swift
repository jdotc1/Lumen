import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSidebarToggleTests: XCTestCase {
    @Observable final class Model {
        var style = LumenChromeStyle.drawn
        var columns = NavigationSplitViewVisibility.all
    }

    private struct Subject: View {
        @Bindable var model: Model
        var body: some View {
            NavigationSplitView(columnVisibility: $model.columns) {
                Text("Sidebar").lumenSidebarToggle(columnVisibility: $model.columns)
                    .navigationSplitViewColumnWidth(210)
            } detail: {
                TextField("Selection survives", text: .constant("Detail"))
            }
            .lumenChromeStyle(model.style)
        }
    }

    func testSidebarToggleSwapsWithChromeStyleInTheSameWindow() throws {
        try XCTSkipUnless(LumenChromeStyle.systemSupportsGlass, "Glass requires macOS 26")
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency, "Glass resolves to drawn under Reduce Transparency")
        let model = Model()
        let host = NSHostingView(rootView: Subject(model: model))
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 972, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // AppKit tracking separators require full-size content; match the Catalog toolbar.
        window.toolbarStyle = .unified
        window.contentView = host
        defer { window.close() }
        func items() -> [NSToolbarItem] {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
            return window.toolbar?.items ?? []
        }
        func assertToggle(drawn: Bool, file: StaticString = #filePath, line: UInt = #line) {
            let identifiers = items().map { $0.itemIdentifier.rawValue }
            XCTAssertEqual(identifiers.filter { $0.contains("lumen.sidebarToggle") }.count, drawn ? 1 : 0,
                           "\(identifiers)", file: file, line: line)
            XCTAssertEqual(identifiers.filter { $0.lowercased().contains("sidebar") && !$0.contains("lumen.sidebarToggle") }.count,
                           drawn ? 0 : 1, "\(identifiers)", file: file, line: line)
        }
        assertToggle(drawn: true)
        let drawnItems = items()
        let toggleIndex = try XCTUnwrap(drawnItems.firstIndex { $0.itemIdentifier.rawValue.contains("lumen.sidebarToggle") })
        let separatorIndex = try XCTUnwrap(drawnItems.firstIndex { $0 is NSTrackingSeparatorToolbarItem })
        XCTAssertLessThan(toggleIndex, separatorIndex, "the toggle belongs on the sidebar side of the divider")
        let toggleView = try XCTUnwrap(drawnItems[toggleIndex].view)
        let toggleFrame = toggleView.convert(toggleView.bounds, to: nil)
        let separator = try XCTUnwrap(drawnItems[separatorIndex] as? NSTrackingSeparatorToolbarItem)
        let sidebar = separator.splitView.arrangedSubviews[separator.dividerIndex]
        let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
        XCTAssertEqual(sidebarFrame.maxX - toggleFrame.maxX, 8, accuracy: 1,
                       "the toggle tracks the actual sidebar trailing edge, including native width restoration")
        model.columns = .detailOnly
        model.style = .glass
        assertToggle(drawn: false)
        XCTAssertEqual(model.columns, .detailOnly)
        model.style = .drawn
        assertToggle(drawn: true)
        XCTAssertEqual(model.columns, .detailOnly)
    }

    func testFlexibleStatusAcceptsNarrowProposalWithoutShrinkingItsHeight() {
        let host = NSHostingController(rootView:
            LumenActivityStatus(.working("Analyzing libsystem_kernel.dylib", progress: 0.42), idealWidth: 300, minWidth: 180))
        let wide = host.sizeThatFits(in: CGSize(width: 300, height: 40))
        let narrow = host.sizeThatFits(in: CGSize(width: 180, height: 40))
        XCTAssertEqual(wide.width, 300, accuracy: 0.5)
        XCTAssertEqual(narrow.width, 180, accuracy: 0.5)
        XCTAssertEqual(narrow.height, wide.height, accuracy: 0.5)
        XCTAssertEqual(narrow.height, 24, accuracy: 0.5)
    }

    func testFlexibleToolbarStatusYieldsSpaceAndIdleStaysEmpty() {
        let activity = LumenActivity.working("Analyzing libsystem_kernel.dylib", progress: 0.42)
        let host = NSHostingView(rootView: LumenToolbarStatus(activity, minWidth: 180)
            .environment(\.lumenToolbarStatusRoom, 500))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 40)
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let wide = host.fittingSize
        host.rootView = LumenToolbarStatus(activity, minWidth: 180)
            .environment(\.lumenToolbarStatusRoom, 200)
        host.layoutSubtreeIfNeeded()
        let narrow = host.fittingSize
        XCTAssertGreaterThan(wide.width, 250, "the natural label grows beyond the old 180 pt budget")
        XCTAssertLessThanOrEqual(narrow.width, 200)
        XCTAssertLessThan(narrow.width, wide.width)
        XCTAssertEqual(narrow.height, wide.height, accuracy: 0.5)
        let idle = NSHostingController(rootView: LumenToolbarStatus(.idle(), minWidth: 180))
        XCTAssertEqual(idle.sizeThatFits(in: CGSize(width: 300, height: 40)).width, 0)
    }
}
