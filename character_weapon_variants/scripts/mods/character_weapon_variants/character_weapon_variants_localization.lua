return {
	mod_description = {
		en = "Adds new weapon variants that combine models from different characters into lore-friendly weapons.",
	},
	mace_sword_tweak = {
		en = "Mace and Sword Name and Cosmetic Tweak",
	},
	mace_sword_tweak_description = {
		en = "When on, renames Kruber's vanilla Mace and Sword to 'Cudgel and Short Sword' and shrinks the off-hand sword to match the Shortsword. This only changes the vanilla weapon; the separate Sword and Mace variant added by this mod is left untouched.",
	},
	cwv_interaction_ammunition_javelin = {
		en = "Tuskgor Javelin",  -- pickup popup text when looking at a stuck javelin
	},

	-- ============================================================
	-- Tuskgor Javelin (BOMB SLOT) — single-use thrown spear grenade
	-- ============================================================
	enable_cwv_tuskgor_javelin_bomb = { en = "Bomb Slot: Tuskgor Javelin (one-shot, full javelin moveset)" },
	enable_cwv_tuskgor_javelin_bomb_tooltip = { en = "When on, a Tuskgor Javelin can appear in the bomb pickup pool in every game mode without replacing the normal frag and fire bombs. It is a boar spear you can stab with in melee or throw once to pierce armour, shields, and a line of enemies, hitting hard on monsters and headshots, but the throw uses it up. It joins the pool on the next keep or level load." },
	-- Item name + description (grenade slot). display_name rarely shown for grenade items, kept for completeness.
	cwv_grenade_tuskgor_javelin_name = { en = "Tuskgor Javelin" },
	cwv_grenade_tuskgor_javelin_description = { en = "A full-size boar spear: stab with it in melee, or throw it once to punch through shields, plate, and the men behind them. One throw and it is gone." },
	-- Pickup interaction prompt + HUD description (Pickups.grenades entry hud_description / item_description).
	cwv_tuskgor_javelin_bomb = { en = "Tuskgor Javelin" },

	-- ============================================================
	-- cwv_es_crossbow variant (v0.1.347-dev)
	-- ============================================================
	enable_cwv_es_crossbow         = { en = "Kruber: Crossbow (Saltzpyre's, rifle anims)" },
	enable_cwv_es_crossbow_tooltip = { en = "When on, adds a version of Saltzpyre's crossbow that Kruber can wield, animated like his handgun in the third-person view. It is on by default." },
	cwv_es_crossbow_name           = { en = "Crossbow" },
	cwv_es_crossbow_description    = { en = "An imperial-issue crossbow taken up by Reikland state troopers, the same Witch Hunter pattern weapon shouldered like a standard handgun." },

	-- On-ice `cwv_es_musket` variant item_type display name. The variant def is
	-- commented out (kept as a backup idea — the live musket is
	-- `cwv_es_musket_old`), but its `item_type = "cwv_es_musket"` literal is
	-- still scanned by qa/check_name_integrity.ps1 check #2. This entry resolves
	-- that reference and documents the on-ice variant's display name. Live code
	-- that operates on the musket family by backend_id prefix
	-- (`:match("^cwv_es_musket")`) keeps this key referenced. v0.1.348-dev.
	cwv_es_musket                  = { en = "Musket" },

}
