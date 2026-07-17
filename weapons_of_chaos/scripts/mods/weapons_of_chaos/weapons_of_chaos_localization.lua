return {
	mod_description = {
		en = "Lets your heroes wield the weapons of their enemies: chaos, skaven, beastmen, and the named trophy weapons from the keep. Each one is a new inventory item any career can equip.",
	},

	-- Blightreaper item (woc_blightreaper). The item's display_name/description
	-- entry fields resolve to these keys via the _G.Localize hook in
	-- weapons_of_chaos.lua.
	woc_blightreaper_name = {
		en = "Blightreaper",
	},
	woc_blightreaper_description = {
		en = "A grim trophy from the Bogenhafen keep. Its cursed edge carries plague, bites through armour, and draws the death wind behind every kill.",
	},
	woc_intrinsic_crit_property = {
		en = "+15%% Critical Strike Chance",
	},
	woc_power_vs_order_property = {
		en = "+50%% Power vs. Order",
	},

	-- Settings
	enable_blightreaper = {
		en = "[verify-fix] Enable Blightreaper",
	},
	enable_blightreaper_tooltip = {
		en = "Adds the Blightreaper: a Cursed 600-power relic using a four-light Sword combat style at 75%% speed, intrinsic +15%% critical chance, armour-capable attacks, Hagbane poison, and kill-spawned Shyish spirits. It becomes 900 power and cannot be tempered in Chaos Wastes. Any career can equip it. Takes effect after you restart the game.",
	},
}
