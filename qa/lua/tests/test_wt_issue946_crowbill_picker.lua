return function(Harness, repo_root)
    local path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_dev_anim_picker.lua"
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a")
    f:close()

    Harness.test("WT dev picker exposes the Imperial Crowbill provider clone", function()
        Harness.truthy(source:find("kruber = { cwv_es_imperial_crowbill = true }", 1, true))
        Harness.truthy(source:find('cwv_es_imperial_crowbill  = "C"', 1, true))
        Harness.truthy(source:find('cwv_es_imperial_crowbill  = "cwv_crowbill_pick_template"', 1, true))
    end)

    Harness.test("Imperial Crowbill picker covers the complete source event vocabulary", function()
        local expected = {
            "attack_swing_charge_left",
            "attack_swing_charge_left_pose",
            "attack_swing_charge_right_pose",
            "attack_swing_heavy_left_up",
            "attack_swing_heavy_right",
            "attack_swing_heavy_left_diagonal",
            "attack_swing_stab",
            "attack_swing_right_diagonal",
            "attack_swing_down",
            "attack_swing_left",
            "attack_swing_up_left",
            "attack_push",
            "parry_pose",
        }
        local attacks_at = assert(source:find("local _WEAPON_ATTACKS = {", 1, true))
        local start_at = assert(source:find("cwv_es_imperial_crowbill = {", attacks_at, true))
        local end_at = assert(source:find("\n    },", start_at, true))
        local block = source:sub(start_at, end_at)
        for i = 1, #expected do
            Harness.truthy(block:find('"' .. expected[i] .. '"', 1, true), expected[i])
        end
    end)

    Harness.test("Imperial Crowbill is tool-only and does not alter WT release status", function()
        Harness.truthy(source:find("local _TOOL_ONLY_NEEDS_ANIMS", 1, true))
        Harness.truthy(source:find("if tool_only or _PORT_STATUS.needs_anims", 1, true))
    end)
end
