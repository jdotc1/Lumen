import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSettingsFormRowTests: XCTestCase {
    func testButtonRowMatchesRegularBorderedPushButtons() throws {
        func actions() -> some View {
            Group {
                Button("Apply") {}
                Button("Refresh") {}
            }
        }
        func raster(_ view: some View) throws -> Data {
            let host = NSHostingView(rootView: view.frame(width: 480, height: 60))
            host.frame = CGRect(x: 0, y: 0, width: 480, height: 60)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        let actual = try raster(LumenSettingsButtonRow { actions() }.controlSize(.small).buttonStyle(.borderless))
        let expected = try raster(HStack(spacing: LumenMetrics.standard.spacing.s3) { actions() }
            .buttonStyle(.bordered).controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, LumenMetrics.standard.spacing.s2))
        XCTAssertEqual(actual, expected, "Settings actions must match regular native bordered controls, including inside borderless forms")
    }

    func testMultipleActionsUseTrailingControlGroup() throws {
        let frames = SettingsFrames()
        let root = LumenSettingsRow("Actions") {
            Button("Apply") {}.background(SettingsFrameReader(id: "apply"))
            Button("Refresh") {}.background(SettingsFrameReader(id: "refresh"))
        }
        .frame(width: 480, height: 60)
        .coordinateSpace(name: "row")
        .onPreferenceChange(SettingsFramesKey.self) { value in
            MainActor.assumeIsolated { frames.values = value }
        }
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 480, height: 60)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        host.layoutSubtreeIfNeeded()
        let apply = try XCTUnwrap(frames.values["apply"])
        let refresh = try XCTUnwrap(frames.values["refresh"])
        let labelWidth = NSHostingView(rootView: Text("Actions").font(LumenMetrics.standard.typography.body)).fittingSize.width
        XCTAssertGreaterThan(apply.minX, labelWidth, "Leading label must have room before the trailing group")
        XCTAssertGreaterThan(refresh.minX, apply.maxX, "Both actions need system spacing without overlap")
        XCTAssertEqual(refresh.maxX, 480, accuracy: 0.5)
        XCTAssertEqual(apply.midY, refresh.midY, accuracy: 0.5)
    }

    func testLayoutPlacesLabelWithZeroOneAndSeveralControls() throws {
        for count in 0...3 {
            for width: CGFloat in [160, 480] {
                let frames = SettingsFrames()
                let root = LumenSettingsRowLayout(spacing: 16) {
                    Text("Actions").background(SettingsFrameReader(id: "label"))
                    ForEach(0..<count, id: \.self) { index in
                        Text("Control \(index)").background(SettingsFrameReader(id: "c\(index)"))
                    }
                }
                .frame(width: width)
                .coordinateSpace(name: "row")
                .onPreferenceChange(SettingsFramesKey.self) { value in
                    MainActor.assumeIsolated { frames.values = value }
                }
                let host = NSHostingView(rootView: root)
                host.frame.size = CGSize(width: width, height: 120)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                host.layoutSubtreeIfNeeded()
                let label = try XCTUnwrap(frames.values["label"])
                XCTAssertEqual(label.minX, 0, accuracy: 0.5)
                XCTAssertGreaterThan(label.height, 0)
                if count > 0 {
                    let controls = try (0..<count).map { try XCTUnwrap(frames.values["c\($0)"]) }
                    XCTAssertEqual(try XCTUnwrap(controls.last).maxX, width, accuracy: 0.5)
                    for control in controls { XCTAssertFalse(label.intersects(control)) }
                    for pair in zip(controls, controls.dropFirst()) { XCTAssertLessThan(pair.0.maxX, pair.1.minX) }
                }
            }
        }
    }

    func testSettingsControlKeepsStateAcrossLayoutPolicyChanges() throws {
        let probe = SettingsControlProbe()
        func root(ownsMeasure: Bool, width: CGFloat, scale: Double) -> some View {
            LumenSettingsRow("Sampling") { SettingsStatefulControl(probe: probe) }
                .environment(\.lumenSettingsPaneOwnsMeasure, ownsMeasure)
                .environment(\.lumenSettingsWidthClass, LumenSettingsWidthClass(width: width))
                .lumenMetrics(.resolving(nil, textScale: scale))
                .frame(width: width, height: 100)
        }
        let host = NSHostingView(rootView: root(ownsMeasure: false, width: 600, scale: 1))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        try XCTUnwrap(probe.increment, "Control did not attach to the offscreen host")()
        settle()
        XCTAssertEqual(probe.value, 1, "Control value before policy flip was \(String(describing: probe.value))")
        for (owns, width, scale) in [(true, 320.0, 1.3), (true, 600.0, 1.0), (false, 600.0, 1.0)] {
            host.rootView = root(ownsMeasure: owns, width: width, scale: scale)
            settle()
            XCTAssertEqual(probe.value, 1, "Control reset: owns=\(owns), width=\(width), scale=\(scale), value=\(String(describing: probe.value))")
            XCTAssertFalse(window.isVisible, "Offscreen row host became visible")
        }
    }

    func testSettingsRowHasFiniteMaximumProposal() {
        let host = NSHostingController(rootView: LumenSettingsRow("Request timeout") { Text("900,000 ms") })
        let size = host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        XCTAssertTrue(size.width.isFinite && size.height.isFinite, "Maximum proposal returned \(size)")
    }

    func testGroupedIntegerInputKeepsExactSevenDigitValue() {
        let raw = LumenNumberField.removingGrouping("9,999,999", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(LumenNumberField.normalized(raw, range: 0...9_999_999, step: 1), 9_999_999,
                       "Grouped input produced \(raw)")
        let german = LumenNumberField.removingGrouping("900.000", locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(german, "900000", "Locale grouping removal produced \(german)")
    }

    func testGroupedFieldReservesSevenDigitsAndScales() {
        func width(_ digits: Int, scale: Double) -> CGFloat {
            NSHostingView(rootView: LumenNumberField(value: .constant(1), in: 0...9, step: 1,
                unit: "ms", minimumDigits: digits, usesGrouping: true)
                .lumenMetrics(.resolving(nil, textScale: scale))
                .environment(\.lumenRendersOffscreen, true).fixedSize()).fittingSize.width
        }
        let short = width(1, scale: 1)
        let standard = width(7, scale: 1)
        let large = width(7, scale: 1.3)
        XCTAssertGreaterThan(standard, short, "Widths: short=\(short), seven=\(standard)")
        XCTAssertGreaterThan(large, standard, "Widths: standard=\(standard), scaled=\(large)")
    }

    func testEmptySectionHasVisibleHeightWithoutLazyContent() {
        let host = NSHostingController(rootView: LumenSettingsEmptyRow("No models discovered",
            detail: "Start a service, then refresh.").lumenMetrics(.standard))
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 600))
        XCTAssertGreaterThan(size.height, 20, "Empty row measured \(size)")
        XCTAssertLessThanOrEqual(size.width, 320, "Empty row measured \(size)")
    }

}

@MainActor
private final class SettingsControlProbe {
    var value: Int?
    var increment: (() -> Void)?
}

private struct SettingsStatefulControl: View {
    let probe: SettingsControlProbe
    @State private var count = 0
    var body: some View {
        Text("Value \(count)").background(SettingsControlBridge(count: $count, probe: probe))
    }
}

private struct SettingsControlBridge: NSViewRepresentable {
    @Binding var count: Int
    let probe: SettingsControlProbe
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        probe.value = count
        probe.increment = { count += 1 }
    }
}

@MainActor private final class SettingsFrames {
    var values: [String: CGRect] = [:]
}

private struct SettingsFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct SettingsFrameReader: View {
    let id: String
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SettingsFramesKey.self,
                value: [id: geometry.frame(in: .named("row"))])
        }
    }
}
