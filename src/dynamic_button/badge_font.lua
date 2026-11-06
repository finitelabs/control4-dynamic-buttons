-- The face a live badge is drawn in on the controller, from outlines: the Button tab's Roboto Bold,
-- so a live badge matches a badge the tab draws. Each glyph is rasterized by its exact area coverage.

local OUTLINES = require("dynamic_button.badge_font_data")

local ceil, floor, sqrt, min, max = math.ceil, math.floor, math.sqrt, math.min, math.max

local BadgeFont = {}

--- Font units in one em.
local UNITS = 2048

--- Canvas text renders heavier than plain coverage; this curve brings the weight close.
local WEIGHT = {}
for i = 0, 255 do
  WEIGHT[i] = floor((i / 255) ^ 0.7 * 255 + 0.5)
end

--- @type table<integer, { advance: integer, contours: number[][] }>|nil
local glyphs = nil

--- @param data string The packed outlines, as tools/badge_font.py writes them.
--- @return table<integer, { advance: integer, contours: number[][] }> glyphs By character code.
local function parseOutlines(data)
  local at, parsed = 1, {}
  local function varint()
    local value, scale = 0, 1
    while true do
      local b = data:byte(at)
      at = at + 1
      value = value + (b % 128) * scale
      if b < 128 then
        return value
      end
      scale = scale * 128
    end
  end
  local quantum = varint()
  while at <= #data do
    local code, advance, count = varint(), varint(), varint()
    local contours, x, y = {}, 0, 0
    for c = 1, count do
      local points = {}
      for i = 1, varint() do
        local a, b = varint(), varint()
        local onCurve = a % 2
        a = (a - onCurve) / 2
        x = x + (a % 2 == 1 and -(a + 1) / 2 or a / 2)
        y = y + (b % 2 == 1 and -(b + 1) / 2 or b / 2)
        points[i * 3 - 2], points[i * 3 - 1], points[i * 3] = x * quantum, y * quantum, onCurve
      end
      contours[c] = points
    end
    parsed[code] = { advance = advance, contours = contours }
  end
  return parsed
end

--- @return table<integer, { advance: integer, contours: number[][] }> glyphs
local function font()
  if not glyphs then
    glyphs = parseOutlines(C4:Base64Decode(OUTLINES))
  end
  return glyphs
end

--- Add one edge to the running area and coverage totals.
--- @param totals number[]
--- @param width integer
--- @param height integer
--- @param x0 number
--- @param y0 number
--- @param x1 number
--- @param y1 number
local function addLine(totals, width, height, x0, y0, x1, y1)
  if y0 == y1 then
    return
  end
  local direction = 1
  if y0 > y1 then
    x0, y0, x1, y1 = x1, y1, x0, y0
    direction = -1
  end
  local slope = (x1 - x0) / (y1 - y0)
  local x = x0
  for y = floor(y0), min(height, ceil(y1)) - 1 do
    local base = y * width
    local dy = min(y + 1, y1) - max(y, y0)
    local nextX = x + slope * dy
    local d = dy * direction
    local xa, xb = x, nextX
    if xa > xb then
      xa, xb = xb, xa
    end
    local left = floor(xa)
    local right = ceil(xb)
    if right <= left + 1 then
      local m = 0.5 * (x + nextX) - left
      totals[base + left] = totals[base + left] + d - d * m
      totals[base + left + 1] = totals[base + left + 1] + d * m
    else
      local s = 1 / (xb - xa)
      local f0 = xa - left
      local a0 = 0.5 * s * (1 - f0) * (1 - f0)
      local f1 = xb - right + 1
      local am = 0.5 * s * f1 * f1
      totals[base + left] = totals[base + left] + d * a0
      if right == left + 2 then
        totals[base + left + 1] = totals[base + left + 1] + d * (1 - a0 - am)
      else
        local a1 = s * (1.5 - f0)
        totals[base + left + 1] = totals[base + left + 1] + d * (a1 - a0)
        for xi = left + 2, right - 2 do
          totals[base + xi] = totals[base + xi] + d * s
        end
        local a2 = a1 + (right - left - 3) * s
        totals[base + right - 1] = totals[base + right - 1] + d * (1 - a2 - am)
      end
      totals[base + right] = totals[base + right] + d * am
    end
    x = nextX
  end
end

--- @param text string UTF-8.
--- @return integer[] codes The character codes the face has.
--- @return string kept The text with only those characters.
function BadgeFont.characters(text)
  local codes, kept = {}, {}
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local first = char:byte(1)
    local code = first
    if first >= 240 then
      code = first % 8
    elseif first >= 224 then
      code = first % 16
    elseif first >= 194 then
      code = first % 32
    end
    for i = 2, #char do
      code = code * 64 + char:byte(i) % 64
    end
    if font()[code] then
      codes[#codes + 1] = code
      kept[#kept + 1] = char
    end
  end
  return codes, table.concat(kept)
end

--- @param code integer A character code.
--- @param fontSize number In pixels.
--- @return number|nil advance How far the character moves the pen, or nil if the face hasn't it.
function BadgeFont.advance(code, fontSize)
  local glyph = font()[code]
  return glyph and glyph.advance * fontSize / UNITS or nil
end

--- One character's coverage at a pen position.
--- @param code integer A character code the face has.
--- @param fontSize number In pixels.
--- @param pen number The pen's x.
--- @param base number The baseline's y.
--- @return integer x The coverage's left pixel.
--- @return integer y Its top pixel.
--- @return integer width
--- @return integer height
--- @return integer[] coverage 0 to 255, by row.
function BadgeFont.glyph(code, fontSize, pen, base)
  local glyph = font()[code]
  local penX, baseY = floor(pen), floor(base + 0.5)
  local fraction = pen - penX
  local scale = fontSize / UNITS
  local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
  for _, points in ipairs(glyph.contours) do
    for i = 1, #points, 3 do
      local px, py = points[i] * scale + fraction, -points[i + 1] * scale
      minX, maxX = min(minX, px), max(maxX, px)
      minY, maxY = min(minY, py), max(maxY, py)
    end
  end
  if minX > maxX then
    return penX, baseY, 0, 0, {}
  end
  local originX, originY = floor(minX), floor(minY)
  local width, height = ceil(maxX) - originX + 1, ceil(maxY) - originY + 1
  local totals = {}
  for i = 0, width * height + 1 do
    totals[i] = 0
  end
  for _, points in ipairs(glyph.contours) do
    local count = #points / 3
    local function X(i)
      return points[(i - 1) % count * 3 + 1] * scale + fraction - originX
    end
    local function Y(i)
      return -points[(i - 1) % count * 3 + 2] * scale - originY
    end
    local function on(i)
      return points[(i - 1) % count * 3 + 3] == 1
    end
    -- A contour starts on an on-curve point, or the midpoint of two off-curve ones.
    local first, startX, startY = 1, nil, nil
    if on(1) then
      startX, startY = X(1), Y(1)
    elseif on(count) then
      first, startX, startY = count, X(count), Y(count)
    else
      first, startX, startY = count, (X(count) + X(1)) / 2, (Y(count) + Y(1)) / 2
    end
    local cx, cy = startX, startY
    local i, stop = first + 1, first + count
    while i <= stop do
      if on(i) then
        local nx, ny = X(i), Y(i)
        addLine(totals, width, height, cx, cy, nx, ny)
        cx, cy = nx, ny
        i = i + 1
      else
        local qx, qy = X(i), Y(i)
        local nx, ny
        if i == stop then
          nx, ny = startX, startY
        elseif on(i + 1) then
          nx, ny = X(i + 1), Y(i + 1)
        else
          nx, ny = (qx + X(i + 1)) / 2, (qy + Y(i + 1)) / 2
        end
        local ddx, ddy = cx - 2 * qx + nx, cy - 2 * qy + ny
        local steps = max(1, ceil(sqrt(sqrt(ddx * ddx + ddy * ddy) * 2.5)))
        local lx, ly = cx, cy
        for step = 1, steps do
          local t = step / steps
          local u = 1 - t
          local mx = u * u * cx + 2 * u * t * qx + t * t * nx
          local my = u * u * cy + 2 * u * t * qy + t * t * ny
          addLine(totals, width, height, lx, ly, mx, my)
          lx, ly = mx, my
        end
        cx, cy = nx, ny
        i = (i == stop or on(i + 1)) and i + 2 or i + 1
      end
    end
    if cx ~= startX or cy ~= startY then
      addLine(totals, width, height, cx, cy, startX, startY)
    end
  end
  local coverage, running = {}, 0
  for i = 0, width * height - 1 do
    running = running + totals[i]
    local value = running < 0 and -running or running
    coverage[i + 1] = WEIGHT[floor(min(value, 1) * 255 + 0.5)]
  end
  return penX + originX, baseY + originY, width, height, coverage
end

return BadgeFont
