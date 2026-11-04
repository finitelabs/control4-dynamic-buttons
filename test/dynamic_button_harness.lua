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
  table.insert(H.proxy, { binding = idBinding, command = strCommand, params = tParams, allowEmpty = allowEmpty })
end
function C4:SendDataToUI(strCommand, tParams)
  table.insert(H.ui, { command = strCommand, params = tParams })
end
function C4:FireEvent(name)
  table.insert(H.fired, name)
end
function C4:FileCreateDir(alias, dir)
  H.dirs[alias .. "/" .. dir] = true
  return true
end
local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "minimum_os_version" then
    return "3.3.1"
  end
  if section == "config" then
    return readXml():match("<config>(.-)</config>")
  end
  return configInfo(self, section)
end

--- Load the driver into this VM and run its start, as Director does on a load.
function H.start()
  Properties = Properties and next(Properties) and Properties or H.defaultProperties()
  dofile(H.DRIVER)
  OnDriverInit()
  OnDriverLateInit()
end

--- Stop and load the driver again, as an update or a Director restart does. Stored data survives.
function H.restart()
  OnDriverDestroyed()
  H.start()
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

--- @return table state The Button tab's last STATE.
function H.state()
  return JSON:decode(H.lastUi("STATE").state)
end

--- Call a Button tab request with its parameters as the tab sends them, base64 JSON in DATA.
--- @param command string
--- @param params table|nil
function H.tab(command, params)
  return UIR[command]({ DATA = C4:Base64Encode(JSON:encode(params or {})) })
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
  chunk = chunk or 49152
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
  return ShimFiles("SANDBOX")
end

return H
