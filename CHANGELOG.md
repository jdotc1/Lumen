# Changelog

Lumen follows semantic versioning (see Docs/ARCHITECTURE.md › Versioning). Every release lists, for
the people moving an app's pin:

- **Breaking:** source changes an app must make.
- **Visual:** things that look or lay out differently with no code change (review snapshots, don't
  record them blind).
- **Validator:** new checks that run on an app's own themes and may flag them.
- **Added** and **Fixed.**

Apps pin exact commits; each release names its commit and tag.

## 1.4.0 (2026-11-13)

### Visual
- Every top-bar button is an app icon (design review 2026-11, note 24): the glyph centered on its own
  continuous-corner rounded square in app-icon proportions, drawn as one vector unit with a subtle
  elevation off the bar. This covers `LumenToolbarIconButtonStyle` (and so `LumenTaskCluster`, the
  sidebar toggle and app toolbar buttons), `LumenPanelToggle`, the New Tab button and Settings' Back
  and Forward. Review toolbar snapshots; Settings' Back and Forward are still native `NSButton`s.
- `LumenToolbarGroup` and `LumenPanelToggles` no longer draw a capsule behind their buttons: each
  button is its own icon, and a group reads as a group by its tighter spacing.
- The rich-text format bar uses pane icon buttons (`LumenPanelIconButtonStyle`): it sits inside the
  field, not on the window's top bar.
- No window offers a Drawn/Glass chrome switch; the Catalog's toggle is gone. The `.drawn` fallback
  for Reduce Transparency and offscreen rendering is unchanged.
- Design review 2026-11 fixes (findings 1–4, 6–9, 12–22): the main sidebar's top rows are no longer
  hidden under a titlebar band, the text scale applies live, segmented controls and Settings panes
  share one selection and leading edge, chart y-axis ticks no longer read as minus signs, form rows
  align on their baselines, and RTL disclosure chevrons mirror.

- Bar labels keep their natural width in every Lumen bar (toolbar, editor bar, header strip, panel
  bar, status bar, tab strip, palette footer). When items don't fit they fall back to icon-only
  (keeping their help and accessibility label) or to an overflow menu; only free text (titles,
  paths, file names) yields, by truncating in the middle with the full text as help. Stats, register
  values and graph details no longer shrink; a stats card stacks instead. Counts and chips hold one
  natural-width line with roomier padding. The status bar, top bar, content tabs, palette scopes and
  footer gained compact and overflow tiers before scrolling. Review bar snapshots.
- A toolbar status that can't show its whole label shows its mark (with the label as help) instead
  of disappearing. `LumenActivityStatus` truncates its label down to its readable width, then shows
  its mark. `LumenCount` pills reserve half their height at each end, so they are slightly wider.
- Bar text that used to wrap in its last fallback (a breadcrumb activity, a stacked sidebar pane
  header) stays on one line and truncates in the middle, with the full text as help.
- Catalog and sample text use neutral names (a binary inspector demo, sample workspaces and paths).

### Validator
- New layout-audit rules: `bar-label-squeezed`, `bar-label-clipped`, `bar-free-text-mode`,
  `bar-yield-order` and `bar-pill-proportions` (padding at least the cap height, horizontal padding
  at least vertical), plus a native toolbar check that a visible item is never narrower than its
  fitting size. The rendered audit adds `rendered-bar-squeeze` (owned ink narrower than 0.96 of the
  natural text width). Lumen's own bar components report their items.

### Added
- `LumenFlowLayout` gains `alignsColumns:`, so wrapped lines share their columns; the 1.3
  initializer `init(spacing:lineSpacing:)` is kept.
- `LumenBarItemReport`, `LumenBarItemKey` and `.lumenBarItem(_:bar:role:mode:fontSize:pillInsets:)`:
  an app's own bar items report their natural and allocated size so the bar rules can check them.
- `LumenToolbarIcon`: the app-icon toolbar button drawing, for apps that build their own controls.
- `LumenToolbarIconMenu`: a toolbar pull-down drawn as a toolbar icon. A SwiftUI `Menu` in a toolbar
  becomes the system's menu item, which ignores button styles and draws a bare glyph with a chevron.
- `LumenMetadataRow`: a label and a selectable value that wraps at any character (hashes, paths,
  bundle IDs, long hex) and never truncates. It follows the Lumen text scale, mirrors in right-to-left
  layouts, lines up with `LumenPropertyRow`'s label column and keeps the exact string for copying.
- `LumenSelectableText`: read-only, selectable text for large content (reports, dumps), backed by a
  native text view with non-contiguous layout. `LumenTextHighlight` marks exact `NSRange` or
  `String.Index` ranges (`.match` on `accent.subtle`, `.current` with an accent underline), and
  `LumenTextReveal` scrolls a range into view. Ranges are clamped and never split a character. A
  `pages:` initializer and `offset(ofPage:in:separator:)` cover paged content.
- `View.lumenExactText(_:)`: text fields inside it keep exactly what is typed or pasted, for
  entitlement keys, identifiers and hex. Smart quotes and dashes, text replacement, spelling and
  grammar correction, link detection, completion, inline prediction, Writing Tools and smart
  insert/delete are all off. The shared field editor is restored when editing moves to another field.
- `.lumenRoot(tint:appearance:windowChrome:)` and `LumenRootAppearance`: an app with no
  `LumenThemeStore` sets the Lumen accent and light, dark or system appearance with one modifier at
  its root. Accent roles are derived from the tint with the system accent's contrast rules.
  `\.lumenRootTint`, `LumenThemeStore.resolvedPalette(tint:)` and `LumenPaletteKey.tint` expose the
  same to store-backed apps, which are unchanged when no tint is set. See
  `Docs/adoption/minimal-palette.md`.
- `LumenProportionalSplit`: a two-pane split (top over bottom, or side by side) whose panes keep
  their ratio as the window resizes. Its divider can be dragged, moved from the keyboard and adjusted
  with VoiceOver. Each pane has a minimum size, and the app persists the `ratio` binding with
  `@AppStorage` or `@SceneStorage`. See `Docs/reference/proportional-split.md`.

### Fixed
- `LumenStatusBar` fills its width again in its full and icon-only tiers, so a `Spacer` pushes
  trailing items to the trailing edge instead of centering the whole bar.
- `LumenComparisonHeader` keeps both side capsules at their natural width at the leading edge of
  their halves instead of stretching and centering them, and its secondary detail wraps to two caption
  lines before it truncates, instead of dropping out.
- `LumenHexDump` draws a selected byte run as one continuous band again; each selected byte had
  picked up a rounded shape of its own.
- The layout audit's content-bounds and ancestor-clip messages name the element's kind and frame.
- `LumenSelectableText` shows its find indicator only in a visible window; in an offscreen window
  it opened an overlay window of its own.
- `LumenStatusStrip` keeps its leading text at full width whenever the strip has room; the
  middle's spacer had taken that room, so the leading text vanished even in a wide pane. When
  narrow, the leading text still shortens first, before the chips fold.
- The rendered bar-squeeze check compares measured ink with the label's glyph ink, not its advance,
  so a short label such as a count is no longer reported as squeezed.
- The rendered text-geometry check treats text that recognition reads across adjacent segments of
  one native control (a segmented picker's labels and divider) as owned by that control, not as one
  segment's text crossing its boundary. The rendered-overlap check likewise treats a segmented
  control's bezel (one connected shape across its segments in dark mode) as owned by the control.
- The rendered truncation differential no longer reports two complete button labels that recognition
  merges at the larger layout when their recognition boxes overlap by a few points or a capsule edge
  between them reads as a lone bar glyph.

### Deprecated
- `lumenNeverTruncates(_:minimumScale:)`: keep labels at their natural size and use a compact or
  overflow presentation instead.

## 1.3.0 (2026-11-12)

### Visual
- Toolbar glass bubbles are gone in both chrome styles: `lumenToolbarPlatter(_:)` always hides the system platter, and `.lumenSidebarToggle(columnVisibility:)` always replaces the system toggle with the bare outline button. Command palette and toast glass are unchanged.

### Added
- `LumenSourceListItem.isEnabled` and `.enabled(_:)`: a source-list item can be shown but not selectable.
  `LumenSourceList` dims it, ignores clicks on it, and ↑/↓/Home/End skip it. Existing items are enabled.
- `LumenDropZone.intrinsicHeight(_:)`: the zone at its content's height instead of filling the offered
  height, for a zone inside a stack or list. The default still fills.

### Fixed
- The rendered audit resolved a full-bleed pigment under the app-wide appearance, so a dark window's
  sidebar read as ink; it now resolves under the window's own appearance.
- The rendered audit now finds text or a control that is cut off by a window or clip edge, text that
  collides with an image or control that covers it, and light text on a dark background that the
  accurate OCR model alone missed. The Welcome starfield draws nothing in offscreen captures, so the
  audit measures layout rather than decorative stars.

## 1.2.0 (2026-11-12)

### Added
- `View.lumenEnvironmentDensityRoot()`: a density root that follows the store in `\.lumenStore`, for a
  window or subtree with a store of its own. Apply it before (inside) the palette root or
  `.environment(\.lumenStore, _)`; modifiers added later are outer, and the environment flows inward.
- `LumenThemeEditor(basedOn:editsInPlace:)`: an editor that edits in the environment's store at render
  time. A different store in the environment starts a fresh editing session.
- Doc comments on the palette and density roots state the ordering rule (a root reads only what is
  above it), and `LumenStoreConfiguration.defaultsSuiteName` documents the bundle-identifier case.

### Fixed
- **Settings:** the Back and Forward history buttons now announce distinct accessible names to
  VoiceOver and other accessibility clients (both read "Back" before).

## 1.1.1 (2026-11-12)

### Fixed
- **Debug builds no longer crash at launch on macOS 27.3.** The Debug-only layout-audit observer that
  `LumenThemeStore.install` starts read SwiftUI accessibility labels as `String`. SwiftUI can answer
  with an `NSAttributedString`, and the bridge raised an Objective-C exception inside a main-actor
  task. Any Debug build that installed a store could crash; Release builds do not run the observer.
  The window checks in `LumenConformance` share that audit code and read labels the same way now.
- `lumenPaletteRoot` no longer reports its content's zero-width (fully stacked) height as its minimum
  at every width, which made conformance overflow checks and `fittingSize` measure inspectors and page
  headers too tall. The root now floors and places its content at the minimum for the proposed width.
- **Settings:** windows always use one unified toolbar row, even without a palette root or
  `lumenSettingsScene()`, and `lumenPreservesExpandedToolbar(true)` does not change that. The category
  sidebar is always visible: there is no sidebar toggle, the divider cannot collapse it, and
  View > Toggle Sidebar cannot collapse it either, nor resize the window. Back/Forward hugs its two
  buttons. A pane wider than its 640 pt measure is centred in every width class, not only above 820 pt.
- `LumenMenuBarPanel` draws its text with the environment's palette, so a panel under a second
  store's `lumenPaletteRoot(store:)` uses that store's colors. The doc comments on `.lumen(_:)`,
  `Lumen.palette`, `Lumen.theme(for:)`, `lumenDensityRoot`, `LumenThemeEditor` and
  `LumenThemeGallery(store:)` now say that they read the active store and name the alternative.
- A `LumenStoreConfiguration.defaultsSuiteName` equal to the app's bundle identifier now resolves to
  the standard defaults, so apps no longer get Foundation's launch warning about using the app's own
  bundle identifier as an `NSUserDefaults` suite name. The Catalog follows the same rule.

### Visual
- Settings windows lose the sidebar toggle (the `lumen.settings.sidebar` toolbar item), put the
  history buttons and title at the leading edge of one toolbar row, and centre the pane when the
  window is wider than the pane's measure. Review the Settings snapshots; don't record them blind.

### Validator
- `LumenConformance.surfaceSteps` no longer reports a shape enclosed by one ground that is no larger
  than a row icon tile (`tileRowDetailed`, 26 pt at standard metrics) in either direction, so tile
  plates close to the ground, such as Midnight's, no longer need an exclusion. It reports fewer
  findings and no new ones.

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
