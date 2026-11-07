-- Dave's reroll, through the same in-memory API main.lua gives gunsmith.lua.
local H = require("fake_game")

local AR = { damage = 100, critmult = 20, critchance = 10, rpm = 600, falloff = 50 }

local function setup(rows)
    local g = H.new_game({ name = "gunsmith" })
    if rows then g:seed_db(rows) end
    return g
end

local function total(t) local n = 0; for _, v in pairs(t) do n = n + v end; return n end

test("reroll is refused below level 5", function()
    local g = setup()
    local w = g:add_weapon({ name = "M2010", stats = AR })
    g:boot(); w:equip():kill(H.total_xp_to(4))
    local okReroll = g.gunsmith.Reroll(w.uid)
    eq(okReroll, false)
end)

test("reroll is refused for a weapon that is not in your hands", function()
    local g = setup()
    local a = g:add_weapon({ name = "M2010", stats = AR })
    local b = g:add_weapon({ name = "BlackOpsUSP", container = "CSidearm", stats = { damage = 26, critchance = 11 } })
    g:boot()
    a:equip():kill(H.total_xp_to(8))
    b:equip()
    eq(g.gunsmith.Reroll(a.uid), false)
end)

test("reroll redistributes upgrades but keeps level, XP, kills and the total", function()
    local g = setup()
    local w = g:add_weapon({ name = "M2010", stats = AR })
    g:boot(); w:equip():kill(H.total_xp_to(10) + 25)
    local before = w:record()
    local okReroll, msg = g.gunsmith.Reroll(w.uid)
    eq(okReroll, true, "reroll result (" .. tostring(msg) .. ")")
    local after = w:record()
    eq(after.level, before.level); near(after.xp, before.xp); eq(after.kills, before.kills)
    eq(total(after.upgrades), total(before.upgrades), "same number of upgrades")
    -- default milestones in play at L10: Proven I damage +2%, Proven II falloff +3%
    local P2, D = H.progression({ Milestones = {
        { level = 5, bonus_type = "DamagePercent", value = 2 }, { level = 10, bonus_type = "FalloffPercent", value = 3 } } })
    for key, base in pairs(AR) do
        near(w:stat(key), P2.StatTarget(D[key], base, after.upgrades[key], after), key .. " live value follows new distribution")
    end
end)

test("rerolling an over-capped legacy weapon drops the wasted upgrades", function()
    -- Like the Crusher in the RC2 data.db: 13 RPM upgrades and 10 crit
    -- multiplier upgrades where fewer reach the cap.
    local uid = "EBB06EB4-4BF6-B29F-1C9F-88B16FC42EDE"
    local g = setup({ { uid = uid, weapon = "Crusher", level = 44, xp = 2250, kills = 384, last_upgrade = "critmult",
        bases = { damage = 96.7572, critmult = 27, critchance = 19, rpm = 1017.167868, falloff = 85.833 },
        upgrades = { damage = 6, critmult = 10, critchance = 6, rpm = 13, falloff = 8 } } })
    local w = g:add_weapon({ uid = uid, name = "Crusher", stats = { damage = 96.7572, critmult = 27, critchance = 19, rpm = 1017.167868, falloff = 85.833 } })
    g:boot(); w:equip():hit()
    eq(g.gunsmith.Reroll(uid), true)
    local r = w:record()
    local P, D = H.progression({ Milestones = {
        { level = 15, bonus_type = "CriticalMultiplierPoints", value = 2 }, { level = 20, bonus_type = "RPMPercent", value = 3 },
        { level = 40, bonus_type = "RPMPercent", value = 4 }, { level = 45, bonus_type = "CriticalMultiplierPoints", value = 2 },
        { level = 5, bonus_type = "DamagePercent", value = 2 }, { level = 30, bonus_type = "DamagePercent", value = 3 },
        { level = 10, bonus_type = "FalloffPercent", value = 3 }, { level = 35, bonus_type = "FalloffPercent", value = 4 },
        { level = 25, bonus_type = "CriticalChancePoints", value = 1 } } })
    ok(total(r.upgrades) <= 43, "no more than the original 43 rolls")
    for key in pairs(r.upgrades) do
        if r.upgrades[key] > 0 then
            local d = D[key]
            local a = P.StatTarget(d, r.bases[key], r.upgrades[key] - 1, r)
            local b = P.StatTarget(d, r.bases[key], r.upgrades[key], r)
            ok(b > a, key .. ": last roll was wasted on a capped stat")
        end
    end
end)
