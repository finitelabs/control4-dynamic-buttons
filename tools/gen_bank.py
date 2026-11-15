#!/usr/bin/env python3
"""Write the picture bank that driver.xml embeds into its display_icons.

The bank is SIZE states, p1 to pSIZE, each pointing at one picture that a button writes while it
runs (src/dynamic_button/bank.lua). driver.xml embeds the fragment at build time; run this again
after changing SIZE and commit the result.

Usage: tools/gen_bank.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRAGMENT = ROOT / "drivers" / "dynamic_button" / "generated" / "picture_bank.xml"

# Bank.SIZE in src/dynamic_button/bank.lua.
SIZE = 256
# The driver's folder on the controller, which names the pictures' addresses.
DRIVER = "dynamic_button"
# One Icon per state: every state goes to every Navigator for every button, so the bank's size is
# paid on each Navigator sync.
ICON_SIZE = 300
INDENT = " " * 10


def fragment() -> str:
    """The bank's states, one per line, indented to sit inside display_icons."""
    lines = []
    for n in range(1, SIZE + 1):
        address = f"controller://driver/{DRIVER}/bank/{n}.png"
        icon = f'<Icon width="{ICON_SIZE}" height="{ICON_SIZE}">{address}</Icon>'
        lines.append(f'{INDENT}<state id="p{n}">{icon}</state>')
    return "\n".join(lines) + "\n"


def main() -> int:
    FRAGMENT.parent.mkdir(parents=True, exist_ok=True)
    FRAGMENT.write_text(fragment(), encoding="utf-8")
    print(f"wrote {SIZE} states to {FRAGMENT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
