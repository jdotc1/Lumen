# Window corners on macOS 27

Lumen requires macOS 27. `LumenRadius.window` is approximately **16 pt**, a reference for
explicit container shapes rather than a replacement for the system's live corner geometry.

## Approximation

A continuous rounded rectangle with a 16–16.5 pt radius approximates the native welcome
window corner. Antialiasing and half-point sampling limit the precision; this value is
not an exact system constant.

## Implementation

- Sheets and both welcome components clip directly with `ConcentricRectangle()`.
- Floating status uses `ConcentricRectangle()` for its opaque background and
  `GeometryProxy.concentricCornerRadii` for its inset border. Without a rounded container,
  its geometry is rectangular; there is no older-system radius-ramp path.
- `LumenConcentricTextView` and `LumenConcentricGlassView` declare
  `.corners(radius: .containerConcentric)`. Both apply `effectiveCornerRadii` through a
  layer mask during layout and `viewDidChangeEffectiveCornerRadii()`. Text-view flipping
  maps the AppKit top/bottom radii into the shape's coordinates.
- Lumen's code-pane API accepts client-owned `NSTextView`s; it creates none itself.
  Clients use `LumenConcentricTextView` when constructing a native editor and then install
  `LumenLineNumberRuler` normally. The Catalog's listing is SwiftUI. Likewise, the native
  glass subclass is available to AppKit hosts; Lumen's own glass surfaces use SwiftUI.

The selected macOS 27.2 SDK's `NSView.h` declares the read-only corner configuration and
instructs subclasses to apply changed effective radii. `NSViewCornerConfiguration.h`
declares the independent per-corner configuration. `SwiftUICore.swiftinterface` declares
`GeometryProxy.concentricCornerRadii` at macOS 27 and `ConcentricRectangle` at macOS 26;
all are used directly under the package's macOS 27 floor.
