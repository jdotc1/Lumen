import AppKit
import LumenTestSupport
import LumenTokens
@_spi(LayoutAudit) @testable import LumenUI
import SwiftUI
import XCTest

@MainActor
final class LumenPinnedTopBarBandTests: XCTestCase {
    private let rule = "pinned-top-bar-sidebar-ground"
    private let painterRule = "pinned-top-bar-band-painter"
    private enum Kind { case workspace, library, utility }

    private func subject(_ kind: Kind) -> AnyView {
        switch kind {
        case .workspace:
            AnyView(LumenWorkspaceWindow(panels: .constant(.init(leading: true, bottom: false, trailing: false))) {
                Color.clear
            } sidebar: { Text("Sidebar") } topLeading: { Text("Workspace") })
        case .library:
            AnyView(LumenLibraryWindow(panels: .constant(.init(sourceList: true, detail: false))) {
                Color.clear
            } sourceList: { Text("Sidebar") } topLeading: { Text("Library") })
        case .utility:
            AnyView(LumenUtilityWindow(panels: .constant(.init(sidebar: true, inspector: false))) {
                Color.clear
            } sidebar: { Text("Sidebar") } topLeading: { Text("Utility") })
        }
    }

    private func host(_ kind: Kind, active: Bool, transparentTitlebar: Bool = true) -> NSWindow {
        _ = NSApplication.shared
        let root = subject(kind).lumenPaletteRoot()
            .environment(\.appearsActive, active)
            .environment(\.controlActiveState, active ? .active : .inactive)
        let content = NSHostingView(rootView: root)
        content.sizingOptions = []
        content.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: .init(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = transparentTitlebar
        window.toolbarStyle = .unifiedCompact
        window.contentView = content
        window.setContentSize(.init(width: 1200, height: 700))
        LumenHeadlessHost.order(window)
        for _ in 0..<20 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func assertContinuousBand(_ kind: Kind, active: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let window = host(kind, active: active)
        defer { window.close() }
        let report = LumenWindowAuditReports.record(for: window)
        let band = try XCTUnwrap(report.pinnedTopBarFrame, file: file, line: line)
        XCTAssertGreaterThan(band.height, 0, file: file, line: line)
        XCTAssertEqual(band.width, window.frame.width, accuracy: 1, file: file, line: line)
        let chrome = LumenWindowGeometry(window: window).chromeBand
        XCTAssertGreaterThan(band.intersection(chrome).height, 0, file: file, line: line)
        let frame = try XCTUnwrap(window.contentView?.superview, file: file, line: line)
        XCTAssertTrue(descendants(frame).contains { $0 is LumenSidebarPaletteReportView },
                      "The sidebar must be present", file: file, line: line)
        for view in descendants(frame).compactMap({ $0 as? NSVisualEffectView })
            where view.material == .sidebar && !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0 {
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            XCTAssertTrue(rect.intersection(chrome).isEmpty, "Sidebar material overlaps chrome: \(rect)", file: file, line: line)
        }
        XCTAssertTrue(report.pinnedBarOwnsBand, "The pinned bar must be reported as the band's painter", file: file, line: line)
        XCTAssertFalse(report.forcesToolbarBand, "No system toolbar background may cover the pinned bar", file: file, line: line)
        XCTAssertTrue(window.titlebarAppearsTransparent, file: file, line: line)
        XCTAssertEqual(LumenRenderedAudit.windowChromeFindings(in: window).filter { $0.rule == rule || $0.rule == painterRule }, [],
                       file: file, line: line)
        let capture = try LumenRenderedAudit.capture(in: window)
        XCTAssertEqual(capture.windowChromeFindings.filter { $0.rule == rule || $0.rule == painterRule }, [], file: file, line: line)
    }

    func testWorkspaceActiveAppearance() throws { try assertContinuousBand(.workspace, active: true) }
    func testWorkspaceInactiveAppearance() throws { try assertContinuousBand(.workspace, active: false) }
    func testLibraryActiveAppearance() throws { try assertContinuousBand(.library, active: true) }
    func testLibraryInactiveAppearance() throws { try assertContinuousBand(.library, active: false) }
    func testUtilityActiveAppearance() throws { try assertContinuousBand(.utility, active: true) }
    func testUtilityInactiveAppearance() throws { try assertContinuousBand(.utility, active: false) }

    func testPinnedBarKeepsTheBandWhenTheWindowStartsWithAnOpaqueTitleBar() throws {
        for kind in [Kind.workspace, .library, .utility] {
            let window = host(kind, active: true, transparentTitlebar: false)
            defer { window.close() }
            let report = LumenWindowAuditReports.record(for: window)
            XCTAssertTrue(report.pinnedBarOwnsBand, "\(kind)")
            XCTAssertFalse(report.forcesToolbarBand, "\(kind)")
            XCTAssertTrue(window.titlebarAppearsTransparent, "\(kind)")
            XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == painterRule }, "\(kind)")
        }
    }

    func testAuditDetectsASystemFillOverThePinnedBar() throws {
        let window = host(.workspace, active: true)
        defer { window.close() }
        let report = LumenWindowAuditReports.record(for: window)
        XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == painterRule })
        report.forcesToolbarBand = true
        XCTAssertEqual(LumenRenderedAudit.windowChromeFindings(in: window).filter { $0.rule == painterRule }.count, 1)
        report.forcesToolbarBand = false
        window.titlebarAppearsTransparent = false
        XCTAssertEqual(LumenRenderedAudit.windowChromeFindings(in: window).filter { $0.rule == painterRule }.count, 1)
        report.pinnedBarOwnsBand = false
        XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == painterRule })
    }

    func testAuditDetectsNativeSidebarMaterialAndIgnoresHiddenOrTransparentGround() throws {
        let window = host(.workspace, active: false)
        defer { window.close() }
        let frame = try XCTUnwrap(window.contentView?.superview)
        let band = try XCTUnwrap(LumenWindowAuditReports.record(for: window).pinnedTopBarFrame)
        let material = NSVisualEffectView(frame: frame.convert(window.convertFromScreen(band), from: nil))
        material.material = .sidebar
        material.blendingMode = .behindWindow
        frame.addSubview(material, positioned: .above, relativeTo: window.contentView)
        XCTAssertEqual(LumenRenderedAudit.windowChromeFindings(in: window).filter { $0.rule == rule }.count, 1)
        material.isHidden = true
        XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == rule })
        material.isHidden = false
        material.alphaValue = 0
        XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == rule })
    }

    func testAuditDetectsDeclaredSidebarGroundOnlyWhenABarIsPinned() throws {
        let window = host(.utility, active: true)
        defer { window.close() }
        let frame = try XCTUnwrap(window.contentView?.superview)
        let report = LumenWindowAuditReports.record(for: window)
        let band = try XCTUnwrap(report.pinnedTopBarFrame)
        let ground = LumenSidebarPaletteReportView(frame: frame.convert(window.convertFromScreen(band), from: nil))
        frame.addSubview(ground, positioned: .above, relativeTo: window.contentView)
        XCTAssertEqual(LumenRenderedAudit.windowChromeFindings(in: window).filter { $0.rule == rule }.count, 1)
        report.pinnedTopBarFrame = nil
        XCTAssertFalse(LumenRenderedAudit.windowChromeFindings(in: window).contains { $0.rule == rule })
    }
}
