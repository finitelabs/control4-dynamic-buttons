--- The DriverCentral build's license gate, driven by the real vendored cloud client against a fake Cloud driver: a
--- licensed install and a trial run; without a license the button shows the driver's own icon after five minutes and
--- nothing changes its look; a license back shows the look again at once.

local T = require("testlib")
local OWN_ICON = "controller://driver/dynamic_button/icons/experience_300.png"
local H = require("dynamic_button_harness")
local cloud = require("dc_cloud")

local UNLICENSED = "No active license"

local gate

--- A load with a fresh client and gate, as Director's start of the driver. The looks and pictures in the driver's
--- storage stay, as they do on a controller.
--- @param answer table|nil What the Cloud driver answers each ping with; nil answers nothing.
--- @param pid integer|nil The product id (900).
local function load(answer, pid)
  if gate and gate._timer then
    gate._timer:Cancel()
  end
  package.preload["cloud-client-byte"] = nil
  package.loaded["cloud-client-byte"] = nil
  package.loaded["lib.drivercentral"] = nil
  gate = require("lib.drivercentral")
  gate.PRODUCT_ID = pid or 900
  cloud.ping, cloud.answer, cloud.silent, cloud.present = nil, answer, answer == nil, true
  DC_OnDriverStatus = nil
  if OnDriverDestroyed then
    H.update()
  else
    H.start()
  end
end

--- `n` rounds of 10 s: one ping, then every timer once, the gate's read among them.
--- @param n integer|nil
local function tick(n)
  for _ = 1, n or 1 do
    if cloud.ping then
      cloud.poll(1)
    end
    ShimFireTimers()
  end
end

--- @return string|nil icon The address the proxy was last told.
local function lastIcon()
  local sent = H.lastIcon()
  return sent and sent.params.icon
end

--- @return integer|nil version The address version of the last picture the proxy was told.
local function lastVersion()
  return tonumber((lastIcon() or ""):match("v=(%d+)$"))
end

--- Every way a look can change, from a press, programming and the Button tab.
local function tryEverything()
  H.press()
  EC.Show_Look({ Look = "Full (1)" })
  EC.Next_Look()
  EC.Previous_Look()
end

local LICENSED = { AC = 1, AS = "License Activated" }

T.section("A licensed install runs, and the gate never stops it")
load(LICENSED)
Properties["Look Control"] = "On Select"
OnPropertyChanged("Look Control")
H.addLook("Full")
H.addLook("Low")
tick(40)
T.eq("DC_X", DC_X, 1)
T.eq("still running after 400 s", gate:licensed(), true)
T.eq("Driver Status", Properties["Driver Status"], "Ready")
H.mark()
H.press()
T.eq("a press shows the next look", Variables["Look"], "Low")

T.section("A trial runs")
load({ AC = -720, AS = "Trial Running, 30 Days Remaining" })
tick(40)
T.eq("DC_X is the hours left", DC_X, -720)
T.eq("still running", gate:licensed(), true)
H.mark()
H.press()
T.eq("a press shows the next look", Variables["Look"], "Full")

T.section("Without a license the button runs five minutes, then shows the driver's icon")
load({ AC = 0, AS = "Invalid License" })
local shown = lastIcon()
T.truthy("at the load it shows its look", shown and shown ~= "")
tick(29)
T.eq("29 reads of 0: running", gate:licensed(), true)
T.eq("and still showing the look", lastIcon(), shown)
tick()
T.eq("the 30th read of 0 stops it", gate:licensed(), false)
T.eq("the button shows the driver's own icon", lastIcon(), OWN_ICON)
T.eq("Driver Status says why", Properties["Driver Status"], UNLICENSED)
T.eq("the looks are kept", #H.state().looks, 2)

T.section("Stopped, nothing changes the look")
H.mark()
tryEverything()
T.eq("presses and programming tell the proxy nothing", #H.proxy, 0)
T.eq("and fire nothing", #H.fired, 0)
T.eq("Show Look offers no looks", GCPL.Show_Look("Look"), {})
local refused = JSON:decode(H.tab("_SAVE_LOOK", H.lookFields("New")))
T.eq("the tab can't add a look", refused._command, "ERROR")
T.contains("and is told why", refused.message, UNLICENSED)
-- Each would fail on its own with these parameters, so only the reason tells the gate stopped it.
for _, command in ipairs({ "_PUT_IMAGE", "_PUT_PICTURE", "_DELETE_LOOK", "_ORDER_LOOKS", "_SHOW_LOOK" }) do
  local answer = JSON:decode(H.tab(command, { id = 1, look = 1, ids = { 2, 1 } }))
  T.eq(command .. " is refused", answer._command, "ERROR")
  T.contains(command .. " because there's no license", answer.message, UNLICENSED)
end
local search = JSON:decode(H.tab("_ICONIFY", { request = "r1", kind = "search", value = "battery" }))
T.eq("an icon search answers at once", search._command, "ICONIFY")
T.contains("with the reason, and asks Iconify nothing", search.error, UNLICENSED)
local fetched = #H.fetched
local fetch = JSON:decode(H.tab("_FETCH_PICTURE", { request = "r2", url = "http://camera.local/a.png" }))
T.eq("a web address answers at once", fetch._command, "FETCHED")
T.contains("with the reason", fetch.error, UNLICENSED)
T.eq("and is not fetched", #H.fetched, fetched)
local web = JSON:decode(H.tab("_ADD_WEB_PICTURE", { request = "r3", url = "http://camera.local/a.jpg", every = 300 }))
T.eq("a refreshing picture answers at once", web._command, "PICTURE_STORED")
T.contains("with the reason", web.error, UNLICENSED)
T.eq("and isn't marked as a failed fetch, so a copy stops on it", web.unfetched, nil)
T.eq("and is not fetched either", #H.fetched, fetched)
EC.Refresh_Web_Picture()
EC.Set_Web_Address({ Look = "Full (1)", Address = "http://camera.local/b.jpg" })
T.eq("Refresh Web Picture and Set Web Address fetch nothing", #H.fetched, fetched)
T.eq("Set Web Address offers no looks", GCPL.Set_Web_Address("Look"), {})
EC.Reset_Driver({ ["Are You Sure?"] = "Yes" })
T.eq("Reset Driver is turned away", #H.state().looks, 2)
T.eq("the proxy still hears nothing", #H.proxy, 0)
T.eq("the tab still reads the state", JSON:decode(H.tab("_GET_STATE"))._command, "STATE")
T.eq(
  "and the other Dynamic Buttons, whose own licenses decide a copy",
  JSON:decode(H.tab("_GET_BUTTONS"))._command,
  "BUTTONS"
)
H.tab("_SET_DRIVER", { property = "Log Level", value = "4 - Debug" })
T.eq("and still sets a property, as Composer's Properties tab can", Properties["Log Level"], "4 - Debug")
H.tab("_SET_DRIVER", { property = "Log Level", value = "3 - Info" })
tick(10)
T.eq("ten more reads leave it stopped", gate:licensed(), false)
T.eq("with the proxy told nothing more", #H.proxy, 0)

T.section("A purchase starts it at once")
local before = lastVersion() or 0
H.mark()
cloud.say(LICENSED)
T.eq("running without waiting for a read", gate:licensed(), true)
T.truthy("the look shows again", (lastIcon() or "") ~= "")
T.truthy("under a new address, so the app loads it again", (lastVersion() or 0) > before)
T.eq("Driver Status", Properties["Driver Status"], "Ready")
T.eq("no look event fires for the same look", #H.fired, 0)
H.mark()
H.press()
T.truthy("a press changes the look again", #H.proxy > 0)

T.section("A trial that expires stops it")
load({ AC = -1, AS = "Trial Running, 1 Hours Remaining" })
tick(2)
cloud.answer = { AC = 0, AS = "Trial Expired" }
tick(29)
T.eq("29 reads after the expiry: running", gate:licensed(), true)
tick()
T.eq("the 30th stops it", gate:licensed(), false)
T.eq("the button shows the driver's own icon", lastIcon(), OWN_ICON)

T.section("A Cloud driver update rides through")
load(LICENSED)
tick(3)
H.mark()
-- The old Cloud driver tells every client 0 as it goes, and the new one is quiet until it has loaded.
cloud.say({ AC = 0, AS = "Cloud driver removed, please install cloud driver." })
cloud.silent = true
tick(3)
T.eq("DC_X while it reloads", DC_X, 0)
cloud.silent = false
tick()
T.eq("DC_X once the new one answers", DC_X, 1)
tick(40)
T.eq("never stopped", gate:licensed(), true)
T.eq("the proxy never heard the driver's icon", lastIcon(), nil)

T.section("A Cloud driver gone quiet stops it, and an answer starts it")
load(LICENSED)
cloud.silent = true
local stopAt
for i = 1, 60 do
  tick()
  stopAt = stopAt or (not gate:licensed() and i or nil)
end
T.eq("stopped 30 reads after the client's sixth unanswered ping", stopAt, 35)
T.eq("the button shows the driver's own icon", lastIcon(), OWN_ICON)
cloud.silent = false
tick()
T.eq("the first answer starts it", gate:licensed(), true)
T.truthy("and shows the look", (lastIcon() or "") ~= "")

T.section("A build with no product yet stops at its load")
load(LICENSED, 0)
T.eq("the client is not loaded", package.loaded["cloud-client-byte"], nil)
T.eq("Cloud Status", Properties["Cloud Status"], "No DriverCentral product")
T.eq("stopped at once", gate:licensed(), false)
T.eq("the button shows the driver's own icon", lastIcon(), OWN_ICON)
T.eq("Driver Status", Properties["Driver Status"], UNLICENSED)

if gate and gate._timer then
  gate._timer:Cancel()
end
T.finish()
