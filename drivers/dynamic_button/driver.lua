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
local driverFilenames = require("lib.driver-filenames")
--#endif

local Looks = require("dynamic_button.looks")
local Images = require("dynamic_button.images")
local Pictures = require("dynamic_button.pictures")
local WebPictures = require("dynamic_button.web_pictures")
local Button = require("dynamic_button.button")
local Iconify = require("dynamic_button.iconify")
local Follow = require("dynamic_button.follow")
local LiveBadges = require("dynamic_button.live_badges")
local Expressions = require("lib.expressions")

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

--- @type Looks
local looks
local pictures = Pictures:new({
  store = persist,
  used = function()
    local used = {}
    for _, look in ipairs(looks:list()) do
      if type(look.icon) == "table" then
        used[look.icon.id] = true
      end
    end
    return used
  end,
})
--- This button's own ids: its device's and its proxy's.
--- @return integer[] ids
local function ownIds()
  local own = tointeger(C4:GetDeviceID())
  local ids = { own }
  local device = (C4:GetDevices({ DeviceIds = tostring(own) }) or {})[own]
  for proxyId in pairs(type(device) == "table" and device.proxies or {}) do
    table.insert(ids, tointeger(proxyId))
  end
  return ids
end

looks = Looks:new(persist, function(id)
  return pictures:get(id) ~= nil
end, function(id)
  return pictures:refreshes(id)
end, ownIds)
local images = Images:new()

--- @type Button
local button

--- @type LiveBadges
local badges
--- @type WebPictures
local refresher
--- @type Follow
local follow

--- Whether the values may change the look.
--- @return boolean
local followAllowed = function()
  return true
end

--- The Look Is conditional's list as last registered.
--- @type string|nil
local gLookIsItems = nil

-- Chunks are large and carry nothing a log needs.
UIR.suppressDebug["_PUT_IMAGE"] = true
UIR.suppressDebug["_PUT_PICTURE"] = true
-- A web address can carry a login or a token, so nothing logs one.
UIR.suppressDebug["_FETCH_PICTURE"] = true
UIR.suppressDebug["_ADD_WEB_PICTURE"] = true
EC.suppressDebug["Set Web Address"] = true
EC.suppressDebug["Set_Web_Address"] = true

--- @return string name The driver's file name without `.c4z`, which names its web folder.
local function driverName()
  return (tostring(C4:GetDriverFileName() or "dynamic_button.c4z"):gsub("%.c4z$", ""))
end

--- Tell the proxy what to show: a picture's address, or "" for the driver's own icon.
--- @param icon string
--- @param description string The text list Navigators show in place of the picture.
local function sendIcon(icon, description)
  -- A notification: the proxy ignores ICON_CHANGED sent as a command. Empty values allowed: a
  -- button with no look has no description.
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
  local byValue = follow ~= nil and lookControl() == "By Value"
  for _, look in ipairs(looks:list()) do
    local live = Looks.liveBadge(look)
    local badgeNow, badgeError
    if live then
      badgeNow, badgeError = LiveBadges.read(live.text)
    end
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
      showWhen = look.showWhen,
      showWhenText = byValue and look.showWhen and Expressions.render(look.showWhen, "condition") or nil,
      whenError = byValue and follow:whenError(look.id) or nil,
      badgeNow = badgeNow,
      badgeError = badgeError,
      badgeText = live and Expressions.render(live.text, "string") or nil,
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
  local own = {}
  for _, picture in ipairs(pictures:list()) do
    local entry = {
      id = picture.id,
      kind = picture.kind,
      width = picture.width,
      height = picture.height,
      name = picture.name,
    }
    if picture.every then
      local status = refresher and refresher:status(picture.id) or {}
      -- The source changes with the bytes, so the tab knows to ask for them again.
      entry.url, entry.every, entry.source = pictures:address(picture.id), picture.every, picture.source
      entry.refreshedAt, entry.error = status.refreshedAt, status.error
    end
    table.insert(own, entry)
  end
  local shown = button:shown()
  return {
    properties = properties,
    looks = list,
    pictures = own,
    shown = shown and shown.id or nil,
    lookControl = lookControl(),
    defaultLook = looks:defaultId(),
    matched = byValue and follow:matched() or nil,
    max = Looks.MAX,
    maxChunk = Images.MAX_CHUNK,
    maxBytes = Images.MAX_BYTES,
    packs = Iconify.PACKS,
  }
end

--- Send the Button tab one message over its socket.
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

--- Tell the Button tab which look is shown, when nothing else in its state changed.
--- @return string json
local function pushShown()
  return uiRespond("SHOWN", { shown = tostring(button:shown().id) })
end

--- While true, property changes leave the state push to the command that made them.
local gTabHeld = false

--- Show a property change in the Button tab, once the button is up.
local function syncTab()
  if button and not gTabHeld then
    pushState()
  end
end

--- Run `fn` with property changes' state pushes held, so the caller pushes the state once after.
--- @param fn function
local function holdingTab(fn)
  gTabHeld = true
  local ok, err = pcall(fn)
  gTabHeld = false
  if not ok then
    error(err, 0)
  end
end

--- Answer the Button tab with the state included.
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

--- The most base64 characters in one message to the Button tab.
local PIECE = 48 * 1024

--- Send the Button tab data in pieces of base64, each wrapped in lines for the controller's broker,
--- whose time grows with the longest unbroken run of characters in a message.
--- @param command string
--- @param fields table<string, string> What each piece carries besides its data.
--- @param data string
local function sendPieces(command, fields, data)
  local b64 = C4:Base64Encode(data)
  local count = math.max(1, math.ceil(#b64 / PIECE))
  for i = 1, count do
    local piece = TableDeepCopy(fields)
    piece.index = tostring(i)
    piece.count = tostring(count)
    piece.data = (b64:sub((i - 1) * PIECE + 1, i * PIECE):gsub(string.rep(".", 76), "%0\n"))
    C4:SendDataToUI(command, piece)
  end
end

--- @param tParams table
--- @return table params The Button tab's parameters, base64 JSON in DATA.
local function tabParams(tParams)
  local ok, params = pcall(function()
    -- The tab wraps its base64 in lines for the controller's broker.
    return JSON:decode(C4:Base64Decode((tostring(Select(tParams, "DATA") or "e30="):gsub("[\r\n]", ""))))
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
    :updateAll(DRIVER_GITHUB_REPO, driverFilenames, Properties["Update Channel"] == "Prerelease", forceUpdate)
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
    badges:watch(nil)
    refresher:watch(nil)
    sendIcon(Images.ownIcon(driverName()), "")
    UpdateProperty("Driver Status", drivercentral.UNLICENSED_STATUS)
    pushState()
    return
  end
  log:info("Licensed again: the button shows its look")
  local shown = button:shown()
  if shown then
    local ok, err = button:show(shown.id, true)
    if not ok then
      log:warn("Could not show look %s: %s", shown.name, err)
    end
  end
  registerLookIs(lookChoices(), true)
  UpdateProperty("Driver Status", "Ready")
  follow:evaluate()
  pushState()
end
--#endif

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end

  for p, _ in pairs(Properties) do
    OnPropertyChanged(p)
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

  -- One engine for Show when and the badges: a variable has one listener in a driver.
  local engine = Expressions:new({
    getExpressions = function()
      local expressions = follow and follow:expressions() or {}
      for name, config in pairs(badges:expressions()) do
        expressions[name] = config
      end
      return expressions
    end,
    recompute = function(name)
      if name == LiveBadges.EXPRESSION then
        badges:check()
      else
        follow:expressionChanged()
      end
    end,
  })
  badges = LiveBadges:new({
    looks = looks,
    images = images,
    engine = engine,
    redraw = function()
      button:redrawBadge()
    end,
    changed = pushState,
    allowed = function()
      return followAllowed()
    end,
  })
  refresher = WebPictures:new({
    pictures = pictures,
    looks = looks,
    arrived = function(lookId, data, source)
      local before = button:shown()
      if not button:imageArrived(lookId, data, source) then
        log:warn("Could not keep look %s's refreshed picture", tostring(lookId))
        return
      end
      announceShown(before and before.id or nil)
    end,
    changed = pushState,
    allowed = function()
      return followAllowed()
    end,
  })
  button = Button:new({
    looks = looks,
    images = images,
    store = persist,
    deviceId = tointeger(C4:GetDeviceID()),
    driverName = driverName(),
    sendIcon = sendIcon,
    badges = badges,
    refresher = refresher,
  })
  badges:boot()
  button:restore()
  pictures:collect()
  events:restoreEvents()
  syncLookEvents()
  announceShown(nil)
  -- Test functions live in memory: Look Is answers from its saved list until the looks change.
  local saved = Select(conditionals:getConditionals(), PROGRAMMING, "look_is", "list_items")
  if saved then
    registerLookIs(saved, true)
  end
  registerLookIs(lookChoices())
  follow = Follow:new({
    looks = looks,
    store = persist,
    engine = engine,
    show = function(id)
      local before = button:shown()
      local ok, err = button:show(id)
      if not ok then
        return false, err
      end
      announceShown(before and before.id or nil)
      pushShown()
      return true
    end,
    changed = pushState,
    allowed = function()
      return followAllowed()
    end,
  })

  gInitialized = true
  UpdateProperty("Driver Status", "Ready")
  -- A tab left open through a restart keeps its socket, so nothing else tells it. With none open this costs nothing.
  pushState()
  --#ifdef DRIVERCENTRAL
  drivercentral:startGate(onLicense)
  --#endif
  -- After the gate: it decides whether the values may change the look.
  follow:start(lookControl() == "By Value")
end

--#ifdef DRIVERCENTRAL
OnDriverLateInit = diagnostics:wrapLateInit(OnDriverLateInit)
--#endif

--- A referenced device's expressions have an error from now on.
--- @param deviceId integer
function OnDeviceRemovedFromProject(deviceId)
  log:trace("OnDeviceRemovedFromProject(%s)", deviceId)
  DeviceUpdated(deviceId)
  if follow then
    follow:deviceRemoved(deviceId)
  end
end

function OnDriverRemovedFromProject()
  log:trace("OnDriverRemovedFromProject()")
  if refresher then
    refresher:watch(nil)
  end
  if button then
    button:removed()
  end
  pictures:clear()
end

-- An update or a restart keeps the served picture: the next start serves it again anyway.
function OnDriverDestroyed()
  log:trace("OnDriverDestroyed()")
  KillAllTimers()
end

--#ifdef DRIVERCENTRAL
-- Director calls these itself, so no dispatcher reports their errors.
OnDeviceRemovedFromProject = diagnostics:wrap(OnDeviceRemovedFromProject, "OnDeviceRemovedFromProject")
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
  if follow then
    follow:setActive(lookControl() == "By Value")
  end
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
      holdingTab(function()
        UpdateProperty(name, value, true)
      end)
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
  if params.isDefault == true then
    looks:setDefault(look.id)
  elseif looks:defaultId() == look.id then
    looks:setDefault(nil)
  end
  if before and before.id == look.id and before.name ~= look.name then
    button:retell()
    announceShown(look.id)
  end
  registerLookIs(lookChoices())
  syncLookEvents()
  follow:lookSaved(look.id)
  pictures:collect()
  -- A picture that refreshes is served as the site sent it: no picture comes from the tab for it.
  local web = pictures:refreshes(look.icon.id) and pictures:get(look.icon.id)
  if web and not (look.image and not look.image.stale and look.image.source == web.source) then
    local data = pictures:load(web.id)
    local before = button:shown()
    if not (data and button:imageArrived(look.id, data, web.source)) then
      return pushError(string.format("the picture for %s could not be kept", look.name))
    end
    announceShown(before and before.id or nil)
    -- By Value saw the look before it had a picture, so it couldn't show it then.
    follow:evaluate()
    look = looks:get(look.id)
  end
  local shown = button:shown()
  if shown and shown.id == look.id then
    refresher:watch(look)
    badges:watch(look)
    -- A stale picture is about to be replaced, and showing the new one draws the badge.
    if not (look.image and look.image.stale) then
      badges:check()
    end
  end
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
    return
  end
  local before = button:shown()
  local ok = button:imageArrived(look.id, png)
  if not ok then
    return pushError(string.format("the picture for %s could not be kept", look.name))
  end
  log:info("Stored the picture for look %s (%d bytes)", look.name, #png)
  announceShown(before and before.id or nil)
  follow:evaluate()
  return reply("IMAGE_STORED", { look = tostring(look.id) })
end

--- One chunk of a picture for the button's own list. The last one keeps it and answers with its id.
--- @param tParams table
function UIR._PUT_PICTURE(tParams)
  local params = tabParams(tParams)
  local data, err = images:accept("picture", params.upload, params.index, params.count, params.data, function(whole)
    if not Pictures.kindOf(whole) then
      return "picture is not a PNG, JPEG or SVG"
    end
    return nil
  end)
  if err then
    return pushError(string.format("the picture did not arrive: %s", err))
  end
  if not data then
    return
  end
  local picture, addErr = pictures:add(data, { width = params.width, height = params.height, name = params.name })
  if not picture then
    return pushError(addErr)
  end
  log:info("Kept picture %s (%d bytes)", picture.id, picture.bytes)
  return reply("PICTURE_STORED", { picture = picture.id })
end

--- One of the button's own pictures, for the Button tab to draw.
--- @param tParams table
function UIR._GET_PICTURE(tParams)
  local id = tostring(tabParams(tParams).id or "")
  local picture = pictures:get(id)
  local data = picture and pictures:load(id)
  if not data then
    return uiRespond("PICTURE", { id = id, error = "the picture is gone" })
  end
  sendPieces("PICTURE", { id = id, kind = picture.kind }, data)
end

--- A picture from a web address, fetched by the controller so an address on the home network works,
--- for the Button tab to draw and keep as it does a file.
--- @param tParams table
function UIR._FETCH_PICTURE(tParams)
  log:trace("UIR._FETCH_PICTURE()")
  local params = tabParams(tParams)
  local request = tostring(params.request or "")
  local address, err = Pictures.checkAddress(params.url)
  if not address then
    return uiRespond("FETCHED", { request = request, error = err })
  end
  Pictures.fetch(address, function(body, refused)
    if not body then
      log:warn("Fetching a picture failed: %s", refused)
      C4:SendDataToUI("FETCHED", { request = request, error = refused })
      return
    end
    sendPieces("FETCHED", { request = request }, body)
  end)
end

--- A picture from a web address that refreshes, kept for a look to use: the controller fetches it
--- again rather than the tab sending back what it fetched, since it's kept as the site sends it.
--- @param tParams table
function UIR._ADD_WEB_PICTURE(tParams)
  log:trace("UIR._ADD_WEB_PICTURE()")
  local params = tabParams(tParams)
  local request = tostring(params.request or "")
  local address, err = Pictures.checkAddress(params.url)
  if address and not Pictures.checkEvery(params.every) then
    address, err = nil, "A picture refreshes every minute, 5 minutes, 15 minutes or hour."
  end
  if not address then
    return uiRespond("PICTURE_STORED", { request = request, error = err })
  end
  Pictures.fetch(address, function(body, refused)
    local picture
    if body then
      picture, refused = pictures:addWeb(body, address, params.every)
    end
    if not picture then
      C4:SendDataToUI("PICTURE_STORED", { request = request, error = refused })
      return
    end
    refresher:noteFetched(picture.id)
    log:info("Kept picture %s, which refreshes every %d seconds", picture.id, picture.every)
    reply("PICTURE_STORED", { request = request, picture = picture.id })
  end)
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
  pictures:collect()
  announceShown(before and before.id or nil)
  registerLookIs(lookChoices())
  syncLookEvents()
  follow:lookDeleted(removed.id, before ~= nil and before.id == removed.id)
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
  follow:evaluate()
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
  return pushShown()
end

--- The devices a Show when can read. This button's own Look variable sends it no change events, and
--- a look following the look shown could only chase itself, so the button isn't offered.
function UIR._GET_DEVICES()
  log:trace("UIR._GET_DEVICES()")
  local own = tointeger(C4:GetDeviceID())
  local devices = {}
  for _, device in ipairs(Expressions.devices()) do
    if device.id ~= own then
      table.insert(devices, device)
    end
  end
  table.sort(devices, function(a, b)
    local roomA, roomB = tostring(a.roomName):lower(), tostring(b.roomName):lower()
    if roomA ~= roomB then
      return roomA < roomB
    end
    local nameA, nameB = tostring(a.name):lower(), tostring(b.name):lower()
    if nameA ~= nameB then
      return nameA < nameB
    end
    return a.id < b.id
  end)
  return uiRespond("DEVICES_DATA", { devices = JSON:encode(devices) })
end

--- @param text string
--- @param bytes integer
--- @return string cut At most that many bytes, on a whole character: a UTF-8 lead byte left on its own isn't valid text.
local function cutText(text, bytes)
  if #text <= bytes then
    return text
  end
  return (text:sub(1, bytes):gsub("[\192-\255][\128-\191]*$", ""))
end

--- One device's variables, with a value short enough to show beside its name.
--- @param tParams table
function UIR._GET_DEVICE_VARIABLES(tParams)
  log:trace("UIR._GET_DEVICE_VARIABLES()")
  local deviceId = tonumber(tabParams(tParams).deviceId)
  local variables = deviceId and Expressions.deviceVariables(deviceId) or {}
  for _, variable in ipairs(variables) do
    variable.value = cutText(tostring(variable.value == nil and "" or variable.value), 60)
  end
  return uiRespond("DEVICE_VARIABLES_DATA", { deviceId = tostring(deviceId or ""), variables = JSON:encode(variables) })
end

--- Try a Show when without saving it, for the editor's preview.
--- @param tParams table
function UIR._EVAL_EXPRESSION(tParams)
  log:trace("UIR._EVAL_EXPRESSION()")
  local params = tabParams(tParams)
  local mode = params.mode == "string" and "string" or "condition"
  local expression = tostring(params.expression or ""):sub(1, Looks.MAX_SHOW_WHEN)
  -- What a save refuses holds Save in the tab: the other errors depend on values, which change.
  local hold
  if Looks.readsOwn(expression, ownIds(), mode) then
    hold = Looks.OWN_VARIABLES
  elseif mode == "condition" then
    hold = Looks.compileError(expression)
  end
  local evaluation = hold and { rendered = Expressions.render(expression, mode) }
    or Expressions.evaluate(mode, expression)
  return uiRespond("EVAL_RESULT", {
    id = tostring(params.id or ""),
    fitted = mode == "string" and evaluation.result and LiveBadges.fit(evaluation.result) or nil,
    rendered = evaluation.rendered or "",
    substituted = cutText(evaluation.substituted or "", Looks.MAX_SHOW_WHEN),
    result = evaluation.result ~= nil and tostring(evaluation.result) or "",
    error = hold or evaluation.error or "",
    hold = hold and "yes" or nil,
  })
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
  pushShown()
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
      -- A look passed over may have lost its picture, which only the whole state tells.
      if next(tried) then
        pushState()
      else
        pushShown()
      end
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
PRESS_ACTIONS["By Value"] = function() end

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

--- Fetch the shown look's picture from its web address now.
function EC.Refresh_Web_Picture()
  log:trace("EC.Refresh_Web_Picture()")
  local ok, err = refresher:refresh()
  if not ok then
    log:warn("Refresh Web Picture: %s", err)
  end
end

--- Point a look's refreshing picture at another web address, and fetch it now.
--- @param params table
function EC.Set_Web_Address(params)
  log:trace("EC.Set_Web_Address()")
  local look = looks:fromChoice(Select(params, "Look"))
  if not look then
    log:warn("Set Web Address: no look %s", tostring(Select(params, "Look")))
    return
  end
  if not pictures:refreshes(look.icon.id) then
    log:warn("Set Web Address: look %s's picture doesn't refresh from a web address", look.name)
    return
  end
  local address, err = Pictures.checkAddress(Select(params, "Address"))
  if not address then
    log:warn("Set Web Address: look %s: %s", look.name, err)
    return
  end
  pictures:setAddress(look.icon.id, address)
  refresher:forget(look.icon.id)
  log:info("Set Web Address: look %s's picture has a new address", look.name)
  refresher:refreshPicture(look.icon.id)
  pushState()
end

--- @param paramName string
--- @return string[] choices The looks whose picture refreshes from a web address.
function GCPL.Set_Web_Address(paramName)
  log:trace("GCPL.Set_Web_Address(%s)", paramName)
  if paramName ~= "Look" then
    return {}
  end
  local choices = {}
  for _, look in ipairs(looks:list()) do
    if pictures:refreshes(look.icon.id) then
      table.insert(choices, Looks.label(look))
    end
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
  follow:stop()
  button:reset()
  pictures:clear()
  values:reset()
  conditionals:reset()
  events:reset()
  gLookIsItems = nil
  -- As a fresh install: the variable comes back empty, and no Look Changed fires.
  announceShown(nil)
  holdingTab(function()
    for name, value in pairs(GetPropertyResetValues({})) do
      UpdateProperty(name, value, true)
    end
    for name, value in pairs(RESET_PROPERTY_VALUES) do
      UpdateProperty(name, value, true)
    end
  end)
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

followAllowed = function()
  return drivercentral:licensed()
end

-- _GET_STATE and _SET_DRIVER stay open while stopped: they only do what Composer's own Properties tab can.
-- _GET_PICTURE does too: it only shows the tab a picture the button already keeps.
RFP.SELECT = whileLicensed(RFP.SELECT)
EC.Show_Look = whileLicensed(EC.Show_Look)
EC.Next_Look = whileLicensed(EC.Next_Look)
EC.Previous_Look = whileLicensed(EC.Previous_Look)
EC.Reset_Driver = whileLicensed(EC.Reset_Driver)
GCPL.Show_Look = whileLicensed(GCPL.Show_Look, function()
  return {}
end)
EC.Refresh_Web_Picture = whileLicensed(EC.Refresh_Web_Picture)
EC.Set_Web_Address = whileLicensed(EC.Set_Web_Address)
GCPL.Set_Web_Address = whileLicensed(GCPL.Set_Web_Address, function()
  return {}
end)
for _, name in ipairs({
  "_SAVE_LOOK",
  "_PUT_IMAGE",
  "_PUT_PICTURE",
  "_DELETE_LOOK",
  "_ORDER_LOOKS",
  "_SHOW_LOOK",
  "_GET_DEVICES",
  "_GET_DEVICE_VARIABLES",
  "_EVAL_EXPRESSION",
}) do
  UIR[name] = whileLicensed(UIR[name], function()
    return pushError(UNLICENSED_REFUSAL)
  end)
end
UIR._ICONIFY = whileLicensed(UIR._ICONIFY, function(tParams)
  return uiRespond("ICONIFY", { request = tostring(tabParams(tParams).request or ""), error = UNLICENSED_REFUSAL })
end)
UIR._FETCH_PICTURE = whileLicensed(UIR._FETCH_PICTURE, function(tParams)
  return uiRespond("FETCHED", { request = tostring(tabParams(tParams).request or ""), error = UNLICENSED_REFUSAL })
end)
UIR._ADD_WEB_PICTURE = whileLicensed(UIR._ADD_WEB_PICTURE, function(tParams)
  return uiRespond(
    "PICTURE_STORED",
    { request = tostring(tabParams(tParams).request or ""), error = UNLICENSED_REFUSAL }
  )
end)
--#endif
