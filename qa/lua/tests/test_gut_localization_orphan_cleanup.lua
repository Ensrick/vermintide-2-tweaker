return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(repo_root .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("GUT #219 removes only the dissolved HUD container label", function()
        local localization = read(
            "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization.lua")
        H.equal(localization:find("gut_hud_visibility_group%s*="), nil)
        H.truthy(localization:find("gut_hide_hud_ui_group%s*=") ~= nil)
        H.truthy(localization:find("gut_hud_mode%s*=") ~= nil)
        H.truthy(localization:find("gut_hud_cycle_hotkey%s*=") ~= nil)
        H.truthy(localization:find("hb_group%s*=") ~= nil)
    end)

    H.test("GUT #219 preserves the live HUD group and direct controls", function()
        local data = read(
            "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_data.lua")
        H.equal(data:find('setting_id%s*=%s*"gut_hud_visibility_group"'), nil)
        H.truthy(data:find('setting_id%s*=%s*"gut_hide_hud_ui_group"') ~= nil)
        H.truthy(data:find('setting_id%s*=%s*"hb_group"') ~= nil)
        H.truthy(data:find('setting_id%s*=%s*"gut_hud_mode"') ~= nil)
        H.truthy(data:find('setting_id%s*=%s*"gut_hud_cycle_hotkey"') ~= nil)
    end)

    H.test("GUT #824 runtime localization check loads the dev localization resource", function()
        local main = read("/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        H.truthy(main:find(
            'pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization")',
            1, true))
        H.equal(main:find("scripts/mods/gui_tweaker_dev/gui_tweaker_localization", 1, true), nil)
        H.truthy(main:find("localization table could not be loaded", 1, true))
    end)
end
