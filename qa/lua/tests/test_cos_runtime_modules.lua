return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"

    local function read(name)
        local file = assert(io.open(base .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    local entry = read("cosmetics_tweaker.lua")
    local runtime_source = read("_cos_runtime_checks.lua")
    local command_source = read("_cos_command_owner.lua")
    local glow_source = read("_cos_glow_probe.lua")
    local la_source = read("_cos_la_commands.lua")

    local function command_mod()
        local commands = {}
        local mod = {
            _cos_mem_t0 = collectgarbage("count"),
            command = function(_, name, _, fn)
                commands[#commands + 1] = { name = name, fn = fn }
            end,
            info = function() end,
            echo = function() end,
        }
        return mod, commands
    end

    H.test("Cosmetics entry installs each extracted runtime owner once", function()
        for _, name in ipairs({
            "_cos_glow_probe", "_cos_la_commands", "_cos_runtime_checks", "_cos_command_owner",
            "_cos_modded_illusion_swap", "_cos_glow_editor_button",
        }) do
            local call = 'mod:dofile("scripts/mods/cosmetics_tweaker/' .. name .. '")'
            H.equal(count_plain(entry, call), 1, name .. " load count")
        end
        H.equal(count_plain(entry, "_cos_glow_probe.install(mod"), 1)
        H.equal(count_plain(entry, "_cos_la_commands.install(mod"), 1)
        H.equal(count_plain(entry, "_cos_runtime_checks.install(mod, _rt_register"), 1)
        H.equal(count_plain(entry, "_cos_command_owner\").install(mod"), 1)
        H.equal(count_plain(entry, "MODDED_ILLUSION_SWAP.install(mod"), 1)
        H.equal(count_plain(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_catalog").install(mod'), 1)
        H.equal(count_plain(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_picker").install(mod'), 1)
        H.equal(count_plain(entry, "local _wielded_units_for_probe = _cos_glow_probe.wielded_units_for_probe"), 1)
    end)

    H.test("Cosmetics command owner preserves registry and maintenance surfaces", function()
        local commands, output, values = {}, {}, {}
        local mod = {
            command = function(_, name, _, fn)
                commands[#commands + 1] = { name = name, fn = fn }
            end,
            echo = function(_, fmt, ...)
                output[#output + 1] = string.format(fmt, ...)
            end,
            info = function() end,
            warning = function(_, fmt, ...)
                output[#output + 1] = string.format(fmt, ...)
            end,
            get = function(_, key) return values[key] end,
            set = function(_, key, value) values[key] = value end,
        }
        local owner_module = assert(loadfile(base .. "_cos_command_owner.lua"))()
        local register, owner = owner_module.install(mod, {
            version = "0.9.test-dev",
            local_player_safe = function(pm) return pm and pm:local_player_safe() end,
            la_persist = {},
            printf = function() end,
        })
        H.equal(owner.command_count, 4)
        H.equal(owner.check_count(), 1)
        H.equal(commands[1].name, "cos_regression_test")
        H.equal(commands[2].name, "cos_persist_dump")
        H.equal(commands[3].name, "cos_persist_replay")
        H.equal(commands[4].name, "cos_persist_clear")

        register("passes", function() end)
        register("fails", function() return "expected failure" end)
        register("skips", function() error("must not run") end, {
            precondition = function() return false, "fixture absent" end,
        })
        commands[1].fn()
        H.equal(owner.check_count(), 4)
        H.truthy(table.concat(output, "\n"):find("2 passed, 1 failed", 1, true))
        H.truthy(table.concat(output, "\n"):find("1 skipped", 1, true))

        commands[4].fn()
        H.equal(values.la_persisted_equips.schema, 1)
        H.equal(next(values.la_persisted_equips.careers), nil)
        local again_register, again_owner = owner_module.install(mod, {})
        H.equal(again_register, register)
        H.equal(again_owner, owner)
        H.equal(#commands, 4)
    end)

    H.test("Cosmetics runtime checks preserve order and command ownership", function()
        local mod, commands = command_mod()
        local checks = {}
        local deps = {
            la_persist = {}, score_identity = {}, rpc_schema = 1,
            composite_icons = {}, custom_hats = {}, la_bridge = {}, gk_set = {},
            glow_picker = {}, weapon_poses = {}, shield_icon_owner_item_types = {},
            offhand_options = {}, multi_mount_item_types = {}, dual_wield_pools = {},
            offhand_names = {}, shield_pools_by_item_type = {}, dbg = function() end,
            dbg_alert = function() end, ui_dump = {}, custom_skin_keys = {},
            offhand_preload_lifecycle = {}, mh_embed = {},
            la_instance_policy = {}, husk_identity = {},
            modded_illusion_swap_owner = {
                hook_count = 8, owns_illusion_swap = function() return false end,
            },
            issue704_picker_family = function(surface, family)
                local expected = {
                    vanilla = "cwv_es_sword_and_mace",
                    right_hand_unit = "es_1h_sword",
                    left_hand_unit = "es_1h_mace",
                }
                return expected[surface] == family
            end,
        }
        local module = assert(loadfile(base .. "_cos_runtime_checks.lua"))()
        module.install(mod, function(name, fn)
            checks[#checks + 1] = { name = name, fn = fn }
        end, deps)
        H.equal(#checks, 61)
        H.equal(checks[1].name, "cos_la_reconcile_and_pull_wired")
        H.equal(checks[2].name, "cos_replay_reconciler_wired")
        -- #25: the cold-load contract must stay registered directly after the
        -- process-mirror roundtrip it exists to harden.
        local cosmetic_roundtrip_index, cold_load_index
        for index, check in ipairs(checks) do
            if check.name == "cos_la_cosmetic_persistence_roundtrip" then
                cosmetic_roundtrip_index = index
            end
            if check.name == "cos_la_cold_load_contract_25" then
                cold_load_index = index
            end
        end
        H.truthy(cosmetic_roundtrip_index)
        H.equal(cold_load_index, cosmetic_roundtrip_index + 1,
            "cold-load contract must follow the mirror roundtrip it hardens")
        local score_identity_index, score_replay_index
        for index, check in ipairs(checks) do
            if check.name == "cos_la_score_screen_apply_wired" then score_identity_index = index end
            if check.name == "issue730_score_armor_visibility_replay" then score_replay_index = index end
        end
        H.truthy(score_identity_index)
        H.equal(score_replay_index, score_identity_index + 1,
            "score appearance replay must follow exact wearer identity")
        H.equal(checks[#checks].name, "mh_package_single_reference")
        H.equal(#commands, 1)
        H.equal(commands[1].name, "verify_gk_set")
        H.equal(count_plain(entry, '_rt_register("cos_la_reconcile_and_pull_wired"'), 0)
        H.equal(count_plain(runtime_source, 'mod:command("verify_gk_set"'), 1)
    end)

    H.test("Cosmetics extracted command modules retain their exact surfaces", function()
        local mod, glow_commands = command_mod()
        local glow = assert(loadfile(base .. "_cos_glow_probe.lua"))()
        glow.install(mod, {
            local_player_safe = function() end,
            is_unit = function() return false end,
            flush_log = function() end,
        })
        H.equal(#glow_commands, 6)
        H.equal(glow_commands[1].name, "glow_dump")
        H.equal(glow_commands[#glow_commands].name, "la_shield_glow_probe")
        H.equal(type(glow.wielded_units_for_probe), "function")
        H.equal(type(mod._glow_scan_tick), "function")
        H.equal(type(mod._la_shield_probe_tick), "function")

        local la_mod, la_commands = command_mod()
        local la = assert(loadfile(base .. "_cos_la_commands.lua"))()
        la.install(la_mod, {
            la_bridge = {}, local_career_name = function() return nil end,
            flush_log = function() end,
        })
        H.equal(#la_commands, 6)
        H.equal(la_commands[1].name, "la_dump")
        H.equal(la_commands[#la_commands].name, "la_hats")

        for _, name in ipairs({ "glow_dump", "glow_probe", "glow_scan", "la_dump", "la_hats" }) do
            H.equal(count_plain(entry, 'mod:command("' .. name .. '"'), 0,
                name .. " duplicated in entry")
        end
        H.equal(count_plain(glow_source, "mod:hook"), 0)
        H.equal(count_plain(la_source, "mod:hook"), 0)
        H.equal(count_plain(runtime_source, "mod:hook"), 0)
        H.equal(count_plain(command_source, "mod:hook"), 0)
    end)
end
