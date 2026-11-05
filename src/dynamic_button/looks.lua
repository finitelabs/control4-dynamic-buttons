-- A button's looks: each one picture the Navigator button can show, with the icon it was drawn
-- from and how it was drawn. The list order is the order the Button tab shows them in, and the
-- order the button cycles through them.

local log = require("lib.logging")

--- @class LookIcon
--- @field id string The icon's Iconify name, `<pack>:<name>`.
--- @field body string The icon's SVG markup, without the outer svg element.
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
--- @field image? { bytes: integer, stale?: boolean } The drawn picture, once the Button tab has sent it;
--- stale while the look's fields have changed since it was drawn.

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

--- The largest icon markup a look keeps, in bytes.
Looks.MAX_ICON_BODY = 16 * 1024

local LOOKS_PERSIST_KEY = "Looks"

--- @param store table A persist-like store with get(key, default) and set(key, value).
--- @return Looks looks
function Looks:new(store)
  local instance = setmetatable({}, self)
  instance._store = store
  return instance
end

--- @private
--- @return { nextId: integer, list: Look[] } data
function Looks:_load()
  local data = self._store:get(LOOKS_PERSIST_KEY)
  if type(data) ~= "table" or type(data.list) ~= "table" then
    data = { nextId = 1, list = {} }
  end
  data.nextId = tonumber(data.nextId) or 1
  return data
end

--- @private
--- @param data { nextId: integer, list: Look[] }
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
  if #name:gsub("[\128-\191]", "") > Looks.MAX_NAME then
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
  local body = tostring(icon.body or "")
  if body == "" or #body > Looks.MAX_ICON_BODY then
    return nil, "the icon's picture is missing or too large"
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
  return {
    name = name,
    icon = {
      id = iconId,
      body = body,
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
  }
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
  if a.icon.id ~= b.icon.id or a.icon.body ~= b.icon.body then
    return true
  end
  for _, field in ipairs(DRAWN_FIELDS) do
    if a[field] ~= b[field] then
      return true
    end
  end
  return Looks.glow(a) ~= Looks.glow(b) or Looks.grayscale(a) ~= Looks.grayscale(b)
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

--- Forget every look. Ids go on from where they were, so a programming choice naming an old
--- look never finds a new one.
function Looks:clear()
  local data = self:_load()
  self:_save({ nextId = data.nextId, list = {} })
end

return Looks
