--- Look Control and the cycle under the C4 shim: presses in each mode, Next Look and Previous Look,
--- looks left out of the cycle or without a picture, and each look's own Shown event through adds,
--- renames, deletes, a Director restart, a driver update and Reset Driver.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_cycle.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

--- @return string name The shown look, as the Look variable names it.
local function shown()
  return Variables["Look"]
end

--- Set Look Control as Composer does.
--- @param mode string
local function setLookControl(mode)
  Properties["Look Control"] = mode
  OnPropertyChanged("Look Control")
end

--- @param name string
--- @return integer id
local function lookId(name)
  for _, look in ipairs(H.state().looks) do
    if look.name == name then
      return look.id
    end
  end
  error("no look named " .. name)
end

H.start()
local red = H.addLook("Red")
local green = H.addLook("Green")
local blue = H.addLook("Blue")
local off = H.addLook("Off")

T.section("Look Control starts as Manual")
T.eq("the property's default", Properties["Look Control"], "Manual")
H.tab("_GET_STATE")
T.eq("and the tab shows it", H.state().lookControl, "Manual")
H.mark()
H.press()
T.eq("a press changes nothing", shown(), "Red")
T.eq("tells the proxy nothing", H.lastIcon(), nil)
T.eq("and fires nothing", H.fired, {})

T.section("On Select steps through the looks in order")
H.mark()
setLookControl("On Select")
T.eq("the tab hears the new mode", H.state().lookControl, "On Select")
H.mark()
H.press()
T.eq("a press shows the next look", shown(), "Green")
T.eq("on the button", H.lastIcon().params.icon_description, "Green")
T.eq("and fires Look Changed and the look's own event", H.fired, { "Look Changed", "Green Shown" })
T.eq(
  "the tab hears the new look, and nothing else",
  H.ui,
  { { command = "SHOWN", params = { shown = tostring(green) } } }
)
H.press()
H.press()
T.eq("each press steps on", shown(), "Off")
H.press()
T.eq("and the last look wraps to the first", shown(), "Red")

T.section("Looks left out of the cycle, and looks without a picture")
H.tab("_SAVE_LOOK", H.lookFields("Blue", { id = blue, inCycle = false }))
T.eq("a look can be left out of the cycle", H.state().looks[3].inCycle, false)
T.eq("while the others stay in it", H.state().looks[2].inCycle, true)
H.tab("_SAVE_LOOK", H.lookFields("Spare"))
local spare = lookId("Spare")
T.eq("a new look is in the cycle", H.state().looks[5].inCycle, true)
H.press()
H.press()
T.eq("a press passes over the look left out", shown(), "Off")
H.press()
T.eq("and over a look with no picture yet, wrapping", shown(), "Red")
H.tab("_ORDER_LOOKS", { ids = { off, red, green, blue, spare } })
H.press()
T.eq("the order the looks are listed in is the cycle's order", shown(), "Green")
H.press()
T.eq("wrapping in the new order", shown(), "Off")
H.tab("_ORDER_LOOKS", { ids = { red, green, blue, off, spare } })

T.section("Next Look and Previous Look")
EC.Show_Look({ Look = "Red (" .. red .. ")" })
H.mark()
EC.Next_Look()
T.eq("Next Look shows the next look", shown(), "Green")
T.eq("and fires the look's own event", H.fired, { "Look Changed", "Green Shown" })
EC.Previous_Look()
T.eq("Previous Look steps back", shown(), "Red")
EC.Previous_Look()
T.eq("and wraps from the first look to the last one it can show", shown(), "Off")
setLookControl("Manual")
H.mark()
H.press()
T.eq("under Manual a press changes nothing", shown(), "Off")
T.eq("and fires nothing", H.fired, {})
EC.Next_Look()
T.eq("while Next Look still works", shown(), "Red")
EC.Previous_Look()
T.eq("and so does Previous Look", shown(), "Off")
EC.Show_Look({ Look = "Blue (" .. blue .. ")" })
T.eq("Show Look shows a look left out of the cycle", shown(), "Blue")
EC.Next_Look()
T.eq("and the cycle goes on from its place", shown(), "Off")
EC.Show_Look({ Look = "Blue (" .. blue .. ")" })
EC.Previous_Look()
T.eq("in either direction", shown(), "Green")
for _, id in ipairs({ red, off }) do
  H.tab("_SAVE_LOOK", H.lookFields(id == red and "Red" or "Off", { id = id, inCycle = false }))
end
H.mark()
EC.Next_Look()
T.eq("with one look left in the cycle, and it shown, Next Look changes nothing", shown(), "Green")
T.eq("and fires nothing", H.fired, {})
for _, id in ipairs({ red, off }) do
  H.tab("_SAVE_LOOK", H.lookFields(id == red and "Red" or "Off", { id = id, inCycle = true }))
end

T.section("Each look's own event")
local ids = H.eventIds()
T.truthy("each look has one", ids["Red Shown"] and ids["Green Shown"] and ids["Blue Shown"] and ids["Off Shown"])
T.truthy("so does a look with no picture yet", ids["Spare Shown"])
T.truthy("in the range kept for dynamic events", ids["Red Shown"] >= 10 and ids["Red Shown"] <= 999)
T.eq(
  "described with the button's name, as Composer titles it",
  ShimEvents()[ids["Off Shown"]].description,
  "When NAME shows Off"
)
H.tab("_SAVE_LOOK", H.lookFields("Lime", { id = green }))
local renamed = H.eventIds()
T.eq("a rename keeps the event's id", renamed["Lime Shown"], ids["Green Shown"])
T.eq("under the new name", renamed["Green Shown"], nil)
H.tab("_DELETE_LOOK", { id = spare })
T.eq("deleting a look deletes its event", H.eventIds()["Spare Shown"], nil)
T.eq("and only its", H.eventIds()["Red Shown"], ids["Red Shown"])
H.mark()
H.tab("_SHOW_LOOK", { id = blue })
T.eq("the event fires when the tab shows the look", H.fired, { "Look Changed", "Blue Shown" })
H.mark()
EC.Show_Look({ Look = "Lime (" .. green .. ")" })
T.eq("and when programming does", H.fired, { "Look Changed", "Lime Shown" })
H.mark()
EC.Show_Look({ Look = "Lime (" .. green .. ")" })
T.eq("but not when the look shown is shown again", H.fired, {})

T.section("A Director restart")
setLookControl("On Select")
local before = H.eventIds()
H.mark()
H.restart()
T.eq("the shown look is kept", shown(), "Lime")
T.eq("and shown", H.lastIcon().params.icon_description, "Lime")
T.eq("each look's event is declared again under its id", H.eventIds(), before)
T.eq("and nothing fires at start", H.fired, {})
H.tab("_GET_STATE")
T.eq("Look Control is kept", H.state().lookControl, "On Select")
H.mark()
EC.Next_Look()
T.eq("the cycle goes on after the restart, still passing over Blue", shown(), "Off")
T.eq("firing the event declared again", H.fired, { "Look Changed", "Off Shown" })

T.section("A driver update")
setLookControl("On Select")
before = H.eventIds()
H.mark()
H.update()
T.eq("the shown look is kept", shown(), "Off")
T.eq("each look's event keeps its id", H.eventIds(), before)
T.eq("and nothing fires at start", H.fired, {})
T.truthy("a tab left open hears the state", H.lastUi("STATE"))
H.press()
T.eq("presses still step the cycle", shown(), "Red")

T.section("Looks from a build without events")
require("lib.events"):reset()
H.mark()
H.restart()
local started = H.eventIds()
T.truthy("get their events at start", started["Red Shown"] and started["Off Shown"])
T.eq("and nothing fires", H.fired, {})

T.section("A press the driver doesn't act on")
H.mark()
ReceivedFromProxy(6001, "SELECT", {})
T.eq("a SELECT on another binding changes nothing", shown(), "Red")
setLookControl("Sideways")
H.press()
T.eq("nor does a press under a Look Control this build doesn't know", shown(), "Red")
T.eq("which the tab shows as Manual", H.state().lookControl, "Manual")
T.eq("and nothing fires", H.fired, {})
setLookControl("On Select")

T.section("A look whose picture can't be served")
local function cantServe(name)
  local file = lookId(name) .. ".png"
  ShimFiles("C4Z/www/buttons/" .. H.DEVICE_ID)[file] = nil
  H.unopenable["C4Z/www/buttons/" .. H.DEVICE_ID .. "/" .. file] = true
end
cantServe("Lime")
H.mark()
H.press()
T.eq("a press passes over it to the next look", shown(), "Off")
T.truthy("and the tab hears the whole state, since the look passed over may have changed", H.lastUi("STATE"))
EC.Show_Look({ Look = "Blue (" .. blue .. ")" })
for _, name in ipairs({ "Red", "Off" }) do
  cantServe(name)
end
H.mark()
EC.Previous_Look()
T.eq("when no look in the cycle can be served, the shown look stays", shown(), "Blue")
T.eq("and nothing fires", H.fired, {})
T.truthy("but the tab is told", H.lastUi("STATE"))
H.unopenable = {}

T.section("A look added after a delete")
local newest = H.addLook("Amber")
local afterAdd = H.eventIds()
T.truthy("gets its own event", afterAdd["Amber Shown"])
local taken = {}
for name, id in pairs(afterAdd) do
  if name ~= "Amber Shown" and name:match(" Shown$") then
    taken[id] = name
  end
end
T.eq("under an id no other look's event has", taken[afterAdd["Amber Shown"]], nil)
T.eq("and the new look is in the cycle", H.state().looks[5].id, newest)

T.section("Reset Driver")
H.mark()
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
local left = {}
for name in pairs(H.eventIds()) do
  if name:match(" Shown$") then
    table.insert(left, name)
  end
end
T.eq("deletes every look's event", left, {})
T.eq("and forgets them", require("lib.events"):getEvents(), {})
T.eq("Look Control returns to Manual", Properties["Look Control"], "Manual")
T.eq("no event fires", H.fired, {})
local again = H.addLook("Again")
T.truthy("a new look gets an event again", H.eventIds()["Again Shown"])

T.section("Stepping from the driver's own icon")
local q = H.addLook("Q")
H.addLook("R")
H.addLook("S")
H.stored()["look-" .. q .. ".png"] = nil
H.tab("_DELETE_LOOK", { id = again })
T.eq("the button shows its own icon", shown(), "")
EC.Previous_Look()
T.eq("Previous Look shows the last look that can show", shown(), "S")
local t = H.addLook("T")
H.stored()["look-" .. t .. ".png"] = nil
EC.Next_Look()
T.eq("a look whose stored picture is gone is passed over", shown(), "R")

T.finish()
