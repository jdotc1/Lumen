#!/usr/bin/env python3
"""Build a two-level Icon Composer document from Lumen hue and glyph sources."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'symbols'))
from gen import SYMBOLS
from svgsym import curve_bbox

# Central circle: center (512, 512), radius 256; square bounds 256...768.
GLYPH_BOX = 512
# Optical adjustment for the heavy-base anonymization silhouette.
OPTICAL_OFFSETS = {'lumen.anonymize': (0, -16), 'lumen.anonymize.fill': (0, -16)}


def build(output, hue, glyph):
    source = (HERE.parent / 'Sources/LumenTokens/LumenCorePalettes.swift').read_text()
    palette = source.split('public static let standardHues: LumenPalette = [', 1)[1].split(']', 1)[0]
    hues = {'hue.' + key.lower(): value for key, value in
            re.findall(r'\.hue(\w+):\s*"(#[0-9A-Fa-f]{6})"', palette)}
    if hue not in hues:
        raise ValueError('unknown hue; choose ' + ', '.join(sorted(hues)))
    if output.suffix != '.icon':
        raise ValueError('output must end in .icon')
    if output.exists():
        raise ValueError(f'refusing to replace existing document: {output}')
    paths = SYMBOLS[glyph]('Regular-S')
    bounds = [curve_bbox(path) for path in paths]
    x0, y0 = min(b[0] for b in bounds), min(b[1] for b in bounds)
    x1, y1 = max(b[2] for b in bounds), max(b[3] for b in bounds)
    scale = GLYPH_BOX / max(x1 - x0, y1 - y0)
    dx, dy = OPTICAL_OFFSETS.get(glyph, (0, 0))
    tx, ty = 512 + dx - scale * (x0 + x1) / 2, 512 + dy - scale * (y0 + y1) / 2
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
           'viewBox="0 0 1024 1024">\n'
           f'<g fill="#FFFFFF" transform="matrix({scale:.8f} 0 0 {scale:.8f} {tx:.8f} {ty:.8f})">\n'
           + '\n'.join(f'<path d="{path}"/>' for path in paths) + '\n</g>\n</svg>\n')
    rgb = [int(hues[hue][i:i + 2], 16) / 255 for i in (1, 3, 5)]
    def color(multiplier):
        return 'srgb:' + ','.join(f'{c * multiplier:.5f}' for c in rgb) + ',1.00000'
    doc = {
        'fill-specializations': [
            {'value': {'solid': color(1)}},
            {'appearance': 'dark', 'value': {'solid': color(0.25)}},
            {'appearance': 'tinted', 'value': {'solid': 'gray:0.25000,1.00000'}},
        ],
        'groups': [{
            'name': '1 Glyph', 'lighting': 'individual', 'specular': True,
            'shadow': {'kind': 'neutral', 'opacity': 0},
            'translucency': {'enabled': False, 'value': 0},
            'layers': [{'name': glyph, 'image-name': 'glyph.svg', 'glass': True}],
        }],
        'supported-platforms': {'squares': ['macOS']},
    }
    (output / 'Assets').mkdir(parents=True)
    (output / 'Assets/glyph.svg').write_text(svg)
    (output / 'icon.json').write_text(json.dumps(doc, indent=2) + '\n')
    print(f'Built {output}: {hue} ({hues[hue]}), {glyph}, {GLYPH_BOX}/1024 glyph box, optical offset ({dx}, {dy})', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--hue', required=True, help='Lumen token, e.g. hue.violet')
    parser.add_argument('--glyph', required=True, choices=sorted(SYMBOLS))
    parser.add_argument('--preview-dir', type=Path, help='also run icon-check once into this new folder')
    args = parser.parse_args()
    try:
        build(args.output, args.hue, args.glyph)
    except (ValueError, OSError) as error:
        parser.exit(1, f'error: {error}\n')
    if args.preview_dir:
        subprocess.run([str(HERE.parent / 'Scripts/icon-check.sh'), str(args.output),
                        '--preview-dir', str(args.preview_dir)], check=True)


if __name__ == '__main__':
    main()
