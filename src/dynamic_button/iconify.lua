-- The icon packs the Button tab may search, and the Iconify addresses the driver fetches when the
-- tab can't reach Iconify itself. Only these packs: each needs no credit on every icon.

require("drivers-common-public.global.url")

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

--- The most results a search asks for; the tab filters them by style.
Iconify.SEARCH_LIMIT = 192

local allowed = {}
for _, prefix in ipairs(Iconify.PACKS) do
  allowed[prefix] = true
end

--- Whether the tab may search a pack.
--- @param prefix string
--- @return boolean offered Whether the pack is one the tab may search.
function Iconify.allowed(prefix)
  return allowed[prefix] == true
end

--- The packs a search names, all of them when it names none.
--- @param prefixes string|nil Comma-separated pack prefixes.
--- @return string|nil packs Comma-separated, or nil when one is not offered.
local function searchPacks(prefixes)
  prefixes = tostring(prefixes or "")
  if prefixes == "" then
    return table.concat(Iconify.PACKS, ",")
  end
  local list = {}
  for prefix in prefixes:gmatch("[^,]+") do
    if not Iconify.allowed(prefix) then
      return nil
    end
    table.insert(list, prefix)
  end
  return #list > 0 and table.concat(list, ",") or nil
end

--- The Iconify address for one of the Button tab's requests, or nil for any other request.
--- @param kind string "search", "icon" or "collections".
--- @param value string|nil The search text, or the icons' `<pack>:<name>[,<name>...]`.
--- @param prefixes? string|nil For a search, the packs to search, comma-separated (optional). All by default.
--- @return string|nil url
--- @return string|nil err
function Iconify.url(kind, value, prefixes)
  local packs = table.concat(Iconify.PACKS, ",")
  if kind == "search" then
    local query = tostring(value or ""):match("^%s*(.-)%s*$")
    if query == "" or #query > Iconify.MAX_QUERY or query:find("[%c]") then
      return nil, "search text is empty or too long"
    end
    local searched = searchPacks(prefixes)
    if not searched then
      return nil, "not an offered icon pack"
    end
    return string.format(
      "%s/search?query=%s&prefixes=%s&limit=%d",
      Iconify.API,
      URLEncode(query, true),
      searched,
      Iconify.SEARCH_LIMIT
    )
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
