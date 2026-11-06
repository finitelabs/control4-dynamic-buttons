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

T.section("Show when")
T.truthy("its rows start hidden", has('id="fld-when" hidden') and has('id="fld-default" hidden'))
T.truthy("and the preview's", has('id="fld-when-preview" hidden') and has('id="fld-when-browser" hidden'))
T.truthy("only By Value shows them", has("$(id).hidden = !byValue();"))
T.truthy("By Value is how the page knows", has("return gState.lookControl === 'By Value';"))
T.truthy("the list follows the same rule", has("if (!byValue()) return '';"))
T.truthy("a variable goes in as a token", has('data-token="PARAM{'))
T.truthy("the save sends the expression and the default", has("showWhen: l.showWhen || '', isDefault: !!l.isDefault"))
T.truthy("a default or match that's gone doesn't carry over", has("{ shown: null, defaultLook: null, matched: null }"))
T.truthy("an answer to earlier text is dropped", has("if (String(p.id) !== String(gEvalSeq)) return;"))
T.truthy("from the moment the text changes", has("clearTimeout(gEvalTimer);\n  gEvalSeq++;"))

T.section("Every command goes through sendCommand, which wraps it")
local _, posts = page:gsub("api%('POST'", "")
T.eq("one place sends commands", posts, 1)
T.truthy("the preview uses it", has("sendCommand('_EVAL_EXPRESSION'"))
T.truthy("and the browser", has("sendCommand('_GET_DEVICES')") and has("sendCommand('_GET_DEVICE_VARIABLES'"))

T.section("Which look is shown")
T.truthy("the page takes the small message", has("if (cmd === 'SHOWN') onShown(params);"))

T.finish()
