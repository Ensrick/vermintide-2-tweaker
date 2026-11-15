-- WP-CIM-06b (#1654, #277): one session-start backup of the crafted store, and
-- /cim_restore_backup that only ever adds missing ids back.

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
            settings = settings, sets = {}, set_args = {}, messages = {},
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
        function mod:set(key, value, notify)
            self.sets[key] = (self.sets[key] or 0) + 1
            self.set_args[key] = notify
            self.settings[key] = value
        end
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

    local function install_owner(mod, inject_all)
        local checks = {}
        local owner = load_module("_cim_forge_state_owner.lua")({
            mod = mod,
            rt_register = function(name, fn) checks[name] = fn end,
            print_line = function() end,
            get_mod = function() return nil end,
            get_managers = function() return nil end,
            get_item_master_list = function() return { es_2h_sword = es_2h_sword } end,
            get_weapon_traits = function() return nil end,
            get_cjson = function() return nil end,
            get_item_helper = function() return nil end,
            get_athanor_inject_all = function() return inject_all end,
            get_restore_modded_loadout = function() return nil end,
        })
        return owner, checks
    end

    H.test("cim store backup: first load in a process backs up a non-empty store once", function()
        local mod = fake_mod({ forged_weapons = { a = record(), b = record() } })
        local owner, checks = install_owner(mod)
        H.equal(mod.sets.forged_weapons_backup, 1)
        H.equal(mod.set_args.forged_weapons_backup, false, "no on_setting_changed notify")
        H.truthy(mod.settings.forged_weapons_backup.a and mod.settings.forged_weapons_backup.b)
        owner.load()
        H.equal(mod.sets.forged_weapons_backup, 1, "one backup per process")
        H.equal(checks.issue_cim_store_backup_present(), nil)
    end)

    H.test("cim store backup: an empty store is never backed up", function()
        local mod = fake_mod({ forged_weapons = {} })
        local _, checks = install_owner(mod)
        H.equal(mod.sets.forged_weapons_backup, nil)
        H.equal(checks.issue_cim_store_backup_present(), "skip: no crafted items")
        local none = fake_mod({})
        install_owner(none)
        H.equal(none.sets.forged_weapons_backup, nil)
    end)

    H.test("cim store backup: /cim_restore_backup counts, then adds only missing ids", function()
        local live = { kept = record({ power_level = 250 }) }
        local mod = fake_mod({
            forged_weapons_backup = {
                kept = record({ power_level = 100 }),
                lost_1 = record(),
                lost_2 = record({ properties = { attack_speed = 0 } }),
            },
        })
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
            commit_craft = noop,
            forge_create_item = noop,
            forge_detect_mil = noop,
            forge_save = noop,
            modded_loadout_save = noop,
        })
        local restore = assert(commands.cim_restore_backup, "command registered")

        restore()
        H.equal(#batches, 0, "dry run changes nothing")
        H.truthy(mod.messages[#mod.messages]:find("2 crafted item", 1, true), mod.messages[#mod.messages])

        restore("CONFIRM")
        H.equal(#batches, 1, "one batch registration")
        H.equal(batches[1].kept, nil, "an existing id is never overwritten")
        H.truthy(batches[1].lost_1 and batches[1].lost_2)
        H.equal(live.kept.power_level, 250, "live record untouched")
        H.equal(loops, 1, "restore loop ran once")

        restore("CONFIRM")
        H.equal(#batches, 1, "nothing left to add")
        H.truthy(mod.messages[#mod.messages]:find("Nothing to restore", 1, true))
    end)

    H.test("cim store backup: a refused batch is reported and the loop does not run", function()
        local mod = fake_mod({ forged_weapons_backup = { lost = record() } })
        local loops = 0
        function mod._cim_register_crafts_batch() return false, "save:store_not_serializable" end
        mod._cim_run_restore_loop = function() loops = loops + 1 end
        local commands = {}
        mod.command = function(_, name, _, callback) commands[name] = callback end
        local noop = function() end
        load_module("_cim_command_owner.lua")({
            mod = mod,
            is_custom_forge_active = function() return false end,
            get_forged_weapons = function() return {} end,
            get_modded_loadout = function() return {} end,
            get_more_items_lib = function() return {} end,
            commit_craft = noop, forge_create_item = noop, forge_detect_mil = noop,
            forge_save = noop, modded_loadout_save = noop,
        })
        commands.cim_restore_backup("CONFIRM")
        H.equal(loops, 0)
        H.truthy(mod.messages[#mod.messages]:find("save:store_not_serializable", 1, true))
    end)
end
