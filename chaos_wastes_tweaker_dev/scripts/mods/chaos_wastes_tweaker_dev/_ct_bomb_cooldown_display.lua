-- Issues #357/#358: owner-only HUD timers for host-authoritative cooldowns.
--
-- These templates are deliberately client-local. They are never appended to
-- NetworkLookup.buff_templates and never sent through vanilla rpc_add_buff; the
-- host targets only the boon owner through a schema-gated VMF event. The display
-- is presentation only -- gameplay timing remains owned by the existing
-- grenade_explode_buff_area gate in chaos_wastes_tweaker_dev.lua.
local mod = get_mod("ct_dev")
local M = {}

local CHANNEL = "ct_bomb_cooldown_display_v1"
local MAX_INTERVAL_SECONDS = 600 -- exact authored setting ceiling
local MAX_MANANN_GENERATION = 2147483647
local READY_TICK_INTERVAL_S = 0.5
local ISSUE358_ERROR_LOG_LIMIT = 4

local BOONS = {
    boon_supportbomb_concentration_01 = {
        template = "ct_bomb_cooldown_display_concentration",
        icon = "deus_icon_supportbomb_concentration_01",
    },
    boon_supportbomb_crit_01 = {
        template = "ct_bomb_cooldown_display_crit",
        icon = "deus_icon_supportbomb_crit_01",
    },
    boon_supportbomb_healing_01 = {
        template = "ct_bomb_cooldown_display_healing",
        icon = "deus_icon_supportbomb_healing_01",
    },
    boon_supportbomb_speed_01 = {
        template = "ct_bomb_cooldown_display_speed",
        icon = "deus_icon_supportbomb_speed_01",
    },
}

-- #358: boon and trait gates have independent timestamp buckets, so they need
-- independent local templates as well. Both use the native weapon-trait icon;
-- sharing one max-stack template would let one source refresh the other's HUD
-- timer and falsely imply that both cooldowns have the same ready time.
--
-- #358 ready state: each source is a two-state local display machine.
--   ready (infinite `ready_template` buff, no is_cooldown) while the source is
--   owned and off cooldown -> cooldown (the finite 8s `template` buff) on an
--   allowed proc -> back to ready when the finite buff expires. Rejected procs
--   never reach notify_allowed, so they cannot restart either display. The
--   reconciler below (M.reconcile_manann_ready) owns acquisition, expiry
--   restoration, and toggle-off / source-loss cleanup.
-- Ownership probes (owner-local buffs on the local player's own extension):
--   * trait: sub-buff "deus_crit_chain_lightning" is applied while the trait
--     weapon is wielded (template morris_buff_settings.lua:7040, sub name
--     :7048; buff_type == sub name, buff_extension.lua:305).
--   * boon: ct's meta-trait boon clone names its applied sub-buff
--     "power_up_ct_boon_manann_tempest_<rarity>" (_ct_meta_trait_boons.lua
--     buff_template.buffs[1].name = buff_name), so a prefix probe over
--     active_buffs() matches exactly what the proc gate matches.
local MANANN_SOURCES = {
    manann_boon = {
        template = "ct_manann_cooldown_display_boon",
        ready_template = "ct_manann_ready_display_boon",
        icon = "deus_icon_trait_crit_chain_lightning",
        owner_prefix = "power_up_ct_boon_manann_tempest_",
    },
    manann_trait = {
        template = "ct_manann_cooldown_display_trait",
        ready_template = "ct_manann_ready_display_trait",
        icon = "deus_icon_trait_crit_chain_lightning",
        owner_buff = "deus_crit_chain_lightning",
    },
}

-- #358: presentation deadlines mirror the host's authoritative per-unit,
-- per-source buckets. Weak unit keys prevent a completed mission/player unit
-- from retaining state into the next run. Source loss and setting/mod disable
-- hide the display but deliberately preserve an unexpired deadline: the host
-- gate preserves that same bucket, so re-wield/re-enable must resume the
-- remaining cooldown instead of claiming the proc is ready early.
local MANANN_DEADLINES = setmetatable({}, { __mode = "k" })

local function _spec(display_name)
    return BOONS[display_name] or MANANN_SOURCES[display_name]
end

local function _valid_interval(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value <= MAX_INTERVAL_SECONDS
end

local function _valid_generation(value)
    return type(value) == "number"
        and value == value
        and value >= 1
        and value <= MAX_MANANN_GENERATION
        and value % 1 == 0
end

local function _game_time_safe()
    local time_manager = Managers and Managers.time
    if not time_manager or type(time_manager.time) ~= "function" then
        return nil
    end
    local ok, value = pcall(time_manager.time, time_manager, "game")
    if not ok then
        return nil, "game-time lookup failed: " .. tostring(value)
    end
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        return nil, "game-time lookup returned a non-finite value"
    end
    return value
end

-- PlayerManager.local_player() calls Network.peer_id() unconditionally.
-- local_player_safe() first checks for a live network game, but StateLoading
-- can still tear the backend down between that check and Network.peer_id()
-- (player_manager.lua:580-595). Treat that known lifecycle race as ordinary
-- absence; surface other failures through the bounded ticker error channel.
local function _local_player_safe()
    local player_manager = Managers and Managers.player
    if not player_manager or type(player_manager.local_player_safe) ~= "function" then
        return nil
    end
    local ok, player = pcall(player_manager.local_player_safe, player_manager, 1)
    if ok then return player end
    local message = tostring(player)
    if message:find("Network backend has not been set", 1, true) then
        return nil
    end
    return nil, "local-player lookup failed: " .. message
end

local function _buff_extension_safe(unit)
    if not unit or not ScriptUnit or type(ScriptUnit.has_extension) ~= "function" then
        return nil
    end
    local ok, extension = pcall(ScriptUnit.has_extension, unit, "buff_system")
    if not ok then
        return nil, "buff extension lookup failed: " .. tostring(extension)
    end
    return extension
end

local function _deadline_state(unit, create)
    local state = MANANN_DEADLINES[unit]
    if not state and create then
        state = {}
        MANANN_DEADLINES[unit] = state
    end
    return state
end

local function _align_unit_clock(unit, now)
    local state = _deadline_state(unit, true)
    local previous = state._last_game_time
    local reset = type(previous) == "number" and now < previous
    if reset then
        for source_name in pairs(MANANN_SOURCES) do
            local receipt = state[source_name]
            if receipt then receipt.deadline = nil end
        end
    end
    state._last_game_time = now
    return reset
end

local function _deadline_remaining(unit, source_name, now)
    local state = _deadline_state(unit, false)
    local receipt = state and state[source_name]
    local deadline = receipt and receipt.deadline
    if type(deadline) == "number" and deadline > now then
        return deadline - now, deadline
    end
    if receipt and deadline ~= nil then
        -- Retain the accepted generation after expiry. Otherwise an equal or
        -- older delayed packet could resurrect a false cooldown after the
        -- visible deadline has elapsed.
        receipt.deadline = nil
    end
    return nil
end

-- A higher host generation is a distinct allowed proc even if it arrives while
-- the prior receipt-relative display window is still live. Equal/older packets
-- are replay/stale work and cannot mutate either the deadline or presentation.
local function _accept_manann_receipt(unit, source_name, now, interval, generation)
    if not _valid_generation(generation) then return nil, nil, false end
    _align_unit_clock(unit, now)
    local state = _deadline_state(unit, true)
    local prior = state[source_name]
    if prior and _valid_generation(prior.generation)
        and generation <= prior.generation then
        return nil, prior.deadline, false
    end
    local deadline = now + interval
    state[source_name] = { deadline = deadline, generation = generation }
    return interval, deadline, true
end

local function _expected_host_peer_id()
    local mechanism = Managers and Managers.mechanism
    if mechanism and type(mechanism.server_peer_id) == "function" then
        local ok, peer_id = pcall(mechanism.server_peer_id, mechanism)
        if ok and peer_id then return peer_id end
    end

    local network = Managers and Managers.state and Managers.state.network
    if not network then return nil end
    if network.network_client and network.network_client.server_peer_id then
        return network.network_client.server_peer_id
    end
    return network.network_server and network.network_server.server_peer_id or nil
end

local function _install_templates()
    local registry = rawget(_G, "BuffTemplates")
    if type(registry) ~= "table" then return false end

    for _, spec in pairs(BOONS) do
        registry[spec.template] = {
            buffs = {
                {
                    duration = 1,
                    icon = spec.icon,
                    is_cooldown = true,
                    max_stacks = 1,
                    name = spec.template,
                    refresh_durations = true,
                },
            },
        }
    end
    for _, spec in pairs(MANANN_SOURCES) do
        registry[spec.template] = {
            buffs = {
                {
                    duration = 1,
                    icon = spec.icon,
                    is_cooldown = true,
                    max_stacks = 1,
                    name = spec.template,
                    refresh_durations = true,
                },
            },
        }
        -- #358 ready state: NO duration and NO external duration at apply time
        -- (buff_extension.lua:193/:244 leave duration nil -> end_time nil ->
        -- infinite), and no is_cooldown so BuffUI presents an active buff, not
        -- a timer. Removed explicitly by the reconciler / _apply_local swap.
        registry[spec.ready_template] = {
            buffs = {
                {
                    icon = spec.icon,
                    max_stacks = 1,
                    name = spec.ready_template,
                },
            },
        }
    end
    return true
end

-- #358: remove one of OUR client-local display buffs by sub-buff name. The
-- display buffs never carry a server sync id, so remove_buff's
-- _remove_buff_synced path is a structural no-op (buff_extension.lua:1679-1686
-- early-outs on the missing id_to_server_sync entry) - removal stays local.
local function _remove_display_buff(buff_extension, template_name)
    if not buff_extension or type(buff_extension.get_buff_type) ~= "function"
        or type(buff_extension.remove_buff) ~= "function" then
        return false
    end
    local ok, buff = pcall(buff_extension.get_buff_type, buff_extension, template_name)
    if ok and buff and buff.id then
        return pcall(buff_extension.remove_buff, buff_extension, buff.id) == true
    end
    return false
end

local function _has_buff_safe(buff_extension, template_name)
    if not buff_extension or type(buff_extension.has_buff_type) ~= "function" then
        return nil, "buff extension lacks has_buff_type"
    end
    local ok, present = pcall(buff_extension.has_buff_type, buff_extension, template_name)
    if not ok then
        return nil, "buff lookup failed for " .. tostring(template_name)
            .. ": " .. tostring(present)
    end
    return present == true
end

local function _add_buff_safe(buff_extension, template_name, duration)
    if not buff_extension or type(buff_extension.add_buff) ~= "function" then
        return false, "buff extension lacks add_buff"
    end
    local params = duration and { external_optional_duration = duration } or nil
    local ok, result = pcall(buff_extension.add_buff, buff_extension, template_name, params)
    if not ok then
        return false, "buff add failed for " .. tostring(template_name)
            .. ": " .. tostring(result)
    end
    return true
end

local function _hide_spec(buff_extension, spec)
    _remove_display_buff(buff_extension, spec.ready_template)
    _remove_display_buff(buff_extension, spec.template)
end

local function _ensure_cooldown(buff_extension, spec, remaining, replace)
    local cooling, error_message = _has_buff_safe(buff_extension, spec.template)
    if cooling == nil then return false, error_message end
    if replace and cooling then
        _remove_display_buff(buff_extension, spec.template)
        cooling = false
    end
    _remove_display_buff(buff_extension, spec.ready_template)
    if not cooling then
        local added, add_error = _add_buff_safe(buff_extension, spec.template, remaining)
        if not added then return false, add_error end
        cooling, error_message = _has_buff_safe(buff_extension, spec.template)
        if cooling == nil then return false, error_message end
        if not cooling then return false, "cooldown display was not retained" end
    end
    return true
end

local function _ensure_ready(buff_extension, spec)
    _remove_display_buff(buff_extension, spec.template)
    local ready, error_message = _has_buff_safe(buff_extension, spec.ready_template)
    if ready == nil then return false, error_message end
    if ready then return true, false end
    local added, add_error = _add_buff_safe(buff_extension, spec.ready_template)
    if not added then return false, add_error end
    ready, error_message = _has_buff_safe(buff_extension, spec.ready_template)
    if ready == nil then return false, error_message end
    if not ready then return false, "ready display was not retained" end
    return true, true
end

local function _apply_local(owner_unit, boon_name, interval, generation)
    local spec = _spec(boon_name)
    if not spec or not _valid_interval(interval) or not owner_unit then return false end

    -- #357 keeps its established client-local timer path unchanged.
    if not spec.ready_template then
        if generation ~= nil then return false end
        local buff_extension = _buff_extension_safe(owner_unit)
        if not buff_extension or type(buff_extension.add_buff) ~= "function" then return false end
        local ok = pcall(buff_extension.add_buff, buff_extension, spec.template, {
            external_optional_duration = interval,
        })
        if ok then
            pcall(printf, "[ct:cooldown-display] name=%s duration=%.1fs",
                boon_name, interval)
        end
        return ok
    end

    -- #358: record the semantic deadline before touching the optional HUD buff.
    -- If the add races extension churn, the next reconcile can still restore
    -- the correct remaining duration. No usable game clock means no mutation:
    -- a made-up deadline would be worse than a temporarily absent display.
    local now = _game_time_safe()
    if now == nil then return false end
    local remaining, _, accepted = _accept_manann_receipt(
        owner_unit, boon_name, now, interval, generation)
    if not accepted then return false end

    -- Semantic receipt ownership precedes optional buff-extension readiness.
    -- If the extension churns, the reconciler can still materialize the exact
    -- remaining duration later.
    local buff_extension = _buff_extension_safe(owner_unit)
    if not buff_extension or type(buff_extension.add_buff) ~= "function" then return true end
    _remove_display_buff(buff_extension, spec.ready_template)
    local ok = _ensure_cooldown(buff_extension, spec, remaining, true)
    if ok then
        pcall(printf, "[ct:cooldown-display] name=%s duration=%.1fs",
            boon_name, remaining)
    end
    return ok
end

-- ============================================================
-- #358 ready-state reconciler (owner-local, presentation only)
-- ============================================================
-- Runs on EVERY machine for the LOCAL player only, off the shared mod.update
-- dispatch (mod._ct_manann_ready_tick, drained by _ct_host_state_transport_
-- owner's update). Per source: shows the infinite ready buff while the toggle
-- is on, the source is owned, and its mirrored deadline has expired. Source
-- loss/toggle-off hides both display buffs without erasing a live deadline;
-- reacquisition resumes the exact remaining duration. Rejected procs never
-- call notify_allowed and therefore cannot stamp or extend a deadline.

local function _toggle_on()
    local eff = mod._ct_effective_setting
    if type(eff) == "function" then
        local ok, v = pcall(eff, "tweak_manann_tempest_cooldown")
        if ok then return v == true end
    end
    if type(mod.get) == "function" then
        local ok, v = pcall(mod.get, mod, "tweak_manann_tempest_cooldown")
        return ok and v == true
    end
    return false
end

local function _owns_source(buff_extension, spec)
    if spec.owner_buff then
        local ok, has = pcall(buff_extension.has_buff_type, buff_extension, spec.owner_buff)
        if not ok then
            return false, "owner buff lookup failed: " .. tostring(has)
        end
        return has == true
    end
    if spec.owner_prefix and type(buff_extension.active_buffs) == "function" then
        local ok, buffs, num = pcall(buff_extension.active_buffs, buff_extension)
        if not ok then
            return false, "owner buff enumeration failed: " .. tostring(buffs)
        end
        if type(buffs) ~= "table" then
            return false, "owner buff enumeration returned a non-table"
        end
        for i = 1, (num or #buffs) do
            local buff = buffs[i]
            local buff_type = buff and buff.buff_type
            if type(buff_type) == "string"
                and buff_type:find(spec.owner_prefix, 1, true) == 1 then
                return true
            end
        end
    end
    return false
end

function M.reconcile_manann_ready()
    local player, player_error = _local_player_safe()
    if player_error then return false, player_error end
    if not player then return true end
    local unit = player and player.player_unit
    local buff_extension, extension_error = _buff_extension_safe(unit)
    if extension_error then return false, extension_error end
    if not buff_extension or type(buff_extension.add_buff) ~= "function"
        or type(buff_extension.has_buff_type) ~= "function" then
        return true
    end

    local enabled = _toggle_on()
    local now, time_error = _game_time_safe()
    if time_error then
        for _, spec in pairs(MANANN_SOURCES) do _hide_spec(buff_extension, spec) end
        return false, time_error
    end
    if now == nil then
        for _, spec in pairs(MANANN_SOURCES) do _hide_spec(buff_extension, spec) end
        return true
    end
    _align_unit_clock(unit, now)

    local first_error
    for source_name, spec in pairs(MANANN_SOURCES) do
        local owned, ownership_error = _owns_source(buff_extension, spec)
        if ownership_error then
            _hide_spec(buff_extension, spec)
            first_error = first_error or ownership_error
        elseif not enabled or not owned then
            -- Visibility is source/toggle scoped; the semantic deadline is not.
            _hide_spec(buff_extension, spec)
        else
            local remaining = _deadline_remaining(unit, source_name, now)
            if remaining then
                local ok, ensure_error = _ensure_cooldown(
                    buff_extension, spec, remaining, false)
                if not ok then first_error = first_error or ensure_error end
            else
                local ok, added_or_error = _ensure_ready(buff_extension, spec)
                if not ok then
                    first_error = first_error or added_or_error
                elseif added_or_error then
                    pcall(printf, "[ct:issue358] ready-state shown source=%s", source_name)
                end
            end
        end
    end
    if first_error then return false, first_error end
    return true
end

-- VMF stops calling update while the mod is disabled, so the normal ticker
-- cannot perform its next cleanup pass. This explicit lifecycle path removes
-- only our client-local presentation buffs and retains the current deadlines
-- for an accurate same-unit re-enable.
function M.hide_manann_displays()
    local player, player_error = _local_player_safe()
    if player_error then return false, player_error end
    if not player or not player.player_unit then return true end
    local buff_extension, extension_error = _buff_extension_safe(player.player_unit)
    if extension_error then return false, extension_error end
    if not buff_extension then return true end
    for _, spec in pairs(MANANN_SOURCES) do _hide_spec(buff_extension, spec) end
    return true
end

local function _report_reconcile_error(error_message)
    local fingerprint = tostring(error_message or "unknown error")
    if fingerprint == M._issue358_last_error then return end
    M._issue358_last_error = fingerprint
    if (M._issue358_error_count or 0) >= ISSUE358_ERROR_LOG_LIMIT then return end
    M._issue358_error_count = (M._issue358_error_count or 0) + 1
    pcall(printf, "[ct:issue358] ready reconcile errored: %s", fingerprint)
end

function M.install_ready_ticker()
    if M._ready_ticker_installed then return true end
    M._ready_accum = 0
    -- Field dispatch, not a mod.update wrap: _ct_host_state_transport_owner's
    -- mod.update drains `mod._ct_manann_ready_tick` by name each frame (same
    -- pattern as _ct_tally_tick / _ct_freeze487), so install order vs. the
    -- update assignment does not matter.
    mod._ct_manann_ready_tick = function(dt)
        M._ready_accum = (M._ready_accum or 0) + (dt or 0)
        if M._ready_accum < READY_TICK_INTERVAL_S then return end
        M._ready_accum = 0
        local ok, reconciled, err = pcall(M.reconcile_manann_ready)
        if not ok then
            _report_reconcile_error(reconciled)
        elseif reconciled == false then
            _report_reconcile_error(err)
        else
            M._issue358_last_error = nil
        end
    end
    M._ready_ticker_installed = true
    return true
end

function M.install(schema_version)
    if M._installed then return true end
    if type(schema_version) ~= "number" or not _install_templates() then return false end
    M.install_ready_ticker()

    M._schema_version = schema_version
    mod:network_register(CHANNEL, function(sender_peer_id, received_schema, boon_name, interval,
            generation)
        if received_schema ~= M._schema_version then
            pcall(printf, "[ct:cooldown-display] dropped: schema=%s expected=%s sender=%s",
                tostring(received_schema), tostring(M._schema_version), tostring(sender_peer_id))
            return
        end
        local host_peer_id = _expected_host_peer_id()
        if not host_peer_id or sender_peer_id ~= host_peer_id then
            pcall(printf, "[ct:cooldown-display] dropped: non-host sender=%s expected=%s",
                tostring(sender_peer_id), tostring(host_peer_id))
            return
        end
        if not M.valid_payload(boon_name, interval, generation) then
            pcall(printf,
                "[ct:cooldown-display] dropped: invalid payload name=%s interval=%s generation=%s",
                tostring(boon_name), tostring(interval), tostring(generation))
            return
        end

        local player, player_error = _local_player_safe()
        if player_error then
            _report_reconcile_error(player_error)
            return
        end
        _apply_local(player and player.player_unit, boon_name, interval, generation)
    end)
    M._installed = true
    return true
end

-- Called only from the existing gate's allowed branch. This function repeats the
-- authority check so a client-side invocation can never forge a HUD cooldown.
function M.notify_allowed(owner_unit, boon_name, interval, generation)
    if not (Managers and Managers.player and Managers.player.is_server) then return false end
    if not _spec(boon_name) or not _valid_interval(interval) then return false end

    local owner = Managers.player:owner(owner_unit)
    if not owner or owner.bot_player then return false end
    if type(owner.is_player_controlled) == "function"
        and not owner:is_player_controlled() then return false end

    local spec = _spec(boon_name)
    if spec.ready_template and not _valid_generation(generation) then return false end
    if not spec.ready_template and generation ~= nil then return false end

    if owner.local_player then
        return _apply_local(owner_unit, boon_name, interval, generation)
    end

    local peer_id = owner.network_id and owner:network_id()
    if not peer_id then return false end
    if spec.ready_template then
        mod:network_send(CHANNEL, peer_id, M._schema_version, boon_name, interval, generation)
    else
        -- #357 retains its exact four-field event payload.
        mod:network_send(CHANNEL, peer_id, M._schema_version, boon_name, interval)
    end
    return true
end

function M.valid_payload(boon_name, interval, generation)
    local spec = _spec(boon_name)
    if not spec or not _valid_interval(interval) then return false end
    if spec.ready_template then return _valid_generation(generation) end
    return generation == nil
end

function M.regression_check(schema_version)
    if not M._installed or M._schema_version ~= schema_version then
        return "display module not installed with current schema"
    end
    local registry = rawget(_G, "BuffTemplates")
    for boon_name, spec in pairs(BOONS) do
        local buff = registry and registry[spec.template]
        local sub = buff and buff.buffs and buff.buffs[1]
        if not sub or sub.icon ~= spec.icon or sub.is_cooldown ~= true then
            return "invalid local template for " .. boon_name
        end
    end
    if _valid_interval(0) or _valid_interval(0 / 0) then
        return "interval validation accepts zero or NaN"
    end
    return nil
end

function M.regression_check_manann(schema_version)
    if not M._installed or M._schema_version ~= schema_version then
        return "display module not installed with current schema"
    end
    local registry = rawget(_G, "BuffTemplates")
    local names = {}
    for source_name, spec in pairs(MANANN_SOURCES) do
        local buff = registry and registry[spec.template]
        local sub = buff and buff.buffs and buff.buffs[1]
        if not sub or sub.icon ~= "deus_icon_trait_crit_chain_lightning"
            or sub.is_cooldown ~= true then
            return "invalid Manann display template for " .. source_name
        end
        if names[spec.template] then return "Manann sources share one timer template" end
        names[spec.template] = true
        -- #358 ready state: an infinite active buff, distinct from the timer.
        local ready = registry and registry[spec.ready_template]
        local ready_sub = ready and ready.buffs and ready.buffs[1]
        if not ready_sub or ready_sub.icon ~= "deus_icon_trait_crit_chain_lightning" then
            return "invalid Manann ready template for " .. source_name
        end
        if ready_sub.duration ~= nil or ready_sub.is_cooldown then
            return "Manann ready template must be an infinite active buff for " .. source_name
        end
        if names[spec.ready_template] then
            return "Manann ready/cooldown templates must be distinct"
        end
        names[spec.ready_template] = true
        if not (spec.owner_buff or spec.owner_prefix) then
            return "Manann source lacks an ownership probe: " .. source_name
        end
    end
    if not M.valid_payload("manann_boon", 8, 1)
        or not M.valid_payload("manann_trait", 8, 1)
        or M.valid_payload("manann_trait", 8, 0)
        or M.valid_payload("manann_trait", 8, 1.5)
        or M.valid_payload("manann_trait", 8, MAX_MANANN_GENERATION + 1) then
        return "Manann payload vocabulary missing"
    end
    if not M._ready_ticker_installed
        or type(mod._ct_manann_ready_tick) ~= "function" then
        return "Manann ready-state reconciler not installed"
    end
    local deadline_meta = getmetatable(MANANN_DEADLINES)
    if not deadline_meta or deadline_meta.__mode ~= "k" then
        return "Manann deadline mirror must use weak player-unit keys"
    end
    if type(M.hide_manann_displays) ~= "function"
        or type(M.deadline_for) ~= "function"
        or type(M.generation_for) ~= "function" then
        return "Manann deadline lifecycle API missing"
    end
    return nil
end

-- Read-only semantic inspection for the runtime check and deterministic tests.
function M.deadline_for(unit, source_name)
    local state = unit and _deadline_state(unit, false)
    local receipt = state and state[source_name]
    return receipt and receipt.deadline or nil
end

function M.generation_for(unit, source_name)
    local state = unit and _deadline_state(unit, false)
    local receipt = state and state[source_name]
    return receipt and receipt.generation or nil
end

M.channel = CHANNEL
M.boons = BOONS
M.manann_sources = MANANN_SOURCES
M.max_manann_generation = MAX_MANANN_GENERATION
M._issue358_error_count = 0

return M
