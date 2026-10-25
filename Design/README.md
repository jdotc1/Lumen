# Design sources

- `LumenCatalog.icon`: the Lumen Catalog app icon, an Icon Composer document with Default,
  Dark and Mono appearances. Four component tiles use Lumen hues; the violet tile carries a spark.
- `catalog-icon-build.py`: generates Catalog icon compositions from procedural vector shapes.
- `Scripts/install-catalog.sh`: builds and installs the Catalog with its compiled icon.

## App icon template

- `LumenAppTemplate.icon`: a violet ground and a `lumen.patchedBytes.fill` glyph, with Default,
  Dark and Mono treatments and system-rendered Clear and Tinted variants.
- `app-icon-build.py`: creates an icon document from a Lumen hue token and glyph name. The optional
  `--preview-dir` compiles and renders it; existing output is preserved.
- `grid-measurement.json`: production-grid geometry and the 512-point inner glyph box on a
  1024-point canvas.
- `previews/`: the Catalog and generic template in six appearances.
- `Docs/reference/app-icon.md`: layer construction, appearance derivation, commands and limitations.

Generate into a new output path and preview directory:

```sh
python3 Design/app-icon-build.py Design/Custom.icon --hue hue.violet --glyph lumen.patchedBytes.fill --preview-dir Design/previews/Custom
```
