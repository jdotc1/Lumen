import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import Vision
@testable import LumenUI
import LumenConformance
@testable import LumenCatalog

@MainActor
final class LumenUtilityCatalogTests: XCTestCase {
    private let sizes = [CatalogUtilityWindow.minimumSize, CGSize(width: 1440, height: 900)]

    func testUtilityStructureAtMinimumAndLargeSizes() {
        for sparse in [false, true] {
            for chrome in [LumenChromeStyle.drawn, .glass] {
                let findings = LumenConformance.windowStructure(kind: .utility, sizes: sizes) {
                    CatalogUtilityWindow(sparse: sparse).lumenChromeStyle(chrome)
                }
                XCTAssertEqual(findings.map(\.description), [], "sparse=\(sparse), chrome=\(chrome)")
            }
        }
    }

    func testUtilityTruncationAtMinimumAndLargeSizes() {
        for sparse in [false, true] {
            XCTAssertEqual(LumenConformance.truncation(sizes: sizes) {
                CatalogUtilityWindow(sparse: sparse)
            }.map(\.description), [])
        }
    }

    func testUtilityNarrowSizingAtMinimumAndLargeWidths() {
        for size in sizes {
            XCTAssertEqual(LumenConformance.narrowSizing([
                ("Utility populated", AnyView(CatalogUtilityWindow())),
                ("Utility sparse", AnyView(CatalogUtilityWindow(sparse: true))),
            ], referenceWidth: size.width).map(\.description), [])
        }
    }

    func testPopulatedWindowSurvivesLiveSizeTransitions() {
        var overflow: Set<String> = []
        var truncated: Set<String> = []
        let root = CatalogUtilityWindow().lumenPaletteRoot()
            .onPreferenceChange(LumenColumnOverflowKey.self) { value in MainActor.assumeIsolated { overflow = value } }
            .onPreferenceChange(LumenTruncationKey.self) { value in MainActor.assumeIsolated { truncated = value } }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: CatalogUtilityWindow.defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.contentView = host
        defer { window.close() }
        for size in [CatalogUtilityWindow.defaultSize, CGSize(width: 1028, height: 645),
                     CatalogUtilityWindow.minimumSize, CGSize(width: 1028, height: 645),
                     CatalogUtilityWindow.defaultSize] {
            window.setContentSize(size)
            for _ in 0..<12 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            XCTAssertEqual(overflow, [], "\(size)")
            XCTAssertEqual(truncated, [], "\(size)")
        }
    }

    /// Capture the offscreen native frame: layout preferences alone passed while all
    /// content glyphs were missing. OCR boxes also establish that text remains inside its pane.
    func testLiveWindowTextAndStatusStayInsideBoundsAfterResize() throws {
        let host = NSHostingView(rootView: CatalogUtilityWindow().lumenPaletteRoot()
            .lumenDensityRoot()
            .modifier(CatalogChromeRoot())
            .lumenMetrics(.standard))
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: CatalogUtilityWindow.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        // A scene embeds its hosting view in a native container with Auto Layout active.
        // minSize constraints are not exercised by an autoresizing-only direct contentView.
        let container = NSView(frame: CGRect(origin: .zero, size: CatalogUtilityWindow.defaultSize))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.contentMinSize = CatalogUtilityWindow.minimumSize
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        defer { window.close() }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/utility-native-resize")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, size) in [CGSize(width: 1100, height: 720), CGSize(width: 640, height: 480),
                             CGSize(width: 1100, height: 720)].enumerated() {
            window.setFrame(CGRect(origin: window.frame.origin, size: size), display: true)
            for _ in 0..<12 {
                (host.superview ?? host).layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            print("Native host frame=\(host.frame), bounds=\(host.bounds), container=\(container.bounds), minimum=\(window.contentMinSize)")
            XCTAssertEqual(host.frame.width, container.bounds.width, accuracy: 0.5,
                           "The constrained host must follow the window allocation")
            inspectNativeTextGeometry(window)
            assertValidGeometry(try XCTUnwrap(host.superview))
            let url = directory.appending(path: "resize-\(index).png")
            try LumenHeadlessHost.png(of: window).write(to: url)
            let request = try LumenAuditOCR.makeRequest()
            try VNImageRequestHandler(url: url).perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            print("Native resize \(index), \(size): \(strings)")
            // At 1100 both side panes fit; at minimum only the central content remains.
            let pane = CGRect(x: size.width > 640 ? 201 : 0, y: 50,
                              width: size.width > 640 ? size.width - 442 : size.width,
                              height: size.height - 110)
            for expected in ["FILE REVIEW", "FILE", "SIZE", "STATE", "Sample 01.dcm",
                             "Sample 02.dcm", "Sample 03.dcm", "Sample 04.dcm"] {
                let boxes = observations.filter { $0.topCandidates(1).first?.string == expected }.map {
                    CGRect(x: $0.boundingBox.minX * size.width,
                           y: (1 - $0.boundingBox.maxY) * size.height,
                           width: $0.boundingBox.width * size.width, height: $0.boundingBox.height * size.height)
                }
                XCTAssertTrue(boxes.contains { pane.contains($0) }, "Missing content text \(expected) inside \(pane); size=\(size)")
            }
            let leading = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string == "4 files" })
            XCTAssertLessThan(leading.boundingBox.minX * size.width, 32, "Status must start at the window's leading edge")
            let trailing = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string == "Reviewing 2 of 4" })
            XCTAssertGreaterThan(trailing.boundingBox.maxX * size.width, size.width - 160,
                                 "Status must span the window, through its trailing progress item")
        }
    }

    private func inspectNativeTextGeometry(_ element: any NSAccessibilityProtocol) {
        let frame = element.accessibilityFrame()
        XCTAssertTrue(frame.size.width >= 0 && frame.size.height >= 0, "\(frame)")
        for child in element.accessibilityChildren() ?? [] {
            if let child = child as? any NSAccessibilityProtocol { inspectNativeTextGeometry(child) }
        }
    }

    private func assertValidGeometry(_ view: NSView) {
        for rect in [view.frame, view.bounds] {
            XCTAssertTrue(rect.origin.x.isFinite && rect.origin.y.isFinite, "\(type(of: view)): \(rect)")
            XCTAssertTrue(rect.size.width.isFinite && rect.size.width >= 0, "\(type(of: view)): \(rect)")
            XCTAssertTrue(rect.size.height.isFinite && rect.size.height >= 0, "\(type(of: view)): \(rect)")
        }
        for child in view.subviews { assertValidGeometry(child) }
    }

    func testUtilityEntryFitsTheCatalogColumn() {
        let column = LumenConformance.Column("Utility entry", minWidth: CatalogLayout.pageMinWidth) {
            CatalogPageView(page: .utility)
        }
        XCTAssertEqual(LumenConformance.layout(windowMinWidth: CatalogLayout.pageMinWidth,
                                               columns: [column]).map(\.description), [])
    }
}
