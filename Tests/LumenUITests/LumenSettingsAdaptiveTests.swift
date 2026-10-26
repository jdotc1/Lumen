import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSettingsAdaptiveTests: XCTestCase {
    @Observable final class SelectionModel {
        var category: String? = "short"
    }

    func testIdealHeightFollowsTallestPaneIndependentOfCategoryOrder() {
        let first = LumenSettingsSizing.idealSize(heights: [510, 635, 570], preferred: nil, visibleHeight: 1200)
        let reordered = LumenSettingsSizing.idealSize(heights: [635, 570, 510], preferred: nil, visibleHeight: 1200)
        XCTAssertEqual(first, CGSize(width: 820, height: 635))
        XCTAssertEqual(first, reordered, "Category selection must not choose the window's height")
    }

    func testIdealHeightHonorsFloorScreenCapAndMissingScreenFallback() {
        XCTAssertEqual(LumenSettingsSizing.idealSize(heights: [200], preferred: nil, visibleHeight: 1000).height, 480)
        XCTAssertEqual(LumenSettingsSizing.idealSize(heights: [], preferred: nil, visibleHeight: nil).height, 480)
        XCTAssertEqual(LumenSettingsSizing.idealSize(heights: [1500], preferred: nil, visibleHeight: nil).height, 720)
        let capped = LumenSettingsSizing.idealSize(heights: [1500], preferred: nil, visibleHeight: 900, toolbarHeight: 40)
        XCTAssertEqual(capped.height, 900 - LumenSettingsSizing.screenMargin - 40)
    }

    func testHostPreferredSizeOverridesMeasuredContentWithinWindowBounds() {
        let preferred = CGSize(width: 1000, height: 640)
        XCTAssertEqual(LumenSettingsSizing.idealSize(heights: [1100], preferred: preferred, visibleHeight: 1200), preferred)
        XCTAssertEqual(LumenSettingsSizing.idealSize(heights: [500], preferred: preferred, visibleHeight: 1200), preferred)
        let minimum = LumenSettingsSizing.idealSize(heights: [600], preferred: CGSize(width: 100, height: 100), visibleHeight: 1200)
        XCTAssertEqual(minimum, CGSize(width: 680, height: 480))
    }

    func testPaneWidthClassBoundaries() {
        XCTAssertEqual(LumenSettingsWidthClass(width: 559), .compact)
        XCTAssertEqual(LumenSettingsWidthClass(width: 560), .regular)
        XCTAssertEqual(LumenSettingsWidthClass(width: 820), .regular)
        XCTAssertEqual(LumenSettingsWidthClass(width: 821), .wide)
    }

    func testNativeWindowOpensToTallestPaneAndCategoryChangesKeepItsSize() throws {
        let selection = SelectionModel()
        var measured: [String: CGFloat] = [:]
        let root = LumenSettingsSidebarView(Self.nativeCategories,
            selection: Binding(get: { selection.category }, set: { selection.category = $0 }))
            .lumenMetrics(.standard)
            .onPreferenceChange(LumenSettingsNaturalHeightKey.self) { measured = $0 }
        let host = NSHostingView(rootView: root)
        let window = makeSettingsWindow(host: host)
        defer { window.close() }
        settle(host, window: window, iterations: 40)
        XCTAssertEqual(Set(measured.keys), Set(["short", "tall"]))
        XCTAssertGreaterThan(try XCTUnwrap(measured["tall"]), 530,
                             "The initially hidden category contributes its header and natural content")
        let band = window.frame.height - window.contentLayoutRect.height
        let expected = LumenSettingsSizing.idealSize(heights: Array(measured.values), preferred: nil,
                                                    visibleHeight: window.screen?.visibleFrame.height, toolbarHeight: band)
        XCTAssertEqual(window.contentLayoutRect.width, expected.width, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, expected.height, accuracy: 1)
        XCTAssertGreaterThan(window.contentLayoutRect.height, 480)
        let openingSize = window.frame.size
        selection.category = "tall"
        settle(host, window: window, iterations: 40)
        XCTAssertEqual(window.frame.size, openingSize, "Selecting the tallest pane must not jump the window")
        var grown = window.frame
        grown.size.width += 160
        grown.size.height += 80
        window.setFrame(grown, display: false)
        selection.category = "short"
        settle(host, window: window, iterations: 40)
        XCTAssertEqual(window.frame.size, grown.size, "Navigation must also preserve the user's larger window")
    }

    func testNativeWindowAppliesHostPreferredOpeningSize() {
        let preferred = CGSize(width: 1000, height: 640)
        let root = LumenSettingsSidebarView(Self.nativeCategories)
            .lumenSettingsPreferredSize(preferred)
            .lumenMetrics(.standard)
        let host = NSHostingView(rootView: root)
        let window = makeSettingsWindow(host: host)
        defer { window.close() }
        settle(host, window: window, iterations: 40)
        XCTAssertEqual(window.contentLayoutRect.width, preferred.width, accuracy: 1)
        XCTAssertEqual(window.contentLayoutRect.height, preferred.height, accuracy: 1)
    }

    func testGroupedPaneMeasuresItsScrollDocumentBeyondViewport() throws {
        var measured: [String: CGFloat] = [:]
        let root = LumenSettingsPane("Grouped sample", systemImage: "gear", hue: .hueBlue) {
            ForEach(0..<24, id: \.self) { index in
                Toggle("Sample option \(index + 1)", isOn: .constant(true))
            }
        }
        .environment(\.lumenSettingsMeasurementID, "grouped")
        .onPreferenceChange(LumenSettingsNaturalHeightKey.self) { measured = $0 }
        .lumenMetrics(.standard)
        .frame(width: 600, height: 320)
        let host = NSHostingView(rootView: root)
        let window = makeWindow(host: host, size: CGSize(width: 600, height: 320))
        defer { window.close() }
        settle(host, window: window, iterations: 40)
        let natural = try XCTUnwrap(measured["grouped"])
        XCTAssertGreaterThan(natural, 480, "A native grouped form must report its document, not its viewport")
        let scroll = try XCTUnwrap(findScrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
        XCTAssertGreaterThanOrEqual(natural, document.bounds.height - 1)
    }

    func testSettingsRowsKeepTrailingControlsBesideLabelsWhenTheyFit() throws {
        let compact = try rowGeometry(width: 550, density: .regular)
        let regular = try rowGeometry(width: 600, density: .regular)
        XCTAssertEqual(compact.control.midY, compact.row.midY, accuracy: 1,
                       "At ordinary Settings width a fitting control stays beside its label")
        XCTAssertEqual(regular.control.midY, regular.row.midY, accuracy: 1,
                       "At regular pane width the trailing control remains vertically centered")
        XCTAssertEqual(compact.row.height, regular.row.height, accuracy: 1)
    }

    func testSettingsRowsRetainThreeDistinctDensityRhythms() throws {
        let compact = try rowGeometry(width: 600, density: .compact)
        let regular = try rowGeometry(width: 600, density: .regular)
        let comfortable = try rowGeometry(width: 600, density: .comfortable)
        XCTAssertLessThan(compact.row.height, regular.row.height)
        XCTAssertLessThan(regular.row.height, comfortable.row.height)
    }

    func testNaturalPaneMeasurementIncludesHeaderAndBottomInsetBeyondViewport() throws {
        var natural: [String: CGFloat] = [:]
        var paneFrame = CGRect.zero
        var lastFrame = CGRect.zero
        let root = LumenSettingsPane("Tall sample", systemImage: "gear", hue: .hueBlue, style: .rich) {
            Color.clear.frame(height: 700)
            Color.blue.frame(height: 24)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { lastFrame = $0 }
        }
        .environment(\.lumenSettingsMeasurementID, "tall")
        .onPreferenceChange(LumenSettingsNaturalHeightKey.self) { natural = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { paneFrame = $0 }
        .lumenMetrics(.standard)
        .frame(width: 600, height: 320)
        let host = NSHostingView(rootView: root)
        let window = makeWindow(host: host, size: CGSize(width: 600, height: 320))
        defer { window.close() }
        settle(host, window: window)
        let measured = try XCTUnwrap(natural["tall"])
        XCTAssertGreaterThan(measured, 724, "Natural height includes header, sections and insets, not just viewport height")
        XCTAssertGreaterThanOrEqual(measured - (lastFrame.maxY - paneFrame.minY), LumenMetrics.standard.spacing.s8 - 1)
        let scroll = try XCTUnwrap(findScrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
        let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
        scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(host, window: window)
        XCTAssertGreaterThan(lastFrame.height, 0)
        XCTAssertLessThanOrEqual(lastFrame.maxY, paneFrame.maxY - LumenMetrics.standard.spacing.s8 + 1,
                                 "The final item must remain above the real bottom inset when scrolled to the end")
    }

    private func rowGeometry(width: CGFloat, density: LumenDensity) throws -> (row: CGRect, control: CGRect) {
        var row = CGRect.zero
        var control = CGRect.zero
        let root = LumenSettingsPane("Sample", systemImage: "gear", hue: .hueBlue, style: .rich) {
            LumenSettingsRow("Runtime") {
                Color.blue.frame(width: 80, height: 24)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { control = $0 }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { row = $0 }
        }
        .environment(\.lumenDensity, density)
        .lumenMetrics(.standard)
        .frame(width: width, height: 320)
        let host = NSHostingView(rootView: root)
        let window = makeWindow(host: host, size: CGSize(width: width, height: 320))
        defer { window.close() }
        settle(host, window: window)
        XCTAssertGreaterThan(row.width, 0)
        XCTAssertEqual(control.size, CGSize(width: 80, height: 24))
        return (row, control)
    }

    private func makeWindow<Content: View>(host: NSHostingView<Content>, size: CGSize) -> NSWindow {
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        return window
    }

    private static var nativeCategories: [LumenSettingsCategory] {
        [
            LumenSettingsCategory(id: "short", title: "Short", systemImage: "gear", hue: .hueBlue) {
                LumenSettingsPane("Short", systemImage: "gear", hue: .hueBlue, style: .rich) {
                    Color.clear.frame(height: 80)
                }
            },
            LumenSettingsCategory(id: "tall", title: "Tall", systemImage: "gear", hue: .hueBlue) {
                LumenSettingsPane("Tall", systemImage: "gear", hue: .hueBlue, style: .rich) {
                    Color.clear.frame(height: 530)
                }
            }
        ]
    }

    private func makeSettingsWindow<Content: View>(host: NSHostingView<Content>) -> NSWindow {
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: -10000, y: -10000, width: 820, height: 480),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unifiedCompact
        window.contentView = host
        LumenHeadlessHost.order(window)
        return window
    }

    private func settle(_ host: NSView, window: NSWindow, iterations: Int = 12) {
        for _ in 0..<iterations {
            host.layoutSubtreeIfNeeded()
            window.update()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
