-- ============================================================================
-- WeaponProgression UI module
-- v0.16.0-dev3 native status-card layout
-- Presentation only: no gameplay hooks, GUID logic, DB access or XP formulas.
-- ============================================================================

local UI = {}
local PREFIX = "[WeaponProgression.UI] "

local config = {
    title = "WEAPON PROGRESSION",
    x = 92.0, y = 250.0, width = 356.0, height = 172.0, z_order = 200,

    outer_colour      = { R=0.18, G=0.18, B=0.18, A=0.95 },
    background_colour = { R=0.035, G=0.035, B=0.035, A=0.94 },
    divider_colour    = { R=0.32, G=0.32, B=0.32, A=0.80 },
    text_colour       = { R=0.93, G=0.93, B=0.93, A=1.00 },
    muted_text_colour = { R=0.68, G=0.68, B=0.68, A=1.00 },
    xp_fill_colour    = { R=0.78, G=0.78, B=0.78, A=1.00 },
    xp_track_colour   = { R=0.12, G=0.12, B=0.12, A=0.95 },

    title_size = 13,
    weapon_size = 23,
    label_size = 14,
    value_size = 16,
}

local runtime = {
    root=nil, tree=nil, canvas=nil, outer=nil, inner=nil, content=nil,
    refs={
        title=nil, weapon=nil,
        level_label=nil, level_value=nil,
        xp_label=nil, xp_value=nil,
        xp_bar=nil, status=nil,
    },
    provider=nil, state=nil, rendered={}, serial=0,
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
        "SD_GameInstance_C", "GameInstance",
        "BP_PlayerController_C", "PlayerController",
    }) do
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
    if class == nil then
        log("construct failed: class unavailable | " .. tostring(class_path))
        return nil
    end

    local ok, result = pcall(function()
        return StaticConstructObject(class, outer, FName(name))
    end)

    if not ok then
        log("construct error | " .. tostring(class_path) .. " | " .. tostring(result))
        return nil
    end

    local obj = unwrap(result)
    if obj == nil or not is_valid(obj) then return nil end
    return obj
end

local function make_vector2d(x, y)
    local lib = find_object("/Script/Engine.Default__KismetMathLibrary")
    if lib == nil then return nil end
    local ok, result = pcall(function() return lib:MakeVector2D(x, y) end)
    if not ok then return nil end
    return result
end

local function make_text(value)
    -- Direct Lua FText construction previously native-crashed SurrounDead.
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
    local ok, err = pcall(function() block:SetText(ftext) end)
    if not ok then
        log("SetText failed | " .. tostring(err))
        return false
    end
    return true
end

local function set_text(key, value)
    value = tostring(value or "")
    if runtime.rendered[key] == value then return true end
    local ref = runtime.refs[key]
    if ref == nil then return false end
    if set_text_raw(ref, value) then
        runtime.rendered[key] = value
        return true
    end
    return false
end

local function set_opacity(widget, value)
    if widget == nil then return end
    pcall(function() widget:SetRenderOpacity(value) end)
end

local function style_text(block, size, colour)
    pcall(function()
        local font = block.Font
        font.Size = size
        block.Font = font
    end)

    pcall(function()
        block:SetColorAndOpacity({
            SpecifiedColor = colour,
            ColorUseRule = 0,
        })
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

local function make_text_block(canvas, suffix, key, initial, size, colour, x, y, width, height)
    local block = construct(
        "/Script/UMG.TextBlock", canvas, "WPUI_" .. key .. "_" .. suffix
    )
    if block == nil then return nil end

    style_text(block, size, colour)
    if not set_text_raw(block, initial or "") then return nil end
    if add_canvas_child(canvas, block, x, y, width, height) == nil then return nil end
    return block
end

local function make_border(canvas, suffix, name, colour, x, y, width, height)
    local border = construct(
        "/Script/UMG.Border", canvas, "WPUI_" .. name .. "_" .. suffix
    )
    if border == nil then return nil end
    pcall(function() border:SetBrushColor(colour) end)
    if add_canvas_child(canvas, border, x, y, width, height) == nil then return nil end
    return border
end

local function clear_widget_refs()
    runtime.root=nil; runtime.tree=nil; runtime.canvas=nil
    runtime.outer=nil; runtime.inner=nil; runtime.content=nil
    for key in pairs(runtime.refs) do runtime.refs[key]=nil end
    runtime.rendered={}
end

local function build()
    if runtime.root ~= nil and is_valid(runtime.root) then return true end
    clear_widget_refs()

    local outer = find_outer()
    if outer == nil then
        log("build aborted: no suitable outer")
        return false
    end

    runtime.serial = runtime.serial + 1
    local suffix = tostring(runtime.serial)

    local root = construct("/Script/UMG.UserWidget", outer, "WPUI_Root_" .. suffix)
    if root == nil then return false end

    local tree = construct("/Script/UMG.WidgetTree", root, "WPUI_Tree_" .. suffix)
    if tree == nil then return false end

    local ok, err = pcall(function() root.WidgetTree = tree end)
    if not ok then
        log("WidgetTree assignment failed | " .. tostring(err))
        return false
    end

    local canvas = construct("/Script/UMG.CanvasPanel", tree, "WPUI_RootCanvas_" .. suffix)
    if canvas == nil then return false end

    ok, err = pcall(function() tree.RootWidget = canvas end)
    if not ok then
        log("RootWidget assignment failed | " .. tostring(err))
        return false
    end

    local outer_frame = make_border(
        canvas, suffix, "OuterFrame", config.outer_colour,
        config.x, config.y, config.width, config.height
    )
    if outer_frame == nil then return false end

    local inner = construct("/Script/UMG.Border", outer_frame, "WPUI_Inner_" .. suffix)
    if inner == nil then return false end
    pcall(function() inner:SetBrushColor(config.background_colour) end)

    ok, err = pcall(function() outer_frame:SetContent(inner) end)
    if not ok then
        log("OuterFrame:SetContent failed | " .. tostring(err))
        return false
    end

    local content = construct("/Script/UMG.CanvasPanel", inner, "WPUI_Content_" .. suffix)
    if content == nil then return false end

    ok, err = pcall(function() inner:SetContent(content) end)
    if not ok then
        log("Inner:SetContent failed | " .. tostring(err))
        return false
    end

    local title = make_text_block(
        content, suffix, "Title", config.title,
        config.title_size, config.muted_text_colour,
        16, 10, 310, 22
    )

    local weapon = make_text_block(
        content, suffix, "Weapon", "No active weapon",
        config.weapon_size, config.text_colour,
        16, 31, 318, 32
    )

    local divider = make_border(
        content, suffix, "Divider", config.divider_colour,
        16, 67, 322, 1
    )

    local level_label = make_text_block(
        content, suffix, "LevelLabel", "LEVEL",
        config.label_size, config.muted_text_colour,
        16, 80, 90, 23
    )

    local level_value = make_text_block(
        content, suffix, "LevelValue", "--",
        config.value_size, config.text_colour,
        265, 78, 70, 25
    )

    local xp_label = make_text_block(
        content, suffix, "XPLabel", "XP",
        config.label_size, config.muted_text_colour,
        16, 107, 90, 23
    )

    local xp_value = make_text_block(
        content, suffix, "XPValue", "--",
        config.value_size, config.text_colour,
        265, 105, 70, 25
    )

    local progress = construct(
        "/Script/UMG.ProgressBar", content, "WPUI_XPBar_" .. suffix
    )

    if progress ~= nil then
        add_canvas_child(content, progress, 16, 137, 322, 12)
        pcall(function() progress:SetPercent(0.0) end)

        -- Keep the filled portion bright, but darken the unfilled track so the
        -- current XP position is immediately readable.
        pcall(function()
            progress:SetFillColorAndOpacity(config.xp_fill_colour)
        end)

        -- UProgressBar's background is stored in WidgetStyle.BackgroundImage.
        -- Mutate a local style copy and assign it back; if this reflected
        -- struct path differs in this UE build, the pcall safely falls back
        -- to the native default.
        pcall(function()
            local style = progress.WidgetStyle
            style.BackgroundImage.TintColor = {
                SpecifiedColor = config.xp_track_colour,
                ColorUseRule = 0,
            }
            progress.WidgetStyle = style
        end)
    end

    local status = make_text_block(
        content, suffix, "Status", "",
        config.label_size, config.muted_text_colour,
        16, 84, 318, 42
    )
    set_opacity(status, 0.0)

    if title == nil or weapon == nil or divider == nil
       or level_label == nil or level_value == nil
       or xp_label == nil or xp_value == nil or status == nil then
        log("build aborted: one or more card widgets failed")
        return false
    end

    runtime.root=root; runtime.tree=tree; runtime.canvas=canvas
    runtime.outer=outer_frame; runtime.inner=inner; runtime.content=content
    runtime.refs.title=title; runtime.refs.weapon=weapon
    runtime.refs.level_label=level_label; runtime.refs.level_value=level_value
    runtime.refs.xp_label=xp_label; runtime.refs.xp_value=xp_value
    runtime.refs.xp_bar=progress; runtime.refs.status=status

    runtime.rendered={
        title=tostring(config.title or ""),
        weapon="No active weapon",
        level_value="--",
        xp_value="--",
        status="",
    }

    return true
end

local function set_progress(value)
    local bar = runtime.refs.xp_bar
    if bar == nil or not is_valid(bar) then return end

    local percent = tonumber(value) or 0
    percent = math.max(0, math.min(100, percent))

    pcall(function()
        bar:SetPercent(percent / 100.0)
    end)
end

local function set_stat_mode(show_stats)
    local stat_opacity = show_stats and 1.0 or 0.0
    local status_opacity = show_stats and 0.0 or 1.0

    set_opacity(runtime.refs.level_label, stat_opacity)
    set_opacity(runtime.refs.level_value, stat_opacity)
    set_opacity(runtime.refs.xp_label, stat_opacity)
    set_opacity(runtime.refs.xp_value, stat_opacity)
    set_opacity(runtime.refs.xp_bar, stat_opacity)
    set_opacity(runtime.refs.status, status_opacity)
end

local function render(state)
    if runtime.root == nil or not is_valid(runtime.root) then return false end
    state = state or {}

    set_text("weapon", state.weapon or "No active weapon")

    if state.status ~= nil and tostring(state.status) ~= "" then
        set_stat_mode(false)
        set_text("status", tostring(state.status))
        set_progress(0)
        return true
    end

    set_stat_mode(true)
    set_text("status", "")

    local level = tonumber(state.level)
    if level == nil then
        set_text("level_value", "--")
    else
        set_text("level_value", tostring(math.floor(level)))
    end

    local xp = tonumber(state.xp_percent)
    if xp == nil then
        set_text("xp_value", "--")
        set_progress(0)
    else
        xp = math.max(0, math.min(100, xp))
        set_text("xp_value", tostring(math.floor(xp + 0.5)) .. "%")
        set_progress(xp)
    end

    return true
end

function UI.Configure(options)
    if type(options) ~= "table" then return end
    for key, value in pairs(options) do
        if config[key] ~= nil then config[key]=value end
    end
end

function UI.SetProvider(provider)
    if provider ~= nil and type(provider) ~= "function" then
        error("WeaponProgression.UI SetProvider expects function or nil")
    end
    runtime.provider=provider
end

function UI.SetState(state)
    if state ~= nil and type(state) ~= "table" then
        error("WeaponProgression.UI SetState expects table or nil")
    end
    runtime.state=state
    return render(state)
end

function UI.Refresh()
    local state=runtime.state
    if runtime.provider ~= nil then
        local ok, result=pcall(runtime.provider)
        if ok then
            state=result
            runtime.state=result
        else
            log("provider failed | " .. tostring(result))
            return false
        end
    end
    return render(state)
end

function UI.IsOpen()
    return runtime.root ~= nil and is_valid(runtime.root)
end

function UI.Show()
    if UI.IsOpen() then
        UI.Refresh()
        return true
    end

    if not build() then return false end

    local ok, err=pcall(function()
        runtime.root:AddToViewport(config.z_order)
    end)

    if not ok then
        log("AddToViewport failed | " .. tostring(err))
        clear_widget_refs()
        return false
    end

    pcall(function() runtime.root:SetVisibility(0) end)
    UI.Refresh()
    return true
end

function UI.Hide()
    if runtime.root ~= nil and is_valid(runtime.root) then
        pcall(function() runtime.root:RemoveFromParent() end)
    end
    clear_widget_refs()
    return true
end

function UI.Toggle()
    if UI.IsOpen() then return UI.Hide() end
    return UI.Show()
end

function UI.Destroy()
    UI.Hide()
    runtime.provider=nil
    runtime.state=nil
end

return UI
