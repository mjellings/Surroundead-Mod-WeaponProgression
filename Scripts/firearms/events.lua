-- WeaponProgression firearm event/progression orchestration.
-- Owns transient damage/death attribution state and the firearm kill -> XP ->
-- level/reward flow. Hook registration remains in core/hook_lifecycle.lua and
-- live UObject/stat mutation remains in resolver.lua + stats.lua.
local M = {}

function M.New(ctx)
    local latestWeaponUID = nil
    local latestWeaponUIDStruct = nil
    local latestVanillaXP = nil
    local pendingDeath = nil

    local function award_kill(uid, weaponName, vanillaXP)
        if uid == nil or vanillaXP == nil or vanillaXP <= 0 then return end
        local r = ctx.ensure_record(uid, weaponName)
        r.kills = (r.kills or 0) + 1

        local weaponXP = vanillaXP * ctx.Config.WeaponXPMultiplier
        if r.level < ctx.Config.MaxLevel then
            r.xp = (r.xp or 0) + weaponXP
            while r.level < ctx.Config.MaxLevel and r.xp >= ctx.xp_required(r.level) do
                local needed = ctx.xp_required(r.level)
                r.xp = r.xp - needed
                r.level = r.level + 1
                ctx.log(string.format("LEVEL UP | %s | %s | consumed=%d XP | new_level=%d | overflow=%.3f", r.weapon, uid, needed, r.level, r.xp))

                local rankAtLevel = nil
                if ctx.Config.MilestonesEnabled then
                    for _, milestone in ipairs(ctx.Config.Milestones or {}) do
                        if milestone.level == r.level then rankAtLevel = milestone; break end
                    end
                end
                if rankAtLevel ~= nil then
                    ctx.log("MILESTONE REACHED | " .. tostring(r.weapon) .. " | " .. tostring(uid) ..
                        " | L" .. tostring(r.level) .. " | " .. tostring(rankAtLevel.rank) ..
                        " | " .. tostring(ctx.milestone_bonus_description(rankAtLevel, r)))
                end

                ctx.award_stat_upgrade(uid, r.weapon, r.level)

                if rankAtLevel ~= nil then
                    ctx.reconcile_weapon_stats(uid, r.weapon, "milestone_level_up")
                end
            end
            if r.level >= ctx.Config.MaxLevel then r.xp = 0 end
        else
            weaponXP = 0
            r.xp = 0
        end

        local saved = ctx.save_db()
        if r.level >= ctx.Config.MaxLevel then
            ctx.log(string.format("KILL XP | %s | %s | vanilla=%.3f | multiplier=%.3fx | weapon_xp=%.3f | L%d MAX | kills=%d | saved=%s", r.weapon, uid, vanillaXP, ctx.Config.WeaponXPMultiplier, weaponXP, r.level, r.kills, tostring(saved)))
        else
            ctx.log(string.format("KILL XP | %s | %s | vanilla=%.3f | multiplier=%.3fx | weapon_xp=%.3f | L%d %.3f/%d | kills=%d | saved=%s", r.weapon, uid, vanillaXP, ctx.Config.WeaponXPMultiplier, weaponXP, r.level, r.xp, ctx.xp_required(r.level), r.kills, tostring(saved)))
        end

        ctx.refresh_ui_if_active(uid)
    end

    local self = {}

    function self.OnGetEquipmentUID(Context, Slot, Value, ...)
        local uidStruct = ctx.unwrap(Value)
        local uid = ctx.guid_to_string(Value)
        if uid then
            latestWeaponUID = uid
            latestWeaponUIDStruct = uidStruct
        end
    end

    function self.OnAddXP(Context, XP, LevelUp, XPOutput, ...)
        local amount = tonumber(ctx.unwrap(XP))
        if amount ~= nil and amount > 0 then latestVanillaXP = amount end
    end

    function self.OnDeath(Context, Actor, Headshot, ...)
        if latestVanillaXP ~= nil then
            pendingDeath = { enemy = ctx.unwrap(Context), xp = latestVanillaXP }
        end
    end

    function self.OnServerDamage(Context, Headshot, DamagedActor, ImpactPoint, ...)
        local weaponName = ctx.short_name(Context)
        local target = ctx.unwrap(DamagedActor)

        ctx.log(string.format("DAMAGE | %s -> %s | uid=%s", weaponName, ctx.short_name(target), latestWeaponUID or "<none>"))

        if latestWeaponUID ~= nil and latestWeaponUIDStruct ~= nil then
            ctx.probe_active_firearm_slot(latestWeaponUIDStruct, latestWeaponUID, weaponName)
        end

        if pendingDeath ~= nil and latestWeaponUID ~= nil and ctx.same_object(target, pendingDeath.enemy) then
            local vanillaXP = pendingDeath.xp
            -- Consume before progression work to guard against duplicate callbacks.
            pendingDeath = nil
            latestVanillaXP = nil
            award_kill(latestWeaponUID, weaponName, vanillaXP)
        end
    end

    return self
end

return M
