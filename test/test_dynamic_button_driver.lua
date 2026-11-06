--- The Dynamic Button driver end to end under the C4 shim: looks made in the Button tab, what the
--- proxy is told and where the picture is served, a Director restart, programming's Show Look,
--- Look Is and Look Changed through renames and deletes, the driver-side icon search, removal from
--- the project, and Reset Driver.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_driver.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

local ADDRESS = "controller://driver/dynamic_button/buttons/" .. H.DEVICE_ID .. "/"
local OWN_ICON = "controller://driver/dynamic_button/icons/experience_300.png"

--- @return function|nil test The Look Is conditional's test, as programming calls it.
--- @return string|nil items Its list.
local function lookIs()
  local cond = require("lib.conditionals"):getConditionals()
  local entry = cond.Programming and cond.Programming.look_is
  return entry and TC[entry.name], entry and entry.list_items
end

--- @return integer|nil version The address version of the last picture the proxy was told.
local function lastVersion()
  local icon = H.lastIcon()
  return icon and tonumber(icon.params.icon:match("v=(%d+)$"))
end

T.section("A fresh button")
H.start()
T.eq("shows the driver's own icon", H.lastIcon().params, { icon = OWN_ICON, icon_description = "" })
T.eq("sent with empty values allowed, as the empty description needs", H.lastIcon().allowEmpty, true)
T.eq("as a notification, which is how the proxy takes it", H.lastIcon().message, "NOTIFY")
T.eq("to the UI Button proxy", H.lastIcon().binding, 5001)
T.eq("the Look variable is empty", Variables["Look"], "")
T.eq("Shown Look is empty", Properties["Shown Look"], "")
T.eq("Driver Status is Ready", Properties["Driver Status"], "Ready")
T.eq("no Look Changed fires at start", #H.fired, 0)
T.eq("there is no Look Is conditional with no looks", select(2, lookIs()), nil)
T.truthy("picture chunks are kept out of the log", UIR.suppressDebug["_PUT_IMAGE"])

T.section("The first look")
H.mark()
local charged = H.addLook("Charged")
T.eq("the look is saved as id 1", charged, 1)
T.eq("the proxy is told its address, version 1", H.lastIcon().params.icon, ADDRESS .. "1.png?v=1")
T.eq("with its name as the text line", H.lastIcon().params.icon_description, "Charged")
T.eq("in a notification", H.lastIcon().message, "NOTIFY")
T.eq("the picture is stored in the button's storage", H.stored()["look-1.png"], H.png("Charged"))
T.eq("and served where the address points", H.served()["1.png"], H.png("Charged"))
T.eq("the Look variable names it", Variables["Look"], "Charged")
T.eq("so does Shown Look", Properties["Shown Look"], "Charged")
T.eq("Look Changed fires once, then the look's own event", H.fired, { "Look Changed", "Charged Shown" })
T.eq("the tab hears the picture was kept", H.lastUi("IMAGE_STORED").look, "1")
T.eq("and its state shows the look shown", H.state().shown, 1)
T.eq("Look Is lists it", select(2, lookIs()), "Charged (1)")

T.section("A command's answer carries the state")
local saved = JSON:decode(H.tab("_SAVE_LOOK", H.lookFields("Spare")))
T.eq("a save answers SAVED", saved._command, "SAVED")
T.eq("with the new look's id", saved.look, "2")
T.eq("and the state", #JSON:decode(saved.state).looks, 2)
local b64 = C4:Base64Encode(H.png("Spare"))
local stored = JSON:decode(H.tab("_PUT_IMAGE", { look = 2, upload = "r", index = 1, count = 1, data = b64 }))
T.eq("the last chunk answers IMAGE_STORED", stored._command, "IMAGE_STORED")
T.eq("with the state showing the picture", JSON:decode(stored.state).looks[2].hasImage, true)
local function statePushes()
  local n = 0
  for _, sent in ipairs(H.ui) do
    n = n + (sent.params.state and 1 or 0)
  end
  return n
end
H.mark()
H.tab("_SAVE_LOOK", H.lookFields("Spare", { id = 2, iconColor = "#000000" }))
T.eq("a save sends the state over the socket once", statePushes(), 1)
local spare = C4:Base64Encode(H.png("Spare black", 8000))
local size = 3072
local count = math.ceil(#spare / size)
T.truthy("a picture of several chunks", count >= 3)
H.mark()
local first = H.tab("_PUT_IMAGE", { look = 2, upload = "s", index = 1, count = count, data = spare:sub(1, size) })
T.eq("a chunk before the last answers nothing", first, nil)
T.eq("and sends nothing over the socket", #H.ui, 0)
local last
for i = 2, count do
  last = H.tab(
    "_PUT_IMAGE",
    { look = 2, upload = "s", index = i, count = count, data = spare:sub((i - 1) * size + 1, i * size) }
  )
end
T.eq("the last chunk answers IMAGE_STORED", JSON:decode(last)._command, "IMAGE_STORED")
T.eq("and the whole picture sends the socket one message", #H.ui, 1)
T.eq("IMAGE_STORED, with the state", { H.ui[1].command, statePushes() }, { "IMAGE_STORED", 1 })
local refused = JSON:decode(H.tab("_SAVE_LOOK", H.lookFields("spare")))
T.eq(
  "a refusal answers ERROR",
  { refused._command, refused.message },
  { "ERROR", "another look is already named Spare" }
)
H.tab("_DELETE_LOOK", { id = 2 })

T.section("A second look, not shown")
H.mark()
local low = H.addLook("Low")
T.eq("is saved as id 3", low, 3)
T.eq("its picture is stored", H.stored()["look-3.png"], H.png("Low"))
T.eq("the proxy is not told anything", H.lastIcon(), nil)
T.eq("and only the shown look is served", H.served()["3.png"], nil)
T.eq("no Look Changed fires", #H.fired, 0)
T.eq("Look Is lists both", select(2, lookIs()), "Charged (1),Low (3)")

T.section("Show Look from programming")
T.eq("the command lists the looks by name and id", GCPL.Show_Look("Look"), { "Charged (1)", "Low (3)" })
T.eq("and nothing for another parameter", GCPL.Show_Look("Other"), {})
H.mark()
EC.Show_Look({ Look = "Low (3)" })
T.eq("the proxy is told the new look, under its picture's version", H.lastIcon().params.icon, ADDRESS .. "3.png?v=4")
T.eq("the new look is served", H.served()["3.png"], H.png("Low"))
T.eq("and the old one stays, for coming back to", H.served()["1.png"], H.png("Charged"))
T.eq("Look Changed fires, then the look's own event", H.fired, { "Look Changed", "Low Shown" })
T.eq("the Look variable follows", Variables["Look"], "Low")
H.mark()
EC.Show_Look({ Look = "Low (3)" })
T.eq("showing the shown look again tells the proxy nothing", H.lastIcon(), nil)
T.eq("and fires no Look Changed", #H.fired, 0)
H.mark()
EC.Show_Look({ Look = "Missing (9)" })
T.eq("a look that is gone shows nothing", H.lastIcon(), nil)

T.section("Look Is")
local test = lookIs()
T.truthy("is true for the shown look", test("", { VALUE = "Low (3)", LOGIC = "EQUAL" }))
T.falsy("and false for another", test("", { VALUE = "Charged (1)", LOGIC = "EQUAL" }))
T.truthy("NOT_EQUAL turns it round", test("", { VALUE = "Charged (1)", LOGIC = "NOT_EQUAL" }))

T.section("Renaming the shown look")
H.mark()
H.tab("_SAVE_LOOK", H.lookFields("Empty", { id = low }))
T.eq("the proxy is told the new name, at the same address", H.lastIcon().params, {
  icon = ADDRESS .. "3.png?v=4",
  icon_description = "Empty",
})
T.eq("the Look variable follows", Variables["Look"], "Empty")
T.eq("a rename is no change of look", #H.fired, 0)
T.eq("Look Is lists the new name", select(2, lookIs()), "Charged (1),Empty (3)")
T.truthy("and a test written before the rename still holds", test("", { VALUE = "Low (3)", LOGIC = "EQUAL" }))
T.falsy("a rename leaves the picture current", H.state().looks[2].stale)
H.mark()
EC.Show_Look({ Look = "Charged (1)" })
EC.Show_Look({ Look = "Low (3)" })
T.eq("Show Look with the old label finds it too", H.lastIcon().params.icon_description, "Empty")

T.section("Editing how a look is drawn")
H.mark()
H.tab("_SAVE_LOOK", H.lookFields("Empty", { id = low, tileColor = "#DC2626" }))
T.truthy("marks its picture out of date until the new one arrives", H.state().looks[2].stale)
T.eq("while the proxy keeps the old picture", H.lastIcon(), nil)
H.sendImage(low, H.png("Empty red"))
T.falsy("the new picture is current", H.state().looks[2].stale)
T.eq("and goes out under a new address", H.lastIcon().params.icon, ADDRESS .. "3.png?v=5")

T.section("A Director restart")
local version = lastVersion()
H.mark()
H.restart()
T.eq("the served picture is still there", H.served()["3.png"], H.png("Empty red"))
T.eq("the proxy is told the same address", H.lastIcon().params.icon, ADDRESS .. "3.png?v=" .. version)
T.eq("the Look variable is restored", Variables["Look"], "Empty")
T.eq("no Look Changed fires at start", #H.fired, 0)
test = lookIs()
T.truthy("Look Is answers again after the restart", test and test("", { VALUE = "Empty (3)", LOGIC = "EQUAL" }))
require("lib.persist"):set("Conditionals", nil)
H.restart()
T.eq("the looks list Look Is when its saved list is gone", select(2, lookIs()), "Charged (1),Empty (3)")

T.section("A stored picture gone at start")
H.stored()["look-3.png"] = nil
H.mark()
H.restart()
T.eq("the next ready look is served", H.served()["1.png"], H.png("Charged"))
T.eq("and shown", H.lastIcon().params.icon_description, "Charged")
H.tab("_GET_STATE")
T.falsy("the look without its picture is marked so", H.state().looks[2].hasImage)
T.eq("and no longer served", H.served()["3.png"], nil)
H.sendImage(low, H.png("Empty again"))
EC.Show_Look({ Look = "Empty (3)" })

T.section("The Button tab refusing changes")
H.mark()
H.tab("_SAVE_LOOK", H.lookFields("charged"))
T.eq("a name another look has is refused", H.lastUi("ERROR").message, "another look is already named Charged")
H.tab("_GET_STATE")
T.eq("and no look is added", #H.state().looks, 2)
H.mark()
H.tab("_PUT_IMAGE", { look = 9, upload = "x", index = 1, count = 1, data = C4:Base64Encode(H.png("Ghost")) })
T.eq("a picture for no look is refused", H.lastUi("ERROR").message, "the picture's look is gone")
H.mark()
local skipped = C4:Base64Encode(H.png("Skipped", 300))
H.tab("_PUT_IMAGE", { look = charged, upload = "y", index = 1, count = 3, data = skipped:sub(1, 136) })
H.tab("_PUT_IMAGE", { look = charged, upload = "y", index = 3, count = 3, data = skipped:sub(273, 408) })
T.contains("a skipped chunk is refused", H.lastUi("ERROR").message, "chunk out of order")
T.eq("and the look keeps its picture", H.stored()["look-1.png"], H.png("Charged"))
H.mark()
H.tab("_SHOW_LOOK", { id = 9 })
T.eq("showing a look that is gone is refused", H.lastUi("ERROR").message, "no such look")
H.mark()
H.tab("_DELETE_LOOK", { id = 9 })
T.eq("deleting one is too", H.lastUi("ERROR").message, "no such look")
H.mark()
H.stored()["look-1.png"] = nil
H.tab("_SHOW_LOOK", { id = charged })
T.eq(
  "showing a look whose stored picture is gone is refused",
  H.lastUi("ERROR").message,
  "the look's picture is missing"
)
H.tab("_GET_STATE")
T.falsy("and the look is marked as having none", H.state().looks[1].hasImage)
H.sendImage(charged, H.png("Charged"))

T.section("Ordering from the tab")
H.tab("_ORDER_LOOKS", { ids = { low, charged } })
T.eq("the state lists the new order", { H.state().looks[1].id, H.state().looks[2].id }, { low, charged })
T.eq("and so does Look Is", select(2, lookIs()), "Empty (3),Charged (1)")
H.tab("_ORDER_LOOKS", { ids = { low } })
T.eq("an order missing a look is refused", H.lastUi("ERROR").message, "the order must name every look once")

T.section("Deleting the shown look")
EC.Show_Look({ Look = "Empty (3)" })
version = lastVersion() or version
H.mark()
H.tab("_DELETE_LOOK", { id = low })
T.contains("the next ready look is shown", H.lastIcon().params.icon, ADDRESS .. "1.png?v=")
T.truthy("under a new address", lastVersion() > version)
T.eq("the deleted look's pictures are gone", { H.served()["3.png"], H.stored()["look-3.png"] }, {})
T.eq("Look Changed fires, then the shown look's own event", H.fired, { "Look Changed", "Charged Shown" })
T.eq("the Look variable follows", Variables["Look"], "Charged")
T.eq("Look Is lists what is left", select(2, lookIs()), "Charged (1)")
T.falsy("and a test naming the deleted look is false", test("", { VALUE = "Empty (3)", LOGIC = "EQUAL" }))
T.truthy("while NOT_EQUAL is true", test("", { VALUE = "Empty (3)", LOGIC = "NOT_EQUAL" }))

T.section("Deleting the last look")
H.mark()
H.tab("_DELETE_LOOK", { id = charged })
T.eq("the driver's own icon shows", H.lastIcon().params, { icon = OWN_ICON, icon_description = "" })
T.eq("the Look variable is empty", Variables["Look"], "")
T.eq("Look Changed fires", H.fired, { "Look Changed" })
T.eq("nothing is served", next(H.served()), nil)
T.eq("Look Is keeps its last list rather than an empty one", select(2, lookIs()), "Charged (1)")
H.restart()
test = lookIs()
T.eq("and keeps it across a restart", select(2, lookIs()), "Charged (1)")
T.truthy("with a test that answers", test and test("", { VALUE = "Charged (1)", LOGIC = "NOT_EQUAL" }))

T.section("The icon search through the driver")
H.mark()
H.fetched = {}
H.tab("_ICONIFY", { request = "7", kind = "search", value = "battery" })
T.contains(
  "the driver asks Iconify in all offered packs",
  H.fetched[1],
  "/search?query=battery&prefixes=material-symbols,mdi,"
)
local answer = H.lastUi("ICONIFY")
T.eq("the tab gets the answer back", answer.request, "7")
T.eq(
  "as JSON, decoded and encoded again rather than a Lua table's name",
  JSON:decode(answer.body),
  { icons = { "mdi:battery" }, total = 1 }
)
H.tab("_ICONIFY", { request = "8", kind = "search", value = "battery", prefixes = "tabler,lucide" })
T.contains("a search can name some of the packs", H.fetched[2], "&prefixes=tabler,lucide&")
H.mark()
H.tab("_ICONIFY", { request = "9", kind = "search", value = "battery", prefixes = "mdi,simple-icons" })
T.eq("a search naming a pack not offered is refused without a request", #H.fetched, 2)
T.eq("and the tab is told why", H.lastUi("ICONIFY"), { request = "9", error = "not an offered icon pack" })
H.tab("_ICONIFY", { request = "10", kind = "icon", value = "simple-icons:github" })
T.eq(
  "so is an icon from a pack not offered",
  H.lastUi("ICONIFY"),
  { request = "10", error = "not an offered icon pack" }
)

T.section("Deleting the shown look when the next look's picture is gone")
local first = H.addLook("First")
local second = H.addLook("Second")
H.stored()["look-" .. second .. ".png"] = nil
H.mark()
H.tab("_DELETE_LOOK", { id = first })
T.eq("the driver's own icon shows", H.lastIcon().params, { icon = OWN_ICON, icon_description = "" })
T.eq("the Look variable is empty", Variables["Look"], "")
T.falsy("and the look left is marked as having no picture", H.state().looks[1].hasImage)
H.tab("_DELETE_LOOK", { id = second })

T.section("A look's glow and grayscale")
local dimmedId = H.addLook("Dimmed")
H.tab("_SAVE_LOOK", H.lookFields("Dimmed", { id = dimmedId, glow = 30, grayscale = true }))
local function dimmedLook()
  H.tab("_GET_STATE")
  for _, look in ipairs(H.state().looks) do
    if look.id == dimmedId then
      return { look.glow, look.grayscale }
    end
  end
end
T.eq("the tab is sent them", dimmedLook(), { 30, true })
H.restart()
T.eq("they are kept across a Director restart", dimmedLook(), { 30, true })
H.update()
T.eq("and a driver update", dimmedLook(), { 30, true })
H.tab("_DELETE_LOOK", { id = dimmedId })

T.section("A look's customization")
local styledId = H.addLook("Styled")
local styledCustom = {
  color = "#14A39A",
  size = 84,
  x = -4,
  badge = { text = "50%", place = "Under", color = "#FFFFFF", background = "None" },
}
H.tab("_SAVE_LOOK", H.lookFields("Styled", { id = styledId, custom = styledCustom }))
local function styledLook()
  H.tab("_GET_STATE")
  for _, look in ipairs(H.state().looks) do
    if look.id == styledId then
      return look
    end
  end
end
T.eq("the tab is sent it", styledLook().custom, styledCustom)
T.truthy("and its picture is out of date until a new one is drawn", styledLook().stale)
H.restart()
T.eq("it is kept across a Director restart", styledLook().custom, styledCustom)
H.update()
T.eq("and a driver update", styledLook().custom, styledCustom)
local refused = JSON:decode(H.tab("_SAVE_LOOK", H.lookFields("Styled", { id = styledId, custom = { size = 20 } })))
T.eq(
  "a customization the driver refuses is answered with why",
  refused.message,
  "size is a whole percent from 50 to 100"
)
T.eq("and the look keeps its own", styledLook().custom, styledCustom)
H.tab("_DELETE_LOOK", { id = styledId })

T.section("The tab hears only which look is shown")
local oneId, twoId = H.addLook("One"), H.addLook("Two")
H.mark()
EC.Show_Look({ Look = "One (" .. oneId .. ")" })
T.eq("Show Look sends it one small message", H.ui, { { command = "SHOWN", params = { shown = tostring(oneId) } } })
H.mark()
local showAnswer = JSON:decode(H.tab("_SHOW_LOOK", { id = twoId }))
T.eq("so does the tab's own Show", H.ui, { { command = "SHOWN", params = { shown = tostring(twoId) } } })
T.eq("which answers the same", { showAnswer._command, showAnswer.state }, { "SHOWN", nil })
H.tab("_DELETE_LOOK", { id = oneId })
H.tab("_DELETE_LOOK", { id = twoId })

T.section("A command's DATA can be wrapped")
--- @param separator string
--- @return string data The fields as the Button tab sends them, with the separator every 76 characters.
local function wrappedData(fields, separator)
  return (C4:Base64Encode(JSON:encode(fields)):gsub(string.rep(".", 76), "%0" .. separator))
end
local wrapped = JSON:decode(UIR._SAVE_LOOK({ DATA = wrappedData(H.lookFields("Wrapped"), "\n") }))
T.eq("a save with newlines in its DATA is taken", wrapped._command, "SAVED")
local crlf = JSON:decode(UIR._SAVE_LOOK({ DATA = wrappedData(H.lookFields("Wrapped CRLF"), "\r\n") }))
T.eq("and so is one with CRLF", crlf._command, "SAVED")
H.tab("_DELETE_LOOK", { id = tonumber(wrapped.look) })
H.tab("_DELETE_LOOK", { id = tonumber(crlf.look) })

T.section("Reset Driver")
H.addLook("Full")
local lastId = H.addLook("Half")
H.tab(
  "_SAVE_LOOK",
  H.lookFields("Half", {
    id = lastId,
    custom = { size = 80, badge = { text = "1/2", place = "Under", color = "#FFFFFF", background = "None" } },
  })
)
local versionBefore = lastVersion()
Properties["Log Level"] = "5 - Trace"
H.mark()
EC.Reset_Driver({ ["Are You Sure?"] = "No" })
H.tab("_GET_STATE")
T.eq("No changes nothing", #H.state().looks, 2)
H.mark()
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("Yes deletes every look", #H.state().looks, 0)
T.eq("and sends the tab the state once, for all the settings it resets", statePushes(), 1)
T.eq("and their stored pictures", next(H.stored()), nil)
T.eq("and served ones", next(H.served()), nil)
T.eq("the driver's own icon shows", H.lastIcon().params, { icon = OWN_ICON, icon_description = "" })
T.eq("the Look variable is back, empty", Variables["Look"], "")
T.eq("no Look Changed fires, as on a fresh install", #H.fired, 0)
T.eq("Look Is is gone", select(2, lookIs()), nil)
T.eq("settings return to their defaults", Properties["Log Level"], "3 - Info")
T.eq("a new look never takes an old look's number", H.addLook("Again"), lastId + 1)
H.tab("_GET_STATE")
T.eq("and none keeps an old look's customization", H.state().looks[1].custom, nil)
T.truthy("nor an address an app has seen", lastVersion() > versionBefore)
H.mark()
EC.Show_Look({ Look = "Half (" .. lastId .. ")" })
T.eq("so programming naming an old look shows nothing", H.lastIcon(), nil)

T.section("Removed from the project")
H.addLook("Kept")
OnDriverRemovedFromProject()
T.eq("its stored pictures are deleted", next(H.stored()), nil)
T.eq("and its served ones", next(H.served()), nil)

T.section("Every message to the proxy")
T.eq("is ICON_CHANGED as a notification", H.sentTypes, { ["ICON_CHANGED NOTIFY"] = true })

T.finish()
