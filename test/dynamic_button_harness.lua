--- The Dynamic Button driver under the C4 shim: its driver.xml defaults as Properties, and a record of
--- what it tells the proxy, the Button tab and programming.

require("c4_shim")

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

local function readXml()
  local f = assert(io.open(H.XML, "r"))
  local xml = f:read("*a")
  f:close()
  return xml
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
function C4:SendDataToUI(strCommand, tParams)
  table.insert(H.ui, { command = strCommand, params = tParams })
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
--- A web server's answer to a fetch, by address: { code, headers, body }, or { unreachable = true }; nil
--- answers as Iconify does.
--- @type fun(url: string): table|nil
H.urlAnswer = nil
C4.url = function()
  local transfer = {}
  function transfer:SetOptions() end
  function transfer:OnDone(callback)
    self.onDone = callback
  end
  function transfer:Get(url)
    table.insert(H.fetched, url)
    local answer = H.urlAnswer and H.urlAnswer(url)
    if answer and answer.unreachable then
      pcall(self.onDone, self, {}, 6, "Could not resolve host")
      return
    end
    if answer then
      pcall(
        self.onDone,
        self,
        { { code = answer.code or 200, headers = answer.headers or {}, body = answer.body } },
        0,
        nil
      )
      return
    end
    local headers = { ["Content-Type"] = "application/json; charset=utf-8" }
    pcall(self.onDone, self, { { code = 200, headers = headers, body = H.iconifyBody } }, 0, nil)
  end
  return transfer
end
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

--- A Director restart: the driver stops, its variables, conditional tests and cached state are gone,
--- and only what it stored comes back.
function H.restart()
  OnDriverDestroyed()
  ShimRestartDirector()
  ShimResetEvents()
  require("lib.persist")._persist = {}
  for name in pairs(TC) do
    if type(name) == "string" and name:match("^CONDITIONAL_%d+$") then
      TC[name] = nil
    end
  end
  H.start()
end

--- A driver update: a new driver file loads into a fresh VM, while Director keeps the driver's
--- variables and the events it declared.
function H.update()
  OnDriverDestroyed()
  ShimUpdateDriver()
  require("lib.persist")._persist = {}
  for name in pairs(TC) do
    if type(name) == "string" and name:match("^CONDITIONAL_%d+$") then
      TC[name] = nil
    end
  end
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
      return JSON:decode(H.ui[i].params.state)
    end
  end
  return nil
end

--- Call a Button tab request with its parameters as the tab sends them, base64 JSON in DATA.
--- @param command string
--- @param params table|nil
function H.tab(command, params)
  return UIR[command]({ DATA = (C4:Base64Encode(JSON:encode(params or {})):gsub(string.rep(".", 76), "%0\n")) })
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

--- @return table<string, string> files The button's stored pictures, by file name.
function H.stored()
  return ShimFiles("SANDBOX/looks")
end

return H
