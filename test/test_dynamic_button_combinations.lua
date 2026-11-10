--- Look Control, what shows a look, the shown look's timer, the looks' links and what happens to the driver, in
--- combination under the C4 shim. Every pair of the axes below is covered by a set generated from the table, plus
--- hand-picked triples. Each case runs a fresh button with three looks against lights that act on what the button
--- sends them, and checks after each step the shown look, the Look variable and the proxy's icon, the events fired,
--- what the button sent on its links, the look timer, and at the end the Button tab. The expectations come from a
--- model of the documented rules, which names the rule behind each one.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_combinations.lua
--- COMBO_CASE=12, or a range such as COMBO_CASE=10-20, runs only those cases, to look into one.

local T = require("testlib")
local H = require("dynamic_button_harness")
local persist = require("lib.persist")
local gate = require("lib.drivercentral")

-- The shim's Base64 encoder works bit by bit, and every request to the Button tab is Base64: this one gives the same
-- text from a table, so the cases run in seconds. Checked against the shim's below.
local shimBase64Encode = C4.Base64Encode
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64Chars = {}
for i = 1, 64 do
  b64Chars[i - 1] = B64:sub(i, i)
end
function C4:Base64Encode(data)
  if type(data) ~= "string" then
    return nil
  end
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = b64Chars[math.floor(n / 262144)]
      .. b64Chars[math.floor(n / 4096) % 64]
      .. (b and b64Chars[math.floor(n / 64) % 64] or "=")
      .. (c and b64Chars[n % 64] or "=")
  end
  return table.concat(out)
end

local clock = 1000000
-- luacheck: push ignore os
os.time = function()
  return clock
end
-- luacheck: pop

--------------------------------------------------------------------------------
-- The axes
--------------------------------------------------------------------------------

--- Each axis's values in order, with the words a case's label uses. A new mode or feature adds a value here, and the
--- pairwise set grows to cover it.
local AXES = {
  {
    name = "mode",
    values = { "On Select", "Manual", "By Value", "By Link" },
  },
  {
    name = "trigger",
    values = { "press", "showLook", "next", "previous", "tabShow", "values", "links", "timer" },
    words = {
      press = "a press",
      showLook = "Show Look",
      next = "Next Look",
      previous = "Previous Look",
      tabShow = "the tab's Show",
      values = "the values",
      links = "the links",
      timer = "a timer",
    },
  },
  {
    name = "timer",
    values = { "none", "before", "chosen", "chain", "cycle" },
    words = {
      none = "no timer",
      before = "a timer to the look before",
      chosen = "a timer to a chosen look",
      chain = "a timer chain",
      cycle = "a timer cycle",
    },
  },
  {
    name = "links",
    values = { "unbound", "toggle", "separate", "rebind", "never", "answers" },
    words = {
      unbound = "links unbound",
      toggle = "one Toggle link",
      separate = "separate On and Off links",
      rebind = "links rebound to another light",
      never = "a light that never reports",
      answers = "a light that answers REQUEST_BUTTON_COLORS",
    },
  },
  {
    name = "lifecycle",
    values = {
      "none",
      "save",
      "rename",
      "reorder",
      "deleteShown",
      "deleteTarget",
      "deleteLinked",
      "import",
      "reset",
      "restart",
      "update",
      "license",
      "modeWhileStopped",
    },
  },
}

--- What each lifecycle step is called in a label.
local LIFECYCLE_WORDS = {
  none = "nothing else",
  save = "a save",
  rename = "a rename",
  reorder = "a reorder",
  deleteShown = "the shown look deleted",
  deleteTarget = "the timer's look deleted",
  deleteLinked = "a linked look deleted",
  import = "Import replacing the looks",
  reset = "Reset Driver",
  restart = "a Director restart",
  update = "a driver update",
  license = "a lapsed license",
  modeWhileStopped = "Look Control changed while stopped",
}

--- The mode a change while the driver is stopped turns each mode to.
local NEXT_MODE =
  { ["On Select"] = "Manual", ["Manual"] = "By Value", ["By Value"] = "By Link", ["By Link"] = "On Select" }

--------------------------------------------------------------------------------
-- The rules, as the docs give them
--------------------------------------------------------------------------------

local RULE = {
  firstPicture = "a look's picture shows when the button shows nothing yet",
  pressSteps = "On Select: a press shows the next look in the cycle",
  pressStays = "a press changes the look only under On Select",
  pressTaps = "a press taps the shown look's Button Link",
  showLook = "Show Look and the tab's Show show a look in every mode",
  next = "Next Look shows the next look in the cycle, wrapping",
  previous = "Previous Look shows the previous look in the cycle, wrapping",
  hold = "a look programming shows stays until the values or the links call for a different look",
  byValue = "By Value: the first look whose Show when is true shows, else the default look",
  byLink = "By Link: the first look whose bound link matches its Show while shows, else the default look",
  onlyByValue = "only By Value follows the values",
  onlyByLink = "only By Link follows the links",
  unreported = "a look with nothing bound, or whose device hasn't reported, never matches",
  activated = "By Value or By Link coming on shows the look it calls for",
  timerStarts = "a press, programming or the tab's Show starts the look's timer",
  timerStops = "showing another look stops the timer",
  followNoTimer = "a look the values or the links show runs no timer",
  timerUp = "when its time is up the timer shows its chosen look, or the look before",
  timerFallback = "with the look before gone, a timer shows the default look, or else the first with a picture",
  timerBack = "under By Value or By Link a timed look goes back to the look they call for",
  chain = "a look a timer shows starts its own timer",
  cycleStops = "a chain stops at a look it already showed",
  events = "a change of look fires Look Changed and the look's Shown event, and nothing else does",
  save = "saving a look as it is changes nothing",
  rename = "renaming a look renames its event and its link, keeps it bound and asks its device again",
  reorder = "moving a look changes which look is checked first, and the cycle",
  deleteShown = "deleting the shown look shows the look the values or links call for, or the first remaining look",
  deleteTarget = "deleting a timer's chosen look turns the timer to the look before",
  deleteLink = "deleting a look removes its Button Link and its state",
  import = "Import replacing the looks brings their fields and timers without their links",
  reset = "Reset Driver deletes every look, returns Look Control to Manual and fires nothing",
  restart = "the shown look, a hold, the links' states and the timer's time stay through a restart and an update",
  stoppedMode = "Look Control changed while the driver was stopped takes effect as it starts",
  startChange = "events fire as the driver starts only when the look changes then",
  timerRanOut = "a time that runs out while the driver is stopped takes effect as it starts",
  requestOnBind = "a link bound asks its device for its state and colors",
  requestAtStart = "the driver's start asks each bound link's device for its state and colors",
  unlicensed = "without a license the button shows its own icon and no look changes",
  licensed = "a license back shows the look, and what the values or the links call for",
  burst = "a light's reports for each of its links settle before the links pick a look",
}

--------------------------------------------------------------------------------
-- The model: what the docs say the button does
--------------------------------------------------------------------------------

--- @class Model
local Model = {}
Model.__index = Model

--- @return Model
function Model.new()
  return setmetatable({
    mode = "Manual",
    licensed = true,
    list = {},
    looks = {},
    default = nil,
    shown = nil,
    before = nil,
    timer = nil,
    applied = nil,
    matched = nil,
    value = "a",
    bound = {},
    reports = {},
    colors = {},
    events = {},
    sends = {},
    why = {},
  }, Model)
end

--- Start a new step's record.
function Model:mark()
  self.events, self.sends, self.why = {}, {}, {}
  self.stepShown = self.shown
end

--- @param rule string
function Model:because(rule)
  for _, seen in ipairs(self.why) do
    if seen == rule then
      return
    end
  end
  table.insert(self.why, rule)
end

function Model:following()
  return self.mode == "By Value" or self.mode == "By Link"
end

--- @param key string|nil
--- @return string name The look's name, "" for none.
function Model:name(key)
  local look = key and self.looks[key]
  return look and look.name or ""
end

--- @param id integer|nil
--- @return string|nil key
function Model:keyOfId(id)
  for key, look in pairs(self.looks) do
    if look.id == id then
      return key
    end
  end
  return nil
end

--- @return string description What the proxy shows: the shown look's name, or "" for the driver's own icon.
function Model:icon()
  return self.licensed and self:name(self.shown) or ""
end

--- The button shows another look, or its own icon for nil.
--- @param key string|nil
--- @param rule string|nil
function Model:setShown(key, rule)
  if key == self.shown then
    return
  end
  self.before = self.shown
  self.shown = key
  table.insert(self.events, "Look Changed")
  if key then
    table.insert(self.events, self.looks[key].name .. " Shown")
  end
  if rule then
    self:because(rule)
  end
  self:because(RULE.events)
end

--- A press, programming or the tab's Show showed the look.
--- @param key string
function Model:startTimer(key)
  local look = self.looks[key]
  if self.timer and self.timer.due and self.timer.look ~= key then
    self:because(RULE.timerStops)
  end
  if look.timer then
    self.timer = { look = key, due = clock + look.timer.after, delay = look.timer.after, run = { key } }
    self:because(RULE.timerStarts)
  else
    self.timer = { look = key, run = { key } }
  end
end

--- The values, the links or a delete showed the look.
--- @param key string|nil
function Model:stopTimer(key)
  if self.timer and self.timer.due then
    self:because(RULE.followNoTimer)
  end
  self.timer = key and { look = key, run = { key } } or nil
end

--- @return boolean armed
function Model:armed()
  return self.timer ~= nil and self.timer.due ~= nil
end

--- @param key string
--- @param rule string
function Model:programShow(key, rule)
  local look = self.looks[key]
  if not (self.licensed and look and look.image) then
    return
  end
  self:because(rule)
  self:setShown(key)
  self:startTimer(key)
  if self:following() then
    self:because(RULE.hold)
  end
end

--- Next Look (1) or Previous Look (-1), from the shown look's place.
--- @param step integer
--- @param rule string
function Model:step(step, rule)
  if not self.licensed then
    return
  end
  local count = #self.list
  local from = step > 0 and 0 or count + 1
  for i, key in ipairs(self.list) do
    if key == self.shown then
      from = i
    end
  end
  for k = 1, count do
    local key = self.list[(from - 1 + step * k) % count + 1]
    if self.looks[key].image then
      self:because(rule)
      self:setShown(key)
      self:startTimer(key)
      return
    end
  end
end

function Model:press()
  if not self.licensed then
    self:because(RULE.unlicensed)
    return
  end
  local key = self.shown
  if key and self.bound[key] then
    table.insert(self.sends, "DO_PUSH " .. self.looks[key].name)
    table.insert(self.sends, "DO_CLICK " .. self.looks[key].name)
    self:because(RULE.pressTaps)
  end
  if self.mode == "On Select" then
    self:step(1, RULE.pressSteps)
  else
    self:because(RULE.pressStays)
  end
end

--- @param key string
--- @return boolean|nil on The link's state, when the device bound to it now reported it.
function Model:trusted(key)
  local bound, report = self.bound[key], self.reports[key]
  if bound and report and report.device == bound then
    return report.on
  end
  return nil
end

--- @param key string
--- @return table|nil colors The link's colors, when the device bound to it now gave them.
function Model:trustedColors(key)
  local bound, colors = self.bound[key], self.colors[key]
  if bound and colors and colors.device == bound then
    return colors
  end
  return nil
end

--- @return string|nil key The look the values or the links call for.
function Model:decide()
  for _, key in ipairs(self.list) do
    local look = self.looks[key]
    if self.mode == "By Value" then
      if look.when(self.value) then
        return key
      end
    else
      local on = self:trusted(key)
      if on ~= nil and on == (look.showWhile == "on") then
        return key
      end
    end
  end
  return self.default
end

--- Under By Value or By Link, show the look they call for when it differs from the one they called for last.
function Model:evaluate()
  if not (self:following() and self.licensed) then
    return
  end
  local match = self:decide()
  self.matched = match
  if match == nil then
    self.applied = nil
    return
  end
  if match == self.applied or not self.looks[match].image then
    return
  end
  self:because(self.mode == "By Value" and RULE.byValue or RULE.byLink)
  self:setShown(match)
  self:stopTimer(match)
  self.applied = match
end

--- @param mode string
function Model:setMode(mode)
  if mode == self.mode then
    return
  end
  if self:following() then
    self.applied, self.matched = nil, nil
  end
  self.mode = mode
  if self:following() then
    self:because(RULE.activated)
    self:evaluate()
  end
end

--- @param key string
--- @param id integer
--- @param spec table
function Model:add(key, id, spec)
  self.looks[key] = {
    key = key,
    id = id,
    name = spec.name,
    when = spec.when,
    showWhen = spec.showWhen,
    showWhile = spec.showWhile,
    timer = spec.timer,
    image = false,
  }
  table.insert(self.list, key)
  if spec.isDefault then
    self.default = key
  end
  self:evaluate()
end

--- @param key string
function Model:image(key)
  self.looks[key].image = true
  if self.shown == nil then
    self:setShown(key, RULE.firstPicture)
  end
  self:evaluate()
end

--- @param key string
--- @param timer { after: integer, show: string }|nil
function Model:setTimer(key, timer)
  self.looks[key].timer = timer
  self:evaluate()
end

--- @param key string
--- @param device integer
function Model:bind(key, device)
  self.bound[key] = device
  table.insert(self.sends, "REQUEST_BUTTON_COLORS " .. self.looks[key].name)
  self:because(RULE.requestOnBind)
  self:because(RULE.unreported)
  self:evaluate()
end

--- @param key string
function Model:unbind(key)
  self.bound[key] = nil
  self:because(RULE.unreported)
  self:evaluate()
end

--- @param key string
--- @param on boolean
--- @param device integer
function Model:report(key, on, device)
  self.reports[key] = { on = on, device = device }
  if self.mode == "By Link" then
    self:because(RULE.burst)
  end
end

--- @param key string
--- @param on string
--- @param off string
--- @param device integer
function Model:giveColors(key, on, off, device)
  self.colors[key] = { on = on, off = off, device = device }
end

--- @param value string
function Model:setValue(value)
  self.value = value
  self:because(self.mode == "By Value" and RULE.byValue or RULE.onlyByValue)
  self:evaluate()
end

--- The shown look's time is up.
function Model:fire()
  local t = self.timer
  if not (t and t.due) then
    return
  end
  local run = t.run
  self.timer = { look = t.look, run = run }
  if not self.licensed then
    self:because(RULE.unlicensed)
    return
  end
  if self:following() then
    self:because(RULE.timerBack)
    self.applied = nil
    self:evaluate()
    return
  end
  local look = self.looks[t.look]
  local targets, seen = {}, { [t.look] = true }
  local function add(key)
    if key and self.looks[key] and self.looks[key].image and not seen[key] then
      seen[key] = true
      table.insert(targets, key)
    end
  end
  if look.timer.show ~= "before" then
    add(look.timer.show)
  end
  add(self.before)
  add(self.default)
  for _, key in ipairs(self.list) do
    add(key)
  end
  local target = targets[1]
  if not target then
    return
  end
  if target == look.timer.show or target == self.before then
    self:because(RULE.timerUp)
  else
    self:because(RULE.timerFallback)
  end
  self:setShown(target)
  for _, key in ipairs(run) do
    if key == target then
      self:because(RULE.cycleStops)
      self.timer = { look = target, run = run }
      return
    end
  end
  local chained = { unpack(run) }
  table.insert(chained, target)
  local after = self.looks[target].timer and self.looks[target].timer.after
  if after then
    self:because(RULE.chain)
    self.timer = { look = target, due = clock + after, delay = after, run = chained }
  else
    self.timer = { look = target, run = chained }
  end
end

--- @param key string
function Model:save(key)
  self:because(RULE.save)
  self:evaluate()
end

--- @param key string
--- @param name string
function Model:rename(key, name)
  self.looks[key].name = name
  self:because(RULE.rename)
  if self.bound[key] then
    table.insert(self.sends, "REQUEST_BUTTON_COLORS " .. name)
  end
  self:evaluate()
end

--- @param keys string[]
function Model:reorder(keys)
  self.list = keys
  self:because(RULE.reorder)
  self:evaluate()
end

--- @param key string
function Model:delete(key)
  if not self.looks[key] then
    return
  end
  local wasShown = self.shown == key
  for i, other in ipairs(self.list) do
    if other == key then
      table.remove(self.list, i)
      break
    end
  end
  self.looks[key] = nil
  if self.default == key then
    self.default = nil
  end
  for _, other in pairs(self.looks) do
    if other.timer and other.timer.show == key then
      other.timer.show = "before"
      self:because(RULE.deleteTarget)
    end
  end
  if self.bound[key] then
    self:because(RULE.deleteLink)
  end
  self.bound[key], self.reports[key], self.colors[key] = nil, nil, nil
  if wasShown then
    local replacement
    if self:following() and self.licensed then
      local match = self:decide()
      if match and self.looks[match].image then
        replacement = match
      end
    end
    if not replacement then
      for _, other in ipairs(self.list) do
        if self.looks[other].image then
          replacement = other
          break
        end
      end
    end
    self:because(RULE.deleteShown)
    self:setShown(replacement)
    self.timer = replacement and { look = replacement, run = { replacement } } or nil
    self.applied = nil
  end
  self:evaluate()
end

function Model:reset()
  self.list, self.looks, self.default = {}, {}, nil
  self.shown, self.before, self.timer, self.applied, self.matched = nil, nil, nil, nil, nil
  self.bound, self.reports, self.colors = {}, {}, {}
  self.mode = "Manual"
  self:because(RULE.reset)
end

--- A Director restart or a driver update, with Look Control changed while stopped when `mode` is given.
--- @param mode string|nil
function Model:restart(mode)
  self.licensed = true
  self:because(RULE.restart)
  if mode and mode ~= self.mode then
    self.applied = nil
    self.mode = mode
    self:because(RULE.stoppedMode)
  end
  if not self:following() then
    self.applied, self.matched = nil, nil
  end
  local fired = #self.events
  if self:following() then
    self:evaluate()
  end
  local t = self.timer
  if t and t.due then
    if t.look ~= self.shown then
      self.timer = nil
    elseif clock >= t.due then
      self:because(RULE.timerRanOut)
      self:fire()
    else
      t.delay = math.min(t.due - clock, self.looks[t.look].timer.after)
    end
  end
  if #self.events > fired then
    self:because(RULE.startChange)
  end
  for _, key in ipairs(self.list) do
    if self.bound[key] then
      table.insert(self.sends, "REQUEST_BUTTON_COLORS " .. self.looks[key].name)
      self:because(RULE.requestAtStart)
    end
  end
end

function Model:lapse()
  self.licensed = false
  self:because(RULE.unlicensed)
end

function Model:relicense()
  self.licensed = true
  self:because(RULE.licensed)
  self:evaluate()
end

--- @param base number The case's start on the clock.
--- @return string timer The look timer as "<look>'s, for <s>s, due at +<s>s", or "none".
function Model:timerText(base)
  if not self:armed() then
    return "none"
  end
  return string.format(
    "%s's, for %ss, due at +%ss",
    self:name(self.timer.look),
    self.timer.delay,
    self.timer.due - base
  )
end

--- @param key string
--- @return string line The look as the Button tab lists it.
function Model:tabLine(key)
  local look = self.looks[key]
  local line = look.name
  if self.mode == "By Link" then
    local on = self:trusted(key)
    line = line .. " · " .. (not self.bound[key] and "not bound" or on == nil and "no state" or on and "on" or "off")
    local colors = self:trustedColors(key)
    if colors then
      line = line .. " · " .. tostring(colors.on) .. "/" .. tostring(colors.off)
    end
  end
  return line
end

--- @return table tab What the Button tab shows.
function Model:tab()
  local lines = {}
  for _, key in ipairs(self.list) do
    table.insert(lines, self:tabLine(key))
  end
  return {
    shown = self:name(self.shown),
    lookControl = self.mode,
    matched = self:following() and self:name(self.matched) or "",
    looks = lines,
  }
end

--- @type Model
local model

--------------------------------------------------------------------------------
-- The world: lights bound to the looks' links, which act on what the button sends
--------------------------------------------------------------------------------

--- A light's button links, as a keypad button binds to them.
local LIGHT_ON, LIGHT_OFF, LIGHT_TOGGLE = 300, 301, 302

--- What the button sent on a link, for the device bound to it.
local wire = {}
--- What the devices send back, delivered once the button's call returns, as Director does.
local inbox = {}
--- What the button sent on its links this step, as "<command> <look>".
local sent = {}
--- What the proxy shows now: the shown look's name, or "" for the driver's own icon.
local iconNow = nil

--- @class Light
local Light = {}
Light.__index = Light

--- @param id integer
--- @param opts { reports: boolean, answers: boolean, colors?: table, form: fun(on: boolean): any }
--- @return Light
function Light.new(id, opts)
  return setmetatable(
    { id = id, on = false, reports = opts.reports, answers = opts.answers, form = opts.form, colors = opts.colors },
    Light
  )
end

--- @param link integer
--- @return boolean on The link's LED: the On and Toggle links' are on while the light is, the Off link's while it isn't.
function Light:led(link)
  if link == LIGHT_OFF then
    return not self.on
  end
  return self.on
end

--- @param binding integer The button's link.
--- @param command string
--- @param params table
--- @param extra table What the model hears.
function Light:tell(binding, command, params, extra)
  table.insert(inbox, { light = self, binding = binding, command = command, params = params, heard = extra })
end

--- The button's links bound to this light, in the order Director made them.
--- @return { binding: integer, link: integer }[]
function Light:consumers()
  local found = {}
  for _, c in ipairs(ShimConnections()) do
    if c.provider == self.id and c.consumer == H.DEVICE_ID then
      table.insert(found, { binding = c.consumerBinding, link = c.providerBinding })
    end
  end
  return found
end

--- The light switches, from a tap or from anywhere else, and a light that reports tells each bound link its LED.
--- @param on boolean
function Light:switch(on)
  if self.on == on then
    return
  end
  self.on = on
  if self.reports then
    for _, c in ipairs(self:consumers()) do
      local led = self:led(c.link)
      self:tell(c.binding, "MATCH_LED_STATE", { STATE = self.form(led) }, { on = led })
    end
  end
end

--- @param command string
--- @param link integer The light's link it came in on.
--- @param binding integer The button's link it came from.
function Light:receive(command, link, binding)
  if command == "DO_PUSH" then
    if link == LIGHT_TOGGLE then
      self:switch(not self.on)
    else
      self:switch(link == LIGHT_ON)
    end
  elseif command == "REQUEST_BUTTON_COLORS" and self.answers then
    self:tell(
      binding,
      "BUTTON_COLORS",
      { ON_COLOR = self.colors.on, OFF_COLOR = self.colors.off, BUTTON_ID = tostring(link) },
      { colors = { on = self.colors.on:lower():gsub("#", ""), off = self.colors.off:lower():gsub("#", "") } }
    )
    local led = self:led(link)
    self:tell(binding, "MATCH_LED_STATE", { STATE = self.form(led) }, { on = led })
  end
end

local lamp = Light.new(900, {
  reports = true,
  form = function(on)
    return on
  end,
})
local other = Light.new(901, {
  reports = true,
  form = function(on)
    return on and "True" or "False"
  end,
})
local mute = Light.new(902, { reports = false, form = tostring })
local answering = Light.new(903, {
  reports = true,
  answers = true,
  form = function(on)
    return on and 1 or 0
  end,
  colors = { on = "FFCC00", off = "#202020" },
})
local LIGHTS = { [lamp.id] = lamp, [other.id] = other, [mute.id] = mute, [answering.id] = answering }

--- @param binding integer
--- @return string|nil key The look whose link the binding is.
local function keyOfBinding(binding)
  local record = ShimDynamicBindings()[binding]
  local id = record and tonumber(record.name:match("%((%d+)%)$"))
  return id and model:keyOfId(id) or nil
end

--- @param key string
--- @return integer bindingId The look's Button Link, found by its name as Composer lists it.
local function linkOf(key)
  local id = tostring(model.looks[key].id)
  for bindingId, record in pairs(ShimDynamicBindings()) do
    if record.class == "BUTTON_LINK" and record.name:match("%((%d+)%)$") == id then
      return bindingId
    end
  end
  error("look " .. key .. " has no Button Link")
end

-- Every message the button sends: the proxy's icon, and anything on a link, which goes to the device bound to it.
local harnessSend = C4.SendToProxy
function C4:SendToProxy(binding, command, params, message, allowEmpty)
  harnessSend(self, binding, command, params, message, allowEmpty)
  if binding == 5001 then
    if command == "ICON_CHANGED" then
      iconNow = params.icon_description
    end
    return
  end
  local record = ShimDynamicBindings()[binding]
  table.insert(sent, command .. " " .. (record and record.name:gsub(" %(%d+%)$", "") or tostring(binding)))
  table.insert(wire, { binding = binding, command = command })
end

-- The look timer's delay as armed, by its handle.
local delays = {}
local setTimer = C4.SetTimer
function C4:SetTimer(ms, fn, repeating)
  local handle = setTimer(self, ms, fn, repeating)
  delays[handle] = ms
  return handle
end

-- Every key the driver stores, so a fresh install can forget them all.
local persistKeys = {}
local persistSet = C4.PersistSetValue
function C4:PersistSetValue(key, ...)
  persistKeys[key] = true
  return persistSet(self, key, ...)
end

--- Run every timer but the look's, three times over: a report or a variable's change arms an evaluation.
local function settle()
  for _ = 1, 3 do
    local names = {}
    for name in pairs(Timer) do
      if type(name) == "string" and name ~= "LookTimer" then
        table.insert(names, name)
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      ExpireTimer(name)
    end
  end
end

--- Deliver what the button sent to the lights, and what they send back, until both settle.
local function deliver()
  local heard = false
  for _ = 1, 500 do
    if #wire > 0 then
      local message = table.remove(wire, 1)
      for _, c in ipairs(ShimConnections()) do
        if c.consumer == H.DEVICE_ID and c.consumerBinding == message.binding and LIGHTS[c.provider] then
          LIGHTS[c.provider]:receive(message.command, c.providerBinding, message.binding)
        end
      end
    elseif #inbox > 0 then
      local message = table.remove(inbox, 1)
      local key = keyOfBinding(message.binding)
      ReceivedFromProxy(message.binding, message.command, message.params)
      if key and message.heard.colors then
        model:giveColors(key, message.heard.colors.on, message.heard.colors.off, message.light.id)
      elseif key then
        model:report(key, message.heard.on, message.light.id)
        heard = true
      end
    else
      settle()
      if heard then
        heard = false
        model:evaluate()
      end
      if #wire == 0 and #inbox == 0 then
        return
      end
    end
  end
  error("the button and the lights never settled")
end

--------------------------------------------------------------------------------
-- A fresh button
--------------------------------------------------------------------------------

--- The doorbell device whose variable the looks' Show when read.
local BELL, BELL_STATE = 100, 1001
local bellValue = "a"

local function setDevices()
  ShimSetDevices({
    [BELL] = {
      deviceName = "Bell",
      roomName = "Porch",
      variables = { [tostring(BELL_STATE)] = { name = "STATE", value = bellValue, type = "STRING" } },
    },
    [H.DEVICE_ID] = { deviceName = "This Button", roomName = "Porch", variables = {} },
  })
end

local running = false

--- A fresh install: nothing the last case stored, bound or declared is left.
local function fresh()
  if running then
    OnDriverDestroyed()
  end
  if gate._timer then
    gate._timer:Cancel()
  end
  ShimPersistLand()
  for key in pairs(persistKeys) do
    C4:PersistDeleteValue(key)
  end
  persist._persist, persist._pending, persist._armed = {}, {}, {}
  ShimRestartDirector()
  ShimResetEvents()
  ShimResetDynamicBindings()
  for name in pairs(TC) do
    if type(name) == "string" and name:match("^CONDITIONAL_%d+$") then
      TC[name] = nil
    end
  end
  for _, handlers in ipairs({ OBC, OWVC }) do
    for id in pairs(handlers) do
      if type(id) == "number" then
        handlers[id] = nil
      end
    end
  end
  for _, dir in ipairs({ H.served(), H.stored() }) do
    for name in pairs(dir) do
      dir[name] = nil
    end
  end
  Properties = H.defaultProperties()
  DC_X = nil
  wire, inbox, sent = {}, {}, {}
  lamp.on, other.on, mute.on, answering.on = false, true, false, true
  bellValue = "a"
  setDevices()
  model = Model.new()
  H.start()
  running = true
end

--------------------------------------------------------------------------------
-- What the test does to the button, and to the model with it
--------------------------------------------------------------------------------

--- The three looks: their names and what they show while.
local SPECS = {
  A = {
    name = "Alpha",
    showWhen = 'PARAM{100,1001} == "a"',
    when = function(v)
      return v == "a"
    end,
  },
  B = {
    name = "Bravo",
    showWhen = 'PARAM{100,1001} ~= "a"',
    when = function(v)
      return v ~= "a"
    end,
  },
  C = {
    name = "Charlie",
    showWhen = 'PARAM{100,1001} == "c"',
    isDefault = true,
    when = function(v)
      return v == "c"
    end,
  },
}

--- Each links setup: each look's Show while, the light and its links they bind to, and what happens then.
local LINKS = {
  unbound = { showWhile = { A = "on", B = "off", C = "off" } },
  toggle = {
    showWhile = { A = "on", B = "off", C = "off" },
    light = lamp,
    links = { A = LIGHT_TOGGLE, B = LIGHT_TOGGLE, C = LIGHT_TOGGLE },
    switchOn = true,
  },
  separate = {
    showWhile = { A = "off", B = "off", C = "off" },
    light = lamp,
    links = { A = LIGHT_OFF, B = LIGHT_ON, C = LIGHT_ON },
    switchOn = true,
  },
  rebind = {
    showWhile = { A = "on", B = "off", C = "off" },
    light = lamp,
    links = { A = LIGHT_TOGGLE, B = LIGHT_TOGGLE, C = LIGHT_TOGGLE },
    switchOn = true,
    rebindTo = other,
  },
  never = {
    showWhile = { A = "on", B = "off", C = "off" },
    light = mute,
    links = { A = LIGHT_TOGGLE, B = LIGHT_TOGGLE, C = LIGHT_TOGGLE },
    switchOn = true,
  },
  answers = {
    showWhile = { A = "on", B = "off", C = "off" },
    light = answering,
    links = { A = LIGHT_TOGGLE, B = LIGHT_TOGGLE, C = LIGHT_TOGGLE },
  },
}

--- @param key string
--- @param name string|nil A new name.
--- @return table fields The look's fields as the Button tab sends them all on a save.
local function fieldsOf(key, name)
  local look = model.looks[key]
  local timer = look.timer
  return H.lookFields(name or look.name, {
    id = look.id,
    showWhen = look.showWhen,
    showWhile = look.showWhile,
    isDefault = model.default == key,
    timerAfter = timer and timer.after or nil,
    timerShow = timer and (timer.show == "before" and "before" or model.looks[timer.show].id) or nil,
  })
end

--- @param key string
--- @return string label The look as programming lists it.
local function label(key)
  return model.looks[key].name .. " (" .. model.looks[key].id .. ")"
end

local act = {}

--- @param key string
--- @param spec table
function act.addLook(key, spec)
  local fields = H.lookFields(spec.name, {
    showWhen = spec.showWhen,
    showWhile = spec.showWhile,
    isDefault = spec.isDefault == true,
    timerAfter = spec.timer and spec.timer.after or nil,
    timerShow = spec.timer and spec.timer.showId or nil,
  })
  H.tab("_SAVE_LOOK", fields)
  local id = tonumber(H.lastUi("SAVED").look)
  model:add(key, id, spec)
  deliver()
  H.sendImage(id, H.png(spec.name))
  model:image(key)
  deliver()
end

--- @param key string
--- @param timer { after: integer, show: string }|nil
function act.setTimer(key, timer)
  model.looks[key].timer = timer
  H.tab("_SAVE_LOOK", fieldsOf(key))
  model:setTimer(key, timer)
  deliver()
end

--- @param mode string
function act.setMode(mode)
  Properties["Look Control"] = mode
  OnPropertyChanged("Look Control")
  model:setMode(mode)
  deliver()
end

--- @param key string
function act.showLook(key)
  EC.Show_Look({ Look = label(key) })
  model:programShow(key, RULE.showLook)
  deliver()
end

--- @param key string
--- @param light Light
--- @param link integer
function act.bind(key, light, link)
  C4:Bind(light.id, link, H.DEVICE_ID, linkOf(key), "BUTTON_LINK")
  OnBindingChanged(linkOf(key), "BUTTON_LINK", true, light.id, link)
  model:bind(key, light.id)
  deliver()
end

--- @param key string
function act.unbind(key)
  local provider = C4:GetBoundProviderDevice(H.DEVICE_ID, linkOf(key))
  C4:Unbind(H.DEVICE_ID, linkOf(key))
  OnBindingChanged(linkOf(key), "BUTTON_LINK", false, provider, LIGHT_TOGGLE)
  model:unbind(key)
  deliver()
end

--- @param light Light
--- @param on boolean
function act.switchLight(light, on)
  light:switch(on)
  deliver()
end

function act.press()
  H.press()
  model:press()
  deliver()
end

--- @param value string
function act.setValue(value)
  bellValue = value
  setDevices()
  OnWatchedVariableChanged(BELL, BELL_STATE, value)
  model:setValue(value)
  deliver()
end

--- @param base number
--- @return string timer The driver's look timer as Model:timerText gives it.
local function driverTimer(base)
  local handle = Timer.LookTimer
  local state = persist:get("LookTimer")
  local due = type(state) == "table" and tonumber(state.due) or nil
  if not handle and not due then
    return "none"
  end
  local key = type(state) == "table" and model:keyOfId(tonumber(state.look))
  local name = key and model:name(key) or tostring(type(state) == "table" and state.look)
  local armed = handle and delays[handle] and string.format("for %ss", math.floor(delays[handle] / 1000))
  return string.format("%s's, %s, due at +%ss", name, armed or "not armed", due and tostring(due - base) or "none")
end

--------------------------------------------------------------------------------
-- One case
--------------------------------------------------------------------------------

--- @class Case
--- @field mode string
--- @field trigger string
--- @field timer string
--- @field links string
--- @field lifecycle string[]
--- @field pressPartway? boolean A press between what happens to the driver and the time running out.
--- @field label? string

--- The looks each role names: the look shown first, the look the trigger shows, and the other.
--- @param trigger string
--- @return { S: string, T: string, O: string } roles
local function rolesFor(trigger)
  if trigger == "previous" then
    return { S = "C", T = "B", O = "A" }
  end
  return { S = "A", T = "B", O = "C" }
end

--- @return string|nil name The look the Button tab last heard is shown this step: from a SHOWN, or from a message
--- carrying the whole state. Nil when it heard of none.
--- @return boolean heard
local function tabHeard()
  for i = #H.ui, 1, -1 do
    local message = H.ui[i]
    if message.command == "SHOWN" then
      return model:name(model:keyOfId(tonumber(message.params.shown))), true
    elseif message.params.state then
      return model:name(model:keyOfId(message.params.state.shown)), true
    end
  end
  return nil, false
end

--- Check the button against the model after a step, and start the next step's record.
--- @param base number
--- @param step string
local function expectStep(base, step)
  local why = #model.why > 0 and table.concat(model.why, "; ") or "nothing changes the look"
  local name = model:name(model.shown)
  T.eq(
    string.format("%s: shows %s [%s]", step, name ~= "" and name or "the driver's own icon", why),
    { variable = Variables["Look"], property = Properties["Shown Look"], icon = iconNow },
    { variable = name, property = name, icon = model:icon() }
  )
  T.eq(string.format("%s: events [%s]", step, RULE.events), H.fired, model.events)
  T.eq(
    string.format(
      "%s: sent on the links [%s; %s; nothing on an unbound link]",
      step,
      RULE.pressTaps,
      RULE.requestOnBind
    ),
    sent,
    model.sends
  )
  T.eq(string.format("%s: the look timer", step), driverTimer(base), model:timerText(base))
  if model.shown ~= model.stepShown then
    local heard, told = tabHeard()
    T.eq(
      string.format("%s: the Button tab hears the look the button shows now", step),
      told and heard or "nothing",
      name
    )
  end
  H.mark()
  sent = {}
  model:mark()
end

--- @param c Case
--- @param r table
local function setup(c, r)
  local links = LINKS[c.links]
  for _, key in ipairs({ "A", "B", "C" }) do
    local spec = {}
    for field, value in pairs(SPECS[key]) do
      spec[field] = value
    end
    spec.showWhile = links.showWhile[key]
    act.addLook(key, spec)
  end
  -- The timers, by role: the trigger's look times out to the look before, or to the other look, which may time out
  -- in turn to the first look, or back to the trigger's look.
  local timers = {}
  if c.timer == "before" then
    timers[r.T] = { after = 30, show = "before" }
  elseif c.timer == "chosen" then
    timers[r.T] = { after = 30, show = r.O }
  elseif c.timer == "chain" then
    timers[r.T] = { after = 30, show = r.O }
    timers[r.O] = { after = 20, show = r.S }
  elseif c.timer == "cycle" then
    timers[r.T] = { after = 30, show = r.O }
    timers[r.O] = { after = 20, show = r.T }
  end
  if c.trigger == "timer" then
    timers[r.S] = { after = 15, show = r.T }
  end
  for _, key in ipairs({ "A", "B", "C" }) do
    if timers[key] then
      act.setTimer(key, timers[key])
    end
  end
  if links.light then
    for _, key in ipairs({ "A", "B", "C" }) do
      act.bind(key, links.light, links.links[key])
    end
    if links.switchOn then
      act.switchLight(links.light, true)
    end
    if links.rebindTo then
      for _, key in ipairs({ "A", "B", "C" }) do
        act.unbind(key)
        act.bind(key, links.rebindTo, links.links[key])
      end
    end
  end
  act.setMode(c.mode)
  act.showLook(r.S)
end

--- @param c Case
--- @param r table
local function trigger(c, r)
  if c.trigger == "press" then
    act.press()
  elseif c.trigger == "showLook" then
    act.showLook(r.T)
  elseif c.trigger == "next" then
    EC.Next_Look()
    model:step(1, RULE.next)
    deliver()
  elseif c.trigger == "previous" then
    EC.Previous_Look()
    model:step(-1, RULE.previous)
    deliver()
  elseif c.trigger == "tabShow" then
    H.tab("_SHOW_LOOK", { id = model.looks[r.T].id })
    model:programShow(r.T, RULE.showLook)
    deliver()
  elseif c.trigger == "values" then
    act.setValue("c")
  elseif c.trigger == "links" then
    local links = LINKS[c.links]
    if c.mode ~= "By Link" then
      model:because(RULE.onlyByLink)
    end
    act.switchLight(links.rebindTo or links.light or lamp, false)
  elseif c.trigger == "timer" then
    clock = model.timer.due
    ShimFireTimers()
    model:fire()
    deliver()
  end
end

--- Restart the driver, as Director does, with Look Control changed while it was stopped when `mode` is given.
--- @param mode string|nil
--- @param update boolean|nil A driver update rather than a Director restart.
local function restart(mode, update)
  if mode then
    Properties["Look Control"] = mode
  end
  clock = clock + 5
  if update then
    H.update()
  else
    H.restart()
  end
  model:restart(mode)
  deliver()
end

--- Import replacing the looks, as the Button tab's page replays it: the looks deleted, the shown look last, then
--- each look given again in order with its picture, a timer naming a look given after it set once that look is.
local function import()
  local items = {}
  for _, key in ipairs(model.list) do
    local look = model.looks[key]
    table.insert(items, {
      key = key,
      name = look.name,
      showWhen = look.showWhen,
      showWhile = look.showWhile,
      when = look.when,
      timer = look.timer and { after = look.timer.after, show = look.timer.show } or nil,
      isDefault = model.default == key,
    })
  end
  local order = {}
  for _, key in ipairs(model.list) do
    if key ~= model.shown then
      table.insert(order, key)
    end
  end
  table.insert(order, model.shown)
  for _, key in ipairs(order) do
    H.tab("_DELETE_LOOK", { id = model.looks[key].id })
    model:delete(key)
    deliver()
  end
  model:because(RULE.import)
  local given, waiting = {}, {}
  for _, item in ipairs(items) do
    local timer = item.timer
    local spec = {
      name = item.name,
      showWhen = item.showWhen,
      showWhile = item.showWhile,
      when = item.when,
      isDefault = item.isDefault,
    }
    if timer then
      local named = timer.show ~= "before" and given[timer.show]
      spec.timer = {
        after = timer.after,
        show = named and timer.show or "before",
        showId = named and model.looks[timer.show].id or "before",
      }
      if timer.show ~= "before" and not named then
        table.insert(waiting, { key = item.key, timer = timer })
      end
    end
    act.addLook(item.key, spec)
    given[item.key] = true
  end
  for _, wait in ipairs(waiting) do
    act.setTimer(wait.key, { after = wait.timer.after, show = wait.timer.show })
  end
end

--- @param c Case
--- @param r table
--- @param step string
local function lifecycle(c, r, step)
  local verb, arg = step:match("^(%a+):(.+)$")
  verb = verb or step
  if verb == "none" then
    return
  elseif verb == "save" then
    if model.shown then
      H.tab("_SAVE_LOOK", fieldsOf(model.shown))
      model:save(model.shown)
    end
  elseif verb == "rename" then
    if model.shown then
      local name = model.looks[model.shown].name .. " 2"
      H.tab("_SAVE_LOOK", fieldsOf(model.shown, name))
      model:rename(model.shown, name)
    end
  elseif verb == "reorder" then
    local reversed = {}
    for i = #model.list, 1, -1 do
      table.insert(reversed, model.list[i])
    end
    local ids = {}
    for _, key in ipairs(reversed) do
      table.insert(ids, model.looks[key].id)
    end
    H.tab("_ORDER_LOOKS", { ids = ids })
    model:reorder(reversed)
  elseif verb == "deleteShown" or verb == "deleteTarget" or verb == "deleteLinked" then
    local key = verb == "deleteShown" and model.shown or verb == "deleteTarget" and r.O or "A"
    if key and model.looks[key] then
      H.tab("_DELETE_LOOK", { id = model.looks[key].id })
      model:delete(key)
    end
  elseif verb == "import" then
    import()
  elseif verb == "reset" then
    EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
    model:reset()
  elseif verb == "restart" then
    restart()
  elseif verb == "update" then
    restart(nil, true)
  elseif verb == "license" then
    DC_X = 0
    gate:_set(false)
    model:lapse()
  elseif verb == "modeWhileStopped" then
    restart(NEXT_MODE[model.mode])
  elseif verb == "stopped" then
    restart(arg)
  elseif verb == "mode" then
    act.setMode(arg)
  elseif verb == "show" then
    act.showLook(r[arg])
  else
    error("no lifecycle step " .. step)
  end
  deliver()
end

--- @param c Case
local function runCase(c)
  T.section(c.label)
  fresh()
  local base = clock
  local r = rolesFor(c.trigger)
  setup(c, r)
  expectStep(base, "set up")
  trigger(c, r)
  expectStep(base, "after " .. AXES[2].words[c.trigger])
  for _, step in ipairs(c.lifecycle) do
    lifecycle(c, r, step)
    expectStep(base, "after " .. (LIFECYCLE_WORDS[step] or step))
  end
  if c.pressPartway then
    act.press()
    expectStep(base, "after a press partway")
  end
  for n = 1, 6 do
    if not model:armed() then
      break
    end
    clock = model.timer.due
    ShimFireTimers()
    model:fire()
    deliver()
    expectStep(base, string.format("time up (%d)", n))
  end
  for _, step in ipairs(c.lifecycle) do
    if step == "license" then
      DC_X = nil
      gate:_set(true)
      model:relicense()
      deliver()
      expectStep(base, "after a license back")
    end
  end
  clock = clock + 100000
  ShimFireTimers()
  deliver()
  expectStep(base, "much later")
  act.press()
  expectStep(base, "after a last press")
  H.tab("_GET_STATE")
  local state = H.state()
  local names, lines = {}, {}
  for _, look in ipairs(state.looks) do
    names[look.id] = look.name
    local line = look.name
    if state.lookControl == "By Link" then
      line = line
        .. " · "
        .. (not look.linkBound and "not bound" or look.linkState == nil and "no state" or look.linkState)
      if look.linkColors then
        line = line .. " · " .. tostring(look.linkColors.on) .. "/" .. tostring(look.linkColors.off)
      end
    end
    table.insert(lines, line)
  end
  T.eq("the Button tab: the shown look, Look Control, the look called for, and each look's link under By Link", {
    shown = names[state.shown] or "",
    lookControl = state.lookControl,
    matched = names[state.matched] or "",
    looks = lines,
  }, model:tab())
  clock = clock + 1000
end

--------------------------------------------------------------------------------
-- The cases
--------------------------------------------------------------------------------

--- Every pair of values of any two axes, in one case or another: a seed pair not yet covered, then each other axis
--- the value that covers the most pairs not yet covered, the first on a tie. No randomness: the same table gives the
--- same cases.
--- @param axes table
--- @return integer[][] picks Each case's value index per axis.
--- @return fun(picks: integer[][]): integer uncovered How many pairs a set leaves uncovered.
local function pairwise(axes)
  local function pairKey(i, a, j, b)
    return i .. ":" .. a .. "|" .. j .. ":" .. b
  end
  local function eachPair(fn)
    for i = 1, #axes do
      for j = i + 1, #axes do
        for a = 1, #axes[i].values do
          for b = 1, #axes[j].values do
            fn(i, a, j, b)
          end
        end
      end
    end
  end
  local uncovered, left = {}, 0
  eachPair(function(i, a, j, b)
    uncovered[pairKey(i, a, j, b)] = true
    left = left + 1
  end)
  local picks = {}
  while left > 0 do
    local pick = {}
    eachPair(function(i, a, j, b)
      if not pick[i] and uncovered[pairKey(i, a, j, b)] then
        pick[i], pick[j] = a, b
      end
    end)
    for k = 1, #axes do
      if not pick[k] then
        local best, bestGain = 1, -1
        for v = 1, #axes[k].values do
          local gain = 0
          for m = 1, #axes do
            if pick[m] and m ~= k then
              local key = m < k and pairKey(m, pick[m], k, v) or pairKey(k, v, m, pick[m])
              if uncovered[key] then
                gain = gain + 1
              end
            end
          end
          if gain > bestGain then
            best, bestGain = v, gain
          end
        end
        pick[k] = best
      end
    end
    for i = 1, #axes do
      for j = i + 1, #axes do
        local key = pairKey(i, pick[i], j, pick[j])
        if uncovered[key] then
          uncovered[key] = nil
          left = left - 1
        end
      end
    end
    table.insert(picks, pick)
  end
  local function missing(set)
    local covered, count = {}, 0
    for _, p in ipairs(set) do
      for i = 1, #axes do
        for j = i + 1, #axes do
          covered[pairKey(i, p[i], j, p[j])] = true
        end
      end
    end
    eachPair(function(i, a, j, b)
      if not covered[pairKey(i, a, j, b)] then
        count = count + 1
      end
    end)
    return count
  end
  return picks, missing
end

local cases = {}
local picks, missing = pairwise(AXES)
for _, pick in ipairs(picks) do
  table.insert(cases, {
    mode = AXES[1].values[pick[1]],
    trigger = AXES[2].values[pick[2]],
    timer = AXES[3].values[pick[3]],
    links = AXES[4].values[pick[4]],
    lifecycle = { AXES[5].values[pick[5]] },
  })
end
local pairwiseCount = #cases

-- The hand-picked triples.
for _, timer in ipairs({ "before", "chosen", "chain", "cycle" }) do
  -- By Link × a timer × a press: the press the links answer, and a press partway through a timed look's time.
  table.insert(cases, { mode = "By Link", trigger = "press", timer = timer, links = "toggle", lifecycle = { "none" } })
  table.insert(cases, {
    mode = "By Link",
    trigger = "showLook",
    timer = timer,
    links = "toggle",
    lifecycle = { "none" },
    pressPartway = true,
  })
  -- By Value × a timer × a hold from programming.
  table.insert(
    cases,
    { mode = "By Value", trigger = "showLook", timer = timer, links = "unbound", lifecycle = { "none" } }
  )
  -- Manual × a press tapping the link × a timer.
  table.insert(cases, {
    mode = "Manual",
    trigger = "showLook",
    timer = timer,
    links = "toggle",
    lifecycle = { "none" },
    pressPartway = true,
  })
end
-- On Select × a timer chain × a press.
for _, links in ipairs({ "toggle", "unbound", "separate" }) do
  table.insert(cases, { mode = "On Select", trigger = "press", timer = "chain", links = links, lifecycle = { "none" } })
end
table.insert(
  cases,
  { mode = "On Select", trigger = "press", timer = "cycle", links = "toggle", lifecycle = { "none" } }
)
-- By Link × a rename × a restart.
table.insert(
  cases,
  { mode = "By Link", trigger = "links", timer = "before", links = "toggle", lifecycle = { "rename", "restart" } }
)
table.insert(
  cases,
  { mode = "By Link", trigger = "showLook", timer = "chain", links = "answers", lifecycle = { "rename", "restart" } }
)
-- Every mode × Reset Driver.
for _, mode in ipairs(AXES[1].values) do
  table.insert(
    cases,
    { mode = mode, trigger = "showLook", timer = "chosen", links = "toggle", lifecycle = { "reset" } }
  )
end
-- By Value and By Link coming back after Look Control changed while the driver was stopped: at the next start, and
-- from the Properties tab.
for _, mode in ipairs({ "By Value", "By Link" }) do
  local how = mode == "By Value" and "values" or "links"
  table.insert(cases, {
    mode = mode,
    trigger = how,
    timer = "none",
    links = "toggle",
    lifecycle = { "stopped:Manual", "show:S", "stopped:" .. mode },
  })
  table.insert(cases, {
    mode = mode,
    trigger = how,
    timer = "none",
    links = "toggle",
    lifecycle = { "stopped:Manual", "show:S", "mode:" .. mode },
  })
end

for n, c in ipairs(cases) do
  local steps = {}
  for _, step in ipairs(c.lifecycle) do
    table.insert(steps, LIFECYCLE_WORDS[step] or step)
  end
  c.label = string.format(
    "#%d %s · %s · %s · %s · %s%s",
    n,
    c.mode,
    AXES[2].words[c.trigger],
    AXES[3].words[c.timer],
    AXES[4].words[c.links],
    table.concat(steps, ", then "),
    c.pressPartway and " · a press partway" or ""
  )
end

T.section("The cases")
local docsFile = assert(io.open(H.DRIVER:gsub("driver%.lua$", "www/documentation/index.md"), "r"))
local docs = docsFile:read("*a"):gsub("%s+", " ")
docsFile:close()
T.truthy(
  "the docs say deleting the shown look under By Value or By Link shows the look they call for",
  docs:find("Under `By Value` or `By Link`, the look the values or the links call for shows instead.", 1, true)
)
T.truthy(
  "and that events fire as the driver starts only when the look changes then",
  docs:find("no event fires when the driver starts, unless the look changes then", 1, true)
)
local samples = { "", "a", "ab", "abc", "\0\255\128", H.png("Alpha"), JSON:encode(H.lookFields("Bravo")) }
local same = true
for _, sample in ipairs(samples) do
  same = same and C4:Base64Encode(sample) == shimBase64Encode(C4, sample)
end
T.truthy("the test's Base64 encoder gives the shim's text", same)
local pairCount = 0
for i = 1, #AXES do
  for j = i + 1, #AXES do
    pairCount = pairCount + #AXES[i].values * #AXES[j].values
  end
end
T.eq(
  string.format("%d pairwise cases cover all %d pairs of the axes' values", pairwiseCount, pairCount),
  missing(picks),
  0
)
local again = pairwise(AXES)
T.eq("and the same table gives the same cases", again, picks)
T.truthy(string.format("%d cases in all, with the hand-picked triples", #cases), #cases > pairwiseCount)

local from, to = (os.getenv("COMBO_CASE") or ""):match("^(%d+)%-?(%d*)$")
from, to = tonumber(from), tonumber(to) or tonumber(from)
for n, c in ipairs(cases) do
  if not from or (n >= from and n <= to) then
    runCase(c)
  end
end

T.finish()
