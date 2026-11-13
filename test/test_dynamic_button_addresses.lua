--- How a look's picture reaches Navigator. A look whose picture stays as it is shows through a
--- slot of the picture bank, a display_icons state Navigators draw again with no gap; it keeps the
--- slot and its files until its picture changes. A tile shows the proxy's own icon while it waits
--- for a picture, which is transparent rather than the driver's icon.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_addresses.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local LibDeflate = require("LibDeflate")

local SERVED = "C4Z/www/buttons/" .. H.DEVICE_ID
local BANK = "C4Z/www/bank"
local WWW = H.DRIVER:gsub("driver%.lua$", "www/")

--- @param name string
--- @param id integer
local function show(name, id)
  EC.Show_Look({ Look = name .. " (" .. id .. ")" })
end

--- @return string|nil icon The last icon the proxy was told: a state id or an address.
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
local text = xml:read("*a")
xml:close()
local icons = text:match("<display_icons>(.-)<state ")
local placeholders = 0
for icon in icons:gmatch("<Icon [^>]*>controller://driver/dynamic_button/([^<]*)</Icon>") do
  placeholders = placeholders + 1
  T.contains("the proxy's own icon is the placeholder", icon, "icons/placeholder_")
  local png = shipped(icon)
  T.truthy(icon .. " ships, transparent", png and transparent(png))
end
T.eq("in every size the proxy asks for", placeholders, 5)

T.section("A button with no look")
T.eq("shows the driver's icon through its own state", address(), "own")
local own = text:match('<state id="own">(.-)</state>')
local ownIcons = 0
for icon in own:gmatch("<Icon [^>]*>controller://driver/dynamic_button/([^<]*)</Icon>") do
  ownIcons = ownIcons + 1
  local png = shipped(icon)
  T.truthy(icon .. " ships, and isn't transparent", png and not transparent(png))
end
T.eq("in the sizes Navigators and remotes ask for", ownIcons, 3)

T.section("Coming back to a look")
local red = H.addLook("Red")
local blue = H.addLook("Blue")
show("Red", red)
local redAddress = address()
T.truthy("a look shows through a bank state", redAddress:match("^p%d+$"))
T.eq("whose slot holds the look's picture", H.banked(redAddress), H.png("Red"))
show("Blue", blue)
local blueAddress = address()
T.neq("each look has its own state", blueAddress, redAddress)
ShimFiles(SERVED)[red .. ".png"] = "left in place"
ShimFiles(BANK)[redAddress:sub(2) .. ".png"] = "left in place"
H.mark()
show("Red", red)
T.eq("a look comes back under the same state, which the app has", address(), redAddress)
T.eq("and its file isn't written again", ShimFiles(SERVED)[red .. ".png"], "left in place")
T.eq("nor is its slot's", H.banked(redAddress), "left in place")
show("Blue", blue)
T.eq("nor is the other look's state new", address(), blueAddress)
H.sendImage(red, H.png("Red"))
ShimFiles(SERVED)[red .. ".png"] = nil

T.section("A new picture")
H.mark()
H.sendImage(red, H.png("Red again"))
T.eq("for a look not shown, the proxy hears nothing", H.lastIcon(), nil)
T.eq("and its old file goes", ShimFiles(SERVED)[red .. ".png"], nil)
show("Red", red)
T.neq("it comes out under a new state", address(), redAddress)
T.eq("with the new picture", ShimFiles(SERVED)[red .. ".png"], H.png("Red again"))
T.eq("in its slot too", H.banked(address()), H.png("Red again"))
local before = address()
H.sendImage(red, H.png("Red once more"))
T.neq("for the shown look, a new state at once", address(), before)
T.eq("with the new picture", H.banked(address()), H.png("Red once more"))

T.section("A restart")
local shownAddress = address()
ShimFiles(SERVED)[blue .. ".png"] = "left in place"
H.restart()
T.eq("the proxy hears the same state", address(), shownAddress)
T.eq("and a look not shown keeps its file", ShimFiles(SERVED)[blue .. ".png"], "left in place")

T.section("A driver update, which replaces the folder")
for _, dir in ipairs({ SERVED, BANK, "C4Z/bank" }) do
  for name in pairs(ShimFiles(dir)) do
    ShimFiles(dir)[name] = nil
  end
end
H.update()
T.eq("the shown look is served again", ShimFiles(SERVED)[red .. ".png"], H.png("Red once more"))
T.eq("under the state it had", address(), shownAddress)
T.eq("whose slot holds its picture again", H.banked(shownAddress), H.png("Red once more"))
show("Blue", blue)
T.eq("and any other when it's shown", ShimFiles(SERVED)[blue .. ".png"], H.png("Blue"))
T.eq("at the state it had", address(), blueAddress)
T.eq("with its slot's picture written again", H.banked(blueAddress), H.png("Blue"))

T.section("A stored picture that's gone")
ShimFiles("SANDBOX/looks")["look-" .. red .. ".png"] = nil
show("Red", red)
T.eq("the look stays where it was", Variables["Look"], "Blue")
T.eq("and its served copy goes too", ShimFiles(SERVED)[red .. ".png"], nil)

T.finish()
