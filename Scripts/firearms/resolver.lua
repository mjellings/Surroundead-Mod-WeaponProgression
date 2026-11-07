-- Weapon Progression - firearm live resolver boundary
-- Owns transient Unreal weapon/slot references. Long-lived progression state stays outside this module.
local M={}
function M.New(d)
    local log=d.log; local FIELDS=d.Fields; local STAT_DEFS=d.StatDefs
    local records=d.records; local save_db=d.save_db
    local full_name=d.full_name; local guid_to_string=d.guid_to_string
    local safe_array_length=d.safe_array_length; local decode_gameplay_tag=d.decode_gameplay_tag
    local stat_target=d.stat_target
    local liveWeapons={}; local pendingCb=nil; local reconcileCb=nil
    local capturedPlayerJigComponent=nil; local capturedPlayerJigSource=nil
    local cacheCounters={hits=0,misses=0,invalid=0,fallbacks=0,lifecycle_resets=0}
    local PLAYER_CHARACTER_CLASS="BP_PlayerCharacter_C"; local PLAYER_JIG_FIELD="BP_JigMultiplayer"; local JSI_SLOT_CLASS="JSI_Slot_C"

    local function object_is_valid(obj)
        if obj==nil then return false end
        local ok,valid=pcall(function() return obj:IsValid() end); return ok and valid==true
    end
    local function resolve_player_jig_direct(reason)
        if capturedPlayerJigComponent~=nil then
            if object_is_valid(capturedPlayerJigComponent) then return capturedPlayerJigComponent end
            capturedPlayerJigComponent=nil; capturedPlayerJigSource=nil
            log("DIRECT JIG RESOLVE | reason="..tostring(reason).." | cached_component_invalid; reacquiring")
        end
        local okPlayer,player=pcall(function() return FindFirstOf(PLAYER_CHARACTER_CLASS) end)
        if not okPlayer or not object_is_valid(player) then log("DIRECT JIG RESOLVE | reason="..tostring(reason).." | player=NOT_FOUND_OR_INVALID"); return nil end
        local okJig,jig=pcall(function() return player[PLAYER_JIG_FIELD] end)
        if not okJig or not object_is_valid(jig) then log("DIRECT JIG RESOLVE | reason="..tostring(reason).." | player=FOUND | BP_JigMultiplayer=NOT_FOUND_OR_INVALID"); return nil end
        capturedPlayerJigComponent=jig; capturedPlayerJigSource="BP_PlayerCharacter.BP_JigMultiplayer"
        log("DIRECT JIG RESOLVE SUCCESS | reason="..tostring(reason).." | source="..capturedPlayerJigSource.." | component="..full_name(jig)); return jig
    end
    local function cache_log(event,uid,weaponName,detail)
        log(string.format("LIVE CACHE %s | %s | %s | %s | totals hit=%d miss=%d invalid=%d fallback=%d lifecycle_reset=%d",tostring(event),tostring(weaponName),tostring(uid),tostring(detail or ""),cacheCounters.hits,cacheCounters.misses,cacheCounters.invalid,cacheCounters.fallbacks,cacheCounters.lifecycle_resets))
    end
    local function read_live_stat_map(slot)
        local okStats,statsArr=pcall(function() return slot["ItemStats"] end); if not okStats or statsArr==nil then return nil,"ItemStats unreadable" end
        local len=safe_array_length(statsArr); if not len or len==0 then return {},nil end
        local result={}
        for statIndex=1,len do
            local okEntry,entry=pcall(function() return statsArr[statIndex] end)
            if okEntry and entry~=nil then
                local tagStruct,tagName,value; pcall(function() tagStruct=entry[FIELDS.stat_name] end)
                if tagStruct~=nil then tagName=decode_gameplay_tag(tagStruct) end; pcall(function() value=entry[FIELDS.min_value] end)
                if tagName and type(value)=="number" then result[tagName]={value=value,tagStruct=tagStruct,entry=entry,index=statIndex} end
            end
        end
        return result,nil
    end
    local function refresh_live_stat_entry(live,def,statIndex)
        if not live or not live.slot or not object_is_valid(live.slot) then return nil,"slot_invalid" end
        local okStats,statsArr=pcall(function() return live.slot["ItemStats"] end); if not okStats or statsArr==nil then return nil,"stats_unreadable" end
        local okEntry,entry=pcall(function() return statsArr[statIndex] end); if not okEntry or entry==nil then return nil,"entry_unreadable" end
        local okTag,tagStruct=pcall(function() return entry[FIELDS.stat_name] end); if not okTag or tagStruct==nil then return nil,"tag_unreadable" end
        local tagName=decode_gameplay_tag(tagStruct); if tagName~=def.tag then return nil,"tag_mismatch:"..tostring(tagName) end
        local value=nil; pcall(function() value=tonumber(entry[FIELDS.min_value]) end); return {entry=entry,tagStruct=tagStruct,value=value},nil
    end
    local function ensure_record(uid,weaponName)
        local rs=records(); local r=rs[uid]
        if r==nil then r={level=1,xp=0,kills=0,weapon=weaponName or "Unknown",last_upgrade="",pending_rewards=0,bases={},upgrades={}}; rs[uid]=r end
        r.weapon=weaponName or r.weapon or "Unknown"; r.bases=r.bases or {}; r.upgrades=r.upgrades or {}; r.last_upgrade=r.last_upgrade or ""; r.pending_rewards=r.pending_rewards or 0; return r
    end
    local function capture_base_stats(uid,weaponName,statMap)
        local r=ensure_record(uid,weaponName); local changed=false
        for _,def in ipairs(STAT_DEFS) do local live=statMap[def.tag]; if live~=nil and r.bases[def.key]==nil then r.bases[def.key]=live.value; r.upgrades[def.key]=r.upgrades[def.key] or 0; changed=true; log(string.format("BASE STAT CAPTURE | %s | %s | %s | base=%.6g",r.weapon,uid,def.tag,live.value)) end end
        if changed then local saved=save_db(); log("BASE STAT CAPTURE | database_saved="..tostring(saved)) end
    end
    local scan_live_jsi_slots
    local function try_cached_live_weapon(reason,targetUid,targetWeapon,targetUidStruct)
        local cached=liveWeapons[targetUid]; if cached==nil or cached.slot==nil then cacheCounters.misses=cacheCounters.misses+1; cache_log("MISS",targetUid,targetWeapon,"no cached slot"); return false end
        local slot=cached.slot; local okValid,isValid=pcall(function() return slot:IsValid() end)
        if not okValid or not isValid then cacheCounters.invalid=cacheCounters.invalid+1; liveWeapons[targetUid]=nil; cache_log("INVALID",targetUid,targetWeapon,"cached UObject failed IsValid"); return false end
        local okUidField,slotUidStruct=pcall(function() return slot[FIELDS.item_unique_id] end)
        if not okUidField or slotUidStruct==nil then cacheCounters.invalid=cacheCounters.invalid+1; liveWeapons[targetUid]=nil; cache_log("INVALID",targetUid,targetWeapon,"ItemUniqueID unreadable"); return false end
        local slotUid=nil; local okGuid=pcall(function() slotUid=guid_to_string(slotUidStruct) end)
        if not okGuid or slotUid~=targetUid then cacheCounters.invalid=cacheCounters.invalid+1; liveWeapons[targetUid]=nil; cache_log("INVALID",targetUid,targetWeapon,"GUID mismatch live="..tostring(slotUid)); return false end
        local statMap,statErr=read_live_stat_map(slot); if statMap==nil then cacheCounters.invalid=cacheCounters.invalid+1; liveWeapons[targetUid]=nil; cache_log("INVALID",targetUid,targetWeapon,"live stats unreadable: "..tostring(statErr)); return false end
        local n=0; for _ in pairs(statMap) do n=n+1 end; if n==0 then cacheCounters.invalid=cacheCounters.invalid+1; liveWeapons[targetUid]=nil; cache_log("INVALID",targetUid,targetWeapon,"cached GUID still matches but ItemStats=0; forcing populated-slot rescan"); return false end
        local jig=resolve_player_jig_direct(reason); liveWeapons[targetUid]={weapon=targetWeapon,uidStruct=slotUidStruct,equipmentUidStruct=targetUidStruct,slotUidStruct=slotUidStruct,jig=jig,slot=slot,stats=statMap}
        capture_base_stats(targetUid,targetWeapon,statMap); if pendingCb then pendingCb(targetUid,targetWeapon) end; if reconcileCb then reconcileCb(targetUid,targetWeapon,"resolve") end
        cacheCounters.hits=cacheCounters.hits+1; cache_log("HIT",targetUid,targetWeapon,"validated populated slot reused"); return true
    end
    scan_live_jsi_slots=function(reason,targetUid,targetWeapon,targetUidStruct)
        local okFindAll,slots=pcall(function() return FindAllOf(JSI_SLOT_CLASS) end); if not okFindAll or slots==nil then log("JSI SCAN | reason="..tostring(reason).." | FindAllOf failed="..tostring(slots)); return false end
        local count=safe_array_length(slots); if count==nil then pcall(function() count=#slots end) end; log("JSI SCAN | reason="..tostring(reason).." | candidates="..tostring(count)); if not count or count==0 then return false end
        local matches={}
        for i=1,count do local okSlot,slot=pcall(function() return slots[i] end); if okSlot and slot~=nil then local okUid,uidStruct=pcall(function() return slot[FIELDS.item_unique_id] end); if okUid and uidStruct~=nil then local suid=nil; pcall(function() suid=guid_to_string(uidStruct) end); if targetUid~=nil and suid==targetUid then local sm,err=read_live_stat_map(slot); if sm~=nil then local n=0; for _ in pairs(sm) do n=n+1 end; matches[#matches+1]={index=i,slot=slot,uidStruct=uidStruct,statMap=sm,statCount=n} else log("JSI MATCH CANDIDATE | index="..i.." | uid="..tostring(suid).." | rejected="..tostring(err)) end end end end end
        if #matches==0 then log("JSI SCAN COMPLETE | reason="..tostring(reason).." | matches=0"); return false end
        local populated={}; for _,m in ipairs(matches) do if (m.statCount or 0)>0 then populated[#populated+1]=m end end
        if #populated==0 then local idx={}; for _,m in ipairs(matches) do idx[#idx+1]=tostring(m.index)..":0" end; log("JSI MATCH REJECTED | uid="..tostring(targetUid).." | all GUID matches have zero decoded firearm stats | candidates="..table.concat(idx,",").." | reason="..tostring(reason)); return false end
        local chosen=populated[1]; for n=2,#populated do if (populated[n].statCount or 0)>(chosen.statCount or 0) then chosen=populated[n] end end
        if #matches>1 then local desc={}; for _,m in ipairs(matches) do desc[#desc+1]=tostring(m.index)..":"..tostring(m.statCount or 0) end; log("JSI MULTI MATCH | uid="..tostring(targetUid).." | count="..#matches.." | candidates=index:stats["..table.concat(desc,",").."] | populated="..#populated.." | selected_index="..chosen.index.." | selected_stats="..(chosen.statCount or 0).." | policy=richest_populated_then_earliest_tie | reason="..tostring(reason)); if #populated>1 then log("JSI POPULATED AMBIGUITY | uid="..tostring(targetUid).." | populated_candidates="..#populated.." | selected_index="..chosen.index.." | reason="..tostring(reason)) end end
        local slot,slotUidStruct,statMap=chosen.slot,chosen.uidStruct,chosen.statMap; log("JSI MATCH | index="..chosen.index.." | uid="..tostring(targetUid).." | reason="..tostring(reason)); local sc=0; for _ in pairs(statMap) do sc=sc+1 end; log("JSI MATCH | exact firearm slot ItemStats="..sc); log("MUTATION UID | using selected live JSI_Slot_C.ItemUniqueID wrapper for UpdateStatByUID")
        for _,def in ipairs(STAT_DEFS) do local live=statMap[def.tag]; if live then log(string.format("JSI MATCH STAT | index=%d | tag=%s | value=%.6g",live.index,def.tag,live.value)) end end
        local jig=resolve_player_jig_direct(reason); liveWeapons[targetUid]={weapon=targetWeapon,uidStruct=slotUidStruct,equipmentUidStruct=targetUidStruct,slotUidStruct=slotUidStruct,jig=jig,slot=slot,stats=statMap}; capture_base_stats(targetUid,targetWeapon,statMap)
        local reasonText=tostring(reason or ""); if reasonText:sub(1,7)=="Verify:" then local r=records()[targetUid]; local mismatches=0; if r then r.bases=r.bases or {}; r.upgrades=r.upgrades or {}; for _,def in ipairs(STAT_DEFS) do local base=r.bases[def.key]; local uc=r.upgrades[def.key] or 0; local ls=statMap[def.tag]; if base~=nil and ls~=nil then local target=stat_target(def,base,uc,r); if target==nil then log("STAT VERIFY SKIP | "..tostring(targetWeapon).." | "..tostring(targetUid).." | "..def.tag.." | target unavailable") else local tol=math.max(0.0001,math.abs(target)*0.000001); if math.abs(ls.value-target)<=tol then log(string.format("STAT VERIFY OK | %s | %s | %s | live=%.6g | target=%.6g",targetWeapon,targetUid,def.tag,ls.value,target)) else mismatches=mismatches+1; log(string.format("STAT VERIFY MISMATCH | %s | %s | %s | live=%.6g | target=%.6g | no_retry_until_next_real_resolution",targetWeapon,targetUid,def.tag,ls.value,target)) end end end end end; log("STAT VERIFY COMPLETE | "..tostring(targetWeapon)..(mismatches==0 and " | no mismatches" or " | mismatches="..mismatches.." | recursive retry suppressed"))
        else if pendingCb then pendingCb(targetUid,targetWeapon) end; if reconcileCb then reconcileCb(targetUid,targetWeapon,"resolve") end end
        log("JSI MATCH COMPLETE | exact firearm live slot located | weapon="..tostring(targetWeapon).." | reason="..tostring(reason)); return true
    end
    local api={}
    function api.Probe(uidStruct,uid,weaponName) if uid==nil or uid=="" or uidStruct==nil then log("FIREARM LIVE STAT | weapon="..tostring(weaponName).." | UID unavailable; scan skipped."); return end; local reason="Firearm:"..tostring(weaponName); local jig=resolve_player_jig_direct(reason); log("FIREARM LIVE STAT | weapon="..tostring(weaponName).." | equipment_uid="..tostring(uid).." | direct_player_jig="..(jig~=nil and "RESOLVED" or "NOT_RESOLVED").." | cache-first resolution."); if try_cached_live_weapon(reason,uid,weaponName,uidStruct) then return end; cacheCounters.fallbacks=cacheCounters.fallbacks+1; cache_log("FALLBACK",uid,weaponName,"running proven full JSI scan"); scan_live_jsi_slots(reason,uid,weaponName,uidStruct) end
    function api.Scan(reason,uid,weaponName,uidStruct) return scan_live_jsi_slots(reason,uid,weaponName,uidStruct) end
    function api.ResolvePlayerJig(reason) return resolve_player_jig_direct(reason) end
    function api.RefreshLiveStatEntry(live,def,index) return refresh_live_stat_entry(live,def,index) end
    function api.GetLive(uid) return liveWeapons[uid] end
    function api.ReadLiveStatMap(slot) return read_live_stat_map(slot) end
    function api.Invalidate(uid,weaponName,detail) if liveWeapons[uid]~=nil then liveWeapons[uid]=nil; cacheCounters.lifecycle_resets=cacheCounters.lifecycle_resets+1; cache_log("RESET",uid,weaponName,detail or "cache invalidated") end end
    function api.SetCallbacks(pending,reconcile) pendingCb=pending; reconcileCb=reconcile end
    return api
end
return M
