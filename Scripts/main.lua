-- WeaponProgression v0.15.1 - Utility / maintenance release
-- SurrounDead 0.8 / UE 5.6 / UE4SS
--
-- Maintenance release based on the proven v0.15.0 progression + native tooltip core.
--
-- Adds:
--   * data.db v2 stores each physical weapon's base firearm stats.
--   * Every weapon level-up awards one random eligible stat upgrade.
--   * Same stat is not selected twice consecutively when another stat exists.
--   * Stat upgrades are authoritative in WeaponProgression data.db.
--   * Missing upgrades are reapplied to the live physical weapon after restart.
--   * Live writes use BP_PlayerCharacter.BP_JigMultiplayer:UpdateStatByUID.
--   * A delayed read-back verifies level-up/reapply writes.
--   * No inventory pickup / Cod Protocol dependency in the production hook set.
--   * Weapons only roll among firearm stats they actually contain.
--
-- Default stat rewards:
--   FirearmDamage             +2% multiplicative from captured base
--   CriticalHitMultiplier     +2 points per upgrade
--   CriticalHitChance         +1 point per upgrade
--   FirearmRPM                +2% multiplicative from captured base
--   DamageFallOff             +2% multiplicative from captured base
--
-- Version history:
--   v0.9.5 - Data collection successful. Tester less successful.
--   v0.9.8 - Integration successful. Timing less successful.
--   v0.9.8a - Delayed registration + immediate DB creation.
--   v0.9.9 - Escalating thresholds, overflow and restart persistence proven.
--   v0.10.0 - Configurable XP multiplier and progression curve.
--   v0.10.1 - First mutation attempt safely stopped: wrong live-slot context exposed empty ItemStats.
--   v0.10.2 - Pickup route did not fire for an existing dropped/re-picked weapon.
--   v0.10.3 - Global JigComponent scan found 3,000+ candidates but none owned the Crusher.
--   v0.10.4 - Confirmed player BP_JigMultiplayer context.
--   v0.10.5 - Cooked Cod capture proved BP_JigMultiplayer + FindItemByUID can resolve equipment UID.
--   v0.10.6 - Crusher resolved but stale FindItemByUID slot exposed empty ItemStats.
--   v0.10.7 - Raw anatomy probing crashed. Cooked Cod retained its dignity.
--   v0.10.8 - UObject identity calls on stale FindItemByUID result could native-crash UE4SS.
--   v0.10.9 - Live JSI_Slot_C scan by ItemUniqueID found exact physical weapon stats.
--   v0.11.0 - Controlled FirearmDamage runtime mutation + read-back confirmed.
--   v0.11.1 - Direct BP_PlayerCharacter.BP_JigMultiplayer resolver confirmed; pickup dependency removed.
--   v0.11.2 - Generic resolver pass exposed a leftover Crusher-only call site.
--   v0.11.3 - Generic primary/secondary/sidearm live-stat resolution confirmed.
--   v0.12.4 - Persistent per-physical-weapon stat upgrades owned by WeaponProgression data.db.
--   v0.12.5 - Player-character notification hook did not observe vanilla XP toast.
--   v0.12.6 - Confirmed vanilla toast route: GameFunctionLibrary:CreateNotificationUI -> HUD_Game:Notification.
--   v0.12.7 - Read-only synchronous S_NotificationDetails anatomy probe; all five fields safely readable.
--   v0.12.8 - Debounce duplicate stat verification scans; custom Lua string -> FText call native-crashed UE4SS.
--   v0.12.9 - Keep verify debounce; synchronous native-toast passthrough using the live vanilla FText wrapper only.
--   v0.12.10 - KismetTextLibrary safely creates custom FText; native custom toast visually confirmed.
--   v0.13.0 - Production native weapon level-up notifications; notification probe hooks removed.
--   v0.14.0-dev - Validate and reuse cached live JSI weapon slots before falling back to a full scan.
--   v0.14.0-dev3 - Prefer GUID-matching JSI slots with populated firearm ItemStats; reject zero-stat duplicate/stub slots.
--   v0.14.0 - Production live weapon cache with populated-slot selection and lifecycle-safe fallback.
--   v0.15.0-dev - Read-only probe for OnHoverTooltipWidget.Update and hovered JSI_Slot_C identity.
--   v0.15.0-dev9 - One-decimal tooltip formatting + native Weapon Level / XP / Kills rows.
--   v0.15.0 - Production native tooltip: rounded bonus stats, Level, XP percentage and Kills; dev probe logging quieted.
--   v0.15.1 - Utility cleanup: safer DB replacement/recovery, lifecycle-safe player Jig cache, dynamic mod paths, quieter production logging, dead tooltip probes/hooks removed.
--   v0.14.0-dev2 - Invalidate cache on inventory re-add and prefer the newest matching JSI slot after lifecycle changes.

local PREFIX = "[WeaponProgression] "
local VERSION = "0.15.1"

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

local MOD_DIR = get_mod_directory()

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
}

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
    LevelThresholds = {},
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

local RETRY_DELAY_MS = 3000
local MAX_RETRY_ROUNDS = 40

local registered = {}
local retryRound = 0
local dbPath = nil
local configPath = nil
local records = {}

local guidLibrary = nil
local latestWeaponUID = nil
local latestVanillaXP = nil
local pendingDeath = nil

local latestWeaponUIDStruct = nil
local liveWeapons = {}
local save_db = nil
local reconcile_weapon_stats = nil
local process_pending_rewards = nil
local cachedJigComponent = nil

local QUIET_LOG_PREFIXES = {
    -- Routine per-hit/cache chatter. Failures and mismatches intentionally remain visible.
    "DAMAGE |",
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

local capturedPlayerJigComponent = nil
local capturedPlayerJigSource = nil

local PLAYER_CHARACTER_CLASS = "BP_PlayerCharacter_C"
local PLAYER_JIG_FIELD = "BP_JigMultiplayer"

local function object_is_valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function resolve_player_jig_direct(reason)
    if capturedPlayerJigComponent ~= nil then
        if object_is_valid(capturedPlayerJigComponent) then
            return capturedPlayerJigComponent
        end
        capturedPlayerJigComponent = nil
        capturedPlayerJigSource = nil
        log("DIRECT JIG RESOLVE | reason=" .. tostring(reason) .. " | cached_component_invalid; reacquiring")
    end

    local okPlayer, player = pcall(function()
        return FindFirstOf(PLAYER_CHARACTER_CLASS)
    end)

    if not okPlayer or not object_is_valid(player) then
        log("DIRECT JIG RESOLVE | reason=" .. tostring(reason) ..
            " | player=NOT_FOUND_OR_INVALID")
        return nil
    end

    local okJig, jig = pcall(function()
        return player[PLAYER_JIG_FIELD]
    end)

    if not okJig or not object_is_valid(jig) then
        log("DIRECT JIG RESOLVE | reason=" .. tostring(reason) ..
            " | player=FOUND | BP_JigMultiplayer=NOT_FOUND_OR_INVALID")
        return nil
    end

    capturedPlayerJigComponent = jig
    capturedPlayerJigSource = "BP_PlayerCharacter.BP_JigMultiplayer"

    log("DIRECT JIG RESOLVE SUCCESS | reason=" .. tostring(reason) ..
        " | source=" .. capturedPlayerJigSource ..
        " | component=" .. full_name(jig))

    return jig
end

local function safe_field(obj, key)
    if obj == nil then return nil, false end
    local ok, value = pcall(function() return obj[key] end)
    if ok then return value, true end
    return nil, false
end

local JSI_SLOT_CLASS = "JSI_Slot_C"

-- v0.14.0 cache instrumentation. The full v0.13.0 JSI scanner remains the
-- authoritative fallback. Cache entries are accepted only after the cached
-- UObject reports IsValid(), its current ItemUniqueID decodes to the expected
-- physical weapon GUID, and its live ItemStats can still be read.
local cacheCounters = { hits=0, misses=0, invalid=0, fallbacks=0, lifecycle_resets=0 }

local function cache_log(event, uid, weaponName, detail)
    log(string.format(
        "LIVE CACHE %s | %s | %s | %s | totals hit=%d miss=%d invalid=%d fallback=%d lifecycle_reset=%d",
        tostring(event), tostring(weaponName), tostring(uid), tostring(detail or ""),
        cacheCounters.hits, cacheCounters.misses, cacheCounters.invalid, cacheCounters.fallbacks, cacheCounters.lifecycle_resets
    ))
end

local function read_live_stat_map(slot)
    local okStats, statsArr = pcall(function() return slot["ItemStats"] end)
    if not okStats or statsArr == nil then return nil, "ItemStats unreadable" end

    local len = safe_array_length(statsArr)
    if not len or len == 0 then return {}, nil end

    local result = {}
    for statIndex = 1, len do
        local okEntry, entry = pcall(function() return statsArr[statIndex] end)
        if okEntry and entry ~= nil then
            local tagStruct, tagName, value
            pcall(function() tagStruct = entry[FIELDS.stat_name] end)
            if tagStruct ~= nil then tagName = decode_gameplay_tag(tagStruct) end
            pcall(function() value = entry[FIELDS.min_value] end)

            if tagName and type(value) == "number" then
                result[tagName] = {
                    value = value,
                    tagStruct = tagStruct,
                    entry = entry,
                    index = statIndex,
                }
            end
        end
    end
    return result, nil
end

local function ensure_record(uid, weaponName)
    local r = records[uid]
    if r == nil then
        r = {
            level=1, xp=0, kills=0, weapon=weaponName or "Unknown",
            last_upgrade="", pending_rewards=0, bases={}, upgrades={}
        }
        records[uid] = r
    end
    r.weapon = weaponName or r.weapon or "Unknown"
    r.bases = r.bases or {}
    r.upgrades = r.upgrades or {}
    r.last_upgrade = r.last_upgrade or ""
    r.pending_rewards = r.pending_rewards or 0
    return r
end

local function capture_base_stats(uid, weaponName, statMap)
    local r = ensure_record(uid, weaponName)
    local changed = false

    for _, def in ipairs(STAT_DEFS) do
        local live = statMap[def.tag]
        if live ~= nil and r.bases[def.key] == nil then
            r.bases[def.key] = live.value
            r.upgrades[def.key] = r.upgrades[def.key] or 0
            changed = true
            log(string.format(
                "BASE STAT CAPTURE | %s | %s | %s | base=%.6g",
                r.weapon, uid, def.tag, live.value
            ))
        end
    end

    if changed and save_db ~= nil then
        local saved = save_db()
        log("BASE STAT CAPTURE | database_saved=" .. tostring(saved))
    end
end

local function try_cached_live_weapon(reason, targetUid, targetWeapon, targetUidStruct)
    local cached = liveWeapons[targetUid]
    if cached == nil or cached.slot == nil then
        cacheCounters.misses = cacheCounters.misses + 1
        cache_log("MISS", targetUid, targetWeapon, "no cached slot")
        return false
    end

    local slot = cached.slot
    local okValid, isValid = pcall(function() return slot:IsValid() end)
    if not okValid or not isValid then
        cacheCounters.invalid = cacheCounters.invalid + 1
        liveWeapons[targetUid] = nil
        cache_log("INVALID", targetUid, targetWeapon, "cached UObject failed IsValid")
        return false
    end

    -- Re-read the UID from the live slot every time. Do not trust a previously
    -- retained struct wrapper when deciding whether this cache entry is safe.
    local okUidField, slotUidStruct = pcall(function()
        return slot[FIELDS.item_unique_id]
    end)
    if not okUidField or slotUidStruct == nil then
        cacheCounters.invalid = cacheCounters.invalid + 1
        liveWeapons[targetUid] = nil
        cache_log("INVALID", targetUid, targetWeapon, "ItemUniqueID unreadable")
        return false
    end

    local slotUid = nil
    local okGuid = pcall(function() slotUid = guid_to_string(slotUidStruct) end)
    if not okGuid or slotUid ~= targetUid then
        cacheCounters.invalid = cacheCounters.invalid + 1
        liveWeapons[targetUid] = nil
        cache_log("INVALID", targetUid, targetWeapon,
            "GUID mismatch live=" .. tostring(slotUid))
        return false
    end

    local statMap, statErr = read_live_stat_map(slot)
    if statMap == nil then
        cacheCounters.invalid = cacheCounters.invalid + 1
        liveWeapons[targetUid] = nil
        cache_log("INVALID", targetUid, targetWeapon,
            "live stats unreadable: " .. tostring(statErr))
        return false
    end

    local cachedStatCount = 0
    for _ in pairs(statMap) do cachedStatCount = cachedStatCount + 1 end
    if cachedStatCount == 0 then
        cacheCounters.invalid = cacheCounters.invalid + 1
        liveWeapons[targetUid] = nil
        cache_log("INVALID", targetUid, targetWeapon,
            "cached GUID still matches but ItemStats=0; forcing populated-slot rescan")
        return false
    end

    local jig = resolve_player_jig_direct(reason)
    liveWeapons[targetUid] = {
        weapon=targetWeapon,
        uidStruct=slotUidStruct,
        equipmentUidStruct=targetUidStruct,
        slotUidStruct=slotUidStruct,
        jig=jig,
        slot=slot,
        stats=statMap,
    }

    capture_base_stats(targetUid, targetWeapon, statMap)

    -- Match v0.13.0 real-resolution behaviour exactly. Verification scans are
    -- intentionally left on the independent full-scan path in this dev build.
    if process_pending_rewards ~= nil then
        process_pending_rewards(targetUid, targetWeapon)
    end
    if reconcile_weapon_stats ~= nil then
        reconcile_weapon_stats(targetUid, targetWeapon, "resolve")
    end

    cacheCounters.hits = cacheCounters.hits + 1
    cache_log("HIT", targetUid, targetWeapon, "validated populated slot reused")
    return true
end

scan_live_jsi_slots = function(reason, targetUid, targetWeapon, targetUidStruct)
    local okFindAll, slotsOrErr = pcall(function() return FindAllOf(JSI_SLOT_CLASS) end)
    if not okFindAll or slotsOrErr == nil then
        log("JSI SCAN | reason=" .. tostring(reason) .. " | FindAllOf failed=" .. tostring(slotsOrErr))
        return false
    end

    local slots = slotsOrErr
    local count = safe_array_length(slots)
    if count == nil then pcall(function() count = #slots end) end
    log("JSI SCAN | reason=" .. tostring(reason) .. " | candidates=" .. tostring(count))
    if not count or count == 0 then return false end

    -- v0.14.0: a physical GUID can exist on multiple live JSI_Slot_C
    -- objects. dev2 proved that the highest-index duplicate may be a zero-stat
    -- stub. Collect every readable GUID match, measure its decoded firearm stat
    -- count, and prefer populated candidates. Never assume scan order implies
    -- authority.
    local matches = {}
    for i = 1, count do
        local okSlot, slot = pcall(function() return slots[i] end)
        if okSlot and slot ~= nil then
            local okUidField, slotUidStruct = pcall(function() return slot[FIELDS.item_unique_id] end)
            if okUidField and slotUidStruct ~= nil then
                local slotUid = nil
                pcall(function() slotUid = guid_to_string(slotUidStruct) end)
                if targetUid ~= nil and slotUid == targetUid then
                    local statMap, statErr = read_live_stat_map(slot)
                    if statMap ~= nil then
                        local statCount = 0
                        for _ in pairs(statMap) do statCount = statCount + 1 end
                        table.insert(matches, {
                            index=i,
                            slot=slot,
                            uidStruct=slotUidStruct,
                            statMap=statMap,
                            statCount=statCount,
                        })
                    else
                        log("JSI MATCH CANDIDATE | index=" .. tostring(i) ..
                            " | uid=" .. tostring(slotUid) ..
                            " | rejected=" .. tostring(statErr))
                    end
                end
            end
        end
    end

    if #matches == 0 then
        log("JSI SCAN COMPLETE | reason=" .. tostring(reason) .. " | matches=0")
        return false
    end

    local populated = {}
    for _, m in ipairs(matches) do
        if (m.statCount or 0) > 0 then populated[#populated+1] = m end
    end

    if #populated == 0 then
        local idx = {}
        for _, m in ipairs(matches) do idx[#idx+1] = tostring(m.index) .. ":0" end
        log("JSI MATCH REJECTED | uid=" .. tostring(targetUid) ..
            " | all GUID matches have zero decoded firearm stats" ..
            " | candidates=" .. table.concat(idx, ",") ..
            " | reason=" .. tostring(reason))
        return false
    end

    -- If several populated representations exist, scan order alone is not authoritative.
    -- proves which is authoritative. For this dev build choose the candidate
    -- with the richest decoded firearm stat set; ties deliberately choose the
    -- earliest index because that matches the known-good pre-drop representation
    -- observed in testing. Ambiguity remains logged.
    local chosen = populated[1]
    for n = 2, #populated do
        local m = populated[n]
        if (m.statCount or 0) > (chosen.statCount or 0) then
            chosen = m
        end
    end

    if #matches > 1 then
        local desc = {}
        for _, m in ipairs(matches) do
            desc[#desc+1] = tostring(m.index) .. ":" .. tostring(m.statCount or 0)
        end
        log("JSI MULTI MATCH | uid=" .. tostring(targetUid) ..
            " | count=" .. tostring(#matches) ..
            " | candidates=index:stats[" .. table.concat(desc, ",") .. "]" ..
            " | populated=" .. tostring(#populated) ..
            " | selected_index=" .. tostring(chosen.index) ..
            " | selected_stats=" .. tostring(chosen.statCount or 0) ..
            " | policy=richest_populated_then_earliest_tie" ..
            " | reason=" .. tostring(reason))
        if #populated > 1 then
            log("JSI POPULATED AMBIGUITY | uid=" .. tostring(targetUid) ..
                " | populated_candidates=" .. tostring(#populated) ..
                " | selected_index=" .. tostring(chosen.index) ..
                " | reason=" .. tostring(reason))
        end
    end

    local slot = chosen.slot
    local slotUidStruct = chosen.uidStruct
    local statMap = chosen.statMap

    log("JSI MATCH | index=" .. tostring(chosen.index) .. " | uid=" .. tostring(targetUid) .. " | reason=" .. tostring(reason))

    local statCount = 0
    for _ in pairs(statMap) do statCount = statCount + 1 end
    log("JSI MATCH | exact firearm slot ItemStats=" .. tostring(statCount))
    log("MUTATION UID | using selected live JSI_Slot_C.ItemUniqueID wrapper for UpdateStatByUID")

    for _, def in ipairs(STAT_DEFS) do
        local live = statMap[def.tag]
        if live then
            log(string.format("JSI MATCH STAT | index=%d | tag=%s | value=%.6g", live.index, def.tag, live.value))
        end
    end

    local jig = resolve_player_jig_direct(reason)
    liveWeapons[targetUid] = {
        weapon=targetWeapon,
        uidStruct=slotUidStruct,
        equipmentUidStruct=targetUidStruct,
        slotUidStruct=slotUidStruct,
        jig=jig,
        slot=slot,
        stats=statMap,
    }

    capture_base_stats(targetUid, targetWeapon, statMap)

    local reasonText = tostring(reason or "")
    local isVerifyScan = reasonText:sub(1, 7) == "Verify:"
    if isVerifyScan then
        local r = records[targetUid]
        local mismatches = 0
        if r ~= nil then
            r.bases = r.bases or {}
            r.upgrades = r.upgrades or {}
            for _, def in ipairs(STAT_DEFS) do
                local base = r.bases[def.key]
                local upgradeCount = r.upgrades[def.key] or 0
                local liveStat = statMap[def.tag]
                if base ~= nil and upgradeCount > 0 and liveStat ~= nil then
                    local target
                    if def.mode == "percent" then
                        target = base * ((1.0 + (Config[def.config] / 100.0)) ^ math.max(0, math.floor(tonumber(upgradeCount) or 0)))
                    else
                        target = base + (Config[def.config] * math.max(0, math.floor(tonumber(upgradeCount) or 0)))
                    end
                    local tolerance = math.max(0.0001, math.abs(target) * 0.000001)
                    if math.abs(liveStat.value - target) <= tolerance then
                        log(string.format("STAT VERIFY OK | %s | %s | %s | live=%.6g | target=%.6g", targetWeapon,targetUid,def.tag,liveStat.value,target))
                    else
                        mismatches = mismatches + 1
                        log(string.format("STAT VERIFY MISMATCH | %s | %s | %s | live=%.6g | target=%.6g | no_retry_until_next_real_resolution", targetWeapon,targetUid,def.tag,liveStat.value,target))
                    end
                end
            end
        end
        if mismatches == 0 then
            log("STAT VERIFY COMPLETE | " .. tostring(targetWeapon) .. " | no mismatches")
        else
            log("STAT VERIFY COMPLETE | " .. tostring(targetWeapon) .. " | mismatches=" .. tostring(mismatches) .. " | recursive retry suppressed")
        end
    else
        if process_pending_rewards ~= nil then
            process_pending_rewards(targetUid, targetWeapon)
        end
        if reconcile_weapon_stats ~= nil then
            reconcile_weapon_stats(targetUid, targetWeapon, "resolve")
        end
    end

    log("JSI MATCH COMPLETE | exact firearm live slot located | weapon=" .. tostring(targetWeapon) .. " | reason=" .. tostring(reason))
    return true
end

local function probe_active_firearm_slot(uidStruct, uid, weaponName)
    if uid == nil or uid == "" or uidStruct == nil then
        log("FIREARM LIVE STAT | weapon=" .. tostring(weaponName) .. " | UID unavailable; scan skipped.")
        return
    end

    local reason = "Firearm:" .. tostring(weaponName)
    local jig = resolve_player_jig_direct(reason)
    log("FIREARM LIVE STAT | weapon=" .. tostring(weaponName) ..
        " | equipment_uid=" .. tostring(uid) ..
        " | direct_player_jig=" .. (jig ~= nil and "RESOLVED" or "NOT_RESOLVED") ..
        " | cache-first resolution.")

    if try_cached_live_weapon(reason, uid, weaponName, uidStruct) then
        return
    end

    cacheCounters.fallbacks = cacheCounters.fallbacks + 1
    cache_log("FALLBACK", uid, weaponName, "running proven full JSI scan")
    scan_live_jsi_slots(reason, uid, weaponName, uidStruct)
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
    Config.LevelThresholds = {}
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

                    elseif section == "Utility" and key == "VerboseLogging" then
                        local b = value:lower()
                        if b == "true" or b == "1" or b == "yes" or b == "on" then
                            Config.VerboseLogging = true
                        elseif b == "false" or b == "0" or b == "no" or b == "off" then
                            Config.VerboseLogging = false
                        else
                            log("CONFIG WARNING | ignored invalid boolean VerboseLogging=" .. tostring(value))
                        end

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
    log("UTILITY CONFIG | verbose_logging=" .. tostring(Config.VerboseLogging))

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
    currentLevel = math.max(1, math.floor(tonumber(currentLevel) or 1))

    -- The INI names the destination level:
    -- Level5=250 means a Level 4 weapon needs 250 XP to become Level 5.
    local targetLevel = currentLevel + 1
    local override = Config.LevelThresholds[targetLevel]

    if override ~= nil then
        return override
    end

    return Config.BaseLevelXP + ((currentLevel - 1) * Config.XPIncreasePerLevel)
end

-- ============================================================================
-- Persistence - data.db v2
-- ============================================================================

local function db_num(v)
    if v == nil then return "" end
    return string.format("%.15g", v)
end

local function ensure_db_file()
    for _, path in ipairs(DB_PATHS) do
        local existing = io.open(path, "r")
        if existing then existing:close(); dbPath = path; return true end

        -- v0.15.1: if a previous replacement was interrupted after rotating the
        -- old database to .bak, recover that last-known-good copy before ever
        -- creating a fresh empty database.
        local backupPath = path .. ".bak"
        local backup = io.open(backupPath, "r")
        if backup then
            backup:close()
            local recovered, recoverErr = os.rename(backupPath, path)
            if recovered then
                dbPath = path
                log("DATABASE RECOVERY | restored last-known-good " .. backupPath)
                return true
            end
            log("DATABASE RECOVERY FAILED | " .. tostring(recoverErr))
        end

        local f = io.open(path, "w")
        if f then
            f:write("# WeaponProgression data.db v2\n")
            f:write("# uid\\tlevel\\txp\\tkills\\tweapon\\tlast_upgrade\\tbase_damage\\tup_damage\\tbase_critmult\\tup_critmult\\tbase_critchance\\tup_critchance\\tbase_rpm\\tup_rpm\\tbase_falloff\\tup_falloff\\tpending_rewards\n")
            f:close(); dbPath = path; return true
        end
    end
    return false
end

local function split_tabs(line)
    local out = {}
    local pos = 1
    while true do
        local tab = line:find("\t", pos, true)
        if not tab then table.insert(out, line:sub(pos)); break end
        table.insert(out, line:sub(pos, tab - 1))
        pos = tab + 1
    end
    return out
end

local function load_db()
    records = {}
    if not ensure_db_file() then log("ERROR: could not find/create a writable data.db."); return end
    log("Database path: " .. dbPath)

    local f = io.open(dbPath, "r")
    if not f then return end

    for line in f:lines() do
        if line:sub(1,1) ~= "#" and line:match("%S") then
            local c = split_tabs(line)
            local uid = c[1]
            if uid and uid ~= "" then
                -- v1 compatibility: first five columns remain identical.
                local r = {
                    level=math.max(1, math.floor(tonumber(c[2]) or 1)),
                    xp=math.max(0, tonumber(c[3]) or 0),
                    kills=math.max(0, math.floor(tonumber(c[4]) or 0)),
                    weapon=(c[5] and c[5] ~= "") and c[5] or "Unknown",
                    last_upgrade=c[6] or "",
                    pending_rewards=math.max(0, math.floor(tonumber(c[17]) or 0)),
                    bases={}, upgrades={}
                }
                r.bases.damage = tonumber(c[7]);      r.upgrades.damage = math.max(0, math.floor(tonumber(c[8]) or 0))
                r.bases.critmult = tonumber(c[9]);    r.upgrades.critmult = math.max(0, math.floor(tonumber(c[10]) or 0))
                r.bases.critchance = tonumber(c[11]); r.upgrades.critchance = math.max(0, math.floor(tonumber(c[12]) or 0))
                r.bases.rpm = tonumber(c[13]);         r.upgrades.rpm = math.max(0, math.floor(tonumber(c[14]) or 0))
                r.bases.falloff = tonumber(c[15]);     r.upgrades.falloff = math.max(0, math.floor(tonumber(c[16]) or 0))
                records[uid] = r
            end
        end
    end
    f:close()

    local count=0; for _ in pairs(records) do count=count+1 end
    log("Loaded " .. count .. " weapon record(s).")
end

save_db = function()
    if dbPath == nil then return false end
    local tmp = dbPath .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then log("ERROR: could not open " .. tmp); return false end

    f:write("# WeaponProgression data.db v2\n")
    f:write("# uid\\tlevel\\txp\\tkills\\tweapon\\tlast_upgrade\\tbase_damage\\tup_damage\\tbase_critmult\\tup_critmult\\tbase_critchance\\tup_critchance\\tbase_rpm\\tup_rpm\\tbase_falloff\\tup_falloff\\tpending_rewards\n")

    local keys={}; for uid in pairs(records) do table.insert(keys,uid) end; table.sort(keys)
    for _, uid in ipairs(keys) do
        local r=records[uid]
        r.bases=r.bases or {}; r.upgrades=r.upgrades or {}
        local weapon=tostring(r.weapon or "Unknown"):gsub("[\t\r\n]"," ")
        local last=tostring(r.last_upgrade or ""):gsub("[\t\r\n]"," ")
        f:write(table.concat({
            uid, tostring(math.floor(r.level or 1)), db_num(r.xp or 0), tostring(math.floor(r.kills or 0)), weapon, last,
            db_num(r.bases.damage), tostring(math.floor(r.upgrades.damage or 0)),
            db_num(r.bases.critmult), tostring(math.floor(r.upgrades.critmult or 0)),
            db_num(r.bases.critchance), tostring(math.floor(r.upgrades.critchance or 0)),
            db_num(r.bases.rpm), tostring(math.floor(r.upgrades.rpm or 0)),
            db_num(r.bases.falloff), tostring(math.floor(r.upgrades.falloff or 0)),
            tostring(math.floor(r.pending_rewards or 0))
        }, "\t") .. "\n")
    end
    f:close()

    -- v0.15.1: never delete the live DB before the replacement is ready. Rotate
    -- it to .bak first, then promote the fully-written .tmp. If promotion fails,
    -- restore the backup. The .bak remains as the previous known-good snapshot.
    local backup = dbPath .. ".bak"
    os.remove(backup)

    local hadExisting = false
    local existing = io.open(dbPath, "r")
    if existing then existing:close(); hadExisting = true end

    if hadExisting then
        local rotated, rotateErr = os.rename(dbPath, backup)
        if not rotated then
            os.remove(tmp)
            log("ERROR rotating data.db to backup: " .. tostring(rotateErr))
            return false
        end
    end

    local ok,err=os.rename(tmp,dbPath)
    if not ok then
        if hadExisting then
            local restored, restoreErr = os.rename(backup, dbPath)
            if not restored then
                log("CRITICAL: data.db promotion failed and backup restore also failed: " .. tostring(restoreErr))
            end
        end
        log("ERROR replacing data.db: " .. tostring(err))
        return false
    end
    return true
end

-- ============================================================================
-- Weapon progression + persistent stat upgrades
-- ============================================================================

local function stat_target(def, base, upgradeCount)
    upgradeCount = math.max(0, math.floor(tonumber(upgradeCount) or 0))
    if def.mode == "percent" then
        return base * ((1.0 + (Config[def.config] / 100.0)) ^ upgradeCount)
    end
    return base + (Config[def.config] * upgradeCount)
end

local function approximately_equal(a,b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a-b) <= math.max(0.0001, math.abs(b)*0.000001)
end

local verifyScheduled = {}

local function schedule_stat_verify(uid, weaponName)
    if verifyScheduled[uid] then
        log("STAT VERIFY DEBOUNCE | " .. tostring(weaponName) .. " | " .. tostring(uid) .. " | already_scheduled")
        return
    end
    verifyScheduled[uid] = true
    ExecuteWithDelay(250, function()
        verifyScheduled[uid] = nil
        local live = liveWeapons[uid]
        if live ~= nil then
            scan_live_jsi_slots("Verify:" .. tostring(weaponName), uid, weaponName, live.uidStruct)
        else
            log("STAT VERIFY SKIP | " .. tostring(weaponName) .. " | " .. tostring(uid) .. " | live_weapon_unavailable")
        end
    end)
end

local function apply_stat_target(uid, weaponName, def, target, reason)
    local live=liveWeapons[uid]
    if not live or not live.jig or not live.uidStruct or not live.stats then
        log("STAT APPLY PENDING | " .. tostring(weaponName) .. " | " .. uid .. " | " .. def.tag .. " | reason=no_live_weapon")
        return false
    end

    local stat=live.stats[def.tag]
    if not stat or stat.tagStruct == nil then
        log("STAT APPLY PENDING | " .. tostring(weaponName) .. " | " .. uid .. " | " .. def.tag .. " | reason=stat_not_live")
        return false
    end

    local current=stat.value
    if approximately_equal(current,target) then return true end

    log(string.format("STAT APPLY | %s | %s | %s | %.6g -> %.6g | reason=%s", weaponName,uid,def.tag,current,target,tostring(reason)))
    local ok,err=pcall(function() if live.slotUidStruct == nil then
            error("live JSI_Slot_C.ItemUniqueID wrapper unavailable; refusing unsafe stat mutation")
        end
        live.jig:UpdateStatByUID(live.slotUidStruct, stat.tagStruct, target) end)
    if not ok then
        log("STAT APPLY FAILED | " .. tostring(def.tag) .. " | " .. tostring(err))
        return false
    end

    -- Optimistic cache update prevents duplicate writes before delayed readback.
    stat.value=target
    -- Multiple reconstructed stats can be applied in one resolution pass. One
    -- delayed readback verifies the complete weapon instead of scheduling one
    -- ~445-object JSI scan per changed stat.
    schedule_stat_verify(uid, weaponName)
    return true
end

reconcile_weapon_stats = function(uid, weaponName, reason)
    local r=records[uid]
    local live=liveWeapons[uid]
    if not r or not live or not live.stats then return false end
    r.bases=r.bases or {}; r.upgrades=r.upgrades or {}

    local changed=false
    for _,def in ipairs(STAT_DEFS) do
        local base=r.bases[def.key]
        local count=r.upgrades[def.key] or 0
        local liveStat=live.stats[def.tag]
        if base ~= nil and count > 0 and liveStat ~= nil then
            local target=stat_target(def,base,count)
            if not approximately_equal(liveStat.value,target) then
                if apply_stat_target(uid,weaponName or r.weapon,def,target,"reapply:" .. tostring(reason)) then changed=true end
            end
        end
    end
    if not changed then
        log("STAT RECONCILE | " .. tostring(weaponName or r.weapon) .. " | " .. uid .. " | already_correct")
    end
    return true
end

local show_level_up_notification = nil

local function choose_upgrade_def(r)
    local eligible={}
    for _,def in ipairs(STAT_DEFS) do
        if r.bases and r.bases[def.key] ~= nil then table.insert(eligible,def) end
    end
    if #eligible == 0 then return nil end

    if Config.PreventConsecutiveSameStat and #eligible > 1 and r.last_upgrade and r.last_upgrade ~= "" then
        local filtered={}
        for _,def in ipairs(eligible) do if def.key ~= r.last_upgrade then table.insert(filtered,def) end end
        if #filtered > 0 then eligible=filtered end
    end

    return eligible[math.random(1,#eligible)]
end

local function award_stat_upgrade(uid, weaponName, newLevel)
    local r=records[uid]
    if not r then return false end
    local def=choose_upgrade_def(r)
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
    local target=stat_target(def,base,r.upgrades[def.key])

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
    if applied then show_level_up_notification(weaponName,newLevel,def) end
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

local function award_kill(uid, weaponName, vanillaXP)
    if uid == nil or vanillaXP == nil or vanillaXP <= 0 then return end
    local r=ensure_record(uid,weaponName)
    r.kills=(r.kills or 0)+1

    local weaponXP=vanillaXP*Config.WeaponXPMultiplier
    if r.level < Config.MaxLevel then
        r.xp=(r.xp or 0)+weaponXP
        while r.level < Config.MaxLevel and r.xp >= xp_required(r.level) do
            local needed=xp_required(r.level)
            r.xp=r.xp-needed
            r.level=r.level+1
            log(string.format("LEVEL UP | %s | %s | consumed=%d XP | new_level=%d | overflow=%.3f",r.weapon,uid,needed,r.level,r.xp))
            award_stat_upgrade(uid,r.weapon,r.level)
        end
        if r.level >= Config.MaxLevel then r.xp=0 end
    else
        weaponXP=0; r.xp=0
    end

    local saved=save_db()
    if r.level >= Config.MaxLevel then
        log(string.format("KILL XP | %s | %s | vanilla=%.3f | multiplier=%.3fx | weapon_xp=%.3f | L%d MAX | kills=%d | saved=%s",r.weapon,uid,vanillaXP,Config.WeaponXPMultiplier,weaponXP,r.level,r.kills,tostring(saved)))
    else
        log(string.format("KILL XP | %s | %s | vanilla=%.3f | multiplier=%.3fx | weapon_xp=%.3f | L%d %.3f/%d | kills=%d | saved=%s",r.weapon,uid,vanillaXP,Config.WeaponXPMultiplier,weaponXP,r.level,r.xp,xp_required(r.level),r.kills,tostring(saved)))
    end
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
local notificationTextLibrary = nil
local notificationMathLibrary = nil
local notificationGameLibrary = nil

local function find_notification_libraries()
    if notificationTextLibrary == nil then
        local ok,obj=pcall(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
        if ok then notificationTextLibrary=obj end
    end
    if notificationMathLibrary == nil then
        local ok,obj=pcall(function() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end)
        if ok then notificationMathLibrary=obj end
    end
    if notificationGameLibrary == nil then
        local ok,obj=pcall(function() return StaticFindObject("/Game/Blueprints/GameFunctionLibrary.Default__GameFunctionLibrary_C") end)
        if ok then notificationGameLibrary=obj end
    end
    return notificationTextLibrary,notificationMathLibrary,notificationGameLibrary
end

local function clean_reward_number(v)
    local n=tonumber(v) or 0
    if math.abs(n-math.floor(n+0.5)) < 0.000001 then return tostring(math.floor(n+0.5)) end
    return string.format("%.3f",n):gsub("0+$",""):gsub("%.$","")
end

local function stat_reward_description(def)
    if def.key == "damage" then return "Damage +" .. clean_reward_number(Config.DamagePercent) .. "%" end
    if def.key == "critmult" then return "Critical Multiplier +" .. clean_reward_number(Config.CriticalMultiplierPoints) end
    if def.key == "critchance" then return "Critical Chance +" .. clean_reward_number(Config.CriticalChancePoints) end
    if def.key == "rpm" then return "RPM +" .. clean_reward_number(Config.RPMPercent) .. "%" end
    if def.key == "falloff" then return "Damage Falloff +" .. clean_reward_number(Config.FalloffPercent) .. "%" end
    return tostring(def.tag)
end

show_level_up_notification = function(weaponName,newLevel,def)
    local textLib,mathLib,gameLib=find_notification_libraries()
    local player=nil
    local okPlayer,objPlayer=pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
    if okPlayer then player=objPlayer end

    if textLib == nil or mathLib == nil or gameLib == nil or player == nil then
        log("LEVEL TOAST SKIP | native notification dependency unavailable")
        return false
    end

    local message=string.format("%s reached Level %d - %s",tostring(weaponName),tonumber(newLevel) or 0,stat_reward_description(def))
    local ok,err=pcall(function()
        local text=textLib:Conv_StringToText(message)
        if text == nil then error("Conv_StringToText returned nil") end
        local colour=mathLib:LinearColor_White()
        if colour == nil then error("LinearColor_White returned nil") end
        gameLib:CreateNotificationUI(text,nil,colour,4.0,true,player)
    end)

    if ok then
        log("LEVEL TOAST | " .. message .. " | issued=true")
        return true
    end
    log("LEVEL TOAST FAILED | " .. message .. " | " .. tostring(err))
    return false
end

local function on_get_equipment_uid(Context, Slot, Value, ...)
    local uidStruct = unwrap(Value)
    local uid = guid_to_string(Value)

    if uid then
        latestWeaponUID = uid
        latestWeaponUIDStruct = uidStruct
    end
end

local function on_add_xp(Context, XP, LevelUp, XPOutput, ...)
    local amount = tonumber(unwrap(XP))
    if amount ~= nil and amount > 0 then
        latestVanillaXP = amount
    end
end

local function on_death(Context, Actor, Headshot, ...)
    if latestVanillaXP ~= nil then
        pendingDeath = {
            enemy = unwrap(Context),
            xp = latestVanillaXP,
        }
    end
end

local function on_server_damage(Context, Headshot, DamagedActor, ImpactPoint, ...)
    local weaponName = short_name(Context)
    local target = unwrap(DamagedActor)

    log(string.format(
        "DAMAGE | %s -> %s | uid=%s",
        weaponName,
        short_name(target),
        latestWeaponUID or "<none>"
    ))

    -- Generic read-only live-stat probe for the exact physical firearm that
    -- produced this SERVER_DamageEvent. weaponName comes directly from Context,
    -- so it cannot be lost through the old Crusher-specific pending state.
    if latestWeaponUID ~= nil and latestWeaponUIDStruct ~= nil then
        probe_active_firearm_slot(latestWeaponUIDStruct, latestWeaponUID, weaponName)
    end


    if pendingDeath ~= nil and
       latestWeaponUID ~= nil and
       same_object(target, pendingDeath.enemy) then

        local vanillaXP = pendingDeath.xp

        -- Consume before writing to guard against duplicate callbacks.
        pendingDeath = nil
        latestVanillaXP = nil

        award_kill(latestWeaponUID, weaponName, vanillaXP)
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

local function display_number(v)
    local n = tonumber(v)
    if n == nil then return nil end
    local rounded = math.floor((n * 10) + (n >= 0 and 0.5 or -0.5)) / 10
    if math.abs(rounded - math.floor(rounded + 0.5)) < 0.000001 then
        return tostring(math.floor(rounded + 0.5))
    end
    return string.format("%.1f", rounded):gsub("0+$", ""):gsub("%.$", "")
end

local function bonus_text(v)
    local n = tonumber(v) or 0
    if math.abs(n) < 0.000001 then return nil end
    return display_number(n)
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

local function add_progression_rows(tooltip, r, weaponName)
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
            if child ~= nil and field_text(child, "TextBlock_56") == "Level" then
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

    local needed = xp_required(r.level or 1)
    local xp = tonumber(r.xp) or 0
    local xpPercent = 0
    if needed ~= nil and needed > 0 then
        xpPercent = math.max(0, math.min(100, (xp / needed) * 100))
    end
    local rows = {
        { label="Level", value=tostring(math.floor(r.level or 1)), row=1, col=1 },
        { label="XP", value=display_number(xpPercent) .. "%", row=2, col=0 },
        { label="Kills", value=tostring(math.floor(r.kills or 0)), row=2, col=1 },
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

        log("TOOLTIP PROGRESSION ADD | " .. tostring(weaponName) ..
            " | " .. info.label .. "=" .. info.value ..
            " | row=" .. tostring(info.row) .. " col=" .. tostring(info.col) ..
            " | delayed_text=1ms")
    end

    return true
end

local function on_tooltip_update(Context, ItemRefParam, ...)
    tooltipBonusContext = nil
    local slot = unwrap(ItemRefParam)
    if slot == nil then
        log("TOOLTIP PROBE | ItemRef=<nil>")
        return
    end

    local uidStruct = nil
    local okUid, rawUid = pcall(function() return slot[FIELDS.item_unique_id] end)
    if okUid and rawUid ~= nil then uidStruct = rawUid end

    local uid = guid_to_string(uidStruct)

    local statsCount = nil
    pcall(function() statsCount = safe_array_length(slot["ItemStats"]) end)

    local itemName = short_name(slot)
    local okName, nameValue = pcall(function() return slot:GetItemName() end)
    if okName and nameValue ~= nil then
        local rawName = unwrap(nameValue)
        local okText, txt = pcall(function() return rawName:ToString() end)
        if okText and txt ~= nil and tostring(txt) ~= "" then itemName = tostring(txt) end
    end

    if uid == nil then
        log(string.format(
            "TOOLTIP PROBE | item=%s | uid=<unresolved> | ItemStats=%s | slot=%s",
            tostring(itemName), tostring(statsCount or "?"), full_name(slot)
        ))
        return
    end

    local r = records[uid]
    if r ~= nil then
        local needed = xp_required(r.level or 1)
        log(string.format(
            "TOOLTIP PROBE | item=%s | uid=%s | ItemStats=%s | record=FOUND | L%d %.3f/%d XP | kills=%d",
            tostring(itemName), uid, tostring(statsCount or "?"),
            math.floor(r.level or 1), tonumber(r.xp or 0) or 0, needed, math.floor(r.kills or 0)
        ))

        -- DB v2 stores bases/upgrades in nested tables. Prefer the persisted
        -- weapon name when GetItemName() exposes a generic UI label such as
        -- "Inventory" through the tooltip callback.
        if (itemName == nil or itemName == "" or itemName == "Inventory") and r.weapon ~= nil then
            itemName = tostring(r.weapon)
        end

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
            by_label = {},
        }
        for _, def in ipairs(STAT_DEFS) do
            local base = tonumber(r.bases[def.key])
            local count = math.floor(tonumber(r.upgrades[def.key]) or 0)
            local live = liveStats[def.tag]
            if base ~= nil then
                local target = stat_target(def, base, count)
                local bonus = (target ~= nil) and (target - base) or 0
                log(string.format(
                    "TOOLTIP STAT | %s | %s | base=%.3f | live=%s | target=%s | bonus=%+.3f | upgrades=%d",
                    tostring(itemName), def.tag, base,
                    live ~= nil and string.format("%.3f", live) or "<missing>",
                    target ~= nil and string.format("%.3f", target) or "<nil>",
                    bonus, count
                ))
                if count > 0 and target ~= nil and math.abs(bonus) >= 0.000001 then
                    parts[#parts + 1] = string.format("%s %+0.3f", def.tag, bonus)
                    tooltipBonusContext.by_tag[def.tag] = bonus
                end
            end
        end
        if #parts > 0 then
            log("TOOLTIP UPGRADES | " .. itemName .. " | " .. table.concat(parts, " ; "))
        else
            log("TOOLTIP UPGRADES | " .. itemName .. " | none recorded")
        end
    else
        log(string.format(
            "TOOLTIP PROBE | item=%s | uid=%s | ItemStats=%s | record=NOT_FOUND",
            tostring(itemName), uid, tostring(statsCount or "?")
        ))
    end

    -- Update is a pre-hook; vanilla creates its BP_StatW/BP_StatTextW children
    -- immediately afterwards. Inspect the finished UniformGrid shortly later.
    local tooltipContext = unwrap(Context)
    ExecuteWithDelay(75, function()
        local valid = false
        if tooltipContext ~= nil then
            pcall(function() valid = tooltipContext:IsValid() end)
        end
        if valid then
            local ctx = tooltipBonusContext
            if ctx ~= nil and ctx.record ~= nil then
                add_progression_rows(tooltipContext, ctx.record, ctx.weapon)
            end
        else
            log("TEXT GRID PROBE | tooltip no longer valid after delay")
        end
    end)

end


-- ============================================================================
-- Native tooltip stat formatting hooks
-- ============================================================================

local PATH_STAT_W_CONSTRUCT =
    "/Game/JigSInventory/Jigsaw/Widgets/BP_StatW.BP_StatW_C:Construct"

local function on_stat_w_construct(Context, ...)
    local w = unwrap(Context)
    if w == nil then
        log("STAT W CONSTRUCT | context=<nil>")
        return
    end

    local parts = {}
    for _, f in ipairs({
        "StatName", "VectValue", "Prefix", "ExtraText",
        "TextBlock", "TextBlock_56", "PrefixTxt", "ExtraTxt"
    }) do
        local v = field_text(w, f)
        if v ~= nil and v ~= "" then
            parts[#parts + 1] = f .. "=" .. v
        end
    end

    log("STAT W CONSTRUCT | widget=" .. full_name(w) ..
        " | " .. (#parts > 0 and table.concat(parts, " ; ") or "<no readable fields>"))

    local ctx = tooltipBonusContext
    if ctx == nil then return end

    local tagName = nil
    local rawStatName, statNameOk = safe_field(w, "StatName")
    if statNameOk and rawStatName ~= nil then
        pcall(function() tagName = decode_gameplay_tag(unwrap(rawStatName)) end)
    end

    local label = field_text(w, "TextBlock_56")
    local labelToTag = {
        ["Damage"] = "Jig.Stat.FirearmDamage",
        ["Critical Hit Multiplier"] = "Jig.Stat.CriticalHitMultiplier",
        ["Critical Hit Chance"] = "Jig.Stat.CriticalHitChance",
        ["RPM"] = "Jig.Stat.FirearmRPM",
        ["Damage Falloff Range"] = "Jig.Stat.DamageFallOff",
    }
    if tagName == nil or ctx.by_tag[tagName] == nil then
        tagName = labelToTag[label]
    end

    if tagName == nil then
        log("TOOLTIP FORMAT NO MATCH | " .. tostring(ctx.weapon) ..
            " | label=" .. tostring(label))
        return
    end
    local bonus = ctx.by_tag[tagName]

    local valueBlock = nil
    pcall(function() valueBlock = unwrap(w["TextBlock"]) end)
    local currentText = textblock_text(valueBlock)
    if valueBlock == nil or currentText == nil then
        log("TOOLTIP FORMAT SKIP | " .. tostring(ctx.weapon) ..
            " | label=" .. tostring(label) .. " | reason=value_text_unavailable")
        return
    end

    local currentNumber = tonumber(trim(currentText))
    if currentNumber == nil then
        log("TOOLTIP FORMAT SKIP | " .. tostring(ctx.weapon) ..
            " | label=" .. tostring(label) .. " | reason=non_numeric_value " .. tostring(currentText))
        return
    end

    local unit = field_text(w, "ExtraText") or field_text(w, "ExtraTxt") or ""
    if unit == "None" then unit = "" end
    local rendered = display_number(currentNumber) .. unit_suffix(unit)
    local suffix = bonus_text(bonus)
    if suffix ~= nil then
        rendered = rendered .. " (+" .. suffix .. ")"
    end

    local okSet, setErr = set_textblock_text(valueBlock, rendered)

    -- We folded % / M into the value text so clear vanilla's separate unit widget.
    if unit ~= "" then
        local extraBlock = nil
        pcall(function() extraBlock = unwrap(w["ExtraTxt"]) end)
        if extraBlock ~= nil then set_textblock_text(extraBlock, "") end
    end

    if okSet then
        log("TOOLTIP FORMAT APPLY | " .. tostring(ctx.weapon) ..
            " | " .. tostring(label or tagName) .. " | " .. rendered)
    else
        log("TOOLTIP FORMAT FAILED | " .. tostring(ctx.weapon) ..
            " | " .. tostring(label or tagName) .. " | " .. tostring(setErr))
    end
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

    if uid ~= nil and liveWeapons[uid] ~= nil then
        local weaponName = liveWeapons[uid].weapon or (records[uid] and records[uid].weapon) or "Unknown"
        liveWeapons[uid] = nil
        cacheCounters.lifecycle_resets = cacheCounters.lifecycle_resets + 1
        cache_log("RESET", uid, weaponName, "JigTryAddItemSomewhere observed same physical GUID")
    end
end

local hooks = {
    {"GET_EQUIPMENT_UID", PATH_GET_EQUIPMENT_UID, on_get_equipment_uid},
    {"JIG_TRY_ADD",       PATH_JIG_TRY_ADD,       on_inventory_add_cache_invalidate},
    {"TOOLTIP_UPDATE",    PATH_TOOLTIP_UPDATE,    on_tooltip_update},
    {"STAT_W_CONSTRUCT",  PATH_STAT_W_CONSTRUCT,  on_stat_w_construct},
    {"ADD_XP",            PATH_ADD_XP,            on_add_xp},
    {"ZOMBIE_DEATH",      PATH_DEATH,             on_death},
    {"SERVER_DAMAGE",     PATH_SERVER_DAMAGE,     on_server_damage},
}

local function register_one(key, path, callback)
    if registered[key] then return true end

    local ok, preId, postId = pcall(function()
        return RegisterHook(path, callback)
    end)

    if ok then
        registered[key] = true
        log(string.format(
            "REGISTERED %-18s | ids=%s,%s",
            key,
            tostring(preId),
            tostring(postId)
        ))
        return true
    end

    return false
end

local function registered_count()
    local n = 0
    for _, h in ipairs(hooks) do
        if registered[h[1]] then n = n + 1 end
    end
    return n
end

local function try_register_hooks()
    retryRound = retryRound + 1
    find_guid_library()

    for _, h in ipairs(hooks) do
        register_one(h[1], h[2], h[3])
    end

    local n = registered_count()

    if n == #hooks then
        log("All " .. tostring(#hooks) .. " hooks active.")
        log("Ready: configurable progression is active.")
        log("Persistent progression armed: first resolved use captures base stats; each level-up awards and stores one stat upgrade.")
        return
    end

    if retryRound == 1 or retryRound % 5 == 0 then
        log(string.format(
            "Waiting for game Blueprints: %d/" .. tostring(#hooks) .. " hooks active (pass %d/%d).",
            n,
            retryRound,
            MAX_RETRY_ROUNDS
        ))
    end

    if retryRound < MAX_RETRY_ROUNDS then
        ExecuteWithDelay(RETRY_DELAY_MS, try_register_hooks)
    else
        log("ERROR: stopped hook retries before all hooks became available.")
    end
end

log("----------------------------------------------------------------")
log("WeaponProgression v" .. VERSION)
log("XP/database/stat writes ENABLED; persistent stat progression ACTIVE; utility safeguards v0.15.1 ACTIVE.")
log("NATIVE LEVEL-UP TOASTS ACTIVE | KismetTextLibrary FText conversion + native SurrounDead notification UI. STAT VERIFY DEBOUNCE active.")
log("data.db v2 is authoritative for base stats + earned upgrades; previous snapshot retained as data.db.bak.")
log("PERSISTENT STAT PROGRESSION | Primary + Secondary + Sidearm | inventory pickup NOT required.\n[WeaponProgression] MUTATION ROUTE | GetEquipmentUID identifies weapon; live JSI_Slot_C.ItemUniqueID wrapper performs stat writes.")
log("NATIVE TOOLTIP ACTIVE | one-decimal stat formatting, inline units/bonuses, and Level / XP% / Kills rows enabled.")
log("----------------------------------------------------------------")

math.randomseed(os.time())
load_config()
load_db()

-- Blueprint classes are not available when the Lua mod first starts.
ExecuteWithDelay(3000, try_register_hooks)
