# Glass policy

macOS 27 draws the system's chrome in Liquid Glass: toolbar platters, sidebars, popovers,
menus and the floating controls over content. Lumen's §1 separates behavior (must match macOS)
from look (Lumen's). Glass is both: a look, and a system behavior that reacts to Reduce
Transparency, Increase Contrast and, on 27, the user's transparency slider. This document is the
policy for it. PRINCIPLES §11 is its summary.

## Policy overview

The drawn chrome is the reference and the default. A Lumen app may opt into system glass for its
navigation layer, and only there, through one switch (`LumenChromeStyle.glass`). Content never
uses glass. Both styles use the same tokens, metrics, keyboard behavior, focus and selection, so a
theme and a component never know which one is drawing. Contrast is measured against the opaque
fallback, so the blur can add legibility but never supply it.

## Two layers

| Layer | Surfaces | Glass? |
|---|---|---|
| Navigation | The window toolbar's background (the system platter under toolbar items), the unified top bar's band, the sidebar edge, floating palettes (the ⌘K command palette, the input palette), transient toast stacks, popovers | May use system glass under `.glass` |
| Content | Lists, source lists and sidebar rows, tables, cards and tiles, editors and code views, inspectors, sheets and their bodies, settings panes, status bars, banners, menus (the command menu, context menus, pop-ups) | Never |

The content layer needs a stable, measured ground: the contrast rules (§2, §3) are checked
against tokens, and a surface that changes with what scrolls under it or with a slider cannot be
checked. Menus are dense text over a list: glass under them is glass under content.

## Rules

1. **No glass on glass.** One glass surface at a time along any line of sight. A popover over a
   glass toolbar is the system's popover; a palette over a glass toolbar is one glass sheet with
   opaque rows inside it. Lumen never applies `glassEffect` to a view that sits inside a surface
   that already has it, and never stacks `GlassEffectContainer`s.
2. **Tint only primary actions.** Glass carries the palette's foreground (`fg.*` on
   `toolbar.background`'s role); `.tint(palette.accent)` goes on the one primary action in a bar
   or palette, as it does in `.drawn`. Interactive, tinted glass on `.lumenPrimary` follows this rule.
3. **Contrast is measured against the opaque fallback.** Every foreground on a glass surface meets
   its contrast rule against the token the drawn chrome paints there: `toolbar.background` for the
   toolbar band, `menu.background` for the palette, `sidebar.background` for the sidebar edge. The
   validator and the conformance checks keep running on the drawn chrome, which is what the glass
   degrades to; nothing may rely on the blur, so Reduce Transparency, Increase Contrast and the
   27 slider can only make a surface more readable.
4. **The drawn chrome stays the reference.** `.drawn` is the default through 0.x.
   The goldens, the validator and every Catalog page are recorded in it; `.glass` gets its own
   goldens for a bounded subset (the surfaces in the navigation row above) on the OS of record
   (macOS 27), recorded through a real window because offscreen renders have no backdrop.
5. **Degrade, never break.** `.glass` draws as `.drawn` when Reduce Transparency
   is on, and in offscreen renders (`ImageRenderer` and the goldens' image renderer). The
   resolution happens once, in the environment, so every surface in a window agrees.
6. **Nothing else changes.** Tokens, metrics, density, keyboard behavior, focus rings, selection
   looks (§10), the title bar's hierarchy and the toolbar's priorities are identical in both
   styles. A theme has no glass keys; a component reads the resolved style only to pick its
   ground.

## The switch

```swift
public enum LumenChromeStyle: String, CaseIterable, Identifiable, Sendable {
    case drawn   // Lumen paints every ground (the default)
    case glass   // the navigation layer uses system glass on macOS 27 and later
}
```

- `LumenStoreConfiguration.chromeStyle` sets an app's style; it defaults to `.drawn`, so every
  existing client renders unchanged. The initializer that takes `chromeStyle:` is a second one;
  the original keeps its signature.
- `.lumenChromeStyle(_:)` overrides the store's style for a subtree: one window, a preview, a
  golden. It is an environment override, not a second store.
- `\.lumenChromeStyle` is what was asked for; `\.lumenResolvedChromeStyle` is what draws. A
  surface in the navigation layer reads the resolved value and picks its ground; it never reads
  `#available` or Reduce Transparency itself. `LumenChromeStyle.systemSupportsGlass` answers the
  capability for code outside a view; it is always true on supported systems.
- Changing the style at run time (the Catalog's toggle) must not reset view state: the surfaces
  switch grounds inside `.background {}` and `.overlay {}` closures and value-based modifiers, never
  by branching around their content.

## What each surface draws

| Surface | `.drawn` | `.glass` (macOS 27 and later) |
|---|---|---|
| Window toolbar (`lumenWindowChrome`) | The title bar's gradient while the window is key (`titlebar.activeTop` to `titlebar.activeBottom`), `toolbar.background` when inactive; toolbar items sit on the band with the system platter hidden (`ToolbarContent.lumenToolbarPlatter(_:)` on each item, which `LumenTopBar` applies and an app's own `.toolbar` items can use); `.lumenSidebarToggle(columnVisibility:)` on a `NavigationSplitView` sidebar replaces the system toggle with a bare outline button matching the inspector toggle | The system platter shows under controls; direct `ToolbarItem` identities stay bare in both styles (the specialized `lumenToolbarPlatter` overload); `.lumenSidebarToggle(columnVisibility:)` keeps the system sidebar toggle; the band is flat `toolbar.background` in both window states, so the gradient never sits under glass |
| Unified top bar (`LumenTitlebarBackground`, hidden title bar) | The same band, drawn by Lumen | Flat `toolbar.background`; the items are Lumen's controls, which draw no glass of their own |
| Command palette (⌘K) | `menu.background` in a `radius.xl` continuous rect, a `border.default` hairline, the popover elevation and an 8 % scrim | `glassEffect(.regular)` in the same shape; no hairline (the glass draws its own rim); the same elevation, scrim, rows, row highlight and keycaps. Nothing inside paints a flat band over the glass: the scope track is a `menu.separator` hairline capsule with no fill, and the footer has no fill in either style; grouping comes from hairlines, spacing and the controls |
| Toasts (`lumenToasts`) | `bg.elevated`, metric radius and border, popover elevation; no scrim | System regular glass over a thick material and an opaque raised backing in the same shape, so page text never reads through; the standard drawn fallback. Each toast is a separate, nonoverlapping floating surface |
| Popovers (`lumenPopover`, `LumenPopoverContent`) | The system popover's material; Lumen draws the content | Unchanged: on 26 and later the system popover is already glass, and rule 1 says Lumen adds none |
| Command menu, context menus, pop-ups | `menu.background`, opaque | Unchanged (content layer) |
| Sidebar (`lumenSidebarBackground`, `lumenSidebarColumn`) | `sidebar.background` | Opaque sidebar content with full-width scrolling and row hit areas; the toolbar uses its own glass treatment |
| Everything in the content layer | Tokens | Unchanged, always |
