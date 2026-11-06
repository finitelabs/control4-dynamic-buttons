-- A button's looks: each one picture the Navigator button can show, with the icon it was drawn
-- from and how it was drawn. The list order is the order the Button tab shows them in, and the
-- order the button cycles through them.

local log = require("lib.logging")

--- @class LookIcon
--- @field id string The icon's Iconify name, `<pack>:<name>`.
--- @field body? string The icon's SVG markup, without the outer svg element; none when carried.
--- @field carried? boolean True for an icon the Button tab carries and draws from its id.
--- @field width number The icon's view box width.
--- @field height number The icon's view box height.
--- @field license string The icon pack's license title.
--- @field licenseUrl string Where the icon pack's license text is.

--- @class Look
--- @field id integer The look's id, unique for the life of the button.
--- @field name string The look's name, shown in programming and as the button's text line.
--- @field icon LookIcon The icon the look was drawn from.
--- @field iconColor string The icon's color, `#RRGGBB`.
--- @field tileShape string The shape behind the icon, one of `Looks.SHAPES`.
--- @field tileColor string The tile's color, `#RRGGBB`.
--- @field inCycle? boolean False for a look the cycle skips; a look without the field is in it.
--- @field glow? integer How much of the picture's own glow is drawn, 0 to 200; 100 without the field.
--- @field grayscale? boolean True for a look drawn in grays, which draws no glow; false without the field.
--- @field custom? LookCustom How the look changes its picture; the picture as it comes without the field.
--- @field showWhen? string When Look Control's By Value shows the look, an expression; never true without the field.
--- @field image? { bytes: integer, stale?: boolean } The drawn picture, once the Button tab has sent it;
--- stale while the look's fields have changed since it was drawn.

--- @class LookBadge
--- @field text string Up to `Looks.MAX_BADGE` characters.
--- @field place string One of `Looks.BADGE_PLACES`.
--- @field color string The text's color, `#RRGGBB`.
--- @field background string The badge's color, `#RRGGBB`, or `None`.
--- @field size? integer The badge's size, `Looks.MIN_BADGE_SIZE` to `Looks.MAX_BADGE_SIZE` percent.

--- @class LookCustom A missing field keeps the picture's own.
--- @field color? string The picture's color, `#RRGGBB`.
--- @field body? string The tint of a drawing's metal or plastic, `#RRGGBB`.
--- @field tile? string A Classic Tile's tile color, `#RRGGBB`.
--- @field symbol? string A Classic Tile's symbol color, `#RRGGBB`.
--- @field glowColor? string The glow's color, `#RRGGBB`.
--- @field size? integer The picture's size, `Looks.MIN_SIZE` to 100 percent.
--- @field x? integer How far right the picture moves, percent of the canvas, within `Looks.MAX_SHIFT`.
--- @field y? integer How far down the picture moves, percent of the canvas, within `Looks.MAX_SHIFT`.
--- @field badge? LookBadge Text drawn over the picture.

--- @class Looks
--- @field _store table The persist store the looks are kept in.
local Looks = {}
Looks.__index = Looks

--- The most looks one button keeps.
Looks.MAX = 8

--- The longest look name, in characters.
Looks.MAX_NAME = 40

--- The fields a look's picture is drawn from.
local DRAWN_FIELDS = { "iconColor", "tileShape", "tileColor" }

--- The glow a look draws when it does not say: the picture's own.
Looks.FULL_GLOW = 100

--- The strongest glow a look can ask for, twice the picture's own.
Looks.MAX_GLOW = 200

--- The shapes a look's tile can take.
Looks.SHAPES = { "None", "Circle", "Rounded Square", "Square" }

--- The smallest a customized picture can be, in percent.
Looks.MIN_SIZE = 50

--- The furthest a customized picture moves each way, in percent.
Looks.MAX_SHIFT = 10

--- The longest badge, in characters.
Looks.MAX_BADGE = 5

--- The smallest and largest badge, in percent.
Looks.MIN_BADGE_SIZE = 50
Looks.MAX_BADGE_SIZE = 150

--- Where a badge can sit.
Looks.BADGE_PLACES = { "Top Right", "Bottom Right", "Under" }

--- The colors a look's customization can set, in the order they are compared.
local CUSTOM_COLORS = { "color", "body", "tile", "symbol", "glowColor" }

--- The largest icon markup a look keeps, in bytes.
Looks.MAX_ICON_BODY = 16 * 1024

--- The longest Show when expression, in bytes.
Looks.MAX_SHOW_WHEN = 2000

local LOOKS_PERSIST_KEY = "Looks"

--- @param store table A persist-like store with get(key, default) and set(key, value).
--- @return Looks looks
function Looks:new(store)
  local instance = setmetatable({}, self)
  instance._store = store
  return instance
end

--- @private
--- @return { nextId: integer, list: Look[], defaultId?: integer } data
function Looks:_load()
  local data = self._store:get(LOOKS_PERSIST_KEY)
  if type(data) ~= "table" or type(data.list) ~= "table" then
    data = { nextId = 1, list = {} }
  end
  data.nextId = tonumber(data.nextId) or 1
  return data
end

--- @private
--- @param data { nextId: integer, list: Look[], defaultId?: integer }
function Looks:_save(data)
  self._store:set(LOOKS_PERSIST_KEY, data)
end

--- The looks in order.
--- @return Look[] list
function Looks:list()
  return self:_load().list
end

--- @param id integer|string|nil
--- @return Look|nil look
function Looks:get(id)
  id = tonumber(id)
  for _, look in ipairs(self:list()) do
    if look.id == id then
      return look
    end
  end
  return nil
end

--- How programming lists a look: its name and id, so a choice keeps working after a rename.
--- @param look Look
--- @return string label
function Looks.label(look)
  return string.format("%s (%d)", look.name, look.id)
end

--- The look a programming choice names: by the id in its label, else by its name.
--- @param choice string|nil
--- @return Look|nil look
function Looks:fromChoice(choice)
  choice = tostring(choice or "")
  local id = tonumber(choice:match("%((%d+)%)%s*$"))
  if id then
    return self:get(id)
  end
  local wanted = choice:match("^%s*(.-)%s*$"):lower()
  for _, look in ipairs(self:list()) do
    if look.name:lower() == wanted then
      return look
    end
  end
  return nil
end

--- @param color any
--- @return string|nil color The color as `#RRGGBB`, or nil if it is not one.
local function normalizeColor(color)
  color = tostring(color or "")
  if color:match("^#%x%x%x%x%x%x$") then
    return color:upper()
  end
  return nil
end

--- @param value any
--- @param low integer
--- @param high integer
--- @return boolean
local function wholeBetween(value, low, high)
  return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

--- @param text string
--- @return integer count Characters, as the tab counts them: UTF-8 continuation bytes don't count.
local function characters(text)
  return #text:gsub("[\128-\191]", "")
end

--- @param raw any
--- @return LookBadge|nil badge
--- @return string|nil err
local function checkBadge(raw)
  if type(raw) ~= "table" then
    return nil, "a badge needs its text, place and colors"
  end
  local text = tostring(raw.text or ""):match("^%s*(.-)%s*$")
  if text == "" or characters(text) > Looks.MAX_BADGE then
    return nil, string.format("a badge is 1 to %d characters", Looks.MAX_BADGE)
  end
  if text:find("%c") then
    return nil, "a badge can't hold control characters"
  end
  local place
  for _, p in ipairs(Looks.BADGE_PLACES) do
    if p == raw.place then
      place = p
    end
  end
  if not place then
    return nil, "unknown badge place"
  end
  local color = normalizeColor(raw.color)
  local background = raw.background == "None" and "None" or normalizeColor(raw.background)
  if not color or not background then
    return nil, "a badge's colors are #RRGGBB, and its background can be None"
  end
  if raw.size ~= nil and not wholeBetween(raw.size, Looks.MIN_BADGE_SIZE, Looks.MAX_BADGE_SIZE) then
    return nil,
      string.format("a badge's size is a whole percent from %d to %d", Looks.MIN_BADGE_SIZE, Looks.MAX_BADGE_SIZE)
  end
  return {
    text = text,
    place = place,
    color = color,
    background = background,
    size = raw.size ~= 100 and raw.size or nil,
  }
end

--- Check a look's customization. What the tab doesn't set, and keys this driver doesn't know,
--- are left out, so the picture keeps its own.
--- @param raw any
--- @return LookCustom|nil custom Nil for no customization.
--- @return string|nil err Why it was refused.
local function checkCustom(raw)
  if raw == nil then
    return nil
  end
  if type(raw) ~= "table" then
    return nil, "a look's customization is a table"
  end
  local custom = {}
  for _, key in ipairs(CUSTOM_COLORS) do
    if raw[key] ~= nil then
      custom[key] = normalizeColor(raw[key])
      if not custom[key] then
        return nil, "colors are #RRGGBB"
      end
    end
  end
  if raw.size ~= nil then
    if not wholeBetween(raw.size, Looks.MIN_SIZE, 100) then
      return nil, string.format("size is a whole percent from %d to 100", Looks.MIN_SIZE)
    end
    custom.size = raw.size ~= 100 and raw.size or nil
  end
  for _, key in ipairs({ "x", "y" }) do
    if raw[key] ~= nil then
      if not wholeBetween(raw[key], -Looks.MAX_SHIFT, Looks.MAX_SHIFT) then
        return nil, string.format("position is a whole percent from -%d to %d", Looks.MAX_SHIFT, Looks.MAX_SHIFT)
      end
      custom[key] = raw[key] ~= 0 and raw[key] or nil
    end
  end
  if raw.badge ~= nil then
    local badge, err = checkBadge(raw.badge)
    if not badge then
      return nil, err
    end
    custom.badge = badge
  end
  return next(custom) and custom or nil
end

--- @param shape any
--- @return boolean
local function knownShape(shape)
  for _, s in ipairs(Looks.SHAPES) do
    if s == shape then
      return true
    end
  end
  return false
end

--- Check a look's fields from the Button tab.
--- @private
--- @param fields table
--- @param exceptId integer|nil The look being edited, whose own name is no clash.
--- @return table|nil look The checked fields, or nil.
--- @return string|nil err Why the fields were refused.
function Looks:_check(fields, exceptId)
  if type(fields) ~= "table" then
    return nil, "no look given"
  end
  local name = tostring(fields.name or ""):match("^%s*(.-)%s*$")
  if name == "" then
    return nil, "a look needs a name"
  end
  -- Characters, as the tab counts them: UTF-8 continuation bytes don't count.
  if characters(name) > Looks.MAX_NAME then
    return nil, string.format("a look's name can be at most %d characters", Looks.MAX_NAME)
  end
  if name:find(",", 1, true) then
    return nil, "a look's name can't contain a comma"
  end
  for _, other in ipairs(self:list()) do
    if other.id ~= exceptId and other.name:lower() == name:lower() then
      return nil, string.format("another look is already named %s", other.name)
    end
  end
  local icon = fields.icon
  if type(icon) ~= "table" then
    return nil, "a look needs an icon"
  end
  local iconId = tostring(icon.id or "")
  if not iconId:match("^[%w%-]+:[%w%-]+$") then
    return nil, "the icon's name is not an icon pack name"
  end
  local carried = icon.carried == true
  local body = nil
  if not carried then
    body = tostring(icon.body or "")
    if body == "" or #body > Looks.MAX_ICON_BODY then
      return nil, "the icon's picture is missing or too large"
    end
  end
  local width, height = tonumber(icon.width), tonumber(icon.height)
  if not width or not height or width <= 0 or height <= 0 then
    return nil, "the icon's size is missing"
  end
  local licenseUrl = tostring(icon.licenseUrl or "")
  if licenseUrl ~= "" and not licenseUrl:match("^https://") then
    return nil, "the icon's license address is not an https address"
  end
  local iconColor, tileColor = normalizeColor(fields.iconColor), normalizeColor(fields.tileColor)
  if not iconColor or not tileColor then
    return nil, "colors are #RRGGBB"
  end
  if not knownShape(fields.tileShape) then
    return nil, "unknown tile shape"
  end
  local glow = fields.glow
  if glow == nil then
    glow = Looks.FULL_GLOW
  end
  if type(glow) ~= "number" or glow ~= math.floor(glow) or glow < 0 or glow > Looks.MAX_GLOW then
    return nil, "glow is a whole percent from 0 to 200"
  end
  if fields.grayscale ~= nil and type(fields.grayscale) ~= "boolean" then
    return nil, "grayscale is on or off"
  end
  local custom, customErr = checkCustom(fields.custom)
  if customErr then
    return nil, customErr
  end
  if fields.showWhen ~= nil and type(fields.showWhen) ~= "string" then
    return nil, '"Show when" is text'
  end
  local showWhen = fields.showWhen and fields.showWhen:match("^%s*(.-)%s*$") or ""
  if #showWhen > Looks.MAX_SHOW_WHEN then
    return nil, string.format('"Show when" can be at most %d characters', Looks.MAX_SHOW_WHEN)
  end
  return {
    name = name,
    icon = {
      id = iconId,
      body = body,
      carried = carried or nil,
      width = width,
      height = height,
      license = tostring(icon.license or ""):sub(1, 100),
      licenseUrl = licenseUrl:sub(1, 300),
    },
    iconColor = iconColor,
    tileShape = fields.tileShape,
    tileColor = tileColor,
    inCycle = fields.inCycle ~= false,
    glow = glow,
    grayscale = fields.grayscale == true,
    custom = custom,
    showWhen = showWhen ~= "" and showWhen or nil,
  }
end

--- A look's customization as one string, the same for the same picture.
--- @param look Look
--- @return string key
function Looks.customKey(look)
  local custom = type(look.custom) == "table" and look.custom or {}
  local parts = {}
  for _, key in ipairs(CUSTOM_COLORS) do
    table.insert(parts, tostring(custom[key] or ""))
  end
  table.insert(parts, tostring(custom.size or 100))
  table.insert(parts, tostring(custom.x or 0))
  table.insert(parts, tostring(custom.y or 0))
  local badge = type(custom.badge) == "table" and custom.badge or {}
  table.insert(parts, tostring(badge.text or ""))
  table.insert(parts, tostring(badge.place or ""))
  table.insert(parts, tostring(badge.color or ""))
  table.insert(parts, tostring(badge.background or ""))
  table.insert(parts, tostring(badge.size or 100))
  return table.concat(parts, "\n")
end

--- @param look Look
--- @return integer glow How much of its picture's glow the look draws, 0 to 200.
function Looks.glow(look)
  return tonumber(look.glow) or Looks.FULL_GLOW
end

--- @param look Look
--- @return boolean grayscale Whether the look is drawn in grays.
function Looks.grayscale(look)
  return look.grayscale == true
end

--- Whether stepping through the cycle can land on a look.
--- @param look Look
--- @return boolean
function Looks.inCycle(look)
  return look.inCycle ~= false
end

--- Add a look at the end of the list.
--- @param fields table The look's fields from the Button tab.
--- @return Look|nil look The new look, or nil.
--- @return string|nil err Why it was refused.
function Looks:add(fields)
  local data = self:_load()
  if #data.list >= Looks.MAX then
    return nil, string.format("a button has at most %d looks", Looks.MAX)
  end
  local look, err = self:_check(fields)
  if not look then
    return nil, err
  end
  look.id = data.nextId
  data.nextId = data.nextId + 1
  table.insert(data.list, look)
  self:_save(data)
  log:debug("Added look %s", Looks.label(look))
  return look
end

--- Change a look's fields. Its drawn picture is kept until a new one arrives.
--- @param id integer
--- @param fields table The look's fields from the Button tab.
--- @return Look|nil look The changed look, or nil.
--- @return string|nil err Why it was refused.
function Looks:update(id, fields)
  id = tonumber(id)
  local data = self:_load()
  for i, old in ipairs(data.list) do
    if old.id == id then
      local look, err = self:_check(fields, id)
      if not look then
        return nil, err
      end
      look.id = id
      look.image = old.image
      if look.image and Looks._drawnDiffers(old, look) then
        look.image.stale = true
      end
      data.list[i] = look
      self:_save(data)
      return look
    end
  end
  return nil, "no such look"
end

--- Whether two versions of a look draw different pictures.
--- @param a Look
--- @param b Look
--- @return boolean
function Looks._drawnDiffers(a, b)
  -- A carried icon's id names its markup, so the ids alone tell when either is carried.
  local carried = a.icon.carried or b.icon.carried
  if a.icon.id ~= b.icon.id or (not carried and a.icon.body ~= b.icon.body) then
    return true
  end
  for _, field in ipairs(DRAWN_FIELDS) do
    if a[field] ~= b[field] then
      return true
    end
  end
  return Looks.glow(a) ~= Looks.glow(b)
    or Looks.grayscale(a) ~= Looks.grayscale(b)
    or Looks.customKey(a) ~= Looks.customKey(b)
end

--- Record that a look's picture arrived, or with nil that it is gone.
--- @param id integer
--- @param bytes integer|nil
--- @return Look|nil look
function Looks:setImage(id, bytes)
  id = tonumber(id)
  local data = self:_load()
  for _, look in ipairs(data.list) do
    if look.id == id then
      look.image = bytes and { bytes = bytes } or nil
      self:_save(data)
      return look
    end
  end
  return nil
end

--- @param id integer
--- @return Look|nil removed The removed look, or nil if there was none.
function Looks:delete(id)
  id = tonumber(id)
  local data = self:_load()
  for i, look in ipairs(data.list) do
    if look.id == id then
      table.remove(data.list, i)
      if data.defaultId == id then
        data.defaultId = nil
      end
      self:_save(data)
      return look
    end
  end
  return nil
end

--- Put the looks in a new order. Every look must be named once.
--- @param ids (integer|string)[]
--- @return boolean ok
--- @return string|nil err
function Looks:reorder(ids)
  local data = self:_load()
  if type(ids) ~= "table" or #ids ~= #data.list then
    return false, "the order must name every look once"
  end
  local byId, list, seen = {}, {}, {}
  for _, look in ipairs(data.list) do
    byId[look.id] = look
  end
  for _, raw in ipairs(ids) do
    local id = tonumber(raw)
    if not id or not byId[id] or seen[id] then
      return false, "the order must name every look once"
    end
    seen[id] = true
    table.insert(list, byId[id])
  end
  data.list = list
  self:_save(data)
  return true
end

--- @return integer|nil id The look By Value shows when no Show when is true.
function Looks:defaultId()
  return tonumber(self:_load().defaultId)
end

--- Pick the look By Value shows when no Show when is true.
--- @param id integer|nil Nil for none.
function Looks:setDefault(id)
  local data = self:_load()
  data.defaultId = id
  self:_save(data)
end

--- Forget every look. Ids go on from where they were, so a programming choice naming an old
--- look never finds a new one.
function Looks:clear()
  local data = self:_load()
  self:_save({ nextId = data.nextId, list = {} })
end

return Looks
