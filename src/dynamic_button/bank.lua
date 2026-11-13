-- The picture bank: the proxy's display_icons states p1 to pSIZE, each a picture the buttons write
-- while they run. Navigators draw a state again with no gap, where an address leaves the tile empty
-- for a moment, and remotes draw states only. So a look whose picture doesn't change shows through a
-- slot of the bank.
--
-- Every Dynamic Button in a project shares the bank, as they share the driver's folder. A button
-- claims a slot with a file in the folder that names it, and keeps its slots in its own store too,
-- since an update replaces the folder. Navigators and remotes keep a state's first picture until
-- Navigators refresh, so a slot a button lets go waits for a refresh before any button takes it.

local log = require("lib.logging")
local Images = require("dynamic_button.images")

--- @class BankSlot
--- @field slot integer The slot's number: its state is p<slot>.
--- @field version integer The look's picture version the slot holds.

--- @class BankWaiting
--- @field slot integer
--- @field at integer When the button let it go, in ms since the epoch.

--- @alias BankSlots table<string, BankSlot> Each look's slot, by look id.

--- @class Bank
--- @field deviceId integer The button's device id, which its claims hold.
--- @field store table A persist-like store with get(key, default) and set(key, value).
--- @field enabled boolean False when the driver's folder isn't the one driver.xml's states name.
--- @field _size integer
--- @field _now fun(): integer The clock, in ms since the epoch.
--- @field _fullSince integer|nil The refresh time of the last search that found no slot free.
local Bank = {}
Bank.__index = Bank

--- The states driver.xml declares (tools/gen_bank.py SIZE).
Bank.SIZE = 1024

--- The driver folder the states' pictures are in.
Bank.DRIVER = "dynamic_button"

--- The state that shows the driver's own icon.
Bank.OWN_STATE = "own"

--- What slotFor answers when no slot is free.
Bank.FULL = "full"

--- The claims' folder: one file per claimed slot, holding the button's device id, or "freed <ms>"
--- for a slot let go then.
local CLAIMS_DIR = "bank"
--- The pictures' folder, which the states' addresses name.
local PICTURES_DIR = "www/bank"
--- The shared file holding when Navigators were last refreshed, in ms.
local REFRESHED_FILE = "refreshed"

local SLOTS_KEY = "BankSlots"
local WAITING_KEY = "BankWaiting"
local REFRESHED_KEY = "BankRefreshed"

--- Creates a new instance of the Bank class.
--- @param opts { store: table, deviceId: integer, enabled: boolean, size?: integer, now?: fun(): integer }
--- @return Bank bank
function Bank:new(opts)
  local instance = setmetatable({}, self)
  instance.store = opts.store
  instance.deviceId = opts.deviceId
  instance.enabled = opts.enabled
  instance._size = opts.size or Bank.SIZE
  instance._now = opts.now or function()
    return C4:GetTime()
  end
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

--- @private
--- @param slot integer
--- @return integer|nil owner The device id holding it.
--- @return integer|nil freedAt When it was let go, for a slot waiting for a refresh.
function Bank:_claim(slot)
  local text = Images.readFile("C4Z", CLAIMS_DIR, tostring(slot))
  if not text or text == "" then
    return nil, nil
  end
  local at = text:match("^freed (%d+)$")
  if at then
    return nil, tonumber(at)
  end
  return tonumber(text), nil
end

--- @private
--- @param slot integer
--- @param text string
--- @return boolean ok
function Bank:_writeClaim(slot, text)
  C4:FileCreateDir("C4Z", CLAIMS_DIR)
  return Images.writeFile("C4Z", CLAIMS_DIR, tostring(slot), text)
end

--- @private
--- @return BankSlots slots
function Bank:_slots()
  return self.store:get(SLOTS_KEY, {})
end

--- @private
--- @param slots BankSlots
function Bank:_setSlots(slots)
  self.store:set(SLOTS_KEY, next(slots) and slots or nil)
end

--- @private
--- @return BankWaiting[] waiting
function Bank:_waiting()
  return self.store:get(WAITING_KEY, {})
end

--- @private
--- @param waiting BankWaiting[]
function Bank:_setWaiting(waiting)
  self.store:set(WAITING_KEY, #waiting > 0 and waiting or nil)
end

--- When Navigators were last refreshed, as the folder or this button's store knows it.
--- @return integer at In ms since the epoch; 0 for never.
function Bank:refreshedAt()
  local shared = tonumber(Images.readFile("C4Z", CLAIMS_DIR, REFRESHED_FILE)) or 0
  local own = tonumber(self.store:get(REFRESHED_KEY)) or 0
  return math.max(shared, own)
end

--- Whether a slot can be taken: no claim, or let go no later than the last refresh, which the
--- Navigators carry out after it's asked for.
--- @private
--- @param slot integer
--- @param refreshedAt integer
--- @return boolean
function Bank:_free(slot, refreshedAt)
  local owner, freedAt = self:_claim(slot)
  if owner then
    return false
  end
  return freedAt == nil or freedAt <= refreshedAt
end

--- At every start: claim this button's slots again, since an update replaces the folder. A slot
--- another button holds now is dropped, and its look takes a new one when it next shows.
function Bank:start()
  if not self.enabled then
    return
  end
  local slots = self:_slots()
  for lookId, held in pairs(slots) do
    local owner = self:_claim(held.slot)
    if owner and owner ~= self.deviceId then
      log:warn("Picture bank slot %d is another button's now: look %s takes a new one", held.slot, lookId)
      slots[lookId] = nil
    elseif owner == nil then
      self:_writeClaim(held.slot, tostring(self.deviceId))
    end
  end
  self:_setSlots(slots)
  local refreshedAt = self:refreshedAt()
  local waiting = {}
  for _, entry in ipairs(self:_waiting()) do
    local owner, freedAt = self:_claim(entry.slot)
    if entry.at > refreshedAt and owner == nil then
      if freedAt == nil then
        self:_writeClaim(entry.slot, string.format("freed %d", entry.at))
      end
      table.insert(waiting, entry)
    end
  end
  self:_setWaiting(waiting)
end

--- Let a slot go: it waits for a Navigator refresh before any button takes it.
--- @private
--- @param slot integer
function Bank:_retire(slot)
  local at = self._now()
  self:_writeClaim(slot, string.format("freed %d", at))
  local waiting = self:_waiting()
  table.insert(waiting, { slot = slot, at = at })
  self:_setWaiting(waiting)
end

--- Claim a free slot, searching from a place set by the device id so buttons rarely meet.
--- @private
--- @return integer|nil slot
function Bank:_take()
  local refreshedAt = self:refreshedAt()
  -- Only a refresh frees slots, so a full bank stays full until one.
  if self._fullSince == refreshedAt then
    return nil
  end
  local start = (self.deviceId * 37) % self._size
  local mine = tostring(self.deviceId)
  for i = 0, self._size - 1 do
    local slot = (start + i) % self._size + 1
    if self:_free(slot, refreshedAt) then
      -- Read back: of two buttons writing at once, the later one holds it.
      if self:_writeClaim(slot, mine) and self:_claim(slot) == self.deviceId then
        local waiting = {}
        for _, entry in ipairs(self:_waiting()) do
          if entry.slot ~= slot then
            table.insert(waiting, entry)
          end
        end
        self:_setWaiting(waiting)
        return slot
      end
    end
  end
  self._fullSince = refreshedAt
  return nil
end

--- The state that shows a look's picture, taking a slot for it when it has none for this version.
--- @param lookId integer
--- @param version integer The picture's version: a new one takes a new slot.
--- @param picture fun(): string|nil Reads the picture, when its file has to be written.
--- @return string|nil state Nil when the bank is off, full, or the picture couldn't be written.
--- @return string|nil err Bank.FULL when no slot is free.
function Bank:slotFor(lookId, version, picture)
  if not self.enabled then
    return nil
  end
  local key = tostring(lookId)
  local slots = self:_slots()
  local held = slots[key]
  if held and held.version == version and self:_claim(held.slot) == self.deviceId then
    C4:FileSetDir("C4Z", PICTURES_DIR)
    if C4:FileExists(pictureName(held.slot)) then
      return Bank.state(held.slot)
    end
    local png = picture()
    if png and self:_writePicture(held.slot, png) then
      return Bank.state(held.slot)
    end
    return nil
  end
  if held then
    slots[key] = nil
    self:_setSlots(slots)
    if self:_claim(held.slot) == self.deviceId then
      self:_retire(held.slot)
    end
  end
  local png = picture()
  if not png then
    return nil
  end
  local slot = self:_take()
  if not slot then
    return nil, Bank.FULL
  end
  if not self:_writePicture(slot, png) then
    -- Never shown, so no Navigator holds it: it's free at once.
    Images.deleteFile("C4Z", CLAIMS_DIR, tostring(slot))
    return nil
  end
  slots[key] = { slot = slot, version = version }
  self:_setSlots(slots)
  return Bank.state(slot)
end

--- @private
--- @param slot integer
--- @param png string
--- @return boolean ok
function Bank:_writePicture(slot, png)
  C4:FileCreateDir("C4Z", PICTURES_DIR)
  return Images.writeFile("C4Z", PICTURES_DIR, pictureName(slot), png)
end

--- Let a look's slot go, when the look is deleted or its picture changes.
--- @param lookId integer
function Bank:release(lookId)
  if not self.enabled then
    return
  end
  local key = tostring(lookId)
  local slots = self:_slots()
  local held = slots[key]
  if not held then
    return
  end
  slots[key] = nil
  self:_setSlots(slots)
  if self:_claim(held.slot) == self.deviceId then
    self:_retire(held.slot)
  end
end

--- The button left the project or was reset: let every slot go.
function Bank:removed()
  if not self.enabled then
    return
  end
  for lookId in pairs(self:_slots()) do
    self:release(tonumber(lookId))
  end
end

--- Navigators were just asked to refresh: every slot let go until now is free to take again.
--- @param at? integer When, in ms since the epoch (optional). Defaults to now.
function Bank:refreshed(at)
  if not self.enabled then
    return
  end
  at = at or self._now()
  C4:FileCreateDir("C4Z", CLAIMS_DIR)
  Images.writeFile("C4Z", CLAIMS_DIR, REFRESHED_FILE, tostring(at))
  self.store:set(REFRESHED_KEY, at)
  local waiting = {}
  for _, entry in ipairs(self:_waiting()) do
    if entry.at > at then
      table.insert(waiting, entry)
    end
  end
  self:_setWaiting(waiting)
end

return Bank
