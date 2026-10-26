# Window chrome guarantee

Apply `lumenPaletteRoot()` to every window root. The shared native bridge normalizes preference
and expanded toolbars to unified, preserves visible content height and the top edge, and enables
full-size content. Native styles already using one row remain unchanged. Owned native changes
are restored when the root detaches. Nested palette roots share the outer owner.

Use `Settings { LumenSettingsSidebarView(categories).lumenPaletteRoot() }.lumenSettingsScene()`
for settings. The scene marker also identifies a custom root as Settings, but the rendered audit
reports that it lacks the stock scaffold. Settings uses automatic native toolbar backgrounds;
workspace and document roots retain their configured glow. Native Settings scene identification
also reaches an app-built root that omits the helper.

An app intentionally using an expanded toolbar can add `.lumenPreservesExpandedToolbar(true)`
after `.lumenPaletteRoot()`. The Boolean can change without replacing app content. Full-height
content remains enabled, and the explicit exception is recorded by the layout audit.

Settings category labels remain regular weight. Active selection uses `accent.filled` and
`accent.filledForeground`; inactive selection uses `settings.rowSelectedInactive` with the primary
sidebar foreground. Themes can override the latter role; the standard dark value is `#32343A`.

## Icon appearance

`LumenIconTile` reads `AppleIconAppearanceTheme` from the global defaults domain and refreshes
when the system preference changes. It never writes that preference. Regular, Dark, Clear and
Tinted styles with Automatic, Light or Dark modes are parsed defensively; unknown values follow
the window appearance. Clear and Tinted currently use dark tiles, without system wallpaper tint
or clear compositing. Light icons use a solid hue and white glyph. Dark icons use a near-black
ground with a quiet rim and keep the vivid hue, lifting only enough to reach graphic contrast.

Symbols are measured once and cached by name. Ink spanning at least 75 percent of each edge in
a 12 percent bounding-box perimeter band, plus at most 35 percent ink in the three-raster-pixel
band immediately inside it, identifies framed artwork. The empty inner band distinguishes a frame
from a solid fill. Framed artwork reduces from 64 to 52 percent of the tile. Separate multi-mark grids are distinguished by clear internal
gutters on both axes. A DEBUG rendered finding recommends an unframed symbol when appropriate.
