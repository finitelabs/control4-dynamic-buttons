--- Look Control's By Value under the C4 shim: each look's Show when over another device's variables,
--- the order rule, the default look, a hold from programming, a Director restart with a variable not
--- there yet, a device leaving the project, and what the Button tab is told.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_follow.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

local BATTERY, METER = 100, 200
local MAX_SHOW_WHEN = require("dynamic_button.looks").MAX_SHOW_WHEN
local LEVEL = "PARAM{100,1001}"
local STATE = "PARAM{100,1002}"

local level, state = "50", "Idle"
local meterHasVariable = true

--- Put the project's devices in the shim, with this button's own entry among them.
local function setDevices()
  local devices = {
    [BATTERY] = {
      deviceName = "Battery",
      roomName = "Garage",
      variables = {
        ["1001"] = { name = "LEVEL", value = level, type = "NUMBER" },
        ["1002"] = { name = "STATE", value = state, type = "STRING" },
      },
    },
    [METER] = { deviceName = "Meter", roomName = "Garage", variables = {} },
    [H.DEVICE_ID] = {
      deviceName = "This Button",
      roomName = "Garage",
      variables = { ["1"] = { name = "Look", value = "", type = "STRING" } },
      proxies = { [tostring(H.DEVICE_ID + 1)] = true },
    },
  }
  if meterHasVariable then
    devices[METER].variables["7"] = { name = "WATTS", value = "5", type = "NUMBER" }
  end
  ShimSetDevices(devices)
end

--- Every timer, three times: a variable appearing arms the debounce, which arms the evaluation.
local function settle()
  ShimFireTimers()
  ShimFireTimers()
  ShimFireTimers()
end

--- A variable changes, as Director tells a driver that listens to it.
--- @param value string
local function setLevel(value)
  level = value
  setDevices()
  OnWatchedVariableChanged(BATTERY, 1001, value)
  settle()
end

--- @param value string
local function setState(value)
  state = value
  setDevices()
  OnWatchedVariableChanged(BATTERY, 1002, value)
  settle()
end

--- @param mode string
local function setLookControl(mode)
  Properties["Look Control"] = mode
  OnPropertyChanged("Look Control")
end

--- @return table|nil result The preview's last answer.
local function evalResult()
  return H.lastUi("EVAL_RESULT")
end

--- @return string name The shown look, as the Look variable names it.
local function shown()
  return Variables["Look"]
end

--- Save a look with its Show when, and send its picture.
--- @param name string
--- @param showWhen string|nil
--- @param extra table|nil
--- @return integer id
local function addLook(name, showWhen, extra)
  local fields = H.lookFields(name, extra)
  fields.showWhen = showWhen
  H.tab("_SAVE_LOOK", fields)
  local id = tonumber(H.lastUi("SAVED").look)
  H.sendImage(id, H.png(name))
  return id
end

--- Change a saved look's fields, as the Button tab does: it sends them all.
--- @param id integer
--- @param name string
--- @param showWhen string|nil
--- @param extra table|nil
local function saveLook(id, name, showWhen, extra)
  local fields = H.lookFields(name, extra)
  fields.id = id
  fields.showWhen = showWhen
  H.tab("_SAVE_LOOK", fields)
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
  error("no look " .. id)
end

-- Listeners registered and dropped, by "<device>:<variable>". Registering drops the last one first.
local listens, stops = {}, {}
local realListen, realStop = C4.RegisterVariableListener, C4.UnregisterVariableListener
function C4:RegisterVariableListener(deviceId, variableId)
  listens[deviceId .. ":" .. variableId] = (listens[deviceId .. ":" .. variableId] or 0) + 1
  return realListen(self, deviceId, variableId)
end
function C4:UnregisterVariableListener(deviceId, variableId)
  stops[deviceId .. ":" .. variableId] = (stops[deviceId .. ":" .. variableId] or 0) + 1
  return realStop(self, deviceId, variableId)
end

setDevices()
H.start()

T.section("Look Control offers By Value")
local xml = assert(io.open(H.XML, "r"))
local driverXml = xml:read("*a")
xml:close()
T.truthy("driver.xml lists it", driverXml:find("<item>By Value</item>", 1, true))

T.section("The first true look in the list wins")
local high = addLook("High", LEVEL .. " >= 80")
local mid = addLook("Mid", LEVEL .. " >= 40")
local plain = addLook("Plain")
local low = addLook("Low", LEVEL .. " < 40")
EC.Show_Look({ Look = "Plain (" .. plain .. ")" })
T.eq("Manual doesn't follow", shown(), "Plain")
setLevel("90")
T.eq("and a value changing doesn't move it", shown(), "Plain")
T.eq("nor is anything watched", listens["100:1001"], nil)

H.mark()
setLookControl("By Value")
T.eq("entering By Value shows the match at once", shown(), "High")
T.eq("and watches what the looks read", listens["100:1001"], 1)
T.truthy("Look Changed fires", H.fired[1] == "Look Changed")
T.eq("then the look's own event", H.fired[2], "High Shown")
T.eq("and the tab hears the small message", H.lastUi("SHOWN").shown, high)
H.tab("_GET_STATE")
T.eq("the state says By Value", H.state().lookControl, "By Value")
T.eq("and which look matched", H.state().matched, high)
T.eq("a look's expression reads in names", stateLook(high).showWhenText, "[Garage > Battery > LEVEL] >= 80")
T.eq("a look without one has none", stateLook(plain).showWhen, nil)

setLevel("50")
T.eq("the match moves down the list", shown(), "Mid")

H.tab("_ORDER_LOOKS", { ids = { low, plain, mid, high } })
T.eq("a new order keeps the match while only one is true", shown(), "Mid")
setLevel("90")
T.eq("the first in the new order is checked first, when both are true", shown(), "Mid")
H.tab("_ORDER_LOOKS", { ids = { high, mid, plain, low } })
T.eq("and reordering changes the winner", shown(), "High")

T.section("Only a change of match shows anything")
setLevel("95")
H.mark()
setLevel("96")
setLevel("97")
T.eq("no new address", H.lastIcon(), nil)
T.eq("no events", #H.fired, 0)
T.eq("no message to the tab", #H.ui, 0)
setLevel("50")
T.eq("a new match tells the tab", (H.state() or {}).matched, mid)
setLevel("95")

T.section("A press leaves the look alone")
H.mark()
H.press()
T.eq("under By Value", shown(), "High")
T.eq("with nothing fired by the driver", #H.fired, 0)

T.section("The default look")
setLevel("95")
saveLook(low, "Low", "false")
saveLook(mid, "Mid", "false")
saveLook(high, "High", "false")
T.eq("with none true and no default, the shown look stays", shown(), "High")
H.tab("_GET_STATE")
T.eq("and nothing is matched", H.state().matched, nil)
local persist = require("lib.persist")
local realSet, writes = persist.set, 0
persist.set = function(self, key, value)
  if key == "FollowApplied" then
    writes = writes + 1
  end
  return realSet(self, key, value)
end
H.tab("_ORDER_LOOKS", { ids = { high, mid, plain, low } })
H.tab("_ORDER_LOOKS", { ids = { high, mid, plain, low } })
persist.set = realSet
T.eq("evaluating with no match writes nothing", writes, 0)
EC.Show_Look({ Look = "Low (" .. low .. ")" })
saveLook(high, "High", LEVEL .. " >= 80")
T.eq("a look true again after none were is a new match", shown(), "High")
saveLook(high, "High", "false")
saveLook(plain, "Plain", nil, { isDefault = true })
T.eq("picking a default shows it", shown(), "Plain")
H.tab("_GET_STATE")
T.eq("the state names it", H.state().defaultLook, plain)
T.eq("and it's what matched", H.state().matched, plain)
saveLook(mid, "Mid", LEVEL .. " >= 40", { isDefault = true })
T.eq("one true look beats the default", shown(), "Mid")
H.tab("_GET_STATE")
T.eq("and a look taking the default replaces the last", H.state().defaultLook, mid)
saveLook(mid, "Mid", LEVEL .. " >= 40")
H.tab("_GET_STATE")
T.eq("a look saved without it gives it up", H.state().defaultLook, nil)
saveLook(high, "High", LEVEL .. " >= 80")
saveLook(low, "Low", LEVEL .. " < 40")
saveLook(plain, "Plain", nil, { isDefault = true })

T.section("What a Show when can hold")
H.mark()
saveLook(plain, "Plain", string.rep("x", MAX_SHOW_WHEN + 1), { isDefault = true })
T.truthy("too long is refused", H.lastUi("ERROR"))
H.mark()
saveLook(plain, "Plain", 5, { isDefault = true })
T.truthy("so is anything but text", H.lastUi("ERROR"))
saveLook(plain, "Plain", "  false  ", { isDefault = true })
T.eq("space around it goes", stateLook(plain).showWhen, "false")
saveLook(plain, "Plain", nil, { isDefault = true })

T.section("A look's Show when doesn't touch its picture")
T.eq("the picture isn't out of date", stateLook(mid).stale, false)
T.eq("and is still there", stateLook(mid).hasImage, true)

T.section("Programming holds until the matched look changes")
setLevel("90")
T.eq("High is matched", shown(), "High")
EC.Show_Look({ Look = "Plain (" .. plain .. ")" })
T.eq("Show Look shows another", shown(), "Plain")
setLevel("91")
T.eq("the same match leaves it", shown(), "Plain")
H.tab("_GET_STATE")
T.eq("while the state says what matched", H.state().matched, high)
setLevel("50")
T.eq("a new match takes over", shown(), "Mid")
setLevel("90")
T.eq("and back", shown(), "High")
EC.Next_Look()
T.eq("Next Look moves on", shown(), "Mid")
setLevel("92")
T.eq("and holds", shown(), "Mid")
EC.Previous_Look()
EC.Previous_Look()
T.eq("Previous Look moves back past it", shown(), "Low")
setLevel("93")
T.eq("and holds", shown(), "Low")
setLevel("50")
T.eq("until the match changes", shown(), "Mid")
setLevel("90")
EC.Show_Look({ Look = "Low (" .. low .. ")" })
H.restart()
setDevices()
settle()
T.eq("a hold outlasts a Director restart", shown(), "Low")
H.update()
setDevices()
settle()
T.eq("and a driver update", shown(), "Low")
setLevel("50")
T.eq("until the match changes", shown(), "Mid")

T.section("A load decides at once")
EC.Show_Look({ Look = "Plain (" .. plain .. ")" })
level = "90"
setDevices()
H.restart()
T.eq("a value that changed while the driver was down shows, with no timer", shown(), "High")
setLevel("50")

-- Warnings, as the driver logs them.
local logged = {}
local log = require("lib.logging")
local realWarn = log.warn
log.warn = function(self, message, ...)
  table.insert(logged, string.format(message, ...))
  return realWarn(self, message, ...)
end

--- @param text string
--- @return integer count How many warnings mention it.
local function warnings(text)
  local count = 0
  for _, line in ipairs(logged) do
    if line:find(text, 1, true) then
      count = count + 1
    end
  end
  return count
end

T.section("A matched look with no picture yet")
setLevel("50")
local fresh = H.tab(
  "_SAVE_LOOK",
  (function()
    local fields = H.lookFields("Fresh")
    fields.showWhen = "true"
    return fields
  end)()
)
T.truthy("the save answers", fresh)
local freshId = tonumber(H.lastUi("SAVED").look)
H.tab("_ORDER_LOOKS", { ids = { freshId, high, mid, plain, low } })
T.eq("it can't show yet", shown(), "Mid")
setLevel("51")
T.eq("and says so once", warnings("Could not show"), 1)
H.sendImage(freshId, H.png("Fresh"))
T.eq("its picture arriving shows it", shown(), "Fresh")
H.tab("_DELETE_LOOK", { id = freshId })
T.eq("deleting a matched look shows the next match", shown(), "Mid")

T.section("An expression with an error isn't true")
H.ui = {}
saveLook(high, "High", "PARAM{100,1001} >=")
T.truthy(
  "one that doesn't read as an expression isn't kept",
  (H.lastUi("ERROR") or {}).message
    == '"Show when": compile error: [string "return __p >="]:1: unexpected symbol near \'<eof>\''
)
for i = #logged, 1, -1 do
  logged[i] = nil
end
saveLook(high, "High", "PARAM{100,1001} >= nil")
T.truthy("the state reports it", stateLook(high).whenError)
T.eq("the next true look shows", shown(), "Mid")
setLevel("60")
setLevel("61")
T.eq("the same error logs once", warnings("Show when"), 1)
saveLook(high, "High", "1 + 1")
T.truthy("a result that isn't true or false is an error too", stateLook(high).whenError:find("not a boolean", 1, true))
T.eq("a new error logs", warnings("Show when"), 2)
setLookControl("Manual")
setLookControl("By Value")
T.eq("coming back to By Value logs it again", warnings("Show when"), 3)
saveLook(high, "High", LEVEL .. " >= 80")
T.eq("a fixed expression clears it", stateLook(high).whenError, nil)
log.warn = realWarn

T.section("A value can't become code")
local LOOP = '"..(function() while true do end end)().."'
local textual = addLook("Textual", STATE .. ' == "Charging"')
H.tab("_ORDER_LOOKS", { ids = { textual, high, mid, plain, low } })
setState(LOOP)
T.eq("a value holding a loop is only text", shown(), "Mid")
saveLook(textual, "Textual", STATE)
setState("1 == 1")
T.eq("a value that reads as true is only text", shown(), "Mid")
T.truthy("so it's neither true nor false", stateLook(textual).whenError:find("not a boolean", 1, true))
saveLook(textual, "Textual", '"' .. STATE .. '" == "x"')
setState('x" == "x" or "')
T.eq("a value inside a string can't close it", shown(), "Mid")
T.eq("and isn't an error", stateLook(textual).whenError, nil)
saveLook(textual, "Textual", STATE .. ' == "Charging"')
setState("Charging")
T.eq("and the comparison works on the real value", shown(), "Textual")
state = "Idle"
setDevices()
local stateStops = stops["100:1002"] or 0
H.tab("_DELETE_LOOK", { id = textual })
T.eq("deleting it unwatches what only it read", stops["100:1002"], stateStops + 1)
settle()

T.section("Leaving By Value")
local stoppedBefore = stops["100:1001"] or 0
setLookControl("Manual")
T.eq("stops the watches", stops["100:1001"], stoppedBefore + 1)
local before = shown()
setLevel("90")
T.eq("and a value changing leaves the look", shown(), before)
H.tab("_ORDER_LOOKS", { ids = { high, mid, plain, low } })
T.eq("as does reordering", shown(), before)
local listened = listens["100:1001"]
saveLook(high, "High", LEVEL .. " >= 80")
T.eq("a look saved meanwhile isn't watched", listens["100:1001"], listened)
H.tab("_GET_STATE")
T.eq("the state has no match", H.state().matched, nil)
T.eq("nor expressions in names", stateLook(high).showWhenText, nil)
T.eq("but keeps what was typed", stateLook(high).showWhen, LEVEL .. " >= 80")

T.section("Deleting the default")
setLookControl("By Value")
T.eq("coming back shows the match at once", shown(), "High")
setLookControl("Manual")
EC.Show_Look({ Look = "Mid (" .. mid .. ")" })
setLookControl("By Value")
T.eq("even when that was the last match too", shown(), "High")
H.tab("_DELETE_LOOK", { id = plain })
H.tab("_GET_STATE")
T.eq("clears it", H.state().defaultLook, nil)

T.section("Deleting a look programming is holding")
local spare = addLook("Spare")
local held = addLook("Held")
H.tab("_ORDER_LOOKS", { ids = { spare, held, high, mid, low } })
setLevel("50")
T.eq("before: the match", shown(), "Mid")
EC.Show_Look({ Look = "Held (" .. held .. ")" })
T.eq("programming holds another", shown(), "Held")
H.tab("_DELETE_LOOK", { id = spare })
T.eq("deleting a look that isn't shown leaves the hold", shown(), "Held")
H.mark()
H.tab("_DELETE_LOOK", { id = held })
T.eq("deleting the held look goes back to the match", shown(), "Mid")
T.eq("without passing through the first look", H.fired, { "Look Changed", "Mid Shown" })
setLevel("90")
T.eq("before: a new match", shown(), "High")

T.section("Back to By Value after a change made while the driver was stopped")
Properties["Look Control"] = "Manual"
H.restart()
setDevices()
settle()
EC.Show_Look({ Look = "Mid (" .. mid .. ")" })
T.eq("programming shows another look under Manual", shown(), "Mid")
Properties["Look Control"] = "By Value"
H.restart()
setDevices()
settle()
T.eq("By Value set while the driver was stopped shows the match as it starts", shown(), "High")
Properties["Look Control"] = "Manual"
H.restart()
setDevices()
settle()
EC.Show_Look({ Look = "Mid (" .. mid .. ")" })
setLookControl("By Value")
T.eq("as does By Value set after such a start", shown(), "High")

T.section("The device browser")
H.tab("_GET_DEVICES")
local devices = H.lastUi("DEVICES_DATA").devices
local offered = {}
for _, device in ipairs(devices) do
  offered[device.id] = true
end
T.truthy("offers other devices", offered[BATTERY])
T.falsy("but not this button, whose own variable sends it no change", offered[H.DEVICE_ID])
local someVariable = { ["1"] = { name = "POWER", value = "1", type = "NUMBER" } }
ShimSetDevices({
  [301] = { deviceName = "TV", roomName = "den", variables = someVariable },
  [302] = { deviceName = "Thermostat", roomName = "Den", variables = someVariable },
  [303] = { deviceName = "amp", roomName = "Den", variables = someVariable },
})
H.tab("_GET_DEVICES")
local sorted = {}
for _, device in ipairs(H.lastUi("DEVICES_DATA").devices) do
  table.insert(sorted, device.name)
end
T.eq("rooms and names sort whatever their case", sorted, { "amp", "Thermostat", "TV" })
setDevices()
state = string.rep("v", 500)
setDevices()
H.tab("_GET_DEVICE_VARIABLES", { deviceId = BATTERY })
local answer = H.lastUi("DEVICE_VARIABLES_DATA")
T.eq("names the device it answers for", answer.deviceId, tostring(BATTERY))
local variables = answer.variables
T.eq("lists its variables", #variables, 2)
T.eq("with a value short enough to show", #variables[2].value, 60)
state = string.rep("v", 59) .. "\195\169"
setDevices()
H.tab("_GET_DEVICE_VARIABLES", { deviceId = BATTERY })
variables = H.lastUi("DEVICE_VARIABLES_DATA").variables
T.eq("cut on a whole character", variables[2].value, string.rep("v", 59))
state = "caf\195\169"
setDevices()
H.tab("_GET_DEVICE_VARIABLES", { deviceId = BATTERY })
variables = H.lastUi("DEVICE_VARIABLES_DATA").variables
T.eq("a short value keeps its last character", variables[2].value, "caf\195\169")
state = "Idle"
setDevices()

T.section("The preview")
H.tab("_EVAL_EXPRESSION", { id = "7", expression = LEVEL .. " >= 80" })
local preview = evalResult()
T.eq("answers its request", preview.id, "7")
T.eq("with the result", preview.result, "true")
T.eq("in names", preview.rendered, "[Garage > Battery > LEVEL] >= 80")
T.eq("and with current values", preview.substituted, level .. " >= 80")
state = string.rep("v", MAX_SHOW_WHEN + 1)
setDevices()
H.tab("_EVAL_EXPRESSION", { id = "7", expression = STATE .. ' == "x"' })
T.eq("a long value is cut", #evalResult().substituted, MAX_SHOW_WHEN)
setState("007")
H.tab("_EVAL_EXPRESSION", { id = "b20", expression = STATE, mode = "string" })
T.eq("a badge's text that reads as a number stays text", evalResult().fitted, "007")
state = "Idle"
setDevices()
H.tab("_EVAL_EXPRESSION", { id = "8", expression = "PARAM{100,NOPE} > 1" })
preview = evalResult()
T.eq("no result for a missing variable", preview.result, "")
T.truthy("but the reason", preview.error:find("NOPE", 1, true))
T.eq("which doesn't hold Save: the variable may come", preview.hold, nil)
local OWN = "A look can't follow this button's own variables."
H.tab("_EVAL_EXPRESSION", { id = "10", expression = "PARAM{" .. H.DEVICE_ID .. ",1} == 'x'" })
preview = evalResult()
T.eq("this button's own variable holds Save, in a plain sentence", { preview.error, preview.hold }, { OWN, true })
H.tab("_EVAL_EXPRESSION", { id = "14", expression = LEVEL .. " > 3 -- was PARAM{" .. H.DEVICE_ID .. ",1} == 'x'" })
T.eq("but not one in a comment, which isn't read", evalResult().hold, nil)
H.tab("_EVAL_EXPRESSION", { id = "11", expression = "PARAM{" .. (H.DEVICE_ID + 1) .. ",1} == 1" })
T.eq("and its proxy's", evalResult().error, OWN)
H.tab("_EVAL_EXPRESSION", { id = "b12", expression = "PARAM{" .. H.DEVICE_ID .. ",1}", mode = "string" })
T.eq("a live badge's text too", { evalResult().error, evalResult().hold }, { OWN, true })
H.tab("_EVAL_EXPRESSION", { id = "13", expression = LEVEL .. " >=" })
preview = evalResult()
T.eq("one that doesn't read as an expression holds Save", preview.hold, true)
T.truthy("as the engine words it", preview.error:find("^compile error: "))
T.eq("still in names", preview.rendered, "[Garage > Battery > LEVEL] >=")
H.ui = {}
saveLook(high, "High", "PARAM{" .. H.DEVICE_ID .. ",1} == 'x'")
T.eq("and a save of it is refused", (H.lastUi("ERROR") or {}).message, OWN)
H.tab("_EVAL_EXPRESSION", { id = "9", expression = "true" .. string.rep(" ", MAX_SHOW_WHEN) .. "and false" })
T.eq("it reads only what a look can keep", evalResult().result, "true")
local showBefore = shown()
H.tab("_EVAL_EXPRESSION", { id = "9", expression = "true" })
T.eq("and it changes nothing", shown(), showBefore)

T.section("A restart with a variable not there yet")
saveLook(high, "High", "PARAM{200,WATTS} > 100")
saveLook(mid, "Mid", LEVEL .. " >= 40", { isDefault = true })
saveLook(low, "Low", LEVEL .. " < 40")
H.tab("_ORDER_LOOKS", { ids = { high, low, mid } })
setLevel("20")
T.eq("before: the second look is true", shown(), "Low")
setLevel("90")
T.eq("then the default", shown(), "Mid")
setLevel("20")
T.eq("and Low again", shown(), "Low")
meterHasVariable = false
setDevices()
H.mark()
H.restart()
T.eq("nothing moves while the first look's variable is missing", shown(), "Low")
T.eq("no event", #H.fired, 0)
-- Only the wait's end is held off here: the shim fires every timer at once.
CancelTimer("FollowBootWait")
setLevel("90")
T.eq("the default doesn't flash meanwhile, with Low no longer true", shown(), "Low")
T.truthy("while the state reports what's missing", stateLook(high).whenError:find("WATTS", 1, true))
meterHasVariable = true
setDevices()
settle()
T.eq("when the variable comes, the looks are decided", shown(), "Mid")
T.eq("and it's watched", listens["200:7"] ~= nil, true)
setLevel("20")
T.eq("Low again", shown(), "Low")
meterHasVariable = false
level = "90"
setDevices()
H.restart()
T.eq("the look waits again", shown(), "Low")
settle()
T.eq("when the wait runs out, a missing variable is just not true", shown(), "Mid")

local broken = addLook("Broken", LEVEL .. " >= nil")
H.tab("_ORDER_LOOKS", { ids = { high, broken, low, mid } })
setLevel("20")
T.eq("before: Low", shown(), "Low")
level = "90"
setDevices()
H.restart()
T.eq("another look's error doesn't end the wait", shown(), "Low")
settle()
H.tab("_DELETE_LOOK", { id = broken })
T.eq("before: the default", shown(), "Mid")

H.tab("_ORDER_LOOKS", { ids = { low, high, mid } })
level = "20"
setDevices()
H.restart()
T.eq("a true look above a missing one shows", shown(), "Low")
settle()

T.section("Entering By Value doesn't wait for a variable")
H.tab("_ORDER_LOOKS", { ids = { high, low, mid } })
level = "90"
setDevices()
H.restart()
T.eq("during the wait, the look stays", shown(), "Low")
setLookControl("Manual")
setLookControl("By Value")
T.eq("leaving and coming back ends it", shown(), "Mid")
setLookControl("Manual")
EC.Show_Look({ Look = "Low (" .. low .. ")" })
H.restart()
setLookControl("By Value")
T.eq("and a load in Manual never starts it", shown(), "Mid")
meterHasVariable = true
setDevices()

T.section("A variable missing after the start doesn't hold")
saveLook(high, "High", "PARAM{200,NOPE} > 100")
setLevel("20")
T.eq("the next true look shows", shown(), "Low")
meterHasVariable = false
setDevices()
saveLook(high, "High", "PARAM{200,WATTS} > 100")
T.truthy("waiting for a variable is an error", stateLook(high).whenError)
H.mark()
meterHasVariable = true
setDevices()
settle()
local pushed = H.state()
T.truthy("the tab hears when it clears", pushed and pushed.looks[1].id == high and not pushed.looks[1].whenError)
saveLook(high, "High", LEVEL .. " >= 80")

T.section("Without a license")
local gate = require("lib.drivercentral")
setLevel("50")
T.eq("before: the default", shown(), "Mid")
-- Each load's gate timer would read the stubbed client and start the driver again.
gate._check = function() end
gate:_set(false)
H.mark()
setLevel("90")
T.eq("a value changing tells the proxy nothing", H.lastIcon(), nil)
T.eq("and fires nothing", #H.fired, 0)
H.tab("_GET_DEVICES")
T.eq("the browser is refused", H.lastUi("DEVICES_DATA"), nil)
H.tab("_GET_DEVICE_VARIABLES", { deviceId = BATTERY })
T.eq("so are a device's variables", H.lastUi("DEVICE_VARIABLES_DATA"), nil)
H.tab("_EVAL_EXPRESSION", { id = "1", expression = "true" })
T.eq("and the preview", evalResult(), nil)
gate:_set(true)
T.eq("a license back shows what the values call for", shown(), "High")

T.section("A load with no license")
local productId = gate.PRODUCT_ID
gate.PRODUCT_ID = 0
level = "50"
setDevices()
H.restart()
T.eq("the look stays", shown(), "High")
gate.PRODUCT_ID = productId
gate:_set(true)
T.eq("until a license is back", shown(), "Mid")

T.section("A device leaving the project")
setLevel("90")
T.eq("before: High", shown(), "High")
saveLook(low, "Low", "PARAM{200,WATTS} >= 0")
H.tab("_ORDER_LOOKS", { ids = { low, high, mid } })
T.eq("Low reads the meter and comes first", shown(), "Low")
local meterStops = stops["200:7"] or 0
OnDeviceRemovedFromProject(METER)
settle()
T.eq("its variable stops being watched", stops["200:7"], meterStops + 1)
T.eq("the next true look shows", shown(), "High")
T.truthy("and the state says why", stateLook(low).whenError:find("removed", 1, true))

T.section("Reset Driver")
local levelStops = stops["100:1001"] or 0
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("stops watching", stops["100:1001"], levelStops + 1)
T.eq("Look Control is back to Manual", Properties["Look Control"], "Manual")
H.tab("_GET_STATE")
T.eq("and there's no default", H.state().defaultLook, nil)

T.finish()
