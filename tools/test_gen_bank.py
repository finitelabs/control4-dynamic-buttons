#!/usr/bin/env python3
"""Tests for tools/gen_bank.py: the committed picture bank is the one it writes, and driver.xml
embeds it inside the proxy's display_icons."""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_bank import FRAGMENT, ROOT, SIZE, fragment  # noqa: E402

XML = ROOT / "drivers" / "dynamic_button" / "driver.xml"
BANK_LUA = ROOT / "src" / "dynamic_button" / "bank.lua"


class PictureBankTest(unittest.TestCase):
    def test_committed_fragment_is_current(self):
        self.assertEqual(
            FRAGMENT.read_text(encoding="utf-8"),
            fragment(),
            "run tools/gen_bank.py and commit the result",
        )

    def test_every_state_once_in_order(self):
        ids = re.findall(r'<state id="p(\d+)">', fragment())
        self.assertEqual([int(i) for i in ids], list(range(1, SIZE + 1)))

    def test_driver_xml_embeds_it_inside_display_icons(self):
        xml = XML.read_text(encoding="utf-8")
        icons = re.search(r"<display_icons>(.*?)</display_icons>", xml, re.S)
        self.assertIsNotNone(icons)
        self.assertIn("<!-- #embed generated/picture_bank.xml -->", icons.group(1))

    def test_size_matches_the_driver(self):
        size = re.search(r"Bank\.SIZE = (\d+)", BANK_LUA.read_text(encoding="utf-8"))
        self.assertIsNotNone(size)
        self.assertEqual(int(size.group(1)), SIZE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
