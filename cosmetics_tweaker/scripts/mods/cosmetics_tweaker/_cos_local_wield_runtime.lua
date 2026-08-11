-- Owns the local SimpleInventoryExtension._wield_slot appearance replay seam.
-- Remote husk wielding remains in the glow/LA transport owners; this module
-- handles only the local player's already-spawned units after a wield change.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered installer call after LA/glow transports exist.

local LocalWieldRuntime = {}

local function publish_owner(mod)
    local owner = mod._cos_local_wield_runtime_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = 1
    mod._cos_local_wield_runtime_owner = owner
    return owner
end

function LocalWieldRuntime.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_local_wield_runtime_state
    if not state then
        state = { installed = false }
        mod._cos_local_wield_runtime_state = state
    end

    state.local_player_safe = assert(
        deps.local_player_safe,
        "local_player_safe is required"
    )
    state.get_managers = assert(deps.get_managers, "get_managers is required")
    state.unit = assert(deps.unit, "unit is required")
    state.la_equips_by_peer = assert(
        deps.la_equips_by_peer,
        "la_equips_by_peer is required"
    )
    state.glow_picker = assert(deps.glow_picker, "glow_picker is required")
    state.trace = assert(deps.trace, "trace is required")
    state.glow_log = assert(deps.glow_log, "glow_log is required")
    state.probe = deps.probe

    if state.installed then return publish_owner(mod) end

    mod:hook_safe("SimpleInventoryExtension", "_wield_slot",
        function(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
            local managers = state.get_managers()
            local player_manager = managers and managers.player
            local local_player = state.local_player_safe(player_manager)
            if not local_player then return end
            if self._unit ~= local_player.player_unit then return end

            local wielded_slot = (slot_data and slot_data.id)
                or (self._equipment and self._equipment.wielded_slot)
            state.trace("TRANSITION WIELD local from=%s to=%s",
                tostring(self._ct_last_wielded), tostring(wielded_slot))
            self._ct_last_wielded = wielded_slot
            mod._cos518_owner_wield(slot_data, wielded_slot)

            local local_peer = local_player.peer_id
            local equips = local_peer and state.la_equips_by_peer[local_peer]
            if equips and self._unit and state.unit.alive(self._unit) then
                local item_data = slot_data and slot_data.item_data
                local wielded_template = item_data and item_data.template
                if wielded_template then
                    for stored_key, entry in pairs(equips) do
                        if entry and entry.armoury_key and entry.kind == "offhand"
                                and stored_key == wielded_template
                                and not mod._la_deus_weapon_yield() then
                            state.trace(
                                "LOCAL wield-reapply stored_key=%s kind=%s armoury=%s slot=%s",
                                tostring(stored_key), tostring(entry.kind),
                                tostring(entry.armoury_key), tostring(wielded_slot))
                            if state.probe then
                                state.probe.emit("cos:sync",
                                    "local_wield/" .. tostring(wielded_slot)
                                        .. "/" .. tostring(stored_key),
                                    string.format(
                                        "peer=local slot=%s template=%s key=%s decision=REAPPLY",
                                        tostring(wielded_slot), tostring(stored_key),
                                        tostring(entry.armoury_key)))
                            end
                            pcall(mod._la_reconcile, local_peer, stored_key,
                                "local-wield", false)
                        end
                    end
                end
            end

            local backend_id
            local glow_units = {}
            if slot_data and type(slot_data) == "table" then
                for _, field in ipairs({
                    "right_unit_1p", "left_unit_1p",
                    "right_unit_3p", "left_unit_3p",
                }) do
                    local unit = slot_data[field]
                    if unit then
                        glow_units[#glow_units + 1] = unit
                        if mod._unit_to_backend_id
                                and mod._unit_to_backend_id[unit] then
                            backend_id = mod._unit_to_backend_id[unit]
                        end
                    end
                end
            end

            local item_data = slot_data and slot_data.item_data
            local skin = slot_data and slot_data.skin
            if backend_id then
                state.glow_picker.restore_runtime_for(backend_id, { skin = skin })
            end
            if mod._cos.bind_glow_unit then
                for _, unit in pairs(glow_units) do
                    mod._cos.bind_glow_unit(unit, backend_id, skin, wielded_slot,
                        item_data and item_data.name,
                        item_data and item_data.template)
                end
            end

            local next_state = backend_id and mod._per_item_glow_runtime
                and mod._per_item_glow_runtime[backend_id] or nil
            local next_identity = backend_id and mod._per_item_glow_identity_runtime
                and mod._per_item_glow_identity_runtime[backend_id] or nil
            mod._active_per_item_glow_skin = next_state and (skin or "") or nil
            mod._active_per_item_glow_slot = next_state and wielded_slot or nil
            mod._active_per_item_glow_item_name = next_state and item_data
                and item_data.name or nil
            mod._active_per_item_glow_item_template = next_state and item_data
                and item_data.template or nil
            if mod._active_per_item_glow ~= next_state
                    or mod._active_per_item_glow_identity ~= next_identity then
                mod._active_per_item_glow = next_state
                mod._active_per_item_glow_identity = next_identity
                if mod._emit_per_item_glow then mod._emit_per_item_glow() end
            end
            mod._cos.apply_glow_override(glow_units, local_player.peer_id)
            if next_state then
                state.glow_log(
                    "rehydrate path=local_wield bid=%s skin=%s slot=%s active=true units=%d",
                    tostring(backend_id), tostring(skin),
                    tostring(wielded_slot), #glow_units)
            end
        end)

    state.installed = true
    return publish_owner(mod)
end

return LocalWieldRuntime
