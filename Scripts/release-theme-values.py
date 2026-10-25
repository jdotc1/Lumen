#!/usr/bin/env python3
"""Write release theme changes for human review; exit 3 when the changelog needed the report."""
import argparse
from pathlib import Path
import re
import subprocess
import sys


HEADING = "#### Theme values"
START = "<!-- lumen-theme-values:start -->"
END = "<!-- lumen-theme-values:end -->"


def update_changelog(text, version, report):
    """Replace this version's generated report without disturbing other sections."""
    sections = list(re.finditer(r"^## (.+)$", text, re.MULTILINE))
    matches = [m for m in sections if re.match(re.escape(version) + r"(?:\s|$)", m[1])]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one CHANGELOG section for {version}")
    match = matches[0]
    index = sections.index(match)
    stop = sections[index + 1].start() if index + 1 < len(sections) else len(text)
    body = text[match.end():stop]
    # CLI reports have standalone headings; nest them below Theme values in the changelog.
    report = re.sub(r"^(#{1,4}) ", "##### ", report.strip(), flags=re.MULTILINE)
    block = f"{HEADING}\n{START}\n{report}\n{END}\n"
    headings = list(re.finditer(r"^#{3,4} Theme values\s*$", body, re.MULTILINE))
    if len(headings) > 1:
        raise ValueError("duplicate Theme values headings; reconcile them before releasing")
    if headings:
        heading = headings[0]
        following = re.search(r"^#{3,4} ", body[heading.end():], re.MULTILINE)
        end = heading.end() + following.start() if following else len(body)
        existing = body[heading.start():end]
        # Keep authored notes, but replace only the owned block on later runs.
        if START in existing or END in existing:
            if existing.count(START) != 1 or existing.count(END) != 1 or existing.index(START) > existing.index(END):
                raise ValueError("malformed generated Theme values markers")
            existing = re.sub(re.escape(START) + r".*?" + re.escape(END),
                              lambda _: f"{START}\n{report}\n{END}", existing, flags=re.DOTALL)
            body = body[:heading.start()] + existing + body[end:]
        else:
            body = body[:heading.end()] + f"\n{START}\n{report}\n{END}\n" + body[heading.end():]
    else:
        visual = re.search(r"^### Visual\s*$", body, re.MULTILINE)
        if visual:
            following = re.search(r"^### ", body[visual.end():], re.MULTILINE)
            end = visual.end() + following.start() if following else len(body)
            body = body[:end].rstrip() + "\n\n" + block + "\n" + body[end:]
        else:
            body = body.rstrip() + "\n\n### Visual\n\n" + block + "\n"
    return text[:match.end()] + body + text[stop:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cli", help="built lumen-theme executable")
    parser.add_argument("previous", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("changelog", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    try:
        result = subprocess.run([args.cli, "diff", str(args.previous), str(args.current),
                                 "--format", "markdown"], capture_output=True, text=True, check=True)
        if not result.stdout.strip():
            return 0
        original = args.changelog.read_text()
        updated = update_changelog(original, args.version, result.stdout)
        if updated == original:
            # The committed changelog already carries this exact report: it was reviewed.
            return 0
        args.changelog.write_text(updated)
        print(f"Theme values changed: review {args.changelog} under {args.version} / Visual / Theme values. "
              "Stopped before tagging; no tag or push was made.", file=sys.stderr)
        return 3
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"error: release theme report: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
