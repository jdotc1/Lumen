import SwiftUI
import XCTest
import LumenTokens
import LumenUI
import LumenConformance
@testable import LumenCatalog

@MainActor
final class CatalogMenuBarPanelTests: XCTestCase {
    func testPanelFitsAtDefaultWidthInEveryTheme() {
        for variant in LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes) {
            let store = LumenSnapshot.store(for: variant, registry: .core)
            LumenThemeStore.withActiveStore(store) {
                MainActor.assumeIsolated {
                    let panel = CatalogMenuBarPanel().lumenPaletteRoot(store: store)
                        .environment(\.colorScheme, variant.colorScheme)
                    let sizes = [CGSize(width: LumenLayout.popoverWidth, height: LumenLayout.panelMaxHeight),
                                 CGSize(width: LumenLayout.popoverWidth, height: 240)]
                    XCTAssertEqual(LumenConformance.windowStructure(kind: .menuBarPanel, sizes: sizes) {
                        panel
                    }.map(\.description), [], variant.label)
                    XCTAssertEqual(LumenConformance.truncation(sizes: sizes) { panel }.map(\.description), [], variant.label)
                    XCTAssertEqual(LumenConformance.narrowSizing([(name: "Agent", view: AnyView(panel))],
                        referenceWidth: LumenLayout.popoverWidth).map(\.description), [], variant.label)
                }
            }
        }
    }
}
