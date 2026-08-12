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
    local owner = read("_ct_curse_lighting_owner.lua")

    H.test("CT curse-lighting owner declares one bounded exact seam", function()
        for _, header in ipairs({
            "-- OWNER:", "-- RESPONSIBILITY:", "-- PUBLIC SURFACE:",
            "-- INVARIANTS:", "-- Owned by:", "-- Consumed via:",
        }) do
            H.equal(count_plain(owner, header), 1, header)
        end
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_curse_lighting_owner"), 1)
        H.equal(count_plain(entry,
            'mod:hook_safe("CameraManager", "shading_callback"'), 0)
        H.equal(count_plain(owner,
            'mod:hook_safe("CameraManager", "shading_callback"'), 1)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "mod:command("), 0)

        local owner_at = assert(entry:find("_ct_curse_lighting_owner", 1, true))
        local shrine_at = assert(entry:find("Replace shrines with missions", 1, true))
        H.truthy(owner_at < shrine_at)
    end)


    H.test("CT curse-lighting hook registration retries after a thrown install", function()
        local install = assert(loadfile(root .. "_ct_curse_lighting_owner.lua"))()
        local attempts = 0
        local mod = {
            hook_safe = function()
                attempts = attempts + 1
                if attempts == 1 then
                    error("sentinel hook registration failure")
                end
            end,
            get = function() return 1 end,
        }
        local ctx = {
            mod = mod,
            on_injected_adventure_level = function() return false end,
            adventure_base_from_level_key = function(value) return value end,
            get_managers = function() return {} end,
            get_level_helper = function() return {} end,
            get_shading_environment = function() return {} end,
            make_vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
            printf = function() end,
        }

        local ok, err = pcall(install, ctx)
        H.equal(ok, false)
        H.truthy(tostring(err):find("sentinel hook registration failure", 1, true))
        H.equal(attempts, 1)

        local second = install(ctx)
        H.equal(attempts, 2,
            "failed registration incorrectly marked the hook installed")
        H.equal(mod._ct_curse_lighting_owner, second)

        local reloaded_install =
            assert(loadfile(root .. "_ct_curse_lighting_owner.lua"))()
        local third = reloaded_install(ctx)
        H.equal(attempts, 2, "successful retry was not idempotent")
        H.equal(third, second)
    end)

    H.test("CT curse-lighting owner exhaustively replays a fresh public map", function()
        local install = assert(loadfile(root .. "_ct_curse_lighting_owner.lua"))()
        local events, callbacks = {}, {}
        local mod = {
            hook_safe = function(_, class_name, method_name, callback)
                events[#events + 1] = class_name .. "." .. method_name
                callbacks[method_name] = callback
            end,
            get = function(_, setting_id)
                H.equal(setting_id, "curse_lighting_brightness")
                return 1
            end,
        }

        local function generation(theme, curse, level_id)
            local calls = {
                injected = 0, managers = 0, level_helper = 0,
                shading = 0, vector = 0, resolver = 0, printf = 0,
            }
            local now = 0
            local node = { theme = theme, curse = curse }
            local run = {
                get_current_node = function() return node end,
            }
            local mechanism = {
                get_deus_run_controller = function() return run end,
            }
            local managers = {
                mechanism = {
                    game_mechanism = function() return mechanism end,
                },
                time = {
                    time = function() return now end,
                },
                state = {
                    networked_flow_state = { _num_states = 7 },
                    conflict = { _num_spawned_ai = 3 },
                    game_mode = {
                        level_key = function() return level_id end,
                    },
                },
            }
            local level_helper = {
                current_level_settings = function()
                    return { level_id = level_id }
                end,
            }
            local shading_environment = {
                vector3 = function()
                    return { x = 1, y = 1, z = 1 }
                end,
                set_vector3 = function() end,
                scalar = function() return 1 end,
                set_scalar = function() end,
            }
            local ctx = {
                mod = mod,
                on_injected_adventure_level = function()
                    calls.injected = calls.injected + 1
                    return true
                end,
                adventure_base_from_level_key = function(value)
                    calls.resolver = calls.resolver + 1
                    H.equal(value, level_id)
                    return value
                end,
                get_managers = function()
                    calls.managers = calls.managers + 1
                    return managers
                end,
                get_level_helper = function()
                    calls.level_helper = calls.level_helper + 1
                    return level_helper
                end,
                get_shading_environment = function()
                    calls.shading = calls.shading + 1
                    return shading_environment
                end,
                make_vector3 = function(x, y, z)
                    calls.vector = calls.vector + 1
                    return { x = x, y = y, z = z }
                end,
                printf = function()
                    calls.printf = calls.printf + 1
                end,
            }
            return ctx, calls, function(value) now = value end
        end

        local ctx1, calls1 = generation(
            "nurgle", "curse_corrupted_flesh", "dlc_termite_3")
        local first = install(ctx1)
        H.deep_equal(events, { "CameraManager.shading_callback" })
        local callback = callbacks.shading_callback
        H.truthy(type(callback) == "function")

        local first_theme = first.current_node_theme
        local first_curse = first.current_node_curse
        local first_belakor = first.current_node_is_belakor
        local first_profiles = first.curse_sky_profiles
        local first_map_brightness = first.curse_map_brightness

        local replacement = { stale = true, removed_export = function() end }
        mod._ct_curse_lighting_owner = replacement
        local ctx2, calls2, set_now2 = generation(
            "khorne", "curse_belakor_totems", "dlc_termite_2")
        local reloaded_install =
            assert(loadfile(root .. "_ct_curse_lighting_owner.lua"))()
        local second = reloaded_install(ctx2)

        H.equal(second, replacement,
            "installer discarded the fresh public namespace map")
        H.equal(mod._ct_curse_lighting_owner, replacement)
        H.truthy(second ~= first)
        H.equal(#events, 1, "reload duplicated CameraManager hook")
        H.equal(callbacks.shading_callback, callback,
            "reload replaced registered callback identity")

        local keys = {}
        for key in pairs(second) do keys[#keys + 1] = key end
        table.sort(keys)
        H.deep_equal(keys, {
            "current_node_curse",
            "current_node_is_belakor",
            "current_node_theme",
            "curse_map_brightness",
            "curse_sky_profiles",
            "perf_census_marker",
            "perf_window",
        })
        H.equal(second.stale, nil)
        H.equal(second.removed_export, nil)
        H.equal(second.current_node_theme, first_theme)
        H.equal(second.current_node_curse, first_curse)
        H.equal(second.current_node_is_belakor, first_belakor)
        H.equal(second.curse_sky_profiles, first_profiles)
        H.equal(second.curse_map_brightness, first_map_brightness)
        H.equal(second.perf_census_marker,
            "perf104:flowstate_enemy_fps_census_v0.7.214")
        H.equal(second.perf_window, 5)
        H.equal(CT_PERF_CENSUS_MARKER, second.perf_census_marker)
        H.equal(CT_PERF_WINDOW, second.perf_window)

        H.equal(second.current_node_theme(), "khorne")
        H.equal(second.current_node_curse(), "curse_belakor_totems")
        H.equal(second.current_node_is_belakor(), true)
        H.equal(calls1.managers, 0,
            "reloaded public helpers retained first-generation Managers")
        H.truthy(calls2.managers >= 3)

        set_now2(0)
        callback({}, {}, {}, {})
        set_now2(6)
        callback({}, {}, {}, {})
        H.equal(calls1.injected, 0)
        H.equal(calls1.level_helper, 0)
        H.equal(calls1.shading, 0)
        H.equal(calls1.vector, 0)
        H.equal(calls1.resolver, 0)
        H.equal(calls1.printf, 0)
        H.truthy(calls2.injected >= 2)
        H.truthy(calls2.level_helper >= 2)
        H.truthy(calls2.shading >= 2)
        H.truthy(calls2.vector >= 12)
        H.truthy(calls2.resolver >= 2)
        H.truthy(calls2.printf >= 1)
    end)
end
