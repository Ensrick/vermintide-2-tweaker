-- CWV lifecycle adapter for the shared complete-snapshot FadeSystem owner
-- (issue #922). This module owns no hooks and adds no network surface.

return function(mod)
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
	return M
end
