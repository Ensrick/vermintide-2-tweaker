-- WP-CIM-06c (#1654, #277): read the other Crafting in Modded stream's store,
-- import its missing crafted items only on CONFIRM, and say once when both
-- streams are enabled. Settings are namespaced per mod id
-- (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-55).

return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function load_module(name)
        local chunk, err = loadfile(root .. name)
        assert(chunk, name .. " is missing: " .. tostring(err))
        return chunk()
    end

    local es_2h_sword = {
        slot_type = "melee", can_wield = { "es_mercenary" },
        template = "two_handed_swords_template_1", item_type = "es_2h_sword",
        inventory_icon = "icon_es_2h_sword", rarity = "plentiful",
    }

    local function record(extra)
        local r = {
            item_key = "es_2h_sword", slot_type = "melee", power_level = 300,
            rarity = "modded", via_mirror = true, properties = {}, traits = {},
        }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end

    local function fake_mod(settings)
        local mod = {
            settings = settings, messages = {}, printed = {},
            _cim_external_trait_policy = {
                merge_traits = function(active) return active or {} end,
                partition = function(combined) return combined, {} end,
                REQUIRED_CAPABILITY_BY_PROVIDER = {},
                RESERVED_PROVIDER_BY_TRAIT = {},
            },
            _cim_synthetic_item_contract = load_module("_cim_synthetic_item_contract.lua"),
            _cim_store_policy = load_module("_cim_store_policy.lua"),
        }
        function mod:get(key) return self.settings[key] end
        function mod:set(key, value) self.settings[key] = value end
        function mod:info() end
        function mod:echo(fmt, ...)
            self.messages[#self.messages + 1] = select("#", ...) > 0
                and string.format(fmt, ...) or fmt
        end
        function mod:warning() end
        function mod:hook() end
        function mod:hook_safe() end
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
            return function() end
        end
        return mod
    end

    local function install_owner(mod, extra)
        local context = {
            mod = mod,
            rt_register = function() end,
            print_line = function(fmt, ...)
                mod.printed[#mod.printed + 1] = select("#", ...) > 0
                    and string.format(fmt, ...) or fmt
            end,
            get_mod = function() return nil end,
            get_managers = function() return nil end,
            get_item_master_list = function() return { es_2h_sword = es_2h_sword } end,
            get_weapon_traits = function() return nil end,
            get_cjson = function() return nil end,
            get_item_helper = function() return nil end,
            get_athanor_inject_all = function() return nil end,
            get_restore_modded_loadout = function() return nil end,
        }
        for k, v in pairs(extra or {}) do context[k] = v end
        return load_module("_cim_forge_state_owner.lua")(context)
    end

    H.test("cim store import: the other stream's store is read through mods_settings", function()
        local mods_settings = {
            cim = { forged_weapons = { stable_1 = record() } },
            cim_dev = { forged_weapons = { dev_1 = record() } },
        }
        local mod = fake_mod({})
        install_owner(mod, { get_user_setting = function(key)
            H.equal(key, "mods_settings")
            return mods_settings
        end })
        local other = mod._cim_other_stream_store()
        H.truthy(other and other.stable_1, "dev reads the cim stream")
        H.equal(other.dev_1, nil)

        for _, broken in ipairs({ {}, { cim = {} }, { cim = { forged_weapons = "x" } } }) do
            local m = fake_mod({})
            install_owner(m, { get_user_setting = function() return broken end })
            H.equal(m._cim_other_stream_store(), nil, "missing level gives nil")
        end
        local raising = fake_mod({})
        install_owner(raising, { get_user_setting = function() error("no Application") end })
        H.equal(raising._cim_other_stream_store(), nil, "a raising getter gives nil")
    end)

    H.test("cim store import: /cim_import_other_stream counts, then adds only missing ids", function()
        local live = { shared = record({ power_level = 250 }) }
        local mod = fake_mod({})
        mod._cim_other_stream_store = function()
            return { shared = record({ power_level = 100 }), only_stable = record() }
        end
        local batches, loops = {}, 0
        function mod._cim_register_crafts_batch(entries)
            batches[#batches + 1] = entries
            for id, entry in pairs(entries) do live[id] = entry end
            return true, entries
        end
        mod._cim_run_restore_loop = function() loops = loops + 1 end
        local commands = {}
        mod.command = function(_, name, _, callback) commands[name] = callback end
        local noop = function() end
        load_module("_cim_command_owner.lua")({
            mod = mod,
            is_custom_forge_active = function() return false end,
            get_forged_weapons = function() return live end,
            get_modded_loadout = function() return {} end,
            get_more_items_lib = function() return {} end,
            commit_craft = noop, forge_create_item = noop, forge_detect_mil = noop,
            forge_save = noop, modded_loadout_save = noop,
        })
        local import = assert(commands.cim_import_other_stream, "command registered")
        import()
        H.equal(#batches, 0, "dry run changes nothing")
        H.truthy(mod.messages[#mod.messages]:find("1 crafted item", 1, true), mod.messages[#mod.messages])
        import("CONFIRM")
        H.equal(#batches, 1)
        H.equal(batches[1].shared, nil, "an existing id is never overwritten")
        H.truthy(batches[1].only_stable)
        H.equal(live.shared.power_level, 250)
        H.equal(loops, 1)
        import("CONFIRM")
        H.equal(#batches, 1, "nothing left to import")
    end)

    H.test("cim store import: both enabled streams are announced once", function()
        local function stream(enabled) return { is_enabled = function() return enabled end } end
        local mod = fake_mod({ forged_weapons = {} })
        local owner = install_owner(mod, { get_mod = function(id)
            if id == "cim_dev" or id == "cim" then return stream(true) end
        end })
        owner.load()
        local hits = 0
        for _, line in ipairs(mod.printed) do
            if line == "[cim:store] both Crafting in Modded streams are enabled; each keeps its own crafted items" then
                hits = hits + 1
            end
        end
        H.equal(hits, 1, "printed once")
        H.equal(#mod.messages, 1, "echoed once")

        local quiet = fake_mod({ forged_weapons = {} })
        install_owner(quiet, { get_mod = function(id)
            if id == "cim_dev" then return stream(true) end
            if id == "cim" then return stream(false) end
        end })
        H.equal(#quiet.printed, 0, "silent when the other stream is disabled")
    end)
end
