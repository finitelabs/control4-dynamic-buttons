--- The Button tab's Properties card under the C4 shim: the properties it is sent, a change made from
--- the tab, the changes it is turned away from, and a change made in Composer reaching the tab.

local T = require("testlib")
local H = require("dynamic_button_harness")

--- @param name string
--- @param state table|nil
--- @return table|nil property
local function property(name, state)
  for _, p in ipairs((state or H.state()).properties) do
    if p.name == name then
      return p
    end
  end
  return nil
end

--- @return integer count STATE messages sent over the socket since the last mark.
local function statePushes()
  local n = 0
  for _, m in ipairs(H.ui) do
    if m.command == "STATE" then
      n = n + 1
    end
  end
  return n
end

H.start()
H.mark()
H.tab("_GET_STATE")

T.section("The properties the tab is sent")
local names = {}
for _, p in ipairs(H.state().properties) do
  table.insert(names, p.name)
end
T.eq("every property in driver.xml order, labels and the Support Code left out", names, {
  "Cloud Status",
  "Automatic Updates",
  "Update Channel",
  "Driver Status",
  "Driver Version",
  "Log Level",
  "Log Mode",
  "Cloud Monitoring",
  "Look Control",
  "Shown Look",
})
T.eq("each under the label above it", property("Log Level").group, "Driver Settings")
T.eq("the cloud ones too", property("Automatic Updates").group, "Cloud Settings")
T.eq("and the button's", property("Look Control").group, "Button Settings")
T.eq("a list carries its driver.xml choices", property("Log Mode").choices, { "Off", "Print", "Log", "Print and Log" })
T.eq("with its value", property("Log Mode").value, "Off")
T.eq("a status is read-only", property("Driver Status").readonly, true)
T.eq("with its value", property("Driver Status").value, "Ready")
T.eq("a list is not", property("Log Level").readonly, false)
T.eq("Shown Look is read-only", property("Shown Look").readonly, true)

T.section("A change made in the tab")
H.mark()
local answer = JSON:decode(H.tab("_SET_DRIVER", { property = "Log Level", value = "4 - Debug" }))
T.eq("sets the property", Properties["Log Level"], "4 - Debug")
T.eq("the reply carries the state", answer._command, "STATE")
T.eq("with the new value", property("Log Level", JSON:decode(answer.state)).value, "4 - Debug")
T.truthy("and the socket hears it", statePushes() >= 1)

H.mark()
H.tab("_SET_DRIVER", { property = "Look Control", value = "On Select" })
T.eq("Look Control is set from the tab", Properties["Look Control"], "On Select")
T.eq("and the state follows it", H.state().lookControl, "On Select")

T.section("Changes the tab is turned away from")
H.mark()
JSON:decode(H.tab("_SET_DRIVER", { property = "Log Mode", value = "Loud" }))
T.eq("a value the list lacks leaves the property as it was", Properties["Log Mode"], "Off")
T.eq("and the tab is shown it unchanged", property("Log Mode").value, "Off")

H.mark()
local refused = JSON:decode(H.tab("_SET_DRIVER", { property = "Driver Version", value = "1" }))
T.eq("a read-only property is refused", refused._command, "ERROR")
T.neq("and keeps its value", Properties["Driver Version"], "1")

refused = JSON:decode(H.tab("_SET_DRIVER", { property = "Support Code", value = "not-a-code" }))
T.eq("the Support Code cannot be set from the tab", refused._command, "ERROR")
T.eq("so no code is entered", Properties["Support Code"], "")

refused = JSON:decode(H.tab("_SET_DRIVER", { property = "Look Control" }))
T.eq("a change with no value is refused", refused._command, "ERROR")
refused = JSON:decode(H.tab("_SET_DRIVER", { property = "Shown Now", value = "Off" }))
T.eq("so is a property the driver lacks", refused._command, "ERROR")

T.section("A change made in Composer")
for _, name in ipairs({
  "Automatic Updates",
  "Update Channel",
  "Log Mode",
  "Log Level",
  "Cloud Monitoring",
  "Look Control",
}) do
  local choices = property(name).choices
  local value = choices[1] == Properties[name] and choices[2] or choices[1]
  H.mark()
  Properties[name] = value
  OnPropertyChanged(name)
  T.truthy(name .. " is pushed to the tab", statePushes() >= 1)
  T.eq("with its new value", property(name).value, Properties[name])
end

T.finish()
