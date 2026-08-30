return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local parent_path = root .. "_ct_regression.lua"
    local child_path = root .. "_ct_regression_resource_safety.lua"
    local child_runtime_path =
        "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression_resource_safety"

    local expected_order = {
        "mission_catalog_localization_format_safe_564",
        "pickup_dump_helpers_forward_declared",
        "variadic_hooks_arity_preserved",
        "home_brewer_add_buff_multireturn_preserved",
        "belakor_forced_rarity_survives_unpack_bound",
        "trait_filter_restores_on_error",
        "dup_chip_no_current_node_fallback",
        "chunk_sends_paced_not_bursted",
        "ct_meta_ammo_server_auth_grant_249",
        "cursed_chest_reconcile_132",
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
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

    local CLEAR = {}

    local function with_globals(values, fn)
        local saved = {}
        for key, value in pairs(values) do
            saved[key] = {
                present = rawget(_G, key) ~= nil,
                value = rawget(_G, key),
            }
            if value == CLEAR then
                rawset(_G, key, nil)
            else
                rawset(_G, key, value)
            end
        end
        local ok, result = pcall(fn)
        for key, box in pairs(saved) do
            if box.present then
                rawset(_G, key, box.value)
            else
                rawset(_G, key, nil)
            end
        end
        if not ok then error(result, 0) end
        return result
    end

    local function reconcile_plan(appearance, pickup_set, cap, alive, waiting)
        local alive_units = {}
        for _, unit in ipairs(appearance) do
            if alive(unit) then alive_units[#alive_units + 1] = unit end
        end
        local over = math.max(0, #alive_units - cap)
        local prune = {}
        for i = #alive_units, 1, -1 do
            local unit = alive_units[i]
            if #prune >= over then break end
            if pickup_set[unit] and waiting(unit) then
                prune[#prune + 1] = unit
            end
        end
        return {
            alive_n = #alive_units,
            over_n = over,
            prune = prune,
            unprunable_n = over - #prune,
        }
    end

    local function healthy_mod()
        local mod = {
            update = function() end,
            _ct_extend_arity_for_forced_rarity = function(n)
                return math.max(n, 8)
            end,
            _ct_dup_chip_node_key_resolution = "final_node_selected>vote>nil",
            _ct_wire_safe = function() return true end,
            _ct_ammo_guard_core = {},
            _ct_chest132 = {
                pickup_chest = function() end,
                RECONCILE_MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298",
            },
        }
        mod._ct_ammo_guard_core.grant_plan = function(is_server, wire_safe, existing, target)
            if existing >= target then return "none", 0 end
            if not is_server then return "defer_to_server", 0 end
            return wire_safe and "networked" or "local", target - existing
        end
        mod.dofile = function(_, path)
            if path == "scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog" then
                return {
                    build_loc_entries = function()
                        return { safe = { en = "100%% complete" } }
                    end,
                }
            end
            if path == "scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_count_audit_core" then
                return { reconcile_plan = reconcile_plan }
            end
            error("unexpected resource-safety dofile: " .. tostring(path))
        end
        return mod
    end

    local function install_checks(mod, ctx)
        local names, checks, seen = {}, {}, {}
        mod._ct_rt_register = function(name, check)
            H.equal(type(name), "string")
            H.equal(type(check), "function")
            H.equal(seen[name], nil, "duplicate resource-safety check")
            seen[name] = true
            names[#names + 1] = name
            checks[name] = check
        end
        local installer = assert(loadfile(child_path))()
        installer(mod, ctx)
        return names, checks
    end

    H.test("CT resource-safety owner is preloaded and invoked at the frozen tail", function()
        local parent = read(parent_path)
        local child = read(child_path)
        H.equal(count_plain(parent, child_runtime_path), 1)
        local load_at = assert(parent:find(child_runtime_path, 1, true))
        local first_registration = assert(parent:find("_rt_register(", 1, true))
        local localization_at = assert(parent:find(
            '_rt_register("localization_format_safe"', 1, true))
        local install_at = assert(parent:find(
            "_install_resource_safety_checks(mod, ctx)", 1, true))
        H.truthy(load_at < first_registration,
            "child chunk must load before the parent can register a partial suite")
        H.truthy(localization_at < install_at,
            "resource-safety checks moved from the original suite tail")
        H.equal(count_plain(parent, "_install_resource_safety_checks(mod, ctx)"), 1)
        H.equal(count_plain(parent, "_rt_register("), 62)
        H.equal(count_plain(child, "_rt_register("), 10)

        local previous = 0
        for _, name in ipairs(expected_order) do
            H.equal(parent:find('_rt_register("' .. name .. '"', 1, true), nil,
                name .. " retained a second parent owner")
            local at = assert(child:find('_rt_register("' .. name .. '"', 1, true),
                name .. " missing from the child owner")
            H.truthy(previous < at, name .. " registration order changed")
            previous = at
        end
        H.equal(child:find('_rt_register("localization_format_safe"', 1, true), nil)
        H.equal(child:find("mod:hook(", 1, true), nil)
        H.equal(child:find("mod:network_register(", 1, true), nil)
        H.equal(child:find("mod.update =", 1, true), nil)
    end)

    H.test("CT resource-safety installer validates before registering its suffix", function()
        local installer = assert(loadfile(child_path))()
        local registrations = 0
        local mod = {
            _ct_rt_register = function() registrations = registrations + 1 end,
        }
        H.equal(pcall(installer, nil, {}), false)
        H.equal(registrations, 0)
        H.equal(pcall(installer, mod, nil), false)
        H.equal(registrations, 0)
        H.equal(pcall(installer, {}, {}), false)
        H.equal(registrations, 0)

        local names, checks = install_checks(healthy_mod(), {})
        H.deep_equal(names, expected_order)
        with_globals({
            _dump_pickup_system_state = CLEAR,
            _dump_pickup_spawners_verbose = CLEAR,
        }, function()
            H.equal(type(checks.pickup_dump_helpers_forward_declared()), "string",
                "missing captured dump helpers must remain a runtime verdict")
            H.equal(type(checks.variadic_hooks_arity_preserved()), "string",
                "missing marker must remain a runtime verdict")
        end)
    end)

    H.test("CT resource-safety checks pass deterministic healthy fixtures", function()
        with_globals({
            _dump_pickup_system_state = CLEAR,
            _dump_pickup_spawners_verbose = CLEAR,
            CT_HOME_BREWER_MULTIRETURN_MARKER =
                "home_brewer_add_buff:capture_returns_unpack_v0.7.203",
            _CT_CHUNK_PACED_SEND_MARKER = "chunk_sends:enqueue_drain_paced_v0.7.163",
            _ct_enqueue_chunk = function() end,
            _CT_CHUNK_DRAIN_BUDGET = 1,
            _ct_chunk_send_queue = {},
            CT_META_AMMO_SERVER_AUTH_MARKER =
                "meta_ammo:server_authoritative_stack_grant_v0.7.298",
        }, function()
            local dump_a, dump_b = function() end, function() end
            local ctx = {
                dump_pickup_system_state = dump_a,
                dump_pickup_spawners_verbose = dump_b,
                variadic_arity_marker = "unpack_arity:select_count_v0.7.133",
            }
            local names, checks = install_checks(healthy_mod(), ctx)
            H.deep_equal(names, expected_order)

            -- The seam must capture the entry's original values, not reread a
            -- context table that another owner could mutate after installation.
            ctx.dump_pickup_system_state = nil
            ctx.dump_pickup_spawners_verbose = nil
            ctx.variadic_arity_marker = "mutated-after-install"
            for _, name in ipairs(expected_order) do
                local ok, verdict = pcall(checks[name])
                H.truthy(ok, name .. " raised under the healthy fixture: " .. tostring(verdict))
                H.equal(verdict, nil, name .. " failed the healthy fixture")
            end
        end)
    end)

    H.test("CT resource-safety resource and late-bound failures stay observable", function()
        local mod = healthy_mod()
        local _, checks = install_checks(mod, {
            dump_pickup_system_state = function() end,
            dump_pickup_spawners_verbose = function() end,
            variadic_arity_marker = "unpack_arity:select_count_v0.7.133",
        })

        mod.dofile = function(_, path)
            if path == "scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog" then
                return { build_loc_entries = function()
                    return { unsafe = { en = "raw 5% value" } }
                end }
            end
            error("unexpected test dofile: " .. tostring(path))
        end
        local verdict = checks.mission_catalog_localization_format_safe_564()
        H.truthy(type(verdict) == "string" and verdict:find("unsafe", 1, true),
            "generated localization format failure disappeared")

        mod.dofile = function() error("catalog unavailable") end
        H.equal(checks.mission_catalog_localization_format_safe_564(),
            "mission catalog localization builder unavailable")

        mod.dofile = function()
            return { build_loc_entries = function() error("builder exploded") end }
        end
        H.equal(pcall(checks.mission_catalog_localization_format_safe_564), false,
            "builder errors must retain their original propagation")

        mod._ct_dup_chip_node_key_resolution = "final_node_selected>vote>current_node_key"
        verdict = checks.dup_chip_no_current_node_fallback()
        H.truthy(type(verdict) == "string" and verdict:find("DUP-CHIP", 1, true),
            "late-bound duplicate-chip drift was not detected")

        with_globals({
            _CT_CHUNK_PACED_SEND_MARKER = "wrong",
            _ct_enqueue_chunk = function() end,
            _CT_CHUNK_DRAIN_BUDGET = 1,
            _ct_chunk_send_queue = {},
        }, function()
            verdict = checks.chunk_sends_paced_not_bursted()
            H.truthy(type(verdict) == "string" and verdict:find("PACED-SEND", 1, true),
                "late-bound paced-send drift was not detected")
        end)
    end)
end
