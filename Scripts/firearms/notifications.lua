-- WeaponProgression native firearm level-up notifications.
-- Owns FText conversion and native SurrounDead toast creation.
local M = {}

function M.New(ctx)
    local Config = assert(ctx.Config, "Config required")
    local log = assert(ctx.Log, "Log required")
    local tr = ctx.Translate or function(key) return key end
    local textLibrary, mathLibrary, gameLibrary = nil, nil, nil

    local function find_libraries()
        if textLibrary == nil then local ok,o=pcall(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end); if ok then textLibrary=o end end
        if mathLibrary == nil then local ok,o=pcall(function() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end); if ok then mathLibrary=o end end
        if gameLibrary == nil then local ok,o=pcall(function() return StaticFindObject("/Game/Blueprints/GameFunctionLibrary.Default__GameFunctionLibrary_C") end); if ok then gameLibrary=o end end
        return textLibrary, mathLibrary, gameLibrary
    end

    local function clean(v)
        local n=tonumber(v) or 0
        if math.abs(n-math.floor(n+0.5)) < 0.000001 then return tostring(math.floor(n+0.5)) end
        return string.format("%.3f",n):gsub("0+$",""):gsub("%.$","")
    end

    local function reward(def)
        if def.key == "damage" then return tr("damage") .. " +" .. clean(Config.DamagePercent) .. "%" end
        if def.key == "critmult" then return tr("critical_multiplier") .. " +" .. clean(Config.CriticalMultiplierPoints) end
        if def.key == "critchance" then return tr("critical_chance") .. " +" .. clean(Config.CriticalChancePoints) end
        if def.key == "rpm" then return tr("rpm") .. " +" .. clean(Config.RPMPercent) .. "%" end
        if def.key == "__text" then return tostring(def.text) end
        if def.key == "falloff" then return tr("damage_falloff") .. " +" .. clean(Config.FalloffPercent) .. "%" end
        return tostring(def.tag)
    end

    -- Level-up toast with a ready-made reward text (used by melee progression).
    function M.ShowReward(weaponName,newLevel,rewardText)
        return M.Show(weaponName,newLevel,{ key="__text", tag=rewardText, text=rewardText })
    end

    function M.Show(weaponName,newLevel,def)
        local textLib,mathLib,gameLib=find_libraries()
        local player=nil
        local okPlayer,objPlayer=pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
        if okPlayer then player=objPlayer end
        if textLib == nil or mathLib == nil or gameLib == nil or player == nil then
            log("LEVEL TOAST SKIP | native notification dependency unavailable")
            return false
        end
        local message=string.format(tr("level_up"),tostring(weaponName),tonumber(newLevel) or 0,reward(def))
        local ok,err=pcall(function()
            local text=textLib:Conv_StringToText(message); if text == nil then error("Conv_StringToText returned nil") end
            local colour=mathLib:LinearColor_White(); if colour == nil then error("LinearColor_White returned nil") end
            gameLib:CreateNotificationUI(text,nil,colour,4.0,true,player)
        end)
        if ok then log("LEVEL TOAST | " .. message .. " | issued=true"); return true end
        log("LEVEL TOAST FAILED | " .. message .. " | " .. tostring(err)); return false
    end

    return M
end

return M
