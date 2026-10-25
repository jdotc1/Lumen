#!/usr/bin/env python3
"""Native macOS icon compilation, compiled appearance inspection, and previews."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
RENDITIONS = ('Default', 'Dark', 'ClearLight', 'ClearDark', 'TintedLight', 'TintedDark')


def run(command, log):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    log.write_bytes(result.stdout + result.stderr)
    return result


def diagnostics(value):
    if isinstance(value, dict):
        return any((re.search(r'(warnings|errors)$', key) and bool(item)) or diagnostics(item)
                   for key, item in value.items())
    if isinstance(value, list):
        return any(diagnostics(item) for item in value)
    return False


def png_size(path):
    with path.open('rb') as file:
        data = file.read(24)
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'not a PNG: {path}')
    return struct.unpack('>II', data[16:24])



def compiled_appearances(entries, name):
    """The runtime derives four Clear/Tinted renditions from the Mono stack."""
    stacks = {entry.get('Appearance'): entry for entry in entries
              if entry.get('Name') == name and entry.get('AssetType') == 'IconImageStack'}
    mapping = {'NSAppearanceNameAqua': ('Default',),
               'NSAppearanceNameDarkAqua': ('Dark',),
               'ISAppearanceTintable': ('ClearLight', 'ClearDark', 'TintedLight', 'TintedDark')}
    found = []
    for key, appearances in mapping.items():
        stack = stacks.get(key, {})
        if (stack.get('CanvasWidth') == 1024 and stack.get('CanvasHeight') == 1024
                and stack.get('LayerCount', 0) >= 2 and stack.get('Layers')):
            found.extend(appearances)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('icon', type=Path)
    parser.add_argument('name', nargs='?')
    parser.add_argument('--preview-dir', required=True, type=Path)
    args = parser.parse_args()
    icon = args.icon.resolve()
    name = args.name or icon.stem
    if icon.suffix != '.icon' or not (icon / 'icon.json').is_file():
        parser.error('input must be an Icon Composer .icon directory containing icon.json')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', name) or name != icon.stem:
        parser.error('name must match the .icon filename without its extension')
    preview = args.preview_dir.resolve()
    if preview.exists():
        parser.error('preview folder already exists; preserve the existing output and choose a new folder')
    if icon == preview or icon in preview.parents:
        parser.error('preview folder must be outside the source icon')
    preview.mkdir(parents=True)
    report = {'icon': str(args.icon), 'name': name, 'compile': 'not run',
              'compiled_appearances': [], 'previews': [], 'errors': []}
    def error(message):
        report['errors'].append(message)
        print('ERROR: ' + message, flush=True)
    # All temporary build products stay inside this checkout and are removed on exit.
    with tempfile.TemporaryDirectory(prefix='.icon-check-', dir=ROOT / 'Design') as work:
        work = Path(work)
        command = ['xcrun', 'actool', str(icon), '--compile', str(work), '--platform', 'macosx',
                   '--minimum-deployment-target', '27.0', '--app-icon', name,
                   '--output-partial-info-plist', str(work / 'partial.plist')]
        report['actool_command'] = command
        result = run(command, preview / 'actool.log')
        try:
            output = plistlib.loads(result.stdout)
            bad = diagnostics(output)
        except (plistlib.InvalidFileException, ValueError):
            bad = True
        # Reject warnings/errors in either stream, even if actool exits zero.
        bad = bad or bool(re.search(rb'\b(?:warning|error)(?:s)?\s*:', result.stdout + result.stderr, re.I))
        if result.returncode or bad:
            report['compile'] = 'failed'
            error(f'actool failed or emitted diagnostics (exit {result.returncode}); see actool.log')
            print((result.stdout + result.stderr).decode(errors='replace'), flush=True)
        else:
            report['compile'] = 'passed'
            for file in ('Assets.car', name + '.icns', 'partial.plist'):
                if not (work / file).is_file():
                    error('missing compiled output: ' + file)
            if (work / 'partial.plist').is_file():
                partial = plistlib.loads((work / 'partial.plist').read_bytes())
                report['partial_info'] = partial
                if partial.get('CFBundleIconName') != name:
                    error('partial plist does not identify the requested app icon')
            if (work / 'Assets.car').is_file():
                inspected = run(['xcrun', 'assetutil', '--info', str(work / 'Assets.car')],
                                preview / 'assets.json')
                if inspected.returncode:
                    error('assetutil could not inspect compiled appearances; see assets.json')
                else:
                    entries = json.loads(inspected.stdout)
                    report['compiled_appearances'] = compiled_appearances(entries, name)
                    if len(report['compiled_appearances']) != len(RENDITIONS):
                        error('compiled metadata does not establish all six appearances; see assets.json')
        developer = subprocess.run(['xcode-select', '-p'], capture_output=True, text=True, check=True).stdout.strip()
        candidates = [Path(developer) / 'Applications/Icon Composer.app/Contents/Executables/ictool',
                      Path('/Applications/Icon Composer.app/Contents/Executables/ictool')]
        renderer = next((path for path in candidates if path.is_file()), None)
        if renderer:
            report['renderer'] = str(renderer)
            for appearance in RENDITIONS:
                target = preview / (appearance + '.png')
                command = [str(renderer), str(icon), '--export-image', '--output-file', str(target),
                           '--platform', 'macOS', '--rendition', appearance, '--width', '1024',
                           '--height', '1024', '--scale', '1', '--design-generation', '27']
                rendered = run(command, preview / (appearance + '.log'))
                if rendered.returncode or not target.is_file():
                    error('ictool failed for ' + appearance + '; see its log')
                    continue
                if png_size(target) != (1024, 1024):
                    error('unexpected preview size for ' + appearance)
                    continue
                report['previews'].append(appearance)
        elif (work / (name + '.icns')).is_file():
            report['renderer'] = 'iconutil (Default only)'
            iconset = work / 'Default.iconset'
            converted = run(['iconutil', '--convert', 'iconset', '--output', str(iconset),
                             str(work / (name + '.icns'))], preview / 'iconutil.log')
            source = iconset / 'icon_512x512@2x.png'
            if converted.returncode or not source.is_file():
                error('iconutil could not extract Default')
            else:
                shutil.copyfile(source, preview / 'Default.png')
                report['previews'].append('Default')
            report['manual_review'] = 'Check Dark, Clear and Tinted in Icon Composer; ictool unavailable.'
        else:
            error('no bundled ictool and no compiled ICNS for Default preview')
    report['status'] = 'FAIL' if report['errors'] else 'PASS'
    (preview / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['status']} {name}: compile={report['compile']}; "
          f"compiled appearances={','.join(report['compiled_appearances']) or 'unconfirmed'}; "
          f"previews={','.join(report['previews']) or 'none'}; {preview}", flush=True)
    return bool(report['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
