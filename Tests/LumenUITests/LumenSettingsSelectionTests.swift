import XCTest
import LumenTokens
@testable import LumenUI

final class LumenSettingsSelectionTests: XCTestCase {
    func testSettingsSelectionContrastAcrossBuiltInAppearances() {
        let registry = LumenRegistry.core
        for theme in registry.galleryThemes {
            for dark in theme.supportedAppearances {
                for increased in [false, true] {
                    let appearance = LumenAppearance(isDark: dark, isHighContrast: increased)
                    for (ink, fill) in [(LumenToken.accentFilledForeground, LumenToken.accentFilled),
                                        (.sidebarForeground, .settingsRowSelectedInactive)] {
                        let ratio = theme.color(ink, for: appearance, in: registry)
                            .contrastRatio(against: theme.color(fill, for: appearance, in: registry))
                        XCTAssertGreaterThanOrEqual(ratio, 4.5,
                            "\(theme.name) dark=\(dark) contrast=\(increased): \(ink) on \(fill) ratio=\(ratio)")
                    }
                }
            }
        }
    }
}
