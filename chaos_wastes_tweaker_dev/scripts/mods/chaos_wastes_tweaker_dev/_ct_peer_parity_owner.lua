-- _ct_peer_parity_owner.lua — CT-authored boon and miracle wire-safety owner.
--
-- Owns exact-catalog peer parity, reversible pool gating, synchronized-state
-- stripping, hot-join/remove-peer hooks, the bounded Mod Tweaker bridge, and
-- the eight runtime checks that guard those surfaces. The installer receives
-- every wrapper dependency explicitly, validates the complete contract before
-- side effects, and owns one terminal false/true installation transaction.
--
-- Owned by: _ct_meta_trait_boons.lua. Consumed via: one synchronous mod:dofile
-- installer at the former inline block position.

return function(mod, deps)
    if type(mod) ~= "table" then
        error("[ct:peer-parity-owner] mod table is required")
    end
    if type(deps) ~= "table" then
        error("[ct:peer-parity-owner] dependency table is required")
    end

    local required_capabilities = { "dofile", "hook", "command", "echo" }
    for i = 1, #required_capabilities do
        local name = required_capabilities[i]
        if type(mod[name]) ~= "function" then
            error("[ct:peer-parity-owner] mod." .. name .. " capability is required")
        end
    end

    local required_functions = {
        "rt_register",
        "collect_setting_ids",
        "add_dormant_to_pool",
        "remove_dormant_from_pool",
        "register_trait_boon",
    }
    for i = 1, #required_functions do
        local name = required_functions[i]
        if type(deps[name]) ~= "function" then
            error("[ct:peer-parity-owner] " .. name .. " dependency is required")
        end
    end
    if type(deps.rpc_schema) ~= "number" then
        error("[ct:peer-parity-owner] numeric rpc_schema dependency is required")
    end
    if type(deps.injected_dormants) ~= "table" then
        error("[ct:peer-parity-owner] injected_dormants dependency is required")
    end
    if type(deps.trait_boons) ~= "table" then
        error("[ct:peer-parity-owner] trait_boons dependency is required")
    end
    if rawget(mod, "_ct_peer_parity_owner_installed") ~= nil then
        error("[ct:peer-parity-owner] owner is already installed")
    end

    -- The owner registers callbacks with several VMF/CT registries that have no
    -- unregister operation. A registrar may retain a callback and then throw, so
    -- retrying a partial attempt is never safe. Snapshot the exact raw publication
    -- surface, reserve a terminal false marker, and make every retained callback
    -- inert until the final true commit below.
    local OWNER_MARKER = "_ct_peer_parity_owner_installed"
    local CHANNEL = "ct_boon_catalog_exact_v1"
    local PUBLIC_FIELDS = {
        "_ct_wire_policy",
        "_ct_wire_catalog_identity",
        "_ct_wire_catalog_error",
        "_ct_wire_catalog_integrity",
        "_ct_wire_catalog_power_count",
        "_ct_wire_catalog_buff_count",
        "_ct_peer_parity",
        "_ct_is_modded_power_up",
        "_ct_wire_safe",
        "_ct_is_ct_buff_template",
        "_ct_filter_wire_entries",
        "_ct_strip_modded_content",
        "_ct_census_modded_content",
        "_ct_wire_runtime_gate_registered",
        "_peer_parity_epoch_sequences",
        "update",
    }
    local raw_before = {}
    for i = 1, #PUBLIC_FIELDS do
        local name = PUBLIC_FIELDS[i]
        raw_before[name] = rawget(mod, name)
    end
    local epoch_sequences_before = raw_before._peer_parity_epoch_sequences
    local epoch_channel_before = type(epoch_sequences_before) == "table"
        and rawget(epoch_sequences_before, CHANNEL) or nil
    local ok_update, effective_update_before = pcall(function() return mod.update end)
    if not ok_update then
        error("[ct:peer-parity-owner] mod.update preflight read failed")
    end

    rawset(mod, OWNER_MARKER, false)

    local staged_values = {}
    local staged_writes = {}
    local function stage_public(name, value)
        staged_writes[name] = true
        staged_values[name] = value
    end
    local function publish_or_stage(name, value)
        if rawget(mod, OWNER_MARKER) == true then
            rawset(mod, name, value)
        else
            stage_public(name, value)
        end
    end
    local function owner_committed()
        return rawget(mod, OWNER_MARKER) == true
    end
    local function restore_raw_publication()
        if type(epoch_sequences_before) == "table" then
            rawset(epoch_sequences_before, CHANNEL, epoch_channel_before)
        end
        for i = 1, #PUBLIC_FIELDS do
            local name = PUBLIC_FIELDS[i]
            rawset(mod, name, raw_before[name])
        end
    end

    local install_plan
    local transaction_ok, transaction_error = pcall(function()

    local _rt_register = deps.rt_register
    local _collect_setting_ids = deps.collect_setting_ids
    local CT_RPC_SCHEMA = deps.rpc_schema
    local _add_dormant_to_pool = deps.add_dormant_to_pool
    local _remove_dormant_from_pool = deps.remove_dormant_from_pool
    local _injected_dormants = deps.injected_dormants
    local CT_TRAIT_BOONS = deps.trait_boons
    local register_trait_boon = deps.register_trait_boon

-- ============================================================
-- Peer-parity wire safety for modded boons and miracles (#426 / #406)
-- v0.7.240-dev -- issue 371 doctrine, BUG_CLASSES 31, cwv beacon pattern
-- ============================================================
-- WHY: ct's modded boons (power_up_ct_boon_*, ct_meta_*, ct_kill_heal) and miracles
-- (ct_miracle_*) register into NetworkLookup.buff_templates / deus_power_up_templates.
-- Registration is UNCONDITIONAL and must stay so (index parity across ct peers,
-- see inject_dormant_boon's v0.7.67 comment). But once such content is GRANTED or
-- APPLIED, its modded lookup index goes on vanilla wire paths that reach EVERY peer,
-- including peers without ct (ct's own create_network_hash shim deliberately lets
-- them join):
--   * host buff apply     -> rpc_add_buff broadcast, buff_system.lua:302-305; receiver
--                            decode :430 fatals on the unknown index (network_lookup
--                            strict __index)
--   * granted power-ups   -> deus run-state sync, deus_run_state_spec.lua:60 encode /
--                            :85 decode on every peer
--   * persistent miracles -> saved names re-applied each mission spawn,
--                            deus_spawning.lua:249 / :277-278
--   * hot-join            -> live server-controlled buffs re-sent to a late joiner,
--                            buff_system.lua:1087-1104
-- These are GAMEPLAY axes: sender-substitution would change what happens, so per the
-- issue 371 axis map they get a PEER-PARITY GATE, not substitution. UNCONDITIONAL
-- (never toggle-gated) per the never-crash doctrine.
--
-- HOW: the shared peer-parity beacon (copied single-source lib, master:
-- tools/shared_lib/_lib_peer_parity.lua; same instance pattern as cwv issue 424),
-- run in EXACT-CATALOG mode since v0.7.322-dev. Presence is proven over VMF's own
-- mod-to-mod channel - wire-safe by construction - and exact mode additionally makes
-- a peer echo the composite identity of both boon axes, so an ack proves not just
-- "runs ct" but "numbers every ct boon the same way this process does" (#1191: two
-- ct peers on different builds could both ack while their indices disagreed).
-- Fail-safe posture: modded content is INERT until every other human peer positively
-- acks; solo enables immediately; any beacon error forces content off. The existing
-- ct_peer_manifest_chunk machinery stays what it is - an on-demand DIAGNOSTIC dump -
-- the beacon is the live gate.
--
-- Gate surfaces (all in this file):
--   1. POOL membership     - eject/inject DeusPowerUpRarityPool entries (below)
--   2. GRANT choke point   - parity filter in the consolidated add_power_ups hook
--   3. STARTING boons      - parity filter in the _add_initial_power_ups hook
--   4. MIRACLE buy/apply   - degrade-to-vanilla in _try_buy_blessing + Isha arm/apply
--   5. PARITY-LOSS STRIP   - debounced host-side removal of already-granted modded
--                            power-ups, persistent-buff names, and live modded buffs
--                            (details on the debounce below)
--   6. HOT-JOIN FENCE      - synchronous pre-roster strip in hot_join_sync (below)
--
-- The EXACT CATALOG is not a seventh surface but the precondition for all six:
-- _ct_wire_policy.lua owns the closed catalogs, the sorted reservation runs in
-- _ct_boon_registry.lua before any per-boon registration, the identity and the
-- integrity snapshot are built at the top of _ct_install_peer_parity, and
-- mod._ct_wire_safe() re-proves integrity on every call. Without an identity no
-- beacon is built at all, so every surface above holds content inert.
do
    -- 200-LOCAL CEILING (Lua 5.1): this owner preserves the original single
    -- builder-function boundary. Its helpers therefore occupy function scope
    -- rather than accumulating in the owner chunk. Keeping that original scope
    -- boundary ensures this extraction cannot reintroduce the Stingray compile
    -- failure that first required the builder shape.
    local function _ct_install_peer_parity()
        local inst

        -- EXACT-CATALOG FINALIZATION (v0.7.322-dev, #426 / #1191) ----------------
        -- _ct_boon_registry.lua already reserved both axes in sorted order and
        -- published the module; prefer that instance so reservation and identity
        -- provably describe the same catalog (mod:dofile is NOT a singleton -
        -- a second call would build a second, independent module).
        local wire_policy = mod._ct_wire_policy
        if type(wire_policy) ~= "table" then
            -- Keep the optional policy load fail-closed: the outer owner
            -- transaction handles registrar failures, while policy absence still
            -- commits the historical beacon-unavailable posture.
            local ok_policy, loaded = pcall(mod.dofile, mod,
                "scripts/mods/chaos_wastes_tweaker_dev/_ct_wire_policy")
            wire_policy = (ok_policy and type(loaded) == "table") and loaded or nil
            if wire_policy == nil then
                pcall(printf, "[ct:426] wire-policy module unavailable (%s); modded content stays inert",
                    tostring(loaded))
            end
        end
        stage_public("_ct_wire_policy", wire_policy)

        local wire_policy_valid = type(wire_policy) == "table"
            and type(wire_policy.power_registry_ready) == "function"
            and type(wire_policy.catalog_ready) == "function"
            and type(wire_policy.capture_integrity) == "function"
            and type(wire_policy.build_identity) == "function"
            and type(wire_policy.integrity) == "function"
            and type(wire_policy.power_up_entries) == "function"
            and type(wire_policy.buff_entries) == "function"
            and type(wire_policy.count) == "function"
            and type(wire_policy.runtime_gate_spec) == "function"
            and type(wire_policy.try_register_runtime_gate) == "function"

        local wire_identity, wire_error, wire_integrity
        local wire_power_count, wire_buff_count = 0, 0
        local ok_catalog, Catalog = pcall(mod.dofile, mod,
            "scripts/mods/chaos_wastes_tweaker_dev/_lib_wire_catalog")
        if not wire_policy_valid then
            wire_error = "wire-policy-missing-or-malformed"
        elseif not ok_catalog or type(Catalog) ~= "table" then
            wire_error = "wire-catalog-library-missing:" .. tostring(Catalog)
        else
            -- Every step is a REFUSAL to publish an identity, never a repair: an
            -- identity that does not describe this process exactly would be
            -- worse than none, because peers would trust it.
            local finalize_ok, built_identity, finalize_error = pcall(function()
                wire_power_count = wire_policy.count(wire_policy.power_up_entries())
                wire_buff_count = wire_policy.count(wire_policy.buff_entries())
                if wire_power_count ~= wire_policy.POWER_UP_COUNT
                        or wire_buff_count ~= wire_policy.BUFF_COUNT then
                    return nil, "wire-policy-catalog-count-mismatch"
                end
                -- Two-way: every injected boon is cataloged and every cataloged
                -- boon was injected. A boon added without a catalog entry stops
                -- the beacon instead of riding the wire uncovered.
                local registry_ready, registry_err = wire_policy.power_registry_ready(
                    _injected_dormants)
                if not registry_ready then return nil, registry_err end
                local ready, ready_err = wire_policy.catalog_ready(_G)
                if not ready then return nil, ready_err end
                local snapshot, snapshot_err = wire_policy.capture_integrity(
                    rawget(_G, "NetworkLookup"))
                if not snapshot then return nil, snapshot_err end
                wire_integrity = snapshot
                return wire_policy.build_identity(Catalog, rawget(_G, "NetworkLookup"))
            end)
            if finalize_ok then
                wire_identity, wire_error = built_identity, finalize_error
            else
                wire_error = "catalog-finalize-error:" .. tostring(built_identity)
            end
        end
        stage_public("_ct_wire_catalog_identity", wire_identity)
        stage_public("_ct_wire_catalog_error", wire_error)
        stage_public("_ct_wire_catalog_integrity", wire_integrity)
        stage_public("_ct_wire_catalog_power_count", wire_power_count)
        stage_public("_ct_wire_catalog_buff_count", wire_buff_count)

        -- The beacon is built ONLY with an exact identity. Channel renamed from
        -- ct_peer_parity_present in v0.7.322-dev and that rename is load-bearing:
        -- a pre-0.7.322 ct peer's handler would ignore the four extra exact
        -- fields on the old channel and ack anyway, which is exactly the false
        -- positive #1191 is about. A distinct channel makes an unconverted build
        -- structurally unable to answer, so it reads as parity-absent.
        local ok_lib, factory = pcall(function()
            return mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_lib_peer_parity")
        end)
        if wire_identity and ok_lib and type(factory) == "function" then
            local ok_inst, built = pcall(factory, mod, {
                channel     = "ct_boon_catalog_exact_v1",
                schema      = CT_RPC_SCHEMA,
                mod_label   = "Chaos Wastes Tweaker",
                echo_prefix = "[ct]",
                wire_identity = wire_identity,
            })
            if ok_inst and type(built) == "table" then
                inst = built
            else
                pcall(printf, "[ct:426] peer-parity factory failed: %s", tostring(built))
            end
        elseif not wire_identity then
            pcall(printf, "[ct:426] exact catalog unavailable (%s); modded boons/miracles inert this session",
                tostring(wire_error))
        else
            pcall(printf, "[ct:426] peer-parity lib failed to load: %s", tostring(factory))
        end

        -- Exports readable from hooks defined lexically ABOVE this block (they read the
        -- mod table at call time, so file position does not matter).
        stage_public("_ct_peer_parity", inst)

        -- "Is this power-up name ct-injected?" The closed catalog and the runtime
        -- injection registry are proven equal by power_registry_ready above, so
        -- this reads either. The UNION is deliberate: membership feeds the strip,
        -- where being too broad only removes more ct content, while being too
        -- narrow leaves a modded index on the wire.
        local is_modded_power_up = function(name)
            if name == nil then return false end
            if _injected_dormants[name] ~= nil then return true end
            return type(wire_policy) == "table"
                and type(wire_policy.is_power_up) == "function"
                and wire_policy.is_power_up(name) == true
        end
        stage_public("_ct_is_modded_power_up", is_modded_power_up)

        -- "Is it wire-safe to grant/apply ct modded content right now?" Four
        -- independent positives, any one of which failing means inert:
        --   1. the beacon installed at all;
        --   2. the SETTLED gate is enabled - the same state the pools and the
        --      Mod Tweaker rows report, so presentation cannot claim available
        --      while the grant path refuses (or the reverse);
        --   3. the LIVE roster still classifies safe, which closes the up-to-one
        --      -poll window between a parity loss and the tick that commits it;
        --   4. the local catalog still equals the identity the peers verified.
        -- (4) is what the exact half adds: presence plus settled parity was
        -- always true in the #1191 drift case, because both peers ran ct.
        local wire_safe = function()
            local pp = mod._ct_peer_parity
            if not pp then return false end
            local ok_installed, installed = pcall(pp.is_installed, pp)
            if not ok_installed or installed ~= true then return false end
            local ok_state, applied = pcall(pp.applied_state, pp)
            if not ok_state or applied ~= "enabled" then return false end
            local ok_live, live = pcall(pp.all_peers_have, pp)
            if not ok_live or live ~= true then return false end
            if not wire_policy_valid then return false end
            local ok_integrity, exact = pcall(
                wire_policy.integrity, mod._ct_wire_catalog_integrity)
            return ok_integrity and exact == true
        end
        stage_public("_ct_wire_safe", wire_safe)

        -- "Is this buff TEMPLATE name ct-owned?" Used by the parity-loss strip.
        -- The catalog names the 21 templates ct registers into the lookup; the
        -- prefix test is retained as the wider net for anything ct writes to
        -- BuffTemplates without a lookup row. No vanilla template name starts
        -- with either prefix (grep-verified across scripts/settings 2026-07-11).
        local is_ct_buff_template = function(n)
            if type(n) ~= "string" then return false end
            if type(wire_policy) == "table"
                    and type(wire_policy.is_buff) == "function"
                    and wire_policy.is_buff(n) == true then
                return true
            end
            return n:find("^ct_") ~= nil or n:find("^power_up_ct_") ~= nil
        end
        stage_public("_ct_is_ct_buff_template", is_ct_buff_template)

        -- Pool eject/inject ------------------------------------------------------
        local TRAIT_BOON_BY_NAME = {}
        for _, spec in ipairs(CT_TRAIT_BOONS) do TRAIT_BOON_BY_NAME[spec.name] = spec end

        local function _ct_eject_modded_pools()
            local n = 0
            for name, rec in pairs(_injected_dormants) do
                _remove_dormant_from_pool(name, rec.rarity)
                n = n + 1
            end
            pcall(printf, "[ct:426] modded boon pools ejected (%d boon(s) unrollable until peer parity is confirmed)", n)
        end

        local function _ct_inject_modded_pools()
            local n = 0
            for name, rec in pairs(_injected_dormants) do
                local spec = TRAIT_BOON_BY_NAME[name]
                if spec then
                    register_trait_boon(spec)   -- respects the user's enable_boon_* toggle
                else
                    _add_dormant_to_pool(name, rec.rarity)
                end
                n = n + 1
            end
            pcall(printf, "[ct:426] modded boon pools restored (%d boon(s) eligible, peer parity confirmed)", n)
        end

        -- Parity-loss strip (DEBOUNCED - see below) ------------------------------
        -- Removes already-granted modded state so the run degrades to a vanilla-safe
        -- lobby: granted modded power-ups out of every player's run-state list (stops
        -- both the state sync to a joiner and next-mission reapply), ct names out of
        -- the persistent-buffs lists (Ulric), and live ct server-controlled buffs off
        -- all units. Buff removal uses remove_server_controlled_buff, whose RPC carries
        -- only an integer server_buff_id (buff_system.lua:340) and no-ops on peers
        -- without the buff (:437-454) - wire-safe by construction.
        local function _ct_filter_wire_entries(values, persistent_names)
            local filtered, removed = {}, 0
            if type(values) ~= "table" then return filtered, removed end
            for i = 1, #values do
                local value = values[i]
                local name = persistent_names and value or (type(value) == "table" and value.name)
                local is_modded
                if persistent_names then
                    is_modded = mod._ct_is_ct_buff_template(name)
                else
                    is_modded = name ~= nil and _injected_dormants[name] ~= nil
                end
                if is_modded then
                    removed = removed + 1
                else
                    filtered[#filtered + 1] = value
                end
            end
            return filtered, removed
        end
        stage_public("_ct_filter_wire_entries", _ct_filter_wire_entries)

        -- Walk one SharedState server key's full composite-key tree. Full sync
        -- serializes every row in `_server_state`, including rows whose players
        -- are no longer enumerable through PlayerManager (shared_state.lua:
        -- 683-708). The previous present-player-only strip left those stale rows
        -- capable of exposing a CT NetworkLookup id to a late joiner.
        local function _ct_each_server_state_row(run_state, key_type, visit)
            local shared = run_state and run_state._shared_state
            local key_state = shared and shared._server_state and shared._server_state[key_type]
            if type(key_state) ~= "table" then return end
            for peer_id, local_players in pairs(key_state) do
                if type(local_players) == "table" then
                    for local_player_id, profiles in pairs(local_players) do
                        if type(profiles) == "table" then
                            for profile_index, careers in pairs(profiles) do
                                if type(careers) == "table" then
                                    for career_index, parties in pairs(careers) do
                                        if type(parties) == "table" then
                                            for _, value in pairs(parties) do
                                                visit(peer_id, local_player_id, profile_index, career_index, value)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local function _ct_strip_modded_content(reason)
            local completed = false
            local ok, err = pcall(function()
                if not (Managers and Managers.player and Managers.player.is_server) then
                    error("server PlayerManager unavailable")
                end
                local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
                local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
                local run_state = rc and rc._run_state
                local stripped_pu, stripped_party, stripped_persist, stripped_buffs = 0, 0, 0, 0

                if run_state then
                    _ct_each_server_state_row(run_state, "power_ups", function(peer_id, lpid, profile_index, career_index, values)
                        local filtered, removed = _ct_filter_wire_entries(values, false)
                        if removed > 0 then
                            run_state:set_player_power_ups(peer_id, lpid, profile_index, career_index, filtered)
                            stripped_pu = stripped_pu + removed
                        end
                    end)
                    _ct_each_server_state_row(run_state, "persistent_buffs", function(peer_id, lpid, profile_index, career_index, values)
                        local filtered, removed = _ct_filter_wire_entries(values, true)
                        if removed > 0 then
                            run_state:set_player_persistent_buffs(peer_id, lpid, profile_index, career_index, filtered)
                            stripped_persist = stripped_persist + removed
                        end
                    end)
                    if run_state.get_party_power_ups and run_state.set_party_power_ups then
                        local party = run_state:get_party_power_ups()
                        local filtered, removed = _ct_filter_wire_entries(party, false)
                        if removed > 0 then
                            run_state:set_party_power_ups(filtered)
                            stripped_party = removed
                        end
                    end
                    -- A stripped Isha buff must not re-arm/re-apply from stale flags.
                    if rc._ct_isha_active then
                        rc._ct_isha_active = nil
                        rc._ct_isha_active_level = nil
                    end
                end

                local buff_system = Managers.state and Managers.state.entity and Managers.state.entity:system("buff_system")
                local scb = buff_system and buff_system.server_controlled_buffs
                if buff_system and scb then
                    for unit, unit_buffs in pairs(scb) do
                        if type(unit_buffs) == "table" then
                            local ids = {}
                            for sbid, entry in pairs(unit_buffs) do
                                if entry and mod._ct_is_ct_buff_template(entry.template_name) then
                                    ids[#ids + 1] = sbid
                                end
                            end
                            for i = 1, #ids do
                                buff_system:remove_server_controlled_buff(unit, ids[i])
                                stripped_buffs = stripped_buffs + 1
                            end
                        end
                    end
                end

                pcall(printf, "[ct:426] parity-loss strip reason=%s: removed %d player power-up(s), %d party power-up(s), %d persistent buff name(s), %d live buff(s) from the full synchronized state - lobby degraded to vanilla-safe state",
                    tostring(reason or "parity_loss"), stripped_pu, stripped_party, stripped_persist, stripped_buffs)
                completed = true
            end)
            if not ok then
                pcall(printf, "[ct:426] parity-loss strip reason=%s errored: %s", tostring(reason or "parity_loss"), tostring(err))
            end
            return ok and completed
        end
        stage_public("_ct_strip_modded_content", _ct_strip_modded_content)

        -- Observation-only counterpart to the destructive strip. It walks the
        -- exact same full SharedState tree, including departed-player rows, so
        -- #426 evidence can distinguish a gate failure from a run that never
        -- carried CT state. No getter result is retained or mutated.
        local function _ct_census_modded_content()
            local result = {
                ok = false,
                run_state = false,
                player_power_ups = 0,
                party_power_ups = 0,
                persistent_buffs = 0,
                live_buffs = 0,
            }
            local ok, err = pcall(function()
                local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
                local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
                local run_state = rc and rc._run_state
                result.run_state = run_state ~= nil

                if run_state then
                    _ct_each_server_state_row(run_state, "power_ups", function(_, _, _, _, values)
                        local _, removed = _ct_filter_wire_entries(values, false)
                        result.player_power_ups = result.player_power_ups + removed
                    end)
                    _ct_each_server_state_row(run_state, "persistent_buffs", function(_, _, _, _, values)
                        local _, removed = _ct_filter_wire_entries(values, true)
                        result.persistent_buffs = result.persistent_buffs + removed
                    end)
                    if run_state.get_party_power_ups then
                        local _, removed = _ct_filter_wire_entries(run_state:get_party_power_ups(), false)
                        result.party_power_ups = removed
                    end
                end

                local buff_system = Managers and Managers.state and Managers.state.entity
                    and Managers.state.entity:system("buff_system")
                local scb = buff_system and buff_system.server_controlled_buffs
                if type(scb) == "table" then
                    for _, unit_buffs in pairs(scb) do
                        if type(unit_buffs) == "table" then
                            for _, entry in pairs(unit_buffs) do
                                if entry and mod._ct_is_ct_buff_template(entry.template_name) then
                                    result.live_buffs = result.live_buffs + 1
                                end
                            end
                        end
                    end
                end
            end)
            result.ok = ok
            if not ok then result.error = tostring(err) end
            result.total = result.player_power_ups + result.party_power_ups
                + result.persistent_buffs + result.live_buffs
            return result
        end
        stage_public("_ct_census_modded_content", _ct_census_modded_content)

        -- #426 bounded diagnostic. The existing fix is source-complete, but the
        -- available logs only prove solo enablement. This command separates:
        -- (1) beacon/hook installation, (2) local catalog registration, (3) an
        -- unsafe CT state surviving while parity is absent, and (4) a test that
        -- never established a remote peer or custom run state.
        local diagnostic_callback = function()
            if not owner_committed() then return end
            local pp = mod._ct_peer_parity
            local function pp_call(method, fallback, ...)
                local fn = type(pp) == "table" and pp[method]
                if type(fn) ~= "function" then return fallback end
                local ok, value = pcall(fn, pp, ...)
                if ok then return value end
                return fallback
            end
            local installed = pp_call("is_installed", false) == true
            local applied = pp_call("applied_state", "missing")
            local all_peers = pp_call("all_peers_have", false) == true
            local feature_count = pp_call("feature_count", 0)

            local roster_known = false
            local peers, missing = {}, 0
            local me
            pcall(function() me = Network and Network.peer_id and Network.peer_id() end)
            local pm = Managers and Managers.player
            if pm and type(pm.human_players) == "function" then
                local ok_roster, humans = pcall(function() return pm:human_players() end)
                if ok_roster and type(humans) == "table" then
                    roster_known = true
                    for _, player in pairs(humans) do
                        local peer_id = player and player.peer_id
                        if type(peer_id) == "string" and peer_id ~= me then
                            peers[#peers + 1] = peer_id
                        end
                    end
                end
            end
            table.sort(peers)
            for i = 1, #peers do
                local peer_id = peers[i]
                local acked = pp_call("peer_has", false, peer_id) == true
                if not acked then missing = missing + 1 end
                pcall(printf, "[ct:426:diag] peer=%s acked=%s", tostring(peer_id), tostring(acked))
            end

            local power_lookup = NetworkLookup and rawget(NetworkLookup, "deus_power_up_templates")
            local buff_lookup = NetworkLookup and rawget(NetworkLookup, "buff_templates")
            local power_expected, buff_expected, catalog_mismatch = 0, 0, 0
            local mismatch_rows = 0
            local function audit_lookup(kind, lookup, name)
                local index = type(lookup) == "table" and rawget(lookup, name) or nil
                local reverse = type(lookup) == "table" and type(index) == "number"
                    and rawget(lookup, index) or nil
                if type(index) ~= "number" or reverse ~= name then
                    catalog_mismatch = catalog_mismatch + 1
                    if mismatch_rows < 24 then
                        mismatch_rows = mismatch_rows + 1
                        pcall(printf, "[ct:426:diag] catalog kind=%s name=%s index=%s reverse=%s ok=false",
                            tostring(kind), tostring(name), tostring(index), tostring(reverse))
                    end
                end
            end
            for name in pairs(_injected_dormants) do
                power_expected = power_expected + 1
                audit_lookup("power_up", power_lookup, name)
            end
            local buff_templates = rawget(_G, "BuffTemplates")
            if type(buff_templates) == "table" then
                for name in pairs(buff_templates) do
                    if mod._ct_is_ct_buff_template(name) then
                        buff_expected = buff_expected + 1
                        audit_lookup("buff", buff_lookup, name)
                    end
                end
            end
            if power_expected == 0 or buff_expected == 0 then
                catalog_mismatch = catalog_mismatch + 1
            end

            local census = _ct_census_modded_content()
            local gate_ok = installed and feature_count >= 1
                and ((all_peers and applied == "enabled") or (not all_peers and applied == "disabled"))
            local catalog_ok = catalog_mismatch == 0
            local state_ok = census.ok and (all_peers or census.total == 0)
            local live_custom = census.run_state and census.total > 0

            pcall(printf,
                "[ct:426:diag] state run_state=%s player_power_ups=%d party_power_ups=%d persistent_buffs=%d live_buffs=%d total=%d ok=%s error=%s",
                tostring(census.run_state), census.player_power_ups, census.party_power_ups,
                census.persistent_buffs, census.live_buffs, census.total,
                tostring(census.ok), tostring(census.error))
            pcall(printf,
                "[ct:426:diag] summary installed=%s gate=%s catalog=%s state=%s live_custom=%s roster_known=%s peers=%d missing=%d all_peers=%s applied=%s features=%d power_catalog=%d buff_catalog=%d mismatches=%d",
                installed and "PASS" or "FAIL", gate_ok and "PASS" or "FAIL",
                catalog_ok and "PASS" or "FAIL", state_ok and "PASS" or "FAIL",
                live_custom and "YES" or "NO", tostring(roster_known), #peers, missing,
                tostring(all_peers), tostring(applied), feature_count,
                power_expected, buff_expected, catalog_mismatch)
            mod:echo("[ct] #426 diagnostic written to the console log")
        end

        -- Debounce: the beacon disables INSTANTLY when an un-acked peer appears (correct,
        -- crash-safe direction for the reversible gates above), but the strip is
        -- DESTRUCTIVE (granted boons do not come back). A ct-running friend hot-joining
        -- produces a transient disable until their ack lands; stripping on that transient
        -- would nuke the lobby's boons for nothing. STRIP_GRACE must exceed the beacon's
        -- WORST-CASE ack path, not the typical one: VMF's network_send silently skips
        -- peers whose VMF handshake hasn't completed (vmf network.lua:236-239), so the
        -- arrival-triggered announce can be lost and the retry only comes at the lib's
        -- ANNOUNCE_EVERY = 10s cadence (review finding, pre-ship - 6s stripped a ct
        -- friend on one lost announce). 15s > announce retry (10s) + settle (2s) + poll
        -- slack, and still lands inside a joining player's map-load + first-fight window.
        -- The synchronous hot-join fence below handles the earlier pre-roster
        -- engine seam; this grace remains only for non-join parity transitions.
        local STRIP_GRACE = 15.0
        local _clock = 0
        local _strip_deadline = nil

        -- Mod Tweaker presentation bridge (issue 426 follow-up; mirrors
        -- career_tweaker.lua:~866-890 for issue 425). The gate surfaces above are
        -- the RUNTIME safety and stay authoritative whether or not GUT is
        -- installed; this only makes the saved rows that control gated content
        -- read as unavailable while the gate is closed, instead of looking
        -- actionable and silently doing nothing.
        --
        -- Reached OUTSIDE the `if inst` branch on purpose: when the beacon is
        -- unavailable the content is inert for the whole session, which is
        -- exactly when the rows most need to say so. `inst` may be nil in the
        -- evaluator below, and a nil beacon reads as permanently closed.
        --
        -- `wire_policy` is the module resolved at the top of this function (the
        -- registry's instance, the one whose reservation the identity describes).
        -- It is deliberately NOT re-loaded here: mod:dofile is not a singleton, so
        -- a second load would gate presentation on a different module object than
        -- the one gameplay reads. A nil module means no gate is ever registered
        -- and runtime safety is unaffected - it never consults this bridge.
        local gate_registered = wire_policy == nil   -- nothing to register; never retry
        local gate_retry = 0
        local try_runtime_gate
        do
            local runtime_mod_id = "ct_dev"
            local ok_name, live_name = pcall(function() return mod:get_name() end)
            if ok_name and type(live_name) == "string" and live_name ~= "" then
                runtime_mod_id = live_name
            end
            local gate_id = runtime_mod_id .. ":426:peer-parity"
            try_runtime_gate = function()
                if gate_registered then return end
                local spec = wire_policy.runtime_gate_spec(
                    runtime_mod_id, wire_policy.GATED_SETTING_IDS,
                    function()
                        if not owner_committed() then
                            return false, wire_policy.GATE_REASON
                        end
                        -- Read the SETTLED gate, not all_peers_have(): the rows
                        -- should track exactly what the boon/miracle surfaces are
                        -- doing, including the enable settle window. No beacon at
                        -- all means the content never activates this session.
                        local available = inst ~= nil
                            and inst:applied_state() == "enabled"
                        return available, available and nil or wire_policy.GATE_REASON
                    end)
                local registered = wire_policy.try_register_runtime_gate(
                    rawget(_G, "get_mod"), gate_id, spec)
                gate_registered = registered == true
                publish_or_stage("_ct_wire_runtime_gate_registered", gate_registered)
                if gate_registered then
                    pcall(printf, "[ct:426] Mod Tweaker gate registered id=%s rows=%d beacon=%s",
                        gate_id, #wire_policy.GATED_SETTING_IDS, tostring(inst ~= nil))
                end
            end
        end
        local gated_feature_spec
        if inst then
            gated_feature_spec = {
                label = "ct_gated_modded_boons",
                on_enable = function()
                    if not owner_committed() then return end
                    _strip_deadline = nil
                    _ct_inject_modded_pools()
                end,
                on_disable = function()
                    if not owner_committed() then return end
                    _ct_eject_modded_pools()
                    if Managers and Managers.player and Managers.player.is_server then
                        _strip_deadline = _clock + STRIP_GRACE
                    end
                end,
            }
        end

        -- Make the gameplay surface fail-closed before any callback registrar can
        -- retain and throw. All subsequent registrations remain retry-terminal and
        -- callback-inert until the final owner marker commits.
        _ct_eject_modded_pools()
        mod:command("ct_426_diag", "Audit modded boon and miracle peer wire safety",
            diagnostic_callback)
        try_runtime_gate()

        if inst then
            inst:register_gated_feature("ct_modded_boons_miracles", gated_feature_spec)

            -- Synchronous hot-join fence. Vanilla calls
            -- GameNetworkManager.hot_join_sync(peer_id) BEFORE it adds the
            -- remote player to PlayerManager (peer_states.lua:432 vs :450).
            -- The poll-only beacon therefore cannot see the peer in time to
            -- protect BuffSystem.hot_join_sync or the Deus SharedState request.
            --
            -- There is no wait/timeout here: an already-acked CT peer passes;
            -- every unknown/missing peer immediately receives the vanilla-safe
            -- degraded run after the full synchronized CT state is stripped.
            -- If the strip itself errors, native hot-join sync is NOT called and
            -- NetworkServer.kick_peer is the bounded fallback. A rejected join
            -- is preferable to sending an unresolved NetworkLookup id and CTDing
            -- the other process. Saved settings are never changed.
            mod:hook("GameNetworkManager", "hot_join_sync", function(func, self, peer_id, ...)
                if not owner_committed() then
                    return func(self, peer_id, ...)
                end
                if type(peer_id) ~= "string" then
                    return func(self, peer_id, ...)
                end

                local confirmed = inst:peer_has(peer_id)
                inst:require_peer(peer_id) -- immediate gate-off before any native sync

                if not confirmed then
                    local stripped = _ct_strip_modded_content("hot_join_unconfirmed:" .. peer_id)
                    -- require_peer() synchronously drove on_disable, which arms
                    -- the ordinary 15-second transition strip. This join has
                    -- already been handled synchronously, so suppress that
                    -- redundant second strip/log row.
                    _strip_deadline = nil
                    if not stripped then
                        pcall(printf, "[ct:426] hot-join sync REJECTED peer=%s: CT state could not be made wire-safe", tostring(peer_id))
                        local network_server = self and self.network_server
                        if network_server and type(network_server.kick_peer) == "function" then
                            pcall(network_server.kick_peer, network_server, peer_id)
                        end
                        return
                    end
                    pcall(printf, "[ct:426] hot-join sync DEGRADED peer=%s: no positive CT acknowledgement before native sync", tostring(peer_id))
                end

                return func(self, peer_id, ...)
            end)

            -- A real network departure invalidates the acknowledgement
            -- immediately. PlayerManager-only level-transition gaps do not call
            -- this method, so the existing bounded transition retention remains
            -- intact; a leave/rejoin with the same Steam peer id cannot reuse the
            -- previous session's proof.
            mod:hook("GameNetworkManager", "remove_peer", function(func, self, peer_id, ...)
                if not owner_committed() then
                    return func(self, peer_id, ...)
                end
                inst:forget_peer(peer_id)
                return func(self, peer_id, ...)
            end)

            -- Strip-debounce ticker, published only after install() commits:
            -- chain is [this] -> [beacon wrapper] -> [ct's own update], then beacon tick,
            -- then this tick. NOT a new (Class, method) hook - plain function chaining.
            local update_chain = { previous = nil }
            local owner_update = function(dt)
                local prev_update = update_chain.previous
                if not owner_committed() then
                    if prev_update then return prev_update(dt) end
                    return
                end
                if prev_update then
                    -- Surface (don't just swallow) errors from the wrapped chain - ct's
                    -- own update carries the chunk drain + tickers and previously errored
                    -- loudly through VMF's caller (review finding, pre-ship).
                    local ok_u, err_u = pcall(prev_update, dt)
                    if not ok_u then
                        pcall(printf, "[ct:426] wrapped mod.update errored: %s", tostring(err_u))
                    end
                end
                _clock = _clock + (dt or 0)
                if _strip_deadline and _clock >= _strip_deadline then
                    _strip_deadline = nil
                    _ct_strip_modded_content("persistent_parity_loss")
                end
                -- Bounded retry on the SAME tick chain (no second mod.update wrap
                -- and no new hook); stops permanently once GUT answers.
                if not gate_registered then
                    gate_retry = gate_retry + (dt or 0)
                    if gate_retry >= 1 then
                        gate_retry = 0
                        pcall(try_runtime_gate)
                    end
                end
            end
            return {
                inst = inst,
                update = owner_update,
                update_chain = update_chain,
                log_kind = "installed",
                rpc_schema = CT_RPC_SCHEMA,
            }
        else
            -- Beacon unavailable: _ct_wire_safe() already returns false (fail-safe), so
            -- every gate holds modded content inert. Pools were ejected above.
            -- Same bounded retry as the installed path. There is no beacon tick to
            -- chain onto here, so wrap the existing update once; the evaluator
            -- reads a nil beacon as permanently closed, which is the truth for
            -- this session and is exactly what the rows should say.
            local update_chain = { previous = effective_update_before }
            local owner_update = function(dt)
                local prev_update = update_chain.previous
                if not owner_committed() then
                    if prev_update then return prev_update(dt) end
                    return
                end
                if prev_update then
                    local ok_u, err_u = pcall(prev_update, dt)
                    if not ok_u then
                        pcall(printf, "[ct:426] wrapped mod.update errored: %s", tostring(err_u))
                    end
                end
                if not gate_registered then
                    gate_retry = gate_retry + (dt or 0)
                    if gate_retry >= 1 then
                        gate_retry = 0
                        pcall(try_runtime_gate)
                    end
                end
            end
            return {
                inst = nil,
                update = owner_update,
                update_chain = update_chain,
                log_kind = "unavailable",
            }
        end
    end
    install_plan = _ct_install_peer_parity()
end

local function register_peer_check(name, callback)
    return _rt_register(name, function(...)
        if not owner_committed() then
            return "peer-parity owner did not commit"
        end
        return callback(...)
    end)
end

register_peer_check("peer_parity_beacon_installed", function()
    local pp = mod._ct_peer_parity
    if type(pp) ~= "table" then return "mod._ct_peer_parity missing (beacon not built)" end
    if not pp:is_installed() then return "beacon not installed (network_register failed?)" end
    if pp._initial_applied ~= "disabled" then return "fail-safe posture changed: initial applied state must be 'disabled'" end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then return "fail-safe posture constant changed" end
    if pp:feature_count() < 1 then return "no gated feature registered" end
    return nil
end)

register_peer_check("ct_426_exact_wire_catalog", function()
    -- The exact half of #426 (kills the #1191 index-drift class). Asserts the
    -- shipped identity is real, short enough for the transport, and still
    -- describes THIS process - not that a lobby is currently parity-safe.
    local policy = mod._ct_wire_policy
    if type(policy) ~= "table" then return "mod._ct_wire_policy missing" end
    if mod._ct_wire_catalog_power_count ~= policy.POWER_UP_COUNT then
        return string.format("power-up catalog is %s, expected %d",
            tostring(mod._ct_wire_catalog_power_count), policy.POWER_UP_COUNT)
    end
    if mod._ct_wire_catalog_buff_count ~= policy.BUFF_COUNT then
        return string.format("buff catalog is %s, expected %d",
            tostring(mod._ct_wire_catalog_buff_count), policy.BUFF_COUNT)
    end
    if type(mod._ct_wire_catalog_identity) ~= "string"
            or #mod._ct_wire_catalog_identity > 64 then
        return "no transport-safe exact identity was built: "
            .. tostring(mod._ct_wire_catalog_error)
    end
    -- Recomputing from the LIVE lookups must reproduce the identity the peers
    -- verified. A mismatch means something renumbered an axis after boot, which
    -- is precisely the drift the beacon cannot see on its own.
    local ok_lib, Catalog = pcall(mod.dofile, mod,
        "scripts/mods/chaos_wastes_tweaker_dev/_lib_wire_catalog")
    if not ok_lib or type(Catalog) ~= "table" then
        return "shared wire-catalog library did not load: " .. tostring(Catalog)
    end
    local current, err = policy.build_identity(Catalog, rawget(_G, "NetworkLookup"))
    if current == nil then
        return "identity no longer computable: " .. tostring(err)
    end
    if current ~= mod._ct_wire_catalog_identity then
        return string.format("catalog drifted since boot: now %s, committed %s",
            tostring(current), tostring(mod._ct_wire_catalog_identity))
    end
    local intact, intact_err = policy.integrity(mod._ct_wire_catalog_integrity)
    if intact ~= true then
        return "integrity snapshot no longer holds: " .. tostring(intact_err)
    end
    -- The beacon must be in exact mode carrying that identity; a legacy-mode
    -- instance would accept a same-mod peer with a different catalog.
    local pp = mod._ct_peer_parity
    if type(pp) ~= "table" then
        return "no beacon built despite a valid exact identity"
    end
    if pp.EXACT_MODE ~= true then return "beacon is not in exact mode" end
    if pp.WIRE_IDENTITY ~= mod._ct_wire_catalog_identity then
        return "beacon carries a different identity than the committed catalog"
    end
    return nil
end)

register_peer_check("ct_426_exact_gate_fails_closed", function()
    -- Drift must FAIL CLOSED, not merely be reported. Mutates a throwaway copy
    -- of the integrity snapshot (never the live lookups) and proves the pure
    -- decision the wire-safe predicate depends on flips to false.
    local policy = mod._ct_wire_policy
    if type(policy) ~= "table" or type(policy.integrity) ~= "function" then
        return "mod._ct_wire_policy integrity decision missing"
    end
    local snapshot = mod._ct_wire_catalog_integrity
    if type(snapshot) ~= "table" or type(snapshot.rows) ~= "table" then
        return "skip: no integrity snapshot in this context (run in keep)"
    end
    if policy.integrity(snapshot) ~= true then
        return "live snapshot must read intact before the drift probe"
    end
    local rows = {}
    for i = 1, #snapshot.rows do
        local row = snapshot.rows[i]
        rows[i] = { axis = row.axis, lookup = row.lookup, name = row.name, id = row.id }
    end
    -- One boon lands on a different integer: the exact #1191 shape.
    rows[1].id = (rows[1].id or 0) + 1000
    if policy.integrity({ network_lookup = snapshot.network_lookup, rows = rows }) ~= false then
        return "a drifted boon index must read as parity-absent"
    end
    -- A truncated catalog must not pass either.
    local short = {}
    for i = 1, #snapshot.rows - 1 do short[i] = snapshot.rows[i] end
    if policy.integrity({ network_lookup = snapshot.network_lookup, rows = short }) ~= false then
        return "a short catalog must read as parity-absent"
    end
    if type(mod._ct_wire_safe) ~= "function" then return "mod._ct_wire_safe missing" end
    return nil
end)

register_peer_check("issue426_runtime_gate_presentation", function()
    -- The GUT bridge is optional, so this asserts the CONTRACT (pure policy is
    -- loaded, the row list is well-formed, the spec builder rejects malformed
    -- input and reports closed while the beacon is disabled) rather than
    -- asserting that a gate is live - which would fail on any GUT-less install.
    local wp = mod._ct_wire_policy
    if type(wp) ~= "table" then return "mod._ct_wire_policy missing (bridge module not loaded)" end
    if type(wp.runtime_gate_spec) ~= "function"
            or type(wp.try_register_runtime_gate) ~= "function" then
        return "wire policy runtime-gate API missing"
    end
    local ids = wp.GATED_SETTING_IDS
    if type(ids) ~= "table" or #ids == 0 then return "no gated setting ids declared" end
    -- Every gated row must be a real widget, else the gate greys nothing (or the
    -- wrong thing) and the presentation silently diverges from the runtime gate.
    -- _collect_setting_ids returns an ARRAY of live widget ids; index it.
    local known_list = _collect_setting_ids and _collect_setting_ids()
    if type(known_list) == "table" then
        local known = {}
        for i = 1, #known_list do known[known_list[i]] = true end
        for i = 1, #ids do
            if not known[ids[i]] then
                return "gated setting id is not a live widget: " .. tostring(ids[i])
            end
        end
    end
    if wp.runtime_gate_spec("ct_dev", { "a", "a" }, function() end) ~= nil then
        return "duplicate setting ids must be rejected"
    end
    if wp.runtime_gate_spec("ct_dev", {}, function() end) ~= nil then
        return "empty setting id list must be rejected"
    end
    local spec = wp.runtime_gate_spec("ct_dev", ids, function() return false, wp.GATE_REASON end)
    if type(spec) ~= "table" or #spec.setting_ids ~= #ids then
        return "valid gate spec was rejected"
    end
    local available, reason = spec.evaluate()
    if available ~= false or type(reason) ~= "string" or reason == "" then
        return "closed gate must report unavailable with a player-facing reason"
    end
    if wp.try_register_runtime_gate(nil, "id", spec) ~= false then
        return "invalid get_mod argument must fail closed"
    end
    return nil
end)

register_peer_check("peer_parity_gate_classify", function()
    -- Simulated peer sets against the lib's pure classifier (issue 426 verify spec).
    local pp = mod._ct_peer_parity
    local classify = pp and pp.__classify
    if type(classify) ~= "function" then return "__classify not exposed" end
    if classify({}, {}) ~= true then return "solo (no other peers) must classify safe" end
    if classify({ p1 = true }, {}) ~= false then return "un-acked peer must classify unsafe" end
    if classify({ p1 = true }, { p1 = true }) ~= true then return "all-acked lobby must classify safe" end
    if classify({ p1 = true, p2 = true }, { p1 = true }) ~= false then return "partially-acked lobby must classify unsafe" end
    if classify({}, { p_stale = true }) ~= true then return "stale ack with empty roster must classify safe" end
    return nil
end)

register_peer_check("issue426_hot_join_fence", function()
    local pp = mod._ct_peer_parity
    if not pp or type(pp.require_peer) ~= "function" then return "peer parity require_peer API missing" end
    if type(pp.peer_has) ~= "function" then return "peer parity peer_has API missing" end
    if type(pp.forget_peer) ~= "function" then return "peer parity forget_peer API missing" end
    if type(mod._ct_strip_modded_content) ~= "function" then return "full-state CT strip missing" end
    local filter = mod._ct_filter_wire_entries
    if type(filter) ~= "function" then return "wire-state filter missing" end
    local player_filtered, player_removed = filter({
        { name = "ct_kill_heal" },
        { name = "deus_larger_clip" },
    }, false)
    if player_removed ~= 1 or #player_filtered ~= 1 or player_filtered[1].name ~= "deus_larger_clip" then
        return "player power-up filter does not remove exactly the CT entry"
    end
    local persistent_filtered, persistent_removed = filter({
        "ct_miracle_of_ulric",
        "natural_bond",
    }, true)
    if persistent_removed ~= 1 or #persistent_filtered ~= 1 or persistent_filtered[1] ~= "natural_bond" then
        return "persistent-buff filter does not remove exactly the CT entry"
    end
    return nil
end)

register_peer_check("ct_wire_strip_name_predicate", function()
    local fn = mod._ct_is_ct_buff_template
    if type(fn) ~= "function" then return "mod._ct_is_ct_buff_template missing" end
    if not fn("ct_miracle_of_ulric") then return "ct_miracle_of_ulric must match" end
    if not fn("ct_miracle_of_isha_aegis") then return "ct_miracle_of_isha_aegis must match" end
    if not fn("ct_meta_movespeed_stack") then return "ct_meta_movespeed_stack must match" end
    if not fn("power_up_ct_boon_vauls_anvil_unique") then return "power_up_ct_boon_* must match" end
    if not fn("power_up_ct_kill_heal_exotic") then return "power_up_ct_kill_heal_exotic must match" end
    if fn("power_up_movespeed_exotic") then return "vanilla power_up_movespeed_exotic must NOT match" end
    if fn("deus_larger_clip") then return "vanilla deus_larger_clip must NOT match" end
    if fn(nil) then return "nil must NOT match" end
    return nil
end)

register_peer_check("modded_power_up_registry", function()
    local f = mod._ct_is_modded_power_up
    if type(f) ~= "function" then return "mod._ct_is_modded_power_up missing" end
    if not f("ct_meta_movespeed") then return "ct_meta_movespeed must be in the modded registry" end
    if not f("ct_boon_vauls_anvil") then return "ct_boon_vauls_anvil must be in the modded registry" end
    if not f("ct_kill_heal") then return "ct_kill_heal must be in the modded registry (issue 406 re-enable)" end
    if f("natural_bond") then return "vanilla natural_bond must NOT be in the modded registry" end
    if f(nil) then return "nil must NOT be in the modded registry" end
    return nil
end)

    -- Every callback/registrar above is now retained but inert behind the false
    -- marker. The shared beacon install is the sole irreversible operation left.
    -- A false/throwing install is terminal; after a true return only raw/local
    -- writes remain, so publication cannot strand a live receiver half-owned.
    stage_public("update", install_plan.update)
    if install_plan.inst ~= nil then
        -- The effective update may be supplied by __index while the raw slot is
        -- absent. Seed that exact callback (or a false nil sentinel) so the
        -- shared installer's ordinary assignment cannot enter __newindex and
        -- leak its wrapper through metatable-owned state before throwing. The
        -- failure path below restores the original raw missing/false/function
        -- shape; on success we capture the installed beacon wrapper before the
        -- owner wrapper is raw-published.
        rawset(mod, "update", effective_update_before ~= nil
            and effective_update_before or false)
        local install_committed = install_plan.inst:install()
        if install_committed ~= true then
            error("[ct:peer-parity-owner] beacon install did not commit")
        end
        install_plan.update_chain.previous = rawget(mod, "update")
    end

    for i = 1, #PUBLIC_FIELDS do
        local name = PUBLIC_FIELDS[i]
        if staged_writes[name] then
            rawset(mod, name, staged_values[name])
        end
    end
    rawset(mod, OWNER_MARKER, true)
end)

    if not transaction_ok then
        restore_raw_publication()
        rawset(mod, OWNER_MARKER, false)
        error(transaction_error)
    end

    -- Logging is deliberately post-commit and pcall-contained; it cannot turn a
    -- committed beacon into a retryable/partial owner transaction.
    if install_plan.log_kind == "installed" then
        pcall(printf, "[ct:426] exact peer-parity beacon installed (channel=ct_boon_catalog_exact_v1, schema=%d, identity=%s, rows=%d); modded boons/miracles inert until catalog parity confirmed",
            install_plan.rpc_schema, tostring(rawget(mod, "_ct_wire_catalog_identity")),
            (rawget(mod, "_ct_wire_catalog_power_count") or 0)
                + (rawget(mod, "_ct_wire_catalog_buff_count") or 0))
    else
        pcall(printf, "[ct:426] peer-parity beacon UNAVAILABLE (%s) - modded boons/miracles remain inert this session (fail-safe)",
            tostring(rawget(mod, "_ct_wire_catalog_error") or "beacon-not-built"))
    end

    return true
end
