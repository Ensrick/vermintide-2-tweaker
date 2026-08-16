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

local function _spec(display_name)
    return BOONS[display_name] or MANANN_SOURCES[display_name]
end

local function _valid_interval(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value <= MAX_INTERVAL_SECONDS
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

local function _apply_local(owner_unit, boon_name, interval)
    local spec = _spec(boon_name)
    if not spec or not _valid_interval(interval) or not owner_unit then return false end

    local buff_extension = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner_unit, "buff_system")
    if not buff_extension or type(buff_extension.add_buff) ~= "function" then return false end

    -- #358: an allowed proc swaps the persistent ready state for the finite
    -- cooldown display; the reconciler restores ready when the timer expires.
    if spec.ready_template then
        _remove_display_buff(buff_extension, spec.ready_template)
    end
    local ok = pcall(buff_extension.add_buff, buff_extension, spec.template, {
        external_optional_duration = interval,
    })
    if ok then
        pcall(printf, "[ct:cooldown-display] name=%s duration=%.1fs",
            boon_name, interval)
    end
    return ok
end

-- ============================================================
-- #358 ready-state reconciler (owner-local, presentation only)
-- ============================================================
-- Runs on EVERY machine for the LOCAL player only, off the shared mod.update
-- dispatch (mod._ct_manann_ready_tick, drained by _ct_host_state_transport_
-- owner's update). Per source: shows the infinite ready buff while the toggle
-- is on and the source is owned and no cooldown display is running; removes
-- BOTH display buffs on toggle-off or source loss (issue #358 fix contract).
-- Expiry restoration falls out of the scan: the finite cooldown buff is
-- removed by the buff extension at end_time, so the next tick sees
-- "owned + no cooldown + no ready" and re-adds ready. Rejected procs never
-- call notify_allowed, so nothing here can refresh a running timer.
-- Presentation-only drift note: unwielding the trait weapon mid-cooldown
-- removes both displays (source loss); re-wielding inside the same 8s window
-- shows ready up to 8s early. The host gate bucket stays authoritative -
-- an early ready icon never unlocks an early proc.
local READY_TICK_INTERVAL_S = 0.5

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
        return ok and has == true
    end
    if spec.owner_prefix and type(buff_extension.active_buffs) == "function" then
        local ok, buffs, num = pcall(buff_extension.active_buffs, buff_extension)
        if not ok or type(buffs) ~= "table" then return false end
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
    local player_manager = Managers and Managers.player
    local player = player_manager and type(player_manager.local_player) == "function"
        and player_manager:local_player(1)
    local unit = player and player.player_unit
    local buff_extension = unit and ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(unit, "buff_system")
    if not buff_extension or type(buff_extension.add_buff) ~= "function"
        or type(buff_extension.has_buff_type) ~= "function" then
        return
    end

    local enabled = _toggle_on()
    for source_name, spec in pairs(MANANN_SOURCES) do
        local show = enabled and _owns_source(buff_extension, spec)
        local cooling = buff_extension:has_buff_type(spec.template) == true
        local ready = buff_extension:has_buff_type(spec.ready_template) == true
        if not show then
            -- Toggle off or source absent: no ready state and no stale timer.
            if ready then _remove_display_buff(buff_extension, spec.ready_template) end
            if cooling then _remove_display_buff(buff_extension, spec.template) end
        elseif cooling then
            -- Timer running: the two states are mutually exclusive.
            if ready then _remove_display_buff(buff_extension, spec.ready_template) end
        elseif not ready then
            -- Acquisition, or the finite cooldown display just expired.
            pcall(buff_extension.add_buff, buff_extension, spec.ready_template)
            if buff_extension:has_buff_type(spec.ready_template) then
                pcall(printf, "[ct:issue358] ready-state shown source=%s", source_name)
            end
        end
    end
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
        local ok, err = pcall(M.reconcile_manann_ready)
        if not ok then
            pcall(printf, "[ct:issue358] ready reconcile errored: %s", tostring(err))
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
    mod:network_register(CHANNEL, function(sender_peer_id, received_schema, boon_name, interval)
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
        if not _spec(boon_name) or not _valid_interval(interval) then
            pcall(printf, "[ct:cooldown-display] dropped: invalid payload name=%s interval=%s",
                tostring(boon_name), tostring(interval))
            return
        end

        local player_manager = Managers and Managers.player
        local player = player_manager and player_manager:local_player(1)
        _apply_local(player and player.player_unit, boon_name, interval)
    end)
    M._installed = true
    return true
end

-- Called only from the existing gate's allowed branch. This function repeats the
-- authority check so a client-side invocation can never forge a HUD cooldown.
function M.notify_allowed(owner_unit, boon_name, interval)
    if not (Managers and Managers.player and Managers.player.is_server) then return false end
    if not _spec(boon_name) or not _valid_interval(interval) then return false end

    local owner = Managers.player:owner(owner_unit)
    if not owner or owner.bot_player then return false end
    if type(owner.is_player_controlled) == "function"
        and not owner:is_player_controlled() then return false end

    if owner.local_player then
        return _apply_local(owner_unit, boon_name, interval)
    end

    local peer_id = owner.network_id and owner:network_id()
    if not peer_id then return false end
    mod:network_send(CHANNEL, peer_id, M._schema_version, boon_name, interval)
    return true
end

function M.valid_payload(boon_name, interval)
    return _spec(boon_name) ~= nil and _valid_interval(interval)
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
    if not M.valid_payload("manann_boon", 8)
        or not M.valid_payload("manann_trait", 8) then
        return "Manann payload vocabulary missing"
    end
    if not M._ready_ticker_installed
        or type(mod._ct_manann_ready_tick) ~= "function" then
        return "Manann ready-state reconciler not installed"
    end
    return nil
end

M.channel = CHANNEL
M.boons = BOONS
M.manann_sources = MANANN_SOURCES

return M
