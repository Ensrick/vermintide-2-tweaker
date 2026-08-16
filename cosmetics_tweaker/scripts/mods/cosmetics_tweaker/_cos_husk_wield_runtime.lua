-- Owns the single remote-husk weapon wield transaction.
--
-- The context bracket must stay atomic: publish wearer/slot identity before
-- vanilla reaches BackendUtils.get_item_units, always restore it afterward,
-- then bind/repaint the units vanilla just spawned.  Splitting those phases
-- across hooks reintroduces the remote base-mesh and stale-glow regressions.

local HuskWieldRuntime = {}

local function publish_owner(mod, state)
    local owner = mod._cos_husk_wield_runtime_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = state.hook_count or 0
    owner.current = function() return state.current end
    mod._cos_husk_wield_runtime_owner = owner
    return owner
end

function HuskWieldRuntime.current(mod)
    local state = mod and mod._cos_husk_wield_runtime_state
    return state and state.current or nil
end

function HuskWieldRuntime.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_husk_wield_runtime_state
    if not state then
        state = { installed = false, hook_count = 0, current = nil }
        mod._cos_husk_wield_runtime_state = state
    end

    state.get_managers = assert(deps.get_managers,
        "get_managers is required")
    state.husk_identity = assert(deps.husk_identity,
        "husk_identity is required")
    state.la_equips_by_peer = assert(deps.la_equips_by_peer,
        "la_equips_by_peer is required")
    state.get_application = assert(deps.get_application,
        "get_application is required")
    state.get_weapon_skins = assert(deps.get_weapon_skins,
        "get_weapon_skins is required")
    state.glow_by_peer = assert(deps.glow_by_peer,
        "glow_by_peer is required")
    state.complete_glow_rehydrate = assert(deps.complete_glow_rehydrate,
        "complete_glow_rehydrate is required")
    state.dbg = assert(deps.dbg, "dbg is required")
    state.dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    state.trace = assert(deps.trace, "trace is required")
    state.glow_log = assert(deps.glow_log, "glow_log is required")
    state.printf = deps.printf

    if state.installed then return publish_owner(mod, state) end

    mod:hook("SimpleHuskInventoryExtension", "_wield_slot",
        function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
            local husk_unit = self and self._unit
            local managers = state.get_managers()
            local pm = managers and managers.player
            local wearer_player = state.husk_identity.player_for_unit(
                pm, husk_unit)
            local wearer_peer = wearer_player and wearer_player.peer_id
            local wearer_is_human, human_reason =
                state.husk_identity.wearer_is_human(wearer_player)
            local wearer_lpid = state.husk_identity.local_player_id(
                wearer_player)
            if wearer_peer and not wearer_is_human then
                if state.printf then
                    state.printf("[cos:698] HUSK identity SKIP wearer=%s local_player_id=%s controlled=%s reason=%s (host bots share the wearer peer; local_player_id~=1 => bot)",
                        tostring(wearer_peer), tostring(wearer_lpid),
                        tostring(state.husk_identity.player_controlled(
                            wearer_player)), tostring(human_reason))
                end
                wearer_peer = nil
            elseif wearer_peer then
                local removed, reason, removed_slots =
                    state.husk_identity.invalidate_for_career(
                        state.la_equips_by_peer, wearer_peer,
                        self and self._career_name, true)
                if removed > 0 and state.printf then
                    state.printf("[cos:698] HUSK career-change invalidated wearer=%s active=%s slots=%s reason=%s",
                        tostring(wearer_peer),
                        tostring(self and self._career_name),
                        table.concat(removed_slots, ","), tostring(reason))
                end
            end

            state.dbg("[husk-wield-wrap] entry wearer=%s slot=%s husk_unit=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))
            if not wearer_peer and husk_unit then
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local seen_key = "wield-nopeer|" .. tostring(husk_unit)
                if not seen[seen_key] and state.printf then
                    seen[seen_key] = true
                    state.printf("[la-state] HUSK-WIELD wearer-unresolved husk=%s slot=%s (mesh swap + repaint skipped this path)",
                        tostring(husk_unit), tostring(slot_name))
                end
            end
            state.trace("HUSK wield_slot entry wearer=%s slot=%s husk_unit=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))

            local previous = state.current
            state.current = {
                wearer_peer = wearer_peer,
                husk_unit = husk_unit,
                slot_name = slot_name,
                career_name = self and self._career_name,
            }

            -- Resolve the same unit vanilla will spawn. A non-resident base is
            -- quiet when a career override or skin supplies a resident unit.
            local application = state.get_application()
            if application and application.can_get and equipment then
                local slot_data = equipment.slots and equipment.slots[slot_name]
                local item_data = slot_data and slot_data.item_data
                local skin = slot_data and slot_data.skin
                local career = self and self._career_name
                if item_data then
                    for _, field in ipairs({
                        "right_hand_unit", "left_hand_unit",
                    }) do
                        local override_field = field .. "_override"
                        local base = item_data[field]
                        local resolved = base
                        local override = item_data[override_field]
                        if career and override and override[career] then
                            resolved = override[career]
                        end
                        local via_skin
                        local weapon_skins = state.get_weapon_skins()
                        if skin and weapon_skins and weapon_skins.skins then
                            local skin_template = rawget(weapon_skins.skins, skin)
                            if skin_template then
                                via_skin = skin
                                resolved = skin_template[field]
                                local skin_override =
                                    skin_template[override_field]
                                if career and skin_override
                                        and skin_override[career] then
                                    resolved = skin_override[career] or resolved
                                end
                            end
                        end
                        if resolved and resolved ~= "" then
                            local resolved_resident = application.can_get(
                                "unit", resolved) and true or false
                            local base_resident = (base and base ~= ""
                                and application.can_get("unit", base))
                                and true or false
                            mod._preflight_seen = mod._preflight_seen or {}
                            local seen_key = (resolved_resident
                                    and "ok|" or "warn|")
                                .. tostring(career) .. "|"
                                .. tostring(item_data.name) .. "|" .. field
                                .. "|" .. tostring(resolved)
                            if not mod._preflight_seen[seen_key] then
                                mod._preflight_seen[seen_key] = true
                                if not resolved_resident then
                                    state.dbg_alert("[husk-wield-wrap] PREFLIGHT WARN wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=%s) RESOLVED=%s(resident=false, NOT in resource manager) via_skin=%s - vanilla will spawn a NON-resident unit; cross-char weapon force-load (weapon_tweaker's) may have missed this for husks",
                                        tostring(wearer_peer), tostring(career),
                                        tostring(slot_name), field,
                                        tostring(item_data.name), tostring(base),
                                        tostring(base_resident), tostring(resolved),
                                        tostring(via_skin))
                                elseif not base_resident then
                                    state.dbg("[husk-wield-wrap] PREFLIGHT OK (false alarm) wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=false) RESOLVED=%s(resident=true) via_skin=%s — base-field warn was spurious; resolved unit is resident",
                                        tostring(wearer_peer), tostring(career),
                                        tostring(slot_name), field,
                                        tostring(item_data.name), tostring(base),
                                        tostring(resolved), tostring(via_skin))
                                end
                            end
                        end
                    end
                end
            end

            local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(
                func, self, world, equipment, slot_name, unit_1p, unit_3p)
            state.current = previous
            if not ok then
                state.dbg_alert("[husk-wield-wrap] vanilla _wield_slot ERRORED wearer=%s slot=%s err=%s — pcall caught it. Husk visual likely missing/stale but host stays alive.",
                    tostring(wearer_peer), tostring(slot_name), tostring(r1))
                return nil
            end

            local glow_slot = equipment and equipment.slots
                and equipment.slots[slot_name]
            local glow_item = glow_slot and glow_slot.item_data
            local glow_units = {
                equipment and equipment.right_hand_wielded_unit_3p,
                equipment and equipment.left_hand_wielded_unit_3p,
                equipment and equipment.right_hand_wielded_unit,
                equipment and equipment.left_hand_wielded_unit,
            }
            local peer_state = wearer_peer
                and state.glow_by_peer[wearer_peer]
            local glow_matches = 0
            if mod._cos.bind_glow_unit then
                for _, glow_unit in pairs(glow_units) do
                    mod._cos.bind_glow_unit(
                        glow_unit, nil, glow_slot and glow_slot.skin,
                        slot_name, glow_item and glow_item.name,
                        glow_item and glow_item.template)
                    if peer_state and mod._cos.remote_glow_matches
                            and mod._cos.remote_glow_matches(
                                glow_unit, peer_state) then
                        glow_matches = glow_matches + 1
                    end
                end
            end
            mod._cos.apply_glow_override(glow_units, wearer_peer)
            if wearer_peer then
                state.glow_log(
                    "repaint path=husk_wield wearer=%s skin=%s slot=%s active=%s",
                    tostring(wearer_peer),
                    tostring(glow_slot and glow_slot.skin),
                    tostring(slot_name),
                    tostring(peer_state
                        and peer_state.active_per_item_glow ~= nil))
                if peer_state and peer_state.active_per_item_glow ~= nil
                        and glow_matches > 0 then
                    state.complete_glow_rehydrate(
                        wearer_peer, "husk_wield", glow_matches)
                end
            end

            if wearer_peer and state.la_equips_by_peer then
                local equips = state.la_equips_by_peer[wearer_peer]
                if equips then
                    local slot_data = equipment and equipment.slots
                        and equipment.slots[slot_name]
                    local item_data = slot_data and slot_data.item_data
                    local wielded_template = item_data and item_data.template
                    -- #476: weapon-side entries a CWV wearer emits are keyed by
                    -- the OWNER-LOCAL variant template/item_type; the husk's
                    -- vanilla base template never equals them, so the re-drive
                    -- below silently skipped this family on every switch-back.
                    -- Resolve the wearer's exact variant once per wield
                    -- (fail-closed: nil leaves the vanilla comparison as the
                    -- only accepted identity; the apply gate downstream stays
                    -- the safety authority either way).
                    local cwv_cands
                    do
                        local peer_identity = mod._cos_cwv_peer_identity
                        if wearer_peer and item_data and peer_identity
                                and type(peer_identity.husk_variant_candidates)
                                    == "function" then
                            cwv_cands = peer_identity.husk_variant_candidates(
                                get_mod("character_weapon_variants"),
                                { wearer_peer = wearer_peer,
                                    slot_name = slot_name },
                                item_data)
                        end
                    end
                    for stored_key, entry in pairs(equips) do
                        if entry and entry.kind and entry.armoury_key then
                            local career_ok, career_reason =
                                state.husk_identity.entry_matches_career(
                                    entry, self and self._career_name)
                            local should_apply = false
                            if not career_ok then
                                if state.printf then
                                    state.printf("[cos:698] HUSK repaint SKIP wearer=%s stored_key=%s kind=%s recorded=%s active=%s reason=%s",
                                        tostring(wearer_peer),
                                        tostring(stored_key),
                                        tostring(entry.kind),
                                        tostring(entry.wearer_career),
                                        tostring(self and self._career_name),
                                        tostring(career_reason))
                                end
                            elseif entry.kind == "hat"
                                    and stored_key == "slot_hat" then
                                should_apply = (slot_name == "slot_hat")
                            elseif entry.kind == "armor"
                                    and stored_key == "slot_skin" then
                                should_apply = true
                            elseif entry.kind == "offhand"
                                    or entry.kind == "illusion" then
                                should_apply = (wielded_template
                                    and stored_key == wielded_template)
                                    or (cwv_cands ~= nil
                                        and (stored_key == cwv_cands.variant_key
                                            or (cwv_cands.template ~= nil
                                                and stored_key
                                                    == cwv_cands.template)))
                                    or false
                            end
                            if should_apply then
                                state.dbg("[husk-wield-repaint] apply stored_key=%s kind=%s key=%s",
                                    tostring(stored_key), tostring(entry.kind),
                                    tostring(entry.armoury_key))
                                state.trace("HUSK wield-repaint stored_key=%s kind=%s armoury=%s slot=%s wearer=%s",
                                    tostring(stored_key), tostring(entry.kind),
                                    tostring(entry.armoury_key),
                                    tostring(slot_name), tostring(wearer_peer))
                                mod._la_reconcile(
                                    wearer_peer, stored_key,
                                    "husk-wield", false)
                            end
                        end
                    end
                end
            end

            return r1, r2, r3, r4, r5, r6, r7, r8
        end)
    state.hook_count = state.hook_count + 1
    state.installed = true
    return publish_owner(mod, state)
end

return HuskWieldRuntime
