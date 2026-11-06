import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSidebarSelectionTests: XCTestCase {
    @Observable final class Model {
        var selected = 0
        var widths: [Int: CGFloat] = [:]
    }

    private struct Subject: View {
        let model: Model
        var body: some View {
            VStack(alignment: .leading) {
                ForEach(0..<2) { row in
                    LumenSidebarTitle(row == 0 ? "Wide navigation title" : "Symbols", font: .system(size: 13),
                                      isSelected: model.selected == row)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            model.widths[row] = width
                        }
                }
            }
        }
    }

    func testMovingSelectionPreservesBothTitleFrameWidths() throws {
        let model = Model()
        let host = NSHostingView(rootView: Subject(model: model))
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: -10000, y: -10000, width: 300, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        settle()
        let before = model.widths
        model.selected = 1
        settle()
        for row in 0..<2 {
            let width = try XCTUnwrap(before[row])
            XCTAssertGreaterThan(width, 20)
            XCTAssertEqual(try XCTUnwrap(model.widths[row]), width, accuracy: 0.01)
        }
    }
}
