return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_ba_attack_labeler.lua"
    local AttackLabeler = assert(loadfile(module_path))()

    H.test("melee chains sort and classify production actions", function()
        local result = AttackLabeler.melee_chains({
            actions = {
                action_one = {
                    light_attack_3 = {},
                    heavy_attack = {},
                    push = {},
                    charged_attack_2 = {},
                    light_attack_1 = {},
                    action_wield = {},
                },
            },
        })

        H.deep_equal(result, {
            light = { "light_attack_1", "light_attack_3" },
            heavy = { "charged_attack_2", "heavy_attack" },
            push = "push",
        })
    end)

    H.test("melee chains tolerate absent action data", function()
        H.deep_equal(AttackLabeler.melee_chains(nil), {
            light = {},
            heavy = {},
            push = nil,
        })
    end)

    H.test("ranged chains filter sentinels and use the label ladder", function()
        local previous_localize = _G.Localize
        _G.Localize = function(key)
            local values = {
                item_attack_sniper = "Precision Shot",
            }
            return values[key] or key
        end

        local ok, result = pcall(AttackLabeler.ranged_chains, {
            actions = {
                action_one = {
                    reload = {},
                    sniper = {},
                    default = {},
                    action_wield = {},
                    quick_shot = {},
                },
                action_two = {
                    action_wield = {},
                    weapon_special = {},
                },
            },
        })
        _G.Localize = previous_localize
        H.truthy(ok, result)

        H.deep_equal(result, {
            ranged = {
                { "default", "Ranged Attack 1" },
                { "quick_shot", "Quick Shot" },
                { "sniper", "Precision Shot" },
            },
            alternate = {
                { "weapon_special", "Weapon Special" },
            },
        })
    end)
end
