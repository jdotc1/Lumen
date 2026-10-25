# Settings sizing and adaptive panes

Compose `Settings { LumenSettingsSidebarView(categories) }.lumenSettingsScene()` for a resizable
settings window with one sidebar toggle and the category title beside Back/Forward in the compact
40 pt chrome band. The root measures every category's natural content height, including the header,
sections and bottom inset, and chooses the tallest for its initial ideal height: at least 480 pt,
at most the screen's visible height less a margin, or 720 pt when no screen is available. It sizes
once so category navigation does not jump the window; longer panes scroll with bottom clearance.
The minimum width remains 680 pt and the default width 820 pt; `.contentMinSize` permits growth.
A pane uses its own width for `LumenSettingsWidthClass`: compact below 560 pt, regular from 560
through 820 pt, and wide above 820 pt. Compact `LumenSettingsRow` controls move below their labels.
Wide content keeps one readable measure of about 640 pt, with space on both sides and leading-aligned
text. Horizontal padding and section spacing grow by width class through `LumenMetrics`; row rhythm
continues to follow the selected density. `LumenSettingsGroup` gives related fields and buttons
inner padding and spacing from the same metrics scale.

Hosts can supply a preferred content size without replacing the scaffold or its Scene helper:

```swift
Settings {
    LumenSettingsSidebarView(categories)
        .lumenSettingsPreferredSize(CGSize(width: 900, height: 640))
}.lumenSettingsScene()
```

The additive API is `View.lumenSettingsPreferredSize(_ size: CGSize) -> some View`. It takes
precedence over measured ideal size, subject to the window minimum and available screen height.
Custom pane content can read `@Environment(\.lumenSettingsWidthClass)` to follow the same class.
The existing initializer signatures remain unchanged. `LumenSettingsSidebarView.stableContentHeight`
and `.windowMaxHeight` remain public for source compatibility but are deprecated; neither is the
sizing policy. Use the host modifier for a preferred size.

The Catalog's Settings page and real Settings window share generic Engine content: a runtime row
with a trailing action, a toggle, a padded field/button group, a footnote and a disclosure. A tall
category demonstrates the screen cap and scrolling. These examples preserve the shared pane
trailing edge and the existing compact native navigation chrome.
