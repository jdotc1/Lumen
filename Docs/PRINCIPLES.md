# Lumen principles

Lumen makes Mac apps that behave exactly like Mac apps and still have character. Its design
principles draw on Simon Lou's thesis on opinionated, expressive, Mac-assed design.

## 1. Compatible with macOS, drawn by Lumen

Lumen separates **behavior** (structure, hierarchy, interaction, system features) from **look**
(color, iconography, typography, shape, motion, microcopy). Behavior must match macOS. The look is
Lumen's, within the standard-element requirement below.
Standard macOS elements (tabs, tab bars, segmented pickers, selection highlights) conform to macOS 27.

| Must work as macOS does | Lumen draws it |
|---|---|
| Windows, the menu bar, context menus and submenus | Icon tiles and colored symbols inside those menus |
| Keyboard shortcuts (⌘N, ⌘, …) and how menus show them | Keycaps in Lumen's own panels (the command menu and launcher are panels, not menus) |
| A separate Settings window (⌘,), changes applied at once | Tiled category tabs and pane headers |
| Controls: keyboard operation, focus, help tags, light/dark, Increase Contrast, Reduce Motion | The controls themselves on Lumen surfaces: checkbox, radio, switch, pop-up, field, slider, mode switcher, tab view |
| Undo, selection, drag and drop, persistence | Selection, focus and motion in the theme's terms (§10) |
| Sidebar, inspector and toolbar hierarchy; key and inactive windows; show/hide shortcuts | Theme-driven chrome, a title bar that glows while active, toggles that draw their region |
| SF Symbols, their grid, weights and template behavior | Lumen glyphs for what SF Symbols lacks, built as custom SF Symbols |

A departure from Mac *behavior* costs people relearning, so Lumen doesn't make one. A departure
from the native *look* outside those standard elements is fine when it's better.

## 2. Expressive enough to create identity, restrained enough to stay legible

- **Color carries meaning first.** Status, evidence and kind colors mean one thing each. The hue
  family (`hue.*`) is for categories and navigation. Saturated color goes on small things (tiles,
  marks, dots); large surfaces stay calm.
- **Keep signifiers.** Interactive things look interactive: carrier shapes, clear focus, real
  contrast. Depth shows hierarchy (a menu above a window), not decoration.
- **Every color is checked.** Text, glyphs, focus rings and categories each have a contrast or
  distinctness rule. A theme that breaks one is told exactly what to fix.

## 3. Personality at the edges, density at the center

Working surfaces stay dense and quiet: the listing, the table, the editor. Personality belongs at
the edges: the welcome window, empty states, icon tiles, Settings. Editors stay plain; welcome surfaces can use an animated starfield.

## 4. Play is useful

Small delights that never get in the way: a tile with a soft top highlight, a menu that opens with
care, an empty state written by a person. Reduce Motion turns animation off. Increase Contrast
gets its own palettes in the standard theme; other themes fall back to their own values.

## 5. One system, many apps

- An app keeps Lumen's language, or brands it through themes, metrics and its own pack. It never
  forks components.
- Each app's purpose shapes its expression: an analysis tool and a journal should not look the same.
- Themes are data. People can share them, edit them, and check them with Lumen's validator.

## 6. Nothing is ever cut off

No window can be resized small enough to clip its content. SwiftUI centers content wider than its
space, cutting off both edges, so Lumen prevents it at the source:

- Every column declares the least width its content needs: the sidebar with
  `navigationSplitViewColumnWidth(min:)`, the inspector through `.lumenInspector`
  (`LumenLayout.inspectorColumn`), the content column with `.frame(minWidth:)`. A window's minimum
  width is the sum of its noncollapsing columns' minimums.
- Content adapts before it reaches its minimum: rows of controls fold (`ViewThatFits`), chips become
  a menu, grids reflow, previews scale down, tab strips scroll. Nothing is hidden to fit.
- Scrolling tab strips fade every edge with hidden content over 24 pt, leaving the overflow
  chevron outside the fade. An unfaded hard clip at a scroll edge is a hidden-truncation finding,
  even if the tab has a full title or is reachable through the overflow menu. No hidden content
  means no fade.
- Tests prove it: `LumenLayout.minimumWidth(of:)` measures the narrowest width a view lays out at,
  and each column's content must fit its minimum (`Tests/LumenCatalogTests`).
- Column overflow is checked too: content wider than its column is shifted, not truncated, so a
  truncation check alone misses it. Every Lumen column (inspector, workspace regions, split-view
  columns and panes, stacked panes, sheet content) reports it, and `LumenConformance.overflow`,
  `.truncation` and `.workspaceWindow` fail on it. Mark an app's own column with
  `.lumenColumnContent(_:)`; mark content inside an app's own scroll view, too.
- Narrow sizing is checked too: a split view sizing its columns measures content at a near-zero
  width, and text that wraps without truncating answers with its height wrapped a few letters per
  line, a minimum taller than the window (0.51.1: the Workspace window drew a blank body). Wrap such
  text with `.lumenWrapsWithoutTruncating()`, never bare `.fixedSize(horizontal: false, vertical:
  true)`; `LumenConformance.narrowSizing` fails on a view that balloons when measured 1 pt wide.

Settings measures every category at its initial pane width and uses the tallest natural height,
including its header, sections and bottom inset, for the initial window size. The content height
has a 480 pt floor and a screen-visible-height cap with a margin (720 pt when no screen is
available); category changes do not resize the window, and taller panes scroll above a real bottom
inset. A host can supply its preferred size with `.lumenSettingsPreferredSize(_:)`; users can grow
the window through `.contentMinSize` resizing. Each pane classifies its own width as compact below
560 pt, regular from 560 through 820 pt, or wide above 820 pt. Compact rows stack their controls;
wide panes keep a shared readable measure of about 640 pt with balanced surrounding space.
Horizontal padding, section separation, grouped-control insets and row rhythm use metrics tokens,
with compact, regular and comfortable density remaining distinct.

## 7. Icons are sized by role and drawn to be read

- A pane's header tile sets the scale (`tileHeader`, `tileInspectorHeader`). A tile that is a whole
  control, such as a tool switcher, is the same size (`tileTool`). Section headers use
  `tileSection`. A tile beside its text is never under 16 pt.
- Unselected tiles keep their full color; the plate behind marks the selection. Fading a tile makes
  it read as smaller and disabled.
- Glyphs under 24 pt draw line work and solid marks only (`LumenGlyph.tintMinimumSize`).
- **Drop shadows come only from `LumenElevation`** (floating menus, popovers). The app icon's
  artwork is the one exception. A glow is light, not depth: `lumenGlow(.hero)` behind a welcome
  tile, `.selection` on a selected graph node.
- **Tile backlight stays inside its strip.** Tile rows (the sidebar switcher, mode tiles) glow
  softly from their tiles, contained so the glow never crosses a hairline. No backlight in the
  toolbar or top bar, where it could only clip.
- Tiles report themselves when undersized for their role (`.lumenIconRole(.control)` marks an app's
  own), and `LumenConformance.iconScale` and `.workspaceWindow` fail on any report.
- An icon-only control keeps a full hit area, at least `minimumHitTarget` (24 pt) on each side.
  Mark it with `.lumenIconOnlyControl()` (Lumen's own are marked, as is every
  `LumenToolbarIconButtonStyle` button) and it reports itself when undersized. A titled button
  shown as an icon uses `.labelStyle(.iconOnly)`. A source scan fails on an unmarked bare-icon
  `Button`; its allow-list names the known undersized ones until they're fixed.

## 8. One surface per pane

A pane is one surface. Its column header, gutter, rulers and listing share the pane's background,
separated by hairlines, and a band (a section header, the current line, a selection) runs the
pane's full width. An inset band or a tinted gutter makes edges start at different x, and the
background steps like a staircase. `LumenConformance.surfaceSteps` renders a pane in a real
offscreen window and fails where two flat background colors meet at a vertical edge inside it
(color steps of 2 to 60). `headerHeight:` also fails a column header whose surface differs from the
pane's (opt-in: a full-width band of its own color is legal). Smooth gradients aren't detected.

**In dark, grounds step up as they nest.** A well (a field, a stat cell, a list box, a console
input) is lighter than the surface holding it: `bg.inset` is a step above the canvas,
`bg.insetRaised` a step above `bg.elevated`. Cards, popovers, sheets and menus apply
`.lumenRaisedGround()`, so the components inside take the raised well; apply it to a custom card.
Light is exempt. The validator's `LumenLiftRule` fails a dark theme whose wells sit darker than
their ground.

## 9. One top bar row, on the window buttons' line

A workspace window's top bar is one compact row. **Every item sits on the window
buttons' center line**, with no empty title strip above and no band below. The bar is native:
`LumenWorkspaceWindow` and `.lumenTopBar` (`LumenTopBarPlacement.unified`, the default) hand their
content to the window's toolbar, and `.windowToolbarStyle(.unifiedCompact(showsTitle: false))` on
the scene makes AppKit size the band (40 pt on macOS 27), center the items, and handle clicks,
dragging and double-click. Lumen hides the toolbar's background and draws its glow behind it. Don't
wrap toolbar items in stacks or padding that shift them off the line. `.underTitleBar` keeps the
older 44 pt SwiftUI bar under the buttons for an app that isn't ready to move.

The toolbar's leading-to-trailing order is:

1. **App mark** (20 pt tile; opens the launcher), a slash (`LumenToolbarDivider`).
2. **Project**: a 20 pt tile, the name in 13 pt semibold over the branch or location in 11 pt
   (`LumenToolbarIdentity` takes these sizes in the toolbar); it opens the project's settings.
   Then a slash.
3. **Tasks**: build, run, stop (`LumenTaskCluster`, glyphs at the toolbar glyph size, optically
   matched), in full color: build in its hue, run green, stop red. Build and run stay colored but
   dimmed when they don't apply; stop is gray while nothing runs. Then the task configuration
   pop-up. (`LumenWorkspaceToolbar` arranges 1–3.)
4. **Status**, temporary: a slash and the activity capsule while work runs or just finished;
   nothing while idle (`LumenToolbarStatus`). It gives way first: it narrows to the room left and
   hides when its label wouldn't fit whole.
5. At the trailing edge, the **panel toggles** and **New Tab** (`LumenNewItemButton`). Never dropped.

Editor tabs and modes live in the content pane's own tab bar (`LumenContentTabBar`), on the pane's
surface (§8). `LumenConformance.workspaceWindow` checks the real window: the band starts at the
window's top edge with the buttons centered in it, the window has a toolbar, every item's center is
on the buttons' center line (±1 pt) and none reaches under the buttons, the leading group and the
panel toggles are never dropped (the status may give way), and no panel starts under the band.

**Adaptive window regions:** when space runs short, collapse the inspector first, then the sidebar;
content never collapses, and the window minimum is the content minimum. Restore automatically in
reverse order when space returns. Explicit toggle, menu or binding choices persist: an explicitly
hidden region never auto-restores; an explicitly shown region collapses after automatic regions,
but still before content clips. Bound state is explicit, and resizing never overwrites intent.
Equal-priority regions retain inspector-first order. Later archetypes reuse this rule.

## 10. One look per role

**Selection** has five families, each with one look:

| Family | Look |
|---|---|
| Navigation lists and tables (source lists, sidebars, `LumenTable`) | Quiet: `bg.selected` (inactive: `bg.selectedInactive`); in a sidebar, `sidebar.rowSelected` (inactive: `sidebar.rowSelectedInactive`), which fall back to them. Across sidebars, selected titles are semi-bold in active and inactive windows; reserve their semi-bold width so selection never shifts text. Subtitles and count badges keep their normal weight |
| Menus, pickers, command results, completion, master-detail lists, history rows, collections and filter chips | Filled: `accent.filled` under `accent.filledForeground` (white); rows inset with `radius.sm` |
| Tabs and segmented pickers (document and panel tabs, mode switchers, tabbed boxes, palette scopes) | Shared continuous rounded chrome: `tab.activeFill` for document tabs, `bg.elevated` for panel and segmented selections, `border.subtle` hairline, and `bg.hover` for hover; optional document accent stays a subtle pill tint. `radius.md` scales with control height; inactive windows dim the chrome |
| Tool tiles | A plate behind the selected item |
| Code rows (listings, hex) | A full-width band with an accent bar |

Sidebar hit areas and scroll regions reach the window and column edges on macOS 27. Visible row selections remain inset, in a `radius.sm` continuous rectangle; padding belongs inside the full-width hit area.

**One filled-accent look.** Every filled accent shape (primary buttons, checked checkboxes and
radios, a switch that's on, selected chips, filled selections) uses `accent.filled` with white text
and glyphs: in dark a deep tone of the accent. The bright `accent` is for lines, glyphs, links,
tints and focus only, never a fill under dark text. Keycaps on a filled row turn to light outlines.

**One-line controls are 24 pt** (`metrics.layout.controlHeight`) with 13 pt text
(`typography.body`): text, search, combo, number, address, find, command and filter fields,
pop-ups, pull-downs, push buttons, and the pill switcher overall. Toolbar icon buttons stay 28 pt.

**Chips:** badges, pills, tags and every in-component chip share one spec: captionEmphasized in a
`radius.sm` continuous rect, `s3` across and `s1` above and below.

**Labels:** section group labels and table column headers share one uppercase, tracked small style
(`typography.sectionLabel`, one tracking, `fg.tertiary` or the surface's secondary foreground).
Tile sections keep Title Case titles. Tags and badges are sentence case.

**Status glyphs:** error and danger are an xmark in an octagon (`xmark.octagon.fill`, in
`status.danger`: error states, console and debugger markers, status chips, banners), warning a
triangle (`exclamationmark.triangle.fill`, in `status.warning`).

## 11. Glass

macOS 27 draws the system's chrome in Liquid Glass. Lumen treats glass as both a look and a
behavior (§1): Reduce Transparency, Increase Contrast and the transparency slider govern it. The
policy is [GLASS.md](GLASS.md); this is its summary.

- **Two layers.** The navigation layer (the window toolbar's background, the unified top bar's
  band, the sidebar edge, floating palettes such as ⌘K and the input palette, transient toast stacks, popovers) may use
  system glass. The content layer (lists, tables, cards, editors, inspectors, sheets, settings
  panes, status bars, menus) never does.
- **No glass on glass.** One glass surface along any line of sight: a palette over a glass toolbar
  is one glass sheet with opaque rows; a popover over it is the system's popover and Lumen adds
  none.
- **Tint only primary actions.** Glass carries the palette's foreground; `.tint(palette.accent)`
  goes on the one primary action, as in `.drawn`.
- **Contrast is measured against the opaque fallback.** Every foreground on a glass surface meets
  its rule against the token the drawn chrome paints there (`toolbar.background`,
  `menu.background`, `sidebar.background`). The blur may add legibility, never supply it, so
  Reduce Transparency and the slider can only make a surface more readable.
- **The drawn chrome is the reference.** `LumenChromeStyle.drawn` is the default through 0.x
: goldens, the validator and the Catalog's pages are recorded in it. `.glass` is
  opt-in per store (`LumenStoreConfiguration.chromeStyle`) or per subtree
  (`.lumenChromeStyle(.glass)`), draws as `.drawn` under Reduce Transparency and
  in offscreen renders, and changes no token, metric, keyboard behavior, focus or selection.

## 12. A window component ships as a whole window

A settings window, workspace or other component intended to be a window's root owns its chrome:
toolbar style and items, sidebar list style, palette surfaces, title placement and frame. If a
native behavior can only be configured on the Scene, Lumen supplies a companion Scene helper and
the integration example includes it. An app supplies its content and state; it must not need to rebuild
the root from tiles, rows and headers to obtain the intended window.

**A window component owns the native window geometry.** Toolbar height, sidebar toggle size,
window title placement, window sizing and scene tint remain coherent with sparse and populated
content in both `.drawn` and `.glass` chrome. The Catalog demonstrates these properties in
real windows as well as component previews.

**Settings has one chrome title rule.** The selected category is the native navigation title beside
the Back/Forward group. Never add another category title as a toolbar item or leave it floating
alone in an empty band. The pane retains its own tile, title and summary: that header introduces
the content, while the navigation title identifies the current destination. Back/Forward and the
sidebar toggle have matching control sizes. There is exactly one icon-only sidebar-toggle item
in the actual native toolbar, no labeled “Sidebar” item and no principal “Settings” text. Measure
the combined titlebar/toolbar height against the system's unified-style reference; a compact-style
modifier alone is not proof of compact geometry.

### Settings composition

`LumenSettingsSidebarView` and its Scene helper own the complete settings composition:
sidebar list style and surfaces, search prompt, selection history, balanced split, stable
frame and scene chrome. Toolbar item ownership and removal scope follow the native window's
items and geometry. Sparse categories use a proportionate stable content height; trailing
row controls stay within a bounded measure.

## Checklist for a new component

1. Which Mac behavior does it touch? Match it (keyboard, focus, menus, appearance).
2. How does it look? Express that only through tokens (`LumenToken`) and metrics
   (`LumenMetrics`), so every app and theme can restyle it, and in the role's look (§10).
3. Which colors carry text or meaning? Give each one a contrast or distinctness rule.
4. Does it read in light, dark, Increase Contrast and Reduce Motion?
5. Add a golden image (or a Catalog page, for native controls that can't render offscreen). A window
   root also requires real Catalog window captures and live-window checks (§12).
6. What's the narrowest it can be? Make it adapt down to that width, and test it with
   `LumenLayout.minimumWidth(of:)`.
7. Does it draw a ground? Then it is content and never glass, unless [GLASS.md](GLASS.md) lists
   it in the navigation layer; only there does it read `\.lumenResolvedChromeStyle` (§11).
8. Does it wrap an app's view? Keep that view in one branch whatever the motion, scale or theme
   policy, never override an app's own setting with `false`, and test a policy flip in one host.

### Hero and welcome actions

`LumenBarAction` describes a compact action:
optional glyph, enabled state, help and an accessibility identifier. A hero supplies its primary
and secondary placement. `LumenWelcomeAction` describes a welcome tile: subtitle, hue, keyboard
shortcut and primary emphasis, with a main-actor action. These are distinct capabilities, not
interchangeable aliases. Reusing their visual parts does not require replacing either public model.

Any common action model must specify enabled state, help, accessibility identifiers, shortcuts,
subtitles and actor isolation for both presentations. Preserve existing initializer signatures and
call-site inference during any migration; do not replace the hero initializer in a polish release.
