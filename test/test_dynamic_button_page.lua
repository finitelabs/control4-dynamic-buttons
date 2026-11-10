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
file = assert(io.open(H.DRIVER:gsub("drivers/dynamic_button/driver%.lua$", "src/lib/ui/page.js"), "r"))
local kit = file:read("*a")
file:close()
file = assert(io.open(H.DRIVER:gsub("drivers/dynamic_button/driver%.lua$", "src/lib/ui/style.css"), "r"))
local style = file:read("*a")
file:close()

--- @param text string
--- @return boolean present The page's source has that text.
local function has(text)
  return page:find(text, 1, true) ~= nil
end

T.section("Commands")
T.truthy("the page sends through lib/ui", has("<!-- #embed ../../../../src/lib/ui/page.js -->"))
T.truthy(
  "whose base64 is wrapped, so the broker never meets a long unbroken run",
  kit:find('.replace(/.{76}/g, "$&\\n")', 1, true) ~= nil
)
T.truthy("and so is a command to another Dynamic Button, on the kit's link", has("var link = Kit.follow(id)"))
for _, component in ipairs({ "variables.js", "expressions.js" }) do
  T.truthy("it embeds the kit's " .. component, has("<!-- #embed ../../../../src/lib/ui/" .. component .. " -->"))
end

T.section("Every command the driver sends reaches the page")
local dfile = assert(io.open(H.DRIVER, "r"))
local driverSource = dfile:read("*a")
dfile:close()
local handled = {}
for command in (page:match("var DRIVER_HANDLERS = {(.-)\n};") or ""):gmatch("\n%s*([A-Z_]+):") do
  handled[command] = true
end
local missing = {}
local seen = {}
for _, sender in ipairs({ "page%.send", "reply", "sendPieces" }) do
  for command in driverSource:gmatch(sender .. '%("([A-Z_]+)"') do
    if not seen[command] then
      seen[command] = true
      if not handled[command] then
        missing[#missing + 1] = command
      end
    end
  end
end
T.truthy("the page lists them", next(handled) ~= nil)
T.truthy("the driver's sends were read", seen.STATE and seen.ERROR and seen.PICTURE)
T.eq("and none is missing, so none waits out a timeout", missing, {})
T.falsy("nothing sends past the kit's one json parameter", driverSource:find("SendDataToUI", 1, true))
-- The kit's driver modules answer its components, which the page embeds.
T.truthy("the variable browser's driver side is served", driverSource:find("uiDevices.serve(", 1, true))
T.truthy("and the browser is on the page", has("Kit.variableBrowser($('var-browser')"))
T.truthy("the preview's driver side is served", driverSource:find("expressionTab.serve(", 1, true))
T.truthy(
  "and both editors are on the page",
  has("Kit.expressionEditor($('f-when')") and has("Kit.expressionEditor($('c-badge')")
)
T.truthy("the properties card's driver side is served", driverSource:find("tabProperties:serve()", 1, true))
T.truthy(
  "and the card is on the page, without what the Shown now card has",
  has("Kit.initPropertiesCard($('props'), { exclude: PROPS_ELSEWHERE });")
)

T.section("Chunks")
T.eq("the page's chunk size is the driver's", tonumber(page:match("maxChunk: (%d+)")), Images.MAX_CHUNK)
T.eq("and so is its fallback", tonumber(page:match("gState%.maxChunk || (%d+)")), Images.MAX_CHUNK)

T.section("How often it asks for the state")
T.falsy("no poll", has("setInterval(refresh"))
local boot = page:match("connectDriver%((.-)%}%);")
T.truthy("the boot code is found", boot)
T.truthy("and boot leaves asking to each connect", boot and boot:find("onConnect: refresh", 1, true))

local _, refreshes = page:gsub("%f[%w.]refresh%(%)", "")
T.eq("and nothing else asks that way, so no refresh follows IMAGE_STORED", refreshes, 1)

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
T.truthy(
  "a variable goes in as a token, into the box the list was opened from",
  has("Kit.variableBrowser($('var-browser'), { target: function() { return $(gVarBox); } });")
)
T.truthy("the save sends the expression and the default", has("showWhen: l.showWhen || '', isDefault: !!l.isDefault"))
T.truthy("a default or match that's gone doesn't carry over", has("{ shown: null, defaultLook: null, matched: null }"))
T.truthy(
  "its preview runs only under By Value",
  has("previewWhen: function(text) { return byValue() && text.trim() !== ''; }")
)
T.truthy(
  "and asks again when By Value comes or goes",
  has("if (wasHidden === byValue() && gEditor.look) whenEditor.preview(true);")
)

T.section("Show when's editor")
T.truthy("is the kit's", has("var whenEditor = Kit.expressionEditor($('f-when'), {"))
T.truthy("whose errors name the field", has("label: 'Show when',"))
T.truthy(
  "with its preview, which keeps the watch line under it",
  has("preview: $('when-preview'),") and has('<div class="kit-prev-foot" id="when-watch" hidden>')
)
T.truthy("how many it watches", has("watch: $('when-watch'),"))
T.truthy(
  "and the help, which opens beside the label",
  has("help: { toggle: $('when-help-toggle'), panel: $('when-help'), wrap: $('fld-when-help') },")
    and has('id="fld-when-help" hidden')
)
T.truthy(
  "each look's row says an error as the preview does",
  has("Kit.esc(Kit.expressionError(l.whenError, l.showWhen, l.showWhenText, 'Show when'))")
)
T.truthy("with the engine's text in its title", has('<div class="sub bad" title="\' + Kit.esc(l.whenError) + \'">'))

T.section("Every command goes through the kit")
local _, posts = page:gsub("api%('POST'", "")
T.eq("the page posts no command itself", posts, 0)
T.falsy(
  "nor keeps a link or banner of its own",
  has('id="conn-bar"') or has('id="conn-warn"') or has("function setConn(")
)
T.truthy(
  "outside Composer, the kit's demo answers stand in",
  has("Kit.devices.demo(DEMO_DEVICES, DEMO_VARIABLES);")
    and has("Kit.deliver('EVAL_RESULT', Object.assign({ id: params.id")
)
T.truthy("and the demo state comes as the driver's would", has("if (command === '_GET_STATE') Kit.deliver('STATE'"))
local script = page:sub(page:find("/* #end-icon-packs */", 1, true) or 1)
for _, name in ipairs({ "esc", "sendCommand", "waitFor", "friendlyError", "gApiHost", "gDriverId" }) do
  T.falsy("nor uses its own " .. name .. ", which the kit has", script:find("%f[%w_.$]" .. name .. "%f[^%w_$]"))
end

T.section("Which look is shown")
T.truthy("the page takes the small message", has("SHOWN: onShown,"))

T.section("The preview's result")
T.falsy("nothing reads it as the socket's boolean any more", has("String(p.result) === 'true'"))
T.truthy(
  "the button that opens the list isn't named like a row's Insert",
  has("Browse Variables") and not has("Insert Variable")
)

T.section("What the driver would refuse holds Save")
T.truthy(
  "a Show when that doesn't read, or reads this button's own variables, holds Save",
  has("if (whenEditor.hold) return '\"Show when\": ' + whenEditor.hold;")
)
T.truthy(
  "and so does a live badge on this button's own variables",
  has("if (isLiveText(badge) && badgeEditor.hold) return 'Badge: ' + badgeEditor.hold;")
)
T.truthy(
  "a refusal reads as the preview does",
  has("return m ? '\"Show when\": ' + Kit.expressionError(m[1], whenEditor.value(), '', 'Show when') : msg;")
)
T.truthy(
  "a look opens on a fresh preview, not the last look's",
  has("gEditor.whenResult = null;\n  gEditor.badgeResult = null;\n  whenEditor.setValue(gEditor.look.showWhen || '');")
)
T.truthy(
  "a badge too long to be one is marked as it's typed",
  has("$('c-badge').classList.toggle('input-error', long);")
)
T.truthy(
  "a badge's text is one line that previews while it reads a variable",
  has("singleLine: true,\n  previewWhen: isLiveText,")
)

T.section("The editor's sections")
T.truthy("the picture's changes have their own section", has("<summary>Customize</summary>"))
T.truthy("and the badge has its own", has("<summary>Badge</summary>"))
T.truthy("reset leaves the badge, which isn't in its section", has("l.custom = badge ? { badge: badge } : {};"))
T.truthy(
  "a badge's box holds what the driver takes",
  has(string.format('id="c-badge" rows="1" maxlength="%d"', Looks.MAX_LIVE_BADGE))
)
for _, seconds in ipairs(Looks.BADGE_EVERY_SECONDS) do
  T.truthy("the Update list offers " .. seconds .. " seconds", has(string.format('<option value="%d">', seconds)))
end
T.truthy(
  "and it starts where the driver does",
  has(string.format("var BADGE_EVERY = %d;", Looks.DEFAULT_BADGE_EVERY_SECONDS))
)
T.truthy(
  "a push under another Look Control leaves the badge's list open",
  has("if (gVarBox === 'f-when') $('fld-when-browser').hidden = true;")
)
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

T.section("Pictures drawn into a canvas")
T.truthy("go through a bitmap, which Edge on Windows draws whole", has("createImageBitmap(img).then(resolve"))
local loaded = 0
for _ in page:gmatch("await loadImage%(svgUrl%(") do
  loaded = loaded + 1
end
T.eq("both of drawLook's pictures load that way", loaded, 2)

T.section("The page's own color picker")
local colorInputs = 0
for _ in page:gmatch('<input type="color"') do
  colorInputs = colorInputs + 1
end
T.eq("the look editor has its nine color boxes", colorInputs, 9)
T.truthy(
  "each gets the page's picker",
  has("document.querySelectorAll('input[type=\"color\"]').forEach(attachColorPicker)")
)
T.truthy("and Edge's own picker never opens: the input hides", has("input.hidden = true;"))
T.truthy("and its label opens the page's picker", has("label.htmlFor = btn.id;"))
T.truthy(
  "a value the page sets in code shows on the swatch",
  has("set: function(v) { INPUT_VALUE.set.call(this, v); paintSwatch(this); }")
)
T.truthy("Escape puts the color back", has("if (pop.dropping) pop.stopDropping();\n    else closeColorPicker(false);"))
T.truthy("as the look had it, not as the box's value", has("var was = JSON.parse(pop.before), l = gEditor.look;"))
T.truthy("and only onto that look, if another is open by then", has("pop.before && gEditor.look === pop.look"))
T.truthy("recent colors survive a browser that refuses storage", has("try { localStorage.setItem(RECENT_COLORS_KEY"))

T.section("The dropper")
T.falsy("Edge's own dropper is never used: it reads the wrong place in Composer's window", has("EyeDropper"))
T.truthy(
  "it reads the preview the page drew",
  has("function previewPicture() { return $('edit-tile').querySelector('img'); }")
)
T.truthy(
  "a pick is the color as the picture shows over its tile",
  has("return hexOf(tileBackdrop().map(function(v, i) { return d[i] * a + v * (1 - a); }));")
)
T.truthy(
  "a click on the picture picks, and the picker stays open",
  has("e.preventDefault();\n        pickColor(input, hex);\n        show(hex);\n        return;")
)
T.truthy("Escape while picking only stops picking", has("if (pop.dropping) pop.stopDropping();"))
T.truthy("only a left click picks", has("p = e.button === 0 && img && e.target === img && previewPixel(img, e)"))
T.truthy("a near miss on the tile only stops the dropper", has("if ($('edit-tile').contains(e.target)) return;"))
T.truthy(
  "it shows for a look with a picture, even while the preview draws",
  has("drop.hidden = !(gEditor.look && gEditor.look.icon && !gEditor.look.icon.missing);")
)
T.truthy("closing the editor closes the picker", has("function closeEditor() {\n  closeColorPicker(true);"))
T.truthy("and the picker closing stops it too", has("pop.stopDropping();\n  pop.remove();"))

T.section("Duplicate")
T.truthy("each look's row has Duplicate", has('data-act="copy"'))
T.truthy("which is off at the most looks a button has", has("(list.length >= gState.max ? ' disabled"))
T.truthy(
  "and opens the editor on a copy with no id, which saves as a new look",
  has("{ id: null, name: copyName(look.name) }")
)

T.truthy(
  "a copy isn't the default, even on a button with none",
  has("gEditor.look.isDefault = !!look && look.id != null && gState.defaultLook === look.id;")
)

T.section("My images")
local Pictures = require("dynamic_button.pictures")
T.truthy("the picture list offers My images", has([['<option value="' + SOURCE_MINE + '">My images</option>']]))
local mine = page:match("// My images: the button's own pictures.-// The look editor\n")
T.truthy("the My images code is found", mine)
for _, insert in ipairs({ "innerHTML", "outerHTML", "insertAdjacentHTML", "document.write" }) do
  T.falsy("puts nothing a person added into the page: no " .. insert, mine:find(insert, 1, true))
end
T.truthy(
  "an SVG loses what runs or embeds",
  has("var SVG_DROP = ['script', 'foreignObject', 'iframe', 'object', 'embed', 'audio', 'video', 'canvas', 'animate',")
)
T.truthy("and every event handler", has("if (name.indexOf('on') === 0) { el.removeAttributeNode(a); return; }"))
T.truthy(
  "and every link but its own parts and pictures in it",
  has(
    [[if (name === 'href') { if (!(/^\s*#/.test(a.value) || SAFE_IMAGE.test(a.value))) el.removeAttributeNode(a); return; }]]
  )
)
T.truthy(
  "CSS that could load from elsewhere however it's written is unsafe: an escape, an import, image-set or an open url(",
  has(
    [[return /\\|@import|image-set\s*\(/i.test(v) || (v.match(/url\s*\(/gi) || []).length !== (v.match(/url\s*\([^)]*\)/gi) || []).length;]]
  )
)
T.truthy("any attribute holding it goes", has("if (cssUnsafe(a.value)) { el.removeAttributeNode(a); return; }"))
T.truthy("as does a stylesheet", has("if (cssUnsafe(c.textContent)) { c.remove(); return; }"))
T.truthy(
  "and a url() in any attribute is checked, a fill or a filter as much as a style",
  has([[if (/url\s*\(/i.test(a.value)) a.value = safeCss(a.value);]])
)
T.truthy(
  "so it reaches only the drawing's own parts",
  has([[return String(css || '').replace(/url\s*\((?!\s*['"]?\s*#)[^)]*\)/gi, 'none');]])
)
T.truthy(
  "the 64 KB limit is on the SVG as kept",
  has("if (new Blob([markup]).size > MINE_SVG_MAX) throw new Error('An SVG can be at most 64 KB.');")
)
T.truthy(
  "one color takes the icon color",
  has("var one = paints.keys.length === 1 && paints.keys[0] !== 'paint server' ? paints.keys[0] : null;")
)
T.truthy("and the editor says so", has("'One color, so Icon color applies.'"))
T.truthy(
  "Icon color shows for a picture only when it's one color",
  has("$('fld-icon-color').hidden = whole || !!every || (isPicture(l.icon) && !pictureOneColor(l.icon));")
)
T.truthy(
  "an SVG is at most what the driver keeps",
  tonumber(page:match("MINE_SVG_MAX = (%d+) %* 1024")) * 1024 == Pictures.MAX_SVG_BYTES
)
T.truthy("a raster is kept at most 600 px on its long side", has("var MINE_SIDE = 600"))
T.truthy("as a JPEG when opaque and a PNG otherwise", has("c.toDataURL(opaque ? 'image/jpeg' : 'image/png', 0.9)"))
T.truthy(
  "a fetched picture is named by its address's last part",
  has("p = await pictureFromBlob(new Blob([bytes]), nameFromUrl(url));")
)
T.truthy(
  "never by its login, query or fragment",
  has("var u = new URL(url), last = u.pathname.split('/').filter(Boolean).pop() || '';")
)
T.truthy(
  "an answer for an editor that closed or moved on is dropped",
  has("if (!gEditor.look || gEditor.look !== gFetch.look)")
)
T.truthy(
  "a kept picture the driver no longer lists is sent again",
  has(
    "var keptHere = l.icon && l.icon.stored && (gState.pictures || []).some(function(p) { return p.id === l.icon.id; });"
  ) and has("if (l.icon && isPicture(l.icon) && !keptHere) {")
)
T.truthy(
  "a message in pieces drops the spaces that break it",
  has([[p.parts[index - 1] = String(params.data || '').replace(/\s+/g, '');]])
)
local keep, save = page:find("await keepPicture(l.icon)", 1, true), page:find("call('_SAVE_LOOK'", 1, true)
T.truthy("Save Look keeps a new picture before the look that names it", keep and save and keep < save)
T.truthy(
  "a look names a kept picture by id alone",
  has("    delete out.body;\n    delete out.carried;\n    out.stored = true;")
)

T.section("A picture from a web address that refreshes")
local refreshOptions = page:match('<select id="mi%-every">(.-)</select>') or ""
T.contains("the Refresh row offers Once first", refreshOptions, '<option value="0">Once, when saved</option>')
for _, choice in ipairs({ '60">Every minute', '300">Every 5 minutes', '900">Every 15 minutes', '3600">Every hour' }) do
  T.contains("and " .. choice:match(">(.*)$"), refreshOptions, choice)
end
T.truthy("it shows with the Web address panel", has("$('fld-mine-every').hidden = !mine || gMineHow !== 'web';"))
T.truthy(
  "and says why less often is better",
  has("Each refresh writes to the controller’s storage, so less often is better.")
)
T.truthy("only a PNG or JPEG refreshes", has("mineMessage('A picture that refreshes has to be a PNG or JPEG.', true)"))
T.truthy(
  "kept as fetched, not redrawn",
  has("p = { kind: kind, b64: b64, width: pic.width, height: pic.height, name: nameFromUrl(url), every: every };")
)
T.truthy(
  "the tile, its colors, Icon and Badge hide for it",
  has("$('fld-shape').hidden = whole || !!every;")
    and has("$('customize').hidden = !l.icon || !!every;")
    and has("$('badge-section').hidden = !l.icon || !!every;")
)
T.truthy(
  "its preview is the picture fitted whole, nothing drawn on it",
  has("ctx.drawImage(shot, (size - w) / 2, (size - h) / 2, w, h);")
)
T.truthy(
  "Save Look draws and sends no picture for it",
  has("if (!every && (!before || !before.hasImage || before.stale")
)
T.truthy(
  "the controller fetches it again to keep it",
  has("Kit.call('_ADD_WEB_PICTURE', { request: request, url: rec.url, every: rec.every }, 'PICTURE_STORED', 60000)")
)
T.truthy(
  "a kept one gone from the button is fetched again, not uploaded",
  has("if (rec && rec.every) return keepWebPicture(rec, src);")
)
T.truthy(
  "opening its look restores Address and Refresh",
  has("$('mi-url').value = opened.url || '';") and has("$('mi-every').value = String(opened.every);")
)
T.truthy("the grid tags it with how often", has("tag.textContent = rec.every ? REFRESH_TAGS[rec.every] || '' : 'SVG';"))
T.truthy(
  "the picked line says how often and how its last refresh went",
  has("', refreshed ' + Kit.esc(REFRESH_WORDS[every] || '')")
)
T.truthy("the list shows a failed refresh", has("function refreshLines(l) {"))
T.truthy(
  "a picture whose source changed is asked for again",
  has("if (p.source && src && !src.pending && src.source !== p.source) {") and has("delete gSources[p.id];")
)
T.truthy(
  "a refreshing picture is named here from its address, since the driver keeps no name from one",
  has("function pictureName(rec) { return rec.every && rec.url ? nameFromUrl(rec.url) : rec.name; }")
)
T.truthy("an address with no path names nothing from the address", has("return last || 'Web picture';"))
T.truthy(
  "the badge's comment still sits over its lines",
  has("// A live badge's text, and what stops it reading.\nfunction badgeLines(l) {")
)

T.section("Copy To, Export and Import")
T.truthy(
  "the Looks card offers all three beside Add Look",
  has('id="copy-to" type="button" disabled>Copy To&hellip;')
    and has('id="export-looks" type="button" disabled>Export')
    and has('id="import-looks" type="button">Import&hellip;')
)
T.truthy(
  "Copy To is off with no looks or no other Dynamic Button",
  has("$('copy-to').disabled = gApplying || !n || !others;")
)
T.truthy("and asks the driver for the other buttons once the state is in", has("sendCommand('_GET_BUTTONS')"))
T.truthy(
  "one routine gives looks to any button, this one too",
  has("async function applyLooks(link, name, items, replace, say)")
)
T.truthy(
  "another button answers on the kit's link, kept and used again by the next copy",
  has("var link = Kit.follow(id), state = null, failed = null;") and has("if (gLinks[id]) return gLinks[id];")
)
T.truthy("and its commands go through it", has("open: link.open, send: link.send, call: link.call"))
local drawAt = page:find(
  "var dataUrl = await lookDataUrl(Object.assign({}, look, { custom: custom, badgeNow: null }), 300);",
  1,
  true
)
local swapAt = page:find("look.icon = Object.assign({}, look.icon, { id: given[pic.key], stored: true }", 1, true)
T.truthy(
  "a look is drawn under the id it came with, before the target's id replaces it",
  drawAt and swapAt and drawAt < swapAt
)
T.truthy("Replace brings the default along, Add leaves the target's", has("isDefault: !!(replace && item.isDefault)"))
T.truthy("a target's looks that don't fit are counted", has("leftOut = items.length - taking.length"))
T.truthy(
  "the file names its format and version",
  has("LOOKS_FORMAT = 'finitelabs.dynamic-buttons.looks', LOOKS_VERSION = 1")
)
T.truthy("and downloads under the button's name", has("a.download = base + '.dynamic-button.json';"))
T.truthy(
  "an imported SVG goes through the pasted SVG's checks, a raster through the upload's",
  has("pictureFromSvg(new TextDecoder().decode(bytes), name) : await pictureFromRaster(new Blob([bytes]), name)")
)
T.truthy("an imported icon's markup is cleaned afresh, not looked up by its id", has("cleanBody(icon.body)"))
T.falsy("never through the cache keyed by id", has("cleanIcon(id, icon.body)"))
T.truthy(
  "the file's own names can't reach an object's built-in fields",
  has("pictures = Object.create(null)") and has("if (!own.call(source, key))")
)
T.truthy(
  "a file's names and text are escaped",
  has("esc(it.look.name)") and has("esc(im.fileName)") and has("esc(im.from)")
)
T.truthy(
  "an unknown version from a newer driver says so",
  has("That file comes from a newer Dynamic Buttons driver. Update this one first.")
)

T.section("Import brings nothing that runs or reaches out unless asked")
T.truthy(
  "the opt-in starts off",
  has(
    '<input type="checkbox" id="im-trust"> Bring Show when, live badge text and web addresses with these looks</label>'
  ) and has("$('im-trust').checked = false;")
)
T.truthy(
  "without it, Show when is cleared and a live badge dropped",
  has("look.showWhen = '';") and has("if (liveBadgeText(look)) delete look.custom.badge;")
)
T.truthy(
  "and a look with a refreshing picture is left out by name",
  has("if (it.picture && it.picture.every) { cut.push(it.look.name); return false; }")
    and has("'Left out without their web addresses: '")
)
T.truthy("only the opt-in sends them as they are", has("var items = trusted ? chosen : chosen.filter("))
T.truthy(
  "each look shows its Show when, live badge text and web address, escaped",
  has("reach.push(['Show when', it.look.showWhen]);")
    and has("reach.push(['Web address', it.picture.url]);")
    and has("<code>' + Kit.esc(r[1]) + '</code>")
)

T.section("A refreshing picture that doesn't fetch costs only its look")
T.truthy(
  "the look is left out and the rest go on",
  has("if (r.unfetched) { unfetched.push(taking[n].look.name); continue; }")
)
T.truthy("and the result names it", has("'. Left out, ' + (unfetched.length === 1 ? 'its web picture didn’t'"))
T.truthy(
  "only on the driver's mark of a fetch that brought nothing",
  has("unfetched: !!every && kept.unfetched === true")
)
T.falsy("never on any refusal", has("unfetched: !!every && !link.failure()"))
T.truthy("Export's note agrees with one picture or many", has("(webs === 1 ? ' that refreshes' : ' that refresh')"))
T.truthy(
  "Copy is plainly labeled until there are looks and buttons to count",
  has("looks && buttons ? 'Copy ' + plural(looks, 'Look') + ' to ' + plural(buttons, 'Button') : 'Copy'")
)

T.section("Replace deletes the shown look last")
T.truthy(
  "the others go first, so no delete shows another look and runs its Shown programming",
  has(
    "var order = existing.filter(function(l) { return l.id !== state.shown; }).concat(existing.filter(function(l) { return l.id === state.shown; }));"
  ) and has("{ id: order[d].id }")
)

T.section("A file's looks meet the driver's rules before anything is deleted")
local Looks2 = require("dynamic_button.looks")
T.truthy("the problem check runs as the file is read", has("var problem = lookProblem(l, refreshes);"))
T.truthy(
  "and a look with one is left out by name",
  has("if (problem) { skipped.push(label + ': ' + problem); continue; }")
)
T.truthy("glow is whole, from 0 to the driver's most", has("!wholeIn(l.glow, 0, " .. Looks2.MAX_GLOW .. ")"))
T.truthy(
  "size, position and badge size have the driver's bounds",
  has("!wholeIn(c.size, " .. Looks2.MIN_SIZE .. ", 100)")
    and has("!wholeIn(c[k], -" .. Looks2.MAX_SHIFT .. ", " .. Looks2.MAX_SHIFT .. ")")
    and has("!wholeIn(b.size, " .. Looks2.MIN_BADGE_SIZE .. ", " .. Looks2.MAX_BADGE_SIZE .. ")")
)
T.truthy(
  "and so do a name, a badge's text and a Show when",
  has("Array.from(name).length > " .. Looks2.MAX_NAME)
    and has("utf8Bytes(text) > " .. Looks2.MAX_LIVE_BADGE)
    and has("utf8Bytes(l.showWhen.trim()) > " .. Looks2.MAX_SHOW_WHEN)
)
local everyChoices = page:match("BADGE_EVERY_CHOICES = %[([%d, ]+)%]")
T.eq("the badge's update choices are the driver's", everyChoices, table.concat(Looks2.BADGE_EVERY_SECONDS, ", "))

T.section("Replace asks twice, Export warns of addresses, and a copy shuts the card")
T.truthy(
  "Replace's first press says what goes",
  has("if (replace && !confirmed($('cp-go'), 'cp-confirm', 'Replaces the looks on ")
    and has("if (replace && !confirmed($('im-go'), 'im-confirm', 'Replaces this button’s looks")
)
T.truthy(
  "and a change to what's ticked ends a Replace waiting for its second press",
  has("function syncCopyGo() {\n  unconfirm($('cp-go'));")
    and has("function syncImportGo() {\n  unconfirm($('im-go'));")
    and has("$('im-trust').addEventListener('change', syncImportGo);")
)
T.truthy("Export says the file holds addresses", has("', which can carry a login or token.'"))
T.truthy(
  "a look whose picture is gone is left out by name",
  has("if (!rec || (!rec.every && !src.b64)) { missing.push(l.name); return; }")
)
T.truthy("the Copy panel keeps its ticks when the list comes again", has("renderCopyPanel(true)"))
T.truthy(
  "while looks are given, the card's buttons are off, not just unclickable",
  has("if (gApplying) Array.prototype.forEach.call(el.querySelectorAll('button'), function(b) { b.disabled = true; });")
)
T.falsy("no pointer-events trick", has("#looks-card.busy"))
T.truthy(
  "an id the page carries uses its own markup",
  has("var own = carriedIcon(id);\n  if (own) return Object.assign({}, own, { carried: true });")
)

T.section("Icon licenses")
T.truthy("the card is collapsed until it's opened", has('<details class="card" id="lic-card">'))
T.truthy("and still names every collection", has("<summary>Icon licenses</summary>") and has('id="lic-list"'))

T.section("A badge's answer")
T.truthy("is the kit's, with the driver's fitted text", has("now = result.error ? '' : Kit.str(result.fitted)"))
T.truthy("and its error in plain words", has("note.textContent = result.error ? result.message"))

T.section("A sentence names the field in quotes")
T.truthy("under Look Control", has([['The first look whose "Show when" is true shows.']]))
T.truthy("beside Default look", has([[Show this look when no "Show when" is true]]))
T.truthy("in the Default tag's tip", has("Shows when no &quot;Show when&quot; is true."))

T.finish()
