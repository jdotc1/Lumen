# Sidebar edges

Sidebar scroll regions and row hit areas extend to the window and column edges. Visible
selection shapes remain inset, with continuous corners. Padding belongs inside the hit area.

## Component behavior

- `LumenSourceList`: move horizontal s2 padding from the entire stack inside each
  row's hit area. Retain the visible selection inset and full-width scroll view.
- `LumenListRow`: sidebar titles reserve semi-bold width and draw semi-bold when
  selected, independently of window activity. Details and counts retain their fonts.
  Explicit content rows retain their existing rendering.
- `LumenStackedSidebar`: inherited sidebar row context and inset apply to caller
  `LumenListRow`s unless the caller supplies an explicit context. Its existing pane
  scroll regions already span their columns; static text has no selection state.
- `LumenSettingsSidebarView`: native sidebar scrolling/hit geometry remains native;
  category titles use the shared width reservation and the custom shape explicitly
  uses continuous corners. Selected categories use semi-bold text.
- Catalog main and Split Workspace use the source-list behavior. The Sample Workspace's
  selected function rows use the sidebar role, have a 12 pt visual inset and
  expand their hit region through the surrounding content padding.
- The real Workspace contains no selected text row; icon/tool selections remain
  the separate tools family in PRINCIPLES §10.
