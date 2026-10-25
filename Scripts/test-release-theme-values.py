#!/usr/bin/env python3
"""Focused release report fixtures; never invokes release.sh or any release gate.

Run after building: python3 Scripts/test-release-theme-values.py .build/debug/lumen-theme
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CLI = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / '.build/debug/lumen-theme'
HELPER = ROOT / 'Scripts/release-theme-values.py'
BASE = """# Changelog

## Unreleased

### Added
- Future feature.

## 0.59.0 (2026-10-23)

### Added
- New commands.

### Visual
- Authored visual change.

### Fixed
- Existing fix.

## 0.58.0 (2026-10-22)

### Visual
#### Theme values
- Older report stays intact.
"""


class ReleaseThemeValuesTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / '.build/release-theme-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        theme = {'id': 'release-fixture', 'name': 'Release fixture', 'schemaVersion': 1,
                 'light': {'fg.primary': '#111111', 'bg.canvas': '#FFFFFF'},
                 'dark': {'fg.primary': '#EEEEEE', 'bg.canvas': '#000000'}}
        self.old = self.directory / 'previous.json'
        self.new = self.directory / 'current.json'
        self.old.write_text(json.dumps([theme]))
        theme['light']['fg.primary'] = '#777777'
        self.new.write_text(json.dumps([theme]))
        self.changelog = self.directory / 'CHANGELOG.md'
        self.changelog.write_text(BASE)

    def run_helper(self, current=None):
        return subprocess.run([sys.executable, str(HELPER), str(CLI), str(self.old),
                               str(current or self.new), str(self.changelog), '0.59.0'],
                              text=True, capture_output=True)

    def test_changed_export_stops_then_reviewed_rerun_continues(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 3, result.stderr)
        first = self.changelog.read_text()
        self.assertIn('#111111', first)
        self.assertIn('#777777', first)
        self.assertIn('Stopped before tagging', result.stderr)
        self.assertEqual(first.count('#### Theme values'), 2)
        self.assertIn('- Authored visual change.', first)
        self.assertIn('### Fixed\n- Existing fix.', first)
        self.assertTrue(first.endswith('#### Theme values\n- Older report stays intact.\n'))
        rerun = self.run_helper()
        self.assertEqual(rerun.returncode, 0, rerun.stderr)
        self.assertEqual(self.changelog.read_text(), first)

    def test_identical_exports_continue_silently_without_edit(self):
        result = self.run_helper(self.old)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout + result.stderr, '')
        self.assertEqual(self.changelog.read_text(), BASE)

    def test_creates_visual_and_preserves_other_versions(self):
        source = BASE.replace('### Visual\n- Authored visual change.\n\n', '')
        self.changelog.write_text(source)
        result = self.run_helper()
        self.assertEqual(result.returncode, 3, result.stderr)
        text = self.changelog.read_text()
        version = text.split('## 0.59.0')[1].split('## 0.58.0')[0]
        self.assertIn('### Visual\n\n#### Theme values', version)
        self.assertEqual(text.split('## 0.58.0')[1], BASE.split('## 0.58.0')[1])

    def test_existing_heading_preserves_authored_notes(self):
        self.changelog.write_text(BASE.replace('- Authored visual change.',
                                              '- Authored visual change.\n\n#### Theme values\n- Review note.'))
        result = self.run_helper()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(self.changelog.read_text().count('#### Theme values'), 2)
        self.assertIn('- Review note.', self.changelog.read_text())

    def test_missing_version_does_not_modify_file(self):
        source = BASE.replace('## 0.59.0', '## 0.60.0')
        self.changelog.write_text(source)
        result = self.run_helper()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changelog.read_text(), source)

    def test_unreadable_export_does_not_modify_file(self):
        result = self.run_helper(self.directory / 'missing.json')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changelog.read_text(), BASE)


if __name__ == '__main__':
    unittest.main()
