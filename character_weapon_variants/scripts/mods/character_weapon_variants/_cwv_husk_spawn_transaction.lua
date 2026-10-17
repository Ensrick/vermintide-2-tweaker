-- _cwv_husk_spawn_transaction.lua -- complete remote-husk GearUtils transaction.
--
-- Keeps preselection/re-key, the one vanilla spawn, and post-spawn presentation
-- in one executable owner. The live GearUtils hook, runtime regression checks,
-- and offline tests all drive this same function.
return function(_, ctx)
	local _om = ctx.om

	_om._husk_spawn_adapter_transaction = function(func, world, hand,
			item_template, item_units, slot_name, item_data, owner_unit_1p,
			owner_unit_3p, unit_template, extra_extension_data, ammo_percent,
			material_settings_name)
		local suppress, husk_template, spawn_evidence = _om._husk_adapter_pre(
			hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		if suppress then
			if _om._probe_279_spawn then
				_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p,
					owner_unit_3p, nil, "deferred_478")
			end
			return nil, nil, nil, nil
		end
		local v_w3p, v_a3p, v_w1p, v_a1p = func(world, hand,
			husk_template or item_template, item_units, slot_name, item_data,
			owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data,
			ammo_percent, material_settings_name)
		if _om._probe_279_spawn then
			_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p,
				owner_unit_3p, v_a3p, nil)
		end
		if _om._husk_adapter_post(hand, item_data, item_units, slot_name,
				owner_unit_3p, v_w3p, v_a3p, spawn_evidence) then
			v_a3p = nil
		end
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
end
