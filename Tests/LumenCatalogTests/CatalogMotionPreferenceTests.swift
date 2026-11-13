import XCTest
import LumenUI
@testable import LumenCatalog

final class CatalogMotionPreferenceTests: XCTestCase {
    func testOnKeepsTheThemeMotion() {
        XCTAssertEqual(CatalogMotionPreference.on.applying(to: .standard).motion, LumenMetrics.standard.motion)
    }

    func testReducedShortensDurationsAndKeepsMotionEnabled() {
        let motion = CatalogMotionPreference.reduced.applying(to: .standard).motion
        XCTAssertTrue(motion.isEnabled)
        XCTAssertLessThan(motion.standard, LumenMetrics.standard.motion.standard)
    }

    func testOffDisablesMotion() {
        let motion = CatalogMotionPreference.off.applying(to: .standard).motion
        XCTAssertFalse(motion.isEnabled)
        XCTAssertEqual(motion.standard, 0)
    }

    func testStoredRawValuesAreStable() {
        XCTAssertEqual(CatalogMotionPreference.allCases.map(\.rawValue), ["on", "reduced", "off"])
    }
}
