# Proportional split

`LumenProportionalSplit` divides a space into two panes that keep a ratio, not a pixel size, as the
window resizes. The first pane takes `ratio` of the space left after the hairline divider.

```swift
@AppStorage("editor.splitRatio") private var ratio = 0.6

LumenProportionalSplit(ratio: $ratio, minimumFirst: 160, minimumSecond: 100) {
    EditorView()
} second: {
    ConsoleView()
}
```

- `axis`: `.vertical` (default, top over bottom) or `.horizontal` (leading then trailing; the drag
  and arrow keys follow the layout direction).
- Minimums (default 120 pt) hold while there is room for both. With too little room the space splits
  in proportion to the minimums so no pane goes negative.
- The stored ratio is only written by the user (divider drag, arrow keys, VoiceOver adjust). Window
  resizes and clamping never rewrite it, so the chosen split returns when the window grows again.
- Persistence is the app's: bind the ratio to `@AppStorage` or `@SceneStorage`. Out-of-range or NaN
  stored values read as the nearest valid share (NaN reads as 0.5).
- Accessibility: the divider is focusable (Up/Down, or Left/Right for horizontal, move it 5%),
  labeled "Resize Panes" (override with `.dividerLabel(_:)`), and reports its position as a percentage.
- It does not use `VSplitView`, which cannot be driven by a ratio.
