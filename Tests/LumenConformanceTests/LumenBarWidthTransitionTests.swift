import AppKit
import LumenTestSupport
@_spi(LayoutAudit) @testable import LumenUI
import SwiftUI
import XCTest

/// Plain SwiftUI fixture: components are integrated and checked by the window matrix later.
struct LumenBarAuditFixture: View {
    let bar: String
    var labels = ["Export results", "Refresh", "Details"]
    @Environment(\.lumenTextScale) private var scale
    var body: some View {
        HStack(spacing: 12) {
            ForEach(labels, id: \.self) { label in
                ViewThatFits(in: .horizontal) {
                    Text(label).font(.system(size: 13 * scale)).fixedSize()
                        .lumenBarItem(label, bar: bar, role: .label)
                    Image(systemName: "ellipsis")
                        .lumenBarItem(label, bar: bar, role: .label, mode: .iconOnly)
                        .help(label).accessibilityLabel(label)
                }.layoutPriority(1)
            }
            Text("/Projects/An exceptionally long folder/Results.txt")
                .font(.system(size: 13 * scale)).lineLimit(1)
                .lumenBarItem("/Projects/An exceptionally long folder/Results.txt", bar: bar, role: .freeText)
                .truncationMode(.middle).frame(minWidth: 0, maxWidth: .infinity)
            let cap = NSFont.systemFont(ofSize: 13 * scale).capHeight + 1
            Text("12").font(.system(size: 13 * scale)).fixedSize()
                .lumenBarItem("12", bar: bar, role: .pill, pillInsets: CGSize(width: cap, height: 2))
                .padding(.horizontal, cap).padding(.vertical, 2)
                .background(Capsule().fill(.gray.opacity(0.15))).layoutPriority(2)
        }.padding(16)
    }
}

@MainActor
final class LumenBarWidthTransitionTests: XCTestCase {
    private final class Reports {
        var items: [LumenBarItemReport] = []
    }

    func testBarWidthTransitionSweep() throws {
        _ = NSApplication.shared
        let reports = Reports()
        let host = NSHostingView(rootView: LumenBarAuditFixture(bar: "sweep")
            .environment(\.lumenReportsLayoutChecks, true)
            .onPreferenceChange(LumenBarItemKey.self) { reports.items = $0 })
        host.sizingOptions = []
        var transitions: [String] = []
        var previous: [LumenBarItemReport.Mode] = []
        for width in stride(from: 160, through: 1200, by: 16) {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 80)
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertFalse(reports.items.isEmpty, "Missing reports at \(width)")
            let findings = LumenLayoutAudit.barItemFindings(reports.items)
            XCTAssertEqual(findings, [], "width=\(width): \(findings)")
            let modes = reports.items.map(\.mode)
            if modes != previous { transitions.append("width=\(width): \(modes)"); previous = modes }
        }
        XCTAssertTrue(transitions.count > 1, "The sweep must cross an icon-only fallback")
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/test-artifacts/bar-detection")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try transitions.joined(separator: "\n").write(to: directory.appending(path: "width-transitions.txt"), atomically: true, encoding: .utf8)
    }
}
