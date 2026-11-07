-- Dave's developer keys only exist when [Utility] DevControls=true.
local H = require("fake_game")

test("F5/F6/F7 dev keys are not registered by default", function()
    local g = H.new_game({ name = "controls", real_gunsmith = true })
    g:boot()
    eq(g.keybinds.F5, nil, "F5"); eq(g.keybinds.F6, nil, "F6"); eq(g.keybinds.F7, nil, "F7")
    ok(g.keybinds.F ~= nil, "Dave's F close key still registered")
    ok(g.keybinds.F8 ~= nil, "F8 progression panel still registered")
    ok(g:has_log("DEV CONTROLS | disabled"), "disabled state logged")
end)

test("DevControls=true registers F5/F6/F7", function()
    local g = H.new_game({ name = "controls", real_gunsmith = true, config = { Utility = { DevControls = "true" } } })
    g:boot()
    ok(g.keybinds.F5 and g.keybinds.F6 and g.keybinds.F7, "all three dev keys registered")
    ok(g:has_log("DEV CONTROLS | ENABLED"), "enabled state logged")
end)
