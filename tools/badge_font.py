#!/usr/bin/env python3
"""Write src/dynamic_button/badge_font_data.lua: the Button tab's badge face as packed outlines.

The face is read from BADGE_FONT in the Button tab, so a live badge matches a badge the tab draws.
Run from the repo root when that face changes:

    uvx --with brotli --from fonttools python tools/badge_font.py
"""

import base64
import io
import re

from fontTools.ttLib import TTFont

PAGE = "drivers/dynamic_button/www/html/index.html"
OUT = "src/dynamic_button/badge_font_data.lua"
QUANTUM = 4
CHARS = [chr(c) for c in range(32, 127)] + ["°"]
LINE = 96


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append(value % 128 + 128)
        value //= 128
    out.append(value)
    return bytes(out)


def zigzag(value):
    return value * 2 if value >= 0 else -value * 2 - 1


def main():
    with open(PAGE, encoding="utf-8") as f:
        match = re.search(
            r"var BADGE_FONT = 'data:font/woff2;base64,([^']+)'", f.read()
        )
    font = TTFont(io.BytesIO(base64.b64decode(match.group(1))))
    cmap, glyf, hmtx = font.getBestCmap(), font["glyf"], font["hmtx"]
    assert font["head"].unitsPerEm == 2048
    out = bytearray(varint(QUANTUM))
    for char in CHARS:
        name = cmap[ord(char)]
        coords, ends, flags = glyf[name].getCoordinates(glyf)
        out += varint(ord(char)) + varint(hmtx[name][0]) + varint(len(ends))
        x, y, start = 0, 0, 0
        for end in ends:
            out += varint(end - start + 1)
            for i in range(start, end + 1):
                nx, ny = round(coords[i][0] / QUANTUM), round(coords[i][1] / QUANTUM)
                out += varint(zigzag(nx - x) * 2 + (flags[i] & 1)) + varint(
                    zigzag(ny - y)
                )
                x, y = nx, ny
            start = end + 1
    data = base64.b64encode(bytes(out)).decode()
    lines = [data[i : i + LINE] for i in range(0, len(data), LINE)]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("-- Written by tools/badge_font.py.\n")
        f.write("return table.concat({\n")
        f.writelines('  "%s",\n' % line for line in lines)
        f.write("})\n")
    print("%d glyphs, %d bytes" % (len(CHARS), len(out)))


if __name__ == "__main__":
    main()
