#!/usr/bin/env python3
"""Fetch the Button tab's bundled icons from Iconify and write them into the tab.

Reads tools/bundled-icons.txt (one Iconify name per line, `# Category` lines
grouping them), fetches each icon's SVG body from Iconify's public API, and
replaces the block between the `#bundled-icons` markers in the tab's
index.html. Run it again after editing the list; commit the result.

Usage: tools/bundle_icons.py [--check]
"""

import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIST = ROOT / "tools" / "bundled-icons.txt"
PAGE = ROOT / "drivers" / "dynamic_button" / "www" / "html" / "index.html"
API = "https://api.iconify.design"
BEGIN = "/* #bundled-icons */"
END = "/* #end-bundled-icons */"
# The packs the bundle may draw from: Apache-2.0, so no per-icon credit is needed.
ALLOWED = {"mdi", "material-symbols"}


def read_list():
    """Return [(category, prefix, name)] in file order."""
    icons, category = [], ""
    for line in LIST.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            category = line.lstrip("# ").strip()
            continue
        prefix, name = line.split(":", 1)
        if prefix not in ALLOWED:
            sys.exit(f"{line}: only {sorted(ALLOWED)} may be bundled")
        icons.append((category, prefix, name))
    return icons


def get_json(path, query):
    url = f"{API}/{path}?{urllib.parse.urlencode(query)}"
    req = urllib.request.Request(url, headers={"User-Agent": "dynamic-buttons-bundle"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def fetch(prefix, names):
    """Return {name: (body, width, height)} for every name, resolving aliases."""
    data = get_json(f"{prefix}.json", {"icons": ",".join(names)})
    missing = data.get("not_found") or []
    if missing:
        sys.exit(f"{prefix}: not on Iconify: {', '.join(missing)}")
    width, height = data.get("width", 24), data.get("height", 24)
    icons, aliases = data.get("icons", {}), data.get("aliases", {})
    out = {}
    for name in names:
        key = name
        while key not in icons and key in aliases:
            key = aliases[key]["parent"]
        icon = icons[key]
        out[name] = (icon["body"], icon.get("width", width), icon.get("height", height))
    return out


def licenses(prefixes):
    data = get_json("collections", {"prefixes": ",".join(sorted(prefixes))})
    return {
        p: {"title": c["license"]["title"], "url": c["license"].get("url", "")}
        for p, c in data.items()
    }


def render():
    entries = read_list()
    by_prefix = {}
    for _, prefix, name in entries:
        by_prefix.setdefault(prefix, []).append(name)
    bodies = {}
    for prefix, names in by_prefix.items():
        for i in range(0, len(names), 60):
            for name, icon in fetch(prefix, names[i : i + 60]).items():
                bodies[(prefix, name)] = icon
    lic = licenses(by_prefix)
    icons = []
    for category, prefix, name in entries:
        body, width, height = bodies[(prefix, name)]
        icons.append(
            {
                "id": f"{prefix}:{name}",
                "category": category,
                "body": body,
                "width": width,
                "height": height,
            }
        )
    packs = {p: lic[p] for p in sorted(by_prefix)}
    return (
        f"{BEGIN}\nconst BUNDLED_PACKS = {json.dumps(packs, separators=(',', ':'))};\n"
        f"const BUNDLED_ICONS = {json.dumps(icons, separators=(',', ':'))};\n{END}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check", action="store_true", help="fail if the page's block is out of date"
    )
    args = parser.parse_args()
    page = PAGE.read_text()
    start, end = page.index(BEGIN), page.index(END) + len(END)
    block = render()
    if args.check:
        if page[start:end] != block:
            sys.exit(
                f"{PAGE.relative_to(ROOT)}: bundled icons are out of date; run tools/bundle_icons.py"
            )
        return
    PAGE.write_text(page[:start] + block + page[end:])
    count = block.count('"id":')
    print(f"{count} icons written to {PAGE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
