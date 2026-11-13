--- The Dynamic Button driver under the C4 shim: its driver.xml defaults as Properties, and a record of
--- what it tells the proxy, the Button tab and programming.

require("c4_shim")

local JSON = require("JSON")

local H = {}

local HERE = debug.getinfo(1, "S").source:match("^@(.*)/") or "."
H.DRIVER = HERE .. "/../drivers/dynamic_button/driver.lua"
H.XML = HERE .. "/../drivers/dynamic_button/driver.xml"
H.DEVICE_ID = 4242
H.PNG_SIGNATURE = "\137PNG\r\n\26\n"

package.preload["cloud-client-byte"] = function()
  return {}
end

-- A product id, so the DriverCentral lines start the gate as a licensed install does: the stubbed client leaves DC_X
-- nil, which runs. test_license_gate.lua drives the gate with the real client.
require("lib.drivercentral").PRODUCT_ID = 900

--- @type string|nil
local xmlText

--- @return string xml driver.xml, read once: nothing changes it during a run.
local function readXml()
  if not xmlText then
    local f = assert(io.open(H.XML, "r"))
    xmlText = f:read("*a")
    f:close()
  end
  return xmlText
end

--- @return table<string, string> props Each property's driver.xml default.
function H.defaultProperties()
  local props = {}
  for block in readXml():gmatch("<property>(.-)</property>") do
    local name = block:match("<name>(.-)</name>")
    if name then
      props[name] = block:match("<default>(.-)</default>") or ""
    end
  end
  return props
end

H.proxy = {}
H.ui = {}
H.fired = {}
H.dirs = {}
--- Every "<command> <message type>" sent to the proxy in the run, kept across H.mark().
H.sentTypes = {}

function C4:GetDeviceID()
  return H.DEVICE_ID
end
function C4:GetDriverFileName()
  return "dynamic_button.c4z"
end
function C4:GetDevicesByC4iName()
  return {}
end
function C4:UpdateProperty(name, value)
  Properties[name] = value
end
function C4:SendToProxy(idBinding, strCommand, tParams, strMessage, allowEmpty)
  table.insert(H.proxy, {
    binding = idBinding,
    command = strCommand,
    params = tParams,
    message = strMessage,
    allowEmpty = allowEmpty,
  })
  H.sentTypes[strCommand .. " " .. tostring(strMessage)] = true
end
-- Each message goes as one parameter, `json`, as lib.ui.page sends it. It is kept decoded, and the text as sent is
-- the entry's `json`, which a comparison of entries leaves out.
function C4:SendDataToUI(strCommand, tParams)
  local keys = 0
  for _ in pairs(tParams or {}) do
    keys = keys + 1
  end
  assert(keys == 1 and type(tParams.json) == "string", strCommand .. " goes to the tab as one json parameter")
  local entry = { command = strCommand, params = JSON:decode(tParams.json) }
  table.insert(H.ui, setmetatable(entry, { __index = { json = tParams.json } }))
end
function C4:FireEvent(name)
  table.insert(H.fired, name)
end
-- A dynamic event is recorded by its declared name, so a test reads "Low Shown" rather than an id;
-- an id nothing declares is recorded as such, and fires nothing on a controller.
function C4:FireEventByID(id)
  local declared = ShimEvents()[id]
  table.insert(H.fired, declared and declared.name or ("undeclared event " .. tostring(id)))
end
function C4:FileCreateDir(alias, dir)
  assert(type(alias) == "string" and type(dir) == "string", "FileCreateDir takes an alias and a folder")
  H.dirs[alias .. "/" .. dir] = true
  return true
end

-- Only the documented forms: an alias, or an alias and a folder. An explicit nil folder is refused,
-- since a controller's API methods check their arguments strictly.
local fileSetDir = C4.FileSetDir
local fileDir = "SANDBOX"
function C4:FileSetDir(...)
  local count, dir, subdir = select("#", ...), ...
  if count >= 2 and subdir == nil then
    error("FileSetDir: an explicit nil folder", 2)
  end
  fileDir = subdir and (dir .. "/" .. subdir) or dir
  return fileSetDir(self, dir, subdir)
end

--- Files the driver can't open, by "<alias>/<folder>/<name>": a storage failure.
H.unopenable = {}
local fileOpen = C4.FileOpen
function C4:FileOpen(name)
  if H.unopenable[fileDir .. "/" .. name] then
    return -1
  end
  return fileOpen(self, name)
end

-- What the driver fetched, and Iconify's answer: a JSON body with Iconify's own content type, so the
-- vendored url.lua decodes it as it does on a controller.
USER_AGENT = "test"
H.fetched = {}
H.iconifyBody = '{"icons":["mdi:battery"],"total":1}'
--- A web server's answer to a fetch, by address: { code, headers, body, chunk }, a list of them as
--- { responses = {...} } when the transfer follows a redirect, or { unreachable = true } or
--- { timeout = true }; nil answers as Iconify does. `chunk` is how many bytes each body chunk carries.
--- @type fun(url: string): table|nil
H.urlAnswer = nil
--- Every transfer started, with its options, the chunks it took and whether a callback stopped it.
H.transfers = {}

-- C4:url() as the DriverWorks docs describe it: OnHeaders(transfer, response) for each response,
-- then OnBodyChunk(transfer, response, chunk) for each chunk (the body then isn't kept) or the body
-- in response.body, then OnBody, and OnDone(transfer, responses, errCode, errMsg) once. A callback
-- returning true aborts, and OnDone gets -1. A timeout is curl's error 28.
C4.url = function()
  local transfer = { callbacks = {}, chunks = 0 }
  table.insert(H.transfers, transfer)
  function transfer:SetOptions(options)
    self.options = options
    return self
  end
  for _, name in ipairs({ "OnHeaders", "OnBodyChunk", "OnBody", "OnDone" }) do
    transfer[name] = function(self, callback)
      self.callbacks[name] = callback
      return self
    end
  end
  function transfer:Cancel()
    self.cancelled = true
    return self
  end
  function transfer:_done(responses, code, message)
    if self.callbacks.OnDone then
      pcall(self.callbacks.OnDone, self, responses, code, message)
    end
  end
  function transfer:_run(answer)
    if answer.unreachable then
      return self:_done({}, 6, "Could not resolve host")
    end
    if answer.timeout then
      return self:_done({}, 28, "Timeout was reached")
    end
    local done, cb = {}, self.callbacks
    for _, r in ipairs(answer.responses or { answer }) do
      local response = { code = r.code or 200, headers = r.headers or {} }
      table.insert(done, response)
      if cb.OnHeaders and cb.OnHeaders(self, response) == true then
        self.aborted = true
        return self:_done(done, -1, nil)
      end
      local body = r.body or ""
      if cb.OnBodyChunk then
        local size = r.chunk or 4096
        for i = 1, #body, size do
          self.chunks = self.chunks + 1
          if cb.OnBodyChunk(self, response, body:sub(i, i + size - 1)) == true then
            self.aborted = true
            return self:_done(done, -1, nil)
          end
        end
      else
        response.body = body
      end
      if cb.OnBody then
        cb.OnBody(self, response)
      end
    end
    self:_done(done, 0, nil)
  end
  function transfer:Get(url, headers)
    table.insert(H.fetched, url)
    self.url, self.headers = url, headers
    local answer = H.urlAnswer and H.urlAnswer(url)
    self:_run(answer or { headers = { ["Content-Type"] = "application/json; charset=utf-8" }, body = H.iconifyBody })
    return self
  end
  return transfer
end
-- The shim has no C4:GetUptime: the controller has been up an hour.
if not C4.GetUptime then
  function C4:GetUptime()
    return 3600
  end
end
-- No Director listens for a Navigator refresh under the shim: count them instead.
require("drivers-common-public.global.lib")
H.navRefreshes = 0
function RefreshNavs()
  H.navRefreshes = H.navRefreshes + 1
end
-- A bank the Navigators have learned since the controller started; test_dynamic_button_bank covers a new one.
ShimFiles("C4Z/bank").refreshed = string.format("%.0f", C4:GetTime())
local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "minimum_os_version" then
    return "3.3.1"
  end
  if section == "config" then
    return readXml():match("<config>(.-)</config>")
  end
  -- The build stamps driver.xml's version; the cloud client's late init stops without one.
  if section == "version" then
    return "20261104"
  end
  return configInfo(self, section)
end

--- Load the driver into this VM and run its start, as Director does on a load.
function H.start()
  Properties = Properties and next(Properties) and Properties or H.defaultProperties()
  dofile(H.DRIVER)
  OnDriverInit()
  ShimLateInit()
end

--- What a new Lua VM no longer has: the stored values' cache, the conditional tests and the variable listeners, whose
--- callbacks would otherwise reach the stopped driver's objects.
local function forgetMemory()
  require("lib.persist")._persist = {}
  for name in pairs(TC) do
    if type(name) == "string" and name:match("^CONDITIONAL_%d+$") then
      TC[name] = nil
    end
  end
  for device in pairs(OWVC) do
    if type(device) == "number" then
      OWVC[device] = nil
    end
  end
end

--- A Director restart: the driver stops, its variables, conditional tests and cached state are gone,
--- and only what it stored comes back.
function H.restart()
  OnDriverDestroyed()
  ShimRestartDirector()
  ShimResetEvents()
  forgetMemory()
  H.start()
end

--- A driver update: a new driver file loads into a fresh VM, while Director keeps the driver's
--- variables and the events it declared.
function H.update()
  OnDriverDestroyed()
  ShimUpdateDriver()
  forgetMemory()
  H.start()
end

--- A press of the button in Navigator, as the UI Button proxy sends it.
function H.press()
  ReceivedFromProxy(5001, "SELECT", { Menu = "comfort", Room = "19", deviceId = "-1" })
end

--- @return table<string, integer> ids Each declared event's id, by its name.
function H.eventIds()
  local ids = {}
  for id, event in pairs(ShimEvents()) do
    ids[event.name] = id
  end
  return ids
end

--- Forget what was recorded.
function H.mark()
  H.proxy, H.ui, H.fired = {}, {}, {}
end

--- @return table|nil last The last ICON_CHANGED the proxy was told.
function H.lastIcon()
  for i = #H.proxy, 1, -1 do
    if H.proxy[i].command == "ICON_CHANGED" then
      return H.proxy[i]
    end
  end
  return nil
end

--- @param command string
--- @return table|nil last The last message of that command sent to the Button tab.
function H.lastUi(command)
  for i = #H.ui, 1, -1 do
    if H.ui[i].command == command then
      return H.ui[i].params
    end
  end
  return nil
end

--- @return table|nil state The state in the Button tab's last message that carries one.
function H.state()
  for i = #H.ui, 1, -1 do
    if H.ui[i].params.state then
      return H.ui[i].params.state
    end
  end
  return nil
end

--- Call a Button tab request with its parameters as the tab sends them, base64 JSON in DATA.
--- @param command string
--- @param params table|nil
--- @return table|nil reply The last message the call sent the tab, its command in `_command`; nil when it sent none.
function H.tab(command, params)
  local before = #H.ui
  UIR[command]({ DATA = (C4:Base64Encode(JSON:encode(params or {})):gsub(string.rep(".", 76), "%0\n")) })
  if #H.ui == before then
    return nil
  end
  local last = H.ui[#H.ui]
  local reply = { _command = last.command }
  for key, value in pairs(last.params) do
    reply[key] = value
  end
  return reply
end

--- A small stand-in PNG; only its signature is checked.
--- @param tag string
--- @param size integer|nil
--- @return string png
function H.png(tag, size)
  local body = tag .. string.rep("x", math.max(0, (size or 64) - #tag))
  return H.PNG_SIGNATURE .. body
end

--- @param name string
--- @param extra table|nil
--- @return table fields A look as the Button tab saves it.
function H.lookFields(name, extra)
  local fields = {
    name = name,
    icon = {
      id = "mdi:battery-50",
      body = '<path fill="currentColor" d="M0 0h24v24H0z"/>',
      width = 24,
      height = 24,
      license = "Apache 2.0",
      licenseUrl = "https://github.com/Templarian/MaterialDesign/blob/master/LICENSE",
    },
    iconColor = "#ffffff",
    tileShape = "Rounded Square",
    tileColor = "#109eff",
  }
  for k, v in pairs(extra or {}) do
    fields[k] = v
  end
  return fields
end

--- Save a look through the Button tab and send its picture in chunks.
--- @param name string
--- @param png string|nil
--- @return integer id
function H.addLook(name, png)
  H.tab("_SAVE_LOOK", H.lookFields(name))
  local id = tonumber(H.lastUi("SAVED").look)
  H.sendImage(id, png or H.png(name))
  return id
end

--- Send a picture as the Button tab does: base64, cut into chunks of at most `chunk` characters.
--- @param id integer
--- @param png string
--- @param chunk integer|nil
function H.sendImage(id, png, chunk)
  chunk = chunk or 3072
  local b64 = C4:Base64Encode(png)
  local count = math.ceil(#b64 / chunk)
  for i = 1, count do
    H.tab("_PUT_IMAGE", {
      look = id,
      upload = "u" .. id,
      index = i,
      count = count,
      data = b64:sub((i - 1) * chunk + 1, i * chunk),
    })
  end
end

--- @return table<string, string> files The button's served pictures, by file name.
function H.served()
  return ShimFiles("C4Z/www/buttons/" .. H.DEVICE_ID)
end

--- @param state string|nil A picture bank state's id.
--- @return string|nil png The picture its slot holds.
function H.banked(state)
  local slot = state and state:match("^p(%d+)$")
  return slot and ShimFiles("C4Z/www/bank")[slot .. ".png"] or nil
end

--- @return table<string, string> files The button's stored pictures, by file name.
function H.stored()
  return ShimFiles("SANDBOX/looks")
end

return H
