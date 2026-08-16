return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_path = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_preview_runtime.lua"
    local source = read(module_path)
    local PreviewRuntime = assert(loadfile(repo_root .. "/" .. module_path))()

    local function fixture()
        local registrations = {}
        local mod = {
            _cos = {
                apply_unit_path_scale_hand = function() end,
                bind_glow_unit = function() end,
                apply_glow_override = function() end,
                apply_composed_shield_glow = function() end,
            },
            _la_instance_policy = {
                resolve_preview_backend_id = function() end,
            },
        }
        function mod:hook(class_name, method_name, callback)
            registrations[#registrations + 1] = {
                kind = "hook", class_name = class_name,
                method_name = method_name, callback = callback,
            }
        end
        function mod:hook_safe(class_name, method_name, callback)
            registrations[#registrations + 1] = {
                kind = "hook_safe", class_name = class_name,
                method_name = method_name, callback = callback,
            }
        end
        function mod:get() return false end

        local getter_calls = 0
        local deps = {
            la_bridge = { backend_to_armoury = {} },
            custom_hats = {},
            score_identity = { resolve_snapshot = function() end },
            gk_set = {},
            glow_preview_policy = {
                resolve_spawn = function(_, backend_id)
                    return {
                        skin = nil,
                        has_skin = false,
                        preview_backend_id = backend_id,
                    }
                end,
                bind_spawned = function() end,
            },
            glow_picker = { restore_runtime_for = function() return false end },
            dbg = function() end,
            dbg_alert = function() end,
            local_player_safe = function() end,
            apply_la_offhand_to_units = function() return false end,
            offhand_paint_mesh_ok = function() return false end,
            resolve_item_type = function() end,
            resolve_composed_appearance = function() end,
            glow_log = function() end,
            get_active_customization_backend_id = function()
                getter_calls = getter_calls + 1
                return "active-backend"
            end,
            get_mod = function() end,
            cim_preview = {
                capture_load = function() return false end,
                destroy = function() end,
                surface = function() return "illusion_browser" end,
                spawn = function() end,
                update = function() end,
            },
        }
        return mod, deps, registrations, function() return getter_calls end
    end

    H.test("Cosmetics preview runtime has one ordered entry owner", function()
        H.equal(occurrences(entry,
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_preview_runtime")'), 1)
        H.truthy(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_preview_runtime").install',
            1, true))
        H.equal(entry:find("mod._cos_score_peer_for_profile = function", 1, true), nil)
        H.equal(occurrences(source, "state.score_peer_for_profile = function"), 1)
        H.truthy(source:find("state.get_active_customization_backend_id()", 1, true))
        H.equal(source:find("\n        _active_customization_backend_id,", 1, true), nil)
        H.truthy(source:find('Managers.backend:get_interface("items")', 1, true))
        H.truthy(source:find("pcall(Managers.package.load", 1, true))
        H.truthy(source:find("pcall(Managers.package.unload", 1, true))
        H.equal(source:find("local Managers =", 1, true), nil)
        for _, forbidden in ipairs({
            "network_register", "network_send", "rpc_", "SimpleHusk",
            "_wield_slot", "create_equipment",
        }) do
            H.equal(source:find(forbidden, 1, true), nil,
                "preview owner captured foreign surface " .. forbidden)
        end
    end)

    H.test("Cosmetics preview runtime installs exact hooks once in stable order", function()
        local mod, deps, registrations = fixture()
        local owner = PreviewRuntime.install(mod, deps)

        local fresh_calls = { score = 0, getter = 0, bind = 0, scale = 0 }
        local fresh_deps
        fresh_deps = {
            la_bridge = { backend_to_armoury = {} },
            custom_hats = {},
            score_identity = {
                resolve_snapshot = function()
                    fresh_calls.score = fresh_calls.score + 1
                    return "fresh-peer", "fresh-score-policy"
                end,
            },
            gk_set = {},
            glow_preview_policy = {
                resolve_spawn = function(_, backend_id, _, resolve_item_type)
                    H.equal(resolve_item_type, fresh_deps.resolve_item_type)
                    return {
                        skin = nil,
                        has_skin = false,
                        preview_backend_id = backend_id,
                    }
                end,
                bind_spawned = function(_, _, picker, owner_map, dbg)
                    fresh_calls.bind = fresh_calls.bind + 1
                    H.equal(picker, fresh_deps.glow_picker)
                    H.equal(owner_map, mod._cos)
                    H.equal(dbg, fresh_deps.dbg)
                end,
            },
            glow_picker = { restore_runtime_for = function() return false end },
            dbg = function() end,
            dbg_alert = function() end,
            local_player_safe = function() end,
            apply_la_offhand_to_units = function() return false end,
            offhand_paint_mesh_ok = function() return false end,
            resolve_item_type = function() return "fresh-item-type" end,
            resolve_composed_appearance = function() end,
            glow_log = function() end,
            get_active_customization_backend_id = function()
                fresh_calls.getter = fresh_calls.getter + 1
                return "fresh-backend"
            end,
            get_mod = function() end,
            cim_preview = {
                capture_load = function() return false end,
                destroy = function() end,
                surface = function() return "illusion_browser" end,
                spawn = function() end,
                update = function() end,
            },
        }
        for key, value in pairs(deps) do
            H.truthy(fresh_deps[key] ~= value,
                "fresh dependency fixture reused " .. key)
        end

        local fresh_owner_map = {
            apply_unit_path_scale_hand = function()
                fresh_calls.scale = fresh_calls.scale + 1
            end,
            bind_glow_unit = function() end,
            apply_glow_override = function() end,
            apply_composed_shield_glow = function() end,
        }
        mod._cos = fresh_owner_map
        mod._cos_score_peer_for_profile = nil
        mod._cos_preview_runtime_owner = nil
        local again = PreviewRuntime.install(mod, fresh_deps)
        H.equal(owner, again)
        H.equal(owner.hook_count, 12)
        H.equal(#registrations, 12)

        local expected = {
            { "hook", "MenuWorldPreviewer", "equip_item" },
            { "hook", "HeroPreviewer", "equip_item" },
            { "hook", "TeamPreviewer", "_spawn_hero" },
            { "hook_safe", "TeamPreviewer", "cb_hero_unit_spawned_skin_preview" },
            { "hook_safe", "PlayerUnitCosmeticExtension", "extensions_ready" },
            { "hook_safe", "HeroPreviewer", "post_update" },
            { "hook", "HeroPreviewer", "_spawn_item" },
            { "hook", "MenuWorldPreviewer", "_spawn_item" },
            { "hook", "LootItemUnitPreviewer", "load_package" },
            { "hook_safe", "LootItemUnitPreviewer", "destroy" },
            { "hook", "LootItemUnitPreviewer", "spawn_units" },
            { "hook", "LootItemUnitPreviewer", "update" },
        }
        for index, row in ipairs(expected) do
            H.deep_equal({
                registrations[index].kind,
                registrations[index].class_name,
                registrations[index].method_name,
            }, row)
        end
        H.equal(owner.score_peer_for_profile, mod._cos_score_peer_for_profile)
        H.equal(owner, mod._cos_preview_runtime_owner)

        local export_keys = {}
        for key in pairs(owner) do export_keys[#export_keys + 1] = key end
        table.sort(export_keys)
        H.equal(table.concat(export_keys, ","),
            "hook_count,score_peer_for_profile")

        local dependency_fields = {
            la_bridge = "la_bridge",
            custom_hats = "custom_hats",
            score_identity = "score_identity",
            gk_set = "gk_set",
            glow_preview_policy = "glow_preview_policy",
            glow_picker = "glow_picker",
            dbg = "dbg",
            dbg_alert = "dbg_alert",
            local_player_safe = "local_player_safe",
            apply_la_offhand_to_units = "apply_la_offhand_to_units",
            offhand_paint_mesh_ok = "offhand_paint_mesh_ok",
            resolve_item_type = "resolve_item_type",
            resolve_composed_appearance = "resolve_composed_appearance",
            glow_log = "glow_log",
            get_active_customization_backend_id =
                "get_active_customization_backend_id",
            get_mod = "get_mod",
            cim_preview = "cim_preview",
        }
        for dependency, field in pairs(dependency_fields) do
            H.equal(mod._cos_preview_runtime_state[field], fresh_deps[dependency],
                "runtime state did not refresh " .. dependency)
        end

        local peer, source_kind = mod._cos_score_peer_for_profile(
            1, 1, { players_session_score = {} })
        H.equal(peer, "fresh-peer")
        H.equal(source_kind, "fresh-score-policy")
        H.equal(fresh_calls.score, 1)

        registrations[11].callback(function() return {} end, {
            _item = { data = {} },
        }, {})
        H.equal(fresh_calls.getter, 1)
        H.equal(fresh_calls.bind, 1)
        H.equal(fresh_calls.scale, 2)
        H.equal(mod._cos, fresh_owner_map)
    end)

    H.test("Cosmetics preview runtime resolves mutable customization identity at action time", function()
        local mod, deps, registrations, getter_calls = fixture()
        PreviewRuntime.install(mod, deps)
        H.equal(getter_calls(), 0)

        local callback
        for _, registration in ipairs(registrations) do
            if registration.class_name == "LootItemUnitPreviewer"
                and registration.method_name == "spawn_units" then
                callback = registration.callback
            end
        end
        H.truthy(callback)
        local units = callback(function() return {} end, {
            _item = { data = {} },
        }, {})
        H.equal(type(units), "table")
        H.equal(getter_calls(), 1)
    end)

    H.test("Cosmetics preview runtime routes CIM without generic LA scale", function()
        local mod, deps, registrations, getter_calls = fixture()
        local calls = { surface = 0, spawn = 0, scale = 0, paint = 0 }
        deps.cim_preview = {
            capture_load = function() return false end,
            destroy = function() end,
            surface = function(previewer)
                calls.surface = calls.surface + 1
                H.truthy(previewer._cim_preview_context)
                return "cim_preview"
            end,
            spawn = function(previewer, spawn_data, units, world)
                calls.spawn = calls.spawn + 1
                H.equal(spawn_data[1].unit_name, "units/la_shield_3p")
                H.equal(units[1], "unit")
                H.equal(world, "world")
            end,
            update = function() end,
        }
        mod._cos.apply_unit_path_scale_hand = function()
            calls.scale = calls.scale + 1
        end
        deps.apply_la_offhand_to_units = function()
            calls.paint = calls.paint + 1
        end
        PreviewRuntime.install(mod, deps)
        local callback = registrations[11].callback
        local units = callback(function() return { "unit" } end, {
            _cim_preview_context = { generation = 1 },
            _background_world = "world",
            _item = { data = {} },
        }, { { unit_name = "units/la_shield_3p" } })
        H.equal(units[1], "unit")
        H.equal(calls.surface, 1)
        H.equal(calls.spawn, 1)
        H.equal(calls.scale, 0)
        H.equal(calls.paint, 0)
        -- CIM is exact-context-only: even glow binding must not consult the
        -- generic customization identity fallback.
        H.equal(getter_calls(), 0)
    end)

    H.test("Cosmetics preview runtime never falls from CIM into generic parent load", function()
        local mod, deps, registrations = fixture()
        deps.cim_preview.capture_load = function()
            return false, "parent-lease-failed", true
        end
        PreviewRuntime.install(mod, deps)
        local callback = registrations[9].callback
        local native_calls = 0
        local saved_application = rawget(_G, "Application")
        _G.Application = {
            can_get = function(kind, path)
                H.equal(path, "units/la_shield_3p")
                return kind == "unit"
            end,
        }
        local previewer = { _packages_to_load = {}, _loaded_packages = {} }
        local ok, err = pcall(callback, function()
            native_calls = native_calls + 1
        end, previewer, "units/la_shield_3p")
        _G.Application = saved_application
        if not ok then error(err, 0) end
        H.equal(native_calls, 0)
        H.equal(previewer._packages_to_load["units/la_shield_3p"], true)
        H.equal(previewer._loaded_packages["units/la_shield_3p"], true)

        ok, err = pcall(callback, function()
            native_calls = native_calls + 1
        end, previewer, nil)
        if not ok then error(err, 0) end
        H.equal(native_calls, 0,
            "a malformed scoped package path must retain base without indexing nil")
    end)

    H.test("Cosmetics preview runtime stays below the cohesive-owner ceiling", function()
        local lines = 0
        for _ in source:gmatch("[^\n]+") do lines = lines + 1 end
        H.truthy(lines < 1500, "preview runtime owner must remain below 1500 lines")
    end)
end
