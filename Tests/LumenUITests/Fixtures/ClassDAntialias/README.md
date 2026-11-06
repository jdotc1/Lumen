# Antialias edge fixture

`actual.png` and `expected.png` are 12 × 10 pixel crops of a utility-window tag label.
Their source ICC profiles are preserved.

The test examines crop-local pixel coordinates (2,4), (8,4), (4,5), and (6,5).
Native-space deltas are 5, 4, 16, and 16. Minimum neighbouring edge ranges are
0.442 actual and 0.444805 expected. All four satisfy the antialias-edge predicate.
The sRGB comparator uses a separate >12 threshold and can select a different set.

Synthetic tests cover count, delta, alpha, edge proximity, and one-pixel-shift rejection.
