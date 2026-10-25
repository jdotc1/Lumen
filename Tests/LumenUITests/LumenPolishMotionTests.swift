import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenPolishMotionTests: XCTestCase {
    func testNumericTextKeepsStateAcrossMotionPolicyChanges() throws {
        let probe = CounterProbe()
        var metrics = LumenMetrics.standard
        let host = NSHostingView(rootView: CounterView(probe: probe)
            .lumenNumericText(value: 123).lumenMetrics(metrics))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 120, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        func render() throws {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
        }

        try render()
        XCTAssertEqual(probe.value, 0)
        try XCTUnwrap(probe.increment)()
        try render()
        XCTAssertEqual(probe.value, 1)
        for enabled in [false, true] {
            metrics.motion.isEnabled = enabled
            host.rootView = CounterView(probe: probe)
                .lumenNumericText(value: 123).lumenMetrics(metrics)
            try render()
            XCTAssertEqual(probe.value, 1, "Counter reset with motion enabled: \(enabled)")
        }
        try XCTUnwrap(probe.increment)()
        try render()
        XCTAssertEqual(probe.value, 2, "The surviving counter remains writable")
    }

    func testAppSymbolEffectsRemovalRemainsEnabled() throws {
        throw XCTSkip("symbolEffectsRemoved is a graph input with no public readable environment key; inherited removal cannot be asserted headlessly through the public interface.")
    }
}

@MainActor
private final class CounterProbe {
    var value: Int?
    var increment: (() -> Void)?
}

private struct CounterView: View {
    let probe: CounterProbe
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .background(CounterBridge(count: $count, probe: probe))
    }
}

private struct CounterBridge: NSViewRepresentable {
    @Binding var count: Int
    let probe: CounterProbe

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        probe.value = count
        probe.increment = { count += 1 }
    }
}
