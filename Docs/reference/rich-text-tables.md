# Rich text and tables

## Table sorting

Mark sortable columns with `LumenTableColumn("Name") { … }.sortable()`. Pass a
`sortOrder: Binding<[LumenTableSort]>` to a new table initializer. Each sort value contains
`column: String` (the column's ID, currently its title) and `ascending: Bool`; it is Hashable
and Sendable. Column titles must be unique within a table.

Lumen contains no comparator. The caller supplies rows in the desired order, for example by
sorting a computed rows property using the binding. Clicking a different sortable header promotes
it to the primary key ascending, retaining other keys as secondary keys; clicking the primary
again flips it. Each sorted column shows a quiet chevron. Unmarked headers remain inert.

Both `minHeight:` and `height:` initializers support sorting, optionally together with resizing.
All preexisting initializer signatures remain available.

## Column resizing

Pass `columnWidths: Binding<[String: CGFloat]>`, with or without `sortOrder:`, to enable header
dividers. Widths are column content widths, excluding the table's outer padding and intercolumn gaps.
Drag a divider to resize the column on its left. The width is clamped to `.minWidth(_:)` and the
viewport width; when the minimum itself is wider than the viewport, the minimum wins. Double-click
restores the measured natural header/cell width, floored by the minimum, even for a column originally
created with a fixed width.

Explicit widths are caller state. Narrowing the table never rewrites them. Unbound columns retain
their fixed or natural/minimum widths, sharing surplus room; overflow scrolls horizontally with
headers and rows together. The outer viewport is measured separately from the scrolling content,
so a content width cannot drive the measurement that allocated it. Without a width binding, the
existing priority-based shrink behavior is unchanged. Row selection remains the quiet navigation
selection described in PRINCIPLES §10.

## Rich text

`LumenRichTextView(text: Binding<AttributedString>, maxHeight: CGFloat = 180)` hosts an `NSTextView`
on Lumen's field surface, with body typography resolved through the theme and app text scale,
palette text/selection colors, a focus ring and the standard disabled fade. Plain and semantic
bold/italic runs acquire the body font; explicit native font runs retain their formatting. Editing
round-trips Foundation/AppKit attributes in the binding. The view grows with its text to the text
area's `maxHeight`, then scrolls vertically. The optional bar adds its own height above that limit.

Use the separate `init(text:maxHeight:showsFormatBar:)` initializer for compact Bold, Italic,
Underline and Bulleted List buttons in `LumenToolbarIconButtonStyle`. The list button opens
AppKit's standard list panel for bullets or numbering. The field remains the formatting target.

Add `TextEditingCommands()` and `TextFormattingCommands()` to the host scene's `.commands` for
system editing and Format menus. While the field is first responder, its native text view handles
⌘B/⌘I/⌘U before host menu and SwiftUI button shortcuts, using the same native formatting actions as
the compact bar. Attaching the first field installs a process-wide `NSWindow.performKeyEquivalent`
method replacement: it offers only these three shortcuts to a focused editable Lumen editor before
calling the original window implementation. Other events retain normal host routing. A host window
override that consumes the event without calling `super` can bypass this boundary. No event monitor
or application activation is used. AppKit owns undo. The text container follows the viewport
width, rewraps after text or attribute changes, and invalidates its measured height so the field grows
or scrolls after formatting as well as typing. The Catalog's Forms & Controls page demonstrates the
scene integration.
