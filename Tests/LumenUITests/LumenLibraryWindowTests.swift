import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import Observation
import LumenConformance
@testable import LumenUI

@MainActor
final class LumenLibraryWindowTests: XCTestCase {
    private func visible(_ width: CGFloat, preferences: LumenLibraryPreferences = .init(),
                         bound: LumenLibraryPanels? = nil) -> LumenLibraryPanels {
        LumenLibraryLayout.visiblePanels(requested: bound ?? preferences.requested,
            explicit: bound == nil ? preferences.explicit : .init(), width: width,
            contentMinimum: 640, sourceListMinimum: 200, detailMinimum: 240)
    }

    func testAutomaticCollapseAndReverseRestorationAtExactBoundaries() {
        let widths: [CGFloat] = [1440, 1082, 1081, 841, 840, 640, 840, 841, 1081, 1082, 1440]
        let all = LumenLibraryPanels()
        let sourceList = LumenLibraryPanels(sourceList: true, detail: false)
        let none = LumenLibraryPanels(sourceList: false, detail: false)
        XCTAssertEqual(widths.map { visible($0) },
                       [all, all, sourceList, sourceList, none, none, none, sourceList, sourceList, all, all])
    }

    func testExplicitlyShownDetailYieldsAfterAutomaticSourceList() {
        var preference = LumenLibraryPreferences()
        preference.set(true, for: \.detail)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sourceList: false, detail: true))
        XCTAssertEqual(visible(881, preferences: preference), .init(sourceList: false, detail: true))
        XCTAssertEqual(visible(880, preferences: preference), .init(sourceList: false, detail: false))
        XCTAssertEqual(visible(1440, preferences: preference), .init())
    }

    func testExplicitlyShownSourceListAndEqualPrioritiesKeepDetailFirstOrder() {
        var preference = LumenLibraryPreferences()
        preference.set(true, for: \.sourceList)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sourceList: true, detail: false))
        preference.set(true, for: \.detail)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sourceList: true, detail: false))
        XCTAssertEqual(visible(640, preferences: preference), .init(sourceList: false, detail: false))
    }

    func testExplicitlyHiddenRegionsNeverAutoRestore() {
        var preference = LumenLibraryPreferences()
        preference.set(false, for: \.sourceList)
        for width: CGFloat in [640, 1440, 900, 1440] {
            XCTAssertFalse(visible(width, preferences: preference).sourceList)
        }
        preference.set(false, for: \.detail)
        XCTAssertEqual(visible(1440, preferences: preference), .init(sourceList: false, detail: false))
        preference.set(true, for: \.sourceList)
        XCTAssertEqual(visible(1440, preferences: preference), .init(sourceList: true, detail: false))
    }

    func testBoundStateIsExplicitAndSurvivesAutomaticCollapse() {
        for panels in LumenLibraryPanels.allCombinations {
            XCTAssertEqual(visible(640, bound: panels), .init(sourceList: false, detail: false))
            XCTAssertEqual(visible(1440, bound: panels), panels)
        }
        XCTAssertEqual(visible(1081, bound: .init()), .init(sourceList: true, detail: false))
    }

    func testMissingRegionsConsumeNoWidth() {
        XCTAssertEqual(LumenLibraryLayout.visiblePanels(requested: .init(), explicit: .init(),
            width: 881, contentMinimum: 640, sourceListMinimum: nil, detailMinimum: 240),
            .init(sourceList: false, detail: true))
        XCTAssertEqual(LumenLibraryLayout.visiblePanels(requested: .init(), explicit: .init(),
            width: 841, contentMinimum: 640, sourceListMinimum: 200, detailMinimum: nil),
            .init(sourceList: true, detail: false))
        XCTAssertEqual(LumenLibraryLayout.visiblePanels(requested: .init(), explicit: .init(),
            width: 640, contentMinimum: 640, sourceListMinimum: nil, detailMinimum: nil),
            .init(sourceList: false, detail: false))
    }

    func testAutoLayoutWindowResizesAndRestoresWithoutWritingItsBinding() {
        let model = LibraryBindingModel()
        var writes = 0
        var contentFrame: CGRect = .zero
        var sourceTokens: Set<UUID> = []
        var detailTokens: Set<UUID> = []
        var sourceListWidth: CGFloat = 0
        var detailWidth: CGFloat = 0
        let root = LumenLibraryWindow(panels: Binding(get: { model.panels }, set: { model.panels = $0; writes += 1 })) {
            Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
        } sourceList: {
            LibraryStatefulRegion { frame, token in
                sourceListWidth = frame.width
                sourceTokens.insert(token)
            }
        } detail: {
            LibraryStatefulRegion { frame, token in
                detailWidth = frame.width
                detailTokens.insert(token)
            }
        } topLeading: { Text("Library") }
        .columnWidths(sourceList: (200, 220, 300), detail: (240, 280, 360))
        .lumenPaletteRoot()
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 1100, height: 720))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.contentMinSize = CGSize(width: 640, height: 400)
        defer { window.close() }
        func settle(_ width: CGFloat) {
            window.setContentSize(CGSize(width: width, height: width == 640 ? 400 : 720))
            for _ in 0..<12 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        for width: CGFloat in [1100, 1000, 640, 1000, 1100] {
            settle(width)
            XCTAssertEqual(host.frame.width, container.bounds.width, accuracy: 0.5)
            XCTAssertEqual(host.frame.height, container.bounds.height, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(contentFrame.width, 639.5, "width=\(width)")
            XCTAssertGreaterThanOrEqual(contentFrame.minX, -0.5, "width=\(width)")
            XCTAssertLessThanOrEqual(contentFrame.maxX, width + 0.5, "width=\(width)")
            XCTAssertEqual(sourceListWidth > 1, width >= 1000, "width=\(width)")
            XCTAssertEqual(detailWidth > 1, width >= 1100, "width=\(width)")
        }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(model.panels, .init())
        XCTAssertEqual(sourceTokens.count, 1, "Automatic collapse must preserve source-list state")
        XCTAssertEqual(detailTokens.count, 1, "Automatic collapse must preserve detail state")
        model.panels.detail = false
        settle(1100)
        XCTAssertLessThanOrEqual(detailWidth, 1)
        settle(640)
        settle(1100)
        XCTAssertFalse(model.panels.detail)
        XCTAssertLessThanOrEqual(detailWidth, 1)
        model.panels.detail = true
        settle(1100)
        XCTAssertGreaterThan(detailWidth, 1)
        XCTAssertEqual(sourceTokens.count, 1)
        XCTAssertEqual(detailTokens.count, 1)
        XCTAssertEqual(writes, 0)
    }

    func testSceneSizingAdvertisesOnlyTheContentMinimum() {
        let root = LumenLibraryWindow { Color.clear } sourceList: { Text("Sources") }
            detail: { Text("Metadata") } topLeading: { Text("Library") }
        let host = NSHostingController(rootView: root)
        XCTAssertEqual(host.sizeThatFits(in: .zero), CGSize(width: 640, height: 400))
    }

    func testContentMinimumOverrideDoesNotReserveHiddenSidePanes() {
        let root = LumenLibraryWindow(minimumSize: CGSize(width: 640, height: 420)) {
            Color.clear
        } sourceList: {
            Text("Collections")
        } detail: {
            Text("Metadata")
        } topLeading: {
            Text("Library")
        }
        .contentMinimumWidth(720)
        let host = NSHostingController(rootView: root)
        XCTAssertEqual(host.sizeThatFits(in: .zero), CGSize(width: 720, height: 420))
    }

    func testEveryRequestedPanelCombinationKeepsTheUnifiedBar() {
        for panels in LumenLibraryPanels.allCombinations {
            let findings = LumenConformance.windowStructure(kind: .library,
                sizes: [CGSize(width: 640, height: 400), CGSize(width: 1440, height: 900)]) {
                LumenLibraryWindow(panels: .constant(panels)) {
                    Text("Library items")
                } sourceList: {
                    Text("Sources")
                } detail: {
                    Text("Metadata")
                } filterChips: {
                    Text("All items")
                } statusBar: {
                    Text("Ready")
                } topLeading: {
                    Text("Library")
                }
            }
            XCTAssertEqual(findings.map(\.description), [], "\(panels)")
        }
    }

    func testOptionalRegionsCanAllBeOmitted() {
        let findings = LumenConformance.windowStructure(kind: .library,
            sizes: [CGSize(width: 640, height: 400)]) {
            LumenLibraryWindow(panels: .constant(.init())) {
                Text("Items")
            } topLeading: {
                Text("Library")
            }
        }
        XCTAssertEqual(findings.map(\.description), [])
    }

    func testLibraryDoesNotInheritTheLegacyTopBarPlacement() {
        let findings = LumenConformance.windowStructure(kind: .library,
            sizes: [CGSize(width: 640, height: 400)]) {
            LumenLibraryWindow(panels: .constant(.init())) {
                Text("Items")
            } topLeading: {
                Text("Library")
            }
            .lumenTopBarPlacement(.underTitleBar)
        }
        XCTAssertEqual(findings.map(\.description), [])
    }
}

@MainActor @Observable
private final class LibraryBindingModel {
    var panels = LumenLibraryPanels()
}

private struct LibraryStatefulRegion: View {
    @State private var token = UUID()
    let report: (CGRect, UUID) -> Void

    var body: some View {
        Color.blue.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report($0, token) }
    }
}
