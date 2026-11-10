--- A button's looks: adding, editing, ordering and deleting them, what a look may be called and
--- drawn with, the programming labels that survive a rename, and that they persist.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_looks.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Looks = require("dynamic_button.looks")
require("lib.utils")

--- A persist-like store that hands out copies, as lib.persist does, so a change that is not saved
--- is lost here as it would be there.
local function memoryStore()
  local data = {}
  return {
    get = function(_, key, default)
      local v = data[key]
      if v == nil then
        return default
      end
      return TableDeepCopy(v)
    end,
    set = function(_, key, value)
      data[key] = TableDeepCopy(value)
    end,
  }
end

T.section("Adding looks")
local looks = Looks:new(memoryStore())
local a = looks:add(H.lookFields("Charged"))
local b = looks:add(H.lookFields("Low"))
T.eq("the first look is id 1", a.id, 1)
T.eq("the next is id 2", b.id, 2)
T.eq("they list in the order added", { looks:list()[1].name, looks:list()[2].name }, { "Charged", "Low" })
T.eq("colors are kept as #RRGGBB upper case", a.iconColor, "#FFFFFF")
T.eq("the icon's pack and license are kept", { a.icon.id, a.icon.license }, { "mdi:battery-50", "Apache 2.0" })
T.eq("a new look has no picture yet", a.image, nil)

T.section("A look's name")
local _, err = looks:add(H.lookFields("   "))
T.eq("an empty name is refused", err, "a look needs a name")
_, err = looks:add(H.lookFields("charged"))
T.eq("a name another look has is refused, in any case", err, "another look is already named Charged")
_, err = looks:add(H.lookFields("Red, White"))
T.eq("a comma is refused, since programming lists are comma-separated", err, "a look's name can't contain a comma")
_, err = looks:add(H.lookFields(string.rep("n", Looks.MAX_NAME + 1)))
T.eq("a name over the limit is refused", err, "a look's name can be at most 40 characters")
local accented = looks:add(H.lookFields("Éclairage extérieur à l'arrière"))
T.eq("a name is counted in characters, not bytes", accented and accented.name, "Éclairage extérieur à l'arrière")
_, err = looks:add(H.lookFields(string.rep("é", Looks.MAX_NAME + 1)))
T.eq("and refused past 40 of them", err, "a look's name can be at most 40 characters")
looks:delete(accented.id)
local trimmed = looks:add(H.lookFields("  Full  "))
T.eq("a name is trimmed", trimmed.name, "Full")
looks:delete(trimmed.id)

T.section("How a look is drawn")
_, err = looks:add(H.lookFields("Bad Color", { iconColor = "white" }))
T.eq("a color that is not #RRGGBB is refused", err, "colors are #RRGGBB")
_, err = looks:add(H.lookFields("Bad Shape", { tileShape = "Hexagon" }))
T.eq("an unknown tile shape is refused", err, "unknown tile shape")
local noIcon = H.lookFields("No Icon")
noIcon.icon = nil
_, err = looks:add(noIcon)
T.eq("a look needs an icon", err, "a look needs an icon")
local badIcon = H.lookFields("Bad Icon")
badIcon.icon.id = "not an icon"
_, err = looks:add(badIcon)
T.eq("an icon name that is not <pack>:<name> is refused", err, "the icon's name is not an icon pack name")
local bigIcon = H.lookFields("Big Icon")
bigIcon.icon.body = string.rep("x", Looks.MAX_ICON_BODY + 1)
_, err = looks:add(bigIcon)
T.eq("an icon over 16 KB is refused", err, "the icon's picture is missing or too large")
local plainLicense = H.lookFields("Plain License")
plainLicense.icon.licenseUrl = "http://example.test/license"
_, err = looks:add(plainLicense)
T.eq("a license address must be https", err, "the icon's license address is not an https address")
for _, shape in ipairs(Looks.SHAPES) do
  local look = looks:add(H.lookFields("Shape " .. shape, { tileShape = shape }))
  T.eq("tile shape " .. shape .. " is taken", look and look.tileShape, shape)
  looks:delete(look.id)
end

T.section("Icons the Button tab carries")
--- @param id string
--- @return table icon An icon as the tab sends one it draws from its id.
local function carried(id)
  return { id = id, carried = true, width = 1024, height = 1024, license = "Own drawings", licenseUrl = "" }
end
local packStore = memoryStore()
local packLooks = Looks:new(packStore)
local pack, packErr = packLooks:add(H.lookFields("Lamp", { icon = carried("classic-device:lamp") }))
T.eq("a pack picture sent without its markup is taken", packErr, nil)
T.eq("and kept without it", pack.icon.body, nil)
T.eq("marked as carried", pack.icon.carried, true)
T.eq(
  "with its name, size and license",
  { pack.icon.id, pack.icon.width, pack.icon.height, pack.icon.license },
  { "classic-device:lamp", 1024, 1024, "Own drawings" }
)
T.eq("and so it reads back", packLooks:get(pack.id).icon.body, nil)
local included = packLooks:add(H.lookFields("Battery", { icon = carried("mdi:battery-50") }))
T.eq("an included icon sent without its markup is kept without it", included and included.icon.body, nil)
local sentBody = carried("modern:tv")
sentBody.body = '<path d="M0 0h1v1z"/>'
local tv = packLooks:add(H.lookFields("TV", { icon = sentBody }))
T.eq("a carried icon's markup, if sent, is not kept", tv and tv.icon.body, nil)
local bare = H.lookFields("Bare")
bare.icon.body = nil
_, err = packLooks:add(bare)
T.eq("an icon with no markup that is not carried is refused", err, "the icon's picture is missing or too large")
local loose = H.lookFields("Loose", { icon = carried("mdi:battery") })
loose.icon.carried = "yes"
_, err = packLooks:add(loose)
T.eq("only carried = true marks an icon carried", err, "the icon's picture is missing or too large")

local oldStore = memoryStore()
oldStore:set("Looks", {
  nextId = 2,
  list = {
    {
      id = 1,
      name = "Drawn",
      icon = H.lookFields("Drawn").icon,
      iconColor = "#FFFFFF",
      tileShape = "Circle",
      tileColor = "#109EFF",
      image = { bytes = 10 },
    },
  },
})
local oldLooks = Looks:new(oldStore)
T.eq("a look saved with its markup keeps it", oldLooks:get(1).icon.body, H.lookFields("Drawn").icon.body)
local resaved = oldLooks:update(1, H.lookFields("Drawn", { tileShape = "Circle", tileColor = "#109EFF" }))
T.eq("saved again with it, it still validates", resaved and resaved.icon.body, H.lookFields("Drawn").icon.body)
T.falsy("and its picture stays current", resaved.image.stale)
local nowCarried = carried("mdi:battery-50")
nowCarried.width, nowCarried.height = 24, 24
local moved =
  oldLooks:update(1, H.lookFields("Drawn", { icon = nowCarried, tileShape = "Circle", tileColor = "#109EFF" }))
T.eq("saved as carried, it drops the markup", moved.icon.body, nil)
T.falsy("and the same icon keeps its picture current", moved.image.stale)
oldLooks:setImage(1, 11)
local other = oldLooks:update(
  1,
  H.lookFields("Drawn", { icon = carried("modern:tv"), tileShape = "Circle", tileColor = "#109EFF" })
)
T.truthy("a carried icon of another name is a change to the picture", other.image.stale)

T.section("At most eight looks")
local store = memoryStore()
local full = Looks:new(store)
for i = 1, Looks.MAX do
  T.truthy("look " .. i .. " is added", full:add(H.lookFields("Look " .. i)))
end
local nine, nineErr = full:add(H.lookFields("Look 9"))
T.eq("a ninth is refused", nine, nil)
T.eq("and says why", nineErr, "a button has at most 8 looks")
full:delete(3)
local again = full:add(H.lookFields("Look 9"))
T.eq("after a delete there is room again, and ids are never reused", again and again.id, 9)

T.section("Editing a look")
looks:setImage(a.id, 1234)
local edited = looks:update(a.id, H.lookFields("Charged", { iconColor = "#000000", tileShape = "Circle" }))
T.eq("its fields change", { edited.iconColor, edited.tileShape }, { "#000000", "Circle" })
T.eq("it keeps its id", edited.id, a.id)
T.eq("it keeps its picture until a new one arrives", edited.image and edited.image.bytes, 1234)
T.truthy("marked out of date, since it was drawn from other fields", edited.image.stale)
T.falsy("until a new picture arrives", looks:setImage(a.id, 2345).image.stale)
local renamed = looks:update(a.id, H.lookFields("Full", { iconColor = "#000000", tileShape = "Circle" }))
T.eq("it can be renamed", renamed.name, "Full")
T.falsy("and a rename leaves the picture current", renamed.image.stale)
T.eq("a look whose stored picture is gone loses its mark", looks:setImage(b.id, nil).image, nil)
local _, clash = looks:update(a.id, H.lookFields("Low"))
T.eq("but not to another look's name", clash, "another look is already named Low")
T.eq("keeping its own name is no clash", looks:update(b.id, H.lookFields("Low")) ~= nil, true)
local _, gone = looks:update(99, H.lookFields("Nothing"))
T.eq("a look that is gone can't be edited", gone, "no such look")

T.section("The cycle")
T.truthy("a look is in the cycle unless the tab says otherwise", Looks.inCycle(looks:get(a.id)))
local left = looks:update(a.id, H.lookFields("Full", { iconColor = "#000000", tileShape = "Circle", inCycle = false }))
T.falsy("it can be left out", Looks.inCycle(left))
T.falsy("which is no change to its picture", left.image.stale)
T.truthy(
  "and back in",
  Looks.inCycle(looks:update(a.id, H.lookFields("Full", { iconColor = "#000000", tileShape = "Circle" })))
)
T.truthy("a look stored without the field is in it", Looks.inCycle({ id = 9, name = "Old" }))

T.section("Glow and grayscale")
T.eq("a look draws its picture's full glow unless the tab says otherwise", looks:get(a.id).glow, 100)
T.falsy("and in color", looks:get(a.id).grayscale)
T.eq("a look stored without the glow draws it in full", Looks.glow({ id = 9, name = "Old" }), 100)
T.falsy("and in color", Looks.grayscale({ id = 9, name = "Old" }))
local drawn = { iconColor = "#000000", tileShape = "Circle" }
local function withDrawn(extra)
  local fields = TableDeepCopy(drawn)
  for k, v in pairs(extra or {}) do
    fields[k] = v
  end
  return H.lookFields("Full", fields)
end
looks:setImage(a.id, 3456)
local dimmed = looks:update(a.id, withDrawn({ glow = 40 }))
T.eq("a glow is kept", dimmed.glow, 40)
T.truthy("and is a change to the picture", dimmed.image.stale)
looks:setImage(a.id, 3457)
local gray = looks:update(a.id, withDrawn({ glow = 40, grayscale = true }))
T.truthy("grayscale is kept", gray.grayscale)
T.truthy("and is a change to the picture", gray.image.stale)
T.eq("a grayscale look keeps its glow for when it is in color again", gray.glow, 40)
T.eq("which it is again with grayscale off", looks:update(a.id, withDrawn({ glow = 40 })).glow, 40)
for _, bad in ipairs({ -1, 201, 40.5, "40", true }) do
  local _, why = looks:update(a.id, withDrawn({ glow = bad }))
  T.eq("a glow of " .. tostring(bad) .. " is refused", why, "glow is a whole percent from 0 to 200")
end
for _, ok in ipairs({ 0, 100, 200 }) do
  T.eq("a glow of " .. ok .. " is taken", looks:update(a.id, withDrawn({ glow = ok })).glow, ok)
end
local _, grayWhy = looks:update(a.id, withDrawn({ grayscale = "yes" }))
T.eq("grayscale must be on or off", grayWhy, "grayscale is on or off")
local store2 = memoryStore()
store2:set("Looks", {
  nextId = 2,
  list = {
    {
      id = 1,
      name = "Old",
      icon = H.lookFields("Old").icon,
      iconColor = "#FFFFFF",
      tileShape = "Circle",
      tileColor = "#109EFF",
      image = { bytes = 10 },
    },
  },
})
local old = Looks:new(store2):update(1, H.lookFields("Old", { tileShape = "Circle", tileColor = "#109EFF" }))
T.falsy("saving a look stored before glow and grayscale, unchanged, keeps its picture current", old.image.stale)
looks:update(a.id, withDrawn())

T.section("Customization")
T.eq("a look has none unless the tab sets some", looks:get(a.id).custom, nil)
T.eq(
  "a look stored without it reads the same",
  Looks.customKey({ id = 9, name = "Old" }),
  Looks.customKey(looks:get(a.id))
)
local badge = { text = "50%", place = "Under", color = "#ffffff", background = "#3e9a1e" }
local custom = {
  color = "#14a39a",
  body = "#2F80D8",
  tile = "#2E9C5A",
  symbol = "#FFD36E",
  glowColor = "#3FC0B6",
  size = 84,
  x = -4,
  y = 6,
  badge = badge,
}
looks:setImage(a.id, 4567)
local styled = looks:update(a.id, withDrawn({ custom = custom }))
T.eq(
  "its colors are kept, as #RRGGBB",
  { styled.custom.color, styled.custom.body, styled.custom.glowColor },
  { "#14A39A", "#2F80D8", "#3FC0B6" }
)
T.eq("so are its size and position", { styled.custom.size, styled.custom.x, styled.custom.y }, { 84, -4, 6 })
T.eq("and its badge", styled.custom.badge, { text = "50%", place = "Under", color = "#FFFFFF", background = "#3E9A1E" })
T.truthy("which is a change to the picture", styled.image.stale)
looks:setImage(a.id, 4568)
T.falsy(
  "saving it again unchanged keeps the picture current",
  looks:update(a.id, withDrawn({ custom = custom })).image.stale
)
local moved = TableDeepCopy(custom)
moved.x = -2
T.truthy("moving it is a change", looks:update(a.id, withDrawn({ custom = moved })).image.stale)
looks:setImage(a.id, 4569)
local rebadged = TableDeepCopy(moved)
rebadged.badge.text = "OFF"
T.truthy("so is new badge text", looks:update(a.id, withDrawn({ custom = rebadged })).image.stale)
looks:setImage(a.id, 4570)
T.truthy("and so is taking it all away", looks:update(a.id, withDrawn()).image.stale)
local plain = looks:update(a.id, withDrawn({ custom = { size = 100, x = 0, y = 0, unknown = "kept?" } }))
T.eq("the picture's own size and place, and keys the driver doesn't know, are no customization", plain.custom, nil)
local extra = looks:update(
  a.id,
  withDrawn({
    custom = {
      size = 90,
      shadow = "none",
      badge = { text = "1", place = "Under", color = "#FFFFFF", background = "None", font = "x" },
    },
  })
)
T.eq(
  "unknown keys are dropped",
  extra.custom,
  { size = 90, badge = { text = "1", place = "Under", color = "#FFFFFF", background = "None" } }
)
for _, ok in ipairs({ 50, 100 }) do
  T.truthy("a size of " .. ok .. " is taken", looks:update(a.id, withDrawn({ custom = { size = ok } })) ~= nil)
end
for _, bad in ipairs({ 49, 101, 75.5, "80" }) do
  local _, why = looks:update(a.id, withDrawn({ custom = { size = bad } }))
  T.eq("a size of " .. tostring(bad) .. " is refused", why, "size is a whole percent from 50 to 100")
end
for _, ok in ipairs({ -10, 10 }) do
  T.eq(
    "a position of " .. ok .. " is taken",
    looks:update(a.id, withDrawn({ custom = { x = ok, y = ok } })).custom,
    { x = ok, y = ok }
  )
end
for _, bad in ipairs({ -11, 11, 2.5, "4" }) do
  local _, why = looks:update(a.id, withDrawn({ custom = { y = bad } }))
  T.eq("a position of " .. tostring(bad) .. " is refused", why, "position is a whole percent from -10 to 10")
end
local _, colorWhy = looks:update(a.id, withDrawn({ custom = { tile = "green" } }))
T.eq("a color that is not #RRGGBB is refused", colorWhy, "colors are #RRGGBB")
local _, tableWhy = looks:update(a.id, withDrawn({ custom = "bright" }))
T.eq("a customization that is not a table is refused", tableWhy, "a look's customization is a table")
local function badgeWhy(b)
  local _, why = looks:update(a.id, withDrawn({ custom = { badge = b } }))
  return why
end
T.eq(
  "five characters are a badge",
  looks:update(
    a.id,
    withDrawn({ custom = { badge = { text = "HDMI1", place = "Top Right", color = "#FFFFFF", background = "None" } } })
  ).custom.badge.text,
  "HDMI1"
)
T.eq(
  "counted as characters, not bytes",
  looks:update(
    a.id,
    withDrawn({ custom = { badge = { text = "20°C", place = "Under", color = "#FFFFFF", background = "None" } } })
  ).custom.badge.text,
  "20°C"
)
T.eq(
  "six are too many",
  badgeWhy({ text = "HDMI12", place = "Under", color = "#FFFFFF", background = "None" }),
  "a badge is 1 to 5 characters"
)
T.eq(
  "an empty badge is refused",
  badgeWhy({ text = "  ", place = "Under", color = "#FFFFFF", background = "None" }),
  "a badge is 1 to 5 characters"
)
T.eq(
  "so are control characters",
  badgeWhy({ text = "a\nb", place = "Under", color = "#FFFFFF", background = "None" }),
  "a badge can't hold control characters"
)
T.eq(
  "and a place it can't sit",
  badgeWhy({ text = "1", place = "Left", color = "#FFFFFF", background = "None" }),
  "unknown badge place"
)
T.eq(
  "and a background that is neither a color nor None",
  badgeWhy({ text = "1", place = "Under", color = "#FFFFFF", background = "clear" }),
  "a badge's colors are #RRGGBB, and its background can be None"
)
T.eq("a badge without its fields is refused", badgeWhy("50%"), "a badge needs its text, place and colors")
looks:update(a.id, withDrawn())

T.section("Programming labels")
T.eq("a look is listed by name and id", Looks.label(looks:get(a.id)), "Full (1)")
local unsaved = looks:get(a.id)
unsaved.name = "Changed without saving"
T.eq("a listed look changed without saving changes nothing", looks:get(a.id).name, "Full")
T.eq("a label finds its look by the id", looks:fromChoice("Charged (1)").name, "Full")
T.eq("so a choice made before a rename still finds it", looks:fromChoice("Charged (1)").id, a.id)
T.eq("a bare name finds a look too", looks:fromChoice("low").id, b.id)
T.eq("a label whose look is deleted finds nothing", looks:fromChoice("Gone (7)"), nil)

T.section("Ordering looks")
local c = looks:add(H.lookFields("Charging"))
T.truthy("a full new order is taken", looks:reorder({ c.id, a.id, b.id }))
T.eq("and kept", { looks:list()[1].id, looks:list()[2].id, looks:list()[3].id }, { c.id, a.id, b.id })
local ok, orderErr = looks:reorder({ c.id, a.id })
T.falsy("an order missing a look is refused", ok)
T.eq("and says why", orderErr, "the order must name every look once")
T.falsy("an order naming a look twice is refused", looks:reorder({ c.id, a.id, a.id }))
T.falsy("an order naming an unknown look is refused", looks:reorder({ c.id, a.id, 42 }))
T.eq("a refused order changes nothing", looks:list()[1].id, c.id)

T.section("Deleting looks")
T.eq("a delete returns the look", looks:delete(b.id).name, "Low")
T.eq("and it is gone", looks:get(b.id), nil)
T.eq("deleting it again finds nothing", looks:delete(b.id), nil)

T.section("Looks persist")
local persist = require("lib.persist")
local saved = Looks:new(persist)
saved:clear()
local kept = saved:add(H.lookFields("Kept"))
saved:setImage(kept.id, 99)
ShimPersistLand()
local reloaded = Looks:new(getmetatable(persist):new())
T.eq("a new persist instance reads the look back", reloaded:get(kept.id).name, "Kept")
T.eq("with its picture's size", reloaded:get(kept.id).image.bytes, 99)
T.eq("and the next id goes on from where it was", reloaded:add(H.lookFields("Next")).id, kept.id + 1)
local nextId = kept.id + 2
reloaded:clear()
T.eq("clear forgets them", #reloaded:list(), 0)
T.eq(
  "but ids go on, so an old programming choice never names a new look",
  reloaded:add(H.lookFields("Fresh")).id,
  nextId
)

T.section("A badge's size")
local function sizedBadge(size)
  return { text = "1", place = "Under", color = "#FFFFFF", background = "None", size = size }
end
T.eq(
  "a badge keeps its size",
  looks:update(a.id, withDrawn({ custom = { badge = sizedBadge(130) } })).custom.badge.size,
  130
)
T.eq(
  "100 percent isn't kept, since it's what a badge has anyway",
  looks:update(a.id, withDrawn({ custom = { badge = sizedBadge(100) } })).custom.badge.size,
  nil
)
for _, size in ipairs({ 40, 160, 75.5, "big" }) do
  T.contains("a size of " .. tostring(size) .. " is refused", badgeWhy(sizedBadge(size)), "whole percent")
end
looks:setImage(a.id, 5678)
T.truthy(
  "a new size asks for a new picture",
  looks:update(a.id, withDrawn({ custom = { badge = sizedBadge(120) } })).image.stale
)

T.section("A look can't follow this button's own variables, and its Show when must read as one")
local guarded = Looks:new(memoryStore(), nil, nil, function()
  return { 4242, 4243 }
end)
local tried = 0
--- @param extra table
--- @return string|nil err Why the look wasn't added.
local function guardWhy(extra)
  tried = tried + 1
  local _, err = guarded:add(H.lookFields("Guarded " .. tried, extra))
  return err
end
local function liveBadge(text)
  return { badge = { text = text, place = "Under", color = "#FFFFFF", background = "None" } }
end
T.eq("its device's variable is refused", guardWhy({ showWhen = 'PARAM{4242,1} == "On"' }), Looks.OWN_VARIABLES)
T.eq("and its proxy's", guardWhy({ showWhen = "PARAM{ 4243 , LOOK } == 1" }), Looks.OWN_VARIABLES)
T.eq("another device's is kept", guardWhy({ showWhen = "PARAM{100,1} > 3" }), nil)
T.eq(
  "its own in a line comment isn't read, so it's kept",
  guardWhy({ showWhen = "PARAM{100,1} > 3 -- was PARAM{4242,1} == 'x'" }),
  nil
)
T.eq("nor in a block comment", guardWhy({ showWhen = "PARAM{100,1} > 3 --[[ PARAM{4242,1} == 'x' ]]" }), nil)
T.eq(
  "but its own inside a string is read, so refused",
  guardWhy({ showWhen = "'PARAM{4242,1}' == 'x'" }),
  Looks.OWN_VARIABLES
)
T.eq(
  "a live badge on its own variable is refused",
  guardWhy({ custom = liveBadge("PARAM{4242,1}") }),
  Looks.OWN_VARIABLES
)
T.eq("one on another device's is kept", guardWhy({ custom = liveBadge("PARAM{100,1}%") }), nil)
T.eq(
  "a Show when that doesn't read as an expression is refused, as the engine words it",
  guardWhy({ showWhen = "PARAM{100,1} >=" }),
  '"Show when": compile error: [string "return __p[1] >="]:1: unexpected symbol near \'<eof>\''
)
T.eq("a variable inside a string still reads", guardWhy({ showWhen = '"PARAM{100,1}" == "x"' }), nil)
T.eq("a comparison of two variables reads", guardWhy({ showWhen = "PARAM{100,1} >= PARAM{100,2} and true" }), nil)
T.eq(
  "without the ids, any device's variable is kept",
  select(2, looks:add(H.lookFields("Unguarded", { showWhen = "PARAM{4242,1} == 1" }))),
  nil
)

T.finish()
