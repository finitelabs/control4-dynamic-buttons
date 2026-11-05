-- Dynamic Button.
--
-- One Navigator button (the UI Button proxy on binding 5001) whose picture is one of its looks
-- (src/dynamic_button/looks.lua). The Button tab draws each look's picture from an icon and sends
-- it here; the driver keeps it (src/dynamic_button/images.lua) and serves the shown one under a new
-- address on every change (src/dynamic_button/button.lua).

--#ifndef DRIVERCENTRAL
DRIVER_GITHUB_REPO = "finitelabs/control4-dynamic-buttons"
--#endif

require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")

JSON = require("JSON")

local log = require("lib.logging")
local persist = require("lib.persist")
local values = require("lib.values")
local conditionals = require("lib.conditionals")
local events = require("lib.events")
local http = require("lib.http")
local updateSettings = require("lib.update-settings")
--#ifdef DRIVERCENTRAL
local drivercentral = require("lib.drivercentral")
local supportCode = require("lib.support-code")
local diagnostics = require("lib.diagnostics")
--#endif
--#ifndef DRIVERCENTRAL
local githubUpdater = require("lib.github-updater")
--#endif

local Looks = require("dynamic_button.looks")
local Images = require("dynamic_button.images")
local Button = require("dynamic_button.button")
local Iconify = require("dynamic_button.iconify")

--- The UI Button proxy's binding.
local PROXY_BINDING = 5001

--- Namespace of the programming conditionals whose lists come from the looks.
local PROGRAMMING = "Programming"

--- The programming variable naming the shown look.
local LOOK_VARIABLE = "Look"

--- The static event fired when the shown look changes.
local LOOK_CHANGED_EVENT = "Look Changed"

--- Namespace of the dynamic events, one per look, keyed by look id.
local LOOK_EVENTS = "Looks"

--- What a press of the button does, by Look Control mode. A value not listed acts as Manual.
--- @type table<string, fun()>
local PRESS_ACTIONS = {}

gInitialized = false

local looks = Looks:new(persist)
local images = Images:new()

--- @type Button
local button

--- The Look Is conditional's list as last registered.
--- @type string|nil
local gLookIsItems = nil

-- Chunks are large and carry nothing a log needs.
UIR.suppressDebug["_PUT_IMAGE"] = true

--- @return string name The driver's file name without `.c4z`, which names its web folder.
local function driverName()
  return (tostring(C4:GetDriverFileName() or "dynamic_button.c4z"):gsub("%.c4z$", ""))
end

--- Tell the proxy what to show: a picture's address, or "" for the driver's own icon.
--- @param icon string
--- @param description string The text list Navigators show in place of the picture.
local function sendIcon(icon, description)
  -- A notification: the proxy ignores ICON_CHANGED sent as a command. Empty values allowed: an
  -- empty icon is the proxy's own icon.
  SendToProxy(PROXY_BINDING, "ICON_CHANGED", { icon = icon, icon_description = description }, "NOTIFY", true)
end

--- Programming's view of the shown look: its variable and property, and the event on a change.
--- @param before integer|nil The look shown before the change.
local function announceShown(before)
  local shown = button:shown()
  local name = shown and shown.name or ""
  values:update(LOOK_VARIABLE, name, "STRING")
  UpdateProperty("Shown Look", name)
  local now = shown and shown.id or nil
  if gInitialized and now ~= before then
    C4:FireEvent(LOOK_CHANGED_EVENT)
    if now then
      events:fire(LOOK_EVENTS, tostring(now))
    end
  end
end

--- Give each look its "<name> Shown" event, renamed with the look, and delete the events of looks
--- that are gone. An event keeps its id for the life of its look.
local function syncLookEvents()
  local kept = {}
  for _, look in ipairs(looks:list()) do
    local key = tostring(look.id)
    kept[key] = true
    events:getOrAddEvent(LOOK_EVENTS, key, look.name .. " Shown", "When NAME shows " .. look.name)
  end
  local gone = {}
  for key in pairs(Select(events:getEvents(), LOOK_EVENTS) or {}) do
    if not kept[key] then
      table.insert(gone, key)
    end
  end
  for _, key in ipairs(gone) do
    events:deleteEvent(LOOK_EVENTS, key)
  end
end

--- @return string mode The Look Control property, Manual when it has no known value.
local function lookControl()
  local mode = Properties["Look Control"]
  return PRESS_ACTIONS[mode] and mode or "Manual"
end

--- @return string items The looks as the Look Is conditional lists them.
local function lookChoices()
  local labels = {}
  for _, look in ipairs(looks:list()) do
    table.insert(labels, Looks.label(look))
  end
  return table.concat(labels, ",")
end

--- Test for the shown look, by the id in its label, so a test holds after a rename.
--- @param _strConditionName string
--- @param tParams table
--- @return boolean
local function testLookIs(_strConditionName, tParams)
  local picked = looks:fromChoice(Select(tParams, "VALUE"))
  local shown = button:shown()
  local matched = picked ~= nil and shown ~= nil and picked.id == shown.id
  if Select(tParams, "LOGIC") == "NOT_EQUAL" then
    return not matched
  end
  return matched
end

--- Register the Look Is conditional with the looks, when its list changed.
--- @param items string Comma-separated choices.
--- @param saved boolean|nil Re-register the conditional saved with the project, as every load must.
local function registerLookIs(items, saved)
  -- A button with no looks gets no conditional, until it has some.
  if not saved and (items == gLookIsItems or items == "") then
    return
  end
  gLookIsItems = items
  conditionals:upsertConditional(PROGRAMMING, "look_is", {
    type = "LIST",
    condition_statement = "Look Is",
    description = "the look NAME shows is LOGIC STRING",
    list_items = items,
  }, testLookIs)
end

--- The driver.xml properties the Button tab shows, read once.
--- @type table[]|nil
local gTabProperties = nil

--- @return table[] properties Each property the Button tab shows, in driver.xml order: its name,
--- the label above it as its group, whether it is read-only, and a list's choices. Passwords stay in
--- Composer.
local function tabProperties()
  if gTabProperties then
    return gTabProperties
  end
  gTabProperties = {}
  local group = ""
  for xml in XMLgCapture(C4:GetDriverConfigInfo("config") or "", "property") do
    local kind = XMLCapture(xml, "type")
    if kind == "LABEL" then
      group = XMLCapture(xml, "default") or ""
    elseif (kind == "LIST" or kind == "STRING") and XMLCapture(xml, "password") ~= "true" then
      local property =
        { name = XMLCapture(xml, "name"), group = group, readonly = XMLCapture(xml, "readonly") == "true" }
      if kind == "LIST" then
        property.choices = {}
        for item in XMLgCapture(xml, "item") do
          table.insert(property.choices, item)
        end
      end
      table.insert(gTabProperties, property)
    end
  end
  return gTabProperties
end

--- @return table state What the Button tab shows.
local function tabState()
  local list = {}
  for _, look in ipairs(looks:list()) do
    table.insert(list, {
      id = look.id,
      name = look.name,
      icon = look.icon,
      iconColor = look.iconColor,
      tileShape = look.tileShape,
      tileColor = look.tileColor,
      hasImage = look.image ~= nil,
      stale = look.image ~= nil and look.image.stale == true,
      inCycle = Looks.inCycle(look),
      glow = Looks.glow(look),
      grayscale = Looks.grayscale(look),
      custom = look.custom,
    })
  end
  local properties = {}
  for _, property in ipairs(tabProperties()) do
    table.insert(properties, {
      name = property.name,
      group = property.group,
      readonly = property.readonly,
      choices = property.choices,
      value = Properties[property.name] or "",
    })
  end
  local shown = button:shown()
  return {
    properties = properties,
    looks = list,
    shown = shown and shown.id or nil,
    lookControl = lookControl(),
    max = Looks.MAX,
    maxChunk = Images.MAX_CHUNK,
    maxBytes = Images.MAX_BYTES,
    packs = Iconify.PACKS,
  }
end

--- Send the Button tab one message, over its socket and as the REST reply.
--- @param command string
--- @param data table<string, string>
--- @return string json
local function uiRespond(command, data)
  local reply = TableDeepCopy(data)
  C4:SendDataToUI(command, data)
  reply._command = command
  return JSON:encode(reply)
end

--- @return string json
local function pushState()
  return uiRespond("STATE", { state = JSON:encode(tabState()) })
end

--- Show a property change in the Button tab, once the button is up.
local function syncTab()
  if button then
    pushState()
  end
end

--- Answer the Button tab with the state included, so a reply that comes back without the socket
--- still updates the page.
--- @param command string
--- @param data table<string, string>
--- @return string json
local function reply(command, data)
  data.state = JSON:encode(tabState())
  return uiRespond(command, data)
end

--- @param message string
--- @return string json
local function pushError(message)
  log:warn("Button tab: %s", message)
  return reply("ERROR", { message = message })
end

--- @param tParams table
--- @return table params The Button tab's parameters, base64 JSON in DATA.
local function tabParams(tParams)
  local ok, params = pcall(function()
    return JSON:decode(C4:Base64Decode(Select(tParams, "DATA") or "e30="))
  end)
  if ok and type(params) == "table" then
    return params
  end
  return {}
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

--#ifndef DRIVERCENTRAL
--- Get all device IDs for instances of this driver, sorted ascending.
--- @return integer[]
local function getDriverIds()
  local drivers = C4:GetDevicesByC4iName(C4:GetDriverFileName()) or {}
  local ids = {}
  for id, _ in pairs(drivers) do
    table.insert(ids, tointeger(id))
  end
  table.sort(ids)
  return ids
end

--- Update the driver from the GitHub repository.
--- @param forceUpdate? boolean Force the update even if already up to date.
function UpdateDrivers(forceUpdate)
  log:trace("UpdateDrivers(%s)", forceUpdate)
  githubUpdater
    :updateAll(
      DRIVER_GITHUB_REPO,
      require("lib.driver-filenames"),
      Properties["Update Channel"] == "Prerelease",
      forceUpdate
    )
    :next(function(updatedDrivers)
      if updatedDrivers and #updatedDrivers > 0 then
        log:info("Updated driver(s): %s", table.concat(updatedDrivers, ","))
      end
    end, function(err)
      log:warn("Driver update failed: %s", err)
    end)
end
--#endif

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function OnDriverInit()
  --#ifdef DRIVERCENTRAL
  drivercentral:startClient()
  --#else
  C4:AllowExecute(true)
  --#endif
  gInitialized = false
  log:setLogName(C4:GetDeviceData(C4:GetDeviceID(), "name"))
  log:setLogLevel(Properties["Log Level"])
  log:setLogMode(Properties["Log Mode"])
  log:trace("OnDriverInit()")

  values:restoreValues()
end

--#ifdef DRIVERCENTRAL
--- The license gate stopped (false) or started (true) the driver. Stopped, the button shows the driver's own icon and
--- keeps its looks; started, it shows its look again as a load would.
--- @param licensed boolean
local function onLicense(licensed)
  if not licensed then
    log:warn("No active license: the button shows the driver's own icon until there is one")
    sendIcon("", "")
    UpdateProperty("Driver Status", drivercentral.UNLICENSED_STATUS)
    pushState()
    return
  end
  log:info("Licensed again: the button shows its look")
  local shown = button:shown()
  if shown then
    -- A new address, since the app may still hold the driver's icon for the old one.
    local ok, err = button:show(shown.id, true)
    if not ok then
      log:warn("Could not show look %s: %s", shown.name, err)
    end
  end
  registerLookIs(lookChoices(), true)
  UpdateProperty("Driver Status", "Ready")
  pushState()
end
--#endif

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end

  for p, _ in pairs(Properties) do
    local ok, err = pcall(OnPropertyChanged, p)
    if not ok then
      log:error("OnPropertyChanged('%s') failed: %s", p, tostring(err))
      --#ifdef DRIVERCENTRAL
      diagnostics:captureError(tostring(err), nil, "DynamicButton.OnPropertyChanged")
      --#endif
    end
  end

  --#ifndef DRIVERCENTRAL
  -- Only the lowest Dynamic Button instance checks, at most every 30 min, and only when
  -- Automatic Updates is On. The DriverCentral build lets cloud-client-byte own updates.
  SetTimer("UpdateCheck", 30 * ONE_MINUTE, function()
    local isLeader = Select(getDriverIds(), 1) == C4:GetDeviceID()
    if isLeader and toboolean(Properties["Automatic Updates"]) then
      log:info("Checking for driver update (leader instance)")
      UpdateDrivers()
    end
  end, true)
  --#endif

  button = Button:new({
    looks = looks,
    images = images,
    store = persist,
    deviceId = tointeger(C4:GetDeviceID()),
    driverName = driverName(),
    sendIcon = sendIcon,
  })
  button:restore()
  events:restoreEvents()
  syncLookEvents()
  announceShown(nil)
  -- Test functions live in memory: Look Is answers from its saved list until the looks change.
  local saved = Select(conditionals:getConditionals(), PROGRAMMING, "look_is", "list_items")
  if saved then
    registerLookIs(saved, true)
  end
  registerLookIs(lookChoices())

  gInitialized = true
  UpdateProperty("Driver Status", "Ready")
  --#ifdef DRIVERCENTRAL
  drivercentral:startGate(onLicense)
  --#endif
end

--#ifdef DRIVERCENTRAL
OnDriverLateInit = diagnostics:wrapLateInit(OnDriverLateInit)
--#endif

function OnDriverRemovedFromProject()
  log:trace("OnDriverRemovedFromProject()")
  if button then
    button:removed()
  end
end

-- An update or a restart keeps the served picture: the next start serves it again anyway.
function OnDriverDestroyed()
  log:trace("OnDriverDestroyed()")
  KillAllTimers()
end

--#ifdef DRIVERCENTRAL
-- Director calls these itself, so no dispatcher reports their errors.
OnDriverRemovedFromProject = diagnostics:wrap(OnDriverRemovedFromProject, "OnDriverRemovedFromProject")
OnDriverDestroyed = diagnostics:wrap(OnDriverDestroyed, "OnDriverDestroyed")
--#endif

--------------------------------------------------------------------------------
-- Property handlers (OPC dispatch)
--------------------------------------------------------------------------------

function OPC.Driver_Status(propertyValue)
  log:trace("OPC.Driver_Status(%s)", propertyValue)
  if not gInitialized then
    UpdateProperty("Driver Status", "Initializing", false)
    return
  end
end

function OPC.Driver_Version(propertyValue)
  log:trace("OPC.Driver_Version(%s)", propertyValue)
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
end

function OPC.Log_Mode(propertyValue)
  log:trace("OPC.Log_Mode(%s)", propertyValue)
  log:setLogMode(propertyValue)
  CancelTimer("LogMode")
  -- Log Level's handler, run below on either path, updates the Button tab.
  if not log:isEnabled() then
    UpdateProperty("Log Level", "3 - Info", true)
    return
  end
  log:warn("Log mode '%s' will expire in 3 hours", propertyValue)
  SetTimer("LogMode", 3 * ONE_HOUR, function()
    log:warn("Setting log mode to 'Off' (timer expired)")
    UpdateProperty("Log Mode", "Off", true)
  end)
  OnPropertyChanged("Log Level")
end

function OPC.Log_Level(propertyValue)
  log:trace("OPC.Log_Level(%s)", propertyValue)
  log:setLogLevel(propertyValue)
  if log:getLogLevel() >= 6 and log:isPrintEnabled() then
    DEBUGPRINT = true
    DEBUG_TIMER = true
    DEBUG_RFN = true
    DEBUG_URL = true
    DEBUG_WEBSOCKET = true
  else
    DEBUGPRINT = false
    DEBUG_TIMER = false
    DEBUG_RFN = false
    DEBUG_URL = false
    DEBUG_WEBSOCKET = false
  end
  syncTab()
end

function OPC.Look_Control(propertyValue)
  log:trace("OPC.Look_Control(%s)", propertyValue)
  syncTab()
end

function OPC.Automatic_Updates(propertyValue)
  log:trace("OPC.Automatic_Updates(%s)", propertyValue)
  if gInitialized then
    updateSettings:share("Automatic Updates", propertyValue)
  end
  syncTab()
end

--#ifndef DRIVERCENTRAL
function OPC.Update_Channel(propertyValue)
  log:trace("OPC.Update_Channel(%s)", propertyValue)
  if gInitialized then
    updateSettings:share("Update Channel", propertyValue)
  end
  syncTab()
end
--#endif

--- An update setting changed on another item.
function EC.SET_UPDATE_SETTING(params)
  log:trace("EC.SET_UPDATE_SETTING(%s)", params)
  updateSettings:take(params)
end

--#ifdef DRIVERCENTRAL
--- Not logged: the value is the code.
function OPC.Support_Code(propertyValue)
  supportCode:enter(propertyValue)
end

--- Turns Cloud Monitoring on or off.
--- @param propertyValue string
function OPC.Cloud_Monitoring(propertyValue)
  log:trace("OPC.Cloud_Monitoring(%s)", propertyValue)
  diagnostics:setEnabled(propertyValue == "Enabled")
  syncTab()
end

--- Prints a diagnostics report, and sends it while Cloud Monitoring is on.
function EC.DiagnosticsSnapshot()
  log:trace("EC.DiagnosticsSnapshot()")
  diagnostics:dumpSnapshot()
end
--#endif

--------------------------------------------------------------------------------
-- Button tab (UIR dispatch)
--------------------------------------------------------------------------------

function UIR._GET_STATE()
  log:trace("UIR._GET_STATE()")
  return pushState()
end

--- Set one of the driver's properties, as Composer's Properties tab would.
--- @param tParams table
function UIR._SET_DRIVER(tParams)
  local params = tabParams(tParams)
  local name, value = params.property, params.value
  log:trace("UIR._SET_DRIVER(%s)", name)
  for _, property in ipairs(tabProperties()) do
    if property.name == name and not property.readonly and type(value) == "string" then
      -- The wrapper turns away a value its list lacks, then runs the property's handler.
      UpdateProperty(name, value, true)
      return pushState()
    end
  end
  return pushError("The tab cannot set " .. tostring(name) .. ".")
end

--- Create a look, or change one when an id is given. Its picture follows in _PUT_IMAGE.
--- @param tParams table
function UIR._SAVE_LOOK(tParams)
  log:trace("UIR._SAVE_LOOK()")
  local params = tabParams(tParams)
  local id = tonumber(params.id)
  local before = button:shown()
  local look, err
  if id then
    look, err = looks:update(id, params)
  else
    look, err = looks:add(params)
  end
  if not look then
    return pushError(err or "the look was not saved")
  end
  if before and before.id == look.id and before.name ~= look.name then
    button:retell()
    announceShown(look.id)
  end
  registerLookIs(lookChoices())
  syncLookEvents()
  return reply("SAVED", { look = tostring(look.id) })
end

--- One chunk of a look's picture.
--- @param tParams table
function UIR._PUT_IMAGE(tParams)
  local params = tabParams(tParams)
  local look = looks:get(params.look)
  if not look then
    return pushError("the picture's look is gone")
  end
  local png, err = images:accept(look.id, params.upload, params.index, params.count, params.data)
  if err then
    return pushError(string.format("the picture for %s did not arrive: %s", look.name, err))
  end
  if not png then
    -- Only the REST reply, and without the state: the broker's time grows with each message's size.
    return JSON:encode({ _command = "CHUNK", look = tostring(look.id), index = tostring(params.index) })
  end
  local before = button:shown()
  local ok = button:imageArrived(look.id, png)
  if not ok then
    return pushError(string.format("the picture for %s could not be kept", look.name))
  end
  log:info("Stored the picture for look %s (%d bytes)", look.name, #png)
  announceShown(before and before.id or nil)
  return reply("IMAGE_STORED", { look = tostring(look.id) })
end

--- @param tParams table
function UIR._DELETE_LOOK(tParams)
  log:trace("UIR._DELETE_LOOK()")
  local before = button:shown()
  local removed = button:deleteLook(tabParams(tParams).id)
  if not removed then
    return pushError("no such look")
  end
  log:info("Deleted look %s", removed.name)
  announceShown(before and before.id or nil)
  registerLookIs(lookChoices())
  syncLookEvents()
  return pushState()
end

--- @param tParams table
function UIR._ORDER_LOOKS(tParams)
  log:trace("UIR._ORDER_LOOKS()")
  local ok, err = looks:reorder(tabParams(tParams).ids)
  if not ok then
    return pushError(err or "the order was not saved")
  end
  registerLookIs(lookChoices())
  return pushState()
end

--- @param tParams table
function UIR._SHOW_LOOK(tParams)
  log:trace("UIR._SHOW_LOOK()")
  local before = button:shown()
  local ok, err = button:show(tabParams(tParams).id)
  if not ok then
    return pushError(err or "the look was not shown")
  end
  announceShown(before and before.id or nil)
  return pushState()
end

--- Fetch from Iconify for a Button tab that can't reach it; only the offered packs.
--- @param tParams table
function UIR._ICONIFY(tParams)
  log:trace("UIR._ICONIFY()")
  local params = tabParams(tParams)
  local request = tostring(params.request or "")
  local url, err = Iconify.url(params.kind, params.value, params.prefixes)
  if not url then
    return uiRespond("ICONIFY", { request = request, error = err })
  end
  http:get(url):next(function(response)
    -- The HTTP library decodes a JSON reply, as Iconify's are: encode it again for the tab.
    local body = response.body
    body = type(body) == "table" and JSON:encode(body) or tostring(body or "")
    C4:SendDataToUI("ICONIFY", { request = request, body = body })
  end, function(failure)
    C4:SendDataToUI("ICONIFY", { request = request, error = tostring(Select(failure, "error") or failure) })
  end)
end

--------------------------------------------------------------------------------
-- Programming (EC, GCPL and TC dispatch)
--------------------------------------------------------------------------------

--- @param params table
function EC.Show_Look(params)
  log:trace("EC.Show_Look(%s)", params)
  local look = looks:fromChoice(Select(params, "Look"))
  if not look then
    log:warn("Show Look: no look %s", tostring(Select(params, "Look")))
    return
  end
  local before = button:shown()
  local ok, err = button:show(look.id)
  if not ok then
    log:warn("Show Look %s: %s", look.name, err)
    return
  end
  announceShown(before and before.id or nil)
  pushState()
end

--- Show the next (1) or previous (-1) look in the cycle. A look whose picture can't be shown is
--- passed over, and the tab is told when none could be.
--- @param step integer
local function stepLook(step)
  local before = button:shown()
  local tried = {}
  for _ = 1, #looks:list() do
    local look = button:cycled(step, tried)
    if not look then
      break
    end
    local ok, err = button:show(look.id)
    if ok then
      announceShown(before and before.id or nil)
      pushState()
      return
    end
    log:warn("Could not show look %s: %s", look.name, err)
    tried[look.id] = true
  end
  if next(tried) then
    pushState()
  end
end

function EC.Next_Look()
  log:trace("EC.Next_Look()")
  stepLook(1)
end

function EC.Previous_Look()
  log:trace("EC.Previous_Look()")
  stepLook(-1)
end

PRESS_ACTIONS["On Select"] = function()
  stepLook(1)
end
PRESS_ACTIONS["Manual"] = function() end

--- A press of the button in Navigator. The proxy fires its own Selected event in every mode.
--- @param idBinding integer
function RFP.SELECT(idBinding)
  log:trace("RFP.SELECT(%s)", idBinding)
  if idBinding == PROXY_BINDING then
    PRESS_ACTIONS[lookControl()]()
  end
end

--- @param paramName string
--- @return string[] choices
function GCPL.Show_Look(paramName)
  log:trace("GCPL.Show_Look(%s)", paramName)
  if paramName ~= "Look" then
    return {}
  end
  local choices = {}
  for _, look in ipairs(looks:list()) do
    table.insert(choices, Looks.label(look))
  end
  return choices
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

--#ifndef DRIVERCENTRAL
function EC.Update_Drivers()
  log:trace("EC.Update_Drivers()")
  log:print("Updating drivers")
  UpdateDrivers(true)
end
--#endif

--- Settable properties a reset returns to their defaults.
--- @type table<string, string>
local RESET_PROPERTY_VALUES = {
  ["Log Level"] = "3 - Info",
  ["Log Mode"] = "Off",
  ["Automatic Updates"] = "On",
  ["Look Control"] = "Manual",
  --#ifndef DRIVERCENTRAL
  ["Update Channel"] = "Production",
  --#endif
  --#ifdef DRIVERCENTRAL
  ["Cloud Monitoring"] = "Enabled",
  --#endif
}

--- Reset the driver to a fresh install: no looks, the driver's own icon.
--- @param params table
function EC.Reset_Driver(params)
  log:trace("EC.Reset_Driver(%s)", params)
  if Select(params, "Are You Sure?") ~= "Yes" then
    return
  end
  log:print("Resetting driver to initial state")
  button:reset()
  values:reset()
  conditionals:reset()
  events:reset()
  gLookIsItems = nil
  -- As a fresh install: the variable comes back empty, and no Look Changed fires.
  announceShown(nil)
  for name, value in pairs(GetPropertyResetValues({})) do
    UpdateProperty(name, value, true)
  end
  for name, value in pairs(RESET_PROPERTY_VALUES) do
    UpdateProperty(name, value, true)
  end
  UpdateProperty("Driver Status", "Ready")
  pushState()
end

--#ifdef DRIVERCENTRAL
--------------------------------------------------------------------------------
-- License gate
--------------------------------------------------------------------------------

--- What the tab hears for a look change while the gate holds the driver stopped.
local UNLICENSED_REFUSAL = "No active license: looks can't change until the driver is licensed"

--- @param fn function
--- @param refused? function What answers instead while stopped; nothing when nil.
--- @return function gated
local function whileLicensed(fn, refused)
  return function(...)
    if drivercentral:licensed() then
      return fn(...)
    end
    if refused then
      return refused(...)
    end
  end
end

-- _GET_STATE and _SET_DRIVER stay open while stopped: they only do what Composer's own Properties tab can.
RFP.SELECT = whileLicensed(RFP.SELECT)
EC.Show_Look = whileLicensed(EC.Show_Look)
EC.Next_Look = whileLicensed(EC.Next_Look)
EC.Previous_Look = whileLicensed(EC.Previous_Look)
EC.Reset_Driver = whileLicensed(EC.Reset_Driver)
GCPL.Show_Look = whileLicensed(GCPL.Show_Look, function()
  return {}
end)
for _, name in ipairs({ "_SAVE_LOOK", "_PUT_IMAGE", "_DELETE_LOOK", "_ORDER_LOOKS", "_SHOW_LOOK" }) do
  UIR[name] = whileLicensed(UIR[name], function()
    return pushError(UNLICENSED_REFUSAL)
  end)
end
UIR._ICONIFY = whileLicensed(UIR._ICONIFY, function(tParams)
  return uiRespond("ICONIFY", { request = tostring(tabParams(tParams).request or ""), error = UNLICENSED_REFUSAL })
end)
--#endif
