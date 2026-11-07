-- A look's stored PNG, prepared so a badge can be redrawn without compressing the whole picture
-- again: the rows above and below the badge stay compressed, and only the badge's rows are redone.

-- LuaJIT's own bit, not bitn: bitn's masked calls make this CRC about 7 times slower with JIT off.
local bit = require("bit")
local LibDeflate = require("LibDeflate")

local band, bxor, rshift = bit.band, bit.bxor, bit.rshift
local byte, char, sub, concat = string.byte, string.char, string.sub, table.concat
local abs, floor, min = math.abs, math.floor, math.min

--- @class PngCache
--- @field width integer
--- @field height integer
--- @field y0 integer The first row the badge can touch, from 0.
--- @field y1 integer The last row the badge can touch.
--- @field head string The file up to the end of the compressed rows above the badge.
--- @field tail string The compressed rows below the badge, as a chunk.
--- @field mid string The badge's rows as plain pixels.
--- @field adlerA integer The checksum of the rows above, first half.
--- @field adlerB integer The checksum of the rows above, second half.
--- @field tailA integer The checksum of the rows below, first half.
--- @field tailB integer The checksum of the rows below, second half.
--- @field tailBytes integer The size of the rows below, uncompressed.

local Png = {}

local SIGNATURE = "\137PNG\r\n\26\n"
local LEVEL = 1
--- Compressed in pieces, since LibDeflate's result must be one block to be joined to what follows.
local PIECE = 60000
--- Wider than a look's picture is, and a row's bytes must fit in one function call's arguments.
local MAX_WIDTH = 1024

local CRC = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    if band(c, 1) == 1 then
      c = bxor(0xEDB88320, rshift(c, 1))
    else
      c = rshift(c, 1)
    end
  end
  CRC[n] = c
end

--- The CRC-32 a PNG chunk carries.
--- @param data string
--- @return integer crc The data's CRC-32, 0 to 2^32 - 1.
function Png.crc32(data)
  local c = -1
  for i = 1, #data do
    c = bxor(CRC[band(bxor(c, byte(data, i)), 255)], rshift(c, 8))
  end
  c = bxor(c, -1)
  return c < 0 and c + 4294967296 or c
end

--- @param value integer
--- @return string bytes Big-endian.
local function u32(value)
  return char(floor(value / 16777216) % 256, floor(value / 65536) % 256, floor(value / 256) % 256, value % 256)
end

--- @param data string
--- @param at integer
--- @return integer value
local function readU32(data, at)
  local a, b, c, d = byte(data, at, at + 3)
  return a * 16777216 + b * 65536 + c * 256 + d
end

--- @param kind string
--- @param data string
--- @return string chunk
local function chunk(kind, data)
  return u32(#data) .. kind .. data .. u32(Png.crc32(kind .. data))
end

--- @param png string
--- @return table parsed The header's bytes and size, and the joined compressed data.
local function parse(png)
  if sub(png, 1, 8) ~= SIGNATURE then
    error("not a PNG file", 0)
  end
  local at, compressed, width, height, header = 9, {}, nil, nil, nil
  while at <= #png do
    local length, kind = readU32(png, at), sub(png, at + 4, at + 7)
    if kind == "IHDR" then
      header = sub(png, at + 8, at + 7 + length)
      width, height = readU32(header, 1), readU32(header, 5)
      local depth, color, compression, filter, interlace = byte(header, 9, 13)
      if depth ~= 8 or color ~= 6 then
        error("only 8-bit RGBA pictures are supported", 0)
      end
      if compression ~= 0 or filter ~= 0 or interlace ~= 0 then
        error("interlaced pictures are not supported", 0)
      end
      if width > MAX_WIDTH then
        error("the picture is too wide", 0)
      end
    elseif kind == "IDAT" then
      compressed[#compressed + 1] = sub(png, at + 8, at + 7 + length)
    elseif kind == "IEND" then
      break
    elseif byte(kind, 1) < 97 then
      error("unsupported chunk " .. kind, 0)
    end
    at = at + 12 + length
  end
  if not header or #compressed == 0 then
    error("the picture has no pixels", 0)
  end
  return { width = width, height = height, header = header, compressed = concat(compressed) }
end

--- Filtered rows to pixel rows, from the top down to `last`.
--- @param raw string The decompressed rows.
--- @param width integer
--- @param last integer The last row wanted, from 0.
--- @return integer[][] rows Each row's bytes.
local function unfilter(raw, width, last)
  local n = width * 4
  local rows, previous = {}, {}
  for i = 1, n do
    previous[i] = 0
  end
  for y = 0, last do
    local at = y * (n + 1) + 1
    local filter = byte(raw, at)
    local current = { byte(raw, at + 1, at + n) }
    if filter == 2 then
      for i = 1, n do
        local value = current[i] + previous[i]
        current[i] = value > 255 and value - 256 or value
      end
    elseif filter == 1 then
      for i = 5, n do
        local value = current[i] + current[i - 4]
        current[i] = value > 255 and value - 256 or value
      end
    elseif filter == 3 then
      for i = 1, n do
        local left = i > 4 and current[i - 4] or 0
        current[i] = (current[i] + floor((left + previous[i]) / 2)) % 256
      end
    elseif filter == 4 then
      for i = 1, n do
        local a, b, c = i > 4 and current[i - 4] or 0, previous[i], i > 4 and previous[i - 4] or 0
        local p = a + b - c
        local pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        local nearest = (pa <= pb and pa <= pc) and a or (pb <= pc and b or c)
        current[i] = (current[i] + nearest) % 256
      end
    elseif filter ~= 0 then
      error("unknown row filter " .. tostring(filter), 0)
    end
    rows[y + 1] = current
    previous = current
  end
  return rows
end

--- One row as PNG's Sub filter (no row above) or Up filter stores it, with its filter byte.
--- @param current integer[]
--- @param above integer[]|nil The row above, or nil for Sub.
--- @param n integer The row's bytes.
--- @return string row
local function filterRow(current, above, n)
  local filtered = {}
  if above then
    for i = 1, n do
      local value = current[i] - above[i]
      filtered[i] = value < 0 and value + 256 or value
    end
  else
    for i = 1, 4 do
      filtered[i] = current[i]
    end
    for i = 5, n do
      local value = current[i] - current[i - 4]
      filtered[i] = value < 0 and value + 256 or value
    end
  end
  return char(above and 2 or 1, unpack(filtered, 1, n))
end

--- A deflate block made to run on into what follows: not final, and ended on a byte boundary.
--- @param compressed string One block from LibDeflate.
--- @param padding integer The unused bits in its last byte.
--- @return string block
local function openBlock(compressed, padding)
  local n = #compressed
  local first, last = byte(compressed, 1), byte(compressed, n)
  first = first - first % 2
  local keep = 2 ^ (8 - padding)
  local marker = padding >= 3 and "\0\0\255\255" or "\0\0\0\255\255"
  if n == 1 then
    return char(first % keep) .. marker
  end
  return char(first) .. sub(compressed, 2, n - 1) .. char(last % keep) .. marker
end

--- @param data string
--- @param final boolean Whether the zlib stream ends with this data.
--- @return string blocks
local function deflate(data, final)
  local out, n, i = {}, #data, 1
  while i <= n do
    local j = min(n, i + PIECE - 1)
    local compressed, padding = LibDeflate:CompressDeflate(sub(data, i, j), { level = LEVEL })
    out[#out + 1] = (final and j == n) and compressed or openBlock(compressed, padding)
    i = j + 1
  end
  if n == 0 and final then
    out[1] = "\1\0\0\255\255"
  end
  return concat(out)
end

--- @param data string
--- @return integer a
--- @return integer b
local function adlerParts(data)
  if #data == 0 then
    return 1, 0
  end
  local value = LibDeflate:Adler32(data)
  return value % 65536, floor(value / 65536)
end

--- @param a1 integer
--- @param b1 integer
--- @param a2 integer
--- @param b2 integer
--- @param length2 integer The second part's size.
--- @return integer a
--- @return integer b
local function adlerJoin(a1, b1, a2, b2, length2)
  return (a1 + a2 - 1) % 65521, (b1 + b2 + (length2 % 65521) * (a1 - 1)) % 65521
end

--- A PNG's width and height, from its header.
--- @param png string
--- @return integer|nil width
--- @return integer|nil height
function Png.size(png)
  if sub(png, 1, 8) ~= SIGNATURE or #png < 24 then
    return nil
  end
  return readU32(png, 17), readU32(png, 21)
end

--- @param png string
--- @param y0 integer The first row the badge can touch, from 0.
--- @param y1 integer The last row it can touch.
--- @return PngCache cache
local function prepare(png, y0, y1)
  local parsed = parse(png)
  local raw = LibDeflate:DecompressZlib(parsed.compressed)
  local n = parsed.width * 4
  local stride = n + 1
  if not raw or #raw ~= stride * parsed.height then
    error("the picture's data did not decode", 0)
  end
  y1 = min(y1, parsed.height - 1)
  local rows = unfilter(raw, parsed.width, min(y1 + 1, parsed.height - 1))
  local above = sub(raw, 1, y0 * stride)
  -- The row below the badge can't keep a filter that reads the badge's last row.
  local below = {}
  if y1 + 1 < parsed.height then
    below[1] = filterRow(rows[y1 + 2], nil, n)
  end
  if y1 + 2 < parsed.height then
    below[2] = sub(raw, (y1 + 2) * stride + 1)
  end
  local tail = concat(below)
  local mid = {}
  for y = y0, y1 do
    mid[#mid + 1] = char(unpack(rows[y + 1], 1, n))
  end
  local adlerA, adlerB = adlerParts(above)
  local tailA, tailB = adlerParts(tail)
  return {
    width = parsed.width,
    height = parsed.height,
    y0 = y0,
    y1 = y1,
    head = SIGNATURE .. chunk("IHDR", parsed.header) .. chunk("IDAT", "\120\1" .. deflate(above, false)),
    tail = chunk("IDAT", deflate(tail, true)),
    mid = concat(mid),
    adlerA = adlerA,
    adlerB = adlerB,
    tailA = tailA,
    tailB = tailB,
    tailBytes = #tail,
  }
end

--- The one-time work for one picture and one badge's rows.
--- @param png string
--- @param y0 integer The first row the badge can touch, from 0.
--- @param y1 integer The last row it can touch.
--- @return PngCache|nil cache
--- @return string|nil err Why the picture can't take a badge.
function Png.setup(png, y0, y1)
  local ok, result = pcall(prepare, png, y0, y1)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

--- A cache as a string to keep in a file.
--- @param cache PngCache
--- @return string data To keep in a file.
function Png.pack(cache)
  local numbers = {
    cache.width,
    cache.height,
    cache.y0,
    cache.y1,
    cache.adlerA,
    cache.adlerB,
    cache.tailA,
    cache.tailB,
    cache.tailBytes,
    #cache.head,
    #cache.tail,
    #cache.mid,
  }
  return concat(numbers, " ") .. "\n" .. cache.head .. cache.tail .. cache.mid
end

--- A cache from what `Png.pack` made.
--- @param data string What `Png.pack` returned.
--- @return PngCache|nil cache Nil if the data isn't that.
function Png.unpack(data)
  local lineEnd = string.find(data, "\n", 1, true)
  if not lineEnd then
    return nil
  end
  local v = {}
  for number in string.gmatch(sub(data, 1, lineEnd - 1), "%d+") do
    v[#v + 1] = tonumber(number)
  end
  if #v ~= 12 or #data ~= lineEnd + v[10] + v[11] + v[12] then
    return nil
  end
  local at = lineEnd + 1
  return {
    width = v[1],
    height = v[2],
    y0 = v[3],
    y1 = v[4],
    adlerA = v[5],
    adlerB = v[6],
    tailA = v[7],
    tailB = v[8],
    tailBytes = v[9],
    head = sub(data, at, at + v[10] - 1),
    tail = sub(data, at + v[10], at + v[10] + v[11] - 1),
    mid = sub(data, at + v[10] + v[11]),
  }
end

--- The badge rows of a cache, to draw on.
--- @param cache PngCache
--- @return integer[][] rows The badge's rows as bytes, to draw on.
function Png.rows(cache)
  local n, rows = cache.width * 4, {}
  for y = 0, cache.y1 - cache.y0 do
    rows[y + 1] = { byte(cache.mid, y * n + 1, y * n + n) }
  end
  return rows
end

--- The finished picture, with the badge's rows as drawn.
--- @param cache PngCache
--- @param rows integer[][] What `Png.rows` returned, drawn on.
--- @return string png
function Png.splice(cache, rows)
  local n, filtered = cache.width * 4, {}
  for i = 1, #rows do
    filtered[i] = filterRow(rows[i], rows[i - 1], n)
  end
  local mid = concat(filtered)
  local midA, midB = adlerParts(mid)
  local a, b = adlerJoin(cache.adlerA, cache.adlerB, midA, midB, #mid)
  a, b = adlerJoin(a, b, cache.tailA, cache.tailB, cache.tailBytes)
  return concat({
    cache.head,
    chunk("IDAT", deflate(mid, false)),
    cache.tail,
    chunk("IDAT", u32(b * 65536 + a)),
    chunk("IEND", ""),
  })
end

return Png
