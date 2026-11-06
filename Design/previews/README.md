# Icon appearances

`LumenCatalog/` and `LumenAppTemplate/` each contain six 1024 × 1024 images:
`Default.png`, `Dark.png`, `ClearLight.png`, `ClearDark.png`, `TintedLight.png`, and
`TintedDark.png`. Mono artwork supplies the Clear and Tinted variants.

The images show the icon documents rendered for macOS at scale 1 with the default tint.
They illustrate static appearance; wallpaper, display settings and custom tints can change
how the system presents an icon.

`Scripts/icon-check.sh` creates native previews in a new directory. It requires Aqua, DarkAqua
and Tintable icon stacks with a 1024-point canvas and nonempty layers. Tool logs and compiled
asset metadata are ignored by Git.
