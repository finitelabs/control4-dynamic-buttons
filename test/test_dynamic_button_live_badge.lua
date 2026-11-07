--- A badge whose text holds a variable, under the C4 shim: the picture the controller draws, how often
--- it draws one, a variable shared with Show when, a restart with the variable not there yet, and what
--- goes wrong out loud.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_live_badge.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local LibDeflate = require("LibDeflate")
local Png = require("dynamic_button.png")
local Looks = require("dynamic_button.looks")
local LiveBadges = require("dynamic_button.live_badges")

local clock = 1000000
-- luacheck: push ignore os
os.time = function()
  return clock
end
-- luacheck: pop

local BATTERY = 100
local LEVEL = "PARAM{100,1001}"
local SERVED = "C4Z/www/buttons/" .. H.DEVICE_ID
local SOURCE = "SANDBOX/looks"

local level = "50"
local hasLevel = true

local function setDevices()
  local variables = { ["1002"] = { name = "STATE", value = "Idle", type = "STRING" } }
  if hasLevel then
    variables["1001"] = { name = "LEVEL", value = level, type = "NUMBER" }
  end
  ShimSetDevices({
    [BATTERY] = { deviceName = "Battery", roomName = "Garage", variables = variables },
    [H.DEVICE_ID] = {
      deviceName = "This Button",
      roomName = "Garage",
      variables = { ["1"] = { name = "Look", value = "", type = "STRING" } },
    },
  })
end

local function settle()
  ShimFireTimers()
  ShimFireTimers()
  ShimFireTimers()
end

--- @param value string
local function setLevel(value)
  level = value
  setDevices()
  OnWatchedVariableChanged(BATTERY, 1001, value)
  settle()
end

local function u32(value)
  return string.char(
    math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 256) % 256,
    value % 256
  )
end

--- A small picture as the Button tab makes one: 8-bit RGBA, not interlaced.
--- @param red integer
--- @return string png
local function realPng(red)
  local size, rows = 60, {}
  local row = string.rep(string.char(red, 40, 90, 255), size)
  for y = 1, size do
    rows[y] = "\0" .. row
  end
  local function chunk(kind, data)
    return u32(#data) .. kind .. data .. u32(Png.crc32(kind .. data))
  end
  return H.PNG_SIGNATURE
    .. chunk("IHDR", u32(size) .. u32(size) .. string.char(8, 6, 0, 0, 0))
    .. chunk("IDAT", LibDeflate:CompressZlib(table.concat(rows)))
    .. chunk("IEND", "")
end

--- @param text string
--- @param extra table|nil The badge's other fields.
--- @return table custom
local function live(text, extra)
  local badge = { text = text, place = "Top Right", color = "#FFFFFF", background = "#DC2626" }
  for k, v in pairs(extra or {}) do
    badge[k] = v
  end
  return { badge = badge }
end

--- @param name string
--- @param custom table|nil
--- @param extra table|nil The look's other fields.
--- @return integer id
local function addLook(name, custom, extra)
  local fields = H.lookFields(name, extra)
  fields.custom = custom
  H.tab("_SAVE_LOOK", fields)
  local id = tonumber(H.lastUi("SAVED").look)
  H.sendImage(id, realPng(#name * 10))
  return id
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

--- @return string|nil address The last address the proxy was told.
local function address()
  local icon = H.lastIcon()
  return icon and icon.params.icon or nil
end

--- @return integer count How many pictures the proxy was told of since the last mark.
local function told()
  local count = 0
  for _, sent in ipairs(H.proxy) do
    if sent.command == "ICON_CHANGED" then
      count = count + 1
    end
  end
  return count
end

--- @param id integer
--- @return string|nil png What Navigator loads for the look.
local function served(id)
  return ShimFiles(SERVED)[id .. ".png"]
end

--- @param id integer
--- @return string|nil png What the driver keeps for the look.
local function stored(id)
  return ShimFiles(SOURCE)["look-" .. id .. ".png"]
end

--- @param id integer
--- @return string|nil data What a redraw starts from.
local function cached(id)
  return ShimFiles(SOURCE)["look-" .. id .. ".badge"]
end

--- @param png string
--- @return integer count The pixels the badge changed, against the plain picture's top left.
local function painted(png)
  local cache = assert(Png.setup(png, 0, 59))
  local rows, count = Png.rows(cache), 0
  local plain = { rows[60][1], rows[60][2], rows[60][3] }
  for _, row in ipairs(rows) do
    for i = 1, #row, 4 do
      if row[i] ~= plain[1] or row[i + 1] ~= plain[2] or row[i + 2] ~= plain[3] then
        count = count + 1
      end
    end
  end
  return count
end

local logged = {}
local log = require("lib.logging")
local realWarn = log.warn
log.warn = function(self, message, ...)
  table.insert(logged, string.format(message, ...))
  return realWarn(self, message, ...)
end

--- @param text string
--- @return integer count Warnings holding that text.
local function warned(text)
  local count = 0
  for _, line in ipairs(logged) do
    if line:find(text, 1, true) then
      count = count + 1
    end
  end
  return count
end

setDevices()
H.start()

T.section("How text fits")
for _, case in ipairs({
  { "62%", "62%" },
  { "  62% ", "62%" },
  { "12.345W", "12.3W" },
  { "1234.6W", "1235W" },
  { "-12.345", "-12.3" },
  { "12345.6W", "12346" },
  { "Charging", "Charg" },
  { "20.6\194\176C", "21\194\176C" },
  { "\194\176\194\176\194\176\194\176\194\176\194\176", "\194\176\194\176\194\176\194\176\194\176" },
  { "On", "On" },
  { "", "" },
  { "K\195\188che", "Kche" },
}) do
  T.eq("'" .. case[1] .. "' fits as '" .. case[2] .. "'", LiveBadges.fit(case[1]), case[2])
end

T.section("A live badge's picture")
H.mark()
local battery = addLook("Battery", live(LEVEL .. "%"))
local key50 = address():match("%-(%x+)$")
T.truthy("its address names the text", key50 ~= nil and #key50 == 8)
T.eq("the proxy hears of it", told(), 1)
T.truthy("the picture Navigator loads has the badge", painted(served(battery)) > 0)
T.eq("the picture the driver keeps doesn't", painted(stored(battery)), 0)
T.truthy("and what a redraw starts from is kept", cached(battery) ~= nil)
local look = stateLook(battery)
T.eq("the tab hears what it says", look.badgeNow, "50%")
T.contains("and which variable it reads", look.badgeText, "LEVEL")
T.eq("with no problem", look.badgeError, nil)

T.section("How often it draws")
local first = served(battery)
clock = clock + 10
H.mark()
setLevel("60")
T.eq("a change within the minute waits", told(), 0)
T.eq("and the picture stays", served(battery), first)
clock = clock + 20
setLevel("61")
clock = clock + 29
settle()
T.eq("one second short of the minute still waits", told(), 0)
clock = clock + 1
settle()
T.eq("at the minute one picture comes", told(), 1)
T.eq("for all the changes", stateLook(battery).badgeNow, "61%")
T.neq("and it's different", served(battery), first)
local key61 = address():match("%-(%x+)$")
T.neq("under a new address", key61, key50)

H.mark()
clock = clock + 300
setLevel("61")
T.eq("the same text draws nothing, however long it's been", told(), 0)
H.mark()
setLevel("62")
T.eq("after a quiet spell a change shows at once", told(), 1)

T.section("A value seen before goes by its old address")
clock = clock + 60
setLevel("61")
T.eq("so the app needn't load it again", address():match("%-(%x+)$"), key61)

T.section("The look's own choice")
local function saveBadge(id, name, custom)
  local fields = H.lookFields(name)
  fields.id = id
  fields.custom = custom
  H.tab("_SAVE_LOOK", fields)
end
clock = clock + 3600
setLevel("70")
saveBadge(battery, "Battery", live(LEVEL .. "%", { every = 300 }))
H.mark()
clock = clock + 120
setLevel("71")
T.eq("every 5 minutes holds past a minute", told(), 0)
clock = clock + 180
settle()
T.eq("until the 5 minutes are up", told(), 1)
saveBadge(battery, "Battery", live(LEVEL .. "%"))

T.section("A save that changes only the choice sends no new picture")
T.falsy("the picture isn't stale", stateLook(battery).stale)

T.section("A save that changes the picture leaves the drawing to the new picture")
clock = clock + 3600
H.mark()
local cacheBefore = cached(battery)
saveBadge(battery, "Battery", live(LEVEL .. " V"))
T.eq("nothing is drawn from the old picture", told(), 0)
T.eq("nor kept from it", cached(battery), cacheBefore)
H.sendImage(battery, realPng(70))
T.eq("the new picture draws it", told(), 1)
saveBadge(battery, "Battery", live(LEVEL .. "%"))
H.sendImage(battery, realPng(70))

T.section("Text that only looks like a variable")
local function unfinished(text)
  local fields = H.lookFields("Battery")
  fields.id = battery
  fields.custom = live(text)
  H.mark()
  H.tab("_SAVE_LOOK", fields)
  return tostring(H.lastUi("ERROR") and H.lastUi("ERROR").message)
end
T.contains("an unfinished one is plain text, and too long", unfinished("PARAM{"), "1 to 5")
T.contains("so is one with no variable named", unfinished("PARAM{100}"), "1 to 5")
T.falsy("neither counts as live", Looks.isLiveText("PARAM{100}"))
T.truthy("a whole one does", Looks.isLiveText("PARAM{ 100 , LEVEL }%"))

T.section("A clock set back")
clock = clock + 3600
setLevel("72")
clock = clock - 86400
H.mark()
setLevel("73")
T.eq("a change waits as usual", told(), 0)
clock = clock + 60
settle()
T.eq("and no longer", told(), 1)

T.section("A plain badge is the tab's to draw")
H.mark()
local plain = addLook("Plain", live("ON"))
EC.Show_Look({ Look = "Plain (" .. plain .. ")" })
T.excludes("its address has no text in it", address(), "-")
T.eq("what Navigator loads is what the tab sent", served(plain), stored(plain))
T.eq("nothing is kept to redraw from", cached(plain), nil)
T.eq("and the tab hears nothing about it", stateLook(plain).badgeNow, nil)

H.mark()
clock = clock + 3600
setLevel("80")
T.eq("a live look that isn't shown draws nothing", told(), 0)

H.mark()
EC.Show_Look({ Look = "Battery (" .. battery .. ")" })
T.eq("showing it draws at once, whatever the last draw", told(), 1)
T.eq("with today's value", stateLook(battery).badgeNow, "80%")
T.contains("and the new address shows", address(), "/" .. battery .. ".png")

T.section("A variable shared with Show when")
local high = addLook("High", live(LEVEL .. "%"), { showWhen = LEVEL .. " >= 50" })
local low = addLook("Low", nil, { showWhen = LEVEL .. " < 50" })
Properties["Look Control"] = "By Value"
OnPropertyChanged("Look Control")
settle()
T.eq("By Value shows the look with the badge", Variables["Look"], "High")
H.mark()
clock = clock + 3600
setLevel("90")
T.eq("the badge hears the variable", told(), 1)
T.eq("reading it", stateLook(high).badgeNow, "90%")
setLevel("40")
T.eq("and Show when hears it too", Variables["Look"], "Low")
setLevel("95")
T.eq("after the badge stopped watching, Show when still hears it", Variables["Look"], "High")
Properties["Look Control"] = "On Select"
OnPropertyChanged("Look Control")
H.tab("_DELETE_LOOK", { id = low })
EC.Show_Look({ Look = "Battery (" .. battery .. ")" })
H.tab("_DELETE_LOOK", { id = high })
settle()

T.section("A Director restart")
local beforeRestart = served(battery)
hasLevel = false
setDevices()
H.mark()
H.restart()
T.eq("with the variable not there yet, the proxy still hears of the look", told(), 1)
T.eq("and the picture from before stays", served(battery), beforeRestart)
H.mark()
hasLevel = true
level = "33"
setDevices()
settle()
T.eq("when it comes, the badge draws", stateLook(battery).badgeNow, "33%")
T.eq("once", told(), 1)
T.contains("under the shown look", address(), "/" .. battery .. ".png")

T.section("A restart where the first value isn't the real one")
saveBadge(battery, "Battery", live(LEVEL .. "%", { every = 3600 }))
-- The shim fires every timer at once, and this one ends the starting window.
local realSetTimer = SetTimer
SetTimer = function(name, ...)
  if name ~= "LiveBadgeBootWait" then
    return realSetTimer(name, ...)
  end
end
H.restart()
settle()
H.mark()
clock = clock + 10
setLevel("44")
T.eq("the wait while starting is short, whatever the look's choice", told(), 0)
clock = clock + 20
settle()
T.eq("so the real value soon shows", told(), 1)
SetTimer = realSetTimer
saveBadge(battery, "Battery", live(LEVEL .. "%"))
H.restart()
settle()

T.section("A variable that comes back")
clock = clock + 3600
hasLevel = false
setDevices()
OnWatchedVariableChanged(BATTERY, 1002, "Idle")
Properties["Look Control"] = "Manual"
saveBadge(battery, "Battery", live(LEVEL .. "%", { every = 3600 }))
settle()
T.eq("while it's gone there's no badge", painted(served(battery)), 0)
hasLevel = true
level = "45"
setDevices()
H.mark()
OnWatchedVariableChanged(BATTERY, 1001, level)
settle()
T.eq("when it's back the badge shows at once, whatever the look's choice", told(), 1)
T.truthy("drawn", painted(served(battery)) > 0)
saveBadge(battery, "Battery", live(LEVEL .. "%"))

T.section("A variable that comes in the gap before By Value starts")
hasLevel = false
setDevices()
SetTimer = function(name, ...)
  if name ~= "LiveBadgeBootWait" then
    return realSetTimer(name, ...)
  end
end
H.restart()
T.falsy("the address has no text in it yet", address():match("%-%x+$"))
hasLevel = true
level = "46"
setDevices()
Properties["Look Control"] = "By Value"
OnPropertyChanged("Look Control")
settle()
T.truthy("the badge's own retry still finds it and draws", address():match("%-%x+$"))
SetTimer = realSetTimer
Properties["Look Control"] = "Manual"
OnPropertyChanged("Look Control")
H.restart()
settle()

T.section("A restart where the variable never comes")
hasLevel = false
setDevices()
H.mark()
H.restart()
settle()
T.eq("once the wait is over the badge goes", painted(served(battery)), 0)
T.eq("the proxy hears of the look, and again when the badge goes", told(), 2)
T.contains("the tab hears why", stateLook(battery).badgeError, "not found")
T.eq("the tab has nothing to draw", stateLook(battery).badgeNow, nil)
hasLevel = true
level = "34"
setDevices()

T.section("A restart with the folder replaced")
H.restart()
settle()
clock = clock + 3600
hasLevel = false
setDevices()
ShimFiles(SERVED)[battery .. ".png"] = nil
H.mark()
H.restart()
T.eq("the stored picture serves, since nothing else is there", served(battery), stored(battery))
T.eq("and the proxy hears", told(), 1)
hasLevel = true
setDevices()
settle()

T.section("A picture it can't draw on")
local oddFields = H.lookFields("Odd")
oddFields.custom = live("PARAM{100,1002}")
H.tab("_SAVE_LOOK", oddFields)
local odd = tonumber(H.lastUi("SAVED").look)
logged = {}
H.mark()
H.sendImage(odd, H.png("odd"))
EC.Show_Look({ Look = "Odd (" .. odd .. ")" })
T.eq("the stored picture serves", served(odd), stored(odd))
T.eq("the proxy hears", told(), 1)
T.truthy("the log says", warned("Badge:") == 1)

T.section("The tab's preview of a badge")
H.tab("_EVAL_EXPRESSION", { id = "b1", expression = "PARAM{100,1002}: 12.345", mode = "string" })
local answer = JSON:decode(H.lastUi("EVAL_RESULT").data)
T.eq("the answer goes by its id", answer.id, "b1")
T.eq("the text as it reads", answer.result, "Idle: 12.345")
T.eq("and as it fits", answer.fitted, "Idle:")
H.tab("_EVAL_EXPRESSION", { id = "b2", expression = "PARAM{100,NOPE}", mode = "string" })
T.contains("a missing variable is an error", JSON:decode(H.lastUi("EVAL_RESULT").data).error, "NOPE")
H.tab("_EVAL_EXPRESSION", { id = "w1", expression = "1 < 2" })
T.eq("Show when's preview is as it was", JSON:decode(H.lastUi("EVAL_RESULT").data).result, "true")

T.section("What the driver takes")
local function refused(badge)
  local fields = H.lookFields("Odd")
  fields.id = odd
  fields.custom = { badge = badge }
  H.mark()
  H.tab("_SAVE_LOOK", fields)
  return H.lastUi("ERROR") and H.lastUi("ERROR").message or H.lastUi("ERROR")
end
T.contains(
  "a live badge's text has a limit",
  tostring(refused(live(string.rep("x", Looks.MAX_LIVE_BADGE) .. LEVEL).badge)),
  "at most"
)
T.contains("a plain one is 5 characters", tostring(refused(live("TOOLONG").badge)), "1 to 5")
T.contains("an update choice is one of the list", tostring(refused(live(LEVEL, { every = 7 }).badge)), "update choice")

T.section("A device leaving the project")
EC.Show_Look({ Look = "Battery (" .. battery .. ")" })
local deviceGone = #logged
clock = clock + 3600
level = "35"
setLevel("35")
T.truthy("the badge is there before", painted(served(battery)) > 0)
clock = clock + 3600
OnDeviceRemovedFromProject(BATTERY)
settle()
T.eq("it goes with the device", painted(served(battery)), 0)
T.contains("the tab hears why", stateLook(battery).badgeError, "removed")
T.truthy("the log says", #logged > deviceGone and warned("Badge:") > 0)
local warnings = warned("Badge:")
settle()
settle()
T.eq("once", warned("Badge:"), warnings)
H.tab("_DELETE_LOOK", { id = battery })
T.eq("deleting the look removes what was kept", cached(battery), nil)

T.finish()
