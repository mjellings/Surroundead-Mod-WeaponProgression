-- WeaponProgression firearm progression policy.
-- Pure Lua calculations only: no UObject discovery, hooks, or live mutation.
local M = {}

function M.New(ctx)
    assert(type(ctx) == "table", "progression context required")
    local Config = assert(ctx.Config, "Config required")
    local STAT_DEFS = assert(ctx.StatDefs, "StatDefs required")
    local MILESTONE_BONUS_TYPES = assert(ctx.MilestoneBonusTypes, "MilestoneBonusTypes required")
    local CAP_CONFIG_BY_STAT = assert(ctx.CapConfigByStat, "CapConfigByStat required")
    local tr = ctx.Translate or function(key) return key end
    local stat_labels = {
        damage="damage", critchance="critical_chance", critmult="critical_multiplier",
        rpm="rpm", falloff="damage_falloff",
    }

    local P = {}

    function P.XPRequired(currentLevel)
        currentLevel = math.max(1, math.floor(tonumber(currentLevel) or 1))
        local targetLevel = currentLevel + 1
        local override = Config.LevelThresholds[targetLevel]
        if override ~= nil then return override end
        return Config.BaseLevelXP + ((currentLevel - 1) * Config.XPIncreasePerLevel)
    end

    function P.GetRankInfo(level)
        level = math.max(1, math.floor(tonumber(level) or 1))
        if not Config.MilestonesEnabled then return nil, nil end
        local current, nextRank = nil, nil
        for _, m in ipairs(Config.Milestones or {}) do
            if m.level <= level then current = m
            elseif nextRank == nil then nextRank = m; break end
        end
        return current, nextRank
    end

    function P.ResolveMilestoneType(m, r)
        if m == nil or r == nil then return nil end
        r.bases = r.bases or {}
        local primary = MILESTONE_BONUS_TYPES[m.bonus_type]
        if primary ~= nil and r.bases[primary.stat_key] ~= nil then return m.bonus_type end
        if m.fallback_type ~= nil then
            local fallback = MILESTONE_BONUS_TYPES[m.fallback_type]
            if fallback ~= nil and r.bases[fallback.stat_key] ~= nil then return m.fallback_type end
        end
        return nil
    end

    function P.MilestoneBonusForStat(r, def)
        if not Config.MilestonesEnabled or r == nil or def == nil then return 0 end
        local level = math.max(1, math.floor(tonumber(r.level) or 1))
        local total = 0
        for _, m in ipairs(Config.Milestones or {}) do
            if m.level > level then break end
            local resolvedType = P.ResolveMilestoneType(m, r)
            local meta = resolvedType and MILESTONE_BONUS_TYPES[resolvedType] or nil
            if meta ~= nil and meta.stat_key == def.key then total = total + (tonumber(m.value) or 0) end
        end
        return total
    end

    function P.MilestoneDescription(m, r)
        if m == nil then return nil end
        local resolvedType = P.ResolveMilestoneType(m, r)
        local meta = resolvedType and MILESTONE_BONUS_TYPES[resolvedType] or nil
        if meta == nil then return tr("no_stat_bonus") end
        local value = tonumber(m.value) or 0
        local rendered = (math.abs(value - math.floor(value + 0.5)) < 0.000001)
            and tostring(math.floor(value + 0.5))
            or string.format("%.1f", value):gsub("0+$", ""):gsub("%.$", "")
        local label = tr(stat_labels[meta.stat_key] or "unknown_weapon")
        if meta.mode == "percent" then return label .. " +" .. rendered .. "%" end
        return label .. " +" .. rendered
    end

    function P.StatTarget(def, base, upgradeCount, record)
        upgradeCount = math.max(0, math.floor(tonumber(upgradeCount) or 0))
        base = tonumber(base)
        if base == nil then return nil end
        local milestoneBonus = P.MilestoneBonusForStat(record, def)
        local target
        if def.mode == "percent" then
            local normalTarget = base * ((1.0 + (Config[def.config] / 100.0)) ^ upgradeCount)
            target = normalTarget + (base * (milestoneBonus / 100.0))
            local capKey = CAP_CONFIG_BY_STAT[def.key]
            local capPercent = capKey and tonumber(Config[capKey]) or nil
            if capPercent ~= nil then target = math.min(target, base * (1.0 + (capPercent / 100.0))) end
        else
            target = base + (Config[def.config] * upgradeCount) + milestoneBonus
            local capKey = CAP_CONFIG_BY_STAT[def.key]
            local capPoints = capKey and tonumber(Config[capKey]) or nil
            if capPoints ~= nil then target = math.min(target, base + capPoints) end
        end
        return target
    end

    -- True when one more ordinary upgrade would not raise this stat's target,
    -- i.e. the configured cap (including milestone bonuses) is already reached.
    -- Uncaptured stats count as capped because they cannot be upgraded.
    function P.IsCapped(def, r)
        if def == nil or r == nil then return true end
        local base = r.bases and tonumber(r.bases[def.key]) or nil
        if base == nil then return true end
        local count = math.max(0, math.floor(tonumber(r.upgrades and r.upgrades[def.key]) or 0))
        local now = P.StatTarget(def, base, count, r)
        local nxt = P.StatTarget(def, base, count + 1, r)
        if now == nil or nxt == nil then return true end
        return (nxt - now) <= math.max(0.000001, math.abs(now) * 0.000000001)
    end

    -- Returns def, nil on success; nil, "no_bases" while no stat has been
    -- captured yet; nil, "capped" when every captured stat is at its cap.
    function P.ChooseUpgradeDef(r)
        local captured, eligible = 0, {}
        for _, def in ipairs(STAT_DEFS) do
            if r.bases and r.bases[def.key] ~= nil then
                captured = captured + 1
                if not P.IsCapped(def, r) then eligible[#eligible + 1] = def end
            end
        end
        if captured == 0 then return nil, "no_bases" end
        if #eligible == 0 then return nil, "capped" end
        if Config.PreventConsecutiveSameStat and #eligible > 1 and r.last_upgrade and r.last_upgrade ~= "" then
            local filtered = {}
            for _, def in ipairs(eligible) do if def.key ~= r.last_upgrade then filtered[#filtered + 1] = def end end
            if #filtered > 0 then eligible = filtered end
        end
        return eligible[math.random(1, #eligible)]
    end

    return P
end

return M
