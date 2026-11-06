import XCTest
import LumenTokens
@testable import LumenUI

extension LumenAccessibilityTests {
    func testEntryControlContrast() {
        let registry = LumenRegistry.core
        let pairs: [(LumenToken, LumenToken)] = [
            (.fgPrimary, .bgElevated), (.fgPrimary, .bgInsetRaised),
            (.chipSelectedForeground, .chipSelectedBackground),
            (.accentFilledForeground, .accentFilled),
        ]
        for theme in registry.galleryThemes {
            for dark in theme.supportedAppearances {
                for highContrast in [false, true] {
                    let appearance = LumenAppearance(isDark: dark, isHighContrast: highContrast)
                    for (ink, ground) in pairs {
                        XCTAssertGreaterThanOrEqual(theme.color(ink, for: appearance, in: registry)
                            .contrastRatio(against: theme.color(ground, for: appearance, in: registry)), 4.5,
                            "\(theme.name): \(ink.rawValue) on \(ground.rawValue)")
                    }
                }
            }
        }
    }
}
