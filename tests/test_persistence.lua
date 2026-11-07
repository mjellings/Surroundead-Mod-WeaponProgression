-- data.db load/save safety (core/persistence.lua), on files in tests/.sandbox.
local H = require("fake_game")

local DIR = H.SANDBOX_ROOT .. "/persistence"
local DB = DIR .. "/data.db"

local SAMPLE = table.concat({
    "# WeaponProgression data.db v2",
    "# uid\\tlevel\\txp\\tkills\\tweapon\\tlast_upgrade\\tbase_damage\\tup_damage\\tbase_critmult\\tup_critmult\\tbase_critchance\\tup_critchance\\tbase_rpm\\tup_rpm\\tbase_falloff\\tup_falloff\\tpending_rewards",
    "0A0AA4EB-4044-8CB2-01C0-AD8FC6FF1F70\t15\t2.33172397017506\t43\tM2010\tdamage\t155\t4\t23\t4\t24\t1\t\t0\t184\t5\t0",
    "376E44F3-4097-97BF-8E42-FFA4EA3457A3\t4\t190.867549623549\t3\tBlackOpsUSP\tcritchance\t26.52\t1\t23\t0\t11\t1\t365.16\t0\t26\t1\t0",
    "55D39D69-4374-0309-4F31-B89792109396\t7\t369.662549628317\t17\tHuntingRifle\tcritchance\t88.74\t1\t22\t1\t13\t3\t\t0\t93.84\t1\t0",
    "EBB06EB4-4BF6-B29F-1C9F-88B16FC42EDE\t44\t2250\t384\tCrusher\tcritmult\t96.7572\t6\t27\t10\t19\t6\t1017.167868\t13\t85.833\t8\t0",
}, "\n") .. "\n"

local function fresh()
    H.mkdir(H.SANDBOX_ROOT); H.mkdir(DIR)
    for _, f in ipairs({ DB, DB .. ".bak", DB .. ".tmp" }) do os.remove(f) end
    return dofile(H.SCRIPTS_DIR .. "/core/persistence.lua")
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function quiet() end

test("loads every record and round-trips values exactly", function()
    local P = fresh(); H.write_file(DB, SAMPLE)
    local r = P.Load({ DB }, quiet)
    eq(count(r), 4)
    ok(P.Save(r, quiet), "save")
    local c = dofile(H.SCRIPTS_DIR .. "/core/persistence.lua").Load({ DB }, quiet)["EBB06EB4-4BF6-B29F-1C9F-88B16FC42EDE"]
    eq(c.level, 44); eq(c.upgrades.rpm, 13); near(c.bases.rpm, 1017.167868)
end)

test("a save keeps the previous file as data.db.bak", function()
    local P = fresh(); H.write_file(DB, SAMPLE)
    P.Save(P.Load({ DB }, quiet), quiet)
    eq(H.read_file(DB .. ".bak"), SAMPLE)
end)

test("an empty data.db falls back to data.db.bak", function()
    local P = fresh(); H.write_file(DB, ""); H.write_file(DB .. ".bak", SAMPLE)
    local logs = {}
    eq(count(P.Load({ DB }, function(m) logs[#logs + 1] = m end)), 4)
    ok(table.concat(logs, "\n"):find("DATABASE RECOVERY", 1, true), "recovery logged")
end)

test("a header-only (truncated) data.db falls back to data.db.bak", function()
    local P = fresh(); H.write_file(DB, "# WeaponProgression data.db v2\n"); H.write_file(DB .. ".bak", SAMPLE)
    eq(count(P.Load({ DB }, quiet)), 4)
end)

test("a missing data.db is restored from data.db.bak", function()
    local P = fresh(); H.write_file(DB .. ".bak", SAMPLE)
    eq(count(P.Load({ DB }, quiet)), 4)
end)

test("saving fewer records than were loaded is refused and touches nothing", function()
    local P = fresh(); H.write_file(DB, SAMPLE); H.write_file(DB .. ".bak", SAMPLE)
    P.Load({ DB }, quiet)
    eq(P.Save({}, quiet), false)
    eq(H.read_file(DB), SAMPLE); eq(H.read_file(DB .. ".bak"), SAMPLE)
end)

test("a failed write leaves data.db untouched and removes the temp file", function()
    local P = fresh(); H.write_file(DB, SAMPLE)
    local r = P.Load({ DB }, quiet)
    local realOpen = io.open
    io.open = function(p, m)
        if tostring(p):match("%.tmp$") and m == "w" then
            local h = realOpen(p, m)
            return setmetatable({}, { __index = {
                write = function() return nil, "No space left on device" end,
                close = function() return h:close() end } })
        end
        return realOpen(p, m)
    end
    local saved = P.Save(r, quiet)
    io.open = realOpen
    eq(saved, false)
    eq(H.read_file(DB), SAMPLE)
    eq(H.exists(DB .. ".tmp"), false)
end)

test("a fresh install creates data.db and saves the first weapon", function()
    local P = fresh()
    local r = P.Load({ DB }, quiet)
    eq(count(r), 0)
    r.A = { level = 2, xp = 1, kills = 1, weapon = "Y", bases = { damage = 10 }, upgrades = { damage = 1 } }
    ok(P.Save(r, quiet))
    eq(count(dofile(H.SCRIPTS_DIR .. "/core/persistence.lua").Load({ DB }, quiet)), 1)
end)
