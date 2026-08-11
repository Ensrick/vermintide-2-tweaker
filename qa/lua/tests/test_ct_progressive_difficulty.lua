return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_difficulty.lua")

    local vanilla_difficulties = {
        "normal", "hard", "harder", "hardest", "cataclysm",
        "cataclysm_2", "cataclysm_3", "versus_base",
    }
    local vanilla_lookup = {}
    for i, key in ipairs(vanilla_difficulties) do
        vanilla_lookup[i], vanilla_lookup[key] = key, i
    end

    H.test("CT #460 difficulty steps only on maps three and five", function()
        H.equal(policy.step_count(0), 0)
        H.equal(policy.step_count(1), 0)
        H.equal(policy.step_count(2), 1)
        H.equal(policy.step_count(3), 1)
        H.equal(policy.step_count(4), 2)
        H.equal(policy.step_count(100), 2)
        H.equal(policy.difficulty("hardest", 1, vanilla_difficulties, vanilla_lookup), "hardest")
        H.equal(policy.difficulty("hardest", 2, vanilla_difficulties, vanilla_lookup), "cataclysm")
        H.equal(policy.difficulty("hardest", 3, vanilla_difficulties, vanilla_lookup), "cataclysm")
        H.equal(policy.difficulty("hardest", 4, vanilla_difficulties, vanilla_lookup), "cataclysm_2")
    end)

    H.test("CT #460 cap uses Cata 5 when registered and never Versus", function()
        local difficulties = {
            "normal", "hard", "harder", "hardest", "cataclysm",
            "cataclysm_2", "cataclysm_3", "cataclysm_4", "cataclysm_5", "versus_base",
        }
        local lookup = {}
        for i, key in ipairs(difficulties) do lookup[i], lookup[key] = key, i end
        H.equal(policy.difficulty("cataclysm_3", 2, difficulties, lookup), "cataclysm_4")
        H.equal(policy.difficulty("cataclysm_3", 4, difficulties, lookup), "cataclysm_5")
        H.equal(policy.difficulty("cataclysm_5", 100, difficulties, lookup), "cataclysm_5")
        H.equal(policy.difficulty("cataclysm_3", 100, vanilla_difficulties, vanilla_lookup), "cataclysm_3")
    end)

    H.test("CT #460 never jumps across a missing registered tier", function()
        local difficulties = {
            "normal", "hard", "harder", "hardest", "cataclysm",
            "cataclysm_2", "cataclysm_3", "cataclysm_5", "versus_base",
        }
        local lookup = {}
        for i, key in ipairs(difficulties) do lookup[i], lookup[key] = key, i end
        H.equal(policy.difficulty("cataclysm_3", 2, difficulties, lookup), "cataclysm_3")
        H.equal(policy.difficulty("cataclysm_3", 4, difficulties, lookup), "cataclysm_3")
    end)

    H.test("CT #460 coin reduction begins on map three and clamps input", function()
        H.equal(policy.coin_multiplier(2, -25, 1), 2)
        H.equal(policy.coin_multiplier(2, -25, 2), 1.5)
        H.equal(policy.coin_multiplier(2, -25, 4), 1.5)
        H.equal(policy.coin_multiplier(2, -100, 2), 0)
        H.equal(policy.coin_multiplier(2, -200, 2), 0)
        H.equal(policy.coin_multiplier(2, 50, 2), 2)
    end)

    H.test("CT #460 hot join sends and consumes one original-tier message", function()
        local callbacks, hooks, events = {}, {}, {}
        local old_managers = rawget(_G, "Managers")
        _G.Managers = { mechanism = { server_peer_id = function() return "host" end } }
        local mod = {}
        function mod:network_register(name, callback) callbacks[name] = callback end
        function mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        function mod:network_send(name, peer_id, schema, start_key)
            events[#events + 1] = table.concat({ "send", name, peer_id, schema, start_key }, ":")
        end

        policy.install_hot_join(mod, 7)
        callbacks.ct_progdiff_start("host", 6, "hardest")
        H.equal(mod._ct_progdiff_pending_host_start, nil)
        callbacks.ct_progdiff_start("not-host", 7, "hardest")
        H.equal(mod._ct_progdiff_pending_host_start, nil)
        callbacks.ct_progdiff_start("host", 7, "hardest")
        H.equal(mod._ct_progdiff_pending_host_start, "hardest")

        local hook = hooks["DeusMechanism.sync_mechanism_data"]
        local mechanism = { _deus_run_controller = {
            _ct_progdiff_start = "hardest",
            _run_state = { is_server = function() return true end },
        } }
        local result = hook(function()
            events[#events + 1] = "vanilla"
            return "ok"
        end, mechanism, "peer-2", true)
        H.equal(result, "ok")
        H.equal(events[1], "send:ct_progdiff_start:peer-2:7:hardest")
        H.equal(events[2], "vanilla")
        _G.Managers = old_managers
    end)

    H.test("CT #460 production wires both advanced host-effective settings", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        local policy_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_difficulty.lua"
        local pf = assert(io.open(policy_path, "rb"))
        local policy_source = pf:read("*a")
        pf:close()
        -- #1159 wave 14: the ramp and its per-controller base moved verbatim into
        -- _ct_run_creation_owner (setup_run establishes the base, so the two are
        -- one mechanism). Needles are byte-identical; only the file moved. The
        -- coin-reduction reader stays in the entry, on the
        -- on_soft_currency_picked_up hook.
        local owner_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua"
        local of = assert(io.open(owner_path, "rb"))
        local owner_source = of:read("*a")
        of:close()
        H.truthy(owner_source:find('effective_setting("progressive_difficulty_increase")', 1, true))
        H.truthy(source:find('effective_setting("progressive_coin_reduction")', 1, true))
        H.truthy(source:find("mod._ct_progressive_policy", 1, true))
        H.truthy(source:find("policy.coin_multiplier", 1, true))
        H.truthy(owner_source:find("mod._ct_progressive_policy.difficulty", 1, true))
        H.truthy(owner_source:find("mod._ct_progdiff_pending_host_start or args[2]", 1, true))
        H.truthy(owner_source:find("(self and self._ct_progdiff_start) or base", 1, true))
        -- The ramp base is per-CONTROLLER, never a mod-global: an overlapping or
        -- replaced controller must not leak its start tier into a later run. Both
        -- files must be clean of the mod-scoped form.
        H.equal(source:find("mod._ct_progdiff_start", 1, true), nil)
        H.equal(owner_source:find("mod._ct_progdiff_start", 1, true), nil)
        H.truthy(owner_source:find("install_hot_join(mod, CT_RPC_SCHEMA)", 1, true))
        H.equal(source:find("install_hot_join(", 1, true), nil,
            "a second hot-join install would double-register the ct_progdiff_start RPC")
        H.truthy(policy_source:find('mod:network_register("ct_progdiff_start"', 1, true))
        H.truthy(policy_source:find('mod:hook("DeusMechanism", "sync_mechanism_data"', 1, true))
        H.truthy(policy_source:find('mod:network_send("ct_progdiff_start", peer_id', 1, true))
    end)
end
