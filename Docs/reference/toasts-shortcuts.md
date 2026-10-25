# Toasts and shortcut reference

- `LumenToast` with title, optional message, `LumenTone`, optional `Action`, and duration.
  Default info/success lifetime is four seconds; warning/danger and explicit nil persist.
- Main-actor observable `LumenToastCenter`, held per window, with `post(_:)`, `dismiss(id:)`,
  `visibleToasts` and `collapsedCount`. Hover and collapse preserve remaining visible time.
- `.lumenToasts(_:bottomInset:)`: newest three at bottom trailing, older +N, optional action,
  plain dismiss buttons, wrapping text and scrolling when the stack exceeds available height.
  Apply above a status bar or pass its occupied height; no global status-bar assumptions.
- `LumenShortcut`, `LumenShortcutGroup`, `LumenShortcutsSheet(groups:)`,
  `.lumenShortcutsSheet(groups:)`, `LumenShortcutsCommands`, and
  `LumenShortcuts.keyboardShortcuts`. The Help command owns Command-Slash.
- `LumenViewCommands.shortcutGroups` / `shortcutGroups(panes:)` share the definitions used by
  menu installation, including customized/nil shortcuts and optional palette/tab commands.
  Groups describe configured command families, not the current focused binding's availability.

## Appearance and layout

Palette status tokens and glyphs match banners; grounds, borders, keycaps, spacing, radii and
motion come from Lumen. Toasts join the floating navigation layer for glass; the shortcuts
sheet remains opaque. Reduce Motion removes toast animation; the existing chrome resolver
handles Reduce Transparency/offscreen fallback. Long labels wrap through the standard layout
helper. Drawn snapshots cover the six built-in appearance variants; window rendering covers
system glass materials.
