return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local build = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua")
    local remaps = build({}, {}, {})
    local saltz = assert(remaps.one_hand_axe_shield_template_1.wh_)

    H.test("WT #576 Axe+Shield maps every Saltz heavy charge and release as a chain", function()
        local expected = {
            { "attack_swing_charge", "attack_swing_charge_down" },
            { "attack_swing_heavy", "attack_swing_heavy_down" },
            { "attack_swing_charge_right_pose", "attack_swing_charge_left" },
            { "attack_swing_heavy_right", "attack_swing_heavy_left" },
            { "attack_swing_charge_left_diagonal_pose", "attack_swing_charge_down" },
            { "attack_swing_heavy_down", "attack_swing_heavy_down" },
        }
        for _, pair in ipairs(expected) do
            H.equal(saltz[pair[1]], pair[2], pair[1] .. " must reach " .. pair[2])
        end
    end)

    H.test("WT #576 Axe+Shield diagnostics distinguish H3 wind-up from release", function()
        local source = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua")
        for _, key in ipairs({ "dr_shield_axe", "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" }) do
            H.truthy(source:find(key .. " = true", 1, true), key .. " must be diagnostic-armed")
        end
        H.truthy(source:find('attack_swing_charge_left_diagonal_pose = "action_one.h3_charge"', 1, true))
        H.truthy(source:find('attack_swing_heavy_down = "action_one.h3_committed_attack"', 1, true))
        H.truthy(source:find("accepted_unverified_no_observable_state_transition", 1, true))
    end)
end
