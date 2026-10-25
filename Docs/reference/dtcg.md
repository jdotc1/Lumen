# DTCG and CSS interchange

Lumen JSON is canonical. DTCG is an editable exchange format; CSS is a web projection.
Neither changes the existing `lumen-theme export <directory>` artifacts or their encoding.

## Specification

The [DTCG format draft](https://www.designtokens.org/tr/drafts/format/) is a preview.
This mapping targets the stable
[2025.10 Final Community Group Report, October 28, 2025](https://www.designtokens.org/tr/2025.10/format/),
particularly token/group extensions, color, dimension, number, duration and shadow values.
It is a bounded Lumen mapping, not an implementation of every DTCG feature.

## Commands and library API

```sh
lumen-theme export --format dtcg lumen.standard ./tokens
lumen-theme export --format dtcg Tests/Fixtures/midnight-deep.json ./tokens
lumen-theme export --format dtcg --all ./tokens
lumen-theme export --format dtcg ./tokens
lumen-theme export --format css lumen.standard ./theme.css
lumen-theme import --format dtcg ./tokens/lumen.standard.tokens.json -o ./edited.theme.json
lumen-theme import --format dtcg ./tokens/lumen.standard.tokens.json
```

A theme argument is a built-in ID or a single Lumen JSON file, as in the report commands.
`--format` may occur before or after positional arguments. DTCG export defaults to all built-in
registry themes; `--all` makes that explicit. Files are named `<id>.tokens.json`; path separators
in an ID are rejected. CSS requires exactly one theme and an output filename. Import writes
JSON to stdout unless `-o` is supplied; warnings and errors go to stderr. Validator errors return
exit status 1 without writing or replacing the destination. Unsupported arguments also fail.
Warnings alone do not prevent saving.

`LumenDTCG.export(_:in:)`, `export(themeJSON:in:)`, and `importTheme(_:in:)` are public in
`LumenTokens`. The import result exposes `theme`, `themeJSON` and `[LumenIssue]` for future editor
integration. Use `themeJSON` to save the exact file. Use the Data export overload for a source
file's original spelling. Value export uses sorted, pretty-printed Lumen encoding with a final
newline, or retained source bytes on a previously imported, unchanged value.
`LumenCSS.export(_:in:)` returns CSS. Both APIs accept an app's registry and its pack tokens.

## Mapping

| Lumen data | DTCG path/type | Interpretation |
|---|---|---|
| Appearance colors | `<appearance>.<spec.group>.<role>` / `color` | `light`, `dark`, `lightHighContrast`, `darkHighContrast`; resolved colors grouped by `LumenTokenSpec.group` |
| `typeScale`, `spacingScale` | `metrics.typeScale`, `metrics.spacingScale` / `number` | Multipliers; omitted values display as 1 |
| `radiusProfile` | `metrics.radius.{xs,sm,md,lg,xl}` / `dimension` | Native points map numerically to CSS `px`, not physical CSS `pt` |
| `motion` | `metrics.motion.{fast,standard,emphasized}` / `duration` | Standard: 0.14/0.22/0.32 s; reduced: 0.07/0.11/0.16 s; none: zero |
| Menu/popover depth | `depth.{menu,popover}.{light,dark}` / `shadow` | Black color with opacity, zero offsetX/spread, radius as blur and y as offsetY |
| Glow depth | `depth.glow.{hero,selection}` / `shadow` | Same composite shape, with neutral black representing geometry and opacity only |

Appearances are ordinary groups, chosen so a DTCG reader can discover every value without a
proprietary modes extension. Flattened inheritance supplies the effective appearances; contrast
palettes are merged over their base palettes, and missing component roles resolve through the
registry. Appearance group names have meaning in this mapping, not in DTCG generally.

Dots are prohibited inside DTCG names. Each entire group/role name is encoded injectively:
`%` → `%25`, `.` → `%2E`, `$` → `%24`, `{` → `%7B`, `}` → `%7D`. Spaces and case stay intact.
For example, `light.Backgrounds.bg%2Ecanvas` is the `bg.canvas` token; its token object contains
`"$type": "color"` and a `$value` object with `colorSpace`, three numeric `components`, and `alpha`.
Using the whole role as one name also avoids a collision between hypothetical app roles `custom` and `custom.variant`.

Color values use `srgb` or `display-p3` matching the theme. Import accepts components and alpha
in 0–1; it does not silently clip or reinterpret mixed color spaces. Lumen files have one color
space and 8-bit hex channels, so edits are quantized to that representation before validation.
The optional DTCG `hex` hint is not authoritative. Other color spaces are reported as warnings.

Radii distinguish absent app defaults (4/6/8/10/14) from explicit `standard` (4/6/8/10/12),
`rounded` (6/8/10/12/12), and uniform values. The five exported radius roles do not model the
app's pill sentinel. An edited ramp must match an explicit preset or a uniform radius; otherwise
it is warned about and the original profile remains. Motion edits must match a complete preset;
seconds and milliseconds are accepted. Animation curves remain implicit in that preset.
Dimensions in `rem` need external context and are not converted. No font family is invented:
schema 2 declares a type multiplier, not a font-family choice.

Shadow import supports Lumen's opacity/radius/y fields. Shared menu/popover geometry edited to
conflicting light and dark values is warned about and retained; independent opacity edits work.
Layered shadows, nonzero horizontal offset/spread, inset shadows, and nonblack shadow colors
cannot be represented and are warned about. Glow tint is supplied by a view at runtime, so the
neutral exported color is not a claim about its rendered tint. Lumen's validator checks the
resulting bounds and popover/menu hierarchy.

## Lossless extension and editing rules

Root `$extensions["com.jdotc1.lumen"]` contains:

- `mappingVersion: 1`;
- `theme`: the source Lumen object, retaining id, name, summary, `inherits`, `schemaVersion`,
  color-space/high-contrast declarations, sparse palettes, metric presets and depth declarations,
  unknown fields, and the distinction between absent and empty objects;
- `sourceJSON`: exact UTF-8 source text for unchanged file round trips;
- `baseline`: the exported token values, for detecting changes independently of registry drift;
- `packs`: exporting pack IDs and their `lockedMetrics` lists.

The interoperable values are always in ordinary `$value` properties. Extension data preserves
Lumen identity and declarations that DTCG cannot express directly. Import compares token values
semantically with the baseline, applies supported changes to the sparse original, then flattens
and validates with `LumenValidator`. Formatting/order-only changes retain source bytes. Source
bytes are reused only when they decode to the same source theme and the resulting theme is
unchanged. A supported edit produces deterministic Lumen JSON and preserves unknown source fields.
A deleted token retains its source declaration with a warning; deletion is not a request to
flatten or discard Lumen inheritance. Unknown paths and unsupported types also warn and are ignored.

Whole-token `{path}` aliases and inherited group `$type` are supported, including cycle detection.
Property-level references, `$extends`, arbitrary renamed paths and general DTCG transforms are
outside this mapping. Keep the exported paths and Lumen extension during a design-tool loop.
Unrecognized DTCG metadata is not represented in the Lumen theme model. Without the Lumen extension,
import uses `imported` / `Imported`, reports the missing metadata, and reads recognized token paths;
source-byte fidelity, sparse declarations and source locks cannot then be recovered.

The destination registry enforces its own pack locks. Source locks are preserved as metadata, not
installed into the destination registry; imports warn if an active source lock is not enforced there.
Source files are not overwritten by export. Import cannot find arbitrary custom parents on disk:
its supplied registry must resolve `inherits` (the CLI uses the core registry).

## CSS

Color role segments become hyphenated custom properties, for example `bg.canvas` →
`--lumen-bg-canvas`, `fg.primary` → `--lumen-fg-primary`, and `accent.default` →
`--lumen-accent-default`. This uses the role's group prefix rather than the human-facing spec group title.
Ambiguous or unsafe CSS identifiers fail export instead of colliding or injecting CSS.
Metric properties start `--lumen-metrics-`; shadow properties start `--lumen-depth-`.
P3 values use `color(display-p3 ...)`; sRGB values retain hex alpha.

`:root` contains light values, or dark values for a dark-only theme. A dark media block follows
when present; contrast blocks are scoped to the matching color scheme when both schemes exist.
This prevents light contrast values from overriding dark values. CSS includes resolved standard
metric/depth defaults, not app-specific runtime overrides or a complete reproduction of native rendering.

## Design-tool loop

1. Export a theme to DTCG and retain the canonical Lumen JSON.
2. Open the token file in a tool that reads DTCG 2025.10 color/composite values and preserves extensions.
3. Edit supported token values without renaming their paths or removing the Lumen extension.
4. Export DTCG from that tool and import it with `lumen-theme import --format dtcg`.
5. Review warnings and validator issues; save only the intended edits and preview them in the app.

External tools must preserve the documented token paths and Lumen extension metadata.
The interchange commands do not require a design-tool plugin.

The checked-in `theme.schema.json` points here with `$comment`. The legacy schema generator stays
unchanged so plain export remains byte-stable; it does not add that documentation-only comment.
