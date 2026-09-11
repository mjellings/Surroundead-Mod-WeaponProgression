-- ============================================================================
-- WeaponProgression Integrated Gunsmith (Dave) - v0.18.4-dev1
--
-- Uses direct in-memory callbacks supplied by WeaponProgression/main.lua.
-- No active_weapon.api or reroll.request files.
--
-- Current research spawn:
--   Safe Zone
--   X=113972.8 Y=132500.1 Z=1269.2
--   Yaw=-14.2
-- ============================================================================

local M = {}
local UEHelpers = require("UEHelpers")

local PREFIX = "[WeaponProgression.Gunsmith] "
local GENERIC_PATH =
    "/Game/Quests/Blueprints/NPCs/BP_QuestGiver.BP_QuestGiver_C"

local function script_dir()
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1,1) == "@" then source = source:sub(2) end
    return source:match("^(.*[\\/])")
end

local function load_location_config()
    local dir = script_dir()
    if not dir then
        error("Could not resolve WeaponProgression Scripts directory")
    end

    local path = dir .. "dave_locations.lua"
    local chunk, loadErr = loadfile(path)
    if not chunk then
        error("Could not load dave_locations.lua: " .. tostring(loadErr))
    end

    local ok, cfg = pcall(chunk)
    if not ok then
        error("dave_locations.lua execution failed: " .. tostring(cfg))
    end
    if type(cfg) ~= "table" then
        error("dave_locations.lua must return a table")
    end
    if type(cfg.Locations) ~= "table" or #cfg.Locations == 0 then
        error("dave_locations.lua has no Locations")
    end

    cfg.ZOffset = tonumber(cfg.ZOffset) or -80.0
    cfg.TestLocation = math.floor(tonumber(cfg.TestLocation) or 1)

    if cfg.TestLocation < 1 or cfg.TestLocation > #cfg.Locations then
        cfg.TestLocation = 1
    end

    return cfg, path
end

local LOCATION_CONFIG, LOCATION_FILE = load_location_config()
local DEV_Z_OFFSET = 0.0

local function current_test_location()
    local spot = LOCATION_CONFIG.Locations[LOCATION_CONFIG.TestLocation]
    if type(spot) ~= "table" then
        spot = LOCATION_CONFIG.Locations[1]
    end
    return spot
end

local UI_CLOSE_DISTANCE = 500.0
local PROXIMITY_CHECK_MS = 250
local NO_FIREARM_CLOSE_MS = 3000

local api = nil
local ui = nil
local spawned = nil
local hookRegistered = false
local spawnGeneration = 0
local proximityGeneration = 0
local uiAutoCloseGeneration = 0
local uiFCloseGeneration = 0
local uiFCloseArmed = false
local handoffCount = 0

local function log(msg)
    if api and type(api.Log) == "function" then
        api.Log(msg)
    else
        print(PREFIX .. tostring(msg))
    end
end

local function unwrap(v)
    if v == nil then return nil end
    local ok, r = pcall(function() return v:get() end)
    if ok and r ~= nil then return r end
    ok, r = pcall(function() return v:Get() end)
    if ok and r ~= nil then return r end
    return v
end

local function valid(o)
    o = unwrap(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function full_name(o)
    o = unwrap(o)
    if not valid(o) then return "<invalid>" end
    local ok, v = pcall(function() return o:GetFullName() end)
    return ok and tostring(v) or tostring(o)
end

local function local_player()
    local ok, p = pcall(function() return UEHelpers.GetPlayer() end)
    if ok and valid(p) then return unwrap(p) end

    local found = nil
    for _, p2 in ipairs(FindAllOf("BP_PlayerCharacter_C") or {}) do
        p2 = unwrap(p2)
        if valid(p2) then
            local okLocal, isLocal = pcall(function() return p2:IsLocallyControlled() end)
            if okLocal and isLocal then
                if found ~= nil then return nil end
                found = p2
            end
        end
    end
    return found
end

local function actor_location(actor)
    actor = unwrap(actor)
    if not valid(actor) then return nil end
    local ok, v = pcall(function() return actor:K2_GetActorLocation() end)
    return ok and v or nil
end

local function distance_between(a, b)
    local la = actor_location(a)
    local lb = actor_location(b)
    if la == nil or lb == nil then return nil end

    local dx = (tonumber(la.X) or 0) - (tonumber(lb.X) or 0)
    local dy = (tonumber(la.Y) or 0) - (tonumber(lb.Y) or 0)
    local dz = (tonumber(la.Z) or 0) - (tonumber(lb.Z) or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function resolve_exact()
    local cls = nil
    pcall(function() cls = StaticFindObject(GENERIC_PATH) end)

    if not valid(cls) then
        local packagePath = GENERIC_PATH:match("^(.+)%.([^%.]+)$")
        if packagePath then
            pcall(function() LoadAsset(packagePath) end)
            pcall(function() cls = StaticFindObject(GENERIC_PATH) end)
        end
    end

    return valid(cls) and unwrap(cls) or nil
end

local function find_text_library()
    local lib = nil
    pcall(function()
        lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    end)
    return valid(lib) and lib or nil
end

local function set_native_name(actor, name)
    local lib = find_text_library()
    if not valid(actor) or not valid(lib) then
        log("NAME WRITE FAILED | invalid actor or KismetTextLibrary")
        return false
    end

    local text = nil
    local okText, textErr = pcall(function()
        text = lib:Conv_StringToText(tostring(name))
    end)

    if not okText or text == nil then
        log("NAME WRITE FAILED | could not create FText | " .. tostring(textErr))
        return false
    end

    local wroteSomething = false

    -- Live View confirmed this is the visible native NPC label:
    -- BP_QuestGiver_C:Name = NSLOCTEXT(..., "Settlement Leader")
    local okName, nameErr = pcall(function()
        actor.Name = text
    end)

    if okName then
        wroteSomething = true
        log("NAME WRITE | Name=" .. tostring(name))
    else
        log("NAME WRITE FAILED | Name | " .. tostring(nameErr))
    end

    -- Keep VendorName in sync in case another UI path uses it.
    local okVendor, vendorErr = pcall(function()
        actor.VendorName = text
    end)

    if okVendor then
        wroteSomething = true
        log("NAME WRITE | VendorName=" .. tostring(name))
    else
        log("NAME WRITE SKIP/FAILED | VendorName | " .. tostring(vendorErr))
    end

    -- Live View also exposed InteractionArgument="SettlementLeader".
    -- This is a StringProperty, so write a normal Lua string.
    local okArg, argErr = pcall(function()
        actor.InteractionArgument = tostring(name)
    end)

    if okArg then
        wroteSomething = true
        log("NAME WRITE | InteractionArgument=" .. tostring(name))
    else
        log("NAME WRITE FAILED | InteractionArgument | " .. tostring(argErr))
    end

    return wroteSomething
end


local function load_ui()
    if ui ~= nil then return true end

    local dir = script_dir()
    if not dir then
        log("UI LOAD FAILED | script directory unresolved")
        return false
    end

    local path = dir .. "gunsmith_ui.lua"
    local okLoad, chunk = pcall(loadfile, path)
    if not okLoad or chunk == nil then
        log("UI LOAD FAILED | " .. tostring(chunk))
        return false
    end

    local okRun, module = pcall(chunk)
    if not okRun or type(module) ~= "table" then
        log("UI LOAD FAILED | " .. tostring(module))
        return false
    end

    ui = module
    if type(ui.Configure) == "function" then
        pcall(function()
            ui.Configure({
                title = "DAVE'S GUNSMITH",
                x = 92,
                y = 210,
                width = 620,
                height = 470,
                z_order = 500,
            })
        end)
    end

    log("UI LOADED | " .. path)
    return true
end

local function ui_is_open()
    if ui == nil or type(ui.IsOpen) ~= "function" then return false end
    local ok, v = pcall(function() return ui.IsOpen() end)
    return ok and v == true
end

local function cancel_ui_auto_close()
    uiAutoCloseGeneration = uiAutoCloseGeneration + 1
end

local function disarm_f_close()
    uiFCloseGeneration = uiFCloseGeneration + 1
    uiFCloseArmed = false
end

local function hide_ui()
    disarm_f_close()
    proximityGeneration = proximityGeneration + 1
    cancel_ui_auto_close()

    if ui ~= nil and type(ui.Hide) == "function" then
        pcall(function() ui.Hide() end)
    end
end

local function arm_f_close_after_open()
    uiFCloseGeneration = uiFCloseGeneration + 1
    local generation = uiFCloseGeneration
    uiFCloseArmed = false

    ExecuteWithDelay(300, function()
        ExecuteInGameThread(function()
            if generation ~= uiFCloseGeneration then return end
            if ui_is_open() then
                uiFCloseArmed = true
                log("UI | F-close armed")
            end
        end)
    end)
end

local function build_ui_state()
    local held = api.GetSnapshot()

    if held.state == "none" then
        return {
            weapon = "DAVE'S GUNSMITH",
            status = "Alright?\nI can't help much if you aren't holding a firearm.",
            show_button = false,
        }, held
    end

    if held.state == "unresolved" then
        return {
            weapon = held.weapon or "UNKNOWN WEAPON",
            status = "I can see it, but I can't identify this weapon yet.\nTry switching weapons and give me another look.",
            show_button = false,
        }, held
    end

    if held.state == "untracked" then
        return {
            weapon = held.weapon or "UNTRACKED WEAPON",
            status = "I don't know this one yet.\nUse it a little and come back.",
            show_button = false,
        }, held
    end

    local level = held.level or 1
    local rolls = held.ordinary_rolls or 0

    if level < 5 then
        return {
            weapon = tostring(held.weapon),
            level = level,
            rank = held.rank,
            stats = held.stats,
            message = "Not enough history on this one yet.\nCome back when it reaches Level 5.",
            show_button = true,
            button_enabled = false,
            button_text = "REROLL",
        }, held
    end

    return {
        weapon = tostring(held.weapon),
        level = level,
        rank = held.rank,
        stats = held.stats,
        message = string.format(
            "Redistributes %d ordinary progression bonuses.\nLevel, XP, kills and mastery are preserved.",
            rolls
        ),
        show_button = true,
        button_enabled = (rolls > 0),
        button_text = "REROLL",
    }, held
end

local function refresh_ui(message, buttonEnabled)
    local state, held = build_ui_state()
    if message ~= nil then state.message = message end
    if buttonEnabled ~= nil then state.button_enabled = buttonEnabled end

    if ui ~= nil and type(ui.SetState) == "function" then
        pcall(function() ui.SetState(state) end)
    end
    return held
end

local function request_reroll()
    local state, held = build_ui_state()

    if held.state ~= "tracked" or held.uid == nil then
        refresh_ui("I can't reroll this weapon right now.", false)
        return
    end

    if (held.level or 1) < 5 then
        refresh_ui("This weapon must reach Level 5\nbefore I can reroll it.", false)
        return
    end

    if (held.ordinary_rolls or 0) <= 0 then
        refresh_ui("This weapon has no ordinary progression bonuses\nto reroll.", false)
        return
    end

    state.message = "Rerolling..."
    state.button_enabled = false
    pcall(function() ui.SetState(state) end)

    local ok, message = api.Reroll(held.uid)

    if ok then
        refresh_ui("Reroll successful.\nNew progression stats are shown above.", true)
        log("REROLL | SUCCESS | weapon=" .. tostring(held.weapon) ..
            " | uid=" .. tostring(held.uid))
    else
        refresh_ui(message or "Reroll failed.", true)
        log("REROLL | FAILED | " .. tostring(message))
    end
end

local function schedule_no_firearm_close(held)
    cancel_ui_auto_close()
    if held.state ~= "none" then return end

    local generation = uiAutoCloseGeneration
    ExecuteWithDelay(NO_FIREARM_CLOSE_MS, function()
        ExecuteInGameThread(function()
            if generation ~= uiAutoCloseGeneration then return end
            if ui_is_open() then
                log("UI | auto-close: no firearm")
                hide_ui()
            end
        end)
    end)
end

local function begin_proximity_watch()
    proximityGeneration = proximityGeneration + 1
    local generation = proximityGeneration

    local function tick()
        if generation ~= proximityGeneration then return end

        ExecuteInGameThread(function()
            if generation ~= proximityGeneration then return end
            if not ui_is_open() then return end

            if not valid(spawned) then
                log("UI | close: Dave no longer valid")
                hide_ui()
                return
            end

            local player = local_player()
            if not valid(player) then
                hide_ui()
                return
            end

            local d = distance_between(player, spawned)
            if d ~= nil and d > UI_CLOSE_DISTANCE then
                log(string.format("UI | proximity close | distance=%.1f", d))
                hide_ui()
                return
            end

            ExecuteWithDelay(PROXIMITY_CHECK_MS, tick)
        end)
    end

    ExecuteWithDelay(PROXIMITY_CHECK_MS, tick)
end

local function show_gunsmith_ui()
    if not load_ui() then return end

    local state, held = build_ui_state()
    if type(ui.SetState) == "function" then
        pcall(function() ui.SetState(state) end)
    end

    local okShow = false
    if type(ui.Show) == "function" then
        okShow = pcall(function() ui.Show() end)
    elseif type(ui.Toggle) == "function" then
        okShow = pcall(function() ui.Toggle() end)
    end

    if not okShow then
        log("UI | show failed")
        return
    end

    handoffCount = handoffCount + 1
    log("HANDOFF SUCCESS | count=" .. tostring(handoffCount) ..
        " | state=" .. tostring(held.state) ..
        " | weapon=" .. tostring(held.weapon) ..
        " | uid=" .. tostring(held.uid))

    arm_f_close_after_open()
    begin_proximity_watch()
    schedule_no_firearm_close(held)
end

local function unwrap_context(ctx)
    local actual = unwrap(ctx)
    return valid(actual) and actual or nil
end

local function register_handoff_hook()
    if hookRegistered then return true end

    local path =
        "/Game/Quests/Blueprints/NPCs/BP_QuestGiver.BP_QuestGiver_C:OnExecuteInteract"

    local fn = nil
    pcall(function() fn = StaticFindObject(path) end)
    if not valid(fn) then return false end

    local ok, a, b = pcall(function()
        return RegisterHook(path, function(ctx, ...)
            local actor = unwrap_context(ctx)
            if not valid(actor) or not valid(spawned) then return end

            -- Compare UObject full names because UE4SS can expose separate Lua
            -- wrappers for the same underlying actor.
            if full_name(actor) ~= full_name(spawned) then return end

            ExecuteInGameThread(function()
                show_gunsmith_ui()
            end)
        end)
    end)

    if not ok then
        log("HOOK | registration failed | " .. tostring(a))
        return false
    end

    hookRegistered = true
    log("HOOK READY | OnExecuteInteract | ids=" .. tostring(a) .. "," .. tostring(b))
    return true
end



local destroy_spawned
local spawn_safe_zone

local function lower_and_respawn(amount)
    amount = tonumber(amount) or 10.0
    DEV_Z_OFFSET = DEV_Z_OFFSET - amount

    local spot = current_test_location()

    log(string.format(
        "DEV | F5 lower requested | location=%s | offset=%.1f | targetZ=%.1f",
        tostring(spot.Name or LOCATION_CONFIG.TestLocation),
        DEV_Z_OFFSET,
        (tonumber(spot.Z) or 0.0) + LOCATION_CONFIG.ZOffset + DEV_Z_OFFSET
    ))

    -- Destroy the current Dave, then create a fresh one at the lowered Z.
    destroy_spawned("F5 lower+respawn")

    ExecuteWithDelay(150, function()
        ExecuteInGameThread(function()
            if spawn_test_location() then
                log(string.format(
                    "DEV | F5 respawn success | location=%s | offset=%.1f | spawnedZ=%.1f",
                    tostring(current_test_location().Name or LOCATION_CONFIG.TestLocation),
                    DEV_Z_OFFSET,
                    (tonumber(current_test_location().Z) or 0.0) + LOCATION_CONFIG.ZOffset + DEV_Z_OFFSET
                ))
            else
                log("DEV | F5 respawn failed")
            end
        end)
    end)
end

destroy_spawned = function(reason)
    hide_ui()
    spawnGeneration = spawnGeneration + 1

    if valid(spawned) then
        local old = spawned
        log("DEV | destroy Dave | reason=" .. tostring(reason or "manual") ..
            " | actor=" .. full_name(old))

        local ok, err = pcall(function()
            old:K2_DestroyActor()
        end)

        if not ok then
            ok, err = pcall(function()
                old:DestroyActor()
            end)
        end

        if not ok then
            log("DEV | destroy request failed | " .. tostring(err))
        else
            log("DEV | destroy requested")
        end
    else
        log("DEV | destroy requested but Dave is not currently valid")
    end

    spawned = nil
end

spawn_safe_zone = function()
    if valid(spawned) then return true end

    local player = local_player()
    if not valid(player) then return false end

    local world = nil
    pcall(function() world = player:GetWorld() end)
    if not valid(world) then
        pcall(function() world = UEHelpers.GetWorld() end)
    end
    if not valid(world) then return false end

    local cls = resolve_exact()
    if not valid(cls) then return false end
    if not register_handoff_hook() then return false end
    load_ui()

    local spot = current_test_location()

    local loc = {
        X = tonumber(spot.X) or 0.0,
        Y = tonumber(spot.Y) or 0.0,
        Z = (tonumber(spot.Z) or 0.0) + LOCATION_CONFIG.ZOffset + DEV_Z_OFFSET,
    }
    local rot = {
        Pitch = tonumber(spot.Pitch) or 0.0,
        Yaw = tonumber(spot.Yaw) or 0.0,
        Roll = tonumber(spot.Roll) or 0.0,
    }

    local ok, err = pcall(function()
        spawned = world:SpawnActor(cls, loc, rot)
    end)

    if not ok or not valid(spawned) then
        spawned = nil
        log("SPAWN FAILED | " .. tostring(err))
        return false
    end

    set_native_name(spawned, "Dave")

    log(string.format(
        "SPAWN SUCCESS | %s | location=%s | index=%d | X=%.1f Y=%.1f Z=%.1f Yaw=%.1f | baseZ=%.1f | zOffset=%.1f | devZOffset=%.1f",
        full_name(spawned),
        tostring(spot.Name or ("Location " .. tostring(LOCATION_CONFIG.TestLocation))),
        LOCATION_CONFIG.TestLocation,
        tonumber(spot.X) or 0.0,
        tonumber(spot.Y) or 0.0,
        (tonumber(spot.Z) or 0.0) + LOCATION_CONFIG.ZOffset + DEV_Z_OFFSET,
        tonumber(spot.Yaw) or 0.0,
        tonumber(spot.Z) or 0.0,
        LOCATION_CONFIG.ZOffset,
        DEV_Z_OFFSET
    ))

    return true
end

local function arm_spawn_retry()
    spawnGeneration = spawnGeneration + 1
    local generation = spawnGeneration
    local round = 0

    local function try_spawn()
        if generation ~= spawnGeneration then return end
        round = round + 1

        ExecuteInGameThread(function()
            if generation ~= spawnGeneration then return end

            if spawn_test_location() then
                return
            end

            if round == 1 or round % 5 == 0 then
                log("SPAWN WAIT | game world not ready | attempt=" .. tostring(round))
            end

            if round < 60 then
                ExecuteWithDelay(2000, try_spawn)
            else
                log("SPAWN STOPPED | test-location spawn never became ready")
            end
        end)
    end

    ExecuteWithDelay(2500, try_spawn)
end

local function register_controls()
    -- Development controls:
    --   F5 = destroy Dave, lower spawn Z by 10 units, then respawn him
    --   F6 = destroy current Dave and spawn a fresh one at the configured test point
    --   F7 = destroy/unload Dave only
    pcall(function()
        RegisterKeyBind(Key.F5, function()
            ExecuteInGameThread(function()
                lower_and_respawn(10.0)
            end)
        end)
    end)

    pcall(function()
        RegisterKeyBind(Key.F6, function()
            ExecuteInGameThread(function()
                destroy_spawned("F6 respawn")
                ExecuteWithDelay(150, function()
                    ExecuteInGameThread(function()
                        if spawn_test_location() then
                            log("DEV | F6 respawn success")
                        else
                            log("DEV | F6 respawn failed; retrying normal spawn loop")
                            arm_spawn_retry()
                        end
                    end)
                end)
            end)
        end)
    end)

    pcall(function()
        RegisterKeyBind(Key.F7, function()
            ExecuteInGameThread(function()
                destroy_spawned("F7 unload")
            end)
        end)
    end)

    -- F closes Dave's panel after the opening keypress debounce.
    pcall(function()
        RegisterKeyBind(Key.F, function()
            ExecuteInGameThread(function()
                if not ui_is_open() then return end
                if not uiFCloseArmed then
                    log("UI | ignored opening F press")
                    return
                end
                hide_ui()
                log("UI CLOSE | F")
            end)
        end)
    end)

    pcall(function()
        RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
            ExecuteInGameThread(function()
                if not ui_is_open() or ui == nil then return end
                if type(ui.IsRerollHovered) ~= "function" then return end

                local hovered = false
                pcall(function() hovered = ui.IsRerollHovered() end)
                if hovered then request_reroll() end
            end)
        end)
    end)

    pcall(function()
        RegisterKeyBind(Key.ESCAPE, function()
            ExecuteInGameThread(function()
                if ui_is_open() then
                    hide_ui()
                    log("UI CLOSE | ESC")
                end
            end)
        end)
    end)
end

function M.Init(callbacks)
    assert(type(callbacks) == "table", "Gunsmith.Init requires callbacks")
    assert(type(callbacks.GetSnapshot) == "function", "Gunsmith requires GetSnapshot")
    assert(type(callbacks.Reroll) == "function", "Gunsmith requires Reroll")

    api = callbacks

    load_ui()
    register_controls()
    arm_spawn_retry()

    log("INTEGRATED READY | direct in-memory WeaponProgression access")
    local selected = current_test_location()
    log("LOCATION CONFIG | " .. tostring(LOCATION_FILE))
    log("TEST LOCATION | index=" .. tostring(LOCATION_CONFIG.TestLocation) ..
        " | name=" .. tostring(selected.Name or "<unnamed>") ..
        " | rawZ=" .. tostring(selected.Z) ..
        " | ZOffset=" .. tostring(LOCATION_CONFIG.ZOffset))
    log("DEV CONTROLS | F5=lower+respawn Dave 10u | F6=respawn current test Z | F7=remove Dave")
    return true
end

return M
