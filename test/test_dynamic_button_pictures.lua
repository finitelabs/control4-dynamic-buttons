--- The button's own pictures: kept in its storage under ids of their own, refused when they aren't a
--- PNG, JPEG or SVG or are too large, deleted once no look uses them and the grace has passed; a look
--- that names one; the Button tab's upload, its request for one and a fetch from a web address.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_pictures.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Images = require("dynamic_button.images")
local Looks = require("dynamic_button.looks")
local Pictures = require("dynamic_button.pictures")
require("lib.utils")

--- @return table merged `a` with `b`'s fields over it.
local function merge(a, b)
  local out = TableDeepCopy(a)
  for k, v in pairs(b) do
    out[k] = v
  end
  return out
end

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

local JPEG = "\255\216\255\224" .. string.rep("j", 60)
local SVG =
  '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/></svg>'
local SIZE = { width = 600, height = 400, name = "porch.png" }

--- @return Pictures pictures
--- @return table<string, boolean> used
--- @return fun(seconds: number) advance
local function library()
  local clock, used = 1000, {}
  local pictures = Pictures:new({
    store = memoryStore(),
    used = function()
      return used
    end,
    now = function()
      return clock
    end,
  })
  return pictures, used, function(seconds)
    clock = clock + seconds
  end
end

T.section("What a picture is")
T.eq("a PNG by its signature", Pictures.kindOf(H.png("p")), "png")
T.eq("a JPEG by its first bytes", Pictures.kindOf(JPEG), "jpeg")
T.eq("SVG markup, after an XML declaration", Pictures.kindOf(SVG), "svg")
T.eq("SVG after a byte order mark", Pictures.kindOf("\239\187\191 <svg/>"), "svg")
T.eq("text that isn't SVG is nothing", Pictures.kindOf("<html><body/></html>"), nil)
T.eq("SVG with a NUL byte is nothing", Pictures.kindOf("<svg>\0</svg>"), nil)
T.eq(
  "SVG after comments and a doctype",
  Pictures.kindOf('<!-- a --><!DOCTYPE svg PUBLIC "x" "y" [ <!ENTITY e "f"> ]>\n<svg/>'),
  "svg"
)
T.eq("a page with SVG inside isn't SVG", Pictures.kindOf("<html><body><svg/></body></html>"), nil)
T.eq("nor is an element named like it", Pictures.kindOf("<svgx/>"), nil)
T.eq("a GIF is not kept as it is", Pictures.kindOf("GIF89a...."), nil)
T.eq("but can be fetched for the tab to draw", Pictures.fetchedKind("GIF89a...."), "gif")
T.eq("as can a WebP", Pictures.fetchedKind("RIFF\0\0\0\0WEBPVP8 "), "webp")
T.eq("and anything kept", Pictures.fetchedKind(JPEG), "jpeg")
T.eq("HTML is not a picture", Pictures.fetchedKind("<!doctype html><html></html>"), nil)

T.section("Adding pictures")
local pictures, used, advance = library()
local first = pictures:add(H.png("one"), SIZE)
local second = pictures:add(JPEG, { width = 240, height = 600, name = "  snapshot.jpg " })
local third = pictures:add(SVG, { width = 24, height = 24 })
T.eq("ids are the button's own, in order", { first.id, second.id, third.id }, { "mine:p1", "mine:p2", "mine:p3" })
T.eq("each knows its kind", { first.kind, second.kind, third.kind }, { "png", "jpeg", "svg" })
T.eq("and its size and bytes", { second.width, second.height, second.bytes }, { 240, 600, #JPEG })
T.eq("a name is trimmed", second.name, "snapshot.jpg")
T.eq("a picture with no name is called Picture", third.name, "Picture")
T.eq("the files are in the button's storage", ShimFiles("SANDBOX/pictures")["p2.jpg"], JPEG)
T.eq("and load back", pictures:load("mine:p3"), SVG)
T.eq("a picture it doesn't have loads nothing", pictures:load("mine:p99"), nil)
T.eq("they list oldest first", #pictures:list(), 3)

T.section("Names")
T.eq("a file's name is kept", Pictures.safeName(" porch.png "), "porch.png")
T.eq(
  "an address keeps its last part, without login, query or fragment",
  Pictures.safeName("http://admin:secret@camera.local/cgi/snapshot.jpg?token=abc#x"),
  "snapshot.jpg"
)
T.eq("or its host when it has no path", Pictures.safeName("https://user:pw@host.example:8443/?t=1"), "host.example")
T.eq(
  "a picture added under an address keeps only that",
  (library()):add(H.png("n"), { width = 1, height = 1, name = "http://a:b@c.local/x.png?key=1" }).name,
  "x.png"
)

T.section("Where a redirect points")
T.eq(
  "an absolute address",
  Pictures.resolve("http://a.local/x/y.png", "https://b.example/z.png"),
  "https://b.example/z.png"
)
T.eq("from the host's root", Pictures.resolve("http://a.local/x/y.png?q=1", "/z.png"), "http://a.local/z.png")
T.eq("beside the address", Pictures.resolve("http://a.local/x/y.png", "z.png"), "http://a.local/x/z.png")
T.eq("on a bare host", Pictures.resolve("http://a.local", "z.png"), "http://a.local/z.png")
T.eq("with the same scheme", Pictures.resolve("https://a.local/x", "//b.example/z.png"), "https://b.example/z.png")
T.eq("nowhere", Pictures.resolve("http://a.local/x", ""), nil)

T.section("Pictures refused")
local _, err = pictures:add("<html/>", SIZE)
T.eq("not a PNG, JPEG or SVG", err, "the picture is not a PNG, JPEG or SVG")
_, err = pictures:add(H.png("big", Pictures.MAX_BYTES + 1), SIZE)
T.eq("larger than 512 KB", err, "the picture is larger than 512 KB")
_, err = pictures:add("<svg>" .. string.rep(" ", Pictures.MAX_SVG_BYTES) .. "</svg>", SIZE)
T.eq("an SVG larger than 64 KB", err, "the picture is larger than 64 KB")
_, err = pictures:add(H.png("p"), { width = 0, height = 10 })
T.eq("a picture with no size", err, "the picture's size is missing")
_, err = pictures:add(H.png("p"), { width = "wide", height = 10 })
T.eq("or a size that isn't a number", err, "the picture's size is missing")
T.eq("nothing refused was kept", #pictures:list(), 3)

T.section("Pictures no look uses")
used["mine:p2"] = true
advance(Pictures.GRACE_SECONDS - 1)
pictures:collect()
T.eq("stay for 10 minutes after they're added", #pictures:list(), 3)
advance(1)
pictures:collect()
T.eq("then go, but one a look uses stays", { #pictures:list(), pictures:list()[1].id }, { 1, "mine:p2" })
T.eq("and their files go too", ShimFiles("SANDBOX/pictures")["p1.png"], nil)
local fourth = pictures:add(H.png("four"), SIZE)
T.eq("a new picture's id goes on from the last", fourth.id, "mine:p4")

T.section("The most pictures a button keeps")
local full = library()
for _ = 1, Pictures.MAX do
  full:add(H.png("x"), SIZE)
end
_, err = full:add(H.png("x"), SIZE)
T.eq("24, counting those still in their 10 minutes", err, "a button keeps at most 24 pictures")

T.section("Clearing")
pictures:clear()
T.eq("every picture goes", #pictures:list(), 0)
T.eq("with its file", ShimFiles("SANDBOX/pictures")["p2.jpg"], nil)
T.eq("and ids go on", pictures:add(H.png("five"), SIZE).id, "mine:p5")

T.section("Web addresses")
T.eq("http is fetched", Pictures.checkAddress(" http://camera.local/snapshot.jpg "), "http://camera.local/snapshot.jpg")
T.eq("as is https", Pictures.checkAddress("HTTPS://example.com/a.png"), "HTTPS://example.com/a.png")
_, err = Pictures.checkAddress("ftp://example.com/a.png")
T.eq("anything else is refused", err, "Enter an http or https address.")
_, err = Pictures.checkAddress("http://a b")
T.eq("as is an address with a space", err, "Enter an http or https address.")
_, err = Pictures.checkAddress("http:///a.png")
T.eq("or no host", err, "Enter an http or https address.")
_, err = Pictures.checkAddress("http://a/" .. string.rep("x", Pictures.MAX_ADDRESS))
T.eq("or too long", err, "That address is too long.")
T.eq("a picture body passes", Pictures.checkFetched(JPEG), nil)
T.eq(
  "a decoded JSON body isn't a picture",
  Pictures.checkFetched({ error = "x" }),
  "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."
)
T.eq(
  "a body over 2 MB is refused",
  Pictures.checkFetched(JPEG .. string.rep("j", Pictures.MAX_FETCH)),
  "The picture at that address is larger than 2 MB."
)
T.eq("a status is told", Pictures.fetchError({ code = 404 }), "The address answered with status 404.")
T.eq("no answer at all", Pictures.fetchError({ code = 0, error = "x" }), "The controller couldn't reach that address.")

T.section("Uploads by name")
local images = Images:new()
local b64 = C4:Base64Encode(SVG)
local accepts = function(data)
  if Pictures.kindOf(data) then
    return nil
  end
  return "picture is not a PNG, JPEG or SVG"
end
T.eq("a picture upload returns the whole picture", images:accept("picture", "t", 1, 1, b64, accepts), SVG)
_, err = images:accept("picture", "t", 1, 1, C4:Base64Encode("<html/>"), accepts)
T.eq("and its own check refuses", err, "picture is not a PNG, JPEG or SVG")
_, err = images:accept(7, "t", 1, 1, b64)
T.eq("a look's upload still takes only a PNG", err, "picture is not a PNG")
images:accept(7, "a", 1, 2, C4:Base64Encode(H.png("a", 12)):sub(1, 8))
T.eq("an upload by name", images:accept("picture", "b", 1, 1, b64, accepts), SVG)
T.eq(
  "leaves a look's upload in progress alone",
  images:accept(7, "a", 2, 2, C4:Base64Encode(H.png("a", 12)):sub(9)),
  H.png("a", 12)
)

T.section("A look naming a picture")
local has = { ["mine:p1"] = true }
local looks = Looks:new(memoryStore(), function(id)
  return has[id] == true
end)
local function storedFields(name, id)
  return H.lookFields(
    name,
    { icon = { id = id, stored = true, width = 600, height = 400, license = "", licenseUrl = "" } }
  )
end
local look, lookErr = looks:add(storedFields("Porch", "mine:p1"))
T.eq("is kept when the button has the picture", lookErr, nil)
T.eq("by id alone", { look.icon.id, look.icon.stored, look.icon.body }, { "mine:p1", true, nil })
_, lookErr = looks:add(storedFields("Gone", "mine:p9"))
T.eq("is refused when it doesn't", lookErr, "the look's picture is not one the button keeps")
_, lookErr = looks:add(H.lookFields("Sneaky", { icon = { id = "mine:p1", body = "<path/>", width = 24, height = 24 } }))
T.eq("a picture's id can't carry markup", lookErr, "the icon's name is not an icon pack name")
T.eq(
  "without the button's pictures, no look can use one",
  select(2, Looks:new(memoryStore()):add(storedFields("A", "mine:p1"))),
  "the look's picture is not one the button keeps"
)
has["mine:p2"] = true
T.eq(
  "another picture draws differently",
  Looks._drawnDiffers(look, looks:_check(storedFields("Porch", "mine:p2"), look.id)),
  true
)
T.eq("the same one doesn't", Looks._drawnDiffers(look, looks:_check(storedFields("Porch", "mine:p1"), look.id)), false)

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

-- The sections above share the controller's storage: the driver starts with an empty folder.
for name in pairs(ShimFiles("SANDBOX/pictures")) do
  C4:FileSetDir("SANDBOX", "pictures")
  C4:FileDelete(name)
end

local realTime = os.time
local clock = 2000000000
-- The driver's pictures read this clock, so a test can let the 10 minutes pass.
os.time = function(t)
  if t then
    return realTime(t)
  end
  return clock
end
H.start()

--- Send a picture as the Button tab does.
local function upload(data, fields)
  local enc = C4:Base64Encode(data)
  local chunk = 3072
  local count = math.ceil(#enc / chunk)
  for i = 1, count do
    H.tab(
      "_PUT_PICTURE",
      merge({ upload = "up", index = i, count = count, data = enc:sub((i - 1) * chunk + 1, i * chunk) }, fields or SIZE)
    )
  end
end

--- The pieces of a message to the tab, joined: its base64 without line breaks, and the longest line.
local function pieces(command)
  local parts, longest, count = {}, 0, nil
  for _, m in ipairs(H.ui) do
    if m.command == command then
      count = tonumber(m.params.count)
      parts[tonumber(m.params.index)] = m.params.data
      for line in (m.params.data .. "\n"):gmatch("([^\n]*)\n") do
        longest = math.max(longest, #line)
      end
    end
  end
  return C4:Base64Decode((table.concat(parts):gsub("\n", ""))), longest, count
end

T.section("The Button tab sends a picture")
H.mark()
local photo = JPEG .. string.rep("p", 9000)
upload(photo, { width = 240, height = 600, name = "porch.jpg" })
local stored = H.lastUi("PICTURE_STORED")
T.eq("the last chunk keeps it and answers with its id", stored and stored.picture, "mine:p1")
T.eq(
  "the state lists it",
  H.state().pictures[1],
  { id = "mine:p1", kind = "jpeg", width = 240, height = 600, name = "porch.jpg" }
)
H.mark()
upload("<html/>")
T.eq("a page isn't kept", H.lastUi("ERROR").message, "the picture did not arrive: picture is not a PNG, JPEG or SVG")

T.section("A look with the picture")
H.mark()
H.tab("_SAVE_LOOK", storedFields("Porch", "mine:p1"))
local porch = tonumber(H.lastUi("SAVED").look)
H.sendImage(porch, H.png("porch"))
T.eq(
  "is saved",
  H.state().looks[1].icon,
  { id = "mine:p1", stored = true, width = 600, height = 400, license = "", licenseUrl = "" }
)
H.mark()
H.tab("_SAVE_LOOK", storedFields("Other", "mine:p8"))
T.eq(
  "one naming a picture the button doesn't have is refused",
  H.lastUi("ERROR").message,
  "the look's picture is not one the button keeps"
)

T.section("The Button tab asks for a picture")
H.mark()
H.tab("_GET_PICTURE", { id = "mine:p1" })
local got, longest, count = pieces("PICTURE")
T.eq("it comes back whole", got, photo)
T.eq("in lines the broker can take", longest <= 76, true)
T.eq("in one piece when small", count, 1)
T.eq("with its kind", H.lastUi("PICTURE").kind, "jpeg")
upload(H.png("big", 100 * 1024), { width = 600, height = 600, name = "big.png" })
H.mark()
H.tab("_GET_PICTURE", { id = "mine:p2" })
got, longest, count = pieces("PICTURE")
T.eq("a larger one comes in pieces", count, 3)
T.eq("that join to the picture", got, H.png("big", 100 * 1024))
H.mark()
H.tab("_GET_PICTURE", { id = "mine:p99" })
T.eq("one it doesn't have says so", H.lastUi("PICTURE"), { id = "mine:p99", error = "the picture is gone" })

T.section("A picture from a web address")
local MB2 = Pictures.MAX_FETCH
local function fetch(url)
  H.mark()
  H.transfers = {}
  H.tab("_FETCH_PICTURE", { request = "r1", url = url })
  return H.lastUi("FETCHED")
end
local function lastTransfer()
  return H.transfers[#H.transfers]
end
H.urlAnswer = function(url)
  if url:find("missing") then
    return { code = 404, headers = { ["Content-Type"] = "text/html" }, body = "Not Found" }
  elseif url:find("page") then
    return { headers = { ["content-type"] = "text/html; charset=utf-8" }, body = "<!doctype html><p>hi</p>" }
  elseif url:find("stream") then
    return {
      headers = { ["Content-Type"] = "multipart/x-mixed-replace; boundary=frame" },
      body = string.rep("f", 4 * MB2),
      chunk = 65536,
    }
  elseif url:find("api") then
    return { headers = { ["Content-Type"] = "application/json" }, body = '{"a":1}' }
  elseif url:find("declared") then
    return {
      headers = { ["Content-Length"] = tostring(MB2 + 1), ["Content-Type"] = "image/jpeg" },
      body = JPEG .. string.rep("j", MB2),
      chunk = 65536,
    }
  elseif url:find("huge") then
    return { headers = { ["Content-Type"] = "image/jpeg" }, body = JPEG .. string.rep("j", 2 * MB2), chunk = 262144 }
  elseif url:find("slow") then
    return { timeout = true }
  elseif url:find("nowhere") then
    return { unreachable = true }
  elseif url:find("github.example/org.png") then
    return {
      responses = {
        { code = 302, headers = { Location = "https://avatars.example/u/1?v=4" }, body = "<a>moved</a>" },
        { headers = { ["Content-Type"] = "image/png" }, body = H.png("avatar", 900) },
      },
    }
  elseif url:find("handed%-back") then
    return { code = 301, headers = { location = "/pictures/real.jpg" } }
  elseif url:find("loop") then
    return { code = 302, headers = { Location = "/loop" } }
  end
  return {
    headers = { ["Content-Type"] = "image/jpeg", ["Content-Length"] = tostring(#photo) },
    body = photo,
    chunk = 1000,
  }
end
fetch("http://camera.local/snapshot.jpg")
T.eq("the controller fetches it", H.fetched[#H.fetched], "http://camera.local/snapshot.jpg")
T.eq(
  "within 20 seconds, reading a refusal's body too",
  { lastTransfer().options.timeout, lastTransfer().options.fail_on_error },
  { 20, false }
)
got, longest = pieces("FETCHED")
T.eq("and sends it whole, from its chunks", got, photo)
T.eq("in lines the broker can take", longest <= 76, true)
T.eq("under the tab's request", H.lastUi("FETCHED").request, "r1")
T.eq("an address that isn't http is refused", fetch("file:///etc/passwd").error, "Enter an http or https address.")
T.eq("and never fetched", #H.transfers, 0)
T.eq("a status is told", fetch("http://camera.local/missing.jpg").error, "The address answered with status 404.")
T.eq("as soon as the headers say it", { lastTransfer().aborted, lastTransfer().chunks }, { true, 0 })
T.eq(
  "a page isn't a picture",
  fetch("http://camera.local/page").error,
  "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."
)
T.eq("and is turned away by its headers", lastTransfer().chunks, 0)
T.eq(
  "nor is a camera's stream",
  fetch("http://camera.local/stream").error,
  "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."
)
T.eq("which is never read", { lastTransfer().aborted, lastTransfer().chunks }, { true, 0 })
T.eq(
  "nor is a JSON answer",
  fetch("http://camera.local/api").error,
  "The address didn't answer with a PNG, JPEG, GIF, WebP or SVG picture."
)
T.eq(
  "a length over 2 MB is refused",
  fetch("http://camera.local/declared.jpg").error,
  "The picture at that address is larger than 2 MB."
)
T.eq("before any of it arrives", { lastTransfer().aborted, lastTransfer().chunks }, { true, 0 })
T.eq(
  "a body that grows past 2 MB is refused",
  fetch("http://camera.local/huge.jpg").error,
  "The picture at that address is larger than 2 MB."
)
T.eq("and stopped once it does, not read to the end", { lastTransfer().aborted, lastTransfer().chunks }, { true, 9 })
T.eq(
  "an address it can't reach says so",
  fetch("http://nowhere.local/a.png").error,
  "The controller couldn't reach that address."
)
T.eq(
  "one that takes too long says so",
  fetch("http://camera.local/slow.jpg").error,
  "The address took too long to answer."
)
fetch("https://github.example/org.png")
T.eq("a redirect the controller follows brings the picture", (pieces("FETCHED")), H.png("avatar", 900))
T.eq("without counting the redirect's own body", H.lastUi("FETCHED").error, nil)
fetch("http://camera.local/handed-back")
T.eq("a redirect handed back is followed", H.fetched[#H.fetched], "http://camera.local/pictures/real.jpg")
T.eq("to the picture", (pieces("FETCHED")), photo)
T.eq("a redirect loop stops", fetch("http://camera.local/loop").error, "The address answered with status 302.")
T.eq("after 5 more tries", #H.transfers, 6)
H.tab("_GET_STATE")
T.eq("nothing fetched is kept until the tab sends it", #H.state().pictures, 2)
H.urlAnswer = nil

T.section("Pictures no look uses, on the controller")
H.mark()
H.tab("_SAVE_LOOK", merge(storedFields("Porch", "mine:p2"), { id = porch }))
T.eq("a look moves to another picture", H.state().looks[1].icon.id, "mine:p2")
T.eq("the one it left stays for its 10 minutes", #H.state().pictures, 2)
clock = clock + Pictures.GRACE_SECONDS
H.tab("_SAVE_LOOK", merge(storedFields("Porch", "mine:p2"), { id = porch }))
T.eq("then the next save deletes it", #H.state().pictures, 1)
T.eq("and keeps the one in use", H.state().pictures[1].id, "mine:p2")
upload(H.png("spare"), SIZE)
T.eq("a picture no look took yet", #H.state().pictures, 2)
clock = clock + Pictures.GRACE_SECONDS
H.restart()
T.eq("is deleted at the next start once its time is up", #H.state().pictures, 1)
T.eq("while a look's picture survives the restart", H.state().looks[1].icon.id, "mine:p2")
H.mark()
H.tab("_GET_PICTURE", { id = "mine:p2" })
T.eq("and its file with it", (pieces("PICTURE")), H.png("big", 100 * 1024))

T.section("Deleting a look")
upload(H.png("doomed"), SIZE)
local doomedId = H.lastUi("PICTURE_STORED").picture
H.tab("_SAVE_LOOK", storedFields("Doomed", doomedId))
local doomed = tonumber(H.lastUi("SAVED").look)
clock = clock + Pictures.GRACE_SECONDS
H.tab("_GET_STATE")
T.eq("its picture stays while the look uses it", H.state().pictures[#H.state().pictures].id, doomedId)
H.tab("_DELETE_LOOK", { id = doomed })
local ids = {}
for _, p in ipairs(H.state().pictures) do
  ids[p.id] = true
end
T.eq("deleting the look deletes its picture, once its time is up", ids[doomedId], nil)

T.section("Reset and removal")
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("Reset Driver deletes every picture", #H.state().pictures, 0)
T.eq("and its file", next(ShimFiles("SANDBOX/pictures")), nil)
upload(H.png("again"), SIZE)
T.eq("ids go on after a reset", H.lastUi("PICTURE_STORED").picture, "mine:p5")
OnDriverRemovedFromProject()
T.eq("removing the button deletes its pictures", next(ShimFiles("SANDBOX/pictures")), nil)

os.time = realTime
T.finish()
