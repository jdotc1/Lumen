#!/usr/bin/env python3
"""README component inventory check, driven by the public symbol graph.

  swift package --scratch-path DIR dump-symbol-graph --minimum-access-level public
  Scripts/readme-inventory.py DIR/out/symbolgraph [--list]

Reads the LumenUI and LumenIntents graphs and compares their public top-level Lumen* views, view
modifiers and control styles (types conforming to SwiftUI View, ViewModifier, ButtonStyle,
ToggleStyle or an NSView representable) with the backticked names in README.md's "## Components"
section. Data types, keys and enums are not components and are not required there.
Exit 1 when a public component is missing from the section (the inventory drifted) or the section
names a type that no longer exists in any Lumen module. Pass --list to print the generated names instead of checking.
"""
import json, re, sys
from pathlib import Path

COMPONENT_MODULES = ["LumenUI", "LumenIntents"]
ALL_MODULES = ["LumenUI", "LumenTokens", "LumenIntents", "LumenConformance"]
COMPONENT_PROTOCOLS = {"View", "ViewModifier", "ButtonStyle", "ToggleStyle", "NSViewRepresentable",
                       "NSViewControllerRepresentable", "PrimitiveButtonStyle"}
KINDS = {"swift.struct", "swift.class", "swift.enum", "swift.protocol", "swift.typealias"}

def load(graph_dir: Path, module: str) -> dict:
    path = graph_dir / f"{module}.symbols.json"
    if not path.exists():
        sys.exit(f"error: missing {path}")
    return json.loads(path.read_text())

def type_names(graph_dir: Path, modules: list[str]) -> dict[str, str]:
    """Public top-level Lumen* types: name -> symbol identifier."""
    found: dict[str, str] = {}
    for module in modules:
        for symbol in load(graph_dir, module)["symbols"]:
            parts = symbol["pathComponents"]
            if len(parts) == 1 and symbol["kind"]["identifier"] in KINDS and parts[0].startswith("Lumen"):
                found[parts[0]] = symbol["identifier"]["precise"]
    return found

def components(graph_dir: Path) -> set[str]:
    types = type_names(graph_dir, COMPONENT_MODULES)
    by_id = {v: k for k, v in types.items()}
    names: set[str] = set()
    for module in COMPONENT_MODULES:
        for rel in load(graph_dir, module)["relationships"]:
            if rel["kind"] != "conformsTo" or rel["source"] not in by_id:
                continue
            target = rel.get("targetFallback", rel["target"]).split(".")[-1]
            if target in COMPONENT_PROTOCOLS:
                names.add(by_id[rel["source"]])
    return names

def readme_names(readme: Path) -> set[str]:
    text = readme.read_text()
    section = text.split("## Components", 1)[1].split("\n## ", 1)[0]
    return set(re.findall(r"`(Lumen[A-Za-z0-9]+)", section))

def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit(__doc__)
    graph_dir = Path(args[0])
    api = components(graph_dir)
    if "--list" in sys.argv:
        print("\n".join(sorted(api)))
        return 0
    everything = set(type_names(graph_dir, ALL_MODULES))
    named = readme_names(Path(__file__).resolve().parent.parent / "README.md")
    missing = sorted(api - named)
    stale = sorted(named - everything)
    if missing:
        print(f"public components missing from README Components ({len(missing)}):")
        print("\n".join("  " + n for n in missing))
    if stale:
        print(f"README Components names with no public type ({len(stale)}):")
        print("\n".join("  " + n for n in stale))
    if not (missing or stale):
        print(f"README inventory matches the symbol graph ({len(api)} components)")
    return 1 if (missing or stale) else 0

sys.exit(main())
