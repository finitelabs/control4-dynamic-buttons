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
local Looks = require("dynamic_button.looks")

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

T.section("Show when's editor")
T.truthy("a textarea over a colored copy of its text", has('<pre id="when-hl"') and has('id="f-when"'))
T.truthy(
  "the text itself is transparent",
  has("background: transparent; color: transparent; caret-color: var(--text);")
)
T.truthy("and the two stay the same height", has("box.style.height = Math.max(64, box.scrollHeight) + 'px';"))
T.truthy("what's colored is escaped", has("escMin(text).replace(HL_RE"))
T.truthy("the help opens beside the label", has('id="when-help-toggle"') and has('id="fld-when-help" hidden'))
T.truthy("the preview shows its references", has(">References<") and has("With current values"))
T.truthy("and a plain result", has("isTrue ? 'True' : 'False'"))
T.truthy("how many it watches", has("'Watching ' + n + ' reference'"))
T.truthy("and marks what's used in the browser", has("(isUsed ? ' used' : '')") and has('class="ins">Insert'))

T.section("What the sandbox has, the help and the highlighter have")
local sandboxFile =
  assert(io.open(H.DRIVER:gsub("drivers/dynamic_button/driver%.lua$", "src/lib/expression-sandbox.lua"), "r"))
local sandbox = sandboxFile:read("*a")
sandboxFile:close()
local help = page:match('id="when%-help">(.-)id="fld%-when%-browser"')
local names = page:match("var WHEN_NAMES = '([^']*)'")
local found = 0
for name in sandbox:match("return {\n    __p = bindings,(.-)\n  }"):gmatch("\n%s+([%w_]+) = ") do
  found = found + 1
  T.truthy(name .. " is in the help", help:find("<code>" .. name, 1, true))
  if name ~= "math" and name ~= "string" then
    T.truthy(name .. " is colored", ("|" .. names .. "|"):find("|" .. name .. "|", 1, true))
  end
end
T.truthy("the sandbox's names were read", found >= 18)
T.truthy("the words a condition uses are colored", has("'|and|or|not|true|false)"))
T.falsy(
  "names it no longer has aren't",
  ("|" .. names .. "|"):find("|value|", 1, true) or ("|" .. names .. "|"):find("|map|", 1, true)
)

T.section("Errors in plain sentences")
T.truthy("the preview says it", has("error.textContent = friendlyError(p.error, $('f-when').value, p.rendered);"))
T.truthy("with the engine's text in its title", has("error.title = p.error;"))
T.truthy("each look's row says it", has("esc(friendlyError(l.whenError, l.showWhen, l.showWhenText))"))
T.truthy("with the engine's text in its title too", has('<div class="sub bad" title="\' + esc(l.whenError) + \'">'))
T.truthy("what isn't recognized stays as it is", has("if (!m) return text;"))
T.truthy("the engine's name for a value never shows", has(".replace(/__p(\\[\\d+\\])?/g, 'a variable')"))

-- Each mistake as the real engine reports it, and what the page has ready for that text.
local Expressions = require("lib.expressions")
ShimSetDevices({
  [100] = {
    deviceName = "Battery",
    roomName = "Garage",
    variables = {
      ["1001"] = { name = "LEVEL", value = "62", type = "NUMBER" },
      ["1002"] = { name = "STATE", value = "Idle", type = "STRING" },
    },
  },
})
for _, case in ipairs({
  { "PARAM{100,1001} >=", "unexpected symbol near '<eof>'", "It stops before it's finished" },
  { "(PARAM{100,1001} > 5", "')' expected near '<eof>'", "It stops before it's finished: " },
  { "PARAM{100,1001} PARAM{100,1001}", "'<eof>' expected near '__p'", "It reads as finished before " },
  { '"abc', "unfinished string near", "a closing quote is missing" },
  { "PARAM{100,1001} = 5", "'<eof>' expected near '='", "Use == to compare, not =." },
  { "PARAM{100,1002} > 5", "attempt to compare number with string", "This can't compare " },
  { 'PARAM{100,1001} > "x"', "attempt to compare string with number", "This can't compare " },
  { "PARAM{100,1002} + 1 > 5", "attempt to perform arithmetic on a string value", "This does math on text" },
  { "nope(1) > 5", "attempt to call global 'nope' (a nil value)", "There's no function named " },
  { "nope.level > 5", "attempt to index global 'nope' (a nil value)", "There's nothing named " },
  {
    "PARAM{100,1001}",
    "result is not a boolean (got number)",
    '"Show when" has to come out true or false: add a comparison.',
  },
  { "PARAM{100,NOPE} > 5", "variable NOPE not found on device 100", " has no variable " },
  { "PARAM{200,1} > 5", "device 200 not found", "There's no device " },
}) do
  local reported = Expressions.evaluate("condition", case[1]).error or ""
  T.truthy(case[2], reported:find(case[2], 1, true))
  T.truthy("has its sentence", has(case[3]))
end
Expressions:new({
  getExpressions = function()
    return {}
  end,
  recompute = function() end,
}):handleDeviceRemoved(100)
local removed = Expressions.evaluate("condition", "PARAM{100,1001} > 5").error or ""
T.truthy("a device removed says so", removed:find("was removed from the project", 1, true))
T.truthy("and the page reads it", has("was removed from the project$/"))

T.section("Every command goes through sendCommand, which wraps it")
local _, posts = page:gsub("api%('POST'", "")
T.eq("one place sends commands", posts, 1)
T.truthy("the preview uses it", has("sendCommand('_EVAL_EXPRESSION'"))
T.truthy("and the browser", has("sendCommand('_GET_DEVICES')") and has("sendCommand('_GET_DEVICE_VARIABLES'"))

T.section("Every select draws one arrow")
local shared = page:find('select, input[type="text"], input[type="search"] {', 1, true)
local arrow = page:find("\n  select { appearance: none; -webkit-appearance: none;", 1, true)
T.truthy("the browser's own is off, after the shared rule's background", shared and arrow and arrow > shared)
local arrowRule = arrow and page:sub(arrow, page:find("\n", arrow + 1, true)) or ""
T.truthy("it's a chevron in the page's muted color", arrowRule:find("stroke='%236b7280'", 1, true))
T.eq("the muted color is still that", page:match("%-%-text%-muted: (#%x+);"), "#6b7280")
T.truthy(
  "the same distance in from the edge everywhere",
  arrowRule:find("background-position: right 10px center;", 1, true)
)
T.truthy("that doesn't repeat", arrowRule:find("background-repeat: no-repeat;", 1, true))
T.truthy("and a long choice stops short of it", arrowRule:find("padding-right: 28px;", 1, true))
T.falsy(
  "no later rule sets a select's padding",
  page:find("\n[^\n]*%f[%w]select%f[%W][^\n{]*{[^\n}]*padding:", arrow + #arrowRule, false)
)
T.falsy(
  "or its background",
  page:find("\n[^\n]*%f[%w]select%f[%W][^\n{]*{[^\n}]*background", arrow + #arrowRule, false)
)

T.section("Which look is shown")
T.truthy("the page takes the small message", has("if (cmd === 'SHOWN') onShown(params);"))

T.section("The preview's result")
T.truthy("it reads the socket's boolean as well as text", has("String(p.result) === 'true'"))
T.truthy("and a rendered expression the socket turned falsy", has("String(p.rendered == null ? '' : p.rendered)"))
T.truthy("the box measures again when its width changes", has("}).observe($('f-when'));"))
T.falsy("nothing compares the result to text alone", has("p.result === 'true'"))
T.truthy(
  "the button that opens the list isn't named like a row's Insert",
  has("Browse Variables") and not has("Insert Variable")
)

T.section("The editor's sections")
T.truthy("the icon's changes have their own section", has("<summary>Icon</summary>"))
T.truthy("and the badge has its own", has("<summary>Badge</summary>"))
T.truthy("reset leaves the badge, which isn't in its section", has("l.custom = badge ? { badge: badge } : {};"))
T.truthy(
  "a badge's box holds what the driver takes",
  has(string.format('id="c-badge" rows="1" maxlength="%d"', Looks.MAX_LIVE_BADGE))
)
for _, seconds in ipairs(Looks.BADGE_EVERY) do
  T.truthy("the Update list offers " .. seconds .. " seconds", has(string.format('<option value="%d">', seconds)))
end
T.truthy("and it starts where the driver does", has(string.format("var BADGE_EVERY = %d;", Looks.DEFAULT_BADGE_EVERY)))
T.truthy(
  "a live look's picture is stored without its badge",
  has("lookDataUrl(Object.assign({}, drawn, { badgeNow: null }), 300)")
)
T.truthy(
  "the slider's range is the driver's",
  has(string.format('id="c-badge-size" min="%d" max="%d"', Looks.MIN_BADGE_SIZE, Looks.MAX_BADGE_SIZE))
)
for note in page:gmatch('<span class="fnote"') do
  T.truthy("a note isn't inside its control's row, where it would push the label down: " .. note, false)
end

T.section("Icon licenses")
T.truthy("the card is collapsed until it's opened", has('<details class="card" id="lic-card">'))
T.truthy("and still names every collection", has("<summary>Icon licenses</summary>") and has('id="lic-list"'))

T.section("A sentence names the field in quotes")
T.truthy("under Look Control", has([['The first look whose "Show when" is true shows.']]))
T.truthy("beside Default look", has([[Show this look when no "Show when" is true]]))
T.truthy("in the Default tag's tip", has("Shows when no &quot;Show when&quot; is true."))

T.finish()
