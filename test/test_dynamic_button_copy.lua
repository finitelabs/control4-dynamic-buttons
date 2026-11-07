--- The other Dynamic Buttons Copy To offers: this driver's items in the project, by room and then name,
--- without the button itself, and the button's own name for an export's file.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_copy.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

local FILE = "dynamic_button.c4z"

T.section("Copy To's list of buttons")
ShimSetDevices({
  [H.DEVICE_ID] = { deviceName = "Lake House", driverFileName = FILE, roomName = "Dock" },
  [910] = { deviceName = "Porch Light", driverFileName = FILE, roomName = "Porch" },
  [911] = { deviceName = "EV Charger", driverFileName = FILE, roomName = "Garage" },
  [912] = { deviceName = "Fan", driverFileName = FILE, roomName = "Family Room" },
  [913] = { deviceName = "Bench", driverFileName = FILE, roomName = "Family Room" },
})
H.start()

local reply = JSON:decode(H.tab("_GET_BUTTONS"))
T.eq("it answers as BUTTONS", reply._command, "BUTTONS")
local buttons = JSON:decode(reply.buttons)
local ids = {}
for _, b in ipairs(buttons) do
  table.insert(ids, b.id)
end
T.eq("the other Dynamic Buttons by room, then name, without this one", ids, { 913, 912, 911, 910 })
T.eq("each with its name and room", buttons[1], { id = 913, name = "Bench", roomName = "Family Room" })
T.eq(
  "and this button's own name and room",
  JSON:decode(reply.self),
  { id = H.DEVICE_ID, name = "Lake House", roomName = "Dock" }
)

T.section("Two buttons with one name in one room")
ShimSetDevices({
  [H.DEVICE_ID] = { deviceName = "Lake House", driverFileName = FILE, roomName = "Dock" },
  [951] = { deviceName = "Fan", driverFileName = FILE, roomName = "Family Room" },
  [950] = { deviceName = "Fan", driverFileName = FILE, roomName = "Family Room" },
})
buttons = JSON:decode(JSON:decode(H.tab("_GET_BUTTONS")).buttons)
T.eq("they come in id order", { buttons[1].id, buttons[2].id }, { 950, 951 })

T.section("Upper and lower case sort together")
ShimSetDevices({
  [H.DEVICE_ID] = { deviceName = "Lake House", driverFileName = FILE, roomName = "Dock" },
  [960] = { deviceName = "TV", driverFileName = FILE, roomName = "family room" },
  [961] = { deviceName = "Thermostat", driverFileName = FILE, roomName = "Family Room" },
  [962] = { deviceName = "amp", driverFileName = FILE, roomName = "Family Room" },
})
buttons = JSON:decode(JSON:decode(H.tab("_GET_BUTTONS")).buttons)
local names = {}
for _, b in ipairs(buttons) do
  table.insert(names, b.name)
end
T.eq("by room, then name, whatever their case", names, { "amp", "Thermostat", "TV" })

T.section("A project with no other Dynamic Button")
ShimSetDevices({ [H.DEVICE_ID] = { deviceName = "Lake House", driverFileName = FILE, roomName = "Dock" } })
reply = JSON:decode(H.tab("_GET_BUTTONS"))
T.eq("the list is empty", #JSON:decode(reply.buttons), 0)
T.eq("and still names this one", JSON:decode(reply.self).name, "Lake House")

ShimResetDevices()
T.finish()
