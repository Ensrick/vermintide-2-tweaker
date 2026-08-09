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

-- #424: every cwv pickup key whose already-spawned world unit must be removed
-- before a non-cwv peer can extract its game object. A pickup that is merely
-- LYING IN THE LEVEL is a crash for that peer even though no cwv RPC ever ran:
-- PickupSystem._spawn_pickup routes through spawn_network_unit
-- (pickup_system.lua:1278), the pickup game object carries the name as a
-- NetworkLookup.pickup_names INDEX (game_object_initializers_extractors.lua:880),
-- and the joining client decodes that index STRICTLY - no rawget - at
-- game_object_initializers_extractors.lua:3411.
--
-- install() seeds the two thrown-javelin recovery pickups. The grenade-slot
-- bomb pickup registers itself through fence_pickup() because its entry block
-- loads AFTER install(), and pool ejection alone only stops future rolls.
M.fenced_pickup_names = {}

function M.fence_pickup(pickup_name)
    if type(pickup_name) ~= "string" or pickup_name == "" then return false end
    local list = M.fenced_pickup_names
    for index = 1, #list do
        if list[index] == pickup_name then return false end
    end
    list[#list + 1] = pickup_name
    return true
end

-- A peer acknowledgement is only ONE axis of exact wire safety. Revalidate the
-- committed receiver AND the local numeric/resource catalog at the actual
-- hot-join boundary, so a registry drift that happened after the ack cannot
-- authorize custom data for that peer. Any missing arm reads false.
function M.exact_peer_safe(parity, peer_id, catalog_intact)
    if type(parity) ~= "table" or type(catalog_intact) ~= "function" then
        return false
    end
    local ok_i, installed = pcall(parity.is_installed, parity)
    local ok_p, has = pcall(parity.peer_has, parity, peer_id)
    local ok_c, intact = pcall(catalog_intact)
    return ok_i and installed == true and ok_p and has == true
        and ok_c and intact == true
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
    -- #423/#424 exact-catalog wiring. `wire_safe` is mod._cwv_thrown_wire_safe
    -- (installed by _cwv_exact_wire_runtime BEFORE this call); donor_policy is
    -- _cwv_thrown_wire_policy; globals is the live global table.
    local wire_safe = ctx.wire_safe
    local catalog_intact = ctx.catalog_intact
    local donor_policy = assert(ctx.donor_policy, "javelin gate requires donor policy")
    local globals = assert(ctx.globals, "javelin gate requires live globals")

    -- Per-peer verdict for the hot-join boundary: the joining peer must have
    -- acknowledged BOTH the presence beacon and the exact thrown catalog, and
    -- our own catalog must still be undrifted.
    local function exact_peer_safe(peer_id)
        return M.exact_peer_safe(mod._cwv_peer_parity, peer_id, catalog_intact)
            and M.exact_peer_safe(mod._cwv_thrown_peer_parity, peer_id, catalog_intact)
    end

    local function gate_state()
        local pp = mod._cwv_peer_parity
        if not (pp and type(pp.applied_state) == "function") then return "disabled" end
        local ok, state = pcall(pp.applied_state, pp)
        if not (ok and state == "enabled") then return "disabled" end
        -- Presence parity proves every peer HAS cwv; it does not prove their
        -- appended NetworkLookup integers mean the same thing (BUG_CLASSES 64).
        -- The thrown feature additionally requires the exact thrown-resource
        -- channel to be installed, agreed, and undrifted. An absent or erroring
        -- wire_safe reads disabled -- the feature never opens on a missing proof.
        local ok_exact, exact = pcall(wire_safe)
        return (ok_exact and exact == true) and "enabled" or "disabled"
    end

    local function wielded_javelin(owner_unit)
        if not (owner_unit and Unit.alive(owner_unit)) then return false end
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        if not inv then return false end
        local ok, slot_data = pcall(function() return inv:get_wielded_slot_data() end)
        return ok and M.is_cwv_javelin(slot_data) or false
    end

    -- Match the action's OWN item_name as well as the wielded slot. The two
    -- disagree in real frames: a grenade-slot throw runs while the melee slot
    -- reads as wielded, and an action mid-flight outlives a wield swap. The
    -- slot read alone let those throws through the gate.
    local function block_throw(self)
        return self and (M.is_cwv_javelin(self.item_name)
                or wielded_javelin(self.owner_unit))
            and not M.feature_enabled(gate_state())
    end

    mod:hook("ActionThrownProjectile", "_fire", function(func, self, add_spread)
        if block_throw(self) then
            self._cwv424_throw_blocked = true
            if not self._cwv424_notice_shown then
                self._cwv424_notice_shown = true
                -- The player pressed throw and nothing happened, so the reason
                -- belongs in chat, not only in the log.
                -- allow-echo: user-triggered safety block
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

    -- Last-resort source-shaped floor for any action class that reaches
    -- ProjectileSystem directly. `_get_projectile_units_names` has NO nil
    -- contract: vanilla dereferences `.projectile_unit_name` on the very next
    -- line (projectile_system.lua:247-249). Now that donor revalidation can
    -- legitimately produce a DROP, that dereference is reachable -- so probe the
    -- already-hooked resolver here and refuse the native spawn when neither the
    -- exact row nor a proven vanilla donor is available.
    -- Hook pre-flight (NON-NEGOTIABLE 8): grepped 2026-08-08 -- cwv hooks
    -- ProjectileSystem._get_projectile_units_names and .rpc_spawn_pickup_projectile
    -- in the entry file; this is the ONLY registration on spawn_player_projectile.
    mod:hook("ProjectileSystem", "spawn_player_projectile", function(func, self,
            owner_unit, position, rotation, scale, angle, target_vector, speed,
            item_name, item_template_name, action_name, sub_action_name,
            fast_forward_time, is_critical_strike, power_level, gaze_settings,
            charge_level)
        if M.is_cwv_javelin(item_name) then
            local ok, projectile_units = pcall(function()
                local weapon_template = WeaponUtils.get_weapon_template(item_template_name)
                local actions = weapon_template and weapon_template.actions
                local action = actions and actions[action_name]
                action = action and action[sub_action_name]
                local projectile_info = action and action.projectile_info
                if not projectile_info then return nil end
                return self:_get_projectile_units_names(projectile_info, owner_unit)
            end)
            if not ok or type(projectile_units) ~= "table"
                    or type(projectile_units.projectile_unit_name) ~= "string" then
                pcall(printf, "[cwv:424] ProjectileSystem spawn BLOCKED: no exact row and no proven vanilla donor for item=%s",
                    tostring(item_name))
                return
            end
        end
        return func(self, owner_unit, position, rotation, scale, angle,
            target_vector, speed, item_name, item_template_name, action_name,
            sub_action_name, fast_forward_time, is_critical_strike, power_level,
            gaze_settings, charge_level)
    end)
    om._cwv424_projectile_preflight_installed = true
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

    M.fence_pickup(pickup_key)
    M.fence_pickup(link_pickup_key)

    -- GameSession.add_peer replays every live network GameObject after
    -- set_peer_synchronizing returns. Shadowing TransientPackageLoader.refs
    -- protects that component's package-id RPC only; it cannot rewrite an
    -- ALREADY-SPAWNED projectile GameObject carrying a custom husk id. Both
    -- live resource classes -- world pickups AND in-flight projectiles -- are
    -- therefore removed as one transaction, and their absence is PROVEN from
    -- the authoritative trackers before the joiner is allowed through.
    local function remove_live_recovery_pickups()
        local state = Managers and Managers.state
        local transition = Managers and Managers.level_transition_handler
        local entity = state and state.entity
        local spawner = state and state.unit_spawner
        local loader = transition and transition.transient_package_loader
        local tracked = loader and loader._tracked_projectiles
        local tracked_units = tracked and tracked.units
        if not entity or not spawner then return true, 0, { projectiles = 0, pickups = 0 } end
        local ok, removed_or_err, projectiles, pickups = pcall(function()
            local pickup_system = entity:system("pickup_system")
            if not pickup_system then return 0, 0, 0 end
            -- Server-only. Retracting a spawned pickup is a host action: the unit
            -- is a server-owned network unit and PickupSystem refuses even the
            -- spawn side on a client (pickup_system.lua:1209-1213), so a client
            -- destroying it locally would desync the session rather than protect
            -- anyone. Every caller before the gate-close on_disable was already
            -- host-side (the set_peer_synchronizing fence); this keeps that true
            -- now that a parity transition can reach here on any peer.
            if not pickup_system.is_server then return 0 end
            local removed, projectiles, pickups = 0, 0, 0
            local seen = {}
            local function mark(unit)
                if not (unit and Unit.alive(unit)) or seen[unit] then return false end
                seen[unit] = true
                if not spawner:is_marked_for_deletion(unit) then
                    spawner:mark_for_deletion(unit)
                end
                removed = removed + 1
                return true
            end
            -- In-flight axis. TransientPackageLoader.add_projectile stores the
            -- exact ProjectileUnits template string in `.units[unit]`
            -- (transient_package_loader.lua:155), so this table is the
            -- authoritative census of live custom projectiles.
            if type(tracked_units) == "table" then
                for unit, template_name in pairs(tracked_units) do
                    if template_name == projectile_key and mark(unit) then
                        projectiles = projectiles + 1
                    end
                end
            end
            for _, pickup_name in ipairs(M.fenced_pickup_names) do
                local units = pickup_system:get_pickups_by_type(pickup_name) or {}
                local snapshot = {}
                for _, unit in pairs(units) do snapshot[#snapshot + 1] = unit end
                for _, unit in ipairs(snapshot) do
                    if mark(unit) then pickups = pickups + 1 end
                end
            end
            if removed > 0 then spawner:commit_and_remove_pending_units() end
            -- Re-read BOTH authoritative trackers after the synchronous commit.
            -- A retained projectile row can still become a custom husk
            -- GameObject and a retained pickup already carries a custom
            -- pickup_names id, so a failed deletion must hold the peer outside
            -- the GameSession rather than be reported as a successful sweep.
            if type(tracked_units) == "table" then
                for unit, template_name in pairs(tracked_units) do
                    if template_name == projectile_key and unit and Unit.alive(unit) then
                        error("custom projectile retained after cleanup")
                    end
                end
            end
            for _, pickup_name in ipairs(M.fenced_pickup_names) do
                local units = pickup_system:get_pickups_by_type(pickup_name) or {}
                for _, unit in pairs(units) do
                    if unit and Unit.alive(unit) then
                        error("custom recovery pickup retained after cleanup: " .. tostring(pickup_name))
                    end
                end
            end
            return removed, projectiles, pickups
        end)
        if not ok then return false, tostring(removed_or_err) end
        return true, removed_or_err, { projectiles = projectiles or 0, pickups = pickups or 0 }
    end
    om._cwv424_remove_live_recovery_pickups = remove_live_recovery_pickups

    local pp = mod._cwv_peer_parity
    if pp and type(pp.register_gated_feature) == "function" then
        pp:register_gated_feature("cwv_tuskgor_javelin_throw", {
            label = "cwv_gated_tuskgor_javelin_throw",
            -- #424: closing the gate stops new emissions but cannot retract a cwv
            -- pickup ALREADY lying in the level, and the grenade-slot bomb's own
            -- gated feature can only eject the spawn pool (future rolls). Sweep
            -- every fenced key on the same transition that closes the gate, so the
            -- world is clean regardless of which seam detected the missing peer -
            -- the set_peer_synchronizing fence below is only one of them. Bounded:
            -- one row per gate close.
            on_disable = function()
                local swept, detail, counts = remove_live_recovery_pickups()
                pcall(printf, "[cwv:424] gate closed; world sweep ok=%s removed=%s projectiles=%s pickups=%s fenced=%d",
                    tostring(swept), tostring(detail),
                    tostring(counts and counts.projectiles), tostring(counts and counts.pickups),
                    #M.fenced_pickup_names)
            end,
        })
        om._cwv424_feature_registered = true
        om._cwv424_gate_close_sweep_installed = true
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
        -- UNCONDITIONAL shadow (never gated on parity or a toggle -- memory
        -- reference_vt2_wire_safety_never_toggle_gated, #278/#371): the custom
        -- ref is removed for EVERY hot-join encode. What the donor proof
        -- decides is only whether a vanilla key may be written in its place; a
        -- donor that is merely PRESENT is not enough, because the joiner
        -- decodes it strictly and a half-registered row fatals the same way.
        local safe_projectile_intact = donor_policy.projectile_donor_intact(
            globals, safe_template_key)
        local safe_unit_intact = safe_projectile_intact and safe_unit ~= nil
            and lookups ~= nil
            and donor_policy.lookup_row_intact(lookups.husks, safe_unit)
        local restore_projectile = M.begin_ref_shadow(
            projectile_refs, projectile_key, safe_template_key,
            safe_projectile_intact == true)
        local restore_unit = M.begin_ref_shadow(
            unit_refs, inflight_unit, safe_unit, safe_unit_intact == true)
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
            local confirmed = exact_peer_safe(peer_id)
            parity:require_peer(peer_id)
            if not confirmed then
                local safe, detail, counts = remove_live_recovery_pickups()
                if not safe then
                    rejected_peers[peer_id] = true
                    pcall(printf, "[cwv:424] hot-join sync REJECTED peer=%s: live thrown-resource cleanup failed: %s",
                        tostring(peer_id), tostring(detail))
                    local server = self and self.network_server
                    if server and type(server.kick_peer) == "function" then
                        pcall(server.kick_peer, server, peer_id)
                    end
                    return
                end
                rejected_peers[peer_id] = nil
                -- fenced= proves WHICH keys the sweep covered: a log line reading
                -- fenced=2 means the grenade-slot bomb never enrolled and a
                -- world-resident bomb pickup can still CTD this joiner (#424).
                pcall(printf, "[cwv:424] hot-join preflight peer=%s gate=disabled removed_pickups=%s removed_projectiles=%s fenced=%d",
                    tostring(peer_id), tostring(counts and counts.pickups),
                    tostring(counts and counts.projectiles), #M.fenced_pickup_names)
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
        -- Retire the peer's proof on EVERY parity instance cwv owns: the
        -- presence beacon and both exact channels (#423 damage, #424 thrown).
        -- The parity library expires an ack on its own only after a bounded
        -- ABSENCE window (_lib_peer_parity.lua:576-583); a disconnect followed
        -- by a fast rejoin under the same peer id lands inside that window, so
        -- without this an exact channel would still read the departed peer as
        -- having proven our catalog and authorize custom ids to a peer that
        -- never re-handshaked. Deduplicated by instance identity so a build
        -- where two of these resolve to the same table forgets once.
        local forgotten = {}
        local function forget_once(instance)
            if type(instance) == "table" and not forgotten[instance]
                    and type(instance.forget_peer) == "function" then
                forgotten[instance] = true
                pcall(instance.forget_peer, instance, peer_id)
            end
        end
        forget_once(mod._cwv_peer_parity)
        forget_once(mod._cwv_thrown_peer_parity)
        forget_once(mod._cwv_damage_peer_parity)
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
    om._cwv424_exact_epoch_retirement_installed = true
    om._cwv424_hot_join_fence_installed = true
end

return M
