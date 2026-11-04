-- What the Navigator button shows: one look at a time, or the driver's own icon when no look is
-- ready. Showing a look serves its picture under a new address version and tells the proxy.

local log = require("lib.logging")
local Images = require("dynamic_button.images")

--- @class Button
--- @field looks Looks
--- @field images Images
--- @field store table A persist-like store with get(key, default) and set(key, value).
--- @field deviceId integer The button's device id, which names its folder.
--- @field driverName string The driver's file name without `.c4z`.
--- @field sendIcon fun(icon: string, description: string) Tells the proxy what to show.
local Button = {}
Button.__index = Button

local SHOWN_PERSIST_KEY = "ShownLook"
local VERSION_PERSIST_KEY = "ImageVersion"

--- @param opts { looks: Looks, images: Images, store: table, deviceId: integer, driverName: string, sendIcon: fun(icon: string, description: string) }
--- @return Button button
function Button:new(opts)
  local instance = setmetatable({}, self)
  instance.looks = opts.looks
  instance.images = opts.images
  instance.store = opts.store
  instance.deviceId = opts.deviceId
  instance.driverName = opts.driverName
  instance.sendIcon = opts.sendIcon
  return instance
end

--- @return Look|nil look The look the button shows, or nil for the driver's own icon.
function Button:shown()
  return self.looks:get(self.store:get(SHOWN_PERSIST_KEY))
end

--- @return integer version The address version the shown look is served under.
function Button:version()
  return tonumber(self.store:get(VERSION_PERSIST_KEY)) or 0
end

--- @private
--- @param look Look
function Button:_tell(look)
  self.sendIcon(Images.address(self.driverName, self.deviceId, look.id, self:version()), look.name)
end

--- @private
function Button:_showDefault()
  self.store:set(SHOWN_PERSIST_KEY, nil)
  self.sendIcon("", "")
end

--- Show a look, under a new address so Navigator loads its picture again.
--- @param id integer|string
--- @return boolean ok
--- @return string|nil err Why it was not shown.
function Button:show(id)
  local look = self.looks:get(id)
  if not look then
    return false, "no such look"
  end
  if not look.image then
    return false, "the look's picture has not arrived"
  end
  local png = self.images:load(look.id)
  if not png then
    return false, "the look's picture is missing"
  end
  local previous = tonumber(self.store:get(SHOWN_PERSIST_KEY))
  if not self.images:serve(self.deviceId, look.id, png) then
    return false, "the look's picture could not be served"
  end
  if previous and previous ~= look.id then
    self.images:unserve(self.deviceId, previous)
  end
  self.store:set(VERSION_PERSIST_KEY, self:version() + 1)
  self.store:set(SHOWN_PERSIST_KEY, look.id)
  self:_tell(look)
  return true
end

--- Tell the proxy the shown look again, after its name changed. The picture is unchanged.
function Button:retell()
  local look = self:shown()
  if look then
    self:_tell(look)
  end
end

--- The first look with a picture, to show when the shown one goes.
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

--- A look's new picture arrived: keep it, and show it if it is shown or nothing is.
--- @param id integer
--- @param png string
--- @return boolean ok
--- @return boolean showed True if the button now shows a new picture.
function Button:imageArrived(id, png)
  local look = self.looks:get(id)
  if not look then
    return false, false
  end
  if not self.images:save(look.id, png) then
    return false, false
  end
  self.looks:setImage(look.id, #png)
  local shown = self:shown()
  if shown == nil or shown.id == look.id then
    local ok, err = self:show(look.id)
    if not ok then
      log:warn("Could not show look %s: %s", look.name, err)
    end
    return true, ok
  end
  return true, false
end

--- Delete a look and its pictures. If it was shown, the first other ready look shows.
--- @param id integer
--- @return Look|nil removed
function Button:deleteLook(id)
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
    local next = self:_fallback(look.id)
    if next then
      self:show(next.id)
    else
      self:_showDefault()
    end
  end
  return look
end

--- At every start: serve the shown look again, since the driver's folder may have been replaced.
function Button:restore()
  local look = self:shown()
  if not (look and look.image) then
    look = self:_fallback()
  end
  for _, other in ipairs(self.looks:list()) do
    if not look or other.id ~= look.id then
      self.images:unserve(self.deviceId, other.id)
    end
  end
  if not look then
    self:_showDefault()
    return
  end
  local png = self.images:load(look.id)
  if not png or not self.images:serve(self.deviceId, look.id, png) then
    log:warn("Look %s has no picture to serve", look.name)
    self:_showDefault()
    return
  end
  self.store:set(SHOWN_PERSIST_KEY, look.id)
  self:_tell(look)
end

--- When the driver stops: remove the served picture; the next start serves it again.
function Button:destroy()
  local shown = tonumber(self.store:get(SHOWN_PERSIST_KEY))
  if shown then
    self.images:unserve(self.deviceId, shown)
  end
end

--- Forget every look and picture, as on a fresh install, and show the driver's own icon.
function Button:reset()
  for _, look in ipairs(self.looks:list()) do
    self.images:cancel(look.id)
    self.images:remove(look.id)
    self.images:unserve(self.deviceId, look.id)
  end
  self.looks:clear()
  self.store:set(VERSION_PERSIST_KEY, nil)
  self:_showDefault()
end

return Button
