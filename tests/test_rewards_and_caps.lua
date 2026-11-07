-- What a level-up does to the weapon: live stat writes, toasts, milestones,
-- caps, and pending rewards.
local H = require("fake_game")

local AR = { damage = 100, critmult = 20, critchance = 10, rpm = 600, falloff = 50 }

local function setup(cfg, stats, name)
    local g = H.new_game({ name = "rewards", config = cfg })
    local w = g:add_weapon({ name = name or "M2010", stats = stats or AR })
    g:boot()
    w:equip()
    return g, w
end

local function level_to(w, level)
    local r = w:record()
    local have = r and H.total_xp_to(r.level) + r.xp or 0
    w:kill(H.total_xp_to(level) - have)
end

test("a level-up raises one live stat by the configured amount", function()
    local g, w = setup({ Milestones = { Enabled = "false" } })
    level_to(w, 2)
    local a = g:awarded()
    eq(#a, 1)
    local key = a[1].key
    local expected = ({ damage = 102, critmult = 22, critchance = 11, rpm = 612, falloff = 51 })[key]
    near(w:stat(key), expected, key .. " after one upgrade")
    for k, v in pairs(AR) do if k ~= key then near(w:stat(k), v, k .. " unchanged") end end
end)

test("the level-up toast names the weapon, level and reward", function()
    local g, w = setup({ Milestones = { Enabled = "false" } })
    level_to(w, 2)
    eq(#g.toasts, 1)
    local label = ({ damage = "Damage +2%", critmult = "Critical Multiplier +2", critchance = "Critical Chance +1",
        rpm = "RPM +2%", falloff = "Damage Falloff +2%" })[g:awarded()[1].key]
    ok(g.toasts[1]:find("M2010", 1, true) and g.toasts[1]:find("2", 1, true) and g.toasts[1]:find(label, 1, true),
        "toast was: " .. tostring(g.toasts[1]) .. " (expected to mention " .. label .. ")")
end)

test("the same stat is never rolled twice in a row", function()
    local g, w = setup()
    level_to(w, 40)
    local a = g:awarded()
    eq(#a, 39)
    for i = 2, #a do ok(a[i].key ~= a[i - 1].key, "L" .. a[i].level .. " repeated " .. a[i].key) end
end)

test("a weapon without RPM never gets an RPM upgrade", function()
    local g, w = setup(nil, { damage = 88.74, critmult = 22, critchance = 13, falloff = 93.84 }, "HuntingRifle")
    level_to(w, 30)
    for _, a in ipairs(g:awarded()) do ok(a.key ~= "rpm", "rolled RPM at L" .. a.level) end
end)

test("reaching a milestone applies its bonus to the live weapon", function()
    -- Only milestone: Level5 damage +10%. No ordinary rewards can touch damage.
    local g, w = setup({ StatUpgrades = { DamagePercent = 0 }, Milestones = {
        Level5 = "Proven I|DamagePercent|10", Level10 = "Disabled", Level15 = "Disabled", Level20 = "Disabled",
        Level25 = "Disabled", Level30 = "Disabled", Level35 = "Disabled", Level40 = "Disabled", Level45 = "Disabled",
        Level50 = "Disabled", Level55 = "Disabled", Level60 = "Disabled", Level65 = "Disabled", Level70 = "Disabled", Level75 = "Disabled" } })
    level_to(w, 4)
    near(w:stat("damage"), 100, "no milestone yet at L4")
    level_to(w, 5)
    ok(g:has_log("MILESTONE REACHED"), "milestone logged")
    near(w:stat("damage"), 110, "damage +10% at L5")
end)

test("live stats never go past their caps, all the way to level 100", function()
    local g, w = setup()
    level_to(w, 100)
    eq(w:record().level, 100)
    near(w:stat("damage"), 130, "damage at +30% cap")
    near(w:stat("rpm"), 750, "RPM at +25% cap")
    near(w:stat("falloff"), 62.5, "falloff at +25% cap")
    near(w:stat("critchance"), 25, "crit chance at +15 cap")
    near(w:stat("critmult"), 40, "crit multiplier at +20 cap")
end)

test("every awarded upgrade actually raises a stat (none wasted on caps)", function()
    local g, w = setup()
    local P = H.progression()
    level_to(w, 100)
    local r = w:record()
    local useful = 0
    for _, a in ipairs(g:awarded()) do useful = useful + 1 end
    local stored = 0
    for _, n in pairs(r.upgrades) do stored = stored + n end
    eq(stored, useful, "stored upgrades = awarded upgrades")
    ok(useful < 99, "some level-ups were skipped once capped (awarded " .. useful .. ")")
    eq(g:log_count("STAT UPGRADE SKIPPED"), 99 - useful, "the rest were logged as skipped")
end)

test("level-ups after everything is capped give no toast and bank nothing", function()
    local g, w = setup()
    level_to(w, 100)
    local r = w:record()
    eq(r.pending_rewards, 0, "no pending rewards piled up")
    eq(#g.toasts, #g:awarded(), "one toast per real upgrade only")
end)

test("rewards earned before stats were known are paid out on the next shot", function()
    local g = H.new_game({ name = "rewards" })
    local uid = "AAAAAAAA-0000-0000-0000-000000000001"
    g:seed_db({ { uid = uid, weapon = "M2010", level = 3, bases = { damage = 100, critmult = 20 },
        upgrades = { damage = 0, critmult = 0 }, pending_rewards = 2 } })
    local w = g:add_weapon({ uid = uid, name = "M2010", stats = { damage = 100, critmult = 20 } })
    g:boot()
    w:equip():hit()
    local r = w:record()
    eq(r.pending_rewards, 0)
    eq((r.upgrades.damage or 0) + (r.upgrades.critmult or 0), 2, "two upgrades stored")
    near(w:stat("damage"), 100 * 1.02 ^ r.upgrades.damage, "live damage matches")
    near(w:stat("critmult"), 20 + 2 * r.upgrades.critmult, "live crit multiplier matches")
end)
