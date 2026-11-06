import SwiftUI
import XCTest
import LumenTokens
import LumenUI
@testable import LumenCatalog

/// Captures the actual Catalog agent panel in all six gallery appearances.
@MainActor
final class LumenMenuBarGoldenTests: XCTestCase {
    func testMenuBarPanel() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
        let variants = LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        for variant in variants {
            let outcome = LumenSnapshot.verify(CatalogMenuBarPanel(), named: "menu-bar-panel",
                size: CGSize(width: LumenLayout.popoverWidth, height: LumenLayout.panelMaxHeight),
                variant: variant, registry: .core, goldenDirectory: directory, renderer: .window)
            if let message = outcome.failureMessage { XCTFail(message) }
        }
    }
}
