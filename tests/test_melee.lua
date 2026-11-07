-- Melee progression (Scripts/melee/melee_progression.lua): melee kills, XP,
-- level-ups, stat writes (including the roll range), stamina cost going down,
-- milestones, attack speed, caps and melee.db.
local H = require("fake_game")

local MACHETE = { meleedamage = { 34, 36 }, staminadrain = 8, critchance = 5, critmult = 20 }

local function setup(cfg, extra)
    local g = H.new_game({ name = "melee", config = cfg })
    local m = g:add_weapon({ name = "Machete", container = "CMelee", melee = true, stats = MACHETE })
    local gun
    if extra then gun = g:add_weapon({ name = "M2010", stats = { damage = 100, critmult = 20 } }) end
    g:boot()
    m:equip()
    return g, m, gun
end

local function level_to(m, level)
    local r = m:record()
    local have = r and H.total_xp_to(r.level) + r.xp or 0
    m:melee_kill(H.total_xp_to(level) - have)
end

test("a melee kill gives the melee weapon XP", function()
    local g, m = setup()
    m:melee_kill(60)
    local r = m:record()
    ok(r ~= nil, "melee.db record created")
    eq(r.kills, 1); near(r.xp, 60); eq(r.level, 1)
    near(r.bases.meleedamage, 34, "base melee damage captured")
    near(r.maxes.meleedamage, 36, "base upper end captured")
end)

test("melee kills never touch firearm data.db", function()
    local g, m = setup()
    m:melee_kill(500)
    eq(next(g:db_records()), nil, "data.db has no records")
end)

test("a hit that does not kill gives no XP", function()
    local g, m = setup()
    m:swing_hit()
    eq(m:record().kills, 0)
    eq(m:record().xp, 0)
end)

test("a firearm kill is not credited to the melee weapon", function()
    local g, m, gun = setup(nil, true)
    gun:equip():kill(60)
    -- the melee weapon then hits the same corpse area / another zombie
    m:equip():swing_hit()
    eq(m:record().kills, 0, "melee not credited")
    eq(gun:record().kills, 1, "gun credited")
end)

test("a melee level-up raises one stat and shows a toast", function()
    local g, m = setup({ MeleeMilestones = { Enabled = "false" } })
    level_to(m, 2)
    local a = g:melee_awarded()
    eq(#a, 1)
    local expected = ({ meleedamage = 34.68, staminadrain = 7.76, critchance = 6, critmult = 22 })[a[1].key]
    near(m:stat(a[1].key), expected, a[1].key)
    eq(#g.toasts, 1)
    ok(g.toasts[1]:find("Machete", 1, true), "toast: " .. tostring(g.toasts[1]))
end)

test("melee damage upgrades keep the roll range (upper end scaled too)", function()
    local g, m = setup({ MeleeStatUpgrades = { StaminaDrainPercent = 0, CriticalChancePoints = 0, CriticalMultiplierPoints = 0 },
        MeleeMilestones = { Enabled = "false" } })
    level_to(m, 4) -- 3 upgrades, only melee damage can move
    local n = m:record().upgrades.meleedamage
    eq(n, 3)
    near(m:stat("meleedamage"), 34 * 1.02 ^ 3, "lower end")
    near(m:stat_max("meleedamage"), 36 * 1.02 ^ 3, "upper end restored after UpdateStatByUID flattened it")
end)

test("stamina cost goes DOWN with upgrades and never below MinStaminaDrain", function()
    local g, m = setup({ Melee = { MinStaminaDrain = 6 },
        MeleeStatUpgrades = { MeleeDamagePercent = 0, CriticalChancePoints = 0, CriticalMultiplierPoints = 0, StaminaDrainPercent = 10 },
        MeleeCaps = { StaminaDrainPercent = 90 }, MeleeMilestones = { Enabled = "false" } })
    level_to(m, 2)
    near(m:stat("staminadrain"), 7.2, "8 - 10%")
    level_to(m, 10)
    near(m:stat("staminadrain"), 6, "floored at MinStaminaDrain")
end)

test("reaching a melee milestone applies its bonus", function()
    local g, m = setup({ MeleeStatUpgrades = { MeleeDamagePercent = 0 } })
    level_to(m, 4)
    near(m:stat("meleedamage"), 34, "no milestone at L4")
    level_to(m, 5) -- Scrapper I: melee damage +2%
    ok(g:has_log("MELEE MILESTONE REACHED"), "logged")
    near(m:stat("meleedamage"), 34 * 1.02)
end)

test("attack speed milestones speed up swings from the captured defaults", function()
    local g, m = setup()
    level_to(m, 9)
    near(m:swing().SwingSpeed, 1.0, "no attack speed before L10")
    level_to(m, 10) -- Scrapper II: +5%
    near(m:swing().SwingSpeed, 1.05, "swing speed +5%")
    near(m:swing().DelayBetweenSwings, 0.57, "delay -5%")
    level_to(m, 25) -- Brawler II: +10% total
    m:swing_hit()
    near(m:swing().SwingSpeed, 1.10, "+10%, not compounded")
end)

test("attack speed is capped by [MeleeCaps] AttackSpeedPercent", function()
    local g, m = setup({ MeleeCaps = { AttackSpeedPercent = 7 } })
    level_to(m, 50)
    near(m:swing().SwingSpeed, 1.07)
end)

test("melee stats stay within caps up to max level, with no wasted upgrades", function()
    local g, m = setup()
    level_to(m, 50)
    local r = m:record()
    eq(r.level, 50)
    ok(m:stat("meleedamage") <= 34 * 1.30 + 1e-6, "melee damage within +30%")
    ok(m:stat("staminadrain") >= 8 * 0.70 - 1e-6, "stamina within -30%")
    ok(m:stat("critchance") <= 5 + 15 + 1e-6, "crit chance within +15")
    ok(m:stat("critmult") <= 20 + 20 + 1e-6, "crit multiplier within +20")
    local stored = 0
    for _, n in pairs(r.upgrades) do stored = stored + n end
    eq(stored, #g:melee_awarded(), "stored = awarded")
    eq(g:log_count("MELEE UPGRADE SKIPPED") + stored, 49, "every level-up either upgraded or was skipped as capped")
end)

test("melee progress survives a restart and is re-applied on the first hit", function()
    local g, m = setup()
    level_to(m, 12)
    local before = { dmg = m:stat("meleedamage"), max = m:stat_max("meleedamage"), stam = m:stat("staminadrain"), cm = m:stat("critmult") }
    local g2 = g:restart()
    local m2 = g2.weapons[1]
    near(m2:stat("meleedamage"), 34, "rebuilt weapon starts from original")
    m2:equip():swing_hit()
    near(m2:stat("meleedamage"), before.dmg, "melee damage restored")
    near(m2:stat_max("meleedamage"), before.max, "upper end restored")
    near(m2:stat("staminadrain"), before.stam, "stamina restored")
    near(m2:stat("critmult"), before.cm, "crit multiplier restored")
    near(m2:swing().SwingSpeed, 1.05, "attack speed re-applied")
    eq(m2:record().level, 12)
end)

test("[Melee] Enabled=false turns melee progression off", function()
    local g, m = setup({ Melee = { Enabled = "false" } })
    m:melee_kill(500)
    eq(m:record(), nil, "no melee record")
end)

test("F8 shows the melee weapon's level, rank and stats", function()
    local g, m = setup()
    level_to(m, 12)
    local st = g:f8_state()
    eq(st.status, nil, "no 'no firearm progression' status")
    eq(st.weapon, "Machete"); eq(st.level, 12)
    eq(st.rank, "Scrapper II"); eq(st.next_rank, "Scrapper III"); eq(st.next_level, 15)
    local byRow = {}
    for _, s in ipairs(st.stats) do byRow[s.row] = s end
    local r = m:record()
    eq(byRow.damage.key, "meleedamage"); eq(byRow.damage.base, "34")
    eq(byRow.rpm.key, "staminadrain"); eq(byRow.rpm.base, "8")
    eq(byRow.critchance.key, "critchance"); eq(byRow.critmult.key, "critmult")
    eq(byRow.falloff.key, "attackspeed"); eq(byRow.falloff.current, "105%"); eq(byRow.falloff.bonus, "+5%")
    if (r.upgrades.staminadrain or 0) > 0 then
        ok(tostring(byRow.rpm.bonus):sub(1, 1) == "-", "stamina bonus shown as a reduction: " .. tostring(byRow.rpm.bonus))
    end
    eq(st.row_labels.damage, "Melee Dmg"); eq(st.row_labels.rpm, "Stamina"); eq(st.row_labels.falloff, "Attack Speed")
end)

test("F8 names an attack speed milestone as the next bonus", function()
    local g, m = setup()
    level_to(m, 5)
    local st = g:f8_state()
    eq(st.next_level, 10)
    eq(st.next_bonus, "Attack Speed +5%")
end)

test("F8 shows a fresh melee weapon at level 1 before its first kill", function()
    local g, m = setup()
    local st = g:f8_state()
    eq(st.status, nil); eq(st.level, 1); eq(st.xp_percent, 0)
    eq(st.row_labels.damage, "Melee Dmg")
end)

test("F8 goes back to firearm labels when a gun is in hand", function()
    local g, m, gun = setup(nil, true)
    level_to(m, 3)
    gun:equip():kill(10)
    local st = g:f8_state()
    eq(st.row_labels, nil, "firearm rows keep their own labels")
    eq(st.stats[1].row, nil)
end)

test("hovering a levelled melee weapon shows upgraded stats and bonuses", function()
    local g, m = setup({ MeleeMilestones = { Enabled = "false" } })
    level_to(m, 12)
    local rows = m:hover()
    local r = m:record()
    for _, key in ipairs({ "meleedamage", "staminadrain", "critchance", "critmult" }) do
        if (r.upgrades[key] or 0) > 0 then
            ok(rows[key] ~= nil and rows[key]:find("(", 1, true), key .. " row rewritten with a bonus: " .. tostring(rows[key]))
        end
    end
    if (r.upgrades.staminadrain or 0) > 0 then
        ok(rows.staminadrain:find("(-", 1, true), "stamina bonus is a reduction: " .. rows.staminadrain)
    end
    ok(g:has_log("MELEE RECORD FOUND"), "melee record used")
    ok(not g:has_log("RECORD NOT FOUND"), "no record-not-found")
end)

test("hovering a melee weapon with no kills leaves the tooltip alone", function()
    local g, m = setup()
    local rows = m:hover()
    eq(next(rows), nil, "no rows rewritten")
end)

test("firearm tooltips are unchanged by melee support", function()
    local g, m, gun = setup(nil, true)
    gun:equip()
    gun:kill(H.total_xp_to(3))
    local rows = gun:hover()
    local any = false
    for key, text in pairs(rows) do any = true; ok(not text:find("%.%d"), key .. " stays whole: " .. text) end
    ok(any, "firearm rows rewritten")
end)
