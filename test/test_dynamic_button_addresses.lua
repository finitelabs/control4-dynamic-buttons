--- How a look's picture reaches Navigator. A tile shows the proxy's own icon while it waits for a
--- picture it doesn't have, so a look keeps its address and its file until its picture changes, and
--- the proxy's own icon is transparent rather than the driver's icon.

local T = require("testlib")
local H = require("dynamic_button_harness")
local LibDeflate = require("LibDeflate")

local SERVED = "C4Z/www/buttons/" .. H.DEVICE_ID
local WWW = H.DRIVER:gsub("driver%.lua$", "www/")

--- @param name string
--- @param id integer
local function show(name, id)
  EC.Show_Look({ Look = name .. " (" .. id .. ")" })
end

--- @return string|nil address The last address the proxy was told.
local function address()
  local icon = H.lastIcon()
  return icon and icon.params.icon or nil
end

--- @param path string
--- @return string|nil data The file the driver ships.
local function shipped(path)
  local file = io.open(WWW .. path, "rb")
  if not file then
    return nil
  end
  local data = file:read("*a")
  file:close()
  return data
end

--- @param png string
--- @return boolean clear Every pixel has no alpha, read without the code under test.
local function transparent(png)
  local function u32(at)
    local a, b, c, d = png:byte(at, at + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  local at, data, width, color = 9, {}, nil, nil
  while at <= #png do
    local length, kind = u32(at), png:sub(at + 4, at + 7)
    if kind == "IHDR" then
      width, color = u32(at + 8), png:byte(at + 17)
    elseif kind == "IDAT" then
      data[#data + 1] = png:sub(at + 8, at + 7 + length)
    end
    at = at + 12 + length
  end
  local raw = color == 6 and LibDeflate:DecompressZlib(table.concat(data))
  if not raw then
    return false
  end
  -- Any filter of rows that are all zero is all zero.
  local stride = width * 4 + 1
  for i = 1, #raw do
    if (i - 1) % stride ~= 0 and raw:byte(i) ~= 0 then
      return false
    end
  end
  return true
end

H.start()

T.section("What a tile shows while it waits")
local xml = assert(io.open(H.XML, "r"))
local placeholders = 0
for icon in xml:read("*a"):gmatch("<Icon [^>]*>controller://driver/dynamic_button/([^<]*)</Icon>") do
  placeholders = placeholders + 1
  T.contains("the proxy's own icon is the placeholder", icon, "icons/placeholder_")
  local png = shipped(icon)
  T.truthy(icon .. " ships, transparent", png and transparent(png))
end
xml:close()
T.eq("in every size the proxy asks for", placeholders, 5)

T.section("A button with no look")
T.eq(
  "shows the driver's icon by its address, not the proxy's",
  address(),
  "controller://driver/dynamic_button/icons/experience_300.png"
)
local logo = shipped("icons/experience_300.png")
T.truthy("which ships, and isn't transparent", logo and not transparent(logo))

T.section("Coming back to a look")
local red = H.addLook("Red")
local blue = H.addLook("Blue")
show("Red", red)
local redAddress = address()
show("Blue", blue)
local blueAddress = address()
T.neq("each look has its own address", blueAddress, redAddress)
ShimFiles(SERVED)[red .. ".png"] = "left in place"
H.mark()
show("Red", red)
T.eq("a look comes back under the same address, which the app has", address(), redAddress)
T.eq("and its file isn't written again", ShimFiles(SERVED)[red .. ".png"], "left in place")
show("Blue", blue)
T.eq("nor is the other look's address new", address(), blueAddress)
H.sendImage(red, H.png("Red"))
ShimFiles(SERVED)[red .. ".png"] = nil

T.section("A new picture")
H.mark()
H.sendImage(red, H.png("Red again"))
T.eq("for a look not shown, the proxy hears nothing", H.lastIcon(), nil)
T.eq("and its old file goes", ShimFiles(SERVED)[red .. ".png"], nil)
show("Red", red)
T.neq("it comes out under a new address", address(), redAddress)
T.eq("with the new picture", ShimFiles(SERVED)[red .. ".png"], H.png("Red again"))
local before = address()
H.sendImage(red, H.png("Red once more"))
T.neq("for the shown look, a new address at once", address(), before)
T.eq("with the new picture", ShimFiles(SERVED)[red .. ".png"], H.png("Red once more"))

T.section("A restart")
local shownAddress = address()
ShimFiles(SERVED)[blue .. ".png"] = "left in place"
H.restart()
T.eq("the proxy hears the same address", address(), shownAddress)
T.eq("and a look not shown keeps its file", ShimFiles(SERVED)[blue .. ".png"], "left in place")

T.section("A driver update, which replaces the folder")
for name in pairs(ShimFiles(SERVED)) do
  ShimFiles(SERVED)[name] = nil
end
H.update()
T.eq("the shown look is served again", ShimFiles(SERVED)[red .. ".png"], H.png("Red once more"))
show("Blue", blue)
T.eq("and any other when it's shown", ShimFiles(SERVED)[blue .. ".png"], H.png("Blue"))
T.eq("at the address it had", address(), blueAddress)

T.section("A stored picture that's gone")
ShimFiles("SANDBOX/looks")["look-" .. red .. ".png"] = nil
show("Red", red)
T.eq("the look stays where it was", Variables["Look"], "Blue")
T.eq("and its served copy goes too", ShimFiles(SERVED)[red .. ".png"], nil)

T.finish()
