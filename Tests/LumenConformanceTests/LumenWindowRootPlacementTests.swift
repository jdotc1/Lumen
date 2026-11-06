import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI
import LumenConformance

@MainActor
final class LumenWindowRootPlacementTests: XCTestCase {
    private final class Measurement { var frame = CGRect.null }

    private func settle(_ window: NSWindow) {
        for _ in 0..<35 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testOffscreenRootAddsNoInsetsOrWindowGrowth() throws {
        _ = NSApplication.shared
        let measure = Measurement()
        let root = Color.clear.frame(minWidth: 400, minHeight: 300)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measure.frame = $0 }
            .lumenPaletteRoot()
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(.init(width: 500, height: 400))
        defer { window.close() }
        settle(window)
        XCTAssertEqual(measure.frame, CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(window.frame.size, CGSize(width: 500, height: 400))
    }

    private struct OverflowContent: View {
        let minimum: CGSize
        let measure: Measurement
        var body: some View {
            Color.clear.frame(minWidth: minimum.width, minHeight: minimum.height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measure.frame = $0 }
        }
    }

    func testScreenLimitedMinimumStaysTopLeadingAndReportsLimit() throws {
        _ = NSApplication.shared
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let roots: [(String, @MainActor (OverflowContent) -> AnyView)] = [
            ("implicit", { AnyView($0.lumenPaletteRoot()) }),
            ("explicit", { AnyView($0.lumenPaletteRoot(store: .active)) }),
            ("implicit plain chrome", { AnyView($0.lumenPaletteRoot(windowChrome: false)) }),
            ("explicit plain chrome", { AnyView($0.lumenPaletteRoot(store: .active, windowChrome: false)) }),
            ("nested implicit", { AnyView($0.lumenPaletteRoot().lumenPaletteRoot()) }),
            ("nested mixed", { AnyView($0.lumenPaletteRoot(store: .active, windowChrome: false).lumenPaletteRoot()) }),
        ]
        for (name, wrap) in roots {
            for (axis, minimum) in [
                ("width", CGSize(width: visible.width + 200, height: 300)),
                ("height", CGSize(width: 400, height: visible.height + 200)),
                ("both", CGSize(width: visible.width + 200, height: visible.height + 200)),
            ] {
                let measure = Measurement()
                let host = NSHostingView(rootView: wrap(OverflowContent(minimum: minimum, measure: measure)))
                host.sizingOptions = []
                let window = LumenHeadlessHost.window(
                    contentRect: .init(x: visible.minX + 40, y: visible.minY + 40, width: 500, height: 400),
                    styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                    backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.title = "Overflow \(name) \(axis)"
                window.contentView = host
                window.setContentSize(.init(width: 500, height: 400))
                LumenHeadlessHost.order(window)
                defer { window.close() }
                settle(window)
                let context = "\(name) \(axis)"
                XCTAssertLessThanOrEqual(window.frame.width, visible.width + 0.5, context)
                XCTAssertLessThanOrEqual(window.frame.height, visible.height + 0.5, context)
                let minFrame = window.frameRect(forContentRect: .init(origin: .zero, size: window.contentMinSize))
                XCTAssertLessThanOrEqual(minFrame.width, visible.width + 0.5, context)
                XCTAssertLessThanOrEqual(minFrame.height, visible.height + 0.5, context)
                let hostScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
                let usable = window.convertToScreen(window.contentLayoutRect)
                XCTAssertEqual(measure.frame.minX, 0, accuracy: 0.5, context)
                XCTAssertEqual(measure.frame.minY, hostScreen.maxY - usable.maxY + LumenMetrics.standard.spacing.s4,
                               accuracy: 0.5, context)
                if axis != "height" {
                    XCTAssertEqual(window.frame.width, visible.width, accuracy: 0.5, context)
                    XCTAssertEqual(measure.frame.width, minimum.width, accuracy: 0.5, context)
                    XCTAssertGreaterThan(measure.frame.maxX, host.bounds.maxX, context)
                }
                if axis != "width" {
                    XCTAssertEqual(window.frame.height, visible.height, accuracy: 0.5, context)
                    XCTAssertEqual(measure.frame.height, minimum.height, accuracy: 0.5, context)
                    XCTAssertGreaterThan(measure.frame.maxY, host.bounds.maxY, context)
                }
                let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
                let closeFrame = window.convertToScreen(close.convert(close.bounds, to: nil))
                XCTAssertGreaterThanOrEqual(closeFrame.minY, usable.maxY - 0.5, context)
                XCTAssertLessThanOrEqual(closeFrame.maxY, window.frame.maxY + 0.5, context)
                XCTAssertTrue(LumenConformance.liveWindow(window).contains {
                    $0.message.contains("content minimum exceeds screen") && $0.subject.contains("OverflowContent")
                }, context)
                print("SCREEN LIMIT \(context): content=\(measure.frame); minimum=\(window.contentMinSize)")
            }
        }
    }
}
