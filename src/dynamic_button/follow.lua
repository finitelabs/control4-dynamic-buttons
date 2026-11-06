-- Look Control's By Value: each look's Show when expression, over device variables, decides which
-- look the button shows. The first true look in the list wins, and otherwise the default look.

local log = require("lib.logging")
local Expressions = require("lib.expressions")

--- @class Follow
--- @field _looks Looks
--- @field _store table A persist-like store with get(key, default) and set(key, value).
--- @field _show fun(id: integer): boolean, string|nil Shows a look the way programming's Show Look does.
--- @field _changed fun() Tells the Button tab what changed.
--- @field _allowed fun(): boolean False while nothing may change the look.
--- @field _engine Expressions
--- @field _active boolean Look Control is By Value.
--- @field _booting boolean A variable another driver hasn't added yet may still come.
--- @field _matched integer|nil The look the values call for.
--- @field _errors table<integer, string> Why a look's expression has no result, by look id.
--- @field _showFailed table<integer, string> Why a matched look couldn't show, by look id, so it logs once.
local Follow = {}
Follow.__index = Follow

--- The look the values last showed. Kept so a hold from programming outlasts a restart.
local APPLIED_PERSIST_KEY = "FollowApplied"
local EVALUATE_TIMER = "FollowEvaluate"
local BOOT_TIMER = "FollowBootWait"

--- How soon after an expression's recompute the looks are evaluated, in milliseconds: several looks
--- reading one variable all recompute together.
local EVALUATE_MS = 50

--- @param opts { looks: Looks, store: table, show: fun(id: integer): boolean, string|nil, changed: fun(), allowed: fun(): boolean }
--- @return Follow follow
function Follow:new(opts)
  local instance = setmetatable({}, self)
  instance._looks = opts.looks
  instance._store = opts.store
  instance._show = opts.show
  instance._changed = opts.changed
  instance._allowed = opts.allowed
  instance._active = false
  instance._booting = false
  instance._matched = nil
  instance._errors = {}
  instance._showFailed = {}
  instance._engine = Expressions:new({
    getExpressions = function()
      return instance:_expressions()
    end,
    recompute = function()
      SetTimer(EVALUATE_TIMER, EVALUATE_MS, function()
        instance:evaluate()
      end)
    end,
  })
  return instance
end

--- @private
--- @return table<string, table> expressions Each look's Show when, by look id, as the engine reads them.
function Follow:_expressions()
  local expressions = {}
  for _, look in ipairs(self._looks:list()) do
    if look.showWhen then
      expressions[tostring(look.id)] = { template = look.showWhen, mode = "condition", auto = self._active }
    end
  end
  return expressions
end

--- @return integer|nil id The look the values call for.
function Follow:matched()
  return self._matched
end

--- @param id integer
--- @return string|nil error Why the look's Show when has no result.
function Follow:whenError(id)
  return self._errors[id]
end

--- Start as a load does. Other drivers add their variables as they start, so for as long as the
--- engine keeps looking for them, an expression still waiting for one holds the decision.
--- @param active boolean Look Control is By Value.
function Follow:start(active)
  self._active = active
  if not active then
    return
  end
  self._booting = true
  SetTimer(BOOT_TIMER, Expressions.RETRY_MS * Expressions.RETRY_ATTEMPTS, function()
    self._booting = false
    self:evaluate()
  end)
  self._engine:resubscribeAll()
  self:evaluate()
end

--- Look Control changed.
--- @param active boolean Look Control is By Value.
function Follow:setActive(active)
  if active == self._active then
    return
  end
  if not active then
    self:stop()
    return
  end
  self._active = true
  self._engine:resubscribeAll()
  self:evaluate()
end

--- Stop watching and forget what the values called for.
function Follow:stop()
  for _, look in ipairs(self._looks:list()) do
    self._engine:unsubscribeExpression(tostring(look.id))
  end
  CancelTimer(EVALUATE_TIMER)
  CancelTimer(BOOT_TIMER)
  self._active = false
  self._booting = false
  self._matched = nil
  self._errors = {}
  self._showFailed = {}
  self._store:set(APPLIED_PERSIST_KEY, nil)
end

--- A look was saved: its expression may have changed.
--- @param id integer
function Follow:lookSaved(id)
  self._engine:refreshExpression(tostring(id))
  self:evaluate()
end

--- A look was deleted.
--- @param id integer
function Follow:lookDeleted(id)
  self._engine:unsubscribeExpression(tostring(id))
  self:evaluate()
end

--- A device left the project. Expressions reading it have an error from now on.
--- @param id integer|string
function Follow:deviceRemoved(id)
  self._engine:handleDeviceRemoved(tonumber(id) or -1)
end

--- Number of variables a look's expression is watching.
--- @param id integer
--- @return number
function Follow:watchedCount(id)
  return self._engine:watchedCount(tostring(id))
end

--- @private
--- @return integer|nil matched The look the values call for.
--- @return boolean holding An expression before any true one is waiting for a variable that may still come.
--- @return table<integer, string> errors Why each look's expression has no result.
function Follow:_decide()
  local matched, holding, errors = nil, false, {}
  for _, look in ipairs(self._looks:list()) do
    if look.showWhen then
      local evaluation = Expressions.evaluate("condition", look.showWhen)
      if evaluation.error then
        errors[look.id] = evaluation.error
        if self._booting and not matched and not holding then
          local _, missing = Expressions.references(look.showWhen, "condition")
          holding = #missing > 0
        end
      elseif evaluation.result and not matched then
        matched = look.id
      end
    end
  end
  if not matched then
    matched = self._looks:defaultId()
  end
  return matched, holding, errors
end

--- @private
--- @param errors table<integer, string>
--- @return boolean changed
function Follow:_noteErrors(errors)
  local changed = false
  for id, message in pairs(errors) do
    if self._errors[id] ~= message then
      changed = true
      local look = self._looks:get(id)
      log:warn("Look %s: Show when: %s", look and look.name or tostring(id), message)
    end
  end
  for id in pairs(self._errors) do
    changed = changed or errors[id] == nil
  end
  self._errors = errors
  return changed
end

--- See which look the values call for, and show it if that changed.
function Follow:evaluate()
  if not self._active or not self._allowed() then
    return
  end
  local matched, holding, errors = self:_decide()
  local changed = self:_noteErrors(errors)
  if not holding then
    changed = changed or matched ~= self._matched
    self._matched = matched
    -- Only a change of match shows anything, so a look shown from programming stays until then.
    if matched == nil then
      self._store:set(APPLIED_PERSIST_KEY, nil)
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
  end
  if changed then
    self._changed()
  end
end

return Follow
