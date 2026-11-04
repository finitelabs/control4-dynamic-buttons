--- The Dynamic Button driver end to end under the C4 shim: looks made in the Button tab, what the
--- proxy is told and where the picture is served, a restart, programming's Show Look, Look Is and
--- Look Changed through renames and deletes, the driver-side icon search, and Reset Driver.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_driver.lua

local T = require("testlib")
local H = require("dynamic_button_harness")
local deferred = require("deferred")

-- The icon search the driver makes for a tab that can't reach Iconify.
local fetched = {}
package.loaded["lib.http"] = {
  get = function(_, url)
    table.insert(fetched, url)
    return deferred.new():resolve({ code = 200, body = '{"icons":["mdi:battery"]}' })
  end,
}

local ADDRESS = "controller://driver/dynamic_button/buttons/" .. H.DEVICE_ID .. "/"

--- @return function|nil test The Look Is conditional's test, as programming calls it.
local function lookIs()
  local cond = require("lib.conditionals"):getConditionals()
  local entry = cond.Programming and cond.Programming.look_is
  return entry and TC[entry.name], entry and entry.list_items
end

T.section("A fresh button")
H.start()
T.eq("runs on the interpreter", jit and jit.status() or false, false)
T.eq("shows the driver's own icon", H.lastIcon().params, { icon = "", icon_description = "" })
T.eq("sent with empty values allowed, as the empty icon needs", H.lastIcon().allowEmpty, true)
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
T.eq("the picture is stored", H.stored()["look-1.png"], H.png("Charged"))
T.eq("and served where the address points", H.served()["1.png"], H.png("Charged"))
T.eq("the Look variable names it", Variables["Look"], "Charged")
T.eq("so does Shown Look", Properties["Shown Look"], "Charged")
T.eq("Look Changed fires once", H.fired, { "Look Changed" })
T.eq("the tab hears the picture was kept", H.lastUi("IMAGE_STORED").look, "1")
T.eq("and its state shows the look shown", H.state().shown, 1)
T.eq("Look Is lists it", select(2, lookIs()), "Charged (1)")

T.section("A second look, not shown")
H.mark()
local low = H.addLook("Low")
T.eq("is saved as id 2", low, 2)
T.eq("its picture is stored", H.stored()["look-2.png"], H.png("Low"))
T.eq("the proxy is not told anything", H.lastIcon(), nil)
T.eq("and only the shown look is served", H.served()["2.png"], nil)
T.eq("no Look Changed fires", #H.fired, 0)
T.eq("the tab's state has both looks, with pictures", { #H.state().looks, H.state().looks[2].hasImage }, { 2, true })
T.eq("Look Is lists both", select(2, lookIs()), "Charged (1),Low (2)")

T.section("Show Look from programming")
T.eq("the command lists the looks by name and id", GCPL.Show_Look("Look"), { "Charged (1)", "Low (2)" })
T.eq("and nothing for another parameter", GCPL.Show_Look("Other"), {})
H.mark()
EC.Show_Look({ Look = "Low (2)" })
T.eq("the proxy is told the new look, under version 2", H.lastIcon().params.icon, ADDRESS .. "2.png?v=2")
T.eq("the new look is served", H.served()["2.png"], H.png("Low"))
T.eq("and the old one no longer is", H.served()["1.png"], nil)
T.eq("Look Changed fires", H.fired, { "Look Changed" })
T.eq("the Look variable follows", Variables["Look"], "Low")
H.mark()
EC.Show_Look({ Look = "Low (2)" })
T.eq("showing it again serves a new address", H.lastIcon().params.icon, ADDRESS .. "2.png?v=3")
T.eq("but fires no Look Changed", #H.fired, 0)
H.mark()
EC.Show_Look({ Look = "Missing (9)" })
T.eq("a look that is gone shows nothing", H.lastIcon(), nil)

T.section("Look Is")
local test = lookIs()
T.truthy("is true for the shown look", test("", { VALUE = "Low (2)", LOGIC = "EQUAL" }))
T.falsy("and false for another", test("", { VALUE = "Charged (1)", LOGIC = "EQUAL" }))
T.truthy("NOT_EQUAL turns it round", test("", { VALUE = "Charged (1)", LOGIC = "NOT_EQUAL" }))

T.section("Renaming the shown look")
H.mark()
H.tab("_SAVE_LOOK", H.lookFields("Empty", { id = low }))
T.eq("the proxy is told the new name, at the same address", H.lastIcon().params, {
  icon = ADDRESS .. "2.png?v=3",
  icon_description = "Empty",
})
T.eq("the Look variable follows", Variables["Look"], "Empty")
T.eq("a rename is no change of look", #H.fired, 0)
T.eq("Look Is lists the new name", select(2, lookIs()), "Charged (1),Empty (2)")
T.truthy("and a test written before the rename still holds", test("", { VALUE = "Low (2)", LOGIC = "EQUAL" }))
H.mark()
EC.Show_Look({ Look = "Low (2)" })
T.eq("Show Look with the old label finds it too", H.lastIcon().params.icon_description, "Empty")

T.section("A restart")
local version = tonumber(H.lastIcon().params.icon:match("v=(%d+)$"))
H.mark()
OnDriverDestroyed()
T.eq("stopping removes the served picture", H.served()["2.png"], nil)
T.eq("and keeps the stored one", H.stored()["look-2.png"], H.png("Low"))
H.start()
T.eq("starting serves it again", H.served()["2.png"], H.png("Low"))
T.eq("and tells the proxy the same address", H.lastIcon().params.icon, ADDRESS .. "2.png?v=" .. version)
T.eq("the Look variable is restored", Variables["Look"], "Empty")
T.eq("no Look Changed fires at start", #H.fired, 0)
test = lookIs()
T.truthy("Look Is answers again after the restart", test and test("", { VALUE = "Empty (2)", LOGIC = "EQUAL" }))

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
local b64 = C4:Base64Encode(H.png("Skipped", 300))
H.tab("_PUT_IMAGE", { look = charged, upload = "y", index = 1, count = 3, data = b64:sub(1, 136) })
H.tab("_PUT_IMAGE", { look = charged, upload = "y", index = 3, count = 3, data = b64:sub(273, 408) })
T.contains("a skipped chunk is refused", H.lastUi("ERROR").message, "chunk out of order")
T.eq("and the look keeps its picture", H.stored()["look-1.png"], H.png("Charged"))
H.mark()
H.tab("_SHOW_LOOK", { id = 9 })
T.eq("showing a look that is gone is refused", H.lastUi("ERROR").message, "no such look")
H.mark()
H.tab("_DELETE_LOOK", { id = 9 })
T.eq("deleting one is too", H.lastUi("ERROR").message, "no such look")

T.section("Ordering from the tab")
H.tab("_ORDER_LOOKS", { ids = { low, charged } })
T.eq("the state lists the new order", { H.state().looks[1].id, H.state().looks[2].id }, { low, charged })
T.eq("and so does Look Is", select(2, lookIs()), "Empty (2),Charged (1)")
H.tab("_ORDER_LOOKS", { ids = { low } })
T.eq("an order missing a look is refused", H.lastUi("ERROR").message, "the order must name every look once")

T.section("Deleting the shown look")
H.mark()
H.tab("_DELETE_LOOK", { id = low })
T.eq(
  "the next ready look is shown, under a new version",
  H.lastIcon().params.icon,
  ADDRESS .. "1.png?v=" .. version + 1
)
T.eq("the deleted look's pictures are gone", { H.served()["2.png"], H.stored()["look-2.png"] }, {})
T.eq("Look Changed fires", H.fired, { "Look Changed" })
T.eq("the Look variable follows", Variables["Look"], "Charged")
T.eq("Look Is lists what is left", select(2, lookIs()), "Charged (1)")
T.falsy("and a test naming the deleted look is false", test("", { VALUE = "Empty (2)", LOGIC = "EQUAL" }))
T.truthy("while NOT_EQUAL is true", test("", { VALUE = "Empty (2)", LOGIC = "NOT_EQUAL" }))

T.section("Deleting the last look")
H.mark()
H.tab("_DELETE_LOOK", { id = charged })
T.eq("the driver's own icon shows", H.lastIcon().params, { icon = "", icon_description = "" })
T.eq("the Look variable is empty", Variables["Look"], "")
T.eq("Look Changed fires", H.fired, { "Look Changed" })
T.eq("nothing is served", next(H.served()), nil)
T.eq("Look Is keeps its last list rather than an empty one", select(2, lookIs()), "Charged (1)")

T.section("The icon search through the driver")
H.mark()
H.tab("_ICONIFY", { request = "7", kind = "search", value = "battery" })
T.contains(
  "the driver asks Iconify, limited to the offered packs",
  fetched[1],
  "/search?query=battery&prefixes=material-symbols,mdi,"
)
T.eq("and hands the tab the answer", H.lastUi("ICONIFY"), { request = "7", body = '{"icons":["mdi:battery"]}' })
H.mark()
H.tab("_ICONIFY", { request = "8", kind = "icon", value = "simple-icons:github" })
T.eq("a pack not offered is refused without a request", #fetched, 1)
T.eq("and the tab is told why", H.lastUi("ICONIFY"), { request = "8", error = "not an offered icon pack" })

T.section("Reset Driver")
H.addLook("Full")
H.addLook("Half")
Properties["Log Level"] = "5 - Trace"
H.mark()
EC.Reset_Driver({ ["Are You Sure?"] = "No" })
H.tab("_GET_STATE")
T.eq("No changes nothing", #H.state().looks, 2)
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("Yes deletes every look", #H.state().looks, 0)
T.eq("and their stored pictures", next(H.stored()), nil)
T.eq("and served ones", next(H.served()), nil)
T.eq("the driver's own icon shows", H.lastIcon().params, { icon = "", icon_description = "" })
T.eq("the Look variable is back, empty", Variables["Look"], "")
T.eq("no Look Changed fires, as on a fresh install", #H.fired, 0)
T.eq("Look Is is gone", select(2, lookIs()), nil)
T.eq("settings return to their defaults", Properties["Log Level"], "3 - Info")
T.eq("a new look starts again from id 1", H.addLook("Again"), 1)

T.finish()
