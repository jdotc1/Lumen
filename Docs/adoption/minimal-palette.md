# Palette and metrics without an app-owned theme store

A small utility can read `lumenPalette` and `lumenMetrics` without creating or installing a
`LumenThemeStore`, applying `.lumenPaletteRoot()`, or adopting Lumen's window chrome.
This means **no app-owned theme store**, not literally no internal store: Lumen's environment
uses a core-only, nonpersisting fallback store until the app installs one. That fallback does
not read or write theme files or user defaults. It is not a standalone public palette constructor.

Use the `LumenUI` product and macOS 27 target described in `small-app.md`. The following entire
example is compiled in `Tests/LumenUITests/LumenWorkspaceExamples.swift`.

```swift
import SwiftUI
import LumenUI

struct ExampleMinimalRoot: View {
    var body: some View {
        ExampleMinimalContent().lumenMetrics(.standard)
    }
}

struct ExampleMinimalContent: View {
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s2) {
            Text("Documents")
                .font(metrics.typography.title2)
                .foregroundStyle(palette[.fgPrimary])
            Text("No documents yet")
                .font(metrics.typography.body)
                .foregroundStyle(palette[.fgSecondary])
        }
        .padding(metrics.spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette[.bgCanvas])
    }
}
```

## Root tint and appearance without a theme store

To set the accent and light/dark/system without a `LumenThemeStore`, apply `.lumenRoot(tint:appearance:)`
once at the root. Every Lumen component reads both. Omit `tint` to keep the theme's accent; use
`.system` (the default) or `.light`/`.dark` for `appearance`. The following example is compiled in
`Tests/LumenUITests/LumenWorkspaceExamples.swift`.

```swift
struct ExampleMinimalTintRoot: View {
    var body: some View {
        ExampleMinimalContent()
            .lumenMetrics(.standard)
            .lumenRoot(tint: "#2F6FEB", appearance: .dark)
    }
}
```

Apply `lumenMetrics(_:)` inside (before) `lumenRoot`. Accent roles are derived from the tint with the
same contrast rules as the macOS system accent. A theme that forces its own scheme (Midnight,
Ultraviolet) still wins over `appearance`. The title-bar glow is off by default (`windowChrome: true`
turns it on). Apps with a theme store keep `.lumenPaletteRoot()`, which is unchanged; they can also set
`.environment(\.lumenRootTint, ...)` above it.

## What works

- Semantic foreground/background roles from the built-in core palette, including light/dark
  resolution through native dynamic colors.
- The standard typography, spacing, radii and layout metrics, or app-supplied `LumenMetrics`.
- Ordinary SwiftUI layout and native controls. The example's `spacing.s2` is the existing 4 pt
  grid step, rather than another local spacing scale.

## What this does not install

- Persisted theme selection, an app themes directory, file watching, custom theme packs or an
  app-specific theme library.
- Theme-forced appearance, native title-bar styling or density syncing. (Root tint and
  light/dark/system are available without a store through `lumenRoot`, below.)
- An app-owned Appearance settings workflow. Use `small-app.md` when exposing theme selection,
  imported themes or Lumen's appearance settings.

Explicit `.lumenMetrics(.standard)` pins the metrics in this subtree. When moving to the complete
store-backed root, remove that override if selected themes should supply metrics. A static
palette lookup is not a replacement for a store-backed root's observation and appearance policy.
For UI-independent theme data, validation and export only, depend on `LumenTokens` instead of
`LumenUI`; it does not supply SwiftUI colors or view modifiers.
