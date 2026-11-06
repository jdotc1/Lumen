# App text scale and density

Text scale is an app preference for dense tools. It is independent of the operating system's text
settings.

Apply `.lumenTextScale(preference)` at each window root, beside `.lumenPaletteRoot(store:)` and
`.lumenDensityRoot(store:)`. The public `EnvironmentValues.lumenTextScale` defaults to `1.0` and
may also be set directly outside a palette root. Within a subtree, use the modifier so the
stored metrics update with the preference. The app owns persistence. The Catalog stores its
stepped `1.0`, `1.15`, and `1.3` preference in its own defaults suite and applies changes live to
every window.

Use `LumenAppearanceSettings(textScale: $textScale, textScaleSteps: [1, 1.15, 1.3])` (optionally with `store:`) for the ready-made preference row.

## Resolution and precedence

1. An explicit `.lumenMetrics(...)` or `environment(\.lumenMetrics, ...)` replaces the entire metrics
   value, including an explicit `.standard`. It wins over both theme and app scale in either modifier
   order. Custom typography and layout are the app's responsibility in this case.
2. Otherwise, multiply the selected window theme's `typeScale` (default `1`) by the app preference,
   then clamp the **product** to `0.9...1.3`. A non-finite app preference uses `1`.
3. Scale every typography role and section-label tracking once. Theme `spacingScale` remains
   independent; radius, depth and motion keep theme-metric resolution.
4. Grow text-bearing control and row heights by `max(1, effectiveScale)`. Controls and icon hit
   targets keep the 24 pt floor; smaller type never shrinks their boxes. `LumenDensity` selects
   compact, regular or comfortable heights from that resolved layout. Compact one-line base rows
   remain 22 pt, distinct from the 24 pt control/icon-target floor; intrinsic text may make rows taller.

| Theme scale | App preference | Effective type | Control / icon hit minimum |
| --- | --- | --- | --- |
| 1.0 | 1.0 | 1.0 | 24 pt |
| 1.0 | 1.15 | 1.15 | 27.6 pt |
| 1.0 | 1.3 | 1.3 | 31.2 pt |
| Contrast 1.1 | 1.3 | 1.3 | 31.2 pt |
| Contrast 1.1 | 0.9 | 0.99 | 24 pt |

Nested palette roots use their own theme. The inherited app preference is resolved once for that
theme; nested text-scale modifiers replace the preference rather than multiplying preferences.
Palette roots and text-scale modifiers resolve at the environment write boundary and store the
result. Reading `lumenMetrics` returns the explicit app override or that stored result without
repeating resolution. Both snapshot renderers use the same theme writer.
`LumenMetrics.resolving(_:textScale:)` exposes the same calculation for hosts that need it directly.

## Bounded visual coverage

The golden harness reuses forms, sidebar (`count-sections` at 1.0), inspector, and settings
(`settings-rich` at 1.0). Only `standard-light` gains `1.15` and `1.3` variants: eight images.
Canvases grow vertically with scale, as Contrast canvases do. Existing 1.0 and other-theme
images stay unchanged. At 1.3, the four subjects also run truncation, overflow and narrow-sizing
checks with compact density.

## Pointer and touch targets

When a screen reports `.multiTouch`, density must resolve to its roomiest setting (`.comfortable`)
and hit targets must grow to at least **44 pt**. Lumen currently implements
no screen detection, touch behavior or touch conformance variant. The pointer-scale rules above
remain the implemented behavior.
