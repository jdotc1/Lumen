import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

@MainActor
final class LumenTextScaleTests: XCTestCase {
    private final class Capture { var metrics: LumenMetrics? }
    private struct Probe: View {
        @Environment(\.lumenMetrics) private var metrics
        let capture: Capture
        var body: some View {
            capture.metrics = metrics
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private func capture(_ build: (Probe) -> some View) throws -> LumenMetrics {
        let result = Capture()
        _ = try XCTUnwrap(ImageRenderer(content: build(Probe(capture: result))).cgImage)
        return try XCTUnwrap(result.metrics)
    }

    func testProductClampsOnceAndPreservesIndependentThemeMetrics() {
        for (theme, app, expected) in [(1.1, 1.3, 1.3), (1.1, 0.9, 0.99), (0.9, 1.3, 1.17),
                                        (1.0, 0.1, 0.9), (1.0, 9.0, 1.3), (1.3, 0.5, 0.9)] {
            let resolved = LumenMetrics.resolving(LumenThemeMetrics(typeScale: theme, spacingScale: 1.25), textScale: app)
            XCTAssertEqual(resolved.typography.sectionLabelTracking, 0.5 * expected, accuracy: 0.000001)
            XCTAssertEqual(resolved.layout.controlHeight, 24 * max(1, expected), accuracy: 0.001)
            XCTAssertEqual(resolved.spacing.s11, 60)
        }
        XCTAssertEqual(LumenMetrics.resolving(nil, textScale: 1), .standard)
        for scale in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(LumenMetrics.resolving(nil, textScale: scale), .standard)
        }
    }

    func testPreferenceScalesEveryTypographyRoleAndTracking() {
        for scale in [0.9, 1.15, 1.3] {
            let resolved = LumenMetrics.resolving(nil, textScale: scale)
            for path in [\LumenMetrics.Typography.title2, \.title3, \.headline, \.body, \.bodyEmphasized,
                         \.callout, \.subheadline, \.footnote, \.caption, \.captionEmphasized,
                         \.sectionLabel, \.monoCaption, \.monoSmall, \.display, \.stat] {
                XCTAssertEqual(resolved.typography[keyPath: path], LumenMetrics.standard.typography[keyPath: path].scaled(by: scale))
            }
            XCTAssertEqual(resolved.typography.sectionLabelTracking, 0.5 * scale)
        }
    }

    func testPreferenceAndPaletteRootWorkInEitherOrderAndWithoutARoot() throws {
        let store = TestPack.store()
        store.select(LumenThemes.contrastID)
        let expected = LumenMetrics.resolving(store.theme().metrics, textScale: 1.3)
        XCTAssertEqual(try capture { $0.lumenTextScale(1.3).lumenPaletteRoot(store: store, windowChrome: false) }, expected)
        XCTAssertEqual(try capture { $0.lumenPaletteRoot(store: store, windowChrome: false).lumenTextScale(1.3) }, expected)
        XCTAssertEqual(try capture { $0.lumenTextScale(1.15) }, LumenMetrics.resolving(nil, textScale: 1.15))
    }

    func testBothModifierOrdersResolveTheSameUnclampedThemeProduct() throws {
        let store = TestPack.store()
        store.select(LumenThemes.contrastID)
        for scale in [0.9, 1.0, 1.15] {
            let expected = LumenMetrics.resolving(store.theme().metrics, textScale: scale)
            let inside = try capture {
                $0.lumenTextScale(scale).lumenPaletteRoot(store: store, windowChrome: false)
            }
            let outside = try capture {
                $0.lumenPaletteRoot(store: store, windowChrome: false).lumenTextScale(scale)
            }
            XCTAssertEqual(inside, outside)
            XCTAssertEqual(inside, expected)
            XCTAssertEqual(try capture {
                $0.lumenPaletteRoot(store: store, windowChrome: false).environment(\.lumenTextScale, scale)
            }, expected)
        }
    }

    func testMetricsReadUsesStoredResolutionAndAppOverride() {
        var environment = EnvironmentValues()
        let resolved = LumenMetrics.resolving(LumenThemeMetrics(typeScale: 1.1), textScale: 1.15)
        environment.lumenResolvedThemeMetrics = resolved
        // Raw inputs are deliberately different: a read must never resolve them again.
        environment.lumenThemeMetrics = LumenThemeMetrics(typeScale: 0.9)
        environment.lumenTextScale = 0.9
        XCTAssertEqual(environment.lumenMetrics, resolved)
        environment.lumenMetrics = .standard
        XCTAssertEqual(environment.lumenMetrics, .standard)
    }

    func testSnapshotRenderersResolveThemeAndTextScale() throws {
        let registry = LumenRegistry(packs: [.core])
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.contrastID, colorScheme: .light)
        let expected = LumenMetrics.resolving(LumenThemes.contrast.metrics, textScale: 1.15)
        for renderer in [LumenSnapshot.Renderer.image, .window] {
            let result = Capture()
            let rendered = LumenSnapshot.render(Probe(capture: result).lumenTextScale(1.15),
                size: CGSize(width: 40, height: 40), variant: variant, registry: registry, renderer: renderer)
            XCTAssertNotNil(rendered.png)
            XCTAssertEqual(result.metrics, expected)
        }
    }

    func testExplicitAppMetricsWinIncludingStandardAndDirectEnvironmentWrites() throws {
        let store = TestPack.store()
        store.select(LumenThemes.contrastID)
        var custom = LumenMetrics.standard
        custom.layout.controlHeight = 37
        custom.typography.body = .system(size: 19, design: .serif)
        for app in [LumenMetrics.standard, custom] {
            XCTAssertEqual(try capture {
                $0.lumenMetrics(app).lumenTextScale(1.3).lumenPaletteRoot(store: store, windowChrome: false)
            }, app)
            XCTAssertEqual(try capture {
                $0.lumenPaletteRoot(store: store, windowChrome: false).lumenTextScale(1.3).lumenMetrics(app)
            }, app)
            XCTAssertEqual(try capture { $0.environment(\.lumenMetrics, app).lumenTextScale(1.3) }, app)
        }
    }

    func testNestedRootsResolveTheirOwnThemeWithoutCompoundingPreference() throws {
        let outer = TestPack.store(), inner = TestPack.store()
        outer.select(LumenThemes.contrastID)
        XCTAssertEqual(try capture {
            $0.lumenPaletteRoot(store: inner, windowChrome: false)
                .lumenPaletteRoot(store: outer, windowChrome: false).lumenTextScale(1.15)
        }, LumenMetrics.resolving(nil, textScale: 1.15))
        XCTAssertEqual(try capture { $0.lumenTextScale(1.15).lumenTextScale(1.3) },
                       LumenMetrics.resolving(nil, textScale: 1.15))
    }

    func testTextFitsRowsAndHitTargetFloorsHoldAtEveryScaleAndDensity() throws {
        for themeScale in [0.9, 1.0, 1.1, 1.3] {
            for appScale in [0.9, 1.0, 1.15, 1.3] {
                let metrics = LumenMetrics.resolving(LumenThemeMetrics(typeScale: themeScale), textScale: appScale)
                let text = try XCTUnwrap(ImageRenderer(content: Text("AgjÅ").font(metrics.typography.body)).cgImage)
                for density in LumenDensity.allCases {
                    XCTAssertGreaterThanOrEqual(metrics.layout.controlHeight, 24)
                    XCTAssertGreaterThanOrEqual(metrics.layout.minimumHitTarget, 24)
                    XCTAssertGreaterThanOrEqual(density.rowHeight(in: metrics.layout), CGFloat(text.height))
                    let row = LumenListRow("AgjÅ", detail: "Two-line detail")
                        .lumenMetrics(metrics).environment(\.lumenDensity, density).frame(width: 300)
                    let rowImage = try XCTUnwrap(ImageRenderer(content: row).cgImage)
                    XCTAssertGreaterThanOrEqual(CGFloat(rowImage.height), density.detailedRowHeight(in: metrics.layout) - 1)
                    let button = Button {} label: { Image(systemName: "plus") }
                        .buttonStyle(LumenPanelIconButtonStyle()).lumenMetrics(metrics)
                        .environment(\.lumenDensity, density)
                    let image = try XCTUnwrap(ImageRenderer(content: button).cgImage)
                    XCTAssertGreaterThanOrEqual(image.width, 24)
                    XCTAssertGreaterThanOrEqual(image.height, 24)
                }
            }
        }
    }
}
