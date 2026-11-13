#!/usr/bin/env python3
"""Write the picture bank that driver.xml embeds into its display_icons.

The bank is SIZE states, p1 to pSIZE. Each state points every size at one picture, which a
button writes while it runs (src/dynamic_button/bank.lua). Navigators and remotes draw a state
with no gap, and remotes draw nothing else. driver.xml embeds the fragment at build time; run this
again after changing SIZE and commit the result.

Usage: tools/gen_bank.py [--check]
"""

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRAGMENT = ROOT / "drivers" / "dynamic_button" / "generated" / "picture_bank.xml"

# Bank.SIZE in src/dynamic_button/bank.lua.
SIZE = 1024
# The driver's folder on the controller, which names the pictures' addresses.
DRIVER = "dynamic_button"
# The sizes Navigators and remotes ask display_icons for; one picture serves them all.
ICON_SIZES = (70, 90, 300)
INDENT = " " * 10


def fragment() -> str:
    """The bank's states, one per line, indented to sit inside display_icons."""
    lines = []
    for n in range(1, SIZE + 1):
        address = f"controller://driver/{DRIVER}/bank/{n}.png"
        icons = "".join(
            f'<Icon width="{size}" height="{size}">{address}</Icon>'
            for size in ICON_SIZES
        )
        lines.append(f'{INDENT}<state id="p{n}">{icons}</state>')
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if the committed fragment differs",
    )
    args = parser.parse_args()
    wanted = fragment()
    if args.check:
        current = FRAGMENT.read_text(encoding="utf-8") if FRAGMENT.exists() else ""
        if current != wanted:
            print(f"{FRAGMENT.relative_to(ROOT)} is out of date: run tools/gen_bank.py")
            return 1
        return 0
    FRAGMENT.parent.mkdir(parents=True, exist_ok=True)
    FRAGMENT.write_text(wanted, encoding="utf-8")
    print(f"wrote {SIZE} states to {FRAGMENT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
