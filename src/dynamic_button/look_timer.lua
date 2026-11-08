-- A look's timer: once its time is up, the button shows the look shown before it or another look,
-- or under By Value the look the values call for. One runs at a time, for the shown look, and its
-- due time is kept, so a restart or an update comes back to it.

local log = require("lib.logging")
local Looks = require("dynamic_button.looks")

--- @class LookTimer
--- @field _looks Looks
--- @field _store table A persist-like store with get(key, default) and set(key, value).
--- @field _shown fun(): Look|nil The look the button shows.
--- @field _show fun(id: integer): boolean, string|nil Shows a look, without starting its own timer.
--- @field _byValue fun(): boolean Look Control is By Value.
--- @field _release fun() Lets the values pick the look again.
--- @field _allowed fun(): boolean False while nothing may change the look.
--- @field _now fun(): number The clock, in seconds.
--- @field _setTimer fun(name: string, ms: number, fn: function)
--- @field _cancelTimer fun(name: string)
local LookTimer = {}
LookTimer.__index = LookTimer

local TIMER = "LookTimer"

--- The timed look, the look shown before it, and when its time is up, in seconds.
local PERSIST_KEY = "LookTimer"

--- Creates a new instance of the LookTimer class.
--- @param opts { looks: Looks, store: table, shown: fun(): Look|nil, show: fun(id: integer): boolean, string|nil, byValue: fun(): boolean, release: fun(), allowed: fun(): boolean, now?: fun(): number, setTimer?: fun(name: string, ms: number, fn: function), cancelTimer?: fun(name: string) }
--- @return LookTimer timer
function LookTimer:new(opts)
  local instance = setmetatable({}, self)
  instance._looks = opts.looks
  instance._store = opts.store
  instance._shown = opts.shown
  instance._show = opts.show
  instance._byValue = opts.byValue
  instance._release = opts.release
  instance._allowed = opts.allowed
  instance._now = opts.now or os.time
  instance._setTimer = opts.setTimer or function(name, ms, fn)
    SetTimer(name, ms, fn)
  end
  instance._cancelTimer = opts.cancelTimer or function(name)
    CancelTimer(name)
  end
  return instance
end

--- @private
--- @return { look: integer, before?: integer, due: number }|nil state
function LookTimer:_state()
  local state = self._store:get(PERSIST_KEY)
  if type(state) == "table" and tonumber(state.look) and tonumber(state.due) then
    return state
  end
  return nil
end

--- @private
--- @param seconds number
function LookTimer:_arm(seconds)
  self._setTimer(TIMER, seconds * 1000, function()
    self:_fire()
  end)
end

--- A press, programming or the Button tab showed a look: its timer starts over, and any other stops.
--- @param id integer The look shown now.
--- @param beforeId integer|nil The look shown before it.
function LookTimer:start(id, beforeId)
  local look = self._looks:get(id)
  if not (look and look.timerAfter) then
    self:cancel()
    return
  end
  local before = beforeId
  if before == look.id then
    -- Shown again: it still goes back to the look from before.
    local state = self:_state()
    before = state and tonumber(state.look) == look.id and tonumber(state.before) or nil
  end
  self._store:set(PERSIST_KEY, { look = look.id, before = before, due = self._now() + look.timerAfter })
  self:_arm(look.timerAfter)
end

--- Stop the timer: another look showed for another reason, or the driver was reset.
function LookTimer:cancel()
  self._cancelTimer(TIMER)
  if self._store:get(PERSIST_KEY) ~= nil then
    self._store:set(PERSIST_KEY, nil)
  end
end

--- At every start: set the timer for what's left of it, or fire it now if its time has passed.
function LookTimer:restore()
  local state = self:_state()
  local shown = self._shown()
  if not (state and shown and shown.id == tonumber(state.look) and shown.timerAfter) then
    self:cancel()
    return
  end
  local left = tonumber(state.due) - self._now()
  if left <= 0 then
    self:_fire()
    return
  end
  -- A clock set back can't stretch it past the look's own time.
  self:_arm(math.min(left, shown.timerAfter))
end

--- The looks a timer tries, in order: the one it names, the look before, the default look, then the
--- others in list order. The timed look and looks with no picture are left out.
--- @private
--- @param look Look The timed look.
--- @param before integer|nil
--- @return integer[] ids
function LookTimer:_targets(look, before)
  local ids, seen = {}, { [look.id] = true }
  local function add(id)
    local candidate = self._looks:get(id)
    if candidate and candidate.image and not seen[candidate.id] then
      seen[candidate.id] = true
      table.insert(ids, candidate.id)
    end
  end
  if look.timerShow ~= Looks.TIMER_BEFORE then
    add(look.timerShow)
  end
  add(before)
  add(self._looks:defaultId())
  for _, other in ipairs(self._looks:list()) do
    add(other.id)
  end
  return ids
end

--- The time is up.
--- @private
function LookTimer:_fire()
  local state = self:_state()
  self:cancel()
  local shown = self._shown()
  if not (state and shown and shown.id == tonumber(state.look) and shown.timerAfter) then
    return
  end
  if not self._allowed() then
    log:debug("Look %s's time is up, but nothing may change the look", shown.name)
    return
  end
  log:debug("Look %s's time is up", shown.name)
  if self._byValue() then
    self._release()
    return
  end
  for _, id in ipairs(self:_targets(shown, tonumber(state.before))) do
    local ok, err = self._show(id)
    if ok then
      return
    end
    log:warn("Look %s's timer could not show look %s: %s", shown.name, tostring(id), tostring(err))
  end
end

return LookTimer
