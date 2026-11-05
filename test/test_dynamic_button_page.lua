--- What the Button tab's page asks of the controller, read from its source: it has no test runner
--- of its own, so these hold the facts a change could quietly undo.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_page.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local Images = require("dynamic_button.images")

local file = assert(io.open(H.DRIVER:gsub("driver%.lua$", "www/html/index.html"), "r"))
local page = file:read("*a")
file:close()

--- @param text string
--- @return boolean present The page's source has that text.
local function has(text)
  return page:find(text, 1, true) ~= nil
end

T.section("Commands")
T.truthy(
  "each command's base64 is wrapped, so the broker never meets a long unbroken run",
  has("DATA: btoa(unescape(encodeURIComponent(JSON.stringify(params || {})))).replace(/.{76}/g, '$&\\n')")
)

T.section("Chunks")
T.eq("the page's chunk size is the driver's", tonumber(page:match("maxChunk: (%d+)")), Images.MAX_CHUNK)
T.eq("and so is its fallback", tonumber(page:match("gState%.maxChunk || (%d+)")), Images.MAX_CHUNK)

T.section("How often it asks for the state")
T.falsy("no poll", has("setInterval(refresh"))
local boot = page:match("initSocket%(%);(.-)%}%)%(%);")
T.truthy("the boot code is found", boot)
T.falsy("and boot leaves asking to the socket's connect", boot:find("refresh", 1, true))

local _, refreshes = page:gsub("refresh%(%)", "")
T.eq("and nothing else asks that way, so no refresh follows IMAGE_STORED", refreshes, 2)

T.section("Answers come over the socket")
T.falsy("nothing reads an answer from a REST reply", has("applyReply") or has("replyOf"))
T.falsy("nothing reads the state right after asking for it", has("await refresh()"))
T.truthy("what needs the state now waits for its push", has("call('_GET_STATE', {}, 'STATE'"))

T.section("Which look is shown")
T.truthy("the page takes the small message", has("if (cmd === 'SHOWN') onShown(params);"))

T.finish()
