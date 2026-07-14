return function(H, repo_root)
    local path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_overcharge_presentation_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("WT Deepwood profile projects native behavior FX and sounds", function()
        local profile = Policy.extension_profile({
            overcharge_threshold = 10,
            overcharge_value_decrease_rate = 1,
            time_until_overcharge_decreases = 0.5,
            onscreen_particles_id = "fx/thornsister_overcharge",
            critical_onscreen_particles_id = "fx/thornsister_overcharge",
            no_explosion = true,
            no_forced_movement = true,
            overcharge_warning_med_sound_event = "life_medium",
            overcharge_warning_high_sound_event = "life_high",
            overcharge_warning_critical_sound_event = "life_critical",
        })
        H.equal(profile.overcharge_threshold, 10)
        H.equal(profile.overcharge_value_decrease_rate, 1)
        H.equal(profile.screen_space_particle, "fx/thornsister_overcharge")
        H.equal(profile.screen_space_particle_critical, "fx/thornsister_overcharge")
        H.equal(profile.no_explosion, true)
        H.equal(profile.no_forced_movement, true)
        H.equal(profile.state_sounds[2], nil)
        H.equal(profile.state_sounds[3], "life_medium")
        H.equal(profile.state_sounds[5], "life_critical")
    end)

    H.test("WT Deepwood HUD uses native green threshold colors", function()
        local ui = {
            material = "overcharge_bar",
            color_normal = { 255, 180, 195, 182 },
            color_medium = { 255, 0, 255, 165 },
            color_high = { 255, 0, 255, 0 },
        }
        local normal = Policy.hud_style(ui, 0.1, 0.25, 0.8)
        local medium = Policy.hud_style(ui, 0.5, 0.25, 0.8)
        local high = Policy.hud_style(ui, 0.9, 0.25, 0.8)
        H.deep_equal(normal.color, ui.color_normal)
        H.equal(normal.alpha, 0.6)
        H.deep_equal(medium.color, ui.color_medium)
        H.equal(medium.alpha, 0.8)
        H.deep_equal(high.color, ui.color_high)
        H.equal(high.alpha, 1)
        H.equal(high.material, "overcharge_bar")
    end)

    H.test("WT issue 388 runtime is exact Deepwood and owner-local", function()
        H.equal(Policy.is_deepwood_key("we_life_staff"), true)
        H.equal(Policy.is_deepwood_key("we_deus_01"), false)
        H.equal(Policy.is_deepwood_key("bw_skullstaff_fireball"), false)

        local runtime_path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_overcharge_presentation.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('players.local_player', 1, true), "owner-local resolver missing")
        H.truthy(source:find('ScriptUnit.has_extension(player_unit, "overcharge_system")', 1, true),
            "owner overcharge extension not wired")
        H.truthy(source:find('mod:hook_safe(cls, "set_charge_bar_fraction"', 1, true),
            "deferred HUD seam not wired")
        H.truthy(source:find('function M.restore()', 1, true), "reversible baseline restore missing")
    end)
end
