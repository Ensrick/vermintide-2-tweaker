-- Owns LA remote-husk identity helpers and the husk-initialization replay edge.
--
-- This concern resolves authored variants, rejects cross-skeleton hats, purges
-- stale peer slots, publishes the mission-state dump, and exposes the one
-- wielded-item identity predicate consumed by the LA apply runtime.  Keeping
-- these policies together makes the spawn monitor and every consumer use the
-- same character and slot authority.

local HuskIdentityRuntime = {}

local function chars_compatible(owner_char_path, la_unit_path, profile_base)
    local la_char = string.match(
        la_unit_path or "", "^units/beings/player/([^/]+)/")
    if not la_char then return true end
    if owner_char_path then
        local owner_char = string.match(
            owner_char_path, "^units/beings/player/([^/]+)/")
        if owner_char then
            if owner_char == la_char then return true end
            return false, ("owner_char=%s la_char=%s"):format(
                owner_char, la_char)
        end
    end
    if profile_base then
        if la_char == profile_base
                or string.sub(la_char, 1, #profile_base + 1)
                    == profile_base .. "_" then
            return true
        end
        return false, ("profile_base=%s la_char=%s"):format(
            profile_base, la_char)
    end
    return false, "no owner_char_path AND no profile_base resolvable"
end

local function purge_stale_peer_slot(cache, wearer_peer, slot_name)
    if not (cache and wearer_peer and slot_name) then return false end
    local equips = cache[wearer_peer]
    if not (equips and equips[slot_name]) then return false end
    equips[slot_name] = nil
    if next(equips) == nil then cache[wearer_peer] = nil end
    return true
end

local function publish_owner(mod, state)
    local owner = mod._cos_la_husk_identity_runtime_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = state.hook_count or 0
    owner.resolve_la_variant = state.resolve_la_variant
    owner.chars_compatible = chars_compatible
    owner.purge_stale_peer_slot = purge_stale_peer_slot
    owner.level_world = state.level_world
    owner.wielded_item_matches = state.wielded_item_matches
    mod._cos_la_husk_identity_runtime_owner = owner
    return owner
end

function HuskIdentityRuntime.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_la_husk_identity_runtime_state
    if not state then
        state = { installed = false, hook_count = 0 }
        mod._cos_la_husk_identity_runtime_state = state
    end

    state.gk_set = deps.gk_set
    state.custom_hats = deps.custom_hats
    state.get_mod = assert(deps.get_mod, "get_mod is required")
    state.husk_identity = assert(deps.husk_identity,
        "husk_identity is required")
    state.la_bridge = assert(deps.la_bridge, "la_bridge is required")
    state.la_equips_by_peer = assert(deps.la_equips_by_peer,
        "la_equips_by_peer is required")
    state.la_persist = assert(deps.la_persist, "la_persist is required")
    state.score_identity = assert(deps.score_identity,
        "score_identity is required")
    state.script_unit = deps.script_unit
    state.unit = assert(deps.unit, "unit is required")
    state.get_managers = assert(deps.get_managers,
        "get_managers is required")
    state.get_profiles = assert(deps.get_profiles,
        "get_profiles is required")
    state.la_replay_policy = assert(deps.la_replay_policy,
        "la_replay_policy is required")
    state.dbg = assert(deps.dbg, "dbg is required")
    state.dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    state.printf = deps.printf

    state.resolve_la_variant = state.resolve_la_variant or function(armoury_key)
        local gk_set = state.gk_set
        if gk_set and gk_set.resolve_variant then
            local authored = gk_set.resolve_variant(armoury_key)
            if authored then return authored, nil end
        end
        local custom_hats = state.custom_hats
        if custom_hats and custom_hats.resolve_variant then
            local custom = custom_hats.resolve_variant(armoury_key)
            if custom then return custom, nil end
        end
        local la = state.get_mod("Loremasters-Armoury")
        if not la or type(la.SKIN_LIST) ~= "table" then return nil, nil end
        return la.SKIN_LIST[armoury_key], la
    end

    state.level_world = state.level_world or function()
        local managers = state.get_managers()
        if managers and managers.world and managers.world.has_world
                and managers.world:has_world("level_world") then
            return managers.world:world("level_world")
        end
        return nil
    end

    state.wielded_item_matches = state.wielded_item_matches
        or function(inv, equipment, slot_name, allow_slot_key)
            local w_slot_name = state.la_replay_policy.wielded_slot(
                inv, equipment)
            local w_slot_data = equipment and equipment.slots and w_slot_name
                and equipment.slots[w_slot_name]
            local w_item = w_slot_data and w_slot_data.item_data
            if not w_item then return false, nil end
            local match = (slot_name == w_item.template)
                or (slot_name == w_item.name)
                or (slot_name == w_item.key)
                or (slot_name == w_item.item_type)
                or (allow_slot_key == true and slot_name == w_slot_name)
            -- #476: a CWV wearer stores weapon-side entries under OWNER-LOCAL
            -- keys (variant item_type + variant template). The husk wields the
            -- vanilla BASE item, so no candidate above can ever produce those
            -- keys on an observer. Extend the candidate set with the wearer's
            -- exact CWV variant identity, resolved through the same
            -- fingerprint-validated provider the #583 dual-hand check uses.
            -- Fails closed to the vanilla family (candidates stay unchanged)
            -- and never admits the shared base template (#514 collision).
            if not match then
                local peer_identity = mod._cos_cwv_peer_identity
                local player = inv and (inv._player or inv.player)
                local wearer_peer = player and player.peer_id
                if wearer_peer and peer_identity
                        and type(peer_identity.husk_variant_candidates)
                            == "function" then
                    local cands = peer_identity.husk_variant_candidates(
                        state.get_mod("character_weapon_variants"),
                        { wearer_peer = wearer_peer, slot_name = w_slot_name },
                        w_item)
                    if cands then
                        match = (slot_name == cands.variant_key)
                            or (cands.template ~= nil
                                and slot_name == cands.template)
                    end
                end
            end
            return match, w_item
        end

    mod._la_chars_compatible = chars_compatible
    mod._purge_stale_peer_slot = purge_stale_peer_slot
    mod._la_wielded_item_matches = state.wielded_item_matches

    -- Refresh the monitor on reload. The one installed hook reads it from the
    -- mod table at action time, so registration cardinality remains stable.
    mod._la_spawn_monitor = state.husk_identity.make_spawn_monitor({
        bridge = state.la_bridge,
        store = state.la_equips_by_peer,
        persistence = state.la_persist,
        score_identity = state.score_identity,
        script_unit = state.script_unit,
        unit_api = state.unit,
        managers = state.get_managers,
        profiles = state.get_profiles,
        resolve_variant = state.resolve_la_variant,
        chars_compatible = chars_compatible,
        purge = purge_stale_peer_slot,
        debug = state.dbg,
        warning = function(...) mod:warning(...) end,
        print = function(...)
            if state.printf then state.printf(...) end
        end,
    })

    mod._la_dump_mission_state = function(reason)
        state.dbg("[la-state-dump] reason=%s", tostring(reason))
        local n_peers = 0
        for peer, slots in pairs(state.la_equips_by_peer) do
            n_peers = n_peers + 1
            for slot, entry in pairs(slots) do
                state.dbg("[la-state-dump]   peer=%s slot=%s kind=%s armoury=%s vanilla=%s",
                    tostring(peer), tostring(slot), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.vanilla_key))
            end
        end
        local persisted = mod:get("la_persisted_equips") or {}
        local n_careers = 0
        if persisted.careers then
            for career, slots in pairs(persisted.careers) do
                n_careers = n_careers + 1
                state.dbg("[la-state-dump]   persisted career=%s hat=%s skin=%s",
                    tostring(career), tostring(slots.slot_hat or "-"),
                    tostring(slots.slot_skin or "-"))
            end
        end
        local n_illusions = 0
        if persisted.illusions then
            for _ in pairs(persisted.illusions) do
                n_illusions = n_illusions + 1
            end
        end
        state.dbg("[la-state-dump] totals: %d live peer(s), %d persisted career entr(ies), %d persisted illusion(s)",
            n_peers, n_careers, n_illusions)
    end

    if state.installed then return publish_owner(mod, state) end

    -- SimpleHuskInventoryExtension has no extensions_ready method. Its init is
    -- the remote-player spawn seam; local-player persistence already owns the
    -- corresponding SimpleInventoryExtension hook.
    mod:hook_safe("SimpleHuskInventoryExtension", "init",
        function(self, extension_init_context, unit, extension_init_data)
            if mod._la_spawn_monitor then
                local ok, err = pcall(mod._la_spawn_monitor, unit)
                if not ok then
                    state.dbg_alert(
                        "[la-spawn-monitor] pcall err: %s", tostring(err))
                end
            end
            if mod._cos_replay then
                local wearer_peer
                local managers = state.get_managers()
                local pm = managers and managers.player
                if pm and pm.owner then
                    local owner = pm:owner(unit)
                    wearer_peer = owner and owner.peer_id or nil
                end
                mod._cos_replay.on_edge("peer-ready",
                    wearer_peer and {
                        only_peer = wearer_peer,
                        invalidate_peer = wearer_peer,
                    } or nil)
            end
        end)
    state.hook_count = state.hook_count + 1
    state.installed = true
    return publish_owner(mod, state)
end

return HuskIdentityRuntime
