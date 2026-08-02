-- CWV lifecycle adapter for the shared complete-snapshot FadeSystem owner
-- (issue #922). Adds no network surface. Owns exactly ONE hook: the
-- post-`_reapply_fade` forced re-enrollment installed at the bottom of the
-- factory (CWV's sole hook on (SimpleHuskInventoryExtension, _reapply_fade)).

return function(mod, om)
	local adapter = mod:dofile(
		"scripts/mods/character_weapon_variants/_lib_appearance_fade").new({
		alive = function(unit) return Unit and Unit.alive and Unit.alive(unit) end,
		get_extension = function(owner, name)
			return ScriptUnit and ScriptUnit.has_extension
				and ScriptUnit.has_extension(owner, name) or nil
		end,
		get_fade_system = function()
			local entity = Managers and Managers.state and Managers.state.entity
			return entity and entity:system("fade_system") or nil
		end,
		diag_budget = 16,
		report = function(row)
			pcall(printf, "[cwv:922] fade edge=%s result=%s linked=%d error=%s",
				tostring(row.edge), tostring(row.reason), tonumber(row.count) or 0,
				tostring(row.error))
		end,
	})
	local M = {}

	function M.owner_wield(extension, equipment)
		return adapter:enroll(extension and extension._unit, "owner_wield", {
			inventory_extension = extension, equipment = equipment,
		})
	end

	function M.husk_wield(extension, equipment)
		return adapter:enroll(extension and extension._unit, "remote_husk_wield", {
			inventory_extension = extension, equipment = equipment,
		})
	end

	-- #922: vanilla wield calls `_reapply_fade` AFTER `_wield_slot`
	-- (simple_husk_inventory_extension.lua:319 then :353) and replaces the
	-- linked set with only the four inventory fields, evicting the wield-edge
	-- snapshot. `force = true` bypasses the `_last_by_owner` fingerprint dedup
	-- (which would otherwise report "unchanged" and skip), mirroring the
	-- proven Cosmetics `remote_husk_reapply` edge.
	function M.husk_reapply(extension, equipment)
		return adapter:enroll(extension and extension._unit, "remote_husk_reapply", {
			inventory_extension = extension, equipment = equipment, force = true,
		})
	end

	function M.created(owner, result, is_bot)
		return adapter:enroll(owner,
			is_bot and "bot_create_equipment" or "owner_create_equipment", {
				extra_units = {
					result and result.right_unit_3p,
					result and result.right_ammo_unit_3p,
					result and result.left_unit_3p,
					result and result.left_ammo_unit_3p,
				},
			})
	end

	M.adapter = adapter

	-- #922 eviction fix: vanilla's `_reapply_fade` reset (rows :292-311) runs
	-- AFTER the `_wield_slot` enrollment; re-enroll behind it with force=true
	-- (the proven Cosmetics pattern, _cos_appearance_fade_runtime.lua). Gated
	-- on the same exact-identity descriptor as the wield-edge enrollment,
	-- resolved lazily through `om` (the descriptor surface installs later in
	-- the entry file); vanilla-only husks keep the native linked set untouched.
	-- Pre-flight (CLAUDE.md NON-NEGOTIABLE #8): CWV's only other
	-- SimpleHuskInventoryExtension hooks are `start_weapon_fx` and
	-- `_wield_slot` in the entry file -- this is the sole CWV hook on
	-- (SimpleHuskInventoryExtension, _reapply_fade).
	if om and type(mod.hook) == "function" then
		mod:hook("SimpleHuskInventoryExtension", "_reapply_fade", function(func, self, equipment)
			local result = func(self, equipment)
			local slot_name = self and self.wielded_slot
			local slot = slot_name and equipment and equipment.slots
				and equipment.slots[slot_name]
			local item_data = slot and slot.item_data
			local descriptor = slot and om._husk_identity_descriptor
				and om._husk_identity_descriptor(self and self._unit, slot_name,
					item_data and item_data.name)
			if descriptor then M.husk_reapply(self, equipment) end
			return result
		end)
	end

	return M
end
