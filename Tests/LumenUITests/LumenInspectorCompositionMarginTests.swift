import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@testable import LumenUI

@MainActor final class LumenInspectorCompositionMarginTests: XCTestCase {
    func testDirectSectionsMatchColumnClearanceWithoutDoublePadding() throws {
        var direct: [LumenMarginElementFrame] = []
        var column: [LumenMarginElementFrame] = []
        let root = HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) { sections }
                .frame(width: 280, height: 420, alignment: .top)
                .onPreferenceChange(LumenMarginElementFrameKey.self) { direct = $0 }
            LumenInspector(scrolls: false) { sections }
                .frame(width: 280, height: 420, alignment: .top)
                .onPreferenceChange(LumenMarginElementFrameKey.self) { column = $0 }
        }
        .lumenScaffoldMargin(16)
        .lumenPaletteRoot()
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        for role in ["inspector header", "inspector section", "inspector summary card", "section trailing control"] {
            let plain = try XCTUnwrap(direct.first { $0.role == role }).frame
            let wrapped = try XCTUnwrap(column.first { $0.role == role }).frame.offsetBy(dx: -320, dy: 0)
            print("INSPECTOR-COMPOSITION role=\(role) direct=\(plain) column=\(wrapped)")
            XCTAssertEqual(plain.minX, wrapped.minX, accuracy: 0.01, role)
            XCTAssertEqual(plain.minY, wrapped.minY, accuracy: 0.01, role)
            XCTAssertEqual(plain.width, wrapped.width, accuracy: 0.01, role)
            XCTAssertEqual(plain.height, wrapped.height, accuracy: 0.01, role)
            XCTAssertLessThanOrEqual(plain.maxX, 264, role)
            if role == "inspector header" || role == "inspector section" {
                XCTAssertEqual(wrapped.width, 264, accuracy: 0.01, "Column width must stay unchanged")
            }
            if role == "inspector summary card" {
                XCTAssertEqual(wrapped.maxX, 258, accuracy: 0.01, "Summary edge must stay unchanged")
            }
            if role == "section trailing control" {
                XCTAssertEqual(wrapped.maxX, 252, accuracy: 0.01, "Section control must stay unchanged")
            }
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }

    private var sections: some View {
        Group {
            LumenInspectorHeader("Document", subtitle: "Plain text", systemImage: "doc.text")
            LumenInspectorSummary(kind: "Instruction", title: "0x100003f0c")
            LumenInspectorSection("Address Detail", systemImage: "scope") {
                HStack {
                    Text("Address")
                    Spacer(minLength: 0)
                    Color.red.frame(width: 8, height: 8)
                        .lumenReportsMarginElement("section trailing control")
                }
            }
        }
    }
}
