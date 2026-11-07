-- Pictures from a web address that refresh: the controller fetches the shown look's picture as often
-- as the picture asks, and when its bytes change, serves them as the site sent them.

local log = require("lib.logging")
local Pictures = require("dynamic_button.pictures")

--- @class WebPictures
--- @field _pictures Pictures
--- @field _looks Looks
--- @field _arrived fun(lookId: integer, data: string, source: string) Serves a look's new bytes.
--- @field _changed fun() Tells the Button tab what changed.
--- @field _allowed fun(): boolean False while nothing may change the picture.
--- @field _now fun(): number The clock, in seconds.
--- @field _fetch fun(address: string, done: fun(body: string|nil, err: string|nil))
--- @field _setTimer fun(name: string, ms: number, fn: function)
--- @field _cancelTimer fun(name: string)
--- @field _watched integer|nil The shown look, while its picture refreshes.
--- @field _fetching table<string, string> The address each picture has a fetch under way for.
--- @field _tried table<string, number> When each picture's last fetch ended, in seconds.
--- @field _good table<string, number> When each picture's last fetch succeeded, in seconds.
--- @field _failed table<string, string> Each picture's last failure, until one succeeds.
local WebPictures = {}
WebPictures.__index = WebPictures

local TIMER = "WebPictureRefresh"

local MISSING_ADDRESS = "The controller lost this picture's web address. Fetch it again in the Button tab."

--- Creates a new instance of the WebPictures class.
--- @param opts { pictures: Pictures, looks: Looks, arrived: fun(lookId: integer, data: string, source: string), changed: fun(), allowed: fun(): boolean, now?: fun(): number, fetch?: fun(address: string, done: function), setTimer?: fun(name: string, ms: number, fn: function), cancelTimer?: fun(name: string) }
--- @return WebPictures refresher
function WebPictures:new(opts)
  local instance = setmetatable({}, self)
  instance._pictures = opts.pictures
  instance._looks = opts.looks
  instance._arrived = opts.arrived
  instance._changed = opts.changed
  instance._allowed = opts.allowed
  instance._now = opts.now or os.time
  instance._fetch = opts.fetch
    or function(address, done)
      Pictures.fetch(address)
        :next(function(body)
          done(body)
        end, function(err)
          done(nil, err)
        end)
        :next(nil, Pictures.reportError("Refreshing a web picture"))
    end
  instance._setTimer = opts.setTimer or function(name, ms, fn)
    SetTimer(name, ms, fn)
  end
  instance._cancelTimer = opts.cancelTimer or function(name)
    CancelTimer(name)
  end
  instance._fetching, instance._tried, instance._good, instance._failed = {}, {}, {}, {}
  return instance
end

--- @private
--- @param look Look|nil
--- @return Picture|nil picture The look's picture, when it refreshes.
function WebPictures:_pictureOf(look)
  local icon = look and look.icon
  local picture = icon and icon.stored and self._pictures:get(icon.id) or nil
  return picture and picture.every and picture or nil
end

--- The shown look changed, or its fields did. Its picture is fetched when it's due, at once when
--- it's older than its refresh.
--- @param look Look|nil
function WebPictures:watch(look)
  local picture = self:_pictureOf(look)
  if not picture then
    self._watched = nil
    self._cancelTimer(TIMER)
    return
  end
  self._watched = look.id
  self:_schedule()
end

--- A look sharing its picture with another can hold older bytes than the picture has now.
--- @param look Look
--- @return string|nil data The picture's bytes, when the look's copy is older.
--- @return string|nil source What names them.
function WebPictures:newer(look)
  local picture = self:_pictureOf(look)
  if not (picture and look.image and look.image.source ~= picture.source) then
    return nil, nil
  end
  return self._pictures:load(picture.id), picture.source
end

--- Arm the timer for the shown look's next fetch, or fetch now when it's due.
--- @private
function WebPictures:_schedule()
  self._cancelTimer(TIMER)
  local picture = self:_pictureOf(self._watched and self._looks:get(self._watched))
  if not picture or not self._allowed() or self._fetching[picture.id] then
    return
  end
  local now = self._now()
  local last = self._tried[picture.id] or tonumber(picture.fetchedAt)
  -- A clock set back would otherwise stretch the wait by as much.
  if last and now < last then
    last = now
  end
  local wait = last and picture.every - (now - last) or 0
  if wait <= 0 then
    self:refreshPicture(picture.id)
    return
  end
  self._setTimer(TIMER, wait * ONE_SECOND, function()
    self:refreshPicture(picture.id)
  end)
end

--- Fetch the shown look's picture now.
--- @return boolean started
--- @return string|nil err Why not.
function WebPictures:refresh()
  local picture = self:_pictureOf(self._watched and self._looks:get(self._watched))
  if not picture then
    return false, "the shown look's picture doesn't refresh from a web address"
  end
  return self:refreshPicture(picture.id)
end

--- Fetch a refreshing picture now, whichever look uses it.
--- @param id string
--- @return boolean started
--- @return string|nil err Why not.
function WebPictures:refreshPicture(id)
  if not self._allowed() then
    return false, "nothing may change the picture now"
  end
  local picture = self._pictures:get(id)
  if not (picture and picture.every) then
    return false, "that picture doesn't refresh from a web address"
  end
  local address = self._pictures:address(id)
  if not address then
    if not self._failed[id] then
      log:warn("Picture %s has no web address to refresh from", id)
    end
    self._failed[id] = MISSING_ADDRESS
    self:_call("telling the Button tab", self._changed)
    return false, "that picture has no web address"
  end
  -- A fetch of another address, under way when the address changed, doesn't answer for this one.
  if self._fetching[id] == address then
    return true
  end
  self._fetching[id] = address
  self._fetch(address, function(body, err)
    if self._fetching[id] == address then
      self._fetching[id] = nil
    end
    self:_fetched(id, address, body, err)
  end)
  return true
end

--- A picture's address now points elsewhere: what was known about the old one no longer holds.
--- @param id string
function WebPictures:forget(id)
  self._tried[id], self._good[id], self._failed[id] = nil, nil, nil
end

--- A fetch from outside the schedule succeeded, as when the picture was added.
--- @param id string
function WebPictures:noteFetched(id)
  local now = self._now()
  self._tried[id], self._good[id], self._failed[id] = now, now, nil
end

--- Run a hook the driver gave, so an error in it is logged rather than lost with the refresh loop.
--- @private
--- @param what string What the hook does, for the log.
--- @param fn function
--- @param ... any The hook's arguments.
function WebPictures:_call(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    log:error("Web picture: %s failed: %s", what, tostring(err))
  end
end

--- @private
--- @param id string
--- @param address string The address fetched.
--- @param body string|nil
--- @param err string|nil
function WebPictures:_fetched(id, address, body, err)
  local picture = self._pictures:get(id)
  -- Gone, or pointed elsewhere while this fetch was under way: its answer is for no picture now.
  if not picture or self._pictures:address(id) ~= address then
    self:_schedule()
    return
  end
  local now = self._now()
  self._tried[id] = now
  if not err then
    local _, refused = Pictures.checkRefreshed(body)
    err = refused
  end
  if err then
    if not self._failed[id] then
      log:warn("Picture %s didn't refresh: %s", id, err)
    end
    self._failed[id] = err
    self:_schedule()
    self:_call("telling the Button tab", self._changed)
    return
  end
  local recovered = self._failed[id] ~= nil
  self._failed[id], self._good[id] = nil, now
  if recovered then
    log:info("Picture %s refreshes again", id)
  end
  -- Armed before storing the new bytes, so an error there can't end the refreshing.
  self:_schedule()
  -- The same length first, so most new pictures are told apart without reading the stored one.
  if not (#body == picture.bytes and body == self._pictures:load(id)) then
    local kept = self._pictures:replace(id, body)
    if not kept then
      log:warn("Picture %s: the controller could not store its new bytes", id)
    else
      local look = self._watched and self._looks:get(self._watched)
      if look and look.icon.id == id then
        self:_call("serving its new bytes", self._arrived, look.id, body, kept.source)
      end
    end
    self:_call("telling the Button tab", self._changed)
  elseif recovered then
    self:_call("telling the Button tab", self._changed)
  end
end

--- What the Button tab shows for a refreshing picture.
--- @param id string
--- @return { refreshedAt: number|nil, error: string|nil } status
function WebPictures:status(id)
  local picture = self._pictures:get(id)
  return {
    refreshedAt = self._good[id] or (picture and tonumber(picture.fetchedAt)) or nil,
    error = self._failed[id],
  }
end

return WebPictures
