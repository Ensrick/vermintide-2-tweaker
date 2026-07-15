return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function read(name)
        local file = assert(io.open(root .. name, "rb"), name)
        local source = file:read("*a")
        file:close()
        return source
    end
    local function absent(name)
        local file = io.open(root .. name, "rb")
        if file then file:close(); return false end
        return true
    end

    H.test("issue528 removes every CKC vanilla Options bridge module", function()
        H.equal(absent("_gut_ckc_bridge.lua"), true)
        H.equal(absent("_gut_ckc_widget_policy.lua"), true)
        H.equal(absent("_gut_ckc_render_policy.lua"), true)
        local main = read("gui_tweaker_dev.lua")
        H.equal(main:find('scripts/mods/gui_tweaker_dev/_gut_ckc_bridge', 1, true), nil)
        H.equal(main:find('cb_crosshair_kill_confirm', 1, true), nil)
        H.equal(main:find('gut_ckc_gear', 1, true), nil)
    end)

    H.test("issue528 leaves non-Video vanilla definitions identity unchanged", function()
        local video = read("_gut_video_profiles.lua")
        H.truthy(video:find("local built_definition = definition", 1, true))
        H.truthy(video:find('if scenegraph_id == "video_settings_list" then', 1, true))
        H.truthy(video:find("return func(self, built_definition, scenegraph_id)", 1, true))
        H.equal(video:find("prepare_settings_definition", 1, true), nil)
        H.equal(video:find("restore_settings_definition", 1, true), nil)
        H.equal(video:find("crosshair_kill_confirm", 1, true), nil)
    end)

    H.test("issue528 removes vanilla gear redirect but keeps Mod Tweaker CKC rows", function()
        local view = read("_mod_tweaker_view.lua")
        local state = read("_mod_tweaker_state.lua")
        H.equal(view:find("_gut_mt_focus_request", 1, true), nil)
        H.equal(view:find("_apply_focus_request", 1, true), nil)
        H.truthy(view:find("_inject_ckc_into_gut", 1, true))
        H.truthy(state:find("_inject_ckc_into_gut", 1, true))
    end)
end
