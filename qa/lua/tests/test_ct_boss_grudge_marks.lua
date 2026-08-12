return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_boss_grudge_marks.lua")

    H.test("CT Boss Grudge owner declares its complete ownership contract", function()
        for _, header in ipairs({
            "-- OWNER:", "-- RESPONSIBILITY:", "-- PUBLIC SURFACE:",
            "-- INSTALL ORDER:", "-- INVARIANTS:",
        }) do
            H.equal(count_plain(owner, header), 1, header)
        end
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "ct_sync_host_settings_chunk"), 0)
        H.equal(count_plain(owner, "_collect_setting_ids"), 0)
    end)

    H.test("CT Boss Grudge owner occupies one exact boundary and facade", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_boss_grudge_marks"), 1)
        H.equal(count_plain(entry,
            'mod:hook(_G.TerrorEventUtils, "apply_breed_enhancements"'), 0)
        H.equal(count_plain(entry, 'mod:command("dump_grudge_marks"'), 0)
        H.equal(count_plain(entry, 'mod:command("verify_grudge_marks"'), 0)
        H.equal(count_plain(owner,
            'mod:hook(terror_event_utils, "apply_breed_enhancements"'), 1)
        H.equal(count_plain(owner, 'mod:command("dump_grudge_marks"'), 1)
        H.equal(count_plain(owner, 'mod:command("verify_grudge_marks"'), 1)
        H.equal(count_plain(entry,
            "local sync_grudge_marks = _boss_grudge_owner.sync"), 1)

        local owner_at = assert(entry:find("_ct_boss_grudge_marks", 1, true))
        local next_command_at = assert(entry:find('mod:command("verify_belakor"', 1, true))
        local settings_at = assert(entry:find("mod.on_setting_changed = function", 1, true))
        H.truthy(owner_at < next_command_at)
        H.truthy(next_command_at < settings_at)
    end)

    H.test("CT Boss Grudge registration order and owner map are exhaustive", function()
        local hook_at = assert(owner:find(
            'mod:hook(terror_event_utils, "apply_breed_enhancements"', 1, true))
        local dump_at = assert(owner:find(
            'mod:command("dump_grudge_marks"', 1, true))
        local verify_at = assert(owner:find(
            'mod:command("verify_grudge_marks"', 1, true))
        H.truthy(hook_at < dump_at)
        H.truthy(dump_at < verify_at)

        local physical = 0
        for _ in owner:gmatch("[^\r\n]+") do physical = physical + 1 end
        H.truthy(physical < 1500)

        local install = assert(loadfile(root .. "_ct_boss_grudge_marks.lua"))()
        local native_marks, breed_enhancements = {}, {}
        local expected_names = {
            "commander", "crippling", "crushing", "frenzy", "intangible",
            "periodic_curse", "periodic_shield", "raging", "ranged_immune",
            "regenerating", "unstaggerable", "vampiric", "warping",
        }
        for _, name in ipairs(expected_names) do
            native_marks[name] = { name = name }
            breed_enhancements[name] = { display_name = "display_" .. name }
        end
        local globals = {
            BossGrudgeMarks = native_marks,
            BreedEnhancements = breed_enhancements,
            TerrorEventUtils = {},
        }
        local active = { commander = true }
        local second_effective_calls, second_policy_calls = 0, 0
        local second_global_calls, second_manager_calls = 0, 0
        local second_dbg_calls, second_printf_calls = 0, 0
        local events, callbacks, commands = {}, {}, {}
        local mod = {
            hook = function(_, target, method_name, callback)
                H.equal(target, globals.TerrorEventUtils)
                events[#events + 1] = "hook:" .. method_name
                callbacks[method_name] = callback
            end,
            command = function(_, name, _, callback)
                events[#events + 1] = "command:" .. name
                commands[name] = callback
            end,
            echo = function() end,
            warning = function() end,
        }
        local function context(current_globals, current_active, generation)
            return {
                mod = mod,
                effective_setting = function(setting_id)
                    if generation == 2 then second_effective_calls = second_effective_calls + 1 end
                    local name = setting_id:match("^ban_grudge_mark_(.+)$")
                    return name and current_active[name] == true or false
                end,
                is_banned = function(master, child)
                    if generation == 2 then second_policy_calls = second_policy_calls + 1 end
                    return master or child
                end,
                get_global = function(name)
                    if generation == 2 then second_global_calls = second_global_calls + 1 end
                    return current_globals[name]
                end,
                get_managers = function()
                    if generation == 2 then second_manager_calls = second_manager_calls + 1 end
                    return { player = { is_server = true } }
                end,
                dbg = function()
                    if generation == 2 then second_dbg_calls = second_dbg_calls + 1 end
                end,
                printf = function()
                    if generation == 2 then second_printf_calls = second_printf_calls + 1 end
                end,
            }
        end

        local first, first_install = install(context(globals, active, 1))
        H.deep_equal(events, {
            "hook:apply_breed_enhancements",
            "command:dump_grudge_marks",
            "command:verify_grudge_marks",
        })
        H.equal(first_install, true)
        H.equal(native_marks.commander, nil)
        H.truthy(native_marks.frenzy ~= nil)

        local export_keys = {}
        for key in pairs(first) do export_keys[#export_keys + 1] = key end
        table.sort(export_keys)
        H.deep_equal(export_keys, { "get_baseline", "names", "sync" })
        H.equal(#first.names, 13)
        for i = 1, #expected_names do H.equal(first.names[i], expected_names[i]) end
        local baseline = first.get_baseline()
        for _, name in ipairs(expected_names) do
            H.truthy(baseline[name] ~= nil, "baseline missing " .. name)
        end

        local replacement_globals = {
            BossGrudgeMarks = {},
            BreedEnhancements = breed_enhancements,
            TerrorEventUtils = globals.TerrorEventUtils,
        }
        local replacement_active = { frenzy = true }
        local reloaded_install = assert(loadfile(root .. "_ct_boss_grudge_marks.lua"))()
        local second, second_install = reloaded_install(
            context(replacement_globals, replacement_active, 2))
        H.equal(second, first)
        H.equal(second_install, false)
        H.equal(#events, 3, "reload duplicated registration")
        H.truthy(replacement_globals.BossGrudgeMarks.commander ~= nil,
            "fresh owner did not replay the original baseline into replacement globals")
        H.equal(replacement_globals.BossGrudgeMarks.frenzy, nil)

        local optional_data = {
            enhancements = {
                { name = "base" }, { name = "frenzy" }, { name = "commander" },
            },
        }
        local forwarded
        callbacks.apply_breed_enhancements(function(_, _, data)
            forwarded = data
            return "native"
        end, {}, { name = "chaos_spawn" }, optional_data)
        H.equal(#forwarded.enhancements, 2)
        H.equal(forwarded.enhancements[1].name, "base")
        H.equal(forwarded.enhancements[2].name, "commander")
        H.truthy(second_effective_calls > 0,
            "registered runtime retained the first owner's setting dependency")
        H.truthy(second_policy_calls > 0,
            "registered callback retained the first owner's policy dependency")
        H.truthy(second_global_calls > 0,
            "registered runtime retained the first owner's global dependency")
        H.truthy(second_manager_calls > 0,
            "registered callback retained the first owner's manager dependency")
        H.truthy(second_dbg_calls > 0,
            "registered runtime retained the first owner's debug dependency")
        H.truthy(second_printf_calls > 0,
            "registered callback retained the first owner's logger dependency")
        H.truthy(type(commands.dump_grudge_marks) == "function")
        H.truthy(type(commands.verify_grudge_marks) == "function")
    end)

    H.test("CT Boss Grudge dependencies remain explicit and late-bound", function()
        for _, dependency in ipairs({
            "effective_setting", "is_banned", "get_global", "get_managers",
            "dbg", "printf",
        }) do
            H.truthy(entry:find(dependency .. " =", 1, true),
                "entry does not inject " .. dependency)
            H.truthy(owner:find("ctx." .. dependency, 1, true),
                "owner does not consume " .. dependency)
        end
        H.truthy(owner:find("state.effective_setting", 1, true))
        H.truthy(owner:find("state.get_managers()", 1, true))
        H.truthy(owner:find("state.get_global", 1, true))
    end)
end
