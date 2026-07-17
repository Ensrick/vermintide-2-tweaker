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
	woc_poisoned_edge_trait = {
		en = "Poisoned Edge",
	},
	description_woc_poisoned_edge_trait = {
		en = "Strikes apply Hagbane poison to enemies.",
	},
	woc_shyish_health_curse_trait = {
		en = "Shyish Health Curse",
	},
	description_woc_shyish_health_curse_trait = {
		en = "Kills release a death spirit that pursues the wielder and converts up to 5 permanent health to temporary health.",
	},

	-- Settings
	enable_blightreaper = {
		en = "Enable Blightreaper",
	},
	enable_blightreaper_tooltip = {
		en = "Adds the Blightreaper: a Cursed 600-power relic using a four-light Sword combat style at 75%% speed, intrinsic +15%% critical chance, armour-capable attacks, Hagbane poison, and kill-spawned Shyish spirits. It becomes 900 power and cannot be tempered in Chaos Wastes. Any career can equip it. Takes effect after you restart the game.",
	},
}
