-- Canonical cross-character transform owner (#1159).
--
-- This module owns one source-baked transform plan across the local player,
-- bots, remote husks, and menu preview. It installs at the entry's former
-- transform block so hook order is unchanged. First-person grip offsets and
-- rotations remain untouched; no transform value is transported over RPC.

local M = {}

function M.install(mod, deps)
    assert(type(mod) == "table", "_wt_transform_runtime requires mod")
    assert(type(deps) == "table", "_wt_transform_runtime requires deps")
    local appearance = assert(deps.appearance, "missing appearance")
    local grip_policy = assert(deps.grip_policy, "missing grip_policy")
    local dbg = assert(deps.dbg, "missing dbg")

    local scale_overrides = {
        we_1h_sword    = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
        bw_sword       = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
        bw_1h_crowbill = { es_ = 1.10, wh_ = 1.10, dr_ = 1.05 },
        we_2h_sword    = { es_ = 1.15 },
        dr_2h_axe      = { es_ = {1, 1.15, 1}, wh_ = {1, 1.15, 1}, we_ = {1, 1.15, 1}, bw_ = {1, 1.15, 1} },
        dr_1h_axe      = { we_ = {0.85, 0.85, 1} },
        dr_1h_hammer   = { we_ = {0.85, 0.85, 1} },
    }

    local function resolve_scale_factor(weapon_key, career_name)
        return grip_policy.resolve(scale_overrides, weapon_key, career_name)
    end

    local scale_field_probe_logged = {}
    local function scale_weapon_units(slot_data, weapon_key, career_name)
        if not weapon_key or not career_name or not scale_overrides[weapon_key] then return end
        if not scale_field_probe_logged[weapon_key] then
            scale_field_probe_logged[weapon_key] = true
            for key, value in pairs(slot_data) do
                local kind = type(value)
                if kind == "userdata" then
                    dbg("[scale_probe] %s slot_data.%s (UNIT)", weapon_key, tostring(key))
                elseif kind == "table" then
                    dbg("[scale_probe] %s slot_data.%s (table)", weapon_key, tostring(key))
                end
            end
        end
        local factor = resolve_scale_factor(weapon_key, career_name)
        if not factor then return end
        local scale = type(factor) == "table"
            and { factor[1], factor[2], factor[3] }
            or { factor, factor, factor }
        for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
            local unit = slot_data[field]
            if unit then appearance.apply(unit, { scale = scale }) end
        end
        if type(factor) == "table" then
            dbg("Scaled %s on %s by {%.2f, %.2f, %.2f}", weapon_key, career_name,
                factor[1], factor[2], factor[3])
        else
            dbg("Scaled %s on %s by %.2fx", weapon_key, career_name, factor)
        end
    end

    local grip_offsets = {
        we_1h_sword = { dr_ = {0, 0, 0.05} },
        bw_sword = { dr_ = {0, 0, 0.05} },
        es_1h_sword = { dr_ = {0, 0, 0.05} },
        wh_dual_hammer = { dr_ = {0, 0, 0.15} },
        wh_1h_hammer = { es_ = {0, 0, 0.15} },
        wh_hammer_shield = { es_ = {0, 0, 0.15, hand = "right"} },
        es_2h_sword = { we_ = {0, 0, -0.085} },
        wh_2h_sword = { we_ = {0, 0, -0.085} },
        bw_ghost_scythe = { es_ = {0, 0, 0.6} },
        we_2h_axe = { es_ = {0, 0, 0.285} },
        bw_skullstaff_flamethrower = { es_ = {0, 0, 0.6} },
        bw_skullstaff_beam = { es_ = {0, 0, 0.6} },
        bw_skullstaff_fireball = { es_ = {0, 0, 0.6} },
        bw_skullstaff_geiser = { es_ = {0, 0, 0.6} },
        bw_skullstaff_spear = { es_ = {0, 0, 0.6} },
        bw_necromancy_staff = { es_ = {0, 0, 0.6} },
        bw_deus_01 = { es_ = {0, 0, 0.6} },
        es_bastard_sword = { wh_ = {0, 0, 0.08} },
        es_handgun = { wh_ = {0, -0.17, -0.05} },
        wh_crossbow = { es_ = {0, 0.100, 0.025, hand = "left"} },
    }

    local saltz_shield_rotation = { 25, -17.5, -15, hand = "left" }
    local rotation_overrides = {
        es_mace_shield = { wh_ = saltz_shield_rotation },
        es_sword_shield = { wh_ = saltz_shield_rotation },
        es_sword_shield_breton = { wh_ = saltz_shield_rotation },
        dr_shield_axe = { wh_ = saltz_shield_rotation },
        cwv_es_axe_shield = { wh_ = saltz_shield_rotation },
        cwv_es_axe_shield_veteran = { wh_ = saltz_shield_rotation },
    }

    local durable_offsets = {
        bw_ghost_scythe = true,
        we_2h_axe = true,
        bw_skullstaff_flamethrower = true,
        bw_skullstaff_beam = true,
        bw_skullstaff_fireball = true,
        bw_skullstaff_geiser = true,
        bw_skullstaff_spear = true,
        bw_necromancy_staff = true,
        bw_deus_01 = true,
        es_bastard_sword = true,
        es_handgun = true,
        wh_crossbow = true,
    }

    local function resolve_grip_offset(weapon_key, career_name)
        return grip_policy.resolve(grip_offsets, weapon_key, career_name)
    end

    local function resolve_rotation_override(weapon_key, career_name)
        return grip_policy.resolve(rotation_overrides, weapon_key, career_name)
    end

    local function offset_weapon_units(slot_data, weapon_key, career_name)
        if not weapon_key or not career_name then return end
        local offset = resolve_grip_offset(weapon_key, career_name)
        if not offset then return end
        local descriptor = { offset = { offset[1], offset[2], offset[3] } }
        for _, field in ipairs(grip_policy.unit_fields_3p(offset)) do
            local unit = slot_data[field]
            if unit then appearance.apply(unit, descriptor) end
        end
        dbg("Offset %s on %s by {%.3f, %.3f, %.3f} (hand=%s)", weapon_key,
            career_name, offset[1], offset[2], offset[3], tostring(offset.hand or "both"))
    end

    local tracked_offsets = setmetatable({}, { __mode = "k" })
    local diag_budget = 24
    mod._wt587_transform_contract = {
        source = "baked_tables",
        transport = "none",
        rpc_channels = 0,
        live_tuner_scope = "local_player_3p_only",
        first_person = "unchanged",
        components = { scale = "scale_only", offset = "position_only", rotation = "wt569_rotation_only" },
        hand_scope = grip_policy.contract.hand_scope,
    }
    mod._wt587_baked_transform_plan = function(weapon_key, career_name)
        return {
            scale = resolve_scale_factor(weapon_key, career_name),
            offset = resolve_grip_offset(weapon_key, career_name),
            rotation = resolve_rotation_override(weapon_key, career_name),
            durable = durable_offsets[weapon_key] == true,
        }
    end

    local function row_is_wielded(row)
        local owner = row.owner
        if not owner then return false end
        local ok_alive, alive = pcall(Unit.alive, owner)
        if not ok_alive or not alive then return false end
        local inventory = ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(owner, "inventory_system")
        if not inventory or type(inventory.get_wielded_slot_name) ~= "function" then return false end
        local ok_slot, wielded_slot = pcall(inventory.get_wielded_slot_name, inventory)
        return ok_slot and wielded_slot == row.slot_name
    end

    local function track_durable_3p_units(slot_data, weapon_key, career_name, owner_3p, slot_name, role)
        if not durable_offsets[weapon_key] then return 0 end
        local offset = resolve_grip_offset(weapon_key, career_name)
        if not offset then return 0 end
        local tracked = 0
        for _, field in ipairs({ "right_unit_3p", "left_unit_3p" }) do
            local hand = field == "right_unit_3p" and "right" or "left"
            local unit = slot_data and slot_data[field]
            if unit and grip_policy.applies_to_hand(offset, hand) and not tracked_offsets[unit] then
                local ok_alive, alive = pcall(Unit.alive, unit)
                local ok_pos, base_position = pcall(Unit.local_position, unit, 0)
                if ok_alive and alive and ok_pos and base_position then
                    tracked_offsets[unit] = {
                        base = Vector3Box(base_position), owner = owner_3p,
                        slot_name = slot_name, weapon_key = weapon_key,
                        career_name = career_name, hand = hand, role = role,
                        offset = { offset[1], offset[2], offset[3] },
                    }
                    tracked = tracked + 1
                    if diag_budget > 0 then
                        diag_budget = diag_budget - 1
                        pcall(printf,
                            "[wt:587] tracked role=%s career=%s weapon=%s hand=%s slot=%s transport=none first_person=untouched",
                            tostring(role or "owner"), tostring(career_name), tostring(weapon_key),
                            tostring(hand), tostring(slot_name))
                    end
                end
            end
        end
        return tracked
    end
    mod._wt587_track_durable_3p_units = track_durable_3p_units

    function mod._reapply_durable_grip_offsets()
        for unit, row in pairs(tracked_offsets) do
            local ok_alive, alive = pcall(Unit.alive, unit)
            if not ok_alive or not alive then
                tracked_offsets[unit] = nil
            elseif row_is_wielded(row) then
                local base = row.base:unbox()
                local target = base + Vector3(row.offset[1], row.offset[2], row.offset[3])
                pcall(Unit.set_local_position, unit, 0, target)
                grip_policy.log_issue701_retained_once(row, unit, target)
            end
        end
    end

    local standard_saltz_careers = {
        wh_captain = true, wh_bountyhunter = true, wh_zealot = true,
    }
    local native_wp_hammer_key = "wh_2h_hammer"
    local remap_event = "to_2h_hammer_priest"
    local tracked_rotations = setmetatable({}, { __mode = "k" })
    mod._wt569_should_rotate_3p = function(weapon_key, career_name, item_template)
        if not standard_saltz_careers[career_name] then return false end
        if resolve_rotation_override(weapon_key, career_name) then return true end
        if weapon_key == native_wp_hammer_key then return false end
        local by_career = item_template and item_template.wield_anim_career_3p
        return type(by_career) == "table" and by_career[career_name] == remap_event
    end
    mod._wt569_orientation_contract = {
        axis = { 0, 0, 1 }, degrees = 180, remap_event = remap_event,
        native_exempt_key = native_wp_hammer_key,
        baked_shield_euler = saltz_shield_rotation,
        baked_shield_scope = "standard_saltzpyre_3p",
        spear_shield_exempt_key = "es_deus_01",
    }

    local function rotation_delta(row)
        local euler = row and row.euler
        if euler then return Quaternion.from_euler_angles_xyz(euler[1], euler[2], euler[3]) end
        return Quaternion.axis_angle(Vector3(0, 0, 1), math.pi)
    end

    local function track_3p_rotation_units(slot_data, weapon_key, career_name,
            item_template, owner_3p, slot_name, preview_wielded, role)
        if not mod._wt569_should_rotate_3p(weapon_key, career_name, item_template) then return end
        local baked_euler = resolve_rotation_override(weapon_key, career_name)
        for _, field in ipairs({ "right_unit_3p", "left_unit_3p" }) do
            local hand = field == "right_unit_3p" and "right" or "left"
            local unit = slot_data and slot_data[field]
            if unit and (not baked_euler or grip_policy.applies_to_hand(baked_euler, hand))
                    and not tracked_rotations[unit] then
                local ok_alive, alive = pcall(Unit.alive, unit)
                local ok_rot, base_rotation = pcall(Unit.local_rotation, unit, 0)
                if ok_alive and alive and ok_rot and base_rotation then
                    tracked_rotations[unit] = {
                        base = QuaternionBox(base_rotation), owner = owner_3p,
                        slot_name = slot_name, preview_wielded = preview_wielded == true,
                        weapon_key = weapon_key, career_name = career_name,
                        hand = hand, role = role,
                        euler = baked_euler and { baked_euler[1], baked_euler[2], baked_euler[3] } or nil,
                    }
                    if baked_euler then
                        pcall(printf,
                            "[wt:112] tracked shield rotation career=%s weapon=%s hand=%s euler={%.1f,%.1f,%.1f} first_person=untouched",
                            tostring(career_name), tostring(weapon_key), hand,
                            baked_euler[1], baked_euler[2], baked_euler[3])
                    else
                        pcall(printf,
                            "[wt:569] tracked career=%s weapon=%s hand=%s remap=%s axis=local_z degrees=180 first_person=untouched",
                            tostring(career_name), tostring(weapon_key), hand, remap_event)
                    end
                end
            end
        end
    end

    local function rotation_row_is_wielded(row)
        if row.preview_wielded then return true end
        return row_is_wielded(row)
    end

    function mod._wt569_reapply_3p_orientation()
        for unit, row in pairs(tracked_rotations) do
            local ok_alive, alive = pcall(Unit.alive, unit)
            if not ok_alive or not alive then
                tracked_rotations[unit] = nil
            else
                local base = row.base:unbox()
                local corrected = rotation_row_is_wielded(row)
                local desired = corrected and Quaternion.multiply(base, rotation_delta(row)) or base
                pcall(Unit.set_local_rotation, unit, 0, desired)
                if corrected then grip_policy.log_issue735_retained_once(row, unit, desired) end
                if row.last_corrected ~= corrected then
                    row.last_corrected = corrected
                    pcall(printf, "[wt:569] applied=%s career=%s weapon=%s hand=%s slot=%s mode=%s",
                        tostring(corrected), tostring(row.career_name), tostring(row.weapon_key),
                        tostring(row.hand), tostring(row.slot_name or "preview"),
                        row.euler and "baked_euler" or "wp_half_turn")
                end
            end
        end
    end

    function mod._wt569_desired_rotation_for_unit(unit)
        local row = tracked_rotations[unit]
        if not row then return nil end
        local base = row.base:unbox()
        if not rotation_row_is_wielded(row) then return base end
        return Quaternion.multiply(base, rotation_delta(row))
    end

    mod:traced_hook("GearUtils", "create_equipment", function(func, world, slot_name,
            item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data,
            ammo_percent, override_item_template, override_item_units, career_name)
        if career_name == nil and unit_3p and ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(unit_3p, "inventory_system") then
            local inventory = ScriptUnit.extension(unit_3p, "inventory_system")
            career_name = inventory and inventory._career_name or nil
            if career_name then
                mod:warning("[create_equipment] recovered nil career_name -> %s (weapon=%s slot=%s is_bot=%s)",
                    tostring(career_name), tostring(item_data and item_data.name),
                    tostring(slot_name), tostring(is_bot))
            end
        end
        if override_item_units == nil and item_data and career_name and BackendUtils
                and BackendUtils.get_item_units
                and ((item_data.right_hand_unit_override and item_data.right_hand_unit_override[career_name])
                    or (item_data.left_hand_unit_override and item_data.left_hand_unit_override[career_name])) then
            local ok_resolve, resolved = pcall(
                BackendUtils.get_item_units, item_data, item_data.backend_id, nil, career_name)
            if ok_resolve and type(resolved) == "table" then
                override_item_units = resolved
                dbg("[create_equipment] pre-resolved item_units for %s on %s (rhu=%s)",
                    tostring(item_data.name), tostring(career_name), tostring(resolved.right_hand_unit))
            end
        end
        local ok, result = pcall(func, world, slot_name, item_data, unit_1p, unit_3p,
            is_bot, unit_template, extra_extension_data, ammo_percent,
            override_item_template, override_item_units, career_name)
        if not ok then
            local weapon_key = item_data and item_data.name or "unknown"
            local has_override = item_data and item_data.right_hand_unit_override and "yes" or "no"
            local right_unit = item_data and item_data.right_hand_unit or "nil"
            mod:error("create_equipment CRASHED: weapon=%s slot=%s career=%s is_bot=%s rhu=%s has_override=%s err=%s",
                tostring(weapon_key), tostring(slot_name), tostring(career_name),
                tostring(is_bot), tostring(right_unit), has_override, tostring(result))
            return {}
        end
        if result and item_data then
            local weapon_key = item_data.name
            scale_weapon_units(result, weapon_key, career_name)
            track_durable_3p_units(result, weapon_key, career_name,
                unit_3p, slot_name, is_bot and "bot" or "owner")
            offset_weapon_units(result, weapon_key, career_name)
            track_3p_rotation_units(result, weapon_key, career_name, result.item_template,
                unit_3p, slot_name, false, is_bot and "bot" or "owner")
        end
        return result or {}
    end)

    mod:hook_safe("SimpleHuskInventoryExtension", "_wield_slot",
        function(self, world, equipment, slot_name, unit_1p, unit_3p)
            local slot = equipment and equipment.slots and equipment.slots[slot_name]
            local item_data = slot and slot.item_data
            local weapon_key = item_data and (item_data.name or item_data.key)
            local career_name = self and self._career_name
            if not weapon_key or not career_name then return end
            local spawned_3p = {
                right_unit_3p = equipment.right_hand_wielded_unit_3p,
                left_unit_3p = equipment.left_hand_wielded_unit_3p,
            }
            scale_weapon_units(spawned_3p, weapon_key, career_name)
            track_durable_3p_units(spawned_3p, weapon_key, career_name,
                (self and self._unit) or unit_3p, slot_name, "remote_husk")
            offset_weapon_units(spawned_3p, weapon_key, career_name)
            local item_template = nil
            if BackendUtils and BackendUtils.get_item_template then
                local ok_template, resolved = pcall(BackendUtils.get_item_template, item_data)
                item_template = ok_template and resolved or nil
            end
            track_3p_rotation_units(spawned_3p, weapon_key, career_name, item_template,
                (self and self._unit) or unit_3p, slot_name, false, "remote_husk")
        end)

    return {
        scale_weapon_units = scale_weapon_units,
        resolve_grip_offset = resolve_grip_offset,
        offset_weapon_units = offset_weapon_units,
        resolve_rotation_override = resolve_rotation_override,
        track_3p_rotation_units = track_3p_rotation_units,
    }
end

return M
