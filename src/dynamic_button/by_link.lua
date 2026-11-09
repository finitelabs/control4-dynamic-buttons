-- Look Control's By Link: each look's Button Link tells the button its LED state, as a keypad button's
-- does, and the first look whose link is bound and on or off as its Show while says is the one shown,
-- and otherwise the default look. The look changes only when a device reports, so a press waits for it.
-- A device reports each of its links bound to the button in turn, so the links pick a look once they all
-- have. A state, and the colors a device gives its LEDs, count only while the link is bound to the device
-- and the device's own link that reported them.

local log = require("lib.logging")
local Looks = require("dynamic_button.looks")

require("lib.utils")

--- @class ByLink
--- @field _looks Looks
--- @field _store table A persist-like store with get(key, default) and set(key, value).
--- @field _provider fun(id: integer): integer, integer|nil The device bound to a look's Button Link now, 0 for none,
--- and which of the device's links it is.
--- @field _show fun(id: integer): boolean, string|nil Shows a look the way programming's Show Look does.
--- @field _changed fun() Tells the Button tab what changed.
--- @field _allowed fun(): boolean False while nothing may change the look.
--- @field _active boolean Look Control is By Link.
--- @field _matched integer|nil The look the links call for.
--- @field _showFailed table<integer, string> Why a matched look couldn't show, by look id, so it logs once.
--- @field _reported boolean A report changed a link's state since the links last picked.
--- @field _pending boolean Reports are waiting for the links to pick.
local ByLink = {}
ByLink.__index = ByLink

--- Each link's last LED state, true for on, and the device and its link that reported it, by look id. Kept so a
--- restart shows the look the links called for before their devices next report.
local STATES_PERSIST_KEY = "LinkStates"

--- Each link's LED colors as its device last gave them, and the device that gave them, by look id.
local COLORS_PERSIST_KEY = "LinkColors"

--- The look the links last showed. Kept so a hold from programming outlasts a restart.
local APPLIED_PERSIST_KEY = "ByLinkApplied"

local EVALUATE_TIMER = "ByLinkEvaluate"

--- How soon after a link's report the links pick a look, in milliseconds: a light's reports for each of its links
--- arrive together, and picking after the first would show a look that only the others' old states call for.
local EVALUATE_MS = 50

--- Whether a MATCH_LED_STATE's STATE says the LED is on. Devices send a boolean, a number or text.
--- @param state any
--- @return boolean|nil on Nil when it has no STATE, as a link's text or color update hasn't.
function ByLink.isOn(state)
  if state == nil or state == "" then
    return nil
  end
  return toboolean(state)
end

--- A BUTTON_COLORS color: six hex digits, as "0000ff". Some devices put a # before them.
--- @param color any
--- @return string|nil hex The color in lowercase, without the #; nil when it isn't one.
function ByLink.color(color)
  local hex = type(color) == "string" and color:match("^#?(%x%x%x%x%x%x)$")
  return hex and hex:lower() or nil
end

--- Creates a new instance of the ByLink class.
--- @param opts { looks: Looks, store: table, provider: fun(id: integer): integer, show: fun(id: integer): boolean, string|nil, changed: fun(), allowed: fun(): boolean }
--- @return ByLink byLink
function ByLink:new(opts)
  local instance = setmetatable({}, self)
  instance._looks = opts.looks
  instance._store = opts.store
  instance._provider = opts.provider
  instance._show = opts.show
  instance._changed = opts.changed
  instance._allowed = opts.allowed
  instance._active = false
  instance._matched = nil
  instance._showFailed = {}
  instance._reported = false
  instance._pending = false
  return instance
end

--- @private
--- @return table<string, { on: boolean, device: integer, binding?: integer }> states Each link's last state, by look id.
function ByLink:_states()
  local states = self._store:get(STATES_PERSIST_KEY)
  return type(states) == "table" and states or {}
end

--- @private
--- @param states table<string, { on: boolean, device: integer, binding?: integer }>
function ByLink:_saveStates(states)
  self._store:set(STATES_PERSIST_KEY, next(states) and states or nil)
end

--- @private
--- @param kept any A link's kept state or colors.
--- @param id integer
--- @return boolean fromBound The link is bound now to the device and the device's link that reported them.
function ByLink:_fromBound(kept, id)
  if type(kept) ~= "table" then
    return false
  end
  local device, binding = self._provider(id)
  device = tonumber(device) or 0
  return device ~= 0 and tonumber(kept.device) == device and tonumber(kept.binding) == tonumber(binding)
end

--- @private
--- @param states table<string, { on: boolean, device: integer, binding?: integer }>
--- @param id integer
--- @return boolean|nil on The link's last state, when the device bound to it now reported it.
function ByLink:_trusted(states, id)
  local state = states[tostring(id)]
  if type(state) ~= "table" or type(state.on) ~= "boolean" or not self:_fromBound(state, id) then
    return nil
  end
  return state.on
end

--- A look's link's last LED state. A state another device or another of its links reported, before the
--- link was bound to the one bound now, doesn't count.
--- @param id integer
--- @return boolean|nil on True for on, false for off, nil when the device bound now hasn't reported.
function ByLink:state(id)
  return self:_trusted(self:_states(), id)
end

--- A look's link reported its LED state: keep it with the device and its link that reported it, and under By Link
--- see which look the links call for once the device's other reports are in.
--- @param id integer
--- @param on boolean
--- @param device integer The device bound to the link, which sent the state.
function ByLink:report(id, on, device)
  local states = self:_states()
  local key = tostring(id)
  local kept = states[key]
  local _, binding = self._provider(id)
  local changed = type(kept) ~= "table"
    or kept.on ~= on
    or tonumber(kept.device) ~= device
    or tonumber(kept.binding) ~= tonumber(binding)
  if changed then
    states[key] = { on = on, device = device, binding = binding }
    self:_saveStates(states)
  end
  if not self._active then
    return
  end
  self._reported = self._reported or changed
  self._pending = true
  SetTimer(EVALUATE_TIMER, EVALUATE_MS, function()
    self:_settle()
  end)
end

--- @private
function ByLink:_settle()
  self._pending = false
  local reported = self._reported
  self._reported = false
  if not self:evaluate() and reported then
    -- The Button tab shows each link's state under By Link.
    self._changed()
  end
end

--- Pick now the look that reports still waiting call for. Programming and the Button tab call this before they
--- show a look, so the links' pick lands first and the look they show holds.
function ByLink:flush()
  if self._pending then
    CancelTimer(EVALUATE_TIMER)
    self:_settle()
  end
end

--- @private
--- @return table<string, { on?: string, off?: string, device: integer, binding?: integer }> colors Each link's last colors, by look id.
function ByLink:_colors()
  local colors = self._store:get(COLORS_PERSIST_KEY)
  return type(colors) == "table" and colors or {}
end

--- A look's link's LED colors. Colors another device or another of its links gave, before the link was bound to the
--- one bound now, don't count.
--- @param id integer
--- @return { on?: string, off?: string }|nil colors Each as six lowercase hex digits; nil when the device bound now
--- hasn't given them.
function ByLink:colors(id)
  local kept = self:_colors()[tostring(id)]
  if not self:_fromBound(kept, id) then
    return nil
  end
  return { on = kept.on, off = kept.off }
end

--- A look's link gave its LED colors: keep them with the device that gave them. They change no look.
--- @param id integer
--- @param on string|nil The on color, as ByLink.color reads it.
--- @param off string|nil The off color.
--- @param device integer The device bound to the link, which sent them.
function ByLink:reportColors(id, on, off, device)
  local colors = self:_colors()
  local key = tostring(id)
  local kept = colors[key]
  local _, binding = self._provider(id)
  if
    type(kept) == "table"
    and kept.on == on
    and kept.off == off
    and tonumber(kept.device) == device
    and tonumber(kept.binding) == tonumber(binding)
  then
    return
  end
  colors[key] = { on = on, off = off, device = device, binding = binding }
  self._store:set(COLORS_PERSIST_KEY, colors)
  if self._active then
    -- The Button tab shows each link's colors under By Link.
    self._changed()
  end
end

--- Forget a look's link's state and colors: the link is gone.
--- @param id integer|string
function ByLink:forget(id)
  local states = self:_states()
  local key = tostring(id)
  if states[key] ~= nil then
    states[key] = nil
    self:_saveStates(states)
  end
  local colors = self:_colors()
  if colors[key] ~= nil then
    colors[key] = nil
    self._store:set(COLORS_PERSIST_KEY, next(colors) and colors or nil)
  end
end

--- The look the links call for.
--- @return integer|nil id
function ByLink:matched()
  return self._matched
end

--- Start as a load does, from the states kept.
--- @param active boolean Look Control is By Link.
function ByLink:start(active)
  self._active = active
  if active then
    self:evaluate()
  else
    -- Look Control can change while the driver is stopped: a hold kept from then would outlive By Link.
    self._store:set(APPLIED_PERSIST_KEY, nil)
  end
end

--- Look Control changed.
--- @param active boolean Look Control is By Link.
function ByLink:setActive(active)
  if active == self._active then
    return
  end
  if not active then
    self:stop()
    return
  end
  self._active = true
  self:evaluate()
end

--- Stop following and forget what the links called for. The links' states are kept: they are what
--- the devices last said.
function ByLink:stop()
  CancelTimer(EVALUATE_TIMER)
  self._pending = false
  self._reported = false
  self._active = false
  self._matched = nil
  self._showFailed = {}
  self._store:set(APPLIED_PERSIST_KEY, nil)
end

--- Stop, and forget every link's state and colors: the driver was reset.
function ByLink:reset()
  self:stop()
  self._store:set(STATES_PERSIST_KEY, nil)
  self._store:set(COLORS_PERSIST_KEY, nil)
end

--- A look was deleted.
--- @param wasShown boolean The button has moved to another look, which nothing asked for, so no hold is left.
function ByLink:lookDeleted(wasShown)
  if wasShown then
    self._store:set(APPLIED_PERSIST_KEY, nil)
  end
  self:evaluate()
end

--- A look's link was bound or unbound: a link with nothing bound never matches, and the Button tab shows whether
--- each link is bound.
function ByLink:bindingChanged()
  if self._active and not self:evaluate() then
    self._changed()
  end
end

--- End a hold from programming: the look the links call for shows again.
function ByLink:release()
  self._store:set(APPLIED_PERSIST_KEY, nil)
  self:evaluate()
end

--- The look the links call for now, while they may pick one.
--- @return integer|nil id
function ByLink:decide()
  if not (self._active and self._allowed()) then
    return nil
  end
  return self:_decide()
end

--- @private
--- @return integer|nil matched The first look whose link's device is on or off as its Show while says, else the
--- default look.
function ByLink:_decide()
  local states = self:_states()
  for _, look in ipairs(self._looks:list()) do
    local on = self:_trusted(states, look.id)
    if on ~= nil and on == Looks.showsWhileOn(look) then
      return look.id
    end
  end
  return self._looks:defaultId()
end

--- See which look the links call for, and show it if that changed.
--- @return boolean told The Button tab was told of a change.
function ByLink:evaluate()
  if not self._active or not self._allowed() then
    return false
  end
  local matched = self:_decide()
  local changed = matched ~= self._matched
  self._matched = matched
  -- Only a change of match shows anything, so a look shown from programming stays until then.
  if matched == nil then
    if self._store:get(APPLIED_PERSIST_KEY) ~= nil then
      self._store:set(APPLIED_PERSIST_KEY, nil)
    end
  elseif matched ~= tonumber(self._store:get(APPLIED_PERSIST_KEY)) then
    local ok, err = self._show(matched)
    if ok then
      self._store:set(APPLIED_PERSIST_KEY, matched)
      self._showFailed[matched] = nil
    elseif self._showFailed[matched] ~= err then
      self._showFailed[matched] = err
      log:warn("Could not show look %s: %s", tostring(matched), tostring(err))
    end
  end
  if changed then
    self._changed()
  end
  return changed
end

return ByLink
