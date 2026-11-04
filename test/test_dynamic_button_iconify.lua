--- The Iconify requests the driver makes for a Button tab that can't reach Iconify itself: a
--- search limited to the offered packs, icons only from those packs, and nothing else.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_iconify.lua

local T = require("testlib")
require("c4_shim")
local Iconify = require("dynamic_button.iconify")

local PACKS = table.concat(Iconify.PACKS, ",")

T.section("The offered packs")
T.eq("are fourteen", #Iconify.PACKS, 14)
T.truthy("include Material Design Icons", Iconify.allowed("mdi"))
T.falsy("leave out Remix Icon, whose license is no longer open", Iconify.allowed("ri"))
T.falsy("leave out Font Awesome, which needs credit", Iconify.allowed("fa7-solid"))
T.falsy("leave out brand marks", Iconify.allowed("simple-icons"))

T.section("A search")
T.eq(
  "searches only the offered packs",
  Iconify.url("search", "battery"),
  "https://api.iconify.design/search?query=battery&prefixes=" .. PACKS .. "&limit=192"
)
T.eq(
  "encodes what it searches for",
  Iconify.url("search", "  light bulb & fan "),
  "https://api.iconify.design/search?query=light%20bulb%20%26%20fan&prefixes=" .. PACKS .. "&limit=192"
)
T.eq(
  "or only the packs it names",
  Iconify.url("search", "battery", "tabler,lucide"),
  "https://api.iconify.design/search?query=battery&prefixes=tabler,lucide&limit=192"
)
local _, err = Iconify.url("search", "battery", "mdi,simple-icons")
T.eq("refuses a pack not offered among them", err, "not an offered icon pack")
_, err = Iconify.url("search", "battery", ",")
T.eq("and a list that names none", err, "not an offered icon pack")
_, err = Iconify.url("search", "   ")
T.eq("refuses an empty search", err, "search text is empty or too long")
_, err = Iconify.url("search", string.rep("a", Iconify.MAX_QUERY + 1))
T.eq("refuses one over 64 characters", err, "search text is empty or too long")
_, err = Iconify.url("search", "bad\nline")
T.eq("refuses control characters", err, "search text is empty or too long")

T.section("Icons")
T.eq("fetches one icon", Iconify.url("icon", "mdi:battery-50"), "https://api.iconify.design/mdi.json?icons=battery-50")
T.eq(
  "or several of one pack",
  Iconify.url("icon", "tabler:bolt,plug"),
  "https://api.iconify.design/tabler.json?icons=bolt,plug"
)
_, err = Iconify.url("icon", "simple-icons:github")
T.eq("refuses a pack not offered", err, "not an offered icon pack")
_, err = Iconify.url("icon", "mdi:../../collections")
T.eq("refuses a name that is not an icon name", err, "not an offered icon pack")
_, err = Iconify.url("icon", "mdi:a,,b")
T.eq("refuses an empty name in a list", err, "too many icons, or an empty icon name")
local many = {}
for i = 1, Iconify.MAX_ICONS + 1 do
  many[i] = "icon-" .. i
end
_, err = Iconify.url("icon", "mdi:" .. table.concat(many, ","))
T.eq("refuses more than 48 at once", err, "too many icons, or an empty icon name")

T.section("Licenses and anything else")
T.eq(
  "fetches the offered packs' licenses",
  Iconify.url("collections"),
  "https://api.iconify.design/collections?prefixes=" .. PACKS
)
_, err = Iconify.url("anything", "https://example.test/")
T.eq("refuses any other request", err, "unknown request")

T.finish()
