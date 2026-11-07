-- WeaponProgression compatibility helper
-- Capability-first guard for fragile native tooltip integration.
--
-- The game version is diagnostic only. Tooltip hooks are gated by the exact
-- Blueprint classes/UFunctions and supporting native libraries they need.
--
-- No arbitrary FText scanning is performed. If the main menu is live, the
-- optional version read targets only the already-confirmed:
-- MenuWidget_C.WidgetTree.TextBlock_146

local Compatibility = {}

local logger = nil
local environmentLogged = false

local PATHS = {
    tooltip_class =
        "/Game/JigSInventory/Jigsaw/Widgets/HoverDrag/Hover/OnHoverTooltipWidget.OnHoverTooltipWidget_C",
    tooltip_update =
        "/Game/JigSInventory/Jigsaw/Widgets/HoverDrag/Hover/OnHoverTooltipWidget.OnHoverTooltipWidget_C:Update",

    stat_w_class =
        "/Game/JigSInventory/Jigsaw/Widgets/BP_StatW.BP_StatW_C",
    stat_w_construct =
        "/Game/JigSInventory/Jigsaw/Widgets/BP_StatW.BP_StatW_C:Construct",

    stat_text_class =
        "/Game/JigSInventory/Jigsaw/Widgets/BP_StatTextW.BP_StatTextW_C",

    widget_blueprint_library =
        "/Script/UMG.Default__WidgetBlueprintLibrary",
    text_library =
        "/Script/Engine.Default__KismetTextLibrary",
    system_library =
        "/Script/Engine.Default__KismetSystemLibrary",
}

local function log(message)
    local text = tostring(message)
    if type(logger) == "function" then
        local ok = pcall(logger, "COMPAT | " .. text)
        if ok then return end
    end
    print("[WeaponProgression:Compatibility] " .. text .. "\n")
end

local function valid(obj)
    if obj == nil then return false end
    local ok, result = pcall(function() return obj:IsValid() end)
    return ok and result == true
end

local function find(path)
    local ok, obj = pcall(function() return StaticFindObject(path) end)
    if ok and obj ~= nil then return obj end
    return nil
end

local function decode_fstring(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and type(result) == "string" then return result end
    return nil
end

local function find_confirmed_version_widget()
    local ok, blocks = pcall(function() return FindAllOf("TextBlock") end)
    if not ok or blocks == nil then return nil end

    local count = nil
    pcall(function() count = #blocks end)
    if type(count) ~= "number" then return nil end

    for i = 1, count do
        local block = nil
        pcall(function() block = blocks[i] end)

        if valid(block) then
            local full = nil
            pcall(function() full = block:GetFullName() end)
            full = full and tostring(full) or nil

            if full
                and full:find("MenuWidget_C_", 1, true)
                and full:match("%.WidgetTree_%d+%.TextBlock_146$")
            then
                return block
            end
        end
    end

    return nil
end

local function try_read_game_version()
    local widget = find_confirmed_version_widget()
    if widget == nil then
        return nil, nil, "main-menu version widget not live"
    end

    local textLib = find(PATHS.text_library)
    if textLib == nil then
        return nil, nil, "KismetTextLibrary unavailable"
    end

    local okText, textValue = pcall(function() return widget.Text end)
    if not okText or textValue == nil then
        return nil, nil, "confirmed version Text unavailable"
    end

    local okConvert, fstring = pcall(function()
        return textLib:Conv_TextToString(textValue)
    end)
    if not okConvert or fstring == nil then
        return nil, nil, "confirmed version FText conversion failed"
    end

    local text = decode_fstring(fstring)
    if text == nil then
        return nil, nil, "version FString decode failed"
    end

    local parsed =
        text:match("[vV](%d+%.%d+%.%d+)")
        or text:match("[vV](%d+%.%d+)")
        or text:match("(%d+%.%d+%.%d+)")
        or text:match("(%d+%.%d+)")

    return text, parsed, nil
end

function Compatibility.Configure(options)
    options = options or {}
    if type(options.log) == "function" then
        logger = options.log
    end
end

function Compatibility.LogEnvironment()
    if environmentLogged then return end
    environmentLogged = true

    log("------------------------------------------------------------")
    log("Environment probe")

    local sys = find(PATHS.system_library)
    if sys ~= nil then
        local okGame, rawGame = pcall(function() return sys:GetGameName() end)
        local okEngine, rawEngine = pcall(function() return sys:GetEngineVersion() end)

        local gameName = okGame and decode_fstring(rawGame) or nil
        local engineVersion = okEngine and decode_fstring(rawEngine) or nil

        log("GameName = " .. tostring(gameName or "<unavailable>"))
        log("EngineVersion = " .. tostring(engineVersion or "<unavailable>"))
    else
        log("GameName = <KismetSystemLibrary unavailable>")
        log("EngineVersion = <KismetSystemLibrary unavailable>")
    end

    local versionText, version, versionErr = try_read_game_version()
    if versionText ~= nil then
        log('GameVersionText = "' .. tostring(versionText) .. '"')
        log("GameVersion = " .. tostring(version or "<unparsed>"))
    else
        log("GameVersion = <" .. tostring(versionErr or "unavailable") .. ">")
    end

    log("Game version is diagnostic only; capability checks gate tooltip hooks.")
    log("------------------------------------------------------------")
end

local function missing(paths)
    local absent = {}
    for _, item in ipairs(paths) do
        if find(item.path) == nil then
            absent[#absent + 1] = item.name
        end
    end
    return absent
end

function Compatibility.CheckHook(key)
    if key == "TOOLTIP_UPDATE" then
        local absent = missing({
            { name="OnHoverTooltipWidget_C", path=PATHS.tooltip_class },
            { name="OnHoverTooltipWidget_C:Update", path=PATHS.tooltip_update },
            { name="BP_StatTextW_C", path=PATHS.stat_text_class },
            { name="WidgetBlueprintLibrary", path=PATHS.widget_blueprint_library },
            { name="KismetTextLibrary", path=PATHS.text_library },
        })
        if #absent > 0 then
            return false, table.concat(absent, ", ")
        end
        return true, "expected tooltip Update dependencies found"

    elseif key == "STAT_W_CONSTRUCT" then
        local absent = missing({
            { name="BP_StatW_C", path=PATHS.stat_w_class },
            { name="BP_StatW_C:Construct", path=PATHS.stat_w_construct },
            { name="KismetTextLibrary", path=PATHS.text_library },
        })
        if #absent > 0 then
            return false, table.concat(absent, ", ")
        end
        return true, "expected BP_StatW dependencies found"
    end

    -- Core progression/UI hooks are intentionally outside this guard.
    return true, "not compatibility-gated"
end

function Compatibility.IsTooltipHook(key)
    return key == "TOOLTIP_UPDATE" or key == "STAT_W_CONSTRUCT"
end

function Compatibility.Summarize()
    local tooltipOK, tooltipReason = Compatibility.CheckHook("TOOLTIP_UPDATE")
    local statOK, statReason = Compatibility.CheckHook("STAT_W_CONSTRUCT")

    log("Tooltip Update capability = " ..
        (tooltipOK and "READY" or ("NOT READY | missing " .. tostring(tooltipReason))))
    log("Stat-row capability = " ..
        (statOK and "READY" or ("NOT READY | missing " .. tostring(statReason))))

    return tooltipOK and statOK
end

return Compatibility
