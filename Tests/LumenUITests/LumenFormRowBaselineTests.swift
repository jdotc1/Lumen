import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenTestSupport
@testable import LumenUI

/// Design review 2026-11 #8: a form row's label shares the first text baseline of its control.
/// The date and time fields host a native editor whose container reported no baseline, so their
/// labels rode up to the field's top edge.
@MainActor
final class LumenFormRowBaselineTests: XCTestCase {
    func testDateAndTimeLabelsSitOnTheFieldBaseline() throws {
        let date = Date(timeIntervalSinceReferenceDate: 815_000_000)
        for (name, field) in [("date", AnyView(LumenDateField(selection: .constant(date)))),
                              ("time", AnyView(LumenTimeField(selection: .constant(date)))),
                              ("number", AnyView(LumenNumberField(value: .constant(3), in: 0...10)))] {
            let (label, control) = try measure(field)
            print("FORM-BASELINE \(name) label=\(label) control=\(control)")
            XCTAssertEqual(label.midY, control.midY, accuracy: 3,
                           "\(name): the label is centred on its field when the baselines agree")
        }
    }

    private func measure(_ field: AnyView) throws -> (CGRect, CGRect) {
        var frames: [LumenMarginElementFrame] = []
        // The same `.firstTextBaseline` row `LumenFormRow` builds, with the label probed.
        let probe = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Label").font(LumenMetrics.standard.typography.callout).lumenReportsMarginElement("probe-label")
            field.lumenReportsMarginElement("probe-control")
        }
        .padding(20)
        let host = NSHostingView(rootView: probe.lumenPaletteRoot()
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 })
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<15 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let label = try XCTUnwrap(frames.first { $0.role == "probe-label" }).frame
        let control = try XCTUnwrap(frames.first { $0.role == "probe-control" }).frame
        return (label, control)
    }
}
