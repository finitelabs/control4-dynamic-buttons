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

T.finish()
