-- WeaponProgression offline test harness: a fake UE4SS + SurrounDead world.
--
-- Loads the REAL Scripts/main.lua (and every module it loads) inside a
-- sandboxed Lua environment where the UE4SS globals (RegisterHook,
-- ExecuteWithDelay, StaticFindObject, FindAllOf, ...) are replaced by fakes.
-- Tests then drive the mod through the same Blueprint hooks the game fires:
--
--   equip weapon -> GetEquipmentUID -> AddXP -> Zombie Death -> SERVER_DamageEvent
--
-- and observe the results the player would: live weapon stats changed through
-- UpdateStatByUID, level-up toasts, log lines, and data.db on disk.
--
-- Nothing here touches the real mod folder's config.ini or data.db: each game
-- session uses its own sandbox folder (tests/.sandbox/<name>/) for those files.

local H = {}

-- --------------------------------------------------------------------------
-- Paths / filesystem helpers (plain Lua, works on Windows and Linux)
-- --------------------------------------------------------------------------
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function this_dir()
    local src = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
    return src:match("^(.*)/[^/]+$") or "."
end

H.TESTS_DIR = this_dir():match("^(.*)/lib$") or "."
-- WP_MOD_ROOT lets you run these tests against another copy of the mod
-- (a folder containing Scripts/ and config.ini). Files there are only read.
H.MOD_ROOT = os.getenv("WP_MOD_ROOT") or H.TESTS_DIR:match("^(.*)/tests$") or (H.TESTS_DIR .. "/..")
H.SCRIPTS_DIR = H.MOD_ROOT .. "/Scripts"
H.SANDBOX_ROOT = H.TESTS_DIR .. "/.sandbox"

local function native(path)
    if IS_WINDOWS then return (path:gsub("/", "\\")) end
    return path
end

function H.mkdir(path)
    if IS_WINDOWS then
        os.execute('if not exist "' .. native(path) .. '" mkdir "' .. native(path) .. '" >nul 2>nul')
    else
        os.execute("mkdir -p '" .. path .. "' 2>/dev/null")
    end
end

function H.read_file(path)
    local f = io.open(path, "rb"); if not f then return nil end
    local s = f:read("a"); f:close(); return s
end

function H.write_file(path, text)
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(text); f:close()
end

function H.exists(path) local f = io.open(path, "rb"); if f then f:close(); return true end; return false end

-- --------------------------------------------------------------------------
-- Game constants the mod reads (mirrors main.lua FIELDS / STAT_DEFS)
-- --------------------------------------------------------------------------
local FIELDS = {
    stat_name = "STAT_NAME_13_8D9D8D5D48A145FB1BAD6E98C69D0A10",
    min_value = "MinValue_6_4B4822A7420F784740B6A58155973EE6",
    item_unique_id = "ItemUniqueID",
}

H.TAGS = {
    damage = "Jig.Stat.FirearmDamage",
    critmult = "Jig.Stat.CriticalHitMultiplier",
    critchance = "Jig.Stat.CriticalHitChance",
    rpm = "Jig.Stat.FirearmRPM",
    falloff = "Jig.Stat.DamageFallOff",
}

local SLOT_TAGS = {
    CPrimary = "Jig.PlayerSlot.PrimaryWeapon",
    CSecondary = "Jig.PlayerSlot.SecondaryWeapon",
    CSidearm = "Jig.PlayerSlot.SidearmWeapon",
}

-- --------------------------------------------------------------------------
-- Fake UObjects
-- --------------------------------------------------------------------------
local UObject = {}
UObject.__index = UObject
function UObject:IsValid() return self.__valid ~= false end
function UObject:GetFullName() return self.__name end

local function uobject(name, fields)
    local o = fields or {}
    o.__name = name
    return setmetatable(o, UObject)
end

-- UE4SS hook parameters are wrappers read with :get()
local function param(v) return { get = function() return v end } end

local function fname(s) return { ToString = function() return s end } end
local function gameplay_tag(s) return { TagName = fname(s) } end

local guidCounter = 0
local function new_guid()
    guidCounter = guidCounter + 1
    return string.format("%08X-%04X-%04X-%04X-%012X", 0x1000 + guidCounter, 0x4000, 0x8000, 0xA000, guidCounter)
end

-- --------------------------------------------------------------------------
-- Deterministic RNG so stat picks are reproducible run to run
-- --------------------------------------------------------------------------
local function make_math(seed)
    local m = {}
    for k, v in pairs(math) do m[k] = v end
    local state = seed or 12345
    local function nextf()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
    m.random = function(a, b)
        if a == nil then return nextf() end
        if b == nil then a, b = 1, a end
        return a + math.floor(nextf() * (b - a + 1))
    end
    m.randomseed = function() end -- main.lua seeds from os.time(); keep ours
    return m
end

-- --------------------------------------------------------------------------
-- Game session
-- --------------------------------------------------------------------------
local Game = {}
Game.__index = Game

-- opts:
--   name     sandbox folder name (keeps data.db between restarts)
--   config   table of { [Section] = { Key = value } } merged over the shipped config.ini,
--            or a string with the full config.ini text
--   seed     RNG seed
--   keep_db  true to keep an existing sandbox data.db (used by restart)
function H.new_game(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.name = opts.name or "default"
    self.dir = H.SANDBOX_ROOT .. "/" .. self.name
    self.seed = opts.seed or 12345
    self.config = opts.config
    self.logs, self.toasts, self.hooks, self.keybinds = {}, {}, {}, {}
    self.timers, self.now = {}, 0
    self.weapons, self.slots = {}, {}
    self.writes = {}
    H.mkdir(H.SANDBOX_ROOT); H.mkdir(self.dir)
    if not opts.keep_db then
        for _, f in ipairs({ "data.db", "data.db.bak", "data.db.tmp" }) do os.remove(self.dir .. "/" .. f) end
    end
    self:write_config()
    return self
end

local function merge_config(text, overrides)
    -- Replace/insert keys in an ini text, section by section.
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line:gsub("\r$", "") end
    for section, kv in pairs(overrides) do
        local start = nil
        for i, l in ipairs(lines) do if l:match("^%[" .. section:gsub("%W", "%%%0") .. "%]") then start = i break end end
        if start == nil then
            lines[#lines + 1] = "[" .. section .. "]"; start = #lines
        end
        for key, value in pairs(kv) do
            local done = false
            local i = start + 1
            while i <= #lines and not lines[i]:match("^%[") do
                if lines[i]:match("^%s*" .. key:gsub("%W", "%%%0") .. "%s*=") then
                    lines[i] = key .. "=" .. tostring(value); done = true; break
                end
                i = i + 1
            end
            if not done then table.insert(lines, start + 1, key .. "=" .. tostring(value)) end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function Game:write_config()
    local text
    if type(self.config) == "string" then
        text = self.config
    else
        text = assert(H.read_file(H.MOD_ROOT .. "/config.ini"), "config.ini not found next to Scripts/")
        if self.config then text = merge_config(text, self.config) end
    end
    H.write_file(self.dir .. "/config.ini", text)
end

function Game:db_path() return self.dir .. "/data.db" end

-- Build the fake UE4SS global environment the mod runs in.
function Game:make_env()
    local game = self
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.math = make_math(self.seed)

    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        local text = table.concat(parts, "\t"):gsub("\n$", "")
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            game.logs[#game.logs + 1] = (line:gsub("^%[WeaponProgression%] ", ""))
        end
        if os.getenv("WP_TEST_VERBOSE") then io.write("    | ", text, "\n") end
    end

    -- Module loading: Scripts/* comes from the real mod; the sandbox folder
    -- is only used for config.ini / data.db. Dave's gunsmith is replaced by a
    -- stub that captures the in-memory API main.lua hands to it.
    env.loadfile = function(path, mode, e)
        path = tostring(path):gsub("\\", "/")
        local rel = path:match("/Scripts/(.+)$")
        if rel == "gunsmith/gunsmith.lua" then
            return function()
                return { Init = function(callbacks) game.gunsmith = callbacks; return true end }
            end
        end
        local real = rel and (H.SCRIPTS_DIR .. "/" .. rel) or path
        return loadfile(real, mode or "t", e or env)
    end
    env.dofile = function(path) return assert(env.loadfile(path))() end
    env.require = function(name) error("require disabled in tests: " .. tostring(name)) end

    -- Timers / threads
    env.ExecuteWithDelay = function(ms, fn)
        game.timers[#game.timers + 1] = { at = game.now + (tonumber(ms) or 0), fn = fn }
    end
    env.ExecuteInGameThread = function(fn) fn() end
    env.ExecuteAsync = function(fn) fn() end
    env.LoopAsync = function() end

    -- Hooks / keys
    env.RegisterHook = function(path, cb)
        game.hooks[path] = cb
        return 1, 2
    end
    env.RegisterKeyBind = function(key, a, b)
        game.keybinds[key] = type(a) == "function" and a or b
    end
    env.Key = setmetatable({}, { __index = function(_, k) return k end })
    env.ModifierKey = env.Key
    env.FName = function(s) return fname(s) end
    env.FText = function(s) return { ToString = function() return s end } end
    env.StaticConstructObject = function() return nil end
    env.NotifyOnNewObject = function() end

    -- Engine libraries
    local guidLib = uobject("KismetGuidLibrary", {})
    function guidLib:Conv_GuidToString(guid)
        return { ToString = function() return guid.__guid end }
    end
    local textLib = uobject("KismetTextLibrary", {})
    function textLib:Conv_StringToText(s) return { __text = s, ToString = function() return s end } end
    local mathLib = uobject("KismetMathLibrary", {})
    function mathLib:LinearColor_White() return { R = 1, G = 1, B = 1, A = 1 } end
    local gameLib = uobject("GameFunctionLibrary", {})
    function gameLib:CreateNotificationUI(text)
        game.toasts[#game.toasts + 1] = text.__text
    end
    local statics = {
        ["/Script/Engine.Default__KismetGuidLibrary"] = guidLib,
        ["/Script/Engine.Default__KismetTextLibrary"] = textLib,
        ["/Script/Engine.Default__KismetMathLibrary"] = mathLib,
        ["/Game/Blueprints/GameFunctionLibrary.Default__GameFunctionLibrary_C"] = gameLib,
    }
    env.StaticFindObject = function(path) return statics[path] end

    -- Player + inventory component that performs stat writes
    local jig = uobject("BP_JigMultiplayer_C /Game/Player.BP_PlayerCharacter_C.BP_JigMultiplayer", {})
    function jig:UpdateStatByUID(slotUid, tagStruct, value)
        game:on_update_stat(slotUid, tagStruct, value)
    end
    local player = uobject("BP_PlayerCharacter_C /Game/Maps/World.BP_PlayerCharacter_C_0", { BP_JigMultiplayer = jig })
    env.FindFirstOf = function(class)
        if class == "BP_PlayerCharacter_C" then return player end
        return nil
    end
    env.FindAllOf = function(class)
        if class == "JSI_Slot_C" then
            local out = {}
            for _, s in ipairs(game.slots) do out[#out + 1] = s end
            return out
        end
        return nil
    end
    return env
end

-- Start the mod: run main.lua, then let the delayed hook registration finish.
function Game:boot()
    self.env = self:make_env()
    local mainPath = H.SCRIPTS_DIR .. "/main.lua"
    local src = assert(H.read_file(mainPath), "cannot read " .. mainPath)
    -- Chunk name points at the sandbox so main.lua's MOD_DIR (where it looks
    -- for config.ini and data.db) is the sandbox folder.
    local chunk = assert(load(src, "@" .. self.dir .. "/Scripts/main.lua", "t", self.env))
    chunk()
    self:run_timers(10 * 60 * 1000)
    assert(self.hooks[self:hook_path("SERVER_DAMAGE")], "core hooks never registered; see game.logs")
    return self
end

-- Simulate a full game restart: weapons go back to their original stats (as
-- SurrounDead rebuilds them), the mod reloads from the same sandbox data.db.
function Game:restart()
    local g = H.new_game({ name = self.name, config = self.config, seed = self.seed + 1, keep_db = true })
    for _, w in ipairs(self.weapons) do
        g:add_weapon({ uid = w.uid, name = w.name, container = w.container, stats = w.original })
    end
    return g:boot()
end

function Game:run_timers(budgetMs)
    local limit = self.now + (budgetMs or 60000)
    for _ = 1, 100000 do
        table.sort(self.timers, function(a, b) return a.at < b.at end)
        local t = self.timers[1]
        if t == nil or t.at > limit then break end
        table.remove(self.timers, 1)
        self.now = math.max(self.now, t.at)
        t.fn()
    end
end

local HOOK_PATHS = {
    GET_EQUIPMENT_UID = "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetEquipmentUID",
    SERVER_DAMAGE = "/Game/Inventory/Items/Pickups/Weapons/Firearms/BP_FirearmPickup.BP_FirearmPickup_C:SERVER_DamageEvent",
    ADD_XP = "/Game/Blueprints/Components/LevellingComponent.LevellingComponent_C:AddXP",
    DEATH = "/Game/AI/Zombies/BP_MasterZombie.BP_MasterZombie_C:Death",
    JIG_TRY_ADD = "/Game/JigSInventory/Jigsaw/Components/BP_JigComponent.BP_JigComponent_C:JigTryAddItemSomewhere",
    GET_ACTIVE_WEAPON = "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetActiveWeapon",
    GET_ACTIVE_SLOT = "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetActiveWeaponSlot",
    GET_EQUIPPED_REF = "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:GetEquippedItemRef",
}
function Game:hook_path(key) return assert(HOOK_PATHS[key], key) end
function Game:fire(key, ...)
    local cb = assert(self.hooks[self:hook_path(key)], "hook not registered: " .. key)
    cb(...)
end

-- --------------------------------------------------------------------------
-- Weapons
-- --------------------------------------------------------------------------
local Weapon = {}
Weapon.__index = Weapon

-- opts: name ("HuntingRifle"), container ("CPrimary"), stats { damage=, critmult=,
-- critchance=, rpm=, falloff= } (omit a stat the weapon does not have), uid
function Game:add_weapon(opts)
    local w = setmetatable({}, Weapon)
    w.game = self
    w.name = opts.name or "HuntingRifle"
    w.container = opts.container or "CPrimary"
    w.uid = opts.uid or new_guid()
    w.original = {}
    for k, v in pairs(opts.stats or {}) do w.original[k] = v end
    w.guid = { __guid = w.uid }
    local statArr = {}
    for _, key in ipairs({ "damage", "critmult", "critchance", "rpm", "falloff" }) do
        local v = w.original[key]
        if v ~= nil then
            statArr[#statArr + 1] = { [FIELDS.stat_name] = gameplay_tag(H.TAGS[key]), [FIELDS.min_value] = v, __key = key }
        end
    end
    local index = #self.slots
    w.slot = uobject(
        string.format("JSI_Slot_C /Game/UI/WBP_Inventory.WBP_Inventory_C_0.WidgetTree.%s.WidgetTree_%d.JSI_Slot_C_%d", w.container, index, index),
        { [FIELDS.item_unique_id] = w.guid, ItemStats = statArr })
    w.pickup = uobject(string.format("BP_%sPickup_C /Game/Maps/World.BP_%sPickup_C_%d", w.name, w.name, index))
    self.slots[#self.slots + 1] = w.slot
    self.weapons[#self.weapons + 1] = w
    return w
end

function Game:on_update_stat(slotUid, tagStruct, value)
    for _, w in ipairs(self.weapons) do
        if w.guid == slotUid then
            for _, entry in ipairs(w.slot.ItemStats) do
                if entry[FIELDS.stat_name] == tagStruct then
                    entry[FIELDS.min_value] = value
                    self.writes[#self.writes + 1] = { weapon = w, key = entry.__key, value = value }
                    return
                end
            end
            error("UpdateStatByUID: tag not on weapon " .. w.name)
        end
    end
    error("UpdateStatByUID: unknown slot UID")
end

-- Current live stat value as the game would see it.
function Weapon:stat(key)
    for _, entry in ipairs(self.slot.ItemStats) do
        if entry.__key == key then return entry[FIELDS.min_value] end
    end
    return nil
end

-- Make this the weapon in the player's hands (fires the UI/equip hooks).
function Weapon:equip()
    local g = self.game
    local container = uobject("JSIContainer_C /Game/UI/WBP_Inventory.WBP_Inventory_C_0.WidgetTree." .. self.container)
    g:fire("GET_EQUIPPED_REF", container, param(true), param(self.slot), param(false))
    g:fire("GET_ACTIVE_SLOT", uobject("BP_JigHelperComp_C"), param(gameplay_tag(SLOT_TAGS[self.container] or SLOT_TAGS.CPrimary)))
    g:fire("GET_ACTIVE_WEAPON", uobject("BP_JigHelperComp_C"), param(self.pickup))
    g:fire("GET_EQUIPMENT_UID", uobject("BP_JigHelperComp_C"), param(nil), param(self.guid))
    return self
end

-- Shoot something without killing it.
function Weapon:hit(target)
    local g = self.game
    g:fire("GET_EQUIPMENT_UID", uobject("BP_JigHelperComp_C"), param(nil), param(self.guid))
    g:fire("SERVER_DAMAGE", self.pickup, param(false), param(target or uobject("BP_Zombie_C /Game/Maps/World.BP_Zombie_C_dummy")), param(nil))
    g:run_timers(5000)
end

-- Kill a zombie with this weapon. The game awards vanilla player XP first,
-- then the zombie's Death fires, then the killing shot's damage event.
function Weapon:kill(xp)
    local g = self.game
    g.zombies = (g.zombies or 0) + 1
    local zombie = uobject("BP_Zombie_C /Game/Maps/World.BP_Zombie_C_" .. g.zombies)
    g:fire("GET_EQUIPMENT_UID", uobject("BP_JigHelperComp_C"), param(nil), param(self.guid))
    g:fire("ADD_XP", uobject("LevellingComponent_C"), param(xp or 50), param(false), param(nil))
    g:fire("DEATH", zombie, param(nil), param(false))
    g:fire("SERVER_DAMAGE", self.pickup, param(false), param(zombie), param(nil))
    g:run_timers(5000)
    return self
end

function Weapon:kills(n, xp) for _ = 1, n do self:kill(xp) end; return self end

-- --------------------------------------------------------------------------
-- Observations
-- --------------------------------------------------------------------------

-- Read this weapon's saved record from data.db (what survives a restart).
function Game:db_records()
    local P = dofile(H.SCRIPTS_DIR .. "/core/persistence.lua")
    local recs = P.Load({ self:db_path() }, function() end)
    return recs
end

function Weapon:record()
    return self.game:db_records()[self.uid]
end

function Game:log_count(pattern)
    local n = 0
    for _, l in ipairs(self.logs) do if l:find(pattern) then n = n + 1 end end
    return n
end

function Game:has_log(pattern) return self:log_count(pattern) > 0 end

function Game:clear_observations()
    self.logs, self.toasts, self.writes = {}, {}, {}
end

-- Ordinary level-up rewards in award order: { {level=, tag=, key=}, ... }
local KEY_BY_TAG = {}
for k, t in pairs(H.TAGS) do KEY_BY_TAG[t] = k end
function Game:awarded()
    local out = {}
    for _, l in ipairs(self.logs) do
        local lvl, tag = l:match("^STAT UPGRADE AWARDED | [^|]+ | [^|]+ | L(%d+) | ([^ |]+)")
        if lvl then out[#out + 1] = { level = tonumber(lvl), tag = tag, key = KEY_BY_TAG[tag] } end
    end
    return out
end

-- Write a data.db for this sandbox before boot(). rows: list of tables with
-- uid, level, xp, kills, weapon, last_upgrade, bases{}, upgrades{}, pending_rewards
function Game:seed_db(rows)
    local P = dofile(H.SCRIPTS_DIR .. "/core/persistence.lua")
    P.Load({ self:db_path() }, function() end)
    local recs = {}
    for _, r in ipairs(rows) do
        recs[r.uid] = { level = r.level or 1, xp = r.xp or 0, kills = r.kills or 0, weapon = r.weapon or "HuntingRifle",
            last_upgrade = r.last_upgrade or "", pending_rewards = r.pending_rewards or 0,
            bases = r.bases or {}, upgrades = r.upgrades or {} }
    end
    assert(P.Save(recs, function() end), "seed_db save failed")
end

-- The pure progression rules module, built from a Config table like main.lua's.
function H.progression(overrides)
    local Config = {
        BaseLevelXP = 100, XPIncreasePerLevel = 50, LevelThresholds = {}, MilestonesEnabled = true,
        PreventConsecutiveSameStat = true,
        DamagePercent = 2, CriticalChancePoints = 1, CriticalMultiplierPoints = 2, RPMPercent = 2, FalloffPercent = 2,
        CapDamagePercent = 30, CapRPMPercent = 25, CapFalloffPercent = 25, CapCriticalChancePoints = 15, CapCriticalMultiplierPoints = 20,
        Milestones = {},
    }
    for k, v in pairs(overrides or {}) do Config[k] = v end
    local STAT_DEFS = {
        { key = "damage", tag = H.TAGS.damage, mode = "percent", config = "DamagePercent" },
        { key = "critmult", tag = H.TAGS.critmult, mode = "points", config = "CriticalMultiplierPoints" },
        { key = "critchance", tag = H.TAGS.critchance, mode = "points", config = "CriticalChancePoints" },
        { key = "rpm", tag = H.TAGS.rpm, mode = "percent", config = "RPMPercent" },
        { key = "falloff", tag = H.TAGS.falloff, mode = "percent", config = "FalloffPercent" },
    }
    local MBT = {
        DamagePercent = { stat_key = "damage", mode = "percent" }, CriticalChancePoints = { stat_key = "critchance", mode = "points" },
        CriticalMultiplierPoints = { stat_key = "critmult", mode = "points" }, RPMPercent = { stat_key = "rpm", mode = "percent" },
        FalloffPercent = { stat_key = "falloff", mode = "percent" },
    }
    local CAP = { damage = "CapDamagePercent", critchance = "CapCriticalChancePoints", critmult = "CapCriticalMultiplierPoints",
        rpm = "CapRPMPercent", falloff = "CapFalloffPercent" }
    local env = setmetatable({ math = make_math(1) }, { __index = _G })
    local mod = assert(loadfile(H.SCRIPTS_DIR .. "/firearms/progression.lua", "t", env))()
    local P = mod.New({ Config = Config, StatDefs = STAT_DEFS, MilestoneBonusTypes = MBT, CapConfigByStat = CAP })
    local defs = {}
    for _, d in ipairs(STAT_DEFS) do defs[d.key] = d end
    return P, defs, Config
end

-- XP needed to go from level 1 to `level` with the default formula.
function H.total_xp_to(level, base, inc)
    base, inc = base or 100, inc or 50
    local t = 0
    for l = 1, level - 1 do t = t + base + (l - 1) * inc end
    return t
end

H.param, H.uobject = param, uobject
return H
