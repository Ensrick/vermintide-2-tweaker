return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_path = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_mod_lifecycle.lua"
    local source = read(module_path)
    local Lifecycle = assert(loadfile(repo_root .. "/" .. module_path))()

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    H.test("Cosmetics entry delegates its lifecycle owner exactly once", function()
        H.equal(occurrences(entry, "_cos_mod_lifecycle"), 1)
        H.truthy(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle").install',
            1, true))
        H.equal(entry:find("mod.on_game_state_changed = function", 1, true), nil)
        H.equal(entry:find("mod.on_disabled = function", 1, true), nil)
        H.equal(entry:find("mod.on_unload = function", 1, true), nil)
        H.truthy(entry:find("_cos_mod_lifecycle", 1, true)
            < entry:find("_cos_settings_runtime", 1, true))
    end)

    H.test("Cosmetics lifecycle owner preserves callback cardinality and order", function()
        local executable = source:gsub("%-%-[^\n]*", "")
        H.equal(occurrences(source, "mod.on_game_state_changed = function"), 1)
        H.equal(occurrences(source, "mod.on_disabled = function"), 1)
        H.equal(occurrences(source, "mod.on_unload = function"), 1)
        local changed = assert(source:find("mod.on_game_state_changed = function", 1, true))
        local disabled = assert(source:find("mod.on_disabled = function", changed, true))
        local unload = assert(source:find("mod.on_unload = function", disabled, true))
        H.truthy(changed < disabled and disabled < unload)
        H.equal(executable:find("network_register", 1, true), nil)
        H.equal(executable:find("network_send", 1, true), nil)
        H.equal(executable:find("mod.update", 1, true), nil)
        H.equal(executable:find("mod:hook", 1, true), nil)
    end)

    H.test("Cosmetics lifecycle transition and teardown effects remain bounded", function()
        local calls = {
            unlocks = 0,
            flow = 0,
            glow = 0,
            trace = 0,
            summaries = 0,
            replay = 0,
            dumps = 0,
            flush = 0,
            gate = 0,
            release = 0,
            info = 0,
        }
        local mod = {
            _cos = {
                apply_cosmetic_unlocks = function()
                    calls.unlocks = calls.unlocks + 1
                end,
            },
            _cos_replay = {
                on_edge = function(edge, options)
                    calls.replay = calls.replay + 1
                    calls.edge = edge
                    calls.invalidate_all = options.invalidate_all
                end,
            },
        }
        function mod:debug() end
        function mod:info() calls.info = calls.info + 1 end
        mod._try_install_flow_glow_hook = function()
            calls.flow = calls.flow + 1
        end
        mod._on_glow_setting_changed = function()
            calls.glow = calls.glow + 1
        end
        mod._la_dump_mission_state = function(reason)
            calls.dumps = calls.dumps + 1
            calls.dump_reason = reason
        end
        mod._release_offhand_packages = function(reason)
            calls.release = calls.release + 1
            calls.release_reason = reason
        end

        local deps = {
            trace = function()
                calls.trace = calls.trace + 1
            end,
            mh_embed = {
                reference_summary = function()
                    calls.summaries = calls.summaries + 1
                    return { held = 1, exact = 1, over = 0, missing = 0 }
                end,
            },
            tpe = {
                flush = function() calls.flush = calls.flush + 1 end,
            },
            la_bridge = {
                uninstall_apply_gate = function() calls.gate = calls.gate + 1 end,
            },
        }

        local owner = Lifecycle.install(mod, deps)
        H.equal(Lifecycle.install(mod, deps), owner)
        H.equal(mod.on_game_state_changed, owner.on_game_state_changed)
        H.equal(mod.on_disabled, owner.on_disabled)
        H.equal(mod.on_unload, owner.on_unload)

        mod.on_game_state_changed("enter", "StateIngame")
        H.equal(calls.unlocks, 1)
        H.equal(calls.flow, 1)
        H.equal(calls.glow, 1)
        H.equal(calls.trace, 1)
        H.equal(calls.replay, 1)
        H.equal(calls.edge, "session-ready")
        H.equal(calls.invalidate_all, true)
        H.equal(calls.dumps, 1)
        H.equal(calls.dump_reason, "game_state_change")
        H.equal(mod._la_self_rebroadcast_pending, true)
        H.deep_equal(mod._la_state_pull_pending, { attempts = 0, next_at = 0 })
        H.truthy(type(mod._la_reapply_remote_until) == "number")

        mod.on_game_state_changed("exit", "StateIngame")
        H.equal(calls.summaries, 1)
        H.equal(calls.unlocks, 2)
        H.equal(calls.replay, 1)
        H.equal(calls.dumps, 2)

        mod.on_disabled()
        H.equal(calls.flush, 1)
        H.equal(calls.gate, 1)
        mod.on_unload()
        H.equal(calls.release, 1)
        H.equal(calls.release_reason, "mod_unload")
        H.equal(calls.info, 1)
    end)
end
