import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Keyboard and readability guarantees for Lumen's own controls.
@MainActor
final class LumenAccessibilityTests: XCTestCase {
    private let registry = LumenRegistry.core
    private var appearances: [LumenAppearance] {
        [false, true].flatMap { dark in [false, true].map { LumenAppearance(isDark: dark, isHighContrast: $0) } }
    }

    /// A glyph's full-strength marks reach 3:1 against its tint layer inside every tile: the tint
    /// deepens the hue under white glyphs and lightens it under dark ones.
    func testGlyphMarksStayReadableOverTheirTintInTiles() {
        let store = TestPack.store(registry: registry)
        for theme in registry.galleryThemes {
            store.select(theme.id)
            for appearance in appearances where theme.supportedAppearances.contains(appearance.isDark) {
                for hue in LumenToken.hues {
                    let colors = LumenTileColors(hue: hue, appearance: appearance, store: store)
                    XCTAssertGreaterThanOrEqual(colors.glyphValue.contrastRatio(against: colors.tintGroundValue), 3,
                                                "\(theme.name) \(appearance) \(hue.rawValue): marks over the tint")
                    XCTAssertGreaterThanOrEqual(colors.glyphValue.contrastRatio(against: colors.baseValue), 3,
                                                "\(theme.name) \(appearance) \(hue.rawValue): marks on the tile")
                }
            }
        }
    }

    /// Letters drawn flat on a hue (avatars, completion kinds) pick white or near-black by the tile
    /// rule and reach 3:1 on every hue, theme and appearance.
    func testLettersOnFlatHuesReachThreeToOne() {
        let store = TestPack.store(registry: registry)
        let hues = LumenToken.hues + LumenAvatar.hues + [LumenToken.hueGraphite, .hueYellow]
        for theme in registry.galleryThemes {
            store.select(theme.id)
            for appearance in appearances where theme.supportedAppearances.contains(appearance.isDark) {
                for hue in hues {
                    let flat = LumenTileColors.flat(hue, appearance: appearance, store: store)
                    XCTAssertGreaterThanOrEqual(flat.ink.contrastRatio(against: flat.ground), 3,
                                                "\(theme.name) \(appearance) \(hue.rawValue): letter on the flat hue")
                }
            }
        }
    }

    /// Ref pill labels read at 4.5:1 on their tinted fill, and comparison capsules pick an ink that
    /// reads at 4.5:1 on their color, in every theme and appearance (HEAD measured 2.5:1, white on
    /// orange less than that).
    func testPillAndCapsuleTextReachesFourPointFive() {
        let store = TestPack.store(registry: registry)
        let kinds: [LumenRefKind] = [.head, .branch, .remote, .tag]
        for theme in registry.galleryThemes {
            store.select(theme.id)
            for appearance in appearances where theme.supportedAppearances.contains(appearance.isDark) {
                for kind in kinds {
                    let pill = LumenTileColors.pillText(kind.token, fillAlpha: LumenRefPill.fillAlpha, over: .bgCanvas,
                                                        appearance: appearance, store: store)
                    XCTAssertGreaterThanOrEqual(pill.ink.contrastRatio(against: pill.fill), 4.5,
                                                "\(theme.name) \(appearance) \(kind.token.rawValue): pill text")
                }
                for tone in [LumenToken.hueBlue, .hueOrange, .hueGreen, .hueViolet] {
                    let base = theme.color(tone, for: appearance, in: registry)
                    XCTAssertGreaterThanOrEqual(LumenTileColors.textInk(on: base).contrastRatio(against: base), 4.5,
                                                "\(theme.name) \(appearance) \(tone.rawValue): capsule text")
                }
            }
        }
    }

    /// Under Increase Contrast a dark tile's symbol reads at 4.5:1 and is never dimmer than on the
    /// standard dark tile (contrast-dark glyphs had looked dimmer than standard-dark).
    func testHighContrastDarkTileSymbolsAreAtLeastAsBright() {
        let store = TestPack.store(registry: registry)
        for theme in registry.galleryThemes where theme.supportedAppearances.contains(true) {
            store.select(theme.id)
            for hue in LumenToken.hues {
                let standard = LumenTileColors(hue: hue, appearance: LumenAppearance(isDark: true, isHighContrast: false), store: store)
                let high = LumenTileColors(hue: hue, appearance: LumenAppearance(isDark: true, isHighContrast: true), store: store)
                XCTAssertGreaterThanOrEqual(high.glyphValue.contrastRatio(against: high.baseValue), 4.5, "\(theme.name) \(hue.rawValue)")
                XCTAssertGreaterThanOrEqual(high.glyphValue.relativeLuminance + 0.0001, standard.glyphValue.relativeLuminance,
                                            "\(theme.name) \(hue.rawValue): dimmer under Increase Contrast")
            }
        }
    }

    /// On a selected history row, ref pills and avatars are drawn in `fgOnAccent` and read on the
    /// accent selection (a yellow tag or a violet avatar on violet didn't).
    func testSelectedHistoryRowPillsAndAvatarsReadOnTheAccent() {
        for theme in registry.galleryThemes {
            for appearance in appearances where theme.supportedAppearances.contains(appearance.isDark) {
                let accent = theme.color(.accent, for: appearance, in: registry)
                let onAccent = theme.color(.fgOnAccent, for: appearance, in: registry)
                let pillGround = onAccent.composited(alpha: LumenRefPill.onAccentFillAlpha, over: accent)
                XCTAssertGreaterThanOrEqual(onAccent.contrastRatio(against: pillGround), 3, "\(theme.name) \(appearance): pill text")
                XCTAssertGreaterThanOrEqual(accent.contrastRatio(against: onAccent), 3, "\(theme.name) \(appearance): avatar initial")
            }
        }
    }

    /// Glyphs drawn in text colors keep 3:1 between their marks and their 30% tint on the canvas.
    func testGlyphMarksStayReadableOverTheirTintInTextColors() {
        for theme in registry.galleryThemes {
            for appearance in appearances where theme.supportedAppearances.contains(appearance.isDark) {
                let canvas = theme.color(.bgCanvas, for: appearance, in: registry)
                for token in [LumenToken.fgPrimary, .fgSecondary, .fgTertiary, .accent] {
                    let ink = theme.color(token, for: appearance, in: registry)
                    let tint = ink.composited(alpha: LumenGlyph.tintOpacity, over: canvas)
                    XCTAssertGreaterThanOrEqual(ink.contrastRatio(against: tint), 3, "\(theme.name) \(appearance) \(token.rawValue)")
                }
            }
        }
    }

    func testSelectionGroupsStopAtTheirEndsAndTabCommandsWrap() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(LumenSelectionStep.next(ids, from: "b", by: 1), "c")
        XCTAssertEqual(LumenSelectionStep.next(ids, from: "c", by: 1), "c", "Groups stop at the end, as segmented controls do")
        XCTAssertEqual(LumenSelectionStep.next(ids, from: "a", by: -1), "a")
        XCTAssertEqual(LumenSelectionStep.next(ids, from: "c", by: 1, wraps: true), "a", "Previous/Next Tab wrap at the ends")
        XCTAssertEqual(LumenSelectionStep.next(ids, from: "a", by: -1, wraps: true), "c")
        XCTAssertEqual(LumenSelectionStep.next(ids, from: nil, by: 1), "a")
        XCTAssertEqual(LumenSelectionStep.next(Array(0..<10), from: 2, by: 5), 7, "Grids move by a row")
        XCTAssertNil(LumenSelectionStep.next([String](), from: nil, by: 1))
    }

    /// An app changes clashing shortcuts in one set, and the toggles and menu use it.
    func testAppsCanReplaceClashingShortcuts() {
        var shortcuts = LumenViewShortcuts.standard
        shortcuts.panel = KeyboardShortcut("y", modifiers: [.control, .command])
        shortcuts.commandPalette = nil
        XCTAssertEqual(shortcuts.shortcut(for: .bottom)?.modifiers, [.control, .command])
        XCTAssertEqual(shortcuts.shortcut(for: .leading)?.key, LumenShortcuts.navigator.key)
        XCTAssertNil(shortcuts.commandPalette)
        _ = LumenViewCommands(shortcuts: shortcuts, commandPalette: false, tabNavigation: false, sidebarFallback: false)
        _ = LumenPanelToggles(bottom: .constant(true), shortcuts: shortcuts, registersShortcuts: false)
        _ = LumenPanelTabs(selection: .constant("a"), tabs: [LumenPanelTab(id: "a", title: "A", systemImage: "circle")], labels: .selectedOnly)
    }

    /// Dragging can use all spare height, while the content minimum always wins.
    func testBottomPanelLimits() {
        typealias Container = LumenBottomPanelContainer<EmptyView, EmptyView>
        XCTAssertEqual(Container.maxPanelHeight(total: 680, minHeight: 120, contentMinHeight: 120, maxFraction: 1), 560)
        XCTAssertEqual(Container.maxPanelHeight(total: 680, minHeight: 120, contentMinHeight: 360, maxFraction: 0.25), 320)
        XCTAssertEqual(Container.maxPanelHeight(total: 1000, minHeight: 120, contentMinHeight: 360, maxFraction: 0.25), 640)
        XCTAssertNil(Container.maxPanelHeight(total: 400, minHeight: 120, contentMinHeight: 360, maxFraction: 0.25),
                     "The content keeps its minimum; the panel steps aside rather than shrink below usable")
        // The content minimum and panel minimum still apply independently of presentation caps.
        XCTAssertEqual(Container.maxPanelHeight(total: 480, minHeight: 48, contentMinHeight: 360, maxFraction: 0.25), 120)
        XCTAssertNil(Container.maxPanelHeight(total: 400, minHeight: 48, contentMinHeight: 360, maxFraction: 0.25))
        XCTAssertEqual(Container.maxPanelHeight(total: 1000, minHeight: 120, contentMinHeight: 360,
                                                maxFraction: 0.01, maximumHeight: 10), 640)
        XCTAssertNil(Container.maxPanelHeight(total: 400, minHeight: 120, contentMinHeight: 360,
                                              maxFraction: 1, maximumHeight: 900))
    }

    func testBottomPanelPresentationCapsDoNotLimitDragging() {
        typealias Container = LumenBottomPanelContainer<EmptyView, EmptyView>
        func shown(_ stored: CGFloat, dragged: Bool = false, fraction: CGFloat = 0.25,
                   maximum: CGFloat? = 360) -> CGFloat {
            Container.presentedPanelHeight(stored: stored, total: 1600, minHeight: 120,
                                           ceiling: 1240, maxFraction: fraction, maximumHeight: maximum,
                                           hasDragged: dragged)
        }
        XCTAssertEqual(shown(900), 360)
        XCTAssertEqual(shown(240), 240)
        XCTAssertEqual(shown(900, maximum: nil), 400)
        XCTAssertEqual(shown(900, fraction: 0.01, maximum: 10), 120)
        XCTAssertEqual(shown(900, dragged: true), 900)
        XCTAssertEqual(shown(1800, dragged: true), 1240)
        XCTAssertEqual(shown(900), 360, "A new presentation reapplies its cap to the stored height")
    }

    /// Lumen's shortcuts are distinct and stay clear of macOS's system and standard app shortcuts.
    func testShortcutsAreDistinctAndAvoidMacOSShortcuts() {
        let key = { (shortcut: KeyboardShortcut) in "\(shortcut.modifiers.rawValue)-\(shortcut.key.character)" }
        let ours = LumenShortcuts.all.map { key($0.shortcut) }
        XCTAssertEqual(Set(ours).count, ours.count, "No two Lumen commands share a shortcut")
        let reserved = (LumenShortcuts.systemReserved + LumenShortcuts.standardCommands).map(\.shortcut)
        let clashes = Set(ours).intersection(reserved.map(key))
        XCTAssertTrue(clashes.isEmpty, "Lumen shortcuts that clash with macOS: \(clashes)")
    }
}
