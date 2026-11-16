--- The driver as the DriverCentral build packages it. The other suites load driver.lua as written, where
--- `--#ifdef` lines are comments and both builds' code runs, so a name only the GitHub build defines
--- still resolves there.
---
--- Run from the driver root:
---   make test
--- or:
---   ./test/run_test.sh test_dynamic_button_drivercentral_build.lua

local T = require("testlib")
local H = require("dynamic_button_harness")

local HERE = debug.getinfo(1, "S").source:match("^@(.*)/") or "."
local built = os.tmpname()

--- @param command string
local function run(command)
  local status = os.execute(command)
  assert(status == 0 or status == true, command)
end

run(string.format("cp %q %q", H.DRIVER, built))
run(
  string.format(
    "python3 -I -c 'import sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); "
      .. 'from preprocess import process_file; process_file(Path(sys.argv[2]), {"DRIVERCENTRAL"})\' %q %q',
    HERE .. "/../tools",
    built
  )
)

local f = assert(io.open(built, "r"))
local source = f:read("*a")
f:close()
T.falsy("the copy is the DriverCentral build", source:find("UpdateDrivers", 1, true))

H.DRIVER = built
local started, err = pcall(H.start)
os.remove(built)
T.check("starts", started, err)

H.tab("_GET_STATE")
T.truthy("the Button tab gets its state", H.state())

T.finish()
