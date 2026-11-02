-- Exact selected donor promotion checks; behavioral owners keep their own suites.
return function(H, repo_root)
    local public = "gui_tweaker/scripts/mods/gui_tweaker/"
    local dev = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function read(path)
        local f = assert(io.open(repo_root .. "/" .. path, "rb"))
        local text = f:read("*a"); f:close()
        return text:gsub("\r\n", "\n")
    end
    local function normalized(text)
        return text:gsub("gui_tweaker_dev", "gui_tweaker"):gsub("gut_dev", "gut")
    end
    for _, name in ipairs({
        "_gut_reset_presentation",
        "_gut_reset_presentation_core",
        "_gut_loadout_paging",
        "_gut_loadout_page_mapper",
        "_gut_loadout_capacity_policy",
        "_gut_damage_numbers",
        "_gut_damage_numbers_policy",
        "_gut_cutscene_skipwindow",
        "_gut_cutscene_policy274",
        "_gut_bot_pose",
        "_gut_tab_property_refresh",
        "_gut_tab_property_policy",
        "_gut_tab_talent_refresh",
        "_gut_respawn_timer",
        "_gut_mission_map",
        "_gut_mission_vote_policy",
        "_gut_video_profiles",
        "_gut_video_profiles_core",
        "_gut_hidden_passives",
        "_gut_hidden_passive_policy",
        "_gut_simple_ui_bounds_policy",
        "_gut_simple_ui_compat",
        "_gut_simple_ui_dropdowns",
        "_gut_scoreboard_live",
        "_gut_scoreboard_policy",
        "_gut_scoreboard_retention",
        "_gut_boss_damage_sync",
        "_gut_boss_damage_sync_policy",
        "_gut_custom_stats",
        "_gut_custom_stats_policy",
        "_gut_custom_stat_sync",
        "_gut_custom_stat_sync_policy",
        "_gut_gui_material_guard",
        "_lib_resource_residency",
        "_lib_ui_presentation_refresh",
        "_gut_freecam",
    }) do
        local module = name
        H.test("GUI public selected donor identity " .. module, function()
            local actual = read(public .. module .. ".lua")
            local expected = normalized(read(dev .. module .. ".lua"))
            H.truthy(actual == expected, module .. " diverged from selected reviewed donor")
            H.truthy(loadstring(actual, "@" .. public .. module .. ".lua"),
                module .. " fails complete Lua 5.1 compilation")
        end)
    end

    H.test("GUI public mission boundary uses only the official CIM provider", function()
        local source = read(public .. "_gut_mission_inventory.lua")
        local gate = source:match("local function _gut_cim_present%(%)%s*(.-)%s*end")
        H.equal(gate, 'return get_mod("cim") ~= nil')
        local tail = source:match("%-%- _gut_mission_inventory%.lua(.*)$")
        local donor = normalized(read(dev .. "_gut_mission_inventory.lua"))
        H.truthy(tail == donor:match("%-%- _gut_mission_inventory%.lua(.*)$"),
            "public mission boundary changed beyond its explicit provider isolation")
    end)

    H.test("GUI public cutscenes retain behavior without the unrelated diagnostic probe", function()
        local expected = normalized(read(dev .. "_gut_cutscenes.lua"))
        expected = expected:gsub('local _probe257 = [^\n]*\nlocal _probe257_state = [^\n]*\n', '', 1)
        expected = expected:gsub('%-%- Automatic #257 evidence,[\n\r]?.-\nend\n\n', '', 1)
        local count
        expected, count = expected:gsub('\n[ \t]+_trace257%b()%s*\n', '\n')
        H.equal(count, 6, "selected donor probe-call inventory changed")
        expected = expected:gsub('for i = 1, #%(_probe257.rt_checks or {}%) do.-\nend\n', '', 1)
        local actual = read(public .. "_gut_cutscenes.lua")
        H.truthy(actual == expected, "public cutscene behavior drifted beyond diagnostic removal")
        H.equal(actual:find("_probe257", 1, true), nil)
        H.equal(actual:find("_trace257", 1, true), nil)
        H.truthy(loadstring(actual, "@public-cutscenes"))
    end)

    H.test("GUI public rollup retains identity and the complete issue inventory", function()
        local cfg = read("gui_tweaker/itemV2.cfg")
        H.truthy(cfg:find('title = "Tweaker: GUI v0.2.290"', 1, true))
        H.truthy(cfg:find("published_id = 3732144878L", 1, true))
        H.truthy(cfg:find('visibility = "public"', 1, true))
        local main = read(public .. "gui_tweaker.lua")
        H.truthy(main:find('local MOD_VERSION = "0.2.290"', 1, true))
        local notes = read("gui_tweaker/CHANGELOG.md"):match("## 0%.2%.290(.-)## 0%.2%.289")
        H.truthy(notes, "public release notes missing")
        for _, issue in ipairs({
            1575,1573,1572,1571,1570,1448,1414,1033,954,938,925,881,717,700,
            605,547,522,402,389,375,354,353,314,292,287,285,281,274,273,
            250,246,245,232,231,224,172,167,153,92,87,80,1796,
        }) do
            H.truthy(notes:find("#" .. issue .. "%f[^0-9]"),
                "public rollup lost issue " .. issue)
        end
        local package = read("gui_tweaker/resource_packages/gui_tweaker/gui_tweaker.package")
        H.truthy(package:find('"scripts/mods/gui_tweaker/*"', 1, true))
    end)

    local function material_guard(can_get)
        local hook, count = nil, 0
        local mod = { info = function() end }
        function mod:dofile(path)
            H.equal(path, "scripts/mods/gui_tweaker/_lib_resource_residency")
            return assert(loadfile(repo_root .. "/gui_tweaker/" .. path .. ".lua"))()
        end
        function mod:hook(class, method, callback)
            H.equal(class, "UIRenderer"); H.equal(method, "create")
            count, hook = count + 1, callback
        end
        local env = setmetatable({
            get_mod = function(id) H.equal(id, "gut"); return mod end,
            Application = { can_get = can_get }, printf = function() end,
        }, { __index = _G })
        env._G = env
        local chunk = assert(loadstring(read(public .. "_gut_gui_material_guard.lua")))
        setfenv(chunk, env); chunk()
        H.equal(count, 1)
        return hook, mod, env
    end

    H.test("GUI public installed material hook preserves unknowns and nil tuples", function()
        local hook = material_guard(function(kind, path)
            H.equal(kind, "material")
            if path == "unknown" then error("foreign resource is unreadable") end
            return path ~= "missing"
        end)
        local count, args
        local a, b, c = hook(function(world, ...)
            H.equal(world, "world")
            count, args = select("#", ...), { ... }
            return "renderer", nil, "third"
        end, "world", "material", "present", "material", "missing", "material", "unknown", nil, "other", nil)
        H.equal(count, 7)
        H.deep_equal(args, { "material", "present", "material", "unknown", nil, "other" })
        H.equal(a, "renderer"); H.equal(b, nil); H.equal(c, "third")
    end)

    H.test("GUI public installed material hook is passive without a trusted font probe", function()
        local hook = material_guard(function() return false end)
        local seen
        hook(function(_, ...) seen = { n = select("#", ...), ... } end,
            "world", "material", "missing", nil)
        H.equal(seen.n, 3)
        H.equal(seen[2], "missing")
    end)

    H.test("GUI public installed material hook publishes only resident mission atlases", function()
        local hook, mod, env = material_guard(function(_, path)
            return path ~= "materials/ui/ui_1080p_store_menu"
        end)
        env.AreaSettings = { test = { video_settings = { material_name = "area_video", resource = "video_resource" } } }
        local received
        hook(function(_, ...) received = { ... } end,
            "world", "material", "materials/ui/ui_1080p_hud_atlas_textures")
        H.equal(mod._gut_pose_atlas_ingame, true)
        H.equal(mod._gut_area_videos_ingame.area_video, true)
        local found = {}
        for i = 1, #received do found[received[i]] = true end
        H.equal(found["materials/ui/ui_1080p_pose_cosmetics"], true)
        H.equal(found["materials/ui/ui_1080p_store_menu"], nil)
        H.equal(found.video_resource, true)
    end)

    H.test("GUI public rollup excludes unrelated development investigations", function()
        for _, name in ipairs({
            "_gut_career_swap", "_gut_all_languages", "_gut_dx12_fence630",
            "_gut_diag_optionsview", "_gut_diag_cutscene257",
            "_gut_screen_particle_ledger", "_gut_diagnostics",
            "_gut_career_hud_holder_policy",
        }) do
            local f = io.open(repo_root .. "/" .. public .. name .. ".lua", "rb")
            if f then f:close() end
            H.equal(f, nil, "unselected dev investigation entered public: " .. name)
        end
    end)
end
