-- The button's own pictures: files, pasted SVG and pictures from web addresses added in the Button
-- tab, kept in the button's storage so a look can be drawn from one again. A look names its picture
-- by id; a picture no look names is deleted.

local deferred = require("deferred")
local log = require("lib.logging")
local Images = require("dynamic_button.images")
--#ifdef DRIVERCENTRAL
local diagnostics = require("lib.diagnostics")
--#endif

--- @class Picture
--- @field id string `mine:p<n>`, unique for the life of the button.
--- @field kind string One of `png`, `jpeg`, `svg`.
--- @field width number Its width, in pixels or its view box's units.
--- @field height number Its height, in pixels or its view box's units.
--- @field bytes integer
--- @field name string Its file name, or a web address's last part.
--- @field added number When it was added, in seconds.
--- @field every? integer For a picture that refreshes: how often, in seconds, one of `Pictures.EVERY_SECONDS`.
--- @field source? string For a picture that refreshes: names its bytes, a new one each time they change.
--- @field fetchedAt? number For a picture that refreshes: when its bytes last changed, in seconds.

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

--- How often a picture from a web address can refresh, in seconds.
Pictures.EVERY_SECONDS = { 60, 300, 900, 3600 }

--- A picture no look names is kept this long after it was added, in seconds: the look saving it
--- comes after it.
Pictures.GRACE_SECONDS = 600

--- The longest name kept, in characters.
local MAX_NAME = 300
local DIR = "pictures"
local PICTURES_PERSIST_KEY = "Pictures"
--- Refreshing pictures' web addresses, by id: encrypted, so storage's trace never shows one, since an
--- address can carry a login or a token.
local ADDRESSES_PERSIST_KEY = "PictureAddresses"
local EXTENSIONS = { png = "png", jpeg = "jpg", svg = "svg" }

--- Creates a new instance of the Pictures class.
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

--- How long a fetch waits for the site to accept the connection, in seconds: half the whole fetch, so
--- an address on no reachable host fails while the tab still waits for an answer.
Pictures.CONNECT_SECONDS = 10

--- The most redirects followed when the controller hands one back unfollowed.
local MAX_HOPS = 5

local TOO_LARGE = "The picture at that address is larger than 2 MB."
local NOT_A_PICTURE = "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."

--- The name of a picture whose name would otherwise come from its web address.
Pictures.WEB_NAME = "Web picture"

--- A name to keep: a web address is cut to its last part, so no login, query or token in it is kept,
--- and one with no path is named nothing from the address.
--- @param raw any
--- @return string name
function Pictures.safeName(raw)
  local name = tostring(raw or ""):match("^%s*(.-)%s*$")
  local rest = name:match("^%a[%w+.-]*://(.*)$")
  if not rest then
    return name
  end
  local path = rest:match("^[^/?#]*(.*)$")
  return path:gsub("[?#].*$", ""):match("([^/]+)/*$") or Pictures.WEB_NAME
end

--- @param data string
--- @param at integer
--- @return integer value The big-endian 16-bit number at `at`.
local function be16(data, at)
  local a, b = data:byte(at, at + 1)
  return (a or 0) * 256 + (b or 0)
end

--- A PNG's or JPEG's size in pixels, from its header.
--- @param data string
--- @return integer|nil width
--- @return integer|nil height
function Pictures.dimensions(data)
  local kind = Pictures.kindOf(data)
  if kind == "png" and data:sub(13, 16) == "IHDR" then
    local width, height = be16(data, 17) * 65536 + be16(data, 19), be16(data, 21) * 65536 + be16(data, 23)
    if width > 0 and height > 0 then
      return width, height
    end
  elseif kind == "jpeg" then
    -- The frame header (SOF0 to SOF15, but not DHT, JPG or DAC) carries the size.
    local at = 3
    while at + 8 <= #data do
      if data:byte(at) ~= 0xFF then
        return nil, nil
      end
      local marker = data:byte(at + 1)
      if marker == 0xFF then
        at = at + 1
      elseif marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
        at = at + 2
      else
        if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
          local height, width = be16(data, at + 5), be16(data, at + 7)
          if width > 0 and height > 0 then
            return width, height
          end
          return nil, nil
        end
        at = at + 2 + be16(data, at + 2)
      end
    end
  end
  return nil, nil
end

--- A refresh interval the button takes.
--- @param value any
--- @return integer|nil every One of `Pictures.EVERY_SECONDS`, or nil.
function Pictures.checkEvery(value)
  local n = tonumber(value)
  for _, every in ipairs(Pictures.EVERY_SECONDS) do
    if n == every then
      return every
    end
  end
  return nil
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
--- grows past `MAX_FETCH` while it arrives, so nothing large is held on the controller. A raw
--- `C4:url()`, not `lib.http`: only it can stop a transfer by its headers or mid-body.
--- @param address string
--- @param hops? integer Redirects followed so far (optional).
--- @return Deferred fetched Resolves with the picture's bytes, or rejects with why it was refused.
function Pictures.fetch(address, hops)
  hops = hops or 0
  local d = deferred.new()
  local parts, bytes, refused = {}, 0, nil
  local function onHeaders(_, response)
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
  end
  local function onBodyChunk(_, response, chunk)
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
  end
  local function onDone(_, responses, errCode)
    if refused then
      return d:reject(refused)
    end
    if tonumber(errCode) ~= 0 then
      -- Only the code: curl's message can carry the address's host.
      log:debug("A picture's fetch ended with error %s", tostring(errCode))
      return d:reject(tonumber(errCode) == 28 and "The address took too long to answer." or Pictures.fetchError(nil))
    end
    local final = type(responses) == "table" and responses[#responses] or nil
    if final and passing(final.code) then
      local nextAddress = hops < MAX_HOPS and Pictures.resolve(address, header(final.headers, "Location"))
      if not (nextAddress and Pictures.checkAddress(nextAddress)) then
        return d:reject(Pictures.fetchError({ code = final.code }))
      end
      return Pictures.fetch(nextAddress, hops + 1):next(function(body)
        d:resolve(body)
      end, function(reason)
        d:reject(reason)
      end)
    end
    local body = table.concat(parts)
    local bad = Pictures.checkFetched(body)
    if bad then
      return d:reject(bad)
    end
    d:resolve(body)
  end
  --#ifdef DRIVERCENTRAL
  -- No dispatcher runs these, so Cloud Monitoring sees their errors only through a wrap.
  onHeaders = diagnostics:wrap(onHeaders, "Pictures.fetch")
  onBodyChunk = diagnostics:wrap(onBodyChunk, "Pictures.fetch")
  onDone = diagnostics:wrap(onDone, "Pictures.fetch")
  --#endif
  C4:url()
    :SetOptions({ fail_on_error = false, timeout = Pictures.FETCH_SECONDS, connect_timeout = Pictures.CONNECT_SECONDS })
    :OnHeaders(onHeaders)
    :OnBodyChunk(onBodyChunk)
    :OnDone(onDone)
    :Get(address, { ["User-Agent"] = "Control4" })
  return d
end

--- A handler that ends a fetch's chain. An error raised after the fetch rejects the Deferred its
--- handler's `:next` returned; this logs it, and reports it in the DriverCentral build, rather than
--- losing it there.
--- @param source string What ran, for the log and Cloud Monitoring: never an address.
--- @return fun(err: any) report
function Pictures.reportError(source)
  return function(err)
    log:error("%s failed: %s", source, tostring(err))
    --#ifdef DRIVERCENTRAL
    diagnostics:captureError(tostring(err), nil, source)
    --#endif
  end
end

--- @private
--- @return { nextId: integer, list: Picture[] } data
function Pictures:_load()
  local data = self._store:get(PICTURES_PERSIST_KEY)
  if type(data) ~= "table" or type(data.list) ~= "table" then
    data = { nextId = 1, list = {} }
  end
  data.nextId = tonumber(data.nextId) or 1
  return data
end

--- @private
--- @param data { nextId: integer, list: Picture[] }
function Pictures:_save(data)
  self._store:set(PICTURES_PERSIST_KEY, data)
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

--- The picture with this id.
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
  return self:_keep(data, { kind = kind, width = width, height = height, name = fields.name })
end

--- Keep a picture from a web address that refreshes: shown as the site sends it, so only a PNG or
--- JPEG, at most `MAX_FETCH` bytes.
--- @param data string
--- @param url any
--- @param every any One of `Pictures.EVERY_SECONDS`.
--- @return Picture|nil picture
--- @return string|nil err Why it was refused, as the Button tab shows it.
function Pictures:addWeb(data, url, every)
  local address, addressErr = Pictures.checkAddress(url)
  if not address then
    return nil, addressErr
  end
  every = Pictures.checkEvery(every)
  if not every then
    return nil, "A picture refreshes every minute, 5 minutes, 15 minutes or hour."
  end
  local kind, err = Pictures.checkRefreshed(data)
  if not kind then
    return nil, err
  end
  local width, height = Pictures.dimensions(data)
  return self:_keep(data, {
    kind = kind,
    width = width,
    height = height,
    -- Not from the address: the list is traced at Trace, and any part of an address can be a token.
    -- The Button tab names it from the address it's sent.
    name = Pictures.WEB_NAME,
    url = address,
    every = every,
    source = "1",
    fetchedAt = self._now(),
  })
end

--- A refreshed picture the Control4 app can show as the site sends it.
--- @param data any
--- @return string|nil kind `png` or `jpeg`.
--- @return string|nil err Why it's refused, as the Button tab shows it.
function Pictures.checkRefreshed(data)
  local kind = type(data) == "string" and Pictures.kindOf(data) or nil
  if kind ~= "png" and kind ~= "jpeg" then
    return nil, "A picture that refreshes has to be a PNG or JPEG."
  end
  if #data > Pictures.MAX_FETCH then
    return nil, "The picture at that address is larger than 2 MB."
  end
  if not Pictures.dimensions(data) then
    return nil, "The controller couldn't read that picture's size."
  end
  return kind, nil
end

--- @private
--- @param data string
--- @param fields table The record's fields but its id, bytes and time.
--- @return Picture|nil picture
--- @return string|nil err
function Pictures:_keep(data, fields)
  self:collect()
  local list = self:_load()
  if #list.list >= Pictures.MAX then
    return nil, string.format("a button keeps at most %d pictures", Pictures.MAX)
  end
  local name = Pictures.safeName(fields.name)
  local picture = {
    id = string.format("mine:p%d", list.nextId),
    kind = fields.kind,
    width = fields.width,
    height = fields.height,
    bytes = #data,
    name = name ~= "" and name:sub(1, MAX_NAME) or "Picture",
    added = self._now(),
    every = fields.every,
    source = fields.source,
    fetchedAt = fields.fetchedAt,
  }
  C4:FileCreateDir("SANDBOX", DIR)
  if not Images.writeFile("SANDBOX", DIR, fileName(picture), data) then
    return nil, "the controller could not store the picture"
  end
  list.nextId = list.nextId + 1
  table.insert(list.list, picture)
  self:_save(list)
  if fields.url then
    self:_setAddresses(function(addresses)
      addresses[picture.id] = fields.url
    end)
  end
  log:debug("Kept picture %s, a %s of %d bytes", picture.id, picture.kind, picture.bytes)
  return picture
end

--- @private
--- @param change fun(addresses: table<string, string>)
function Pictures:_setAddresses(change)
  local addresses = self._store:get(ADDRESSES_PERSIST_KEY, nil, true)
  addresses = type(addresses) == "table" and addresses or {}
  change(addresses)
  self._store:set(ADDRESSES_PERSIST_KEY, addresses, true)
end

--- A refreshing picture's web address.
--- @param id any
--- @return string|nil address The web address a refreshing picture comes from. Never log it.
function Pictures:address(id)
  local addresses = self._store:get(ADDRESSES_PERSIST_KEY, nil, true)
  return type(addresses) == "table" and addresses[tostring(id or "")] or nil
end

--- Whether a picture refreshes from a web address.
--- @param id any
--- @return boolean refreshes Whether the button keeps a picture by that id that refreshes.
function Pictures:refreshes(id)
  local picture = self:get(id)
  return picture ~= nil and picture.every ~= nil
end

--- @private
--- @param id any
--- @param change fun(picture: Picture): boolean|nil Changes the record; false leaves it unsaved.
--- @return Picture|nil picture
function Pictures:_change(id, change)
  local data = self:_load()
  for _, picture in ipairs(data.list) do
    if picture.id == tostring(id or "") then
      if change(picture) == false then
        return nil
      end
      self:_save(data)
      return picture
    end
  end
  return nil
end

--- A refreshing picture's new bytes: kept in place of the old ones.
--- @param id any
--- @param data string Checked with `Pictures.checkRefreshed`.
--- @return Picture|nil picture Nil when it isn't a refreshing picture or couldn't be stored.
function Pictures:replace(id, data)
  local kind = Pictures.checkRefreshed(data)
  if not kind then
    return nil
  end
  return self:_change(id, function(picture)
    if not picture.every then
      return false
    end
    local width, height = Pictures.dimensions(data)
    local was, now = fileName(picture), fileName({ id = picture.id, kind = kind })
    if not Images.writeFile("SANDBOX", DIR, now, data) then
      return false
    end
    if now ~= was then
      Images.deleteFile("SANDBOX", DIR, was)
    end
    picture.kind, picture.width, picture.height, picture.bytes = kind, width, height, #data
    picture.source, picture.fetchedAt = tostring((tonumber(picture.source) or 0) + 1), self._now()
  end)
end

--- Point a refreshing picture at another address. Its bytes stay until the next fetch.
--- @param id any
--- @param address string Checked with `Pictures.checkAddress`.
--- @return Picture|nil picture
function Pictures:setAddress(id, address)
  return self:_change(id, function(picture)
    if not picture.every then
      return false
    end
    picture.fetchedAt = nil
    self:_setAddresses(function(addresses)
      addresses[picture.id] = address
    end)
  end)
end

--- A picture's bytes.
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
    self:_keepAddresses(kept)
  end
end

--- @private
--- @param list Picture[] The pictures whose addresses stay.
function Pictures:_keepAddresses(list)
  if self._store:get(ADDRESSES_PERSIST_KEY, nil, true) == nil then
    return
  end
  self:_setAddresses(function(addresses)
    local kept = {}
    for _, picture in ipairs(list) do
      kept[picture.id] = true
    end
    for id in pairs(addresses) do
      if not kept[id] then
        addresses[id] = nil
      end
    end
  end)
end

--- Delete every picture. Ids go on from where they were.
function Pictures:clear()
  local data = self:_load()
  for _, picture in ipairs(data.list) do
    Images.deleteFile("SANDBOX", DIR, fileName(picture))
  end
  self:_save({ nextId = data.nextId, list = {} })
  self:_keepAddresses({})
end

return Pictures
