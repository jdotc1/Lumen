import LumenTestSupport
import LumenTokens
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenLayoutGuaranteeTests: XCTestCase {
    private final class Recorder { var frames: [LumenMarginElementFrame] = [] }
    private final class Arrangement {
        var raw = "tool9,-tool8,tool7,tool6,tool5,tool4,tool3,tool2,tool1,tool0"
        var writes = 0
    }

    private func measure<Content: View>(_ content: Content, width: CGFloat) -> [LumenMarginElementFrame] {
        let recorder = Recorder()
        let root = content.frame(width: width, height: 120, alignment: .top)
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames in
                MainActor.assumeIsolated { recorder.frames = frames }
            }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: width, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        window.close()
        return recorder.frames
    }

    private func headerRuleSpansRegion(_ frames: [LumenMarginElementFrame]) throws -> Bool {
        let rule = try XCTUnwrap(frames.first { $0.role == "inspector header rule" }?.frame)
        let region = try XCTUnwrap(frames.first { $0.role == "inspector header region" }?.frame)
        return abs(rule.minX - region.minX) < 0.5 && abs(rule.maxX - region.maxX) < 0.5
    }

    func testInspectorHeaderRuleSpansItsColumnIncludingTheContentMargin() throws {
        for width: CGFloat in [220, 320] {
            for margin: CGFloat in [0, 16, 24] {
                let frames = measure(LumenInspectorHeader("Selection", systemImage: "doc")
                    .environment(\.lumenScaffoldContentMargin, margin), width: width)
                XCTAssertTrue(try headerRuleSpansRegion(frames), "Reject a rule narrower than its inspector")
                let region = try XCTUnwrap(frames.first { $0.role == "inspector header region" }?.frame)
                XCTAssertEqual(region.width, width, accuracy: 0.5)
            }
        }
    }

    func testInspectorHeaderConformanceRejectsTheOldOverlayBeforeTrailingPadding() throws {
        let oldOrder = HStack { Text("Selection"); Spacer(minLength: 0) }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().frame(height: 1).lumenReportsMarginElement("inspector header rule")
            }
            .padding(.trailing, 16)
            .lumenReportsMarginElement("inspector header region")
        let frames = measure(oldOrder, width: 320)
        XCTAssertFalse(try headerRuleSpansRegion(frames), "The old order must fail the same conformance condition")
        let rule = try XCTUnwrap(frames.first { $0.role == "inspector header rule" }?.frame)
        XCTAssertEqual(rule.width, 304, accuracy: 0.5)
    }

    func testWholeTileStripUsesOnlyCompleteSlotsAndNeverWritesArrangement() throws {
        let state = Arrangement()
        let binding = Binding(get: { state.raw }, set: { state.raw = $0; state.writes += 1 })
        let items = (0..<10).map { LumenSidebarItem(id: "tool\($0)", title: "Tool \($0)", systemImage: "doc") }
        let slot = LumenSidebarSwitcher.tileSlotWidth(tileSize: LumenMetrics.standard.layout.tileTool)
        for width in [4 * slot, 4 * slot - 0.001, 4.8 * slot, 2 * slot - 0.001, 10 * slot] {
            let frames = measure(LumenSidebarSwitcher(selection: .constant("tool4"), items: items,
                shortcuts: false, arrangement: binding, style: .tiles, overflow: .wholeTiles), width: width)
            let tiles = frames.filter { $0.role.hasPrefix("sidebar tile:") }
            XCTAssertTrue(tiles.contains { $0.role == "sidebar tile:tool4" }, "Reject a missing selection")
            XCTAssertFalse(tiles.contains { $0.role == "sidebar tile:tool8" }, "Reject a user-hidden tile")
            for tile in tiles { XCTAssertEqual(tile.frame.width, slot, accuracy: 0.01, "Reject a fractional tile") }
            let more = frames.filter { $0.role == "sidebar more" }
            let expectedSlots = width >= 9 * slot ? 9 : (width < 2 * slot ? 1 : (width < 4 * slot ? 3 : 4))
            let ordered = (tiles + more).sorted { $0.frame.minX < $1.frame.minX }
            if let first = ordered.first, let last = ordered.last {
                XCTAssertEqual(first.frame.minX, 0, accuracy: 0.5, "Reject a row that leaves the leading edge")
                if more.isEmpty {
                    XCTAssertEqual(last.frame.maxX, CGFloat(ordered.count) * slot, accuracy: 0.5, "Reject spreading a row that fits")
                } else {
                    XCTAssertEqual(last.role, "sidebar more", "Reject a More slot that is not last")
                    XCTAssertEqual(last.frame.maxX, width, accuracy: 0.5, "Reject a ragged trailing remainder")
                }
            }
            XCTAssertEqual(tiles.count + more.count, expectedSlots, "Reject a lost More reserve or upward rounding")
            if width < 2 * slot { XCTAssertTrue(more.isEmpty) }
            // Allow subpixel placement rounding; slot widths and capacities stay exact above.
            for element in tiles + more {
                XCTAssertGreaterThanOrEqual(element.frame.minX, -0.5)
                XCTAssertLessThanOrEqual(element.frame.maxX, width + 0.5, "Reject a clipped whole slot")
            }
        }
        XCTAssertEqual(state.writes, 0, "Reject persisting fit-driven hiding")
        XCTAssertEqual(state.raw, "tool9,-tool8,tool7,tool6,tool5,tool4,tool3,tool2,tool1,tool0")
    }

    func testDefaultTileStyleRetainsAllVisibleItemsWithoutMore() {
        let items = (0..<10).map { LumenSidebarItem(id: "tool\($0)", title: "Tool \($0)", systemImage: "doc") }
        let frames = measure(LumenSidebarSwitcher(selection: .constant("tool0"), items: items,
            shortcuts: false, style: .tiles), width: 160)
        XCTAssertEqual(frames.filter { $0.role.hasPrefix("sidebar tile:") }.count, 10)
        XCTAssertFalse(frames.contains { $0.role == "sidebar more" })
    }
}
