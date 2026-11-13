import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@testable import LumenUI

@MainActor
final class LumenBarLabelGuaranteeTests: XCTestCase {
    private final class Reports {
        var truncated: Set<String> = []
    }

    private final class Marker: NSView {
        var probeID = ""
    }

    private struct Probe: NSViewRepresentable {
        let id: String
        func makeNSView(context: Context) -> Marker {
            let view = Marker()
            view.probeID = id
            return view
        }
        func updateNSView(_ view: Marker, context: Context) { view.probeID = id }
    }

    private struct IdealStatValue: View {
        let value: String
        @Environment(\.lumenMetrics) private var metrics
        var body: some View {
            Text(value).font(metrics.typography.stat).lineLimit(1).fixedSize()
                .background(Probe(id: "ideal"))
        }
    }

    private func hosted<V: View>(_ view: V, width: CGFloat,
                                 inspect: (NSHostingView<AnyView>) throws -> Void) rethrows {
        let host = NSHostingView(rootView: AnyView(view
            .environment(\.lumenRendersOffscreen, true)
            .environment(\.lumenReportsLayoutChecks, true)
            .frame(width: width, alignment: .leading)))
        host.sizingOptions = []
        let size = CGSize(width: width, height: 240)
        let window = LumenHeadlessHost.window(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        try inspect(host)
    }

    private func frames(in host: NSView, id: String) -> [CGRect] {
        func collect(_ view: NSView) -> [CGRect] {
            var result: [CGRect] = []
            if let marker = view as? Marker, marker.probeID == id,
               !marker.isHiddenOrHasHiddenAncestor, marker.bounds.width > 0.5 {
                result.append(marker.convert(marker.bounds, to: host))
            }
            return result + view.subviews.flatMap(collect)
        }
        return collect(host)
    }

    func testSourcesNeverScaleLabelsDown() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Sources/LumenUI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
        var checked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            checked += 1
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("minimumScaleFactor"), file.lastPathComponent)
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testStatRetainsIdealValueSizeAtTextScaleOnePointThree() throws {
        let value = "987654"
        var ideal = CGRect.zero
        try hosted(IdealStatValue(value: value).lumenTextScale(1.3), width: 400) { host in
            ideal = try XCTUnwrap(frames(in: host, id: "ideal").first)
        }
        let reports = Reports()
        let stat = LumenStatCell(LumenStat("A long localized statistic label", value: value))
            .background(Probe(id: "stat"))
            .onPreferenceChange(LumenTruncationKey.self) { reports.truncated = $0 }
            .lumenTextScale(1.3)
        try hosted(stat, width: max(40, ideal.width - 20)) { host in
            let actual = try XCTUnwrap(frames(in: host, id: "stat").first)
            XCTAssertGreaterThanOrEqual(actual.width + 0.5, ideal.width, "The value retains its ideal font width even when its label drops")
            XCTAssertGreaterThanOrEqual(actual.height + 0.5, ideal.height)
            XCTAssertFalse(reports.truncated.contains(value))
        }
    }

    private var statusItems: some View {
        ForEach(["Index complete", "All changes saved", "Connection available"], id: \.self) { title in
            Text(title).lumenNeverTruncates(title).background(Probe(id: title))
        }
    }

    func testStatusItemsKeepIdealWidthsInLastResortScroll() throws {
        let titles = ["Index complete", "All changes saved", "Connection available"]
        var ideals: [String: CGFloat] = [:]
        try hosted(LumenStatusBar { statusItems }.lumenTextScale(1.3), width: 800) { host in
            for title in titles { ideals[title] = try XCTUnwrap(frames(in: host, id: title).first).width }
        }
        let reports = Reports()
        // Smaller than the overflow trigger plus the capsule insets: exercises the last scroll tier.
        try hosted(LumenStatusBar { statusItems }
            .onPreferenceChange(LumenTruncationKey.self) { reports.truncated = $0 }
            .lumenTextScale(1.3), width: 40) { host in
            for title in titles {
                let actual = try XCTUnwrap(frames(in: host, id: title).first)
                XCTAssertEqual(actual.width, try XCTUnwrap(ideals[title]), accuracy: 0.5)
            }
            XCTAssertTrue(reports.truncated.isEmpty)
            let last = try XCTUnwrap(frames(in: host, id: titles[2]).first)
            XCTAssertGreaterThan(last.maxX, host.bounds.maxX, "Items occupy a natural-width scroll track")
        }
    }

    func testStatusOverflowPrecedesScrolling() {
        hosted(LumenStatusBar { statusItems }.lumenTextScale(1.3), width: 100) { host in
            XCTAssertTrue(frames(in: host, id: "Index complete").isEmpty, "Long labels move into the overflow menu")
            XCTAssertLessThanOrEqual(host.fittingSize.width, 100.5)
        }
    }

    func testCountKeepsNaturalWidthBesideLongTitle() throws {
        var ideal: CGFloat = 0
        try hosted(LumenCount(123456).background(Probe(id: "count")).lumenTextScale(1.3), width: 400) { host in
            ideal = try XCTUnwrap(frames(in: host, id: "count").first).width
        }
        try hosted(HStack(spacing: 4) {
            Text("A very long sidebar section title").lineLimit(1).truncationMode(.middle)
                .layoutPriority(1).background(Probe(id: "title"))
            LumenCount(123456).background(Probe(id: "count"))
        }.lumenTextScale(1.3), width: 140) { host in
            let count = try XCTUnwrap(frames(in: host, id: "count").first)
            XCTAssertEqual(count.width, ideal, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(count.minX, -0.5)
            XCTAssertLessThanOrEqual(count.maxX, host.bounds.maxX + 0.5)
            let title = try XCTUnwrap(frames(in: host, id: "title").first)
            XCTAssertLessThanOrEqual(title.maxX, count.minX)
        }
    }

    func testPopupWidthIsAMinimum() {
        let title = "A longer localized menu choice"
        let requested = NSHostingView(rootView: LumenPopUpLabel(title, width: 20).fixedSize())
        let natural = NSHostingView(rootView: LumenPopUpLabel(title).fixedSize())
        XCTAssertGreaterThan(requested.fittingSize.width, 20)
        XCTAssertEqual(requested.fittingSize.width, natural.fittingSize.width, accuracy: 0.5)
    }

    func testTinyActivityWidthUsesMarkOnly() {
        let activity = LumenActivity.working("Processing a long document name", progress: 1)
        let compact = NSHostingView(rootView: LumenActivityStatus(activity, idealWidth: 20, minWidth: 0).fixedSize())
        let mark = NSHostingView(rootView: LumenActivityStatus(activity).markOnly.fixedSize())
        XCTAssertGreaterThan(compact.fittingSize.width, 0)
        XCTAssertEqual(compact.fittingSize.width, mark.fittingSize.width, accuracy: 0.5)
    }

    func testToolbarIdentityCapsFreeTextInsideFixedGroup() {
        let host = NSHostingView(rootView: LumenToolbarIdentity(String(repeating: "Long document title ", count: 12),
                                                               subtitle: "/a/long/location", systemImage: "doc")
            .environment(\.lumenToolbarCompact, true).lumenTextScale(1.3).fixedSize())
        XCTAssertLessThan(host.fittingSize.width, 400)
        XCTAssertGreaterThan(host.fittingSize.width, 200)
    }
}
