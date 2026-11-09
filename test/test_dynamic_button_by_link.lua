--- Look Control's By Link under the C4 shim: each look's Button Link reports its LED state with MATCH_LED_STATE, and
--- the first look whose link is bound and on or off as its Show while says shows. One link and separate links, every
--- STATE form, the default look, a press and the device's reply, a hold from programming, a Director restart and a
--- driver update, REQUEST_BUTTON_COLORS on a bind, at start and after a rename and the BUTTON_COLORS kept from it, a
--- timed look, an unbound link, a link removed with its look, Copy To and Import, Reset Driver and a lapsed license.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_by_link.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local persist = require("lib.persist")
local gate = require("lib.drivercentral")
local Looks = require("dynamic_button.looks")

--- A light offering an On, Off and Toggle link, as a keypad button binds to it, and another light.
local LIGHT, LIGHT_ON, LIGHT_OFF, LIGHT_TOGGLE = 900, 300, 301, 302
local OTHER_LIGHT = 901

--- @param id integer
--- @return integer|nil bindingId The look's Button Link, found by its name as Composer lists it.
local function linkOf(id)
  for bindingId, binding in pairs(GetDeviceBindings(H.DEVICE_ID)) do
    for _, class in pairs(binding.bindingclasses or {}) do
      if class.class == "BUTTON_LINK" and binding.name:match("%((%d+)%)$") == tostring(id) then
        return bindingId
      end
    end
  end
  return nil
end

--- Bind a look's link to one of the light's links, as Composer's Connections does.
--- @param id integer
--- @param lightLink integer
local function bind(id, lightLink)
  C4:Unbind(H.DEVICE_ID, linkOf(id))
  C4:Bind(LIGHT, lightLink, H.DEVICE_ID, linkOf(id), "BUTTON_LINK")
end

--- The light tells a look's link its LED state.
--- @param id integer
--- @param state any
local function led(id, state)
  ReceivedFromProxy(linkOf(id), "MATCH_LED_STATE", { STATE = state })
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

--- Save a look's fields, as the Button tab does: it sends them all.
--- @param id integer|nil Nil for a new look.
--- @param name string
--- @param extra table|nil
--- @return table reply
local function save(id, name, extra)
  local fields = H.lookFields(name, extra)
  fields.id = id
  return JSON:decode(H.tab("_SAVE_LOOK", fields))
end

--- Add a look with its picture.
--- @param name string
--- @param extra table|nil
--- @return integer id
local function addLook(name, extra)
  local id = tonumber(save(nil, name, extra).look)
  H.sendImage(id, H.png(name))
  return id
end

--- @param id integer
--- @return table|nil look The look as the Button tab's state has it.
local function tabLook(id)
  H.tab("_GET_STATE")
  for _, look in ipairs(H.state().looks) do
    if look.id == id then
      return look
    end
  end
  return nil
end

--- @return table<string, boolean> states Each link's last state as the driver keeps it, by look id.
local function kept()
  return persist:get("LinkStates") or {}
end

--- Show a look from programming.
--- @param id integer
local function showLook(id)
  EC.Show_Look({ Look = Looks.label(tabLook(id)) })
end

--- @return { binding: integer, params: table, type: string }[] asked Each REQUEST_BUTTON_COLORS sent since the mark.
local function asked()
  local found = {}
  for _, message in ipairs(H.proxy) do
    if message.command == "REQUEST_BUTTON_COLORS" then
      table.insert(found, { binding = message.binding, params = message.params, type = message.message or "COMMAND" })
    end
  end
  return found
end

--- The device bound to a look's link gives its LED colors, as it answers REQUEST_BUTTON_COLORS.
--- @param id integer
--- @param on any
--- @param off any
--- @param extra table|nil Other parameters a device sends with them.
local function giveColors(id, on, off, extra)
  local params = { ON_COLOR = on, OFF_COLOR = off }
  for name, value in pairs(extra or {}) do
    params[name] = value
  end
  ReceivedFromProxy(linkOf(id), "BUTTON_COLORS", params)
end

local clock = 1000000
-- luacheck: push ignore os
os.time = function()
  return clock
end
-- luacheck: pop

H.start()

T.section("Look Control offers By Link")
local choices
H.tab("_GET_STATE")
for _, property in ipairs(H.state().properties) do
  if property.name == "Look Control" then
    choices = property.choices
  end
end
T.eq("after the other three", choices, { "On Select", "Manual", "By Value", "By Link" })

T.section("A look's Show while")
local bulbOn = addLook("Bulb on")
local bulbOff = addLook("Bulb off", { showWhile = "off" })
T.eq("a look shows while its link is on, unless it says", tabLook(bulbOn).showWhile, "on")
T.eq("a look can show while its link is off", tabLook(bulbOff).showWhile, "off")
T.eq(
  "anything else is refused",
  save(bulbOn, "Bulb on", { showWhile = "dim" }).message,
  '"Show while" is "on" or "off"'
)
T.eq("and the look keeps its own", tabLook(bulbOn).showWhile, "on")
T.truthy("a look kept before Show while shows while its link is on", Looks.showsWhileOn({ name = "Old" }))

T.section("One link")
bind(bulbOn, LIGHT_TOGGLE)
bind(bulbOff, LIGHT_TOGGLE)
setLookControl("By Link")
T.eq("before the light reports, the look stays", shown(), "Bulb on")
led(bulbOn, false)
led(bulbOff, false)
T.eq("the light off shows the look that shows while its link is off", shown(), "Bulb off")
H.mark()
led(bulbOn, true)
led(bulbOff, true)
T.eq("the light on shows the look that shows while its link is on", shown(), "Bulb on")
T.eq("as any change of look, firing its events", H.fired, { "Look Changed", "Bulb on Shown" })
T.eq("the tab hears each link's state", { tabLook(bulbOn).linkState, tabLook(bulbOff).linkState }, { "on", "on" })
T.eq("and that both are bound", { tabLook(bulbOn).linkBound, tabLook(bulbOff).linkBound }, { true, true })
T.eq("and which look the links call for", H.state().matched, bulbOn)

T.section("Look Control changes")
setLookControl("Manual")
led(bulbOn, false)
led(bulbOff, false)
T.eq("under Manual a link's state leaves the look", shown(), "Bulb on")
T.eq("and the tab has no link lines", tabLook(bulbOn).linkState, nil)
setLookControl("By Link")
T.eq("By Link again shows what the links call for", shown(), "Bulb off")

T.section("Every form a STATE comes in")
for _, form in ipairs({ true, "True", "true", "TRUE", "yes", "on", "On", 1, 2, "1" }) do
  led(bulbOn, false)
  led(bulbOn, form)
  T.eq(string.format("%s (%s) is on", tostring(form), type(form)), tabLook(bulbOn).linkState, "on")
end
for _, form in ipairs({ false, "False", "false", 0, "0", "off", "no", "dim" }) do
  led(bulbOn, true)
  led(bulbOn, form)
  T.eq(string.format("%q (%s) is off", tostring(form), type(form)), tabLook(bulbOn).linkState, "off")
end

T.section("A message with no state")
led(bulbOn, true)
led(bulbOff, true)
T.eq("the light is on", shown(), "Bulb on")
H.mark()
ReceivedFromProxy(linkOf(bulbOn), "MATCH_LED_STATE", {})
ReceivedFromProxy(linkOf(bulbOff), "MATCH_LED_STATE", { STATE = "" })
T.eq("leaves each link's state as it was", { tabLook(bulbOn).linkState, tabLook(bulbOff).linkState }, { "on", "on" })
T.eq("so the look that shows while its link is off stays out", shown(), "Bulb on")
T.eq("and nothing fires", H.fired, {})
led(bulbOn, false)
led(bulbOff, false)
ReceivedFromProxy(5001, "MATCH_LED_STATE", { STATE = true })
T.eq(
  "a state on another binding is no link's",
  { tabLook(bulbOn).linkState, tabLook(bulbOff).linkState },
  { "off", "off" }
)

T.section("A press")
T.eq("the light is off", shown(), "Bulb off")
H.mark()
H.press()
T.eq(
  "taps the shown look's link",
  H.proxy[1] and { H.proxy[1].binding, H.proxy[1].command, H.proxy[2].binding, H.proxy[2].command },
  { linkOf(bulbOff), "DO_PUSH", linkOf(bulbOff), "DO_CLICK" }
)
T.eq("and leaves the look until the light reports", shown(), "Bulb off")
led(bulbOn, true)
led(bulbOff, true)
T.eq("then the light's reply moves it", shown(), "Bulb on")

T.section("Separate links")
bind(bulbOn, LIGHT_ON)
bind(bulbOff, LIGHT_OFF)
save(bulbOff, "Bulb off", { showWhile = "on" })
led(bulbOn, true)
led(bulbOff, false)
T.eq("the light on: its On link is on", shown(), "Bulb on")
led(bulbOn, false)
led(bulbOff, true)
T.eq("the light off: its Off link is on", shown(), "Bulb off")

T.section("No look matches")
local away = addLook("Away")
T.eq("a look with nothing bound", tabLook(away).linkBound, false)
led(bulbOn, false)
led(bulbOff, false)
T.eq("with no default look, the look stays", shown(), "Bulb off")
save(away, "Away", { isDefault = true })
T.eq("a save shows the default look", shown(), "Away")
led(bulbOn, true)
T.eq("until a look matches", shown(), "Bulb on")
led(bulbOn, false)
T.eq("and back", shown(), "Away")

T.section("An unbound link never matches")
led(bulbOn, true)
T.eq("bound, it matches", shown(), "Bulb on")
C4:Unbind(H.DEVICE_ID, linkOf(bulbOn))
OnBindingChanged(linkOf(bulbOn), "BUTTON_LINK", false, LIGHT, LIGHT_ON)
T.eq("unbound, it doesn't, though its state is on", shown(), "Away")
T.eq("the tab says it isn't bound", tabLook(bulbOn).linkBound, false)
T.eq("and gives no state", tabLook(bulbOn).linkState, nil)
led(bulbOff, false)
T.eq("nor does it on the next report", shown(), "Away")
H.mark()
C4:Bind(OTHER_LIGHT, LIGHT_ON, H.DEVICE_ID, linkOf(bulbOn), "BUTTON_LINK")
OnBindingChanged(linkOf(bulbOn), "BUTTON_LINK", true, OTHER_LIGHT, LIGHT_ON)
T.eq("bound to another light, the first light's state doesn't count", shown(), "Away")
T.eq("nothing fires", H.fired, {})
T.eq(
  "and the tab says the light bound now hasn't reported",
  { tabLook(bulbOn).linkBound, tabLook(bulbOn).linkState },
  { true, nil }
)
led(bulbOff, false)
T.eq("nor on the next report", shown(), "Away")
led(bulbOn, true)
T.eq("until the light bound now reports", shown(), "Bulb on")
led(bulbOn, false)
bind(bulbOn, LIGHT_ON)
OnBindingChanged(linkOf(bulbOn), "BUTTON_LINK", true, LIGHT, LIGHT_ON)
T.eq("bound back, the other light's state doesn't count either", shown(), "Away")
led(bulbOn, true)
T.eq("until the first light reports", shown(), "Bulb on")
C4:Unbind(H.DEVICE_ID, linkOf(bulbOn))
OnBindingChanged(linkOf(bulbOn), "BUTTON_LINK", false, LIGHT, LIGHT_ON)
T.eq("unbound again", shown(), "Away")
bind(bulbOn, LIGHT_ON)
OnBindingChanged(linkOf(bulbOn), "BUTTON_LINK", true, LIGHT, LIGHT_ON)
T.eq("bound again to the same light, its state was kept and matches", shown(), "Bulb on")
T.eq("as the tab says", tabLook(bulbOn).linkState, "on")
local fresh = addLook("Fresh")
C4:Bind(LIGHT, LIGHT_ON, H.DEVICE_ID, linkOf(fresh), "BUTTON_LINK")
H.tab("_ORDER_LOOKS", { ids = { fresh, bulbOn, bulbOff, away } })
T.eq("a link that hasn't reported never matches", shown(), "Bulb on")
T.eq("and the tab says so", { tabLook(fresh).linkBound, tabLook(fresh).linkState }, { true, nil })

T.section("The list's order")
led(fresh, true)
T.eq("the first look that matches shows", shown(), "Fresh")
H.tab("_ORDER_LOOKS", { ids = { bulbOn, fresh, bulbOff, away } })
T.eq("so moving a look changes which", shown(), "Bulb on")

T.section("A look's link removed")
H.tab("_DELETE_LOOK", { id = fresh })
T.eq("forgets its state", kept()[tostring(fresh)], nil)
T.eq("and only its", (kept()[tostring(bulbOn)] or {}).on, true)

T.section("A rename")
save(bulbOn, "Lamp on")
T.eq("re-binds its link to the same light", C4:GetBoundProviderDevice(H.DEVICE_ID, linkOf(bulbOn)), LIGHT)
T.eq("and keeps its state", tabLook(bulbOn).linkState, "on")
T.eq("so its look still shows", shown(), "Lamp on")
save(bulbOn, "Bulb on")

T.section("A save")
save(bulbOn, "Bulb on", { showWhile = "off" })
T.eq("re-picks with the look's new Show while", shown(), "Away")
save(bulbOn, "Bulb on")
T.eq("and back", shown(), "Bulb on")

T.section("A hold from programming")
showLook(bulbOff)
T.eq("Show Look shows another look", shown(), "Bulb off")
led(bulbOn, true)
T.eq("which stays while the links call for the same look", shown(), "Bulb off")
T.eq("and the tab marks the look they call for", H.state().matched, bulbOn)
led(bulbOn, false)
T.eq("until they call for another", shown(), "Away")

T.section("A deleted look")
led(bulbOn, true)
H.tab("_DELETE_LOOK", { id = bulbOn })
T.eq("the next look that matches, or the default, shows", shown(), "Away")
bulbOn = addLook("Bulb on")
bind(bulbOn, LIGHT_ON)
led(bulbOn, true)
T.eq("a new look's link matches once it reports", shown(), "Bulb on")

T.section("A Director restart")
setLookControl("Manual")
led(bulbOn, false)
led(bulbOff, true)
T.eq("under Manual the look stays", shown(), "Bulb on")
-- Set while the driver is stopped, so late init is first to pick.
Properties["Look Control"] = "By Link"
H.mark()
H.restart()
T.eq("late init picks from the states kept", shown(), "Bulb off")
T.eq("with the link states as they were", { tabLook(bulbOn).linkState, tabLook(bulbOff).linkState }, { "off", "on" })
led(bulbOn, true)
led(bulbOff, false)
T.eq("and the links still pick the look", shown(), "Bulb on")
H.restart()
T.eq("a restart before the light reports again keeps the look", shown(), "Bulb on")
T.eq("and its states", tabLook(bulbOn).linkState, "on")

T.section("A driver update")
setLookControl("Manual")
led(bulbOn, false)
led(bulbOff, true)
Properties["Look Control"] = "By Link"
H.update()
T.eq("picks from the states kept too", shown(), "Bulb off")

T.section("Back to By Link after a change made while the driver was stopped")
led(bulbOn, true)
led(bulbOff, false)
T.eq("the links show a look", shown(), "Bulb on")
Properties["Look Control"] = "On Select"
H.update()
EC.Show_Look({ Look = "Bulb off (" .. bulbOff .. ")" })
T.eq("programming shows another", shown(), "Bulb off")
setLookControl("By Link")
T.eq("and By Link again shows the look the links call for", shown(), "Bulb on")

T.section("A link bound asks its device for its state and colors")
local porch = addLook("Porch")
H.mark()
OnBindingChanged(linkOf(porch), "BUTTON_LINK", false, LIGHT, LIGHT_TOGGLE)
T.eq("an unbound link asks nothing", asked(), {})
C4:Bind(LIGHT, LIGHT_TOGGLE, H.DEVICE_ID, linkOf(porch), "BUTTON_LINK")
OnBindingChanged(linkOf(porch), "BUTTON_LINK", true, LIGHT, LIGHT_TOGGLE)
T.eq(
  "bound, it sends REQUEST_BUTTON_COLORS on the link, as a command",
  asked(),
  { { binding = linkOf(porch), params = {}, type = "COMMAND" } }
)
H.mark()
giveColors(porch, "0000FF", "#000000", { BUTTON_ID = "1", TEXT = "Porch", IMAGE_ON = "on.png" })
T.eq("the device's BUTTON_COLORS are kept", tabLook(porch).linkColors, { on = "0000ff", off = "000000" })
T.eq(
  "with the device that gave them, and nothing else it sent",
  (persist:get("LinkColors") or {})[tostring(porch)],
  { on = "0000ff", off = "000000", device = LIGHT }
)
T.eq("they change no look's picture", H.lastIcon(), nil)
T.eq("and fire nothing", H.fired, {})
giveColors(porch, "blue", "")
T.eq("colors it can't read are ignored", tabLook(porch).linkColors, { on = "0000ff", off = "000000" })
setLookControl("Manual")
T.eq("only By Link's tab shows them", tabLook(porch).linkColors, nil)
setLookControl("By Link")
C4:Unbind(H.DEVICE_ID, linkOf(porch))
C4:Bind(OTHER_LIGHT, LIGHT_TOGGLE, H.DEVICE_ID, linkOf(porch), "BUTTON_LINK")
H.mark()
OnBindingChanged(linkOf(porch), "BUTTON_LINK", true, OTHER_LIGHT, LIGHT_TOGGLE)
T.eq("bound to another light, it asks that light", #asked(), 1)
T.eq("and the first light's colors don't count", tabLook(porch).linkColors, nil)
giveColors(porch, "ff0000", "111111")
T.eq("until the light bound now gives its own", tabLook(porch).linkColors, { on = "ff0000", off = "111111" })

T.section("The driver's start asks every bound link")
local sentWith = {}
local sendToProxy = C4.SendToProxy
C4.SendToProxy = function(self, binding, command, ...)
  if command == "REQUEST_BUTTON_COLORS" then
    sentWith[binding] = ShimDynamicBindings()[binding] ~= nil and C4:GetBoundProviderDevice(H.DEVICE_ID, binding) ~= 0
  end
  return sendToProxy(self, binding, command, ...)
end
H.mark()
H.restart()
C4.SendToProxy = sendToProxy
local startAsked = {}
for _, request in ipairs(asked()) do
  table.insert(startAsked, request.binding)
end
table.sort(startAsked)
local boundLinks = { linkOf(bulbOff), linkOf(bulbOn), linkOf(porch) }
table.sort(boundLinks)
T.eq("each bound link's device once, and not the look with nothing bound", startAsked, boundLinks)
T.eq(
  "after the links are back and bound",
  { sentWith[linkOf(bulbOff)], sentWith[linkOf(bulbOn)], sentWith[linkOf(porch)] },
  { true, true, true }
)
T.eq("the colors are kept through a restart", tabLook(porch).linkColors, { on = "ff0000", off = "111111" })

T.section("A rename binds the link again and asks again")
H.mark()
save(porch, "Front porch")
T.eq("a renamed look's link asks its device", asked(), { { binding = linkOf(porch), params = {}, type = "COMMAND" } })
H.mark()
save(porch, "Front porch")
T.eq("a save that keeps the name asks nothing", asked(), {})
save(away, "Away from home", { isDefault = true })
T.eq("nor does a rename with nothing bound", asked(), {})
save(away, "Away", { isDefault = true })
H.tab("_DELETE_LOOK", { id = porch })
T.eq("a deleted look's link's colors are forgotten", persist:get("LinkColors"), nil)

T.section("A timed look")
local bell = addLook("Doorbell", { timerAfter = 30 })
led(bulbOn, true)
led(bulbOff, false)
T.eq("the links pick a look", shown(), "Bulb on")
showLook(bulbOff)
showLook(bell)
T.eq("programming shows a timed look", shown(), "Doorbell")
T.truthy("whose timer runs", persist:get("LookTimer").due)
H.mark()
ShimFireTimers()
T.eq("its time up, the links' look shows, not the look before", shown(), "Bulb on")
T.eq("firing its events", H.fired, { "Look Changed", "Bulb on Shown" })
showLook(bell)
led(bulbOn, false)
led(bulbOff, true)
T.eq("the links calling for another look show it", shown(), "Bulb off")
T.eq("and stop the timer", persist:get("LookTimer").due, nil)
save(bell, "Doorbell", { timerAfter = 30, isDefault = true })
led(bulbOff, false)
T.eq("a timed default look the links show", shown(), "Doorbell")
T.eq("runs no timer", persist:get("LookTimer").due, nil)
save(bell, "Doorbell", { timerAfter = 30 })
H.tab("_DELETE_LOOK", { id = bell })

T.section("Copy To, Export and Import")
T.eq("the tab has each look's Show while to copy", tabLook(bulbOff).showWhile, "on")
save(bulbOff, "Bulb off", { showWhile = "off" })
local copied = tabLook(bulbOff)
local copy = tonumber(save(nil, "Bulb off 2", { showWhile = copied.showWhile }).look)
T.eq("and a copy saved with it keeps it", tabLook(copy).showWhile, "off")
H.tab("_DELETE_LOOK", { id = copy })
save(bulbOff, "Bulb off", { showWhile = "on" })
local file = assert(io.open(H.DRIVER:gsub("driver%.lua$", "www/html/index.html"), "r"))
local page = file:read("*a")
file:close()
--- @param text string
--- @return boolean present The page's source has that text.
local function has(text)
  return page:find(text, 1, true) ~= nil
end
T.truthy(
  "Copy To and Export read it",
  has("grayscale: !!l.grayscale, showWhile: whileOf(l), showWhen: l.showWhen || '', custom:")
)
T.truthy("Copy To and Import save it", has("grayscale: !!look.grayscale, showWhile: whileOf(look), showWhen:"))
T.truthy("Import takes it from the file", has("showWhile: whileOf(l), showWhen: typeof l.showWhen === 'string'"))
T.truthy(
  "after the driver's own check",
  has(
    "if (l.showWhile != null && l.showWhile !== 'on' && l.showWhile !== 'off') return 'its Show while isn’t on or off';"
  )
)
T.truthy(
  "the editor saves it",
  has("grayscale: !!l.grayscale, showWhile: whileOf(l), showWhen: l.showWhen || '', isDefault:")
)

T.section("The Button tab")
T.truthy("By Link has its note", has([['By Link': 'The first look whose link matches its "Show while" shows.']]))
T.truthy("the Show while row starts hidden", has('<div class="frow" id="fld-while" hidden>'))
T.truthy("and only By Link shows it", has("$('fld-while').hidden = !byLink();"))
T.truthy(
  "which offers on and off",
  has('<option value="on">its link is on</option><option value="off">its link is off</option>')
)
T.truthy("the default look's row shows under By Link too", has("$('fld-default').hidden = !following();"))
T.truthy("each look's row gives its link's state under By Link", has("refreshLines(l) + whenLines(l) + linkLines(l)"))
T.truthy("or that it isn't bound", has("!l.linkBound ? 'not bound'"))
T.truthy("with its device's on and off colors beside it", has("esc(text) + linkSwatches(l) + '</div>'"))
T.truthy("each only as six hex digits", has("/^[0-9a-f]{6}$/i.test(c) ? '#' + c.toLowerCase() : null"))
T.truthy("By Link is how the page knows", has("function byLink() { return gState.lookControl === 'By Link'; }"))
T.truthy("the timer goes back to the links", has("byLink() ? 'back to the links' : timerTarget(l)"))
T.truthy("the demo offers By Link", has("['On Select', 'Manual', 'By Value', 'By Link']"))

T.section("Without a license")
led(bulbOn, true)
led(bulbOff, false)
T.eq("the links pick a look", shown(), "Bulb on")
DC_X = 0
gate:_set(false)
H.mark()
led(bulbOn, false)
led(bulbOff, true)
T.eq("a link's state changes nothing", shown(), "Bulb on")
T.eq("fires nothing", H.fired, {})
T.eq("but is kept", tabLook(bulbOff).linkState, "on")
DC_X = nil
gate:_set(true)
T.eq("a license back shows what the links call for", shown(), "Bulb off")

T.section("The docs")
local docsFile = assert(io.open(H.DRIVER:gsub("driver%.lua$", "www/documentation/index.md"), "r"))
local docs = docsFile:read("*a"):gsub("%s+", " ")
docsFile:close()
T.truthy(
  "say the button asks for each device's state when a link is bound and at start",
  docs:find(
    "asks each device for its state and its LED colors when a look's link is bound and when the driver",
    1,
    true
  )
)
T.truthy(
  "and keep the rule for a device that hasn't reported",
  docs:find("hasn't reported yet, never matches", 1, true)
)

T.section("Reset Driver")
giveColors(bulbOn, "00ff00", "000000")
T.truthy("a link's colors kept", persist:get("LinkColors"))
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("forgets every link's state", persist:get("LinkStates"), nil)
T.eq("and its colors", persist:get("LinkColors"), nil)
T.eq("and Look Control goes back to Manual", Properties["Look Control"], "Manual")

T.finish()
