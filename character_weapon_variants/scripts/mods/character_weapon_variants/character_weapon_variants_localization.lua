local mod = get_mod("character_weapon_variants")
local loc = {
	mod_description = {
		en = "Adds new weapon variants that combine models from different characters into lore-friendly weapons.",
	},
	cwv_dev_options = { en = "Dev Options" },
	enable_cwv_dev_anim_picker = { en = "3P Animation Picker" },
	enable_cwv_dev_anim_picker_tooltip = { en = "Shows live third-person animation controls for CWV weapons. Picks are saved and apply to the selected receiver only. First-person animations are never changed." },
	mace_sword_tweak = {
		en = "Mace and Sword Name and Cosmetic Tweak",
	},
	mace_sword_tweak_description = {
		en = "When on, renames Kruber's vanilla Mace and Sword to 'Cudgel and Short Sword' and shrinks the off-hand sword to match the Shortsword. This only changes the vanilla weapon; the separate Sword and Mace variant added by this mod is left untouched.",
	},
	cwv_interaction_ammunition_javelin = {
		en = "Tuskgor Javelin",  -- pickup popup text when looking at a stuck javelin
	},
	cwv_cycle_combat_style_hotkey = { en = "Cycle Combat Style" },
	cwv_cycle_combat_style_hotkey_tooltip = { en = "Cycles the wielded supported weapon's saved Combat Style. The style belongs to that exact weapon instance and changes only when no attack is active. Greatswords cycle Greatsword, Imperial Longsword, Bretonnian, and Kerillian; Greathammers cycle Kruber and Warrior Priest; Tuskgor Spear cycles Hunter and Infantry; Kruber and Elven Spear and Shield cycle each other's style when the corresponding DLC is owned." },
	cwv_cycle_combat_style_controller = { en = "Switch Combat Style" },

	-- ============================================================
	-- Tuskgor Javelin (BOMB SLOT) — single-use thrown spear grenade
	-- ============================================================
	enable_cwv_tuskgor_javelin_bomb = { en = "Javelin" },
	enable_cwv_tuskgor_javelin_bomb_tooltip = { en = "When on, a Tuskgor Javelin can appear in the bomb pickup pool in every game mode without replacing the normal frag and fire bombs. It is a boar spear you can stab with in melee or throw once to pierce armour, shields, and a line of enemies, hitting hard on monsters and headshots, but the throw uses it up. It joins the pool on the next keep or level load." },
	-- Item name + description (grenade slot). display_name rarely shown for grenade items, kept for completeness.
	cwv_grenade_tuskgor_javelin_name = { en = "Tuskgor Javelin" },
	cwv_grenade_tuskgor_javelin_description = { en = "A full-size boar spear: stab with it in melee, or throw it once to punch through shields, plate, and the men behind them. One throw and it is gone." },
	-- Pickup interaction prompt + HUD description (Pickups.grenades entry hud_description / item_description).
	cwv_tuskgor_javelin_bomb = { en = "Tuskgor Javelin" },
	-- Peer-parity gated-feature label (issue 371). Shown in the beacon's chat
	-- notice when the bomb pool injection is auto-disabled because a lobby peer
	-- lacks cwv, and again when it re-enables. No em dashes (menu-facing string).
	cwv_gated_javelin_bomb_pool = { en = "Tuskgor Javelin bomb world spawns" },

	-- ============================================================
	-- cwv_es_crossbow variant (v0.1.347-dev)
	-- ============================================================
	enable_cwv_es_crossbow         = { en = "Kruber: Crossbow (Saltzpyre's, rifle anims)" },
	enable_cwv_es_crossbow_tooltip = { en = "When on, adds a version of Saltzpyre's crossbow that Kruber can wield, animated like his handgun in the third-person view. It is on by default." },
	enable_cwv_mace_hammer_identity = { en = "Distinguish Maces and Hammers" },
	enable_cwv_mace_hammer_identity_tooltip = { en = "On by default. One-handed maces, mace and shield, and Dual Maces attack 5%% faster. One-handed hammers, hammer and shield, and Dual Hammers deal 12.5%% more direct damage but have 25%% less cleave. Stagger, ordinary pushes, blocks, wield actions, two-handed hammers, Hammer and Tome, Maul, and mixed Mace and Sword weapons are unchanged." },
	cwv_es_crossbow_name           = { en = "Crossbow" },
	cwv_es_crossbow_description    = { en = "An imperial-issue crossbow taken up by Reikland state troopers, the same Witch Hunter pattern weapon shouldered like a standard handgun." },
	cwv_dr_dawi_mace = { en = "Dawi Mace" },
	cwv_dr_dawi_mace_name = { en = "Dawi Mace" },
	cwv_dr_dawi_mace_description = { en = "A compact Dawi striking weapon, balanced for forceful mace blows." },
	cwv_dr_dawi_mace_shield = { en = "Dawi Mace and Shield" },
	cwv_dr_dawi_mace_shield_name = { en = "Dawi Mace and Shield" },
	cwv_dr_dawi_mace_shield_description = { en = "A Dawi mace paired with a broad shield for holding the line." },
	cwv_dr_dawi_dual_maces = { en = "Dawi Dual Maces" },
	cwv_dr_dawi_dual_maces_name = { en = "Dawi Dual Maces" },
	cwv_dr_dawi_dual_maces_description = { en = "A matched pair of Dawi maces for an unbroken rhythm of crushing blows." },
	cwv_es_imperial_crowbill = { en = "Imperial Crowbill" },
	cwv_dr_dawi_crowbill = { en = "Dawi Crowbill" },

	-- On-ice `cwv_es_musket` variant item_type display name. The variant def is
	-- commented out (kept as a backup idea — the live musket is
	-- `cwv_es_musket_old`), but its `item_type = "cwv_es_musket"` literal is
	-- still scanned by qa/check_name_integrity.ps1 check #2. This entry resolves
	-- that reference and documents the on-ice variant's display name. Live code
	-- that operates on the musket family by backend_id prefix
	-- (`:match("^cwv_es_musket")`) keeps this key referenced. v0.1.348-dev.
	cwv_es_musket                  = { en = "Musket" },

}

local _anim_picker = mod:dofile("scripts/mods/character_weapon_variants/cwv_dev_anim_picker")
for key, value in pairs(_anim_picker.loc_keys()) do loc[key] = value end

return loc
