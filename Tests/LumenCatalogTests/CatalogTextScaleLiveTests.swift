import AppKit
import CoreText
import SwiftUI
import XCTest
import LumenUI
@testable import LumenCatalog

/// Design review 2026-11 #3: a text-scale change in Settings must reach a window that is already
/// open, not only windows opened afterwards. The change is written through the shared `UserDefaults`
/// instance the real Settings pane writes through.
@MainActor final class CatalogTextScaleLiveTests: XCTestCase {
    private final class Box { var size: CGFloat = 0 }

    private struct Probe: View {
        let box: Box
        @Environment(\.lumenMetrics) private var metrics
        @Environment(\.fontResolutionContext) private var context
        var body: some View {
            let size = CTFontGetSize(metrics.typography.body.resolve(in: context).ctFont)
            box.size = size
            return Text("Scale").font(metrics.typography.body)
        }
    }

    func testOpenWindowFollowsTextScaleChange() throws {
        let writer = CatalogChrome.defaults
        let saved = writer.object(forKey: CatalogTextScale.key)
        defer {
            if let saved { writer.set(saved, forKey: CatalogTextScale.key) } else { writer.removeObject(forKey: CatalogTextScale.key) }
        }
        writer.set(1.0, forKey: CatalogTextScale.key)

        let box = Box()
        // The order of the "catalog" scene: CatalogView applies the motion preference inside.
        let root = Probe(box: box)
            .catalogMotionPreference()
            .lumenPaletteRoot()
            .lumenDensityRoot()
            .modifier(CatalogTextScaleRoot())
            .modifier(CatalogChromeRoot())
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 200, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
        }
        settle()
        let base = box.size
        XCTAssertGreaterThan(base, 0)

        writer.set(1.3, forKey: CatalogTextScale.key)
        settle()
        print("TEXTSCALE base=\(base) after=\(box.size)")
        XCTAssertEqual(box.size, base * 1.3, accuracy: 0.6, "The open window kept its old text size")
    }

    /// At 1.3× the sidebar grows with its labels, and the window minimum still covers the split's
    /// real width (sidebar and inspector at their scaled ideals), so nothing runs off the leading edge.
    func testSidebarAndWindowMinimumGrowWithTextScale() {
        let regular = LumenMetrics.resolving(nil, textScale: 1)
        XCTAssertEqual(CatalogLayout.sidebarColumn(metrics: regular).ideal, CatalogLayout.sidebarIdealWidth)
        XCTAssertEqual(CatalogLayout.windowMinWidth(metrics: regular), CatalogLayout.windowMinWidth)

        let large = LumenMetrics.resolving(nil, textScale: 1.3)
        let sidebar = CatalogLayout.sidebarColumn(metrics: large)
        XCTAssertEqual(sidebar.ideal, CatalogLayout.sidebarIdealWidth * 1.3, accuracy: 1)
        XCTAssertEqual(CatalogLayout.windowMinWidth(metrics: large),
                       sidebar.ideal + CatalogLayout.pageMinWidth + LumenLayout.inspectorColumn(metrics: large).ideal + 2,
                       accuracy: 0.5)
        XCTAssertGreaterThan(CatalogLayout.windowMinWidth(metrics: large), CatalogLayout.windowMinWidth)
    }
}
