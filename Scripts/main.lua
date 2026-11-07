-- WeaponProgression - SurrounDead UE4SS Lua mod.
-- Release history and research checkpoints: see CHANGELOG.md.
-- Configuration and installation: see README.md.

local PREFIX = "[WeaponProgression] "
local VERSION = "0.18.5"

local PATH_GET_EQUIPMENT_UID =
    "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetEquipmentUID"
local PATH_SERVER_DAMAGE =
    "/Game/Inventory/Items/Pickups/Weapons/Firearms/BP_FirearmPickup.BP_FirearmPickup_C:SERVER_DamageEvent"
local PATH_ADD_XP =
    "/Game/Blueprints/Components/LevellingComponent.LevellingComponent_C:AddXP"
local PATH_DEATH =
    "/Game/AI/Zombies/BP_MasterZombie.BP_MasterZombie_C:Death"
local PATH_JIG_TRY_ADD =
    "/Game/JigSInventory/Jigsaw/Components/BP_JigComponent.BP_JigComponent_C:JigTryAddItemSomewhere"
local PATH_TOOLTIP_UPDATE =
    "/Game/JigSInventory/Jigsaw/Widgets/HoverDrag/Hover/OnHoverTooltipWidget.OnHoverTooltipWidget_C:Update"
local PATH_GET_ACTIVE_WEAPON =
    "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetActiveWeapon"
local PATH_GET_ACTIVE_WEAPON_SLOT =
    "/Game/JigSInventory/Jigsaw/Components/BP_JigHelperComp.BP_JigHelperComp_C:GetActiveWeaponSlot"
local PATH_MELEE_HIT_HEAD =
    "/Game/Inventory/Items/Pickups/Weapons/Melee/BP_MeleePickup.BP_MeleePickup_C:HitHead"
local PATH_MELEE_HIT_BODY =
    "/Game/Inventory/Items/Pickups/Weapons/Melee/BP_MeleePickup.BP_MeleePickup_C:HitBody"
local PATH_GET_EQUIPPED_ITEM_REF =
    "/Game/JigSInventory/Jigsaw/Widgets/JSIContainer.JSIContainer_C:GetEquippedItemRef"

-- Confirmed JSI_Slot_C / S_ItemStat field names from the 0.8 investigation.
local FIELDS = {
    stat_name = "STAT_NAME_13_8D9D8D5D48A145FB1BAD6E98C69D0A10",
    min_value = "MinValue_6_4B4822A7420F784740B6A58155973EE6",
    item_unique_id = "ItemUniqueID",
    item_info = "ItemInfo_25_937A083B4BD3D9B590E0A69C76A4F6F7",
    item_id = "ItemID_28_01CA27D84AF7D1014D9E2E83894C1848",
    stats = "Stats_26_C770972746930CB80CC49AB7A6D19359",
}

local function get_mod_directory()
    local info = debug.getinfo(1, "S")
    local source = info and info.source or nil
    if source == nil then return nil end
    source = tostring(source)
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    source = source:gsub("\\", "/")
    local scriptsDir = source:match("^(.*)/[^/]+$")
    if scriptsDir == nil then return nil end
    return scriptsDir:match("^(.*)/Scripts$") or scriptsDir
end

-- debug.getinfo normally gives main.lua's full path. If a UE4SS build ever
-- reports only a bare chunk name, fall back to the usual install locations
-- (relative to the game's Win64 folder) instead of failing on a nil path.
local MOD_DIR_WARNING = nil
local function resolve_mod_directory()
    local dir = get_mod_directory()
    if dir ~= nil then return dir end
    for _, candidate in ipairs({ "Mods/WeaponProgression", "ue4ss/Mods/WeaponProgression", "./Mods/WeaponProgression" }) do
        local f = io.open(candidate .. "/Scripts/main.lua", "r")
        if f then
            f:close()
            MOD_DIR_WARNING = "MOD DIR | script path unavailable; using " .. candidate
            return candidate
        end
    end
    MOD_DIR_WARNING = "MOD DIR ERROR | could not locate the WeaponProgression folder; modules will fail to load"
    return "Mods/WeaponProgression"
end

local MOD_DIR = resolve_mod_directory()

local function candidate_paths(fileName)
    local paths = {}
    if MOD_DIR ~= nil then paths[#paths + 1] = MOD_DIR .. "/" .. fileName end
    paths[#paths + 1] = "Mods\\WeaponProgression\\" .. fileName
    paths[#paths + 1] = "ue4ss\\Mods\\WeaponProgression\\" .. fileName
    paths[#paths + 1] = ".\\Mods\\WeaponProgression\\" .. fileName
    return paths
end

local DB_PATHS = candidate_paths("data.db")
local CONFIG_PATHS = candidate_paths("config.ini")

local DEFAULT_MILESTONES = {
    { level=5,  rank="Proven I",      bonus_type="DamagePercent",             value=2.0 },
    { level=10, rank="Proven II",     bonus_type="FalloffPercent",            value=3.0 },
    { level=15, rank="Proven III",    bonus_type="CriticalMultiplierPoints",  value=2.0 },
    { level=20, rank="Trusted I",     bonus_type="RPMPercent",                value=3.0, fallback_type="FalloffPercent" },
    { level=25, rank="Trusted II",    bonus_type="CriticalChancePoints",      value=1.0 },
    { level=30, rank="Trusted III",   bonus_type="DamagePercent",             value=3.0 },
    { level=35, rank="Veteran I",     bonus_type="FalloffPercent",            value=4.0 },
    { level=40, rank="Veteran II",    bonus_type="RPMPercent",                value=4.0, fallback_type="FalloffPercent" },
    { level=45, rank="Veteran III",   bonus_type="CriticalMultiplierPoints",  value=2.0 },
    { level=50, rank="Elite I",       bonus_type="DamagePercent",             value=4.0 },
    { level=55, rank="Elite II",      bonus_type="CriticalChancePoints",      value=2.0 },
    { level=60, rank="Elite III",     bonus_type="FalloffPercent",            value=5.0 },
    { level=65, rank="Signature I",   bonus_type="RPMPercent",                value=5.0, fallback_type="FalloffPercent" },
    { level=70, rank="Signature II",  bonus_type="DamagePercent",             value=5.0 },
    { level=75, rank="Signature III", bonus_type="CriticalMultiplierPoints",  value=3.0 },
}

local DEFAULT_CONFIG = {
    WeaponXPMultiplier = 1.0,
    BaseLevelXP = 100,
    XPIncreasePerLevel = 50,
    MaxLevel = 100,
    DamagePercent = 2.0,
    CriticalChancePoints = 1.0,
    CriticalMultiplierPoints = 2.0,
    RPMPercent = 2.0,
    FalloffPercent = 2.0,
    PreventConsecutiveSameStat = true,
    VerboseLogging = false,
    ShowProgressionTooltipRows = false,
    DevControls = false,
    Language = "en",

    MilestonesEnabled = true,
    CapDamagePercent = 30.0,
    CapRPMPercent = 25.0,
    CapFalloffPercent = 25.0,
    CapCriticalChancePoints = 15.0,
    CapCriticalMultiplierPoints = 20.0,
}

local function copy_milestones(source)
    local out = {}
    for _, m in ipairs(source or {}) do
        out[#out + 1] = {
            level = m.level,
            rank = m.rank,
            bonus_type = m.bonus_type,
            value = m.value,
            fallback_type = m.fallback_type,
        }
    end
    return out
end

local Config = {
    WeaponXPMultiplier = DEFAULT_CONFIG.WeaponXPMultiplier,
    BaseLevelXP = DEFAULT_CONFIG.BaseLevelXP,
    XPIncreasePerLevel = DEFAULT_CONFIG.XPIncreasePerLevel,
    MaxLevel = DEFAULT_CONFIG.MaxLevel,
    DamagePercent = DEFAULT_CONFIG.DamagePercent,
    CriticalChancePoints = DEFAULT_CONFIG.CriticalChancePoints,
    CriticalMultiplierPoints = DEFAULT_CONFIG.CriticalMultiplierPoints,
    RPMPercent = DEFAULT_CONFIG.RPMPercent,
    FalloffPercent = DEFAULT_CONFIG.FalloffPercent,
    PreventConsecutiveSameStat = DEFAULT_CONFIG.PreventConsecutiveSameStat,
    VerboseLogging = DEFAULT_CONFIG.VerboseLogging,
    ShowProgressionTooltipRows = DEFAULT_CONFIG.ShowProgressionTooltipRows,
    DevControls = DEFAULT_CONFIG.DevControls,
    Language = DEFAULT_CONFIG.Language,

    MilestonesEnabled = DEFAULT_CONFIG.MilestonesEnabled,
    CapDamagePercent = DEFAULT_CONFIG.CapDamagePercent,
    CapRPMPercent = DEFAULT_CONFIG.CapRPMPercent,
    CapFalloffPercent = DEFAULT_CONFIG.CapFalloffPercent,
    CapCriticalChancePoints = DEFAULT_CONFIG.CapCriticalChancePoints,
    CapCriticalMultiplierPoints = DEFAULT_CONFIG.CapCriticalMultiplierPoints,

    LevelThresholds = {},
    Milestones = copy_milestones(DEFAULT_MILESTONES),
}

local STAT_DEFS = {
    { key="damage",   tag="Jig.Stat.FirearmDamage",         mode="percent", config="DamagePercent" },
    { key="critmult", tag="Jig.Stat.CriticalHitMultiplier", mode="points",  config="CriticalMultiplierPoints" },
    { key="critchance",tag="Jig.Stat.CriticalHitChance",    mode="points",  config="CriticalChancePoints" },
    { key="rpm",      tag="Jig.Stat.FirearmRPM",            mode="percent", config="RPMPercent" },
    { key="falloff",  tag="Jig.Stat.DamageFallOff",         mode="percent", config="FalloffPercent" },
}

local STAT_BY_TAG = {}
for _, def in ipairs(STAT_DEFS) do STAT_BY_TAG[def.tag] = def end

local MILESTONE_BONUS_TYPES = {
    DamagePercent = { stat_key="damage", mode="percent", label="Damage" },
    CriticalChancePoints = { stat_key="critchance", mode="points", label="Critical Chance" },
    CriticalMultiplierPoints = { stat_key="critmult", mode="points", label="Critical Multiplier" },
    RPMPercent = { stat_key="rpm", mode="percent", label="RPM" },
    FalloffPercent = { stat_key="falloff", mode="percent", label="Damage Falloff" },
}

local CAP_CONFIG_BY_STAT = {
    damage = "CapDamagePercent",
    critchance = "CapCriticalChancePoints",
    critmult = "CapCriticalMultiplierPoints",
    rpm = "CapRPMPercent",
    falloff = "CapFalloffPercent",
}

local RETRY_DELAY_MS = 3000
local MAX_RETRY_ROUNDS = 40

local configPath = nil
local records = {}

local guidLibrary = nil
local save_db = nil
local reconcile_weapon_stats = nil
local process_pending_rewards = nil
local stat_target = nil
local progression_bonus_label = nil
local MeleeProgression = nil -- set by load_melee_progression()
local cachedJigComponent = nil

local QUIET_LOG_PREFIXES = {
    -- Routine per-hit/cache chatter. Failures and mismatches intentionally remain visible.
    "DAMAGE |",
    "KILL CREDIT |",
    "FIREARM LIVE STAT |",
    "LIVE CACHE ",
    "JSI SCAN |",
    "JSI MATCH |",
    "JSI MATCH STAT |",
    "JSI MATCH COMPLETE |",
    "MUTATION UID |",
    "DIRECT JIG RESOLVE SUCCESS |",
    "STAT RECONCILE |",
    "STAT VERIFY DEBOUNCE |",
    "STAT VERIFY OK |",
    "STAT VERIFY COMPLETE |",
    "TOOLTIP PROBE |",
    "TOOLTIP STAT |",
    "TOOLTIP UPGRADES |",
    "STAT W CONSTRUCT |",
    "TOOLTIP FORMAT APPLY |",
    "TOOLTIP PROGRESSION ADD |",
    "TOOLTIP PROGRESSION TEXT APPLY |",
    "UI STATE |",
    "UI EQUIPPED |",
}

local function log(msg)
    local text = tostring(msg)
    if not Config.VerboseLogging then
        for _, prefix in ipairs(QUIET_LOG_PREFIXES) do
            if text:sub(1, #prefix) == prefix then return end
        end
    end
    print(PREFIX .. text .. "\n")
end

if MOD_DIR_WARNING ~= nil then log(MOD_DIR_WARNING) end

local translate, translate_rank = nil, nil
do
    local path = MOD_DIR and (MOD_DIR .. "/Scripts/core/localization.lua")
    local chunk, err = path and loadfile(path)
    if chunk then
        local ok, module = pcall(chunk)
        if ok and type(module) == "table" and type(module.new) == "function" then
            local english, englishCode, englishSupported, englishRank = module.new("en")
            translate, translate_rank = english, englishRank
            local function select_language(language)
                local t, code, supported, rank = module.new(language)
                translate, translate_rank = t, rank
                if not supported then log("LOCALIZATION | unsupported " .. tostring(language) .. "; using English") end
                log("LOCALIZATION | active=" .. (supported and code or "en"))
            end
            Config.SelectLanguage = select_language
        else
            log("LOCALIZATION LOAD FAILED | " .. tostring(module))
        end
    else
        log("LOCALIZATION LOAD FAILED | " .. tostring(err))
    end
end
local function tr(key)
    return translate and translate(key) or key
end
local function display_rank(name)
    return translate_rank and translate_rank(name) or name
end

-- ============================================================================
-- Compatibility / fragile native-tooltip guard
-- ============================================================================

local Compatibility = nil

local FirearmProgression = nil
local ProgressionModule = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/progression.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            ProgressionModule = moduleOrErr
            local okNew, instanceOrErr = pcall(moduleOrErr.New, {
                Config = Config,
                StatDefs = STAT_DEFS,
                MilestoneBonusTypes = MILESTONE_BONUS_TYPES,
                CapConfigByStat = CAP_CONFIG_BY_STAT,
                Translate = tr,
            })
            if okNew then FirearmProgression = instanceOrErr else log("FIREARM PROGRESSION INIT FAILED | " .. tostring(instanceOrErr)) end
        else
            log("FIREARM PROGRESSION LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("FIREARM PROGRESSION LOAD FAILED | " .. tostring(chunkOrErr))
    end
end

local function load_compatibility_module()
    local errors = {}

    if MOD_DIR ~= nil then
        local compatPath = MOD_DIR .. "/Scripts/compatibility/compatibility.lua"
        local okLoad, chunkOrErr = pcall(loadfile, compatPath)
        if okLoad and type(chunkOrErr) == "function" then
            local okRun, moduleOrErr = pcall(chunkOrErr)
            if okRun and type(moduleOrErr) == "table" then
                Compatibility = moduleOrErr
                Compatibility.Configure({ log = log })
                log("COMPAT MODULE | loaded " .. compatPath)
                return true
            end
            errors[#errors + 1] = "loadfile run: " .. tostring(moduleOrErr)
        else
            errors[#errors + 1] = "loadfile: " .. tostring(chunkOrErr)
        end
    end

    local okRequire, moduleOrErr = pcall(require, "compatibility")
    if okRequire and type(moduleOrErr) == "table" then
        Compatibility = moduleOrErr
        Compatibility.Configure({ log = log })
        log('COMPAT MODULE | loaded via require("compatibility")')
        return true
    end

    errors[#errors + 1] = "require: " .. tostring(moduleOrErr)
    log("COMPAT MODULE UNAVAILABLE | tooltip hooks will use legacy registration | " ..
        table.concat(errors, " | "))
    return false
end

load_compatibility_module()

-- ============================================================================
-- Reusable native UI module
-- ============================================================================

local UI = nil

local function load_ui_module()
    local errors = {}

    -- Preferred route: ui.lua lives beside main.lua in Scripts/. This avoids
    -- depending on UE4SS package.path details and keeps the mod self-contained.
    if MOD_DIR ~= nil then
        local uiPath = MOD_DIR .. "/Scripts/ui/status.lua"
        local okLoad, chunkOrErr = pcall(loadfile, uiPath)
        if okLoad and type(chunkOrErr) == "function" then
            local okRun, moduleOrErr = pcall(chunkOrErr)
            if okRun and type(moduleOrErr) == "table" then
                UI = moduleOrErr
                log("UI MODULE | loaded " .. uiPath)
                return true
            end
            errors[#errors + 1] = "loadfile run: " .. tostring(moduleOrErr)
        else
            errors[#errors + 1] = "loadfile: " .. tostring(chunkOrErr)
        end
    end

    -- Fallback for UE4SS installations that expose the Scripts directory on
    -- package.path.
    local okRequire, moduleOrErr = pcall(require, "ui")
    if okRequire and type(moduleOrErr) == "table" then
        UI = moduleOrErr
        log("UI MODULE | loaded via require(\"ui\")")
        return true
    end

    errors[#errors + 1] = "require: " .. tostring(moduleOrErr)
    log("UI MODULE DISABLED | " .. table.concat(errors, " | "))
    return false
end

load_ui_module()

local function trim(s)
    if s == nil then return "" end
    return tostring(s):match("^%s*(.-)%s*$")
end

local function unwrap(v)
    if v == nil then return nil end

    local ok, r = pcall(function() return v:get() end)
    if ok and r ~= nil then return r end

    ok, r = pcall(function() return v:Get() end)
    if ok and r ~= nil then return r end

    return v
end

local function full_name(v)
    local o = unwrap(v)
    if o == nil then return "<nil>" end

    local ok, s = pcall(function() return o:GetFullName() end)
    if ok and s then return tostring(s) end

    return tostring(o)
end

local function short_name(v)
    local n = full_name(v)

    local bp = n:match("BP_([%w_]+)Pickup_C")
    if bp and bp ~= "" then return bp end

    bp = n:match("BP_([%w_]+)_C")
    if bp and bp ~= "" then return bp end

    local tail = n:match("([^%.:]+)$")
    return tail or n
end

local function same_object(a, b)
    local aa = unwrap(a)
    local bb = unwrap(b)
    if aa == nil or bb == nil then return false end

    local ok, result = pcall(function() return aa == bb end)
    if ok and result then return true end

    return full_name(aa) == full_name(bb)
end

local function find_guid_library()
    if guidLibrary ~= nil then return guidLibrary end

    local ok, obj = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetGuidLibrary")
    end)

    if ok and obj ~= nil then
        guidLibrary = obj
        return obj
    end

    return nil
end

local function looks_like_guid(s)
    if type(s) ~= "string" then return false end
    local compact = s:gsub("[{}%-]", "")
    return #compact == 32 and compact:match("^[0-9A-Fa-f]+$") ~= nil
end

local function normalize_guid(s)
    if not looks_like_guid(s) then return nil end
    local c = s:gsub("[{}%-]", ""):upper()

    return string.format(
        "%s-%s-%s-%s-%s",
        c:sub(1, 8),
        c:sub(9, 12),
        c:sub(13, 16),
        c:sub(17, 20),
        c:sub(21, 32)
    )
end

local function guid_to_string(v)
    local guid = unwrap(v)
    if guid == nil then return nil end

    local lib = find_guid_library()
    if lib == nil then return nil end

    local ok, fstr = pcall(function()
        return lib:Conv_GuidToString(guid)
    end)
    if not ok or fstr == nil then return nil end

    local raw = unwrap(fstr)
    ok, fstr = pcall(function() return raw:ToString() end)
    if not ok or type(fstr) ~= "string" then return nil end

    return normalize_guid(fstr)
end


-- ============================================================================
-- Controlled weapon-stat mutation helpers
-- ============================================================================
-- This is intentionally copied from the mechanics already proven in the
-- Weapon Roulette investigation:
--
-- JigTryAddItemSomewhere Context = the correct live BP_JigComponent
--       -> capture UID
--       -> wait for JSI_Slot_C to materialise
--       -> FindItemByUID(uid, foundOut)
--       -> foundOut.Found["ItemStats"]
--       -> match GameplayTag
--       -> UpdateStatByUID(uid, tag, newValue)
--
-- v0.10.1 used FindFirstOf(BP_JigComponent), which can resolve the wrong
-- inventory component. This build does NOT use that route for the stat write.

local function safe_array_length(arr)
    if arr == nil then return nil end
    local ok, len = pcall(function() return #arr end)
    if ok and type(len) == "number" then return len end
    return nil
end

local function safe_fname_to_string(v)
    if v == nil then return nil end

    local ok, s = pcall(function() return v:ToString() end)
    if ok and s ~= nil then return tostring(s) end

    ok, s = pcall(function() return tostring(v) end)
    if ok and s ~= nil then return s end

    return nil
end

local function decode_gameplay_tag(tagStruct)
    if tagStruct == nil then return nil end

    local okName, rawName = pcall(function() return tagStruct["TagName"] end)
    if okName and rawName ~= nil then
        local decoded = safe_fname_to_string(rawName)
        if decoded ~= nil then return decoded end
    end

    for _, field in ipairs({"GameplayTagName", "Name"}) do
        local ok, raw = pcall(function() return tagStruct[field] end)
        if ok and raw ~= nil then
            local decoded = safe_fname_to_string(raw)
            if decoded ~= nil then return decoded end
        end
    end

    local okDirect, direct = pcall(function() return tagStruct:ToString() end)
    if okDirect and direct ~= nil then return tostring(direct) end

    return nil
end

local function safe_field(obj,key)
    if obj==nil then return nil,false end
    local ok,value=pcall(function() return obj[key] end)
    if ok then return value,true end
    return nil,false
end

-- ============================================================================
-- Firearm live resolver boundary (Scripts/firearms/resolver.lua)
-- ============================================================================
local FirearmResolver = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/resolver.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            local okNew, instanceOrErr = pcall(moduleOrErr.New, {
                log=log, Fields=FIELDS, StatDefs=STAT_DEFS,
                records=function() return records end,
                save_db=function() return save_db and save_db() or false end,
                full_name=full_name, guid_to_string=guid_to_string,
                safe_array_length=safe_array_length, decode_gameplay_tag=decode_gameplay_tag,
                stat_target=function(def,base,count,r) return stat_target and stat_target(def,base,count,r) end,
            })
            if okNew then FirearmResolver=instanceOrErr else log("FIREARM RESOLVER INIT FAILED | " .. tostring(instanceOrErr)) end
        else log("FIREARM RESOLVER LOAD FAILED | " .. tostring(moduleOrErr)) end
    else log("FIREARM RESOLVER LOAD FAILED | " .. tostring(chunkOrErr)) end
end

local function ensure_record(uid, weaponName)
    local r=records[uid]
    if r == nil then
        r={level=1,xp=0,kills=0,weapon=weaponName or "Unknown",last_upgrade="",pending_rewards=0,bases={},upgrades={}}
        records[uid]=r
    end
    r.weapon=weaponName or r.weapon or "Unknown"; r.bases=r.bases or {}; r.upgrades=r.upgrades or {}
    r.last_upgrade=r.last_upgrade or ""; r.pending_rewards=r.pending_rewards or 0
    return r
end

local function probe_active_firearm_slot(uidStruct, uid, weaponName)
    if FirearmResolver then FirearmResolver.Probe(uidStruct,uid,weaponName) end
end

-- ============================================================================
-- Configuration
-- ============================================================================

local function reset_config()
    Config.WeaponXPMultiplier = DEFAULT_CONFIG.WeaponXPMultiplier
    Config.BaseLevelXP = DEFAULT_CONFIG.BaseLevelXP
    Config.XPIncreasePerLevel = DEFAULT_CONFIG.XPIncreasePerLevel
    Config.MaxLevel = DEFAULT_CONFIG.MaxLevel
    Config.DamagePercent = DEFAULT_CONFIG.DamagePercent
    Config.CriticalChancePoints = DEFAULT_CONFIG.CriticalChancePoints
    Config.CriticalMultiplierPoints = DEFAULT_CONFIG.CriticalMultiplierPoints
    Config.RPMPercent = DEFAULT_CONFIG.RPMPercent
    Config.FalloffPercent = DEFAULT_CONFIG.FalloffPercent
    Config.PreventConsecutiveSameStat = DEFAULT_CONFIG.PreventConsecutiveSameStat
    Config.VerboseLogging = DEFAULT_CONFIG.VerboseLogging
    Config.ShowProgressionTooltipRows = DEFAULT_CONFIG.ShowProgressionTooltipRows
    Config.DevControls = DEFAULT_CONFIG.DevControls
    Config.Language = DEFAULT_CONFIG.Language

    Config.MilestonesEnabled = DEFAULT_CONFIG.MilestonesEnabled
    Config.CapDamagePercent = DEFAULT_CONFIG.CapDamagePercent
    Config.CapRPMPercent = DEFAULT_CONFIG.CapRPMPercent
    Config.CapFalloffPercent = DEFAULT_CONFIG.CapFalloffPercent
    Config.CapCriticalChancePoints = DEFAULT_CONFIG.CapCriticalChancePoints
    Config.CapCriticalMultiplierPoints = DEFAULT_CONFIG.CapCriticalMultiplierPoints

    Config.LevelThresholds = {}
    Config.Milestones = copy_milestones(DEFAULT_MILESTONES)
end

local function find_config_file()
    for _, path in ipairs(CONFIG_PATHS) do
        local f = io.open(path, "r")
        if f then
            f:close()
            return path
        end
    end
    return nil
end

local function set_progression_value(key, rawValue)
    local n = tonumber(trim(rawValue))
    if n == nil then
        log("CONFIG WARNING | ignored invalid " .. tostring(key) .. "=" .. tostring(rawValue))
        return
    end

    if key == "WeaponXPMultiplier" then
        -- Keep the setting useful and safe from accidental negative/absurd values.
        if n < 0.1 then n = 0.1 end
        if n > 10.0 then n = 10.0 end
        Config.WeaponXPMultiplier = n

    elseif key == "BaseLevelXP" then
        Config.BaseLevelXP = math.max(1, math.floor(n))

    elseif key == "XPIncreasePerLevel" then
        Config.XPIncreasePerLevel = math.max(0, math.floor(n))

    elseif key == "MaxLevel" then
        Config.MaxLevel = math.max(2, math.floor(n))
    end
end

local function set_stat_upgrade_value(key, rawValue)
    local boolText = trim(rawValue):lower()
    if key == "PreventConsecutiveSameStat" then
        if boolText == "true" or boolText == "1" or boolText == "yes" or boolText == "on" then
            Config.PreventConsecutiveSameStat = true
        elseif boolText == "false" or boolText == "0" or boolText == "no" or boolText == "off" then
            Config.PreventConsecutiveSameStat = false
        else
            log("CONFIG WARNING | ignored invalid boolean " .. key .. "=" .. tostring(rawValue))
        end
        return
    end

    local n = tonumber(trim(rawValue))
    if n == nil or n < 0 then
        log("CONFIG WARNING | ignored invalid " .. tostring(key) .. "=" .. tostring(rawValue))
        return
    end

    if key == "DamagePercent" then Config.DamagePercent = n
    elseif key == "CriticalChancePoints" then Config.CriticalChancePoints = n
    elseif key == "CriticalMultiplierPoints" then Config.CriticalMultiplierPoints = n
    elseif key == "RPMPercent" then Config.RPMPercent = n
    elseif key == "FalloffPercent" then Config.FalloffPercent = n
    end
end


local function parse_bool(rawValue)
    local b = trim(rawValue):lower()
    if b == "true" or b == "1" or b == "yes" or b == "on" then return true end
    if b == "false" or b == "0" or b == "no" or b == "off" then return false end
    return nil
end

local function set_cap_value(key, rawValue)
    local n = tonumber(trim(rawValue))
    if n == nil or n < 0 then
        log("CONFIG WARNING | ignored invalid cap " .. tostring(key) .. "=" .. tostring(rawValue))
        return
    end

    if key == "DamagePercent" then Config.CapDamagePercent = n
    elseif key == "RPMPercent" then Config.CapRPMPercent = n
    elseif key == "FalloffPercent" then Config.CapFalloffPercent = n
    elseif key == "CriticalChancePoints" then Config.CapCriticalChancePoints = n
    elseif key == "CriticalMultiplierPoints" then Config.CapCriticalMultiplierPoints = n
    else
        log("CONFIG WARNING | ignored unknown cap " .. tostring(key))
    end
end

local function remove_milestone_level(level)
    for i = #Config.Milestones, 1, -1 do
        if Config.Milestones[i].level == level then
            table.remove(Config.Milestones, i)
        end
    end
end

local function set_milestone_value(key, rawValue)
    if key == "Enabled" then
        local b = parse_bool(rawValue)
        if b == nil then
            log("CONFIG WARNING | ignored invalid boolean Milestones.Enabled=" .. tostring(rawValue))
        else
            Config.MilestonesEnabled = b
        end
        return
    end

    local level = tonumber(tostring(key):match("^Level(%d+)$"))
    if level == nil or level < 1 then
        log("CONFIG WARNING | ignored invalid milestone key " .. tostring(key))
        return
    end
    level = math.floor(level)

    local raw = trim(rawValue)
    if raw:lower() == "disabled" or raw:lower() == "off" or raw:lower() == "none" then
        remove_milestone_level(level)
        return
    end

    local parts = {}
    for part in (raw .. "|"):gmatch("(.-)|") do
        parts[#parts + 1] = trim(part)
    end

    local rank = parts[1] or ""
    local bonusType = parts[2] or ""
    local value = tonumber(parts[3])
    local fallbackType = parts[4]
    if fallbackType == "" then fallbackType = nil end

    if rank == "" then
        log("CONFIG WARNING | milestone Level" .. tostring(level) .. " has empty rank name")
        return
    end
    if MILESTONE_BONUS_TYPES[bonusType] == nil then
        log("CONFIG WARNING | milestone Level" .. tostring(level) ..
            " uses unsupported bonus type " .. tostring(bonusType))
        return
    end
    if value == nil or value < 0 then
        log("CONFIG WARNING | milestone Level" .. tostring(level) ..
            " has invalid value " .. tostring(parts[3]))
        return
    end
    if fallbackType ~= nil and MILESTONE_BONUS_TYPES[fallbackType] == nil then
        log("CONFIG WARNING | milestone Level" .. tostring(level) ..
            " uses unsupported fallback type " .. tostring(fallbackType))
        return
    end

    remove_milestone_level(level)
    Config.Milestones[#Config.Milestones + 1] = {
        level = level,
        rank = rank,
        bonus_type = bonusType,
        value = value,
        fallback_type = fallbackType,
    }
end

local function sort_milestones()
    table.sort(Config.Milestones, function(a, b)
        if a.level == b.level then return tostring(a.rank) < tostring(b.rank) end
        return a.level < b.level
    end)
end

local function load_config()
    reset_config()
    configPath = find_config_file()

    if configPath == nil then
        log("CONFIG | config.ini not found; using built-in defaults.")
        log(string.format(
            "CONFIG | multiplier=%.3fx | base=%d | increase=%d | max_level=%d | overrides=0",
            Config.WeaponXPMultiplier,
            Config.BaseLevelXP,
            Config.XPIncreasePerLevel,
            Config.MaxLevel
        ))
        return false
    end

    local f = io.open(configPath, "r")
    if not f then
        log("CONFIG WARNING | could not open " .. tostring(configPath) .. "; using defaults.")
        return false
    end

    local section = ""

    for rawLine in f:lines() do
        local line = trim(rawLine)

        if line ~= "" and line:sub(1, 1) ~= ";" and line:sub(1, 1) ~= "#" then
            local newSection = line:match("^%[([^%]]+)%]$")
            if newSection then
                section = trim(newSection)
            else
                local key, value = line:match("^([^=]+)=(.*)$")
                if key ~= nil then
                    key = trim(key)
                    value = trim(value)

                    if section == "Progression" then
                        set_progression_value(key, value)

                    elseif section == "StatUpgrades" then
                        set_stat_upgrade_value(key, value)

                    elseif section == "Utility" and
                           (key == "VerboseLogging" or key == "ShowProgressionTooltipRows" or key == "DevControls") then
                        local b = parse_bool(value)
                        if b == nil then
                            log("CONFIG WARNING | ignored invalid boolean " ..
                                tostring(key) .. "=" .. tostring(value))
                        elseif key == "VerboseLogging" then
                            Config.VerboseLogging = b
                        elseif key == "DevControls" then
                            Config.DevControls = b
                        else
                            Config.ShowProgressionTooltipRows = b
                        end

                    elseif section == "Localization" and key == "Language" then
                        Config.Language = value

                    elseif section == "Caps" then
                        set_cap_value(key, value)

                    elseif section == "Milestones" then
                        set_milestone_value(key, value)

                    elseif section == "LevelThresholds" then
                        local targetLevel = tonumber(key:match("^Level(%d+)$"))
                        local threshold = tonumber(value)

                        if targetLevel ~= nil and targetLevel >= 2 and
                           threshold ~= nil and threshold > 0 then
                            Config.LevelThresholds[math.floor(targetLevel)] =
                                math.max(1, math.floor(threshold))
                        else
                            log("CONFIG WARNING | ignored invalid threshold " ..
                                tostring(key) .. "=" .. tostring(value))
                        end
                    end
                end
            end
        end
    end

    f:close()
    sort_milestones()
    if Config.SelectLanguage then Config.SelectLanguage(Config.Language) end

    local overrideCount = 0
    for _ in pairs(Config.LevelThresholds) do overrideCount = overrideCount + 1 end

    log("Config path: " .. configPath)
    log(string.format(
        "CONFIG | multiplier=%.3fx | base=%d | increase=%d | max_level=%d | overrides=%d",
        Config.WeaponXPMultiplier,
        Config.BaseLevelXP,
        Config.XPIncreasePerLevel,
        Config.MaxLevel,
        overrideCount
    ))

    log(string.format(
        "STAT CONFIG | damage=+%.3f%% | crit_chance=+%.3f | crit_mult=+%.3f | rpm=+%.3f%% | falloff=+%.3f%% | no_repeat=%s",
        Config.DamagePercent, Config.CriticalChancePoints, Config.CriticalMultiplierPoints,
        Config.RPMPercent, Config.FalloffPercent, tostring(Config.PreventConsecutiveSameStat)
    ))
    log("UTILITY CONFIG | verbose_logging=" .. tostring(Config.VerboseLogging) ..
    " | progression_tooltip_rows=" .. tostring(Config.ShowProgressionTooltipRows))
    log(string.format(
        "CAPS | damage=+%.3f%% | crit_chance=+%.3f | crit_mult=+%.3f | rpm=+%.3f%% | falloff=+%.3f%%",
        Config.CapDamagePercent, Config.CapCriticalChancePoints,
        Config.CapCriticalMultiplierPoints, Config.CapRPMPercent,
        Config.CapFalloffPercent
    ))
    log("MILESTONES | enabled=" .. tostring(Config.MilestonesEnabled) ..
        " | configured=" .. tostring(#Config.Milestones))

    for _, m in ipairs(Config.Milestones) do
        log("MILESTONE CONFIG | L" .. tostring(m.level) ..
            " | " .. tostring(m.rank) ..
            " | " .. tostring(m.bonus_type) ..
            "=" .. tostring(m.value) ..
            (m.fallback_type and (" | fallback=" .. tostring(m.fallback_type)) or ""))
    end

    if overrideCount > 0 then
        local levels = {}
        for targetLevel in pairs(Config.LevelThresholds) do
            table.insert(levels, targetLevel)
        end
        table.sort(levels)

        for _, targetLevel in ipairs(levels) do
            log(string.format(
                "CONFIG OVERRIDE | Level%d requires %d XP",
                targetLevel,
                Config.LevelThresholds[targetLevel]
            ))
        end
    end

    return true
end

local function xp_required(currentLevel)
    return FirearmProgression.XPRequired(currentLevel)
end

local function get_rank_info(level)
    return FirearmProgression.GetRankInfo(level)
end

local function resolved_milestone_type_for_record(m, r)
    return FirearmProgression.ResolveMilestoneType(m, r)
end

local function milestone_bonus_for_stat(r, def)
    return FirearmProgression.MilestoneBonusForStat(r, def)
end

local function milestone_bonus_description(m, r)
    return FirearmProgression.MilestoneDescription(m, r)
end

-- ============================================================================
-- Reusable UI state bridge
-- ============================================================================
--
-- ui.lua is presentation-only. main.lua owns active-weapon discovery, physical
-- UID resolution and progression calculations, then supplies a tiny state table.
--
-- Proven SurrounDead 0.8 route:
--   GetActiveWeaponSlot GameplayTag
--       -> CPrimary / CSecondary / CPistol / CMelee
--       -> GetEquippedItemRef JSI_Slot_C.ItemUniqueID
--       -> records[physical UID]
--
-- A one-time top-level JSI slot scan on first F8 open handles the case where
-- those Blueprint callbacks have not fired since this Lua mod loaded.

local ui_scan_startup_candidates = nil

local uiActive = {
    weapon = nil,
    slot_tag = nil,
    container = nil,
    uid = nil,
    firearm = false,
}

local uiEquipped = {}
local uiPendingEquipped = {}
local uiLastStateSignature = nil
local uiLastEquippedSignature = {}

-- Popup-style lifecycle. ExecuteWithDelay cannot be cancelled, so a generation
-- token invalidates older close callbacks whenever the popup is reopened or a
-- weapon switch restarts the timer.
local UI_AUTO_CLOSE_MS = 3000
local uiCloseGeneration = 0

local function ui_normalize_weapon_name(name)
    if name == nil then return nil end
    local n = tostring(name):lower()
    n = n:gsub("^bp_", "")
    n = n:gsub("pickup_c$", "")
    n = n:gsub("pickup$", "")
    n = n:gsub("_c$", "")
    n = n:gsub("[^%w]", "")
    return n
end

local function ui_uid_matches_weapon(uid, weaponName)
    if uid == nil or weaponName == nil then return false end

    local r = records[uid]
    if r == nil then return false end

    return ui_normalize_weapon_name(r.weapon) ==
           ui_normalize_weapon_name(weaponName)
end

local function ui_promote_pending_for_active_weapon()
    local container = uiActive.container
    if container == nil then return false end

    local pending = uiPendingEquipped[container]
    if pending == nil or pending.uid == nil then return false end

    -- A DB-backed name match is authoritative enough for the UI bridge.
    if ui_uid_matches_weapon(pending.uid, uiActive.weapon) then
        uiEquipped[container] = pending
        uiPendingEquipped[container] = nil
        return true
    end

    -- For a genuinely untracked weapon, allow the candidate only if we do not
    -- already hold a DB-confirmed mapping for the current active weapon.
    local current = uiEquipped[container]
    if current == nil or
       not ui_uid_matches_weapon(current.uid, uiActive.weapon)
    then
        if records[pending.uid] == nil then
            uiEquipped[container] = pending
            uiPendingEquipped[container] = nil
            return true
        end
    end

    return false
end

local function ui_cancel_auto_close()
    uiCloseGeneration = uiCloseGeneration + 1
end

local function ui_arm_auto_close()
    if UI == nil then return end

    uiCloseGeneration = uiCloseGeneration + 1
    local generation = uiCloseGeneration

    ExecuteWithDelay(UI_AUTO_CLOSE_MS, function()
        if generation ~= uiCloseGeneration then return end

        ExecuteInGameThread(function()
            if generation ~= uiCloseGeneration or UI == nil then return end

            local okOpen, isOpen = pcall(function()
                return UI.IsOpen()
            end)

            if okOpen and isOpen then
                pcall(function()
                    UI.Hide()
                end)
            end
        end)
    end)
end

local function ui_restart_auto_close_if_open()
    if UI == nil then return end

    local okOpen, isOpen = pcall(function()
        return UI.IsOpen()
    end)

    if okOpen and isOpen then
        ui_arm_auto_close()
    end
end

local function ui_slot_tag_to_container(tag)
    if tag == "Jig.PlayerSlot.PrimaryWeapon" then
        return "CPrimary", true
    elseif tag == "Jig.PlayerSlot.SecondaryWeapon" then
        return "CSecondary", true
    elseif tag == "Jig.PlayerSlot.SidearmWeapon" then
        if uiEquipped.CPistol ~= nil then return "CPistol", true end
        return "CSidearm", true
    elseif tag == "Jig.PlayerSlot.MeleeWeapon" then
        return "CMelee", false
    end
    return nil, false
end

local function ui_container_name(context)
    local name = full_name(context)
    for _, candidate in ipairs({"CPrimary", "CSecondary", "CPistol", "CSidearm", "CMelee"}) do
        if name:find("." .. candidate .. ".", 1, true) ~= nil
            or name:match("%." .. candidate .. "$") ~= nil
        then
            return candidate
        end
    end
    return nil
end

local function ui_slot_uid(slot)
    local raw = nil
    local ok = pcall(function() raw = slot[FIELDS.item_unique_id] end)
    if not ok or raw == nil then return nil end
    return guid_to_string(raw)
end

local function ui_update_active_from_slot()
    local container, firearm = ui_slot_tag_to_container(uiActive.slot_tag)
    uiActive.container = container
    uiActive.firearm = firearm
    uiActive.uid = nil

    if container ~= nil and uiEquipped[container] ~= nil then
        uiActive.uid = uiEquipped[container].uid
    end
end

local function ui_state_signature()
    return table.concat({
        tostring(uiActive.weapon),
        tostring(uiActive.slot_tag),
        tostring(uiActive.container),
        tostring(uiActive.uid),
        tostring(uiActive.firearm),
    }, "|")
end

local function ui_log_state(reason)
    local sig = ui_state_signature()
    if sig == uiLastStateSignature then return end
    uiLastStateSignature = sig
    log("UI STATE | reason=" .. tostring(reason) ..
        " | weapon=" .. tostring(uiActive.weapon) ..
        " | slot=" .. tostring(uiActive.slot_tag) ..
        " | container=" .. tostring(uiActive.container) ..
        " | uid=" .. tostring(uiActive.uid) ..
        " | firearm=" .. tostring(uiActive.firearm))
end

local function ui_refresh_if_open()
    if UI == nil then return end
    local okOpen, isOpen = pcall(function() return UI.IsOpen() end)
    if okOpen and isOpen then
        local okRefresh, err = pcall(function() UI.Refresh() end)
        if not okRefresh then log("UI ERROR | refresh failed | " .. tostring(err)) end
    end
end

-- Whole numbers stay whole; small stats such as a 7.76 stamina cost keep one
-- decimal so a 3% change is still visible.
local function display_stat_value(v)
    local n = tonumber(v)
    if n == nil then return nil end
    local rounded = math.floor(n + (n >= 0 and 0.5 or -0.5))
    if math.abs(n - rounded) < 0.05 then return tostring(rounded) end
    return string.format("%.1f", n)
end

-- F8 rows are shared with firearms. Melee stats borrow them in this order:
-- damage, crit mult, crit chance, then stamina cost in the RPM row and attack
-- speed in the falloff row.
local MELEE_UI_ROWS = { meleedamage = "damage", critmult = "critmult", critchance = "critchance", staminadrain = "rpm" }

local function melee_row_labels()
    return {
        damage = tr("melee_dmg_short"), critmult = tr("crit_mult"), critchance = tr("crit_chance"),
        rpm = tr("stamina_short"), falloff = tr("attack_speed"),
    }
end

local function melee_progression_state()
    local weaponName = tostring(uiActive.weapon)
    if MeleeProgression == nil or MeleeProgression.Config.Enabled ~= true then
        return { weapon = weaponName, status = tr("no_firearm_progression") }
    end
    if uiActive.uid == nil then
        return { weapon = weaponName, status = tr("resolving_weapon") }
    end

    local labels = melee_row_labels()
    local r = MeleeProgression.Records()[uiActive.uid]
    if r == nil then
        return { weapon = weaponName, level = 1, xp_percent = 0, row_labels = labels, stats = {} }
    end

    local MP = MeleeProgression.Progression
    local MC = MeleeProgression.Config
    local level = math.max(1, math.floor(tonumber(r.level) or 1))
    local xpPercent = 100
    if level < MC.MaxLevel then
        local needed = MP.XPRequired(level)
        xpPercent = (needed and needed > 0) and math.max(0, math.min(100, ((tonumber(r.xp) or 0) / needed) * 100)) or 0
    end

    local uiStats = {}
    r.bases = r.bases or {}
    r.upgrades = r.upgrades or {}
    for _, def in ipairs(MeleeProgression.STAT_DEFS or {}) do
        local base = tonumber(r.bases[def.key])
        if base ~= nil then
            local target = MP.StatTarget(def, base, math.floor(tonumber(r.upgrades[def.key]) or 0), r)
            if target ~= nil then
                uiStats[#uiStats + 1] = {
                    key = def.key, row = MELEE_UI_ROWS[def.key],
                    base = display_stat_value(base), current = display_stat_value(target),
                    bonus = progression_bonus_label(def, base, target),
                }
            end
        end
    end
    local speed = MeleeProgression.AttackSpeedPercent(level) or 0
    uiStats[#uiStats + 1] = {
        key = "attackspeed", row = "falloff", base = "100%",
        current = display_stat_value(100 + speed) .. "%",
        bonus = speed > 0 and ("+" .. display_stat_value(speed) .. "%") or nil,
    }

    local currentRank, nextRank = MP.GetRankInfo(level)
    local nextBonus = nil
    if nextRank ~= nil then
        if nextRank.bonus_type == "AttackSpeedPercent" then
            nextBonus = tr("attack_speed") .. " +" .. tostring(display_stat_value(nextRank.value)) .. "%"
        else
            nextBonus = MP.MilestoneDescription(nextRank, r)
        end
    end

    return {
        weapon = tostring(r.weapon or weaponName),
        level = level,
        xp_percent = xpPercent,
        rank = currentRank and display_rank(currentRank.rank) or nil,
        next_rank = nextRank and display_rank(nextRank.rank) or nil,
        next_level = nextRank and tonumber(nextRank.level) or nil,
        next_bonus = nextBonus,
        stats = uiStats,
        row_labels = labels,
    }
end

local function ui_progression_state()
    if uiActive.weapon == nil or uiActive.weapon == "" then
        return { weapon = tr("no_active_weapon"), status = tr("no_progression_data") }
    end

    if uiActive.container == "CMelee" or
       uiActive.slot_tag == "Jig.PlayerSlot.MeleeWeapon" then
        return melee_progression_state()
    end

    if uiActive.uid == nil then
        return { weapon = tostring(uiActive.weapon), status = tr("resolving_weapon") }
    end

    local r = records[uiActive.uid]
    if r == nil then
        return {
            weapon = tostring(uiActive.weapon),
            level = 1,
            xp_percent = 0,
        }
    end

    local level = math.max(1, math.floor(tonumber(r.level) or 1))
    local xpPercent = 0

    if level >= Config.MaxLevel then
        xpPercent = 100
    else
        local needed = xp_required(level)
        if needed ~= nil and needed > 0 then
            xpPercent = math.max(0, math.min(100,
                ((tonumber(r.xp) or 0) / needed) * 100))
        end
    end

    local currentRank, nextRank = get_rank_info(level)

    local uiStats = {}
    r.bases = r.bases or {}
    r.upgrades = r.upgrades or {}
    for _, def in ipairs(STAT_DEFS) do
        local base = tonumber(r.bases[def.key])
        if base ~= nil then
            local count = math.floor(tonumber(r.upgrades[def.key]) or 0)
            local target = stat_target(def, base, count, r)
            if target ~= nil then
                uiStats[#uiStats + 1] = {
                    key = def.key,
                    base = math.floor(base + 0.5),
                    current = math.floor(target + 0.5),
                    bonus = progression_bonus_label(def, base, target),
                }
            end
        end
    end

    return {
        weapon = tostring(r.weapon or uiActive.weapon or tr("unknown_weapon")),
        level = level,
        xp_percent = xpPercent,
        rank = currentRank and display_rank(currentRank.rank) or nil,
        next_rank = nextRank and display_rank(nextRank.rank) or nil,
        next_level = nextRank and tonumber(nextRank.level) or nil,
        next_bonus = nextRank and milestone_bonus_description(nextRank, r) or nil,
        stats = uiStats,
    }
end


-- ============================================================================
-- Integrated Gunsmith API
-- ============================================================================
-- Dave now lives inside WeaponProgression and consumes progression state
-- directly in memory. No active_weapon.api / reroll.request file bridge is used.

local function gunsmith_snapshot()
    if uiActive.weapon == nil or uiActive.weapon == "" then
        return {
            state = "none",
            weapon = nil,
            slot = uiActive.slot_tag,
            reason = "no active weapon",
        }
    end

    if uiActive.container == "CMelee" or
       uiActive.slot_tag == "Jig.PlayerSlot.MeleeWeapon" or
       uiActive.firearm ~= true then
        return {
            state = "none",
            weapon = tostring(uiActive.weapon),
            slot = uiActive.slot_tag,
            reason = "active item is not a firearm",
        }
    end

    if uiActive.uid == nil then
        -- Reuse WeaponProgression's proven startup resolver. This covers saves
        -- loaded with an already-held firearm before a weapon switch occurs.
        pcall(function() ui_scan_startup_candidates() end)
    end

    if uiActive.uid == nil then
        return {
            state = "unresolved",
            weapon = tostring(uiActive.weapon),
            slot = uiActive.slot_tag,
            reason = "physical weapon UID is still resolving",
        }
    end

    local uid = uiActive.uid
    local r = records[uid]
    if r == nil then
        return {
            state = "untracked",
            weapon = tostring(uiActive.weapon),
            uid = uid,
            slot = uiActive.slot_tag,
        }
    end

    local level = math.max(1, math.floor(tonumber(r.level) or 1))
    local currentRank = select(1, get_rank_info(level))
    local rolls = 0
    local stats = {}

    r.bases = r.bases or {}
    r.upgrades = r.upgrades or {}

    for _, def in ipairs(STAT_DEFS) do
        local count = math.max(0, math.floor(tonumber(r.upgrades[def.key]) or 0))
        rolls = rolls + count

        local base = tonumber(r.bases[def.key])
        if base ~= nil then
            local target = stat_target(def, base, count, r)
            if target ~= nil then
                stats[def.key] = {
                    base = math.floor(base + 0.5),
                    current = math.floor(target + 0.5),
                    bonus = progression_bonus_label(def, base, target),
                }
            end
        end
    end

    return {
        state = "tracked",
        weapon = tostring(r.weapon or uiActive.weapon or tr("unknown_weapon")),
        uid = uid,
        slot = uiActive.slot_tag,
        level = level,
        xp = math.max(0, tonumber(r.xp) or 0),
        kills = math.max(0, math.floor(tonumber(r.kills) or 0)),
        rank = currentRank and display_rank(currentRank.rank) or nil,
        ordinary_rolls = rolls,
        stats = stats,
    }
end

local function gunsmith_copy_upgrade_counts(r)
    local out = {}
    r.upgrades = r.upgrades or {}
    for _, def in ipairs(STAT_DEFS) do
        out[def.key] = math.max(0, math.floor(tonumber(r.upgrades[def.key]) or 0))
    end
    return out
end

local function gunsmith_upgrade_counts_equal(a, b)
    for _, def in ipairs(STAT_DEFS) do
        if (a[def.key] or 0) ~= (b[def.key] or 0) then
            return false
        end
    end
    return true
end

local function gunsmith_generate_distribution(r, rollCount)
    local eligible = {}
    r.bases = r.bases or {}

    for _, def in ipairs(STAT_DEFS) do
        if r.bases[def.key] ~= nil then
            eligible[#eligible + 1] = def
        end
    end

    if #eligible == 0 then
        return nil, nil, tr("reroll_no_stats")
    end
    if rollCount <= 0 then
        return nil, nil, tr("reroll_no_rolls")
    end

    local counts = {}
    for _, def in ipairs(STAT_DEFS) do
        counts[def.key] = 0
    end

    -- Roll against a scratch record so caps (including the weapon's current
    -- milestone bonuses) are evaluated with the counts rolled so far.
    local scratch = { bases = r.bases, level = r.level, upgrades = counts }
    local last = ""
    for _ = 1, rollCount do
        local choices = {}
        for _, def in ipairs(eligible) do
            if not FirearmProgression.IsCapped(def, scratch) then choices[#choices + 1] = def end
        end
        -- Every stat capped: remaining rolls could not improve anything.
        if #choices == 0 then break end
        local uncapped = choices

        if Config.PreventConsecutiveSameStat and #uncapped > 1 and last ~= "" then
            choices = {}
            for _, def in ipairs(uncapped) do
                if def.key ~= last then
                    choices[#choices + 1] = def
                end
            end
            if #choices == 0 then choices = uncapped end
        end

        local chosen = choices[math.random(1, #choices)]
        counts[chosen.key] = (counts[chosen.key] or 0) + 1
        last = chosen.key
    end

    return counts, last, nil
end

local function gunsmith_reroll(uid)
    if uid == nil or uid == "" then
        return false, tr("reroll_no_uid")
    end

    -- Dave is only allowed to touch the firearm currently in the player's hand.
    if uiActive.uid ~= uid then
        return false, tr("reroll_weapon_changed")
    end

    local r = records[uid]
    if r == nil then
        return false, tr("reroll_record_missing")
    end

    local level = math.max(1, math.floor(tonumber(r.level) or 1))
    if level < 5 then
        return false, tr("reroll_min_level")
    end

    local oldCounts = gunsmith_copy_upgrade_counts(r)
    local rollCount = 0
    for _, def in ipairs(STAT_DEFS) do
        rollCount = rollCount + (oldCounts[def.key] or 0)
    end

    if rollCount <= 0 then
        return false, tr("reroll_no_rewards")
    end

    local oldLast = r.last_upgrade or ""
    local newCounts, newLast, err

    -- Avoid returning an identical distribution where another outcome exists.
    for _ = 1, 20 do
        newCounts, newLast, err = gunsmith_generate_distribution(r, rollCount)
        if newCounts == nil then
            return false, err
        end
        if not gunsmith_upgrade_counts_equal(oldCounts, newCounts) then
            break
        end
    end

    if gunsmith_upgrade_counts_equal(oldCounts, newCounts) then
        return false, tr("reroll_same_distribution")
    end

    r.upgrades = newCounts
    r.last_upgrade = newLast or ""

    if not save_db() then
        r.upgrades = oldCounts
        r.last_upgrade = oldLast
        return false, tr("reroll_save_failed")
    end

    if reconcile_weapon_stats ~= nil then
        reconcile_weapon_stats(uid, r.weapon, "gunsmith_reroll")
    end

    if uiActive.uid == uid then
        ui_refresh_if_open()
    end

    log("GUNSMITH REROLL | SUCCESS | " .. tostring(r.weapon) ..
        " | uid=" .. tostring(uid) ..
        " | rolls=" .. tostring(rollCount))

    return true, tr("reroll_success")
end

ui_scan_startup_candidates = function()
    if uiActive.uid ~= nil or uiActive.weapon == nil then return false end

    local okFind, slots = pcall(function() return FindAllOf(JSI_SLOT_CLASS) end)
    if not okFind or slots == nil then return false end

    local count = safe_array_length(slots)
    if count == nil then pcall(function() count = #slots end) end
    if count == nil or count == 0 then return false end

    local target = ui_normalize_weapon_name(uiActive.weapon)
    local matches = {}
    local seenUid = {}

    for i = 1, count do
        local slot = nil
        pcall(function() slot = slots[i] end)
        if slot ~= nil then
            local full = full_name(slot)
            local container = nil

            for _, candidate in ipairs({"CPrimary", "CSecondary", "CPistol", "CSidearm", "CMelee"}) do
                local pattern = ""
                -- Exact top-level JSI slot pattern used by the proven UIResearch
                -- startup resolver. Build it here to avoid matching nested slots.
                pattern = "%." .. candidate .. "%.WidgetTree_%d+%.JSI_Slot_C_%d+$"
                if full:match(pattern) ~= nil then
                    container = candidate
                    break
                end
            end

            if container ~= nil then
                local uid = ui_slot_uid(slot)
                if uid ~= nil and not seenUid[uid] then
                    seenUid[uid] = true
                    local r = records[uid]
                    if r ~= nil and ui_normalize_weapon_name(r.weapon) == target then
                        matches[#matches + 1] = {
                            uid = uid,
                            container = container,
                            slot = slot,
                        }
                    end
                end
            end
        end
    end

    if #matches == 1 then
        local m = matches[1]
        uiEquipped[m.container] = { uid = m.uid, slot = m.slot }
        uiActive.container = m.container
        uiActive.uid = m.uid
        uiActive.firearm = m.container ~= "CMelee"
        ui_log_state("startup_scan")
        return true
    end

    if #matches > 1 then
        log("UI STARTUP | ambiguous equipped DB matches for " ..
            tostring(uiActive.weapon) .. " | count=" .. tostring(#matches) ..
            " | waiting for active slot callback")
    end
    return false
end

local function ui_on_get_active_weapon(Context, ActiveWeapon, ...)
    local pickup = unwrap(ActiveWeapon)
    local name = full_name(pickup):match("BP_([%w_]+)Pickup_C")

    -- GetActiveWeapon briefly emits transient UObject wrappers during slot
    -- transitions. Ignore anything that is not a real pickup Blueprint.
    if name == nil or name == "" then return end

    local changed = uiActive.weapon ~= name

    uiActive.weapon = name

    -- GetEquippedItemRef commonly fires before GetActiveWeapon during a switch.
    -- Promote the queued candidate now that we know the new authoritative name.
    ui_promote_pending_for_active_weapon()
    ui_update_active_from_slot()

    ui_log_state("active_weapon")
    ui_refresh_if_open()

    -- Weapon switches turn the panel into a fresh 3-second popup. Routine
    -- repeated GetActiveWeapon callbacks do not extend its lifetime.
    if changed then
        ui_restart_auto_close_if_open()
    end
end

local function ui_on_get_active_weapon_slot(Context, SlotTag, ...)
    local raw = unwrap(SlotTag)
    local tag = decode_gameplay_tag(raw)
    if tag == nil then return end

    local previousTag = uiActive.slot_tag

    if tag == "None" then
        uiActive.slot_tag = nil
        uiActive.container = nil
        uiActive.uid = nil
        uiActive.firearm = false
    else
        uiActive.slot_tag = tag
        ui_update_active_from_slot()
    end

    ui_log_state("active_slot")
    ui_refresh_if_open()

    -- A real slot change is a weapon switch, so reset popup lifetime.
    -- Ignore the transient None phase; the real destination tag will follow.
    if tag ~= "None" and tag ~= previousTag then
        ui_restart_auto_close_if_open()
    end
end

local function ui_on_get_equipped_item_ref(Context, Found, ItemRef, IsPending, ...)
    local found = unwrap(Found)
    local slot = unwrap(ItemRef)
    if found ~= true or slot == nil then return end

    local container = ui_container_name(Context)
    if container == nil then return end

    local uid = ui_slot_uid(slot)
    if uid == nil then return end

    local candidate = { uid = uid, slot = slot }
    local isActiveContainer = container == uiActive.container

    if isActiveContainer then
        -- During combat SurrounDead can expose alternate/stub JSI slots for the
        -- same container. Never replace a known-good DB-backed active UID with
        -- an unrelated candidate. Queue it until GetActiveWeapon confirms the
        -- new weapon name during an actual switch.
        if ui_uid_matches_weapon(uid, uiActive.weapon) then
            uiEquipped[container] = candidate
            uiPendingEquipped[container] = nil
        else
            local current = uiEquipped[container]

            if current ~= nil and
               ui_uid_matches_weapon(current.uid, uiActive.weapon)
            then
                uiPendingEquipped[container] = candidate
            else
                -- No confirmed mapping yet. Preserve the candidate so the
                -- following active-weapon callback can validate/promote it.
                uiPendingEquipped[container] = candidate

                if uiActive.weapon == nil or records[uid] == nil then
                    uiEquipped[container] = candidate
                end
            end
        end
    else
        -- Non-active containers can be cached freely for the next switch.
        uiEquipped[container] = candidate
        uiPendingEquipped[container] = nil
    end

    local sig = tostring(uid)
    if uiLastEquippedSignature[container] ~= sig then
        uiLastEquippedSignature[container] = sig
        log("UI EQUIPPED | container=" .. tostring(container) .. " | uid=" .. tostring(uid))
    end

    ui_update_active_from_slot()
    ui_log_state("equipped")
    ui_refresh_if_open()

    -- Deliberately do NOT restart auto-close here. GetEquippedItemRef can fire
    -- during combat and inventory maintenance; only actual weapon switches
    -- extend the popup lifetime.
end

if UI ~= nil then
    local okConfig, configErr = pcall(function()
        UI.Configure({
            title = tr("weapon_progression"),
            Translate = tr,
            x = 92,
            y = 250,
            width = 356,
            height = 362,
            z_order = 200,
        })

        UI.SetProvider(ui_progression_state)
    end)

    if not okConfig then
        log("UI MODULE DISABLED | configure/provider failed | " .. tostring(configErr))
        UI = nil
    end
end

local function ui_toggle()
    if UI == nil then
        log("UI ERROR | ui.lua is not loaded")
        return
    end

    local okOpen, isOpen = pcall(function() return UI.IsOpen() end)

    if okOpen and isOpen then
        -- Manual close invalidates any delayed auto-close callback.
        ui_cancel_auto_close()

        local okHide, hideErr = pcall(function()
            UI.Hide()
        end)

        if not okHide then
            log("UI ERROR | F8 close failed | " .. tostring(hideErr))
        end
        return
    end

    if uiActive.uid == nil then
        ui_scan_startup_candidates()
    end

    local okShow, showErr = pcall(function()
        UI.Show()
    end)

    if not okShow then
        log("UI ERROR | F8 open failed | " .. tostring(showErr))
        return
    end

    ui_arm_auto_close()
end

-- ============================================================================
-- Persistence - data.db v2 (Scripts/core/persistence.lua)
-- ============================================================================
local Persistence = nil

do
    local path = MOD_DIR .. "/Scripts/core/persistence.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            Persistence = moduleOrErr
        else
            log("PERSISTENCE LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("PERSISTENCE LOAD FAILED | " .. tostring(chunkOrErr))
    end
end

local function load_db()
    if Persistence == nil then
        log("ERROR: persistence module unavailable; progression database not loaded.")
        records = {}
        return
    end
    records = Persistence.Load(DB_PATHS, log)
end

save_db = function()
    if Persistence == nil then return false end
    return Persistence.Save(records, log)
end

-- ============================================================================
-- Weapon progression + persistent stat upgrades
-- ============================================================================

stat_target = function(def, base, upgradeCount, record)
    return FirearmProgression.StatTarget(def, base, upgradeCount, record)
end

local FirearmStats = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/stats.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" and FirearmResolver ~= nil then
            local okNew, instanceOrErr = pcall(moduleOrErr.New, {
                log=log, Resolver=FirearmResolver, StatDefs=STAT_DEFS,
                records=function() return records end,
                stat_target=function(def,base,count,r) return stat_target(def,base,count,r) end,
            })
            if okNew then FirearmStats=instanceOrErr else log("FIREARM STATS INIT FAILED | " .. tostring(instanceOrErr)) end
        else log("FIREARM STATS LOAD FAILED | " .. tostring(moduleOrErr)) end
    else log("FIREARM STATS LOAD FAILED | " .. tostring(chunkOrErr)) end
end

local function apply_stat_target(uid,weaponName,def,target,reason)
    return FirearmStats and FirearmStats.Apply(uid,weaponName,def,target,reason) or false
end
reconcile_weapon_stats=function(uid,weaponName,reason)
    return FirearmStats and FirearmStats.Reconcile(uid,weaponName,reason) or false
end

local show_level_up_notification = nil

local function choose_upgrade_def(r)
    return FirearmProgression.ChooseUpgradeDef(r)
end

local function award_stat_upgrade(uid, weaponName, newLevel)
    local r=records[uid]
    if not r then return false end
    local def,noDefReason=choose_upgrade_def(r)
    if not def and noDefReason == "capped" then
        -- Every captured stat is already at its cap. The level still counts
        -- (rank/milestones are level-derived) but there is nothing left for an
        -- ordinary reward to improve, so consume it instead of banking it.
        local saved=save_db()
        log("STAT UPGRADE SKIPPED | " .. tostring(weaponName) .. " | " .. uid .. " | L" .. tostring(newLevel) .. " | all captured stats capped | saved=" .. tostring(saved))
        return true
    end
    if not def then
        r.pending_rewards=(r.pending_rewards or 0)+1
        local saved=save_db()
        log("STAT UPGRADE PENDING | " .. tostring(weaponName) .. " | " .. uid .. " | L" .. tostring(newLevel) .. " | no captured eligible stats yet | pending=" .. tostring(r.pending_rewards) .. " | saved=" .. tostring(saved))
        return false
    end

    local previousLastUpgrade = r.last_upgrade
    r.upgrades[def.key]=(r.upgrades[def.key] or 0)+1
    r.last_upgrade=def.key
    local base=r.bases[def.key]
    local target=stat_target(def,base,r.upgrades[def.key],r)

    -- Persist the earned reward BEFORE attempting the runtime write. A failed
    -- persistence write must never create a live-only upgrade that disappears
    -- on restart, so roll the in-memory reward back and defer application.
    local saved=save_db()
    if not saved then
        r.upgrades[def.key]=math.max(0,(r.upgrades[def.key] or 1)-1)
        r.last_upgrade=previousLastUpgrade or ""
        r.pending_rewards=(r.pending_rewards or 0)+1
        log("STAT UPGRADE DEFERRED | " .. tostring(weaponName) .. " | " .. tostring(uid) ..
            " | L" .. tostring(newLevel) .. " | database write failed; live mutation refused")
        return false
    end

    log(string.format(
        "STAT UPGRADE AWARDED | %s | %s | L%d | %s | base=%.6g | count=%d | target=%.6g | saved=%s",
        weaponName,uid,newLevel,def.tag,base,r.upgrades[def.key],target,tostring(saved)
    ))

    local applied=apply_stat_target(uid,weaponName,def,target,"level_up")
    log("STAT UPGRADE RESULT | " .. tostring(weaponName) .. " | " .. def.tag .. " | applied=" .. tostring(applied))
    if applied then
        -- Do not re-enter the Blueprint VM with CreateNotificationUI while the
        -- damage/death hook is still unwinding. A one-tick defer proved safer
        -- in the community fork and does not change progression semantics.
        local toastWeapon,toastLevel,toastDef=weaponName,newLevel,def
        ExecuteWithDelay(1,function()
            ExecuteInGameThread(function()
                show_level_up_notification(toastWeapon,toastLevel,toastDef)
            end)
        end)
    end
    return true
end

process_pending_rewards = function(uid, weaponName)
    local r=records[uid]
    if not r or (r.pending_rewards or 0) <= 0 then return end
    local pending=r.pending_rewards
    r.pending_rewards=0
    log("PENDING REWARDS | " .. tostring(weaponName or r.weapon) .. " | " .. uid .. " | processing=" .. tostring(pending))
    for _=1,pending do
        local ok=award_stat_upgrade(uid,weaponName or r.weapon,r.level)
        if not ok then
            -- award_stat_upgrade has restored one pending reward if it still cannot roll.
            local remaining=pending-_
            r.pending_rewards=(r.pending_rewards or 0)+remaining
            break
        end
    end
    save_db()
end

if FirearmResolver ~= nil then
    FirearmResolver.SetCallbacks(function(uid,weaponName)
        if process_pending_rewards then process_pending_rewards(uid,weaponName) end
    end, function(uid,weaponName,reason)
        if reconcile_weapon_stats then reconcile_weapon_stats(uid,weaponName,reason) end
    end)
end

-- ============================================================================
-- Native level-up notifications
-- ============================================================================

-- v0.12.10 proved the safe text path:
-- Lua string -> KismetTextLibrary:Conv_StringToText -> genuine FText ->
-- GameFunctionLibrary:CreateNotificationUI -> native SurrounDead HUD toast.
--
-- Production notifications do not borrow wrappers from another notification.
-- FText and LinearColor are created fresh for each level-up, and the player is
-- resolved fresh as the WorldContext object. A nil icon intentionally produces
-- a neutral text toast without depending on a game texture asset.
local FirearmNotifications = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/notifications.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            local okNew, instanceOrErr = pcall(moduleOrErr.New, { Config = Config, Log = log, Translate = tr })
            if okNew then FirearmNotifications = instanceOrErr else log("FIREARM NOTIFICATIONS INIT FAILED | " .. tostring(instanceOrErr)) end
        else
            log("FIREARM NOTIFICATIONS LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("FIREARM NOTIFICATIONS LOAD FAILED | " .. tostring(chunkOrErr))
    end
end

show_level_up_notification = function(weaponName,newLevel,def)
    if FirearmNotifications == nil then
        log("LEVEL TOAST SKIP | firearm notifications module unavailable")
        return false
    end
    return FirearmNotifications.Show(weaponName,newLevel,def)
end

-- ============================================================================
-- Firearm event / kill-attribution boundary (Scripts/firearms/events.lua)
-- ============================================================================
local FirearmEvents = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/events.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            local okNew, instanceOrErr = pcall(moduleOrErr.New, {
                Config = Config,
                log = log,
                unwrap = unwrap,
                guid_to_string = guid_to_string,
                short_name = short_name,
                same_object = same_object,
                ensure_record = ensure_record,
                get_record = function(uid) return records[uid] end,
                xp_required = xp_required,
                milestone_bonus_description = milestone_bonus_description,
                award_stat_upgrade = award_stat_upgrade,
                reconcile_weapon_stats = function(uid, weaponName, reason)
                    return reconcile_weapon_stats and reconcile_weapon_stats(uid, weaponName, reason) or false
                end,
                save_db = function() return save_db and save_db() or false end,
                probe_active_firearm_slot = probe_active_firearm_slot,
                refresh_ui_if_active = function(uid)
                    if uiActive.uid == uid then ui_refresh_if_open() end
                end,
            })
            if okNew then FirearmEvents = instanceOrErr else log("FIREARM EVENTS INIT FAILED | " .. tostring(instanceOrErr)) end
        else
            log("FIREARM EVENTS LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("FIREARM EVENTS LOAD FAILED | " .. tostring(chunkOrErr))
    end
end

local function safe_call(obj, method, ...)
    if obj == nil then return nil, false end
    local args = {...}
    local ok, result = pcall(function()
        return obj[method](obj, table.unpack(args))
    end)
    if ok then return result, true end
    return nil, false
end

local function textblock_text(obj)
    if obj == nil then return nil end
    local u = unwrap(obj)
    if u == nil then return nil end
    local ok, txt = pcall(function() return u:GetText() end)
    if not ok or txt == nil then return nil end
    local raw = unwrap(txt)
    local ok2, s = pcall(function() return raw:ToString() end)
    if ok2 and s ~= nil then return tostring(s) end
    return tostring(raw)
end

local function field_text(obj, field)
    local v, ok = safe_field(obj, field)
    if not ok or v == nil then return nil end
    local u = unwrap(v)
    if u == nil then return nil end

    if type(u) == "string" or type(u) == "number" or type(u) == "boolean" then
        return tostring(u)
    end

    local tb = textblock_text(u)
    if tb ~= nil then return tb end

    local ok2, s = pcall(function() return u:ToString() end)
    if ok2 and s ~= nil then return tostring(s) end

    return full_name(u)
end


-- Current native tooltip weapon context. Update() runs before the individual
-- BP_StatW widgets are constructed, so this gives their Construct hook a safe,
-- read-only lookup of the persisted enhancement for the weapon being rendered.
local tooltipBonusContext = nil

-- Extra Level / XP / Kills / Rank rows require creating additional tooltip
-- widgets and have caused native access violations on some UE4SS builds.
-- Disabled by default through config.ini; F8 remains the detailed progression view.

local function display_number(v)
    local n = tonumber(v)
    if n == nil then return nil end
    local rounded = math.floor((n * 10) + (n >= 0 and 0.5 or -0.5)) / 10
    if math.abs(rounded - math.floor(rounded + 0.5)) < 0.000001 then
        return tostring(math.floor(rounded + 0.5))
    end
    return string.format("%.1f", rounded):gsub("0+$", ""):gsub("%.$", "")
end

local function display_integer(v)
    local n = tonumber(v)
    if n == nil then return nil end
    return tostring(math.floor(n + (n >= 0 and 0.5 or -0.5)))
end

local function bonus_text(v)
    local n = tonumber(v) or 0
    if math.abs(n) < 0.000001 then return nil end
    return display_integer(n)
end

progression_bonus_label = function(def, base, target)
    base = tonumber(base)
    target = tonumber(target)
    if def == nil or base == nil or target == nil then return nil end
    if def.mode == "percent" or def.mode == "reduce" then
        if math.abs(base) < 0.000001 then return nil end
        local pct = ((target / base) - 1.0) * 100.0
        if math.abs(pct) < 0.000001 then return nil end
        return (pct >= 0 and "+" or "") .. display_integer(pct) .. "%"
    end
    local points = target - base
    if math.abs(points) < 0.000001 then return nil end
    return (points >= 0 and "+" or "") .. display_integer(points)
end

local tooltipTextLibrary = nil

local function get_tooltip_text_library()
    if tooltipTextLibrary ~= nil then return tooltipTextLibrary end
    local okLib, lib = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    end)
    if okLib and lib ~= nil then tooltipTextLibrary = lib end
    return tooltipTextLibrary
end

local function set_textblock_text(block, value)
    local b = unwrap(block)
    if b == nil then return false, "block=nil" end
    local textLib = get_tooltip_text_library()
    if textLib == nil then return false, "KismetTextLibrary unavailable" end
    local okSet, err = pcall(function()
        local ftext = textLib:Conv_StringToText(tostring(value or ""))
        if ftext == nil then error("Conv_StringToText returned nil") end
        b:SetText(ftext)
    end)
    return okSet, err
end

local function unit_suffix(unit)
    unit = trim(unit or "")
    if unit == "" or unit == "None" then return "" end
    if unit == "%" then return "%" end
    return " " .. unit
end

-- prog: optional { XPRequired, GetRankInfo } for melee records; firearms by default.
local function add_progression_rows(tooltip, r, weaponName, prog)
    local t = unwrap(tooltip)
    if t == nil or r == nil then return false end

    local grid = nil
    pcall(function() grid = unwrap(t["TextStatsGrid"]) end)
    if grid == nil then
        log("TOOLTIP PROGRESSION SKIP | " .. tostring(weaponName) .. " | TextStatsGrid unavailable")
        return false
    end

    -- Do not duplicate rows if Update fires repeatedly on the same tooltip instance.
    local count = nil
    local countValue, countOk = safe_call(grid, "GetChildrenCount")
    if countOk then count = tonumber(unwrap(countValue)) end
    if count ~= nil then
        for i = 0, count - 1 do
            local child = nil
            local c, got = safe_call(grid, "GetChildAt", i)
            if got then child = unwrap(c) end
            if child ~= nil and field_text(child, "TextBlock_56") == tr("level") then
                log("TOOLTIP PROGRESSION SKIP | " .. tostring(weaponName) .. " | rows already present")
                return true
            end
        end
    end

    local widgetClass = nil
    local okClass, cls = pcall(function()
        return StaticFindObject("/Game/JigSInventory/Jigsaw/Widgets/BP_StatTextW.BP_StatTextW_C")
    end)
    if okClass then widgetClass = cls end
    if widgetClass == nil then
        log("TOOLTIP PROGRESSION SKIP | " .. tostring(weaponName) .. " | BP_StatTextW_C class unavailable")
        return false
    end

    local widgetLib = nil
    local okWbl, wbl = pcall(function()
        return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    end)
    if okWbl then widgetLib = wbl end
    if widgetLib == nil then
        log("TOOLTIP PROGRESSION SKIP | " .. tostring(weaponName) .. " | WidgetBlueprintLibrary unavailable")
        return false
    end

    local needed = prog and prog.XPRequired(r.level or 1) or xp_required(r.level or 1)
    local xp = tonumber(r.xp) or 0
    local xpPercent = 0
    if needed ~= nil and needed > 0 then
        xpPercent = math.max(0, math.min(100, (xp / needed) * 100))
    end
    local currentRank, nextRank
    if prog then currentRank, nextRank = prog.GetRankInfo(r.level or 1)
    else currentRank, nextRank = get_rank_info(r.level or 1) end
    local nextText = tr("max")
    if nextRank ~= nil then
        nextText = tostring(display_rank(nextRank.rank)) .. " @ L" .. tostring(nextRank.level)
    end

    local rows = {
        { label=tr("level"), value=tostring(math.floor(r.level or 1)), row=1, col=1 },
        { label=tr("xp"), value=display_number(xpPercent) .. "%", row=2, col=0 },
        { label=tr("kills"), value=tostring(math.floor(r.kills or 0)), row=2, col=1 },
        { label=tr("rank"), value=currentRank and display_rank(currentRank.rank) or tr("unranked"), row=3, col=0 },
        { label=tr("next"), value=nextText, row=3, col=1 },
    }

    for _, info in ipairs(rows) do
        local child = nil
        local okCreate, created = pcall(function()
            return widgetLib:Create(t, widgetClass, nil)
        end)
        if okCreate then child = unwrap(created) end
        if child == nil then
            log("TOOLTIP PROGRESSION FAILED | " .. tostring(weaponName) .. " | create " .. info.label)
            return false
        end

        local okAdd, slotOrErr = pcall(function()
            return grid:AddChildToUniformGrid(child, info.row, info.col)
        end)
        if not okAdd then
            log("TOOLTIP PROGRESSION FAILED | " .. tostring(weaponName) .. " | add " .. info.label .. " | " .. tostring(slotOrErr))
            return false
        end

        -- BP_StatTextW_C:Construct initializes the child with its blueprint
        -- defaults (Name / None).  Apply our label/value on the next tick so
        -- the blueprint has finished constructing before we overwrite them.
        local delayedChild = child
        local delayedLabel = tostring(info.label)
        local delayedValue = tostring(info.value)
        local delayedWeapon = tostring(weaponName)
        ExecuteWithDelay(1, function()
            ExecuteInGameThread(function()
                local labelBlock, valueBlock = nil, nil
                pcall(function() labelBlock = unwrap(delayedChild["TextBlock_56"]) end)
                pcall(function() valueBlock = unwrap(delayedChild["TextBlock"]) end)

                local okLabel, labelErr = set_textblock_text(labelBlock, delayedLabel)
                local okValue, valueErr = set_textblock_text(valueBlock, delayedValue)
                if okLabel and okValue then
                    log("TOOLTIP PROGRESSION TEXT APPLY | " .. delayedWeapon ..
                        " | " .. delayedLabel .. "=" .. delayedValue)
                else
                    log("TOOLTIP PROGRESSION TEXT FAILED | " .. delayedWeapon ..
                        " | " .. delayedLabel ..
                        " | label=" .. tostring(labelErr) ..
                        " | value=" .. tostring(valueErr))
                end
            end)
        end)

        log("TOOLTIP PROGRESSION ADD | " .. tostring(weaponName) ..
            " | " .. info.label .. "=" .. info.value ..
            " | row=" .. tostring(info.row) .. " col=" .. tostring(info.col) ..
            " | delayed_text=1ms")
    end

    return true
end

-- Tooltip context for a melee weapon tracked in melee.db (nil when untracked).
local function melee_tooltip_context(uid, itemName)
    if MeleeProgression == nil or MeleeProgression.Config.Enabled ~= true then return nil end
    local r = MeleeProgression.Records()[uid]
    if r == nil then return nil end
    local MP = MeleeProgression.Progression
    local weaponName = (r.weapon ~= nil and tostring(r.weapon) ~= "") and tostring(r.weapon) or tostring(itemName)
    local ctx = { uid = uid, weapon = weaponName, record = r, by_tag = {}, prog = MP, melee = true }
    r.bases = r.bases or {}
    r.upgrades = r.upgrades or {}
    local tracked = 0
    for _, def in ipairs(MeleeProgression.STAT_DEFS or {}) do
        local base = tonumber(r.bases[def.key])
        if base ~= nil then
            local count = math.floor(tonumber(r.upgrades[def.key]) or 0)
            local target = MP.StatTarget(def, base, count, r)
            if target ~= nil then
                local bonusLabel = progression_bonus_label(def, base, target)
                if bonusLabel ~= nil then tracked = tracked + 1 end
                ctx.by_tag[def.tag] = { base = base, target = target, bonus_label = bonusLabel }
                log(string.format("TOOLTIP STAT | %s | %s | base=%.3f | target=%.3f | upgrades=%d | melee",
                    weaponName, def.tag, base, target, count))
            end
        end
    end
    log(string.format("TOOLTIP DIAG | MELEE RECORD FOUND | item=%s | uid=%s | L%d | kills=%d | tracked_stats=%d",
        weaponName, uid, math.floor(r.level or 1), math.floor(r.kills or 0), tracked))
    return ctx
end

local function on_tooltip_update(Context, ItemRefParam, ...)
    -- v0.18.2-dev2 diagnostic:
    -- Keep the tooltip path one-way with respect to FText. We may CREATE FText
    -- later for our own rows/values, but do not read/convert live tooltip FText.
    tooltipBonusContext = nil
    log("TOOLTIP DIAG | ENTER")

    local slot = unwrap(ItemRefParam)
    if slot == nil then
        log("TOOLTIP DIAG | ABORT | reason=ItemRef_nil")
        return
    end
    log("TOOLTIP DIAG | SLOT OK | slot=" .. full_name(slot))

    local uidStruct = nil
    local okUid, rawUid = pcall(function() return slot[FIELDS.item_unique_id] end)
    if okUid and rawUid ~= nil then uidStruct = rawUid end

    local uid = guid_to_string(uidStruct)

    local statsCount = nil
    pcall(function() statsCount = safe_array_length(slot["ItemStats"]) end)

    -- IMPORTANT: do not call slot:GetItemName() here. That returns FText on this
    -- path and converting arbitrary live FText is a suspected native-crash edge
    -- on some UE4SS builds. short_name() is UObject-name based and safe enough
    -- for diagnostics; tracked weapons prefer the persisted DB weapon name.
    local itemName = short_name(slot)

    if uid == nil then
        log(string.format(
            "TOOLTIP DIAG | UID UNRESOLVED | item=%s | ItemStats=%s | slot=%s",
            tostring(itemName), tostring(statsCount or "?"), full_name(slot)
        ))
        return
    end
    log("TOOLTIP DIAG | UID OK | uid=" .. tostring(uid) .. " | item=" .. tostring(itemName))

    local r = records[uid]
    if r ~= nil then
        if r.weapon ~= nil and tostring(r.weapon) ~= "" then
            itemName = tostring(r.weapon)
        end

        local needed = xp_required(r.level or 1)
        log(string.format(
            "TOOLTIP DIAG | RECORD FOUND | item=%s | uid=%s | ItemStats=%s | L%d %.3f/%d XP | kills=%d",
            tostring(itemName), uid, tostring(statsCount or "?"),
            math.floor(r.level or 1), tonumber(r.xp or 0) or 0, needed, math.floor(r.kills or 0)
        ))

        local liveStats = {}
        local arr = nil
        pcall(function() arr = slot["ItemStats"] end)
        local arrLen = safe_array_length(arr) or 0
        for i = 1, arrLen do
            local stat = nil
            pcall(function() stat = arr[i] end)
            if stat ~= nil then
                local tag = nil
                local value = nil
                pcall(function() tag = decode_gameplay_tag(stat[FIELDS.stat_name]) end)
                pcall(function() value = tonumber(unwrap(stat[FIELDS.min_value])) end)
                if tag ~= nil and value ~= nil then liveStats[tag] = value end
            end
        end

        local parts = {}
        r.bases = r.bases or {}
        r.upgrades = r.upgrades or {}
        tooltipBonusContext = {
            uid = uid,
            weapon = tostring(itemName),
            record = r,
            by_tag = {},
        }

        for _, def in ipairs(STAT_DEFS) do
            local base = tonumber(r.bases[def.key])
            local count = math.floor(tonumber(r.upgrades[def.key]) or 0)
            local live = liveStats[def.tag]
            if base ~= nil then
                local target = stat_target(def, base, count, r)
                local bonus = (target ~= nil) and (target - base) or 0
                log(string.format(
                    "TOOLTIP STAT | %s | %s | base=%.3f | live=%s | target=%s | bonus=%+.3f | upgrades=%d",
                    tostring(itemName), def.tag, base,
                    live ~= nil and string.format("%.3f", live) or "<missing>",
                    target ~= nil and string.format("%.3f", target) or "<nil>",
                    bonus, count
                ))
                if target ~= nil then
                    local bonusLabel = progression_bonus_label(def, base, target)
                    if bonusLabel ~= nil then
                        parts[#parts + 1] = string.format("%s %s", def.tag, bonusLabel)
                    end
                    tooltipBonusContext.by_tag[def.tag] = {
                        base = base,
                        target = target,
                        bonus_label = bonusLabel,
                    }
                end
            end
        end

        log("TOOLTIP DIAG | CONTEXT BUILT | weapon=" .. tostring(itemName) ..
            " | tracked_stats=" .. tostring(#parts))
    else
        tooltipBonusContext = melee_tooltip_context(uid, itemName)
        if tooltipBonusContext ~= nil then
            itemName = tooltipBonusContext.weapon
        else
            log(string.format(
                "TOOLTIP DIAG | RECORD NOT FOUND | item=%s | uid=%s | ItemStats=%s",
                tostring(itemName), uid, tostring(statsCount or "?")
            ))
        end
    end

    local tooltipContext = unwrap(Context)
    ExecuteWithDelay(75, function()
        ExecuteInGameThread(function()
            local valid = false
            if tooltipContext ~= nil then
                pcall(function() valid = tooltipContext:IsValid() end)
            end
            if valid then
                local ctx = tooltipBonusContext
                if ctx ~= nil and ctx.record ~= nil then
                    if Config.ShowProgressionTooltipRows then
                        log("TOOLTIP DIAG | BEFORE PROGRESSION ROWS | weapon=" .. tostring(ctx.weapon))
                        add_progression_rows(tooltipContext, ctx.record, ctx.weapon, ctx.prog)
                        log("TOOLTIP DIAG | AFTER PROGRESSION ROWS | weapon=" .. tostring(ctx.weapon))
                    else
                        log("TOOLTIP DIAG | PROGRESSION ROWS SKIPPED | weapon=" .. tostring(ctx.weapon) ..
                            " | disabled for compatibility | use F8 for Level/XP/Kills/Rank")
                    end
                end
            else
                log("TOOLTIP DIAG | DELAY ABORT | tooltip no longer valid")
            end
        end)
    end)

    log("TOOLTIP DIAG | UPDATE COMPLETE | item=" .. tostring(itemName))
end


-- ============================================================================
-- Native tooltip stat formatting hooks
-- ============================================================================

local PATH_STAT_W_CONSTRUCT =
    "/Game/JigSInventory/Jigsaw/Widgets/BP_StatW.BP_StatW_C:Construct"

local TOOLTIP_UNIT_BY_TAG = {
    ["Jig.Stat.FirearmDamage"] = "",
    ["Jig.Stat.CriticalHitMultiplier"] = "%",
    ["Jig.Stat.CriticalHitChance"] = "%",
    ["Jig.Stat.FirearmRPM"] = "",
    ["Jig.Stat.DamageFallOff"] = " M",
    ["Jig.Stat.MeleeDamage"] = "",
    ["Jig.Stat.StaminaDrain"] = "",
}

local function on_stat_w_construct(Context, ...)
    -- v0.18.2-dev2 safety rule:
    -- Do not touch unrelated stat widgets, and do not READ any live FText.
    -- Match the row only by its GameplayTag, calculate the display from our
    -- authoritative numeric context, then CREATE fresh FText for SetText().
    local ctx = tooltipBonusContext
    if ctx == nil or ctx.record == nil then return end

    local w = unwrap(Context)
    if w == nil then
        log("TOOLTIP DIAG | STAT ROW ABORT | weapon=" .. tostring(ctx.weapon) .. " | reason=context_nil")
        return
    end

    local tagName = nil
    local rawStatName, statNameOk = safe_field(w, "StatName")
    if statNameOk and rawStatName ~= nil then
        pcall(function() tagName = decode_gameplay_tag(unwrap(rawStatName)) end)
    end

    log("TOOLTIP DIAG | STAT ROW ENTER | weapon=" .. tostring(ctx.weapon) ..
        " | tag=" .. tostring(tagName or "<unresolved>"))

    if tagName == nil then
        log("TOOLTIP DIAG | STAT ROW SKIP | weapon=" .. tostring(ctx.weapon) ..
            " | reason=tag_unresolved")
        return
    end

    local statInfo = ctx.by_tag[tagName]
    if type(statInfo) ~= "table" then
        log("TOOLTIP DIAG | STAT ROW SKIP | weapon=" .. tostring(ctx.weapon) ..
            " | tag=" .. tostring(tagName) .. " | reason=not_progression_stat")
        return
    end

    local effective = tonumber(statInfo.target)
    if effective == nil then
        log("TOOLTIP DIAG | STAT ROW SKIP | weapon=" .. tostring(ctx.weapon) ..
            " | tag=" .. tostring(tagName) .. " | reason=target_nil")
        return
    end

    local valueBlock = nil
    pcall(function() valueBlock = unwrap(w["TextBlock"]) end)
    if valueBlock == nil then
        log("TOOLTIP DIAG | STAT ROW SKIP | weapon=" .. tostring(ctx.weapon) ..
            " | tag=" .. tostring(tagName) .. " | reason=value_block_nil")
        return
    end

    local shown = ctx.melee and display_stat_value(effective) or display_integer(effective)
    local rendered = shown .. (TOOLTIP_UNIT_BY_TAG[tagName] or "")
    local suffix = statInfo.bonus_label
    if suffix ~= nil then
        rendered = rendered .. " (" .. tostring(suffix) .. ")"
    end

    log("TOOLTIP DIAG | BEFORE ROW WRITE | weapon=" .. tostring(ctx.weapon) ..
        " | tag=" .. tostring(tagName) .. " | rendered=" .. tostring(rendered))

    local okSet, setErr = set_textblock_text(valueBlock, rendered)
    if not okSet then
        log("TOOLTIP DIAG | ROW WRITE FAILED | weapon=" .. tostring(ctx.weapon) ..
            " | tag=" .. tostring(tagName) .. " | error=" .. tostring(setErr))
        return
    end

    -- Vanilla may render a separate unit widget. We do not READ it. For rows
    -- whose unit is now folded into our value, clear ExtraTxt using fresh FText.
    if (TOOLTIP_UNIT_BY_TAG[tagName] or "") ~= "" then
        local extraBlock = nil
        pcall(function() extraBlock = unwrap(w["ExtraTxt"]) end)
        if extraBlock ~= nil then
            set_textblock_text(extraBlock, "")
        end
    end

    log("TOOLTIP DIAG | ROW WRITE OK | weapon=" .. tostring(ctx.weapon) ..
        " | tag=" .. tostring(tagName))
end

local function on_inventory_add_cache_invalidate(Context, LocalCompParam, ItemIdParam, CountParam, AddedParam, UIDParam, ...)
    -- v0.14.0-dev2: a dropped/re-picked item can retain the same physical GUID
    -- while SurrounDead creates/rebinds JSI slot state. The old UObject may remain
    -- IsValid(), so GUID + IsValid alone is insufficient. Clear any known cache
    -- entry when this inventory-add path reports that GUID; next damage performs
    -- one authoritative full reacquisition.
    local uid = nil
    pcall(function()
        local uidStruct = UIDParam:get()
        uid = guid_to_string(uidStruct)
    end)

    if uid ~= nil and FirearmResolver ~= nil and FirearmResolver.GetLive(uid) ~= nil then
        local live = FirearmResolver.GetLive(uid)
        local weaponName = live.weapon or (records[uid] and records[uid].weapon) or "Unknown"
        FirearmResolver.Invalidate(uid, weaponName, "JigTryAddItemSomewhere observed same physical GUID")
    end
end

-- ============================================================================
-- Melee progression (Scripts/melee/melee_progression.lua), own melee.db
-- ============================================================================
local function load_melee_progression()
    local path = MOD_DIR .. "/Scripts/melee/melee_progression.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if not okLoad or chunkOrErr == nil then log("MELEE LOAD FAILED | " .. tostring(chunkOrErr)); return end
    local okRun, moduleOrErr = pcall(chunkOrErr)
    if not okRun or type(moduleOrErr) ~= "table" then log("MELEE LOAD FAILED | " .. tostring(moduleOrErr)); return end
    if ProgressionModule == nil or Persistence == nil or FirearmResolver == nil then
        log("MELEE LOAD FAILED | progression, persistence or resolver module unavailable"); return
    end
    local okNew, instanceOrErr = pcall(moduleOrErr.New, {
        log = log, Translate = tr, unwrap = unwrap, short_name = short_name, same_object = same_object,
        guid_to_string = guid_to_string, Fields = FIELDS,
        read_live_stat_map = FirearmResolver.ReadLiveStatMap,
        resolve_player_jig = FirearmResolver.ResolvePlayerJig,
        get_equipped_melee = function() return uiEquipped.CMelee end,
        get_active_container = function() return uiActive.container end,
        ProgressionModule = ProgressionModule, Persistence = Persistence,
        config_path = configPath,
        show_toast = function(weaponName, level, text)
            if FirearmNotifications then return FirearmNotifications.ShowReward(weaponName, level, text) end
        end,
        defer = function(fn) ExecuteWithDelay(1, function() ExecuteInGameThread(fn) end) end,
    })
    if not okNew then log("MELEE INIT FAILED | " .. tostring(instanceOrErr)); return end
    instanceOrErr.Load(candidate_paths("melee.db"))
    MeleeProgression = instanceOrErr
    log("MELEE PROGRESSION | active=" .. tostring(MeleeProgression.Config.Enabled))
end

local hooks = nil
do
    local path = MOD_DIR .. "/Scripts/firearms/hooks.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            hooks = moduleOrErr.Build({
                GET_EQUIPMENT_UID = PATH_GET_EQUIPMENT_UID,
                GET_ACTIVE_WEAPON = PATH_GET_ACTIVE_WEAPON,
                GET_ACTIVE_WEAPON_SLOT = PATH_GET_ACTIVE_WEAPON_SLOT,
                GET_EQUIPPED_ITEM_REF = PATH_GET_EQUIPPED_ITEM_REF,
                JIG_TRY_ADD = PATH_JIG_TRY_ADD,
                TOOLTIP_UPDATE = PATH_TOOLTIP_UPDATE,
                STAT_W_CONSTRUCT = PATH_STAT_W_CONSTRUCT,
                ADD_XP = PATH_ADD_XP,
                DEATH = PATH_DEATH,
                SERVER_DAMAGE = PATH_SERVER_DAMAGE,
                MELEE_HIT_HEAD = PATH_MELEE_HIT_HEAD,
                MELEE_HIT_BODY = PATH_MELEE_HIT_BODY,
            }, {
                on_get_equipment_uid = FirearmEvents and FirearmEvents.OnGetEquipmentUID or nil,
                ui_on_get_active_weapon = ui_on_get_active_weapon,
                ui_on_get_active_weapon_slot = ui_on_get_active_weapon_slot,
                ui_on_get_equipped_item_ref = ui_on_get_equipped_item_ref,
                on_inventory_add_cache_invalidate = on_inventory_add_cache_invalidate,
                on_tooltip_update = on_tooltip_update,
                on_stat_w_construct = on_stat_w_construct,
                on_add_xp = function(...)
                    if FirearmEvents then FirearmEvents.OnAddXP(...) end
                    if MeleeProgression then MeleeProgression.OnAddXP(...) end
                end,
                on_death = function(...)
                    if FirearmEvents then FirearmEvents.OnDeath(...) end
                    if MeleeProgression then MeleeProgression.OnDeath(...) end
                end,
                on_server_damage = FirearmEvents and FirearmEvents.OnServerDamage or nil,
                on_melee_hit = function(...)
                    if MeleeProgression then MeleeProgression.OnHit(...); ui_refresh_if_open() end
                end,
            })
        else
            log("FIREARM HOOK MANIFEST LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("FIREARM HOOK MANIFEST LOAD FAILED | " .. tostring(chunkOrErr))
    end
end


local HookLifecycle = nil
do
    local path = MOD_DIR .. "/Scripts/core/hook_lifecycle.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if okLoad and chunkOrErr ~= nil then
        local okRun, moduleOrErr = pcall(chunkOrErr)
        if okRun and type(moduleOrErr) == "table" then
            HookLifecycle = moduleOrErr
        else
            log("HOOK LIFECYCLE LOAD FAILED | " .. tostring(moduleOrErr))
        end
    else
        log("HOOK LIFECYCLE LOAD FAILED | " .. tostring(chunkOrErr))
    end
end

local function try_register_hooks()
    if HookLifecycle == nil then
        log("ERROR: hook lifecycle module unavailable.")
        return
    end
    if hooks == nil then
        log("ERROR: firearm hook manifest unavailable.")
        return
    end

    HookLifecycle.Start({
        Hooks = hooks,
        Compatibility = Compatibility,
        FindGuidLibrary = find_guid_library,
        Log = log,
        RetryDelayMs = RETRY_DELAY_MS,
        InitialDelayMs = 6000,
        MaxRetryRounds = MAX_RETRY_ROUNDS,
    })
end


local Gunsmith = nil

local function load_integrated_gunsmith()
    local path = MOD_DIR .. "/Scripts/gunsmith/gunsmith.lua"
    local okLoad, chunkOrErr = pcall(loadfile, path)
    if not okLoad or chunkOrErr == nil then
        log("GUNSMITH LOAD FAILED | " .. tostring(chunkOrErr))
        return false
    end

    local okRun, moduleOrErr = pcall(chunkOrErr)
    if not okRun or type(moduleOrErr) ~= "table" then
        log("GUNSMITH LOAD FAILED | " .. tostring(moduleOrErr))
        return false
    end

    Gunsmith = moduleOrErr

    local okInit, initErr = pcall(function()
        Gunsmith.Init({
            GetSnapshot = gunsmith_snapshot,
            Reroll = gunsmith_reroll,
            Translate = tr,
            DevControls = Config.DevControls == true,
            Log = function(msg)
                log("GUNSMITH | " .. tostring(msg))
            end,
        })
    end)

    if not okInit then
        log("GUNSMITH INIT FAILED | " .. tostring(initErr))
        Gunsmith = nil
        return false
    end

    log("GUNSMITH INTEGRATED | direct in-memory progression API active")
    return true
end

log("----------------------------------------------------------------")
log("WeaponProgression v" .. VERSION)
log("XP/database/stat writes ENABLED; persistent stat progression ACTIVE; v0.15.1 utility safeguards retained.")
log("NATIVE LEVEL-UP TOASTS ACTIVE | KismetTextLibrary FText conversion + native SurrounDead notification UI. STAT VERIFY DEBOUNCE active.")
log("data.db v2 is authoritative for base stats + earned upgrades; previous snapshot retained as data.db.bak.")
log("PERSISTENT STAT PROGRESSION | Primary + Secondary + Sidearm | inventory pickup NOT required.\n[WeaponProgression] MUTATION ROUTE | GetEquipmentUID identifies weapon; live JSI_Slot_C.ItemUniqueID wrapper performs stat writes.")
log("NATIVE TOOLTIP REQUESTED | rounded effective stats, inline progression bonuses, and Level / XP% / Kills / mastery rows.")
log("COMPATIBILITY GUARD ACTIVE | tooltip hooks are attempted only after their expected Blueprint classes/UFunctions are present; game version is logged diagnostically.")
log("REUSABLE NATIVE UI ACTIVE | mastery rank + next milestone | XP bar | 3s auto-close reset by weapon switch.")
log("MASTERY MILESTONES ACTIVE | config.ini-driven fixed bonuses + cumulative caps | deterministic reconstruction from weapon level.")
log("INTEGRATED GUNSMITH ACTIVE | Dave spawns at the Safe Zone test location; rerolls use direct in-memory progression state. F5/F6/F7 dev keys follow [Utility] DevControls.")
log("----------------------------------------------------------------")

math.randomseed(os.time())
load_config()
load_db()
load_melee_progression()
load_integrated_gunsmith()

if UI ~= nil then
    local okKeybind, keybindErr = pcall(function()
        RegisterKeyBind(Key.F8, function()
            ExecuteInGameThread(function()
                ui_toggle()
            end)
        end)
    end)

    if okKeybind then
        log("UI KEYBIND | F8 registered")
    else
        log("UI KEYBIND FAILED | " .. tostring(keybindErr))
    end
end

-- Blueprint classes are not available when the Lua mod first starts.
ExecuteWithDelay(3000, function() ExecuteInGameThread(try_register_hooks) end)
