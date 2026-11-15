-- WP-WT-06: the pure 3P decision (_wt_anim_resolver.lua) without the hook.
-- Each case runs with has_event always true and again always false (the
-- fall-through). The full funnel stays pinned by test_wt_anim_funnel_golden.

return function(H, repo_root)
    local trees = {
        { name = "wt", path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_resolver.lua" },
        { name = "wt_dev", path = repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_anim_resolver.lua" },
    }

    local function yes() return true end
    local function no() return false end

    local function decide(M, event, career, has_event, state)
        return M.decide({
            event = event, career = career, state = state, has_event = has_event,
            template_remaps = {},
            remap_identity = function(template_name, item_key, career_name)
                return tostring(template_name) .. "|" .. tostring(item_key) .. "|" .. tostring(career_name)
            end,
        })
    end

    -- event, career, mode/delivered when authored, mode/delivered when nothing is authored
    local cases = {
        { "to_spear", "wh_captain", "career", "to_2h_billhook", "career_pass", "to_spear" },
        { "to_2h_billhook", "wh_captain", "career_pass", "to_2h_billhook", "career_pass", "to_2h_billhook" },
        { "to_longbow", "es_huntsman", "career", "to_es_longbow", "career_pass", "to_longbow" },
        { "probe_2h_billhook", "es_knight", "suffix", "probe_polearm", "pass", "probe_2h_billhook" },
        { "wt_probe_no_rule", "dr_ranger", "pass", "wt_probe_no_rule", "pass", "wt_probe_no_rule" },
    }

    for _, tree in ipairs(trees) do
        H.test(tree.name .. " resolver is pure and exports its tables", function()
            local file = assert(io.open(tree.path, "rb"))
            local source = file:read("*a")
            file:close()
            for _, banned in ipairs({ "has_animation_event", "get_mod", "Managers" }) do
                H.equal(source:find(banned, 1, true), nil, "resolver mentions " .. banned)
            end
            local M = dofile(tree.path)
            H.equal(type(M.decide), "function")
            H.equal(M.remap_triggers.to_spear.wh_, M.remap_spear_to_billhook, "trigger table identity")
            H.equal(M.remap_triggers.to_polearm._default, M.remap_billhook_to_polearm, "trigger table identity")
        end)

        for _, case in ipairs(cases) do
            local event, career = case[1], case[2]
            H.test(tree.name .. " resolver " .. event .. " for " .. career, function()
                local M = dofile(tree.path)
                local mode, delivered = decide(M, event, career, yes)
                H.equal(mode, case[3], "authored mode")
                H.equal(delivered, case[4], "authored target")
                mode, delivered = decide(M, event, career, no)
                H.equal(mode, case[5], "fall-through mode")
                H.equal(delivered, case[6], "fall-through target")
            end)
        end

        H.test(tree.name .. " resolver career redirect installs the trigger remap on the unit", function()
            local M = dofile(tree.path)
            local state = {}
            local mode = decide(M, "to_spear", "wh_captain", yes, state)
            H.equal(mode, "career")
            H.equal(state.remap, M.remap_spear_to_billhook)
        end)

        H.test(tree.name .. " resolver remap miss reports the lookup and falls through", function()
            local M = dofile(tree.path)
            local state = { remap = M.remap_spear_to_polearm, template = "t", key = "k" }
            local mode, delivered, info = decide(M, "attack_swing_left", "es_knight", no, state)
            H.equal(mode, "pass")
            H.equal(delivered, "attack_swing_left")
            H.equal(info.remap_miss, true)
            H.equal(info.remap_target, "attack_swing_down_left")
            H.equal(info.remap_target_capability, false)
            mode, delivered, info = decide(M, "attack_swing_left", "es_knight", yes, state)
            H.equal(mode, "remap")
            H.equal(delivered, "attack_swing_down_left")
            H.equal(info.remap_miss, nil)
        end)
    end
end
