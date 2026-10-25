import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import Observation
@testable import LumenUI

@MainActor
final class LumenDocumentWindowTests: XCTestCase {
    func testAutoLayoutWindowResizesAndRestoresWithoutWritingItsBinding() {
        let model = DocumentBindingModel()
        var writes = 0
        var contentFrame: CGRect = .zero
        var inspectorTokens: Set<UUID> = []
        var inspectorWidth: CGFloat = 0
        let root = LumenDocumentWindow(title: .constant("Notes"), isModified: true,
            inspectorPresented: Binding(get: { model.inspector }, set: { model.inspector = $0; writes += 1 })) {
            Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
        } inspector: {
            DocumentStatefulRegion { frame, token in
                inspectorWidth = frame.width
                inspectorTokens.insert(token)
            }
        }
        .inspectorWidth((240, 280, 360))
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
            XCTAssertEqual(inspectorWidth > 1, width >= 1000, "width=\(width)")
        }
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(model.inspector)
        XCTAssertEqual(inspectorTokens.count, 1, "Automatic collapse must preserve inspector state")
        model.inspector = false
        settle(1100)
        XCTAssertLessThanOrEqual(inspectorWidth, 1)
        settle(640)
        settle(1100)
        XCTAssertFalse(model.inspector)
        XCTAssertLessThanOrEqual(inspectorWidth, 1)
        model.inspector = true
        settle(1100)
        XCTAssertGreaterThan(inspectorWidth, 1)
        XCTAssertEqual(inspectorTokens.count, 1)
        XCTAssertEqual(writes, 0)
    }

    func testSceneSizingAdvertisesOnlyTheContentMinimum() {
        let root = LumenDocumentWindow(title: .constant("Notes"), isModified: false) {
            Color.clear
        } inspector: {
            Text("Details")
        }
        let host = NSHostingController(rootView: root)
        XCTAssertEqual(host.sizeThatFits(in: .zero), CGSize(width: 640, height: 400))
    }

    func testContentMinimumOverrideAndOmittedRegions() {
        let root = LumenDocumentWindow(title: .constant("Notes"), isModified: false,
                                      minimumSize: CGSize(width: 640, height: 420)) {
            Color.clear
        }
        .contentMinimumWidth(720)
        let host = NSHostingController(rootView: root)
        XCTAssertEqual(host.sizeThatFits(in: .zero), CGSize(width: 720, height: 420))
    }
}

@MainActor @Observable
private final class DocumentBindingModel {
    var inspector = true
}

private struct DocumentStatefulRegion: View {
    @State private var token = UUID()
    let report: (CGRect, UUID) -> Void

    var body: some View {
        Color.blue.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report($0, token) }
    }
}
