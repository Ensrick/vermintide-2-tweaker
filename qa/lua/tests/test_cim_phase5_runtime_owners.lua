return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    H.test("CIM bootstrap owns one regression registry and raw settings dump", function()
        local commands, infos, echoes, printed = {}, {}, {}, {}
        local mod = { settings = { alpha = true, beta = 3 } }
        function mod:warning() end
        function mod:info(fmt, ...)
            infos[#infos + 1] = string.format(fmt, ...)
        end
        function mod:echo(fmt, ...)
            echoes[#echoes + 1] = string.format(fmt, ...)
        end
        function mod:get(key) return self.settings[key] end
        function mod:command(name, _, fn) commands[name] = fn end
        function mod:dofile(path)
            if path:find("_lib_debug", 1, true) then
                return function()
                    return function() end, function() end
                end
            end
            return { options = { type = "group", sub_widgets = {
                { setting_id = "alpha", type = "checkbox" },
                { setting_id = "beta", type = "numeric" },
            } } }
        end

        local install = assert(loadfile(root .. "_cim_bootstrap_runtime.lua"))()
        local owner = install({
            mod = mod,
            version = "0.8.121-dev",
            print_line = function(fmt, ...)
                printed[#printed + 1] = string.format(fmt, ...)
            end,
        })
        H.equal(owner.rpc_schema, 1)
        H.equal(type(owner.rt_register), "function")
        H.equal(type(owner.rt_src_read), "function")
        H.equal(type(commands.cim_dump_settings), "function")
        H.equal(type(commands.cim_regression_test), "function")
        H.truthy(printed[1]:find("phase=load", 1, true))
        H.truthy(printed[2]:find("alpha get=1", 1, true))
        H.truthy(printed[3]:find("beta get=3", 1, true))

        local ran = 0
        owner.rt_register("planted", function() ran = ran + 1 end)
        commands.cim_regression_test()
        H.equal(ran, 1)
        mod:warning("(hook_safe): Attempting to rehook active hook [x].")
        H.equal(#owner.rehook_warnings, 1)
        H.truthy(infos[1]:find("0.8.121%-dev"))
        H.truthy(echoes[1]:find("0.8.121%-dev"))
    end)

    H.test("CIM forge state owner preserves reload identity and backend order", function()
        local saved = {
            old = {
                item_key = "es_1h_sword", slot_type = "melee",
                rarity = "promo", properties = {}, traits = {},
            },
        }
        local hooks, checks = {}, {}
        local athanor_calls, restore_calls = 0, 0
        local mod = {
            _cim_external_trait_policy = {
                merge_traits = function(active) return active or {} end,
                partition = function(combined) return combined, {} end,
                REQUIRED_CAPABILITY_BY_PROVIDER = {},
                RESERVED_PROVIDER_BY_TRAIT = {},
            },
            _cim_synthetic_item_contract = {
                SCHEMA_VERSION = 1,
                OWNER = "cim",
                gate_record = function(_, backend_id, input)
                    local record = {}
                    for key, value in pairs(input or {}) do record[key] = value end
                    record.schema_version = 1
                    record.owner = "cim"
                    record.backend_id = backend_id
                    return record
                end,
            },
            settings = { forged_weapons = saved },
            infos = {},
        }
        local set_calls, fail_set = 0, false
        function mod:get(key) return self.settings[key] end
        function mod:set(key, value)
            set_calls = set_calls + 1
            if fail_set then error("forced settings failure") end
            self.settings[key] = value
        end
        function mod:info(fmt, ...)
            self.infos[#self.infos + 1] = string.format(fmt, ...)
        end
        function mod:echo() end
        function mod:hook_safe(_, method, fn) hooks[method] = fn end
        function mod:dofile(path)
            if path:find("_cim_custom_glow_notice", 1, true) then
                return { new = function()
                    return { observe = function() return 0, false end }
                end }
            end
            if path:find("_cim_mil_entry_builder", 1, true) then
                return function(weapon, backend_id)
                    return { backend_id = backend_id, key = weapon.item_key }
                end
            end
            error("unexpected dofile: " .. path)
        end

        local install = assert(loadfile(root .. "_cim_forge_state_owner.lua"))()
        local owner = install({
            mod = mod,
            rt_register = function(name, fn) checks[name] = fn end,
            print_line = function() end,
            get_mod = function() return nil end,
            get_managers = function() return {} end,
            get_item_master_list = function() return {} end,
            get_weapon_traits = function() return nil end,
            get_cjson = function() return nil end,
            get_item_helper = function() return nil end,
            get_athanor_inject_all = function()
                return function() athanor_calls = athanor_calls + 1 end
            end,
            get_restore_modded_loadout = function()
                return function() restore_calls = restore_calls + 1 end
            end,
        })

        H.equal(owner.get_forged_weapons().old.rarity, "modded")
        H.equal(mod.settings.forged_weapons.old.rarity, "modded")
        H.equal(type(checks.issue628_saved_instance_contract), "function")
        H.equal(type(hooks._create_interfaces), "function")

        local replacement = { fresh = {
            item_key = "dr_1h_hammer", schema_version = 1,
            owner = "cim", backend_id = "fresh",
        } }
        owner.set_forged_weapons(replacement)
        H.equal(owner.get_forged_weapons(), replacement)
        mod._cim_persist_crafts()
        H.equal(mod.settings.forged_weapons.fresh.item_key, "dr_1h_hammer")
        hooks._create_interfaces()
        H.equal(athanor_calls, 1)
        H.equal(restore_calls, 1)

        -- #1141 single Temper-Craft registration uses the same candidate-state
        -- persistence boundary as batch import: no ghost is published when the
        -- settings write throws, and an existing exact ID is never replaced.
        set_calls = 0
        local single_ok = mod._cim_register_craft("temper-one", {
            item_key = "es_1h_sword", slot_type = "melee",
        })
        H.equal(single_ok, true)
        H.equal(set_calls, 1)
        H.equal(owner.get_forged_weapons()["temper-one"].item_key,
            "es_1h_sword")
        single_ok = mod._cim_register_craft("temper-one", {
            item_key = "es_handgun", slot_type = "ranged",
        })
        H.equal(single_ok, false)
        H.equal(owner.get_forged_weapons()["temper-one"].item_key,
            "es_1h_sword")

        fail_set = true
        local failed_single, failed_reason = mod._cim_register_craft(
            "temper-rejected", {
                item_key = "es_1h_sword", slot_type = "melee",
            })
        H.equal(failed_single, false)
        H.truthy(failed_reason:find("save:", 1, true))
        H.equal(owner.get_forged_weapons()["temper-rejected"], nil)
        H.equal(mod.settings.forged_weapons["temper-rejected"], nil)
        fail_set = false

        -- #1360's five-item import uses one candidate-state persistence
        -- boundary. A rejected settings write must publish neither a partial
        -- in-memory registry nor a partial persisted registry.
        set_calls = 0
        local registered, normalized = mod._cim_register_crafts_batch({
            build_melee = { item_key = "es_1h_sword", slot_type = "melee" },
            build_ranged = { item_key = "es_handgun", slot_type = "ranged" },
        })
        H.equal(registered, true)
        H.equal(type(normalized.build_melee), "table")
        H.equal(set_calls, 1)
        H.equal(owner.get_forged_weapons().build_melee.item_key, "es_1h_sword")
        H.equal(mod.settings.forged_weapons.build_ranged.item_key, "es_handgun")

        fail_set = true
        registered, normalized = mod._cim_register_crafts_batch({
            rejected_a = { item_key = "es_1h_sword", slot_type = "melee" },
            rejected_b = { item_key = "es_handgun", slot_type = "ranged" },
        })
        H.equal(registered, false)
        H.truthy(normalized:find("save:", 1, true))
        H.equal(owner.get_forged_weapons().rejected_a, nil)
        H.equal(owner.get_forged_weapons().rejected_b, nil)
        H.equal(mod.settings.forged_weapons.rejected_a, nil)
        H.equal(mod.settings.forged_weapons.rejected_b, nil)

        -- Removal is transactional too: a failed persistence write retains
        -- the complete prior registry instead of creating a restart-only
        -- resurrection mismatch.
        local removed, remove_err = mod._cim_unregister_crafts_batch({
            "build_melee", "build_ranged",
        })
        H.equal(removed, false)
        H.truthy(remove_err:find("save:", 1, true))
        H.truthy(owner.get_forged_weapons().build_melee)
        H.truthy(mod.settings.forged_weapons.build_melee)

        fail_set = false
        removed = mod._cim_unregister_crafts_batch({ "build_melee", "build_ranged" })
        H.equal(removed, true)
        H.equal(owner.get_forged_weapons().build_melee, nil)
        H.equal(mod.settings.forged_weapons.build_ranged, nil)
    end)

    H.test("CIM loadout wire owner substitutes only on wire and fails unknown ids closed", function()
        local old_loadout_utils = _G.LoadoutUtils
        local old_network_lookup = _G.NetworkLookup
        local ok, err = pcall(function()
            _G.LoadoutUtils = { sync_loadout_slot = function() end }
            _G.NetworkLookup = {
                item_names = { [1] = "es_1h_sword" },
                equipment_slots = { [1] = "slot_melee" },
            }
            local hooks, networks, alerts = {}, {}, {}
            local managers = { player = { _player_loadouts = {} } }
            local mod = { settings = {}, infos = {} }
            function mod:get(key) return self.settings[key] end
            function mod:set(key, value) self.settings[key] = value end
            function mod:info(fmt, ...)
                self.infos[#self.infos + 1] = string.format(fmt, ...)
            end
            function mod:hook(_, method, fn) hooks[method] = fn end
            function mod:network_register(name, fn) networks[name] = fn end
            function mod:network_send(...)
                self.last_send = { ... }
            end

            local install = assert(loadfile(root .. "_cim_loadout_wire_owner.lua"))()
            local owner = install({
                mod = mod,
                rpc_schema = 1,
                dbg_alert = function(...) alerts[#alerts + 1] = { ... } end,
                print_line = function() end,
                get_managers = function() return managers end,
            })
            H.equal(mod.settings.persist_modded_loadouts, false)
            H.equal(owner.wire_safe_rarity("modded"), "unique")
            H.equal(owner.wire_safe_rarity("exotic"), "exotic")

            local player = {
                network_id = function() return "peer" end,
                local_player_id = function() return 1 end,
            }
            local item = { rarity = "modded" }
            local encoded
            hooks.sync_loadout_slot(function(_, _, wire_item)
                encoded = wire_item.rarity
            end, player, "slot_melee", item)
            H.equal(encoded, "unique")
            H.equal(item.rarity, "modded")
            H.equal(owner.get_modded_slot_state()["peer:1"].slot_melee, true)

            networks.cim_modded_slot("sender", 99, "peer", 1,
                "slot_melee", false)
            H.equal(#alerts, 1)
            H.equal(owner.get_modded_slot_state()["peer:1"].slot_melee, true,
                "schema mismatch must not mutate state")

            managers.player._player_loadouts["peer:1"] = {
                slot_melee = { rarity = "unique" },
            }
            local vanilla_calls = 0
            hooks.rpc_sync_loadout_slot(function()
                vanilla_calls = vanilla_calls + 1
            end, managers.player, 1, "peer", 1, 1, 1, 1, 300, {}, {}, {})
            H.equal(vanilla_calls, 1)
            H.equal(managers.player._player_loadouts["peer:1"].slot_melee.rarity,
                "modded")
            hooks.rpc_sync_loadout_slot(function()
                vanilla_calls = vanilla_calls + 1
            end, managers.player, 1, "peer", 1, 1, 99, 1, 300, {}, {}, {})
            H.equal(vanilla_calls, 1, "unknown item id must be dropped pre-decode")
        end)
        _G.LoadoutUtils = old_loadout_utils
        _G.NetworkLookup = old_network_lookup
        if not ok then error(err) end
    end)
end
