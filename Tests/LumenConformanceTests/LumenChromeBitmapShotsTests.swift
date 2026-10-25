import AppKit
import LumenTestSupport
@_spi(LayoutAudit) import LumenUI
import SwiftUI
import XCTest

/// Reference artifacts use only the guarded bitmap route.
@MainActor
final class LumenChromeBitmapShotsTests: XCTestCase {
    func testBeforeAndAfterRootBitmaps() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "shots")
        for rooted in [false, true] {
            let fixture = VStack {
                Button("Open Comparison Fixture") {}
                Color.gray.opacity(0.1)
                    .overlay(alignment: .topLeading) {
                        Text("Reference workspace · 1000 × 760 minimum").padding(40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .font(.custom("Arial", size: 10))
            .frame(minWidth: 1000, minHeight: 760)
            let root = rooted ? AnyView(fixture.lumenPaletteRoot()) : AnyView(fixture)
            let host = NSHostingView(rootView: root.environment(\.colorScheme, .dark))
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(
                contentRect: CGRect(x: 0, y: 0, width: 1000, height: 660),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Lumen Chrome Measurement"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            LumenHeadlessHost.order(window)
            defer { window.close() }
            for _ in 0..<12 {
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            let capture = try LumenRenderedAudit.capture(in: window)
            let name = rooted ? "chrome-after.png" : "chrome-before.png"
            let bitmap = NSBitmapImageRep(cgImage: capture.image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appending(path: name))
            print("CHROME BITMAP \(name): \(capture.image.width)x\(capture.image.height); root=\(rooted)")
        }
    }
}
