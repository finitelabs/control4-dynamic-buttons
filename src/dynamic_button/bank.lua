-- The picture bank: the proxy's display_icons states p1 to pSIZE, each a picture the buttons write
-- while they run. Navigators draw a state again with no gap, where an address leaves the tile empty
-- for a moment, and remotes draw states only.
--
-- Every Dynamic Button in a project shares the bank, as they share the driver's folder. A picture's
-- hash picks its slot, so the same picture shows through the same state whichever look or button
-- shows it. Once they've drawn a state, remotes keep its picture until the controller restarts and
-- apps keep it until the Navigators refresh, so the first button to start after a restart refreshes
-- them, and only a slot not sent since both can take a new picture.

local log = require("lib.logging")
local Images = require("dynamic_button.images")

--- @class BankShown
--- @field hash string The picture's SHA-256, in hex.
--- @field at integer When a button last sent the slot's state, in ms since the epoch.

--- @alias BankShownSlots table<string, BankShown> The slots this button sent, by slot number.

--- @class BankLive
--- @field since integer The controller start the counts are for, in ms since the epoch.
--- @field counts table<string, integer> New slots each live look took since then, by look id.

--- @class Bank
--- @field store table A persist-like store with get(key, default) and set(key, value).
--- @field enabled boolean False when the driver's folder isn't the one driver.xml's states name.
--- @field _size integer
--- @field _liveCap integer
--- @field _now fun(): integer The clock, in ms since the epoch.
--- @field _uptime fun(): number Seconds since the controller started.
--- @field _refresh fun() Refreshes the Navigators.
--- @field _found table<string, integer> Slots found this run, by picture hash.
local Bank = {}
Bank.__index = Bank

--- The states driver.xml declares (tools/gen_bank.py SIZE).
Bank.SIZE = 256

--- New slots a live look can take between controller restarts.
Bank.LIVE_CAP = 32

--- The driver folder the states' pictures are in.
Bank.DRIVER = "dynamic_button"

--- The state that shows the driver's own icon.
Bank.OWN_STATE = "own"

--- What slotFor answers when no slot can take a new picture.
Bank.FULL = "full"

--- What slotFor answers when a live look took its share of new slots since the controller started.
Bank.CAPPED = "capped"

--- The slots' records: one file per slot, "<hash> <ms>", the picture's hash and when a button last
--- sent the state.
local RECORDS_DIR = "bank"
--- The file, among the records, that holds when a button last refreshed the Navigators, in ms.
local REFRESHED_NAME = "refreshed"
--- The pictures' folder, which the states' addresses name.
local PICTURES_DIR = "www/bank"

local SHOWN_KEY = "BankShown"
local LIVE_KEY = "BankLive"
--- Each button keeps the refresh time too, to write it again after an update replaces the folder.
local REFRESHED_KEY = "BankRefreshed"

--- Slack in the controller's start time, as the two clocks are read a moment apart. A slot sent
--- just before a restart only keeps its picture a little longer.
local START_SLACK_MS = 60000

--- Creates a new instance of the Bank class.
--- @param opts { store: table, enabled: boolean, refresh: fun(), size?: integer, liveCap?: integer, now?: fun(): integer, uptime?: fun(): number }
--- @return Bank bank
function Bank:new(opts)
  local instance = setmetatable({}, self)
  instance.store = opts.store
  instance.enabled = opts.enabled
  instance._size = opts.size or Bank.SIZE
  instance._liveCap = opts.liveCap or Bank.LIVE_CAP
  instance._now = opts.now or function()
    return C4:GetTime()
  end
  instance._uptime = opts.uptime or function()
    return C4:GetUptime()
  end
  instance._refresh = opts.refresh
  instance._found = {}
  return instance
end

--- @param slot integer
--- @return string state The slot's display_icons state id.
function Bank.state(slot)
  return "p" .. slot
end

--- @param slot integer
--- @return string name The slot's picture file.
local function pictureName(slot)
  return string.format("%d.png", slot)
end

--- When the controller last started, which cleared the remotes' copies of the states' pictures.
--- @return integer at In ms since the epoch, less a minute's slack.
function Bank:startedAt()
  return self._now() - math.floor(self._uptime() * 1000) - START_SLACK_MS
end

--- @private
--- @return integer at When a button last refreshed the Navigators, which cleared the apps' copies; 0 for never.
function Bank:_refreshedAt()
  local text = Images.readFile("C4Z", RECORDS_DIR, REFRESHED_NAME)
  return tonumber((text or ""):match("^(%d+)$")) or 0
end

--- When apps and remotes last both dropped their copies: a slot sent before then can take a new picture.
--- @return integer at In ms since the epoch.
function Bank:clearedAt()
  return math.min(self:startedAt(), self:_refreshedAt())
end

--- @private
--- @param slot integer
--- @return string|nil hash The picture the slot holds.
--- @return integer at When its state was last sent; 0 for never.
function Bank:_record(slot)
  local text = Images.readFile("C4Z", RECORDS_DIR, tostring(slot))
  local hash, at = (text or ""):match("^(%x+) (%d+)$")
  return hash, tonumber(at) or 0
end

--- @private
--- @param slot integer
--- @param hash string
--- @param at integer
--- @return boolean ok
function Bank:_writeRecord(slot, hash, at)
  C4:FileCreateDir("C4Z", RECORDS_DIR)
  return Images.writeFile("C4Z", RECORDS_DIR, tostring(slot), string.format("%s %.0f", hash, at))
end

--- @private
--- @return BankShownSlots shown
function Bank:_shown()
  return self.store:get(SHOWN_KEY, {})
end

--- Keep a slot this button sent with its others, dropping those sent before apps and remotes last
--- dropped their copies.
--- @private
--- @param slot integer
--- @param hash string
--- @param at integer
function Bank:_remember(slot, hash, at)
  local clearedAt = self:clearedAt()
  local shown = {}
  for key, entry in pairs(self:_shown()) do
    if entry.at >= clearedAt then
      shown[key] = entry
    end
  end
  shown[tostring(slot)] = { hash = hash, at = at }
  self.store:set(SHOWN_KEY, shown)
end

--- At every start: the first button to start since the controller started refreshes the
--- Navigators, so apps drop their copies as remotes did. Then each writes again the refresh time and
--- the records of the slots it sent since, since an update replaces the folder.
function Bank:start()
  if not self.enabled then
    return
  end
  local onFile = self:_refreshedAt()
  local refreshed = math.max(onFile, self.store:get(REFRESHED_KEY, 0))
  if refreshed == 0 then
    -- A new bank, which no app has drawn. A refresh now could also land while Director is still
    -- updating the drivers, and the apps would show the buttons empty until the next one.
    refreshed = self._now()
  elseif refreshed < self:startedAt() then
    log:info("Refreshing Navigators, once since the controller started, so picture bank slots can take new pictures")
    refreshed = self._now()
    self._refresh()
  end
  if refreshed ~= onFile then
    C4:FileCreateDir("C4Z", RECORDS_DIR)
    Images.writeFile("C4Z", RECORDS_DIR, REFRESHED_NAME, string.format("%.0f", refreshed))
  end
  self.store:set(REFRESHED_KEY, refreshed)
  local clearedAt = self:clearedAt()
  local shown = {}
  for key, entry in pairs(self:_shown()) do
    local slot = tonumber(key)
    if slot and slot <= self._size and entry.at >= clearedAt then
      local held = self:_record(slot)
      if held == nil then
        self:_writeRecord(slot, entry.hash, entry.at)
        shown[key] = entry
      elseif held == entry.hash then
        shown[key] = entry
      else
        log:warn("Picture bank slot %d holds another button's picture now", slot)
      end
    end
  end
  self.store:set(SHOWN_KEY, next(shown) and shown or nil)
end

--- The slot's state is about to be sent: from then on it keeps its picture until the controller
--- restarts and a button refreshes the Navigators.
--- @private
--- @param slot integer
--- @param hash string
--- @param at integer When its state was last sent before now.
function Bank:_sending(slot, hash, at)
  if at >= self:startedAt() then
    return
  end
  local now = self._now()
  if self:_writeRecord(slot, hash, now) then
    self:_remember(slot, hash, now)
  end
end

--- A slot that holds the picture: write its file if an update took it, and note it's sent.
--- @private
--- @param slot integer
--- @param hash string
--- @param at integer When its state was last sent.
--- @param png string
--- @return string|nil state
function Bank:_use(slot, hash, at, png)
  C4:FileSetDir("C4Z", PICTURES_DIR)
  if not C4:FileExists(pictureName(slot)) then
    C4:FileCreateDir("C4Z", PICTURES_DIR)
    if not Images.writeFile("C4Z", PICTURES_DIR, pictureName(slot), png) then
      return nil
    end
  end
  self._found[hash] = slot
  self:_sending(slot, hash, at)
  return Bank.state(slot)
end

--- A slot this button knows holds the picture: one found this run, or one it sent.
--- @private
--- @param hash string
--- @return integer|nil slot
--- @return integer at When its state was last sent.
function Bank:_known(hash)
  local found = self._found[hash]
  if found then
    local held, at = self:_record(found)
    if held == hash then
      return found, at
    end
    self._found[hash] = nil
  end
  for key, entry in pairs(self:_shown()) do
    local slot = tonumber(key)
    if slot and entry.hash == hash then
      local held, at = self:_record(slot)
      if held == hash then
        return slot, at
      end
    end
  end
  return nil, 0
end

--- Give a slot no one sent since apps and remotes last dropped their copies a new picture. Of two
--- buttons binding it at once, the later record holds it.
--- @private
--- @param slot integer
--- @param hash string
--- @param png string
--- @return boolean ok
function Bank:_bind(slot, hash, png)
  local now = self._now()
  if not self:_writeRecord(slot, hash, now) or self:_record(slot) ~= hash then
    return false
  end
  C4:FileCreateDir("C4Z", PICTURES_DIR)
  if not Images.writeFile("C4Z", PICTURES_DIR, pictureName(slot), png) then
    Images.deleteFile("C4Z", PICTURES_DIR, pictureName(slot))
    self:_writeRecord(slot, hash, 0)
    return false
  end
  self._found[hash] = slot
  self:_remember(slot, hash, now)
  return true
end

--- @private
--- @return BankLive live The live looks' counts since the controller started.
function Bank:_live()
  local startedAt = self:startedAt()
  local live = self.store:get(LIVE_KEY, {})
  if not live.since or math.abs(live.since - startedAt) > START_SLACK_MS then
    live = { since = startedAt, counts = {} }
  end
  return live
end

--- The state that shows a picture: the slot already holding it, or one that can take it.
--- @param png string The picture, as it is served.
--- @param liveLookId? integer The look, when its picture changes while it shows (optional).
--- @return string|nil state Nil when the bank is off, full, or the look took its share.
--- @return string|nil err Bank.FULL or Bank.CAPPED.
function Bank:slotFor(png, liveLookId)
  if not self.enabled or not png then
    return nil
  end
  local hash = C4:Hash("SHA256", png)
  if not hash or hash == "" then
    return nil
  end
  local slot, at = self:_known(hash)
  if slot then
    return self:_use(slot, hash, at, png)
  end
  local clearedAt = self:clearedAt()
  local first = tonumber(hash:sub(1, 8), 16) % self._size
  local open = {}
  for i = 0, self._size - 1 do
    slot = (first + i) % self._size + 1
    local held
    held, at = self:_record(slot)
    if held == hash then
      return self:_use(slot, hash, at, png)
    end
    if held == nil or at < clearedAt then
      table.insert(open, slot)
    end
    -- A picture takes the first open slot on its path, so it's never past an empty one.
    if held == nil then
      break
    end
  end
  local live = liveLookId and self:_live()
  local key = liveLookId and tostring(liveLookId)
  if live and (live.counts[key] or 0) >= self._liveCap then
    return nil, Bank.CAPPED
  end
  for _, candidate in ipairs(open) do
    if self:_bind(candidate, hash, png) then
      if live then
        live.counts[key] = (live.counts[key] or 0) + 1
        self.store:set(LIVE_KEY, live)
      end
      return Bank.state(candidate)
    end
  end
  return nil, Bank.FULL
end

--- The slots this button sent since apps and remotes last dropped their copies, for another button
--- to keep when this one leaves the project.
--- @return string slots "<slot>:<hash>:<ms>" entries joined by commas; empty when none.
function Bank:handOver()
  if not self.enabled then
    return ""
  end
  local clearedAt = self:clearedAt()
  local parts = {}
  for key, entry in pairs(self:_shown()) do
    if entry.at >= clearedAt then
      table.insert(parts, string.format("%s:%s:%.0f", key, entry.hash, entry.at))
    end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

--- Keep a leaving button's slots with this button's own, so their records survive an update.
--- @param slots string|nil What the leaving button's handOver returned.
function Bank:adopt(slots)
  if not self.enabled or not slots then
    return
  end
  local clearedAt = self:clearedAt()
  local shown = self:_shown()
  for slotText, hash, atText in slots:gmatch("(%d+):(%x+):(%d+)") do
    local slot, at = tonumber(slotText), tonumber(atText)
    local mine = shown[slotText]
    if slot >= 1 and slot <= self._size and at >= clearedAt and not (mine and mine.at >= at) then
      shown[slotText] = { hash = hash, at = at }
    end
  end
  self.store:set(SHOWN_KEY, next(shown) and shown or nil)
end

return Bank
