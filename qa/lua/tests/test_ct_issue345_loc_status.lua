return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_localization.lua"
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a")
    f:close()

    local function authored_value(key)
        local escaped = key:gsub("([^%w])", "%%%1")
        return source:match("\n%s*" .. escaped .. "%s*=%s*{%s*en%s*=%s*\"([^\"]*)\"")
    end

    H.test("CT #345 status rows match the current open-issue label surface", function()
        local expected = {
            inject_adventure_maps = "[diag] [Issue 52 & 251] Inject Adventure Missions into CW Map Pool",
            progressive_difficulty = "[untested] Progressive Difficulty",
            finale_dominant_god = "[diag] [Issue 135] Finale God",
            respawn_on_chest_complete = "[verify-fix] [Issue 299] Revive Team on Chest Completion",
            disable_boon_ct_meta_ammo = "[verify-fix] [diag] [Issue 256 & 249] Disable Boon: (Mod Boon) Quiver Cascade",
            start_boon_ct_meta_ammo = "[verify-fix] [diag] [Issue 256 & 249] Starting Boon: (Mod Boon) Quiver Cascade",
            enable_boon_vauls_anvil = "[verify-fix] [Issue 144] Rework: Vaul's Anvil as Boon (Unique)",
            start_boon_ct_boon_vauls_anvil = "[verify-fix] [Issue 144] Starting Boon: (Mod Boon) Vaul's Anvil",
        }
        for key, value in pairs(expected) do H.equal(authored_value(key), value, key) end
    end)

    H.test("CT #345 removes closed references and keeps navigation groups untagged", function()
        H.equal(authored_value("starting_boons_group"), "Starting Boons")
        for _, issue in ipairs({ "131", "145", "156", "291" }) do
            for _, key in ipairs({
                "inject_adventure_maps", "progressive_difficulty", "finale_dominant_god",
                "respawn_on_chest_complete", "disable_boon_ct_meta_ammo",
                "start_boon_ct_meta_ammo", "starting_boons_group",
            }) do
                local value = authored_value(key) or ""
                H.equal(value:find("Issue " .. issue, 1, true), nil,
                    key .. " retains closed #" .. issue)
            end
        end
    end)

    H.test("CT #345 runtime regression mirrors the offline status contract", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local main_file = assert(io.open(main_path, "rb"))
        local main = main_file:read("*a")
        main_file:close()
        H.truthy(main:find('_rt_register("issue345_ct_localization_status_sync"', 1, true))
        H.truthy(main:find('mod:localize("starting_boons_group") ~= "Starting Boons"', 1, true))
    end)
end
