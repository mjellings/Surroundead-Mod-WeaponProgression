-- Weapon Progression - live firearm stat mutation/reconciliation boundary
local M={}
function M.New(d)
    local log=d.log; local Resolver=d.Resolver; local STAT_DEFS=d.StatDefs; local records=d.records; local stat_target=d.stat_target
    local verifyScheduled={}
    local function approximately_equal(a,b) if type(a)~="number" or type(b)~="number" then return false end; return math.abs(a-b)<=math.max(0.0001,math.abs(b)*0.000001) end
    local api={}
    local function schedule_stat_verify(uid,weaponName)
        if verifyScheduled[uid] then log("STAT VERIFY DEBOUNCE | "..tostring(weaponName).." | "..tostring(uid).." | already_scheduled"); return end
        verifyScheduled[uid]=true
        ExecuteWithDelay(250,function()
            ExecuteInGameThread(function()
                verifyScheduled[uid]=nil
                local live=Resolver.GetLive(uid)
                if live~=nil then
                    Resolver.Scan("Verify:"..tostring(weaponName),uid,weaponName,live.uidStruct)
                else
                    log("STAT VERIFY SKIP | "..tostring(weaponName).." | "..tostring(uid).." | live_weapon_unavailable")
                end
            end)
        end)
    end
    function api.Apply(uid,weaponName,def,target,reason)
        local live=Resolver.GetLive(uid); if not live or not live.jig or not live.uidStruct or not live.stats then log("STAT APPLY PENDING | "..tostring(weaponName).." | "..uid.." | "..def.tag.." | reason=no_live_weapon"); return false end
        local stat=live.stats[def.tag]; if not stat or stat.tagStruct==nil then log("STAT APPLY PENDING | "..tostring(weaponName).." | "..uid.." | "..def.tag.." | reason=stat_not_live"); return false end
        local current=stat.value; if approximately_equal(current,target) then return true end
        local jig=Resolver.ResolvePlayerJig("apply:"..tostring(reason)); live.jig=jig
        local fresh,freshErr=Resolver.RefreshLiveStatEntry(live,def,stat.index); if fresh==nil then log("STAT APPLY PENDING | "..tostring(weaponName).." | "..uid.." | "..def.tag.." | reason=stale_stat_entry:"..tostring(freshErr)); return false end
        if type(fresh.value)=="number" then current=fresh.value end; if approximately_equal(current,target) then stat.value=current; return true end
        log(string.format("STAT APPLY | %s | %s | %s | %.6g -> %.6g | reason=%s",weaponName,uid,def.tag,current,target,tostring(reason)))
        local ok,err=pcall(function() if live.slotUidStruct==nil then error("live JSI_Slot_C.ItemUniqueID wrapper unavailable; refusing unsafe stat mutation") end; if jig==nil then error("player jig component unavailable; refusing unsafe stat mutation") end; jig:UpdateStatByUID(live.slotUidStruct,fresh.tagStruct,target) end)
        if not ok then log("STAT APPLY FAILED | "..tostring(def.tag).." | "..tostring(err)); return false end
        stat.value=target; schedule_stat_verify(uid,weaponName); return true
    end
    function api.Reconcile(uid,weaponName,reason)
        local r=records()[uid]; local live=Resolver.GetLive(uid); if not r or not live or not live.stats then return false end; r.bases=r.bases or {}; r.upgrades=r.upgrades or {}; local changed=false
        for _,def in ipairs(STAT_DEFS) do local base=r.bases[def.key]; local count=r.upgrades[def.key] or 0; local ls=live.stats[def.tag]; if base~=nil and ls~=nil then local target=stat_target(def,base,count,r); if not approximately_equal(ls.value,target) then if api.Apply(uid,weaponName or r.weapon,def,target,"reapply:"..tostring(reason)) then changed=true end end end end
        if not changed then log("STAT RECONCILE | "..tostring(weaponName or r.weapon).." | "..uid.." | already_correct") end; return true
    end
    return api
end
return M
