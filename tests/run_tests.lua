-- WeaponProgression offline tests.
--
-- Run from anywhere with Lua 5.4:
--     lua tests/run_tests.lua            (all tests)
--     lua tests/run_tests.lua milestone  (only tests whose name contains "milestone")
--
-- Set WP_TEST_VERBOSE=1 to echo the mod's log output while tests run.

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]+$") or "."
package.path = dir .. "/lib/?.lua;" .. package.path

local T = require("testlib")
_G.test, _G.eq, _G.near, _G.ok = T.test, T.eq, T.near, T.ok

local files = {
    "test_progression_rules.lua",
    "test_kills_and_levels.lua",
    "test_rewards_and_caps.lua",
    "test_restart_and_save.lua",
    "test_gunsmith.lua",
    "test_persistence.lua",
}

for _, f in ipairs(files) do
    T.current_file = f
    local chunk = assert(loadfile(dir .. "/" .. f))
    chunk()
end

local allPassed = T.run(arg[1])
os.exit(allPassed and 0 or 1)
