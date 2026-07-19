-- Paired inventory-preview transform adapter (#735).
--
-- MenuWorldPreviewer._spawn_item_unit does not expose which hand it spawned.
-- The enclosing _spawn_item retains vanilla's exact spawn_data hand flags and
-- numeric slot bridge, so hand-scoped transforms are applied only after it
-- returns. This module owns the sole _spawn_item hook and sends no RPC.

local M = {}

function M.install(mod, deps)
    mod:hook("MenuWorldPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
        local hero_material_changed = func(self, item_name, spawn_data)
        if type(spawn_data) ~= "table" or type(self._equipment_units) ~= "table" then
            return hero_material_changed
        end

        local career_name = self._current_career_name or deps.local_career_name()
            or self._character_name or (self._profile and self._profile.name)
        local rotation = deps.resolve_rotation(item_name, career_name)
        local offset = deps.resolve_offset(item_name, career_name)
        if not ((rotation and rotation.hand) or (offset and offset.hand)) then
            return hero_material_changed
        end

        local has_left, has_right = false, false
        for _, entry in ipairs(spawn_data) do
            has_left = has_left or entry.left_hand == true
            has_right = has_right or entry.right_hand == true
        end
        if not (has_left and has_right) then return hero_material_changed end

        local item_template = ItemHelper and ItemHelper.get_template_by_item_name
            and ItemHelper.get_template_by_item_name(item_name)
        for _, entry in ipairs(spawn_data) do
            local hand = entry.left_hand and "left" or entry.right_hand and "right" or nil
            local units = hand and self._equipment_units[entry.slot_index]
            local unit = type(units) == "table" and units[hand] or nil
            if hand and not entry.is_ammo_unit and unit and deps.is_unit(unit) then
                local exact_slot = { [hand .. "_unit_3p"] = unit }
                if offset and offset.hand and deps.policy.applies_to_hand(offset, hand) then
                    deps.offset_weapon_units(exact_slot, item_name, career_name)
                end
                if rotation and rotation.hand and deps.policy.applies_to_hand(rotation, hand) then
                    local preview_wielded = not entry.skip_wield_anim
                        and self._wielded_slot_type == entry.item_slot_type
                    deps.track_rotation(exact_slot, item_name, career_name, item_template,
                        nil, entry.item_slot_type, preview_wielded, "inventory_preview")
                end
            end
        end
        return hero_material_changed
    end)
end

return M
