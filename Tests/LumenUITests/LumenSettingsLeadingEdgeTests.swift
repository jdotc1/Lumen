import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenTestSupport
@testable import LumenUI

/// Design review 2026-11 #7: settings panes must share one leading edge. The pane header's tile,
/// a rich pane's rows and a grouped pane's row labels all start at the same x, whichever style
/// or grouping the pane uses.
@MainActor
final class LumenSettingsLeadingEdgeTests: XCTestCase {
    func testPanesShareTheHeaderLeadingEdge() throws {
        for width: CGFloat in [520, 700, 900] {
            let grouped = try measure(width: width, AnyView(
                LumenSettingsPane("Shortcuts", systemImage: "command", hue: .hueBlue, summary: "Keys.") {
                    LabeledContent { Text("⌘G") } label: { Text("Go to Address").lumenReportsMarginElement("probe-row") }
                }))
            let rich = try measure(width: width, AnyView(
                LumenSettingsPane("Automation", systemImage: "gearshape.2", hue: .hueTeal, summary: "Steps.", style: .rich) {
                    LumenFormSection("Before analysis") {
                        LumenSettingsRow("Validate input", description: "Check files.") { Toggle("", isOn: .constant(true)) }
                            .lumenReportsMarginElement("probe-row")
                    }
                }))
            let group = try measure(width: width, AnyView(
                LumenSettingsPane("Engine", systemImage: "cpu", hue: .hueViolet, summary: "Engine.", style: .rich) {
                    LumenSettingsGroup {
                        LumenFormSection("Analysis engine") {
                            LumenSettingsRow("Bundled runtime", description: "Ready.") { Button("Check") {} }
                                .lumenReportsMarginElement("probe-row")
                        }
                    }
                }))
            let appearance = try measure(width: width, AnyView(LumenAppearanceSettings(showsGallery: false)), row: false)
            XCTAssertEqual(appearance.header, rich.header, accuracy: 1, "appearance vs rich header edge at \(width)")
            print("SETTINGS-EDGE appearance=\(appearance)  width=\(width) grouped=\(grouped) rich=\(rich) group=\(group)")
            for (name, m) in [("rich", rich), ("group", group)] {
                XCTAssertEqual(m.row, m.header, accuracy: 1, "\(name) pane at \(width): rows start at the header's edge")
            }
            // A grouped pane's row text sits one box inset inside the box, whose edge is the header's.
            XCTAssertEqual(grouped.row, grouped.header + LumenGroupedFormInsets.row, accuracy: 1,
                           "grouped pane at \(width): row text one box inset in from the header")
            XCTAssertEqual(grouped.header, rich.header, accuracy: 1, "grouped vs rich header edge at \(width)")
            XCTAssertEqual(group.header, rich.header, accuracy: 1, "grouped-rows vs rich header edge at \(width)")
        }
    }

    private func measure(width: CGFloat, _ pane: AnyView, row measuresRow: Bool = true) throws -> (header: CGFloat, row: CGFloat) {
        var frames: [LumenMarginElementFrame] = []
        let host = NSHostingView(rootView: pane.lumenPaletteRoot()
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 })
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: width, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<25 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let header = try XCTUnwrap(frames.first { $0.role == "settings-pane-header" }, "header frame")
        guard measuresRow else { return (header.frame.minX, header.frame.minX) }
        let row = try XCTUnwrap(frames.first { $0.role == "probe-row" }, "row frame; roles: \(frames.map(\.role))")
        return (header.frame.minX, row.frame.minX)
    }
}
