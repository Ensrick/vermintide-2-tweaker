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

    H.test("WT #431 identity is order-stable and detects numeric reorder", function()
        local fallbacks_a = { wt_beta = "vanilla_b", wt_alpha = "vanilla_a" }
        local fallbacks_b = { wt_alpha = "vanilla_a", wt_beta = "vanilla_b" }
        local catalog = lookup({ "vanilla_a", "vanilla_b", "wt_alpha", "wt_beta" })
        local a, err_a, names_a = Contract.build_wire_identity(fallbacks_a, catalog)
        local b, err_b, names_b = Contract.build_wire_identity(fallbacks_b, catalog)
        H.equal(err_a, nil)
        H.equal(err_b, nil)
        H.equal(a, b)
        H.deep_equal(names_a, { "wt_alpha", "wt_beta" })
        H.deep_equal(names_a, names_b)

        local reordered = lookup({ "vanilla_a", "vanilla_b", "wt_beta", "wt_alpha" })
        local shifted = assert(Contract.build_wire_identity(fallbacks_a, reordered))
        H.truthy(shifted ~= a,
            "same names at different process-local ids must not establish parity")

        local missing = lookup({ "vanilla_a", "vanilla_b", "wt_alpha" })
        local identity, err = Contract.build_wire_identity(fallbacks_a, missing)
        H.equal(identity, nil)
        H.truthy(err:find("custom%-lookup%-mismatch") ~= nil)

        local with_extra = {
            wt_alpha = "vanilla_a", wt_beta = "vanilla_b", wt_gamma = "vanilla_c",
        }
        local extra_catalog = lookup({
            "vanilla_a", "vanilla_b", "vanilla_c", "wt_alpha", "wt_beta", "wt_gamma",
        })
        local expanded = assert(Contract.build_wire_identity(with_extra, extra_catalog))
        H.truthy(expanded ~= a,
            "an extra WT-owned generated profile must change exact identity")
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
            "wt431-v1:2:12345678:abcdef01", { session_epoch = "local-e1" }))
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

        proxy:network_send("presence", "peer-a", 1, 0)
        local query = sent[#sent]
        H.truthy(type(query.query) == "string" and query.query ~= "")
        receiver("peer-a", 1, 1, "wt431-v1:2:12345678:abcdef01",
            "remote-e1", "", query.query)
        H.equal(accepted, 1, "exact identity plus current challenge must pass")

        parity:forget_peer("peer-a")
        receiver("peer-a", 1, 1, "wt431-v1:2:12345678:abcdef01",
            "remote-e1", "", query.query)
        H.equal(accepted, 1, "delayed pre-disconnect reply must not re-ack")
        H.truthy(forgotten >= 2)
        H.truthy(required >= 1)

        proxy:network_send("presence", "peer-a", 1, 0)
        local fresh = sent[#sent]
        receiver("peer-a", 1, 1, "wt431-v1:2:12345678:abcdef01",
            "remote-e2", "", fresh.query)
        H.equal(accepted, 2, "fresh epoch and fresh challenge may re-establish parity")

        receiver("peer-a", 1, 0, "wt431-v1:2:00000000:00000000",
            "remote-e3", "remote-q", "")
        H.equal(accepted, 2, "catalog mismatch must never reach presence classifier")
    end)

    H.test("WT #431 retired peer history is globally bounded across churn", function()
        local identity = "wt431-v1:2:12345678:abcdef01"
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
            { session_epoch = "local-churn" }))
        local parity = {
            forget_peer = function() end,
            require_peer = function() end,
        }
        proxy:_bind_parity_instance(parity)
        proxy:network_register("presence", function() accepted = accepted + 1 end)

        local churn = Contract.MAX_RETIRED_PEERS + 7
        for i = 1, churn do
            local peer = "peer-" .. i
            receiver(peer, 1, 0, identity, "epoch-" .. i, "remote-q-" .. i, "")
            parity:forget_peer(peer)
        end
        H.equal(accepted, churn)
        H.equal(proxy:_wt431_retired_peer_count(), Contract.MAX_RETIRED_PEERS,
            "unique peer churn must not grow retired state without bound")
        H.equal(proxy:_wt431_is_epoch_retired("peer-1", "epoch-1"), false,
            "FIFO eviction must remove the oldest retired peer deterministically")
        H.equal(proxy:_wt431_is_epoch_retired("peer-" .. churn, "epoch-" .. churn), true,
            "the newest retired peer must remain protected")

        receiver("peer-" .. churn, 1, 0, identity, "epoch-" .. churn,
            "retired-query", "")
        H.equal(accepted, churn, "a retained retired epoch must remain rejected")

        proxy:network_send("presence", "peer-1", 1, 0)
        receiver("peer-1", 1, 1, identity, "epoch-1", "", "remote-q-1")
        H.equal(accepted, churn,
            "an evicted peer's stale reply must still fail the current challenge")

        proxy:network_send("presence", "peer-1", 1, 0)
        local fresh = sent[#sent]
        receiver("peer-1", 1, 1, identity, "epoch-rejoined", "", fresh.query)
        H.equal(accepted, churn + 1,
            "an evicted peer may rejoin only with a fresh epoch and challenge")
        H.equal(proxy:_wt431_retired_peer_count(), Contract.MAX_RETIRED_PEERS,
            "rejoin churn must preserve the global bound")
    end)

    H.test("WT #431 parity payload stays below VMF's 500-character cap", function()
        H.truthy(Contract.max_json_envelope_length() <= Contract.MAX_VMF_JSON_LENGTH)
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
    end)
end

return register
