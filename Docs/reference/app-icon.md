# App icon kit

Use `Design/LumenAppTemplate.icon` as a starting point for macOS 27 app artwork.
The icon kit generates a new icon document and appearance previews.

## Make and check an icon

From the Lumen checkout, choose a new output name and a new preview folder:

```sh
python3 Design/app-icon-build.py Design/examples/MyClient.icon --hue hue.violet --glyph lumen.anonymize.fill --preview-dir Design/previews/MyClient
```

That single command generates the document and runs the native check once. For an existing document:

```sh
Scripts/icon-check.sh Design/examples/MyClient.icon MyClient --preview-dir Design/previews/MyClient-review
```

The optional name defaults to the document basename and must match it. Existing documents and
preview folders are never replaced. Reuse previous check results for unchanged inputs rather than
repeating a check. Python 3 and the selected Xcode command-line tools are required; nothing is
installed by these commands. `--help` lists the supported Lumen glyph names. The generator reads
`standardHues` directly from `Sources/LumenTokens/LumenCorePalettes.swift`, and uses the Regular-S
paths from `Design/symbols/gen.py`. It does not regenerate the Swift resource catalog.

## Layers and appearances

There are two visual levels: an opaque, full-canvas ground and one white vector glyph in a single
foreground group. The template uses `lumen.patchedBytes.fill` with `hue.violet`
(`#7B5CE6`). The foreground has Liquid Glass enabled,
specular enabled, zero configured shadow opacity and no translucency. SVG artwork has no baked
shadows, bevels, gradients, text, or masks. System lighting supplies the visible edge treatment.

| Appearance | Derivation |
| --- | --- |
| Default | Solid standard Lumen hue ground and the white glyph. |
| Dark | Same geometry; ground sRGB components multiplied by 0.25; white glyph retained. This is a Lumen derivation, not a separate hue token. |
| Mono | Same geometry, with a neutral gray ground specialization under the document's `tinted` key, following Apple's demo schema. |
| Clear Light / Dark | Icon Composer renders the Mono treatment for the selected light or dark environment. |
| Tinted Light / Dark | Icon Composer renders the Mono treatment with its tint treatment. Preview PNGs use the renderer's default tint settings. |

Apple describes these appearance controls in [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
The compiler emits three `IconImageStack` records for the requested app name:
`NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, and `ISAppearanceTintable`. The latter supplies
both Clear and Tinted variants; six independent compiled bitmap records are not expected.
In this toolchain, the tintable stack's reported base color matches Default despite the neutral
specialization. The PNGs demonstrate the rendered treatment; exact internal color conversion is
unconfirmed and is not asserted by the checker.

## Glyph sizing

Apple's [production template](https://devimages-cdn.apple.com/design/resources/download/iOS-27-Icon-Templates-Photoshop-Illustrator.dmg),
linked by [Apple Design Resources](https://developer.apple.com/design/resources/), contains
`iOS 27 - Icon Templates - Illustrator/App Icon Template.ai`. Its PDF-compatible page measures
1024 × 1024. The `Grid` layer's central circle has radius **256**, centered at (512,512).
Its bounding square meets the inner guides at **256 and 768** on both axes, giving a
**512 × 512 glyph box (50% of the canvas)**.
The vector evidence is the translation (512,768), followed by circle endpoints at local
(256,-256), (0,-512), (-256,-256), and (0,0). `Design/grid-measurement.json` records these
measurements. The extent is measured from Apple's grid; it is not a universal Apple glyph percentage.

The generator preserves aspect ratio and fits the longer dimension to 512. Bounds use the existing
Lumen cubic-curve sampling helper. The template remains centered at (512,512). The heavy-base
`lumen.anonymize.fill` and outline variant receive a Lumen optical offset of (0,-16), centering
their bounds at (512,496). The anonymize glyph therefore spans approximately x=273–751, y=240–752.
That small upward adjustment balances its shoulders without changing its proportions.

The square-canvas guidance is in Apple's
[App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons).
Keep source artwork unmasked so the system applies its corners.

## Keep the mark simple

Use one recognizable glyph. Avoid text, photos, hairline strokes that disappear in Mono, and more
than two visual levels of detail. Do not bake drop shadows, fake bevels, highlights or a rounded
icon mask into the SVG. Preserve the same silhouette across appearances. Apple's HIG explains
why vector layers, simple shapes and system effects are appropriate for these icons.

## What the check proves

`Scripts/icon-check.sh` delegates to `Design/icon-check.py`. Its `xcrun actool` invocation matches
`Scripts/install-catalog.sh`: platform `macosx`, deployment target `27.0`, `--app-icon`, and
`--output-partial-info-plist`. It builds in a temporary folder under `Design/` and removes that
folder on exit. Nonzero compiler status, warnings/errors, missing products, a mismatched app-icon
name, or missing appearance stacks fail the check. `assetutil --info` inspects the compiled CAR.

When present, the selected Xcode's bundled `Icon Composer.app/Contents/Executables/ictool` renders
six 1024 × 1024 PNGs with design generation 27. The standalone installed Icon Composer is the
second lookup location. Preview files are `Default.png`, `Dark.png`, `ClearLight.png`,
`ClearDark.png`, `TintedLight.png`, and `TintedDark.png`. They render the source document;
compiled-stack inspection is separate evidence. Each run retains `actool.log`, `assets.json`,
renderer logs, and a small `report.json` alongside the PNGs. Tool logs and `assets.json` are
local diagnostics ignored by Git; PNG previews can be retained alongside the source document. A failed compile may still produce previews
for diagnosis, but cannot produce a passing report.

If neither existing app contains `ictool`, `iconutil` extracts the Default PNG from the compiled
ICNS. The report then explicitly requires Dark, Clear and Tinted review in Icon Composer.
No alternate renderer or installation is attempted. These PNGs do not prove installed Dock behavior,
HDR display behavior, animation, or every user-selected wallpaper and tint.
