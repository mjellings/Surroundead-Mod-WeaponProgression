-- ============================================================================
-- NPCRerollResearch - Dave's Gunsmith UI v0.18
--
-- Layout rewrite:
--   * one root Canvas coordinate space
--   * frame/background are decorative siblings, not layout parents
--   * all children use the same coordinate system
--   * UI-only input while open so clicks do not fire the held weapon
--
-- Presentation only. WeaponProgression remains authoritative for rerolls.
-- ============================================================================

local UI = {}
local PREFIX = "[DaveGunsmith.UI] "

local config = {
    title = "DAVE'S GUNSMITH",
    x = 92.0,
    y = 210.0,
    width = 620.0,
    height = 470.0,
    z_order = 500,

    frame_colour      = { R=0.34, G=0.34, B=0.34, A=1.00 },
    background_colour = { R=0.045, G=0.045, B=0.045, A=0.96 },
    divider_colour    = { R=0.30, G=0.30, B=0.30, A=0.90 },
    text_colour       = { R=0.93, G=0.93, B=0.93, A=1.00 },
    muted_text_colour = { R=0.68, G=0.68, B=0.68, A=1.00 },
    button_colour     = { R=0.22, G=0.22, B=0.22, A=1.00 },
    button_disabled   = { R=0.10, G=0.10, B=0.10, A=0.75 },

    title_size   = 12,
    weapon_size  = 23,
    label_size   = 13,
    value_size   = 14,
    message_size = 12,
    button_size  = 14,
}

local runtime = {
    root=nil,
    tree=nil,
    canvas=nil,
    refs={
        frame=nil,
        background=nil,
        title=nil,
        weapon=nil,
        level=nil,
        rank=nil,
        service=nil,
        message=nil,
        button=nil,
        button_text=nil,
        stat_labels={},
        stat_values={},
    },
    state=nil,
    serial=0,
    previous_cursor=nil,
    cursor_pc=nil,
}

local STAT_ROWS = {
    {key="damage",     label="Damage"},
    {key="critmult",   label="Critical Hit Multiplier"},
    {key="critchance", label="Critical Hit Chance"},
    {key="rpm",        label="RPM"},
    {key="falloff",    label="Damage Falloff"},
}

local function log(message)
    print(PREFIX .. tostring(message) .. "\n")
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    ok, result = pcall(function() return value:Get() end)
    if ok and result ~= nil then return result end
    return value
end

local function is_valid(value)
    local obj = unwrap(value)
    if obj == nil then return false end
    local ok, result = pcall(function() return obj:IsValid() end)
    return ok and result == true
end

local function find_object(path)
    local ok, result = pcall(function() return StaticFindObject(path) end)
    if not ok then return nil end
    return unwrap(result)
end

local function find_outer()
    for _, class_name in ipairs({
        "SD_GameInstance_C",
        "GameInstance",
        "BP_PlayerController_C",
        "PlayerController",
    }) do
        local ok, result = pcall(function() return FindFirstOf(class_name) end)
        if ok then
            local obj = unwrap(result)
            if obj ~= nil and is_valid(obj) then return obj end
        end
    end
    return nil
end

local function find_player_controller()
    for _, class_name in ipairs({"BP_PlayerController_C", "PlayerController"}) do
        local ok, result = pcall(function() return FindFirstOf(class_name) end)
        if ok then
            local obj = unwrap(result)
            if obj ~= nil and is_valid(obj) then return obj end
        end
    end
    return nil
end

local function construct(class_path, outer, name)
    local class = find_object(class_path)
    if class == nil then return nil end
    local ok, result = pcall(function()
        return StaticConstructObject(class, outer, FName(name))
    end)
    if not ok then
        log("construct failed | " .. tostring(class_path) .. " | " .. tostring(result))
        return nil
    end
    return unwrap(result)
end

local function make_vector2d(x, y)
    local lib = find_object("/Script/Engine.Default__KismetMathLibrary")
    if lib == nil then return nil end
    local ok, result = pcall(function() return lib:MakeVector2D(x, y) end)
    if not ok then return nil end
    return result
end

local function make_text(value)
    local lib = find_object("/Script/Engine.Default__KismetTextLibrary")
    if lib == nil then return nil end
    local ok, result = pcall(function()
        return lib:Conv_StringToText(tostring(value or ""))
    end)
    if not ok then return nil end
    return result
end

local function set_text_raw(block, value)
    if block == nil or not is_valid(block) then return false end
    local ftext = make_text(value)
    if ftext == nil then return false end
    local ok = pcall(function() block:SetText(ftext) end)
    return ok
end

local function style_text(block, size, colour)
    pcall(function()
        local font = block.Font
        font.Size = size
        block.Font = font
    end)
    pcall(function()
        block:SetColorAndOpacity({SpecifiedColor=colour, ColorUseRule=0})
    end)
end

local function add_canvas_child(canvas, widget, x, y, width, height)
    local ok, result = pcall(function() return canvas:AddChildToCanvas(widget) end)
    if not ok then return nil end
    local slot = unwrap(result)
    if slot == nil then return nil end

    local pos = make_vector2d(x, y)
    local size = make_vector2d(width, height)
    if pos == nil or size == nil then return nil end

    pcall(function() slot:SetPosition(pos) end)
    pcall(function() slot:SetSize(size) end)
    return slot
end

local function make_text_block(canvas, suffix, name, initial, size, colour, x, y, w, h)
    local block = construct("/Script/UMG.TextBlock", canvas, "DG_" .. name .. "_" .. suffix)
    if block == nil then return nil end
    style_text(block, size, colour)
    set_text_raw(block, initial or "")
    if add_canvas_child(canvas, block, x, y, w, h) == nil then return nil end
    return block
end

local function make_border(canvas, suffix, name, colour, x, y, w, h)
    local border = construct("/Script/UMG.Border", canvas, "DG_" .. name .. "_" .. suffix)
    if border == nil then return nil end
    pcall(function() border:SetBrushColor(colour) end)
    if add_canvas_child(canvas, border, x, y, w, h) == nil then return nil end
    return border
end

local function set_cursor(show)
    if show then
        local pc = find_player_controller()
        if pc == nil then return end
        runtime.cursor_pc = pc
        pcall(function()
            runtime.previous_cursor = pc.bShowMouseCursor
            pc.bShowMouseCursor = true
        end)
    else
        local pc = runtime.cursor_pc
        if pc ~= nil and is_valid(pc) then
            pcall(function()
                pc.bShowMouseCursor = (runtime.previous_cursor == true)
            end)
        end
        runtime.cursor_pc = nil
        runtime.previous_cursor = nil
    end
end

local function set_ui_input_mode(show)
    local pc = runtime.cursor_pc or find_player_controller()
    if pc == nil then return false end

    local lib = find_object("/Script/UMG.Default__WidgetBlueprintLibrary")
    if lib == nil then
        log("input mode | WidgetBlueprintLibrary unavailable")
        return false
    end

    if show then
        local ok, err = pcall(function()
            lib:SetInputMode_UIOnlyEx(pc, runtime.root, 2, false)
        end)
        if ok then
            log("input mode | UIOnly")
            return true
        end

        ok, err = pcall(function()
            lib:SetInputMode_GameAndUIEx(pc, runtime.root, 2, false, false)
        end)
        if ok then
            log("input mode | GameAndUI fallback")
            return true
        end

        log("input mode | UI capture failed | " .. tostring(err))
        return false
    end

    local ok, err = pcall(function()
        lib:SetInputMode_GameOnly(pc, false)
    end)
    if ok then
        log("input mode | GameOnly restored")
        return true
    end

    log("input mode | GameOnly restore failed | " .. tostring(err))
    return false
end

local function clear_refs()
    runtime.root=nil
    runtime.tree=nil
    runtime.canvas=nil
    runtime.refs.frame=nil
    runtime.refs.background=nil
    runtime.refs.title=nil
    runtime.refs.weapon=nil
    runtime.refs.level=nil
    runtime.refs.rank=nil
    runtime.refs.service=nil
    runtime.refs.message=nil
    runtime.refs.button=nil
    runtime.refs.button_text=nil
    runtime.refs.stat_labels={}
    runtime.refs.stat_values={}
end

local function build()
    if runtime.root ~= nil and is_valid(runtime.root) then return true end
    clear_refs()

    local outer = find_outer()
    if outer == nil then return false end

    runtime.serial = runtime.serial + 1
    local suffix = tostring(runtime.serial)

    local root = construct("/Script/UMG.UserWidget", outer, "DG_Root_" .. suffix)
    if root == nil then return false end

    local tree = construct("/Script/UMG.WidgetTree", root, "DG_Tree_" .. suffix)
    if tree == nil then return false end
    if not pcall(function() root.WidgetTree = tree end) then return false end

    local canvas = construct("/Script/UMG.CanvasPanel", tree, "DG_RootCanvas_" .. suffix)
    if canvas == nil then return false end
    if not pcall(function() tree.RootWidget = canvas end) then return false end

    local X = config.x
    local Y = config.y
    local W = config.width
    local H = config.height

    -- Shell: decorative siblings only. Nothing is nested inside these borders.
    local frame = make_border(canvas, suffix, "Frame", config.frame_colour, X, Y, W, H)
    local background = make_border(canvas, suffix, "Background", config.background_colour,
        X + 3, Y + 3, W - 6, H - 6)

    if frame == nil or background == nil then return false end

    local function tx(name, text, size, colour, lx, ly, lw, lh)
        return make_text_block(canvas, suffix, name, text, size, colour,
            X + lx, Y + ly, lw, lh)
    end

    local function divider(name, ly)
        return make_border(canvas, suffix, name, config.divider_colour,
            X + 20, Y + ly, W - 40, 1)
    end

    -- Header
    local title = tx("Title", config.title,
        config.title_size, config.muted_text_colour,
        20, 13, W - 40, 20)

    local weapon = tx("Weapon", "No active weapon",
        config.weapon_size, config.text_colour,
        20, 34, W - 40, 32)

    divider("DividerHeader", 70)

    local level = tx("Level", "LEVEL --",
        config.label_size, config.muted_text_colour,
        20, 82, 180, 22)

    local rank = tx("Rank", "",
        config.label_size, config.text_colour,
        W - 205, 82, 185, 22)

    divider("DividerStats", 111)

    -- Stats
    local statY = 126
    for _, row in ipairs(STAT_ROWS) do
        runtime.refs.stat_labels[row.key] = tx(
            "StatLabel_" .. row.key,
            row.label,
            config.label_size,
            config.muted_text_colour,
            20, statY, 255, 22
        )

        runtime.refs.stat_values[row.key] = tx(
            "StatValue_" .. row.key,
            "--",
            config.value_size,
            config.text_colour,
            300, statY - 1, W - 320, 24
        )

        statY = statY + 30
    end

    divider("DividerService", 281)

    -- Service footer
    local service = tx("Service", "FREE REROLL",
        config.title_size, config.muted_text_colour,
        20, 292, 180, 20)

    local message = tx("Message",
        "Redistributes ordinary progression bonuses.\nLevel, XP, kills and mastery are preserved.",
        config.message_size, config.text_colour,
        20, 318, W - 40, 54)

    -- Keep the action completely separate from explanatory copy.
    divider("DividerAction", 385)

    local buttonW = 170
    local buttonH = 42
    local buttonX = X + W - 20 - buttonW
    local buttonY = Y + 402

    local button = construct("/Script/UMG.Button", canvas, "DG_RerollButton_" .. suffix)
    if button ~= nil then
        add_canvas_child(canvas, button, buttonX, buttonY, buttonW, buttonH)
        pcall(function() button:SetBackgroundColor(config.button_colour) end)
        pcall(function() button.IsFocusable = true end)

        local buttonText = construct("/Script/UMG.TextBlock", button, "DG_RerollText_" .. suffix)
        if buttonText ~= nil then
            style_text(buttonText, config.button_size, config.text_colour)
            set_text_raw(buttonText, "REROLL")
            pcall(function() button:SetContent(buttonText) end)
            runtime.refs.button_text = buttonText
        end
    end

    if title == nil or weapon == nil or level == nil or rank == nil
       or service == nil or message == nil then
        return false
    end

    runtime.root=root
    runtime.tree=tree
    runtime.canvas=canvas
    runtime.refs.frame=frame
    runtime.refs.background=background
    runtime.refs.title=title
    runtime.refs.weapon=weapon
    runtime.refs.level=level
    runtime.refs.rank=rank
    runtime.refs.service=service
    runtime.refs.message=message
    runtime.refs.button=button

    return true
end

local function set_widget_text(ref, value)
    if ref ~= nil then set_text_raw(ref, tostring(value or "")) end
end

local function set_button_enabled(enabled)
    local button = runtime.refs.button
    if button == nil or not is_valid(button) then return end

    pcall(function() button:SetIsEnabled(enabled == true) end)
    pcall(function()
        button:SetBackgroundColor(
            (enabled == true) and config.button_colour or config.button_disabled
        )
    end)
end

local function render(state)
    if runtime.root == nil or not is_valid(runtime.root) then return false end
    state = state or {}
    runtime.state = state

    set_widget_text(runtime.refs.weapon, state.weapon or "No active weapon")

    if state.level ~= nil then
        set_widget_text(runtime.refs.level,
            "LEVEL " .. tostring(math.floor(tonumber(state.level) or 1)))
    else
        set_widget_text(runtime.refs.level, "")
    end

    set_widget_text(runtime.refs.rank, state.rank or "")

    local stats = state.stats or {}
    for _, row in ipairs(STAT_ROWS) do
        local st = stats[row.key]
        local label = runtime.refs.stat_labels[row.key]
        local value = runtime.refs.stat_values[row.key]

        if st ~= nil then
            pcall(function() label:SetRenderOpacity(1.0) end)
            pcall(function() value:SetRenderOpacity(1.0) end)

            local rendered = tostring(st.base or "--")
                .. "  ->  "
                .. tostring(st.current or "--")

            if st.bonus ~= nil and tostring(st.bonus) ~= "" then
                rendered = rendered .. "   (" .. tostring(st.bonus) .. ")"
            end

            set_widget_text(value, rendered)
        else
            pcall(function() label:SetRenderOpacity(0.0) end)
            pcall(function() value:SetRenderOpacity(0.0) end)
        end
    end

    set_widget_text(runtime.refs.message,
        state.message
        or state.status
        or "Redistributes ordinary progression bonuses.\nLevel, XP, kills and mastery are preserved.")

    set_widget_text(runtime.refs.button_text, state.button_text or "REROLL")
    set_button_enabled(state.button_enabled == true)

    local buttonOpacity = (state.show_button == false) and 0.0 or 1.0
    if runtime.refs.button ~= nil then
        pcall(function() runtime.refs.button:SetRenderOpacity(buttonOpacity) end)
    end
    if runtime.refs.button_text ~= nil then
        pcall(function() runtime.refs.button_text:SetRenderOpacity(buttonOpacity) end)
    end

    return true
end

function UI.Configure(options)
    if type(options) ~= "table" then return end
    for k, v in pairs(options) do
        if config[k] ~= nil then config[k] = v end
    end
end

function UI.SetProvider(_) end

function UI.SetState(state)
    runtime.state = state
    return render(state)
end

function UI.Refresh()
    return render(runtime.state)
end

function UI.IsOpen()
    return runtime.root ~= nil and is_valid(runtime.root)
end

function UI.IsRerollHovered()
    local button = runtime.refs.button
    if button == nil or not is_valid(button) then return false end
    local ok, hovered = pcall(function() return button:IsHovered() end)
    return ok and hovered == true
end

function UI.Show()
    if UI.IsOpen() then return UI.Refresh() end
    if not build() then return false end

    local ok, err = pcall(function()
        runtime.root:AddToViewport(config.z_order)
    end)

    if not ok then
        log("AddToViewport failed | " .. tostring(err))
        clear_refs()
        return false
    end

    pcall(function() runtime.root:SetVisibility(0) end)

    set_cursor(true)
    set_ui_input_mode(true)
    UI.Refresh()
    return true
end

function UI.Hide()
    set_ui_input_mode(false)
    set_cursor(false)

    if runtime.root ~= nil and is_valid(runtime.root) then
        pcall(function() runtime.root:RemoveFromParent() end)
    end

    clear_refs()
    return true
end

function UI.Toggle()
    if UI.IsOpen() then return UI.Hide() end
    return UI.Show()
end

function UI.Destroy()
    UI.Hide()
    runtime.state=nil
end

return UI
