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
		en = "Adds the Blightreaper: a Cursed 600-power relic using Sienna's Crowbill combat style at 83%% speed, intrinsic +15%% critical chance, armour-capable attacks, Hagbane poison, and kill-spawned Shyish spirits. It becomes 900 power and cannot be tempered in Chaos Wastes. Any career can equip it. Takes effect after you restart the game.",
	},

	-- Blightreaper Combat: attack-order picker (group, dropdowns, unit labels).
	blightreaper_combat = {
		en = "Blightreaper Combat",
	},
	woc_blightreaper_light_1 = {
		en = "Light attack 1",
	},
	woc_blightreaper_light_2 = {
		en = "Light attack 2",
	},
	woc_blightreaper_light_3 = {
		en = "Light attack 3",
	},
	woc_blightreaper_light_4 = {
		en = "Light attack 4",
	},
	woc_blightreaper_heavy_1 = {
		en = "Heavy attack 1",
	},
	woc_blightreaper_heavy_2 = {
		en = "Heavy attack 2",
	},
	woc_blightreaper_heavy_3 = {
		en = "Heavy attack 3",
	},
	woc_blightreaper_push_follow = {
		en = "Push follow-up",
	},
	woc_blightreaper_light_tooltip = {
		en = "Chooses which swing plays at this step of the light chain. Picking the same swing for two steps plays it at both. The swing keeps its own speed, damage, and sweep; chain flow between steps is unchanged. Applies to your next attack, or when the relic installs.",
	},
	woc_blightreaper_heavy_tooltip = {
		en = "Chooses which heavy plays at this step of the heavy chain. Each heavy brings its matching charge-up windup with it, so windup and release always match. Picking the same heavy for two steps plays it at both. Applies to your next attack, or when the relic installs.",
	},
	woc_blightreaper_push_tooltip = {
		en = "Chooses which strike follows a push. The Blightreaper has one push follow-up for now; more options arrive with future weapons.",
	},
	woc_atk_overhead = {
		en = "Overhead",
	},
	woc_atk_upper_left = {
		en = "Upper left",
	},
	woc_atk_right_diagonal = {
		en = "Right diagonal",
	},
	woc_atk_stab = {
		en = "Stab",
	},
	woc_atk_left_up_smash = {
		en = "Left-up smash",
	},
	woc_atk_right_smash = {
		en = "Right smash",
	},
	woc_atk_diagonal_smash = {
		en = "Diagonal smash",
	},
	woc_atk_upper_bopp = {
		en = "Upper bopp",
	},
}
