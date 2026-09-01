return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua"
    local Swap = dofile(path)

    local function fixture()
        local registrations = {}
        local installed_mods = {}
        local apply_commits = {}
        local mod = {
            hook = function(_, class, method, callback)
                registrations[#registrations + 1] = {
                    kind = "hook", class = class, method = method, callback = callback,
                }
            end,
            hook_safe = function(_, class, method, callback)
                registrations[#registrations + 1] = {
                    kind = "hook_safe", class = class, method = method, callback = callback,
                }
            end,
            get = function() return false end,
            info = function() end,
            echo = function() end,
        }
        local owner = Swap.install(mod, {
            get_mod = function(name) return installed_mods[name] end,
            skin_requires_unowned_dlc = function() return false end,
            custom_skin_keys = { ct_test_skin = true },
            glow_picker = {
                is_open = function() return false end,
                is_open_for = function() return false end,
                close = function() end,
            },
            refresh_glow_editor_button = function() end,
            offhand_commit = {
                commit_for_backend = function(pending, persistence, backend_id)
                    apply_commits[#apply_commits + 1] = {
                        pending = pending,
                        persistence = persistence,
                        backend_id = backend_id,
                    }
                    return 1
                end,
            },
            la_persist = { identity = "exact-persistence-owner" },
            debug = function() end,
            trace = function() end,
        })
        return mod, owner, registrations, installed_mods, apply_commits
    end

    H.test("Cosmetics #504 illusion owner registers its exact hook surface once", function()
        local mod, owner, hooks = fixture()
        H.equal(owner.hook_count, 8)
        local expected = {
            { "hook", "BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key" },
            { "hook", "HeroWindowItemCustomization", "_enable_craft_button" },
            { "hook", "HeroWindowItemCustomization", "_on_illusion_index_pressed" },
            { "hook", "HeroWindowItemCustomization", "_update_state_craft_button" },
            { "hook", "BackendInterfaceCraftingPlayfab", "craft" },
            { "hook_safe", "BackendInterfaceCraftingPlayfab", "update" },
            { "hook", "HeroWindowItemCustomization", "_upgrade_item_craft_complete" },
            { "hook_safe", "HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete" },
        }
        H.equal(#hooks, #expected)
        for index, contract in ipairs(expected) do
            H.equal(hooks[index].kind, contract[1])
            H.equal(hooks[index].class, contract[2])
            H.equal(hooks[index].method, contract[3])
        end

        local again = Swap.install(mod, {})
        H.equal(again, owner)
        H.equal(#hooks, #expected)
    end)

    H.test("Cosmetics #504 illusion lookup safely synthesizes custom skin identity", function()
        local _, _, hooks, installed_mods = fixture()
        local old_iml, old_script = ItemMasterList, script_data
        ItemMasterList = { ct_test_skin = { rarity = "unique" } }
        script_data = { ["eac-untrusted"] = true }

        local original_calls = 0
        local callback = hooks[1].callback
        local id, item = callback(function()
            original_calls = original_calls + 1
            return nil
        end, {}, "ct_test_skin")
        H.equal(original_calls, 1)
        H.equal(id, "ct_fake_ct_test_skin")
        H.equal(item.skin, "ct_test_skin")
        H.equal(item.rarity, "unique")

        installed_mods.cim = {}
        H.equal(select(1, callback(function() return nil end, {}, "vanilla_unknown")), nil)

        ItemMasterList, script_data = old_iml, old_script
    end)

    H.test("Cosmetics #1465 yields to exact stable or Dev CIM capability providers", function()
        local _, owner, _, installed_mods = fixture()
        H.equal(owner.owns_illusion_swap(), false)

        installed_mods.cim = {
            _cim_illusion_swap_provider = {
                schema = 1,
                owns_illusion_swap = function() return true end,
            },
        }
        H.equal(owner.owns_illusion_swap(), true)

        installed_mods.cim = nil
        installed_mods.cim_dev = {
            _cim_illusion_swap_provider = {
                schema = 1,
                owns_illusion_swap = function() return true end,
            },
        }
        H.equal(owner.owns_illusion_swap(), true)

        installed_mods.cim_dev._cim_illusion_swap_provider.schema = 2
        H.equal(owner.owns_illusion_swap(), false)
        installed_mods.cim_dev._cim_illusion_swap_provider.schema = 1
        installed_mods.cim_dev._cim_illusion_swap_provider.owns_illusion_swap = function()
            error("hostile-provider")
        end
        H.equal(owner.owns_illusion_swap(), false)
    end)

    H.test("Cosmetics #702 Apply completion commits the exact pending offhand", function()
        local mod, _, hooks, _, commits = fixture()
        mod._pending_la_emit_on_exit = {
            ["item_a|left_hand_unit"] = {
                backend_id = "item_a",
                hand_field = "left_hand_unit",
            },
        }
        hooks[8].callback({ _item_backend_id = "item_a" }, { ok = true })
        H.equal(#commits, 1)
        H.equal(commits[1].pending, mod._pending_la_emit_on_exit)
        H.equal(commits[1].persistence.identity, "exact-persistence-owner")
        H.equal(commits[1].backend_id, "item_a")
        H.equal(mod._offhand_committed.item_a, true)
    end)
end
