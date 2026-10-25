import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenLegacyColumnSizingTests: XCTestCase {
    func testSidebarUsesHostWidthsBeyondLegacyCap() {
        let view = Color.clear.lumenSidebarColumn(min: 300, ideal: 460, max: 640)
        XCTAssertEqual(width(of: view, proposed: 520), 520, accuracy: 0.5)
        XCTAssertEqual(width(of: view, proposed: 1), 300, accuracy: 0.5)
        XCTAssertEqual(width(of: view, proposed: 900), 640, accuracy: 0.5)
    }

    func testInspectorPaneUsesHostWidthsBeyondLegacyCap() {
        let view = LumenInspectorPane { Color.clear.frame(height: 40) }
            .columnWidth(min: 300, ideal: 460, max: 640)
        XCTAssertEqual(width(of: view, proposed: 520), 520, accuracy: 0.5)
        XCTAssertEqual(width(of: view, proposed: 1), 300, accuracy: 0.5)
        XCTAssertEqual(width(of: view, proposed: 900), 640, accuracy: 0.5)
    }

    func testImplicitColumnsGrowWithTextScale() {
        let scaled = LumenMetrics.resolving(nil, textScale: 1.3)
        XCTAssertEqual(width(of: Color.clear.lumenSidebarColumn(), metrics: .standard), 320, accuracy: 0.5)
        XCTAssertEqual(width(of: Color.clear.lumenSidebarColumn(), metrics: scaled), 416, accuracy: 0.5)
        let inspector = LumenInspectorPane { Color.clear.frame(height: 40) }
        XCTAssertEqual(width(of: inspector, metrics: .standard), 360, accuracy: 0.5)
        XCTAssertEqual(width(of: inspector, metrics: scaled), 468, accuracy: 0.5)
    }

    func testExplicitColumnWidthsRemainPointsAtLargerTextScale() {
        let scaled = LumenMetrics.resolving(nil, textScale: 1.3)
        let sidebar = Color.clear.lumenSidebarColumn(min: 300, ideal: 460, max: 640)
        let inspector = LumenInspectorPane { Color.clear.frame(height: 40) }
            .columnWidth(min: 300, ideal: 460, max: 640)
        XCTAssertEqual(width(of: sidebar, metrics: scaled), 640, accuracy: 0.5)
        XCTAssertEqual(width(of: inspector, metrics: scaled), 640, accuracy: 0.5)
    }

    private func width(of view: some View, proposed: CGFloat = 900, metrics: LumenMetrics = .standard) -> CGFloat {
        let host = NSHostingController(rootView: view.lumenPaletteRoot().lumenMetrics(metrics))
        return host.sizeThatFits(in: CGSize(width: proposed, height: 240)).width
    }
}
