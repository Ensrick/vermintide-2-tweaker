local function register(H, repo_root)
    local contract_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_wire_contract.lua"
    local Contract = assert(loadfile(contract_path))()

    local function lookup(rows)
        local out = {}
        for i = 1, #rows do
            out[rows[i]] = i
            out[i] = rows[i]
        end
        return out
    end

    local function profiles_for(fallbacks)
        local profiles = {}
        for custom, fallback in pairs(fallbacks) do
            profiles[custom] = {
                charge_value = "light_attack",
                source = fallback,
                power_distribution = { attack = 0.25, impact = 0.1 },
            }
        end
        return profiles
    end

    H.test("WT #431 v2 identity binds order, numeric ids, and semantic profiles", function()
        local fallbacks_a = { wt_beta = "vanilla_b", wt_alpha = "vanilla_a" }
        local fallbacks_b = { wt_alpha = "vanilla_a", wt_beta = "vanilla_b" }
        local catalog = lookup({ "vanilla_a", "vanilla_b", "wt_alpha", "wt_beta" })
        local profiles_a = profiles_for(fallbacks_a)
        local profiles_b = profiles_for(fallbacks_b)
        local a, err_a, names_a = Contract.build_wire_identity(
            fallbacks_a, catalog, profiles_a)
        local b, err_b, names_b = Contract.build_wire_identity(
            fallbacks_b, catalog, profiles_b)
        H.equal(err_a, nil)
        H.equal(err_b, nil)
        H.equal(a, b)
        H.truthy(a:find("wt431-v2:", 1, true) == 1)
        H.deep_equal(names_a, { "wt_alpha", "wt_beta" })
        H.deep_equal(names_a, names_b)

        local reordered = lookup({ "vanilla_a", "vanilla_b", "wt_beta", "wt_alpha" })
        local shifted = assert(Contract.build_wire_identity(
            fallbacks_a, reordered, profiles_a))
        H.truthy(shifted ~= a,
            "same names at different process-local ids must not establish parity")

        local missing = lookup({ "vanilla_a", "vanilla_b", "wt_alpha" })
        local identity, err = Contract.build_wire_identity(
            fallbacks_a, missing, profiles_a)
        H.equal(identity, nil)
        H.truthy(err:find("custom%-lookup%-mismatch") ~= nil)

        local with_extra = {
            wt_alpha = "vanilla_a", wt_beta = "vanilla_b", wt_gamma = "vanilla_c",
        }
        local extra_catalog = lookup({
            "vanilla_a", "vanilla_b", "vanilla_c", "wt_alpha", "wt_beta", "wt_gamma",
        })
        local expanded = assert(Contract.build_wire_identity(
            with_extra, extra_catalog, profiles_for(with_extra)))
        H.truthy(expanded ~= a,
            "an extra WT-owned generated profile must change exact identity")

        profiles_b.wt_alpha.power_distribution.attack = 0.26
        local changed = assert(Contract.build_wire_identity(
            fallbacks_b, catalog, profiles_b))
        H.truthy(changed ~= a,
            "same names and ids with different gameplay content must not acknowledge")

        H.equal(Contract.build_wire_identity(fallbacks_a, catalog, nil), nil,
            "v2 must never silently create an identity without semantic profiles")
    end)

    H.test("WT #431 semantic digest is deterministic and rejects unsafe values", function()
        local left = {
            z = { [2] = "two", [1] = "one" },
            a = { impact = 0.1, attack = 0.25 },
            enabled = true,
        }
        local right = {
            enabled = true,
            a = { attack = 0.25, impact = 0.1 },
            z = { [1] = "one", [2] = "two" },
        }
        H.equal(Contract.profile_content_digest(left),
            Contract.profile_content_digest(right),
            "table insertion order must not affect semantic identity")
        right.a.attack = 0.251
        H.truthy(Contract.profile_content_digest(left)
            ~= Contract.profile_content_digest(right))

        local cycle = {}
        cycle.self = cycle
        H.equal(Contract.profile_content_digest(cycle), nil)
        H.equal(select(2, Contract.profile_content_digest(cycle)), "profile-cycle")
        H.equal(Contract.profile_content_digest({ callback = function() end }), nil)
    end)

    H.test("WT #431 semantic digest preserves signed zero and bounded failure modes", function()
        local negative_zero = -math.ldexp(0, 0)
        H.equal(1 / negative_zero, -math.huge,
            "test host must preserve an explicitly constructed negative zero")
        local positive_digest = assert(Contract.profile_content_digest({ value = 0 }))
        local negative_digest = assert(Contract.profile_content_digest(
            { value = negative_zero }))
        H.truthy(positive_digest ~= negative_digest,
            "+0 and -0 must not establish the same semantic wire identity")

        for _, row in ipairs({
                { value = math.huge, error = "profile-number-nonfinite" },
                { value = -math.huge, error = "profile-number-nonfinite" },
                { value = 0 / 0, error = "profile-number-nonfinite" },
            }) do
            local digest, digest_error = Contract.profile_content_digest(
                { value = row.value })
            H.equal(digest, nil)
            H.equal(digest_error, row.error)
        end

        local nonfinite_key = { [math.huge] = true }
        H.equal(select(2, Contract.profile_content_digest(nonfinite_key)),
            "profile-key-number-nonfinite")

        local cycle = {}
        cycle.child = cycle
        H.equal(select(2, Contract.profile_content_digest(cycle)), "profile-cycle")

        local deep, cursor = {}, nil
        cursor = deep
        for _ = 1, Contract.MAX_PROFILE_DIGEST_DEPTH do
            cursor.child = {}
            cursor = cursor.child
        end
        H.equal(select(2, Contract.profile_content_digest(deep)), "profile-too-deep")

        -- One root plus a key and value node per entry crosses the bound by
        -- exactly one without relying on elapsed time or host performance.
        local large = {}
        for index = 1, Contract.MAX_PROFILE_DIGEST_NODES / 2 do
            large[index] = index
        end
        H.equal(select(2, Contract.profile_content_digest(large)), "profile-too-large")
    end)

    H.test("WT #431 numeric digest is independent of the Windows decimal locale", function()
        local original_locale = os.setlocale(nil, "numeric")
        local ok, outcome = xpcall(function()
            H.truthy(os.setlocale("C", "numeric") ~= nil)
            local profile = {
                positive = 0.25,
                negative = -1.5,
                small = 1.23456789012345e-200,
                large_integer = 9007199254740991,
            }
            local c_digest = assert(Contract.profile_content_digest(profile))
            local localized_locale
            for _, candidate in ipairs({
                    "German_Germany.1252", "French_France.1252" }) do
                if os.setlocale(candidate, "numeric")
                        and string.format("%.2f", 1.25):find(",", 1, true) then
                    localized_locale = candidate
                    break
                end
            end
            H.truthy(localized_locale ~= nil,
                "the Windows Lua test host must expose a comma-decimal locale")
            H.equal(Contract.profile_content_digest(profile), c_digest,
                "peer fingerprints must not depend on Windows regional settings")
        end, debug.traceback)
        if original_locale then os.setlocale(original_locale, "numeric") end
        if not ok then error(outcome, 0) end
    end)

    H.test("WT #431 sender fallback is unconditional and setting-free", function()
        local fallbacks = { wt_custom = "vanilla" }
        H.equal(Contract.safe_profile_name(fallbacks, "wt_custom", false), "vanilla")
        H.equal(Contract.safe_profile_name(fallbacks, "wt_custom", nil), "vanilla")
        H.equal(Contract.safe_profile_name(fallbacks, "wt_custom", true), "wt_custom")
        H.equal(Contract.safe_profile_name(fallbacks, "unowned", false), "unowned")
    end)

    H.test("WT #431 transport requires exact identity and a current challenge", function()
        local receiver, accepted = nil, 0
        local sent = {}
        local fake_mod = {
            network_send = function(_, channel, recipient, schema, is_reply,
                    identity, epoch, query, echo)
                sent[#sent + 1] = {
                    channel = channel, recipient = recipient, schema = schema,
                    is_reply = is_reply, identity = identity, epoch = epoch,
                    query = query, echo = echo,
                }
            end,
            network_register = function(_, _, callback) receiver = callback end,
            debug = function() end,
            echo = function() end,
            localize = function(_, value) return value end,
        }
        local proxy = assert(Contract.wrap_parity_transport(fake_mod,
            "wt431-v2:2:12345678:abcdef01",
            { session_epoch = "local-e1", schema = 2 }))
        local forgotten, required = 0, 0
        local parity = {
            forget_peer = function(_, peer)
                if peer == "peer-a" then forgotten = forgotten + 1 end
            end,
            require_peer = function(_, peer)
                if peer == "peer-a" then required = required + 1 end
            end,
        }
        proxy:_bind_parity_instance(parity)
        proxy:network_register("presence", function() accepted = accepted + 1 end)

        proxy:network_send("presence", "peer-a", 2, 0)
        local query = sent[#sent]
        H.truthy(type(query.query) == "string" and query.query ~= "")
        receiver("peer-a", 2, 1, "wt431-v2:2:12345678:abcdef01",
            "remote-e1", "", query.query)
        H.equal(accepted, 1, "exact identity plus current challenge must pass")

        parity:forget_peer("peer-a")
        receiver("peer-a", 2, 1, "wt431-v2:2:12345678:abcdef01",
            "remote-e1", "", query.query)
        H.equal(accepted, 1, "delayed pre-disconnect reply must not re-ack")
        H.truthy(forgotten >= 2)
        H.truthy(required >= 1)

        proxy:network_send("presence", "peer-a", 2, 0)
        local fresh = sent[#sent]
        receiver("peer-a", 2, 1, "wt431-v2:2:12345678:abcdef01",
            "remote-e2", "", fresh.query)
        H.equal(accepted, 2, "fresh epoch and fresh challenge may re-establish parity")

        receiver("peer-a", 2, 0, "wt431-v2:2:00000000:00000000",
            "remote-e3", "remote-q", "")
        H.equal(accepted, 2, "catalog mismatch must never reach presence classifier")
    end)

    H.test("WT #431 retired peer history is globally bounded across churn", function()
        local identity = "wt431-v2:2:12345678:abcdef01"
        local receiver, accepted = nil, 0
        local sent = {}
        local fake_mod = {
            network_send = function(_, channel, recipient, schema, is_reply,
                    remote_identity, epoch, query, echo)
                sent[#sent + 1] = {
                    channel = channel, recipient = recipient, schema = schema,
                    is_reply = is_reply, identity = remote_identity, epoch = epoch,
                    query = query, echo = echo,
                }
            end,
            network_register = function(_, _, callback) receiver = callback end,
            debug = function() end,
            echo = function() end,
            localize = function(_, value) return value end,
        }
        local proxy = assert(Contract.wrap_parity_transport(fake_mod, identity,
            { session_epoch = "local-churn", schema = 2 }))
        local parity = {
            forget_peer = function() end,
            require_peer = function() end,
        }
        proxy:_bind_parity_instance(parity)
        proxy:network_register("presence", function() accepted = accepted + 1 end)

        local churn = Contract.MAX_RETIRED_PEERS + 7
        for i = 1, churn do
            local peer = "peer-" .. i
            receiver(peer, 2, 0, identity, "epoch-" .. i, "remote-q-" .. i, "")
            parity:forget_peer(peer)
        end
        H.equal(accepted, churn)
        H.equal(proxy:_wt431_retired_peer_count(), Contract.MAX_RETIRED_PEERS,
            "unique peer churn must not grow retired state without bound")
        H.equal(proxy:_wt431_is_epoch_retired("peer-1", "epoch-1"), false,
            "FIFO eviction must remove the oldest retired peer deterministically")
        H.equal(proxy:_wt431_is_epoch_retired("peer-" .. churn, "epoch-" .. churn), true,
            "the newest retired peer must remain protected")

        receiver("peer-" .. churn, 2, 0, identity, "epoch-" .. churn,
            "retired-query", "")
        H.equal(accepted, churn, "a retained retired epoch must remain rejected")

        proxy:network_send("presence", "peer-1", 2, 0)
        receiver("peer-1", 2, 1, identity, "epoch-1", "", "remote-q-1")
        H.equal(accepted, churn,
            "an evicted peer's stale reply must still fail the current challenge")

        proxy:network_send("presence", "peer-1", 2, 0)
        local fresh = sent[#sent]
        receiver("peer-1", 2, 1, identity, "epoch-rejoined", "", fresh.query)
        H.equal(accepted, churn + 1,
            "an evicted peer may rejoin only with a fresh epoch and challenge")
        H.equal(proxy:_wt431_retired_peer_count(), Contract.MAX_RETIRED_PEERS,
            "rejoin churn must preserve the global bound")
    end)

    H.test("WT #431 parity payload stays below VMF's 500-character cap", function()
        H.truthy(Contract.max_json_envelope_length() <= Contract.MAX_VMF_JSON_LENGTH)
    end)

    H.test("WT #431 legacy and exact protocol generations cannot acknowledge", function()
        local factory = assert(loadfile(repo_root
            .. "/tools/shared_lib/_lib_peer_parity.lua"))()
        local handlers = {}
        local function fake_mod(peer_id)
            return {
                network_register = function(_, channel, callback)
                    handlers[channel] = handlers[channel] or {}
                    handlers[channel][peer_id] = callback
                end,
                network_send = function(_, channel, recipient, ...)
                    local by_peer = handlers[channel] or {}
                    if recipient == "others" then
                        for target, callback in pairs(by_peer) do
                            if target ~= peer_id then callback(peer_id, ...) end
                        end
                    elseif by_peer[recipient] then
                        by_peer[recipient](peer_id, ...)
                    end
                end,
                debug = function() end,
                echo = function() end,
                localize = function(_, value) return value end,
            }
        end

        local legacy_mod = fake_mod("legacy")
        local exact_mod = fake_mod("exact")
        local legacy = assert(factory(legacy_mod, {
            channel = "wt_peer_parity_present", schema = 1,
            poll_interval = 0, settle_enable = 0,
        }))
        local proxy = assert(Contract.wrap_parity_transport(exact_mod,
            "wt431-v2:2:12345678:abcdef01",
            { session_epoch = "exact-e1", schema = 2 }))
        local exact = assert(factory(proxy, {
            channel = "wt_damage_profiles_exact_v2", schema = 2,
            poll_interval = 0, settle_enable = 0,
        }))
        proxy:_bind_parity_instance(exact)
        legacy:install()
        exact:install()
        legacy:require_peer("exact")
        exact:require_peer("legacy")
        H.equal(legacy:peer_has("exact"), false,
            "legacy host must not mistake an exact peer for presence-only parity")
        H.equal(exact:peer_has("legacy"), false,
            "exact peer must not accept a legacy presence acknowledgement")
    end)

    H.test("WT #431 Dual Axes profiles register while the action repoint fails closed", function()
        local Axe = assert(loadfile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_axe_balance.lua"))()
        local action = { kind = "sweep", damage_profile = "axe_light" }
        local weapons = { dual_wield_axes_template_1 = {
            actions = { action_one = { light_attack_left = action } },
        } }
        local profiles = { axe_light = { cleave_distribution = { attack = 1, impact = 2 } } }
        local registered, fallbacks = {}, {}
        local function clone(value)
            if type(value) ~= "table" then return value end
            local copy = {}
            for key, child in pairs(value) do copy[key] = clone(child) end
            return copy
        end
        local state = Axe.new()
        state:apply_dual_cleave(true, weapons, profiles, {}, clone,
            function(name) registered[name] = true end, fallbacks, false)
        H.equal(action.damage_profile, "axe_light",
            "unconfirmed exact catalog must retain the vanilla source")
        H.equal(fallbacks.wt_axe_cleave_axe_light, "axe_light")
        H.equal(registered.wt_axe_cleave_axe_light, true,
            "catalog registration must not depend on the local toggle/gate")

        state:apply_dual_cleave(true, weapons, profiles, {}, clone,
            nil, fallbacks, true)
        H.equal(action.damage_profile, "wt_axe_cleave_axe_light")
        state:apply_dual_cleave(true, weapons, profiles, {}, clone,
            nil, fallbacks, false)
        H.equal(action.damage_profile, "axe_light",
            "parity loss must restore the exact vanilla source")
    end)

    H.test("WT #431 registers only exact affected settings with Mod Tweaker", function()
        local captured_id, captured_spec
        local fake_tweaker = {
            register_runtime_gate = function(_, gate_id, spec)
                captured_id, captured_spec = gate_id, spec
                return true
            end,
        }
        local available = false
        local spec = assert(Contract.runtime_gate_spec("wt", function()
            return available, "catalog mismatch"
        end))
        local ok = Contract.try_register_runtime_gate(function(name)
            if name == "gut_dev" then return { mod_tweaker = fake_tweaker } end
        end, "wt:431:test", spec)
        H.truthy(ok)
        H.equal(captured_id, "wt:431:test")
        H.equal(captured_spec.mod_id, "wt")
        H.deep_equal(captured_spec.setting_ids, Contract.RUNTIME_GATE_SETTINGS)

        local Gates = assert(loadfile(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_runtime_gates.lua"))()
        H.truthy(Gates.register(captured_id, captured_spec))
        local blocked, reason = Gates.status("wt", "wt_dual_axes_cleave")
        H.equal(blocked, true)
        H.equal(reason, "catalog mismatch")
        local pending = { wt = { wt_dual_axes_cleave = true, wt_cog_hammer_heavy_speed_nerf = true } }
        H.equal(Gates.prune_pending(pending, { "wt" }), 1)
        H.equal(pending.wt.wt_dual_axes_cleave, nil)
        H.equal(pending.wt.wt_cog_hammer_heavy_speed_nerf, true)

        available = true
        H.equal(Gates.status("wt", "wt_dual_axes_cleave"), false)
    end)

    -- ---------------------------------------------------------------
    -- Application floor (#1158): installed + enabled + source-qualified live
    -- catalog integrity. A policy or lookup failure must substitute a PROVEN
    -- RESIDENT vanilla profile or drop the RPC -- never retain the custom id.
    -- ---------------------------------------------------------------

    H.test("WT #431 application floor never wires a custom id on any failure", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))
        local custom_id = live.wt_custom
        local vanilla_id = live.vanilla_a
        H.equal(Contract.catalog_intact(snapshot, fallbacks, live, profiles), true)

        -- The ONLY branch that keeps the custom id: gate open AND catalog intact.
        local id, disposition = Contract.profile_id_for_send(false, custom_id,
            true, snapshot, fallbacks, live, profiles)
        H.equal(id, custom_id)
        H.equal(disposition, "custom")

        -- Every failure axis, one at a time. None may return the custom id.
        local cases = {
            { name = "gate closed",       exact = false, snap = snapshot, fb = fallbacks, lk = live, p = profiles },
            { name = "gate nil",          exact = nil,   snap = snapshot, fb = fallbacks, lk = live, p = profiles },
            { name = "gate not boolean",  exact = 1,     snap = snapshot, fb = fallbacks, lk = live, p = profiles },
            { name = "snapshot missing",  exact = true,  snap = nil,      fb = fallbacks, lk = live, p = profiles },
            { name = "snapshot garbage",  exact = true,  snap = 7,        fb = fallbacks, lk = live, p = profiles },
            { name = "fallbacks missing", exact = true,  snap = snapshot, fb = nil,       lk = live, p = profiles },
            { name = "lookup missing",    exact = true,  snap = snapshot, fb = fallbacks, lk = nil,  p = profiles },
            { name = "profiles missing",  exact = true,  snap = snapshot, fb = fallbacks, lk = live, p = nil },
        }
        for i = 1, #cases do
            local case = cases[i]
            local out = Contract.profile_id_for_send(false, custom_id,
                case.exact, case.snap, case.fb, case.lk, case.p)
            H.truthy(out ~= custom_id,
                "custom id leaked onto the wire under: " .. case.name)
            H.truthy(out == nil or out == vanilla_id,
                "floor returned an unproven id under: " .. case.name)
        end
    end)

    H.test("WT #431 catalog mutation after capture closes the exact gate", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))
        local custom_id = live.wt_custom
        local vanilla_id = live.vanilla_a

        -- A late third-party registration shifts our index underneath us.
        live.wt_custom = custom_id + 5
        live[custom_id + 5] = "wt_custom"
        H.equal(Contract.catalog_intact(snapshot, fallbacks, live, profiles), false,
            "a moved custom index must fail the live integrity check")
        local id, disposition = Contract.profile_id_for_send(false, custom_id,
            true, snapshot, fallbacks, live, profiles)
        H.equal(disposition, "fallback")
        H.equal(id, vanilla_id,
            "a mutated catalog must substitute the proven vanilla donor")

        -- Mutating the DONOR instead: nothing is proven, so the RPC is dropped.
        local live2 = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local snapshot2 = assert(Contract.capture_catalog(fallbacks, live2, profiles))
        live2.vanilla_a = nil
        live2[vanilla_id] = nil
        H.equal(Contract.catalog_intact(snapshot2, fallbacks, live2, profiles), false)
        H.equal(Contract.profile_id_for_send(false, live2.wt_custom, true,
            snapshot2, fallbacks, live2, profiles), nil,
            "an evicted donor must drop the RPC, not fall back to the custom id")

        local live3 = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local snapshot3 = assert(Contract.capture_catalog(fallbacks, live3, profiles))
        fallbacks.wt_custom = nil
        H.equal(Contract.profile_id_for_send(false, live3.wt_custom, true,
            snapshot3, fallbacks, live3, profiles), nil,
            "a removed fallback row must fail closed without throwing")
    end)

    H.test("WT #431 custom-send path rehashes the active semantic profile", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        local original_profile = profiles.wt_custom
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))
        local custom_id, fallback_id = live.wt_custom, live.vanilla_a

        H.equal(Contract.profile_id_for_send(false, custom_id, true,
            snapshot, fallbacks, live, profiles), custom_id)

        -- The numeric lookup and peer gate remain valid, but gameplay data was
        -- changed in place after capture. The sender must not trust any cached
        -- full-catalog verdict: it rehashes this row and falls back now.
        original_profile.power_distribution.attack = 99
        local id, disposition = Contract.profile_id_for_send(false, custom_id,
            true, snapshot, fallbacks, live, profiles)
        H.equal(id, fallback_id)
        H.equal(disposition, "fallback")

        -- Object identity is not part of the wire contract. An independently
        -- reconstructed, semantically identical profile remains compatible.
        profiles.wt_custom = profiles_for(fallbacks).wt_custom
        H.equal(Contract.profile_id_for_send(false, custom_id, true,
            snapshot, fallbacks, live, profiles), custom_id)

        -- Replacing the table with different or unsupported content fails
        -- closed just like in-place mutation.
        profiles.wt_custom = { source = "vanilla_a", attack = 0.5 }
        H.equal(Contract.profile_id_for_send(false, custom_id, true,
            snapshot, fallbacks, live, profiles), fallback_id)
        profiles.wt_custom = { callback = function() end }
        H.equal(Contract.profile_id_for_send(false, custom_id, true,
            snapshot, fallbacks, live, profiles), fallback_id)
    end)

    H.test("WT #431 active-row hostile mutations fall back without throwing", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        profiles.wt_custom.signed_zero = 0
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))
        local custom_id, fallback_id = live.wt_custom, live.vanilla_a

        local cycle = {}
        cycle.self = cycle
        local deep, cursor = {}, nil
        cursor = deep
        for _ = 1, Contract.MAX_PROFILE_DIGEST_DEPTH do
            cursor.child = {}
            cursor = cursor.child
        end
        local large = {}
        for index = 1, Contract.MAX_PROFILE_DIGEST_NODES / 2 do
            large[index] = index
        end
        local mutations = {
            { signed_zero = -math.ldexp(0, 0) },
            { value = math.huge },
            cycle,
            deep,
            large,
        }
        for index, mutation in ipairs(mutations) do
            profiles.wt_custom = mutation
            local call_ok, id, disposition = pcall(Contract.profile_id_for_send,
                false, custom_id, true, snapshot, fallbacks, live, profiles)
            H.equal(call_ok, true, "hostile row threw at case " .. index)
            H.equal(id, fallback_id, "hostile row did not use donor at case " .. index)
            H.equal(disposition, "fallback")
        end
    end)

    H.test("WT #431 hot sender hashes only the selected custom row", function()
        local fallbacks = { wt_alpha = "vanilla_a", wt_beta = "vanilla_b" }
        local live = lookup({ "vanilla_a", "vanilla_b", "wt_alpha", "wt_beta" })
        local profiles = profiles_for(fallbacks)
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))

        local cycle = {}
        cycle.self = cycle
        profiles.wt_beta = cycle
        H.equal(Contract.catalog_intact(snapshot, fallbacks, live, profiles), false,
            "full-catalog audit must observe the unrelated broken row")

        local id, disposition = Contract.profile_id_for_send(false, live.wt_alpha,
            true, snapshot, fallbacks, live, profiles)
        H.equal(id, live.wt_alpha,
            "an unrelated broken row must not force a hot-path full-catalog scan")
        H.equal(disposition, "custom")

        id, disposition = Contract.profile_id_for_send(false, live.wt_beta,
            true, snapshot, fallbacks, live, profiles)
        H.equal(id, live.vanilla_b)
        H.equal(disposition, "fallback",
            "the selected broken row must still fail closed")
    end)

    H.test("WT #431 donor residency is proven, not assumed from presence", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))
        local custom_id = live.wt_custom
        local vanilla_id = live.vanilla_a

        -- Present by name, but the reverse entry points elsewhere: a
        -- half-registered donor is NOT resident and must not be wired.
        live[vanilla_id] = "something_else"
        H.equal(Contract.profile_id_for_send(false, custom_id, false,
            snapshot, fallbacks, live, profiles), nil,
            "a donor that does not round-trip is not proven resident")
    end)

    H.test("WT #431 vanilla ids pass while post-capture WT names are dropped", function()
        local fallbacks = { wt_custom = "vanilla_a" }
        local live = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
        local profiles = profiles_for(fallbacks)
        local snapshot = assert(Contract.capture_catalog(fallbacks, live, profiles))

        local id, disposition = Contract.profile_id_for_send(false, live.vanilla_b,
            false, snapshot, fallbacks, live, profiles)
        H.equal(id, live.vanilla_b)
        H.equal(disposition, "vanilla")

        -- Registered after the snapshot: absent from custom_by_id, but the
        -- fallback map still knows it is ours, so it must never reach the wire.
        fallbacks.wt_late = "vanilla_b"
        live.wt_late = 4
        live[4] = "wt_late"
        H.equal(Contract.profile_id_for_send(false, 4, true, snapshot,
            fallbacks, live, profiles), nil,
            "a WT-owned id registered after capture must be dropped, not wired")
        H.equal(Contract.profile_id_for_send(false, 99, false, snapshot,
            fallbacks, live, profiles), nil, "an id absent from the catalog must be dropped")
        H.equal(Contract.profile_id_for_send(false, nil, false, snapshot,
            fallbacks, live, profiles), nil, "a malformed id must be dropped")

        -- The host never wires the id (weapon_system.lua:179 dispatches its
        -- local receiver), so the host branch must pass through untouched --
        -- narrowing it would drop the host's own attack RPCs.
        H.equal(Contract.profile_id_for_send(true, 4, false, snapshot,
            fallbacks, live, profiles), 4)
        H.equal(Contract.profile_id_for_send("truthy", live.wt_custom, false,
            snapshot, fallbacks, live, profiles), live.wt_custom,
            "is_server is truthy-tested to match the engine's own branch")
    end)

    H.test("WT #431 incompatible schema generation is revoked before epoch acceptance", function()
        local identity = "wt431-v2:2:12345678:abcdef01"
        local receiver, accepted = nil, 0
        local fake_mod = {
            network_send = function() end,
            network_register = function(_, _, callback) receiver = callback end,
            debug = function() end,
            echo = function() end,
            localize = function(_, value) return value end,
        }
        local proxy = assert(Contract.wrap_parity_transport(fake_mod, identity,
            { session_epoch = "local-e1", schema = 2 }))
        local forgotten, required = 0, 0
        local parity = {
            forget_peer = function(_, peer)
                if peer == "peer-a" then forgotten = forgotten + 1 end
            end,
            require_peer = function(_, peer)
                if peer == "peer-a" then required = required + 1 end
            end,
        }
        proxy:_bind_parity_instance(parity)
        proxy:network_register("exact", function() accepted = accepted + 1 end)

        -- A peer on another protocol generation presents an otherwise valid
        -- identity and query. It must be revoked outright.
        receiver("peer-a", 1, 0, identity, "peer-epoch-1", "remote-q1", "")
        H.equal(accepted, 0, "a mismatched schema must never reach the classifier")
        H.truthy(forgotten >= 1 and required >= 1,
            "a mismatched-generation peer must be revoked")

        -- Unmovable proof the rejected epoch was never recorded: a DIFFERENT
        -- epoch on the correct schema is still treated as this peer's first and
        -- passes. Had "peer-epoch-1" been accepted, an unchallenged epoch
        -- change would fail instead.
        receiver("peer-a", 2, 0, identity, "peer-epoch-2", "remote-q2", "")
        H.equal(accepted, 1, "schema rejection must precede epoch acceptance")

        H.equal(select(2, Contract.wrap_parity_transport(fake_mod, identity,
            { session_epoch = "local-e2", schema = 0 })), "schema-invalid")
    end)

    H.test("WT #431 runtime gate retry is bounded and terminal at the cap", function()
        local function make_spec()
            return { mod_id = "wt", setting_ids = {}, evaluate = function() end }
        end
        local calls = 0
        local state = {}
        for _ = 1, Contract.RUNTIME_GATE_MAX_ATTEMPTS + 5 do
            state = Contract.runtime_gate_retry_step(state, make_spec,
                function() calls = calls + 1 return false end)
        end
        H.equal(state.registered, false)
        H.equal(state.terminal, true)
        H.equal(state.attempts, Contract.RUNTIME_GATE_MAX_ATTEMPTS)
        H.equal(calls, Contract.RUNTIME_GATE_MAX_ATTEMPTS,
            "a player without Mod Tweaker must not retry forever")

        -- Success is terminal too; later ticks are no-ops.
        local ok_calls, ok_state = 0, {}
        for _ = 1, 10 do
            ok_state = Contract.runtime_gate_retry_step(ok_state, make_spec,
                function() ok_calls = ok_calls + 1 return ok_calls >= 3 end)
        end
        H.equal(ok_state.registered, true)
        H.equal(ok_state.terminal, true)
        H.equal(ok_state.attempts, 3)
        H.equal(ok_calls, 3)

        -- Neither callback may escape.
        H.equal(Contract.runtime_gate_retry_step({}, function() error("boom") end,
            function() return true end).registered, false)
        H.equal(Contract.runtime_gate_retry_step({}, make_spec,
            function() error("boom") end).registered, false)
    end)

    H.test("WT #431 runtime gate accepts either GUT stream and survives a throwing tweaker", function()
        local spec = assert(Contract.runtime_gate_spec("wt", function() return true end))
        local seen
        H.equal(Contract.try_register_runtime_gate(function(name)
            if name == "gut" then
                return { mod_tweaker = { register_runtime_gate = function(_, id)
                    seen = id
                    return true
                end } }
            end
        end, "wt:431:gut", spec), true, "the public GUT stream must also be tried")
        H.equal(seen, "wt:431:gut")

        H.equal(Contract.try_register_runtime_gate(function()
            return { mod_tweaker = { register_runtime_gate = function() error("boom") end } }
        end, "wt:431:throw", spec), false,
            "a throwing third-party Mod Tweaker must not escape into gameplay")

        H.equal(Contract.try_register_runtime_gate(nil, "wt:431:x", spec), false)
        H.equal(Contract.try_register_runtime_gate(function() end, "", spec), false)
        H.equal(Contract.try_register_runtime_gate(function() end, "wt:431:x", nil), false)
    end)

    H.test("WT #431 both stream copies enforce the same application floor", function()
        local dev_contract = assert(loadfile(repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_wire_contract.lua"))()
        local fallbacks = { wt_custom = "vanilla_a" }
        local streams = { { "public", Contract }, { "dev", dev_contract } }
        for i = 1, #streams do
            local label, C = streams[i][1], streams[i][2]
            local live = lookup({ "vanilla_a", "vanilla_b", "wt_custom" })
            local profiles = profiles_for(fallbacks)
            local snapshot = assert(C.capture_catalog(fallbacks, live, profiles))
            local custom_id, vanilla_id = live.wt_custom, live.vanilla_a
            H.equal(C.RUNTIME_GATE_MAX_ATTEMPTS, 30, label)
            H.equal(C.profile_id_for_send(false, custom_id, true, snapshot,
                fallbacks, live, profiles), custom_id,
                label .. ": open gate keeps the custom id")
            H.equal(C.profile_id_for_send(false, custom_id, false, snapshot,
                fallbacks, live, profiles), vanilla_id,
                label .. ": closed gate substitutes")
            live.vanilla_a = nil
            live[vanilla_id] = nil
            H.equal(C.profile_id_for_send(false, custom_id, false, snapshot,
                fallbacks, live, profiles), nil, label .. ": unprovable donor drops")
        end
    end)

    H.test("WT #431 beta and dev carry normalized exact-catalog wiring", function()
        local function read(path)
            local file = assert(io.open(repo_root .. "/" .. path, "rb"))
            local value = file:read("*a")
            file:close()
            return value
        end
        local beta_contract = read(
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_wire_contract.lua")
        local dev_contract = read(
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_wire_contract.lua")
        H.equal(beta_contract, dev_contract, "pure contract copies must be byte-identical")

        local beta = read(
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_damage_profile_parity.lua")
        local dev = read(
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_damage_profile_parity.lua")
        dev = dev:gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
            :gsub("scripts/mods/weapon_tweaker_dev/", "scripts/mods/weapon_tweaker/")
            :gsub('gate_id = "wt_dev:', 'gate_id = "wt:')
            :gsub('runtime_gate_spec%("wt_dev"', 'runtime_gate_spec("wt"')
        H.equal(beta, dev, "beta/dev runtime policy drifted beyond namespace normalization")
        H.truthy(beta:find('channel     = "wt_damage_profiles_exact_v2"', 1, true),
            "exact WT transport must use its dedicated protocol-generation channel")
        H.equal(beta:find('channel     = "wt_peer_parity_present"', 1, true), nil,
            "exact WT transport must never reuse the legacy presence channel")
    end)
end

return register
