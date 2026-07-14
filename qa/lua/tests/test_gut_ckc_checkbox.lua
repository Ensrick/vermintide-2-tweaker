return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_ckc_widget_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("CKC bridge temporarily dispatches only its row as a checkbox", function()
        local other = { setting_name = "other", widget_type = "drop_down" }
        local ckc = { setting_name = "crosshair_kill_confirm", widget_type = "drop_down" }
        local definition = { other, ckc }
        local token = Policy.prepare_definition(definition, "crosshair_kill_confirm", true)
        H.truthy(token)
        H.equal(other.widget_type, "drop_down")
        H.equal(ckc.widget_type, "checkbox")
        Policy.restore_definition(token)
        H.equal(ckc.widget_type, "drop_down")
        H.equal(Policy.prepare_definition(definition, "crosshair_kill_confirm", false), nil)
    end)

    H.test("CKC checkbox setup and callbacks use the native boolean flag", function()
        local flag, label, default = Policy.checkbox_setup(true, "menu_settings_crosshair_kill_confirm")
        H.equal(flag, true)
        H.equal(label, "menu_settings_crosshair_kill_confirm")
        H.equal(default, true)
        local content = { flag = false }
        H.equal(Policy.checkbox_value(content), false)
        Policy.restore_checkbox(content, true)
        H.equal(content.flag, true)
        H.equal(Policy.checkbox_value(content), true)
    end)

    H.test("CKC checkbox policy fails closed on malformed definitions", function()
        H.equal(Policy.prepare_definition(nil, "crosshair_kill_confirm", true), nil)
        H.equal(Policy.prepare_definition({}, "crosshair_kill_confirm", true), nil)
        H.equal(Policy.checkbox_value(nil), false)
        Policy.restore_definition(nil)
        Policy.restore_checkbox(nil, true)
    end)
end
