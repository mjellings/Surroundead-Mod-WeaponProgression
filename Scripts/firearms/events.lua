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

    -- GetEquipmentUID fires for every equipment slot the game or UI asks
    -- about, not only the gun being fired. Remember the last few UIDs seen so
    -- a damage event can be matched to the UID whose saved record is the same
    -- weapon model as the firearm that dealt the damage.
    local RECENT_LIMIT = 8
    local recentUIDs = {}   -- uid -> { uid=, struct=, seq= }
    local uidSeq = 0
    local lastMismatchKey = nil -- log each mismatch once, not on every shot

    local function remember_uid(uid, struct)
        uidSeq = uidSeq + 1
        recentUIDs[uid] = { uid = uid, struct = struct, seq = uidSeq }
        local count, oldest = 0, nil
        for _, e in pairs(recentUIDs) do
            count = count + 1
            if oldest == nil or e.seq < oldest.seq then oldest = e end
        end
        if count > RECENT_LIMIT and oldest ~= nil then recentUIDs[oldest.uid] = nil end
    end

    local function record_weapon(uid)
        local r = ctx.get_record and ctx.get_record(uid) or nil
        if r == nil or r.weapon == nil or r.weapon == "" or r.weapon == "Unknown" then return nil end
        return r.weapon
    end

    -- Returns uid, uidStruct for the weapon that fired, or nil when the only
    -- candidate UIDs all belong to other, already-tracked weapons.
    local function resolve_firing_uid(weaponName)
        if latestWeaponUID == nil then return nil, nil end
        if weaponName == nil or weaponName == "" then return latestWeaponUID, latestWeaponUIDStruct end

        local latestName = record_weapon(latestWeaponUID)
        if latestName == weaponName then return latestWeaponUID, latestWeaponUIDStruct end

        local best = nil
        for uid, e in pairs(recentUIDs) do
            if record_weapon(uid) == weaponName and (best == nil or e.seq > best.seq) then best = e end
        end
        if best ~= nil then
            ctx.log(string.format("KILL CREDIT | %s | latest uid %s is %s; using recent matching uid %s",
                tostring(weaponName), tostring(latestWeaponUID), tostring(latestName), tostring(best.uid)))
            return best.uid, best.struct
        end

        -- No tracked UID for this model. An untracked latest UID is assumed to
        -- be this (new) weapon, which is how first use has always worked.
        if latestName == nil then return latestWeaponUID, latestWeaponUIDStruct end

        return nil, nil
    end

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
            remember_uid(uid, uidStruct)
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

        local uid, uidStruct = resolve_firing_uid(weaponName)

        ctx.log(string.format("DAMAGE | %s -> %s | uid=%s", weaponName, ctx.short_name(target), uid or "<none>"))

        local mismatchKey = (uid == nil and latestWeaponUID ~= nil) and (tostring(weaponName) .. "|" .. tostring(latestWeaponUID)) or nil
        if mismatchKey ~= nil and mismatchKey ~= lastMismatchKey then
            ctx.log(string.format("KILL CREDIT MISMATCH | %s fired but latest uid %s is %s and no recent uid matches; damage not credited",
                tostring(weaponName), tostring(latestWeaponUID), tostring(record_weapon(latestWeaponUID))))
        end
        lastMismatchKey = mismatchKey

        if uid ~= nil and uidStruct ~= nil then
            ctx.probe_active_firearm_slot(uidStruct, uid, weaponName)
        end

        if pendingDeath ~= nil and ctx.same_object(target, pendingDeath.enemy) then
            local vanillaXP = pendingDeath.xp
            -- Consume before progression work to guard against duplicate callbacks.
            pendingDeath = nil
            latestVanillaXP = nil
            if uid ~= nil then award_kill(uid, weaponName, vanillaXP) end
        end
    end

    return self
end

return M
