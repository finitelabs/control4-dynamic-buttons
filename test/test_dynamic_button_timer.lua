--- A look's timer under the C4 shim: its fields, going back to the look before or to a chosen look,
--- what starts and stops it, a deleted look, By Value, a Director restart and a driver update, the
--- replay Copy To and Import make, Reset Driver, and a lapsed license.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_timer.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local persist = require("lib.persist")
local gate = require("lib.drivercentral")

local clock = 1000000
-- luacheck: push ignore os
os.time = function()
  return clock
end
-- luacheck: pop

local delays = {}
local setTimer = C4.SetTimer
function C4:SetTimer(ms, fn, repeating)
  local handle = setTimer(self, ms, fn, repeating)
  delays[handle] = ms
  return handle
end

--- @return number|nil seconds What the look's timer is set for, while one is set.
local function timerSet()
  local handle = Timer.LookTimer
  return handle and delays[handle] / 1000 or nil
end

--- The look's time passes, and the shim runs every timer due, the look's among them.
local function timeUp()
  clock = clock + (timerSet() or 0)
  ShimFireTimers()
end

--- Every timer but the look's, three times over: a variable's change arms a debounce, which arms
--- the evaluation.
local function settle()
  for _ = 1, 3 do
    local names = {}
    for name in pairs(Timer) do
      if type(name) == "string" and name ~= "LookTimer" then
        table.insert(names, name)
      end
    end
    for _, name in ipairs(names) do
      ExpireTimer(name)
    end
  end
end

--- @return string name The shown look, as the Look variable names it.
local function shown()
  return Variables["Look"]
end

--- @param mode string
local function setLookControl(mode)
  Properties["Look Control"] = mode
  OnPropertyChanged("Look Control")
end

--- Change a saved look's fields, as the Button tab does: it sends them all.
--- @param id integer
--- @param name string
--- @param extra table|nil
--- @return table reply
local function save(id, name, extra)
  local fields = H.lookFields(name, extra)
  fields.id = id
  return JSON:decode(H.tab("_SAVE_LOOK", fields))
end

--- @param id integer
--- @return table look The look in the state.
local function stateLook(id)
  H.tab("_GET_STATE")
  for _, look in ipairs(H.state().looks) do
    if look.id == id then
      return look
    end
  end
  error("no look " .. tostring(id))
end

--- Show a look from programming.
--- @param id integer
local function showLook(id)
  EC.Show_Look({ Look = "look (" .. id .. ")" })
end

H.start()
local quiet = H.addLook("Quiet")
local ringing = H.addLook("Ringing")
local visitor = H.addLook("Visitor")

T.section("A look's timer")
T.eq("a look has none to start", stateLook(ringing).timerAfter, nil)
save(ringing, "Ringing", { timerAfter = 30 })
T.eq("it takes a time in seconds", stateLook(ringing).timerAfter, 30)
T.eq("and shows the look before when it doesn't say", stateLook(ringing).timerShow, "before")
save(ringing, "Ringing", { timerAfter = 600, timerShow = visitor })
T.eq("or another look on the button", stateLook(ringing).timerShow, visitor)
save(ringing, "Ringing", { timerAfter = 600, timerShow = tostring(quiet) })
T.eq("named by its id", stateLook(ringing).timerShow, quiet)
save(ringing, "Ringing", { timerAfter = 86400 })
T.eq("a day at most", stateLook(ringing).timerAfter, 86400)
for _, case in ipairs({
  { "no time", { timerAfter = 0 } },
  { "more than a day", { timerAfter = 86401 } },
  { "part of a second", { timerAfter = 1.5 } },
  { "a time that isn't a number", { timerAfter = "30" } },
  { "the look itself", { timerAfter = 30, timerShow = ringing } },
  { "a look the button doesn't have", { timerAfter = 30, timerShow = 999 } },
  { "a look named some other way", { timerAfter = 30, timerShow = "Quiet" } },
}) do
  local reply = save(ringing, "Ringing", case[2])
  T.eq("refuses " .. case[1], reply._command, "ERROR")
end
T.contains(
  "saying why",
  save(ringing, "Ringing", { timerAfter = 30, timerShow = ringing }).message,
  "the look before it or another look"
)
T.eq("a refused save leaves the timer as it was", stateLook(ringing).timerAfter, 86400)
save(ringing, "Ringing", { timerShow = visitor })
T.eq("without a time, the look stays", stateLook(ringing).timerAfter, nil)
T.eq("and names no look", stateLook(ringing).timerShow, nil)
local added = JSON:decode(H.tab("_SAVE_LOOK", H.lookFields("Away", { timerAfter = 60, timerShow = quiet })))
T.eq("a new look can have one", stateLook(tonumber(added.look)).timerShow, quiet)
H.tab("_DELETE_LOOK", { id = tonumber(added.look) })

T.section("A timed look goes back to the look before")
save(ringing, "Ringing", { timerAfter = 30 })
showLook(visitor)
H.mark()
showLook(ringing)
T.eq("showing it starts its timer", timerSet(), 30)
T.eq("which is kept", persist:get("LookTimer").due, clock + 30)
H.mark()
timeUp()
T.eq("once it's up, the look before shows", shown(), "Visitor")
T.eq("on the button", H.lastIcon().params.icon_description, "Visitor")
T.eq("firing Look Changed and the look's own event", H.fired, { "Look Changed", "Visitor Shown" })
T.eq("and the tab hears it", H.lastUi("SHOWN"), { shown = tostring(visitor) })
T.eq("the timer is done", timerSet(), nil)
T.eq("and forgotten", persist:get("LookTimer"), nil)
showLook(quiet)
showLook(ringing)
timeUp()
T.eq("the look before is whichever showed", shown(), "Quiet")

T.section("Or a chosen look")
save(ringing, "Ringing", { timerAfter = 600, timerShow = visitor })
showLook(ringing)
T.eq("set for its time", timerSet(), 600)
timeUp()
T.eq("shows the look it names", shown(), "Visitor")

T.section("Whatever shows the look starts its timer")
showLook(quiet)
H.tab("_SHOW_LOOK", { id = ringing })
T.eq("the tab's Show", timerSet(), 600)
showLook(quiet)
EC.Next_Look()
T.eq("Next Look", timerSet(), 600)
showLook(visitor)
EC.Previous_Look()
T.eq("Previous Look", timerSet(), 600)
showLook(quiet)
setLookControl("On Select")
H.press()
T.eq("a press", timerSet(), 600)
setLookControl("Manual")

T.section("Another look stops it, and the same look starts it over")
showLook(quiet)
T.eq("another look stops it", timerSet(), nil)
T.eq("and it's forgotten", persist:get("LookTimer"), nil)
H.mark()
ShimFireTimers()
T.eq("nothing changes later", shown(), "Quiet")
T.eq("and nothing fires", H.fired, {})
save(ringing, "Ringing", { timerAfter = 30 })
showLook(ringing)
local due = persist:get("LookTimer").due
clock = clock + 20
H.mark()
showLook(ringing)
T.eq("showing it again starts it over", persist:get("LookTimer").due, due + 20)
T.eq("for its whole time", timerSet(), 30)
T.eq("without a change of look to tell", H.fired, {})
clock = clock + 20
H.tab("_SHOW_LOOK", { id = ringing })
T.eq("the tab's Show starts it over too", persist:get("LookTimer").due, clock + 30)
timeUp()
T.eq("and it still goes back to the look from before", shown(), "Quiet")
save(visitor, "Visitor", { timerAfter = 30 })
save(ringing, "Ringing", { timerAfter = 30, timerShow = visitor })
showLook(ringing)
timeUp()
T.eq("a look the timer shows", shown(), "Visitor")
T.eq("doesn't start its own", timerSet(), nil)
save(visitor, "Visitor")

T.section("A deleted look")
local away = H.addLook("Away")
save(ringing, "Ringing", { timerAfter = 30, timerShow = away })
H.tab("_DELETE_LOOK", { id = away })
T.eq("a timer that named it shows the look before", stateLook(ringing).timerShow, "before")
away = H.addLook("Away")
save(quiet, "Quiet", { isDefault = true })
showLook(away)
showLook(ringing)
H.tab("_DELETE_LOOK", { id = away })
timeUp()
T.eq("with the look before gone, the default look shows", shown(), "Quiet")
save(quiet, "Quiet")
away = H.addLook("Away")
H.tab("_ORDER_LOOKS", { ids = { ringing, visitor, quiet, away } })
showLook(away)
showLook(ringing)
H.tab("_DELETE_LOOK", { id = away })
timeUp()
T.eq("with no default, the first look with a picture", shown(), "Visitor")
H.tab("_ORDER_LOOKS", { ids = { quiet, ringing, visitor } })
local gone = H.addLook("Gone")
save(gone, "Gone", { timerAfter = 30 })
showLook(gone)
T.eq("a timed look shown", timerSet(), 30)
H.tab("_DELETE_LOOK", { id = gone })
T.eq("deleting it stops its timer", timerSet(), nil)
T.eq("and forgets it", persist:get("LookTimer"), nil)
local reset = H.addLook("Reset")
showLook(quiet)
save(reset, "Reset", { timerAfter = 30 })
showLook(reset)
H.tab("_DELETE_LOOK", { id = quiet })
T.eq("deleting the look before leaves it running", timerSet(), 30)
timeUp()
T.eq("and it shows the first other look then", shown(), "Ringing")
H.tab("_DELETE_LOOK", { id = reset })
quiet = H.addLook("Quiet")
H.tab("_ORDER_LOOKS", { ids = { quiet, ringing, visitor } })

T.section("By Value")
local BELL = 100
local bell = "Idle"
local function setDevices()
  ShimSetDevices({
    [BELL] = {
      deviceName = "Bell",
      roomName = "Porch",
      variables = { ["1001"] = { name = "STATE", value = bell, type = "STRING" } },
    },
    [H.DEVICE_ID] = { deviceName = "This Button", roomName = "Porch", variables = {} },
  })
end
local function setBell(value)
  bell = value
  setDevices()
  OnWatchedVariableChanged(BELL, 1001, value)
  settle()
end
setDevices()
save(quiet, "Quiet", { showWhen = 'PARAM{100,1001} == "Idle"' })
save(ringing, "Ringing", { showWhen = 'PARAM{100,1001} == "Ring"', timerAfter = 30 })
save(visitor, "Visitor", { showWhen = 'PARAM{100,1001} == "Visitor"' })
setLookControl("By Value")
settle()
T.eq("the values pick a look", shown(), "Quiet")
setBell("Ring")
T.eq("a timed look the values show", shown(), "Ringing")
T.eq("runs no timer", timerSet(), nil)
ShimFireTimers()
T.eq("and stays while its Show when is true", shown(), "Ringing")
setBell("Idle")
T.eq("until the values pick another", shown(), "Quiet")
showLook(ringing)
T.eq("shown from programming, it runs its timer", timerSet(), 30)
H.mark()
timeUp()
T.eq("and goes back to what the values pick", shown(), "Quiet")
T.eq("firing the events", H.fired, { "Look Changed", "Quiet Shown" })
showLook(visitor)
showLook(ringing)
timeUp()
T.eq("not to the look before", shown(), "Quiet")
showLook(ringing)
setBell("Visitor")
T.eq("the values picking another look stop it", timerSet(), nil)
T.eq("and show theirs", shown(), "Visitor")
setBell("Ring")
setBell("Idle")
showLook(ringing)
setBell("Ring")
T.eq("the values picking the timed look itself stop its timer", timerSet(), nil)
ShimFireTimers()
T.eq("so it stays while its Show when is true", shown(), "Ringing")
setBell("Idle")
setLookControl("Manual")
save(quiet, "Quiet")
save(ringing, "Ringing", { timerAfter = 30 })
save(visitor, "Visitor")

T.section("A Director restart")
showLook(visitor)
showLook(ringing)
due = persist:get("LookTimer").due
clock = clock + 10
H.restart()
T.eq("the timed look still shows", shown(), "Ringing")
T.eq("its timer is set for what's left", timerSet(), 20)
T.eq("with the same due time", persist:get("LookTimer").due, due)
timeUp()
T.eq("and goes back to the look before", shown(), "Visitor")

T.section("A driver update")
showLook(quiet)
showLook(ringing)
clock = clock + 25
H.update()
T.eq("its timer is set for what's left", timerSet(), 5)
timeUp()
T.eq("and goes back to the look before", shown(), "Quiet")

T.section("A due time that passed while the driver was stopped")
showLook(visitor)
showLook(ringing)
clock = clock + 3600
H.mark()
H.restart()
T.eq("goes back at the start", shown(), "Visitor")
T.eq("telling programming", H.fired, { "Look Changed", "Visitor Shown" })
T.eq("with no timer left", timerSet(), nil)
showLook(ringing)
clock = clock + 31
H.update()
T.eq("after an update too", shown(), "Visitor")

T.section("A clock set back")
showLook(ringing)
clock = clock - 86400
H.restart()
T.eq("the timer runs no longer than the look's own time", timerSet(), 30)
clock = clock + 86400
timeUp()

T.section("Copy To and Import")
T.contains(
  "a target the button doesn't have is refused, so the page maps a copy's ids",
  save(ringing, "Ringing", { timerAfter = 30, timerShow = "l2" }).message,
  "another look on this button"
)
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
H.tab("_SAVE_LOOK", H.lookFields("Ringing", { timerAfter = 30, timerShow = "before" }))
local copied = tonumber(H.lastUi("SAVED").look)
H.sendImage(copied, H.png("Ringing"))
local target = H.addLook("Visitor")
local resaved = save(copied, "Ringing", { timerAfter = 30, timerShow = target })
T.eq("a timer whose look came after it takes that look's new id", resaved._command, "SAVED")
T.eq("which it shows", stateLook(copied).timerShow, target)
T.eq("and the look keeps its picture", stateLook(copied).stale, false)
local file = assert(io.open(H.DRIVER:gsub("driver%.lua$", "www/html/index.html"), "r"))
local page = file:read("*a")
file:close()
local function has(text)
  return page:find(text, 1, true) ~= nil
end
T.truthy("the page keeps each look's new id by the id it came with", has("ids[taking[n].key] = r.id;"))
T.truthy(
  "names a look given before it by its new id, and the look before until then",
  has("fields.timerShow = !look.timerAfter ? null : timerLook && ids[timerLook] ? ids[timerLook] : 'before';")
)
T.truthy(
  "saves a timer again once its look is given",
  has("Object.assign({}, done[t].fields, { id: done[t].id, timerShow: ids[wait] })")
)
T.truthy(
  "and says when its look wasn't given",
  has("if (!ids[wait] || wait === done[t].key) { lostTimers.push(done[t].fields.name); continue; }")
    and has("'Its timer shows the look before, since its look wasn’t '")
)
T.truthy("a copy names each look by its id", has("items.push({ key: String(l.id), look: lookFields(look)"))
T.truthy("an export names the timer's look by the file's id", has("fileIds[String(look.timerShow)] || 'before'"))
T.truthy("and an import by the file's", has("items.push({ key: l.id == null ? '#' + i : String(l.id), look: look"))

T.section("The Button tab's Timer row")
T.truthy("the editor's save sends the timer", has("Object.assign(fields, timerFields());"))
T.truthy("Stay sends none", has("return { timerAfter: null, timerShow: null };"))
T.truthy("under By Value there's no look to pick", has("$('f-timer-show').hidden = !after || byValue();"))
T.truthy("and the row goes back to the values", has("byValue() ? ', go back to the values' : ', show'"))
T.truthy("the list shows a timed look's timer", has("timerLines(l) + badgeLines(l)"))
T.truthy("the editor holds a time past a day", has("total >= 1 && total <= TIMER_MAX"))
T.eq("which is the driver's", tonumber(page:match("var TIMER_MAX = (%d+)")), require("dynamic_button.looks").MAX_TIMER)

T.section("Reset Driver")
H.addLook("Quiet")
showLook(copied)
T.eq("a timed look shown", timerSet(), 30)
H.mark()
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("Reset Driver stops its timer", timerSet(), nil)
T.eq("and forgets it", persist:get("LookTimer"), nil)
ShimFireTimers()
T.eq("so nothing shows later", shown(), "")
T.eq("and nothing fires", H.fired, {})

T.section("Without a license, nothing fires")
quiet = H.addLook("Quiet")
ringing = H.addLook("Ringing")
save(ringing, "Ringing", { timerAfter = 30 })
showLook(ringing)
T.eq("a timed look shown", timerSet(), 30)
-- Each read of 0 counts toward the five minutes, which the gate is past.
DC_X = 0
gate:_set(false)
H.mark()
timeUp()
T.eq("its time up while stopped changes nothing", shown(), "Ringing")
T.eq("tells the proxy nothing", #H.proxy, 0)
T.eq("fires nothing", H.fired, {})
T.eq("and the timer is done", timerSet(), nil)
DC_X = nil
gate:_set(true)
T.eq("a license back shows the look again", H.lastIcon().params.icon_description, "Ringing")
T.eq("without its timer", timerSet(), nil)
showLook(ringing)
T.eq("showing it again starts it over", timerSet(), 30)
timeUp()
T.eq("and it goes back", shown(), "Quiet")

T.finish()
