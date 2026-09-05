return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua"
    local Swap = dofile(path)
    local Authority = dofile(repo_root
        .. "/tools/shared_lib/_lib_modded_realm_authority.lua")

    local function fixture()
        local registrations = {}
        local installed_mods = {}
        local apply_commits = {}
        local glow_refreshes = {}
        local lookup_errors = {}
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
            get_mod = function(name)
                if lookup_errors[name] then error("lookup-error:" .. name) end
                return installed_mods[name]
            end,
            with_eac_off = function(func, self, ...)
                return Authority.with_eac_off(
                    script_data, nil, func, self, nil, ...)
            end,
            skin_requires_unowned_dlc = function() return false end,
            custom_skin_keys = { ct_test_skin = true },
            glow_picker = {
                is_open = function() return false end,
                is_open_for = function() return false end,
                close = function() end,
            },
            refresh_glow_editor_button = function(window, skin_key)
                glow_refreshes[#glow_refreshes + 1] = {
                    window = window,
                    skin_key = skin_key,
                }
            end,
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
        return mod, owner, registrations, installed_mods, apply_commits,
            glow_refreshes, lookup_errors
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

    H.test("Cosmetics #434 fallback bracket restores after throws and preserves nil holes", function()
        local _, _, hooks = fixture()
        local old_script = script_data
        rawset(_G, "script_data", { ["eac-untrusted"] = true })
        local window = {
            _current_recipe_name = "apply_weapon_skin",
            _widgets_by_name = { craft_button = { content = {
                button_hotspot = { is_held = true, input_pressed = true },
            } } },
        }

        local a, b, c = hooks[2].callback(function()
            H.equal(script_data["eac-untrusted"], nil)
            return "enable", nil, "tail"
        end, window, true, true)
        H.equal(a, "enable")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(script_data["eac-untrusted"], true)

        local ok, err = pcall(hooks[2].callback, function()
            H.equal(script_data["eac-untrusted"], nil)
            error("enable-bracket-boom")
        end, window, true, true)
        H.equal(ok, false)
        H.truthy(tostring(err):find("enable-bracket-boom", 1, true) ~= nil)
        H.equal(script_data["eac-untrusted"], true)

        a, b, c = hooks[4].callback(function(_, recipe, marker)
            H.equal(script_data["eac-untrusted"], nil)
            return recipe, nil, marker
        end, window, "apply_weapon_skin", "state-tail")
        H.equal(a, "apply_weapon_skin")
        H.equal(b, nil)
        H.equal(c, "state-tail")
        H.equal(script_data["eac-untrusted"], true)

        ok, err = pcall(hooks[4].callback, function()
            H.equal(script_data["eac-untrusted"], nil)
            error("state-bracket-boom")
        end, window, "apply_weapon_skin")
        H.equal(ok, false)
        H.truthy(tostring(err):find("state-bracket-boom", 1, true) ~= nil)
        H.equal(script_data["eac-untrusted"], true)
        rawset(_G, "script_data", old_script)
    end)

    H.test("Cosmetics #1465 legacy public CIM delegates every competing seam", function()
        local _, owner, hooks, installed_mods, _, glow_refreshes = fixture()
        installed_mods.cim = {}
        H.equal(owner.owns_illusion_swap(), true)

        local window = {
            _item_backend_id = "weapon-bid",
            _illusion_widgets = {
                { content = { skin_key = "skin_b", locked = true } },
            },
        }
        local calls = {}
        local a, b, c = hooks[2].callback(function(self, enable, disable_edges)
            calls.enable = { self, enable, disable_edges }
            return "enable", nil, "tail"
        end, window, true, true)
        H.equal(a, "enable")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(calls.enable[1], window)
        H.equal(calls.enable[2], true)
        H.equal(calls.enable[3], true)

        a, b, c = hooks[3].callback(function(self, index, ignore_item_spawn,
                mark_as_equipped)
            calls.pressed = { self, index, ignore_item_spawn, mark_as_equipped }
            return "pressed", nil, "tail"
        end, window, 1, false, false)
        H.equal(a, "pressed")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(calls.pressed[1], window)
        H.equal(calls.pressed[2], 1)
        H.equal(#glow_refreshes, 1)
        H.equal(glow_refreshes[1].window, window)
        H.equal(glow_refreshes[1].skin_key, "skin_b")
        H.equal(window._illusion_widgets[1].content.locked, true)

        a, b, c = hooks[4].callback(function(self, recipe_name, marker)
            calls.update_state = { self, recipe_name, marker }
            return "state", nil, "tail"
        end, window, "apply_weapon_skin", "marker")
        H.equal(a, "state")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(calls.update_state[2], "apply_weapon_skin")
        H.equal(calls.update_state[3], "marker")

        local result, recipe = hooks[5].callback(function(self, career_name,
                item_backend_ids, recipe_override)
            calls.craft = { self, career_name, item_backend_ids, recipe_override }
            return "request-id", { name = "apply_weapon_skin" }
        end, {}, "witch_hunter", { "weapon", "skin" }, "apply_weapon_skin")
        H.equal(result, "request-id")
        H.equal(recipe.name, "apply_weapon_skin")
        H.equal(calls.craft[2], "witch_hunter")
        H.equal(calls.craft[4], "apply_weapon_skin")

        -- Cosmetics still owns its non-competing completion observers (#48,
        -- #200, #702) even while public CIM owns selection and crafting.
        H.equal(hooks[8].method, "_apply_weapon_skin_craft_complete")
    end)

    H.test("Cosmetics #1465 requires an explicit CIM Dev capability", function()
        local _, owner, _, installed_mods, _, _, lookup_errors = fixture()
        H.equal(owner.owns_illusion_swap(), false)

        installed_mods.cim_dev = {
            _cim_illusion_swap_provider = {
                schema = 1,
                owns_illusion_swap = function() return true end,
            },
        }
        H.equal(owner.owns_illusion_swap(), true)
        lookup_errors.cim = true
        H.equal(owner.owns_illusion_swap(), true)
        lookup_errors.cim = nil

        installed_mods.cim_dev._cim_illusion_swap_provider.schema = 2
        H.equal(owner.owns_illusion_swap(), false)
        installed_mods.cim_dev._cim_illusion_swap_provider.schema = 1
        installed_mods.cim_dev._cim_illusion_swap_provider.owns_illusion_swap =
            function() return false end
        H.equal(owner.owns_illusion_swap(), false)
        installed_mods.cim_dev._cim_illusion_swap_provider.owns_illusion_swap = function()
            error("hostile-provider")
        end
        H.equal(owner.owns_illusion_swap(), false)
        lookup_errors.cim_dev = true
        H.equal(owner.owns_illusion_swap(), false)
        lookup_errors.cim_dev = nil

        -- The public compatibility rule is intentionally presence-based: the
        -- deployed 0.8.92 stream has no provider and must retain ownership.
        installed_mods.cim = { _cim_illusion_swap_provider = "malformed" }
        H.equal(owner.owns_illusion_swap(), true)
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
