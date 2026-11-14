-- The looks' pictures: received from the Button tab in base64 chunks, kept in the button's own
-- storage, and copied into the driver's web folder where Navigator loads the one shown.
--
-- Navigator keeps a picture for each address until Navigators refresh, so a new picture is served
-- under a new `?v=` number, and a look keeps its address until then, so the app downloads each
-- picture once.

local log = require("lib.logging")

--- @class Upload
--- @field token string The upload's id, chosen by the Button tab.
--- @field at number When its last chunk arrived, in seconds.
--- @field count integer How many chunks the upload has.
--- @field nextIndex integer The chunk expected next, from 1.
--- @field parts string[] The decoded chunks so far.
--- @field bytes integer The decoded size so far.

--- @class Images
--- @field _uploads table<integer|string, Upload> The upload in progress for each look, or by name.
--- @field _now fun(): number The clock, in seconds.
local Images = {}
Images.__index = Images

--- The largest picture a look keeps, in bytes: well above a 300 px PNG.
Images.MAX_BYTES = 512 * 1024

--- An upload with no new chunk for this long is dropped, in seconds.
Images.STALE_SECONDS = 60

--- The largest chunk the Button tab sends, in base64 characters, a multiple of 4. Director's time
--- on a command grows faster than its size: one 48 KB chunk took 1.9 s, four 12 KB chunks 1.1 s.
Images.MAX_CHUNK = 12 * 1024

local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local WWW_ROOT = "www/buttons"
--- The stored pictures' folder in the button's own storage.
local SOURCE_DIR = "looks"

--- Creates a new instance of the Images class.
--- @param now? fun(): number The clock, in seconds (optional). Defaults to os.time.
--- @return Images images
function Images:new(now)
  local instance = setmetatable({}, self)
  instance._uploads = {}
  instance._now = now or os.time
  return instance
end

--- Drop uploads that stopped arriving, so an abandoned one doesn't hold its chunks.
--- @private
function Images:_dropStale()
  local now = self._now()
  for key, upload in pairs(self._uploads) do
    if now - upload.at >= Images.STALE_SECONDS then
      self._uploads[key] = nil
    end
  end
end

--- @param data string
--- @return string|nil err Why a look's picture is refused: it must be a PNG.
local function checkPng(data)
  if data:sub(1, #PNG_SIGNATURE) ~= PNG_SIGNATURE then
    return "picture is not a PNG"
  end
  return nil
end

--- Take one chunk of a picture: a look's, or another upload's by name.
--- @param key integer|string The look's id, or the upload's name.
--- @param token string The upload's id; chunk 1 starts a new upload under it.
--- @param index integer The chunk's place, from 1.
--- @param count integer How many chunks the picture has.
--- @param data string The chunk, base64.
--- @param check? fun(data: string): string|nil Why the whole picture is refused; a look's picture must be a PNG.
--- @return string|nil picture The whole picture once its last chunk arrived, else nil.
--- @return string|nil err Why the upload was dropped.
function Images:accept(key, token, index, count, data, check)
  self:_dropStale()
  index, count = tonumber(index), tonumber(count)
  token, data = tostring(token or ""), tostring(data or "")
  local maxChunks = math.ceil(Images.MAX_BYTES * 4 / 3 / Images.MAX_CHUNK) + 1
  if key == nil or key == "" or not index or not count or token == "" then
    return nil, "chunk without its look, upload, place or count"
  end
  if count < 1 or count > maxChunks or index < 1 or index > count then
    self._uploads[key] = nil
    return nil, "chunk out of range"
  end
  if #data == 0 or #data > Images.MAX_CHUNK or #data % 4 ~= 0 then
    self._uploads[key] = nil
    return nil, "chunk is not whole base64 of the allowed size"
  end
  local upload = self._uploads[key]
  if index == 1 then
    upload = { token = token, count = count, nextIndex = 1, parts = {}, bytes = 0, at = self._now() }
    self._uploads[key] = upload
  elseif not upload or upload.token ~= token or upload.count ~= count or upload.nextIndex ~= index then
    self._uploads[key] = nil
    return nil, "chunk out of order"
  end
  local decoded = C4:Base64Decode(data)
  if decoded == nil or decoded == "" then
    self._uploads[key] = nil
    return nil, "chunk is not base64"
  end
  upload.bytes = upload.bytes + #decoded
  if upload.bytes > Images.MAX_BYTES then
    self._uploads[key] = nil
    return nil, "picture is larger than 512 KB"
  end
  table.insert(upload.parts, decoded)
  upload.nextIndex = index + 1
  upload.at = self._now()
  if index < count then
    return nil
  end
  self._uploads[key] = nil
  local whole = table.concat(upload.parts)
  local refused = (check or checkPng)(whole)
  if refused then
    return nil, refused
  end
  return whole
end

--- Forget a look's upload in progress.
--- @param lookId integer
function Images:cancel(lookId)
  self._uploads[tonumber(lookId) or -1] = nil
end

--- Write a file, replacing any there.
--- @param alias string A documented path alias.
--- @param subdir string The sub-folder of the alias.
--- @param name string
--- @param data string
--- @return boolean ok
function Images.writeFile(alias, subdir, name, data)
  C4:FileSetDir(alias, subdir)
  if C4:FileExists(name) then
    C4:FileDelete(name)
  end
  local fh = C4:FileOpen(name)
  if fh == nil or fh == -1 then
    log:error("Could not open %s/%s for writing", alias, name)
    return false
  end
  local written = C4:FileWrite(fh, #data, data)
  C4:FileClose(fh)
  if written ~= #data then
    log:error("Wrote %s of %d bytes to %s/%s", tostring(written), #data, alias, name)
    return false
  end
  return true
end

--- Read a whole file.
--- @param alias string A documented path alias.
--- @param subdir string The sub-folder of the alias.
--- @param name string
--- @return string|nil data
function Images.readFile(alias, subdir, name)
  C4:FileSetDir(alias, subdir)
  if not C4:FileExists(name) then
    return nil
  end
  local fh = C4:FileOpen(name)
  if fh == nil or fh == -1 then
    return nil
  end
  C4:FileSetPos(fh, 0)
  local data = C4:FileRead(fh, C4:FileGetSize(fh))
  C4:FileClose(fh)
  return data
end

--- Delete a file, if it's there.
--- @param alias string A documented path alias.
--- @param subdir string The sub-folder of the alias.
--- @param name string
function Images.deleteFile(alias, subdir, name)
  C4:FileSetDir(alias, subdir)
  if C4:FileExists(name) then
    C4:FileDelete(name)
  end
end

--- @param lookId integer
--- @return string name The file of what a live badge's redraw starts from.
local function cacheName(lookId)
  return string.format("look-%d.badge", lookId)
end

--- @param lookId integer
--- @return string name The stored picture's file name.
local function sourceName(lookId)
  return string.format("look-%d.png", lookId)
end

--- Keep a look's picture in the button's own storage.
--- @param lookId integer
--- @param png string
--- @return boolean ok
function Images:save(lookId, png)
  C4:FileCreateDir("SANDBOX", SOURCE_DIR)
  Images.deleteFile("SANDBOX", SOURCE_DIR, cacheName(lookId))
  return Images.writeFile("SANDBOX", SOURCE_DIR, sourceName(lookId), png)
end

--- A look's stored picture.
--- @param lookId integer
--- @return string|nil png The look's stored picture.
function Images:load(lookId)
  return Images.readFile("SANDBOX", SOURCE_DIR, sourceName(lookId))
end

--- Delete a look's stored picture and its badge cache.
--- @param lookId integer
function Images:remove(lookId)
  Images.deleteFile("SANDBOX", SOURCE_DIR, sourceName(lookId))
  Images.deleteFile("SANDBOX", SOURCE_DIR, cacheName(lookId))
end

--- Keep what a live badge's redraw starts from.
--- @param lookId integer
--- @param data string What a live badge's redraw starts from.
function Images:saveCache(lookId, data)
  Images.writeFile("SANDBOX", SOURCE_DIR, cacheName(lookId), data)
end

--- What a live badge's redraw starts from, if kept.
--- @param lookId integer
--- @return string|nil data
function Images:loadCache(lookId)
  return Images.readFile("SANDBOX", SOURCE_DIR, cacheName(lookId))
end

--- @param deviceId integer
--- @return string subdir The button's folder in the driver's web folder.
local function servedDir(deviceId)
  return string.format("%s/%d", WWW_ROOT, deviceId)
end

--- Copy a look's picture to where Navigator loads it.
--- @param deviceId integer
--- @param lookId integer
--- @param png string
--- @return boolean ok
function Images:serve(deviceId, lookId, png)
  C4:FileCreateDir("C4Z", WWW_ROOT)
  C4:FileCreateDir("C4Z", servedDir(deviceId))
  return Images.writeFile("C4Z", servedDir(deviceId), string.format("%d.png", lookId), png)
end

--- Whether a look's picture is served from before.
--- @param deviceId integer
--- @param lookId integer
--- @return boolean served A picture for the look is in place from before.
function Images:served(deviceId, lookId)
  C4:FileSetDir("C4Z", servedDir(deviceId))
  return C4:FileExists(string.format("%d.png", lookId)) == true
end

--- Stop serving a look's picture.
--- @param deviceId integer
--- @param lookId integer
function Images:unserve(deviceId, lookId)
  Images.deleteFile("C4Z", servedDir(deviceId), string.format("%d.png", lookId))
end

--- The address Navigator loads a served look from. A new version is a new address to Navigator.
--- @param driverName string The driver's file name without `.c4z`.
--- @param deviceId integer
--- @param lookId integer
--- @param version integer
--- @param key? string Names a live badge's text, so a text seen before needs no new download (optional).
--- @return string address
function Images.address(driverName, deviceId, lookId, version, key)
  local address = string.format("controller://driver/%s/buttons/%d/%d.png?v=%d", driverName, deviceId, lookId, version)
  return key and (address .. "-" .. key) or address
end

--- The address of the driver's own icon, for a button with no look.
--- @param driverName string The driver's file name without `.c4z`.
--- @return string address
function Images.ownIcon(driverName)
  return string.format("controller://driver/%s/icons/experience_300.png", driverName)
end

return Images
