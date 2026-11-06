--- Pictures from a web address that refresh: only the shown look's is fetched, at once when it's
--- older than its refresh and then as often as it asks; the same bytes again change nothing, new
--- bytes are served as the site sent them; a failure keeps the last picture and warns once; only a
--- PNG or JPEG refreshes; a look on one keeps nothing drawn on it; the two programming commands; the
--- timer stops when nothing may fetch; and the address is in no log line.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_web_refresh.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Looks = require("dynamic_button.looks")
local Pictures = require("dynamic_button.pictures")
local WebPictures = require("dynamic_button.web_pictures")
local log = require("lib.logging")
require("lib.utils")

local function memoryStore()
  local data = {}
  return {
    get = function(_, key, default)
      local v = data[key]
      if v == nil then
        return default
      end
      return TableDeepCopy(v)
    end,
    set = function(_, key, value)
      data[key] = TableDeepCopy(value)
    end,
  }
end

--- @param n integer
--- @return string bytes Big-endian, two bytes.
local function be16(n)
  return string.char(math.floor(n / 256), n % 256)
end

--- A small JPEG with a real frame header, so its size reads.
--- @param width integer
--- @param height integer
--- @param tag string Makes the bytes differ.
--- @return string jpeg
local function jpeg(width, height, tag)
  return "\255\216"
    .. "\255\224\0\16JFIF\0\1\1\0\0\1\0\1\0\0"
    .. "\255\192\0\17\8"
    .. be16(height)
    .. be16(width)
    .. "\3\1\34\0\2\17\1\3\17\1"
    .. "\255\218"
    .. tag
    .. "\255\217"
end

--- A small PNG with a real IHDR, so its size reads.
--- @param width integer
--- @param height integer
--- @param tag string
--- @return string png
local function png(width, height, tag)
  return H.PNG_SIGNATURE
    .. "\0\0\0\13IHDR\0\0"
    .. be16(width)
    .. "\0\0"
    .. be16(height)
    .. "\8\6\0\0\0"
    .. "crc!"
    .. tag
end

local ADDRESS = "http://user:secret@camera.local/snap.jpg?token=abc"
local SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>'

--- Capture warnings and info lines from the shared logger.
--- @return table lines { warn = {...}, info = {...} }
--- @return fun() restore
local function captureLog()
  local lines, was = { warn = {}, info = {} }, { warn = log.warn, info = log.info }
  for level in pairs(was) do
    log[level] = function(_, fmt, ...)
      table.insert(lines[level], string.format(fmt, ...))
    end
  end
  return lines, function()
    for level, fn in pairs(was) do
      log[level] = fn
    end
  end
end

--- A refresher over a memory store, with its fetches, timers, clock and served pictures in reach.
local function setup()
  local s = { clock = 1000, fetches = {}, timers = {}, arrived = {}, changed = 0, allowed = true }
  local store = memoryStore()
  local looks
  s.pictures = Pictures:new({
    store = store,
    used = function()
      local used = {}
      for _, look in ipairs(looks:list()) do
        used[look.icon.id] = true
      end
      return used
    end,
    now = function()
      return s.clock
    end,
  })
  looks = Looks:new(store, function(id)
    return s.pictures:get(id) ~= nil
  end, function(id)
    return s.pictures:refreshes(id)
  end)
  s.looks = looks
  s.refresher = WebPictures:new({
    pictures = s.pictures,
    looks = looks,
    arrived = function(id, data, source)
      table.insert(s.arrived, { id = id, data = data, source = source })
      looks:setImage(id, #data, #s.arrived, source)
    end,
    changed = function()
      s.changed = s.changed + 1
    end,
    allowed = function()
      return s.allowed
    end,
    now = function()
      return s.clock
    end,
    fetch = function(address, done)
      table.insert(s.fetches, { address = address, done = done })
    end,
    setTimer = function(name, ms, fn)
      s.timers[name] = { ms = ms, fn = fn }
    end,
    cancelTimer = function(name)
      s.timers[name] = nil
    end,
  })
  --- A look on a refreshing picture, with the picture's bytes served.
  function s.webLook(name, address, data, every)
    local picture = assert(s.pictures:addWeb(data, address, every or 300))
    local look = assert(looks:add(H.lookFields(name, {
      icon = { id = picture.id, stored = true, width = picture.width, height = picture.height },
    })))
    looks:setImage(look.id, #data, 0, picture.source)
    return looks:get(look.id), picture
  end
  --- The last fetch answers.
  function s.answer(body, err)
    local fetch = table.remove(s.fetches, 1)
    fetch.done(body, err)
    return fetch.address
  end
  function s.timer()
    return s.timers.WebPictureRefresh
  end
  return s
end

T.section("A picture's size, from its header")
T.eq("a JPEG's from its frame", { Pictures.dimensions(jpeg(640, 400, "a")) }, { 640, 400 })
T.eq("a PNG's from its IHDR", { Pictures.dimensions(png(300, 200, "a")) }, { 300, 200 })
T.eq("SVG has none here", { Pictures.dimensions(SVG) }, {})
T.eq("a JPEG cut before its frame has none", { Pictures.dimensions(jpeg(640, 400, "a"):sub(1, 22)) }, {})

T.section("Only a PNG or JPEG refreshes")
do
  local s = setup()
  local picture, err = s.pictures:addWeb(jpeg(640, 400, "a"), ADDRESS, 300)
  T.truthy("a JPEG is kept", picture)
  T.eq("named by its address's last part, with no login or token", picture.name, "snap.jpg")
  T.eq("with the address it refreshes from", s.pictures:address(picture.id), ADDRESS)
  T.eq("its size from its header", { picture.width, picture.height }, { 640, 400 })
  T.eq("and a name for its bytes", picture.source, Pictures.source(jpeg(640, 400, "a")))
  picture, err = s.pictures:addWeb(png(300, 300, "a"), ADDRESS, 60)
  T.truthy("a PNG is kept", picture)
  picture, err = s.pictures:addWeb(SVG, ADDRESS, 300)
  T.eq("SVG isn't", picture, nil)
  T.eq("and the tab is told why", err, "A picture that refreshes has to be a PNG or JPEG.")
  T.eq("nor is a GIF", (s.pictures:addWeb("GIF89a......", ADDRESS, 300)), nil)
  picture, err = s.pictures:addWeb(jpeg(640, 400, "a"), ADDRESS, 120)
  T.eq("a refresh not on the list isn't", picture, nil)
  T.contains("and says which there are", err, "every minute, 5 minutes, 15 minutes or hour")
  T.eq("an address that isn't http isn't", (s.pictures:addWeb(jpeg(1, 1, "a"), "ftp://camera.local/a.jpg", 300)), nil)
  local big = jpeg(640, 400, string.rep("x", Pictures.MAX_FETCH))
  T.eq(
    "nor are more than 2 MB",
    select(2, s.pictures:addWeb(big, ADDRESS, 300)),
    "The picture at that address is larger than 2 MB."
  )
  local upload = assert(s.pictures:add(jpeg(10, 10, "u"), { width = 10, height = 10, name = "u.jpg" }))
  T.eq("an upload doesn't refresh", s.pictures:refreshes(upload.id), false)
end

T.section("A look on a refreshing picture keeps nothing drawn on it")
do
  local s = setup()
  local picture = assert(s.pictures:addWeb(jpeg(640, 400, "a"), ADDRESS, 300))
  local fields = H.lookFields("Driveway", {
    icon = { id = picture.id, stored = true, width = 640, height = 400 },
    tileShape = "Circle",
    glow = 50,
    grayscale = true,
    custom = { size = 80, x = 2, badge = { text = "Hi", place = "Top Right", color = "#FFFFFF", background = "None" } },
  })
  local look = assert(s.looks:add(fields))
  T.eq("no tile", look.tileShape, "None")
  T.eq("its whole glow", look.glow, Looks.FULL_GLOW)
  T.eq("no grayscale", look.grayscale, false)
  T.eq("no size, position or badge", look.custom, nil)
  local upload = assert(s.pictures:add(jpeg(10, 10, "u"), { width = 10, height = 10, name = "u.jpg" }))
  fields.name, fields.icon = "Logo", { id = upload.id, stored = true, width = 10, height = 10 }
  local other = assert(s.looks:add(fields))
  T.eq("a picture that doesn't refresh keeps its tile", other.tileShape, "Circle")
  T.eq("and its badge", other.custom.badge.text, "Hi")
end

T.section("Only the shown look's picture is fetched")
do
  local s = setup()
  local driveway = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  local radar = s.webLook("Radar", "http://weather.local/radar.png", png(300, 300, "r"), 60)
  local logo = assert(s.looks:add(H.lookFields("Logo")))
  s.refresher:watch(logo)
  T.eq("a look that doesn't refresh arms nothing", s.timer(), nil)
  T.eq("and fetches nothing", #s.fetches, 0)
  s.refresher:watch(driveway)
  T.eq("the shown one waits out its refresh", s.timer().ms, 300 * 1000)
  T.eq("its bytes are new, so nothing is fetched yet", #s.fetches, 0)
  s.clock = s.clock + 300
  s.timer().fn()
  T.eq("then its address is fetched", #s.fetches, 1)
  T.eq("its own, not another look's", s.fetches[1].address, ADDRESS)
  s.answer(jpeg(640, 400, "a"))
  T.eq("the next fetch waits a whole refresh", s.timer().ms, 300 * 1000)
  s.refresher:watch(nil)
  T.eq("nothing shown, nothing armed", s.timer(), nil)
  s.clock = s.clock + 30
  s.refresher:watch(radar)
  T.eq(
    "another look's picture, older than its minute, is fetched at once",
    s.fetches[1].address,
    "http://weather.local/radar.png"
  )
  T.eq("and nothing is armed while it's under way", s.timer(), nil)
end

T.section("The same bytes change nothing; new ones are served as they came")
do
  local s = setup()
  local driveway, picture = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  s.refresher:watch(driveway)
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(jpeg(640, 400, "a"))
  T.eq("the same bytes serve nothing", #s.arrived, 0)
  T.eq("keep the picture's time", s.pictures:get(picture.id).fetchedAt, 1000)
  T.eq("and tell the tab nothing", s.changed, 0)
  T.eq("its last good refresh is now", s.refresher:status(picture.id).refreshedAt, 1300)
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(jpeg(640, 400, "b"))
  T.eq("new bytes are served once", #s.arrived, 1)
  T.eq("as the site sent them", s.arrived[1].data, jpeg(640, 400, "b"))
  T.eq("to the shown look", s.arrived[1].id, driveway.id)
  T.eq("the picture keeps them", s.pictures:load(picture.id), jpeg(640, 400, "b"))
  T.eq("under their name", s.pictures:get(picture.id).source, Pictures.source(jpeg(640, 400, "b")))
  T.eq("the tab is told", s.changed, 1)
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(png(320, 200, "c"))
  T.eq("a PNG may follow a JPEG", s.pictures:get(picture.id).kind, "png")
  T.eq("with its own size", { s.pictures:get(picture.id).width, s.pictures:get(picture.id).height }, { 320, 200 })
  T.eq("and the JPEG's file goes", s.pictures:load(picture.id), png(320, 200, "c"))
end

T.section("A failed fetch keeps the last picture and warns once")
do
  local s = setup()
  local driveway, picture = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  local lines, restore = captureLog()
  s.refresher:watch(driveway)
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(nil, "The address answered with status 500.")
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(SVG)
  restore()
  T.eq("one warning for the run of failures", #lines.warn, 1)
  T.contains("that says why", lines.warn[1], "status 500")
  T.eq("the last picture stays", s.pictures:load(picture.id), jpeg(640, 400, "a"))
  T.eq("and nothing is served", #s.arrived, 0)
  T.eq(
    "the tab sees the latest error",
    s.refresher:status(picture.id).error,
    "A picture that refreshes has to be a PNG or JPEG."
  )
  T.eq("and when the last good refresh was", s.refresher:status(picture.id).refreshedAt, 1000)
  T.eq("a failure waits a whole refresh too", s.timer().ms, 300 * 1000)
  lines, restore = captureLog()
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(jpeg(640, 400, "a"))
  restore()
  T.eq("a success clears the error", s.refresher:status(picture.id).error, nil)
  T.eq("and says it refreshes again", #lines.info, 1)
  T.eq("without a warning", #lines.warn, 0)
end

T.section("Nothing fetches while nothing may change the picture")
do
  local s = setup()
  local driveway, picture = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  s.allowed = false
  s.refresher:watch(driveway)
  T.eq("no timer", s.timer(), nil)
  local ok = s.refresher:refreshPicture(picture.id)
  T.eq("and a refresh is turned away", ok, false)
  T.eq("so nothing is fetched", #s.fetches, 0)
end

T.section("A new address: the old answer is for no picture")
do
  local s = setup()
  local driveway, picture = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  s.refresher:watch(driveway)
  s.refresher:refresh()
  s.pictures:setAddress(picture.id, "http://camera.local/other.jpg")
  s.refresher:forget(picture.id)
  T.eq("the name follows the address", s.pictures:get(picture.id).name, "other.jpg")
  s.answer(jpeg(640, 400, "old"))
  T.eq("the old address's answer is dropped", #s.arrived, 0)
  T.eq("and the new address is fetched at once", s.fetches[1].address, "http://camera.local/other.jpg")
  s.answer(jpeg(640, 400, "new"))
  T.eq("its answer is served", s.arrived[1].data, jpeg(640, 400, "new"))
end

T.section("A look sharing a picture catches up when it's shown")
do
  local s = setup()
  local driveway, picture = s.webLook("Driveway", ADDRESS, jpeg(640, 400, "a"))
  local copy = assert(s.looks:add(H.lookFields("Driveway 2", { icon = driveway.icon })))
  s.looks:setImage(copy.id, 10, 0, picture.source)
  s.refresher:watch(driveway)
  s.clock = s.clock + 300
  s.timer().fn()
  s.answer(jpeg(640, 400, "b"))
  s.refresher:watch(s.looks:get(copy.id))
  T.eq("the copy is served the picture's latest bytes", s.arrived[2].data, jpeg(640, 400, "b"))
  T.eq("to the copy", s.arrived[2].id, copy.id)
  T.eq("without a fetch, since they're fresh", #s.fetches, 0)
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

local JPEG_A, JPEG_B = jpeg(640, 400, "a"), jpeg(640, 400, "b")
local answer = { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG_A }
H.urlAnswer = function(url)
  if url:find("^http://user:secret@camera.local/") or url:find("^http://camera.local/") then
    return answer
  end
  return nil
end
H.start()

local function addWeb(url, every)
  H.mark()
  H.tab("_ADD_WEB_PICTURE", { request = "w1", url = url, every = every })
  return H.lastUi("PICTURE_STORED")
end

--- Save a look on a picture as the tab does: the stored id, no body, no picture of its own sent.
local function saveOn(name, id, extra)
  H.mark()
  local fields = H.lookFields(name, extra)
  fields.icon = { id = id, stored = true, width = 640, height = 400 }
  H.tab("_SAVE_LOOK", fields)
  return tonumber(H.lastUi("SAVED").look)
end

T.section("The tab adds a picture that refreshes")
local stored = addWeb(ADDRESS, 300)
T.truthy("it's kept under an id", stored and stored.picture)
local webId = stored.picture
local entry
for _, p in ipairs(H.state().pictures) do
  if p.id == webId then
    entry = p
  end
end
T.eq("the tab sees how often it refreshes", entry.every, 300)
T.eq("and its address, to show in the editor", entry.url, ADDRESS)
T.eq("named with no login or token", entry.name, "snap.jpg")
T.truthy("and when it last refreshed", entry.refreshedAt)
T.contains("a refresh not on the list is refused", addWeb(ADDRESS, 30).error, "every minute")
answer = { headers = { ["Content-Type"] = "image/gif" }, body = "GIF89a......" }
T.eq("so is a GIF from the address", addWeb(ADDRESS, 300).error, "A picture that refreshes has to be a PNG or JPEG.")
answer = { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG_A }

T.section("A look on it is served the bytes as they came")
local driveway = saveOn("Driveway", webId, { tileShape = "Circle", custom = { badge = { text = "Hi" } } })
local served = H.served()[driveway .. ".png"]
T.eq("the served file is the site's JPEG, byte for byte", served, JPEG_A)
T.truthy("the button shows it", H.lastIcon() and H.lastIcon().params.icon:find("/" .. driveway .. ".png", 1, true))
local look = H.state().looks[#H.state().looks]
T.eq("drawn with no tile", look.tileShape, "None")
T.eq("and no badge", look.custom, nil)
T.truthy("the timer waits for the next refresh", Timer.WebPictureRefresh)

T.section("Refresh Web Picture")
H.mark()
local fetchedBefore = #H.fetched
EC.Refresh_Web_Picture()
T.eq("fetches the shown look's address", H.fetched[#H.fetched], ADDRESS)
T.eq("once", #H.fetched, fetchedBefore + 1)
T.eq("the same bytes tell the proxy nothing", H.lastIcon(), nil)
answer = { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG_B }
EC.Refresh_Web_Picture()
local icon = H.lastIcon()
T.truthy("new bytes are shown under a new address", icon)
T.eq("and served as they came", H.served()[driveway .. ".png"], JPEG_B)

T.section("Set Web Address")
local logo = H.addLook("Logo")
local lines, restore = captureLog()
fetchedBefore = #H.fetched
EC.Set_Web_Address({ Look = "Logo (" .. logo .. ")", Address = "http://camera.local/b.jpg" })
EC.Set_Web_Address({ Look = "Nothing (99)", Address = "http://camera.local/b.jpg" })
EC.Set_Web_Address({ Look = "Driveway (" .. driveway .. ")", Address = "not an address" })
restore()
T.eq("a look that doesn't refresh, no look, and a bad address are each refused", #lines.warn, 3)
T.eq("and fetch nothing", #H.fetched, fetchedBefore)
EC.Set_Web_Address({ Look = "Driveway (" .. driveway .. ")", Address = "http://camera.local/b.jpg" })
T.eq("a good one is fetched at once", H.fetched[#H.fetched], "http://camera.local/b.jpg")
for _, p in ipairs(H.state().pictures) do
  if p.id == webId then
    entry = p
  end
end
T.eq("and named for it", entry.name, "b.jpg")
T.eq(
  "Set Web Address lists only the looks that refresh",
  GCPL.Set_Web_Address("Look"),
  { "Driveway (" .. driveway .. ")" }
)

T.section("The timer runs only while a refreshing look shows")
EC.Show_Look({ Look = "Logo (" .. logo .. ")" })
T.eq("another look stops it", Timer.WebPictureRefresh, nil)
EC.Show_Look({ Look = "Driveway (" .. driveway .. ")" })
T.truthy("showing it again arms it", Timer.WebPictureRefresh)
OnDriverRemovedFromProject()
T.eq("removing the driver stops it", Timer.WebPictureRefresh, nil)
H.restart()
T.truthy("a restart arms it again for the shown look", Timer.WebPictureRefresh or #H.fetched > 0)
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("a reset stops it", Timer.WebPictureRefresh, nil)
T.eq("and keeps no picture", #H.state().pictures, 0)

T.section("The address is in no log line, at any level")
H.restart()
local logged = {}
local wasPrint, wasDebug, wasError = print, C4.DebugLog, C4.ErrorLog
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  table.insert(logged, table.concat(parts, " "))
end
C4.DebugLog = function(_, text)
  table.insert(logged, tostring(text))
end
C4.ErrorLog = C4.DebugLog
DEBUGPRINT = true
log:setLogLevel("6 - Ultra")
log:setOutputPrintEnabled(true)
log:setOutputC4LogEnabled(true)
answer = { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG_A }
local function tabRequest(command, params)
  return UIRequest(command, { DATA = (C4:Base64Encode(JSON:encode(params)):gsub(string.rep(".", 76), "%0\n")) })
end
tabRequest("_FETCH_PICTURE", { request = "f1", url = ADDRESS })
tabRequest("_ADD_WEB_PICTURE", { request = "w2", url = ADDRESS, every = 60 })
local secretId = H.lastUi("PICTURE_STORED").picture
local fields = H.lookFields("Gate")
fields.icon = { id = secretId, stored = true, width = 640, height = 400 }
tabRequest("_SAVE_LOOK", fields)
local gate = tonumber(H.lastUi("SAVED").look)
answer = { code = 503, headers = {}, body = "" }
ExecuteCommand("Refresh Web Picture", {})
answer = { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG_B }
ExecuteCommand("Refresh Web Picture", {})
ExecuteCommand(
  "Set Web Address",
  { Look = "Gate (" .. gate .. ")", Address = "http://user:secret@camera.local/c.jpg?token=abc" }
)
tabRequest("_GET_STATE", {})
print, C4.DebugLog, C4.ErrorLog = wasPrint, wasDebug, wasError
DEBUGPRINT = false
log:setOutputPrintEnabled(false)
log:setOutputC4LogEnabled(false)
log:setLogLevel("3 - Info")
T.truthy("the run logged", #logged > 10)
local leaks = {}
for _, line in ipairs(logged) do
  if line:find("secret", 1, true) or line:find("token=", 1, true) or line:find("camera.local", 1, true) then
    table.insert(leaks, line)
  end
end
T.eq("no line holds the login, the token or the host", leaks, {})

T.finish()
