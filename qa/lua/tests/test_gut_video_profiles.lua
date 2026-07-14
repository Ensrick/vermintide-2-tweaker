return function(H, repo_root)
    local Core = dofile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_video_profiles_core.lua")

    local function widget(name, kind, values, selection, value)
        return {
            type = kind,
            content = {
                definition = { callback = name },
                options_values = values,
                current_selection = selection,
                value = value,
            },
        }
    end

    H.test("GUT Video profiles capture concrete native widget values", function()
        local widgets = {
            widget("cb_resolutions", "drop_down", { { 1280, 720 }, { 1920, 1080 } }, 2),
            widget("cb_gamma", "slider", nil, nil, 2.2),
            widget("cb_graphics_quality", "stepper", { "custom", "high" }, 2),
        }
        local profile, count = Core.capture(widgets)
        H.equal(count, 2)
        H.truthy(Core.equal(profile.values.cb_resolutions.value, { 1920, 1080 }))
        H.equal(profile.values.cb_gamma.value, 2.2)
        H.equal(profile.values.cb_graphics_quality, nil)
    end)

    H.test("GUT Video profile replay skips unavailable hardware values", function()
        local saved_widgets = {
            widget("cb_resolutions", "drop_down", { { 1920, 1080 } }, 1),
            widget("cb_dlss_enabled", "stepper", { false, true }, 2),
        }
        local profile = Core.capture(saved_widgets)
        local current_widgets = {
            widget("cb_resolutions", "drop_down", { { 1280, 720 } }, 1),
            widget("cb_gamma", "slider", nil, nil, 2.2),
        }
        local operations, missing = Core.plan(current_widgets, profile)
        H.equal(#operations, 0)
        H.equal(missing, 1)
    end)

    H.test("GUT Video profile keys are bounded and flat", function()
        H.equal(Core.slot_key(0), "gut_video_profile_slot_1")
        H.equal(Core.slot_key(99), "gut_video_profile_slot_5")
        H.equal(Core.name_key(3), "gut_video_profile_name_3")
    end)
end
