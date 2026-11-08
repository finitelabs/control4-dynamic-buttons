-- A look's timer: once its time is up, the button shows the look shown before it or another look,
-- or under By Value the look the values call for. A look a timer shows starts its own timer, so looks
-- can follow one another, and a chain stops at a look it already showed. One timer runs at a time,
-- for the shown look. The shown look, the look before it, the chain's looks and any due time are
-- kept, so a restart or an update comes back to them.

local log = require("lib.logging")
local Looks = require("dynamic_button.looks")

--- @class LookTimer
--- @field _looks Looks
--- @field _store table A persist-like store with get(key, default) and set(key, value).
--- @field _shown fun(): Look|nil The look the button shows.
--- @field _show fun(id: integer): boolean, string|nil Shows a look, which tells this nothing.
--- @field _byValue fun(): boolean Look Control is By Value.
--- @field _release fun() Lets the values pick the look again.
--- @field _allowed fun(): boolean False while nothing may change the look.
--- @field _now fun(): number The clock, in seconds.
--- @field _setTimer fun(name: string, ms: number, fn: function)
--- @field _cancelTimer fun(name: string)
local LookTimer = {}
LookTimer.__index = LookTimer

local TIMER = "LookTimer"

--- The shown look, the look shown before it, the looks its chain showed since a press, programming,
--- the Button tab or the values began it, and while its timer runs, when its time is up, in seconds.
local PERSIST_KEY = "LookTimer"

--- @class LookTimerOptions
--- @field looks Looks
--- @field store table
--- @field shown fun(): Look|nil
--- @field show fun(id: integer): boolean, string|nil
--- @field byValue fun(): boolean
--- @field release fun()
--- @field allowed fun(): boolean
--- @field now? fun(): number
--- @field setTimer? fun(name: string, ms: number, fn: function)
--- @field cancelTimer? fun(name: string)

--- Creates a new instance of the LookTimer class.
--- @param opts LookTimerOptions
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
--- @return { look: integer, before?: integer, run?: integer[], due?: number }|nil state
function LookTimer:_state()
  local state = self._store:get(PERSIST_KEY)
  if type(state) == "table" and tonumber(state.look) then
    return state
  end
  return nil
end

--- @private
--- @param state table|nil
--- @return integer[] run The looks the state's chain showed, its own look among them.
function LookTimer:_run(state)
  local run = {}
  if state and type(state.run) == "table" then
    for _, id in ipairs(state.run) do
      table.insert(run, tonumber(id))
    end
  end
  if #run == 0 and state then
    run = { tonumber(state.look) }
  end
  return run
end

--- Note the look the button shows now and the look before it. The same look shown again keeps the
--- look from before.
--- @private
--- @param id integer
--- @param beforeId integer|nil
--- @param due number|nil When its time is up, while its timer runs.
--- @param run integer[]|nil The looks its chain showed; a new chain of this look alone when nil.
function LookTimer:_record(id, beforeId, due, run)
  local before = beforeId
  if before == id then
    local state = self:_state()
    before = state and tonumber(state.look) == id and tonumber(state.before) or nil
  end
  self._store:set(PERSIST_KEY, { look = id, before = before, run = run or { id }, due = due })
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
  local after = look and look.timerAfter
  self:_record(id, beforeId, after and self._now() + after or nil)
  if after then
    self:_arm(after)
  else
    self._cancelTimer(TIMER)
  end
end

--- The values or a delete showed a look: any timer stops, and the look's own doesn't start.
--- @param id integer|nil The look shown now; nil for the driver's own icon.
--- @param beforeId integer|nil The look shown before it.
function LookTimer:shown(id, beforeId)
  self._cancelTimer(TIMER)
  if id then
    self:_record(id, beforeId, nil)
  else
    self._store:set(PERSIST_KEY, nil)
  end
end

--- A look's fields were saved. A timer counting for it ends no later than its new time allows, and
--- stops when the look no longer has one.
--- @param id integer
function LookTimer:saved(id)
  local state = self:_state()
  local due = state and tonumber(state.due)
  if not (due and tonumber(state.look) == id) then
    return
  end
  local look = self._looks:get(id)
  if not (look and look.timerAfter) then
    self._cancelTimer(TIMER)
    self:_record(id, id, nil, self:_run(state))
    return
  end
  local now = self._now()
  if now + look.timerAfter >= due then
    return
  end
  self:_record(id, id, now + look.timerAfter, self:_run(state))
  self:_arm(look.timerAfter)
end

--- Stop the timer and forget the looks: the driver was reset.
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
  if not (state and shown and shown.id == tonumber(state.look)) then
    self:cancel()
    return
  end
  local due = tonumber(state.due)
  if not due then
    return
  end
  if not shown.timerAfter then
    self._cancelTimer(TIMER)
    self:_record(shown.id, shown.id, nil, self:_run(state))
    return
  end
  local left = due - self._now()
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

--- The timer showed a look: its own timer starts, unless the chain already showed it.
--- @private
--- @param id integer
--- @param beforeId integer
--- @param run integer[] The looks the chain showed before it.
function LookTimer:_chain(id, beforeId, run)
  for _, seen in ipairs(run) do
    if seen == id then
      self:_record(id, beforeId, nil, run)
      return
    end
  end
  local chained = { unpack(run) }
  table.insert(chained, id)
  local look = self._looks:get(id)
  local after = look and look.timerAfter
  self:_record(id, beforeId, after and self._now() + after or nil, chained)
  if after then
    self:_arm(after)
  end
end

--- The time is up.
--- @private
function LookTimer:_fire()
  local state = self:_state()
  local shown = self._shown()
  if not (state and tonumber(state.due) and shown and shown.id == tonumber(state.look)) then
    return
  end
  local run = self:_run(state)
  self._cancelTimer(TIMER)
  self:_record(shown.id, shown.id, nil, run)
  if not shown.timerAfter then
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
      self:_chain(id, shown.id, run)
      return
    end
    log:warn("Look %s's timer could not show look %s: %s", shown.name, tostring(id), tostring(err))
  end
end

return LookTimer
