#!/usr/bin/env python3
"""Build the Button tab's three icon packs and write them into the tab.

Reads resources/icon-packs/subjects.tsv (one picture per row), the base glyphs in
resources/icon-packs/glyphs/<library>/ and the Classic Device art in
resources/icon-packs/classic-device/, builds the Classic Tile and Modern pictures from
the glyphs, and replaces the block between the `#icon-packs` markers in the tab's
index.html. Run it again after editing the list or the art; commit the result.

`fetch` downloads, at the pinned versions below, every glyph the list names that is not
in resources/icon-packs/glyphs yet, with each library's license file.

Usage: tools/icon_packs.py [--check]
       tools/icon_packs.py fetch
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS_DIR = ROOT / "resources" / "icon-packs"
LIST = PACKS_DIR / "subjects.tsv"
GLYPHS = PACKS_DIR / "glyphs"
DEVICE = PACKS_DIR / "classic-device"
PAGE = ROOT / "drivers" / "dynamic_button" / "www" / "html" / "index.html"
BEGIN = "/* #icon-packs */"
END = "/* #end-icon-packs */"

# The largest picture a look keeps (Looks.MAX_ICON_BODY in src/dynamic_button/looks.lua).
MAX_BODY = 16 * 1024

# The glyph libraries, pinned, with where each glyph and license file comes from.
CDN = "https://cdn.jsdelivr.net/npm"
LIBRARIES = {
    "mdi": {
        "name": "Material Design Icons",
        "license": "Apache 2.0",
        "url": "https://github.com/Templarian/MaterialDesign/blob/master/LICENSE",
        "glyph": CDN + "/@mdi/svg@7.4.47/svg/{name}.svg",
        "license_file": CDN + "/@mdi/svg@7.4.47/LICENSE",
        "kind": "fill",
    },
    "lucide": {
        "name": "Lucide",
        "license": "ISC",
        "url": "https://github.com/lucide-icons/lucide/blob/main/LICENSE",
        "glyph": CDN + "/lucide-static@0.460.0/icons/{name}.svg",
        "license_file": CDN + "/lucide-static@0.460.0/LICENSE",
        "kind": "stroke",
    },
    "tabler": {
        "name": "Tabler Icons",
        "license": "MIT",
        "url": "https://github.com/tabler/tabler-icons/blob/main/LICENSE",
        "glyph": CDN + "/@tabler/icons@3.19.0/icons/outline/{name}.svg",
        "license_file": CDN + "/@tabler/icons@3.19.0/LICENSE",
        "kind": "stroke",
    },
}
OURS = {"license": "Finite Labs", "url": ""}

PACKS = [
    {
        "id": "classic-device",
        "name": "Classic Device",
        "note": "Shaded device pictures that match the OS 3 look.",
        "size": 1024,
        "shadow": True,
    },
    {
        "id": "classic-tile",
        "name": "Classic Tile",
        "note": "A white symbol on a colored tile that matches the OS 3 look.",
        "size": 1024,
        "shadow": True,
    },
    {
        "id": "modern",
        "name": "Modern",
        "note": "Line icons, colored when on, that match the X4 look.",
        "size": 32,
        "shadow": False,
    },
]

# Classic Tile colors by category; off is gray and alert is red, whatever the category.
TILE_COLORS = {
    "Battery": "#3E9A1E",
    "Power and Plugs": "#E3A21A",
    "Energy and Solar": "#E39A12",
    "EV Charging": "#2E9C5A",
    "Water and Leaks": "#1C7FD6",
    "Air Quality": "#14A39A",
    "Network": "#1E9BD7",
    "Generators": "#E0761A",
    "Pumps and Irrigation": "#2F8FD0",
    "Pool and Spa": "#1AA9D6",
    "Temperature and Humidity": "#E0761A",
    "Devices": "#2F80D8",
    "Appliances": "#5B6CD6",
    "Status": "#5B5FD6",
    "Home Modes": "#3B6FD8",
    "Holidays": "#D8352E",
    "Weather": "#3B8FD8",
}
TILE_OFF, TILE_ALERT = "#8A949C", "#C42032"
HOLIDAY_TILES = {
    "christmas": "#D8352E",
    "halloween": "#F07A1A",
    "fourth-of-july": "#2E5DBB",
    "thanksgiving": "#C26A1C",
    "new-year": "#B8902A",
    "valentines-day": "#D8356A",
    "easter": "#8E63C8",
    "st-patricks-day": "#2E9C5A",
}

# Modern colors when on, by category; off is white at 45% and alert is red.
YELLOW, RED, CYAN, ORANGE, GREEN, WHITE = (
    "#FFBE70",
    "#C42032",
    "#00C2F3",
    "#F57F25",
    "#7ED321",
    "#FFFFFF",
)
MODERN_ON = {
    "Battery": GREEN,
    "Power and Plugs": YELLOW,
    "Energy and Solar": YELLOW,
    "EV Charging": GREEN,
    "Water and Leaks": CYAN,
    "Air Quality": GREEN,
    "Network": CYAN,
    "Generators": ORANGE,
    "Pumps and Irrigation": CYAN,
    "Pool and Spa": CYAN,
    "Temperature and Humidity": ORANGE,
    "Devices": YELLOW,
    "Appliances": YELLOW,
    "Status": GREEN,
    "Home Modes": CYAN,
    "Holidays": WHITE,
    "Weather": WHITE,
}
# On colors that follow the subject rather than its category.
SUBJECT_ON = {
    "cooling": CYAN,
    "alarm": RED,
    "lock": WHITE,
    "fan": CYAN,
    "shade": "#9DCEFF",
    "window": "#9DCEFF",
    "tv": CYAN,
    "speaker": GREEN,
    "spa": ORANGE,
    "pool-heater": ORANGE,
    "water-heater": ORANGE,
    "oven": ORANGE,
    "warning": "#F5A623",
}

SVG_TAGS = {
    "g",
    "path",
    "circle",
    "ellipse",
    "rect",
    "line",
    "polyline",
    "polygon",
    "defs",
    "clipPath",
    "mask",
    "linearGradient",
    "radialGradient",
    "stop",
    "symbol",
    "use",
}


def read_list():
    """Return the rows of the subject list as dicts, in file order."""
    lines = [
        l for l in LIST.read_text().splitlines() if l.strip() and not l.startswith("#")
    ]
    header = lines[0].split("\t")
    rows = [dict(zip(header, l.split("\t"))) for l in lines[1:]]
    ids = [r["id"] for r in rows]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        sys.exit(f"{LIST.relative_to(ROOT)}: repeated ids: {', '.join(dupes)}")
    for r in rows:
        if r["state"] not in ("on", "off", "alert", "none"):
            sys.exit(f"{r['id']}: unknown state {r['state']}")
    return rows


def glyph_names(rows):
    """Return every lib:name glyph the list uses."""
    names = set()
    for r in rows:
        names.add(r["tile"])
        modern = r["modern"]
        if modern.startswith("frame:"):
            names.add(modern[len("frame:") :])
        elif modern.startswith("battery:"):
            if modern.endswith(":charging"):
                names.add(CHARGING_BOLT)
        else:
            names.add(modern)
        if r["device"] != "ours":
            names.add(r["device"])
    return sorted(names)


def glyph_path(ref):
    lib, name = ref.split(":", 1)
    if lib not in LIBRARIES:
        sys.exit(f"{ref}: unknown glyph library {lib}")
    return GLYPHS / lib / f"{name}.svg"


def fetch(rows):
    def get(url):
        req = urllib.request.Request(
            url, headers={"User-Agent": "dynamic-buttons-icon-packs"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read()

    added = 0
    for lib, spec in LIBRARIES.items():
        lic = GLYPHS / lib / "LICENSE"
        if not lic.exists():
            lic.parent.mkdir(parents=True, exist_ok=True)
            lic.write_bytes(get(spec["license_file"]))
    for ref in glyph_names(rows):
        path = glyph_path(ref)
        if path.exists():
            continue
        lib, name = ref.split(":", 1)
        try:
            path.write_bytes(get(LIBRARIES[lib]["glyph"].format(name=name)))
        except OSError as err:
            sys.exit(f"{ref}: {err}")
        added += 1
    print(f"{added} glyphs fetched into {GLYPHS.relative_to(ROOT)}")


def svg_inner(text, where):
    """Return an SVG file's view box and its markup without the outer svg element."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    m = re.search(r"<svg\b([^>]*)>(.*)</svg>", text, re.S)
    if not m:
        sys.exit(f"{where}: not an SVG file")
    box = re.search(r"""viewBox=["']([^"']+)["']""", m.group(1))
    body = m.group(2)
    # Tabler's glyphs open with an invisible square that only sizes the icon.
    body = re.sub(r'<path stroke="none" d="M0 0h24v24H0z" fill="none"\s*/>', "", body)
    body = re.sub(r'\s(class|id)="[^"]*"', "", body) if "<defs" not in body else body
    body = re.sub(r">\s+<", "><", body.strip())
    return (box.group(1) if box else "0 0 24 24"), body


def glyph(ref):
    path = glyph_path(ref)
    if not path.exists():
        sys.exit(
            f"{ref}: not in {GLYPHS.relative_to(ROOT)}; run tools/icon_packs.py fetch"
        )
    box, body = svg_inner(path.read_text(), ref)
    if box != "0 0 24 24":
        sys.exit(f"{ref}: view box {box}, expected 0 0 24 24")
    return body


def num(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def placed(ref, x, y, size, color, stroke_units=None, opacity=1):
    """A 24-unit glyph scaled into a square at (x, y), in one color."""
    lib = ref.split(":", 1)[0]
    s = size / 24
    attrs = f"transform='translate({num(x)} {num(y)}) scale({num(s)})'"
    op = f" opacity='{num(opacity)}'" if opacity != 1 else ""
    if LIBRARIES[lib]["kind"] == "stroke":
        attrs += (
            f" fill='none' stroke='{color}' stroke-width='{num(stroke_units / s)}'"
            " stroke-linecap='round' stroke-linejoin='round'"
        )
        body = re.sub(r'\sstroke-width="[^"]*"', "", glyph(ref))
        body = body.replace('stroke="currentColor"', "").replace('fill="none"', "")
    else:
        attrs += f" fill='{color}'"
        body = glyph(ref).replace('fill="currentColor"', "")
    return f"<g {attrs}{op}>{body}</g>"


def mix(color, toward, amount):
    a = [int(color[i : i + 2], 16) for i in (1, 3, 5)]
    b = [int(toward[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * amount):02X}" for x, y in zip(a, b))


def tile_color(row):
    if row["state"] == "off":
        return TILE_OFF
    if row["state"] == "alert":
        return TILE_ALERT
    return HOLIDAY_TILES.get(row["id"]) or TILE_COLORS[row["category"]]


def classic_tile(row):
    """A white glyph on a colored rounded-square tile, lit from the top (1024 units)."""
    color = tile_color(row)
    top, bottom, edge = (
        mix(color, "#FFFFFF", 0.22),
        mix(color, "#000000", 0.28),
        mix(color, "#000000", 0.4),
    )
    # The symbol is defined once and drawn twice: its shadow, then itself.
    body = glyph(row["tile"]).replace('fill="currentColor"', "")
    return (
        "<defs><linearGradient id='t' x1='0' y1='0' x2='0' y2='1'>"
        f"<stop offset='0' stop-color='{top}'/><stop offset='1' stop-color='{bottom}'/></linearGradient>"
        f"<g id='s' transform='translate(262 226) scale({num(500 / 24)})'>{body}</g></defs>"
        "<rect x='70' y='34' width='884' height='884' rx='133' fill='url(#t)'/>"
        f"<rect x='73' y='37' width='878' height='878' rx='130' fill='none' stroke='{edge}' stroke-opacity='0.5' stroke-width='6'/>"
        "<path d='M210 48H814' stroke='#FFFFFF' stroke-opacity='0.55' stroke-width='10' stroke-linecap='round'/>"
        "<use href='#s' transform='translate(0 14)' fill='#000000' opacity='0.28'/>"
        "<use href='#s' fill='#FFFFFF'/>"
    )


def modern_color(row):
    state = row["state"]
    if state == "alert":
        return RED, 1
    if state == "off":
        return WHITE, 0.45
    if state == "none":
        return WHITE, 1
    return SUBJECT_ON.get(row["subject"]) or MODERN_ON[row["category"]], 1


def modern_battery(spec, color, opacity):
    parts = spec.split(":")
    level = int(parts[1]) / 100
    mode = parts[2] if len(parts) > 2 else ""
    bar = {"charging": GREEN, "low": RED}.get(mode, color)
    body = (
        f"<rect x='3' y='10' width='22' height='12' rx='2.5' fill='none' stroke='{WHITE}' stroke-width='2'/>"
        f"<rect x='25.5' y='14' width='2.5' height='4' rx='1' fill='{WHITE}'/>"
    )
    if level > 0:
        body += f"<rect x='6' y='13' width='{num(16 * level)}' height='6' rx='1' fill='{bar}'/>"
    if mode == "charging":
        bolt = path_data(glyph(CHARGING_BOLT))[0]
        body += (
            f"<g transform='translate(9 9.5) scale(0.5)'><path d='{bolt}' "
            f"fill='{GREEN}' stroke='#000000' stroke-opacity='0.6' stroke-width='2' stroke-linejoin='round'/></g>"
        )
    return f"<g opacity='{num(opacity)}'>{body}</g>" if opacity != 1 else body


# The bolt a charging battery carries.
CHARGING_BOLT = "mdi:flash"

FRAME = "M6,2L26,2A4,4 0,0 1,30 6L30,26A4,4 0,0 1,26 30L6,30A4,4 0,0 1,2 26L2,6A4,4 0,0 1,6 2z"


def modern_frame(ref, color, opacity, filled):
    """A sensor: the glyph in a rounded square with a status dot, filled when on or in alert."""
    if not filled:
        return (
            f"<g opacity='{num(opacity)}'><path d='{FRAME}' fill='none' stroke='{color}' stroke-width='2'/>"
            f"<circle cx='16' cy='25' r='2' fill='{color}'/>{placed(ref, 10, 7, 12, color, 1)}</g>"
        )
    knock = (
        placed(ref, 10, 7, 12, "#000000", 1.4)
        + "<circle cx='16' cy='25' r='2' fill='#000000'/>"
    )
    return (
        f"<defs><mask id='k'><rect width='32' height='32' fill='#FFFFFF'/>{knock}</mask></defs>"
        f"<rect x='1' y='1' width='30' height='30' rx='5' fill='{color}' mask='url(#k)'/>"
    )


def modern(row):
    """An X4-style line icon on a 32-unit grid: outline when off, filled and colored when on."""
    color, opacity = modern_color(row)
    spec = row["modern"]
    if spec.startswith("battery:"):
        return modern_battery(spec, WHITE if row["state"] == "none" else color, opacity)
    if spec.startswith("frame:"):
        return modern_frame(
            spec[len("frame:") :], color, opacity, row["state"] in ("on", "alert")
        )
    return placed(spec, 1, 1, 30, color, 2, opacity)


def source_of(ref):
    """The glyph a picture is drawn from, as lib:name, or ours for our own drawing."""
    if ref.startswith("battery:"):
        return CHARGING_BOLT if ref.endswith(":charging") else "ours"
    if ref == "ours":
        return "ours"
    return ref.removeprefix("frame:")


def licenses():
    """The licenses pictures carry, by glyph library: ours for our own drawings."""
    table = {
        "ours": {"name": "Finite Labs", "license": OURS["license"], "url": OURS["url"]}
    }
    for lib, spec in LIBRARIES.items():
        table[lib] = {
            "name": spec["name"],
            "license": spec["license"],
            "url": spec["url"],
        }
    return table


def device(row):
    path = DEVICE / f"{row['id']}.svg"
    if not path.exists():
        sys.exit(f"{row['id']}: no Classic Device art at {path.relative_to(ROOT)}")
    box, body = svg_inner(path.read_text(), str(path.relative_to(ROOT)))
    if box != "0 0 1024 1024":
        sys.exit(f"{path.relative_to(ROOT)}: view box {box}, expected 0 0 1024 1024")
    return body


def path_data(body):
    """Every path's data in a picture, in order."""
    return re.findall(r"""\sd=["']([^"']+)["']""", body)


def vendored_paths():
    """{path data: {lib:name}} for every vendored glyph, for telling their art from ours."""
    found = {}
    for lib in LIBRARIES:
        for path in sorted((GLYPHS / lib).glob("*.svg")):
            ref = f"{lib}:{path.stem}"
            for d in path_data(svg_inner(path.read_text(), ref)[1]):
                if len(d) >= 16:
                    found.setdefault(d, set()).add(ref)
    return found


def check_source(icon, vendored):
    """A picture recorded as ours holds no vendored glyph, and a named glyph is in the art."""
    paths = set(path_data(icon["body"]))
    if icon["source"] == "ours":
        held = sorted({ref for d in paths for ref in vendored.get(d, ())})
        if held:
            sys.exit(
                f"{icon['id']}: recorded as our own drawing but contains {', '.join(held)}"
            )
        return
    named = {d for d in path_data(glyph(icon["source"])) if len(d) >= 16}
    if named and not named & paths:
        sys.exit(
            f"{icon['id']}: records {icon['source']} but its path is not in the picture"
        )


def check_body(icon):
    if len(icon["body"].encode()) > MAX_BODY:
        sys.exit(
            f"{icon['id']}: {len(icon['body'].encode())} bytes, more than a look keeps ({MAX_BODY})"
        )
    tags = set(re.findall(r"<([A-Za-z]+)", icon["body"]))
    if tags - SVG_TAGS:
        sys.exit(
            f"{icon['id']}: elements the tab drops: {', '.join(sorted(tags - SVG_TAGS))}"
        )


def render():
    rows = read_list()
    vendored = vendored_paths()
    icons = []
    for pack, build, ref in (
        ("classic-device", device, "device"),
        ("classic-tile", classic_tile, "tile"),
        ("modern", modern, "modern"),
    ):
        for r in rows:
            icon = {
                "id": f"{pack}:{r['id']}",
                "category": r["category"],
                "label": r["label"],
                "state": r["state"],
                "source": source_of(r[ref]),
                "body": build(r),
            }
            check_body(icon)
            check_source(icon, vendored)
            icons.append(icon)
    parts = intern_parts(icons)
    return (
        f"{BEGIN}\nconst ICON_PACKS = {json.dumps(PACKS, separators=(',', ':'))};\n"
        f"const PACK_LICENSES = {json.dumps(licenses(), separators=(',', ':'))};\n"
        f"const PACK_PARTS = {json.dumps(parts, separators=(',', ':'))};\n"
        f"const PACK_ICONS = {json.dumps(icons, separators=(',', ':'))};\n{END}"
    )


def intern_parts(icons):
    """Move markup that pictures share into one list, written in the bodies as @n@.

    Shared parts are long path data and whole repeated elements. The tab puts each part back
    (packIcon in index.html) before it draws or saves a picture.
    """
    patterns = [
        re.compile(r"""(?<=\sd=["'])[^"'@]{120,}(?=["'])"""),
        re.compile(r"<[a-zA-Z][^<>@]{50,}/>"),
    ]
    shared = []
    for pattern in patterns:
        counts = {}
        for icon in icons:
            for m in pattern.finditer(icon["body"]):
                counts[m.group(0)] = counts.get(m.group(0), 0) + 1
        found = sorted(
            (d for d, n in counts.items() if n > 1), key=lambda d: (-counts[d], d)
        )
        base = len(shared)
        shared += found
        index = {d: base + i for i, d in enumerate(found)}
        for icon in icons:
            icon["body"] = pattern.sub(
                lambda m: (
                    f"@{index[m.group(0)]}@" if m.group(0) in index else m.group(0)
                ),
                icon["body"],
            )
    return shared


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "command", nargs="?", choices=["fetch"], help="download missing glyphs"
    )
    parser.add_argument(
        "--check", action="store_true", help="fail if the page's block is out of date"
    )
    args = parser.parse_args()
    if args.command == "fetch":
        fetch(read_list())
        return
    page = PAGE.read_text()
    start, end = page.index(BEGIN), page.index(END) + len(END)
    block = render()
    if args.check:
        if page[start:end] != block:
            sys.exit(
                f"{PAGE.relative_to(ROOT)}: icon packs are out of date; run tools/icon_packs.py"
            )
        return
    PAGE.write_text(page[:start] + block + page[end:])
    count = block.count('"source":')
    print(f"{count} pictures in {len(PACKS)} packs written to {PAGE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
