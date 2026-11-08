--- Each look's Button Link under the C4 shim: added, renamed and removed with its look, tapped by a press while its
--- look shows, re-added before late init so Director keeps its connection through a restart and an update, and
--- removed by Reset Driver.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_links.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

--- A light offering an On, Off and Toggle link, as a keypad button binds to it.
local LIGHT, LIGHT_TOGGLE = 900, 302

--- @return table<string, table> links This button's Button Link connections, by name.
local function links()
  local found = {}
  for id, binding in pairs(GetDeviceBindings(H.DEVICE_ID)) do
    for _, class in pairs(binding.bindingclasses or {}) do
      if class.class == "BUTTON_LINK" then
        found[binding.name] = { id = id, provider = binding.provider, type = binding.type }
      end
    end
  end
  return found
end

--- @param name string
--- @return integer|nil id The binding id of the look's link.
local function linkId(name)
  local link = links()[name]
  return link and link.id
end

--- @return { binding: integer, command: string }[] taps What the press sent on any binding but the proxy's.
local function taps()
  local sent = {}
  for _, message in ipairs(H.proxy) do
    if message.binding ~= 5001 then
      table.insert(sent, { binding = message.binding, command = message.command })
    end
  end
  return sent
end

--- @param mode string
local function setLookControl(mode)
  Properties["Look Control"] = mode
  OnPropertyChanged("Look Control")
end

H.start()
local closed = H.addLook("Closed")
local open = H.addLook("Open")

T.section("Each look has a Button Link")
T.truthy("named for the look and its number", linkId("Closed (" .. closed .. ")"))
T.truthy("as the Show Look list names it", linkId("Open (" .. open .. ")"))
local closedLink = links()["Closed (" .. closed .. ")"]
T.eq("a control connection, on the button's side of the link", { closedLink.type, closedLink.provider }, { 1, false })
T.truthy("in the range kept for dynamic connections", closedLink.id >= 10 and closedLink.id <= 999)

T.section("A press with nothing bound")
setLookControl("On Select")
H.mark()
H.press()
T.eq("sends nothing on the links", taps(), {})
T.eq("and Look Control still steps", Variables["Look"], "Open")
EC.Show_Look({ Look = "Closed (" .. closed .. ")" })

T.section("A press taps the shown look's link")
C4:Bind(LIGHT, LIGHT_TOGGLE, H.DEVICE_ID, closedLink.id, "BUTTON_LINK")
H.mark()
H.press()
T.eq(
  "a push and a click, as a keypad tap sends them",
  taps(),
  { { binding = closedLink.id, command = "DO_PUSH" }, { binding = closedLink.id, command = "DO_CLICK" } }
)
T.eq("then On Select steps to the next look", Variables["Look"], "Open")
H.mark()
H.press()
T.eq("the next press taps the look shown then, which has nothing bound", taps(), {})
setLookControl("Manual")
EC.Show_Look({ Look = "Closed (" .. closed .. ")" })
H.mark()
H.press()
T.eq("Manual taps the link too", #taps(), 2)
T.eq("and leaves the look alone", Variables["Look"], "Closed")

T.section("A message from the bound device")
local ok, err = pcall(ReceivedFromProxy, closedLink.id, "MATCH_LED_STATE", { STATE = true })
T.check("is taken without an error", ok, tostring(err))

T.section("Renaming a look")
H.tab("_SAVE_LOOK", H.lookFields("Shut", { id = closed }))
T.eq("renames its link", linkId("Shut (" .. closed .. ")"), closedLink.id)
T.eq("under its new name only", linkId("Closed (" .. closed .. ")"), nil)
T.eq("and keeps what it's bound to", C4:GetBoundProviderDevice(H.DEVICE_ID, closedLink.id), LIGHT)

T.section("A Director restart")
local readded = {}
local wasAdd, wasLateInit = C4.AddDynamicBinding, ShimLateInit
local lateInit = false
C4.AddDynamicBinding = function(self, id, ...)
  readded[id] = lateInit and "late init" or "init"
  return wasAdd(self, id, ...)
end
ShimLateInit = function(...)
  lateInit = true
  return wasLateInit(...)
end
H.restart()
C4.AddDynamicBinding, ShimLateInit = wasAdd, wasLateInit
T.eq("re-adds each link before late init, so Director can reattach its connection", readded[closedLink.id], "init")
T.eq("under the same id and name", linkId("Shut (" .. closed .. ")"), closedLink.id)
T.eq("still bound", C4:GetBoundProviderDevice(H.DEVICE_ID, closedLink.id), LIGHT)
H.mark()
H.press()
T.eq("and a press taps it", #taps(), 2)

T.section("A driver update")
H.update()
T.eq("keeps the link and its id", linkId("Shut (" .. closed .. ")"), closedLink.id)
T.eq("still bound", C4:GetBoundProviderDevice(H.DEVICE_ID, closedLink.id), LIGHT)

T.section("Deleting a look")
H.tab("_DELETE_LOOK", { id = open })
T.eq("removes its link", linkId("Open (" .. open .. ")"), nil)
T.eq("and only its", linkId("Shut (" .. closed .. ")"), closedLink.id)
local spare = H.addLook("Spare")
T.truthy("a new look gets a link of its own", linkId("Spare (" .. spare .. ")"))

T.section("Reset Driver")
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("removes every link", links(), {})
T.eq("and their connections", C4:GetBoundProviderDevice(H.DEVICE_ID, closedLink.id), 0)

T.finish()
