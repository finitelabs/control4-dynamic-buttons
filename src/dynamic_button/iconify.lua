-- The icon packs the Button tab may search, and the Iconify addresses the driver fetches when the
-- tab can't reach Iconify itself. Only these packs: each needs no credit on every icon.

local Iconify = {}

--- Iconify's public API: no account or key.
Iconify.API = "https://api.iconify.design"

--- The packs offered, by Iconify prefix.
Iconify.PACKS = {
  "material-symbols",
  "mdi",
  "fluent",
  "ph",
  "tabler",
  "mingcute",
  "carbon",
  "bi",
  "lucide",
  "iconoir",
  "ion",
  "heroicons",
  "meteocons",
  "wi",
}

--- The longest search the driver passes on.
Iconify.MAX_QUERY = 64

--- The most icons of one pack fetched in one request.
Iconify.MAX_ICONS = 48

local allowed = {}
for _, prefix in ipairs(Iconify.PACKS) do
  allowed[prefix] = true
end

--- @param prefix string
--- @return boolean
function Iconify.allowed(prefix)
  return allowed[prefix] == true
end

--- @param s string
--- @return string encoded
local function encode(s)
  return (s:gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--- The Iconify address for one of the Button tab's requests, or nil for any other request.
--- @param kind string "search", "icon" or "collections".
--- @param value string|nil The search text, or the icons' `<pack>:<name>[,<name>...]`.
--- @return string|nil url
--- @return string|nil err
function Iconify.url(kind, value)
  local packs = table.concat(Iconify.PACKS, ",")
  if kind == "search" then
    local query = tostring(value or ""):match("^%s*(.-)%s*$")
    if query == "" or #query > Iconify.MAX_QUERY or query:find("[%c]") then
      return nil, "search text is empty or too long"
    end
    return string.format("%s/search?query=%s&prefixes=%s&limit=96", Iconify.API, encode(query), packs)
  elseif kind == "icon" then
    local prefix, names = tostring(value or ""):match("^([%w%-]+):([%w%-,]+)$")
    if not prefix or not Iconify.allowed(prefix) then
      return nil, "not an offered icon pack"
    end
    local count = select(2, names:gsub(",", ",")) + 1
    if count > Iconify.MAX_ICONS or names:find(",,", 1, true) or names:match("^,") or names:match(",$") then
      return nil, "too many icons, or an empty icon name"
    end
    return string.format("%s/%s.json?icons=%s", Iconify.API, prefix, names)
  elseif kind == "collections" then
    return string.format("%s/collections?prefixes=%s", Iconify.API, packs)
  end
  return nil, "unknown request"
end

return Iconify
