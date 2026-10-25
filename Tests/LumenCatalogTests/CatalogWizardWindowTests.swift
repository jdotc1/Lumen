import SwiftUI
import XCTest
import LumenTokens
import LumenUI
import LumenConformance
@testable import LumenCatalog

@MainActor
final class CatalogWizardWindowTests: XCTestCase {
    func testEmptyWizardClampsItsBindingAndHasNoPageContent() {
        var current = 9
        var builtPage = false
        let wizard = LumenWizardWindow(pages: [],
            current: Binding(get: { current }, set: { current = $0 }),
            onCancel: {}, onFinish: {}) { _ in
                builtPage = true
                return Text("Unexpected page")
            }
        XCTAssertEqual(LumenConformance.windowStructure(kind: .wizard,
            sizes: [.init(width: 640, height: 460)]) { wizard }.map(\.description), [])
        XCTAssertEqual(current, 0)
        XCTAssertFalse(builtPage)
    }

    func testLongSummaryValuesWrapAndTallBodyScrolls() {
        let wizard = LumenWizardWindow(pages: [.init(id: "summary", title: "Summary")],
            current: .constant(0), onCancel: {}, onFinish: {}) { _ in
                LumenWizardSummary((0..<12).map {
                    (label: "Folder \($0 + 1)", value: "Example Project / Research / Reference Images / Original Measurements")
                })
            }
        XCTAssertEqual(LumenConformance.windowStructure(kind: .wizard,
            sizes: [.init(width: 640, height: 460)]) { wizard }.map(\.description), [])
    }

    func testInlinePreviewFitsNarrowAndWideColumnsAtBothTextScales() {
        let store = LumenSnapshot.store(for: .init(themeID: LumenRegistry.core.defaultThemeID, colorScheme: .light), registry: .core)
        LumenThemeStore.withActiveStore(store) {
            MainActor.assumeIsolated {
                for scale in [1.0, 1.3] {
                    for width in [424.0, 960.0] {
                        let size = CGSize(width: width, height: min(width, 640 * scale) * 460 / 640)
                        let preview = CatalogWizardPreview()
                            .lumenPaletteRoot(store: store).lumenTextScale(scale)
                        XCTAssertEqual(LumenConformance.windowStructure(kind: .wizard, sizes: [size]) {
                            preview
                        }.map(\.description), [], "column \(width), scale \(scale)")
                    }
                }
            }
        }
    }

    func testEveryPageFitsAtNaturalSizeAndLargerText() {
        let store = LumenSnapshot.store(for: .init(themeID: LumenRegistry.core.defaultThemeID, colorScheme: .light), registry: .core)
        LumenThemeStore.withActiveStore(store) {
            MainActor.assumeIsolated {
                for scale in [1.0, 1.3] {
                    let size = CGSize(width: 640 * scale, height: 460 * scale)
                    for current in 0..<4 {
                        let wizard = CatalogWizardWindow(current: current)
                            .lumenPaletteRoot(store: store).lumenTextScale(scale)
                        XCTAssertEqual(LumenConformance.windowStructure(kind: .wizard, sizes: [size]) {
                            wizard
                        }.map(\.description), [], "page \(current), scale \(scale)")
                        XCTAssertEqual(LumenConformance.truncation(sizes: [size]) { wizard }.map(\.description), [],
                                       "page \(current), scale \(scale)")
                    }
                }
            }
        }
    }
}
