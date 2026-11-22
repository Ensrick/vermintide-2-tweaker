-- WP-WT-05 step 6: Kruber Mercenary with the Volley Crossbow. The empty-wield
-- override is a 1P event (audit A1-F05: set at
-- weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_char_template_patches.lua,
-- consumed at Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2052, 2113).
-- Intended check once the rig can equip: enable
-- unlock_es_mercenary_we_crossbow_repeater, equip and wield we_crossbow_repeater,
-- then expect Unit.has_animation_event(<first person unit>, "to_repeating_handgun").
-- A FAIL would confirm A1-F05; record it under D-WT-06, do not change the override.
-- The driver has no equip helper yet, so the case ends INCONCLUSIVE.
return {
	card = "WP-WT-05",
	issue = 0,
	class = "R",
	arena = "keep",
	mods = { "wt" },
	timeout = 60,
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil, "wt is loaded")
		local player = Managers.player:local_player()
		T.require(player ~= nil and player:career_name() == "es_mercenary", "plan starts as es_mercenary")
		T.require(false, "equip helper missing")
	end,
}
