# Floating surface sizing

Command and input palettes accept preferred maximum widths and content-height limits through
`.lumenCommandPaletteSize(width:maximumListHeight:)` and
`.lumenInputPaletteSize(width:maximumContentHeight:)`. Apply the modifier after the presentation
modifier, or directly to the surface. Positive finite values are points; nil, nonpositive and
nonfinite values restore the text-scaled defaults. Smaller host proposals take precedence.

Command menus accept an explicit `width:` on the presentation modifier, and
`.lumenCommandMenuMaximumHeight(_:)` bounds long lists. Cascading submenus resolve their own
width before the zero-width positioning anchor, so the anchor cannot collapse or stretch the
panel. A short host uses the existing in-place navigation and a scrolling list.

`View.lumenToastWidth(_ width: CGFloat?) -> some View` sets a preferred maximum toast width.
Apply it after `.lumenToasts(center, bottomInset: ...)`. The override is in points at every text
scale and remains bounded by the host, including the host's scrolling fallback. Nil, nonpositive
and nonfinite values restore the automatic 360 pt width multiplied by the resolved text growth.
Existing toast initializers and the existing hosting modifier retain their signatures.

Automatic popover overloads distinguish text-scaled defaults from explicitly supplied point
widths. Toolbar identities yield to finite host widths; keycaps and activity status heights grow
with text. Panel bars, text-only mode switchers and tab bars provide overflow fallbacks.

In debug builds, a failed snapshot comparison saves `<name>@<variant>-actual.png`,
`<name>@<variant>-diff.png` and `<name>@<variant>-report.txt` to `.build/snapshot-failures/`, or
`LUMEN_SNAPSHOT_FAILURES` when set. The diff contains absolute RGB/alpha channel changes on black;
magenta marks areas outside one image when sizes differ. The report names the expected image.
Passing comparisons, recording behavior and release builds are unchanged. Both verification
entry points use the same diagnostic writer, without changing the public snapshot API.
