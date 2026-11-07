-- Pure progression maths (firearms/progression.lua): XP curve, stat targets,
-- milestones, caps and which stat a level-up may pick. No game needed.
local H = require("fake_game")

local function ms(level, bonus, value, fallback)
    return { level = level, rank = "R" .. level, bonus_type = bonus, value = value, fallback_type = fallback }
end

test("XP needed per level follows BaseLevelXP + (level-1) * XPIncreasePerLevel", function()
    local P = H.progression()
    eq(P.XPRequired(1), 100, "L1 -> L2")
    eq(P.XPRequired(2), 150, "L2 -> L3")
    eq(P.XPRequired(10), 550, "L10 -> L11")
end)

test("[LevelThresholds] override replaces the formula for that destination level", function()
    local P = H.progression({ LevelThresholds = { [5] = 250 } })
    eq(P.XPRequired(4), 250, "L4 -> L5 uses Level5=250")
    eq(P.XPRequired(5), 300, "L5 -> L6 back to formula")
end)

test("percent stats compound per upgrade from the captured base", function()
    local P, D = H.progression()
    local r = { level = 1, bases = { damage = 100 }, upgrades = {} }
    near(P.StatTarget(D.damage, 100, 0, r), 100, "no upgrades")
    near(P.StatTarget(D.damage, 100, 1, r), 102, "1 upgrade")
    near(P.StatTarget(D.damage, 100, 3, r), 100 * 1.02 ^ 3, "3 upgrades")
end)

test("point stats add a flat amount per upgrade", function()
    local P, D = H.progression()
    local r = { level = 1, bases = { critmult = 20 }, upgrades = {} }
    near(P.StatTarget(D.critmult, 20, 4, r), 28, "4 x 2 points")
end)

test("milestone percent bonus is added from base, not compounded", function()
    local P, D = H.progression({ Milestones = { ms(5, "DamagePercent", 2) } })
    local r = { level = 5, bases = { damage = 100 }, upgrades = {} }
    near(P.StatTarget(D.damage, 100, 1, r), 102 + 2, "1 upgrade (+2%) + milestone (+2 from base)")
    r.level = 4
    near(P.StatTarget(D.damage, 100, 1, r), 102, "milestone not yet reached at L4")
end)

test("milestones are disabled with [Milestones] Enabled=false", function()
    local P, D = H.progression({ MilestonesEnabled = false, Milestones = { ms(5, "DamagePercent", 2) } })
    local r = { level = 50, bases = { damage = 100 }, upgrades = {} }
    near(P.StatTarget(D.damage, 100, 0, r), 100)
end)

test("RPM milestone falls back to FalloffPercent on a weapon with no RPM stat", function()
    local P, D = H.progression({ Milestones = { ms(20, "RPMPercent", 3, "FalloffPercent") } })
    local r = { level = 20, bases = { falloff = 50 }, upgrades = {} }
    near(P.StatTarget(D.falloff, 50, 0, r), 51.5, "falloff +3% of 50")
    local withRpm = { level = 20, bases = { falloff = 50, rpm = 600 }, upgrades = {} }
    near(P.StatTarget(D.falloff, 50, 0, withRpm), 50, "weapon with RPM keeps falloff unchanged")
    near(P.StatTarget(D.rpm, 600, 0, withRpm), 618, "and gets RPM +3%")
end)

test("caps clamp upgrades and milestones combined", function()
    local P, D = H.progression({ Milestones = { ms(5, "DamagePercent", 10) } })
    local r = { level = 5, bases = { damage = 100, critmult = 20 }, upgrades = {} }
    near(P.StatTarget(D.damage, 100, 50, r), 130, "damage capped at +30%")
    near(P.StatTarget(D.critmult, 20, 50, r), 40, "crit multiplier capped at +20 points")
end)

test("IsCapped is false while there is headroom and true once at the cap", function()
    local P, D = H.progression()
    local r = { level = 1, bases = { critmult = 20 }, upgrades = { critmult = 9 } }
    ok(not P.IsCapped(D.critmult, r), "9 x 2 = 18 of 20 points")
    r.upgrades.critmult = 10
    ok(P.IsCapped(D.critmult, r), "10 x 2 = 20 of 20 points")
    ok(P.IsCapped(D.damage, r), "a stat the weapon does not have counts as capped")
end)

test("ChooseUpgradeDef reports no_bases before any stat is captured", function()
    local P = H.progression()
    local def, why = P.ChooseUpgradeDef({ level = 2, bases = {}, upgrades = {} })
    eq(def, nil); eq(why, "no_bases")
end)

test("ChooseUpgradeDef never picks a capped stat", function()
    local P = H.progression()
    local r = { level = 30, bases = { critmult = 20, damage = 100 }, upgrades = { critmult = 10, damage = 0 }, last_upgrade = "" }
    for _ = 1, 100 do eq(P.ChooseUpgradeDef(r).key, "damage") end
end)

test("ChooseUpgradeDef reports capped when every stat is at its cap", function()
    local P = H.progression()
    local r = { level = 80, bases = { critmult = 20 }, upgrades = { critmult = 10 } }
    local def, why = P.ChooseUpgradeDef(r)
    eq(def, nil); eq(why, "capped")
end)

test("PreventConsecutiveSameStat avoids repeating the last stat", function()
    local P = H.progression()
    local r = { level = 3, bases = { critmult = 20, damage = 100 }, upgrades = {}, last_upgrade = "damage" }
    for _ = 1, 50 do eq(P.ChooseUpgradeDef(r).key, "critmult") end
end)

test("PreventConsecutiveSameStat gives way when only one stat has headroom", function()
    local P = H.progression()
    local r = { level = 3, bases = { critmult = 20, damage = 100 }, upgrades = { critmult = 10 }, last_upgrade = "damage" }
    eq(P.ChooseUpgradeDef(r).key, "damage")
end)
