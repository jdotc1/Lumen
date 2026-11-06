import SwiftUI
import XCTest
import LumenTokens
import LumenConformance
@testable import LumenUI

@MainActor
final class LumenThemeEditorLayoutTests: XCTestCase {
    func testMetricControlsFitAtLargestSupportedScales() {
        let store = TestPack.store(registry: .core)
        let session = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        session.setRadiusProfile(.uniform(12))
        session.setTypeScale(1.3)
        session.setSpacingScale(1.25)
        let themeMetrics = LumenMetrics.resolving(session.draft.metrics)
        let sizes = [CGSize(width: 360, height: 650)]
        XCTAssertEqual(LumenConformance.overflow(sizes: sizes) {
            LumenThemeMetricControls(session: session).lumenMetrics(themeMetrics)
        }, [])
        XCTAssertEqual(LumenConformance.truncation(sizes: sizes) {
            LumenThemeMetricControls(session: session).lumenMetrics(themeMetrics)
        }, [])
    }

    func testSeedSheetFitsItsMinimumWidth() {
        let store = TestPack.store(registry: .core)
        XCTAssertEqual(LumenConformance.overflow(sizes: [CGSize(width: 580, height: 650)]) {
            LumenThemeSeedSheet(store: store)
        }, [])
    }
}
