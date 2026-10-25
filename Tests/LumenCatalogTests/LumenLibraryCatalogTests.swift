import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import Vision
@testable import LumenUI
import LumenConformance
@testable import LumenCatalog

@MainActor
final class LumenLibraryCatalogTests: XCTestCase {
    private let sizes = [CatalogLibraryWindow.minimumSize, CGSize(width: 1440, height: 900)]

    func testLibraryStructureAtMinimumAndLargeSizes() {
        for sparse in [false, true] {
            for chrome in [LumenChromeStyle.drawn, .glass] {
                let findings = LumenConformance.windowStructure(kind: .library, sizes: sizes) {
                    CatalogLibraryWindow(sparse: sparse).lumenChromeStyle(chrome)
                }
                XCTAssertEqual(findings.map(\.description), [], "sparse=\(sparse), chrome=\(chrome)")
            }
        }
    }

    func testLibraryTruncationAtMinimumAndLargeSizes() {
        for sparse in [false, true] {
            XCTAssertEqual(LumenConformance.truncation(sizes: sizes) {
                CatalogLibraryWindow(sparse: sparse)
            }.map(\.description), [])
        }
    }

    func testLibraryNarrowSizingAtMinimumAndLargeWidths() {
        for size in sizes {
            XCTAssertEqual(LumenConformance.narrowSizing([
                ("Library populated", AnyView(CatalogLibraryWindow())),
                ("Library sparse", AnyView(CatalogLibraryWindow(sparse: true))),
            ], referenceWidth: size.width).map(\.description), [])
        }
    }

    func testPopulatedWindowSurvivesLiveSizeTransitions() {
        var overflow: Set<String> = []
        var truncated: Set<String> = []
        let root = CatalogLibraryWindow().lumenPaletteRoot()
            .onPreferenceChange(LumenColumnOverflowKey.self) { value in MainActor.assumeIsolated { overflow = value } }
            .onPreferenceChange(LumenTruncationKey.self) { value in MainActor.assumeIsolated { truncated = value } }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: CatalogLibraryWindow.defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.contentView = host
        defer { window.close() }
        for size in [CatalogLibraryWindow.defaultSize, CGSize(width: 1028, height: 645),
                     CatalogLibraryWindow.minimumSize, CGSize(width: 1028, height: 645),
                     CatalogLibraryWindow.defaultSize] {
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
        let host = NSHostingView(rootView: CatalogLibraryWindow().lumenPaletteRoot()
            .lumenDensityRoot()
            .modifier(CatalogChromeRoot())
            .lumenMetrics(.standard))
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.toolbars]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: CatalogLibraryWindow.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        // A scene embeds its hosting view in a native container with Auto Layout active.
        // minSize constraints are not exercised by an autoresizing-only direct contentView.
        let container = NSView(frame: CGRect(origin: .zero, size: CatalogLibraryWindow.defaultSize))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.contentMinSize = CatalogLibraryWindow.minimumSize
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        defer { window.close() }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/library-native-resize")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, size) in [CGSize(width: 1100, height: 720), CGSize(width: 640, height: 440),
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
            assertValidGeometry(try XCTUnwrap(host.superview))
            let url = directory.appending(path: "resize-\(index).png")
            try LumenHeadlessHost.png(of: window).write(to: url)
            let request = try LumenAuditOCR.makeRequest()
            try VNImageRequestHandler(url: url).perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            print("Native resize \(index), \(size): \(strings)")
            // At 1100 both side panes fit; at minimum only the central content remains.
            let pane = CGRect(x: size.width > 640 ? 181 : 0, y: 50,
                              width: size.width > 640 ? size.width - 442 : size.width,
                              height: size.height - 110)
            for expected in ["Image 01", "Image 02", "Image 03", "Image 04"] {
                let boxes = observations.filter { $0.topCandidates(1).first?.string == expected }.map {
                    CGRect(x: $0.boundingBox.minX * size.width,
                           y: (1 - $0.boundingBox.maxY) * size.height,
                           width: $0.boundingBox.width * size.width, height: $0.boundingBox.height * size.height)
                }
                XCTAssertTrue(boxes.contains { pane.contains($0) }, "Missing content text \(expected) inside \(pane); size=\(size)")
            }
            let leading = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string == "40 images" })
            XCTAssertLessThan(leading.boundingBox.minX * size.width, 32, "Status must start at the window's leading edge")
            let trailing = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string == "1 selected" })
            XCTAssertGreaterThan(trailing.boundingBox.maxX * size.width, size.width - 40,
                                 "Status must span the window, through its trailing selection count")
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

    func testLibrarySearchAndFiltersUseOriginalItems() {
        XCTAssertEqual(LibraryDemoImage.samples.count, 40)
        XCTAssertEqual(Set(LibraryDemoImage.samples.map(\.id)).count, 40)
        XCTAssertEqual(LibraryDemoImage.filtered(source: "Coast", query: "", filter: "All", sparse: false).count, 10)
        XCTAssertEqual(LibraryDemoImage.filtered(source: "all", query: "Image 01", filter: "All", sparse: false).map(\.id), ["image-01"])
        XCTAssertEqual(LibraryDemoImage.filtered(source: "all", query: "", filter: "Favorites", sparse: false).count, 14)
        XCTAssertEqual(LibraryDemoImage.filtered(source: "all", query: "", filter: "Recent", sparse: false).count, 10)
        XCTAssertEqual(LibraryDemoImage.filtered(source: "all", query: "missing", filter: "All", sparse: false).count, 0)
        XCTAssertEqual(LibraryDemoImage.filtered(source: "all", query: "", filter: "All", sparse: true).count, 1)
    }

    func testLibraryEntryFitsTheCatalogColumn() {
        let column = LumenConformance.Column("Library entry", minWidth: CatalogLayout.pageMinWidth) {
            CatalogPageView(page: .library)
        }
        XCTAssertEqual(LumenConformance.layout(windowMinWidth: CatalogLayout.pageMinWidth,
                                               columns: [column]).map(\.description), [])
    }
}
