--- A look's picture on its way from the Button tab: base64 chunks taken in order, refused out of
--- order, short, oversized or not a PNG, and dropped when they stop arriving; kept in a folder of
--- the button's storage; served from the driver's web folder; and the address Navigator loads it from.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_images.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Images = require("dynamic_button.images")

--- @return string[] chunks The picture as the tab sends it, cut at `size` base64 characters.
local function chunks(png, size)
  local b64 = C4:Base64Encode(png)
  local out = {}
  for i = 1, #b64, size do
    table.insert(out, b64:sub(i, i + size - 1))
  end
  return out
end

T.section("A picture in chunks")
local images = Images:new()
local png = H.png("three chunks", 292)
local parts = chunks(png, 136)
T.eq("the picture makes three chunks", #parts, 3)
T.eq("the first chunk is taken and waits for more", images:accept(1, "a", 1, 3, parts[1]), nil)
T.eq("so is the second", images:accept(1, "a", 2, 3, parts[2]), nil)
T.eq("the last returns the whole picture", images:accept(1, "a", 3, 3, parts[3]), png)

T.section("A picture in one chunk")
local single = H.png("one", 40)
T.eq("one chunk is the whole picture", images:accept(2, "b", 1, 1, chunks(single, 49152)[1]), single)

T.section("Chunks out of order")
local _, err = images:accept(3, "c", 2, 3, parts[2])
T.eq("a second chunk with no first is refused", err, "chunk out of order")
images:accept(3, "c", 1, 3, parts[1])
_, err = images:accept(3, "c", 3, 3, parts[3])
T.eq("a skipped chunk is refused", err, "chunk out of order")
_, err = images:accept(3, "c", 2, 3, parts[2])
T.eq("and the upload is dropped, so the rest is refused too", err, "chunk out of order")
images:accept(3, "c", 1, 3, parts[1])
_, err = images:accept(3, "other", 2, 3, parts[2])
T.eq("a chunk from another upload is refused", err, "chunk out of order")
images:accept(3, "c", 1, 3, parts[1])
_, err = images:accept(3, "c", 2, 4, parts[2])
T.eq("a chunk that changes the count is refused", err, "chunk out of order")

T.section("A new upload replaces an unfinished one")
images:accept(4, "first", 1, 3, parts[1])
images:accept(4, "first", 2, 3, parts[2])
T.eq("chunk 1 of a new upload starts over", images:accept(4, "second", 1, 1, chunks(single, 49152)[1]), single)
_, err = images:accept(4, "first", 3, 3, parts[3])
T.eq("and the old upload's last chunk is refused", err, "chunk out of order")

T.section("An upload that stops arriving")
local clock = 1000
local timed = Images:new(function()
  return clock
end)
timed:accept(11, "s", 1, 3, parts[1])
clock = clock + Images.STALE_SECONDS - 1
timed:accept(11, "s", 2, 3, parts[2])
T.eq("waits while its chunks keep coming", timed._uploads[11] ~= nil, true)
clock = clock + Images.STALE_SECONDS
timed:accept(12, "t", 1, 1, chunks(single, 49152)[1])
T.eq("is dropped a minute after its last chunk", timed._uploads[11], nil)
_, err = timed:accept(11, "s", 3, 3, parts[3])
T.eq("so its last chunk is refused", err, "chunk out of order")

T.section("A missing last chunk")
local waiting = Images:new()
waiting:accept(5, "d", 1, 3, parts[1])
waiting:accept(5, "d", 2, 3, parts[2])
T.eq("without its last chunk nothing is returned", waiting._uploads[5] ~= nil, true)
waiting:cancel(5)
T.eq("cancel forgets it", waiting._uploads[5], nil)

T.section("Uploads are kept apart by look")
local apart = Images:new()
apart:accept(6, "e", 1, 3, parts[1])
T.eq("another look's picture arrives whole meanwhile", apart:accept(7, "f", 1, 1, chunks(single, 49152)[1]), single)
apart:accept(6, "e", 2, 3, parts[2])
T.eq("and the first look's goes on", apart:accept(6, "e", 3, 3, parts[3]), png)

T.section("Chunks that are refused")
_, err = images:accept(8, "g", 1, 1, "")
T.eq("an empty chunk", err, "chunk is not whole base64 of the allowed size")
_, err = images:accept(8, "g", 1, 1, "abc")
T.eq("a chunk that is not whole base64", err, "chunk is not whole base64 of the allowed size")
_, err = images:accept(8, "g", 1, 1, string.rep("A", Images.MAX_CHUNK + 4))
T.eq("a chunk over the limit", err, "chunk is not whole base64 of the allowed size")
_, err = images:accept(8, "g", 0, 1, parts[1])
T.eq("a chunk numbered 0", err, "chunk out of range")
_, err = images:accept(8, "g", 2, 1, parts[1])
T.eq("a chunk past the count", err, "chunk out of range")
_, err = images:accept(8, "g", 1, 500, parts[1])
T.eq("a count more than the largest picture needs", err, "chunk out of range")
_, err = images:accept(nil, "g", 1, 1, parts[1])
T.eq("a chunk with no look", err, "chunk without its look")
_, err = images:accept(8, "", 1, 1, parts[1])
T.eq("a chunk with no upload", err, "chunk without its upload, place or count")
_, err = images:accept(8, "g", 1, 1, C4:Base64Encode("not a png at all"))
T.eq("a picture that is not a PNG", err, "picture is not a PNG")

T.section("A picture over 512 KB")
local big = H.PNG_SIGNATURE .. string.rep("z", Images.MAX_BYTES)
local bigParts = chunks(big, Images.MAX_CHUNK)
local bigErr
for i, part in ipairs(bigParts) do
  local _, e = images:accept(9, "h", i, #bigParts, part)
  if e then
    bigErr = e
    break
  end
end
T.eq("is refused once its size passes the limit", bigErr, "picture is larger than 512 KB")
local exact = H.PNG_SIGNATURE .. string.rep("z", Images.MAX_BYTES - #H.PNG_SIGNATURE)
local exactParts, whole = chunks(exact, Images.MAX_CHUNK), nil
for i, part in ipairs(exactParts) do
  whole = images:accept(10, "i", i, #exactParts, part)
end
T.eq("a picture of exactly 512 KB is taken", whole and #whole, Images.MAX_BYTES)
T.eq("which is 240 chunks at the largest size", #exactParts, 240)

T.section("A chunk's command")
--- @return string body A command's body as the Button tab builds it: its fields as JSON, base64 into DATA.
local function requestBody(command, fields)
  return JSON:encode({ command = command, tParams = { DATA = C4:Base64Encode(JSON:encode(fields)) }, async = false })
end
local fullChunk = string.rep("A", Images.MAX_CHUNK)
local token = "mhn6zv2kq4x9aa"
T.truthy(
  "a picture's largest chunk goes in 4 KB or less",
  #requestBody("_PUT_IMAGE", { look = 8, upload = token, index = 240, count = 240, data = fullChunk }) <= 4096
)
T.truthy(
  "so does an icon's",
  #requestBody("_PUT_ICON", { upload = token, index = 8, count = 8, data = fullChunk }) <= 4096
)
T.eq("each chunk is whole base64", Images.MAX_CHUNK % 4, 0)

T.section("An online icon's markup in chunks")
local markup = '<path fill="currentColor" d="M0 0h24v24H0z"/>' .. string.rep('<circle r="1"/>', 20) .. "caf\195\169"
local markupParts = chunks(markup, 136)
local icons = Images:new()
T.truthy("the markup makes several chunks", #markupParts > 1)
for i, part in ipairs(markupParts) do
  T.eq("chunk " .. i .. " is taken", icons:acceptIcon("m", i, #markupParts, part, 16384), nil)
end
T.eq("it comes back whole, with no PNG check", icons:takeIcon("m"), markup)
T.eq("once", icons:takeIcon("m"), nil)
T.eq("an upload that never came gives nothing", icons:takeIcon("nothing"), nil)
icons:acceptIcon("kept", 1, 1, chunks(markup, 8192)[1], 16384)
T.eq("another upload's name gives nothing", icons:takeIcon("other"), nil)
T.eq("and leaves it waiting", icons:takeIcon("kept"), markup)
icons:acceptIcon("old", 1, 1, chunks("old", 8192)[1], 16384)
icons:acceptIcon("new", 1, 1, chunks(markup, 8192)[1], 16384)
T.eq("a new upload replaces one waiting", icons:takeIcon("old"), nil)
T.eq("and is the one kept", icons:takeIcon("new"), markup)
T.eq(
  "a chunk out of order is refused",
  icons:acceptIcon("m", 2, #markupParts, markupParts[2], 16384),
  "chunk out of order"
)
T.eq(
  "a chunk that isn't whole base64 is refused",
  icons:acceptIcon("m", 1, 1, "abc", 16384),
  "chunk is not whole base64 of the allowed size"
)
T.eq("a count past the cap is refused", icons:acceptIcon("m", 1, 500, markupParts[1], 16384), "chunk out of range")
local tooBig = chunks(string.rep("x", 90), 8192)[1]
T.eq("markup past the cap is refused", icons:acceptIcon("big", 1, 1, tooBig, 64), "the markup is too large")
T.eq("and keeps nothing", icons:takeIcon("big"), nil)

T.section("An icon's upload and a picture's are kept apart")
local both = Images:new()
both:accept(1, "p", 1, 3, parts[1])
both:acceptIcon("i", 1, 1, chunks(markup, 8192)[1], 16384)
T.eq("the icon's markup is whole", both:takeIcon("i"), markup)
both:accept(1, "p", 2, 3, parts[2])
T.eq("and the picture goes on", both:accept(1, "p", 3, 3, parts[3]), png)

T.section("Icon markup that waits too long")
local iconClock = 2000
local late = Images:new(function()
  return iconClock
end)
late:acceptIcon("s", 1, 1, chunks(markup, 8192)[1], 16384)
iconClock = iconClock + Images.STALE_SECONDS - 1
T.eq("waits a little under a minute", late:takeIcon("s"), markup)
late:acceptIcon("t", 1, 1, chunks(markup, 8192)[1], 16384)
iconClock = iconClock + Images.STALE_SECONDS
T.eq("and is gone after", late:takeIcon("t"), nil)

T.section("Keeping and serving a picture")
T.raises("the harness refuses a folder call with an explicit nil folder", function()
  C4:FileSetDir("SANDBOX", nil)
end)
local store = Images:new()
T.truthy("a picture is kept", store:save(3, png))
T.truthy("in a folder made in the button's storage", H.dirs["SANDBOX/looks"])
T.eq("under the look's number", H.stored()["look-3.png"], png)
T.eq("and nothing at the storage's top", ShimFiles("SANDBOX")["look-3.png"], nil)
T.eq("and read back", store:load(3), png)
T.truthy("a new picture replaces it", store:save(3, single))
T.eq("whole, not appended", store:load(3), single)
T.truthy("a picture is served", store:serve(H.DEVICE_ID, 3, png))
T.eq("in the button's folder of the driver's web folder", H.served()["3.png"], png)
T.truthy("whose folders are made first", H.dirs["C4Z/www/buttons"] and H.dirs["C4Z/www/buttons/" .. H.DEVICE_ID])
store:unserve(H.DEVICE_ID, 3)
T.eq("unserving removes the served copy", H.served()["3.png"], nil)
T.eq("and keeps the stored one", store:load(3), single)
store:remove(3)
T.eq("removing deletes the stored one", store:load(3), nil)

T.section("The address Navigator loads")
T.eq(
  "names the driver's folder, the button, the look and the version",
  Images.address("dynamic_button", 4242, 3, 7),
  "controller://driver/dynamic_button/buttons/4242/3.png?v=7"
)

T.finish()
