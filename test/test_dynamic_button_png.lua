--- A live badge's picture work: a stored PNG prepared once, then its badge rows redone on their own,
--- checked by decoding the result here, without the code under test.

local T = require("testlib")
require("c4_shim")
local bit = require("bit")
local LibDeflate = require("LibDeflate")
local Png = require("dynamic_button.png")
local BadgeArt = require("dynamic_button.badge_art")

local SIGNATURE = "\137PNG\r\n\26\n"

local function u32(value)
  return string.char(
    math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 256) % 256,
    value % 256
  )
end

local function chunk(kind, data)
  return u32(#data) .. kind .. data .. u32(Png.crc32(kind .. data))
end

--- @param width integer
--- @param height integer
--- @param depth integer
--- @param color integer
--- @param interlace integer
local function header(width, height, depth, color, interlace)
  return chunk("IHDR", u32(width) .. u32(height) .. string.char(depth, color, 0, 0, interlace))
end

--- @return integer r, integer g, integer b, integer a The test picture's pixel.
local function pixel(x, y)
  return (x * 7 + y) % 256, (y * 11 + x) % 256, (x * y) % 256, (x + y) % 5 == 0 and 0 or 255
end

--- A PNG whose rows use every filter in turn, as a browser's encoder may.
--- @param size integer
--- @return string png
local function testPng(size)
  local out, above = {}, nil
  for y = 0, size - 1 do
    local row = {}
    for x = 0, size - 1 do
      row[#row + 1], row[#row + 2], row[#row + 3], row[#row + 4] = pixel(x, y)
    end
    local filter, filtered = y % 5, {}
    for i, value in ipairs(row) do
      local left = i > 4 and row[i - 4] or 0
      local up = above and above[i] or 0
      local upLeft = (above and i > 4) and above[i - 4] or 0
      local predictor = 0
      if filter == 1 then
        predictor = left
      elseif filter == 2 then
        predictor = up
      elseif filter == 3 then
        predictor = math.floor((left + up) / 2)
      elseif filter == 4 then
        local p = left + up - upLeft
        local pa, pb, pc = math.abs(p - left), math.abs(p - up), math.abs(p - upLeft)
        predictor = (pa <= pb and pa <= pc) and left or (pb <= pc and up or upLeft)
      end
      filtered[i] = (value - predictor) % 256
    end
    out[#out + 1] = string.char(filter, unpack(filtered))
    above = row
  end
  local compressed = LibDeflate:CompressZlib(table.concat(out), { level = 6 })
  return SIGNATURE .. header(size, size, 8, 6, 0) .. chunk("IDAT", compressed) .. chunk("IEND", "")
end

--- Every chunk's checksum, the stream's, and the pixels, read without the code under test.
--- @param png string
--- @return integer[][]|nil rows
--- @return string|nil why
local function decode(png)
  if png:sub(1, 8) ~= SIGNATURE then
    return nil, "signature"
  end
  local at, data, width, height = 9, {}, nil, nil
  local sawEnd = false
  while at <= #png do
    local a, b, c, d = png:byte(at, at + 3)
    local length = a * 16777216 + b * 65536 + c * 256 + d
    local kind = png:sub(at + 4, at + 7)
    local body = png:sub(at + 8, at + 7 + length)
    if png:sub(at + 8 + length, at + 11 + length) ~= u32(Png.crc32(kind .. body)) then
      return nil, "chunk checksum of " .. kind
    end
    if kind == "IHDR" then
      local w1, w2, w3, w4 = body:byte(1, 4)
      width = w1 * 16777216 + w2 * 65536 + w3 * 256 + w4
      w1, w2, w3, w4 = body:byte(5, 8)
      height = w1 * 16777216 + w2 * 65536 + w3 * 256 + w4
    elseif kind == "IDAT" then
      data[#data + 1] = body
    elseif kind == "IEND" then
      sawEnd = true
    end
    at = at + 12 + length
  end
  if not sawEnd then
    return nil, "no end"
  end
  -- LibDeflate checks the stream's own checksum here.
  local raw = LibDeflate:DecompressZlib(table.concat(data))
  if not raw then
    return nil, "the stream"
  end
  if #raw ~= (width * 4 + 1) * height then
    return nil, "size " .. #raw
  end
  local rows, above = {}, nil
  for y = 0, height - 1 do
    local start = y * (width * 4 + 1) + 1
    local filter = raw:byte(start)
    local row = { raw:byte(start + 1, start + width * 4) }
    for i = 1, #row do
      local left = i > 4 and row[i - 4] or 0
      local up = above and above[i] or 0
      local upLeft = (above and i > 4) and above[i - 4] or 0
      local predictor = 0
      if filter == 1 then
        predictor = left
      elseif filter == 2 then
        predictor = up
      elseif filter == 3 then
        predictor = math.floor((left + up) / 2)
      elseif filter == 4 then
        local p = left + up - upLeft
        local pa, pb, pc = math.abs(p - left), math.abs(p - up), math.abs(p - upLeft)
        predictor = (pa <= pb and pa <= pc) and left or (pb <= pc and up or upLeft)
      end
      row[i] = (row[i] + predictor) % 256
    end
    rows[y + 1] = row
    above = row
  end
  return rows
end

--- @param rows integer[][]
--- @param size integer
--- @param changed fun(x: integer, y: integer): integer|nil, integer|nil, integer|nil, integer|nil
--- @return integer|nil x The first pixel that isn't as expected.
--- @return integer|nil y
local function firstWrong(rows, size, changed)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local r, g, b, a = changed(x, y)
      if not r then
        r, g, b, a = pixel(x, y)
      end
      local i = x * 4 + 1
      local row = rows[y + 1]
      if row[i] ~= r or row[i + 1] ~= g or row[i + 2] ~= b or row[i + 3] ~= a then
        return x, y
      end
    end
  end
  return nil
end

local SIZE = 48
local stored = testPng(SIZE)

T.section("The rows come back as the picture has them")
T.eq("the test's own decoder reads the test picture", firstWrong(assert(decode(stored)), SIZE, function() end), nil)
local cache = assert(Png.setup(stored, 5, 12))
T.eq("the size", cache.width, SIZE)
local rows = Png.rows(cache)
T.eq("one row for each the badge can touch", #rows, 8)
local matches = true
for y = 5, 12 do
  for x = 0, SIZE - 1 do
    local r, g, b, a = pixel(x, y)
    local row, i = rows[y - 4], x * 4 + 1
    matches = matches and row[i] == r and row[i + 1] == g and row[i + 2] == b and row[i + 3] == a
  end
end
T.truthy("whatever filter each row used", matches)

T.section("Redrawing")
for _, range in ipairs({ { 5, 12 }, { 0, 7 }, { SIZE - 8, SIZE - 1 }, { SIZE - 9, SIZE - 2 }, { 20, 20 } }) do
  local y0, y1 = range[1], range[2]
  local prepared = assert(Png.setup(stored, y0, y1))
  local drawn = Png.rows(prepared)
  for _, row in ipairs(drawn) do
    row[1], row[2], row[3], row[4] = 9, 8, 7, 255
  end
  local decoded, why = decode(Png.splice(prepared, drawn))
  local label = string.format("rows %d to %d", y0, y1)
  T.truthy(label .. " make a whole, valid PNG: " .. tostring(why), decoded ~= nil)
  if decoded then
    local x, y = firstWrong(decoded, SIZE, function(px, py)
      if px == 0 and py >= y0 and py <= y1 then
        return 9, 8, 7, 255
      end
    end)
    T.eq(label .. " change those pixels and no others", x and (x .. "," .. y), nil)
  end
end

T.section("Again and again from one preparation")
local first = Png.rows(cache)
first[1][1] = 200
Png.splice(cache, first)
local again, whyAgain = decode(Png.splice(cache, Png.rows(cache)))
T.truthy("an earlier redraw leaves nothing behind: " .. tostring(whyAgain), again ~= nil)
T.eq("the picture is as it was", firstWrong(again, SIZE, function() end), nil)

T.section("Kept in a file")
local packed = Png.pack(cache)
local unpacked = Png.unpack(packed)
T.eq("it comes back the same", unpacked, cache)
T.eq("something else in the file isn't taken for it", Png.unpack("not this"), nil)
T.eq("and neither is a cut one", Png.unpack(packed:sub(1, #packed - 1)), nil)

T.section("Pictures it can't take")
local function whyNot(png)
  local _, why = Png.setup(png, 0, 1)
  return why
end
T.contains("not a PNG", whyNot("JFIF"), "not a PNG")
T.contains("no alpha", whyNot(SIGNATURE .. header(4, 4, 8, 2, 0) .. chunk("IEND", "")), "RGBA")
T.contains("16-bit", whyNot(SIGNATURE .. header(4, 4, 16, 6, 0) .. chunk("IEND", "")), "RGBA")
T.contains("interlaced", whyNot(SIGNATURE .. header(4, 4, 8, 6, 1) .. chunk("IEND", "")), "interlaced")
T.contains("no pixels", whyNot(SIGNATURE .. header(4, 4, 8, 6, 0) .. chunk("IEND", "")), "no pixels")
T.contains("a broken stream", whyNot(SIGNATURE .. header(4, 4, 8, 6, 0) .. chunk("IDAT", "xx")), "did not decode")

T.section("The address's key is the standard CRC-32")
T.eq("the check value", Png.crc32("123456789"), 0xCBF43926)
T.eq("nothing", Png.crc32(""), 0)
T.eq("uses the bit library's signed results", bit.tobit(Png.crc32("123456789")) < 0, true)

T.section("The badge's place")
local CANVAS = 300
local function placed(place, size)
  return { text = "x", place = place, color = "#FFFFFF", background = "#DC2626", size = size }
end
for _, place in ipairs({ "Top Right", "Bottom Right", "Under" }) do
  for _, size in ipairs({ 50, 100, 150 }) do
    local y0, y1 = BadgeArt.rows(placed(place, size), CANVAS)
    T.truthy(string.format("%s at %d%% stays in the picture", place, size), y0 >= 0 and y1 < CANVAS and y0 < y1)
  end
end
local small0, small1 = BadgeArt.rows(placed("Top Right", 50), CANVAS)
local large0, large1 = BadgeArt.rows(placed("Top Right", 150), CANVAS)
T.truthy("a larger badge covers more rows", large1 - large0 > small1 - small0)

--- @param badge LookBadge
--- @param text string
--- @return integer[][] rows
--- @return integer y0
local function drawnOnClear(badge, text)
  local y0, y1 = BadgeArt.rows(badge, CANVAS)
  local clear = {}
  for y = 1, y1 - y0 + 1 do
    local row = {}
    for i = 1, CANVAS * 4 do
      row[i] = 0
    end
    clear[y] = row
  end
  BadgeArt.draw(clear, y0, CANVAS, badge, text)
  return clear, y0
end

--- @param rows integer[][]
--- @return integer count The pixels with any paint, by their alpha.
local function painted(rows)
  local count = 0
  for _, row in ipairs(rows) do
    for i = 4, #row, 4 do
      if row[i] > 0 then
        count = count + 1
      end
    end
  end
  return count
end

T.section("The badge's art")
local badge = placed("Top Right", 100)
local art = drawnOnClear(badge, "62%")
local middle = art[math.floor(#art / 2)]
local right = CANVAS - 20
T.eq("the pill is its color, in its last column", { middle[right * 4 + 1], middle[right * 4 + 4] }, { 220, 255 })
local noFill = placed("Top Right", 100)
noFill.background = "None"
local textOnly = drawnOnClear(noFill, "62%")
T.truthy("without a background only the text paints", painted(textOnly) > 0 and painted(textOnly) < painted(art) / 2)
T.truthy("and more text paints more", painted(drawnOnClear(noFill, "88888")) > painted(textOnly))
T.eq("a character the face hasn't draws nothing", painted(drawnOnClear(noFill, "\226\130\172")), 0)
local degree = drawnOnClear(noFill, "\194\176")
T.truthy("a two-byte character the face has draws", painted(degree) > 0)

local wide = placed("Under", 150)
local wideRows = drawnOnClear(wide, "WWWWW")
local leftmost, rightmost = CANVAS, 0
for _, row in ipairs(wideRows) do
  for x = 0, CANVAS - 1 do
    if row[x * 4 + 4] > 0 then
      leftmost, rightmost = math.min(leftmost, x), math.max(rightmost, x)
    end
  end
end
T.truthy("the widest text at the largest size stays inside the picture", leftmost > 0 and rightmost < CANVAS - 1)

T.section("On a real redraw")
local big = testPng(CANVAS)
local y0, y1 = BadgeArt.rows(badge, CANVAS)
local forBadge = assert(Png.setup(big, y0, y1))
local badgeRows = Png.rows(forBadge)
BadgeArt.draw(badgeRows, y0, CANVAS, badge, "12.3W")
local finished, whyFinished = decode(Png.splice(forBadge, badgeRows))
T.truthy("the finished picture decodes: " .. tostring(whyFinished), finished ~= nil)
if finished then
  local x, y = firstWrong(finished, CANVAS, function(_, py)
    if py >= y0 and py <= y1 then
      return 0, 0, 0, 0
    end
  end)
  T.truthy("rows outside the badge's aren't touched", x ~= nil and y >= y0 and y <= y1)
  local outside = true
  for py = 0, CANVAS - 1 do
    if py < y0 or py > y1 then
      for px = 0, CANVAS - 1 do
        local r, g, b, a = pixel(px, py)
        local row, i = finished[py + 1], px * 4 + 1
        outside = outside and row[i] == r and row[i + 1] == g and row[i + 2] == b and row[i + 3] == a
      end
    end
  end
  T.truthy("not one of them", outside)
end

T.finish()
