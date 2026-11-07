-- A badge whose text holds a variable: the controller draws it on the shown look's picture, and
-- draws it again when the text changes, at most as often as the look asks.

local log = require("lib.logging")
local Expressions = require("lib.expressions")
local BadgeArt = require("dynamic_button.badge_art")
local BadgeFont = require("dynamic_button.badge_font")
local Looks = require("dynamic_button.looks")
local Png = require("dynamic_button.png")

--- @class LiveBadges
--- @field _looks Looks
--- @field _images Images
--- @field _engine Expressions
--- @field _redraw fun() Draws the shown look's badge again and serves it.
--- @field _changed fun() Tells the Button tab what changed.
--- @field _allowed fun(): boolean False while nothing may change the picture.
--- @field _now fun(): number The clock, in seconds.
--- @field _watched integer|nil The look being watched, the shown one when it has a live badge.
--- @field _booting boolean A variable another driver hasn't added yet may still come.
--- @field _drawnText string|nil|false What the served picture's badge says: nil for no badge, false when unknown.
--- @field _drawnAt number|nil When it was drawn.
--- @field _noted string|nil The last problem logged, so it logs once.
local LiveBadges = {}
LiveBadges.__index = LiveBadges

--- The one expression this watches, in the engine it shares.
LiveBadges.EXPRESSION = "badge"

local DRAW_TIMER = "LiveBadgeDraw"
local BOOT_TIMER = "LiveBadgeBootWait"

--- The longest a change waits while the project starts, in seconds: a variable's first value may
--- be its driver's default, with the real one moments later.
local BOOT_EVERY_SECONDS = 30

--- @param text string
--- @param count integer
--- @return string text Its first `count` characters.
local function firstCharacters(text, count)
  local out, used = {}, 0
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if used == count then
      break
    end
    used = used + 1
    out[used] = char
  end
  return table.concat(out)
end

--- A badge's text as it will draw: only the characters the face has, cut to what fits. A number
--- gives up decimals first, then the end goes.
--- @param text string
--- @return string text
function LiveBadges.fit(text)
  local _, kept = BadgeFont.characters(text)
  text = kept:match("^%s*(.-)%s*$")
  if Looks.characters(text) <= Looks.MAX_BADGE then
    return text
  end
  local before, number, after = text:match("^(.-)(%-?%d+%.%d+)(.*)$")
  if number then
    for places = #number:match("%.(%d+)$") - 1, 0, -1 do
      local shorter = before .. string.format("%." .. places .. "f", tonumber(number)) .. after
      if Looks.characters(shorter) <= Looks.MAX_BADGE then
        return shorter
      end
      text = shorter
    end
  end
  return firstCharacters(text, Looks.MAX_BADGE)
end

--- What a live badge says now.
--- @param template string The badge's text, with its variables.
--- @return string|nil text Nil when a variable is missing.
--- @return string|nil err Which one.
function LiveBadges.read(template)
  local evaluation = Expressions.evaluate("string", template)
  if evaluation.error then
    return nil, evaluation.error
  end
  return LiveBadges.fit(tostring(evaluation.result)), nil
end

--- @param text string|nil
--- @return string key Names the picture for this text in its address.
local function addressKey(text)
  return string.format("%08x", Png.crc32(text or ""))
end

--- Creates a new instance of the LiveBadges class.
--- @param opts { looks: Looks, images: Images, engine: Expressions, redraw: fun(), changed: fun(), allowed: fun(): boolean, now?: fun(): number }
--- @return LiveBadges badges
function LiveBadges:new(opts)
  local instance = setmetatable({}, self)
  instance._looks = opts.looks
  instance._images = opts.images
  instance._engine = opts.engine
  instance._redraw = opts.redraw
  instance._changed = opts.changed
  instance._allowed = opts.allowed
  instance._now = opts.now or os.time
  instance._booting = false
  return instance
end

--- The shown look's live badge text, for the expressions engine to watch.
--- @return table<string, table> expressions What to watch, as the engine reads them.
function LiveBadges:expressions()
  local look = self._watched and self._looks:get(self._watched)
  local badge = look and Looks.liveBadge(look)
  if not badge then
    return {}
  end
  return { [LiveBadges.EXPRESSION] = { template = badge.text, mode = "string", auto = true } }
end

--- Start as a load does, with the wait for other drivers' variables that `Follow:start` has.
function LiveBadges:boot()
  self._booting = true
  SetTimer(BOOT_TIMER, Expressions.RETRY_MS * Expressions.RETRY_ATTEMPTS, function()
    self._booting = false
    self:check()
  end)
end

--- Whether a look's badge is waiting for a variable that may still come, so the picture from
--- before the restart stays until then.
--- @param look Look
--- @return boolean holding
function LiveBadges:holding(look)
  local badge = Looks.liveBadge(look)
  if not (self._booting and badge) then
    return false
  end
  local _, err = LiveBadges.read(badge.text)
  if err then
    self._drawnText = false
  end
  return err ~= nil
end

--- The shown look changed, or its fields did.
--- @param look Look|nil
function LiveBadges:watch(look)
  local watched = look and Looks.liveBadge(look) and look.id or nil
  if watched ~= self._watched then
    self._noted = nil
  end
  self._watched = watched
  CancelTimer(DRAW_TIMER)
  if watched then
    self._engine:refreshExpression(LiveBadges.EXPRESSION)
  else
    self._engine:unsubscribeExpression(LiveBadges.EXPRESSION)
    self._drawnText, self._drawnAt = nil, nil
  end
end

--- Log a problem once, until it changes.
--- @private
--- @param look Look
--- @param problem string|nil
function LiveBadges:_note(look, problem)
  if problem and problem ~= self._noted then
    log:warn("Look %s: Badge: %s", look.name, problem)
  end
  self._noted = problem
end

--- @private
--- @param look Look
--- @param badge LookBadge
--- @param png string The look's stored picture.
--- @param text string
--- @return string|nil drawn
--- @return string|nil err
function LiveBadges:_draw(look, badge, png, text)
  local canvas = Png.size(png)
  if not canvas then
    return nil, "the picture isn't a PNG"
  end
  local y0, y1 = BadgeArt.rows(badge, canvas)
  local stored = self._images:loadCache(look.id)
  local cache = stored and Png.unpack(stored)
  if not (cache and cache.y0 == y0 and cache.y1 == y1 and cache.width == canvas) then
    local err
    cache, err = Png.setup(png, y0, y1)
    if not cache then
      return nil, err
    end
    self._images:saveCache(look.id, Png.pack(cache))
  end
  local rows = Png.rows(cache)
  BadgeArt.draw(rows, y0, canvas, badge, text)
  return Png.splice(cache, rows)
end

--- The picture to serve for a look: with its live badge as it reads now, or as stored.
--- @param look Look
--- @param png string The look's stored picture.
--- @return string picture
--- @return string|nil key Names this text in the picture's address, for a look with a live badge.
function LiveBadges:picture(look, png)
  local badge = Looks.liveBadge(look)
  if not badge then
    return png, nil
  end
  local text, err = LiveBadges.read(badge.text)
  local drawn
  if text and text ~= "" then
    drawn, err = self:_draw(look, badge, png, text)
  end
  self:_note(look, err)
  -- Only a badge starts the wait, so one that comes back shows at once.
  self._drawnText, self._drawnAt = text, drawn and self._now() or nil
  return drawn or png, addressKey(drawn and text or nil)
end

--- A watched variable changed: draw the badge again if its text did and its time has come. The
--- value read when the time comes is the one drawn, so a burst of changes costs one picture.
function LiveBadges:check()
  CancelTimer(DRAW_TIMER)
  local look = self._watched and self._looks:get(self._watched)
  local badge = look and Looks.liveBadge(look)
  if not badge or not self._allowed() then
    return
  end
  local text, err = LiveBadges.read(badge.text)
  if err and self._booting then
    return
  end
  self:_note(look, err)
  if text == self._drawnText then
    return
  end
  local now, every = self._now(), Looks.badgeEvery(badge)
  if self._booting then
    every = math.min(every, BOOT_EVERY_SECONDS)
  end
  -- A clock set back would otherwise stretch the wait by as much.
  if self._drawnAt and now < self._drawnAt then
    self._drawnAt = now
  end
  local wait = self._drawnAt and every - (now - self._drawnAt) or 0
  if wait > 0 then
    SetTimer(DRAW_TIMER, wait * ONE_SECOND, function()
      self:check()
    end)
    return
  end
  self._redraw()
  self._changed()
end

return LiveBadges
