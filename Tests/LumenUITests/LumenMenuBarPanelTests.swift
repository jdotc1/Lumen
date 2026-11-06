import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenConformance
@testable import LumenUI

@MainActor
final class LumenMenuBarPanelTests: XCTestCase {
    func testOptionalRegionsAndLongContentStayInsidePanel() {
        for header in [false, true] {
            for footer in [false, true] {
                for count in [1, 40] {
                    let findings = LumenConformance.windowStructure(kind: .menuBarPanel,
                        sizes: [.init(width: 280, height: 480), .init(width: 280, height: 240)]) {
                        LumenMenuBarPanel(header ? "Agent" : nil, width: 280, maximumHeight: 480, showsFooter: footer) {
                            ForEach(0..<count, id: \.self) { index in
                                Text("Recent item \(index)").lineLimit(1).lumenNeverTruncates("Recent item \(index)")
                            }
                        } accessory: {
                            Text("Ready")
                        } footer: {
                            Text("Last sync just now")
                        }
                        .lumenPaletteRoot()
                    }
                    XCTAssertEqual(findings.map(\.description), [], "header=\(header), footer=\(footer), count=\(count)")
                }
            }
        }
    }

    func testShortContentHugsAndLongContentScrollsAtCustomMaximum() throws {
        for bodyHeight: CGFloat in [20, 600] {
            var entries: [LumenMenuBarPanelLayoutEntry] = []
            let view = LumenMenuBarPanel("Agent", width: 280, maximumHeight: 240) {
                Color.clear.frame(height: bodyHeight)
            }.lumenPaletteRoot()
                .onPreferenceChange(LumenMenuBarPanelLayoutKey.self) { value in
                    MainActor.assumeIsolated { entries = value }
                }
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 280, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let panel = try XCTUnwrap(entries.first { $0.region == .panel }).frame
            let viewport = try XCTUnwrap(entries.first { $0.region == .content }).frame
            let content = try XCTUnwrap(entries.first { $0.region == .scrollContent }).frame
            let header = try XCTUnwrap(entries.first { $0.region == .header }).frame
            let footer = try XCTUnwrap(entries.first { $0.region == .footer }).frame
            let dividers = viewport.minY - header.maxY + footer.minY - viewport.maxY
            let naturalHeight = header.height + content.height + footer.height + dividers
            XCTAssertEqual(panel.height, min(naturalHeight, 240), accuracy: 0.5)
            if bodyHeight == 20 {
                XCTAssertLessThan(panel.height, 240)
                XCTAssertEqual(viewport.height, content.height, accuracy: 0.5)
            } else {
                XCTAssertEqual(panel.height, 240, accuracy: 0.5)
                XCTAssertGreaterThan(content.height, viewport.height)
            }
            print("Panel sizing: body=\(bodyHeight), panel=\(panel.height), natural=\(naturalHeight), viewport=\(viewport.height), content=\(content.height)")
        }
    }

    func testHeaderTruncationIsReported() {
        let findings = LumenConformance.windowStructure(kind: .menuBarPanel, sizes: [.init(width: 280, height: 480)]) {
            LumenMenuBarPanel("A very long agent title that cannot possibly fit in this panel", width: 280, maximumHeight: 480) {
                Text("Ready")
            }.lumenPaletteRoot()
        }
        XCTAssertTrue(findings.contains { $0.message.contains("is cut short") })
    }

    func testContentWiderThanTheViewportIsReported() {
        let findings = LumenConformance.windowStructure(kind: .menuBarPanel, sizes: [.init(width: 280, height: 480)]) {
            LumenMenuBarPanel(width: 280, maximumHeight: 480) {
                Color.clear.frame(width: 400, height: 20)
            }.lumenPaletteRoot()
        }
        XCTAssertTrue(findings.contains {
            $0.message == "the menu bar panel scrolling content exceeds its width"
                || ($0.message.contains("Menu bar panel content") && $0.message.contains("wider than its column"))
        }, findings.map(\.description).joined(separator: "\n"))
    }

    func testMaximumHeightAndPinnedFooterWithOverflowingBody() {
        var entries: [LumenMenuBarPanelLayoutEntry] = []
        let view = LumenMenuBarPanel("Agent", width: 280, maximumHeight: 240) {
            ForEach(0..<40, id: \.self) { Text("Item \($0)") }
        }.lumenPaletteRoot()
            .onPreferenceChange(LumenMenuBarPanelLayoutKey.self) { value in
                MainActor.assumeIsolated { entries = value }
            }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 280, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let panel = entries.first { $0.region == .panel }?.frame ?? .zero
        let content = entries.first { $0.region == .content }?.frame ?? .zero
        let scroll = entries.first { $0.region == .scrollContent }?.frame ?? .zero
        let footer = entries.first { $0.region == .footer }?.frame ?? .zero
        XCTAssertEqual(panel.width, 280, accuracy: 0.5)
        XCTAssertEqual(panel.height, 240, accuracy: 0.5)
        XCTAssertGreaterThan(scroll.height, content.height)
        XCTAssertGreaterThan(footer.height, 0)
        XCTAssertEqual(footer.maxY, panel.maxY, accuracy: 0.5)
    }
}
