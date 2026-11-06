import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSheetFollowupSizingTests: XCTestCase {
    func testAutomaticLabelMeasureFollowsTypographyAndExplicitWidthStaysExact() {
        var automaticWidths: [Double: CGFloat] = [:]
        for scale in [1.0, 1.3] {
            let metrics = LumenMetrics.resolving(nil, textScale: scale)
            for explicit in [false, true] {
                var controlX: CGFloat = 0
                let row = LumenFormRow("Name", labelWidth: explicit ? 60 : nil) {
                    Color.clear.frame(width: 10, height: 10)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { controlX = $0 }
                }
                _ = hostedSize(row, width: 220, scale: scale)
                let labelWidth = controlX - metrics.spacing.s3
                if explicit {
                    XCTAssertEqual(labelWidth, 60, accuracy: 0.5)
                } else {
                    automaticWidths[scale] = labelWidth
                    if scale == 1 { XCTAssertEqual(labelWidth, 82, accuracy: 0.5) }
                }
            }
        }
        XCTAssertGreaterThan(automaticWidths[1.3] ?? 0, (automaticWidths[1.0] ?? 0) + 15,
                             "The measured automatic column must grow with enlarged typography")
        var custom = LumenMetrics.standard
        custom.typography.caption = .system(size: 26)
        custom.layout.propertyLabelWidth = 100
        var customX: CGFloat = 0
        let customRow = LumenFormRow("Name") {
            Color.clear.frame(width: 10, height: 10)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { customX = $0 }
        }
        _ = hostedSize(customRow, width: 300, scale: 1, metrics: custom)
        XCTAssertGreaterThan(customX, 180, "App-supplied typography must grow the shared automatic measure")
    }

    func testSheetSubtitleAndOversizedActionsWrapInNarrowHost() {
        for scale in [1.0, 1.3] {
            let long = "Continue reviewing the complete workspace configuration before saving changes"
            func sheet(_ subtitle: String, action: String) -> some View {
                LumenSheet("Review", subtitle: subtitle, systemImage: "doc",
                           status: .init("Ready"), cancelTitle: action, onCancel: {},
                           primary: LumenBarAction(action) {}) { Color.clear.frame(height: 1) }
            }
            let compact = hostedSize(sheet("Context", action: "Save"), width: 240, scale: scale)
            let subtitle = hostedSize(sheet(long, action: "Save"), width: 240, scale: scale)
            let actions = hostedSize(sheet("Context", action: long), width: 240, scale: scale)
            XCTAssertGreaterThan(subtitle.height, compact.height + 15)
            XCTAssertGreaterThan(actions.height, compact.height + 30)
            XCTAssertLessThanOrEqual(actions.width, 240.5)
        }
    }

    func testProcessIdentityAndSecondaryDetailsGrowInsteadOfTruncating() {
        for scale in [1.0, 1.3] {
            func list(_ name: String, user: String) -> some View {
                LumenProcessList([LumenProcess(pid: 4312, name: name, path: "/Library/Services/Worker",
                                              user: user, isPrivileged: true)], selection: .constant(nil))
            }
            let short = hostedSize(list("Worker", user: "root"), width: 220, scale: scale)
            let long = hostedSize(list("Workspace configuration indexing and dependency analysis worker",
                                       user: "An administrator account with a long display name"), width: 220, scale: scale)
            XCTAssertGreaterThan(long.height, short.height + 30)
            XCTAssertLessThanOrEqual(long.width, 220.5)
        }
    }

    private func hostedSize(_ view: some View, width: CGFloat, scale: Double, metrics: LumenMetrics? = nil) -> CGSize {
        var laidOutSize = CGSize.zero
        let controller = NSHostingController(rootView: view
            .lumenMetrics(metrics ?? .resolving(nil, textScale: scale))
            .lumenRendersOffscreen()
            .frame(width: width)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { laidOutSize = $0 }
            .fixedSize(horizontal: false, vertical: true))
        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: 2_000))
        let host = controller.view
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: 2_000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(CGSize(width: width, height: 2_000))
        defer { window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertGreaterThan(laidOutSize.height, 0, "Measure the laid-out SwiftUI content, not an unconstrained AppKit fitting size")
        XCTAssertEqual(fitted.height, laidOutSize.height, accuracy: 0.5)
        return laidOutSize
    }
}
