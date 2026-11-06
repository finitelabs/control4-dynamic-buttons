-- A badge drawn on a picture's rows: the pill and its text, where the Button tab's drawBadge puts them.

local BadgeFont = require("dynamic_button.badge_font")

local ceil, floor, sqrt, min, max = math.ceil, math.floor, math.sqrt, math.min, math.max

local BadgeArt = {}

--- Sub-rows per pixel row when working out the pill's curved ends.
local SUBROWS = 8

--- @param badge LookBadge
--- @param canvas integer The picture's width and height.
--- @return integer height The pill's height.
local function pillHeight(badge, canvas)
  local share = badge.place == "Under" and 0.2 or 0.24
  return floor(canvas * share * (badge.size or 100) / 100 + 0.5)
end

--- @param badge LookBadge
--- @param canvas integer
--- @param width number The pill's width.
--- @param height integer The pill's height.
--- @return number x The pill's left edge.
--- @return number y The pill's top edge.
local function pillAt(badge, canvas, width, height)
  if badge.place == "Top Right" then
    return canvas - width - canvas * 0.03, canvas * 0.03
  elseif badge.place == "Bottom Right" then
    return canvas - width - canvas * 0.03, canvas - height - canvas * 0.03
  end
  return (canvas - width) / 2, canvas - height - canvas * 0.02
end

--- @param badge LookBadge
--- @param canvas integer The picture's width and height.
--- @return integer y0 The first row the badge can touch, from 0.
--- @return integer y1 The last row it can touch.
function BadgeArt.rows(badge, canvas)
  local height = pillHeight(badge, canvas)
  local _, y = pillAt(badge, canvas, 0, height)
  return floor(y), ceil(y + height) - 1
end

--- @param color string `#RRGGBB`.
--- @return integer red
--- @return integer green
--- @return integer blue
local function rgb(color)
  return tonumber(color:sub(2, 3), 16), tonumber(color:sub(4, 5), 16), tonumber(color:sub(6, 7), 16)
end

--- Put a color over one pixel of a row, by how much of the pixel it covers.
--- @param row integer[]
--- @param i integer The pixel's first byte.
--- @param red integer
--- @param green integer
--- @param blue integer
--- @param coverage integer 0 to 255.
local function blend(row, i, red, green, blue, coverage)
  if coverage <= 0 then
    return
  end
  if coverage >= 255 then
    row[i], row[i + 1], row[i + 2], row[i + 3] = red, green, blue, 255
    return
  end
  local alpha = row[i + 3]
  if alpha == 0 then
    row[i], row[i + 1], row[i + 2], row[i + 3] = red, green, blue, coverage
    return
  end
  local keep = alpha * (255 - coverage) / 255
  local total = coverage + keep
  row[i] = floor((red * coverage + row[i] * keep) / total + 0.5)
  row[i + 1] = floor((green * coverage + row[i + 1] * keep) / total + 0.5)
  row[i + 2] = floor((blue * coverage + row[i + 2] * keep) / total + 0.5)
  row[i + 3] = floor(total + 0.5)
end

--- @param rows integer[][]
--- @param firstRow integer The picture row `rows[1]` is.
--- @param canvas integer
--- @param x number
--- @param y number
--- @param width number
--- @param height integer
--- @param color string `#RRGGBB`.
local function fillPill(rows, firstRow, canvas, x, y, width, height, color)
  local radius = height / 2
  local centerY = y + radius
  local red, green, blue = rgb(color)
  for py = floor(y), ceil(y + height) - 1 do
    local row = rows[py - firstRow + 1]
    local lefts, rights, innerLeft, innerRight, outerLeft, outerRight, hits =
      {}, {}, -math.huge, math.huge, math.huge, -math.huge, 0
    for s = 1, SUBROWS do
      local dy = py + (s - 0.5) / SUBROWS - centerY
      local q = radius * radius - dy * dy
      if q > 0 then
        local dx = sqrt(q)
        local left, right = x + radius - dx, x + width - radius + dx
        hits = hits + 1
        lefts[hits], rights[hits] = left, right
        innerLeft, innerRight = max(innerLeft, left), min(innerRight, right)
        outerLeft, outerRight = min(outerLeft, left), max(outerRight, right)
      end
    end
    if row and hits > 0 then
      local solidFrom, solidTo = ceil(innerLeft), floor(innerRight) - 1
      for px = max(0, floor(outerLeft)), min(canvas - 1, ceil(outerRight) - 1) do
        local i = px * 4 + 1
        if px >= solidFrom and px <= solidTo and hits == SUBROWS then
          row[i], row[i + 1], row[i + 2], row[i + 3] = red, green, blue, 255
        else
          local sum = 0
          for k = 1, hits do
            sum = sum + max(0, min(px + 1, rights[k]) - max(px, lefts[k]))
          end
          blend(row, i, red, green, blue, floor(sum / SUBROWS * 255 + 0.5))
        end
      end
    end
  end
end

--- @param text string UTF-8.
--- @return integer[] codes The characters the face has.
local function characters(text)
  local codes = {}
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
    if BadgeFont.advance(code, 1) then
      codes[#codes + 1] = code
    end
  end
  return codes
end

--- @param codes integer[]
--- @param fontSize number
--- @return number width
local function textWidth(codes, fontSize)
  local width = 0
  for _, code in ipairs(codes) do
    width = width + BadgeFont.advance(code, fontSize)
  end
  return width
end

--- Draw a badge on the rows that `BadgeArt.rows` named.
--- @param rows integer[][]
--- @param firstRow integer The picture row `rows[1]` is.
--- @param canvas integer The picture's width and height.
--- @param badge LookBadge Its place, colors and size.
--- @param text string What it says now.
function BadgeArt.draw(rows, firstRow, canvas, badge, text)
  local height = pillHeight(badge, canvas)
  local codes = characters(text)
  local fontSize = floor(height * 0.68 + 0.5)
  local measured = textWidth(codes, fontSize)
  local width = min(canvas * 0.94, max(height, measured + height * 0.7))
  -- Text too long for the widest pill draws smaller, where the tab's canvas squeezes it.
  local room = width - height * 0.3
  if measured > room then
    fontSize = fontSize * room / measured
    measured = textWidth(codes, fontSize)
  end
  local x, y = pillAt(badge, canvas, width, height)
  if badge.background ~= "None" then
    fillPill(rows, firstRow, canvas, x, y, width, height, badge.background)
  end
  local pen = x + width / 2 - measured / 2
  local base = y + height / 2 + height * 0.03 + fontSize * 0.25
  local red, green, blue = rgb(badge.color)
  for _, code in ipairs(codes) do
    local gx, gy, gw, gh, coverage = BadgeFont.glyph(code, fontSize, pen, base)
    for r = 0, gh - 1 do
      local row = rows[gy + r - firstRow + 1]
      if row then
        for c = 0, gw - 1 do
          local px = gx + c
          if px >= 0 and px < canvas then
            blend(row, px * 4 + 1, red, green, blue, coverage[r * gw + c + 1])
          end
        end
      end
    end
    pen = pen + BadgeFont.advance(code, fontSize)
  end
end

return BadgeArt
