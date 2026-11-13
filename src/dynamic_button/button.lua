-- What the Navigator button shows: one look at a time, or the driver's own icon when no look is
-- ready. Showing a look serves its picture and tells the proxy: through the picture bank's slot for
-- that picture, or by its address when the bank can't take it.

local log = require("lib.logging")
local Images = require("dynamic_button.images")
local Looks = require("dynamic_button.looks")
local Bank = require("dynamic_button.bank")

--- @class Button
--- @field looks Looks
--- @field images Images
--- @field store table A persist-like store with get(key, default) and set(key, value).
--- @field deviceId integer The button's device id, which names its folder.
--- @field driverName string The driver's file name without `.c4z`.
--- @field sendIcon fun(icon: string, description: string) Tells the proxy what to show.
--- @field badges LiveBadges Draws the shown look's live badge.
--- @field refresher? WebPictures Refreshes the shown look's picture from its web address.
--- @field bank Bank The picture bank every Dynamic Button shares.
--- @field onFull? fun(full: boolean) Hears when a look goes to its address because the bank is full, and back.
--- @field _badgeKey string|nil Names the shown look's live badge text in its address.
--- @field _full boolean True while the shown look is at its address because the bank is full.
--- @field _waiting boolean True while the shown look is at its address until every button has started.
local Button = {}
Button.__index = Button

local SHOWN_PERSIST_KEY = "ShownLook"
local VERSION_PERSIST_KEY = "ImageVersion"

--- Creates a new instance of the Button class.
--- @param opts { looks: Looks, images: Images, store: table, deviceId: integer, driverName: string, sendIcon: fun(icon: string, description: string), badges: LiveBadges, refresher?: WebPictures, bank: Bank, onFull?: fun(full: boolean) }
--- @return Button button
function Button:new(opts)
  local instance = setmetatable({}, self)
  instance.looks = opts.looks
  instance.images = opts.images
  instance.store = opts.store
  instance.deviceId = opts.deviceId
  instance.driverName = opts.driverName
  instance.sendIcon = opts.sendIcon
  instance.badges = opts.badges
  instance.refresher = opts.refresher
  instance.bank = opts.bank
  instance.onFull = opts.onFull
  instance._full = false
  instance._waiting = false
  return instance
end

--- A look's stored picture to serve. A look sharing a refreshing picture with another can hold
--- older bytes than the picture has now: those are brought up to date first, under a new version,
--- so the proxy hears of the look once, with its current picture.
--- @private
--- @param look Look
--- @return Look look As it is after any update.
--- @return string|nil png
function Button:_current(look)
  local data, source
  if self.refresher then
    data, source = self.refresher:newer(look)
  end
  if data and self.images:save(look.id, data) then
    self.looks:setImage(look.id, #data, self:_nextVersion(), source)
    self.images:unserve(self.deviceId, look.id)
    return self.looks:get(look.id), data
  end
  return look, self.images:load(look.id)
end

--- Tell what watches the shown look which one it is now, or nil for none.
--- @private
--- @param look Look|nil
function Button:_watch(look)
  self.badges:watch(look)
  if self.refresher then
    self.refresher:watch(look)
  end
end

--- The look the button shows now.
--- @return Look|nil look The look the button shows, or nil for the driver's own icon.
function Button:shown()
  return self.looks:get(self.store:get(SHOWN_PERSIST_KEY))
end

--- @private
--- @return integer version A number no picture has been served under.
function Button:_nextVersion()
  local version = (tonumber(self.store:get(VERSION_PERSIST_KEY)) or 0) + 1
  self.store:set(VERSION_PERSIST_KEY, version)
  return version
end

--- Put a look's picture where Navigator loads it. A look without a live badge keeps its file from
--- one showing to the next.
--- @private
--- @param look Look
--- @param picture string
--- @param key string|nil Names a live badge's text.
--- @return boolean ok
function Button:_serve(look, picture, key)
  if not key and self.images:served(self.deviceId, look.id) then
    return true
  end
  return self.images:serve(self.deviceId, look.id, picture)
end

--- @private
--- @param look Look Its stored picture is gone.
function Button:_lostPicture(look)
  self.looks:setImage(look.id, nil)
  self.images:unserve(self.deviceId, look.id)
end

--- Whether a look's picture changes while it shows: a live badge, or a picture that refreshes.
--- @private
--- @param look Look
--- @return boolean
function Button:_live(look)
  return Looks.liveBadge(look) ~= nil or (self.refresher ~= nil and self.refresher:refreshes(look))
end

--- The shown look went to its address because the bank is full (true), or no longer waits for a
--- slot (false).
--- @private
--- @param full boolean
--- @param look? Look The shown look (optional).
function Button:_noteFull(full, look)
  if full == self._full then
    return
  end
  self._full = full
  if full then
    log:warn("The picture bank is full: look %s shows by its address until the controller restarts", look.name)
  elseif look then
    log:info("Look %s shows through the picture bank again", look.name)
  end
  if self.onFull then
    self.onFull(full)
  end
end

--- @private
--- @param look Look
--- @param picture? string The picture as served, when at hand (optional).
function Button:_tell(look, picture)
  local version = look.image and look.image.version or 0
  local state, err
  if self.bank.enabled then
    local live = self:_live(look)
    picture = picture or self.images:readServed(self.deviceId, look.id)
    state, err = self.bank:slotFor(picture, live and look.id or nil)
  end
  self._waiting = err == Bank.WAIT
  if state then
    self:_noteFull(false, look)
    self.sendIcon(state, look.name)
    return
  end
  if err == Bank.FULL then
    self:_noteFull(true, look)
  else
    self:_noteFull(false)
  end
  if err == Bank.CAPPED then
    log:debug("Look %s took its share of the picture bank until the controller restarts", look.name)
  end
  if self._waiting then
    log:debug("Look %s shows by its address until every Dynamic Button has started", look.name)
  end
  self.sendIcon(Images.address(self.driverName, self.deviceId, look.id, version, self._badgeKey), look.name)
end

--- @private
function Button:_showDefault()
  self.store:set(SHOWN_PERSIST_KEY, nil)
  self._badgeKey = nil
  self:_watch(nil)
  self:_noteFull(false)
  self._waiting = false
  self.sendIcon(self.bank.enabled and Bank.OWN_STATE or Images.ownIcon(self.driverName), "")
end

--- Show a look. A look already shown is left as it is, unless asked to show it again.
--- @param id integer|string
--- @param again? boolean Serve it and tell the proxy even if it's shown (optional).
--- @return boolean ok
--- @return string|nil err Why it was not shown.
function Button:show(id, again)
  local look = self.looks:get(id)
  if not look then
    return false, "no such look"
  end
  if not look.image then
    return false, "the look's picture has not arrived"
  end
  local previous = tonumber(self.store:get(SHOWN_PERSIST_KEY))
  if previous == look.id and not again then
    return true
  end
  local png
  look, png = self:_current(look)
  if not png then
    self:_lostPicture(look)
    return false, "the look's picture is missing"
  end
  local picture, key = self.badges:picture(look, png)
  if not self:_serve(look, picture, key) then
    return false, "the look's picture could not be served"
  end
  self.store:set(SHOWN_PERSIST_KEY, look.id)
  self._badgeKey = key
  self:_tell(look, picture)
  self:_watch(look)
  return true
end

--- Draw the shown look's live badge again and serve it.
function Button:redrawBadge()
  local look = self:shown()
  local png = look and self.images:load(look.id)
  if not png then
    return
  end
  local picture, key = self.badges:picture(look, png)
  if not self.images:serve(self.deviceId, look.id, picture) then
    log:warn("Could not serve look %s's new badge", look.name)
    return
  end
  self._badgeKey = key
  self:_tell(look, picture)
end

--- Every Dynamic Button wrote its picture bank records again after an update: a look that waited
--- for a slot takes one.
function Button:bankReady()
  if self._waiting then
    self:retell()
  end
end

--- Tell the proxy the shown look again, after its name changed. The picture is unchanged.
function Button:retell()
  local look = self:shown()
  if look then
    self:_tell(look)
  end
end

--- The first look with a picture, to show when the shown one goes.
--- @private
--- @param exceptId integer|nil
--- @return Look|nil look
function Button:_fallback(exceptId)
  for _, look in ipairs(self.looks:list()) do
    if look.id ~= exceptId and look.image then
      return look
    end
  end
  return nil
end

--- The look one step through the cycle lands on: the next (1) or previous (-1) look in the list
--- that is in the cycle and has a picture, wrapping, counted from the shown look's place. With
--- nothing shown, the first such look (or the last, stepping back).
--- @param step integer 1 or -1.
--- @param skip? table<integer, boolean> Look ids to pass over as well (optional).
--- @return Look|nil look Nil when no look can show; the shown look when it is the only one.
function Button:cycled(step, skip)
  local list = self.looks:list()
  local count = #list
  local shown = self:shown()
  local from = step > 0 and 0 or count + 1
  for i, look in ipairs(list) do
    if shown and look.id == shown.id then
      from = i
    end
  end
  for k = 1, count do
    local look = list[(from - 1 + step * k) % count + 1]
    if look.image and Looks.inCycle(look) and not (skip and skip[look.id]) then
      return look
    end
  end
  return nil
end

--- A look's new picture arrived: keep it, and show it if it is shown or nothing is.
--- @param id integer
--- @param png string The picture: a PNG, or as a refreshing picture's site sent it.
--- @param source? string Names a refreshing picture's bytes (optional).
--- @return boolean ok
--- @return boolean showed True if the button now shows a new picture.
function Button:imageArrived(id, png, source)
  local look = self.looks:get(id)
  if not look then
    return false, false
  end
  if not self.images:save(look.id, png) then
    return false, false
  end
  self.looks:setImage(look.id, #png, self:_nextVersion(), source)
  self.images:unserve(self.deviceId, look.id)
  local shown = self:shown()
  if shown == nil or shown.id == look.id then
    local ok, err = self:show(look.id, true)
    if not ok then
      log:warn("Could not show look %s: %s", look.name, err)
    end
    return true, ok
  end
  return true, false
end

--- Delete a look and its pictures. If it was shown, the look `preferred` names shows, or else the
--- first other ready look, or the driver's own icon when that look can't be shown.
--- @param id integer
--- @param preferred? fun(): integer|nil The look to show in its place, asked once it's gone (optional).
--- @return Look|nil removed
function Button:deleteLook(id, preferred)
  local look = self.looks:get(id)
  if not look then
    return nil
  end
  local wasShown = tonumber(self.store:get(SHOWN_PERSIST_KEY)) == look.id
  self.images:cancel(look.id)
  self.images:remove(look.id)
  self.images:unserve(self.deviceId, look.id)
  self.looks:delete(look.id)
  if wasShown then
    local wanted = preferred and self.looks:get(preferred())
    local replacement = wanted and wanted.image and wanted or self:_fallback(look.id)
    if not (replacement and self:show(replacement.id)) then
      self:_showDefault()
    end
  end
  return look
end

--- At every start: serve the shown look again, since the driver's folder may have been replaced.
--- A look whose stored picture is gone loses its mark, and the next ready look shows.
function Button:restore()
  local look = self:shown()
  if not (look and look.image) then
    look = self:_fallback()
  end
  local png
  while look do
    look, png = self:_current(look)
    if png then
      break
    end
    log:warn("Look %s has no stored picture", look.name)
    self:_lostPicture(look)
    look = self:_fallback()
  end
  if look and self.badges:holding(look) and self.images:served(self.deviceId, look.id) then
    -- The picture from before stays until the variable comes.
    self.store:set(SHOWN_PERSIST_KEY, look.id)
    self._badgeKey = nil
    self:_tell(look)
    self:_watch(look)
    return
  end
  local picture, key
  if look then
    picture, key = self.badges:picture(look, png)
  end
  if not look or not self:_serve(look, picture, key) then
    self:_showDefault()
    return
  end
  self.store:set(SHOWN_PERSIST_KEY, look.id)
  self._badgeKey = key
  self:_tell(look, picture)
  self:_watch(look)
end

--- The button left the project: remove every stored and served picture.
function Button:removed()
  for _, look in ipairs(self.looks:list()) do
    self.images:cancel(look.id)
    self.images:remove(look.id)
    self.images:unserve(self.deviceId, look.id)
  end
end

--- Forget every look and picture, as on a fresh install, and show the driver's own icon. The
--- address version and look ids go on, so no app shows an old picture for a new look.
function Button:reset()
  self:removed()
  self.looks:clear()
  self:_showDefault()
end

return Button
