return function(H, repo_root)
    local path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua"

    local settings = {}
    local fake_mod = {
        get = function(_, key) return settings[key] end,
        command = function() end,
        info = function() end,
    }
    local old_get_mod = _G.get_mod
    _G.get_mod = function() return fake_mod end
    local Picker = assert(loadfile(path))()
    _G.get_mod = old_get_mod

    H.test("CWV animation picker scopes picks to receiver and preserves defaults", function()
        local sid = "cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"
        settings.enable_cwv_dev_anim_picker = true
        settings[sid] = "attack_swing_heavy_down"
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"),
            "attack_swing_heavy_down")
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_zealot", "attack_swing_heavy_right"),
            "attack_swing_heavy_down")
        H.equal(Picker.resolve("dr_dual_wield_axes", "dr_slayer", "attack_swing_heavy_right"), nil)
        H.equal(Picker.resolve("dr_dual_wield_axes", "es_mercenary", "attack_swing_heavy_right"), nil)
        settings[sid] = "__cwv_anim_unset__"
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"), nil)
        settings[sid] = "attack_swing_heavy_down"
        settings.enable_cwv_dev_anim_picker = false
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"), nil,
            "master toggle off must restore baked/default behavior")
    end)

    H.test("CWV animation picker options are closed-vocabulary and unshared", function()
        local groups = Picker.build_widget_tree()
        H.equal(#groups, 2)
        local first = groups[1].sub_widgets[1]
        local second = groups[1].sub_widgets[2]
        H.truthy(first.options ~= second.options)
        H.equal(first.options[1].value, "__cwv_anim_unset__")
        settings.enable_cwv_dev_anim_picker = true
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] =
            "invented_not_receiver_native"
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_captain", "attack_swing_heavy_right"), nil,
            "invalid persisted values must never reach the animation network lookup")
        H.truthy(Picker.regression_check():find("out%-of%-vocabulary"))
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] = nil
        H.equal(Picker.regression_check(), nil)
    end)

    H.test("CWV issue 317 picker owns only the pre-RPC resolver seam", function()
        local main_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(main_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("mod._cwv_dev_anim_picker.resolve(item_key, career, source_event)", 1, true))
        H.truthy(source:find('mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true))
        local picker_file = assert(io.open(path, "rb"))
        local picker_source = picker_file:read("*a")
        picker_file:close()
        H.equal(picker_source:find("anim_event_3p%s*="), nil,
            "picker must not mutate the shared Bardin template")
        H.equal(picker_source:find("NetworkLookup", 1, true), nil,
            "picker must not add a network payload")
    end)
end
