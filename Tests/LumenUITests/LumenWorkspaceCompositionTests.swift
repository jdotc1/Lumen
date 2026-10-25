import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenConformance
@testable import LumenUI
@testable import LumenCatalog

@MainActor final class LumenWorkspaceCompositionTests: XCTestCase {
    func testHeaderMovesActionsBelowTitleAndGrowsWithTextScale() {
        let wide = height(width: 760, scale: 1)
        let narrow = height(width: 240, scale: 1)
        let scaled = height(width: 240, scale: 1.3)
        XCTAssertGreaterThan(narrow, wide + 20, "Actions must move beneath the heading at narrow widths")
        XCTAssertGreaterThan(scaled, narrow, "Wrapped header must grow with the type ramp")
    }

    func testHeaderWithoutOptionalContentFits() {
        let view = LumenPageHeader("Files").lumenPaletteRoot().frame(width: 240)
        let host = NSHostingView(rootView: view)
        XCTAssertGreaterThan(host.fittingSize.height, 10)
        XCTAssertLessThan(host.fittingSize.height, 60)
    }

    func testHeaderAndStatusPrimaryLabelsAtSupportedScales() {
        for scale in [1.0, 1.3] {
            let header = LumenWorkspaceCompositionHeaderSubject().lumenTextScale(scale)
            XCTAssertTrue(LumenConformance.truncation(sizes: [.init(width: 240, height: 300), .init(width: 760, height: 160)]) {
                header
            }.isEmpty)
            XCTAssertTrue(LumenConformance.truncation(sizes: [.init(width: 360, height: 80)]) {
                CatalogSmallAppStatus(isBusy: .constant(true)).lumenTextScale(scale)
            }.isEmpty)
        }
    }

    func testWorkspaceDestinationsHaveDistinctStableIDs() {
        let library = CatalogSmallApp.library
        let review = CatalogSmallApp.review
        XCTAssertEqual(library.count, 5)
        XCTAssertEqual(review.count, 4)
        XCTAssertEqual(Set((library + review).map(\.id)).count, 9)
        XCTAssertTrue(library.allSatisfy { $0.id.hasPrefix("library.") })
        XCTAssertTrue(review.allSatisfy { $0.id.hasPrefix("review.") })
    }

    private func height(width: CGFloat, scale: Double) -> CGFloat {
        let view = LumenWorkspaceCompositionHeaderSubject().lumenPaletteRoot().lumenTextScale(scale)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
        return NSHostingView(rootView: view).fittingSize.height
    }
}

struct LumenWorkspaceCompositionHeaderSubject: View {
    var body: some View {
        LumenPageHeader("Workspace overview", subtitle: "Files ready for review", systemImage: "folder") {
            Button("Import files") {}
            Button("New collection") {}
        }
        .padding(16)
    }
}

/// Only these new subjects may be recorded; existing golden files are never written here.
@MainActor final class LumenWorkspaceCompositionGoldenTests: XCTestCase {
    private let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")

    func testPageHeaderGoldens() {
        for scheme in [ColorScheme.light, .dark] {
            for scale in [1.0, 1.3] {
                for width in [240.0, 760.0] {
                    check(LumenWorkspaceCompositionHeaderSubject().lumenTextScale(scale),
                          name: "workspace-composition-page-header-\(Int(width))-\(scale)",
                          size: .init(width: width, height: 240), scheme: scheme)
                }
            }
        }
    }

    func testBusyCancelGoldens() {
        for scheme in [ColorScheme.light, .dark] {
            check(CatalogSmallAppStatus(isBusy: .constant(true)).padding(16),
                  name: "workspace-composition-status-busy-cancel", size: .init(width: 460, height: 80), scheme: scheme)
        }
    }

    private func check<V: View>(_ view: V, name: String, size: CGSize, scheme: ColorScheme) {
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: scheme)
        // Refuse an accidental overwrite, even if a recording environment leaks into this test.
        if LumenSnapshot.isRecording {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "\(name)@\(variant.label).png").path))
            guard !FileManager.default.fileExists(atPath: directory.appending(path: "\(name)@\(variant.label).png").path) else { return }
        }
        let outcome = LumenSnapshot.verify(view, named: name, size: size, variant: variant,
                                           registry: .core, goldenDirectory: directory, renderer: .window)
        if let message = outcome.failureMessage { XCTFail("\(name): \(message)") }
    }
}

@MainActor final class LumenWorkspaceCompositionCaptureTests: XCTestCase {
    func testSmallAppBitmaps() throws {
        guard let path = ProcessInfo.processInfo.environment["LUMEN_WORKSPACE_SHOTS"] else {
            throw XCTSkip("Set LUMEN_WORKSPACE_SHOTS for the one-time Catalog bitmap capture")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let data = try XCTUnwrap(LumenSnapshot.png(of: CatalogSmallApp(), size: .init(width: 1000, height: 660),
                variant: .init(themeID: LumenThemes.standardID, colorScheme: scheme), registry: .core, scale: 1, renderer: .window))
            let image = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(image.pixelsWide, 1000)
            XCTAssertEqual(image.pixelsHigh, 660)
            try data.write(to: directory.appending(path: "small-app-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
