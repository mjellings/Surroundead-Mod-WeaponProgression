-- WeaponProgression melee progression.
--
-- Melee weapons level up from kills like firearms, but through their own
-- hooks, their own config sections ([Melee], [MeleeStatUpgrades], [MeleeCaps],
-- [MeleeMilestones] in config.ini) and their own database (melee.db), so the
-- firearm progression in data.db is never touched.
--
-- How a melee kill is seen (SurrounDead 0.8):
--   * Melee weapons do not fire BP_FirearmPickup_C:SERVER_DamageEvent. Each
--     landed swing fires BP_MeleePickup_C:HitHead or :HitBody once, with the
--     melee pickup actor as Context and the struck actor as DamagedActor.
--   * On a killing blow the zombie's Death fires before that hit callback, so
--     Death queues the kill (only while the melee slot is active) and the hit
--     that follows on the same actor claims it.
--   * The weapon's UID and stats come from the equipped CMelee JSI slot that
--     main.lua's UI bridge already tracks.
--
-- Stats (item stat gameplay tags on melee weapons):
--   Jig.Stat.MeleeDamage            percent, compounding
--   Jig.Stat.StaminaDrain           reduce: lower is better, floor MinStaminaDrain
--   Jig.Stat.CriticalHitChance      points
--   Jig.Stat.CriticalHitMultiplier  points
-- Every item stat is a MinValue..MaxValue range. UpdateStatByUID writes one
-- value to both ends, so after it the MaxValue field is restored to the
-- upgraded upper end (scaled from the captured base range) and read back.
--
-- Attack speed is not an item stat. It comes only from AttackSpeedPercent
-- milestones and is applied to the pickup's BP_WeaponsPickupComponent
-- (SwingSpeed up, DelayBetweenSwings down), always from the captured
-- defaults so it never compounds. The component resets when the pickup is
-- rebuilt, so it is re-applied on each landed hit when it differs.
local M = {}

local STAT_DEFS = {
    { key = "meleedamage",  tag = "Jig.Stat.MeleeDamage",           mode = "percent", config = "MeleeDamagePercent" },
    { key = "staminadrain", tag = "Jig.Stat.StaminaDrain",          mode = "reduce",  config = "StaminaDrainPercent", floor = "MinStaminaDrain" },
    { key = "critchance",   tag = "Jig.Stat.CriticalHitChance",     mode = "points",  config = "CriticalChancePoints" },
    { key = "critmult",     tag = "Jig.Stat.CriticalHitMultiplier", mode = "points",  config = "CriticalMultiplierPoints" },
}
M.STAT_DEFS = STAT_DEFS

local ITEM_BONUS_TYPES = {
    MeleeDamagePercent = { stat_key = "meleedamage", mode = "percent" },
    StaminaDrainPercent = { stat_key = "staminadrain", mode = "reduce" },
    CriticalChancePoints = { stat_key = "critchance", mode = "points" },
    CriticalMultiplierPoints = { stat_key = "critmult", mode = "points" },
}
local ATTACK_SPEED_BONUS = "AttackSpeedPercent"

local CAP_KEYS = {
    meleedamage = "CapMeleeDamagePercent",
    staminadrain = "CapStaminaDrainPercent",
    critchance = "CapCriticalChancePoints",
    critmult = "CapCriticalMultiplierPoints",
}

local LABELS = {
    meleedamage = "melee_damage", staminadrain = "stamina_cost",
    critchance = "critical_chance", critmult = "critical_multiplier",
}

local FIELD_MAX_VALUE = "MaxValue_8_04A5809A498E900862BCCA9A6E412BD7"
local SPEED_COMPONENT = "BP_WeaponsPickupComponent"
local MIN_SWING_DELAY = 0.05

local DEFAULTS = {
    Enabled = true,
    WeaponXPMultiplier = 1.0,
    BaseLevelXP = 100,
    XPIncreasePerLevel = 50,
    MaxLevel = 50,
    PreventConsecutiveSameStat = true,
    MinStaminaDrain = 0.5,

    MeleeDamagePercent = 2.0,
    StaminaDrainPercent = 3.0,
    CriticalChancePoints = 1.0,
    CriticalMultiplierPoints = 2.0,

    CapMeleeDamagePercent = 30.0,
    CapStaminaDrainPercent = 30.0,
    CapCriticalChancePoints = 15.0,
    CapCriticalMultiplierPoints = 20.0,
    CapAttackSpeedPercent = 20.0,

    MilestonesEnabled = true,
}

local function default_milestones()
    return {
        { level = 5,  rank = "Scrapper I",    bonus_type = "MeleeDamagePercent",       value = 2 },
        { level = 10, rank = "Scrapper II",   bonus_type = "AttackSpeedPercent",       value = 5 },
        { level = 15, rank = "Scrapper III",  bonus_type = "StaminaDrainPercent",      value = 5 },
        { level = 20, rank = "Brawler I",     bonus_type = "CriticalChancePoints",     value = 1 },
        { level = 25, rank = "Brawler II",    bonus_type = "AttackSpeedPercent",       value = 5 },
        { level = 30, rank = "Brawler III",   bonus_type = "MeleeDamagePercent",       value = 3 },
        { level = 35, rank = "Bruiser I",     bonus_type = "CriticalMultiplierPoints", value = 2 },
        { level = 40, rank = "Bruiser II",    bonus_type = "AttackSpeedPercent",       value = 5 },
        { level = 45, rank = "Bruiser III",   bonus_type = "MeleeDamagePercent",       value = 4 },
        { level = 50, rank = "Executioner",   bonus_type = "AttackSpeedPercent",       value = 5 },
    }
end

-- melee.db layout (see core/persistence.lua NewStore).
M.DB_SCHEMA = {
    title = "WeaponProgression melee.db v1",
    label = "melee.db",
    stats = { "meleedamage", "staminadrain", "critchance", "critmult" },
    sub_tables = { "maxes" },
    extra = {
        { key = "pending_rewards", kind = "int" },
        { key = "base_swingspeed", kind = "num" },
        { key = "base_swingdelay", kind = "num" },
        { key = "maxes.meleedamage", column = "max_meleedamage", kind = "num" },
        { key = "maxes.staminadrain", column = "max_staminadrain", kind = "num" },
        { key = "maxes.critchance", column = "max_critchance", kind = "num" },
        { key = "maxes.critmult", column = "max_critmult", kind = "num" },
    },
}

local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end

local function parse_bool(v)
    v = trim(v):lower()
    if v == "true" or v == "1" or v == "yes" or v == "on" then return true end
    if v == "false" or v == "0" or v == "no" or v == "off" then return false end
    return nil
end

function M.New(d)
    assert(type(d) == "table", "melee deps required")
    local log = d.log or function() end
    local tr = d.Translate or function(k) return k end
    local unwrap = d.unwrap
    local records = {}

    local Config = { LevelThresholds = {} }
    for k, v in pairs(DEFAULTS) do Config[k] = v end
    Config.Milestones = default_milestones()

    -- ------------------------------------------------------------------
    -- Config: the [Melee*] sections of config.ini
    -- ------------------------------------------------------------------
    local NUMERIC = {
        Melee = { WeaponXPMultiplier = 0, BaseLevelXP = 1, XPIncreasePerLevel = 0, MaxLevel = 2, MinStaminaDrain = 0 },
        MeleeStatUpgrades = { MeleeDamagePercent = 0, StaminaDrainPercent = 0, CriticalChancePoints = 0, CriticalMultiplierPoints = 0 },
        MeleeCaps = { MeleeDamagePercent = 0, StaminaDrainPercent = 0, CriticalChancePoints = 0, CriticalMultiplierPoints = 0, AttackSpeedPercent = 0 },
    }
    local INTEGER = { BaseLevelXP = true, XPIncreasePerLevel = true, MaxLevel = true }

    local function set_milestone(key, raw)
        if key == "Enabled" then
            local b = parse_bool(raw)
            if b == nil then log("MELEE CONFIG WARNING | ignored MeleeMilestones Enabled=" .. tostring(raw)) else Config.MilestonesEnabled = b end
            return
        end
        local level = tonumber(tostring(key):match("^Level(%d+)$"))
        if level == nil or level < 1 then log("MELEE CONFIG WARNING | ignored milestone key " .. tostring(key)); return end
        for i = #Config.Milestones, 1, -1 do
            if Config.Milestones[i].level == level then table.remove(Config.Milestones, i) end
        end
        local lower = trim(raw):lower()
        if lower == "disabled" or lower == "off" or lower == "none" then return end
        local parts = {}
        for part in (trim(raw) .. "|"):gmatch("(.-)|") do parts[#parts + 1] = trim(part) end
        local rank, bonus, value = parts[1], parts[2], tonumber(parts[3])
        if rank == nil or rank == "" or value == nil or (ITEM_BONUS_TYPES[bonus] == nil and bonus ~= ATTACK_SPEED_BONUS) then
            log("MELEE CONFIG WARNING | ignored milestone Level" .. level .. "=" .. tostring(raw))
            return
        end
        Config.Milestones[#Config.Milestones + 1] = { level = level, rank = rank, bonus_type = bonus, value = value }
    end

    local function load_config(path)
        if path == nil then log("MELEE CONFIG | config.ini not found; using melee defaults"); return end
        local f = io.open(path, "r")
        if not f then log("MELEE CONFIG | could not open " .. tostring(path) .. "; using melee defaults"); return end
        local section = ""
        for raw in f:lines() do
            local line = trim(raw)
            if line ~= "" and line:sub(1, 1) ~= ";" and line:sub(1, 1) ~= "#" then
                local sec = line:match("^%[([^%]]+)%]$")
                if sec then
                    section = trim(sec)
                else
                    local key, value = line:match("^([^=]+)=(.*)$")
                    if key then
                        key, value = trim(key), trim(value)
                        if section == "MeleeMilestones" then
                            set_milestone(key, value)
                        elseif section == "Melee" and (key == "Enabled" or key == "PreventConsecutiveSameStat") then
                            local b = parse_bool(value)
                            if b == nil then log("MELEE CONFIG WARNING | ignored " .. key .. "=" .. value) else Config[key] = b end
                        elseif NUMERIC[section] and NUMERIC[section][key] ~= nil then
                            local n = tonumber(value)
                            if n == nil or n < NUMERIC[section][key] then
                                log("MELEE CONFIG WARNING | ignored " .. section .. " " .. key .. "=" .. value)
                            else
                                if INTEGER[key] then n = math.floor(n) end
                                if section == "MeleeCaps" then Config["Cap" .. key] = n else Config[key] = n end
                            end
                        elseif section:sub(1, 5) == "Melee" then
                            log("MELEE CONFIG WARNING | ignored unknown " .. section .. " key " .. key)
                        end
                    end
                end
            end
        end
        f:close()
        table.sort(Config.Milestones, function(a, b) return a.level < b.level end)
    end

    load_config(d.config_path)
    log(string.format("MELEE CONFIG | enabled=%s | multiplier=%.3fx | base=%d | increase=%d | max_level=%d | milestones=%d",
        tostring(Config.Enabled), Config.WeaponXPMultiplier, Config.BaseLevelXP, Config.XPIncreasePerLevel,
        Config.MaxLevel, Config.MilestonesEnabled and #Config.Milestones or 0))

    local P = d.ProgressionModule.New({
        Config = Config, StatDefs = STAT_DEFS, MilestoneBonusTypes = ITEM_BONUS_TYPES,
        CapConfigByStat = CAP_KEYS, Translate = tr, StatLabels = LABELS,
    })

    -- ------------------------------------------------------------------
    -- melee.db
    -- ------------------------------------------------------------------
    local store = d.Persistence.NewStore(M.DB_SCHEMA)
    local function save() return store.Save(records, log) end

    local function ensure_record(uid, weaponName)
        local r = records[uid]
        if r == nil then
            r = { level = 1, xp = 0, kills = 0, weapon = weaponName or "Unknown", last_upgrade = "",
                pending_rewards = 0, bases = {}, upgrades = {}, maxes = {} }
            records[uid] = r
        end
        if weaponName and weaponName ~= "" then r.weapon = weaponName end
        r.bases = r.bases or {}; r.upgrades = r.upgrades or {}; r.maxes = r.maxes or {}
        return r
    end

    -- ------------------------------------------------------------------
    -- Live weapon
    -- ------------------------------------------------------------------
    local function read_max(stat)
        if stat == nil or stat.entry == nil then return nil end
        local ok, v = pcall(function() return stat.entry[FIELD_MAX_VALUE] end)
        return ok and tonumber(v) or nil
    end

    local function resolve_live(reason)
        local eq = d.get_equipped_melee and d.get_equipped_melee() or nil
        if eq == nil or eq.slot == nil then return nil, "no equipped melee slot" end
        local slot = eq.slot
        local okValid, valid = pcall(function() return slot:IsValid() end)
        if not okValid or valid ~= true then return nil, "melee slot invalid" end
        local okUid, uidStruct = pcall(function() return slot[d.Fields.item_unique_id] end)
        if not okUid or uidStruct == nil then return nil, "ItemUniqueID unreadable" end
        local uid = d.guid_to_string(uidStruct)
        if uid == nil then return nil, "ItemUniqueID did not decode" end
        local stats, err = d.read_live_stat_map(slot)
        if stats == nil then return nil, "stats unreadable: " .. tostring(err) end
        if next(stats) == nil then return nil, "no readable stats" end
        return { uid = uid, slot = slot, uidStruct = uidStruct, stats = stats,
            jig = d.resolve_player_jig and d.resolve_player_jig("melee:" .. tostring(reason)) or nil }
    end

    local function capture_bases(live, weaponName)
        local r = ensure_record(live.uid, weaponName)
        local changed = false
        for _, def in ipairs(STAT_DEFS) do
            local stat = live.stats[def.tag]
            if stat ~= nil and r.bases[def.key] == nil then
                r.bases[def.key] = stat.value
                r.maxes[def.key] = read_max(stat)
                r.upgrades[def.key] = r.upgrades[def.key] or 0
                changed = true
                log(string.format("MELEE BASE CAPTURE | %s | %s | %s | %.6g..%s", r.weapon, live.uid, def.tag, stat.value, tostring(r.maxes[def.key])))
            end
        end
        if changed then log("MELEE BASE CAPTURE | saved=" .. tostring(save())) end
        return r
    end

    local function near(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= math.max(0.0001, math.abs(b) * 0.000001)
    end

    -- Upper end of the roll range that goes with an upgraded lower end.
    local function target_max(def, r, target)
        local base, baseMax = r.bases[def.key], r.maxes[def.key]
        if base == nil or baseMax == nil or target == nil then return nil end
        if def.mode == "points" then return baseMax + (target - base) end
        if base == 0 then return baseMax end
        return baseMax * (target / base)
    end

    local function apply(live, weaponName, def, r, reason)
        local stat = live.stats[def.tag]
        local base = r.bases[def.key]
        if stat == nil or stat.tagStruct == nil or base == nil then return false end
        local target = P.StatTarget(def, base, r.upgrades[def.key] or 0, r)
        local tmax = target_max(def, r, target)
        if near(stat.value, target) and (tmax == nil or near(read_max(stat), tmax)) then return true end
        if live.jig == nil or live.uidStruct == nil then
            log("MELEE STAT APPLY PENDING | " .. tostring(weaponName) .. " | " .. def.tag .. " | no player inventory component")
            return false
        end
        log(string.format("MELEE STAT APPLY | %s | %s | %s | %.6g -> %.6g (max %s) | reason=%s",
            tostring(weaponName), live.uid, def.tag, stat.value, target, tostring(tmax), tostring(reason)))
        local ok, err = pcall(function() live.jig:UpdateStatByUID(live.uidStruct, stat.tagStruct, target) end)
        if not ok then log("MELEE STAT APPLY FAILED | " .. def.tag .. " | " .. tostring(err)); return false end
        stat.value = target
        if tmax ~= nil and not near(target, tmax) then
            local okMax = pcall(function() stat.entry[FIELD_MAX_VALUE] = tmax end)
            local after = read_max(stat)
            if not okMax or not near(after, tmax) then
                log("MELEE STAT RANGE | " .. def.tag .. " | upper end did not stick (now " .. tostring(after) .. ", wanted " .. tostring(tmax) .. ")")
            end
        end
        return true
    end

    local function reconcile(live, weaponName, reason)
        local r = records[live.uid]
        if r == nil then return end
        for _, def in ipairs(STAT_DEFS) do
            if r.bases[def.key] ~= nil then apply(live, weaponName, def, r, reason) end
        end
    end

    -- ------------------------------------------------------------------
    -- Attack speed (AttackSpeedPercent milestones)
    -- ------------------------------------------------------------------
    local function attack_speed_percent(level)
        if not Config.MilestonesEnabled then return 0 end
        local total = 0
        for _, m in ipairs(Config.Milestones) do
            if m.level <= level and m.bonus_type == ATTACK_SPEED_BONUS then total = total + (tonumber(m.value) or 0) end
        end
        return math.min(total, tonumber(Config.CapAttackSpeedPercent) or total)
    end

    local speedLogged = {}
    local function apply_attack_speed(pickup, r, uid, weaponName)
        local okComp, comp = pcall(function() return pickup[SPEED_COMPONENT] end)
        if not okComp or comp == nil then return end
        local captured = false
        if r.base_swingspeed == nil then
            local ok, v = pcall(function() return comp.SwingSpeed end)
            if ok and tonumber(v) then r.base_swingspeed = tonumber(v); captured = true end
        end
        if r.base_swingdelay == nil then
            local ok, v = pcall(function() return comp.DelayBetweenSwings end)
            if ok and tonumber(v) then r.base_swingdelay = tonumber(v); captured = true end
        end
        if captured then save() end

        local pct = attack_speed_percent(r.level)
        local wantSpeed = r.base_swingspeed and r.base_swingspeed * (1 + pct / 100) or nil
        local wantDelay = r.base_swingdelay and math.max(MIN_SWING_DELAY, r.base_swingdelay * (1 - pct / 100)) or nil
        local function set(field, want)
            if want == nil then return end
            local ok, cur = pcall(function() return comp[field] end)
            if ok and near(tonumber(cur), want) then return end
            pcall(function() comp[field] = want end)
        end
        set("SwingSpeed", wantSpeed)
        set("DelayBetweenSwings", wantDelay)
        local sig = uid .. "|" .. tostring(pct)
        if pct > 0 and not speedLogged[sig] then
            speedLogged[sig] = true
            log(string.format("MELEE SPEED | %s | %s | L%d | +%g%% | swing %s -> %s | delay %s -> %s", tostring(weaponName), uid,
                r.level, pct, tostring(r.base_swingspeed), tostring(wantSpeed), tostring(r.base_swingdelay), tostring(wantDelay)))
        end
    end

    -- ------------------------------------------------------------------
    -- Rewards and kills
    -- ------------------------------------------------------------------
    local function reward_text(def)
        local amount = Config[def.config]
        local s = (math.abs(amount - math.floor(amount + 0.5)) < 1e-6) and tostring(math.floor(amount + 0.5)) or string.format("%g", amount)
        if def.mode == "percent" then return tr(LABELS[def.key]) .. " +" .. s .. "%" end
        if def.mode == "reduce" then return tr(LABELS[def.key]) .. " -" .. s .. "%" end
        return tr(LABELS[def.key]) .. " +" .. s
    end

    local function milestone_at(level)
        if not Config.MilestonesEnabled then return nil end
        for _, m in ipairs(Config.Milestones) do if m.level == level then return m end end
        return nil
    end

    -- Returns true when the reward was used (applied, or nothing left to improve).
    local function award_upgrade(live, uid, weaponName, level)
        local r = records[uid]
        local def, why = P.ChooseUpgradeDef(r)
        if def == nil and why == "capped" then
            log("MELEE UPGRADE SKIPPED | " .. tostring(weaponName) .. " | " .. uid .. " | L" .. level .. " | all stats capped")
            return true
        end
        if def == nil then
            r.pending_rewards = (r.pending_rewards or 0) + 1
            log("MELEE UPGRADE PENDING | " .. tostring(weaponName) .. " | " .. uid .. " | L" .. level .. " | no captured stats")
            return false
        end
        local previous = r.last_upgrade
        r.upgrades[def.key] = (r.upgrades[def.key] or 0) + 1
        r.last_upgrade = def.key
        if not save() then
            r.upgrades[def.key] = r.upgrades[def.key] - 1
            r.last_upgrade = previous or ""
            r.pending_rewards = (r.pending_rewards or 0) + 1
            log("MELEE UPGRADE DEFERRED | " .. tostring(weaponName) .. " | " .. uid .. " | melee.db write failed")
            return false
        end
        log(string.format("MELEE UPGRADE AWARDED | %s | %s | L%d | %s | count=%d", tostring(weaponName), uid, level, def.tag, r.upgrades[def.key]))
        if live ~= nil and apply(live, weaponName, def, r, "level_up") and d.show_toast then
            local text = reward_text(def)
            d.defer(function() d.show_toast(weaponName, level, text) end)
        end
        return true
    end

    local function pay_pending(live, uid, weaponName)
        local r = records[uid]
        if r == nil or (r.pending_rewards or 0) <= 0 then return end
        local pending = r.pending_rewards
        r.pending_rewards = 0
        for i = 1, pending do
            if not award_upgrade(live, uid, weaponName, r.level) then
                r.pending_rewards = r.pending_rewards + (pending - i)
                break
            end
        end
        save()
    end

    local function award_kill(live, weaponName, vanillaXP)
        local uid = live.uid
        local r = ensure_record(uid, weaponName)
        r.kills = (r.kills or 0) + 1
        local gained = 0
        if r.level < Config.MaxLevel then
            gained = vanillaXP * Config.WeaponXPMultiplier
            r.xp = (r.xp or 0) + gained
            while r.level < Config.MaxLevel and r.xp >= P.XPRequired(r.level) do
                r.xp = r.xp - P.XPRequired(r.level)
                r.level = r.level + 1
                log(string.format("MELEE LEVEL UP | %s | %s | new_level=%d", tostring(weaponName), uid, r.level))
                local m = milestone_at(r.level)
                if m then log("MELEE MILESTONE REACHED | " .. tostring(weaponName) .. " | L" .. r.level .. " | " .. tostring(m.rank)) end
                award_upgrade(live, uid, weaponName, r.level)
                if m then reconcile(live, weaponName, "milestone") end
            end
        end
        if r.level >= Config.MaxLevel then r.xp = 0 end
        local saved = save()
        log(string.format("MELEE KILL XP | %s | %s | vanilla=%.3f | weapon_xp=%.3f | L%d %.3f/%d | kills=%d | saved=%s",
            tostring(weaponName), uid, vanillaXP, gained, r.level, r.xp, P.XPRequired(r.level), r.kills, tostring(saved)))
    end

    -- ------------------------------------------------------------------
    -- Hook callbacks
    -- ------------------------------------------------------------------
    local latestXP, pendingKill = nil, nil
    local api = { Config = Config, Progression = P, STAT_DEFS = STAT_DEFS }

    function api.Load(paths)
        records = store.Load(paths, log)
        return records
    end

    function api.Records() return records end
    function api.Save() return save() end
    function api.AttackSpeedPercent(level) return attack_speed_percent(level) end

    function api.OnAddXP(Context, XP)
        local amount = tonumber(unwrap(XP))
        if amount ~= nil and amount > 0 then latestXP = amount end
    end

    function api.OnDeath(Context)
        if not Config.Enabled then return end
        -- Only a death while the melee slot is in hand can be a melee kill;
        -- otherwise a firearm kill would sit queued for the next melee hit.
        if latestXP ~= nil and d.get_active_container and d.get_active_container() == "CMelee" then
            pendingKill = { enemy = unwrap(Context), xp = latestXP }
        else
            pendingKill = nil
        end
    end

    function api.OnHit(Context, DamagedActor)
        if not Config.Enabled then return end
        local weaponName = d.short_name(Context)
        local live, why = resolve_live("hit:" .. tostring(weaponName))
        if live == nil then
            if pendingKill ~= nil then log("MELEE KILL SKIPPED | " .. tostring(weaponName) .. " | " .. tostring(why)) end
            pendingKill = nil
            return
        end
        local r = capture_bases(live, weaponName)
        pay_pending(live, live.uid, weaponName)
        reconcile(live, weaponName, "hit")
        apply_attack_speed(unwrap(Context) or Context, r, live.uid, weaponName)

        if pendingKill ~= nil and d.same_object(unwrap(DamagedActor), pendingKill.enemy) then
            local xp = pendingKill.xp
            pendingKill, latestXP = nil, nil
            award_kill(live, weaponName, xp)
            apply_attack_speed(unwrap(Context) or Context, records[live.uid], live.uid, weaponName)
        end
    end

    return api
end

return M
