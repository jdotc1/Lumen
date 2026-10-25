import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import Observation
import LumenConformance
@testable import LumenUI

@MainActor
final class LumenUtilityWindowTests: XCTestCase {
    private func visible(_ width: CGFloat, preferences: LumenUtilityPreferences = .init(),
                         bound: LumenUtilityPanels? = nil) -> LumenUtilityPanels {
        LumenUtilityLayout.visiblePanels(requested: bound ?? preferences.requested,
            explicit: bound == nil ? preferences.explicit : .init(), width: width,
            contentMinimum: 640, sidebarMinimum: 200, inspectorMinimum: 240)
    }

    func testAutomaticCollapseAndReverseRestorationAtExactBoundaries() {
        let widths: [CGFloat] = [1440, 1082, 1081, 841, 840, 640, 840, 841, 1081, 1082, 1440]
        let all = LumenUtilityPanels()
        let sidebar = LumenUtilityPanels(sidebar: true, inspector: false)
        let none = LumenUtilityPanels(sidebar: false, inspector: false)
        XCTAssertEqual(widths.map { visible($0) },
                       [all, all, sidebar, sidebar, none, none, none, sidebar, sidebar, all, all])
    }

    func testExplicitlyShownInspectorYieldsAfterAutomaticSidebar() {
        var preference = LumenUtilityPreferences()
        preference.set(true, for: \.inspector)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sidebar: false, inspector: true))
        XCTAssertEqual(visible(881, preferences: preference), .init(sidebar: false, inspector: true))
        XCTAssertEqual(visible(880, preferences: preference), .init(sidebar: false, inspector: false))
        XCTAssertEqual(visible(1440, preferences: preference), .init())
    }

    func testExplicitlyShownSidebarAndEqualPrioritiesKeepInspectorFirstOrder() {
        var preference = LumenUtilityPreferences()
        preference.set(true, for: \.sidebar)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sidebar: true, inspector: false))
        preference.set(true, for: \.inspector)
        XCTAssertEqual(visible(1081, preferences: preference), .init(sidebar: true, inspector: false))
        XCTAssertEqual(visible(640, preferences: preference), .init(sidebar: false, inspector: false))
    }

    func testExplicitlyHiddenRegionsNeverAutoRestore() {
        var preference = LumenUtilityPreferences()
        preference.set(false, for: \.sidebar)
        for width: CGFloat in [640, 1440, 900, 1440] {
            XCTAssertFalse(visible(width, preferences: preference).sidebar)
        }
        preference.set(false, for: \.inspector)
        XCTAssertEqual(visible(1440, preferences: preference), .init(sidebar: false, inspector: false))
        preference.set(true, for: \.sidebar)
        XCTAssertEqual(visible(1440, preferences: preference), .init(sidebar: true, inspector: false))
    }

    func testBoundStateIsExplicitAndSurvivesAutomaticCollapse() {
        for panels in LumenUtilityPanels.allCombinations {
            XCTAssertEqual(visible(640, bound: panels), .init(sidebar: false, inspector: false))
            XCTAssertEqual(visible(1440, bound: panels), panels)
        }
        XCTAssertEqual(visible(1081, bound: .init()), .init(sidebar: true, inspector: false))
    }

    func testMissingRegionsConsumeNoWidth() {
        XCTAssertEqual(LumenUtilityLayout.visiblePanels(requested: .init(), explicit: .init(),
            width: 881, contentMinimum: 640, sidebarMinimum: nil, inspectorMinimum: 240),
            .init(sidebar: false, inspector: true))
    }

    func testRealWindowResizesAndRestoresWithoutWritingItsBinding() {
        let model = UtilityBindingModel()
        var writes = 0
        var contentFrame: CGRect = .zero
        var regionTokens: Set<UUID> = []
        var sidebarWidth: CGFloat = 0
        var inspectorWidth: CGFloat = 0
        let root = LumenUtilityWindow(panels: Binding(get: { model.panels }, set: { model.panels = $0; writes += 1 })) {
            Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
        } sidebar: {
            Color.red.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sidebarWidth = $0 }
                .onDisappear { sidebarWidth = 0 }
        } inspector: {
            UtilityStatefulRegion { frame, token in
                inspectorWidth = frame.width
                regionTokens.insert(token)
            }
        } topLeading: { Text("Utility") }
        .columnWidths(sidebar: (200, 220, 300), inspector: (240, 280, 360))
        .lumenPaletteRoot()
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.contentView = host
        defer { window.close() }
        func settle(_ width: CGFloat) {
            window.setContentSize(CGSize(width: width, height: 900))
            for _ in 0..<12 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        for width: CGFloat in [1440, 1000, 640, 1000, 1440] {
            settle(width)
            XCTAssertGreaterThanOrEqual(contentFrame.width, 639.5, "width=\(width)")
            XCTAssertGreaterThanOrEqual(contentFrame.minX, -0.5, "width=\(width)")
            XCTAssertLessThanOrEqual(contentFrame.maxX, width + 0.5, "width=\(width)")
            XCTAssertEqual(sidebarWidth > 1, width >= 1000, "width=\(width)")
            XCTAssertEqual(inspectorWidth > 1, width >= 1440, "width=\(width)")
        }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(model.panels, .init())
        XCTAssertEqual(regionTokens.count, 1, "Automatic collapse must preserve region-local state")
        model.panels.inspector = false
        settle(1440)
        XCTAssertLessThanOrEqual(inspectorWidth, 1)
        settle(640)
        settle(1440)
        XCTAssertFalse(model.panels.inspector)
        XCTAssertLessThanOrEqual(inspectorWidth, 1)
        model.panels.inspector = true
        settle(1440)
        XCTAssertGreaterThan(inspectorWidth, 1)
        XCTAssertEqual(regionTokens.count, 1)
        XCTAssertEqual(writes, 0)
    }

    func testSceneSizingAdvertisesOnlyTheContentMinimum() {
        let root = LumenUtilityWindow { Color.clear } sidebar: { Text("Sources") }
            inspector: { Text("Tags") } topLeading: { Text("Utility") }
        let host = NSHostingController(rootView: root)
        XCTAssertEqual(host.sizeThatFits(in: .zero), CGSize(width: 640, height: 400))
    }

    func testEveryRequestedPanelCombinationKeepsTheUnifiedBar() {
        for panels in LumenUtilityPanels.allCombinations {
            let findings = LumenConformance.windowStructure(kind: .utility,
                sizes: [CGSize(width: 640, height: 400), CGSize(width: 1440, height: 900)]) {
                LumenUtilityWindow(panels: .constant(panels)) {
                    Text("File review")
                } sidebar: {
                    Text("Sources")
                } inspector: {
                    Text("Tags")
                } statusBar: {
                    Text("Ready")
                } topLeading: {
                    Text("Utility")
                }
            }
            XCTAssertEqual(findings.map(\.description), [], "\(panels)")
        }
    }

    func testOptionalRegionsCanAllBeOmitted() {
        let findings = LumenConformance.windowStructure(kind: .utility,
            sizes: [CGSize(width: 640, height: 400)]) {
            LumenUtilityWindow(panels: .constant(.init())) {
                Text("Files")
            } topLeading: {
                Text("Utility")
            }
        }
        XCTAssertEqual(findings.map(\.description), [])
    }

    func testUtilityDoesNotInheritTheLegacyTopBarPlacement() {
        let findings = LumenConformance.windowStructure(kind: .utility,
            sizes: [CGSize(width: 640, height: 400)]) {
            LumenUtilityWindow(panels: .constant(.init())) {
                Text("Files")
            } topLeading: {
                Text("Utility")
            }
            .lumenTopBarPlacement(.underTitleBar)
        }
        XCTAssertEqual(findings.map(\.description), [])
    }
}

@MainActor @Observable
private final class UtilityBindingModel {
    var panels = LumenUtilityPanels()
}

private struct UtilityStatefulRegion: View {
    @State private var token = UUID()
    let report: (CGRect, UUID) -> Void

    var body: some View {
        Color.blue.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report($0, token) }
    }
}
