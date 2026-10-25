# Motion

`LumenMotion.Transition` is the shared vocabulary for insertion/removal, value changes and
imperative actions. The Catalog's **Motion** page lists every case with its resolved duration,
a Trigger/Reset button, the current Reduce Motion state, and count/status examples.

| Cases | Standard duration | Curve | Insertion/removal |
| --- | --- | --- | --- |
| `inspector` | 0.22 s | metrics `standardCurve` (snappy) | trailing move + opacity |
| `bottomPanel` | 0.22 s | metrics `standardCurve` | bottom move |
| `sidebar` | 0.22 s | metrics `standardCurve` | leading move + opacity |
| `selection`, `disclosure`, `themeHover` | 0.22 s | metrics `standardCurve` | opacity |
| `notice` | 0.22 s | metrics `standardCurve` | trailing move + opacity |
| `palette`, `statusGlyph`, `hover`, `control`, `reorder`, `toolLayout` | 0.14 s | metrics `fastCurve` (ease-in-out) | opacity |
| `toast` | 0.22 s | metrics `regularCurve` (ease-in-out) | bottom move + opacity |
| `progress` | 0.22 s | metrics `regularCurve` | opacity |
| `scroll` | 0.50 s | SwiftUI default snappy | opacity |
| `loading` | 1.10 s per leg | ease-in-out, repeating/autoreversing | opacity |

The final two cases preserve existing scroll and indeterminate-progress timing; they do not
consume the emphasized ramp. Existing metric overrides and custom curves remain authoritative
for the other cases. The legacy `Motion.animation(_:reduceMotion:)` API remains available.

## Using motion

```swift
if isPresented {
    Panel().lumenTransition(.bottomPanel)
}
// Apply to the stable enclosing container, not the conditional child:
// .lumenAnimation(.bottomPanel, value: isPresented)

Text(count, format: .number).lumenNumericText(value: count)
LumenSymbol(symbolName).lumenStatusSymbol(value: symbolName)
```

The public entry points are:

- `View.lumenAnimation<Value: Equatable>(_: LumenMotion.Transition, value: Value)`
- `View.lumenTransition(_: LumenMotion.Transition)`
- `View.lumenNumericText<Value: Equatable>(value: Value)`
- `View.lumenStatusSymbol<Value: Equatable>(value: Value)`
- `LumenMotion.perform(_:metrics:reduceMotion:_:)` for actions such as `ScrollViewProxy.scrollTo`
  which must execute inside a transaction. Views pass their environment metrics/Reduce Motion;
  scene commands retain their existing system Reduce Motion read and default scroll timing.
- `Transition.duration(in:)`, `animation(in:reduceMotion:)`, and `transition(in:reduceMotion:)`
  resolve a case for clients that need the underlying values.

The modifiers read `lumenMetrics` and `accessibilityReduceMotion` themselves. Under Reduce
Motion, **every case has no animation and an identity insertion/removal transition**. Disabled
theme motion has the same behavior. Numeric text uses identity instead of rolling digits;
symbol replacement is disabled and inherited symbol effects are removed. The loading bar stops
and centers its segment. Existing activity pulse is also disabled. No new repeating effect or
bounce is introduced.

Numeric transitions apply to badges/pills, count labels, stat cells, inspector summaries,
status-strip counts, toolbar progress percentages and chart content. Charts retain their native
automatically formatted axis labels; the numeric content transition is inherited from the chart,
without replacing labels or adding annotations. Status replacement applies to badge/status-strip
glyphs and the activity status glyph. Motion does not change static geometry or typography.

## Adding a case

Add one entry to `Transition`: a new case defaults to the fast ramp and opacity. `allCases`
automatically adds its Catalog row. If it needs an existing non-default ramp or movement, list it
in the corresponding switch in the same type; do not add component-local timings or Reduce
Motion branches. Extend the focused resolution tests and this table to document its contract.

## Platform

The package targets macOS 27 and uses `ContentTransition.numericText(countsDown:)`,
`ContentTransition.symbolEffect(_:options:)`, `View.contentTransition(_:)`, and
`View.symbolEffectsRemoved(_:)`; SwiftUI's default snappy duration is 0.5 seconds.
