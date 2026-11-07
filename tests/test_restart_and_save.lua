-- Progress survives a game restart, and stats are rebuilt from data.db.
local H = require("fake_game")

local AR = { damage = 100, critmult = 20, critchance = 10, rpm = 600, falloff = 50 }

test("progress is saved to data.db after every kill", function()
    local g = H.new_game({ name = "restart" })
    local w = g:add_weapon({ name = "M2010", stats = AR })
    g:boot(); w:equip()
    w:kill(40)
    near(w:record().xp, 40)
    w:kill(40)
    near(w:record().xp, 80)
    eq(w:record().kills, 2)
end)

test("after a restart the first shot re-applies saved upgrades to the rebuilt weapon", function()
    local g = H.new_game({ name = "restart" })
    local w = g:add_weapon({ name = "M2010", stats = AR })
    g:boot(); w:equip()
    w:kill(H.total_xp_to(12))
    local before = {}
    for k in pairs(AR) do before[k] = w:stat(k) end
    local saved = w:record()

    local g2 = g:restart()
    local w2 = g2.weapons[1]
    for k, v in pairs(AR) do near(w2:stat(k), v, k .. " is back to original before the mod resolves it") end
    w2:equip():hit()
    for k, v in pairs(before) do near(w2:stat(k), v, k .. " restored") end
    local r = w2:record()
    eq(r.level, saved.level); near(r.xp, saved.xp); eq(r.kills, saved.kills)
    near(r.bases.damage, 100, "bases not re-captured from boosted stats")
end)

test("an empty data.db after a crash is recovered from data.db.bak", function()
    local g = H.new_game({ name = "restart" })
    local w = g:add_weapon({ name = "M2010", stats = AR })
    g:boot(); w:equip()
    w:kill(H.total_xp_to(6)); w:kill(10) -- second save rotates the L6 state into .bak
    local level = w:record().level

    H.write_file(g:db_path(), "") -- simulate a crash that truncated data.db
    local g2 = g:restart()
    ok(g2:has_log("DATABASE RECOVERY"), "recovery logged")
    local w2 = g2.weapons[1]
    w2:equip():hit()
    eq(w2:record().level, level, "level kept")
end)
