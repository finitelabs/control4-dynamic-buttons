--- The picture bank: display_icons states whose pictures the buttons write while they run. A
--- picture's hash picks its slot, so every look and button showing it shares one state, and a slot
--- keeps its picture until the controller restarts and a button refreshes the Navigators, since
--- remotes and apps keep a state's picture.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_bank.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Bank = require("dynamic_button.bank")
local persist = require("lib.persist")

local RECORDS = "C4Z/bank"
local PICTURES = "C4Z/www/bank"
local HOUR = 3600000

local clock = 1794600000000
local booted = clock - HOUR

--- @return integer ms
local function now()
  return clock
end

--- @return number seconds
local function uptime()
  return (clock - booted) / 1000
end

--- The controller restarts and has been up two minutes.
local function restartController()
  clock = clock + HOUR
  booted = clock
  clock = clock + 120000
end

--- @param value any
--- @return any copy
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = copy(v)
  end
  return out
end

--- A store like persist, which hands out copies: one per button.
--- @return table store
local function memoryStore()
  local values = {}
  return {
    get = function(_, key, default)
      local value = values[key]
      if value == nil then
        return default
      end
      return copy(value)
    end,
    set = function(_, key, value)
      values[key] = copy(value)
    end,
  }
end

local refreshes = 0

--- @param size integer
--- @param store? table
--- @param liveCap? integer
--- @param id? integer The button (optional; 1).
--- @param buttons? fun(): integer[] The project's Dynamic Buttons (optional; none to wait on).
--- @return Bank bank
local function newBank(size, store, liveCap, id, buttons)
  return Bank:new({
    store = store or memoryStore(),
    enabled = true,
    refresh = function()
      refreshes = refreshes + 1
    end,
    deviceId = id or 1,
    buttons = buttons or function()
      return {}
    end,
    size = size,
    liveCap = liveCap,
    now = now,
    uptime = uptime,
  })
end

--- @param state string|nil
--- @return string|nil slot
local function slotOf(state)
  return state and state:match("^p(%d+)$")
end

--- @param state string|nil
--- @return string|nil record The slot's record: the picture's hash and when it was last sent.
local function record(state)
  return ShimFiles(RECORDS)[slotOf(state) or ""]
end

--- @param png string
--- @return string hash
local function hashOf(png)
  return (C4:Hash("SHA256", png))
end

--- @param png string
--- @param at integer
--- @return string record
local function recordOf(png, at)
  return string.format("%s %.0f", hashOf(png), at)
end

--- @param dir string
local function wipe(dir)
  for name in pairs(ShimFiles(dir)) do
    ShimFiles(dir)[name] = nil
  end
end

T.section("A picture's slot")
local a = newBank(8)
a:start()
local red = a:slotFor("Red")
T.eq("starts at the picture's place in the bank", slotOf(red), tostring(tonumber(hashOf("Red"):sub(1, 8), 16) % 8 + 1))
T.eq("whose record holds the picture's hash and when it was sent", record(red), recordOf("Red", clock))
T.eq("and whose picture is written", H.banked(red), "Red")

T.section("The same picture again")
T.eq("from another look keeps its state", a:slotFor("Red"), red)
T.eq("from another button too", newBank(8):slotFor("Red"), red)
ShimFiles(PICTURES)[slotOf(red) .. ".png"] = nil
T.eq("a picture file that's gone keeps its state", a:slotFor("Red"), red)
T.eq("and is written again", H.banked(red), "Red")

T.section("Another picture")
local blue = a:slotFor("Blue")
T.truthy("takes another state", slotOf(blue) and blue ~= red)
T.eq("with its picture", H.banked(blue), "Blue")

T.section("Until the controller restarts")
wipe(RECORDS)
wipe(PICTURES)
local b = newBank(2)
none, err = b:slotFor("One")
T.eq("a new bank shows pictures by address until its buttons start", { none, err }, { nil, Bank.WAIT })
local refreshesBefore = refreshes
b:start()
T.eq("and once they all have, refreshes the Navigators so apps learn its states", refreshes, refreshesBefore + 1)
local one, two = b:slotFor("One"), b:slotFor("Two")
T.truthy("(two slots)", slotOf(one) and slotOf(two) and one ~= two)
clock = clock + 24 * HOUR
local none, err = b:slotFor("Three")
T.eq("no slot takes a new picture, however long it's been", { none, err }, { nil, Bank.FULL })
T.eq("so each keeps its picture", { H.banked(one), H.banked(two) }, { "One", "Two" })

T.section("After a controller restart")
restartController()
T.eq("a picture shown again keeps its slot", b:slotFor("One"), one)
T.eq("and is marked sent again", record(one), recordOf("One", clock))
T.eq("a new picture takes no slot yet, as apps keep their copies", select(2, b:slotFor("Three")), Bank.FULL)
refreshesBefore = refreshes
b:start()
T.eq("the first button to start since refreshes the Navigators", refreshes, refreshesBefore + 1)
newBank(2):start()
T.eq("and the others don't", refreshes, refreshesBefore + 1)
T.eq("then a new picture takes a slot not sent since", b:slotFor("Three"), two)
T.eq("with its picture", H.banked(two), "Three")
T.eq("so the bank is full again until the next one", select(2, b:slotFor("Two")), Bank.FULL)

T.section("A look whose picture changes while it shows")
wipe(RECORDS)
wipe(PICTURES)
local live = newBank(8, nil, 2)
live:start()
local first = live:slotFor("Badge 1", 7)
T.truthy("takes slots for its pictures", slotOf(first) and slotOf(live:slotFor("Badge 2", 7)))
none, err = live:slotFor("Badge 3", 7)
T.eq("up to its share between restarts", { none, err }, { nil, Bank.CAPPED })
T.eq("a picture it showed before keeps its slot", live:slotFor("Badge 1", 7), first)
T.truthy("another such look has a share of its own", slotOf(live:slotFor("Badge 3", 8)))
T.truthy("and a look whose picture stays has no share", slotOf(live:slotFor("Still")))
restartController()
T.truthy("a restart gives the look its share again", slotOf(live:slotFor("Badge 4", 7)))

T.section("An update, which replaces the folder")
wipe(RECORDS)
wipe(PICTURES)
local store = memoryStore()
local u = newBank(256, store)
u:start()
local old = u:slotFor("Old")
restartController()
local kept = u:slotFor("Kept")
local keptAt = clock
T.truthy("(two slots)", slotOf(old) and slotOf(kept) and old ~= kept)
wipe(RECORDS)
wipe(PICTURES)
u = newBank(256, store)
u:start()
T.eq("a button writes again the records of the slots it sent since the restart", record(kept), recordOf("Kept", keptAt))
T.eq("but not one it sent before", record(old), nil)
T.eq("its look keeps its state", u:slotFor("Kept"), kept)
T.eq("with the picture written again", H.banked(kept), "Kept")
local mine = u:slotFor("Mine")
ShimFiles(RECORDS)[slotOf(mine)] = recordOf("Theirs", clock)
u = newBank(256, store)
u:start()
T.eq("a slot another button bound at the same moment is left to it", record(mine), recordOf("Theirs", clock))
local moved = u:slotFor("Mine")
T.truthy("and the picture takes another", slotOf(moved) and moved ~= mine)
restartController()
u = newBank(256, store)
u:start()
T.eq("a restart drops them all", store:get("BankShown"), nil)

T.section("An update, before every button has started")
wipe(RECORDS)
wipe(PICTURES)
local both = function()
  return { 1, 2 }
end
local firstStore, lastStore = memoryStore(), memoryStore()
local firstBank = newBank(8, firstStore, nil, 1, both)
local lastBank = newBank(8, lastStore, nil, 2, both)
refreshesBefore = refreshes
firstBank:start()
none, err = firstBank:slotFor("Early")
T.eq("a new bank waits for its other buttons to start", { none, err }, { nil, Bank.WAIT })
T.eq("before it refreshes the Navigators", refreshes, refreshesBefore)
T.eq("which the last to start does", lastBank:start(), true)
T.eq("once", refreshes, refreshesBefore + 1)
firstBank:ready()
T.eq("and the others keep its time", firstStore:get("BankRefreshed"), lastStore:get("BankRefreshed"))
local theirs = lastBank:slotFor("Theirs")
local theirsAt = clock
local onTheirs
for n = 1, 500 do
  if tonumber(hashOf("P" .. n):sub(1, 8), 16) % 8 + 1 == tonumber(slotOf(theirs)) then
    onTheirs = "P" .. n
    break
  end
end
T.truthy("(a picture whose path starts on another button's slot)", onTheirs)
wipe(RECORDS)
wipe(PICTURES)
firstBank = newBank(8, firstStore, nil, 1, both)
T.eq("the first button to start doesn't make the bank whole", firstBank:start(), false)
none, err = firstBank:slotFor(onTheirs)
T.eq("so a new picture waits rather than take a slot whose record isn't back", { none, err }, { nil, Bank.WAIT })
T.eq("and the other button's slot is left alone", { record(theirs), H.banked(theirs) }, {})
lastBank = newBank(8, lastStore, nil, 2, both)
T.eq("the last button to start makes it whole", lastBank:start(), true)
T.eq("with its slot's record back", record(theirs), recordOf("Theirs", theirsAt))
local after = firstBank:slotFor(onTheirs)
T.truthy("then the picture takes another slot", slotOf(after) and after ~= theirs)
T.eq("and the other button keeps its own", lastBank:slotFor("Theirs"), theirs)
lastBank = newBank(8, lastStore, nil, 2, both)
T.eq("a start with the bank already whole has no one to tell", lastBank:start(), false)

T.section("The refresh time through an update")
wipe(RECORDS)
local refreshStore = memoryStore()
newBank(8, refreshStore):start()
local refreshedAt = ShimFiles(RECORDS).refreshed
T.eq("(written at the new bank's refresh)", refreshedAt, string.format("%.0f", clock))
refreshesBefore = refreshes
wipe(RECORDS)
newBank(8, refreshStore):start()
T.eq("a button writes it again", ShimFiles(RECORDS).refreshed, refreshedAt)
T.eq("and doesn't refresh the Navigators again", refreshes, refreshesBefore)

T.section("A smaller bank after an update")
wipe(RECORDS)
wipe(PICTURES)
local shrinkStore = memoryStore()
local shrink = newBank(256, shrinkStore)
shrink:start()
local past
for n = 1, 20 do
  local state = shrink:slotFor("S" .. n)
  if tonumber(slotOf(state)) > 2 then
    past = state
    break
  end
end
T.truthy("(a slot past the smaller bank's end)", past)
wipe(RECORDS)
wipe(PICTURES)
shrink = newBank(2, shrinkStore)
shrink:start()
T.eq("drops a slot past its end", { record(past), shrinkStore:get("BankShown") }, { nil, nil })

T.section("A button leaving the project")
wipe(RECORDS)
wipe(PICTURES)
local leaving = newBank(256)
leaving:start()
local leavingState = leaving:slotFor("Leaving")
local hand = leaving:handOver()
T.eq(
  "hands over the slots it sent since the restart",
  hand,
  string.format("%s:%s:%.0f", slotOf(leavingState), hashOf("Leaving"), clock)
)
local keeperStore = memoryStore()
local keeper = newBank(256, keeperStore)
keeper:adopt(hand)
keeper:adopt("999:abc:" .. string.format("%.0f", clock))
keeper:adopt("9:abc:1")
T.eq("to a button that keeps those inside its bank and sent since", keeper:handOver(), hand)
wipe(RECORDS)
wipe(PICTURES)
keeper = newBank(256, keeperStore)
keeper:start()
T.eq("which writes their records again after an update", record(leavingState), recordOf("Leaving", clock))

T.section("A bank that's off")
wipe(RECORDS)
wipe(PICTURES)
local off = Bank:new({
  store = memoryStore(),
  enabled = false,
  refresh = function()
    refreshes = refreshes + 1
  end,
  now = now,
  uptime = uptime,
})
refreshesBefore = refreshes
off:start()
none, err = off:slotFor("Off")
T.eq("gives no state, and isn't full", { none, err }, { nil, nil })
off:adopt(hand)
T.eq("hands over nothing", off:handOver(), "")
T.eq("and writes nothing", { next(ShimFiles(RECORDS)), next(ShimFiles(PICTURES)) }, {})
T.eq("nor refreshes the Navigators", refreshes, refreshesBefore)

--- A controller restart: every slot was last sent, and the Navigators last refreshed, before it,
--- and Director starts the driver.
local function controllerRestarted()
  for name, text in pairs(ShimFiles(RECORDS)) do
    ShimFiles(RECORDS)[name] = (text:gsub(" %d+$", " 1"))
  end
  ShimFiles(RECORDS).refreshed = "1"
  persist:set("BankRefreshed", 1)
  local shown = persist:get("BankShown", {})
  for _, entry in pairs(shown) do
    entry.at = 1
  end
  persist:set("BankShown", next(shown) and shown or nil)
  H.restart()
end

T.section("A button whose bank is full")
Bank.SIZE = 2
H.start()
T.eq("a button with no look shows its own icon through a state", H.lastIcon().params.icon, Bank.OWN_STATE)
T.eq("and its first start refreshes the Navigators, as it's a new bank", H.navRefreshes, 1)
local oneId = H.addLook("One")
local twoId = H.addLook("Two")
EC.Show_Look({ Look = "Two (" .. twoId .. ")" })
local twoState = H.lastIcon().params.icon
local threeId = H.addLook("Three")
EC.Show_Look({ Look = "Three (" .. threeId .. ")" })
T.contains("shows a new picture by its address when no slot can take it", H.lastIcon().params.icon, "controller://")
T.eq("and Driver Status says so", Properties["Driver Status"], "Picture bank full until the controller restarts")
H.tab("_DELETE_LOOK", { id = oneId })
EC.Show_Look({ Look = "Two (" .. twoId .. ")" })
EC.Show_Look({ Look = "Three (" .. threeId .. ")" })
T.contains("a deleted look's slot keeps its picture until a restart", H.lastIcon().params.icon, "controller://")
local fourId = H.addLook("Four", H.png("Two"))
EC.Show_Look({ Look = "Four (" .. fourId .. ")" })
T.eq("a look with another's picture shows through its state", H.lastIcon().params.icon, twoState)
T.eq("and Driver Status is Ready", Properties["Driver Status"], "Ready")
EC.Show_Look({ Look = "Three (" .. threeId .. ")" })
controllerRestarted()
local threeState = H.lastIcon().params.icon
T.eq("after a controller restart the button refreshes the Navigators", H.navRefreshes, 2)
T.truthy("and the shown look takes a slot", slotOf(threeState))
T.eq("with its picture", H.banked(threeState), H.png("Three"))
T.eq("and Driver Status is Ready again", Properties["Driver Status"], "Ready")

T.section("A renamed driver file")
function C4:GetDriverFileName()
  return "dynamic_button_copy.c4z"
end
H.restart()
T.contains("shows by address, as the states name the dynamic_button folder", H.lastIcon().params.icon, "controller://")
H.tab("_DELETE_LOOK", { id = fourId })
H.tab("_DELETE_LOOK", { id = threeId })
H.tab("_DELETE_LOOK", { id = twoId })
T.eq(
  "and the driver's own icon by its address",
  H.lastIcon().params.icon,
  "controller://driver/dynamic_button_copy/icons/experience_300.png"
)

T.section("A button that waits for the others after an update")
function C4:GetDriverFileName()
  return "dynamic_button.c4z"
end
function C4:GetDevicesByC4iName()
  return { [tostring(H.DEVICE_ID)] = "This button", ["905"] = "Another button", ["903"] = "A third button" }
end
local told, sent = {}, nil
function C4:SendToDevice(id, command, params)
  table.insert(told, id .. " " .. command)
  sent = params
end
wipe(RECORDS)
wipe(PICTURES)
persist:set("BankShown", nil)
Bank.SIZE = 8
H.restart()
local earlyId = H.addLook("Early")
T.contains("shows a new look by its address while others haven't started", H.lastIcon().params.icon, "controller://")
T.eq("and Driver Status is Ready, as the bank isn't full", Properties["Driver Status"], "Ready")
ShimFiles(RECORDS)["up-905"] = "1"
ShimFiles(RECORDS)["up-903"] = "1"
EC.BANK_READY()
local earlyState = H.lastIcon().params.icon
T.truthy("once they have, it shows through a state", slotOf(earlyState))
T.eq("with its picture", H.banked(earlyState), H.png("Early"))
ShimFiles(RECORDS)["up-" .. H.DEVICE_ID] = nil
told = {}
H.restart()
T.eq("the last button to start tells the others", told, { "903 BANK_READY", "905 BANK_READY" })
H.tab("_DELETE_LOOK", { id = earlyId })

T.section("A new bank, from an update of a version without one")
wipe(RECORDS)
wipe(PICTURES)
persist:set("BankShown", nil)
persist:set("BankRefreshed", nil)
local refreshes = H.navRefreshes
told = {}
H.restart()
local freshId = H.addLook("Fresh")
T.contains("shows a look by its address while others haven't started", H.lastIcon().params.icon, "controller://")
T.eq("and doesn't refresh the Navigators yet", H.navRefreshes, refreshes)
local refreshedAt = string.format("%.0f", C4:GetTime())
ShimFiles(RECORDS)["up-905"] = "1"
ShimFiles(RECORDS)["up-903"] = "1"
ShimFiles(RECORDS).refreshed = refreshedAt
EC.BANK_READY()
local freshState = H.lastIcon().params.icon
T.truthy("once the last button has refreshed them, it shows through a state", slotOf(freshState))
T.eq("and keeps that refresh time for its next update", persist:get("BankRefreshed"), tonumber(refreshedAt))
H.tab("_DELETE_LOOK", { id = freshId })
wipe(RECORDS)
wipe(PICTURES)
persist:set("BankShown", nil)
persist:set("BankRefreshed", nil)
ShimFiles(RECORDS)["up-905"] = "1"
ShimFiles(RECORDS)["up-903"] = "1"
H.restart()
T.eq("the last button to start refreshes the Navigators once", H.navRefreshes, refreshes + 1)
T.eq("and tells the others", told, { "903 BANK_READY", "905 BANK_READY" })
local lastId = H.addLook("Last")
T.truthy("and shows its own looks through states", slotOf(H.lastIcon().params.icon))
H.restart()
T.eq("its next start doesn't refresh again", H.navRefreshes, refreshes + 1)
H.tab("_DELETE_LOOK", { id = lastId })

T.section("Removing a button from the project")
told = {}
wipe(RECORDS)
wipe(PICTURES)
persist:set("BankShown", nil)
for _, id in ipairs({ H.DEVICE_ID, 905, 903 }) do
  ShimFiles(RECORDS)["up-" .. id] = "1"
end
H.restart()
H.addLook("Gone")
local goneState = H.lastIcon().params.icon
OnDriverRemovedFromProject()
T.eq("hands its slots to one other Dynamic Button", told, { "903 BANK_ADOPT" })
T.contains("with the slot it sent", sent.SLOTS, slotOf(goneState) .. ":" .. hashOf(H.png("Gone")) .. ":")
T.eq("whose picture stays", H.banked(goneState), H.png("Gone"))
persist:set("BankShown", nil)
EC.BANK_ADOPT(sent)
T.truthy("a button handed slots keeps them in its own store", persist:get("BankShown", {})[slotOf(goneState)])

T.finish()
