import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenTestSupport
@testable import LumenUI

@MainActor final class LumenBottomMarginGuaranteeTests: XCTestCase {
    func testHostedBarKeepsTrailingItemAndStrokeInsideDeclaredMargin() throws {
        let margin: CGFloat = 16
        var bars: [CGRect] = []
        var trailing = CGRect.zero
        let root = VStack(spacing: 0) {
            Color.clear
            LumenStatusBar {
                Text("Leading")
                Spacer(minLength: 0)
                Color.red.frame(width: 8, height: 8)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trailing = $0 }
            }
            .padding(4)
        }
        .lumenScaffoldMargin(margin)
        .onPreferenceChange(LumenBottomBarFrameKey.self) { bars = $0 }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let size = CGSize(width: 400, height: 160)
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                                             styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let bar = try XCTUnwrap(bars.first)
        print("MARGIN-GUARANTEE bar=\(bar) trailing=\(trailing) declared=\(margin) window=\(window.frame)")
        XCTAssertGreaterThan(trailing.width, 0)
        XCTAssertGreaterThanOrEqual(size.width - trailing.maxX, margin)
        XCTAssertGreaterThanOrEqual(bar.minX, margin)
        XCTAssertGreaterThanOrEqual(size.width - bar.maxX, margin)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }

    func testInspectorPreservesContentTrailingPaddingInsideDeclaredMargin() throws {
        var trailing = CGRect.zero
        let root = LumenInspector {
            // Clearance belongs to shared sections, including when composed without the column.
            LumenInspectorSection("Content") {
                HStack {
                    Spacer(minLength: 0)
                    Color.red.frame(width: 8, height: 8)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { trailing = $0 }
                }.padding(.trailing, 12)
            }
        }.lumenScaffoldMargin(16)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 280, height: 200),
                                             styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        print("INSPECTOR-GUARANTEE trailing=\(trailing) declared=16 ownPadding=12")
        XCTAssertEqual(trailing.width, 8)
        XCTAssertGreaterThanOrEqual(280 - trailing.maxX, 16 + 12)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }


    func testNestedPaletteRootPreservesLargerAndZeroScaffoldMargins() throws {
        for margin: CGFloat in [24, 0] {
            var bars: [CGRect] = []
            let root = LumenStatusBar { Text("Leading"); Spacer(minLength: 0); Text("Trailing") }
                .lumenPaletteRoot()
                .lumenScaffoldMargin(margin)
                .onPreferenceChange(LumenBottomBarFrameKey.self) { bars = $0 }
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 400, height: 160),
                                                 styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            LumenHeadlessHost.prepare(window)
            defer { window.close() }
            for _ in 0..<20 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let bar = try XCTUnwrap(bars.first)
            print("NESTED-MARGIN-GUARANTEE bar=\(bar) declared=\(margin)")
            XCTAssertEqual(bar.minX, margin, accuracy: 0.5)
            XCTAssertEqual(400 - bar.maxX, margin, accuracy: 0.5)
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertFalse(NSApp.isActive)
        }
    }

}
