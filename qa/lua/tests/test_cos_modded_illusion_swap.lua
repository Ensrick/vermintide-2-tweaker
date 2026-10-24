return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua"
    local Swap = dofile(path)
    local Authority = dofile(repo_root
        .. "/tools/shared_lib/_lib_modded_realm_authority.lua")
    local Presentation = dofile(repo_root .. "/tools/shared_lib/_lib_local_illusion_apply.lua")

    local function fixture(options)
        options = options or {}
        local globals = options.env or _G
        local swap = Swap
        if options.env then
            local chunk = assert(loadfile(path))
            setfenv(chunk, options.env)
            swap = chunk()
        end
        local registrations = {}
        local installed_mods = {}
        local apply_commits = {}
        local glow_refreshes = {}
        local lookup_errors = {}
        local checks = {}
        local actions = options.actions or { default = {}, item_setting = { {
            input_action = "refresh", description_text = "crafting_recipe_apply_weapon_skin",
        } } }
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
        local owner = swap.install(mod, {
            presentation = Presentation,
            register_check = function(name, fn) checks[name] = fn end,
            is_modded_realm = function()
                return Authority.is_modded(rawget(globals, "script_data"), 0,
                    rawget(globals, "Development"), globals)
            end,
            get_generic_input_actions = function() return actions end,
            get_mod = function(name)
                if lookup_errors[name] then error("lookup-error:" .. name) end
                return installed_mods[name]
            end,
            with_eac_off = function(func, self, ...)
                return Authority.with_eac_off(
                    script_data, nil, func, self, nil, ...)
            end,
            skin_requires_unowned_dlc = function(key)
                if options.dlc_throws then error("dlc-reader-unavailable") end
                return options.denied and options.denied[key] == true or false
            end,
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
            glow_refreshes, lookup_errors, checks
    end

    local function modern_case(options)
        options = options or {}
        local state = { original_crafts = 0, dirtified = 0 }
        state.actions = { default = {}, item_setting = { {
            input_action = "refresh", description_text = "crafting_recipe_apply_weapon_skin",
        } } }
        local env = setmetatable({
            MODDED_REALM = true, script_data = {}, printf = function() end,
            GameSettingsDevelopment = { read_only_backend = true },
            ItemMasterList = { native_skin = { rarity = "exotic" } },
            WeaponSkins = { skins = { native_skin = {}, skin_old = {} },
                default_skins = { weapon = "skin_old" } },
        }, { __index = _G })
        env._G = env
        state.env = env
        state.weapon = { key = "weapon", skin = "skin_old", data = { slot_type = "melee" },
            CustomData = { skin = "skin_old" } }
        state.mirror = { _inventory_items = { weapon_bid = state.weapon } }
        local hooks
        local items = {
            get_item_from_id = function(_, id)
                if id == "weapon_bid" then return state.weapon end
                if id == "skin_bid" then return { key = "native_skin", data = { slot_type = "weapon_skin" } } end
            end,
            get_all_fake_backend_items = function() return {} end,
            get_weapon_skin_from_skin_key = function(self, key)
                return hooks[1].callback(function() return nil end, self, key)
            end,
        }
        env.Managers = { backend = {
            get_interface = function(_, name) H.equal(name, "items"); return items end,
            dirtify_interfaces = function() state.dirtified = state.dirtified + 1 end,
        } }
        state.mod, state.owner, hooks, state.installed, _, _, _, state.checks = fixture({
            env = env, actions = state.actions, denied = options.denied, dlc_throws = options.dlc_throws,
        })
        state.hooks, state.items = hooks, items
        local function widget() return { content = { visible = false } } end
        local widgets = { craft_button = { content = { visible = false,
            button_hotspot = { disable_button = true } } } }
        for _, name in ipairs({ "button_top_edge_left", "button_top_edge_right", "button_top_edge_glow",
            "experience_bar", "experience_bar_edge" }) do widgets[name] = widget() end
        local window = {
            _state = "item_setting", _current_recipe_name = "apply_weapon_skin",
            _item_backend_id = "weapon_bid", _material_items = {},
            _illusion_widgets = { { content = { skin_key = "native_skin", locked = true } } },
            _widgets_by_name = widgets, _get_item = function() return state.weapon end,
            _menu_input_description = { generic_actions = state.actions.default,
                change_generic_actions = function(self, actions) self.generic_actions = actions end },
        }
        window._enable_craft_button = function(self, enabled, edges)
            return hooks[2].callback(function(view, requested)
                if env.GameSettingsDevelopment.read_only_backend then requested = false end
                for _, row in pairs(view._widgets_by_name) do row.content.visible = requested end
                view._widgets_by_name.craft_button.content.button_hotspot.disable_button = not requested
                view._menu_input_description:change_generic_actions(
                    state.actions[requested and "item_setting" or "default"])
                return "enable", nil, "tail"
            end, self, enabled, edges)
        end
        state.window = window
        state.press = function()
            return hooks[3].callback(function(view, index)
                local content = view._illusion_widgets[index].content
                view._skin_dirty = false
                view._material_items = {}
                if not content.locked then
                    view._material_items[1] = items:get_weapon_skin_from_skin_key(content.skin_key)
                    view:_enable_craft_button(true, true)
                    view._skin_dirty = true
                end
                return "pressed", nil, "tail"
            end, window, 1, false, false)
        end
        state.new_ids = 72
        state.crafting = { _backend_mirror = state.mirror, _craft_requests = {},
            _new_id = function() state.new_ids = state.new_ids + 1; return state.new_ids end }
        state.craft = function(ids, recipe)
            return hooks[5].callback(function()
                state.original_crafts = state.original_crafts + 1
                return "native", { name = recipe }
            end, state.crafting, "mercenary", ids, recipe)
        end
        return state
    end

    H.test("Cosmetics #1690 installed modern callbacks restore Apply and complete one local transaction", function()
        local s = modern_case()
        local a, b, c = s.press()
        H.equal(a, "pressed"); H.equal(b, nil); H.equal(c, "tail")
        H.equal(s.window._widgets_by_name.craft_button.content.visible, true)
        H.equal(s.window._menu_input_description.generic_actions, s.actions.item_setting)
        local id = s.craft({ "weapon_bid", s.window._material_items[1] }, "apply_weapon_skin")
        H.equal(id, 73)
        H.equal(s.original_crafts, 0)
        H.equal(s.weapon.skin, "native_skin")
        H.equal(s.weapon.CustomData.skin, "native_skin")
        s.hooks[6].callback(s.crafting, 0)
        s.hooks[6].callback(s.crafting, 0)
        H.equal(s.dirtified, 1)
        H.truthy(s.crafting._craft_requests[73])
        s.hooks[8].callback(s.window, {})
        H.equal(s.window._cim1465_apply_owned, false)
        H.equal(s.window._menu_input_description.generic_actions, s.actions.default)
        H.equal(s.env.MODDED_REALM, true)
        H.equal(s.env.GameSettingsDevelopment.read_only_backend, true)
        H.equal(s.checks.issue1690_local_illusion_apply_surface(), nil)
    end)

    H.test("Cosmetics #1690 existing state-writer callback reasserts the owned selection", function()
        local s = modern_case()
        s.press()
        local a, b, c = s.hooks[4].callback(function(view)
            view._widgets_by_name.craft_button.content.button_hotspot.disable_button = true
            return "state", nil, "tail"
        end, s.window, "apply_weapon_skin")
        H.equal(a, "state"); H.equal(b, nil); H.equal(c, "tail")
        H.equal(s.window._widgets_by_name.craft_button.content.button_hotspot.disable_button, false)
        H.equal(s.window._menu_input_description.generic_actions, s.actions.item_setting)
    end)

    H.test("Cosmetics local Apply denies DLC and missing mirror ownership without backend fallback", function()
        local denied = modern_case({ denied = { native_skin = true } })
        H.equal(denied.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(denied.original_crafts, 0)
        H.equal(denied.weapon.skin, "skin_old")
        local absent = modern_case()
        absent.crafting._backend_mirror = nil
        H.equal(absent.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(absent.original_crafts, 0)
    end)

    H.test("Cosmetics local Apply leaves explicit unrelated recipes native", function()
        local s = modern_case()
        H.equal(s.craft({ "weapon_bid", "skin_bid" }, "reroll_properties"), "native")
        H.equal(s.original_crafts, 1)
        H.equal(s.weapon.skin, "skin_old")
    end)

    H.test("Cosmetics local Apply rejects request allocation failure before changing the item", function()
        local s = modern_case()
        s.crafting._new_id = function() error("request-id-unavailable") end
        H.equal(s.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(s.new_ids, 72)
        H.equal(s.weapon.skin, "skin_old")
        H.equal(s.weapon.CustomData.skin, "skin_old")
        H.equal(s.weapon.bypass_skin_ownership_check, nil)
        H.equal(s.original_crafts, 0)
    end)

    H.test("Cosmetics local Apply has at most one pending request and contains late teardown", function()
        local s = modern_case()
        H.equal(s.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), 73)
        H.equal(s.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(s.new_ids, 73)
        s.crafting._craft_requests = nil
        s.hooks[6].callback(s.crafting, 0)
        H.equal(s.original_crafts, 0)
        H.equal(s.dirtified, 0)
    end)

    H.test("Cosmetics local Apply contains unavailable material and DLC readers", function()
        local s = modern_case()
        s.items.get_item_from_id = function() error("item-reader-unavailable") end
        H.equal(s.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(s.weapon.skin, "skin_old")
        H.equal(s.original_crafts, 0)
        local dlc = modern_case({ dlc_throws = true })
        H.equal(dlc.craft({ "weapon_bid", "skin_bid" }, "apply_weapon_skin"), nil)
        H.equal(dlc.original_crafts, 0)
        H.equal(dlc.weapon.skin, "skin_old")
    end)

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
