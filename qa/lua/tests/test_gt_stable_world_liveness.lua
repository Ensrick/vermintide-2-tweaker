return function(H, repo_root)
    local function read(path)
        local f = assert(io.open(repo_root .. "/" .. path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    H.test("GT stable debug HUD uses a resident GUI material", function()
        local s = read("general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua")
        H.truthy(s:find('GUI_MTRL  = "materials/fonts/gw_fonts"', 1, true))
        H.truthy(s:find('World.create_screen_gui(world, "material", GUI_MTRL', 1, true))
        H.equal(s:find('World.create_screen_gui(world, "material", FONT_MTRL', 1, true), nil)
    end)

    H.test("GT stable native draw paths gate level-world liveness", function()
        local bot = read("general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua")
        local solo = read("general_tweaker/scripts/mods/general_tweaker/_gt_solo_qol.lua")
        H.truthy(bot:find('has_world("level_world")', 1, true))
        H.truthy(bot:find("w == live", 1, true))
        H.truthy(solo:find('has_world("level_world")', 1, true))
    end)
end
