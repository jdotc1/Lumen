import AppKit
import SwiftUI
import XCTest
import LumenUI
import LumenCatalog

// The sample workspace uses the real-window minimum/toolbar host and public API.
extension LumenLiveWindowTests {
    func testSampleWorkspaceFitsMinimumAndDefaultSizes() throws {
        let minimum = layOut(SampleWorkspace(), size: SampleWorkspace.defaultSize,
                             compact: true, sizing: [.minSize]).contentMinSize
        XCTAssertEqual(minimum.width, SampleWorkspace.minimumSize.width, accuracy: 0.5)
        XCTAssertEqual(minimum.height, SampleWorkspace.minimumSize.height, accuracy: 1)
        // Check the supported workspace modes at their minimum and default sizes.
        for mode in [SampleWorkspaceMode.disassembly, .graph, .welcome] {
            for size in [minimum, SampleWorkspace.defaultSize] {
                let reports = SampleWorkspaceLayoutReports()
                let view = SampleWorkspace(mode: mode)
                    .onPreferenceChange(LumenTruncationKey.self) { value in
                        MainActor.assumeIsolated { reports.truncated = value }
                    }
                    .onPreferenceChange(LumenOverflowKey.self) { value in
                        MainActor.assumeIsolated { reports.overflow = value }
                    }
                    .onPreferenceChange(LumenColumnOverflowKey.self) { value in
                        MainActor.assumeIsolated { reports.columns = value }
                    }
                let layout = layOut(view, size: size, compact: true)
                let context = "\(mode) at \(size)"
                XCTAssertEqual(reports.truncated, [], context)
                XCTAssertEqual(reports.overflow, [], context)
                XCTAssertEqual(reports.columns, [], context)
                let split = try XCTUnwrap(layout.splits.first, context)
                XCTAssertGreaterThanOrEqual(split.frame.minX, -0.5, context)
                XCTAssertLessThanOrEqual(split.frame.maxX, size.width + 0.5, context)
                XCTAssertGreaterThan(split.frame.height, 360, context)
                let shown = split.columns.filter { $0.width > 1 }
                XCTAssertEqual(shown.count, size.width < 1220 ? 2 : 3, context)
                for column in shown {
                    XCTAssertGreaterThan(column.height, 360, context)
                    XCTAssertGreaterThanOrEqual(column.minY, split.frame.minY - 0.5, context)
                    XCTAssertLessThanOrEqual(column.maxY, split.frame.maxY + 0.5, context)
                }
                XCTAssertGreaterThanOrEqual(shown[0].width, 328 - 0.5, context)
                XCTAssertGreaterThanOrEqual(shown[1].width, 560 - 0.5, context)
                let bar = try XCTUnwrap(layout.bar, context)
                XCTAssertEqual(bar.minY, 0, accuracy: 0.5, context)
                if let top = layout.regionTop { XCTAssertGreaterThanOrEqual(top, bar.maxY - 0.5, context) }
            }
        }
    }

    func testBottomPanelAbsoluteAndFractionalCaps() {
        // Ask for more than either cap so this measures the rendered clamp, not the default height.
        let cases: [(CGFloat, CGFloat, CGFloat?, CGFloat?)] = [
            (1600.0, 120.0, Optional(360.0), 360.0),
            (800.0, 120.0, Optional(360.0), nil),
            (1800.0, 400.0, Optional(360.0), 400.0),
            (1600.0, 120.0, nil, nil),
        ]
        for (total, minimum, cap, expected) in cases {
            let reports = SampleWorkspaceLayoutReports()
            let view = Color.clear
                .lumenBottomPanel(isPresented: .constant(true), height: .constant(900),
                                  minHeight: minimum, contentMinHeight: 360,
                                  maxFraction: 0.25, maximumHeight: cap) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomPanelHeightKey.self, value: proxy.size.height)
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomPanelAvailableHeightKey.self, value: proxy.size.height)
                    }
                }
                .onPreferenceChange(BottomPanelAvailableHeightKey.self) { value in
                    MainActor.assumeIsolated { reports.availableHeight = value }
                }
                .onPreferenceChange(BottomPanelHeightKey.self) { value in
                    MainActor.assumeIsolated { reports.panelHeight = value }
                }
            _ = layOut(view, size: CGSize(width: 900, height: total), compact: true)
            XCTAssertGreaterThan(reports.availableHeight, 0)
            let expected = expected ?? reports.availableHeight * 0.25
            XCTAssertEqual(reports.panelHeight, expected, accuracy: 0.5, "total \(total), minimum \(minimum)")
            XCTAssertLessThanOrEqual(reports.panelHeight, expected)
        }
    }

    func testWorkspacePublicContentMinimumWidth() throws {
        let view = LumenWorkspaceWindow(panels: .constant(.init(leading: true, bottom: false, trailing: false))) {
            Color.clear
        } sidebar: {
            Color.clear
        } topLeading: {
            Text("Editor minimum")
        }
        .columnWidths(sidebar: (328, 328, 384))
        .contentMinimumWidth(560)
        .frame(minWidth: 890, minHeight: 500)
        let layout = layOut(view, size: CGSize(width: 890, height: 600), compact: true)
        let split = try XCTUnwrap(layout.splits.first)
        XCTAssertEqual(split.columns.count, 2)
        XCTAssertGreaterThanOrEqual(split.columns[1].width, 560 - 0.5)
        XCTAssertLessThanOrEqual(split.frame.maxX, 890.5)
    }
}

@MainActor
private final class SampleWorkspaceLayoutReports {
    var availableHeight: CGFloat = 0
    var panelHeight: CGFloat = 0
    var truncated: Set<String> = []
    var overflow: Set<String> = []
    var columns: Set<String> = []
}

private struct BottomPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BottomPanelAvailableHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
