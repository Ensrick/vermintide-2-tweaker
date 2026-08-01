return function(H, repo_root)
    local Core = dofile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_numericui_ammo_core.lua")

    H.test("GUT #249 preserves authoritative dynamically buffed ammo", function()
        local current_ammo, max_ammo, reason = Core.normalize(69, 77)
        H.equal(current_ammo, 69)
        H.equal(max_ammo, 77)
        H.equal(reason, nil)
        H.equal(Core.format(2, current_ammo, max_ammo), "69/77")
    end)

    H.test("GUT #249 formats every NumericUI teammate-ammo mode", function()
        local text, style = Core.format(true, 77, 77)
        H.equal(text, "77")
        H.equal(style, 1)
        text, style = Core.format(2, 77, 77)
        H.equal(text, "77/77")
        H.equal(style, 2)
        text, style = Core.format(3, 77, 77)
        H.equal(text, "")
        H.equal(style, 3)
        H.equal(Core.format(false, 77, 77), nil)
    end)

    H.test("GUT #249 rejects malformed engine ammo values", function()
        local current_ammo, _, reason = Core.normalize(0 / 0, 77)
        H.equal(current_ammo, nil)
        H.equal(reason, "invalid_current")
        current_ammo, _, reason = Core.normalize(10, 0)
        H.equal(current_ammo, nil)
        H.equal(reason, "invalid_max")
        current_ammo, _, reason = Core.normalize(-1, 77)
        H.equal(current_ammo, nil)
        H.equal(reason, "invalid_current")
    end)

    H.test("GUT #249 uses one existing sync hook and no custom wire", function()
        local path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_numericui_cooldown_realtime.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        local hook_count = 0
        for _ in source:gmatch('mod:hook%("UnitFramesHandler", "_sync_player_stats"') do
            hook_count = hook_count + 1
        end
        H.equal(hook_count, 1)
        H.truthy(source:find("inventory.ammo_status", 1, true) ~= nil)
        H.truthy(source:find("[gut:249] corrected peer ammo", 1, true) ~= nil)
        H.truthy(source:find("AMMO_LOG_LIMIT = 12", 1, true) ~= nil)
        H.truthy(source:find("issue249_numericui_authoritative_ammo", 1, true) ~= nil)
        H.truthy(source:find("numericui:authoritative_inventory_ammo_v1", 1, true) ~= nil)
        H.equal(source:find("mod:network_register", 1, true), nil)
        H.equal(source:find("GameSession.set_game_object_field", 1, true), nil)
        H.equal(source:find("ammo_data.max_ammo =", 1, true), nil)
    end)
end
