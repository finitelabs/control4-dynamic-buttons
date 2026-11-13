--- The picture bank: display_icons states whose pictures the buttons write while they run. Every
--- Dynamic Button shares the bank, so a button claims slots in the driver's folder, and a slot it
--- lets go waits for a Navigator refresh, since apps and remotes keep a state's first picture.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_bank.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Bank = require("dynamic_button.bank")

local CLAIMS = "C4Z/bank"
local PICTURES = "C4Z/www/bank"

local clock = 1000

--- @return integer ms
local function now()
  return clock
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

--- @param deviceId integer
--- @param size integer
--- @param store? table
--- @return Bank bank
local function newBank(deviceId, size, store)
  return Bank:new({ store = store or memoryStore(), deviceId = deviceId, enabled = true, size = size, now = now })
end

--- @param png string
--- @return fun(): string picture
--- @return fun(): integer reads How many times the picture was read.
local function picture(png)
  local reads = 0
  return function()
    reads = reads + 1
    return png
  end, function()
    return reads
  end
end

--- @param state string|nil
--- @return string|nil slot
local function slotOf(state)
  return state and state:match("^p(%d+)$")
end

--- @param state string|nil
--- @return string|nil claim
local function claim(state)
  return ShimFiles(CLAIMS)[slotOf(state) or ""]
end

--- @param dir string
local function wipe(dir)
  for name in pairs(ShimFiles(dir)) do
    ShimFiles(dir)[name] = nil
  end
end

T.section("Taking a slot")
local a = newBank(843, 4)
local a1 = a:slotFor(1, 1, picture("A1"))
T.truthy("a look's picture gets a state", slotOf(a1))
T.eq("whose claim names the button", claim(a1), "843")
T.eq("and whose picture is written", H.banked(a1), "A1")

T.section("The same picture again")
local read, reads = picture("A1")
T.eq("keeps its state", a:slotFor(1, 1, read), a1)
T.eq("without reading the picture", reads(), 0)
ShimFiles(PICTURES)[slotOf(a1) .. ".png"] = nil
T.eq("a picture file that's gone keeps its state", a:slotFor(1, 1, read), a1)
T.eq("and is written again", H.banked(a1), "A1")

T.section("A new picture")
local a2 = a:slotFor(1, 2, picture("A2"))
T.neq("takes a new state, so no app shows the old picture", a2, a1)
T.eq("with the new picture", H.banked(a2), "A2")
T.eq("the old slot waits for a refresh", claim(a1), "freed 1000")

T.section("Another button")
local b = newBank(845, 4)
local b1 = b:slotFor(1, 1, picture("B1"))
T.truthy("takes a slot of its own", slotOf(b1) and b1 ~= a1 and b1 ~= a2)
local b2 = b:slotFor(2, 1, picture("B2"))
T.truthy("and another", slotOf(b2) and b2 ~= b1 and b2 ~= a1 and b2 ~= a2)
local none, err = b:slotFor(3, 1, picture("B3"))
T.eq("a full bank gives no state", none, nil)
T.eq("and says it's full", err, Bank.FULL)
T.eq("a slot waiting for a refresh is not taken", claim(a1), "freed 1000")

T.section("A Navigator refresh")
clock = 2000
a:refreshed()
T.eq("is kept in the folder for every button", ShimFiles(CLAIMS)["refreshed"], "2000")
local b3 = b:slotFor(3, 1, picture("B3"))
T.eq("a slot let go before it can be taken", b3, a1)
T.eq("by any button", claim(b3), "845")
T.eq("with its new picture", H.banked(b3), "B3")
clock = 3000
a:release(1)
T.eq("a slot let go after it waits for the next", claim(a2), "freed 3000")
T.eq("so a full bank stays full", b:slotFor(4, 1, picture("B4")), nil)
clock = 3000
b:refreshed()
T.eq("a refresh at the moment it was let go frees it", b:slotFor(4, 1, picture("B4")), a2)

T.section("An update, which replaces the folder")
wipe(CLAIMS)
wipe(PICTURES)
local cStore = memoryStore()
local c = newBank(847, 8, cStore)
local c1 = c:slotFor(1, 1, picture("C1"))
local c2 = c:slotFor(2, 1, picture("C2"))
clock = 4000
local c3 = c:slotFor(2, 2, picture("C2 again"))
wipe(CLAIMS)
wipe(PICTURES)
-- Another button that started first took look 1's slot.
ShimFiles(CLAIMS)[slotOf(c1)] = "849"
c = newBank(847, 8, cStore)
c:start()
T.eq("a button claims its slots again at start", claim(c3), "847")
T.eq("and keeps the one it let go waiting for a refresh", claim(c2), "freed 4000")
T.eq("but leaves one another button holds now", claim(c1), "849")
read, reads = picture("C2 again")
T.eq("its look keeps its state", c:slotFor(2, 2, read), c3)
T.eq("with the picture written again", H.banked(c3), "C2 again")
local c4 = c:slotFor(1, 1, picture("C1"))
T.truthy("a look whose slot was taken gets a new one", slotOf(c4) and c4 ~= c1 and c4 ~= c2 and c4 ~= c3)

T.section("A button leaving the project")
clock = 5000
c:removed()
T.eq("lets every slot go", { claim(c3), claim(c4) }, { "freed 5000", "freed 5000" })
local d = newBank(851, 8)
d:refreshed()
local taken = {}
for look = 1, 7 do
  local state = d:slotFor(look, 1, picture("D"))
  if state then
    taken[state] = true
  end
end
T.truthy("which another button takes after a refresh", taken[c3] and taken[c4])
T.falsy("but not one a button still holds", taken[c1])

T.section("A bank that's off")
wipe(CLAIMS)
wipe(PICTURES)
local off = Bank:new({ store = memoryStore(), deviceId = 853, enabled = false, now = now })
off:start()
local offState, offErr = off:slotFor(1, 1, picture("Off"))
T.eq("gives no state", offState, nil)
T.eq("and isn't full", offErr, nil)
off:release(1)
off:refreshed()
T.eq("and writes nothing", { next(ShimFiles(CLAIMS)), next(ShimFiles(PICTURES)) }, {})

T.section("A button whose bank is full")
wipe(CLAIMS)
wipe(PICTURES)
Bank.SIZE = 2
H.start()
T.eq("a button with no look shows its own icon through a state", H.lastIcon().params.icon, Bank.OWN_STATE)
local refreshes = 0
RefreshNavs = function()
  refreshes = refreshes + 1
end
local one = H.addLook("One")
local oneState = H.lastIcon().params.icon
local two = H.addLook("Two")
EC.Show_Look({ Look = "Two (" .. two .. ")" })
local three = H.addLook("Three")
EC.Show_Look({ Look = "Three (" .. three .. ")" })
T.contains("shows a look by its address when no slot is free", H.lastIcon().params.icon, "controller://")
T.eq("and Driver Status says so", Properties["Driver Status"], "Picture bank full, run Refresh Navigators")
H.tab("_DELETE_LOOK", { id = one })
EC.Show_Look({ Look = "Two (" .. two .. ")" })
EC.Show_Look({ Look = "Three (" .. three .. ")" })
T.contains("a deleted look's slot waits for a refresh", H.lastIcon().params.icon, "controller://")
local told = {}
function C4:GetDevicesByC4iName()
  return { [tostring(H.DEVICE_ID)] = "This button", ["902"] = "Another button" }
end
function C4:SendToDevice(id, command)
  table.insert(told, id .. " " .. command)
end
H.mark()
EC.Refresh_Navigators()
T.eq("Refresh Navigators refreshes them", refreshes, 1)
T.eq("and tells every other Dynamic Button", told, { "902 BANK_REFRESHED" })
T.eq("the shown look takes the freed slot", H.lastIcon().params.icon, oneState)
T.eq("with its picture", H.banked(oneState), H.png("Three"))
T.eq("Driver Status is Ready again", Properties["Driver Status"], "Ready")
T.contains("the action is in driver.xml", io.open(H.XML):read("*a"), "<command>Refresh_Navigators</command>")

T.section("Another button refreshing Navigators")
local four = H.addLook("Four")
EC.Show_Look({ Look = "Four (" .. four .. ")" })
T.contains("a full bank shows the look by its address", H.lastIcon().params.icon, "controller://")
local liveFields = H.lookFields("Live")
liveFields.custom =
  { badge = { text = "PARAM{100,1002}", place = "Top Right", color = "#FFFFFF", background = "#DC2626" } }
H.mark()
H.tab("_SAVE_LOOK", liveFields)
local liveLook = tonumber(H.lastUi("SAVED").look)
H.sendImage(liveLook, H.png("Live"))
EC.Show_Look({ Look = "Live (" .. liveLook .. ")" })
T.eq("a look with a live badge needs no slot, so Driver Status is Ready", Properties["Driver Status"], "Ready")
H.tab("_DELETE_LOOK", { id = liveLook })
EC.Show_Look({ Look = "Four (" .. four .. ")" })
T.eq("and a look that does reads full again", Properties["Driver Status"], "Picture bank full, run Refresh Navigators")
H.tab("_DELETE_LOOK", { id = two })
Bank:new({ store = memoryStore(), deviceId = 902, enabled = true }):refreshed(C4:GetTime() + 1)
H.mark()
EC.BANK_REFRESHED()
T.truthy("takes the slot the other button's refresh freed", slotOf(H.lastIcon().params.icon))
T.eq("and Driver Status is Ready", Properties["Driver Status"], "Ready")

T.section("A renamed driver file")
function C4:GetDriverFileName()
  return "dynamic_button_copy.c4z"
end
H.restart()
T.contains("shows by address, as the states name the dynamic_button folder", H.lastIcon().params.icon, "controller://")
H.tab("_DELETE_LOOK", { id = four })
H.tab("_DELETE_LOOK", { id = three })
T.eq(
  "and the driver's own icon by its address",
  H.lastIcon().params.icon,
  "controller://driver/dynamic_button_copy/icons/experience_300.png"
)

T.finish()
