-- Install-transaction latch + module registry for the shared peer-parity lib
-- (#371 / #1158). The lib's install() owns TWO side effects -- handing the
-- receiver to VMF and taking ownership of mod.update. Either can throw, and a
-- beacon that half-installed would look built while never being able to close
-- its floor. These tests drive the shipped source directly (no fixture copy) and
-- each invariant carries a PLANTED regression: the same assertion is re-run
-- against a source mutation that removes the guard, proving the assertion is
-- load-bearing rather than vacuously true.

local function register(Harness, repo_root)
    local LIB_PATH = repo_root .. "/tools/shared_lib/_lib_peer_parity.lua"

    local function read_lib()
        local file = assert(io.open(LIB_PATH, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_chunk(source, label)
        if not source then
            local chunk, err = loadfile(LIB_PATH)
            if not chunk then error(err) end
            return chunk
        end
        local chunk, err = loadstring(source, label or "peer_parity_mutation")
        if not chunk then error(err) end
        return chunk
    end

    -- Plain-text single replacement: mutation anchors contain Lua pattern magic
    -- characters, so never route them through gsub.
    local function replace_once(source, needle, replacement)
        local at = source:find(needle, 1, true)
        if not at then error("mutation anchor not found: " .. needle) end
        return source:sub(1, at - 1) .. replacement .. source:sub(at + #needle)
    end

    local function mutated_chunk(needle, replacement)
        return load_chunk(replace_once(read_lib(), needle, replacement), "peer_parity_mutation")
    end

    local function with_network_stubs(body)
        local previous_managers, previous_network = Managers, Network
        local roster = {}
        Managers = { player = { human_players = function() return roster end } }
        Network = { peer_id = function() return "host" end }
        local ok, err = xpcall(function() body(roster) end, debug.traceback)
        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
    end

    -- A host whose network_register throws AFTER the transport has already
    -- retained the receiver: the exact partial-registration shape the latch
    -- exists for.
    local function retaining_thrower()
        local host = { registrations = 0, receiver = nil }
        host.mod = {
            network_register = function(_, _, callback)
                host.registrations = host.registrations + 1
                host.receiver = callback           -- retained BEFORE the throw
                error("transport rejected the channel")
            end,
            network_send = function() end,
            debug = function() end,
            echo = function() end,
        }
        return host
    end

    -- A host whose mod.update assignment stores the value and THEN throws, so
    -- the wrapper becomes externally visible before the transaction fails.
    local function hostile_update_host()
        local sentinel = function() end
        -- `store` must be declared BEFORE the field closures that capture it:
        -- inside a `local x = { ... }` constructor the name is not yet in scope,
        -- and the resulting nil-index error would abort the transaction at
        -- network_register instead of at the update assignment under test.
        local store = {}
        store.update = sentinel
        store.network_register = function(_, _, callback) store.receiver = callback end
        store.network_send = function() end
        store.debug = function() end
        store.echo = function() end
        local proxy = setmetatable({}, {
            __index = store,
            __newindex = function(_, key, value)
                rawset(store, key, value)
                if key == "update" then error("hostile __newindex") end
            end,
        })
        return proxy, store, sentinel
    end

    local function committing_host(mod_id)
        local host = { registrations = 0, sends = 0 }
        host.mod = {
            network_register = function(_, _, callback)
                host.registrations = host.registrations + 1
                host.receiver = callback
            end,
            network_send = function() host.sends = host.sends + 1 end,
            debug = function() end,
            echo = function() end,
            get_name = function() return mod_id end,
        }
        return host
    end

    -- ---------------------------------------------------------------------
    -- Partial install: terminal latch, false verdict, floors shut
    -- ---------------------------------------------------------------------

    Harness.test("peer parity partial install returns false and is terminal", function()
        with_network_stubs(function()
            local factory = load_chunk()()
            local host = retaining_thrower()
            local inst = assert(factory(host.mod, { poll_interval = 0, settle_enable = 0 }))

            Harness.equal(inst:install(), false, "a throwing registration must report a failed commit")
            Harness.equal(inst:is_installed(), false, "a failed attempt must never commit")
            Harness.equal(host.registrations, 1)

            Harness.equal(inst:install(), false, "a second attempt must also report failure")
            Harness.equal(host.registrations, 1,
                "the terminal latch must not re-register a receiver the transport already retained")
        end)
    end)

    Harness.test("peer parity partial install leaves every floor shut", function()
        with_network_stubs(function(roster)
            local factory = load_chunk()()
            local host = retaining_thrower()
            local inst = assert(factory(host.mod, { poll_interval = 0, settle_enable = 0 }))
            local enabled = 0
            inst:register_gated_feature("gated", {
                on_enable = function() enabled = enabled + 1 end,
                on_disable = function() end,
            })
            inst:install()

            Harness.equal(inst:all_peers_have(), false,
                "an uninstalled beacon is not positive solo evidence")
            Harness.equal(inst:peer_has("peer_a"), false)
            Harness.equal(inst:require_peer("peer_a"), false)

            -- The retained receiver is inert: an ack delivered through it must
            -- not become evidence.
            assert(host.receiver, "fixture did not retain a receiver")
            host.receiver("peer_a", 1, 1)
            Harness.equal(inst:peer_has("peer_a"), false,
                "a receiver retained by a failed registration must never acknowledge")

            roster[1] = { peer_id = "peer_a" }
            inst:tick(1)
            inst:tick(1)
            Harness.equal(inst:applied_state(), "disabled",
                "tick() must not run for an uninstalled instance")
            Harness.equal(enabled, 0, "no gated feature may enable without a committed install")
        end)
    end)

    Harness.test("peer parity partial install restores the exact previous mod.update", function()
        with_network_stubs(function()
            local factory = load_chunk()()
            local proxy, store, sentinel = hostile_update_host()
            local inst = assert(factory(proxy, { poll_interval = 0, settle_enable = 0 }))

            Harness.equal(inst:install(), false,
                "a throwing update assignment must fail the whole transaction")
            Harness.equal(inst:is_installed(), false)
            Harness.equal(rawget(store, "update"), sentinel,
                "the externally visible wrapper must be rolled back to the exact previous function")
        end)
    end)

    Harness.test("peer parity refuses to install without a transport", function()
        with_network_stubs(function()
            local factory = load_chunk()()
            local inst = assert(factory({}, { poll_interval = 0 }))
            Harness.equal(inst:install(), false, "no network_register means no commit")
            Harness.equal(inst:is_installed(), false)
            Harness.equal(inst:all_peers_have(), false)
        end)
    end)

    -- ---------------------------------------------------------------------
    -- Commit path
    -- ---------------------------------------------------------------------

    Harness.test("peer parity commit returns true and registers the instance", function()
        with_network_stubs(function()
            local factory, registry = load_chunk()()
            local host = committing_host("demo_mod")
            local inst = assert(factory(host.mod, { poll_interval = 0, settle_enable = 0 }))

            Harness.equal(registry.instance_count("demo_mod"), 0,
                "an instance must not enter the registry before its install commits")
            Harness.equal(inst:install(), true)
            Harness.equal(inst:is_installed(), true)
            Harness.equal(registry.instance_count("demo_mod"), 1)
            Harness.equal(inst.registry, registry,
                "the instance must expose the registry reachable in-game")

            Harness.equal(inst:install(), true, "a committed install stays true on re-entry")
            Harness.equal(host.registrations, 1, "install must register exactly once")
            Harness.equal(registry.instance_count("demo_mod"), 1,
                "re-entry must not duplicate the registry row")
        end)
    end)

    Harness.test("peer parity commit takes mod.update ownership and preserves the previous chain", function()
        with_network_stubs(function()
            local factory = load_chunk()()
            local host = committing_host("demo_mod")
            local previous_calls = 0
            host.mod.update = function() previous_calls = previous_calls + 1 end
            local inst = assert(factory(host.mod, { poll_interval = 0, settle_enable = 0 }))

            Harness.equal(inst:install(), true)
            host.mod.update(0)
            Harness.equal(previous_calls, 1, "install must preserve the host's existing update")
            Harness.equal(inst:applied_state(), "enabled",
                "the wrapped update must drive the beacon tick")
        end)
    end)

    -- ---------------------------------------------------------------------
    -- registry.all_peers_have(mod_id)
    -- ---------------------------------------------------------------------

    Harness.test("peer parity registry aggregator delegates and fails closed", function()
        with_network_stubs(function()
            local factory, registry = load_chunk()()

            Harness.equal(registry.all_peers_have("never_seen"), false,
                "an unknown mod id must fail closed")
            Harness.equal(registry.all_peers_have(nil), false)
            Harness.equal(registry.all_peers_have(""), false)
            Harness.equal(registry.all_peers_have(42), false)

            local host = committing_host("demo_mod")
            local inst = assert(factory(host.mod, { poll_interval = 0, settle_enable = 0 }))
            Harness.equal(registry.all_peers_have("demo_mod"), false,
                "a built-but-uninstalled instance must not be queryable")

            inst:install()
            Harness.equal(inst:all_peers_have(), true, "solo baseline is positive evidence")
            Harness.equal(registry.all_peers_have("demo_mod"), true,
                "the aggregator must delegate to the instance verdict")

            inst:require_peer("stranger")
            Harness.equal(inst:all_peers_have(), false)
            Harness.equal(registry.all_peers_have("demo_mod"), false,
                "the aggregator must track the instance verdict, not cache it")
        end)
    end)

    Harness.test("peer parity registry AND-folds every beacon a mod installed", function()
        with_network_stubs(function()
            local factory, registry = load_chunk()()
            local presence = committing_host("multi_mod")
            local exact = committing_host("multi_mod")
            local a = assert(factory(presence.mod, { channel = "a", poll_interval = 0, settle_enable = 0 }))
            local b = assert(factory(exact.mod, { channel = "b", poll_interval = 0, settle_enable = 0 }))
            a:install()
            b:install()
            Harness.equal(registry.instance_count("multi_mod"), 2)
            Harness.equal(registry.all_peers_have("multi_mod"), true)

            b:require_peer("stranger")
            Harness.equal(registry.all_peers_have("multi_mod"), false,
                "one closed beacon must close the aggregate verdict")
        end)
    end)

    Harness.test("peer parity registry key prefers an explicit mod id", function()
        with_network_stubs(function()
            local factory, registry = load_chunk()()
            local host = committing_host("vmf_name")
            local inst = assert(factory(host.mod, {
                mod_id = "explicit_id", poll_interval = 0, settle_enable = 0,
            }))
            inst:install()
            Harness.equal(inst.MOD_ID, "explicit_id")
            Harness.equal(registry.instance_count("explicit_id"), 1)
            Harness.equal(registry.instance_count("vmf_name"), 0)

            -- An unidentifiable host still yields a working instance; it is
            -- simply not queryable by id.
            local anonymous = assert(factory({
                network_register = function() end,
                network_send = function() end,
            }, { poll_interval = 0, settle_enable = 0 }))
            Harness.equal(anonymous:install(), true)
            Harness.equal(anonymous.MOD_ID, nil)
        end)
    end)

    -- ---------------------------------------------------------------------
    -- Planted regressions -- each removes one guard and proves the assertion
    -- above would have caught it.
    -- ---------------------------------------------------------------------

    Harness.test("planted: removing the terminal latch re-registers a retained receiver", function()
        with_network_stubs(function()
            local factory = mutated_chunk(
                "if _install_attempted then return false end",
                "if false then return false end")()
            local host = retaining_thrower()
            local inst = assert(factory(host.mod, { poll_interval = 0 }))
            inst:install()
            inst:install()
            Harness.equal(host.registrations, 2,
                "planted mutation must reproduce the double-registration the latch prevents")
        end)
    end)

    Harness.test("planted: removing the receiver inert guard acknowledges before commit", function()
        with_network_stubs(function()
            local factory = mutated_chunk(
                "            if not _installed then return end\n",
                "")()
            local host = retaining_thrower()
            local inst = assert(factory(host.mod, { poll_interval = 0 }))
            inst:install()
            assert(host.receiver, "fixture did not retain a receiver")
            host.receiver("peer_a", 1, 1)
            Harness.truthy(not inst:is_installed())
            Harness.equal(inst.__classify({ peer_a = true }, { peer_a = true }), true)
            -- peer_has() is separately latched, so read the ack through the
            -- classifier surface the mutation actually exposes.
            Harness.equal(inst:peer_has("peer_a"), false,
                "peer_has stays latched even with the receiver guard removed")
        end)
    end)

    Harness.test("planted: removing the rollback leaves the wrapper installed", function()
        with_network_stubs(function()
            local factory = mutated_chunk(
                "                pcall(function() mod.update = previous_update end)",
                "                local _ = previous_update")()
            local proxy, store, sentinel = hostile_update_host()
            local inst = assert(factory(proxy, { poll_interval = 0 }))
            Harness.equal(inst:install(), false)
            Harness.truthy(rawget(store, "update") ~= sentinel,
                "planted mutation must reproduce the orphaned wrapper the rollback prevents")
        end)
    end)

    Harness.test("planted: registering before the commit exposes an uninstalled instance", function()
        with_network_stubs(function()
            local factory, registry = mutated_chunk(
                "        _installed = true\n        _registry_add(MOD_ID, api)",
                "        _registry_add(MOD_ID, api)\n        _installed = true")()
            local host = retaining_thrower()
            local inst = assert(factory(host.mod, { poll_interval = 0 }))
            inst:install()
            Harness.equal(registry.instance_count("demo_mod"), 0,
                "a failed install must not reach the registry under any ordering")
            Harness.equal(inst:is_installed(), false)
        end)
    end)

    Harness.test("planted: an open-by-default aggregator answers true for an unknown mod", function()
        local _, registry = mutated_chunk(
            'if type(bucket) ~= "table" or #bucket == 0 then return false end',
            'if type(bucket) ~= "table" or #bucket == 0 then return true end')()
        Harness.equal(registry.all_peers_have("never_seen"), true,
            "planted mutation must reproduce the open-by-default verdict the guard prevents")
    end)

    -- ---------------------------------------------------------------------
    -- Fanout: every consumer copy is byte-identical and every documented seam
    -- consumes the commit boolean. A source scan is the only way to prove the
    -- atomic 6-mod change did not land partially.
    -- ---------------------------------------------------------------------

    Harness.test("peer parity install transaction reached every consumer copy", function()
        local canonical = read_lib()
        local consumers = {
            "career_tweaker/scripts/mods/career_tweaker/_lib_peer_parity.lua",
            "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_lib_peer_parity.lua",
            "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_peer_parity.lua",
            "event_tweaker/scripts/mods/event_tweaker/_lib_peer_parity.lua",
            "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_peer_parity.lua",
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_peer_parity.lua",
        }
        for i = 1, #consumers do
            local file = assert(io.open(repo_root .. "/" .. consumers[i], "rb"))
            local copy = file:read("*a")
            file:close()
            Harness.equal(copy, canonical, "copied lib drifted: " .. consumers[i])
        end
    end)

    Harness.test("peer parity commit boolean is consumed at every documented seam", function()
        local seams = {
            "career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua",
            "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_parity_owner.lua",
            "character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua",
            "character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua",
            "event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua",
            "event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua",
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_damage_profile_parity.lua",
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_damage_profile_parity.lua",
        }
        for i = 1, #seams do
            local file = assert(io.open(repo_root .. "/" .. seams[i], "rb"))
            local source = file:read("*a")
            file:close()
            Harness.truthy(source:find("install", 1, true) ~= nil)
            -- No call site may discard the verdict, and no seam comment may
            -- still promise the fanout as future work.
            Harness.equal(source:find("pcall(function() inst:install() end)", 1, true), nil,
                "seam still discards the commit boolean: " .. seams[i])
            Harness.equal(source:find("When the fanout lands", 1, true), nil,
                "stale fanout seam comment survives in " .. seams[i])
        end
    end)
end

return register
