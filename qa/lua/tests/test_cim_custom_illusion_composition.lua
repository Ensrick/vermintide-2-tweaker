return function(H, repo_root)
    local CosmeticsSwap = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua")

    local function with_globals(body)
        local names = {
            "get_mod", "printf", "script_data", "ItemMasterList",
            "WeaponSkins", "Managers",
        }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        local ok, result = pcall(body)
        for _, name in ipairs(names) do rawset(_G, name, saved[name]) end
        if not ok then error(result, 0) end
        return result
    end

    local function production_case(cim_outermost, modded, public_cim)
        return with_globals(function()
            local function key(class, method)
                return class .. "." .. method
            end

            local cim_hooks, cosmetics_hooks = {}, {}
            local settings = {}
            local setting_writes = 0
            local cim = {
                _cim_is_modded_realm = function() return modded end,
                _cim_with_eac_off = function(func, self, ...)
                    return func(self, ...)
                end,
                _cim_rt_register = function() end,
                _cim_is_modded_backend_id = function() return false end,
                hook = function(_, class, method, callback)
                    cim_hooks[key(class, method)] = callback
                end,
                hook_safe = function(_, class, method, callback)
                    cim_hooks[key(class, method)] = callback
                end,
                command = function() end,
                info = function() end,
                warning = function() end,
                echo = function() end,
                get = function(_, name) return settings[name] end,
                set = function(_, name, value)
                    setting_writes = setting_writes + 1
                    settings[name] = value
                end,
            }
            local cim_dir = public_cim and "crafting_in_modded"
                or "crafting_in_modded_dev"
            function cim:dofile(path)
                return dofile(repo_root .. "/" .. cim_dir .. "/" .. path .. ".lua")
            end

            local mods = { [public_cim and "cim" or "cim_dev"] = cim }
            rawset(_G, "get_mod", function(name) return mods[name] end)
            rawset(_G, "printf", function() end)
            rawset(_G, "script_data", { ["eac-untrusted"] = modded })

            local custom_skin = "ct_test_custom_skin"
            rawset(_G, "ItemMasterList", {
                [custom_skin] = { slot_type = "weapon_skin", rarity = "exotic" },
            })
            rawset(_G, "WeaponSkins", {
                skins = { [custom_skin] = {} },
                default_skins = {},
            })

            local weapon = {
                key = "weapon", ItemId = "weapon",
                skin = "base_skin", CustomData = {},
                data = { slot_type = "melee" },
            }
            local items = {}
            function items:get_item_from_id(backend_id)
                if backend_id == "weapon-bid" then return weapon end
            end
            function items:get_all_fake_backend_items() return {} end
            local backend = {}
            function backend:get_interface(name)
                if name == "items" then return items end
            end
            function backend:dirtify_interfaces() end
            rawset(_G, "Managers", {
                backend = backend,
                unlock = { is_dlc_unlocked = function() return true end },
            })

            dofile(repo_root .. "/" .. cim_dir .. "/scripts/mods/" .. cim_dir
                .. "/illusion_swap.lua")

            local cosmetics = {
                hook = function(_, class, method, callback)
                    cosmetics_hooks[key(class, method)] = callback
                end,
                hook_safe = function(_, class, method, callback)
                    cosmetics_hooks[key(class, method)] = callback
                end,
                get = function() return false end,
                info = function() end,
                echo = function() end,
            }
            CosmeticsSwap.install(cosmetics, {
                get_mod = get_mod,
                with_eac_off = function(func, self, ...)
                    return func(self, ...)
                end,
                skin_requires_unowned_dlc = function() return false end,
                custom_skin_keys = { [custom_skin] = true },
                glow_picker = {
                    is_open = function() return false end,
                    is_open_for = function() return false end,
                    close = function() end,
                },
                refresh_glow_editor_button = function() end,
                offhand_commit = { commit_for_backend = function() end },
                la_persist = {},
                debug = function() end,
                trace = function() end,
            })

            local lookup_key = key(
                "BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key")
            local function wrap(callback, downstream)
                return function(self, ...)
                    return callback(downstream, self, ...)
                end
            end
            local vanilla_lookup = function() return nil, nil end
            if cim_outermost then
                items.get_weapon_skin_from_skin_key = wrap(
                    cim_hooks[lookup_key], wrap(cosmetics_hooks[lookup_key], vanilla_lookup))
            else
                items.get_weapon_skin_from_skin_key = wrap(
                    cosmetics_hooks[lookup_key], wrap(cim_hooks[lookup_key], vanilla_lookup))
            end

            local skin_backend_id = items:get_weapon_skin_from_skin_key(custom_skin)
            local facts = {
                skin_backend_id = skin_backend_id,
                settings = settings,
                setting_writes = function() return setting_writes end,
                weapon = weapon,
            }
            if not modded then return facts end

            local crafting = {
                _backend_mirror = { _inventory_items = {
                    ["weapon-bid"] = weapon,
                } },
                _new_id = function() return "craft-id" end,
            }
            local craft_key = key("BackendInterfaceCraftingPlayfab", "craft")
            local cim_craft_calls = 0
            facts.craft_id, facts.recipe = cosmetics_hooks[craft_key](
                function(self, career_name, item_backend_ids, recipe_override)
                    cim_craft_calls = cim_craft_calls + 1
                    return cim._cim_try_illusion_apply(
                        self, career_name, item_backend_ids, recipe_override)
                end,
                crafting, "witch_hunter", { "weapon-bid", skin_backend_id },
                "apply_weapon_skin")
            facts.cim_craft_calls = cim_craft_calls
            return facts
        end)
    end

    H.test("CIM Dev owns Cosmetics custom fake identity in both hook orders", function()
        for _, cim_outermost in ipairs({ false, true }) do
            local result = production_case(cim_outermost, true)
            H.equal(result.skin_backend_id, "cim_fake_ct_test_custom_skin")
            H.equal(result.skin_backend_id:find("^ct_fake_"), nil)
            H.equal(result.cim_craft_calls, 1)
            H.equal(result.craft_id, "craft-id")
            H.equal(result.recipe.name, "apply_weapon_skin")
            H.equal(result.weapon.skin, "ct_test_custom_skin")
            H.equal(result.weapon.CustomData.skin, "ct_test_custom_skin")
            H.equal(result.weapon.bypass_skin_ownership_check, true)
            H.equal(result.setting_writes(), 1)
            H.equal(result.settings.vanilla_skin_overrides_by_backend_id["weapon-bid"],
                "ct_test_custom_skin")
        end
    end)

    H.test("legacy public CIM retains custom fake ownership in both hook orders", function()
        for _, cim_outermost in ipairs({ false, true }) do
            local result = production_case(cim_outermost, true, true)
            H.equal(result.skin_backend_id, "cim_fake_ct_test_custom_skin")
            H.equal(result.skin_backend_id:find("^ct_fake_"), nil)
            H.equal(result.cim_craft_calls, 1)
            H.equal(result.craft_id, "craft-id")
            H.equal(result.recipe.name, "apply_weapon_skin")
            H.equal(result.weapon.skin, "ct_test_custom_skin")
            H.equal(result.settings.vanilla_skin_overrides_by_backend_id["weapon-bid"],
                "ct_test_custom_skin")
        end
    end)

    H.test("composed custom lookup stays fail-closed in official realm", function()
        for _, cim_outermost in ipairs({ false, true }) do
            local result = production_case(cim_outermost, false)
            H.equal(result.skin_backend_id, nil)
            H.equal(result.setting_writes(), 0)
            H.equal(result.weapon.skin, "base_skin")
        end
    end)
end
