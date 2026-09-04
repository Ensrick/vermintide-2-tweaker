-- Public Tweaker: Chaos Wastes exact wire-parity owner (issue #426).
--
-- The public catalog is gameplay-bearing: its process-local NetworkLookup ids
-- ride vanilla Deus state and buff RPCs. This owner keeps those producers inert
-- until every live human peer proves the exact frozen catalog, strips all
-- already-live CT state before an unproven hot join, and puts rawget-based
-- receiver floors in front of every vanilla decoder used by the catalog.

return function(mod, deps)
    if type(mod) ~= "table" or type(deps) ~= "table" then
        error("[ct:426] owner requires mod and dependency tables")
    end
    for _, name in ipairs({ "dofile", "hook", "command", "echo" }) do
        if type(mod[name]) ~= "function" then
            error("[ct:426] missing mod capability: " .. name)
        end
    end
    for _, name in ipairs({ "rt_register", "collect_setting_ids",
            "add_dormant_to_pool", "remove_dormant_from_pool",
            "register_trait_boon" }) do
        if type(deps[name]) ~= "function" then
            error("[ct:426] missing dependency: " .. name)
        end
    end
    if type(deps.rpc_schema) ~= "number"
            or type(deps.injected_dormants) ~= "table"
            or type(deps.trait_boons) ~= "table" then
        error("[ct:426] malformed catalog dependencies")
    end
    if rawget(mod, "_ct_peer_parity_owner_installed") ~= nil then
        error("[ct:426] owner already attempted")
    end

    local OWNER = "_ct_peer_parity_owner_installed"
    local CHANNEL = "ct_public_boon_catalog_exact_v1"
    local PUBLIC_FIELDS = {
        "_ct_wire_catalog_identity", "_ct_wire_catalog_error",
        "_ct_wire_catalog_integrity", "_ct_wire_catalog_power_count",
        "_ct_wire_catalog_buff_count", "_ct_peer_parity",
        "_ct_wire_safe", "_ct_sender_wire_safe",
        "_ct_is_modded_power_up", "_ct_is_ct_buff_template",
        "_ct_power_up_wire_allowed", "_ct_buff_wire_allowed",
        "_ct_filter_wire_entries", "_ct_strip_modded_content",
        "_ct_census_modded_content", "_ct_force_wire_inert",
        "_ct_wire_runtime_gate_registered", "_ct_wire_hook_markers",
        "_peer_parity_epoch_sequences", "update",
    }
    local raw_before = {}
    for i = 1, #PUBLIC_FIELDS do
        raw_before[PUBLIC_FIELDS[i]] = rawget(mod, PUBLIC_FIELDS[i])
    end
    local epoch_before = raw_before._peer_parity_epoch_sequences
    local epoch_channel_before = type(epoch_before) == "table"
        and rawget(epoch_before, CHANNEL) or nil
    local ok_update, effective_update_before = pcall(function() return mod.update end)
    if not ok_update then error("[ct:426] mod.update preflight read failed") end

    local STRIP_GRACE = 15
    local STRIP_RETRY = 1
    local STRIP_LOG_LIMIT = 16
    local MAX_GATE_ATTEMPTS = 30
    local unpack = unpack
    local function pack(...)
        return { n = select("#", ...), ... }
    end
    local function log(fmt, ...)
        local printer = rawget(_G, "printf")
        if type(printer) == "function" then pcall(printer, fmt, ...) end
    end
    local function safe_text(value)
        local ok, rendered = pcall(tostring, value)
        return ok and rendered or "<unprintable>"
    end
    local strip_failure_logs = 0
    local function log_strip_failure(fmt, ...)
        if strip_failure_logs >= STRIP_LOG_LIMIT then return end
        strip_failure_logs = strip_failure_logs + 1
        log(fmt, ...)
    end
    local function committed()
        return rawget(mod, OWNER) == true
    end
    local admission_pending = {}
    local admission_sanitized = {}
    local admission_rejected = {}
    rawset(mod, OWNER, false)

    local staged_values, staged_writes = {}, {}
    local function stage_public(name, value)
        staged_writes[name] = true
        staged_values[name] = value
    end
    local function publish_or_stage(name, value)
        if committed() then rawset(mod, name, value)
        else stage_public(name, value) end
    end
    local function restore_publication()
        if type(epoch_before) == "table" then
            rawset(epoch_before, CHANNEL, epoch_channel_before)
        end
        for i = 1, #PUBLIC_FIELDS do
            local name = PUBLIC_FIELDS[i]
            rawset(mod, name, raw_before[name])
        end
    end

    -- Registrars can retain a callback and then throw. Every retained hook uses
    -- the same fail-closed policy even before/after a failed commit: native rows
    -- still pass, while CT-owned rows cannot escape a terminal owner failure.
    local registration_errors = {}
    local function registration_failed(kind, name, value)
        registration_errors[#registration_errors + 1] = kind .. ":"
            .. tostring(name) .. ":" .. tostring(value)
    end
    local function register_hook(class_name, method_name, callback)
        local wrapped = function(func, ...)
            return callback(func, ...)
        end
        local ok, value = pcall(
            mod.hook, mod, class_name, method_name, wrapped)
        if not ok or value == false then registration_failed(
            "hook", class_name .. "." .. method_name,
            ok and "explicit-false" or value) end
        return ok and value ~= false
    end

    local transaction_ok, transaction_value = pcall(function()

    -- Fail-safe cleanup starts before any module load or registrar can throw.
    -- The normal ejection below repeats this after every hook was attempted.
    for name, record in pairs(deps.injected_dormants) do
        local ok, value = pcall(
            deps.remove_dormant_from_pool, name, record.rarity)
        if not ok or value == false then
            registration_failed("early-pool-ejection", name,
                ok and "explicit-false" or value)
        end
    end

    local policy = rawget(mod, "_ct_wire_policy")
    local ok_runtime, Runtime = pcall(mod.dofile, mod,
        "scripts/mods/chaos_wastes_tweaker/_ct_wire_runtime")
    local ok_catalog, Catalog = pcall(mod.dofile, mod,
        "scripts/mods/chaos_wastes_tweaker/_lib_wire_catalog")
    if type(policy) ~= "table" or not ok_runtime or type(Runtime) ~= "table" then
        error("[ct:426] wire policy/runtime unavailable")
    end
    local initial_power_up_codec, codec_error = Runtime.power_up_codec(
        deps.byte_array, deps.lib_deflate, rawget(_G, "NetworkLookup"))
    if type(initial_power_up_codec) ~= "table" then
        error("[ct:426] isolated power-up codec unavailable: "
            .. tostring(codec_error))
    end

    local identity, identity_error, integrity
    local finalize_ok, finalize_value, finalize_reason = pcall(function()
        if rawget(mod, "_ct_wire_reservation_ready") ~= true then
            return nil, rawget(mod, "_ct_wire_reservation_error")
                or "wire-reservation-unavailable"
        end
        if not ok_catalog or type(Catalog) ~= "table" then
            return nil, "wire-catalog-library-unavailable"
        end
        if policy.count(policy.power_up_entries()) ~= policy.POWER_UP_COUNT
                or policy.count(policy.buff_entries()) ~= policy.BUFF_COUNT
                or policy.POWER_UP_COUNT + policy.BUFF_COUNT ~= policy.WIRE_ROW_COUNT then
            return nil, "wire-catalog-count-mismatch"
        end
        local registry_ok, registry_error = policy.power_registry_ready(
            deps.injected_dormants)
        if not registry_ok then return nil, registry_error end
        local ready, ready_error = policy.catalog_ready(_G)
        if not ready then return nil, ready_error end
        local snapshot, snapshot_error = policy.capture_integrity(
            rawget(_G, "NetworkLookup"))
        if not snapshot then return nil, snapshot_error end
        integrity = snapshot
        return policy.build_identity(Catalog, rawget(_G, "NetworkLookup"))
    end)
    if finalize_ok then
        identity, identity_error = finalize_value, finalize_reason
    else
        identity_error = "catalog-finalize-error:" .. tostring(finalize_value)
    end

    stage_public("_ct_wire_catalog_identity", identity)
    stage_public("_ct_wire_catalog_error", identity_error)
    stage_public("_ct_wire_catalog_integrity", integrity)
    stage_public("_ct_wire_catalog_power_count",
        policy.count(policy.power_up_entries()))
    stage_public("_ct_wire_catalog_buff_count",
        policy.count(policy.buff_entries()))

    local instance
    if identity then
        local ok_factory, factory = pcall(mod.dofile, mod,
            "scripts/mods/chaos_wastes_tweaker/_lib_peer_parity")
        if ok_factory and type(factory) == "function" then
            local ok_instance, built, build_error = pcall(factory, mod, {
                channel = CHANNEL,
                schema = deps.rpc_schema,
                mod_id = "ct",
                mod_label = "Tweaker: Chaos Wastes",
                echo_prefix = "[ct]",
                wire_identity = identity,
            })
            if ok_instance and type(built) == "table" then
                instance = built
            else
                identity_error = "peer-parity-instance-error:"
                    .. tostring(build_error or built)
            end
        else
            identity_error = "peer-parity-library-error:" .. tostring(factory)
        end
    end
    stage_public("_ct_wire_catalog_error", identity_error)
    stage_public("_ct_peer_parity", instance)
    if not instance then
        error("[ct:426] exact peer beacon unavailable: "
            .. tostring(identity_error or "unknown"))
    end

    local function integrity_ok()
        if type(integrity) ~= "table" or not rawequal(
                rawget(_G, "NetworkLookup"),
                rawget(integrity, "network_lookup")) then
            return false
        end
        local ok, value = pcall(policy.integrity, integrity)
        return ok and value == true
    end
    local function admission_roster_exact()
        -- Rejected native connections remain part of the safety boundary until
        -- remove_peer clears them, even if a late SharedState request happened
        -- to clear the pending marker.
        for _ in pairs(admission_rejected) do return false end
        for peer_id in pairs(admission_sanitized) do
            if Runtime.sender_exact(instance, peer_id, integrity_ok) then
                admission_sanitized[peer_id] = nil
                admission_pending[peer_id] = nil
            else
                return false
            end
        end
        for peer_id in pairs(admission_pending) do
            if Runtime.sender_exact(instance, peer_id, integrity_ok) then
                admission_pending[peer_id] = nil
            else
                return false
            end
        end
        return true
    end
    local function wire_safe()
        if not committed() or not admission_roster_exact() then return false end
        return Runtime.wire_safe(instance, integrity_ok)
    end
    local function sender_safe(peer_id)
        -- Receiver proof is per sender. It must not depend on the local feature
        -- gate reaching its post-handshake settle state or on unrelated peers.
        return committed() and not admission_rejected[peer_id]
            and Runtime.sender_exact(instance, peer_id, integrity_ok)
    end
    local function relay_sender_safe(peer_id)
        return committed()
            and admission_roster_exact()
            and Runtime.roster_sender_exact(instance, peer_id, integrity_ok)
    end
    stage_public("_ct_wire_safe", wire_safe)
    stage_public("_ct_sender_wire_safe", sender_safe)
    stage_public("_ct_is_modded_power_up", policy.is_owned_power_up_name)
    stage_public("_ct_is_ct_buff_template", policy.is_owned_buff_name)
    stage_public("_ct_power_up_wire_allowed", function(name)
        return policy.power_up_allowed(name, wire_safe())
    end)
    stage_public("_ct_buff_wire_allowed", function(name)
        return policy.buff_allowed(name, wire_safe())
    end)
    stage_public("_ct_filter_wire_entries", function(values, kind, exact)
        return Runtime.filter_values(policy, kind, values,
            exact == nil and wire_safe() or exact == true)
    end)

    local trait_by_name = {}
    for _, spec in ipairs(deps.trait_boons) do trait_by_name[spec.name] = spec end
    local function eject_pools()
        local clean = true
        for name, record in pairs(deps.injected_dormants) do
            local ok, value = pcall(
                deps.remove_dormant_from_pool, name, record.rarity)
            if not ok or value == false then
                clean = false
                log_strip_failure("[ct:426] pool removal failed name=%s error=%s",
                    tostring(name), tostring(ok and "explicit-false" or value))
            end
        end
        return clean
    end
    local function inject_pools()
        if not wire_safe() then return end
        for name, record in pairs(deps.injected_dormants) do
            local spec = trait_by_name[name]
            local fn, a, b = deps.add_dormant_to_pool, name, record.rarity
            if spec then fn, a, b = deps.register_trait_boon, spec, nil end
            local ok, err = pcall(fn, a, b)
            if not ok then
                log("[ct:426] pool injection failed name=%s error=%s",
                    tostring(name), tostring(err))
            end
        end
    end

    local function run_controller()
        local managers = rawget(_G, "Managers")
        local mechanism = managers and managers.mechanism
            and managers.mechanism:game_mechanism()
        return mechanism and mechanism.get_deus_run_controller
            and mechanism:get_deus_run_controller() or nil
    end

    local function collect_rows(run_state, key_type)
        local rows = {}
        local shared = run_state and rawget(run_state, "_shared_state")
        local server_state = shared and rawget(shared, "_server_state")
        local root = type(server_state) == "table" and rawget(server_state, key_type)
        if root == nil then return rows end
        if type(root) ~= "table" then error(key_type .. " state root malformed") end
        local function positive_key(value)
            return type(value) == "number" and value > 0 and value == value
                and value ~= math.huge and value ~= -math.huge
                and value == math.floor(value) and value <= 2147483647
        end
        local branch_count = 0
        local function account_branch()
            branch_count = branch_count + 1
            if branch_count > policy.MAX_STATE_ROWS then
                error(key_type .. " coordinate tree unbounded")
            end
        end
        for peer_id, local_players in next, root do
            account_branch()
            if type(peer_id) ~= "string" or peer_id == "" or peer_id == "0" then
                error(key_type .. " peer key malformed")
            end
            if type(local_players) ~= "table" then error(key_type .. " local-player tree malformed") end
            for local_player_id, profiles in next, local_players do
                account_branch()
                if not positive_key(local_player_id) then
                    error(key_type .. " local-player key malformed")
                end
                if type(profiles) ~= "table" then error(key_type .. " profile tree malformed") end
                for profile_index, careers in next, profiles do
                    account_branch()
                    if not positive_key(profile_index) then
                        error(key_type .. " profile key malformed")
                    end
                    if type(careers) ~= "table" then error(key_type .. " career tree malformed") end
                    for career_index, parties in next, careers do
                        account_branch()
                        if not positive_key(career_index) then
                            error(key_type .. " career key malformed")
                        end
                        if type(parties) ~= "table" then error(key_type .. " party tree malformed") end
                        for party_id, values in next, parties do
                            account_branch()
                            if party_id ~= 0 then error(key_type .. " party key malformed") end
                            if type(values) ~= "table" then error(key_type .. " value malformed") end
                            rows[#rows + 1] = {
                                key = {
                                    peer_id = peer_id,
                                    local_player_id = local_player_id,
                                    profile_index = profile_index,
                                    career_index = career_index,
                                    party_id = party_id,
                                },
                                values = values,
                            }
                            if #rows > policy.MAX_STATE_ROWS then
                                error(key_type .. " coordinate leaves unbounded")
                            end
                        end
                    end
                end
            end
        end
        return rows
    end

    -- Build the complete destructive plan before touching any state. A failure
    -- at any reader/method seam aborts native hot-join sync; the commit itself is
    -- monotonic and deliberately never rolls already-removed CT content back.
    local function preflight_strip()
        local rc = run_controller()
        local run_state = rc and rawget(rc, "_run_state")
        local snapshot = { player = {}, persistent = {} }
        if run_state then
            for _, method in ipairs({ "set_player_power_ups",
                    "set_player_persistent_buffs", "get_party_power_ups",
                    "set_party_power_ups", "get_bought_power_ups",
                    "set_bought_power_ups" }) do
                if type(run_state[method]) ~= "function" then
                    error("run-state method missing: " .. method)
                end
            end
            snapshot.player = collect_rows(run_state, "power_ups")
            snapshot.persistent = collect_rows(run_state, "persistent_buffs")
            local ok_party, party = pcall(run_state.get_party_power_ups, run_state)
            local ok_bought, bought = pcall(run_state.get_bought_power_ups, run_state)
            if not ok_party or type(party) ~= "table" then error("party state unreadable") end
            if not ok_bought or type(bought) ~= "table" then error("bought state unreadable") end
            snapshot.party, snapshot.bought = party, bought
        end
        local plan = Runtime.plan_state_strip(policy, snapshot)
        plan.rc, plan.run_state = rc, run_state
        plan.controller_buffs = 0
        if rc then
            local active = rawget(rc, "_ct_isha_active")
            if active ~= nil then
                if type(active) ~= "string" then
                    error("controller buff marker malformed: _ct_isha_active")
                end
                if policy.is_owned_buff_name(active) then
                    plan.controller_buffs = 1
                end
            end
        end
        plan.server_buffs, plan.local_buffs, plan.game_object_buffs = {}, {}, {}

        local managers = rawget(_G, "Managers")
        local entity = managers and managers.state and managers.state.entity
        local buff_system = entity and entity:system("buff_system")
        plan.buff_system = buff_system
        local excluded = {}
        local server_buffs = buff_system and rawget(buff_system, "server_controlled_buffs")
        if type(server_buffs) == "table" then
            if type(buff_system.remove_server_controlled_buff) ~= "function" then
                error("server buff remover unavailable")
            end
            local server_nodes = 0
            for unit, unit_buffs in next, server_buffs do
                server_nodes = server_nodes + 1
                if server_nodes > Runtime.MAX_ACTIVE_BUFF_ROWS then
                    error("server buff ownership state unbounded")
                end
                if type(unit_buffs) ~= "table" then error("server buff table malformed") end
                for server_id, entry in next, unit_buffs do
                    server_nodes = server_nodes + 1
                    if server_nodes > Runtime.MAX_ACTIVE_BUFF_ROWS then
                        error("server buff ownership state unbounded")
                    end
                    if type(server_id) ~= "number" or server_id <= 0
                            or server_id ~= server_id or server_id == math.huge
                            or server_id == -math.huge
                            or server_id ~= math.floor(server_id)
                            or server_id > 2147483647 then
                        error("server buff id malformed")
                    end
                    if type(entry) ~= "table"
                            or type(rawget(entry, "template_name")) ~= "string"
                            or rawget(entry, "template_name") == "" then
                        error("server buff entry malformed")
                    end
                    local local_id = rawget(entry, "local_buff_id")
                    if local_id ~= nil and (type(local_id) ~= "number"
                            or local_id <= 0 or local_id ~= local_id
                            or local_id == math.huge or local_id == -math.huge
                            or local_id ~= math.floor(local_id)
                            or local_id > 2147483647) then
                        error("server buff local id malformed")
                    end
                    if policy.is_owned_buff_name(rawget(entry, "template_name")) then
                        plan.server_buffs[#plan.server_buffs + 1] = {
                            unit = unit, id = server_id,
                        }
                        if local_id ~= nil then
                            excluded[unit] = excluded[unit] or {}
                            excluded[unit][local_id] = true
                        end
                    end
                end
            end
        end
        local active = buff_system and rawget(buff_system, "active_buff_units")
        if type(active) == "table" then
            local active_units, active_rows, planned_ids = 0, 0, 0
            for unit, extension in next, active do
                active_units = active_units + 1
                if active_units > Runtime.MAX_ACTIVE_BUFF_ROWS then
                    error("active buff unit state unbounded")
                end
                if type(extension) ~= "table"
                        or type(extension.active_buffs) ~= "function" then
                    error("active buff extension unreadable")
                end
                local ok_buffs, buffs, count = pcall(extension.active_buffs, extension)
                if not ok_buffs or type(buffs) ~= "table" then
                    error("active buff list unreadable")
                end
                if type(count) ~= "number" or count ~= count
                        or count == math.huge or count == -math.huge
                        or count < 0 or count ~= math.floor(count)
                        or count > Runtime.MAX_ACTIVE_BUFF_ROWS then
                    error("active buff count malformed")
                end
                active_rows = active_rows + count
                if active_rows > Runtime.MAX_ACTIVE_BUFF_ROWS then
                    error("active buff row state unbounded")
                end
                local ids, ids_error = Runtime.ct_live_buff_ids(
                    policy, buffs, count, excluded[unit])
                if not ids then
                    error("active buff list malformed: " .. tostring(ids_error))
                end
                if #ids > 0 and type(extension.remove_buff) ~= "function" then
                    error("active buff remover unavailable")
                end
                for i = 1, #ids do
                    planned_ids = planned_ids + 1
                    if planned_ids > Runtime.MAX_ACTIVE_BUFF_ROWS then
                        error("active CT buff state unbounded")
                    end
                    plan.local_buffs[#plan.local_buffs + 1] = {
                        extension = extension, id = ids[i], unit = unit,
                    }
                end
            end
        end

        -- A player GameObject caches persistent buff lookup ids when it is
        -- created. Full GameSession replay happens before the later hot-join
        -- callbacks, so removing the live buff alone does not prove that this
        -- cached numeric array is safe for an unproven joining peer.
        local network = managers and managers.state
            and rawget(managers.state, "network")
        local game = type(network) == "table"
            and rawget(network, "game_session") or nil
        if game ~= nil then
            local game_session = rawget(_G, "GameSession")
            local field = type(game_session) == "table"
                and rawget(game_session, "game_object_field")
            local set_field = type(game_session) == "table"
                and rawget(game_session, "set_game_object_field")
            local unit_storage = rawget(network, "unit_storage")
            local go_id = type(unit_storage) == "table"
                and unit_storage.go_id or nil
            -- Only human player_unit GameObjects carry this initializer field.
            -- PlayerManager:players() also contains bots, whose player_bot_unit
            -- schema omits network_buff_ids entirely.
            local players_fn = managers.player and managers.player.human_players
            if type(field) ~= "function" or type(set_field) ~= "function"
                    or type(go_id) ~= "function"
                    or type(players_fn) ~= "function" then
                error("player game-object census unavailable")
            end
            local ok_players, players = pcall(players_fn, managers.player)
            if not ok_players or type(players) ~= "table" then
                error("human player game-object roster unreadable")
            end
            local seen_units, player_count = {}, 0
            local cached_id_count = 0
            local network_lookup = rawget(_G, "NetworkLookup")
            local buff_lookup = type(network_lookup) == "table"
                and rawget(network_lookup, "buff_templates") or nil
            for _, player in next, players do
                player_count = player_count + 1
                if player_count > 64 then error("player game-object roster unbounded") end
                if type(player) ~= "table" then error("player game-object row malformed") end
                local unit = rawget(player, "player_unit")
                if unit ~= nil and not seen_units[unit] then
                    seen_units[unit] = true
                    local ok_id, id = pcall(go_id, unit_storage, unit)
                    if not ok_id then error("player game-object id unreadable") end
                    if id ~= nil then
                        if type(id) ~= "number" or id <= 0 or id ~= id
                                or id == math.huge or id == -math.huge
                                or id ~= math.floor(id) or id > 2147483647 then
                            error("player game-object id malformed")
                        end
                        local ok_field, values = pcall(
                            field, game, id, "network_buff_ids")
                        if not ok_field then
                            error("player game-object buff field unreadable")
                        end
                        if values ~= nil then
                            local filtered, removed, reason =
                                Runtime.filter_lookup_ids(policy, buff_lookup,
                                    values, false, "buff")
                            if not filtered then
                                error("player game-object buff field malformed: "
                                    .. tostring(reason))
                            end
                            cached_id_count = cached_id_count + #filtered + removed
                            if cached_id_count > Runtime.MAX_WIRE_ARRAY_ROWS then
                                error("player game-object buff fields unbounded")
                            end
                            if removed > 0 then
                                plan.game_object_buffs[#plan.game_object_buffs + 1] = {
                                    set_field = set_field,
                                    game = game,
                                    id = id,
                                    values = filtered,
                                    removed = removed,
                                }
                            end
                        end
                    end
                end
            end
        end
        return plan
    end

    local function commit_strip(plan, reason)
        local state = plan.run_state
        if state then
            for i = 1, #plan.player do
                local row, key = plan.player[i], plan.player[i].key
                state:set_player_power_ups(key.peer_id, key.local_player_id,
                    key.profile_index, key.career_index, row.values)
            end
            for i = 1, #plan.persistent do
                local row, key = plan.persistent[i], plan.persistent[i].key
                state:set_player_persistent_buffs(key.peer_id, key.local_player_id,
                    key.profile_index, key.career_index, row.values)
            end
            if plan.party ~= nil then state:set_party_power_ups(plan.party) end
            if plan.bought ~= nil then state:set_bought_power_ups(plan.bought) end
        end
        if plan.rc and plan.controller_buffs > 0 then
            plan.rc._ct_isha_active = nil
            plan.rc._ct_isha_active_level = nil
        end
        for i = 1, #plan.game_object_buffs do
            local row = plan.game_object_buffs[i]
            row.set_field(row.game, row.id, "network_buff_ids", row.values)
        end
        for i = 1, #plan.server_buffs do
            local row = plan.server_buffs[i]
            plan.buff_system:remove_server_controlled_buff(row.unit, row.id)
        end
        for i = 1, #plan.local_buffs do
            local row = plan.local_buffs[i]
            -- Ordinary BuffSyncType.All rows must notify existing peers too.
            -- Server-controlled rows were excluded above and use their own
            -- integer-only removal RPC, so native sync here is both necessary
            -- and wire-safe.
            row.extension:remove_buff(row.id)
        end
        local removed = plan.removed
        log("[ct:426] strip reason=%s player=%d party=%d bought=%d persistent=%d controller_buffs=%d game_object_buffs=%d server_buffs=%d local_buffs=%d",
            tostring(reason), removed.player, removed.party, removed.bought,
            removed.persistent, plan.controller_buffs,
            #plan.game_object_buffs, #plan.server_buffs, #plan.local_buffs)
        return true
    end

    local function strip(reason)
        local managers = rawget(_G, "Managers")
        if not (managers and managers.player and managers.player.is_server) then
            return false, "server-player-manager-unavailable"
        end
        local ok_plan, plan = pcall(preflight_strip)
        if not ok_plan then
            log_strip_failure("[ct:426] strip preflight refused reason=%s error=%s",
                safe_text(reason), safe_text(plan))
            return false, safe_text(plan)
        end
        local ok_commit, result = pcall(commit_strip, plan, reason)
        if not ok_commit then
            log_strip_failure("[ct:426] strip commit failed reason=%s error=%s",
                safe_text(reason), safe_text(result))
            return false, safe_text(result)
        end
        local ok_verify, residual = pcall(preflight_strip)
        if not ok_verify then
            log_strip_failure("[ct:426] strip verification failed reason=%s error=%s",
                safe_text(reason), safe_text(residual))
            return false, safe_text(residual)
        end
        local remaining = residual.removed.player + residual.removed.party
            + residual.removed.bought + residual.removed.persistent
            + residual.controller_buffs
            + #residual.game_object_buffs
            + #residual.server_buffs + #residual.local_buffs
        if remaining ~= 0 then
            log_strip_failure("[ct:426] strip incomplete reason=%s residual=%d",
                tostring(reason), remaining)
            return false, "residual-ct-state:" .. tostring(remaining)
        end
        strip_failure_logs = 0
        return result == true
    end
    stage_public("_ct_strip_modded_content", strip)

    local function census()
        local result = {
            ok = false, player_power_ups = 0, party_power_ups = 0,
            bought_power_ups = 0, persistent_buffs = 0,
            controller_buffs = 0, game_object_buffs = 0,
            server_buffs = 0, local_buffs = 0,
        }
        local ok, plan = pcall(preflight_strip)
        if not ok then result.error = safe_text(plan); return result end
        result.ok = true
        result.player_power_ups = plan.removed.player
        result.party_power_ups = plan.removed.party
        result.bought_power_ups = plan.removed.bought
        result.persistent_buffs = plan.removed.persistent
        result.controller_buffs = plan.controller_buffs
        result.game_object_buffs = #plan.game_object_buffs
        result.server_buffs = #plan.server_buffs
        result.local_buffs = #plan.local_buffs
        result.total = result.player_power_ups + result.party_power_ups
            + result.bought_power_ups + result.persistent_buffs
            + result.controller_buffs + result.game_object_buffs
            + result.server_buffs + result.local_buffs
        return result
    end
    stage_public("_ct_census_modded_content", census)

    local function sender_from_channel(channel_id)
        local map = rawget(_G, "CHANNEL_TO_PEER_ID")
        local peer_id = type(map) == "table" and rawget(map, channel_id)
        return type(peer_id) == "string" and peer_id or nil
    end
    local function filter_for(kind, values)
        local filtered, removed, reason = Runtime.filter_values(
            policy, kind, values, wire_safe())
        if not filtered then
            log_strip_failure("[ct:426] refused malformed %s writer: %s",
                tostring(kind), tostring(reason))
        end
        return filtered, removed, reason
    end

    -- Run-state setters are the final pre-serialization choke points, including
    -- direct end-of-level grants that bypass DeusRunController.add_power_ups.
    register_hook("DeusRunState", "set_player_power_ups",
        function(func, self, peer_id, local_id, profile, career, values)
            local filtered = filter_for("power_ups", values)
            if not filtered then return end
            return func(self, peer_id, local_id, profile, career, filtered)
        end)
    register_hook("DeusRunState", "set_party_power_ups", function(func, self, values)
        local filtered = filter_for("party_power_ups", values)
        if not filtered then return end
        return func(self, filtered)
    end)
    register_hook("DeusRunState", "set_bought_power_ups", function(func, self, values)
        local filtered = filter_for("bought_power_ups", values)
        if not filtered then return end
        return func(self, filtered)
    end)
    register_hook("DeusRunState", "set_player_persistent_buffs",
        function(func, self, peer_id, local_id, profile, career, values)
            local filtered = filter_for("persistent_buffs", values)
            if not filtered then return end
            return func(self, peer_id, local_id, profile, career, filtered)
        end)

    register_hook("DeusRunController", "_try_buy_power_up",
        function(func, self, buyer, power_up, discount)
            local name = type(power_up) == "table" and power_up.name
            if not policy.power_up_allowed(name, wire_safe()) then return false end
            return func(self, buyer, power_up, discount)
        end)
    register_hook("DeusRunController", "rpc_deus_shop_power_up_bought",
        function(func, self, channel_id, rarity, name, client_id, discount)
            local sender = sender_from_channel(channel_id)
            local run_state = type(self) == "table" and rawget(self, "_run_state")
            local receiver_is_server = type(run_state) == "table"
                and rawget(run_state, "_is_server") == true
            local server_peer_id = type(run_state) == "table"
                and rawget(run_state, "_server_peer_id") or nil
            local sender_exact = receiver_is_server and type(sender) == "string"
                and sender ~= server_peer_id and relay_sender_safe(sender) or false
            local allowed, reason = policy.shop_power_up_decision(
                rawget(_G, "DeusPowerUps"), rarity, name, client_id, discount,
                sender, sender_exact, server_peer_id, receiver_is_server)
            if not allowed then
                log("[ct:426] dropped shop power-up sender=%s rarity=%s name=%s reason=%s",
                    safe_text(sender), safe_text(rarity), safe_text(name), safe_text(reason))
                return
            end
            return func(self, channel_id, rarity, name, client_id, discount)
        end)
    register_hook("DeusRunController", "grant_party_power_up",
        function(func, self, name, rarity)
            if not policy.power_up_allowed(name, wire_safe()) then return nil end
            return func(self, name, rarity)
        end)
    register_hook("DeusRunController", "remove_power_ups",
        function(func, self, name, local_id)
            if not policy.power_up_allowed(name, wire_safe()) then return false end
            return func(self, name, local_id)
        end)

    register_hook("DeusRunController", "rpc_deus_add_power_ups",
        function(func, self, channel_id, encoded, node_key)
            local sender = sender_from_channel(channel_id)
            local sender_is_exact = wire_safe() and sender_safe(sender)
            local ok_codec, live_codec, live_codec_error = pcall(
                Runtime.power_up_codec, deps.byte_array, deps.lib_deflate,
                rawget(_G, "NetworkLookup"))
            if not ok_codec or type(live_codec) ~= "table" then
                log("[ct:426] dropped deus-add sender=%s codec=%s",
                    tostring(sender), tostring(ok_codec and live_codec_error
                        or live_codec))
                return
            end
            local sanitized, err, _, remaining = Runtime.sanitize_encoded_power_ups(
                policy, live_codec, encoded, sender_is_exact)
            if not sanitized then
                log("[ct:426] dropped malformed deus-add sender=%s error=%s",
                    tostring(sender), tostring(err))
                return
            end
            if remaining == 0 then return end
            return func(self, channel_id, sanitized, node_key)
        end)
    register_hook("DeusRunController", "rpc_deus_remove_power_up",
        function(func, self, channel_id, power_up_id)
            local nl = rawget(_G, "NetworkLookup")
            local lookup = type(nl) == "table"
                and rawget(nl, "deus_power_up_templates")
            local sender = sender_from_channel(channel_id)
            local sender_is_exact = wire_safe() and sender_safe(sender)
            local allowed = Runtime.lookup_receiver_decision(policy, lookup,
                power_up_id, sender_is_exact, "power_up")
            if not allowed then return end
            return func(self, channel_id, power_up_id)
        end)

    local function buff_id_allowed(self, channel_id, template_id)
        local nl = rawget(_G, "NetworkLookup")
        local lookup = type(nl) == "table" and rawget(nl, "buff_templates")
        local sender = sender_from_channel(channel_id)
        local exact
        if type(self) == "table" and rawget(self, "is_server") == true then
            exact = relay_sender_safe(sender)
        else
            exact = sender_safe(sender)
        end
        return Runtime.lookup_receiver_decision(policy, lookup, template_id,
            exact, "buff")
    end
    register_hook("BuffSystem", "add_buff",
        function(func, self, unit, name, attacker, server_controlled, power, source)
            if not policy.buff_allowed(name, wire_safe()) then return nil end
            return func(self, unit, name, attacker, server_controlled, power, source)
        end)
    register_hook("BuffSystem", "add_buff_synced",
        function(func, self, unit, name, sync_type, params, peer_id)
            if not policy.buff_allowed(name, wire_safe()) then return -1 end
            return func(self, unit, name, sync_type, params, peer_id)
        end)
    register_hook("BuffSystem", "rpc_add_buff",
        function(func, self, channel_id, unit_id, template_id, attacker_id, server_id, echo)
            if not buff_id_allowed(self, channel_id, template_id) then return end
            return func(self, channel_id, unit_id, template_id, attacker_id, server_id, echo)
        end)
    for _, method in ipairs({ "rpc_add_buff_synced", "rpc_add_buff_synced_relay",
            "rpc_add_buff_synced_params", "rpc_add_buff_synced_relay_params",
            "rpc_add_volume_buff_multiplier", "rpc_remove_volume_buff" }) do
        register_hook("BuffSystem", method, function(func, self, channel_id, unit_id,
                template_id, ...)
            if not buff_id_allowed(self, channel_id, template_id) then return end
            return func(self, channel_id, unit_id, template_id, ...)
        end)
    end

    -- SharedState receives full Deus state before a late peer necessarily appears
    -- in PlayerManager. Decode in containment, remove locally-recognized CT rows,
    -- then let vanilla cache/apply only the sanitized payload.
    local shared_kinds = {
        power_ups = "power_ups",
        party_power_ups = "party_power_ups",
        bought_power_ups = "bought_power_ups",
        persistent_buffs = "persistent_buffs",
    }
    register_hook("SharedState", "_set_server_rpc", function(func, self, channel_id,
            key_id, peer_id, local_id, profile, career, party_id, encoded)
        local context = rawget(self, "_original_context")
        if type(context) ~= "string" or context:find("^deus_run_state_") == nil then
            return func(self, channel_id, key_id, peer_id, local_id,
                profile, career, party_id, encoded)
        end
        local key_lookup = rawget(self, "_key_type_lookup")
        local key_type = type(key_lookup) == "table" and rawget(key_lookup, key_id)
        if type(key_type) ~= "string" then return end
        local kind = shared_kinds[key_type]
        if not kind then
            return func(self, channel_id, key_id, peer_id, local_id,
                profile, career, party_id, encoded)
        end
        -- Server-state mutation is authoritative server -> client only. A host
        -- must never accept this path from a peer, and a client accepts it only
        -- from the exact server peer it is currently bound to.
        if rawget(self, "_is_server") == true then return end
        local sender = sender_from_channel(channel_id)
        local server_peer = rawget(self, "_server_peer_id")
        if type(server_peer) ~= "string" or sender ~= server_peer then return end
        local spec_root = rawget(self, "_spec")
        local spec = type(spec_root) == "table" and type(spec_root.server) == "table"
            and rawget(spec_root.server, key_type)
        local decoder = type(spec) == "table" and spec.decode
        local encoder = type(spec) == "table" and spec.encode
        if type(decoder) ~= "function" or type(encoder) ~= "function" then return end
        local ok_decode, values = pcall(decoder, encoded)
        if not ok_decode or type(values) ~= "table" then return end
        local filtered, removed = Runtime.filter_values(policy, kind, values,
            sender_safe(sender))
        if not filtered then return end
        if removed == 0 then
            return func(self, channel_id, key_id, peer_id, local_id,
                profile, career, party_id, encoded)
        end
        local ok_encode, sanitized = pcall(encoder, filtered)
        if not ok_encode or sanitized == nil
                or type(sanitized) ~= type(encoded) then return end
        return func(self, channel_id, key_id, peer_id, local_id,
            profile, career, party_id, sanitized)
    end)

    local strip_deadline, clock = nil, 0
    local hotjoin_preflight = {}
    local function reject_peer(manager, peer_id, reason)
        log("[ct:426] rejecting hot join peer=%s reason=%s",
            tostring(peer_id), tostring(reason))
        local server = manager and (rawget(manager, "network_server")
            or rawget(manager, "_network_server"))
        if server == nil and type(manager) == "table" then server = manager end
        local ok_method, kick = pcall(function()
            return server and server.kick_peer
        end)
        if ok_method and type(kick) == "function" then
            pcall(kick, server, peer_id)
        end
    end
    local function local_server_peer(manager, peer_id)
        if type(peer_id) ~= "string" or peer_id == "" then return false end
        local server = type(manager) == "table"
            and (rawget(manager, "network_server")
                or rawget(manager, "_network_server")) or nil
        if server == nil and type(manager) == "table" then server = manager end
        return type(server) == "table"
            and (peer_id == rawget(server, "my_peer_id")
                or peer_id == rawget(server, "server_peer_id"))
    end
    local function require_exact(peer_id, label)
        local required = false
        if instance and type(peer_id) == "string" then
            local ok_require, value = pcall(
                instance.require_peer, instance, peer_id)
            required = ok_require and value == true
            if not ok_require then
                log_strip_failure("[ct:426] %s peer proof errored peer=%s error=%s",
                    safe_text(label), safe_text(peer_id), safe_text(value))
            end
        end
        return required and sender_safe(peer_id)
    end
    local function sanitize_admission(manager, peer_id, label)
        -- Rejection is terminal for this native connection.  A delayed beacon
        -- packet must not revive a peer after the host has already kicked it;
        -- only remove_peer owns route cleanup and permits a future connection.
        if admission_rejected[peer_id] then return false end
        if require_exact(peer_id, label) then
            admission_pending[peer_id] = nil
            admission_sanitized[peer_id] = nil
            return true
        end
        admission_pending[peer_id] = true
        if admission_sanitized[peer_id] then return true end
        strip_deadline = clock
        local stripped, reason = strip(label .. ":" .. tostring(peer_id))
        if not stripped then
            strip_deadline = clock + STRIP_RETRY
            admission_rejected[peer_id] = tostring(reason or "strip-failed")
            reject_peer(manager, peer_id, reason)
            return false
        end
        strip_deadline = nil
        admission_sanitized[peer_id] = true
        return true
    end
    register_hook("NetworkServer", "peer_connected", function(func, self, peer_id)
        if type(peer_id) ~= "string" or peer_id == ""
                or peer_id == rawget(self, "my_peer_id")
                or peer_id == rawget(self, "server_peer_id") then
            return func(self, peer_id)
        end
        admission_pending[peer_id] = true
        if require_exact(peer_id, "peer-admission") then
            admission_pending[peer_id] = nil
        end
        return func(self, peer_id)
    end)
    -- PeerStates calls this immediately before it tests
    -- NetworkServer.is_network_state_fully_synced_for_peer and then executes
    -- GameSession.add_peer. This is the last source-backed point at which the
    -- host can sanitize numeric Deus/buff state before full GameObject replay.
    register_hook("GameNetworkManager", "set_peer_synchronizing",
        function(func, self, peer_id)
            if local_server_peer(self, peer_id) then
                return func(self, peer_id)
            end
            if type(peer_id) ~= "string" or peer_id == "" then return end
            if not sanitize_admission(self, peer_id, "pre_game_object_sync") then
                return
            end
            return func(self, peer_id)
        end)
    register_hook("NetworkServer", "is_network_state_fully_synced_for_peer",
        function(func, self, peer_id)
            if local_server_peer(self, peer_id) then return func(self, peer_id) end
            if type(peer_id) ~= "string" or peer_id == ""
                    or admission_rejected[peer_id] then return false end
            if admission_pending[peer_id] and not admission_sanitized[peer_id]
                    and not require_exact(peer_id, "pre_game_object_predicate") then
                return false
            end
            if sender_safe(peer_id) then
                admission_pending[peer_id] = nil
            elseif not admission_sanitized[peer_id] then
                -- The predicate is a second, independently source-pinned floor.
                -- A missed/disconnected set_peer_synchronizing hook must not
                -- silently admit an unproven peer into GameSession replay.
                return false
            end
            return func(self, peer_id)
        end)
    register_hook("SharedState", "rpc_shared_state_request_sync",
        function(func, self, channel_id, context)
            local original_context = type(self) == "table"
                and rawget(self, "_original_context") or nil
            if type(self) ~= "table" or rawget(self, "_is_server") ~= true
                    or type(original_context) ~= "string"
                    or original_context:find("^deus_run_state_") == nil
                    or context ~= rawget(self, "_context") then
                return func(self, channel_id, context)
            end
            local peer_id = sender_from_channel(channel_id)
            if peer_id and admission_rejected[peer_id] then return end
            local confirmed = require_exact(peer_id, "shared-state")
            if not confirmed then
                strip_deadline = clock
                local stripped, reason = strip(
                    "shared_state_unproven:" .. tostring(peer_id))
                if not stripped then
                    strip_deadline = clock + STRIP_RETRY
                    reject_peer(self, peer_id, reason)
                    return
                end
                strip_deadline = nil
                if peer_id then admission_sanitized[peer_id] = true end
            else
                admission_pending[peer_id] = nil
                admission_sanitized[peer_id] = nil
            end
            return func(self, channel_id, context)
        end)
    register_hook("GameNetworkManager", "hot_join_sync", function(func, self, peer_id, ...)
        if type(peer_id) ~= "string" then return func(self, peer_id, ...) end
        if admission_rejected[peer_id] then return end
        local confirmed = require_exact(peer_id, "hot-join")
        if confirmed then
            admission_pending[peer_id] = nil
            admission_sanitized[peer_id] = nil
        end
        if not confirmed then
            strip_deadline = clock
            local stripped, reason = strip("hot_join_unproven:" .. peer_id)
            if not stripped then
                strip_deadline = clock + STRIP_RETRY
                reject_peer(self, peer_id, reason)
                return
            end
            strip_deadline = nil
        end
        hotjoin_preflight[peer_id] = true
        local result = pack(pcall(func, self, peer_id, ...))
        hotjoin_preflight[peer_id] = nil
        if not result[1] then error(result[2]) end
        return unpack(result, 2, result.n)
    end)
    register_hook("BuffSystem", "hot_join_sync", function(func, self, peer_id, ...)
        if type(peer_id) == "string" and admission_rejected[peer_id] then return end
        if type(peer_id) == "string" and not hotjoin_preflight[peer_id] then
            local confirmed = require_exact(peer_id, "buff-hot-join")
            if confirmed then
                admission_pending[peer_id] = nil
                admission_sanitized[peer_id] = nil
            end
            if not confirmed then
                strip_deadline = clock
                local stripped = strip("buff_hot_join_unproven:" .. peer_id)
                if not stripped then
                    strip_deadline = clock + STRIP_RETRY
                    return
                end
                strip_deadline = nil
            end
        end
        return func(self, peer_id, ...)
    end)
    register_hook("GameNetworkManager", "remove_peer", function(func, self, peer_id, ...)
        local valid_peer = type(peer_id) == "string" and peer_id ~= ""
        if valid_peer then
            hotjoin_preflight[peer_id] = nil
            admission_pending[peer_id] = nil
            admission_sanitized[peer_id] = nil
            -- Close the route before either independently fallible cleanup.
            -- A peer-id may be reused only after native departure and exact
            -- beacon retirement have both completed successfully.
            admission_rejected[peer_id] = "peer-removal-pending"
        end
        local result = pack(pcall(func, self, peer_id, ...))
        local proof_clean = false
        if instance and valid_peer then
            local ok_forget, err = pcall(instance.forget_peer, instance, peer_id)
            proof_clean = ok_forget
            if not ok_forget then
                log_strip_failure("[ct:426] peer proof cleanup errored peer=%s error=%s",
                    safe_text(peer_id), safe_text(err))
            end
        end
        if valid_peer and result[1] and proof_clean then
            admission_rejected[peer_id] = nil
        elseif valid_peer then
            admission_rejected[peer_id] = "peer-removal-incomplete"
        end
        if not result[1] then error(result[2]) end
        return unpack(result, 2, result.n)
    end)

    local gate_registered, gate_elapsed, gate_attempts = false, 0, 0
    local function try_gate()
        if gate_registered or gate_attempts >= MAX_GATE_ATTEMPTS then return end
        gate_attempts = gate_attempts + 1
        local runtime_mod_id = "ct"
        local spec = policy.runtime_gate_spec(runtime_mod_id,
            policy.GATED_SETTING_IDS, function()
                local available = wire_safe()
                return available, available and nil or policy.GATE_REASON
            end)
        gate_registered = policy.try_register_runtime_gate(
            rawget(_G, "get_mod"), runtime_mod_id .. ":426:public-wire", spec) == true
        publish_or_stage("_ct_wire_runtime_gate_registered", gate_registered)
    end

    local feature
    if instance then
        feature = {
            label = "ct_public_modded_boons",
            on_enable = function()
                if not committed() then return end
                strip_deadline = nil
                inject_pools()
            end,
            on_disable = function()
                if not committed() then return end
                local managers = rawget(_G, "Managers")
                if managers and managers.player
                        and managers.player.is_server then
                    strip_deadline = clock + STRIP_GRACE
                end
                if not eject_pools() then
                    log_strip_failure("[ct:426] pool ejection incomplete during parity loss")
                end
            end,
        }
    end
    local pools_clean = eject_pools()
    if not pools_clean then
        registration_failed("pool-ejection", "initial", "incomplete")
    end
    if instance then
        local ok_feature, value = pcall(instance.register_gated_feature,
            instance, "ct_public_modded_boons", feature)
        if not ok_feature or value == false then
            registration_failed("feature", "ct_public_modded_boons",
                ok_feature and "explicit-false" or value)
        end
    end

    stage_public("_ct_force_wire_inert", function(reason)
        local managers = rawget(_G, "Managers")
        local stripped, strip_error = true, nil
        if managers and managers.player and managers.player.is_server then
            strip_deadline = clock
            stripped, strip_error = strip(reason or "mod-disabled")
            strip_deadline = stripped and nil or clock + STRIP_RETRY
        end
        local ejected = eject_pools()
        if not ejected then
            log_strip_failure("[ct:426] pool ejection incomplete while forcing inert")
        end
        return stripped and ejected, strip_error
    end)

    local ok_command, command_value = pcall(mod.command, mod,
        "ct_426_diag", "Write the public boon wire-safety audit to the log",
        function()
            if not committed() then return end
            local c = census()
            log("[ct:426:diag] version=public rows=%d identity=%s error=%s installed=%s applied=%s all=%s safe=%s gate=%s state_ok=%s state_total=%s player=%s party=%s bought=%s persistent=%s controller_buffs=%s game_object_buffs=%s server_buffs=%s local_buffs=%s",
                policy.WIRE_ROW_COUNT, tostring(identity), tostring(identity_error),
                tostring(instance and instance:is_installed()),
                tostring(instance and instance:applied_state()),
                tostring(instance and instance:all_peers_have()), tostring(wire_safe()),
                tostring(gate_registered), tostring(c.ok), tostring(c.total),
                tostring(c.player_power_ups), tostring(c.party_power_ups),
                tostring(c.bought_power_ups), tostring(c.persistent_buffs),
                tostring(c.controller_buffs),
                tostring(c.game_object_buffs),
                tostring(c.server_buffs), tostring(c.local_buffs))
            mod:echo("[ct] #426 public wire audit written to the console log")
        end)
    if not ok_command or command_value == false then
        registration_failed("command", "ct_426_diag",
            ok_command and "explicit-false" or command_value)
    end

    local hook_markers = {
        run_state = true, purchase = true, shop_preclone = true,
        deus_receivers = true,
        buff_senders = true, buff_receivers = true, shared_state = true,
        peer_admission = true, pre_game_object_sync = true, hot_join = true,
    }
    stage_public("_ct_wire_hook_markers", hook_markers)

    local function register_check(name, callback)
        local ok, value = pcall(deps.rt_register, name, function(...)
            if not committed() then return "public wire owner did not commit" end
            return callback(...)
        end)
        if not ok or value == false then
            registration_failed("runtime-check", name,
                ok and "explicit-false" or value)
        end
        return ok and value ~= false
    end

    register_check("ct_426_public_exact_catalog", function()
        if policy.POWER_UP_COUNT ~= 10 or policy.BUFF_COUNT ~= 19
                or policy.WIRE_ROW_COUNT ~= 29 then return "public catalog count drift" end
        if type(identity) ~= "string" or #identity > 64 then
            return "exact identity unavailable: " .. tostring(identity_error)
        end
        if not integrity_ok() then return "live lookup integrity failed" end
        if not instance or instance.EXACT_MODE ~= true
                or instance.WIRE_IDENTITY ~= identity then
            return "exact peer beacon unavailable"
        end
    end)
    register_check("ct_426_public_receiver_floors", function()
        for name, value in pairs(hook_markers) do
            if value ~= true then return "receiver/writer floor missing: " .. name end
        end
        local nl = rawget(_G, "NetworkLookup")
        local buffs = type(nl) == "table" and rawget(nl, "buff_templates")
        local powers = type(nl) == "table" and rawget(nl, "deus_power_up_templates")
        if Runtime.lookup_receiver_decision(policy, buffs, -1, false, "buff") ~= false
                or Runtime.lookup_receiver_decision(policy, powers, 2147483647,
                    false, "power_up") ~= false then
            return "unknown numeric receiver id was not rejected"
        end
        local shop_exact = policy.shop_power_up_decision(
            rawget(_G, "DeusPowerUps"), "exotic", "ct_meta_health", 17, 0,
            "ct-426-probe-peer", true, "ct-426-probe-host", true)
        local shop_unproven = policy.shop_power_up_decision(
            nil, "exotic", "ct_meta_health", 17, 0,
            "ct-426-probe-peer", false, "ct-426-probe-host", true)
        if shop_exact ~= true or shop_unproven ~= false then
            return "pre-clone shop receiver floor failed"
        end
    end)
    register_check("ct_426_public_hot_join_containment", function()
        if type(mod._ct_strip_modded_content) ~= "function"
                or type(mod._ct_census_modded_content) ~= "function" then
            return "hot-join strip/census unavailable"
        end
        local c = census()
        if not c.ok then return "state census failed: " .. tostring(c.error) end
        if not wire_safe() and (c.total or 0) ~= 0 then
            return "unsafe lobby still carries " .. tostring(c.total) .. " CT state row(s)"
        end
    end)
    register_check("ct_426_public_gate_surface", function()
        local known, ids = {}, deps.collect_setting_ids()
        for i = 1, #(ids or {}) do known[ids[i]] = true end
        for i = 1, #policy.GATED_SETTING_IDS do
            if not known[policy.GATED_SETTING_IDS[i]] then
                return "gated setting is not live: " .. policy.GATED_SETTING_IDS[i]
            end
        end
    end)

    -- Every registrar above is attempted so a retained fail-closed receiver is
    -- not skipped merely because an earlier VMF registrar retained and threw.
    -- Nothing that can announce/enable the exact catalog is installed until
    -- the complete mandatory floor and both pool-ejection passes succeeded.
    if #registration_errors > 0 then
        error("[ct:426] mandatory registration failed: "
            .. table.concat(registration_errors, " | "))
    end

    try_gate()
    local previous_update = effective_update_before
    local integrity_failed = false
    local owner_update = function(dt)
        if previous_update then
            local ok, err = pcall(previous_update, dt)
            if not ok then log("[ct:426] wrapped update failed: %s", safe_text(err)) end
        end
        if not committed() then return end
        clock = clock + (tonumber(dt) or 0)
        local intact = integrity_ok()
        if not intact and not integrity_failed then
            integrity_failed = true
            strip_deadline = clock
            if not eject_pools() then
                log_strip_failure("[ct:426] pool ejection incomplete after lookup drift")
            end
        elseif intact and integrity_failed then
            integrity_failed = false
            if wire_safe() then inject_pools() end
        end
        if strip_deadline and clock >= strip_deadline then
            local stripped = strip("persistent-parity-loss")
            strip_deadline = stripped and nil or clock + STRIP_RETRY
        end
        if not gate_registered and gate_attempts < MAX_GATE_ATTEMPTS then
            gate_elapsed = gate_elapsed + (tonumber(dt) or 0)
            if gate_elapsed >= 1 then gate_elapsed = 0; try_gate() end
        end
    end
    if instance then
        -- Avoid an inherited update entering a hostile __newindex during the
        -- beacon's own transaction. Its wrapper is captured only after commit.
        rawset(mod, "update", effective_update_before ~= nil
            and effective_update_before or false)
        if instance:install() ~= true then
            error("[ct:426] exact peer beacon install failed")
        end
        previous_update = rawget(mod, "update")
    end
    stage_public("update", owner_update)

    -- After a successful beacon install only raw table writes remain. Commit
    -- every staged publication as one terminal owner state.
    for i = 1, #PUBLIC_FIELDS do
        local name = PUBLIC_FIELDS[i]
        if staged_writes[name] then rawset(mod, name, staged_values[name]) end
    end

    rawset(mod, OWNER, true)
    log("[ct:426] public exact wire owner installed channel=%s identity=%s rows=%d posture=inert-until-all-exact",
        CHANNEL, tostring(identity), policy.WIRE_ROW_COUNT)
    return true
    end)

    if not transaction_ok then
        restore_publication()
        rawset(mod, OWNER, false)
        error(transaction_value)
    end
    return transaction_value
end
