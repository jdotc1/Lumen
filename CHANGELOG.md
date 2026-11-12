# Changelog

Public releases of the Lumen design system and Catalog.

## 1.1.0 (2026-11-12)

### Added
- **About-panel credit links:** `LumenAboutCredit(name:url:)`, with `credits: [LumenAboutCredit]`
  and an optional `creditsHeading:` on `LumenAboutPanel.options`, `LumenAboutPanel.show` and
  `LumenAboutCommands`. Each credit is its own line; one with a URL is a clickable link. The
  string `credits:` overloads are unchanged.

## 1.0.0 (2026-11-12)

### Breaking
This is the 1.0 bundle. It lists exactly these changes. `Scripts/api-check.sh` against
0.63.0 reports 13 digester findings in LumenUI and none in LumenTokens, LumenIntents or
LumenConformance; the findings below account for all of them.

- **One `LumenAction` with a `Role` (`.bar`, `.welcome`, `.hero`)** replaces the two action models.
  `LumenBarAction` and `LumenWelcomeAction` stay as aliases of it, and both initializer shapes still
  compile, so call sites need no change. `systemImage` is now optional on the type; code that read
  `LumenWelcomeAction.systemImage` as a non-optional `String` must unwrap it.
- **`LumenEmptyState` takes `link: LumenAction?`** in place of `actionTitle:`/`action:`, and
  `lumenInspectorEmptyState` follows the same shape. The deprecated `actionTitle:`/`action:`
  overloads are removed; pass `link: LumenAction("Title") { … }`.
- **`LumenItemCard` and `LumenDetailHeader` default to `.hueBlue`** instead of `.accent`. Pass
  `hue: .accent` for the previous look.
- **`Lumen.color(_:)` and `Lumen.nsColor(_:)` are removed.** Read the palette from
  `@Environment(\.lumenPalette)`, or `store.color(_:)` from a store you hold.
- **Removed deprecated members:** `LumenSettingsSidebarView.stableContentHeight`,
  `LumenSettingsSidebarView.windowMaxHeight` and `LumenToolbarStatus.init(_:idealWidth:minWidth:)`.
- **Theme `schemaVersion` 2 is the default write format.** A theme made in code, and every built-in
  theme in `builtin-themes.json`, now writes `"schemaVersion": 2`. A version-1 file you load keeps
  version 1 and round-trips byte for byte until you add metrics to it. Tools that insist on
  version 1 must accept 2.
- **Platform floor:** macOS 27 (D9), unchanged since 0.57; recorded here as the 1.0 floor.
- **`LumenConformance` static functions** stay as wrappers over the `LumenCheck` types, which run
  the same code; they are not removed in 1.0 (they stay in 1.0).

### Fixed
- `LumenBanner` wraps its message and drops its action to its own line when narrow, instead of
  exceeding the proposed width; `lumenWrapsWithoutTruncating(minimumMeasureWidth:)` lets a view
  choose its measuring floor.
- The `welcome-panel` goldens match the flat icon tiles every other golden already shows.
- Pill-shaped tab chrome draws true semicircular ends; a continuous full-radius corner flattens into a
  squircle on macOS 27.
- Rich-text format buttons are icon-only toolbar buttons with a tooltip and an accessibility title.
- Snapshots pin the icon appearance, so goldens no longer vary with the Mac's icon style setting.

### Known issues
- The live-window audit tests in `LumenAuditProductionCompositionTests` (sidebar wash, split sidebar,
  transparent helper divider, workspace band) report off-screen edge slivers on macOS 27. They fail
  identically on 0.63.0's parent commit, so they are not a regression; the render-based checks pass.

### Changed
- **Visual:** `LumenChromeStyle.glass` is now the default chrome style (`LumenStoreConfiguration.chromeStyle`, `LumenChromeStyle.resolve`, the Catalog's saved default). Apps that want the previous look set `chromeStyle: .drawn`. Offscreen renders and Reduce Transparency still draw `.drawn`, so goldens are unchanged.

## 0.63.0 (2026-11-05)

### Added
- Tests proving a Settings window hosted without `.lumenSettingsScene()` still gets one unified toolbar row with adjacent Back/Forward, plus gated proof renders and an audit test for two-row Settings chrome.
- Gated offscreen review gallery of current UI and documented text proportion guarantees for bounded grounds.
- English source string catalog for package-owned interface labels, prompts, help and default text.
- Headless pseudo-localization checks with expanded text and right-to-left layout.

### Changed
- Package interface text resolves from its module bundle; caller-supplied text keeps its existing behavior.
- Directional controls and workspace chrome follow leading and trailing layout.

### Fixed
- Mirror directional dragging, disclosure glyphs and overflow indicators in right-to-left interfaces.
- Preserve left-to-right ordering for source code, addresses and hexadecimal data.

## 0.62.2 (2026-11-04)

### Fixed
- Bottom panels scroll rigid content that exceeds their height while preserving panel state and nested scrolling.
- Let bottom panels resize to the height available above the content minimum.
- Apply fractional and absolute height caps on presentation while allowing subsequent dragging beyond them.

## 0.62.1 (2026-10-26)

### Fixed
- Keep native sidebar material full-height behind the titlebar across settings and window scaffolds.
- Use the accent focus ring across text, number, search and address fields; align Settings control wells and fills.
- Omit the native text ownership reporter during offscreen rendering while preserving live-window reporting.
- Refresh workspace goldens for the system icon tile appearance.

## 0.62.0 (2026-10-26)

- Settings windows match macOS System Settings with one unified toolbar row, a full-height sidebar, and accent selection.
- Shared window chrome guarantees consistent native geometry for app-built windows.
- Icon tiles follow the system icon appearance.
- Framed symbols use sizing that preserves their artwork within icon tiles.
- New settings form rows provide labeled text and numeric fields, status, empty states, and trailing actions.

## 0.61.0 (2026-10-24)

- Theme tokens, scoped stores, editable color and depth metrics, validated theme files, and command-line theme exchange.
- Consistent controls, rich text, tables, charts, source lists, inspectors, developer tools, and feedback surfaces.
- Workspace, document, utility, library, welcome, wizard, settings, and menu-bar window compositions with native macOS 27 chrome.
- Shared text scale, density, container-relative corners, window activity, and drawn or glass appearance.
- Layout conformance checks identify clipped text, overlapping content, insufficient margins, and drawing outside native boundaries. Offscreen test hosting preserves the embedding application's activation policy.
- The Catalog demonstrates components and complete sample windows using synthetic data.

## 0.60.0 (2026-10-23)

- Added application text scaling and density-aware control sizing.
- Added themed bar and line charts, histograms computed from observations, legends, and empty states.
- Added utility-window composition with responsive sidebars and inspectors, plus window-structure checks.

## 0.59.0 (2026-10-23)

- Added theme schema 2 with inherited metrics, depth, and configurable locks.
- Added theme editing with undo, contrast fixes, seed generation, DTCG exchange, CSS export, and command-line comparisons.
- Added window-owned toast notifications and searchable keyboard shortcuts.

## 0.58.0 (2026-10-23)

- Raised the minimum deployment target to macOS 27.
- Added complete settings-window composition, native activity handling, and container-relative corners.
- Added configurable native menu image visibility.

## 0.57.0 (2026-10-23)

- Added scoped theme stores, extensible conformance checks, and drawn or glass chrome.
- Improved toolbar sizing, sidebar toggles, and command-palette scrolling.
- Deprecated global color lookup in favor of the current environment or an explicit store.

## 0.56.2 (2026-10-18)

- Improved quiet-button sizing and hex-dump scrolling.
- Improved native split-view sizing on supported systems.

## 0.56.1 (2026-10-17)

- Corrected hidden-region appearance checks and accent derivation naming.

## 0.56.0 (2026-10-16)

- Added an optional maximum height for bottom panels.
- Improved inspector sizing during split-view measurement.
