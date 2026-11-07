-- Kill attribution, weapon XP and level-ups, driven through the real main.lua
-- via the same Blueprint hooks the game fires.
local H = require("fake_game")

local RIFLE = { damage = 88.74, critmult = 22, critchance = 13, falloff = 93.84 }

local function setup(cfg)
    local g = H.new_game({ name = "kills", config = cfg })
    local w = g:add_weapon({ name = "HuntingRifle", stats = RIFLE })
    g:boot()
    w:equip()
    return g, w
end

test("first shot captures the weapon's base stats into data.db", function()
    local g, w = setup()
    w:hit()
    local r = w:record()
    ok(r ~= nil, "record created")
    near(r.bases.damage, 88.74, "base damage")
    near(r.bases.falloff, 93.84, "base falloff")
    eq(r.bases.rpm, nil, "weapon has no RPM stat")
    eq(r.level, 1); eq(r.kills, 0, "a hit is not a kill")
end)

test("a kill gives weapon XP equal to the vanilla XP", function()
    local g, w = setup()
    w:kill(60)
    local r = w:record()
    eq(r.kills, 1); near(r.xp, 60); eq(r.level, 1)
end)

test("WeaponXPMultiplier scales the XP a kill gives", function()
    local g, w = setup({ Progression = { WeaponXPMultiplier = 2.5 } })
    w:kill(20)
    near(w:record().xp, 50)
end)

test("reaching the threshold levels up and carries the overflow", function()
    local g, w = setup()
    w:kill(60); w:kill(60)
    local r = w:record()
    eq(r.level, 2, "120 XP passes the 100 XP threshold")
    near(r.xp, 20, "20 XP carried over")
    eq(#g:awarded(), 1, "one stat upgrade")
end)

test("one huge kill can level up several times, one reward per level", function()
    local g, w = setup()
    w:kill(H.total_xp_to(5) + 10) -- 100 + 150 + 200 + 250 + 10
    local r = w:record()
    eq(r.level, 5); near(r.xp, 10)
    eq(#g:awarded(), 4)
    local total = 0
    for _, n in pairs(r.upgrades) do total = total + n end
    eq(total, 4, "four upgrades stored")
end)

test("damage to a different zombie than the one that died gives no XP", function()
    local g, w = setup()
    local zombie = H.uobject("BP_Zombie_C /Game/Maps/World.BP_Zombie_C_victim")
    g:fire("ADD_XP", H.uobject("LevellingComponent_C"), H.param(60), H.param(false), H.param(nil))
    g:fire("DEATH", zombie, H.param(nil), H.param(false))
    w:hit(H.uobject("BP_Zombie_C /Game/Maps/World.BP_Zombie_C_bystander"))
    eq(w:record().kills, 0)
end)

test("player XP from something else (no zombie death) gives the gun nothing", function()
    local g, w = setup()
    g:fire("ADD_XP", H.uobject("LevellingComponent_C"), H.param(500), H.param(false), H.param(nil))
    w:hit()
    eq(w:record().xp, 0)
end)

test("a duplicate damage event for the same kill is only counted once", function()
    local g, w = setup()
    w:kill(60)
    local zombie = H.uobject("BP_Zombie_C /Game/Maps/World.BP_Zombie_C_1")
    g:fire("SERVER_DAMAGE", w.pickup, H.param(false), H.param(zombie), H.param(nil))
    eq(w:record().kills, 1)
end)

test("at MaxLevel XP stops but kills keep counting", function()
    local g, w = setup({ Progression = { MaxLevel = 3 } })
    w:kill(H.total_xp_to(3) + 500)
    local r = w:record()
    eq(r.level, 3); eq(r.xp, 0)
    w:kill(100)
    r = w:record()
    eq(r.level, 3); eq(r.xp, 0); eq(r.kills, 2)
    eq(#g:awarded(), 2, "only the two real level-ups were rewarded")
end)

test("each weapon tracks its own progression", function()
    local g = H.new_game({ name = "kills" })
    local rifle = g:add_weapon({ name = "HuntingRifle", stats = RIFLE })
    local pistol = g:add_weapon({ name = "BlackOpsUSP", container = "CSidearm", stats = { damage = 26.52, critchance = 11, rpm = 365.16 } })
    g:boot()
    rifle:equip():kill(150)
    pistol:equip():kill(30)
    eq(rifle:record().level, 2); eq(rifle:record().kills, 1)
    eq(pistol:record().level, 1); near(pistol:record().xp, 30)
end)
