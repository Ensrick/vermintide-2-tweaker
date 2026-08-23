local function register(H, repo_root)
    local policy_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_wire_policy.lua"
    local Policy = assert(loadfile(policy_path))()
    local runtime_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_wire_runtime.lua"
    local Runtime = assert(loadfile(runtime_path))()
    local catalog_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_lib_wire_catalog.lua"
    local Catalog = assert(loadfile(catalog_path))()

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
        local a, err_a, names_a = Catalog.build_identity(
            "crt.buff_templates", registry_a, lookup)
        local b, err_b, names_b = Catalog.build_identity(
            "crt.buff_templates", registry_b, lookup)
        H.equal(err_a, nil)
        H.equal(err_b, nil)
        H.equal(a, b, "registry insertion order must not affect identity")
        H.equal(#names_a, 3)
        H.deep_equal(names_a, names_b)

        local shifted = {
            crt_a = 1575, crt_z = 1600, victor_mod = 1601,
            [1575] = "crt_a", [1600] = "crt_z", [1601] = "victor_mod",
        }
        local shifted_identity = assert(Catalog.build_identity(
            "crt.buff_templates", registry_a, shifted))
        H.truthy(shifted_identity ~= a,
            "same names at different process-local ids must not establish parity")

        local changed_names = { crt_a = true, crt_z = true, victor_other = true }
        local changed_lookup = {
            crt_a = 1574, crt_z = 1600, victor_other = 1601,
            [1574] = "crt_a", [1600] = "crt_z", [1601] = "victor_other",
        }
        local changed_identity = assert(Catalog.build_identity(
            "crt.buff_templates", changed_names, changed_lookup))
        H.truthy(changed_identity ~= a,
            "same ids assigned to different names must not establish parity")

        lookup[1600] = "wrong_reverse_name"
        local invalid, invalid_err = Catalog.build_identity(
            "crt.buff_templates", registry_a, lookup)
        H.equal(invalid, nil)
        H.truthy(invalid_err:find("lookup%-mismatch") ~= nil)
    end)

    H.test("CRT #776 optional runtime gate preserves settings and supports GUT load order", function()
        local ids = { "setting_a", "setting_b" }
        local spec = assert(Policy.runtime_gate_spec("crt", ids, function()
            return false, "catalog unavailable"
        end))
        ids[1] = "mutated"
        H.deep_equal(spec.setting_ids, { "setting_a", "setting_b" },
            "runtime gate must own a defensive setting-id copy")
        local available, reason = spec.evaluate()
        H.equal(available, false)
        H.equal(reason, "catalog unavailable")

        local calls, captured = {}, nil
        local ok, err = Policy.try_register_runtime_gate(function(name)
            calls[#calls + 1] = name
            if name == "gut" then
                return { mod_tweaker = {
                    register_runtime_gate = function(_, gate_id, gate_spec)
                        captured = { id = gate_id, spec = gate_spec }
                        return true
                    end,
                } }
            end
        end, "crt:776:exact-buff-catalog", spec)
        H.equal(ok, true)
        H.equal(err, nil)
        H.deep_equal(calls, { "gut_dev", "gut" })
        H.equal(captured.id, "crt:776:exact-buff-catalog")
        H.equal(captured.spec, spec)

        local absent, absent_err = Policy.try_register_runtime_gate(
            function() return nil end, "crt:776:exact-buff-catalog", spec)
        H.equal(absent, false)
        H.equal(absent_err, "mod-tweaker-unavailable")
        H.deep_equal(spec.setting_ids, { "setting_a", "setting_b" },
            "registration must never change saved setting identities")

        local fallback_calls = {}
        local fallback_ok = Policy.try_register_runtime_gate(function(name)
            fallback_calls[#fallback_calls + 1] = name
            if name == "gut_dev" then
                return { mod_tweaker = { register_runtime_gate = function()
                    error("malformed dev GUI")
                end } }
            end
            return { mod_tweaker = { register_runtime_gate = function() return true end } }
        end, "crt:776:exact-buff-catalog", spec)
        H.equal(fallback_ok, true,
            "throwing dev presentation owner must be contained before stable fallback")
        H.deep_equal(fallback_calls, { "gut_dev", "gut" })
    end)

    H.test("CRT #1158 runtime gate retry is bounded and permits late success", function()
        local state = Policy.runtime_gate_retry_step({},
            function() error("spec failure") end, function() return true end)
        H.equal(state.attempts, 1)
        H.equal(state.registered, false)
        H.equal(state.terminal, false, "a throwing spec builder must not retire the retry")

        state = Policy.runtime_gate_retry_step(state,
            function() return "malformed" end, function() return true end)
        H.equal(state.attempts, 2)
        H.equal(state.registered, false)

        local thrown = Policy.runtime_gate_retry_step({},
            function() return {} end, function() error("register failure") end)
        H.equal(thrown.registered, false)
        H.equal(thrown.terminal, false,
            "a throwing GUI owner must be contained, not escape the update path")

        -- Terminal exactly at the cap, never before, with no further attempts.
        local absent = {}
        for i = 1, Policy.RUNTIME_GATE_MAX_ATTEMPTS do
            absent = Policy.runtime_gate_retry_step(absent,
                function() return {} end, function() return false end)
            H.equal(absent.attempts, i)
            H.equal(absent.terminal, i == Policy.RUNTIME_GATE_MAX_ATTEMPTS,
                "retry must retire at the cap and not one attempt early or late")
        end
        H.equal(Policy.RUNTIME_GATE_MAX_ATTEMPTS, 30)
        H.equal(absent.registered, false)
        local frozen = absent.attempts
        local register_calls = 0
        Policy.runtime_gate_retry_step(absent, function() return {} end,
            function() register_calls = register_calls + 1; return true end)
        H.equal(absent.attempts, frozen, "terminal retry owner must stay retired")
        H.equal(register_calls, 0, "a retired retry must not keep polling get_mod()")

        -- A GUT that loads late still registers, and that also retires the retry.
        local late = {}
        for _ = 1, 5 do
            late = Policy.runtime_gate_retry_step(late,
                function() return {} end, function() return false end)
        end
        H.equal(late.terminal, false)
        late = Policy.runtime_gate_retry_step(late,
            function() return {} end, function() return true end)
        H.equal(late.registered, true)
        H.equal(late.terminal, true)
        H.equal(late.attempts, 6)
    end)

    H.test("CRT #1158 catalog_intact rejects a lookup row that lost one direction", function()
        local names = { "crt_a", "crt_z" }
        local ids = { 1574, 1600 }
        local function fresh()
            return { crt_a = 1574, crt_z = 1600, [1574] = "crt_a", [1600] = "crt_z" }
        end
        H.equal(Policy.catalog_intact(names, ids, fresh(), 2), true)

        -- The planted defect: forward name->id still resolves exactly as it did
        -- when build_identity fingerprinted it, but the reverse row was
        -- reassigned by a later writer. build_identity ran at boot and would
        -- never see this; only the live floor can.
        local one_way = fresh()
        one_way[1600] = "someone_elses_buff"
        H.equal(Policy.catalog_intact(names, ids, one_way, 2), false,
            "a name that no longer round-trips must invalidate the advertised identity")

        local moved = fresh()
        moved.crt_z, moved[1600], moved[1601] = 1601, nil, "crt_z"
        H.equal(Policy.catalog_intact(names, ids, moved, 2), false,
            "an id that moved after boot must invalidate the advertised identity")

        local dropped = fresh()
        dropped.crt_z, dropped[1600] = nil, nil
        H.equal(Policy.catalog_intact(names, ids, dropped, 2), false)

        H.equal(Policy.catalog_intact(names, ids, fresh(), 3), false,
            "a count that disagrees with the fingerprinted name set must fail closed")
        H.equal(Policy.catalog_intact(names, { 1574 }, fresh(), 2), false,
            "a missing boot-time id snapshot entry must fail closed")
        H.equal(Policy.catalog_intact(names, ids, nil, 2), false,
            "an absent NetworkLookup.buff_templates must fail closed")
        H.equal(Policy.catalog_intact(names, ids, fresh(), 0), false)
        H.equal(Policy.catalog_intact({ "crt_a" }, { 1574.5 },
            { crt_a = 1574.5, [1574.5] = "crt_a" }, 1), false,
            "a non-integer wire id is not a legal lookup identity")
    end)

    H.test("CRT #1158 composite floor is false when any single conjunct fails", function()
        local function beacon(overrides)
            local b = {
                _installed = true, _state = "enabled", _peers = true,
                is_installed  = function(self) return self._installed end,
                applied_state = function(self) return self._state end,
                all_peers_have = function(self) return self._peers end,
            }
            for k, v in pairs(overrides or {}) do b[k] = v end
            return b
        end
        local function intact() return true end
        local function broken() return false end

        H.equal(Policy.wire_safe(beacon(), intact), true)
        H.equal(Policy.wire_live(beacon(), intact), true)

        -- Conjunct 1: transport never committed.
        H.equal(Policy.wire_safe(beacon({ _installed = false }), intact), false)
        H.equal(Policy.wire_live(beacon({ _installed = false }), intact), false)
        -- Conjunct 2: catalog no longer exact.
        H.equal(Policy.wire_safe(beacon(), broken), false)
        H.equal(Policy.wire_live(beacon(), broken), false)
        -- Conjunct 3: peer-set evidence.
        H.equal(Policy.wire_safe(beacon({ _state = "disabled" }), intact), false)
        H.equal(Policy.wire_live(beacon({ _peers = false }), intact), false)

        -- No beacon at all (factory failed) and a beacon missing its accessors.
        H.equal(Policy.wire_safe(nil, intact), false)
        H.equal(Policy.wire_live(nil, intact), false)
        H.equal(Policy.wire_safe({}, intact), false)
        H.equal(Policy.wire_live({}, intact), false)
        H.equal(Policy.wire_safe(beacon(), nil), false)

        -- A throwing accessor or catalog check must fail closed, never propagate.
        H.equal(Policy.wire_safe(beacon({
            is_installed = function() error("boom") end }), intact), false)
        H.equal(Policy.wire_safe(beacon({
            applied_state = function() error("boom") end }), intact), false)
        H.equal(Policy.wire_live(beacon({
            all_peers_have = function() error("boom") end }), intact), false)
        H.equal(Policy.wire_safe(beacon(), function() error("boom") end), false)

        -- Truthy-but-not-true must not satisfy a safety conjunct.
        H.equal(Policy.wire_safe(beacon({ _installed = "yes" }), intact), false)
        H.equal(Policy.wire_live(beacon({ _peers = "yes" }), intact), false)
        H.equal(Policy.wire_safe(beacon(), function() return "yes" end), false)

        -- The reason the live read is not expressed as the settled read: the
        -- beacon's applied state is refreshed by a 0.5s poll while the roster is
        -- evaluated per call, so a peer that just joined without crt is visible
        -- to wire_live one poll interval before wire_safe reacts. A per-send
        -- guard routed through wire_safe would emit into that window (#425).
        local racing = beacon({ _state = "enabled", _peers = false })
        H.equal(Policy.wire_safe(racing, intact), true)
        H.equal(Policy.wire_live(racing, intact), false,
            "per-send guard must see the un-acked peer before the settled state does")
    end)

    H.test("CRT #776 runtime gate pins all eleven network-unsafe setting rows", function()
        local regression = read(
            "career_tweaker/scripts/mods/career_tweaker/_crt_regression.lua")
        local begin_at = assert(regression:find(
            "local _CRT_NETWORK_UNSAFE_ALL_EXPECTED = {", 1, true))
        local end_at = assert(regression:find("\n}", begin_at, true))
        local block = regression:sub(begin_at, end_at)
        local actual = {}
        for setting_id in block:gmatch('"([%w_]+)"') do
            actual[#actual + 1] = setting_id
        end
        H.deep_equal(actual, {
            "maidenguard_focused_spirit_ignore_chip_damage",
            "rework_bw_unchained_abandon_innate_flame_unending",
            "rework_bw_unchained_natural_talent_ranged",
            "rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit",
            "rework_es_mercenary_blade_barrier_60x_minus_10_on_hit",
            "rework_es_mercenary_enhanced_training_tiered",
            "rework_es_questingknight_virtue_of_impetuous_buffed",
            "rework_we_maidenguard_dance_of_blades",
            "rework_we_maidenguard_focused_spirit_stacks",
            "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
            "trn_wh_priest_prayer_movement_speed",
        })
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
        local balance = require("crt_source").combined(repo_root)
        local runtime = read("career_tweaker/scripts/mods/career_tweaker/_crt_wire_runtime.lua")
        local hooks = read("career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua")
        H.truthy(entry:find("local CRT_RPC_SCHEMA = 3", 1, true))
        H.truthy(entry:find('build_identity(', 1, true))
        H.truthy(entry:find('"crt.buff_templates"', 1, true))
        H.truthy(entry:find("mod._crt_mod_registered_buff_names", 1, true))
        H.truthy(entry:find("NetworkLookup and NetworkLookup.buff_templates", 1, true))
        H.truthy(entry:find("wire_identity = wire_identity", 1, true))
        H.truthy(entry:find("_crt_wire_transport_identity = wire_identity", 1, true))
        H.truthy(entry:find('mod:hook_safe("GameNetworkManager", "remove_peer"', 1, true))
        -- #1158 install-transaction floor: the beacon is only published after the
        -- lib reports a committed transport, and the floors delegate to the pure
        -- policy rather than re-deriving the conjuncts in the entry file.
        H.truthy(entry:find("wire_catalog_intact", 1, true))
        H.truthy(entry:find("pcall(inst.is_installed, inst)", 1, true))
        H.truthy(entry:find("installed ~= true", 1, true))
        -- #1158 fanout: install() now returns the commit boolean, and the entry
        -- consumes it alongside is_installed() rather than relying on the
        -- state read alone.
        H.truthy(entry:find("committed ~= true", 1, true),
            "CRT must consume install()'s commit boolean")
        H.truthy(entry:find("wire_policy.catalog_intact(", 1, true))
        H.truthy(entry:find("wire_policy.wire_safe(", 1, true))
        H.truthy(entry:find("wire_policy.wire_live(", 1, true))
        H.truthy(entry:find("runtime_gate_retry_step", 1, true))
        local install_at = assert(entry:find("local install_ok, committed = pcall(inst.install, inst)", 1, true))
        local publish_at = assert(entry:find("mod._crt_peer_parity = inst", 1, true))
        H.truthy(install_at < publish_at,
            "the commit check must precede publishing the beacon to call sites")
        H.truthy(entry:find("_crt_wire_disconnect_guard = true", 1, true))
        H.equal(runtime:find("wrap_parity_transport", 1, true), nil,
            "CRT must not retain a bespoke exact transport proxy")
        H.truthy(entry:find("network_unsafe_setting_ids", 1, true))
        H.truthy(entry:find("runtime_gate_spec", 1, true))
        H.truthy(entry:find("try_register_runtime_gate", 1, true))
        H.truthy(entry:find(":776:exact-buff-catalog", 1, true))
        H.truthy(entry:find("Unavailable until every player has the same Tweaker: Careers buff catalog.", 1, true))
        local gate_at = assert(entry:find("local runtime_gate_id", 1, true))
        local gate_end = assert(entry:find("WARNING peer-parity factory failed", gate_at, true))
        H.equal(entry:sub(gate_at, gate_end):find("mod:set(", 1, true), nil,
            "optional runtime gate must not rewrite saved settings")

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
        H.truthy(floor:find("mod._crt_wire_safe() == true", 1, true),
            "#1158 receiver floor must require this peer's own composite floor")
    end)

    H.test("CRT #1158 every authoritative parity read routes through the floor", function()
        local balance_src = read(
            "career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua")
        local tourney = read(
            "career_tweaker/scripts/mods/career_tweaker/career_tweaker_tourney.lua")

        -- The lock: no gameplay owner may reach past the floor to the beacon.
        -- Re-introducing a bare mod._crt_peer_parity read in either apply engine
        -- is exactly the bypass this slice exists to close, so it fails here.
        H.equal(balance_src:find("mod._crt_peer_parity", 1, true), nil,
            "balance apply engine must not read the beacon directly")
        H.equal(tourney:find("mod._crt_peer_parity", 1, true), nil,
            "tourney apply engine must not read the beacon directly")

        H.truthy(balance_src:find("mod._crt_wire_live() == true", 1, true),
            "per-send guard must keep the instant roster read")
        H.truthy(balance_src:find("mod._crt_wire_safe() == true", 1, true),
            "feature gate must use the settled composite")
        H.truthy(tourney:find("mod._crt_wire_safe() == true", 1, true))

        -- The two reads must stay distinct owners: collapsing the live guard onto
        -- the settled read reopens the poll-interval send window (#425).
        H.equal(count_plain(balance_src, "mod._crt_wire_live() == true"), 1)
        H.equal(count_plain(balance_src, "mod._crt_wire_safe() == true"), 1)
    end)
end

return register
