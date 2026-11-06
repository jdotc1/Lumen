import AppKit
import SwiftUI
import Synchronization
import XCTest
@testable import LumenUI

@MainActor
final class LumenWindowRootSizingTests: XCTestCase {
    private final class Measurement: Sendable {
        private let storage = Mutex<[CGSize]>([])
        var sizes: [CGSize] {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }

    /// Query LayoutSubview directly so nil proposals are not replaced by a CGSize bridge.
    private struct ProposalProbe: Layout {
        let measurement: Measurement
        let proposals: [ProposedViewSize]

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            measurement.sizes = proposals.map { subviews[0].sizeThatFits($0) }
            return CGSize(width: 1000, height: 800)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    func testOffWindowRootPreservesScaffoldResponsesForEveryProposal() throws {
        let body = AnyView(VStack(alignment: .leading) {
            Text("Fixture content")
            Button("Open Fixture") {}
            Spacer(minLength: 0)
        })
        let minimum = CGSize(width: 640, height: 400)
        let subjects: [(String, AnyView)] = [
            ("bare stack", body),
            ("document", AnyView(LumenDocumentWindow(title: .constant("Document"), isModified: false,
                                                     minimumSize: minimum) { body })),
            ("utility", AnyView(LumenUtilityWindow(minimumSize: minimum) { body } topLeading: { Text("Utility") })),
            ("workspace", AnyView(LumenWorkspaceWindow(panels: .constant(.init(leading: false, bottom: false, trailing: false))) {
                body
            } topLeading: { Text("Workspace") })),
            ("library", AnyView(LumenLibraryWindow(minimumSize: minimum) { body } topLeading: { Text("Library") })),
            ("wizard", AnyView(LumenWizardWindow(pages: [.init(id: "one", title: "Page")], current: .constant(0),
                                                onCancel: {}, onFinish: {}) { _ in body })),
            ("menu bar panel", AnyView(LumenMenuBarPanel("Panel", width: 360, maximumHeight: 480, showsFooter: false) {
                body.frame(minHeight: 200)
            })),
            ("Settings", AnyView(LumenSettingsSidebarView([
                LumenSettingsCategory(id: "general", title: "General", systemImage: "gear", hue: .hueBlue) { body },
                LumenSettingsCategory(id: "other", title: "Other", systemImage: "gear", hue: .hueTeal) { body },
            ]))),
        ]
        let proposals: [ProposedViewSize] = [.zero, .unspecified, .infinity, .init(width: 1000, height: 800)]
        for (name, subject) in subjects {
            let plain = measure(subject, proposals: proposals)
            let rooted = measure(AnyView(subject.lumenPaletteRoot()), proposals: proposals)
            XCTAssertEqual(plain.count, proposals.count, name)
            XCTAssertEqual(rooted.count, proposals.count, name)
            for index in proposals.indices {
                let expected = try XCTUnwrap(plain.indices.contains(index) ? plain[index] : nil)
                let actual = try XCTUnwrap(rooted.indices.contains(index) ? rooted[index] : nil)
                XCTAssertEqual(actual, expected, "\(name), proposal=\(proposals[index])")
                print("ROOT SIZING: \(name), proposal=\(proposals[index]), plain=\(expected), root=\(actual)")
            }
        }
    }

    private func measure(_ content: AnyView, proposals: [ProposedViewSize]) -> [CGSize] {
        let result = Measurement()
        let host = NSHostingView(rootView: ProposalProbe(measurement: result, proposals: proposals) {
            content.lumenMetrics(.standard)
        })
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        host.layoutSubtreeIfNeeded()
        XCTAssertNil(host.window, "Sizing contract is measured without any window")
        return result.sizes
    }
}
