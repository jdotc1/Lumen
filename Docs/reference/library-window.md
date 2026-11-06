# Library window

`LumenLibraryWindow` is the library/browser archetype for a shoebox app. Pair the root with
`.lumenPaletteRoot()` and the scene with `.lumenLibraryScene()` to obtain the unified compact
native toolbar and content minimum. The README has a complete region-composition recipe.

The host owns data, search/filter state and selection. Supply `LumenCollection` in `content`,
`LumenSourceList` in `sourceList`, `LumenFilterChips` in `filterChips`, and a `LumenDetailHeader`
followed by metadata in `detail`. The scaffold owns the source surface, detail scroll view,
filter-row separator and status container. A long collection needs its own `ScrollView`;
mark its content with `.lumenColumnContent` after a flexible frame. Top-bar builders provide
identity, search and filter controls on the window buttons' line. Any optional region may be
omitted; an omitted source or detail region has no toggle.

`minimumSize` (default 640 × 400) describes the content area below the native top bar. It must
fit the collection, chips, fixed toolbar controls and status. `.contentMinimumWidth(_:)` can
raise that width. `.columnWidths(sourceList:detail:)` declares the side-pane bounds. The
Catalog uses 180/200/280 pt source and 260/280/380 pt detail widths, with a 1200 × 720 default.

`LumenLibraryPanels` records requested source/detail visibility. Without a binding both panes
start automatic; toggle choices become explicit. With a binding both values are explicit.
`LumenLibraryLayout` maps these two regions directly onto `LumenUtilityLayout.visiblePanels`;
the utility implementation is unchanged. Detail collapses first at equal priority, then source;
restoration reverses that order. An explicitly shown detail yields after an automatic source.
An explicitly hidden region stays hidden. Resizing never writes to the host binding.

Real content remains mounted in `HSplitView` panes using `lumenWorkspaceRegion(shown:width:)`.
Only the flexible, clipped outer allocation is measured. The root minimum stays outside that
wrapper, avoiding a split-pane width feeding back into its own available-space measurement.

`windowStructure(kind: .library)` checks native toolbar alignment, minimum sizing, truncation,
overflow, icons and region placement just as the utility kind does. The library additionally
requires `LumenLibraryLayoutKey` reports and flags a visible detail with an automatically
collapsed source when both are requested at equal priority. Reports preserve the explicit
priority exception. Run at the content minimum and 1440 × 900, alongside `narrowSizing` and
`truncation`. The Catalog tests include sparse/populated content in drawn/glass chrome and
an Auto Layout `.minSize` host with a 1100 × 720 → minimum → 1100 × 720 capture regression.
