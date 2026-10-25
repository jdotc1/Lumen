# Charts

Register the chart pack in the app's theme store:

```swift
let registry = LumenRegistry(packs: [.core, .chart])
```

A palette root supplies the current theme. `EnvironmentValues.lumenChartStyle` resolves all eight
series colors in pack order, the grid, axis and label colors, the canvas, caption type, and stroke
widths from that subtree's palette and metrics. Theme and type-ramp changes flow through the same
environment as other Lumen components. No chart colors are fixed in the views.

```swift
let observations = [
    LumenChartDatum(label: "May", value: 12, series: "Current"),
    LumenChartDatum(label: "June", value: 18, series: "Current"),
    LumenChartDatum(label: "May", value: 9, series: "Previous"),
    LumenChartDatum(label: "June", value: 14, series: "Previous"),
]
LumenBarChart(observations).frame(height: 240)
LumenLineChart(observations).frame(height: 240)
```

Keep the data's IDs stable when updating values. The bar and line views preserve category and
series order of first appearance. Lines connect categorical labels in input order. A point mark
keeps a one-observation line visible. Nonfinite observations are omitted; zero and negative values
remain valid. No finite observations shows `LumenEmptyState`. Only multiple series show a legend,
using `LumenSwatchStrip` with the same assigned colors as the marks. A missing series is independent
of any named series. Eight colors are available; additional series repeat them.

`LumenHistogram(values:binCount:)` takes raw `[Double]` observations, with one series and no
legend. Already-binned counts belong in `LumenBarChart`. Omit `binCount` to use Swift Charts'
`NumberBins` automatic choice, or pass a positive count for equal-width bins over the observed
range. Nonpositive counts use one bin. Constant observations get a padded range and one bin
by default (padding is the larger of 0.5 and 5% of the observation's magnitude).
Empty and all-nonfinite input show the shared empty state; other nonfinite values are dropped.
Bin ranges include their lower bound; only the last bin includes its upper bound.

```swift
LumenHistogram(values: [0, 1, 1, 2, 3, 4], binCount: 2).frame(height: 240)
LumenHistogram(values: measurements).frame(height: 240) // automatic bins
```

Use Swift Charts directly for dates, continuous x axes, custom marks, interactions and scales.
The same style applies with one modifier; it leaves the native legend available:

```swift
Chart(observations) { item in
    PointMark(x: .value("Month", item.label), y: .value("Value", item.value))
        .foregroundStyle(by: .value("Series", item.series ?? "Value"))
}
.lumenChartStyle(series: ["Current", "Previous"])
```

The chart pack already declares each series on `bg.canvas` at 3:1 through `LumenContrast.graphic`
and checks all 28 pairs with `LumenDistinctRule` at 0.08 OKLab distance. The chart examples exercise those existing
requirements rather than adding duplicate findings. The views draw the canvas that those rules
measure, including when embedded in a raised surface.
