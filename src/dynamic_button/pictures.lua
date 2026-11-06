-- The button's own pictures: files, pasted SVG and pictures from web addresses added in the Button
-- tab, kept in the button's storage so a look can be drawn from one again. A look names its picture
-- by id; a picture no look names is deleted.

local log = require("lib.logging")
local Images = require("dynamic_button.images")

--- @class Picture
--- @field id string `mine:p<n>`, unique for the life of the button.
--- @field kind string One of `png`, `jpeg`, `svg`.
--- @field width number Its width, in pixels or its view box's units.
--- @field height number Its height, in pixels or its view box's units.
--- @field bytes integer
--- @field name string Its file name or web address.
--- @field added number When it was added, in seconds.

--- @class Pictures
--- @field _store table The persist store the list is kept in.
--- @field _used fun(): table<string, boolean> The ids the looks name.
--- @field _now fun(): number The clock, in seconds.
local Pictures = {}
Pictures.__index = Pictures

--- The most pictures a button keeps.
Pictures.MAX = 24

--- The largest picture kept, in bytes: the Button tab sends a file at most 600 px on its long side.
Pictures.MAX_BYTES = Images.MAX_BYTES

--- The largest SVG kept, in bytes.
Pictures.MAX_SVG_BYTES = 64 * 1024

--- The largest picture fetched from a web address, in bytes.
Pictures.MAX_FETCH = 2 * 1024 * 1024

--- The longest web address fetched, in bytes.
Pictures.MAX_ADDRESS = 2048

--- A picture no look names is kept this long after it was added, in seconds: the look saving it
--- comes after it.
Pictures.GRACE_SECONDS = 600

--- The longest name kept, in characters.
local MAX_NAME = 300
local DIR = "pictures"
local PERSIST_KEY = "Pictures"
local EXTENSIONS = { png = "png", jpeg = "jpg", svg = "svg" }

--- @param opts { store: table, used: fun(): table<string, boolean>, now?: fun(): number }
--- @return Pictures pictures
function Pictures:new(opts)
  local instance = setmetatable({}, self)
  instance._store = opts.store
  instance._used = opts.used
  instance._now = opts.now or os.time
  return instance
end

--- @param data string
--- @return boolean svg Whether the data is SVG markup: its root element is svg, after any XML
--- declaration, comments and doctype.
local function isSvg(data)
  if data:find("\0", 1, true) then
    return false
  end
  local head = data:sub(1, 4096):gsub("^\239\187\191", "")
  local pos = 1
  while true do
    pos = head:match("^%s*()", pos)
    local close
    if head:sub(pos, pos + 1) == "<?" then
      close = select(2, head:find("?>", pos + 2, true))
    elseif head:sub(pos, pos + 3) == "<!--" then
      close = select(2, head:find("-->", pos + 4, true))
    elseif head:sub(pos, pos + 8):upper() == "<!DOCTYPE" then
      local subset, gt = head:find("[", pos, true), head:find(">", pos, true)
      if subset and gt and subset < gt then
        local ends = head:find("]", subset, true)
        gt = ends and head:find(">", ends, true)
      end
      close = gt
    else
      return head:match("^<svg[%s>/]", pos) ~= nil
    end
    if not close then
      return false
    end
    pos = close + 1
  end
end

--- What a stored picture is, from its first bytes.
--- @param data string
--- @return string|nil kind `png`, `jpeg` or `svg`; nil for anything else.
function Pictures.kindOf(data)
  if type(data) ~= "string" then
    return nil
  end
  if data:sub(1, 8) == "\137PNG\r\n\26\n" then
    return "png"
  end
  if data:sub(1, 3) == "\255\216\255" then
    return "jpeg"
  end
  if isSvg(data) then
    return "svg"
  end
  return nil
end

--- What a fetched picture is: the Button tab draws any of these and stores it as PNG or JPEG.
--- @param data string
--- @return string|nil kind `png`, `jpeg`, `gif`, `webp` or `svg`; nil for anything else.
function Pictures.fetchedKind(data)
  local kind = Pictures.kindOf(data)
  if kind then
    return kind
  end
  if type(data) ~= "string" then
    return nil
  end
  local head = data:sub(1, 6)
  if head == "GIF87a" or head == "GIF89a" then
    return "gif"
  end
  if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
    return "webp"
  end
  return nil
end

--- How long each fetch may take, in seconds: a redirect handed back starts a new one.
Pictures.FETCH_SECONDS = 20

--- The most redirects followed when the controller hands one back unfollowed.
local MAX_HOPS = 5

local TOO_LARGE = "The picture at that address is larger than 2 MB."
local NOT_A_PICTURE = "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."

--- A name to keep: a web address is cut to its last part, so no login, query or token in it is kept.
--- @param raw any
--- @return string name
function Pictures.safeName(raw)
  local name = tostring(raw or ""):match("^%s*(.-)%s*$")
  local rest = name:match("^%a[%w+.-]*://(.*)$")
  if not rest then
    return name
  end
  local authority, path = rest:match("^([^/?#]*)(.*)$")
  local last = path:gsub("[?#].*$", ""):match("([^/]+)/*$")
  return last or (authority:gsub("^.*@", ""):gsub(":%d*$", ""))
end

--- A web address the controller fetches: http or https, with no spaces.
--- @param raw any
--- @return string|nil address
--- @return string|nil err
function Pictures.checkAddress(raw)
  local address = tostring(raw or ""):match("^%s*(.-)%s*$")
  if #address > Pictures.MAX_ADDRESS then
    return nil, "That address is too long."
  end
  if not address:lower():match("^https?://[^%s/][^%s]*$") then
    return nil, "Enter an http or https address."
  end
  return address
end

--- A fetched body the Button tab can draw.
--- @param body any
--- @return string|nil err Why it's refused, as the Button tab shows it.
function Pictures.checkFetched(body)
  if type(body) ~= "string" or not Pictures.fetchedKind(body) then
    return NOT_A_PICTURE
  end
  if #body > Pictures.MAX_FETCH then
    return TOO_LARGE
  end
  return nil
end

--- A failed fetch, as the Button tab shows it.
--- @param failure any The HTTP library's rejection.
--- @return string err
function Pictures.fetchError(failure)
  local code = tonumber(type(failure) == "table" and failure.code or nil)
  if code and code > 0 then
    return string.format("The address answered with status %d.", code)
  end
  return "The controller couldn't reach that address."
end

--- @param headers any
--- @param name string
--- @return string|nil value The header's value, whatever case the server wrote its name in.
local function header(headers, name)
  if type(headers) ~= "table" then
    return nil
  end
  name = name:lower()
  for key, value in pairs(headers) do
    if type(key) == "string" and key:lower() == name then
      return tostring(type(value) == "table" and value[#value] or value)
    end
  end
  return nil
end

--- @param code any
--- @return boolean passing A response on the way to the answer: a redirect or an interim response.
local function passing(code)
  code = tonumber(code) or 0
  return code < 200 or (code >= 300 and code < 400)
end

--- Where a redirect points, from the address it came from.
--- @param base string
--- @param location any
--- @return string|nil address
function Pictures.resolve(base, location)
  location = tostring(location or ""):match("^%s*(.-)%s*$")
  if location == "" then
    return nil
  end
  if location:lower():match("^https?://") then
    return location
  end
  local scheme, authority, path = base:match("^(%a[%w+.-]*:)//([^/?#]*)([^?#]*)")
  if not scheme then
    return nil
  end
  if location:sub(1, 2) == "//" then
    return scheme .. location
  end
  if location:sub(1, 1) == "/" then
    return scheme .. "//" .. authority .. location
  end
  return scheme .. "//" .. authority .. (path:match("^(.*/)") or "/") .. location
end

--- Fetch a picture for the Button tab. What can't be a picture is refused as soon as the answer
--- shows it: a status, a length over `MAX_FETCH` or a page or stream by its headers, and a body that
--- grows past `MAX_FETCH` while it arrives, so nothing large is held on the controller.
--- @param address string
--- @param done fun(body: string|nil, err: string|nil)
--- @param hops? integer Redirects followed so far (optional).
function Pictures.fetch(address, done, hops)
  hops = hops or 0
  local parts, bytes, refused = {}, 0, nil
  C4:url()
    :SetOptions({ fail_on_error = false, timeout = Pictures.FETCH_SECONDS, connect_timeout = 10 })
    :OnHeaders(function(_, response)
      parts, bytes = {}, 0
      if passing(response.code) then
        return false
      end
      local code = tonumber(response.code) or 0
      local length = tonumber(header(response.headers, "Content-Length"))
      local kind = (header(response.headers, "Content-Type") or ""):lower()
      if code >= 400 then
        refused = Pictures.fetchError({ code = code })
      elseif length and length > Pictures.MAX_FETCH then
        refused = TOO_LARGE
      elseif kind:match("^%s*multipart/") or kind:match("^%s*text/html") then
        refused = NOT_A_PICTURE
      end
      return refused ~= nil
    end)
    :OnBodyChunk(function(_, response, chunk)
      if passing(response.code) then
        return false
      end
      bytes = bytes + #chunk
      if bytes > Pictures.MAX_FETCH then
        refused, parts = TOO_LARGE, {}
        return true
      end
      table.insert(parts, chunk)
      return false
    end)
    :OnDone(function(_, responses, errCode, errMsg)
      if refused then
        return done(nil, refused)
      end
      if tonumber(errCode) ~= 0 then
        log:debug("A picture's fetch ended with error %s: %s", tostring(errCode), tostring(errMsg))
        return done(nil, tonumber(errCode) == 28 and "The address took too long to answer." or Pictures.fetchError(nil))
      end
      local final = type(responses) == "table" and responses[#responses] or nil
      if final and passing(final.code) then
        local nextAddress = hops < MAX_HOPS and Pictures.resolve(address, header(final.headers, "Location"))
        if not (nextAddress and Pictures.checkAddress(nextAddress)) then
          return done(nil, Pictures.fetchError({ code = final.code }))
        end
        return Pictures.fetch(nextAddress, done, hops + 1)
      end
      local body = table.concat(parts)
      local bad = Pictures.checkFetched(body)
      if bad then
        return done(nil, bad)
      end
      done(body)
    end)
    :Get(address, { ["User-Agent"] = "Control4" })
end

--- @private
--- @return { nextId: integer, list: Picture[] } data
function Pictures:_load()
  local data = self._store:get(PERSIST_KEY)
  if type(data) ~= "table" or type(data.list) ~= "table" then
    data = { nextId = 1, list = {} }
  end
  data.nextId = tonumber(data.nextId) or 1
  return data
end

--- @private
--- @param data { nextId: integer, list: Picture[] }
function Pictures:_save(data)
  self._store:set(PERSIST_KEY, data)
end

--- @param picture Picture
--- @return string name Its file in the button's storage.
local function fileName(picture)
  return string.format("%s.%s", picture.id:match("^mine:(.+)$"), EXTENSIONS[picture.kind] or "bin")
end

--- The pictures, oldest first.
--- @return Picture[] list
function Pictures:list()
  return self:_load().list
end

--- @param id any
--- @return Picture|nil picture
function Pictures:get(id)
  id = tostring(id or "")
  for _, picture in ipairs(self:list()) do
    if picture.id == id then
      return picture
    end
  end
  return nil
end

--- @param value any
--- @return number|nil size A picture's side: positive and no larger than any picture is.
local function side(value)
  local n = tonumber(value)
  if not n or n ~= n or n <= 0 or n > 100000 then
    return nil
  end
  return n
end

--- Keep a new picture.
--- @param data string The picture: PNG, JPEG or SVG.
--- @param fields { width: any, height: any, name: any } How the Button tab measured and named it.
--- @return Picture|nil picture
--- @return string|nil err Why it was refused.
function Pictures:add(data, fields)
  local kind = Pictures.kindOf(data)
  if not kind then
    return nil, "the picture is not a PNG, JPEG or SVG"
  end
  if #data > Pictures.MAX_BYTES or (kind == "svg" and #data > Pictures.MAX_SVG_BYTES) then
    return nil,
      string.format(
        "the picture is larger than %d KB",
        (kind == "svg" and Pictures.MAX_SVG_BYTES or Pictures.MAX_BYTES) / 1024
      )
  end
  fields = type(fields) == "table" and fields or {}
  local width, height = side(fields.width), side(fields.height)
  if not width or not height then
    return nil, "the picture's size is missing"
  end
  self:collect()
  local list = self:_load()
  if #list.list >= Pictures.MAX then
    return nil, string.format("a button keeps at most %d pictures", Pictures.MAX)
  end
  local name = Pictures.safeName(fields.name)
  local picture = {
    id = string.format("mine:p%d", list.nextId),
    kind = kind,
    width = width,
    height = height,
    bytes = #data,
    name = name ~= "" and name:sub(1, MAX_NAME) or "Picture",
    added = self._now(),
  }
  C4:FileCreateDir("SANDBOX", DIR)
  if not Images.writeFile("SANDBOX", DIR, fileName(picture), data) then
    return nil, "the controller could not store the picture"
  end
  list.nextId = list.nextId + 1
  table.insert(list.list, picture)
  self:_save(list)
  log:debug("Kept picture %s, a %s of %d bytes", picture.id, picture.kind, picture.bytes)
  return picture
end

--- @param id any
--- @return string|nil data The picture's bytes.
function Pictures:load(id)
  local picture = self:get(id)
  return picture and Images.readFile("SANDBOX", DIR, fileName(picture)) or nil
end

--- Delete the pictures no look names, except ones added in the last `GRACE_SECONDS`.
function Pictures:collect()
  local data, used, now = self:_load(), self._used(), self._now()
  local kept = {}
  for _, picture in ipairs(data.list) do
    if used[picture.id] or now - (tonumber(picture.added) or 0) < Pictures.GRACE_SECONDS then
      table.insert(kept, picture)
    else
      Images.deleteFile("SANDBOX", DIR, fileName(picture))
      log:debug("Deleted picture %s, which no look uses", picture.id)
    end
  end
  if #kept ~= #data.list then
    data.list = kept
    self:_save(data)
  end
end

--- Delete every picture. Ids go on from where they were.
function Pictures:clear()
  local data = self:_load()
  for _, picture in ipairs(data.list) do
    Images.deleteFile("SANDBOX", DIR, fileName(picture))
  end
  self:_save({ nextId = data.nextId, list = {} })
end

return Pictures
