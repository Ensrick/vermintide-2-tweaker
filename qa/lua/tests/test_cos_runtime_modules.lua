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
            "_cos_glow_probe", "_cos_la_commands", "_cos_runtime_checks",
        }) do
            local call = 'mod:dofile("scripts/mods/cosmetics_tweaker/' .. name .. '")'
            H.equal(count_plain(entry, call), 1, name .. " load count")
        end
        H.equal(count_plain(entry, "_cos_glow_probe.install(mod"), 1)
        H.equal(count_plain(entry, "_cos_la_commands.install(mod"), 1)
        H.equal(count_plain(entry, "_cos_runtime_checks.install(mod, _rt_register"), 1)
        H.equal(count_plain(entry, "local _wielded_units_for_probe = _cos_glow_probe.wielded_units_for_probe"), 1)
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
        H.equal(#checks, 59)
        H.equal(checks[1].name, "cos_la_reconcile_and_pull_wired")
        H.equal(checks[2].name, "cos_replay_reconciler_wired")
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
    end)
end
