local function register(H, repo_root)
    local policy_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_wire_policy.lua"
    local Policy = assert(loadfile(policy_path))()
    local runtime_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_wire_runtime.lua"
    local Runtime = assert(loadfile(runtime_path))()

    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local function count_plain(text, needle)
        local count, at = 0, 1
        while true do
            local found = text:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    H.test("CRT #776 wire identity includes every name and numeric lookup id", function()
        local registry_a = { crt_z = true, crt_a = true, victor_mod = true }
        local registry_b = { victor_mod = true, crt_a = true, crt_z = true }
        local lookup = {
            crt_a = 1574, crt_z = 1600, victor_mod = 1601,
            [1574] = "crt_a", [1600] = "crt_z", [1601] = "victor_mod",
        }
        local a, err_a, names_a = Policy.build_wire_identity(registry_a, lookup)
        local b, err_b, names_b = Policy.build_wire_identity(registry_b, lookup)
        H.equal(err_a, nil)
        H.equal(err_b, nil)
        H.equal(a, b, "registry insertion order must not affect identity")
        H.equal(#names_a, 3)
        H.deep_equal(names_a, names_b)

        local shifted = {
            crt_a = 1575, crt_z = 1600, victor_mod = 1601,
            [1575] = "crt_a", [1600] = "crt_z", [1601] = "victor_mod",
        }
        local shifted_identity = assert(Policy.build_wire_identity(registry_a, shifted))
        H.truthy(shifted_identity ~= a,
            "same names at different process-local ids must not establish parity")

        local changed_names = { crt_a = true, crt_z = true, victor_other = true }
        local changed_lookup = {
            crt_a = 1574, crt_z = 1600, victor_other = 1601,
            [1574] = "crt_a", [1600] = "crt_z", [1601] = "victor_other",
        }
        local changed_identity = assert(Policy.build_wire_identity(changed_names, changed_lookup))
        H.truthy(changed_identity ~= a,
            "same ids assigned to different names must not establish parity")

        lookup[1600] = "wrong_reverse_name"
        local invalid, invalid_err = Policy.build_wire_identity(registry_a, lookup)
        H.equal(invalid, nil)
        H.truthy(invalid_err:find("lookup%-mismatch") ~= nil)
    end)

    H.test("CRT #776 Impetuous effects remain one refreshing 20-second stack", function()
        local buff = Policy.make_timed_stat_buff("crt_test", "attack_speed", 0.2)
        H.equal(buff.duration, 20)
        H.equal(buff.max_stacks, 1)
        H.equal(buff.refresh_durations, true)

        local state = Policy.refresh_timed_state(nil, 100)
        H.equal(state.stack_count, 1)
        H.equal(state.end_time, 120)
        H.truthy(not Policy.is_expired(state, 119.999))
        H.truthy(Policy.is_expired(state, 120))

        state = Policy.refresh_timed_state(state, 110)
        H.equal(state.stack_count, 1, "refresh must not add a second writer/stack")
        H.equal(state.start_time, 110)
        H.equal(state.end_time, 130)
        H.truthy(not Policy.is_expired(state, 129.999))
        H.truthy(Policy.is_expired(state, 130))
    end)

    H.test("CRT #776 parity transport accepts only the exact catalog identity", function()
        local receiver
        local sent_identity
        local accepted = 0
        local fake_mod = {
            network_send = function(_, _, _, _, _, identity)
                sent_identity = identity
            end,
            network_register = function(_, _, callback)
                receiver = callback
            end,
            debug = function() end,
            echo = function() end,
            localize = function(_, value) return value end,
        }
        local proxy = assert(Runtime.wrap_parity_transport(fake_mod, "catalog:exact"))
        proxy:network_send("channel", "others", 2, 0)
        H.equal(sent_identity, "catalog:exact")

        local forgotten, required = 0, 0
        local instance = {
            forget_peer = function(_, peer)
                if peer == "peer-a" then forgotten = forgotten + 1 end
            end,
            require_peer = function(_, peer)
                if peer == "peer-a" then required = required + 1 end
            end,
        }
        proxy:_bind_parity_instance(instance)
        proxy:network_register("channel", function()
            accepted = accepted + 1
        end)

        receiver("peer-a", 2, 1, nil)
        receiver("peer-a", 2, 1, "catalog:other")
        H.equal(accepted, 0, "missing and mismatched identities must not acknowledge")
        H.equal(forgotten, 1, "repeated mismatch must revoke at most once until recovery")
        H.equal(required, 1)

        receiver("peer-a", 2, 1, "catalog:exact")
        H.equal(accepted, 1, "exact identity reaches the established parity classifier")
        receiver("peer-a", 2, 1, "catalog:changed")
        H.equal(forgotten, 2, "a later drift must revoke an earlier exact acknowledgement")
        H.equal(required, 2)
    end)

    H.test("CRT #776 receiver floor covers all attached positive ids and collisions", function()
        local timed = { buffs = { { duration = 20 } } }
        local permanent = { buffs = { { stat_buff = "power_level" } } }

        for _, server_id in ipairs({ 12, 13, 9 }) do
            local decision = Policy.rpc_add_buff_decision({
                resolves_to_crt = true,
                peer_catalog_exact = true,
                server_buff_id = server_id,
                template = timed,
            })
            H.equal(decision, "drop_server_controlled_duration",
                "positive server id from an attached crash must not reach vanilla")
        end

        H.equal(Policy.rpc_add_buff_decision({
            resolves_to_crt = true,
            peer_catalog_exact = false,
            server_buff_id = 13,
            template = permanent,
        }), "drop_catalog_mismatch", "unrelated host id collision must fail closed")

        H.equal(Policy.rpc_add_buff_decision({
            resolves_to_crt = true,
            peer_catalog_exact = true,
            server_buff_id = 7,
            template = permanent,
        }), "accept", "exact catalog plus duration-free server buff remains native")

        H.equal(Policy.rpc_add_buff_decision({
            resolves_to_crt = false,
            peer_catalog_exact = false,
            server_buff_id = 13,
            template = timed,
        }), "accept", "CRT must not intercept unrelated local names")

        H.equal(Policy.rpc_add_buff_decision({
            resolves_to_crt = true,
            peer_catalog_exact = true,
            server_buff_id = 0,
            template = timed,
        }), "accept", "ordinary non-server-controlled timed buff remains legal")
    end)

    H.test("CRT #776 production uses exact parity, one receiver floor, and native timed sync", function()
        local entry = read("career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua")
        local balance = read("career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua")
        local runtime = read("career_tweaker/scripts/mods/career_tweaker/_crt_wire_runtime.lua")
        local hooks = read("career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua")
        H.truthy(entry:find("local CRT_RPC_SCHEMA = 2", 1, true))
        H.truthy(entry:find("build_wire_identity(", 1, true))
        H.truthy(entry:find("mod._crt_mod_registered_buff_names", 1, true))
        H.truthy(entry:find("NetworkLookup and NetworkLookup.buff_templates", 1, true))
        H.truthy(entry:find("wrap_parity_transport(mod, wire_identity)", 1, true))
        H.truthy(entry:find("_crt_wire_transport_identity = wire_identity", 1, true))
        H.truthy(runtime:find("remote_identity ~= identity", 1, true))
        H.truthy(runtime:find("parity_instance.forget_peer", 1, true))
        H.truthy(runtime:find("parity_instance.require_peer", 1, true))

        H.equal(count_plain(balance, "buff_func = \"crt_wire_safe_add_timed_buff\""), 2)
        H.equal(count_plain(balance, "wire_policy.make_timed_stat_buff("), 2)
        H.equal(count_plain(balance, "wire_runtime.ensure_timed_proc("), 1)
        local wrapper_at = assert(runtime:find("PF.crt_wire_safe_add_timed_buff = function", 1, true))
        local wrapper = runtime:sub(wrapper_at)
        local parity_at = assert(wrapper:find("parity_live()", 1, true))
        local synced_at = assert(wrapper:find("add_buff_synced", 1, true))
        H.truthy(parity_at < synced_at, "#425 exact parity must precede timed emission")
        H.equal(wrapper:find("PF.add_buff(", 1, true), nil,
            "timed route must have no unsafe generic fallback")
        H.equal(count_plain(wrapper, "buff_system:add_buff_synced("), 1,
            "one proc invocation must have one writer")
        H.truthy(wrapper:find("policy.TIMED_SYNC_TYPE", 1, true))

        H.equal(count_plain(hooks, 'mod:hook("BuffSystem", "rpc_add_buff"'), 1)
        H.equal(count_plain(hooks, 'mod:hook("BuffSystem", "hot_join_sync"'), 1,
            "#425 hot-join filter must remain installed exactly once")
        local floor_at = assert(hooks:find('mod:hook("BuffSystem", "rpc_add_buff"', 1, true))
        local floor_end = assert(hooks:find("mod._crt_rpc_add_buff_floor_installed = true", floor_at, true))
        local floor = hooks:sub(floor_at, floor_end)
        H.truthy(floor:find("rpc_add_buff_decision", 1, true))
        H.truthy(floor:find("if decision ~= \"accept\"", 1, true))
        H.truthy(floor:find("return", floor:find("if decision", 1, true), true))
        H.truthy(hooks:find("_crt_rpc_floor_logged", 1, true),
            "receiver diagnostics must be bounded")
    end)
end

return register
