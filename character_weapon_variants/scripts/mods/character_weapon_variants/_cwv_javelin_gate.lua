local M = {}

local function _is_javelin_id(value)
    if type(value) ~= "string" then return false end
    if value == "cwv_es_javelin" or value == "cwv_wh_javelin"
            or value == "cwv_grenade_tuskgor_javelin" then
        return true
    end

    -- Backend ids and the generated default skins append a suffix to the
    -- concrete item key. Do not catch the retired/future javelin+shield family:
    -- that is a different weapon and must earn its own wire contract.
    local es_suffix = value:match("^cwv_es_javelin_(.+)$")
    if es_suffix and es_suffix:sub(1, 6) ~= "shield" then return true end
    local wh_suffix = value:match("^cwv_wh_javelin_(.+)$")
    if wh_suffix and wh_suffix:sub(1, 6) ~= "shield" then return true end
    return false
end

local function _candidate_is_javelin(value)
    return _is_javelin_id(value)
end

-- Accept the three shapes used by the live inventory paths: a backend item,
-- its `.data`/`.master_item` wrapper, or a SimpleInventory slot_data row.
-- The inherited vanilla name (`we_javelin`) is deliberately not evidence.
function M.is_cwv_javelin(item)
    if _candidate_is_javelin(item) then return true end
    if type(item) ~= "table" then return false end

    local data = item.item_data or item.data or item.master_item or item
    local mod_data = type(data) == "table" and data.mod_data or nil
    local candidates = {
        item.backend_id, item.ItemId, item.ItemInstanceId, item.skin,
        type(data) == "table" and data.backend_id or nil,
        type(data) == "table" and data.ItemId or nil,
        type(data) == "table" and data.ItemInstanceId or nil,
        type(data) == "table" and data.key or nil,
        type(data) == "table" and data.skin or nil,
        type(mod_data) == "table" and mod_data.backend_id or nil,
    }
    -- The candidate array is intentionally sparse for most wrapper shapes;
    -- `#candidates` is undefined across holes in Lua 5.1, so iterate present
    -- values rather than truncating at the first absent field.
    for _, candidate in pairs(candidates) do
        if _candidate_is_javelin(candidate) then return true end
    end
    return false
end

function M.feature_enabled(applied_state)
    return applied_state == "enabled"
end

function M.should_block(item, applied_state)
    return M.is_cwv_javelin(item) and not M.feature_enabled(applied_state)
end

-- Return the original table when no row is removed. Several callers cache the
-- backend result by identity, so needless copies would be observable churn.
function M.filter_unavailable(items, applied_state)
    if type(items) ~= "table" or M.feature_enabled(applied_state) then
        return items, 0
    end
    local filtered, removed = {}, 0
    for index = 1, #items do
        local item = items[index]
        if M.is_cwv_javelin(item) then
            removed = removed + 1
        else
            filtered[#filtered + 1] = item
        end
    end
    if removed == 0 then return items, 0 end
    return filtered, removed
end

-- Temporarily replace a custom transient-package reference with a registered
-- vanilla reference while a hot-join packet is encoded. The returned closure
-- restores the table byte-for-byte, including an absent fallback entry. This
-- helper is engine-free so the mutation and rollback contract can be tested
-- outside Vermintide.
function M.begin_ref_shadow(refs, custom_key, safe_key, safe_registered)
    if type(refs) ~= "table" or type(custom_key) ~= "string" then
        return function() end, false
    end

    local old_custom = rawget(refs, custom_key)
    local old_safe = type(safe_key) == "string" and rawget(refs, safe_key) or nil
    if old_custom == nil then return function() end, false end

    refs[custom_key] = nil
    if safe_registered and type(safe_key) == "string" then
        refs[safe_key] = (old_safe or 0) + old_custom
    end

    local restored = false
    return function()
        if restored then return end
        restored = true
        refs[custom_key] = old_custom
        if safe_registered and type(safe_key) == "string" then
            refs[safe_key] = old_safe
        end
    end, true
end

-- Own every live hook for the mixed-lobby javelin boundary. Keeping the hook
-- graph here prevents the already-large CWV entry chunk from regrowing while
-- leaving the pure identity/ref-shadow helpers above independently testable.
function M.install(ctx)
    local mod = assert(ctx and ctx.mod, "javelin gate requires mod")
    local om = assert(ctx.om, "javelin gate requires owner state")
    local pickup_key = assert(ctx.pickup_key, "javelin gate requires pickup key")
    local link_pickup_key = assert(ctx.link_pickup_key, "javelin gate requires link pickup key")
    local projectile_key = assert(ctx.projectile_key, "javelin gate requires projectile key")
    local inflight_unit = assert(ctx.inflight_unit, "javelin gate requires inflight unit")
    local safe_template_key = assert(ctx.safe_template_key, "javelin gate requires safe template")

    local function gate_state()
        local pp = mod._cwv_peer_parity
        if not (pp and type(pp.applied_state) == "function") then return "disabled" end
        local ok, state = pcall(pp.applied_state, pp)
        return ok and state or "disabled"
    end

    local function wielded_javelin(owner_unit)
        if not (owner_unit and Unit.alive(owner_unit)) then return false end
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        if not inv then return false end
        local ok, slot_data = pcall(function() return inv:get_wielded_slot_data() end)
        return ok and M.is_cwv_javelin(slot_data) or false
    end

    local function block_throw(self)
        return self and wielded_javelin(self.owner_unit)
            and not M.feature_enabled(gate_state())
    end

    mod:hook("ActionThrownProjectile", "_fire", function(func, self, add_spread)
        if block_throw(self) then
            self._cwv424_throw_blocked = true
            if not self._cwv424_notice_shown then
                self._cwv424_notice_shown = true
                mod:echo("[cwv] Tuskgor Javelin is unavailable until every player in the lobby has Career Weapon Variants.")
                pcall(printf, "[cwv:424] throw BLOCKED before projectile spawn: peer capability=%s",
                    tostring(gate_state()))
            end
            return
        end
        self._cwv424_throw_blocked = nil
        self._cwv424_notice_shown = nil
        return func(self, add_spread)
    end)
    mod:hook("ActionThrownProjectile", "_use_ammo", function(func, self)
        if self._cwv424_throw_blocked then
            self._cwv424_throw_blocked = nil
            return
        end
        return func(self)
    end)
    om._cwv424_throw_gate_installed = true

    mod:hook("ActionUtils", "spawn_pickup_projectile", function(func, world, weapon_unit,
            projectile_unit_name, projectile_unit_template_name, current_action,
            owner_unit, position, rotation, velocity, angular_velocity, item_name, spawn_type)
        if item_name == "cwv_grenade_tuskgor_javelin" and gate_state() ~= "enabled" then
            pcall(printf, "[cwv:424] grenade-slot javelin drop BLOCKED before ActionUtils wire encode")
            return
        end
        return func(world, weapon_unit, projectile_unit_name, projectile_unit_template_name,
            current_action, owner_unit, position, rotation, velocity, angular_velocity,
            item_name, spawn_type)
    end)
    om._cwv424_actionutils_sender_guard_installed = true

    local function remove_live_recovery_pickups()
        local state = Managers and Managers.state
        local entity = state and state.entity
        local spawner = state and state.unit_spawner
        if not entity or not spawner then return true, 0 end
        local ok, removed_or_err = pcall(function()
            local pickup_system = entity:system("pickup_system")
            if not pickup_system then return 0 end
            local removed = 0
            for _, pickup_name in ipairs({ pickup_key, link_pickup_key }) do
                local units = pickup_system:get_pickups_by_type(pickup_name) or {}
                local snapshot = {}
                for _, unit in pairs(units) do snapshot[#snapshot + 1] = unit end
                for _, unit in ipairs(snapshot) do
                    if unit and Unit.alive(unit) and not spawner:is_marked_for_deletion(unit) then
                        spawner:mark_for_deletion(unit)
                        removed = removed + 1
                    end
                end
            end
            if removed > 0 then spawner:commit_and_remove_pending_units() end
            return removed
        end)
        if not ok then return false, tostring(removed_or_err) end
        return true, removed_or_err
    end
    om._cwv424_remove_live_recovery_pickups = remove_live_recovery_pickups

    local pp = mod._cwv_peer_parity
    if pp and type(pp.register_gated_feature) == "function" then
        pp:register_gated_feature("cwv_tuskgor_javelin_throw", {
            label = "cwv_gated_tuskgor_javelin_throw",
        })
        om._cwv424_feature_registered = true
    end

    mod:hook("TransientPackageLoader", "hot_join_sync", function(func, self, peer_id)
        local parity = mod._cwv_peer_parity
        if parity and type(parity.require_peer) == "function" then
            parity:require_peer(peer_id)
        end
        local projectile_refs = self and self._tracked_projectiles and self._tracked_projectiles.refs
        local unit_refs = self and self._tracked_units and self._tracked_units.refs
        local safe_units = rawget(_G, "ProjectileUnits")
        local safe_template = safe_units and safe_units[safe_template_key]
        local safe_unit = safe_template and safe_template.projectile_unit_name
        local lookups = rawget(_G, "NetworkLookup")
        local safe_projectile_registered = lookups and lookups.projectile_units
            and rawget(lookups.projectile_units, safe_template_key)
        local safe_unit_registered = safe_unit and lookups and lookups.husks
            and rawget(lookups.husks, safe_unit)
        local restore_projectile = M.begin_ref_shadow(
            projectile_refs, projectile_key, safe_template_key,
            safe_projectile_registered ~= nil)
        local restore_unit = M.begin_ref_shadow(
            unit_refs, inflight_unit, safe_unit, safe_unit_registered ~= nil)
        local ok, err = pcall(func, self, peer_id)
        restore_unit()
        restore_projectile()
        if not ok then error(err) end
    end)
    om._cwv424_transient_sender_guard_installed = true

    local rejected_peers = {}
    mod:hook("GameNetworkManager", "set_peer_synchronizing", function(func, self, peer_id)
        local parity = mod._cwv_peer_parity
        if type(peer_id) == "string" and parity
                and type(parity.require_peer) == "function"
                and type(parity.peer_has) == "function" then
            local confirmed = parity:peer_has(peer_id)
            parity:require_peer(peer_id)
            if not confirmed then
                local safe, detail = remove_live_recovery_pickups()
                if not safe then
                    rejected_peers[peer_id] = true
                    pcall(printf, "[cwv:424] hot-join sync REJECTED peer=%s: recovery pickup cleanup failed: %s",
                        tostring(peer_id), tostring(detail))
                    local server = self and self.network_server
                    if server and type(server.kick_peer) == "function" then
                        pcall(server.kick_peer, server, peer_id)
                    end
                    return
                end
                rejected_peers[peer_id] = nil
                pcall(printf, "[cwv:424] hot-join preflight peer=%s gate=disabled removed_pickups=%d",
                    tostring(peer_id), detail)
            end
        end
        return func(self, peer_id)
    end)
    mod:hook("NetworkServer", "is_network_state_fully_synced_for_peer", function(func, self, peer_id)
        if rejected_peers[peer_id] then return false end
        return func(self, peer_id)
    end)
    -- CONSOLIDATED hook_safe on (GameNetworkManager, remove_peer) -- the real
    -- peer-teardown seam (game_network_manager.lua:814, invoked from
    -- peer_states.lua:574 on disconnect). Any CWV per-peer teardown belongs in
    -- THIS body; a second registration on the same pair is silently dropped
    -- (CLAUDE.md NON-NEGOTIABLE #8).
    mod:hook_safe("GameNetworkManager", "remove_peer", function(self, peer_id)
        rejected_peers[peer_id] = nil
        local parity = mod._cwv_peer_parity
        if parity and type(parity.forget_peer) == "function" then
            parity:forget_peer(peer_id)
        end
        -- #914: clear the appearance lifecycle's per-peer ledgers (exact
        -- identity states, accepted request generations, pending deliveries)
        -- so a later rejoin under the same peer id cannot reuse stale exact
        -- appearance or a coalesced request generation. The lifecycle is
        -- installed later in the entry file (_om._appearance_lifecycle), so
        -- resolve it lazily at event time.
        local lifecycle = om._appearance_lifecycle
        if lifecycle and type(lifecycle.clear_peer) == "function" then
            pcall(lifecycle.clear_peer, lifecycle, peer_id)
        end
    end)
    om._cwv424_hot_join_fence_installed = true
end

return M
