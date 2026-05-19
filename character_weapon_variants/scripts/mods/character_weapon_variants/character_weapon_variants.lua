local mod = get_mod("character_weapon_variants")

local MOD_VERSION = "0.1.328-dev"

mod:info("Character Weapon Variants v%s loading", MOD_VERSION)
-- In-game chat echo so version is visible without opening console.log —
-- matches cosmetics_tweaker's pattern. Required by `feedback_version_bump.md`:
-- a build that doesn't visibly confirm its version isn't deployable.
mod:echo("Character Weapon Variants v" .. MOD_VERSION)

-- ============================================================================
-- ANIMATION ARCHITECTURE — READ BEFORE TOUCHING ANY ANIM CODE BELOW
-- ============================================================================
-- 1P (first-person) animations are UNIVERSAL across all six characters and all
-- weapons. The first_person_base unit is shared; any weapon's 1P state machine
-- and clips play correctly on any character's first-person view, by default,
-- with zero work from us.
--
-- This means: do not override anim_event (1P), wield_anim (1P), or
-- state_machine on any cloned template, and do not author per-character
-- variants of a template "to fix 1P" — there is nothing to fix. The 1P side
-- works automatically.
--
-- ALL animation work in this file is 3P-only:
--   * anim_event_3p          — per-action 3P body anim event
--   * wield_anim_3p          — 3P body wield/equip pose
--   * wield_anim_career_3p   — per-career 3P wield override
--
-- The 3P body skeleton is character-specific (Kruber's empire skeleton has a
-- different event vocabulary than Kerillian's elf skeleton, etc.). When a
-- cross-character weapon's 3P anims look wrong, the fix lives in this 3P
-- vocabulary — never in any 1P field.
--
-- This rule keeps recurring as a misunderstanding. Every animation-touching
-- function below carries an inline reminder. See memory note
-- `feedback_1p_animations_universal.md` for the full rationale.
-- ============================================================================

-- ============================================================
-- Cross-character weapon analogues (public API)
-- ============================================================
-- Vanilla weapon items that are mechanically analogous and may share
-- cosmetic/visual assets when this mod is loaded. Other mods (e.g.
-- cosmetics_tweaker) read this to expand cosmetic targeting beyond a
-- single character.

-- CLARIFY: Public API consumed by cosmetics_tweaker (CHANGELOG v0.1.45).
-- Contract: mod.weapon_analogues : { [vanilla_item_key:string] = { vanilla_item_key:string, ... } }
-- Returned arrays should NOT include the input key itself.
-- mod.get_analogues(key) returns a freshly-allocated empty table on miss; callers
-- must not mutate the returned table (it may be the live mod.weapon_analogues entry).
mod.weapon_analogues = {
	es_2h_sword = { "wh_2h_sword" },
	wh_2h_sword = { "es_2h_sword" },
}

function mod.get_analogues(item_key)
	return mod.weapon_analogues[item_key] or {}
end

-- ============================================================
-- Variant weapon definitions
-- ============================================================

local _es_all_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local _wh_all_careers = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" }
local _bw_all_careers = { "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer" }

local _variant_definitions = {
	{
		item_key        = "cwv_es_axe_shield",
		base_weapon     = "dr_shield_axe",
		display_name    = "Axe and Shield",
		description     = "A one-handed axe paired with a sturdy imperial shield.",
		character       = "empire_soldier",
		careers         = { "es_mercenary", "es_huntsman", "es_knight" },
		right_hand_unit = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Axe and Shield",
		rarity          = "default",
		power_level     = 5,
		item_type       = "cwv_es_axe_shield",
	},
	{
		item_key        = "cwv_es_axe_shield_veteran",
		base_weapon     = "dr_shield_axe",
		display_name    = "Imperial Axe and Shield",
		description     = "A battle-hardened hatchet paired with a sturdy imperial shield. Reforged for Kruber's arsenal.",
		character       = "empire_soldier",
		careers         = { "es_mercenary", "es_huntsman", "es_knight" },
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Imperial Axe and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
		item_type       = "cwv_es_axe_shield",
	},
	{
		item_key        = "cwv_we_sword_shield",
		base_weapon     = "es_sword_shield",
		display_name    = "Sword and Shield",
		description     = "An elven blade paired with an Athel Loren shield.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Sword and Shield",
		rarity          = "default",
		power_level     = 5,
		template        = "elven_sword_shield_template",
	},
	{
		item_key        = "cwv_we_sword_shield_veteran",
		base_weapon     = "es_sword_shield",
		display_name    = "Elven Sword and Shield",
		description     = "A keen elven blade paired with a sturdy Athel Loren shield. Forged for the Asrai's front line.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Elven Sword and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
		template        = "elven_sword_shield_template",
	},
	{
		item_key        = "cwv_es_longsword",
		base_weapon     = "es_bastard_sword",
		display_name    = "Recruit Longsword",
		description     = "Standard issue to the state regiments of the Reikland. Forged in their thousands by the smithies of Altdorf — serviceable steel for the men who hold the line against beast and greenskin alike.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		-- QUESTION: model is from two_handed_swords_template_1 (Kruber greatsword) but
		-- this entry uses imperial_longsword_template (cloned from bastard_sword_template).
		-- Mismatched model+moveset is intentional per CHANGELOG v0.1.25, but worth
		-- documenting in DEVELOPMENT.md.
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
		inventory_icon  = "icon_wpn_empire_2h_sword_04_t1",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Recruit Longsword",
		rarity          = "default",
		-- CLARIFY: power_level = 5 is intentional (a "blacksmith template" item per
		-- CHANGELOG v0.1.25), not a typo for 300. Properties roll on power_level.
		power_level     = 5,
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`.
	},
	{
		item_key        = "cwv_es_longsword_blackguard",
		base_weapon     = "es_bastard_sword",
		display_name    = "Black Guard Blade",
		description     = "Borne by the Knights of Morr, the black-mantled brotherhood of the death-god whose vigil keeps Stirland's tombs sealed against the necromancers of Sylvania.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2",
		inventory_icon  = "icon_wpn_empire_2h_sword_03_t2",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Black Guard Blade",
		rarity          = "unique",
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`.
	},
	{
		-- Imperial Longsword and Shield: Bretonnian sword+shield moveset
		-- (`one_handed_sword_shield_template_2`, native to es_questingknight)
		-- repurposed as Kruber's longsword+shield combo. Right hand uses the
		-- Recruit Longsword mesh (`wpn_2h_sword_04_t1`); left hand uses
		-- Kruber's standard Empire shield (`wpn_emp_shield_02`). Cosmetic
		-- illusion picker registers every unique shield from the vanilla
		-- `es_sword_shield` skin pool (Empire Shield 01 / 02 / 03 / 04 / 05
		-- + runed variants) on the left, paired with the same Imperial
		-- Longsword mesh on the right.
		--
		-- Native template's animations work on all 4 Kruber careers (per
		-- weapon_tweaker's existing es_sword_shield_breton cross-access on
		-- Mercenary/Huntsman/Knight at weapon_tweaker.lua:30-33 — proven
		-- compatible). No anim remap or wield routing needed.
		--
		-- DLC: `es_sword_shield_breton` is `required_dlc = "lake"` in vanilla;
		-- `_build_entry` strips `required_dlc` from the cwv variant so users
		-- without Lake DLC can still equip it. Mesh assets (`wpn_2h_sword_*`,
		-- `wpn_emp_shield_*`) live in base packages, so they resolve without
		-- the DLC.
		item_key        = "cwv_es_longsword_shield",
		base_weapon     = "es_sword_shield_breton",
		display_name    = "Imperial Longsword and Shield",
		description     = "A Reikland longsword paired with a state-issue shield. The Empire's answer to the Grail Knight's pose — proper steel and a wall of oak.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Imperial Longsword and Shield",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_longsword_shield",
		-- Stat tune (v0.1.310): match the 2H Imperial Longsword on sword swings
		-- only (-15% damage, +15% speed, +15% cleave, -15% stagger). Shield
		-- bashes, block, and the universal push are untouched. See
		-- `_create_imperial_longsword_shield_template`.
		template        = "imperial_longsword_shield_template",
	},
	{
		-- Kruber javelin variant: uses we_javelin's throwing moveset (template,
		-- slot_type=ranged, item_type=we_javelin) but swaps the held model to
		-- the Tuskgor Spear (wpn_emp_boar_spear_01). Javelin model lives on
		-- left_hand_unit (right_hand_unit is invisible during the wield pose);
		-- placing the spear on left_hand_unit matches that attachment so the
		-- throw animation drives the visible model.
		-- Stat-modifying clone via `tuskgor_javelin_template` (defined below):
		--   * 15-shot finite stack — vanilla auto-catch reload disabled
		--   * Vanilla ammo pickups refill (block_ammo_pickup=false,
		--     unique_ammo_type=false)
		--   * 2x damage on melee stabs and the throw projectile
		--   * 0.5x speed (slower wind-up + slower throw recovery)
		--
		-- Known caveats:
		--   * Thrown projectile is still the slim javelin model
		--     (Projectiles.javelin) — the held model is the boar spear, but
		--     mid-air it shows as a javelin. Fixing requires cloning the
		--     projectile config + a custom prj_*_3ps unit; the boar spear
		--     package doesn't ship a projectile variant.
		--   * Kruber's 3P body skeleton lacks elf throw events (attack_throw,
		--     throw_charge). 3P-side fix: pick anim_event_3p strings from the
		--     empire-skeleton's vocabulary (e.g. polearm wind-up events) via
		--     this template's actions, or add remaps in weapon_tweaker
		--     (_career_anim_redirect / _suffix_career_map). 1P is unaffected
		--     and needs no changes — see top-of-file ANIMATION ARCHITECTURE.
		item_key        = "cwv_es_javelin",
		base_weapon     = "we_javelin",
		display_name    = "Tuskgor Javelin",
		description     = "A heavy boar-spear, balanced for the throw. Hits like a kicking mule but takes both hands to wind up — and the supply runs out.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_invisible_weapon",
		left_hand_unit  = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01",
		-- v0.1.314: REVERTED v0.1.259's `ammo_unit = wpn_invisible_weapon`.
		-- That broke held-mesh rendering — the wielded javelin went invisible
		-- in 1P + 3P. Per `feedback_cwv_ammo_unit_required.md`: "Mirror
		-- ammo_unit + ammo_unit_3p + projectile_units_template +
		-- pickup_template_name + link_pickup_template_name from base; skin
		-- nukes them otherwise (previewer/throw/pickup all crash)." Pointing
		-- ammo_unit at invisible_weapon nuked downstream paths that read it
		-- for the held visual. Removing the override lets the skin-registration
		-- fallback (`ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)`)
		-- restore the working state: ammo_unit = boar spear, same as the held mesh.
		-- Side effect: 3P shows a duplicate boar spear as the offhand spare.
		-- TODO entry in CWV TODO covers the 3P-only hide via runtime
		-- Unit.set_unit_visibility on the spawned ammo unit.
		inventory_icon  = "icon_emp_boar_spear_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Tuskgor Javelin",
		rarity          = "exotic",
		template        = "tuskgor_javelin_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- v0.1.157 hybrid: in-flight uses vanilla `javelin` (slim elf javelin
		-- prj_we_javelin_01_3ps — properly authored, +Y is tip, no spin in
		-- flight). Pickup uses boar spear via Pickups.ammo unit_name. The
		-- vanilla `javelin` key triggers the package loader to load the elf
		-- javelin units at equip time, which is what allows them to spawn at
		-- throw time without the v0.1.71 crash. Trade: in-flight visual is
		-- slim elf javelin (brief), stuck/dropped pickup is the chunky boar
		-- spear.
		projectile_units_template = "javelin",
		pickup_template_name      = "cwv_tuskgor_javelin_pickup",
		link_pickup_template_name = "cwv_tuskgor_javelin_link_pickup",
		-- scale_3p_only: shrink the boar spear in 3P + character/illusion previews
		-- (where its native length looks oversized next to other ranged silhouettes)
		-- but leave the 1P held viewport at native scale so the throw animation
		-- doesn't clip into the camera. Tweak the 0.80 uniform if needed.
		left_hand_scale = { 0.80, 0.80, 0.80 },
		scale_3p_only   = true,
	},
	{
		-- Saltzpyre javelin variant — same Tuskgor Spear model + tuskgor_javelin_template
		-- as Kruber's cwv_es_javelin. Distinct item_key so per-character backend ids /
		-- can_wield rules don't collide. Same 3P anim caveat as the Kruber variant: WH
		-- 3P body skeleton may need throw-event remaps via weapon_tweaker. 1P needs
		-- nothing — universal across characters (see top-of-file ANIMATION ARCHITECTURE).
		item_key        = "cwv_wh_javelin",
		base_weapon     = "we_javelin",
		display_name    = "Tuskgor Javelin",
		description     = "A heavy boar-spear, balanced for the throw. Hits like a kicking mule but takes both hands to wind up — and the supply runs out.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_invisible_weapon",
		left_hand_unit  = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01",
		-- v0.1.314: REVERTED v0.1.259's ammo_unit = invisible (see cwv_es_javelin above for the full story).
		inventory_icon  = "icon_emp_boar_spear_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Tuskgor Javelin",
		rarity          = "exotic",
		template        = "tuskgor_javelin_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- v0.1.157 hybrid: same setup as cwv_es_javelin — in-flight = vanilla
		-- elf javelin (slim, no spin), pickup = boar spear visual.
		projectile_units_template = "javelin",
		pickup_template_name      = "cwv_tuskgor_javelin_pickup",
		link_pickup_template_name = "cwv_tuskgor_javelin_link_pickup",
		left_hand_scale = { 0.80, 0.80, 0.80 },
		scale_3p_only   = true,
	},
	{
		-- Outrider Grenade Launcher: Frankenstein weapon — Bardin Engineer's
		-- Trollhammer Torpedo behavior (single explosive projectile,
		-- charge-and-release mechanics, blast damage) wrapped in Kruber's
		-- blunderbuss visual layer (model + 1P/3P state machine + wield
		-- animations). Per user: "WIP, I'll have to test."
		--
		-- Cross-character considerations:
		--   * 1P state machine: blunderbuss state machine is shared across
		--     characters via first_person_base unit (per top-of-file
		--     ANIMATION ARCHITECTURE) — Kruber natively wields blunderbuss
		--     so all 1P anims work.
		--   * 3P body events: blunderbuss anim_event "attack_shoot" is
		--     authored on Kruber's empire-soldier 3P body (his vanilla
		--     blunderbuss uses it). The trollhammer template's action_one
		--     uses the same "attack_shoot" event, so no per-action remap
		--     needed — events fall through cleanly.
		--
		-- Tunes (vs vanilla trollhammer):
		--   * speed 2500 → 3500 (faster projectile, "travels further/faster")
		--   * reload_time 3 → 2 (faster reload than the trollhammer)
		--   * damage 0.65× (proportionally smaller damage and stagger via
		--     damage profile clone — see _create_outrider_grenade_launcher_template)
		--   * max_range 20 → 30 (longer aim-assist reach)
		--
		-- KNOWN WIP / TODO:
		--   * Explosion radius — `ExplosionTemplates.dr_deus_01` isn't in the
		--     decompiled source we work from, so the explosion template is
		--     used as-is (vanilla trollhammer radius). Smaller-radius tune
		--     is a follow-up once the user tests the current behavior in
		--     game.
		--   * Projectile model — currently uses the trollhammer torpedo
		--     model (Projectiles.dr_deus_01). User mentioned wanting a
		--     grenade-shaped projectile; that's a follow-up — projectile_info
		--     needs custom Projectiles.cwv_outrider_grenade entry pointing
		--     at a grenade-shaped unit.
		item_key        = "cwv_es_outrider_grenade_launcher",
		base_weapon     = "dr_deus_01",
		display_name    = "Outrider Grenade Launcher",
		description     = "An imperial-pattern grenade launcher in the Outrider style — built on a blunderbuss frame, fires a single charge-loaded grenade. Fewer pellets, more boom.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1",
		-- Trollhammer is left-hand-mount (entry inherits left_hand_unit =
		-- wpn_dr_deus_01 from the clone). We're moving to right-hand-mount
		-- on the blunderbuss model — clear the inherited left so the preview
		-- doesn't render BOTH weapons.
		no_left_hand    = true,
		inventory_icon  = "icon_wpn_empire_blunderbuss_t1",
		hud_icon        = "weapon_generic_icon_blunderbuss",
		skin_display_name = "Outrider Grenade Launcher",
		rarity          = "exotic",
		template        = "outrider_grenade_launcher_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_outrider_grenade_launcher",
	},
	-- v0.1.300: cwv_es_musket variant put ON ICE per user request — kept as a
	-- backup idea (don't delete). The cross-slot stance-toggle approach using
	-- the vanilla rifle's mesh with weird scaling worked but the cwv_es_musket_old
	-- variant with a proper custom mesh is the live one. To re-enable: uncomment
	-- the block below. The supporting code (musket_template + musket_template_melee
	-- + bayonet system) is still in place so this variant works the moment it's
	-- re-added to the list. _create_musket_template / _melee still run at boot.
	--[[
	{
		item_key        = "cwv_es_musket",
		base_weapon     = "es_handgun",
		display_name    = "Musket",
		description     = "A long-barrel imperial musket — heavier and slower than the standard rifle, but harder-hitting and fitted with a fixed bayonet for close work. The Reikland regiments who carry these prefer one good shot to a flurry of mediocre ones. Equippable in the melee or ranged slot.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",
		inventory_icon  = "icon_wpn_empire_handgun_t1",
		hud_icon        = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
		skin_display_name = "Musket",
		rarity          = "exotic",
		template        = "musket_template",
		traits          = { "ranged_increase_power_level_vs_armour_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_musket",
		instances       = 2,
		instance_skins  = { nil, "cwv_es_musket_aunty_bessie" },
	},
	]]
	{
		-- "Old Musket" — second cwv musket variant. v0.1.286 LA-pattern rewrite:
		-- right_hand_unit IS our custom mesh path. The .unit file uses LA's
		-- `data = { mat_to_use = "<vanilla>" }` pattern which references a
		-- vanilla 1P/3P weapon material at runtime — that's how we get proper
		-- FP rendering (no shadow in FP, correct depth, no overlay drawn on
		-- top of hands). The PackageManager.load/unload/has_loaded hooks below
		-- (search "_LA_PATTERN_CUSTOM_PACKAGES") intercept the engine's
		-- attempts to package-load our custom path and silently no-op, so
		-- there's no "Resource not found" crash.
		-- v0.1.277-285 history: ran an overlay (World.spawn_unit + link_unit
		-- against a vanilla rifle) — got the mesh on screen but with wrong
		-- render layer (cast shadow in FP, always-on-top depth bug). Replaced
		-- with the LA pattern in v0.1.286.
		-- v0.1.302: equippable in BOTH ranged AND melee inventory slots via
		-- the cross-slot inject hook. Stance toggle (special key, F/C) flips
		-- between two templates regardless of which slot it's equipped in:
		--   * old_musket_template (ranged):   handgun_template_1 + 1.5x damage + 1.5x reload time vs vanilla rifle
		--   * old_musket_template_melee:      Tuskgor spear clone + 1.2 range_mod + 0.9x melee damage vs vanilla spear
		-- The mesh has a bayonet baked into the FBX so no separate bayonet
		-- child unit is spawned (v0.1.278 gate).
		item_key        = "cwv_es_musket_old",
		base_weapon     = "es_handgun",
		display_name    = "Old Musket",
		description     = "An older imperial pattern — heavier wood, longer barrel, fitted bayonet. Hits harder than the standard rifle, reloads slower. Special key (F/C) flips between rifle stance and bayonet stance.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/cwv_es_musket_custom/cwv_es_musket_custom",
		inventory_icon  = "icon_wpn_empire_handgun_t1",
		hud_icon        = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
		skin_display_name = "Old Musket",
		rarity          = "exotic",
		template        = "old_musket_template",
		traits          = { "ranged_increase_power_level_vs_armour_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_musket_old",
		instances       = 2,
		-- v0.1.311: cross-slot eligible. _build_entry sets entry.slot_type =
		-- "cwv_dual" so the item shows in both slot_melee AND slot_ranged
		-- grids (Kruber careers' slot type list extended at mod init).
		cross_slot      = true,
	},
	{
		item_key        = "cwv_es_longsword_nordland",
		base_weapon     = "es_bastard_sword",
		display_name    = "Nordland Claymore",
		description     = "Forged for the swordsmen of Nordland's coastal regiments, who have stood against the Norscan reaver from Salzenmund to the Sea of Claws. The grip is bound in seal-hide for a surer hold in the rain and salt-spray of the northern shore.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_greatsword/wpn_greatsword",
		inventory_icon  = "icon_wpn_greatsword",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Nordland Claymore",
		rarity          = "exotic",
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- skin_only = true means this entry is registered for skin/illusion purposes
		-- only — it never gets handed to the player as a real inventory item via
		-- _auto_register_all (skipped at line 830). It still produces a custom skin
		-- entry in _register_variant_skins (which checks def.no_skin, not skin_only).
		skin_only       = true,
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`. Note:
		-- this variant uses `wpn_greatsword` (different model from the Empire
		-- 2h_sword family), so the type-level Y-width / Z-length convention
		-- may not be a perfect fit. If the Helmgart reads wrong, override
		-- with per-variant `right_hand_scale` / `right_hand_offset` here.
	},
	{
		item_key        = "cwv_dr_priest_greathammer",
		base_weapon     = "wh_2h_hammer",
		display_name    = "Sigmarite Greathammer",
		description     = "A Sigmarite warrior-priest's greathammer in the form of a familiar dwarf two-hander. Charge it up and bring Sigmar's wrath crashing down.",
		character       = "dwarf_ranger",
		careers         = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" },
		right_hand_unit = "units/weapons/player/wpn_dw_2h_hammer_01_t1/wpn_dw_2h_hammer_01_t1",
		inventory_icon  = "icon_wpn_dw_2h_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Sigmarite Greathammer",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- TODO(anim): cloned moveset = two_handed_hammer_priest_template, authored
		-- against Saltzpyre's 3P body skeleton. Dwarf 3P body anim event coverage
		-- NOT yet verified or remapped — see CHANGELOG 0.1.61 known issues. 1P
		-- needs nothing — universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE).
	},
	{
		item_key        = "cwv_es_priest_greathammer",
		base_weapon     = "wh_2h_hammer",
		display_name    = "Sigmarite Greathammer",
		description     = "A Sigmarite warrior-priest's greathammer in the form of a familiar Reikland two-hander. Charge it up and bring Sigmar's wrath crashing down.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_hammer_01_t1/wpn_2h_hammer_01_t1",
		inventory_icon  = "icon_wpn_empire_2h_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Sigmarite Greathammer",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_priest_greathammer",
		-- TODO(anim): cloned moveset = two_handed_hammer_priest_template, authored
		-- against Saltzpyre's 3P body skeleton. Saltzpyre and Kruber are both
		-- empire-human 3P skeletons so most events likely overlap, but coverage
		-- NOT yet verified — see CHANGELOG 0.1.61 known issues. 1P needs nothing
		-- — universal across characters (see top-of-file ANIMATION ARCHITECTURE).
	},
	{
		-- Warrior-Priest Hammer: Saltzpyre's wh_1h_hammer (Skullsplitter) cloned
		-- onto Kruber. Same model and one-handed priest-hammer moveset; carries
		-- the rescaled `es_2h_hammer_skin_*` greathammer illusions as cosmetic
		-- options (see `_custom_illusions` block — entries with
		-- `target_combo = "cwv_es_warpriest_hammer_skins"`). Picker shows the
		-- vanilla wh_1h_hammer mesh by default plus the 8 oversized-greathammer
		-- alternatives the user iterated through in v0.1.151.
		item_key        = "cwv_es_warpriest_hammer",
		base_weapon     = "wh_1h_hammer",
		display_name    = "Warrior-Priest Hammer",
		description     = "A warrior-priest's blessing-hammer, taken up by the state regiments who fight beside Sigmar's chosen. Single-handed, faster than the greathammer, no less righteous.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		inventory_icon  = "icon_wpn_wh_1h_hammer_01",
		hud_icon        = "weapon_generic_icon_hammer1h",
		skin_display_name = "Warrior-Priest Hammer",
		rarity          = "exotic",
		template        = "one_handed_hammer_priest_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_warpriest_hammer",
		-- TODO(anim): cloned moveset = one_handed_hammer_priest_template,
		-- authored against Saltzpyre's 3P body skeleton. Both Saltzpyre and
		-- Kruber are empire-human 3P skeletons so most events likely overlap;
		-- if any 3P clip plays nothing, add a per-event remap entry. 1P
		-- needs nothing — universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE).
	},
	{
		-- Maul: Sienna's bw_1h_mace template (Morningstar — visually
		-- two-handed despite the "1h" naming) cloned for Kruber.
		-- Default mesh: Kruber's mace+sword mace (wpn_emp_mace_04_t2);
		-- curated illusions are the OTHER mace meshes from
		-- es_dual_wield_hammer_sword skins (mace+sword's mace half only —
		-- sword half discarded). Registered by
		-- _register_macesword_mace_maul_illusions. Type-level scale
		-- inflates the 1H mesh into a 2H silhouette; shared across
		-- default + every illusion via _type_transforms.
		--
		-- Source template: one_handed_hammer_wizard_template_1.
		-- Carries fire damage in EXACTLY one place — `medium_blunt_smiter_heavy`
		-- (H1 heavy attack)'s default_target chains to
		-- `default_target_slashing_smiter_burn_M`. Damage-type swap
		-- handled in `_create_maul_template`: H1's damage_profile is
		-- swapped to `medium_blunt_smiter_2h_hammer` (same heavy-smiter
		-- shape, no burn). All other profiles (lights L1-L3, heavy H2/H3,
		-- pushes) are clean — no FX/sound swaps needed (verified
		-- against `1h_hammers_wizard.lua` — all `melee_hit_hammers_1h`
		-- + `blunt_hit`, no `staff_spark` or `fire_hit`).
		--
		-- 3P wield routes to Kruber's greathammer SM (to_2h_hammer);
		-- per-action remap covers wizard-mace events that aren't in
		-- two_handed_hammers_template_1's closed vocabulary.
		item_key        = "cwv_es_maul",
		base_weapon     = "bw_1h_mace",
		display_name    = "Maul",
		description     = "A heavy reikland war-maul — double-fisted iron, swung with the weight of both shoulders. Slower than a sword, but it caves armour.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
		-- TODO icon: placeholder uses Sienna's mace icon. Variant is NOT
		-- complete until proper inventory_icon + hud_icon are authored.
		inventory_icon  = "icon_wpn_brw_mace_01",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Maul",
		rarity          = "exotic",
		template        = "maul_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_maul",
		-- Scale lives at type level: _type_transforms.cwv_es_maul.
	},
	{
		-- Poleaxe: Bardin's dr_2h_axe (Greataxe) template cloned for
		-- Kruber. Default mesh: Kruber's halberd. Type-level scale
		-- (1, 1, 0.65) shortens the halberd's Z-length so it reads as
		-- a polearm, not a full halberd.
		--
		-- Source template: two_handed_axes_template_1. Already wields
		-- to to_2h_hammer (Kruber's greathammer SM is native), so no
		-- wield_anim_3p patch needed. Per-action remap covers a few
		-- greataxe events (heavy_*_diagonal, swing_up) not in
		-- two_handed_hammers_template_1's vocabulary.
		--
		-- No fire damage (verified — heavy_slashing_axe_linesman /
		-- medium_slashing_smiter_2h / medium_slashing_axe_linesman
		-- have no _burn_ references).
		item_key        = "cwv_es_poleaxe",
		base_weapon     = "dr_2h_axe",
		display_name    = "Poleaxe",
		description     = "A reikland poleaxe — axe-head, hammer-back, and a piercing spike on the crown. Cuts cavalry, breaks armour, and reaches further than a soldier's blade.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_halberd_01/wpn_wh_halberd_01",
		-- TODO icon: placeholder uses vanilla halberd icon. Variant is NOT
		-- complete until proper inventory_icon + hud_icon are authored.
		inventory_icon  = "icon_wpn_wh_halberd_01",
		hud_icon        = "weapon_generic_icon_staff_3",
		skin_display_name = "Poleaxe",
		rarity          = "exotic",
		template        = "poleaxe_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_poleaxe",
		-- Scale lives at type level: _type_transforms.cwv_es_poleaxe.
	},
	{
		-- Rapier: Saltzpyre's `wh_fencing_sword` template cloned for
		-- Kruber, with the pistol shoot ability disabled. Pistol mesh
		-- replaced with the invisible weapon unit so only the rapier
		-- renders (left_hand_unit slot held but not visible).
		--
		-- Source template: fencing_sword_template_1. Carries an
		-- `action_three` (kind="handgun", anim_event="attack_shoot") that
		-- fires the off-hand pistol; `_create_rapier_template` overrides
		-- its `condition_func` / `chain_condition_func` to a `_always_false`
		-- closure (same pattern as the tuskgor javelin's auto-catch
		-- reload disable in v0.1.65). Action stays defined for
		-- state-machine / network consistency but never fires.
		--
		-- 3P wield routes to Kruber's native `to_1h_sword` SM. Closed-vocab
		-- per-action remap covers fencing-specific events
		-- (attack_swing_stab, attack_swing_stab_charge, attack_swing_left)
		-- not authored on Kruber's 1h_sword vocabulary.
		--
		-- Type-level scale `{1.1, 1.25, 1.0}` broadens X/Y for a
		-- basket-hilt feel. Curated illusions: every
		-- `wh_fencing_sword_skin_*` (registered by
		-- `_register_rapier_illusions`), each with the pistol forced
		-- invisible.
		item_key        = "cwv_es_rapier",
		base_weapon     = "wh_fencing_sword",
		display_name    = "Rapier",
		description     = "A reikland duellist's basket-hilted rapier. The cup-guard catches steel; the long thrust reaches farther than a state-issue blade.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1",
		-- Single-handed: NO left mesh at all. Sentinel `no_left_hand = true`
		-- tells `_build_entry` to nil out the inherited `left_hand_unit` from
		-- the base fencing-sword IML entry (which has the pistol). With
		-- entry.left_hand_unit = nil, vanilla's
		-- `if item_units.left_hand_unit then ... end` skips the entire
		-- left-hand spawn pipeline (in-game equip + cosmetic picker BOTH).
		-- Replaces the v0.1.187 invisible-pistol approach which crashed the
		-- cosmetic picker on default-skin render (crash GUIDs
		-- 962fe355-... and 77e636ee-...). Picker no longer tries to
		-- attach anything at j_leftweaponattach because there's nothing
		-- to attach.
		no_left_hand    = true,
		-- TODO icon: placeholder uses vanilla fencing-sword icon. Variant
		-- is NOT complete until proper inventory_icon + hud_icon are
		-- authored.
		inventory_icon  = "icon_wpn_fencingsword_01_t1",
		hud_icon        = "weapon_generic_icon_fencing_sword",
		skin_display_name = "Rapier",
		rarity          = "exotic",
		template        = "rapier_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_rapier",
		-- Scale lives at type level: _type_transforms.cwv_es_rapier.
	},
	{
		item_key        = "cwv_es_dual_swords",
		base_weapon     = "we_dual_wield_swords",
		display_name    = "Imperial Dual Swords",
		description     = "Two Reikland arming swords wielded in tandem. Heavier and slower than the elven dance, but each blow lands with imperial weight.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		inventory_icon  = "icon_wpn_emp_sword_02_t1",
		hud_icon        = "weapon_generic_icon_dual_elf_sword",
		skin_display_name = "Imperial Dual Swords",
		rarity          = "exotic",
		template        = "imperial_dual_swords_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_dual_swords",
		right_hand_scale = { 1.0, 1.0, 1.0 },
		left_hand_scale  = { 1.0, 1.0, 1.0 },
		-- Single-handed sword model reads slightly small in first-person view —
		-- bump 1P only by 10%. 3P keeps native scale (other players see this).
		right_hand_scale_1p = { 1.1, 1.1, 1.1 },
		left_hand_scale_1p  = { 1.1, 1.1, 1.1 },
	},
	{
		-- Sword and Mace: INVERSE of Kruber's mace+sword. Sword in RIGHT hand,
		-- mace in LEFT hand. Visual models are his vanilla 1H sword
		-- (`wpn_emp_sword_02_t1`, from `es_1h_sword`) and 1H mace
		-- (`wpn_emp_mace_02_t1`, from `es_1h_mace`).
		--
		-- Damage profiles, hit effects, and impact sounds per-sub-action are
		-- swapped between blunt (was mace) and slashing (was sword) based on
		-- weapon_action_hand — see `sword_and_mace_template` clone above.
		item_key        = "cwv_es_sword_and_mace",
		base_weapon     = "es_dual_wield_hammer_sword",
		display_name    = "Sword and Mace",
		description     = "A reikland sword in the strong hand, a mace as the off-hand counterweight. The mirror of the soldier's pair.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Sword and Mace",
		rarity          = "exotic",
		template        = "sword_and_mace_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table — without
		-- this, the variant inherits es_dual_wield_hammer_sword's vanilla
		-- skin_combination_table and the picker shows vanilla mace+sword
		-- skins (which would invert the variant's intent: vanilla skins set
		-- mace=right + sword=left, the OPPOSITE of this variant's
		-- sword=right + mace=left layout).
		item_type       = "cwv_es_sword_and_mace",
	},
	{
		-- Cudgel: Saltzpyre's falchion moveset (one_hand_falchion_template_1)
		-- with every cutting hit converted to a crushing one — slashing damage
		-- profiles → blunt cousins, axe/sword hit effects → hammer effects,
		-- slashing impact sounds → blunt thuds. See `cudgel_template` clone
		-- below. Visual model stays the Empire mace from Kruber's mace+sword
		-- (`wpn_emp_mace_04_t2`), so it reads as a heavier baton with the
		-- charge-and-release tempo of a falchion. Cross-character moveset
		-- (falchion is wh_1h_falchion's native template) — Kruber's 3P body
		-- already plays falchion anims via WT's `wh_1h_falchion` cross-access.
		item_key        = "cwv_es_cudgel",
		base_weapon     = "es_1h_mace",
		display_name    = "Cudgel",
		description     = "A heavy iron baton swung with a duellist's tempo — wind up, snap through, follow with a crushing overhead.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Cudgel",
		rarity          = "exotic",
		template        = "cudgel_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
	},
	{
		-- Shortsword: Sienna's dagger moveset (one_handed_daggers_template_1)
		-- with the fire DoT scrubbed and stats tweaked — −20% speed, +15%
		-- power. Visual model is Kruber's mace+sword sword (`wpn_emp_sword_06_t1`).
		-- Stats + DoT-removal handled in shortsword_template clone below.
		-- For Kruber — dagger moveset on his empire-soldier 3P body (cross-
		-- character; if specific anim events don't read on his sub-graph,
		-- a `_cross_access_action_remap` entry can be added).
		item_key        = "cwv_es_shortsword",
		base_weapon     = "bw_dagger",
		display_name    = "Shortsword",
		description     = "An unenchanted reikland shortsword. Quick steel for close work.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		-- Sienna's dagger model is bigger than a Reikland shortsword should
		-- read; thin it on the X/Y axes (length kept at native).
		right_hand_scale = { 0.7, 0.7, 1.0 },
		right_hand_unit = "units/weapons/player/wpn_emp_sword_06_t1/wpn_emp_sword_06_t1",
		inventory_icon  = "icon_wpn_brw_dagger_01",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Shortsword",
		rarity          = "exotic",
		template        = "shortsword_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
	},
	-- ============================================================
	-- Dual Axes — Saltzpyre's 1H axe model dual-wielded
	-- Both Kruber + Saltzpyre variants share Bardin's dual-axes moveset
	-- (template = "dual_wield_axes_template_1") with a model swap to
	-- Saltzpyre's wpn_axe_hatchet_t1. 3P wield routes per-character via
	-- _cross_access_template_wield_3p (Kruber → mace+sword, Saltzpyre →
	-- axe+falchion).
	-- ============================================================
	{
		item_key        = "cwv_es_dual_axes",
		base_weapon     = "dr_dual_wield_axes",
		display_name    = "Dual Axes",
		description     = "Twin reikland hatchets in either hand. Soldier's choice for close, fast work.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		left_hand_unit  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		inventory_icon  = "icon_wpn_axe_hatchet_t1",
		hud_icon        = "weapon_generic_icon_axe1h",
		skin_display_name = "Dual Axes",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table so the
		-- Saltzpyre 1h-axe cosmetic illusions appended by
		-- `_register_saltzpyre_1h_axe_dual_illusions` show up in the picker
		-- on this variant only (not on every dr_dual_wield_axes wielder).
		item_type       = "cwv_es_dual_axes",
	},
	{
		item_key        = "cwv_wh_dual_axes",
		base_weapon     = "dr_dual_wield_axes",
		display_name    = "Dual Axes",
		description     = "Twin hatchets — bite, hook, and cleave in the witch hunter's hands.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		left_hand_unit  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		inventory_icon  = "icon_wpn_axe_hatchet_t1",
		hud_icon        = "weapon_generic_icon_axe1h",
		skin_display_name = "Dual Axes",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
	},
	-- ============================================================
	-- Dual Maces — Kruber's 1H mace model dual-wielded
	-- Both Kruber + Saltzpyre variants share Bardin's dual-hammers moveset
	-- (template = "dual_wield_hammers_template") with a model swap to
	-- Kruber's wpn_emp_mace_02_t1. 3P wield routes per-character via
	-- _cross_access_template_wield_3p (Kruber → mace+sword, Saltzpyre →
	-- dual_hammers, wh_priest → dual_hammers_priest).
	-- ============================================================
	{
		item_key        = "cwv_es_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		display_name    = "Dual Maces",
		description     = "Two reikland maces. Crushing strikes in both hands — armour breakers and skull crackers.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dual Maces",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table so vanilla
		-- dr_dual_wield_hammers skins (Bardin's slayer dual-axes-style hammers)
		-- don't bleed into the picker. Dual-wield display rig (`display_dual_hammers`)
		-- is forced in `_force_display_unit` to prevent the j_leftweaponattach
		-- crash on the cosmetic picker.
		item_type       = "cwv_es_dual_maces",
	},
	{
		item_key        = "cwv_wh_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		display_name    = "Dual Maces",
		description     = "Two reikland maces, judgement in steel. The witch hunter's blunt sermon.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dual Maces",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- See cwv_es_dual_maces above for the item_type / display rig rationale.
		item_type       = "cwv_wh_dual_maces",
	},
	{
		-- Dual Warrior-Priest Hammers — paired clone of cwv_es_warpriest_hammer
		-- (which is itself a clone of Saltzpyre's wh_1h_hammer Skullsplitter).
		-- Uses vanilla `wh_dual_hammer` as base_weapon: Saltzpyre's Bless DLC
		-- priest dual-hammers item, template `dual_wield_hammers_priest_template`,
		-- mesh `wpn_wh_1h_hammer_01` on each hand (identical-mesh dual-wield).
		-- Native on all 4 Kruber careers.
		--
		-- ANIMATION ROUTING: the priest template's default wield event is
		-- `to_dual_hammers_priest`, which doesn't exist on Kruber's empire-soldier
		-- 3P body skeleton. Routed to `to_dual_hammer_sword_es` (Kruber's mace+sword
		-- SM) via `_cross_access_template_wield_3p[dual_wield_hammers_priest_template]`
		-- below — same approach as cwv_es_dual_maces uses for non-priest
		-- dual_wield_hammers_template. This is the Kruber-specific equivalent of
		-- weapon_tweaker's `to_dual_hammers_priest → to_dual_hammers` redirect
		-- (which targets Bardin's body, where `to_dual_hammers` exists natively).
		--
		-- GRIP OFFSET: matches weapon_tweaker's `wh_1h_hammer = { es_ = {0,0,0.15} }`
		-- tune (per `feedback_grip_offset_sign.md` — +Z lowers grip onto haft
		-- when the priest hammer rides high on the empire-soldier hand bone).
		-- Same mesh, same hand bone, same correction needed on each hand.
		item_key        = "cwv_es_dual_warpriest_hammers",
		base_weapon     = "wh_dual_hammer",
		display_name    = "Dual Warrior-Priest Hammers",
		description     = "A pair of warrior-priest blessing-hammers, taken up by Reikland regiments who fight beside Sigmar's chosen. The two-handed prayer of justice, dealt in stereo.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		left_hand_unit  = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		inventory_icon  = "icon_wpn_wh_dual_hammer_skin_01_t1",
		hud_icon        = "weapon_generic_icon_hammer1h",
		skin_display_name = "Dual Warrior-Priest Hammers",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_dual_warpriest_hammers",
		right_hand_offset = { 0, 0, 0.15 },
		left_hand_offset  = { 0, 0, 0.15 },
	},
	{
		-- Warrior-Priest Hammer and Shield — clone of Saltzpyre's Bless DLC
		-- `wh_hammer_shield` (priest 1H hammer + shield) on Kruber. Right-hand
		-- mesh is the Skullsplitter `wpn_wh_1h_hammer_01`, left-hand is the
		-- standard Empire shield `wpn_emp_shield_02` (not Saltzpyre's
		-- wpn_wh_shield_01 — this variant lives on Kruber's body).
		--
		-- ANIMATION ROUTING: the priest template's default wield event is
		-- `to_1h_hammer_shield_priest`, only authored on Saltzpyre's wh_priest
		-- 3P body. Kruber routes via
		-- `_cross_access_template_wield_3p[one_handed_hammer_shield_priest_template]`
		-- to `to_1h_hammer_shield` (his vanilla mace+shield wield). Mirrors
		-- weapon_tweaker's `to_1h_hammer_shield_priest → to_1h_hammer_shield`
		-- redirect at weapon_tweaker.lua:231 (which targets all non-priest
		-- careers).
		--
		-- GRIP OFFSET: matches weapon_tweaker's `wh_hammer_shield = { es_ = {0,0,0.15} }`
		-- tune (right hand only — same Skullsplitter haft riding high on the
		-- empire-soldier hand bone, like the single 1H and dual variants).
		item_key        = "cwv_es_warpriest_hammer_shield",
		base_weapon     = "wh_hammer_shield",
		display_name    = "Warrior-Priest Hammer and Shield",
		description     = "A warrior-priest's blessing-hammer paired with a state-issue shield. Sigmar's wrath in the strong hand, faith and steel in the other.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_wh_shield_01_t1",
		hud_icon        = "weapon_generic_icon_hammer_and_sheild",
		skin_display_name = "Warrior-Priest Hammer and Shield",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_warpriest_hammer_shield",
		right_hand_offset = { 0, 0, 0.15 },
	},
}

-- ============================================================
-- Cross-character access: extend can_wield on vanilla dual-wield items
-- ============================================================
-- Some weapons read fine on the "other" character without any model swap or
-- variant — just expand the vanilla item's can_wield list so the new careers
-- can equip the existing inventory item directly. No new item is created;
-- inventory shows the original Saltzpyre / Kruber weapon as-is.
local _cross_access_can_wield = {
	wh_1h_falchion             = _es_all_careers,  -- Kruber gets Saltzpyre's Falchion
	wh_dual_wield_axe_falchion = _es_all_careers,  -- Kruber gets Saltzpyre's Axe + Falchion
	es_dual_wield_hammer_sword = _wh_all_careers,  -- Saltzpyre gets Kruber's Mace + Sword
}

local function _apply_cross_access_can_wield()
	if not ItemMasterList then return end
	for item_key, careers_to_add in pairs(_cross_access_can_wield) do
		local item = rawget(ItemMasterList, item_key)
		if item and type(item.can_wield) == "table" then
			for _, career in ipairs(careers_to_add) do
				local already_present = false
				for _, existing in ipairs(item.can_wield) do
					if existing == career then
						already_present = true
						break
					end
				end
				if not already_present then
					item.can_wield[#item.can_wield + 1] = career
				end
			end
		end
	end
end

_apply_cross_access_can_wield()

-- 3P wield routing for the cross-access dual-wield items. Each character
-- body gets routed into its native dual-wield sub-graph so idle / walk /
-- block reads correctly:
--   Kruber (es_*)        → to_dual_hammer_sword_es (his mace+sword SM)
--   Saltzpyre (wh_*)     → to_dual_axe_sword_wh    (his axe+falchion SM, for dual axes)
--   Saltzpyre wh_priest  → to_dual_hammers_priest  (his Bless dual-hammers SM, for dual maces)
--   Saltzpyre other wh_* → to_dual_hammers         (cross-character into the dual_hammers SM)
-- Bardin careers (dr_*) aren't listed and fall through to each template's
-- default wield_anim (to_dual_axes / to_dual_hammers), so Bardin natives are
-- unaffected.
--
-- Per-action anim_event_3p is intentionally NOT remapped — same-named events
-- that exist on the target sub-graph play visibly, others may fail silently.
-- If specific attacks read wrong on a body, a per-template clone with an
-- anim_event_3p remap can be added later (see imperial_dual_swords_template
-- for that pattern). Starting simple per "no templates from scratch".
local _cross_access_template_wield_3p = {
	-- Saltzpyre's Axe + Falchion on Kruber: native wield event is
	-- `to_dual_axe_sword_wh`, which isn't authored on Kruber's empire-soldier
	-- 3P body. Route Kruber careers into his mace+sword SM. Saltzpyre's careers
	-- are intentionally absent — his witch-hunter body wields this template
	-- natively, so no redirect needed.
	dual_wield_axe_falchion_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	},
	-- Bardin's Dual Axes template: used by the cwv_es_dual_axes and
	-- cwv_wh_dual_axes variants below. Kruber routes to mace+sword;
	-- Saltzpyre routes to his axe+falchion SM. Bardin careers (dr_*) are
	-- intentionally absent — they wield Bardin's native dr_dual_wield_axes
	-- with the unmodified default wield (to_dual_axes).
	dual_wield_axes_template_1 = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
		wh_captain        = "to_dual_axe_sword_wh",
		wh_bountyhunter   = "to_dual_axe_sword_wh",
		wh_zealot         = "to_dual_axe_sword_wh",
		wh_priest         = "to_dual_axe_sword_wh",
	},
	-- Bardin's Dual Hammers template: used by the cwv_es_dual_maces and
	-- cwv_wh_dual_maces variants below. Kruber routes to mace+sword;
	-- non-priest Saltzpyre uses dual_hammers; wh_priest gets his Bless DLC
	-- dual_hammers_priest variant. Bardin (dr_*) absent — keeps default.
	dual_wield_hammers_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
		wh_captain        = "to_dual_hammers",
		wh_bountyhunter   = "to_dual_hammers",
		wh_zealot         = "to_dual_hammers",
		wh_priest         = "to_dual_hammers_priest",
	},
	-- Saltzpyre's Bless DLC priest Dual Hammers template: used by the new
	-- cwv_es_dual_warpriest_hammers variant (Kruber-side clone of
	-- vanilla wh_dual_hammer). The template's default wield event is
	-- `to_dual_hammers_priest`, only authored on Saltzpyre's wh_priest 3P
	-- body. For Kruber careers, route into his mace+sword SM
	-- (`to_dual_hammer_sword_es`) — same approach cwv_es_dual_maces uses
	-- for non-priest dual_wield_hammers_template, and the Kruber-specific
	-- equivalent of weapon_tweaker's `to_dual_hammers_priest → to_dual_hammers`
	-- redirect (which targets Bardin where `to_dual_hammers` exists).
	-- Other Saltzpyre careers and Bardin absent — they wield this template
	-- natively (priest) or via vanilla mechanics if exposed via cross-access.
	dual_wield_hammers_priest_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	},
	-- Saltzpyre's Bless DLC priest 1H Hammer + Shield template: used by the
	-- new cwv_es_warpriest_hammer_shield variant (Kruber-side clone of
	-- vanilla wh_hammer_shield). The template's default wield event is
	-- `to_1h_hammer_shield_priest`, only authored on Saltzpyre's wh_priest
	-- 3P body. For Kruber careers, route to `to_1h_hammer_shield` (his
	-- vanilla mace+shield wield) — direct Kruber equivalent of
	-- weapon_tweaker's `to_1h_hammer_shield_priest → to_1h_hammer_shield`
	-- redirect at weapon_tweaker.lua:231.
	one_handed_hammer_shield_priest_template = {
		es_mercenary      = "to_1h_hammer_shield",
		es_huntsman       = "to_1h_hammer_shield",
		es_knight         = "to_1h_hammer_shield",
		es_questingknight = "to_1h_hammer_shield",
	},
}

local function _apply_cross_access_template_wield_3p()
	if not Weapons then return end
	for template_name, career_to_wield in pairs(_cross_access_template_wield_3p) do
		local tpl = Weapons[template_name]
		if tpl then
			tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
			for career, wield in pairs(career_to_wield) do
				tpl.wield_anim_career_3p[career] = wield
			end
		end
	end
end

_apply_cross_access_template_wield_3p()

-- ============================================================
-- Cross-character per-action 3P anim event remap (career-specific runtime hook)
-- ============================================================
-- WHY THIS EXISTS:
--   For weapons made cross-character via can_wield expansion (above), we
--   often need to redirect specific attack events on the foreign wielder's
--   3P body — e.g. Kruber's empire-soldier body has no overhead heavy clip
--   on its dual_hammer_sword sub-graph, so Saltzpyre's `attack_swing_heavy_down`
--   needs to play a Kruber-vocab heavy instead.
--
--   The engine's per-sub-action anim_event_3p resolution is NOT career-keyed
--   (`weapon_unit_extension.lua:512` reads `current_action_settings.anim_event_3p`
--   directly with no career context). So mutating the BASE template's
--   anim_event_3p affects EVERY wielder including the native one — wrong.
--
-- HOW THIS WORKS:
--   We hook `Unit.animation_event` and rewrite the event name when:
--     1. The target unit is the local 3P body (player.player_unit) — never 1P
--     2. The local player's career has a remap entry for the wielded weapon
--     3. The event matches the remap
--   Native wielders (their career not present in the remap) are unaffected.
--   weapon_tweaker has its own Unit.animation_event hook for cross-career
--   unlocks; both hooks coexist via VMF's hook stacking.
--
-- LIMITATIONS (relative to weapon_tweaker's full system):
--   - Local player only. Husks of remote players still see the base
--     template's events. Acceptable for now — visual fidelity for husks
--     is a fallback case; mechanics still work.
--   - No 1P remapping (universal rule — see top-of-file ANIMATION ARCHITECTURE).
--   - No suffix/career-prefix logic — remaps are explicit per (item, career).
--
-- HOW TO ADD A NEW REMAP:
--   1. Add an entry to `_cross_access_action_remap[item_key][career_name]`
--      mapping the source event → 3P substitute.
--   2. Source event names come from the BASE template's sub_action.anim_event
--      values (use `wt dump_actions <pattern>` to inspect).
--   3. Substitute event names should be authored on the wielder's body's
--      target sub-graph (the SM you wield_anim_career_3p'd to above).
--   4. Direction-coherence: when remapping a heavy release, also remap its
--      paired charge sub-action so the wind-up and strike directions match.
--      Source chain graph tells you which charge feeds which release.
--   5. Verify visually with `wt animlog` — exists=true is necessary but not
--      sufficient (stub transitions exist).
--
-- See `character_weapon_variants/DEVELOPMENT.md` "Animation: cross-access
-- runtime remap" for the long-form pattern.

-- Reusable Kruber-on-dual-axes remap (Bardin's dr_dual_wield_axes on Kruber).
-- Source events not authored on Kruber's dual_hammer_sword sub-graph:
--   attack_swing_charge_diagonal — charge that feeds heavy_attack_3
--   attack_swing_heavy_right     — heavy_attack release (fed by charge_right)
--   attack_swing_heavy           — heavy_attack_2 release (fed by charge_left)
-- heavy_attack_3 fires `attack_swing_heavy_left_diagonal` which already exists
-- on dual_hammer_sword — no remap needed there. Charge directions
-- (charge_left, charge_right) match Kruber's vocab natively; only
-- charge_diagonal needs a substitute.
local _kruber_dual_axes_remap = {
	-- Charge that feeds heavy_attack_3 (heavy_left_diagonal). Cock left to
	-- match the left-diagonal strike direction.
	attack_swing_charge_diagonal = "attack_swing_charge_left",
	-- heavy_attack release (fed by charge_right): cock right → strike
	-- right-diagonal. Direction-coherent.
	attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal",
	-- heavy_attack_2 release (fed by charge_left): cock left → strike
	-- left-diagonal. Direction-coherent.
	attack_swing_heavy           = "attack_swing_heavy_left_diagonal",
}

-- Reusable Kruber-on-axe-falchion remap (same for all 4 Kruber careers).
--
-- 3P ONLY. 1P animations are universal across all six characters via the
-- shared `first_person_base` unit and need no remap work. The
-- `Unit.animation_event` hook that consumes this table is gated to fire only
-- on the local 3P body (see five early-exits in the hook). Never add 1P-side
-- fields here — `anim_event`, `wield_anim`, `state_machine` are out of scope.
--
-- CLOSED-VOCABULARY RULE: every value MUST be an `anim_event` already
-- authored in `dual_wield_hammer_sword_template` (target wield SM). Verified
-- against `dumps/weapon_actions.txt` and the rule documented in
-- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md`. Closed list:
--   charges:   attack_swing_charge_right, attack_swing_charge_left
--   strikes:   attack_swing_heavy_left_diagonal, attack_swing_heavy_right_diagonal,
--              attack_swing_left_diagonal, attack_swing_down,
--              attack_swing_left, attack_swing_right, attack_swing_right_diagonal
--   universal: attack_push, parry_pose, inspect_start
-- Source events already in this list (e.g. attack_push, attack_swing_down,
-- attack_swing_charge_left, attack_swing_left_diagonal, attack_swing_right,
-- attack_swing_right_diagonal) are NOT remapped — they play natively. Only
-- events missing from the closed list need entries below.
local _kruber_axe_falchion_remap = {
	-- ===== HEAVY CHAIN — chain-context rule =====
	-- The body's clip selection depends on chain STATE, not just event name.
	-- An event in the closed vocab can still produce no animation if the
	-- body's current chain state has no clip mapped for it. Native Kruber's
	-- mace+sword heavy chain from IDLE (per dual_wield_hammer_sword.lua):
	--   H1 from idle:   `action_one.default`             → charge_left  → heavy_left_diagonal
	--   H2 (chained):   `action_one.default_right_heavy` → charge_left  → heavy_right_diagonal
	-- The body's "from idle" state has clips for charge_left and
	-- heavy_left_diagonal. It does NOT have clips for charge_right or
	-- heavy_right_diagonal from idle — those reachable only after the chain
	-- has advanced. v0.1.158-v0.1.192 mapped H1 to charge_right +
	-- heavy_right_diagonal; result was the body stood still on H1 because
	-- those clips aren't reachable from idle.
	--
	-- Fix: H1 mirrors Kruber's idle-heavy chain (left-diagonal). H2 maps to
	-- Kruber's H2 chain (right-diagonal). Source's H2 charge is already
	-- attack_swing_charge_left and matches Kruber's H2 charge natively, so
	-- no charge remap is needed for H2.
	attack_swing_charge_down = "attack_swing_charge_left",          -- H1 charge
	attack_swing_heavy_down  = "attack_swing_heavy_left_diagonal",  -- H1 release (Kruber idle H1)
	attack_swing_heavy_left  = "attack_swing_heavy_right_diagonal", -- H2 release (Kruber chained H2)

	-- ===== LIGHT VARIANT =====
	-- Source down_left → left_diagonal. Lights chain from idle and
	-- left_diagonal is in the idle-light vocab; plays correctly.
	attack_swing_down_left   = "attack_swing_left_diagonal",

	-- ===== PUSH-ATTACK =====
	-- Source `light_attack_bopp` fires `attack_swing_down`. In target vocab
	-- but plays a right-hand mace chop. User wants a left-hand falchion
	-- swing — remap to attack_swing_left (Kruber's light_attack_left).
	-- "In vocab" is necessary but not sufficient; the clip must match intent.
	attack_swing_down        = "attack_swing_left",
}

-- Per (vanilla item key, career name) → event remap. Add new entries here as
-- new cross-access weapons are introduced. Career names must be exact (career
-- prefix matching could be added later if needed).
local _cross_access_action_remap = {
	wh_dual_wield_axe_falchion = {
		es_mercenary      = _kruber_axe_falchion_remap,
		es_huntsman       = _kruber_axe_falchion_remap,
		es_knight         = _kruber_axe_falchion_remap,
		es_questingknight = _kruber_axe_falchion_remap,
	},
	dr_dual_wield_axes = {
		es_mercenary      = _kruber_dual_axes_remap,
		es_huntsman       = _kruber_dual_axes_remap,
		es_knight         = _kruber_dual_axes_remap,
		es_questingknight = _kruber_dual_axes_remap,
	},
}

-- Track local player's wielded melee weapon key + career for cheap lookup
-- on every Unit.animation_event hit. Updated only on melee wield.
local _cross_access_local_weapon_key = nil
local _cross_access_local_career     = nil

mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
	if slot_name ~= "slot_melee" then return end
	local pm = Managers.player
	if not pm then return end
	local local_player = pm:local_player(1)
	if not local_player or local_player.player_unit ~= self.owner_unit then return end
	local slot_data = self:get_slot_data(slot_name)
	_cross_access_local_weapon_key = slot_data and slot_data.item_data and slot_data.item_data.key or nil
	local ok, career = pcall(local_player.career_name, local_player)
	_cross_access_local_career = ok and career or nil
end)

-- Resolve the local player's 3P body unit fresh each call (the unit can
-- change across respawns / level transitions).
local function _local_3p_body_unit()
	local pm = Managers.player
	if not pm then return nil end
	local p = pm:local_player(1)
	return p and p.player_unit or nil
end

-- The hook itself. Cheap early-exits keep the hot path fast — we only do real
-- work when (1) we have a tracked local weapon and career, (2) that combo has
-- a remap entry, (3) the event has a substitute, AND (4) the unit is the
-- local 3P body. Native wielders, husks, 1P unit, and unrelated weapons
-- all bypass via the early returns.
mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
	if not event_name then return func(unit, event_name, ...) end
	if not _cross_access_local_weapon_key or not _cross_access_local_career then
		return func(unit, event_name, ...)
	end
	local item_remaps = _cross_access_action_remap[_cross_access_local_weapon_key]
	if not item_remaps then return func(unit, event_name, ...) end
	local career_remaps = item_remaps[_cross_access_local_career]
	if not career_remaps then return func(unit, event_name, ...) end
	local target = career_remaps[event_name]
	if not target then return func(unit, event_name, ...) end
	if unit ~= _local_3p_body_unit() then return func(unit, event_name, ...) end
	return func(unit, target, ...)
end)

-- ============================================================
-- Imperial Longsword template (modified bastard_sword_template)
-- -15% damage, +15% speed, +15% cleave, -15% stagger
-- ============================================================

local _IL_DAMAGE_MULT  = 0.85
local _IL_SPEED_MULT   = 1.15
local _IL_CLEAVE_MULT  = 1.15
local _IL_STAGGER_MULT = 0.85

-- CLARIFY: Damage-profile clone. Each cwv template clone calls this once per
-- sub-action's damage_profile string; the function is idempotent (early-return
-- on existing clone) so the same source profile shared across multiple
-- sub-actions is cloned only once.
-- Prefix-collision risk: prefixes are tied to the specific multiplier set
-- ("cwv_il_" = imperial longsword, "cwv_ess_" = elven sword+shield). DO NOT
-- reuse a prefix with different `mults` — the second caller will reuse the
-- first caller's already-mutated PowerLevelTemplates entry and silently inherit
-- the wrong multipliers.
local function _clone_damage_profile(source_name, prefix, mults)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	if DamageProfileTemplates[new_name] then return new_name end

	local dmg_mult = mults.damage or 1
	local stg_mult = mults.stagger or 1
	local clv_mult = mults.cleave or 1

	local clone = table.clone(source, true)

	if type(clone.cleave_distribution) == "string" and PowerLevelTemplates then
		local key = clone.cleave_distribution
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.attack then c.attack = c.attack * clv_mult end
				if c.impact then c.impact = c.impact * clv_mult end
				PowerLevelTemplates[new_key] = c
			end
			clone.cleave_distribution = new_key
		end
	end

	if type(clone.default_target) == "string" and PowerLevelTemplates then
		local key = clone.default_target
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.default_target = new_key
		end
	end

	if type(clone.targets) == "string" and PowerLevelTemplates then
		local key = clone.targets
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				for _, target in ipairs(c) do
					if target.power_distribution then
						if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * dmg_mult end
						if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * stg_mult end
					end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.targets = new_key
		end
	end

	if type(clone.critical_strike) == "string" and PowerLevelTemplates then
		local key = clone.critical_strike
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.critical_strike = new_key
		end
	end

	DamageProfileTemplates[new_name] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, new_name)
		rawset(tbl, new_name, idx)
	end

	return new_name
end

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P animations
-- are universal (see top-of-file ANIMATION ARCHITECTURE) and need no work.
local function _create_imperial_longsword_template()
	if not Weapons or not Weapons.bastard_sword_template then
		mod:warning("bastard_sword_template not found — Imperial Longsword stat modifications unavailable")
		return
	end
	if Weapons.imperial_longsword_template then return end

	-- CLARIFY: table.clone(t, true) is recursive (deep clone) per
	-- foundation/scripts/util/table.lua — it walks every nested table value.
	-- skip_metatable=true is required because Weapon templates contain functions
	-- (anim_end_event_condition_func) which would otherwise trip the metatable
	-- assertion. Sub-tables (action_one.default.allowed_chain_actions, buff_data,
	-- weapon_sway_settings, etc.) are all freshly-allocated copies, so mutating
	-- this clone is safe for the original bastard_sword_template.
	local template = table.clone(Weapons.bastard_sword_template, true)

	-- CLARIFY: Two-level loop is sufficient. anim_time_scale and damage_profile
	-- live at the sub-action level (template.actions.action_one.default.*), not
	-- in deeper structures like allowed_chain_actions.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_", {
								damage = _IL_DAMAGE_MULT, stagger = _IL_STAGGER_MULT, cleave = _IL_CLEAVE_MULT,
							})
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_template = template
	mod:info("Created imperial_longsword_template (dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_template()

-- ============================================================
-- Imperial Longsword + Shield template (modified one_handed_sword_shield_template_2)
-- Same tune as the 2H Imperial Longsword (-15% damage, +15% speed, +15% cleave,
-- -15% stagger), but applied ONLY to sword-swing sub-actions. Shield bashes
-- (shield_slam*, shield_push), the block action, and the universal push
-- (medium_push) are left at vanilla so the shield half behaves like a normal
-- shield. Filter: skip sub_action if `kind == "block"` OR its damage_profile
-- starts with "shield_". The push baseline uses `damage_profile_inner` /
-- `damage_profile_outer` (no plain `damage_profile`), so it's naturally skipped.
--
-- Prefix `cwv_il_` is intentionally REUSED from the 2H Imperial Longsword: the
-- multipliers are identical, the damage_profile names don't overlap (bastard
-- sword uses 2H slashing profiles, bret sword+shield uses 1h slashing profiles),
-- and `_clone_damage_profile` is idempotent within a prefix.
local function _create_imperial_longsword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_2 then
		mod:warning("one_handed_sword_shield_template_2 not found — Imperial Longsword + Shield stat mods unavailable")
		return
	end
	if Weapons.imperial_longsword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_2, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						local is_shield_action = (sub_action.kind == "block")
							or (type(dp) == "string" and dp:sub(1, 7) == "shield_")
						if not is_shield_action then
							if sub_action.anim_time_scale then
								sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
							end
							if sub_action.damage_profile then
								sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_", {
									damage = _IL_DAMAGE_MULT, stagger = _IL_STAGGER_MULT, cleave = _IL_CLEAVE_MULT,
								})
							end
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_shield_template = template
	mod:info("Created imperial_longsword_shield_template (sword-only: dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_shield_template()

-- ============================================================
-- Elven Sword+Shield template (modified one_handed_sword_shield_template_1)
-- +15% speed, -15% stagger
--
-- ANIM ADDENDUM: _ess_anim_remap remaps 3P body events ONLY (anim_event_3p
-- field — see _create_elven_sword_shield_template body). The 1P side is
-- universal across characters and needs no remapping — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

local _ESS_SPEED_MULT   = 1.15
local _ESS_STAGGER_MULT = 0.85

-- 3P body event remap: keys are events the cloned template fires; values are
-- substitutes that exist on the empire-soldier 3P skeleton. 1P unaffected.
local _ess_anim_remap = {
	attack_swing_left_diagonal     = "attack_swing_left",
	attack_swing_charge            = "attack_swing_charge_stab",
	attack_swing_heavy             = "attack_push",
	attack_swing_heavy_right       = "attack_swing_heavy_down_right",
	attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
}

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P is universal.
local function _create_elven_sword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_1 then
		mod:warning("one_handed_sword_shield_template_1 not found — Elven Sword+Shield stat modifications unavailable")
		return
	end
	if Weapons.elven_sword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _ESS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_ess_", {
								stagger = _ESS_STAGGER_MULT,
							})
						end
						if sub_action.anim_event and _ess_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ess_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_1h_spear_shield"
	template.wield_anim_career_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}

	Weapons.elven_sword_shield_template = template

	-- CLARIFY: Per memory note feedback_cwv_previewer_template_lookup.md, the
	-- inventory previewer resolves item templates via item_data.name (= base
	-- weapon key for cwv items), so it reads one_handed_sword_shield_template_1
	-- NOT our elven_sword_shield_template. Patch the BASE template's
	-- wield_anim_career_3p so the menu preview pose is correct for elf careers.
	-- Scoped to elf careers only — Kruber/etc. fall through to original behavior.
	local elf_wield_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}
	local base = Weapons.one_handed_sword_shield_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(elf_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end
	-- QUESTION: Attack-event remaps from _ess_anim_remap are only applied to the
	-- cloned template. The previewer reads the BASE template (see comment above),
	-- so previewer attack animations would NOT pick up the remap. Currently this
	-- is fine because the previewer doesn't fire attack events — only the
	-- wield_anim. If that changes, the attack remaps must also be patched onto
	-- the base template (probably via career_anim_event tables).

	mod:info("Created elven_sword_shield_template (spd=%.0f%% stagger=%.0f%%, %d 3p anim remaps, wield_3p=to_1h_spear_shield) + patched base template career_3p table for elf careers",
		_ESS_SPEED_MULT * 100, _ESS_STAGGER_MULT * 100, 5)
end

_create_elven_sword_shield_template()

-- ============================================================
-- Imperial Dual Swords template (modified dual_wield_swords_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- 3P anim redirect to Kruber's dual_wield_hammer_sword_template.
--
-- ANIM ADDENDUM: All anim work below is 3P-only (anim_event_3p,
-- wield_anim_3p, wield_anim_career_3p). 1P is universal — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

local _IDS_SPEED_MULT = 0.80
local _IDS_POWER_MULT = 1.15

-- 3P body event remap: elf dual-sword events with no 1:1 on Kruber's
-- dual_wield_hammer_sword_template. Substitutes are picked from the empire-
-- soldier 3P skeleton's authored vocabulary so a valid clip plays. Same-named
-- events (attack_swing_left, attack_swing_right, attack_swing_left_diagonal,
-- etc.) need no remap — Kruber's mace+sword template uses those same names
-- and they're authored on the empire-soldier 3P skeleton. 1P unaffected.
--
-- Heavy combo release reversed on 3P: H1 release (source anim_event
-- attack_swing_heavy_left_diagonal) plays right-diagonal on the body;
-- H2 release (source attack_swing_heavy_right) plays left-diagonal. 1P keeps
-- the source events unchanged.
--
-- push_stab → attack_swing_right: a native dual_hammer_sword event (line
-- 1082 of dual_wield_hammer_sword.lua), a fast lateral swing with the lead
-- sword. Picked after the SM has no visible stab — investigation summary:
--
-- The dual_hammer_sword 3P sub-graph doesn't author a visible stab clip;
-- the empire-soldier skeleton's stab clips live in the 1h_sword_shield
-- sub-graph. Attempts to reach them failed:
--   1. attack_swing_stab as a plain anim_event_3p remap → force3p reports
--      exists=true but no visible clip plays (stub transition).
--   2. SM-switch graft (v0.1.89) via pre_action_anim_event =
--      "to_1h_sword_shield" + anim_end_event_3p = "to_dual_hammer_sword_es"
--      → the wield-change clip eats the damage window AND push_stab's
--      anim_end_event_condition_func returns false on action_complete
--      which gates ALL end events including our return transition — body
--      got stuck in 1h_sword_shield sub-graph permanently.
--   3. Full SM switch (change template's wield_anim_3p to to_1h_sword_shield)
--      → gives visible stab but breaks the dual-wield idle/wield identity
--      (left sword renders in shield-defensive stance). Reference pattern:
--      Peregrinaje's markus_torch_and_shield uses exactly this approach
--      with model aligned to the SM (torch fits axe+shield); not applicable
--      to two swords without a model rework.
-- Decision: stay native to dual_hammer_sword, use a non-stab clip that reads
-- as a committed forward strike. attack_swing_right reads as a quick
-- follow-up swing after the push.
local _ids_anim_remap = {
	-- Charge for H1 from idle — matches H1's swapped strike direction.
	-- Elf source `default` sub-action fires attack_swing_charge_diagonal; we
	-- route to charge_right (not charge_left) so the wind-up direction
	-- aligns with H1's release (heavy_right_diagonal). Cock right → strike
	-- right. Was incoherent (left cock, right strike) prior to v0.1.102.
	attack_swing_charge_diagonal     = "attack_swing_charge_right",
	-- Heavy combo release reversed.
	attack_swing_heavy_left_diagonal = "attack_swing_heavy_right_diagonal",
	attack_swing_heavy_right         = "attack_swing_heavy_left_diagonal",
	-- Push-attack — see comment block above.
	push_stab                        = "attack_swing_right",
}

-- ANIM ADDENDUM: this function touches stats + 3P fields. 1P is universal.
local function _create_imperial_dual_swords_template()
	if not Weapons or not Weapons.dual_wield_swords_template_1 then
		mod:warning("dual_wield_swords_template_1 not found — Imperial Dual Swords template unavailable")
		return
	end
	if Weapons.imperial_dual_swords_template then return end

	local template = table.clone(Weapons.dual_wield_swords_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IDS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_eds_", {
								damage = _IDS_POWER_MULT, stagger = _IDS_POWER_MULT,
							})
						end
						if sub_action.anim_event and _ids_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ids_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_dual_hammer_sword_es"
	template.wield_anim_career_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}

	Weapons.imperial_dual_swords_template = template

	-- Same patch pattern as _create_elven_sword_shield_template: the inventory
	-- previewer reads the BASE template (dual_wield_swords_template_1), not our
	-- clone, so patch the base template's wield_anim_career_3p for Kruber careers
	-- to keep the menu preview pose correct. Scoped to es_* only — elf careers
	-- fall through to the original wield anim.
	local kruber_wield_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}
	local base = Weapons.dual_wield_swords_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	mod:info("Created imperial_dual_swords_template (spd=%.0f%% power=%.0f%%, 3p anim redirect to mace+sword, wield_3p=to_dual_hammer_sword_es)",
		_IDS_SPEED_MULT * 100, _IDS_POWER_MULT * 100)
end

_create_imperial_dual_swords_template()

-- ============================================================
-- Cudgel template (one_hand_falchion_template_1 — recoloured to blunt)
-- ============================================================
-- Saltzpyre's falchion moveset (charge-and-release light combo, smiter
-- heavy) but every cutting hit becomes a crushing one. Cosmetic stays
-- the empire mace mesh — only the moveset, damage_type, and impact
-- effects/sounds change.
--
-- Damage profile swap: the falchion uses one of three slashing profile
-- families across its sweeps. Each maps to a vanilla blunt cousin with
-- the same cleave/range/stagger shape:
--
--   light_slashing_axe_linesman       → light_blunt_tank_diag    (light combo sweeps)
--   light_slashing_axe_linesman_upper → light_blunt_tank_upper   (light upper variants)
--   medium_slashing_smiter_1h         → medium_blunt_smiter_1h   (heavy attack)
--
-- All three blunt targets are vanilla DamageProfileTemplates entries
-- (see damage_profile_templates.lua:253+ / 430+). Push profiles
-- (medium_push / light_push) are universal and stay untouched.
--
-- Effects/sounds: hit_effect → melee_hit_hammers_1h, slashing_hit
-- swoosh/impact → blunt_hit (and _armour). display_unit and block-arc
-- sound also swapped so the inventory rig and parry foley match a
-- mace, not a falchion.
local _CUDGEL_DAMAGE_PROFILE_SWAP = {
	light_slashing_axe_linesman       = "light_blunt_tank_diag",
	light_slashing_axe_linesman_upper = "light_blunt_tank_upper",
	medium_slashing_smiter_1h         = "medium_blunt_smiter_1h",
}

local _CUDGEL_HIT_EFFECT_SWAP = {
	melee_hit_axes_1h  = "melee_hit_hammers_1h",
	melee_hit_sword_1h = "melee_hit_hammers_1h",
}

local _CUDGEL_IMPACT_SOUND_SWAP = {
	slashing_hit         = "blunt_hit",
	slashing_hit_armour  = "blunt_hit_armour",
}

local function _create_cudgel_template()
	if not Weapons or not Weapons.one_hand_falchion_template_1 then
		mod:warning("one_hand_falchion_template_1 not found — Cudgel template unavailable")
		return
	end
	if Weapons.cudgel_template then return end

	local template = table.clone(Weapons.one_hand_falchion_template_1, true)

	local swapped, hit_swapped, sound_swapped = 0, 0, 0
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						if dp and _CUDGEL_DAMAGE_PROFILE_SWAP[dp] then
							sub_action.damage_profile = _CUDGEL_DAMAGE_PROFILE_SWAP[dp]
							swapped = swapped + 1
						end
						local hit = sub_action.hit_effect
						if hit and _CUDGEL_HIT_EFFECT_SWAP[hit] then
							sub_action.hit_effect = _CUDGEL_HIT_EFFECT_SWAP[hit]
							hit_swapped = hit_swapped + 1
						end
						local imp = sub_action.impact_sound_event
						if imp and _CUDGEL_IMPACT_SOUND_SWAP[imp] then
							sub_action.impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[imp]
							sound_swapped = sound_swapped + 1
						end
						local nd = sub_action.no_damage_impact_sound_event
						if nd and _CUDGEL_IMPACT_SOUND_SWAP[nd] then
							sub_action.no_damage_impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[nd]
						end
					end
				end
			end
		end
	end

	-- Inventory / preview shows on a hammer display rig (mace mesh sits in
	-- the hammer cradle), not the falchion's. Block-arc swoosh swapped
	-- to the wood-block blunt foley used by 1h hammers.
	template.display_unit = "units/weapons/weapon_display/display_1h_hammer"
	template.sound_event_block_within_arc = "weapon_foley_blunt_1h_block_wood"

	Weapons.cudgel_template = template
	mod:info("Created cudgel_template (one_hand_falchion_template_1 → blunt: %d damage profiles, %d hit effects, %d impact sounds swapped)",
		swapped, hit_swapped, sound_swapped)
end

_create_cudgel_template()

-- ============================================================
-- Sword and Mace template — INVERSE of dual_wield_hammer_sword
-- Native Kruber mace+sword has: mace in RIGHT hand, sword in LEFT hand.
-- Inverse:                       sword in RIGHT hand, mace in LEFT hand.
--
-- The variant def sets right_hand_unit = sword, left_hand_unit = mace.
-- Sub-actions in the cloned template have weapon_action_hand = "right" /
-- "left" / "both" — we walk them and swap damage profile / hit effect /
-- impact sound fields so that:
--   * Right-hand strikes (was mace=blunt) now play sword/slashing
--   * Left-hand strikes  (was sword=slashing) now play mace/blunt
--   * Both-hand strikes:  swap damage_profile_left ↔ damage_profile_right
--                         where they differ (so each hand's damage type
--                         follows whichever weapon is in that hand now).
--
-- Per-hand `range_mod` override (v0.1.163): the dual-wield baseline is
-- shorter than the 1h equivalents (1.1 / 1.15 vs the 1h templates' 1.2),
-- but the user wants each weapon to feel like its 1h source. Override
-- per-hand sweeps to match `es_1h_sword` / `es_1h_mace` light-attack reach.
-- See `_SAM_HAND_RANGE_MOD` below for the values and rationale.
--
-- ANIM ADDENDUM: the underlying anim events / state machine are unchanged —
-- the body still goes through `to_dual_hammer_sword_es` and plays the same
-- dual-wield clips. Only damage / sound / hit-effect / range data per-action swaps.
-- ============================================================

-- Right-hand strike fields (was mace=blunt → sword=slashing).
local _SAM_RIGHT_HAND_SWAP = {
	damage_profile = {
		light_blunt_tank_diag = "light_slashing_linesman",
	},
	hit_effect = {
		melee_hit_hammers_1h = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		blunt_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		blunt_hit_armour = "slashing_hit_armour",
	},
}

-- Left-hand strike fields (was sword=slashing → mace=blunt).
local _SAM_LEFT_HAND_SWAP = {
	damage_profile = {
		light_slashing_linesman = "light_blunt_tank_diag",
	},
	hit_effect = {
		melee_hit_sword_1h = "melee_hit_hammers_1h",
	},
	impact_sound_event = {
		slashing_hit = "blunt_hit",
	},
	no_damage_impact_sound_event = {
		slashing_hit_armour = "blunt_hit_armour",
	},
}

-- Per-hand `range_mod` override. range_mod is per-sub-action (each sweep has its
-- own value), so the reach overhaul is per-hit, not template-level.
--
-- Vanilla `dual_wield_hammer_sword` is a close-quarters dual-wield: right-hand
-- mace sweeps run at 1.15 and left-hand sword sweeps at 1.1 — shorter than the
-- 1h variants because both arms are committed and the wielder reads "tighter
-- box". Our variant flips the hands but the user wants each weapon's reach to
-- match its single-hand source instead of the tighter dual-wield baseline:
--
--   right hand (sword in our variant) → 1h_swords light_attack reach (1.2)
--   left hand  (mace  in our variant) → 1h_hammers light_attack reach (1.2)
--
-- Both numerically land at 1.2 because that's what each 1h template uses for
-- its light attacks (the heavies in 1h_swords go up to 1.25 and in 1h_hammers
-- to 1.3, but every per-hand sweep in dual_wield_hammer_sword is a LIGHT
-- attack — the heavies are `weapon_action_hand = "both"`, left untouched here
-- since they involve both weapons swung together).
--
-- "both"-hand sweeps, push, and block don't have a sword/mace assignment, so
-- they're absent from this map and keep the vanilla dual-wield range.
local _SAM_HAND_RANGE_MOD = {
	right = 1.2,  -- matches es_1h_sword light_attack range_mod (1h_swords.lua light_attack actions)
	left  = 1.2,  -- matches es_1h_mace  light_attack range_mod (1h_hammers.lua light_attack actions)
}

local function _sam_apply_field_swaps(sub_action, swaps)
	for field, swap_map in pairs(swaps) do
		local current = sub_action[field]
		if current and swap_map[current] then
			sub_action[field] = swap_map[current]
		end
	end
end

local function _create_sword_and_mace_template()
	if not Weapons or not Weapons.dual_wield_hammer_sword_template then
		mod:warning("dual_wield_hammer_sword_template not found — Sword and Mace template unavailable")
		return
	end
	if Weapons.sword_and_mace_template then return end

	local template = table.clone(Weapons.dual_wield_hammer_sword_template, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local hand = sub_action.weapon_action_hand
						if hand == "right" then
							_sam_apply_field_swaps(sub_action, _SAM_RIGHT_HAND_SWAP)
						elseif hand == "left" then
							_sam_apply_field_swaps(sub_action, _SAM_LEFT_HAND_SWAP)
						elseif hand == "both" then
							-- For dual-hand strikes, swap left/right damage profile
							-- references where they differ (so left=mace and
							-- right=sword damage types follow the new hand
							-- placement).
							local pl = sub_action.damage_profile_left
							local pr = sub_action.damage_profile_right
							if pl and pr and pl ~= pr then
								sub_action.damage_profile_left  = pr
								sub_action.damage_profile_right = pl
							end
						end
						-- Per-hand reach override (independent of damage/sound swaps).
						-- Only sweeps have range_mod authored; we guard on its presence
						-- so non-sweep sub-actions (push, block_break, etc.) don't get
						-- a range_mod field accidentally introduced.
						if sub_action.range_mod and _SAM_HAND_RANGE_MOD[hand] then
							sub_action.range_mod = _SAM_HAND_RANGE_MOD[hand]
						end
					end
				end
			end
		end
	end

	Weapons.sword_and_mace_template = template
	mod:info("Created sword_and_mace_template (inverse of dual_wield_hammer_sword: damage/sound/effect swap by hand; per-hand range_mod = right %.2f / left %.2f)",
		_SAM_HAND_RANGE_MOD.right, _SAM_HAND_RANGE_MOD.left)
end

_create_sword_and_mace_template()

-- ============================================================
-- Shortsword template (modified one_handed_daggers_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- Fire DoT removed: burning damage profiles swapped to non-burning slashing
-- analogs. Slam-specific aoe/target damage profile fields are nilled out
-- because no non-burning slam analog exists for Sienna's body — the heavy
-- slam loses its AoE component but the visual + main-target damage remain.
--
-- ANIM ADDENDUM: native template applies on Sienna's bright_wizard body — no
-- anim work needed. 1P universal across characters.
-- ============================================================

local _SHORTSWORD_SPEED_MULT = 0.92
local _SHORTSWORD_POWER_MULT = 1.15

-- Burning damage profiles → non-burning analogs. `false` means "remove the
-- field entirely" (used for AoE/target slam fields with no clean non-burning
-- analog — see header for the AoE-loss caveat).
-- v0.1.151 used `medium_slashing_linesman_fencer` as the slam swap — that
-- name DOES NOT exist in DamageProfileTemplates. NetworkLookup.damage_profiles
-- is a strict-lookup table that crashes on missing keys, so heavy_attack_left
-- fire crashed the game. Fixed v0.1.152: use `medium_slashing_linesman`
-- (real, heavy slashing — closest non-burning analog by damage shape).
local _SHORTSWORD_DAMAGE_PROFILE_SWAP = {
	dagger_burning_slam_fencer        = "medium_slashing_linesman",
	dagger_burning_slam_fencer_aoe    = false,
	dagger_burning_slam_target_fencer = false,
	medium_burning_smiter_stab_H      = "medium_slashing_smiter_stab",
}

-- Fire-themed FX/sound fields → sword-themed analogs. The dagger's burning
-- heavies hardcode hit_effect = "staff_spark" + fire_hit sounds at the
-- sub-action level. v0.1.155 left these untouched and the engine crashed
-- when `World.create_particles("fx/wpnfx_staff_spark_impact")` fired during
-- a sweep on Kruber's body — the staff_spark FX package isn't loaded for
-- empire-soldier wielders. Fixed v0.1.156 by swapping these fields too so
-- the shortsword reads as steel-on-target (no fire visuals or sounds).
local _SHORTSWORD_FX_SWAP = {
	hit_effect = {
		staff_spark = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	armor_impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		fire_hit_armour = "slashing_hit_armour",
	},
}

local function _create_shortsword_template()
	if not Weapons or not Weapons.one_handed_daggers_template_1 then
		mod:warning("one_handed_daggers_template_1 not found — Shortsword template unavailable")
		return
	end
	if Weapons.shortsword_template then return end

	local template = table.clone(Weapons.one_handed_daggers_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _SHORTSWORD_SPEED_MULT
						end
						-- Step 1: swap burning damage profiles to non-burning
						-- analogs (or remove for AoE/target slam fields).
						-- Order matters — must run BEFORE _clone_damage_profile
						-- so the power scaling clones the swapped profile.
						local swap_fields = { "damage_profile", "damage_profile_aoe", "damage_profile_target" }
						for _, field in ipairs(swap_fields) do
							local profile = sub_action[field]
							if profile and _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile] ~= nil then
								local replacement = _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile]
								sub_action[field] = replacement or nil
							end
						end
						-- Step 2: scale power on the (possibly swapped) damage_profile.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_shortsword_", {
								damage = _SHORTSWORD_POWER_MULT, stagger = _SHORTSWORD_POWER_MULT,
							})
						end
						-- Step 3: swap fire-themed FX / sounds → sword-themed
						-- analogs. Without this, sub-actions that previously
						-- referenced burning damage profiles still ran their
						-- staff_spark hit_effect — and the staff_spark FX
						-- package isn't loaded for empire-soldier wielders, so
						-- World.create_particles crashed mid-sweep (v0.1.155
						-- regression — fixed v0.1.156).
						for field, swap_map in pairs(_SHORTSWORD_FX_SWAP) do
							local current = sub_action[field]
							if current and swap_map[current] then
								sub_action[field] = swap_map[current]
							end
						end
					end
				end
			end
		end
	end

	Weapons.shortsword_template = template
	mod:info("Created shortsword_template (spd=%.0f%% power=%.0f%%, fire DoT removed)",
		_SHORTSWORD_SPEED_MULT * 100, _SHORTSWORD_POWER_MULT * 100)
end

_create_shortsword_template()

-- ============================================================
-- Maul template (modified one_handed_hammer_wizard_template_1)
-- Sienna's Morningstar moveset cloned for Kruber. H1 heavy attack's
-- damage_profile (medium_blunt_smiter_heavy) is swapped to a non-burn
-- analog (medium_blunt_smiter_2h_hammer) — wizard fire is in the
-- damage-profile resolution chain, not the FX/sound fields.
--
-- 3P wield routes to Kruber's greathammer SM (to_2h_hammer); per-action
-- 3P remap covers wizard-mace events not authored on
-- two_handed_hammers_template_1's vocabulary.
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

-- Single-entry burn swap. Verified that medium_blunt_smiter_heavy is the
-- ONLY profile in the wizard mace template that resolves to a _burn_*
-- PowerLevelTemplates entry. Other damage profiles (light_blunt_tank,
-- light_blunt_smiter, medium_blunt_tank_upper_1h, medium_push, light_push)
-- are clean. FX/sound fields already non-fire (melee_hit_hammers_1h /
-- blunt_hit / blunt_hit_armour) — no FX swap pass needed.
local _MAUL_DAMAGE_PROFILE_SWAP = {
	medium_blunt_smiter_heavy = "medium_blunt_smiter_2h_hammer",
}

-- 3P remap — source events (one_handed_hammer_wizard_template_1) →
-- target events (two_handed_hammers_template_1, Kruber greathammer SM).
-- Closed-vocabulary rule: every value MUST appear in the greathammer
-- template's anim_event set. Verified against
-- weapon_templates/2h_hammers.lua: charge / charge_right / charge_left /
-- heavy_right / heavy / down_left / left / left_diagonal / down_right /
-- push / parry_pose. Source events already in target (left_diagonal,
-- left, push, parry_pose) need no entry.
local _MAUL_ANIM_REMAP_3P = {
	-- charges: source has _diagonal / _pose suffixes; target has none.
	attack_swing_charge_left_diagonal = "attack_swing_charge_left",
	attack_swing_charge_left_pose     = "attack_swing_charge_left",
	attack_swing_charge_right_pose    = "attack_swing_charge_right",
	-- heavies: source overhead / sided "_up" variants; target has plain
	-- heavy + heavy_right (no heavy_left).
	attack_swing_heavy_down           = "attack_swing_heavy",
	attack_swing_heavy_right_up       = "attack_swing_heavy_right",
	attack_swing_heavy_left_up        = "attack_swing_heavy",
	-- lights: source right_diagonal / down / left_diagonal_last need
	-- closest-in-vocab strikes.
	attack_swing_right_diagonal       = "attack_swing_down_right",
	attack_swing_down                 = "attack_swing_down_right",
	attack_swing_left_diagonal_last   = "attack_swing_left_diagonal",
}

local _maul_kruber_wield_3p = {
	es_mercenary      = "to_2h_hammer",
	es_huntsman       = "to_2h_hammer",
	es_knight         = "to_2h_hammer",
	es_questingknight = "to_2h_hammer",
}

local function _create_maul_template()
	if not Weapons or not Weapons.one_handed_hammer_wizard_template_1 then
		mod:warning("one_handed_hammer_wizard_template_1 not found — Maul template unavailable")
		return
	end
	if Weapons.maul_template then return end

	local template = table.clone(Weapons.one_handed_hammer_wizard_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						-- Step 1: scrub fire by swapping the burn-bearing
						-- damage_profile to a non-burn analog. Single-entry
						-- map; nothing else in this template fires.
						local profile = sub_action.damage_profile
						if profile and _MAUL_DAMAGE_PROFILE_SWAP[profile] then
							sub_action.damage_profile = _MAUL_DAMAGE_PROFILE_SWAP[profile]
						end
						-- Step 2: 3P body event remap (3P only —
						-- never write anim_event / 1P fields).
						if sub_action.anim_event and _MAUL_ANIM_REMAP_3P[sub_action.anim_event] then
							sub_action.anim_event_3p = _MAUL_ANIM_REMAP_3P[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_2h_hammer"
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for k, v in pairs(_maul_kruber_wield_3p) do
		template.wield_anim_career_3p[k] = v
	end

	-- Override attachment_node_linking from the source template's
	-- `AttachmentNodeLinking.brw_hammer` to the generic two-handed linking.
	-- The wizard linking specifies `unwielded.source = "a_unwielded_brw_mace"`
	-- — a bone authored ONLY on Sienna's 3P body skeleton. When Kruber
	-- (who lacks that bone) unequips the maul, the engine's `Unit.node()`
	-- lookup fails and crashes (`[Script Error]: a_unwielded_brw_mace`,
	-- crash GUID 37ead770-8f34-4821-b71d-2de354929a80, v0.1.167). The
	-- visual silhouette is two-handed (the variant scales the mesh up to
	-- 1.4×1.4×2.0), so two_handed_melee_weapon linking — `a_unwielded_2h`
	-- for unwielded, which Kruber has — is the right choice both visually
	-- and skeletally. Wielded source is `j_rightweaponattach` either way.
	if AttachmentNodeLinking and AttachmentNodeLinking.two_handed_melee_weapon then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.two_handed_melee_weapon
	end

	Weapons.maul_template = template

	-- Patch the BASE template's wield_anim_career_3p so the inventory
	-- previewer (HeroPreviewer reads BASE template, not our clone — see
	-- feedback_cwv_previewer_template_lookup.md) shows the right wield
	-- pose for Kruber careers. Scoped to es_* only — Sienna careers fall
	-- through to original behavior.
	local base = Weapons.one_handed_hammer_wizard_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(_maul_kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	-- Patch the BASE template's right_hand_attachment_node_linking too.
	-- Reason: the inventory previewer reads BASE template attachments,
	-- not our clone (per `feedback_cwv_previewer_template_lookup.md`).
	-- Without this, opening the inventory on a Kruber career carrying
	-- the Maul triggers `[Script Error]: a_unwielded_brw_mace` on the
	-- preview body. Crash GUID `258c5f1c-dbe0-4ebd-8ef6-0b43d95c3b9d`,
	-- v0.1.187. Replace ONLY the `third_person.unwielded` binding —
	-- `wielded` uses the universal `j_rightweaponattach` (all bodies
	-- have it), so leaving it alone preserves Sienna's native
	-- in-hand behavior. Cost: Sienna's holstered-mace pose now sits on
	-- standard hips instead of her dedicated mace-bone — small visual
	-- regression for her, fixes Kruber crash. AttachmentNodeLinking.brw_hammer
	-- is referenced by ONLY this one weapon template (verified via
	-- source-wide grep), so the patch is well-scoped.
	if base and base.right_hand_attachment_node_linking
			and base.right_hand_attachment_node_linking.third_person then
		base.right_hand_attachment_node_linking.third_person.unwielded = {
			{ source = "j_hips", target = 0 },
		}
	end

	mod:info("Created maul_template (burn scrub: %d profile swap, 3p anim remap: %d entries, wield_3p=to_2h_hammer)",
		1, 9)
end

_create_maul_template()

-- ============================================================
-- Poleaxe template (modified two_handed_axes_template_1)
-- Bardin's Greataxe moveset cloned for Kruber. Source template already
-- wields to to_2h_hammer (Kruber's greathammer SM is native), so no
-- wield_anim_3p patch needed. Per-action 3P remap covers a few
-- greataxe events (heavy_*_diagonal, attack_swing_up) not in
-- two_handed_hammers_template_1's vocabulary.
--
-- Stats (v0.1.171): speed × 1.2 (faster than the greataxe baseline —
-- poleaxe is a lighter polearm than a 2H greataxe), power × 0.85 (less
-- damage and stagger than a full greataxe). Per user.
--
-- No fire damage in the source (verified — all damage profiles use
-- _slashing_axe_linesman / _slashing_smiter_2h shapes, no _burn_).
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

local _POLEAXE_SPEED_MULT = 1.20
local _POLEAXE_POWER_MULT = 0.85

-- 3P remap — source (two_handed_axes_template_1) → target
-- (two_handed_hammers_template_1). Source events already in target
-- vocab (charge, charge_right, down_left, down_right, left, push,
-- parry_pose) need no entry.
local _POLEAXE_ANIM_REMAP_3P = {
	-- Heavy releases: source has _diagonal suffix; target has heavy_right
	-- and plain heavy (no heavy_left). Pick closest-direction substitute.
	attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
	attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
	-- Light: source attack_swing_up (overhead) → target's heavy is the
	-- closest overhead-feel clip (greathammer template authors no _up
	-- light variant).
	attack_swing_up                   = "attack_swing_heavy",
}

local function _create_poleaxe_template()
	if not Weapons or not Weapons.two_handed_axes_template_1 then
		mod:warning("two_handed_axes_template_1 not found — Poleaxe template unavailable")
		return
	end
	if Weapons.poleaxe_template then return end

	local template = table.clone(Weapons.two_handed_axes_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _POLEAXE_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_poleaxe_", {
								damage = _POLEAXE_POWER_MULT, stagger = _POLEAXE_POWER_MULT,
							})
						end
						if sub_action.anim_event and _POLEAXE_ANIM_REMAP_3P[sub_action.anim_event] then
							sub_action.anim_event_3p = _POLEAXE_ANIM_REMAP_3P[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	-- No wield_anim_3p change — source already wields to to_2h_hammer.
	-- No base-template patch — same reason; previewer's wield read of the
	-- base resolves to the same SM Kruber's body uses natively.

	Weapons.poleaxe_template = template

	mod:info("Created poleaxe_template (spd=%.0f%% power=%.0f%%, 3p anim remap: %d entries, native wield to_2h_hammer)",
		_POLEAXE_SPEED_MULT * 100, _POLEAXE_POWER_MULT * 100, 3)
end

_create_poleaxe_template()

-- ============================================================
-- Outrider Grenade Launcher template (modified dr_deus_01_template_1)
-- Behavior comes from Bardin Engineer's Trollhammer Torpedo
-- (`dr_deus_01_template_1`); visual layer is swapped to Kruber's
-- blunderbuss (state machine, wield anims, display unit, attachment
-- node linking). The trollhammer's action_one fires `attack_shoot`,
-- which is also a blunderbuss-state-machine event — so no per-action
-- anim_event remap is needed. 3P body anims work because Kruber's
-- empire-soldier skeleton has `attack_shoot` authored for his vanilla
-- blunderbuss.
--
-- Tunes vs vanilla trollhammer (per user, v0.1.176):
--   * speed × 1.4   (2500 → 3500 — faster projectile, "travels further")
--   * reload × 0.65 (3.0s → ~1.95s — faster reload than trollhammer)
--   * damage × 0.65 (proportionally smaller damage and stagger via
--                    cloned damage profile)
--   * max_range 20 → 30 (longer aim-assist reach)
--
-- Hand swap: trollhammer mounts the gun on the LEFT hand
-- (`weapon_action_hand = "left"`, `ammo_data.ammo_hand = "left"`,
-- `left_hand_unit = "...wpn_dr_deus_01"`). Blunderbuss is right-hand.
-- All `weapon_action_hand` and `ammo_hand` fields swapped to "right";
-- left_hand_unit cleared, right_hand_attachment set to
-- `AttachmentNodeLinking.rifles` (matches vanilla blunderbuss).
--
-- WIP / TODO:
--   * Explosion radius — `ExplosionTemplates.dr_deus_01` isn't in the
--     decompiled source we work from, so the explosion template is
--     used as-is. Smaller-radius tune is a follow-up.
--   * Projectile model — currently the trollhammer torpedo. User
--     mentioned wanting a grenade-shaped projectile; that's a follow-up
--     once `Projectiles.cwv_outrider_grenade` is set up.
-- ============================================================

local _OUTRIDER_PROJECTILE_SPEED = 3500
local _OUTRIDER_RELOAD_MULT      = 0.75   -- 0.75× trollhammer reload = ~25% faster reload
local _OUTRIDER_DAMAGE_MULT      = 0.65
local _OUTRIDER_MAX_RANGE        = 30
local _OUTRIDER_MAX_AMMO         = 10     -- v0.1.260: bumped from inherited 7 (trollhammer base)

local function _create_outrider_grenade_launcher_template()
	if not Weapons or not Weapons.dr_deus_01_template_1 then
		mod:warning("dr_deus_01_template_1 not found — Outrider Grenade Launcher template unavailable (Outcast Engineer DLC required)")
		return
	end
	if Weapons.outrider_grenade_launcher_template then return end

	local template = table.clone(Weapons.dr_deus_01_template_1, true)

	-- Swap visual layer: blunderbuss state machine + anims + display unit.
	-- 1P state machine and anim assets live on the shared first_person_base
	-- unit, so loading the blunderbuss state machine works on any character.
	template.state_machine          = "units/beings/player/first_person_base/state_machines/ranged/blunderbuss"
	template.wield_anim             = "to_blunderbuss"
	template.wield_anim_no_ammo     = "to_blunderbuss_noammo"
	template.wield_anim_not_loaded  = nil   -- blunderbuss has no "not_loaded" wield variant
	template.display_unit           = "units/weapons/weapon_display/display_blunderbusses"
	template.reload_event           = "reload"   -- vanilla blunderbuss event name (kept for clarity)

	-- Hand swap: weapon mounts on the right hand instead of left.
	template.left_hand_unit                    = ""
	template.left_hand_attachment_node_linking = nil
	if AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	-- ammo_data: swap ammo_hand to right (it's set to "left" on the trollhammer
	-- because the gun is held in the left hand there). Also bump max_ammo
	-- from inherited 7 (trollhammer base) to _OUTRIDER_MAX_AMMO per user.
	if template.ammo_data then
		template.ammo_data.ammo_hand   = "right"
		template.ammo_data.reload_time = (template.ammo_data.reload_time or 3) * _OUTRIDER_RELOAD_MULT
		template.ammo_data.max_ammo    = _OUTRIDER_MAX_AMMO
	end

	-- attack_meta_data.max_range: bump for "travels further" reach.
	if template.attack_meta_data then
		template.attack_meta_data.max_range = _OUTRIDER_MAX_RANGE
	end

	-- wwise_dep_left_hand: rename to right_hand since the gun lives on the
	-- right now. The wwise dependency package is loaded based on the
	-- weapon's hand mount, so this matters for sound bank loading.
	template.wwise_dep_right_hand = template.wwise_dep_left_hand
	template.wwise_dep_left_hand  = nil

	-- Projectile-visual swap: replace the trollhammer torpedo mesh with
	-- the hand grenade mesh, keeping all other trollhammer projectile
	-- physics intact (gravity, life_time, impact_type, trajectory).
	-- `Projectiles.dr_deus_01` is the trollhammer's projectile config;
	-- `ProjectileUnits.grenade` is the hand grenade visual
	-- (`wpn_emp_grenade_01_t1_3p`). Build our own Projectiles entry
	-- by cloning and swapping just `projectile_units_template`.
	-- The cloned config is referenced from each shoot sub-action below.
	if Projectiles and Projectiles.dr_deus_01
			and not Projectiles.cwv_outrider_grenade_projectile then
		local p = table.clone(Projectiles.dr_deus_01, true)
		p.projectile_units_template = "grenade"
		Projectiles.cwv_outrider_grenade_projectile = p
	end

	-- Per-action tunes: walk action_one and the reload/wield variants.
	-- Specifically: action_one.default is the shoot action (kind = grenade_thrower).
	if template.actions and template.actions.action_one then
		for _, sub_action in pairs(template.actions.action_one) do
			if type(sub_action) == "table" then
				-- Hand swap: every weapon_action_hand = "left" → "right".
				if sub_action.weapon_action_hand == "left" then
					sub_action.weapon_action_hand = "right"
				end
				-- Speed tune: bump projectile speed.
				if sub_action.speed then
					sub_action.speed = _OUTRIDER_PROJECTILE_SPEED
				end
				-- Damage tune: clone damage profile in impact_data with reduced
				-- damage and stagger multipliers.
				if sub_action.impact_data and sub_action.impact_data.damage_profile then
					sub_action.impact_data.damage_profile = _clone_damage_profile(
						sub_action.impact_data.damage_profile,
						"cwv_outrider_grenade_launcher_",
						{ damage = _OUTRIDER_DAMAGE_MULT, stagger = _OUTRIDER_DAMAGE_MULT })
				end
				-- Projectile visual swap: point at our cloned config.
				-- Only swap if vanilla had this sub-action pointed at the
				-- trollhammer projectile config (defensive — other sub-actions
				-- in this group might use different projectiles).
				if sub_action.projectile_info == Projectiles.dr_deus_01
						and Projectiles.cwv_outrider_grenade_projectile then
					sub_action.projectile_info = Projectiles.cwv_outrider_grenade_projectile
				end
			end
		end
	end

	-- default_loaded_projectile_settings reads `action.speed` at template-load
	-- time. Since we just bumped action.speed above, sync the cached value.
	if template.default_loaded_projectile_settings then
		template.default_loaded_projectile_settings.speed = _OUTRIDER_PROJECTILE_SPEED
	end

	-- weapon_type identifier — used by some sibling-mod hooks for filtering.
	template.weapon_type = "cwv_es_outrider_grenade_launcher"

	-- Right-click bash (replaces trollhammer's left-handed push). Without
	-- this, right-click crashes on the cwv variant because the trollhammer's
	-- action_one.push has `weapon_action_hand = "left"` (Bardin holds the
	-- gun in his left hand, so push is naturally left-handed) — and our
	-- variant has `no_left_hand = true`, so there's no left-hand wielded
	-- unit to back the push. Crash:
	-- `player_character_state_helper.lua: tried to start a left hand
	-- weapon action without a left hand wielded unit` (GUID 33e82f2c).
	--
	-- Per user, the bash should feel like the blunderbuss's. Copy the
	-- blunderbuss's `action_two.default` directly — kind = "shield_slam",
	-- damage_profile = "shield_slam_shotgun", anim_event = "attack_push".
	-- This is right-handed (no `weapon_action_hand` field set on
	-- blunderbuss bash), so it works with our right-mounted gun.
	if Weapons.blunderbuss_template_1 and Weapons.blunderbuss_template_1.actions
			and Weapons.blunderbuss_template_1.actions.action_two then
		template.actions.action_two = table.clone(Weapons.blunderbuss_template_1.actions.action_two, true)
	end

	-- Inspect / wield action templates: trollhammer uses the LEFT-handed
	-- variants (`ActionTemplates.action_inspect_left`, `wield_left`)
	-- because its weapon mount is left-handed. Swap to right-handed to
	-- match our right-mounted blunderbuss model.
	if ActionTemplates and ActionTemplates.action_inspect then
		template.actions.action_inspect = ActionTemplates.action_inspect
	end
	if ActionTemplates and ActionTemplates.wield then
		template.actions.action_wield = ActionTemplates.wield
	end

	-- Drop the trollhammer's chained push (`action_one.push`) — it had
	-- `weapon_action_hand = "left"` and `kind = "push_stagger"`. Even
	-- though the iterator above flipped the hand to "right", the action's
	-- chain entry references action_two now, and we'd rather have the
	-- bash be the user-facing right-click than a chained push.
	if template.actions.action_one then
		template.actions.action_one.push = nil
	end

	Weapons.outrider_grenade_launcher_template = template

	-- Patch BASE template (`dr_deus_01_template_1`) too. The inventory
	-- previewer (`world_hero_previewer.lua` `equip_item`) calls
	-- `ItemHelper.get_template_by_item_name(item_name)` where item_name is
	-- the BASE weapon's name (cwv variants inherit `entry.name` from the
	-- clone — see `feedback_cwv_clone_name_clobber.md`), so the previewer
	-- reads the BASE template, NOT our clone (per
	-- `feedback_cwv_previewer_template_lookup.md`).
	--
	-- Vanilla `dr_deus_01_template_1` has only `left_hand_attachment_node_linking`
	-- set (Bardin's trollhammer is a left-hand-mount weapon — his
	-- `right_hand_unit` is nil natively, so the previewer's
	-- `if right_hand_unit then` branch never fires for him). For our
	-- cwv variant on Kruber, `entry.right_hand_unit` IS set (the blunderbuss
	-- model), so the previewer hits that branch and reads
	-- `item_template.right_hand_attachment_node_linking.third_person` →
	-- crashes if the BASE template doesn't have right_hand_attachment_node_linking
	-- (crash GUID c847908d-c1e0-46be-8d15-c45c2a80e8a0, v0.1.179).
	--
	-- Fix: add `right_hand_attachment_node_linking = AttachmentNodeLinking.rifles`
	-- to the BASE template. Bardin still doesn't reach the right-hand path
	-- (his right_hand_unit stays nil) so this is harmless for vanilla
	-- trollhammer; our cwv variant does reach the path and now has a valid
	-- linking.
	if Weapons.dr_deus_01_template_1 and AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		Weapons.dr_deus_01_template_1.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	mod:info("Created outrider_grenade_launcher_template (blunderbuss visuals + trollhammer behavior, speed=%d, reload×%.2f, damage×%.2f, max_range=%d)",
		_OUTRIDER_PROJECTILE_SPEED, _OUTRIDER_RELOAD_MULT, _OUTRIDER_DAMAGE_MULT, _OUTRIDER_MAX_RANGE)
end

_create_outrider_grenade_launcher_template()

-- ============================================================
-- Musket template (modified handgun_template_1)
-- ============================================================
-- Kruber's vanilla rifle moveset, with stats tuned for an "imperial
-- long musket": slower reload, heavier per-shot damage, smaller ammo
-- pool, much louder report. Visual is the rifle stretched 1.35x along
-- Y (handled at type level — see `_type_transforms.cwv_es_musket`).
--
--   damage profile: clone of `shot_sniper` with default_target's
--                   power_distribution_{near,far}.attack and .impact
--                   both 2x. Dropoff curve preserved (matches the
--                   user-confirmed v1 spec — handgun-near damage at
--                   close, ~80% at far).
--   reload time:    2x (1.5s → 3.0s) on `ammo_data.reload_time`,
--                   plus 2x on per-action `total_time_secondary`
--                   (the secondary timing the reload anim runs against).
--   max ammo:       12 (vanilla 16). ammo_per_clip and ammo_per_reload
--                   stay at 1 (handgun's bolt-action style).
--   alert range:    25m (vanilla 10m) on `alert_sound_range_fire`
--                   for every firing sub-action — matches the
--                   blunderbuss's audible radius. Black-powder boom.

local _MUSKET_DAMAGE_MULT      = 2.0
local _MUSKET_RELOAD_MULT      = 2.0
local _MUSKET_MAX_AMMO         = 12
local _MUSKET_ALERT_RANGE_FIRE = 25

-- Bayonet thrust (action_three / special key F). Clone of Kerillian's spear
-- heavy stab (`heavy_slashing_smiter_stab_polearm`) with the user-requested
-- "slowed down + boosted stagger" tune: attack × 0.85 (lighter per-thrust
-- punch), impact × 1.5 (much harder enemies-stagger). Slot in as a melee
-- sweep on action_three. Single-press F triggers one thrust; player can
-- spam F for repeated thrusts. NOT a true stance toggle (vanilla doesn't
-- support runtime template swapping cleanly) — for full "switch to spear
-- moveset on F" behavior, see the v3 TODO note above the variant def.
local _MUSKET_BAYONET_DAMAGE_MULT  = 0.85
local _MUSKET_BAYONET_STAGGER_MULT = 1.5

local function _create_cwv_musket_damage_profile()
	if not DamageProfileTemplates then return "shot_sniper" end
	local source = DamageProfileTemplates.shot_sniper
	if not source then return "shot_sniper" end
	local key = "cwv_musket_shot"
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)

	-- shot_sniper carries near/far variants on default_target.power_distribution.
	-- Multiply BOTH attack (damage) and impact (stagger) on each variant by
	-- the musket damage multiplier. Per memory `feedback_cwv_*` the dropoff
	-- curve and shield_break flag inherited from shot_sniper are preserved
	-- by the deep clone above.
	if clone.default_target then
		local function _scale(pd)
			if not pd then return end
			if pd.attack then pd.attack = pd.attack * _MUSKET_DAMAGE_MULT end
			if pd.impact then pd.impact = pd.impact * _MUSKET_DAMAGE_MULT end
		end
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
		_scale(clone.default_target.power_distribution)  -- defensive (some profiles use the un-near/un-far shape)
	end

	-- targets[] (per-target overrides, e.g. headshot vs body) — same scale.
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			if target.power_distribution_near then
				if target.power_distribution_near.attack then target.power_distribution_near.attack = target.power_distribution_near.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution_near.impact then target.power_distribution_near.impact = target.power_distribution_near.impact * _MUSKET_DAMAGE_MULT end
			end
			if target.power_distribution_far then
				if target.power_distribution_far.attack then target.power_distribution_far.attack = target.power_distribution_far.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution_far.impact then target.power_distribution_far.impact = target.power_distribution_far.impact * _MUSKET_DAMAGE_MULT end
			end
			if target.power_distribution then
				if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * _MUSKET_DAMAGE_MULT end
			end
		end
	end

	DamageProfileTemplates[key] = clone

	-- Register in NetworkLookup.damage_profiles so multiplayer hit RPCs can
	-- serialize the new key. Without this, any networked damage event
	-- referencing cwv_musket_shot crashes the client with "Table
	-- damage_profiles does not contain key" — same family of issue as the
	-- weapon_skins / item_names lookups (crash GUID a8094388, hit on first
	-- musket fire).
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

-- Bayonet thrust damage profile: clone Kerillian spear's heavy stab profile
-- with attack scaled down (slower per-thrust damage to balance the always-
-- ready melee on a ranged weapon) and impact scaled up (heavier stagger,
-- per the user's "use it like his 1h spear, slow it down and add more
-- stagger" spec).
local function _create_cwv_musket_bayonet_damage_profile()
	if not DamageProfileTemplates then return "heavy_slashing_smiter_stab_polearm" end
	local source = DamageProfileTemplates.heavy_slashing_smiter_stab_polearm
	if not source then return "heavy_slashing_smiter_stab_polearm" end
	local key = "cwv_musket_bayonet_thrust"
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)

	-- Spear stab profile uses the simpler `power_distribution` shape (no near/far
	-- variants — melee distance is uniform). Scale attack and impact independently.
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _MUSKET_BAYONET_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _MUSKET_BAYONET_STAGGER_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end

	DamageProfileTemplates[key] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

-- ============================================================
-- Musket stance toggle helpers (forward-declared for closure capture)
-- ============================================================
-- The action_three.enter_function below references this helper. In Lua 5.1
-- a closure resolves upvalues at function-creation time; declaring this
-- BEFORE `_create_musket_template` and `_create_musket_template_melee`
-- ensures the binding exists when the action_three closure is built.

local function _toggle_musket_stance_and_rewield(player_unit)
	if not player_unit or not Unit.alive(player_unit) then return end
	local ok_inv, inv = pcall(ScriptUnit.extension, player_unit, "inventory_system")
	if not ok_inv or not inv then return end
	local equipment = inv:equipment()
	if not equipment then return end
	local wielded_slot = equipment.wielded_slot
	if not wielded_slot then return end
	local slot_data = equipment.slots[wielded_slot]
	if not slot_data or not slot_data.item_data then return end
	local item_data = slot_data.item_data

	-- Gate: operate on EITHER cwv_es_musket or cwv_es_musket_old items.
	-- Both share this helper (stance flag is per-item via mod_data so no
	-- collision); the get_item_template hook below routes to the correct
	-- template family. v0.1.301: extended to cover old musket templates.
	local is_musket     = (item_data.template == "musket_template" or item_data.template == "musket_template_melee")
	local is_old_musket = (item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee")
	if not (is_musket or is_old_musket) then
		local bid = item_data.backend_id
		if not bid or not bid:match("^cwv_es_musket_") then return end
	end

	-- v0.1.265: removed the v0.1.260 slot_type gate. Polearm variant
	-- now uses musket_template (ranged) and toggles to musket_template_melee
	-- like the ranged variant. The defensive WeaponSpreadExtension
	-- hook (added v0.1.265) handles the nil spread_settings crash that
	-- previously blocked this design.

	-- Stance flag stored on the IML item_data's mod_data. mod_data is
	-- mutable across the whole equip lifecycle; survives wield+unwield.
	item_data.mod_data = item_data.mod_data or {}
	local current = item_data.mod_data.cwv_musket_stance or "ranged"
	local next_stance = (current == "ranged") and "melee" or "ranged"
	item_data.mod_data.cwv_musket_stance = next_stance

	-- v0.1.307: capture EXACT ammo state (chambered + reserve + reloading flag)
	-- separately, instead of a single `total_ammo_fraction`. The fraction
	-- collapses chamber + reserve into one number, and vanilla's
	-- `_starting_loaded_ammo / _start_ammo` reconstruction always gives
	-- `_current_ammo = min(ammo_per_clip, start_ammo) = 1` — meaning EVERY
	-- stance toggle "refills" the chamber from 0 to 1, which is a free
	-- reload exploit. Capture precise values and restore them post-spawn
	-- to lock the player's actual ammo state across the toggle.
	item_data.mod_data = item_data.mod_data or {}
	local cap_current, cap_reserve, cap_shots_fired, cap_reloading = nil, nil, nil, nil
	local rifle_unit_for_ammo = equipment.right_hand_wielded_unit or equipment.right_hand_wielded_unit_3p
	if rifle_unit_for_ammo and Unit.alive(rifle_unit_for_ammo)
			and ScriptUnit.has_extension(rifle_unit_for_ammo, "ammo_system") then
		local ok_ammo, ext = pcall(ScriptUnit.extension, rifle_unit_for_ammo, "ammo_system")
		if ok_ammo and ext then
			cap_current      = ext._current_ammo
			cap_reserve      = ext._available_ammo
			cap_shots_fired  = ext._shots_fired
			cap_reloading    = ext.is_reloading and ext:is_reloading() or false
		end
	end
	-- If we couldn't get live readings (toggling FROM melee — no ammo
	-- extension on the polearm-template unit), fall back to persisted
	-- values from the previous capture.
	if cap_current ~= nil then
		item_data.mod_data.cwv_musket_cap_current     = cap_current
		item_data.mod_data.cwv_musket_cap_reserve     = cap_reserve
		item_data.mod_data.cwv_musket_cap_shots_fired = cap_shots_fired
		item_data.mod_data.cwv_musket_cap_reloading   = cap_reloading
	else
		cap_current     = item_data.mod_data.cwv_musket_cap_current
		cap_reserve     = item_data.mod_data.cwv_musket_cap_reserve
		cap_shots_fired = item_data.mod_data.cwv_musket_cap_shots_fired
		cap_reloading   = item_data.mod_data.cwv_musket_cap_reloading
	end
	-- If reloading was in progress at toggle time, set the same flag used
	-- by the _wield_slot POST hook so vanilla's auto-reload-on-wield gets
	-- aborted on toggle-back.
	if cap_reloading then
		item_data.mod_data.cwv_musket_reload_interrupted = true
	end

	-- Force a destroy + add + wield cycle on the slot so the new template
	-- (resolved by the BackendUtils.get_item_template hook below) takes
	-- effect. Vanilla `wield()` only show/hides existing units — it doesn't
	-- respawn with a new template. We have to destroy + re-add.
	local slot_name = wielded_slot
	mod:info("[cwv musket] stance: %s → %s (slot=%s, current=%s reserve=%s reloading=%s)",
		current, next_stance, slot_name, tostring(cap_current), tostring(cap_reserve), tostring(cap_reloading))
	local ok_destroy, err_destroy = pcall(function() inv:destroy_slot(slot_name, true) end)
	if not ok_destroy then
		mod:warning("[cwv musket] destroy_slot failed: %s", tostring(err_destroy))
		return
	end
	-- v0.1.328: choose `target_percent` so vanilla's wield-animation picker
	-- in _wield_slot:2050 sees the CORRECT chamber state.
	-- Vanilla: `_current_ammo = math.min(_ammo_per_clip, _start_ammo)`
	-- where `_start_ammo = round(percent * max_ammo)`.
	-- ammo_per_clip = 1 for handgun; so any percent yielding start_ammo >= 1
	-- gives _current_ammo = 1 (chamber loaded → "loaded" wield anim).
	-- ammo_percent = 0 always gives _current_ammo = 0 → "not_loaded" anim.
	-- v0.1.307 passed 0 unconditionally and restored ammo afterward, but
	-- the anim was already selected → user saw empty-chamber pose even with
	-- a round chambered. Now pass a percent matching captured state:
	--   chamber loaded (cap_current >= 1) → fraction = total/max → loaded anim
	--   chamber empty  (cap_current == 0, mid-reload) → 0 → not-loaded anim
	-- POST-spawn we still restore precise reserves below.
	local target_percent = 0
	if cap_current and cap_current >= 1 then
		local _MAX_AMMO = 11  -- old_musket_template max_ammo
		target_percent = math.min(1, ((cap_current or 0) + (cap_reserve or 0)) / _MAX_AMMO)
	end
	local ok_add, err_add = pcall(function() inv:add_equipment(slot_name, item_data, nil, nil, target_percent) end)
	if not ok_add then
		mod:warning("[cwv musket] add_equipment failed: %s", tostring(err_add))
		return
	end
	local ok_wield, err_wield = pcall(function() inv:wield(slot_name) end)
	if not ok_wield then
		mod:warning("[cwv musket] wield failed: %s", tostring(err_wield))
	end
	-- v0.1.307: restore precise ammo state on the freshly-spawned ammo
	-- extension (if present — ranged template has one, melee polearm doesn't).
	local new_eq = inv:equipment()
	local new_unit = new_eq and (new_eq.right_hand_wielded_unit or new_eq.right_hand_wielded_unit_3p)
	if new_unit and Unit.alive(new_unit) and ScriptUnit.has_extension(new_unit, "ammo_system")
			and cap_current ~= nil then
		local new_ext = ScriptUnit.extension(new_unit, "ammo_system")
		new_ext._current_ammo  = cap_current
		new_ext._available_ammo = cap_reserve or 0
		new_ext._shots_fired   = cap_shots_fired or 0
		-- If we restored ammo_count to 0 AND reload was interrupted, vanilla
		-- _wield_slot may have already kicked off an auto-reload by now —
		-- cancel it. (Same logic as the _wield_slot POST hook, but for the
		-- stance-toggle path which doesn't go through that hook's PRE.)
		if cap_reloading and new_ext.is_reloading and new_ext:is_reloading() then
			pcall(function() new_ext:abort_reload() end)
		end
		-- v0.1.307: re-sync shared pool to the restored reserve so the
		-- other pool member (if any) sees the same reserve.
		if _cwv_musket_sync_pool then _cwv_musket_sync_pool(new_ext) end
	end
end

local function _create_musket_template()
	if not Weapons or not Weapons.handgun_template_1 then
		mod:warning("handgun_template_1 not found — Musket template unavailable")
		return
	end
	if Weapons.musket_template then return end

	local template = table.clone(Weapons.handgun_template_1, true)
	local damage_key = _create_cwv_musket_damage_profile()

	-- Walk every sub-action; swap damage_profile (when shot_sniper) and
	-- bump alert_sound_range_fire on any firing sub-action that has one.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.damage_profile == "shot_sniper" then
							sub_action.damage_profile = damage_key
						end
						if sub_action.alert_sound_range_fire then
							sub_action.alert_sound_range_fire = _MUSKET_ALERT_RANGE_FIRE
						end
					end
				end
			end
		end
	end

	if template.ammo_data then
		template.ammo_data.reload_time = (template.ammo_data.reload_time or 1.5) * _MUSKET_RELOAD_MULT
		template.ammo_data.max_ammo = _MUSKET_MAX_AMMO
	end

	-- ============================================================
	-- BAYONET STANCE TOGGLE (action_three / special key, F or C)
	-- ============================================================
	-- The musket carries TWO templates registered on `Weapons`:
	--
	--   `musket_template`        — ranged moveset (this template; handgun shoot)
	--   `musket_template_melee`  — Kerillian spear moveset, slowed + boosted
	--                              stagger (built below `_create_musket_template`)
	--
	-- F press triggers a hidden destroy_slot + add_equipment + wield cycle
	-- on the musket's slot. Per-item stance flag stored at
	-- `item_data.mod_data.cwv_musket_stance`. The
	-- `BackendUtils.get_item_template` hook (further down) reads the flag
	-- and returns the matching template, so the recreated weapon spawns
	-- with the correct moveset.
	--
	-- This is the "runtime template swap" approach — true unequip+equip
	-- with template swap, not the v0.1.203-204 chain-conditional dual-
	-- sub-action experiment (which crashed lookup_data + sweep target,
	-- and didn't actually switch movesets in practice).
	--
	-- Stance toggle action is shared verbatim with `musket_template_melee`
	-- so the player can press F from either stance to toggle back.

	template.actions.action_three = {
		default = {
			kind = "dummy",
			anim_event = "reload",
			anim_end_event = "attack_finished",
			total_time = 0.4,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- Attach lookup_data on every sub_action, including our new ones.
	-- Vanilla `weapons.lua:305-312` does this during `Weapons[]` init at
	-- boot but our mod-loaded additions miss it and crash on first touch.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "musket_template",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- v0.1.258: add melee-tooltip-required fields. The handgun template
	-- this clones from has none of these (ranged weapon), but vanilla's
	-- `ui_passes_tooltips.lua` does arithmetic on `max_fatigue_points`
	-- when displaying the tooltip for ANY equipped weapon — including a
	-- ranged-template weapon equipped in a melee slot via the polearm
	-- variant. nil → arithmetic crash (GUID 451895b3). Defensive defaults
	-- below mirror tuskgor spear values; benign when the weapon is
	-- actually used in a ranged slot (the fields just sit unread).
	template.max_fatigue_points = template.max_fatigue_points or 8
	template.dodge_count = template.dodge_count or 3
	template.block_angle = template.block_angle or 180
	template.outer_block_angle = template.outer_block_angle or 360
	template.block_fatigue_point_multiplier = template.block_fatigue_point_multiplier or 0.5
	template.outer_block_fatigue_point_multiplier = template.outer_block_fatigue_point_multiplier or 2

	Weapons.musket_template = template
	mod:info("Created musket_template (damage×%.1f, reload×%.1f, max_ammo=%d, alert_range=%dm, bayonet stance toggle on F: damage×%.2f, stagger×%.2f)",
		_MUSKET_DAMAGE_MULT, _MUSKET_RELOAD_MULT, _MUSKET_MAX_AMMO, _MUSKET_ALERT_RANGE_FIRE,
		_MUSKET_BAYONET_DAMAGE_MULT, _MUSKET_BAYONET_STAGGER_MULT)
end

_create_musket_template()

-- ============================================================
-- Musket melee template (Kruber's native heavy spear, slow + stagger)
-- ============================================================
-- v0.1.206: switched from `two_handed_spears_elf_template_1` (Kerillian
-- spear) to `two_handed_heavy_spears_template` (Kruber's tuskgor spear).
-- The elf spear's state_machine, display_unit, and other assets live in
-- Kerillian's package and aren't loaded for Kruber, which crashed with
-- "Resource not loaded" (GUID 1363574c) on stance toggle. Kruber's
-- native heavy spear template uses
-- `units/beings/player/first_person_base/state_machines/melee/polearm`
-- and other Kruber-loaded resources — no cross-character package issue.
--
-- Functionally similar to the elf spear (polearm thrust moveset), and
-- since the user originally suggested heavy_spear as one option, this
-- is acceptable behavior. If we later want elf-spear flavor specifically,
-- we'd need to force-load the elf spear's package via Managers.package
-- per the cross-character pattern.
--
-- Damage tuning (per user "slow it down + add stagger"):
--   * attack power × 0.85 on every sub-action with a damage_profile
--   * impact (stagger) × 1.5 on the same
--   * anim_time_scale × 0.85 on every sub-action that has it
--     (makes swings 15% slower; tuskgor spear is already measured —
--      this leans into "musket-bayonet drilling" feel)
--
-- Visual: NO override of right_hand_unit etc. — the IML inheritance
-- system uses item_data.right_hand_unit (the rifle mesh) regardless
-- of which template is active, so the rifle stays the wielded mesh.
-- The bayonet child-link also persists (it's spawned by the
-- GearUtils.spawn_inventory_unit hook below, which fires for either
-- template since the gate is on item_template family, not specific
-- template).

local _MUSKET_MELEE_DAMAGE_MULT     = 0.85
local _MUSKET_MELEE_STAGGER_MULT    = 1.5
local _MUSKET_MELEE_ANIM_TIME_SCALE = 0.85  -- swings ~15% slower

local function _scale_melee_damage_profile(profile_name)
	if not DamageProfileTemplates then return profile_name end
	local source = DamageProfileTemplates[profile_name]
	if not source then return profile_name end
	local key = "cwv_musket_melee_" .. profile_name
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _MUSKET_MELEE_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _MUSKET_MELEE_STAGGER_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end

	DamageProfileTemplates[key] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

local function _create_musket_template_melee()
	if not Weapons or not Weapons.two_handed_heavy_spears_template then
		mod:warning("two_handed_heavy_spears_template not found — Musket melee template unavailable")
		return
	end
	if Weapons.musket_template_melee then return end

	local template = table.clone(Weapons.two_handed_heavy_spears_template, true)

	-- v0.1.227: per user "make it have it's normal speed and melee values" —
	-- DO NOT apply damage scaling or anim_time_scale changes. Vanilla
	-- tuskgor spear stats are kept verbatim. Previously v0.1.220-226
	-- applied attack ×0.85, stagger ×1.5, anim_time ×0.85; reverted.
	--
	-- v0.1.243: per user "make the range_mod 1.2" — override every
	-- sub-action's range_mod to 1.2 (vanilla tuskgor uses 1.35 on every
	-- attack). Bayonet shouldn't reach as far as a full polearm haft.
	-- range_mod_add (the additive component, varies 0.25-1.0 per
	-- sub-action) kept vanilla.
	local _MELEE_RANGE_MOD = 1.2
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.range_mod then
						sub_action.range_mod = _MELEE_RANGE_MOD
					end
				end
			end
		end
	end

	-- Stance toggle back to ranged on action_three. Mirrors the one on
	-- musket_template; the toggle helper handles both directions.
	template.actions = template.actions or {}
	template.actions.action_three = {
		default = {
			kind = "dummy",
			-- No anim_event: dummy action just toggles stance, no visual needed.
			-- Polearm SM has its own anim vocabulary; using the wrong event
			-- would crash. Vanilla state machines fall through cleanly when
			-- anim_event is omitted (the current pose holds for total_time).
			total_time = 0.4,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- Same lookup_data attach as musket_template — vanilla weapons.lua's
	-- init pass doesn't run on our mod-loaded template.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "musket_template_melee",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- Override display_unit to handgun rig. v0.1.227: tuskgor spear's
	-- display_unit `display_2h_polearm` should also be loaded for Kruber
	-- (his native weapon) but using the handgun rig is safe + idempotent.
	template.display_unit = "units/weapons/weapon_display/display_1h_handguns"

	Weapons.musket_template_melee = template
	mod:info("Created musket_template_melee (Kruber tuskgor spear clone, vanilla stats — no damage/speed scaling)")
end

_create_musket_template_melee()

-- ============================================================
-- "Old Musket" template (cwv_es_musket_old) — ranged-only
-- ============================================================
-- v0.1.300: clone of vanilla `handgun_template_1` with modifiers per user
-- spec ("based on the original rifle"):
--   * Reload time: 1.5x vanilla (50% slower)
--   * Ranged damage: 1.5x vanilla (+50%, via cloned damage profile)
--   * Max ammo: 11 (vanilla rifle has 16; user spec v0.1.305)
--   * Hip-fire spread: 1.5x wider cone (continuous still/moving and crouch
--     pitch/yaw; ADS / zoomed unchanged so ironsights stays accurate)
-- v0.1.305: wrapped the helpers in `do ... end` to release top-level local
-- slots — Lua 5.1 main chunk has a 200-local limit and we hit it.
do
local _OLD_MUSKET_RELOAD_MULT = 1.5
local _OLD_MUSKET_DAMAGE_MULT = 1.5
local _OLD_MUSKET_MAX_AMMO    = 11
local _OLD_MUSKET_SPREAD_MULT = 1.5

local function _create_cwv_old_musket_damage_profile()
	if not DamageProfileTemplates then return "shot_sniper" end
	local source = DamageProfileTemplates.shot_sniper
	if not source then return "shot_sniper" end
	local key = "cwv_old_musket_shot"
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _OLD_MUSKET_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _OLD_MUSKET_DAMAGE_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
		_scale(clone.default_target.power_distribution)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
			_scale(target.power_distribution)
		end
	end

	-- v0.1.305: penetration tuning per user spec.
	--   * Cleave distribution boosted so the shot punches through ~6 regular
	--     enemies (vanilla shot_sniper = 0.3, gives 1-2 pierce on unarmored).
	--   * Armor modifier bumped on the higher-armor indices so the shot reads
	--     "a bit better through armor" without making it a tank-deleter. The
	--     `armor_modifier_*` arrays are indexed by armor type — vanilla
	--     shot_sniper has (1, 1.2, 1.5, 1, 0.75, 0.5). We bring the upper
	--     three (super-armor / berserker-shielded / chaos-warrior class) up.
	local _CLEAVE_ATTACK = 1.5  -- ~6-target pierce on regular enemies
	local _CLEAVE_IMPACT = 0.6  -- proportional stagger cleave
	if clone.cleave_distribution then
		clone.cleave_distribution.attack = _CLEAVE_ATTACK
		clone.cleave_distribution.impact = _CLEAVE_IMPACT
	end
	local function _boost_armor_attack(mod_table)
		if not mod_table or not mod_table.attack then return end
		-- attack[i] for i=4..6 — armored / super-armored. Bring each up by ~0.2.
		for i = 4, 6 do
			if mod_table.attack[i] then mod_table.attack[i] = mod_table.attack[i] + 0.2 end
		end
	end
	_boost_armor_attack(clone.armor_modifier_near)
	_boost_armor_attack(clone.armor_modifier_far)

	DamageProfileTemplates[key] = clone

	-- Register in NetworkLookup so multiplayer hit RPCs can serialize the key
	-- (see _create_cwv_musket_damage_profile for the rationale + GUID a8094388).
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end
	return key
end

local function _create_old_musket_template()
	if not Weapons or not Weapons.handgun_template_1 then
		mod:warning("handgun_template_1 not found — old_musket_template unavailable")
		return
	end
	if Weapons.old_musket_template then return end

	local template = table.clone(Weapons.handgun_template_1, true)
	local damage_key = _create_cwv_old_musket_damage_profile()

	-- Swap damage_profile on every shot_sniper firing sub-action.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.damage_profile == "shot_sniper" then
						sub_action.damage_profile = damage_key
					end
				end
			end
		end
	end

	-- Reload time bump (vanilla baseline * 1.5).
	if template.ammo_data and template.ammo_data.reload_time then
		template.ammo_data.reload_time = template.ammo_data.reload_time * _OLD_MUSKET_RELOAD_MULT
	end

	-- v0.1.305: max ammo = 11 per user spec (vanilla rifle has 16).
	if template.ammo_data then
		template.ammo_data.max_ammo = _OLD_MUSKET_MAX_AMMO
	end

	-- v0.1.305: hip-fire spread cone 1.5x wider. Vanilla `handgun_template_1`
	-- references SpreadTemplates.handgun via `default_spread_template = "handgun"`.
	-- Clone that template and scale ONLY the hip-fire / non-zoomed cones; ADS
	-- (zoomed_*) cones left at vanilla so ironsights stays precise.
	if SpreadTemplates and SpreadTemplates.handgun and not SpreadTemplates.cwv_old_musket then
		local sclone = table.clone(SpreadTemplates.handgun, true)
		if sclone.continuous then
			for state, vals in pairs(sclone.continuous) do
				-- Skip zoomed variants; scale only hip-fire poses.
				if not state:find("zoomed") and type(vals) == "table" then
					if vals.max_pitch then vals.max_pitch = vals.max_pitch * _OLD_MUSKET_SPREAD_MULT end
					if vals.max_yaw   then vals.max_yaw   = vals.max_yaw   * _OLD_MUSKET_SPREAD_MULT end
				end
			end
		end
		SpreadTemplates.cwv_old_musket = sclone
		mod:info("Registered SpreadTemplates.cwv_old_musket (hip-fire %.2fx wider; ADS unchanged)", _OLD_MUSKET_SPREAD_MULT)
	end
	template.default_spread_template = "cwv_old_musket"

	-- v0.1.301: stance toggle on action_three (special key). Mirrors the one
	-- on musket_template — same toggle helper handles both variants (gated on
	-- item_data.template + backend_id).
	template.actions.action_three = {
		default = {
			kind = "dummy",
			anim_event = "reload",
			anim_end_event = "attack_finished",
			total_time = 0.4,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- Attach lookup_data on every sub_action (else lookup crashes on first
	-- touch — see _create_musket_template for the rationale).
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "old_musket_template",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	Weapons.old_musket_template = template
	mod:info("Created old_musket_template (handgun_template_1 + %.2fx damage + %.2fx reload time)",
		_OLD_MUSKET_DAMAGE_MULT, _OLD_MUSKET_RELOAD_MULT)
end

_create_old_musket_template()
end  -- end of do-block opened above _OLD_MUSKET_RELOAD_MULT

-- ============================================================
-- "Old Musket" melee template (bayonet stance) — Tuskgor spear clone
-- ============================================================
-- v0.1.301: clone of `two_handed_heavy_spears_template` with:
--   * range_mod 1.2 on every sweep (absolute, vs vanilla tuskgor 1.35)
--   * damage profiles cloned with 0.9x attack (10% less than vanilla spear).
--     Stagger left at vanilla 1.0x.
-- Stance toggle on action_three swaps back to old_musket_template (ranged).
-- The user's earlier instruction was "based on the original rifle" — the
-- rifle has no melee, so for the melee branch we anchor to vanilla
-- Tuskgor spear baseline rather than the existing cwv_musket bayonet
-- (which has -15% damage + 1.5x stagger). Result: old musket bayonet
-- hits softer than vanilla spear (and softer than existing musket
-- bayonet's stagger boost) but reaches farther than ours used to.
-- v0.1.305: wrapped in do-end to release top-level local slots.
do
local _OLD_MUSKET_BAYONET_DAMAGE_MULT = 0.9
local _OLD_MUSKET_BAYONET_RANGE_MOD   = 1.2

local function _scale_old_musket_melee_damage_profile(profile_name)
	if not DamageProfileTemplates then return profile_name end
	local source = DamageProfileTemplates[profile_name]
	if not source then return profile_name end
	local key = "cwv_old_musket_melee_" .. profile_name
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _OLD_MUSKET_BAYONET_DAMAGE_MULT end
		-- stagger (impact) left at vanilla — user didn't ask for stagger change.
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end
	DamageProfileTemplates[key] = clone
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end
	return key
end

local function _create_old_musket_template_melee()
	if not Weapons or not Weapons.two_handed_heavy_spears_template then
		mod:warning("two_handed_heavy_spears_template not found — old_musket_template_melee unavailable")
		return
	end
	if Weapons.old_musket_template_melee then return end

	local template = table.clone(Weapons.two_handed_heavy_spears_template, true)

	-- range_mod 1.2 + swap damage profiles to scaled clones.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.range_mod then
							sub_action.range_mod = _OLD_MUSKET_BAYONET_RANGE_MOD
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _scale_old_musket_melee_damage_profile(sub_action.damage_profile)
						end
					end
				end
			end
		end
	end

	-- Stance toggle back to ranged.
	template.actions = template.actions or {}
	template.actions.action_three = {
		default = {
			kind = "dummy",
			total_time = 0.4,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- lookup_data attach.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "old_musket_template_melee",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- Display unit — handgun rig (same as musket_template_melee).
	template.display_unit = "units/weapons/weapon_display/display_1h_handguns"

	Weapons.old_musket_template_melee = template
	mod:info("Created old_musket_template_melee (Tuskgor spear clone, range_mod=%.2f, damage=%.2fx)",
		_OLD_MUSKET_BAYONET_RANGE_MOD, _OLD_MUSKET_BAYONET_DAMAGE_MULT)
end

_create_old_musket_template_melee()
end  -- end of do-block opened above _OLD_MUSKET_BAYONET_DAMAGE_MULT

-- ============================================================
-- cwv musket shared ammo pool
-- ============================================================
-- v0.1.306: when the player has cwv musket items equipped in BOTH the
-- ranged slot AND the melee slot (per the cross-slot enable v0.1.304),
-- their reserve ammo (`_available_ammo` on the ammo extension) is shared.
-- Each item keeps its own CHAMBER (`_current_ammo`, capped by
-- `ammo_per_clip = 1`). Per user spec: max_ammo = 11 → 1 chambered + 10
-- reserve per item. Two equipped = 1+1 chambered (separate) + 20 reserve
-- (pooled).
--
-- Mechanism: weak-keyed set of registered ammo extensions. Whenever any
-- pool member's `_available_ammo` changes (reload completion, ammo
-- pickup), the sync helper copies the new value to every other live
-- member. Cap dynamically scales with the count of alive pool members.
do
	_CWV_MUSKET_AMMO_EXTS    = setmetatable({}, { __mode = "k" })
	_CWV_RESERVE_PER_MUSKET  = 10  -- max_ammo (11) - ammo_per_clip (1)

	local function _count_alive_pool_members()
		local n = 0
		for ext in pairs(_CWV_MUSKET_AMMO_EXTS) do
			if ext.unit and Unit.alive(ext.unit) then n = n + 1 end
		end
		return n
	end

	_cwv_musket_pool_cap = function()
		return _count_alive_pool_members() * _CWV_RESERVE_PER_MUSKET
	end

	-- Sync one member's _available_ammo across all alive pool members,
	-- capped by the dynamic pool max. Called whenever any single
	-- member's available_ammo changes.
	_cwv_musket_sync_pool = function(source_ext)
		if not source_ext or not source_ext._cwv_musket_pool_member then return end
		local cap = _cwv_musket_pool_cap()
		local pool = math.min(source_ext._available_ammo or 0, cap)
		source_ext._available_ammo = pool
		for ext in pairs(_CWV_MUSKET_AMMO_EXTS) do
			if ext ~= source_ext and ext.unit and Unit.alive(ext.unit) then
				ext._available_ammo = pool
			end
		end
	end

	-- Called from our existing GearUtils.spawn_inventory_unit hook for
	-- cwv_es_musket_old items, to mark + register the spawned ammo
	-- extension. Aligns its initial `_available_ammo` with any existing
	-- pool member's value (so a second-spawned musket inherits the
	-- pool's current reserve, doesn't reset it to default 10).
	_cwv_musket_register_ammo_ext = function(ext)
		if not ext or not ext.unit or not Unit.alive(ext.unit) then return end
		if ext._cwv_musket_pool_member then return end
		ext._cwv_musket_pool_member = true
		_CWV_MUSKET_AMMO_EXTS[ext] = true
		-- Inherit existing pool value if any live members exist
		for other in pairs(_CWV_MUSKET_AMMO_EXTS) do
			if other ~= ext and other.unit and Unit.alive(other.unit) then
				ext._available_ammo = other._available_ammo
				break
			end
		end
		-- Re-sync with new cap (which grew when we added this member)
		_cwv_musket_sync_pool(ext)
		mod:info("[cwv musket pool] registered ext on unit=%s, members=%d, pool_cap=%d, available=%s",
			tostring(ext.unit), _count_alive_pool_members(), _cwv_musket_pool_cap(), tostring(ext._available_ammo))
	end

	-- Hook ammo extension update — vanilla's reload completion mutates
	-- `_available_ammo` in-place (line 174 of generic_ammo_user_extension.lua).
	-- After the vanilla update tick, if our pool member's available_ammo
	-- changed, sync to the other members.
	mod:hook("GenericAmmoUserExtension", "update", function(orig, self, ...)
		local was_member = self._cwv_musket_pool_member
		local before = was_member and self._available_ammo or nil
		local r = orig(self, ...)
		if was_member and self._available_ammo ~= before then
			_cwv_musket_sync_pool(self)
		end
		return r
	end)

	-- Hook add_ammo — ammo pickups (or any direct call) should propagate
	-- to all pool members so they all see the refill.
	mod:hook("GenericAmmoUserExtension", "add_ammo", function(orig, self, amount)
		if self._cwv_musket_pool_member then
			local before = self._available_ammo
			local r = orig(self, amount)
			if self._available_ammo ~= before then
				_cwv_musket_sync_pool(self)
			end
			return r
		end
		return orig(self, amount)
	end)
end

-- ============================================================
-- Musket template-swap hook (BackendUtils.get_item_template)
-- ============================================================
-- Reads the per-item stance flag on item_data.mod_data and returns the
-- appropriate template. Without this hook, vanilla returns
-- musket_template (the one set on the variant def) regardless of stance.
-- The toggle helper above flips the flag and forces a destroy+add+wield
-- cycle, which makes vanilla call get_item_template again, which we
-- intercept here to return musket_template_melee on melee stance.

mod:hook("BackendUtils", "get_item_template", function(func, item_data, backend_id)
	local template = func(item_data, backend_id)
	if not item_data then return template end

	-- v0.1.301: identify variant family — cwv_es_musket vs cwv_es_musket_old.
	-- Both use mod_data.cwv_musket_stance as the per-item stance flag (it's
	-- per-item via mod_data so no name collision); we just return different
	-- template pairs depending on which family.
	local is_old_musket = false
	local is_musket     = false
	if item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee" then
		is_old_musket = true
	elseif item_data.template == "musket_template" or item_data.template == "musket_template_melee" then
		is_musket = true
	else
		local bid = item_data.backend_id or backend_id
		if type(bid) == "string" then
			if bid:match("^cwv_es_musket_old_") then
				is_old_musket = true
			elseif bid:match("^cwv_es_musket_") then
				is_musket = true
			end
		end
	end
	if not (is_musket or is_old_musket) then return template end

	-- Read stance from mod_data; default to ranged.
	local stance = item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged"
	if is_old_musket then
		if stance == "melee" and Weapons.old_musket_template_melee then
			return Weapons.old_musket_template_melee
		end
		return Weapons.old_musket_template or template
	end
	if stance == "melee" and Weapons.musket_template_melee then
		return Weapons.musket_template_melee
	end
	return Weapons.musket_template or template
end)

-- ============================================================
-- Cross-slot inventory: musket items appear in BOTH ranged AND melee
-- inventory grids
-- ============================================================
-- v0.1.268: per user direction, both `cwv_es_musket` (ranged-slot
-- inheritance) and `cwv_es_musket_polearm` (melee-slot inheritance)
-- should be equippable in EITHER slot. Player picks which musket
-- goes where; equipping consumes the item from both lists.
--
-- Mechanism: vanilla's `BackendInterfaceItemPlayfab:get_filtered_items`
-- evaluates the slot-grid filter string ("slot_type == ranged" /
-- "slot_type == melee") against each backend item. Our hook detects
-- those filters and APPENDS any musket items the player owns that
-- weren't already in the result. Since each item is a unique backend
-- entry, equipping it in one slot prevents it from showing as
-- available in the other (the slot tracks the equipped ItemId).
--
-- This is a UI-layer trick — the items keep their declared slot_type
-- in IML; the filter just becomes permissive for our muskets. The
-- equip path doesn't check slot_type compatibility, so vanilla accepts
-- the cross-slot equip without complaint. The wielded weapon's
-- behavior is determined by its template (musket_template), not by
-- its slot, so it fires identically in either slot.

-- v0.1.308: list of cwv item-key prefixes that should be cross-slot
-- equippable. These items inherit slot_type="ranged" via their base_weapon
-- but the player should be able to equip them in either slot_ranged or
-- slot_melee via the cross-slot inject below. Other cwv ranged weapons
-- (e.g. cwv_es_outrider_grenade_launcher) are NOT in this list and remain
-- ranged-only.
local _CWV_CROSS_SLOT_PREFIXES = {
	"cwv_es_musket",          -- musket family (covers cwv_es_musket and cwv_es_musket_old + backend_ids)
}

-- v0.1.327: check ALL candidate id fields, not just the first non-nil one.
-- Earlier `data.key or data.name or item.ItemId or item.backend_id` would
-- short-circuit on the first non-nil — if `data.name` happened to be the
-- inherited base name "es_handgun", the function returned false even though
-- `item.ItemId` was "cwv_es_musket_old_001". Likely root cause of "musket
-- doesn't appear in melee slot" in v0.1.316+ (post-filter scoping dropped
-- the item because the gate returned false).
local function _is_cwv_musket_item(item)
	if not item then return false end
	local data = item.data or item.master_item or item
	local function _check(key)
		if type(key) ~= "string" then return false end
		for _, prefix in ipairs(_CWV_CROSS_SLOT_PREFIXES) do
			if string.find(key, prefix, 1, true) == 1 then
				return true
			end
		end
		return false
	end
	if _check(data and data.key) then return true end
	if _check(data and data.name) then return true end
	if _check(item.ItemId) then return true end
	if _check(item.backend_id) then return true end
	if _check(data and data.backend_id) then return true end
	if _check(data and data.mod_data and data.mod_data.backend_id) then return true end
	return false
end

-- ============================================================
-- Career slot-type override + scoped post-filter
-- ============================================================
-- v0.1.312: combine the v0.1.304 broad career override (which actually
-- surfaced items in the melee grid) with a post-filter on the result that
-- removes non-allowlisted ranged items. End result: only items flagged
-- with `def.cross_slot = true` (currently just `cwv_es_musket_old`) appear
-- in BOTH grids; other ranged weapons stay in slot_ranged only.
--
-- History:
--   v0.1.304 — added "ranged" to slot_melee. Worked but showed ALL ranged.
--   v0.1.310 — reverted to cross-slot inject only. Didn't surface items.
--   v0.1.311 — tried entry.slot_type = "cwv_dual" custom. Item disappeared
--              from BOTH grids (MIL/vanilla doesn't accept unknown slot_type).
--   v0.1.312 — back to broad career override + post-filter for scope.
-- v0.1.313: iterate ALL careers (not just hardcoded Kruber list). Append
-- "ranged" to any career's slot_melee that's exactly {"melee"} (i.e., the
-- default Kruber-style careers). Also clean up cwv_dual leftovers from
-- v0.1.311. Mutation deferred via `mod.on_all_mods_loaded` to ensure
-- CareerSettings is fully populated.
-- Post-filter REMOVED (was scoping items too aggressively or not running
-- on the path the user's UI uses). v0.1.304 broad behavior is restored —
-- ALL ranged weapons will appear in melee grid until we confirm what's
-- breaking, then re-scope.
do
	local function _do_extend()
		if not CareerSettings then
			mod:warning("[cwv slot] CareerSettings nil — skip extension")
			return 0
		end
		local extended = 0
		for career_name, career in pairs(CareerSettings) do
			if type(career) == "table" and career.item_slot_types_by_slot_name then
				local slot_map = career.item_slot_types_by_slot_name
				if slot_map.slot_melee then
					-- Cleanup cwv_dual leftovers from v0.1.311 if they're there.
					for i = #slot_map.slot_melee, 1, -1 do
						if slot_map.slot_melee[i] == "cwv_dual" then
							table.remove(slot_map.slot_melee, i)
						end
					end
					if slot_map.slot_ranged then
						for i = #slot_map.slot_ranged, 1, -1 do
							if slot_map.slot_ranged[i] == "cwv_dual" then
								table.remove(slot_map.slot_ranged, i)
							end
						end
					end
					-- Append "ranged" to slot_melee if not present.
					local has_ranged = false
					for _, t in ipairs(slot_map.slot_melee) do
						if t == "ranged" then has_ranged = true; break end
					end
					if not has_ranged then
						slot_map.slot_melee[#slot_map.slot_melee + 1] = "ranged"
						extended = extended + 1
					end
				end
			end
		end
		mod:echo("[cwv slot] extended slot_melee with 'ranged' on %d careers", extended)
		return extended
	end
	_do_extend()
	-- Re-run after all mods loaded in case CareerSettings was partial earlier.
	function mod.on_all_mods_loaded()
		_do_extend()
	end
end

-- v0.1.314: SINGLE consolidated post-filter hook on get_filtered_items.
-- The career mutation above adds "ranged" to slot_melee, which surfaces
-- ALL ranged weapons in the melee grid. This filter scopes that down so
-- only items whose key matches `_CWV_CROSS_SLOT_PREFIXES` (currently the
-- musket and jav+shield families) remain in the melee result. Native
-- melee items are kept untouched. The ranged-slot filter is NOT touched —
-- vanilla ranged items appear there naturally regardless.
--
-- Replaces the prior dual-hook setup (inject + post-filter) that had
-- potential chain-ordering issues. One hook, one job: take the result
-- vanilla produces, drop the unwanted ranged items from melee grid.
mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
	local items = func(self, filter, params)
	if not items or type(filter) ~= "string" then return items end
	-- Only run for the melee-slot filter.
	if not string.find(filter, "slot_type == melee", 1, true) then return items end

	local filtered, kept, dropped, dropped_examples = {}, 0, 0, {}
	for _, item in ipairs(items) do
		local data = item.data or {}
		local item_slot_type = data.slot_type
		if item_slot_type ~= "ranged" then
			-- Native melee / shield / etc — keep.
			filtered[#filtered + 1] = item
			kept = kept + 1
		else
			-- Ranged item — only keep if it's in our cross-slot allowlist.
			if _is_cwv_musket_item(item) then
				filtered[#filtered + 1] = item
				kept = kept + 1
			else
				dropped = dropped + 1
				-- Log first 3 dropped items so we can see if a musket got dropped.
				if #dropped_examples < 3 then
					dropped_examples[#dropped_examples + 1] = string.format(
						"{key=%s name=%s ItemId=%s bid=%s mod_bid=%s}",
						tostring(data and data.key),
						tostring(data and data.name),
						tostring(item.ItemId),
						tostring(item.backend_id),
						tostring(data and data.mod_data and data.mod_data.backend_id))
				end
			end
		end
	end
	mod:info("[cwv melee-grid filter] kept=%d  dropped_ranged=%d  drop_samples=[%s]",
		kept, dropped, table.concat(dropped_examples, ", "))
	return filtered
end)

-- ============================================================
-- Defensive WeaponSpreadExtension.init hook
-- ============================================================
-- v0.1.265: vanilla `WeaponSpreadExtension.init` does
-- `ItemMasterList[item_name]` to fetch the weapon's template — for
-- our cwv polearm musket variant `item_name` is the inherited base
-- name "es_2h_heavy_spear" (per `feedback_cwv_clone_name_clobber.md`),
-- so the lookup returns the BASE spear IML whose template has no
-- `default_spread_template`. Vanilla then sets
-- `self.spread_settings = SpreadTemplates[nil] = nil`, which crashes
-- the next update frame's arithmetic on `state_settings.max_pitch`.
--
-- Our `BackendUtils.get_item_template` hook can't intercept because
-- the call comes from a name-keyed lookup with no cwv marker.
--
-- Defensive fix: hook init AFTER vanilla, check for nil
-- spread_settings, fall back to handgun spread defaults. This only
-- triggers when the original lookup returned a template without
-- spread settings — vanilla weapons that have proper spread settings
-- never hit the nil branch.

mod:hook_safe("WeaponSpreadExtension", "init", function(self, extension_init_context, unit, extension_init_data)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
		mod:info("[cwv musket] patched WeaponSpreadExtension nil spread_settings → SpreadTemplates.handgun (item_name=%s)",
			tostring(extension_init_data and extension_init_data.item_name))
	end
end)

-- Belt-and-suspenders: also patch in update. v0.1.265's init-only hook
-- fired (per log) but the user still crashed, suggesting either a fresh
-- spread extension was created without our init hook firing, OR
-- spread_settings became nil at some point post-init. Wrapping update
-- with `mod:hook` (full wrapper) lets us patch BEFORE vanilla's update
-- logic runs each frame — guaranteed safety.
mod:hook("WeaponSpreadExtension", "update", function(func, self, unit, input, dt, context, t)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
	end
	return func(self, unit, input, dt, context, t)
end)

-- ============================================================
-- Musket bayonet — child-link a scaled 1H sword to the rifle unit
-- ============================================================
-- The musket carries a fixed bayonet visual: a copy of Kruber's 1H
-- sword (`wpn_emp_sword_02_t1`), scaled thin/short, spawned as its
-- own unit and `World.link_unit`'d to the rifle unit so it inherits
-- the rifle's transform (any animation, swap, holster motion etc.
-- carries the bayonet along). Two units total — one linked to the 1P
-- rifle (player's first-person view) and one to the 3P rifle (other
-- players + previewer + Versus opponents). Both spawned in the
-- `GearUtils.spawn_inventory_unit` post-hook below.
--
-- Lifetime: each bayonet is tracked on the rifle's unit data via
-- `Unit.set_data(rifle, "cwv_musket_bayonet", bayonet_unit)`. When
-- vanilla destroys the rifle (weapon swap, pickup drop, level end),
-- the `GearUtils.destroy_wielded` hook below reads that data slot,
-- destroys the bayonet, and falls through to vanilla. Without this
-- the bayonet would orphan as a free-floating world unit.
--
-- Position/scale tuning: the rifle .unit's local +Y is barrel-forward
-- (verified by visual reference to Kruber's vanilla wield pose), so
-- the bayonet sits at +Y 0.55m relative to the rifle root and is
-- scaled to a thin spike. These two constants are the tuning knobs —
-- if the bayonet floats off the muzzle or reads too thick/long, edit
-- _MUSKET_BAYONET_LOCAL_TRANSLATION and _MUSKET_BAYONET_SCALE.
--
-- Cross-character package note: the rifle's package is auto-loaded
-- by inventory (right_hand_unit), but the sword unit isn't part of
-- that chain. Force-load the sword via `Managers.package:load`
-- (Tuskgor Javelin pup pattern, per `feedback_cwv_cross_character_unit_packages.md`).

-- v0.1.212: switched to wpn_emp_sword_03_t1 — the "Soldier's Longsword"
-- cosmetic skin for `es_1h_sword` (verified via cosmetics_tweaker/
-- VETERAN_SKIN_CATALOG.md:900). v0.1.211's wpn_emp_sword_04_t1 turned
-- out to be the falchion mesh (matching_item_key = "wh_1h_falchion"
-- in item_master_list_weapon_skins.lua:5185), not a real es_1h_sword
-- variant — explains "that's the falchion model". The new path is a
-- proper Kruber 1H sword distinct from the default skin_01 mesh.
local _MUSKET_BAYONET_UNIT_1P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1"
local _MUSKET_BAYONET_UNIT_3P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1_3p"
-- {x, y, z} relative to rifle root. v0.1.206: re-deduced axis convention
-- from the user's prior "elongate the rifle on the Y axis" hint — rifle's
-- local +Y IS the barrel direction (which is why scaling Y stretches the
-- rifle along its length). v0.1.204's {0, 0, 0.55} placed the bayonet
-- 0.55m along rifle's local +Z, which must be the perpendicular "up"
-- axis — explains "floating above". v0.1.205 went MORE along Z (worse).
-- v0.1.206 puts the bayonet along +Y (toward muzzle) with zero Z offset:
--   * X 0    (centered on the barrel)
--   * Y 1.0  (push 1.0m toward the muzzle along the barrel)
--   * Z 0    (no vertical offset; bayonet sits AT barrel level)
-- TUNABLE — if the bayonet is still misplaced, edit these and rebuild.
-- Orientation rotation below is per v0.1.204 user confirmation; don't
-- touch the rotation constants.
local _MUSKET_BAYONET_LOCAL_TRANSLATION = { 0, 0.8, 0.025 }
-- Rotation: the sword model's blade extends along +Y (1H sword convention).
-- Rotate -90° about X to align the blade with the rifle's barrel direction.
-- v0.1.204 user confirmed this orientation is correct. Don't change unless
-- the rifle .unit's local axis convention is empirically different.
local _MUSKET_BAYONET_LOCAL_ROTATION_AXIS  = { 1, 0, 0 }
local _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE = -math.pi / 2
-- Scale: applied in the bayonet's MODEL space (before rotation). Y is the
-- blade-length axis; X/Z thin the blade cross-section.
local _MUSKET_BAYONET_SCALE = { 0.35, 0.6, 0.2 }

local _MUSKET_BAYONET_DATA_KEY = "cwv_musket_bayonet"

-- Weak-keyed table mapping rifle units to their bayonet child units. Used
-- by the visibility-sync hook below (vanilla wield doesn't propagate
-- visibility to linked child units, so when a player holsters the rifle
-- the bayonet stays visible floating in space). Weak rifle keys = entries
-- auto-cleared when the rifle is GC'd.
local _musket_bayonet_pairs = setmetatable({}, { __mode = "k" })

local function _force_load_musket_bayonet_units()
	if not (Managers and Managers.package) then return end
	local function _load(unit_path, ref)
		local ok, err = pcall(function()
			Managers.package:load(unit_path, ref, nil, true, true)
		end)
		if ok then
			mod:info("[cwv musket-bayonet] force-loaded %s (ref=%s)", unit_path, ref)
		else
			mod:warning("[cwv musket-bayonet] failed to force-load %s: %s", unit_path, tostring(err))
		end
	end
	_load(_MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
	_load(_MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
end

_force_load_musket_bayonet_units()

-- ============================================================
-- Musket melee template — force-load polearm state machine
-- ============================================================
-- v0.1.227: reverted from Kerillian's elf spear back to Kruber's NATIVE
-- tuskgor spear (`two_handed_heavy_spears_template`) per user direction.
-- The elf spear's animations didn't read well on the rifle, and the
-- display_unit caused load issues. Tuskgor is Kruber-native; only the
-- polearm state machine needs force-loading (vanilla loads it for
-- Kruber only when his loadout includes es_2h_heavy_spear).

local _MUSKET_MELEE_STATE_MACHINE = "units/beings/player/first_person_base/state_machines/melee/polearm"

local function _force_load_musket_melee_assets()
	if not (Managers and Managers.package) then return end
	local ok, err = pcall(function()
		Managers.package:load(_MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm", nil, true, true)
	end)
	if ok then
		mod:info("[cwv musket-melee] force-loaded %s (ref=%s)", _MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm")
	else
		mod:warning("[cwv musket-melee] failed to force-load %s: %s", _MUSKET_MELEE_STATE_MACHINE, tostring(err))
	end
end

_force_load_musket_melee_assets()

local function _spawn_and_link_musket_bayonet(world, rifle_unit, bayonet_unit_path, package_ref)
	if not world or not rifle_unit or not Unit.alive(rifle_unit) then return nil end
	if not (Managers and Managers.package and Managers.package:has_loaded(bayonet_unit_path, package_ref)) then
		-- Package not ready yet — bail silently; bayonet will be missing on
		-- this equip. Player can re-equip after the load completes (rare race
		-- only at first equip immediately after mod load).
		return nil
	end
	local pos = Unit.world_position(rifle_unit, 0)
	local rot = Unit.world_rotation(rifle_unit, 0)
	local ok_spawn, bayonet = pcall(World.spawn_unit, world, bayonet_unit_path, pos, rot)
	if not ok_spawn or not bayonet then
		mod:warning("[cwv musket-bayonet] spawn failed: %s", tostring(bayonet))
		return nil
	end

	-- Link to root node. The child inherits the parent's full transform
	-- (translation + rotation + scale). Subsequent local_position/scale
	-- ops override the inherited translation/scale at composition time.
	pcall(World.link_unit, world, bayonet, 0, rifle_unit, 0)

	local t = _MUSKET_BAYONET_LOCAL_TRANSLATION
	pcall(Unit.set_local_position, bayonet, 0, Vector3(t[1], t[2], t[3]))
	local r_axis = _MUSKET_BAYONET_LOCAL_ROTATION_AXIS
	local r_ang  = _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE
	pcall(Unit.set_local_rotation, bayonet, 0, Quaternion.axis_angle(Vector3(r_axis[1], r_axis[2], r_axis[3]), r_ang))
	local s = _MUSKET_BAYONET_SCALE
	pcall(Unit.set_local_scale, bayonet, 0, Vector3(s[1], s[2], s[3]))

	return bayonet
end

local function _attach_musket_bayonets(world, rifle_3p, rifle_1p)
	-- Idempotent: skip per-rifle if a bayonet is already tracked for it.
	-- Without this, a code path that re-fires our spawn hook on the same
	-- rifle (e.g. cosmetic application that refreshes equipment without
	-- going through destroy_wielded) would attach a SECOND bayonet,
	-- leaving the first as an orphan tracked-but-not-cleaned-up unit.
	local skipped_3p, skipped_1p = false, false
	if rifle_3p and Unit.alive(rifle_3p) and not _musket_bayonet_pairs[rifle_3p] then
		local bayonet_3p = _spawn_and_link_musket_bayonet(world, rifle_3p, _MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
		if bayonet_3p then
			pcall(Unit.set_data, rifle_3p, _MUSKET_BAYONET_DATA_KEY, bayonet_3p)
			_musket_bayonet_pairs[rifle_3p] = bayonet_3p
		end
	elseif rifle_3p then
		skipped_3p = true
	end
	if rifle_1p and Unit.alive(rifle_1p) and not _musket_bayonet_pairs[rifle_1p] then
		local bayonet_1p = _spawn_and_link_musket_bayonet(world, rifle_1p, _MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
		if bayonet_1p then
			pcall(Unit.set_data, rifle_1p, _MUSKET_BAYONET_DATA_KEY, bayonet_1p)
			_musket_bayonet_pairs[rifle_1p] = bayonet_1p
		end
	elseif rifle_1p then
		skipped_1p = true
	end
	-- Diagnostic log: counts pairs after each attach so duplicate-attach
	-- bugs are visible in mod log. v0.1.239 added to debug user-reported
	-- "floating bayonet on both melee and ranged".
	local pair_count = 0
	for _ in pairs(_musket_bayonet_pairs) do pair_count = pair_count + 1 end
	mod:info("[cwv musket-bayonet] attach: 3p=%s 1p=%s (skipped: 3p=%s 1p=%s) total_pairs=%d",
		tostring(rifle_3p ~= nil), tostring(rifle_1p ~= nil),
		tostring(skipped_3p), tostring(skipped_1p), pair_count)
end

local function _detach_musket_bayonet(world, rifle_unit)
	if not world or not rifle_unit then return end
	local has_data = false
	local ok_check = pcall(function() has_data = Unit.has_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not ok_check or not has_data then return end
	local bayonet
	pcall(function() bayonet = Unit.get_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not bayonet then return end
	-- Hide the bayonet IMMEDIATELY before queuing for deletion. mark_for_deletion
	-- runs at the end of the next frame; without the visibility flag, the
	-- bayonet stays rendered for that frame at its last world position
	-- (frozen where the rifle was when destroyed). User reported this as
	-- a "floating bayonet" after stance toggle — the old bayonet flickered
	-- visible while the new rifle's bayonet was already attached.
	pcall(Unit.set_unit_visibility, bayonet, false)
	if Managers and Managers.state and Managers.state.unit_spawner then
		pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
	else
		pcall(World.destroy_unit, world, bayonet)
	end
end

mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
	local v_w3p, v_a3p, v_w1p, v_a1p =
		func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

	-- Gate: only attach for the musket variant on its right-hand spawn.
	-- IMPORTANT: cwv variants inherit `entry.name` from the base weapon
	-- (per `feedback_cwv_clone_name_clobber.md` — clobbering crashes equip),
	-- so `item_data.name` for cwv_es_musket is "es_handgun", not the cwv key.
	-- Compare the template-table reference instead. v0.1.205: the musket
	-- has TWO templates (ranged + melee for stance toggle); fire for both.
	if hand ~= "right" then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	if not item_template or not Weapons then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	-- v0.1.300-301: gate accepts both musket families (cwv_es_musket and
	-- cwv_es_musket_old), ranged and melee templates. The bayonet attach
	-- is suppressed below for old musket (its mesh has bayonet baked in);
	-- texture/transform/FX-proxy fire for either family.
	if item_template ~= Weapons.musket_template and item_template ~= Weapons.musket_template_melee
	   and item_template ~= Weapons.old_musket_template and item_template ~= Weapons.old_musket_template_melee then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end

	-- v0.1.292: bind textures + v0.1.293: track unit for live transform tuning +
	-- v0.1.293: spawn hidden vanilla rifle proxy for FX emission. All gated on
	-- cwv_es_musket_old backend_id. Helpers defined globally below (search
	-- "_apply_old_musket_textures", "_track_old_musket_unit",
	-- "_spawn_old_musket_fx_proxy").
	local _bid_for_tex = item_data and item_data.backend_id
	if _bid_for_tex and type(_bid_for_tex) == "string" and _bid_for_tex:match("^cwv_es_musket_old") then
		-- v0.1.295: distinguish ranged vs melee mode for 1P transform tuning.
		-- The user wants different pos/rot/scale per stance.
		local _mode = (item_template == Weapons.musket_template_melee
		               or item_template == Weapons.old_musket_template_melee) and "melee" or "ranged"
		_apply_old_musket_textures(v_w1p)
		_apply_old_musket_textures(v_w3p)
		_track_old_musket_unit(v_w1p, "1p", _mode)
		_track_old_musket_unit(v_w3p, "3p", _mode)
		_apply_old_musket_transform(v_w1p, "1p", _mode)
		_apply_old_musket_transform(v_w3p, "3p", _mode)
		_spawn_old_musket_fx_proxy(world, v_w1p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",     owner_unit_1p, "j_rightweaponattach")
		_spawn_old_musket_fx_proxy(world, v_w3p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p", owner_unit_3p, "j_rightweaponattach")

		-- v0.1.306: register the spawned ammo extension into the shared
		-- reserve pool so cross-slot equipped cwv muskets share reserve
		-- ammo (chambered ammo stays per-item). 1P unit only — 3P doesn't
		-- have ammo_system in vanilla rifle template.
		if _cwv_musket_register_ammo_ext and v_w1p and Unit.alive(v_w1p)
				and ScriptUnit.has_extension(v_w1p, "ammo_system") then
			_cwv_musket_register_ammo_ext(ScriptUnit.extension(v_w1p, "ammo_system"))
		end
	end

	-- v0.1.248: aggressive orphan prune BEFORE attaching new bayonet.
	-- Catches stale entries from any code path that bypassed our
	-- destroy_wielded cleanup hook (e.g. world transition / hot-load /
	-- any equipment re-creation that doesn't go through destroy_slot).
	-- Without this, an orphan from a previous spawn floats while a
	-- fresh bayonet attaches to the new rifle — user sees a SECOND
	-- floating bayonet on every equip.
	local orphans_pruned = 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans_pruned = orphans_pruned + 1
		end
	end
	if orphans_pruned > 0 then
		mod:info("[cwv musket-bayonet] pruned %d orphan(s) before new attach", orphans_pruned)
	end

	-- v0.1.278: skip bayonet attach for cwv_es_musket_old — the custom mesh
	-- already has a fixed bayonet baked into the model.
	local _bid_pre = item_data and item_data.backend_id
	local _is_old_musket = _bid_pre and type(_bid_pre) == "string" and _bid_pre:match("^cwv_es_musket_old")

	if not _is_old_musket then
		-- pcall outer: bayonet failure should never break the equip itself.
		pcall(_attach_musket_bayonets, world, v_w3p, v_w1p)
	end
	-- v0.1.286: cwv_es_musket_old overlay system DELETED. The variant now uses
	-- our custom mesh path as right_hand_unit and the vanilla GearUtils pipeline
	-- spawns it directly. See PackageManager hooks at top of file for the
	-- "Resource not found" workaround, and the .unit files for the
	-- `data.mat_to_use` vanilla-material reference that gives FP rendering.

	-- v0.1.220: in melee mode (musket_template_melee), the polearm
	-- attachment_node_linking holds the rifle perpendicular to its
	-- intended orientation. Apply rotations to correct it. v0.1.226
	-- composes Y barrel-spin + Z. v0.1.227: melee template is back to
	-- Kruber's tuskgor spear (also AttachmentNodeLinking.polearm) so
	-- same correction applies.
	if item_template == Weapons.musket_template_melee then
		-- v0.1.241: per user "rotate along z-axis about 90 degrees more",
		-- bump outermost q_z2 from π to 3π/2 (adds another 90° at the
		-- outermost composition position).
		-- Total composition: `q_z2(3π/2) * q_y(-π/2) * q_z(π/2) * q_x(π)`.
		local q_y  = Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2)
		local q_z  = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi / 2)
		local q_x  = Quaternion.axis_angle(Vector3(1, 0, 0), math.pi)
		local q_z2 = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi * 1.5)
		local q    = Quaternion.multiply(q_z2, Quaternion.multiply(Quaternion.multiply(q_y, q_z), q_x))
		if v_w3p and Unit.alive(v_w3p) then
			pcall(Unit.set_local_rotation, v_w3p, 0, q)
		end
		if v_w1p and Unit.alive(v_w1p) then
			pcall(Unit.set_local_rotation, v_w1p, 0, q)
		end

		-- v0.1.227: per user, scale the rifle DOWN in 1st person ONLY
		-- when in melee mode (3P stays at the type-level scale so other
		-- players see the normal-sized musket-bayonet). Multiply the
		-- existing local scale by the factor below — the type-level
		-- {0.9, 1.35, 0.9} is already applied by the
		-- GearUtils.create_equipment hook by the time we get here.
		-- Reading current scale and multiplying composes correctly
		-- regardless of pre-existing scale.
		-- v0.1.247: per-axis scale factors per user "0.8x and 0.8y"
		-- (Z unchanged). v0.1.265: Y bumped 0.8 → 1.2 per user "make
		-- 1P melee 1.8y" — composes against type-level 1P Y of 1.5 to
		-- give 1.5 * 1.2 = 1.8 for 1P melee. 3P unchanged at 1.35.
		local _MELEE_1P_SCALE_FACTOR = { 0.8, 1.2, 1.0 }  -- TUNABLE per-axis
		if v_w1p and Unit.alive(v_w1p) then
			pcall(function()
				local current = Unit.local_scale(v_w1p, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				local f = _MELEE_1P_SCALE_FACTOR
				Unit.set_local_scale(v_w1p, 0, Vector3(cx * f[1], cy * f[2], cz * f[3]))
			end)
		end

		-- v0.1.229: melee grip height/forward offset. After the rotation
		-- correction the rifle sits too low and slightly back from where
		-- a polearm grip should hold it. Apply a translation delta on
		-- top of vanilla's attachment_node_linking offset (read current
		-- local position, ADD our delta, set back). Compose-friendly so
		-- it doesn't fight the polearm attachment offset.
		--   Y +0.1 — push slightly forward along the rifle's barrel axis
		--   Z -0.3 — drop the grip height
		-- Applied to BOTH 1P and 3P so the held view and other players
		-- see the same pose. TUNABLE constants.
		local _MELEE_LOCAL_OFFSET = { 0, 0.06, -0.3 }
		local function _apply_melee_offset(unit)
			if not unit or not Unit.alive(unit) then return end
			pcall(function()
				local current = Unit.local_position(unit, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				Unit.set_local_position(unit, 0, Vector3(
					cx + _MELEE_LOCAL_OFFSET[1],
					cy + _MELEE_LOCAL_OFFSET[2],
					cz + _MELEE_LOCAL_OFFSET[3]))
			end)
		end
		_apply_melee_offset(v_w3p)
		_apply_melee_offset(v_w1p)
	end

	return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- ============================================================
-- Musket bayonet visibility sync
-- ============================================================
-- VT2's wield system DOESN'T destroy the rifle's units when the player
-- swaps to a different weapon — it just hides them via
-- Unit.set_unit_visibility(rifle, false). The bayonet is a separate
-- World.link_unit'd unit that doesn't inherit the rifle's visibility
-- flag (Stingray links transforms, not visibility), so it stays visible
-- floating in space when the rifle is hidden.
--
-- Fix: track all spawned bayonet pairs in a weak-keyed table. Hook the
-- inventory paths that change wielded state (`_wield_slot` runs whenever
-- the player switches weapons). After each, walk the table and set each
-- bayonet's visibility based on whether its rifle is the currently-
-- wielded weapon. When player wields the rifle: bayonet shows. When they
-- swap to a different slot: bayonet hides.

-- (_musket_bayonet_pairs declared above near the bayonet constants so
-- _attach_musket_bayonets can register entries directly.)

-- Sync visibility of all tracked bayonets based on current wielded state.
-- Also opportunistically destroys ORPHAN bayonets (rifle is dead but
-- bayonet still alive — happens when a code path bypasses our
-- destroy_wielded cleanup hook, e.g. cosmetic application or any
-- equipment refresh that swaps the rifle without firing destroy_wielded).
local function _sync_all_bayonets_visibility(equipment)
	if not equipment then return end
	local wielded_3p = equipment.right_hand_wielded_unit_3p
	local wielded_1p = equipment.right_hand_wielded_unit
	local orphans, shown, hidden = 0, 0, 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			-- Orphan: rifle gone but bayonet lingers. Hide and destroy.
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans = orphans + 1
		elseif Unit.alive(bayonet) then
			local should_show = (rifle == wielded_3p) or (rifle == wielded_1p)
			pcall(Unit.set_unit_visibility, bayonet, should_show)
			if should_show then shown = shown + 1 else hidden = hidden + 1 end
		end
	end
	if orphans + shown + hidden > 0 then
		mod:info("[cwv musket-bayonet] sync: orphans=%d shown=%d hidden=%d", orphans, shown, hidden)
	end
end

-- Hook the wield path. Full wrapper because we need PRE and POST work:
--   PRE  — detect if the outgoing wielded weapon is one of our cwv muskets
--          AND mid-reload. If so, flag item_data so we can cancel the
--          auto-reload-on-wield that vanilla triggers when wielding back.
--   POST — sync bayonet visibility against the new wielded state (existing
--          v0.1.281 behavior), AND if the newly-wielded weapon is a flagged
--          cwv musket that just got auto-reload-on-wield kicked off, abort it.
-- v0.1.305: anti-exploit. User report: empty rifle reload start → swap to
-- melee → swap back → fully reloaded immediately. Root cause: vanilla
-- `SimpleInventoryExtension._wield_slot:2046-2068` auto-starts a reload
-- on wield if ammo_count == 0. The earlier abort_reload (line 1937) of the
-- old reload progress was working, but vanilla's auto-on-wield gave the
-- player a free "instant restart" of the reload that they could complete
-- visually without paying the full reload_time wait. Fix: when our cwv
-- musket was reloading at unwield time, abort the auto-reload-on-wield
-- when re-wielded. Player must press R explicitly to start a fresh reload.
-- v0.1.306: backend_id is stored at `item_data.mod_data.backend_id` for cwv
-- entries (see _build_entry — `entry.mod_data.backend_id = backend_id`).
-- Sometimes vanilla also copies it to `item_data.backend_id` directly
-- (other hooks in this file rely on that), so check BOTH locations.
local function _item_backend_id(item_data)
	if not item_data then return nil end
	local bid = item_data.backend_id
	if type(bid) ~= "string" then
		bid = item_data.mod_data and item_data.mod_data.backend_id
	end
	return type(bid) == "string" and bid or nil
end

mod:hook("SimpleInventoryExtension", "_wield_slot", function(orig, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
	-- PRE — detect unwield-of-reloading-cwv-musket.
	local outgoing_unit = equipment.right_hand_wielded_unit
	if outgoing_unit and Unit.alive(outgoing_unit) and ScriptUnit.has_extension(outgoing_unit, "ammo_system") then
		local outgoing_slot = equipment.wielded_slot
		local outgoing_slot_data = outgoing_slot and equipment.slots[outgoing_slot]
		local outgoing_item_data = outgoing_slot_data and outgoing_slot_data.item_data
		local outgoing_bid = _item_backend_id(outgoing_item_data)
		if outgoing_bid and outgoing_bid:match("^cwv_es_musket") then
			local ammo_ext = ScriptUnit.extension(outgoing_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				outgoing_item_data.mod_data = outgoing_item_data.mod_data or {}
				outgoing_item_data.mod_data.cwv_musket_reload_interrupted = true
			end
		end
	end

	-- Run vanilla. Vanilla aborts the outgoing reload (clean) AND triggers
	-- auto-reload-on-wield for the incoming weapon if its clip is empty.
	local result = orig(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)

	-- POST — cancel the auto-reload-on-wield for flagged cwv musket items.
	local incoming_item_data = slot_data and slot_data.item_data
	local incoming_bid = _item_backend_id(incoming_item_data)
	if incoming_bid and incoming_bid:match("^cwv_es_musket")
			and incoming_item_data.mod_data
			and incoming_item_data.mod_data.cwv_musket_reload_interrupted then
		-- One-shot flag: clear after handling so a future manual reload works.
		incoming_item_data.mod_data.cwv_musket_reload_interrupted = nil
		local incoming_unit = equipment.right_hand_wielded_unit
		if incoming_unit and Unit.alive(incoming_unit) and ScriptUnit.has_extension(incoming_unit, "ammo_system") then
			local ammo_ext = ScriptUnit.extension(incoming_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				pcall(function() ammo_ext:abort_reload() end)
			end
		end
	end

	-- POST — bayonet visibility sync (v0.1.281 behavior, preserved).
	_sync_all_bayonets_visibility(self._equipment or equipment)

	-- v0.1.322: hide the duplicated 3P offhand spare boar spear for cwv
	-- javelin variants. Vanilla _wield_slot (simple_inventory_extension.lua:2153)
	-- sets ammo_unit_3p visible when the weapon is wielded. For our javelin
	-- the IML's `left_hand_unit` AND the resolved `ammo_unit` both point
	-- at the boar spear (per v0.1.314 revert — keeping ammo_unit on the
	-- held mesh is mandatory for projectile/pickup paths). Result: 3P
	-- renders two boar spears (held + spare offhand). We can't blank
	-- ammo_unit on the data table without breaking the ammo paths, so we
	-- runtime-hide the spawned 3P instance instead. 1P offhand left alone.
	local js_bid = _item_backend_id(slot_data and slot_data.item_data)
	if js_bid and (js_bid:match("^cwv_es_javelin_") or js_bid:match("^cwv_wh_javelin_")) then
		if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
		end
		if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
		end
	end

	return result
end)

-- v0.1.263: hook FP/3P camera-mode toggle methods. When player switches
-- between first-person and third-person view, vanilla toggles the
-- relevant rifle units' visibility — but `World.link_unit` doesn't
-- propagate visibility to children, so the linked bayonet keeps
-- rendering in BOTH cameras (visible from 3P even though 1P rifle is
-- hidden). User reported this as a "floating dagger" in third-person
-- view. Now the bayonet's visibility mirrors its parent rifle's
-- per-camera state.
mod:hook_safe("SimpleInventoryExtension", "show_first_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_1p = equipment.right_hand_wielded_unit
	if rifle_1p and Unit.alive(rifle_1p) then
		local bayonet = _musket_bayonet_pairs[rifle_1p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end
end)

mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_3p = equipment.right_hand_wielded_unit_3p
	if rifle_3p and Unit.alive(rifle_3p) then
		local bayonet = _musket_bayonet_pairs[rifle_3p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end

	-- v0.1.322: re-hide cwv javelin 3P spare boar spear when the engine
	-- toggles 3P inventory visibility to true (camera switch, level start).
	-- Without this, the _wield_slot-time hide is undone on every FP→3P
	-- camera flip. show=false naturally hides everything, no work needed.
	if show then
		local wielded_slot = equipment.wielded_slot
		local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
		local item_data = slot_data and slot_data.item_data
		local bid = _item_backend_id(item_data)
		if bid and (bid:match("^cwv_es_javelin_") or bid:match("^cwv_wh_javelin_")) then
			if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
			end
			if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
			end
		end
	end
end)

-- Cleanup: when the rifle is destroyed (weapon swap, holster, level end),
-- destroy any bayonet linked to it. Run BEFORE vanilla so we still have a
-- live unit handle to read get_data from.
mod:hook("GearUtils", "destroy_wielded", function(func, world, wielded_unit)
	if wielded_unit and Unit.alive(wielded_unit) then
		-- Also clear any tracking entry to avoid using a dead key.
		_musket_bayonet_pairs[wielded_unit] = nil
		_detach_musket_bayonet(world, wielded_unit)
		-- v0.1.293: destroy Old Musket FX-proxy (hidden vanilla rifle) when
		-- our custom mesh is destroyed.
		if _destroy_old_musket_fx_proxy then
			_destroy_old_musket_fx_proxy(wielded_unit)
		end
	end
	return func(world, wielded_unit)
end)

-- ============================================================
-- cwv_es_musket_old — LA-pattern PackageManager hooks
-- ============================================================
-- v0.1.286: completely replaced the v0.1.277-285 overlay system with the
-- Loremaster's Armoury pattern. Our custom mesh path IS the variant's
-- right_hand_unit; vanilla GearUtils spawns it directly, which means the
-- mesh gets the engine's first-person rendering pipeline for free (no
-- shadow in FP, correct depth, draws under the FP hand model).
--
-- The .unit file references a VANILLA material via `data.mat_to_use`,
-- so the spawned mesh uses an existing vanilla 1P/3P material that has
-- the FP rendering shader baked in. See LA's utils/hooks.lua for the
-- prior art that informed this pattern.
--
-- The two hooks below intercept the engine's package_manager.load /
-- unload / has_loaded calls. When the engine tries to package-load our
-- custom unit path (which has no sibling .package file), we silently
-- no-op (load/unload) or report success (has_loaded). The unit data is
-- already in our master bundle via the unit-glob, so the engine can
-- still find it for World.spawn_unit + GearUtils linking.
--
-- v0.1.271-276 had this same crash; the early "fix" attempts (sibling
-- packages, .mod packages list, etc.) all failed because the engine's
-- global Application.resource_package only finds vanilla bundles. The
-- LA pattern avoids the lookup entirely by hooking before it runs.

local _LA_PATTERN_CUSTOM_PACKAGES = {
	["units/cwv_es_musket_custom/cwv_es_musket_custom"]    = true,
	["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = true,
}

mod:hook(PackageManager, "load", function(func, self, package_name, reference_name, callback, asynchronous, prioritize)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return end
	return func(self, package_name, reference_name, callback, asynchronous, prioritize)
end)

mod:hook(PackageManager, "unload", function(func, self, package_name, reference_name)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return end
	return func(self, package_name, reference_name)
end)

mod:hook(PackageManager, "has_loaded", function(func, self, package_name, reference_name)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return true end
	return func(self, package_name, reference_name)
end)

-- v0.1.287: register custom-mesh unit paths in NetworkLookup.inventory_packages.
-- The engine syncs equip events across multiplayer via this table — when our
-- custom right_hand_unit is equipped, the engine indexes `inventory_packages`
-- by our path. That table has a strict __index that errors on unknown keys
-- (see feedback_vt2_strict_lookup_rawget.md). LA's solution: alias our path
-- to an existing vanilla path's network index (forward direction only — we
-- do NOT overwrite the reverse index->path mapping like LA's skin-replacement
-- code does, because we don't want to hijack vanilla equip events).
-- Crash trail: v0.1.286 — "Table inventory_packages does not contain key:
-- units/cwv_es_musket_custom/cwv_es_musket_custom_3p" on equip.
do
	local nl_inventory = NetworkLookup and NetworkLookup.inventory_packages
	if nl_inventory then
		local vanilla_1p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1")
		local vanilla_3p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p")
		if vanilla_1p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom"] = vanilla_1p_idx
		end
		if vanilla_3p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = vanilla_3p_idx
		end
	end
end

-- ============================================================
-- cwv_es_musket_old — runtime texture binding + live-tunable transforms
-- ============================================================
-- Defined as GLOBAL (no `local`) so the spawn_inventory_unit hook above
-- (which is parsed before this code) can reach them at call time. Locals
-- are resolved at parse time and wouldn't be visible — see
-- feedback_lua_forward_reference.md.

-- Mutable transform constants. Edit via `cwv_om_pos_*` / `om_rot_*` /
-- `om_scale_*` commands. Split into three buckets:
--   1P RANGED — musket_template (rifle stance)
--   1P MELEE  — musket_template_melee (polearm stance) [TBD]
--   3P        — both modes share (works at identity per v0.1.295 user feedback)
-- v0.1.295 defaults for 1P ranged from user tune: pos (0, 0.62, 0),
-- rot axis (1,1,-1) @ -90°, scale (1, 1.2, 1.4).
-- v0.1.297: rotation state is now a QuaternionBox (or nil for identity). The
-- previous `{ax, ay, az, radians}` axis-angle table couldn't represent
-- composed rotations (e.g., diagonal axis-angle + an additional barrel-roll).
-- Quaternions compose via `Quaternion.multiply(q1, q2)` so the new
-- `cwv_om_rotmul_*` commands can stack rotations on top of whatever's
-- currently applied.
-- v0.1.298: WRAP in `QuaternionBox(...)`. Stingray's raw Quaternion type is
-- a stack-allocated temporary — valid only within the frame it was created.
-- Storing the raw value in a Lua global makes it stale across frames (the
-- memory gets recycled by other Quaternion temporaries). v0.1.297 stored
-- raw Quaternions; the gun appeared correct on first frame after equip but
-- then the rotation became garbage as the temp slot was reused. Vanilla
-- pattern (e.g., `bt_attack_action.lua:99`): `QuaternionBox(rotation)` to
-- box for long-term storage, `:unbox()` to get a fresh raw Quaternion when
-- you need to pass it to an API that wants a raw value.
-- Defaults for 1P-RANGED match v0.1.295 user-tuned values.
_CWV_OLD_MUSKET_POS_1P_RANGED   = { 0, 0.62, 0 }
_CWV_OLD_MUSKET_ROT_1P_RANGED   = QuaternionBox(Quaternion.axis_angle(Vector3(1, 1, -1), -math.pi / 2))
_CWV_OLD_MUSKET_SCALE_1P_RANGED = { 1, 1.2, 1.4 }

-- v0.1.299 1P MELEE defaults from user live-tune: pos (0, 0.06, 0),
-- rot axis (0, 1, 0) @ -90° (pure Y-axis rotation), scale identity.
_CWV_OLD_MUSKET_POS_1P_MELEE   = { 0, 0.06, 0 }
_CWV_OLD_MUSKET_ROT_1P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_CWV_OLD_MUSKET_SCALE_1P_MELEE = { 1, 1, 1 }

-- v0.1.318: 3P split into _RANGED / _MELEE.
-- v0.1.320: final tuned values from user live-tune:
--   3P-RANGED — pos (0, 0.64, -0.01), rot Euler XYZ (-90, -90, 0), scale (1, 1.1, 1.1)
--   3P-MELEE  — pos (0, 0.045, 0.1) (unchanged from v0.1.318), rot (0, 1, 0) @ -90°
--               (unchanged), scale (1, 1.1, 1.1) (matched to 3P-RANGED per user
--               "do the same scaling for melee as well")
_CWV_OLD_MUSKET_POS_3P_RANGED   = { 0, 0.64, -0.01 }
_CWV_OLD_MUSKET_ROT_3P_RANGED   = QuaternionBox(Quaternion.from_euler_angles_xyz(-90, -90, 0))
_CWV_OLD_MUSKET_SCALE_3P_RANGED = { 1, 1.1, 1.1 }

_CWV_OLD_MUSKET_POS_3P_MELEE   = { 0, 0.045, 0.1 }
_CWV_OLD_MUSKET_ROT_3P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_CWV_OLD_MUSKET_SCALE_3P_MELEE = { 1, 1.1, 1.1 }

-- Weak-keyed tracking sets — one per (perspective × mode) bucket.
_CWV_OLD_MUSKET_UNITS_1P_RANGED = setmetatable({}, { __mode = "k" })
_CWV_OLD_MUSKET_UNITS_1P_MELEE  = setmetatable({}, { __mode = "k" })
_CWV_OLD_MUSKET_UNITS_3P_RANGED = setmetatable({}, { __mode = "k" })
_CWV_OLD_MUSKET_UNITS_3P_MELEE  = setmetatable({}, { __mode = "k" })

_track_old_musket_unit = function(unit, perspective, mode)
	if not unit or not Unit.alive(unit) then return end
	if perspective == "1p" then
		if mode == "melee" then
			_CWV_OLD_MUSKET_UNITS_1P_MELEE[unit] = true
		else
			_CWV_OLD_MUSKET_UNITS_1P_RANGED[unit] = true
		end
	else
		if mode == "melee" then
			_CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = true
		else
			_CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = true
		end
	end
end

_apply_old_musket_textures = function(unit)
	if not unit or not Unit.alive(unit) then return end
	local ok, num_meshes = pcall(Unit.num_meshes, unit)
	if not ok or not num_meshes then return end
	for i = 0, num_meshes - 1 do
		local mok, mesh = pcall(Unit.mesh, unit, i)
		if mok and mesh then
			local nok, num_mats = pcall(Mesh.num_materials, mesh)
			if nok and num_mats then
				for j = 0, num_mats - 1 do
					local matok, mat = pcall(Mesh.material, mesh, j)
					if matok and mat then
						pcall(Material.set_texture, mat, "texture_map_c0ba2942", "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo")
						pcall(Material.set_texture, mat, "texture_map_59cd86b9", "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal")
						pcall(Material.set_texture, mat, "texture_map_0205ba86", "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic")
					end
				end
			end
		end
	end
end

_apply_old_musket_transform = function(unit, perspective, mode)
	if not unit or not Unit.alive(unit) then return end
	local pos, rot, scale
	if perspective == "1p" then
		if mode == "melee" then
			pos, rot, scale = _CWV_OLD_MUSKET_POS_1P_MELEE, _CWV_OLD_MUSKET_ROT_1P_MELEE, _CWV_OLD_MUSKET_SCALE_1P_MELEE
		else
			pos, rot, scale = _CWV_OLD_MUSKET_POS_1P_RANGED, _CWV_OLD_MUSKET_ROT_1P_RANGED, _CWV_OLD_MUSKET_SCALE_1P_RANGED
		end
	else
		if mode == "melee" then
			pos, rot, scale = _CWV_OLD_MUSKET_POS_3P_MELEE, _CWV_OLD_MUSKET_ROT_3P_MELEE, _CWV_OLD_MUSKET_SCALE_3P_MELEE
		else
			pos, rot, scale = _CWV_OLD_MUSKET_POS_3P_RANGED, _CWV_OLD_MUSKET_ROT_3P_RANGED, _CWV_OLD_MUSKET_SCALE_3P_RANGED
		end
	end
	pcall(Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3]))
	-- rot is a QuaternionBox (or nil for identity); see v0.1.298 note.
	-- Unbox to get a fresh raw Quaternion for the API call.
	pcall(Unit.set_local_rotation, unit, 0, rot and rot:unbox() or Quaternion.identity())
	pcall(Unit.set_local_scale, unit, 0, Vector3(scale[1], scale[2], scale[3]))
end

-- v0.1.293 approach A: spawn a hidden vanilla rifle alongside our custom mesh
-- so sound/VFX actions (which look up named nodes like "fx_muzzle" / "j_hammer"
-- on the weapon unit) can find them. The vanilla rifle's flow events + FX
-- emission points are baked into its compiled .unit; our custom mesh has none.
-- We hide the vanilla rifle (visibility=false), link it to our mesh, and proxy
-- Unit.node/Unit.has_node lookups so any action calling
-- `Unit.node(our_mesh, "fx_muzzle")` gets the vanilla rifle's node back.
-- Result: muzzle flash, smoke, sound, casing-eject all emit from the right
-- world position (our mesh's hand-attached position, since the proxy is
-- linked) while only our custom mesh renders.
_CWV_OLD_MUSKET_FX_PROXY = setmetatable({}, { __mode = "k" })  -- our_unit -> proxy_unit

_spawn_old_musket_fx_proxy = function(world, our_unit, vanilla_path, owner_unit, owner_hand_node_name)
	if not our_unit or not Unit.alive(our_unit) then
		mod:info("[cwv old-musket fx] our_unit invalid; skip proxy for %s", vanilla_path)
		return
	end
	if not Managers.state or not Managers.state.unit_spawner then
		mod:info("[cwv old-musket fx] unit_spawner not available; skip proxy")
		return
	end
	-- v0.1.296: link the proxy directly to the player's hand-attach bone
	-- rather than to our_unit's root. Why: our visible mesh has a rotation
	-- (e.g., axis (1,1,-1) @ -90° for 1P-ranged) that re-orients the gun to
	-- align with the player's grip. If the proxy inherits that rotation,
	-- its "fx_muzzle" node ends up pointing toward the camera/stomach
	-- instead of forward, so muzzle flash + bullet trail spawn at weird
	-- locations. By linking the proxy to the same bone vanilla rifle would
	-- link to, the proxy gets vanilla's natural pose — muzzle ends up where
	-- a vanilla empire-handgun's muzzle would be (in front of hand). That
	-- matches what the player visually expects regardless of how our
	-- visible mesh is reoriented.
	-- Falls back to linking to our_unit's root if the player unit + node
	-- aren't available (defensive only — they should always be present
	-- when called from the spawn_inventory_unit hook).
	local ok, proxy = pcall(function()
		return Managers.state.unit_spawner:spawn_local_unit(vanilla_path, Vector3(0, 0, 0), Quaternion.identity())
	end)
	if not ok or not proxy then
		mod:warning("[cwv old-musket fx] spawn proxy failed for %s: %s", vanilla_path, tostring(proxy))
		return
	end
	local linked_to = "fallback(our_unit root)"
	local lok = false
	if owner_unit and Unit.alive(owner_unit) and owner_hand_node_name and Unit.has_node(owner_unit, owner_hand_node_name) then
		local hand_idx = Unit.node(owner_unit, owner_hand_node_name)
		lok = pcall(World.link_unit, world, proxy, 0, owner_unit, hand_idx)
		linked_to = string.format("owner_unit %s.%s(idx=%d)", tostring(owner_unit), owner_hand_node_name, hand_idx)
	else
		lok = pcall(World.link_unit, world, proxy, 0, our_unit, 0)
	end
	-- Reset proxy's local transform so it sits exactly at the link parent's
	-- node. Without this the proxy retains its spawn-time pose relative to
	-- the new parent, which can shift its node offsets in world space.
	pcall(Unit.set_local_position, proxy, 0, Vector3(0, 0, 0))
	pcall(Unit.set_local_rotation, proxy, 0, Quaternion.identity())
	pcall(Unit.set_local_scale, proxy, 0, Vector3(1, 1, 1))
	local vok = pcall(Unit.set_unit_visibility, proxy, false)
	_CWV_OLD_MUSKET_FX_PROXY[our_unit] = proxy
	mod:info("[cwv old-musket fx] proxy spawned: path=%s linked_to=%s link_ok=%s vis_ok=%s",
		vanilla_path, linked_to, tostring(lok), tostring(vok))
end

_destroy_old_musket_fx_proxy = function(our_unit)
	local proxy = _CWV_OLD_MUSKET_FX_PROXY[our_unit]
	if proxy and Unit.alive(proxy) then
		if Managers and Managers.state and Managers.state.unit_spawner then
			pcall(function() Managers.state.unit_spawner:mark_for_deletion(proxy) end)
		end
	end
	_CWV_OLD_MUSKET_FX_PROXY[our_unit] = nil
end

-- Proxy Unit.node lookups: when called on our custom mesh and the requested
-- name doesn't resolve on it, redirect to the linked vanilla rifle. has_node
-- returns true if either has the node. Hooks are global (every Unit.node call
-- in the game routes through), but the proxy-table lookup is a cheap weak-
-- table read.
-- Capture the pre-hook Unit.has_node BEFORE installing any hooks so the
-- Unit.node hook can probe our mesh without invoking its own hook chain.
local _orig_unit_has_node = Unit.has_node
mod:hook(Unit, "node", function(orig, unit, name)
	local proxy = _CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) and not _orig_unit_has_node(unit, name) then
		return orig(proxy, name)
	end
	return orig(unit, name)
end)
mod:hook(Unit, "has_node", function(orig, unit, name)
	local proxy = _CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(unit, name) or orig(proxy, name)
	end
	return orig(unit, name)
end)

-- v0.1.294: flow events drive most weapon FX in VT2 (muzzle flash, smoke,
-- bullet trail, casing eject, dry-fire click — all baked into the rifle's
-- compiled .unit as flow graph nodes triggered by named events fired from
-- Lua action code like ActionHandgun:line 194 `Unit.flow_event(weapon_unit,
-- "lua_bullet_trail")`). Our custom mesh has no flow graph, so firing on it
-- no-ops. Redirect to the proxy (which has the full vanilla flow graph).
-- Same proxy-table-lookup pattern as Unit.node hook above.
mod:hook(Unit, "flow_event", function(orig, unit, event_name)
	local proxy = _CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, event_name)
	end
	return orig(unit, event_name)
end)
-- Flow VARIABLES seed values that flow graph nodes read (e.g. "hit_position"
-- on line 192 of action_handgun.lua). Redirect to proxy for the same reason.
mod:hook(Unit, "set_flow_variable", function(orig, unit, name, value)
	local proxy = _CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, name, value)
	end
	return orig(unit, name, value)
end)

_reapply_old_musket_transforms_all = function()
	local n_1p_r, n_1p_m = 0, 0
	for unit in pairs(_CWV_OLD_MUSKET_UNITS_1P_RANGED) do
		if Unit.alive(unit) then
			_apply_old_musket_transform(unit, "1p", "ranged"); n_1p_r = n_1p_r + 1
		else
			_CWV_OLD_MUSKET_UNITS_1P_RANGED[unit] = nil
		end
	end
	for unit in pairs(_CWV_OLD_MUSKET_UNITS_1P_MELEE) do
		if Unit.alive(unit) then
			_apply_old_musket_transform(unit, "1p", "melee"); n_1p_m = n_1p_m + 1
		else
			_CWV_OLD_MUSKET_UNITS_1P_MELEE[unit] = nil
		end
	end
	local n_3p_r, n_3p_m = 0, 0
	for unit in pairs(_CWV_OLD_MUSKET_UNITS_3P_RANGED) do
		if Unit.alive(unit) then
			_apply_old_musket_transform(unit, "3p", "ranged"); n_3p_r = n_3p_r + 1
		else
			_CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = nil
		end
	end
	for unit in pairs(_CWV_OLD_MUSKET_UNITS_3P_MELEE) do
		if Unit.alive(unit) then
			_apply_old_musket_transform(unit, "3p", "melee"); n_3p_m = n_3p_m + 1
		else
			_CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = nil
		end
	end
	mod:echo("[cwv old-musket] reapplied to %d 1P-r + %d 1P-m + %d 3P-r + %d 3P-m unit(s)", n_1p_r, n_1p_m, n_3p_r, n_3p_m)
end

-- v0.1.290: filter attachment_node_linking entries that reference skeleton
-- nodes not present on our custom mesh. The vanilla empire-rifle template's
-- `AttachmentNodeLinking.rifles.first_person.wielded` links 4 player-side
-- hand-component bones to 4 weapon-side rig nodes (j_lock, j_hammer,
-- j_trigger, plus node 0). Our FBX has no skeleton (just mesh geometry),
-- so the engine's `Unit.node(target, "j_lock")` call in `GearUtils.link_units`
-- crashes with `[Script Error]: j_lock`. Filter: keep entries whose target
-- is a node-index (always 0 = root, safe on any unit) or whose named target
-- actually resolves; drop the rest. The root link is what physically
-- attaches the weapon to the hand — the others are decorative finger-pose
-- attachments that only matter for vanilla rifles with the full rig.
mod:hook("GearUtils", "link_units", function(orig, world, attachment_node_linking, link_table, source, target)
	if not target then return orig(world, attachment_node_linking, link_table, source, target) end
	-- v0.1.291: `Unit.has_node` returns a boolean — verified used in vanilla
	-- ai_bot_group_system.lua:190 and similar. The v0.1.290 attempt used
	-- `pcall(Unit.node, ...)`, but Stingray's Unit.node throws an error that
	-- pcall doesn't catch (engine-level fatal, not a Lua error). has_node
	-- is the correct safe-existence API.
	for _, entry in ipairs(attachment_node_linking) do
		local tgt = entry.target
		if type(tgt) == "string" and not Unit.has_node(target, tgt) then
			-- Found a missing node — filter the whole table.
			local safe = {}
			for _, e in ipairs(attachment_node_linking) do
				local t = e.target
				if type(t) ~= "string" or Unit.has_node(target, t) then
					safe[#safe + 1] = e
				end
			end
			return orig(world, safe, link_table, source, target)
		end
	end
	return orig(world, attachment_node_linking, link_table, source, target)
end)

-- ============================================================
-- Tuskgor Javelin template (modified javelin_template)
-- 15 max ammo, no auto-catch reload, ammo pickups refill, 2x damage, 0.5x speed
--
-- ANIM ADDENDUM: this template clone is shared across Kruber and Saltzpyre
-- variants (cwv_es_javelin / cwv_wh_javelin). 1P animations are universal —
-- the 1P state machine and clips reference shared first_person_base assets
-- and play correctly on every character without intervention. Only 3P body
-- anims need cross-character work, via anim_event_3p / wield_anim_3p /
-- wield_anim_career_3p. See top-of-file ANIMATION ARCHITECTURE.
-- ============================================================
--
-- Differs from the longsword/sword+shield clones in two important ways:
--
-- 1. Ammo system: vanilla javelin uses `unique_ammo_type=true` + a custom
--    auto-replenish action (`weapon_reload.default` with `kind="catch"`) that
--    magically refills the player's javelin stack to max whenever they're
--    below it. We override `condition_func`/`chain_condition_func` to always
--    return false, which keeps the action defined for state-machine/network
--    purposes but prevents it from ever firing — turning the weapon into a
--    finite-stack thrown weapon. Combined with `block_ammo_pickup=false` and
--    `unique_ammo_type=false`, vanilla ammo crates refill it like any other
--    Kruber ranged weapon (handgun/blunderbuss/longbow style).
--
-- 2. Damage profile shape: the throw projectile uses `thrown_javelin`, which
--    is an INLINE damage profile (`default_target.power_distribution_near.attack`
--    is a literal number) — NOT the PowerLevelTemplates string-key indirection
--    used by melee weapons. The shared `_clone_damage_profile` helper assumes
--    the string-key shape, so we use a dedicated `_clone_inline_throw_profile`
--    for the throw and reuse `_clone_damage_profile` for the melee stab
--    sub-actions (which DO use the string-key shape).
--
-- The "half speed" axis multiplies `total_time` and `minimum_hold_time` on
-- `kind="thrown_projectile"` sub-actions, plus `attack_meta_data.minimum_charge_time`
-- (the wind-up). Most javelin sub-actions don't carry `anim_time_scale`, so
-- the longsword-style anim_time_scale multiplication is mostly a no-op here —
-- timing fields are the actual lever.

local _TJ_DAMAGE_MULT          = 2.0
local _TJ_SPEED_MULT           = 0.5   -- action speed: half = 2x wind-up + recovery duration
local _TJ_PROJECTILE_SPEED_MULT = 0.9  -- in-flight projectile velocity (sub_action.speed) — slower than vanilla javelin
local _TJ_MAX_AMMO             = 10

-- Custom projectile + pickup keys (registered below). Variant defs reference
-- these via projectile_units_template / pickup_template_name /
-- link_pickup_template_name, which the skin registration mirrors onto the
-- weapon skin entry so the engine resolves them at projectile spawn time.
local _TJ_PROJECTILE_KEY        = "cwv_tuskgor_javelin"
local _TJ_PICKUP_KEY            = "cwv_tuskgor_javelin_pickup"
local _TJ_LINK_PICKUP_KEY       = "cwv_tuskgor_javelin_link_pickup"
-- Pickup + in-flight unit selection.
--
-- v0.1.73 split the in-flight unit (boar spear) from the pickup unit (elf
-- javelin prj_*_3ps), with the rationale that the elf javelin had verified
-- physics + correct axes for pickup spawn while the held boar spear _3p
-- might lack those.
--
-- v0.1.118 reverts to using the boar spear _3p for BOTH paths, because:
--   * The elf javelin _3ps unit is in the woods DLC's per-weapon package,
--     which is loaded with the elf's `we_javelin` inventory entry — but
--     OUR cwv_es_javelin item declares the boar spear in left_hand_unit/
--     right_hand_unit, so the package loader never queues the elf javelin
--     unit for our equipped variant. Result: `World.spawn_unit` crashes
--     when the engine tries to spawn the unloaded prj_we_javelin_01_3ps
--     pickup unit (crash GUID b7936944).
--   * The mod-tools compiler doesn't ship DLC units locally, so we can't
--     reference the elf javelin in our resource_packages/.package file.
--   * The boar spear _3p IS reliably loaded (it's our held mesh).
--
-- Trade-off: the boar spear may have weak physics for pickup interaction
-- and wrong local axes (hand-attachment), so v0.1.71's symptoms (no F/E
-- prompt + 90° rotation off) may resurface. But those are now actually
-- diagnosable since the link_pickup branch is finally engaged. We can
-- iterate from there with rotation hooks and see if pickup interaction
-- actually works with the held mesh.
local _TJ_BOAR_SPEAR_UNIT       = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p"
-- v0.1.164: carrier-unit pattern. Probe data (v0.1.137 dump) confirmed the
-- boar spear _3p has 0 actors while pup_dw_thrown_axe_01_t1 has 3. Without
-- actors the interactor's aim raycast finds nothing → no E-prompt. Use the
-- throwing axe pup as the actual spawn unit (real interaction collision)
-- and attach the boar spear visually as a child via World.link_unit at
-- extensions_ready time. Player sees boar spear, interacts with throwing
-- axe collision underneath. Force-loaded via Managers.package:load() at
-- mod init since base inventory doesn't queue the pup package.
local _TJ_THROWING_AXE_PUP      = "units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1"
local _TJ_PICKUP_UNIT           = _TJ_THROWING_AXE_PUP
-- v0.1.314: REVERTED v0.1.258 / v0.1.263's pull-back fix. The
-- `pos - Quaternion.forward(rot) * offset` math along the spear's forward
-- axis didn't visibly change stuck-javelin depth — see TODO in
-- character_weapon_variants/TODO.md. Constant kept at 0 so the math
-- branch is a no-op; the spawn position equals the parent's pose
-- exactly. Real fix is unknown — likely the parent unit's rotation
-- doesn't have its forward axis aligned with the spear's pointing
-- direction (so `Quaternion.forward(rot)` is the wrong axis), or the
-- parent isn't at the contact point we assume.
local _TJ_VISUAL_PULL_BACK_M    = 0

local function _register_tuskgor_javelin_assets()
	-- 1. Projectile unit — controls the in-flight + stuck mesh when the throw
	-- action's `use_weapon_skin = true` resolves to our skin's
	-- projectile_units_template = _TJ_PROJECTILE_KEY.
	if not ProjectileUnits then
		mod:warning("ProjectileUnits global missing — projectile/pickup model swap unavailable")
		return
	end
	if not ProjectileUnits[_TJ_PROJECTILE_KEY] then
		ProjectileUnits[_TJ_PROJECTILE_KEY] = {
			dummy_linker_unit_name = _TJ_BOAR_SPEAR_UNIT,
			projectile_unit_name   = _TJ_BOAR_SPEAR_UNIT,
		}
		if NetworkLookup and NetworkLookup.projectile_units
			and not rawget(NetworkLookup.projectile_units, _TJ_PROJECTILE_KEY)
		then
			local tbl = NetworkLookup.projectile_units
			local idx = #tbl + 1
			rawset(tbl, idx, _TJ_PROJECTILE_KEY)
			rawset(tbl, _TJ_PROJECTILE_KEY, idx)
		end
		mod:info("Registered ProjectileUnits.%s -> %s", _TJ_PROJECTILE_KEY, _TJ_BOAR_SPEAR_UNIT)
	end

	-- 1b. Husk lookup injection — required for non-link pickup spawn path.
	-- PlayerProjectileUnitExtension._spawn_pickup_projectile (player_projectile_unit_extension.lua:1382)
	-- looks up `NetworkLookup.husks[pickup_unit_name]` before sending the spawn
	-- RPC. The boar spear's `_3p` unit was never registered as husk-spawnable
	-- (anvil_common_settings.lua:8-18 declares the throwing axe's pup_/prj_/_3p
	-- variants in `husk_lookup`, but the boar spear only got the held _3p
	-- declaration in anvil_equipment_settings.lua's player_units list — that
	-- list doesn't feed into NetworkLookup.husks). Without this injection,
	-- throws that take the non-link path (friendly hits, shields, certain
	-- terrain with allow_link=false) crash with the "Table husks does not
	-- contain key" error from network_lookup.lua's __index metamethod.
	-- v0.1.71 hit this crash on the very first thrown javelin.
	if NetworkLookup and NetworkLookup.husks
		and not rawget(NetworkLookup.husks, _TJ_BOAR_SPEAR_UNIT)
	then
		local tbl = NetworkLookup.husks
		local idx = #tbl + 1
		rawset(tbl, idx, _TJ_BOAR_SPEAR_UNIT)
		rawset(tbl, _TJ_BOAR_SPEAR_UNIT, idx)
		mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_BOAR_SPEAR_UNIT, idx)
	end

	-- 1c. Throwing axe pup unit force-load + husks injection.
	-- Carrier-unit pattern (v0.1.164): the boar spear has 0 actors so the
	-- interactor can't detect aim hits on it. The throwing axe pup unit has
	-- 3 actors (verified via cwv_probe_unit). Use the throwing axe pup as
	-- the actual spawned pickup, attach the boar spear visually as a child
	-- in the extensions_ready hook below.
	-- The pup unit isn't loaded by base inventory (only loads when Bardin
	-- equips throwing axes AND throws one). Force-load via the same API
	-- vanilla pickup_package_loader uses (`Managers.package:load(unit_path,
	-- ref, nil, async, prioritize)`), reference at pickup_package_loader.lua:191.
	if Managers and Managers.package then
		local ok, err = pcall(function()
			Managers.package:load(_TJ_THROWING_AXE_PUP, "cwv_throwing_axe_pup", nil, true, true)
		end)
		if ok then
			mod:info("Force-loaded throwing axe pup unit: %s", _TJ_THROWING_AXE_PUP)
		else
			mod:warning("Failed to force-load throwing axe pup: %s", tostring(err))
		end
	end
	if NetworkLookup and NetworkLookup.husks
		and not rawget(NetworkLookup.husks, _TJ_THROWING_AXE_PUP)
	then
		local tbl = NetworkLookup.husks
		local idx = #tbl + 1
		rawset(tbl, idx, _TJ_THROWING_AXE_PUP)
		rawset(tbl, _TJ_THROWING_AXE_PUP, idx)
		mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_THROWING_AXE_PUP, idx)
	end

	-- 2. Pickup templates — define ground pickup + linked-pickup (stuck variant).
	-- Modeled after anvil_pickup_settings.lua's throwing_axe pickups, but the
	-- can_interact / outline checks query for ammo_type "throwing_javelin"
	-- (vanilla javelin's ammo_type, which we kept on tuskgor_javelin_template)
	-- so only players wielding our javelin can pick these up — and any actual
	-- elf carrying we_javelin would also see them, which is fine since they
	-- share the ammo_type.
	if not Pickups or not Pickups.ammo then
		mod:warning("Pickups.ammo missing — link_pickup behavior unavailable")
		return
	end
	if not Pickups.ammo[_TJ_PICKUP_KEY] then
		local function _can_interact(interactor_unit, _interactable_unit, _data)
			local inv = ScriptUnit.has_extension(interactor_unit, "inventory_system")
			local result = inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
			mod:info("[cwv stick] can_interact_func -> %s (inv=%s)", tostring(result), tostring(inv ~= nil))
			return result
		end
		local function _outline_available(local_player_unit)
			local inv = ScriptUnit.has_extension(local_player_unit, "inventory_system")
			return inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
		end
		local function _on_pick_up(_world, _interactor_unit, _is_server, interactable_unit)
			mod:info("[cwv stick] on_pick_up_func fired")
			local peer_id = Network.peer_id()
			local pickup_system = Managers.state.entity:system("pickup_system")
			pickup_system:delete_limited_owned_pickup_unit(peer_id, interactable_unit)
		end
		local base = {
			ammo_kind            = "thrown",
			consumable_item      = true,
			debug_pickup_category = "throwing_weapons",
			hud_description      = "cwv_interaction_ammunition_javelin",  -- v0.1.183: own loc string (was "interaction_ammunition_axe" — wrong text)
			local_pickup_sound   = true,
			only_once            = true,
			outline_distance     = "small_pickup",
			pickup_sound_event   = "pickup_ammo",
			refill_amount        = 1,
			spawn_weighting      = 1e-06,
			type                 = "ammo",
			can_interact_func    = _can_interact,
			outline_available_func = _outline_available,
			on_pick_up_func      = _on_pick_up,
		}
		-- v0.1.118: unit_name = boar spear _3p for both variants (held mesh
		-- is reliably loaded for our cwv weapon, unlike the elf javelin
		-- prj_*_3ps which is in the woods DLC's per-weapon package).
		-- v0.1.119: unit_template_name = "limited_owned_pickup_unit" for BOTH
		-- variants (was "limited_owned_pickup_projectile_unit" for the
		-- non-link/dropped variant). The "_projectile_unit" template requires
		-- the unit to have a physics actor named "throw" for bouncy ground
		-- pickup behavior — the boar spear _3p doesn't have that actor and
		-- crashes Actor.create_actor (crash GUID 86d07a4e on dummy hit). The
		-- non-projectile template doesn't need it; pickups spawn statically
		-- at the impact position instead of bouncing. Acceptable trade-off.
		Pickups.ammo[_TJ_PICKUP_KEY] = table.clone(base)
		Pickups.ammo[_TJ_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
		Pickups.ammo[_TJ_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
		Pickups.ammo[_TJ_PICKUP_KEY].pickup_name        = _TJ_PICKUP_KEY
		Pickups.ammo[_TJ_LINK_PICKUP_KEY] = table.clone(base)
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].pickup_name        = _TJ_LINK_PICKUP_KEY
		-- Re-attach the function refs after table.clone (closures get shallow-copied
		-- correctly, but be explicit so a future refactor doesn't trip us).
		for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
			Pickups.ammo[key].can_interact_func      = _can_interact
			Pickups.ammo[key].outline_available_func = _outline_available
			Pickups.ammo[key].on_pick_up_func        = _on_pick_up
		end

		-- AllPickups is built once at boot from Pickups.<group>.<name> and is
		-- the lookup the pickup system reads. Mirror our entries in.
		if AllPickups then
			AllPickups[_TJ_PICKUP_KEY]      = Pickups.ammo[_TJ_PICKUP_KEY]
			AllPickups[_TJ_LINK_PICKUP_KEY] = Pickups.ammo[_TJ_LINK_PICKUP_KEY]
		end

		-- NetworkLookup.pickup_names is built from AllPickups at boot. Mirror
		-- our keys in via rawset (the table has an error-throwing __index).
		if NetworkLookup and NetworkLookup.pickup_names then
			local tbl = NetworkLookup.pickup_names
			for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
				if not rawget(tbl, key) then
					local idx = #tbl + 1
					rawset(tbl, idx, key)
					rawset(tbl, key, idx)
				end
			end
		end

		mod:info("Registered pickups: %s + %s (boar spear unit, ammo_type=throwing_javelin)",
			_TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY)
	end
end

-- ============================================================
-- Stuck-pickup rotation cleanup (Tuskgor Javelin) — INSTRUMENTED
-- ============================================================
-- v0.1.81 hooked ProjectileLinkerSystem.link_pickup but that fires AFTER
-- PickupSystem._spawn_pickup has already set the unit's world rotation
-- (pickup_system.lua:1441 _spawn_pickup → 1446 link_pickup). For the common
-- "stuck in a level wall" case, hit_unit doesn't have a projectile_linker_system
-- extension, so link_pickup falls through to the else branch which never
-- re-applies link_rotation. The hook therefore had no effect on wall-sticks.
--
-- v0.1.82 moves the hook earlier: PickupSystem.rpc_spawn_linked_pickup runs
-- server-side BEFORE _spawn_pickup is called, with link_rotation as a parameter
-- we can rewrite. Modifying it here propagates through the spawn AND through
-- the subsequent rpc_link_pickup that fans to clients.
--
-- Also rotation logic upgraded: horizontal-projection variant. The engine
-- applies random_pitch (math.pi/6 to math.pi/3 = 30°-60° around unit-left)
-- and random_roll (±18° around unit-forward) on top of the clean directional
-- look. To wipe both completely, project the rotated forward onto the
-- horizontal plane (Stingray world: x,y horizontal; z vertical) and rebuild
-- look using world up. Cost: floor/ceiling sticks would point sideways
-- instead of into-the-surface. Acceptable trade-off given vertical walls
-- are >90% of stick locations.
--
-- Verbose logging (mod:info) on every fire — input rotation axes, output
-- rotation axes, pickup name. Lets us see in console.log whether the hook
-- fires AND whether the math produces the correction we expect.
local function _log_quat(prefix, q)
	local fwd = Quaternion.forward(q)
	local rgt = Quaternion.right(q)
	local up  = Quaternion.up(q)
	mod:info("  %s: fwd=(%.2f,%.2f,%.2f) right=(%.2f,%.2f,%.2f) up=(%.2f,%.2f,%.2f)",
		prefix,
		Vector3.x(fwd), Vector3.y(fwd), Vector3.z(fwd),
		Vector3.x(rgt), Vector3.y(rgt), Vector3.z(rgt),
		Vector3.x(up),  Vector3.y(up),  Vector3.z(up))
end

local function _is_our_pickup(pickup_name)
	return pickup_name == _TJ_PICKUP_KEY or pickup_name == _TJ_LINK_PICKUP_KEY
end

local function _clean_horizontal_rotation(rot)
	local fwd = Quaternion.forward(rot)
	local horizontal = Vector3(Vector3.x(fwd), Vector3.y(fwd), 0)
	if Vector3.length(horizontal) <= 0.01 then return rot, false end
	horizontal = Vector3.normalize(horizontal)
	local clean = Quaternion.look(horizontal, Vector3.up())
	-- v0.1.119: boar spear's local +Z is the tip axis (held mesh, hand grip
	-- pose). Engine's Quaternion.look orients local +Y to forward, so the
	-- visible tip ends up pointing world up — user reports "stuck straight
	-- up and down vertically". Post-multiply by a -90° rotation around the
	-- unit's local right axis (+X) to swing local +Z (tip) onto local +Y
	-- (link_direction). After this, the visible tip points along link_direction
	-- = into the wall.
	local tip_correction = Quaternion(Vector3.right(), -math.pi / 2)
	return Quaternion.multiply(clean, tip_correction), true
end

-- ============================================================================
-- THE ACTUAL FIX (v0.1.97): force projectile/action system to use our cloned
-- template, not the base.
-- ============================================================================
-- v0.1.96 diagnostic confirmed the engine reads `javelin_template` (base) at
-- projectile init, NOT `tuskgor_javelin_template`. Cause: per memory note
-- `feedback_cwv_backend_id_lookup.md`, `item_data.name`/`.key` returns the
-- BASE weapon key for cwv items. The projectile system does
-- `ItemMasterList[item_name]` (item_name = "we_javelin") then
-- `BackendUtils.get_item_template(item_data)` reads `item_data.template`
-- which is the base template name. Our cloned template was dead code at
-- runtime — every stat/timing/impact_data override never took effect.
--
-- Hook `BackendUtils.get_item_template`. When the backend_id matches our cwv
-- javelin pattern, return `Weapons.tuskgor_javelin_template` instead of the
-- resolved base template.
--
-- Scope: only fires when backend_id matches `cwv_..._javelin_001`. Other cwv
-- weapons hit the same bug in principle but happen to share the SAME template
-- name as their base (e.g. cwv_es_longsword still uses `imperial_longsword_template`
-- which the engine resolves correctly via the base lookup since our clone IS
-- registered under that exact name). Javelin is special because we cloned to
-- a DIFFERENT name (`tuskgor_javelin_template` vs base `javelin_template`)
-- and the engine doesn't know about the rename.
-- v0.1.97 hook on BackendUtils.get_item_template was a no-op: the projectile
-- system passes `ItemMasterList[item_name]` where item_name = "we_javelin"
-- (BASE key, since cwv items return base for item_data.name/.key per memory
-- `feedback_cwv_backend_id_lookup.md`). The base entry has no backend_id, so
-- the cwv match never fired.
--
-- v0.1.98 fix: hook PlayerProjectileUnitExtension.init AFTER vanilla init
-- runs, look up the OWNER's slot_ranged backend_id (where the cwv prefix
-- actually lives), and if it matches our javelin pattern, swap
-- self._current_action / self._impact_data / self.projectile_info to point
-- at our cloned tuskgor_javelin_template's throw_charged sub-action. The
-- projectile then reads OUR fields for the rest of its lifecycle (impact
-- handling, link_pickup, pickup_settings, etc.).
-- Single init hook combining the v0.1.98 fix and the v0.1.96 diagnostic
-- trace. v0.1.99 had two separate `hook_safe` registrations on the same
-- method which silently never fired (VMF doesn't chain multiple hook_safe
-- handlers for one method).
mod:hook_safe("PlayerProjectileUnitExtension", "init", function(self, extension_init_context, unit, extension_init_data)
	-- 1) Diagnostic trace (always fires).
	local item = extension_init_data and extension_init_data.item_name or "?"
	local tmpl = extension_init_data and extension_init_data.item_template_name or "?"
	local action = extension_init_data and extension_init_data.action_name or "?"
	local sub = extension_init_data and extension_init_data.sub_action_name or "?"
	mod:info("[cwv stick] PROJ INIT item=%s tmpl=%s action=%s sub=%s",
		tostring(item), tostring(tmpl), tostring(action), tostring(sub))

	-- 2) Post-fix: if this projectile belongs to one of our cwv javelin
	--    variants, swap the action data references onto our cloned template.
	--    Filter to javelin-class items only to avoid log spam on arrows/bolts.
	if item ~= "we_javelin" then return end

	local owner_unit = extension_init_data and extension_init_data.owner_unit
	if not owner_unit then
		mod:info("[cwv stick] post-fix BAIL: no owner_unit in extension_init_data")
		return
	end
	local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
	if not inv then
		mod:info("[cwv stick] post-fix BAIL: no inventory_system extension on owner")
		return
	end
	local slot_data = inv:get_slot_data("slot_ranged")
	if not slot_data then
		mod:info("[cwv stick] post-fix BAIL: no slot_ranged slot_data")
		return
	end
	-- v0.1.106 diagnostic dump revealed: slot_data.id is the slot NAME
	-- ("slot_ranged"), slot_data.backend_id is nil. The cwv identifier
	-- actually lives in slot_data.skin (e.g. "cwv_es_javelin_skin").
	-- Match the skin field instead.
	local skin = slot_data.skin
	if type(skin) ~= "string" or not skin:match("^cwv_.+_javelin_skin$") then
		mod:info("[cwv stick] post-fix BAIL: skin=%s did not match cwv javelin pattern", tostring(skin))
		return
	end

	if not (Weapons and Weapons.tuskgor_javelin_template) then return end
	local our_template = Weapons.tuskgor_javelin_template
	local lookup = self.action_lookup_data
	if not lookup then return end
	local action_group = our_template.actions and our_template.actions[lookup.action_name]
	local our_action = action_group and action_group[lookup.sub_action_name]
	if not our_action then return end

	self._current_action = our_action
	self._impact_data    = our_action.impact_data
	self.projectile_info = our_action.projectile_info or self.projectile_info
	if our_action.impact_data and our_action.impact_data.damage_profile then
		local dmg_id = NetworkLookup.damage_profiles[our_action.impact_data.damage_profile]
		if dmg_id then self._impact_damage_profile_id = dmg_id end
	end
	mod:info("[cwv stick] init post-fix swap: skin=%s -> tuskgor_javelin_template (action=%s sub=%s, link=%s link_pickup=%s)",
		tostring(skin), tostring(lookup.action_name), tostring(lookup.sub_action_name),
		tostring(our_action.impact_data and our_action.impact_data.link),
		tostring(our_action.impact_data and our_action.impact_data.link_pickup))

	-- v0.1.125–v0.1.156 carried a child-node rotation correction here for the
	-- boar spear's wrong-axis in-flight visual. v0.1.157 made the in-flight
	-- unit the vanilla elf javelin (correctly authored, +Y is tip), so the
	-- correction is no longer applicable — and would actively wrongly rotate
	-- the elf javelin's child nodes. Removed.
end)

mod:hook_safe("PlayerProjectileUnitExtension", "hit_level_unit", function(self, impact_data, hit_unit)
	local lookup = self.action_lookup_data
	local tmpl = lookup and lookup.item_template_name or "?"
	mod:info("[cwv stick] HIT_LEVEL_UNIT tmpl=%s link=%s link_pickup=%s",
		tostring(tmpl),
		tostring(impact_data and impact_data.link),
		tostring(impact_data and impact_data.link_pickup))
end)

mod:hook("PlayerProjectileUnitExtension", "_handle_linking", function(func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
	local lookup = self.action_lookup_data
	local tmpl = lookup and lookup.item_template_name or "?"
	mod:info("[cwv stick] HANDLE_LINKING tmpl=%s allow_link=%s link=%s link_pickup=%s",
		tostring(tmpl), tostring(allow_link),
		tostring(impact_data and impact_data.link),
		tostring(impact_data and impact_data.link_pickup))
	return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
end)

-- One-shot dump command: read the live runtime tuskgor_javelin_template's
-- impact_data. Tells us if our modifications actually persisted into the
-- runtime template state, or if something overwrote them.
mod:command("cwv_dump_javelin_impact", "Dump runtime tuskgor_javelin_template throw_charged.impact_data", function()
	if not Weapons or not Weapons.tuskgor_javelin_template then
		mod:echo("Weapons.tuskgor_javelin_template not found")
		return
	end
	mod:echo("=== tuskgor_javelin_template runtime dump ===")
	for action_name, action_group in pairs(Weapons.tuskgor_javelin_template.actions) do
		if type(action_group) == "table" then
			for sub_name, sub in pairs(action_group) do
				if type(sub) == "table" and sub.kind == "thrown_projectile" then
					mod:echo("action.%s.%s:", action_name, sub_name)
					mod:echo("  speed=%s total_time=%s",
						tostring(sub.speed), tostring(sub.total_time))
					if sub.impact_data then
						local i = sub.impact_data
						mod:echo("  link=%s link_pickup=%s wall_nail=%s",
							tostring(i.link), tostring(i.link_pickup), tostring(i.wall_nail))
						mod:echo("  flow_walls=%s flow_init=%s",
							tostring(i.flow_event_on_walls), tostring(i.flow_event_on_init))
						mod:echo("  pickup_settings=%s",
							tostring(i.pickup_settings))
					else
						mod:echo("  impact_data = nil")
					end
				end
			end
		end
	end
end)

-- Path A entry on thrower's side — log only.
mod:hook("PlayerProjectileUnitExtension", "_spawn_linked_pickup_projectile", function(func, self, pickup_name, ...)
	if _is_our_pickup(pickup_name) then
		mod:info("[cwv stick:trace] _spawn_linked_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
	end
	return func(self, pickup_name, ...)
end)

-- Path B entry on thrower's side — log only.
mod:hook("PlayerProjectileUnitExtension", "_spawn_pickup_projectile", function(func, self, pickup_name, ...)
	if _is_our_pickup(pickup_name) then
		mod:info("[cwv stick:trace] _spawn_pickup_projectile (PATH B) fired (pickup=%s)", tostring(pickup_name))
	end
	return func(self, pickup_name, ...)
end)

-- Path A server-side: PickupSystem.rpc_spawn_linked_pickup.
mod:hook("PickupSystem", "rpc_spawn_linked_pickup", function(func, self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
	local pickup_name = NetworkLookup and NetworkLookup.pickup_names and NetworkLookup.pickup_names[pickup_name_id]
	if _is_our_pickup(pickup_name) then
		mod:info("[cwv stick] PATH A rpc_spawn_linked_pickup fired (pickup=%s)", tostring(pickup_name))
		_log_quat("  input ", link_rotation)
		local cleaned, ok = _clean_horizontal_rotation(link_rotation)
		if ok then link_rotation = cleaned; _log_quat("  output", link_rotation)
		else mod:info("  forward is near-vertical; skipping correction") end
	end
	return func(self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
end)

-- Path B server-side: ProjectileSystem.rpc_spawn_pickup_projectile (DIFFERENT
-- class than PickupSystem). Pickup has physics so it bounces/lands rather
-- than sticking; align rotation with velocity for a sensible resting pose.
mod:hook("ProjectileSystem", "rpc_spawn_pickup_projectile", function(func, self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
	local pickup_name = NetworkLookup and NetworkLookup.pickup_names and NetworkLookup.pickup_names[pickup_name_id]
	if _is_our_pickup(pickup_name) then
		mod:info("[cwv stick] PATH B rpc_spawn_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
		local vel = AiAnimUtils.velocity_network_scale(network_velocity)
		if vel and Vector3.length(vel) > 0.1 then
			local fwd = Vector3.normalize(vel)
			local cleaned = Quaternion.look(fwd, Vector3.up())
			network_rotation = AiAnimUtils.rotation_network_scale(cleaned, true)
			_log_quat("  velocity-aligned", cleaned)
		end
	end
	return func(self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
end)

-- v0.1.248: parent→visual map for the outline mirror hook below. Weak keys so
-- entries auto-clear when a parent unit gets GC'd without _detach firing.
local _carrier_visuals = setmetatable({}, { __mode = "k" })

-- Carrier-unit pattern (v0.1.164, hook target fixed in v0.1.172): when our
-- pickup spawns (the throwing axe pup unit — chosen for its baked-in
-- interaction collision actors), spawn the boar spear _3p mesh as a visual
-- on top, link it to the parent's transform so it follows wall-stuck
-- position/rotation, and shrink the parent to near-zero scale so only the
-- boar spear is visible.
--
-- v0.1.172 fix: hook target was `PickupUnitExtension` (base class) and
-- silently never fired. Per memory `feedback_vt2_class_hook_derived.md`,
-- VT2's class() copies methods into derived classes at definition time, so
-- a hook on the base never fires for derived-class instances. Our pickup
-- uses `unit_template_name = "limited_owned_pickup_unit"` which instantiates
-- `LimitedOwnedPickupUnitExtension`. Hook the derived class instead, plus
-- the two siblings as cheap insurance for future variants.
local function _attach_carrier_visual(self)
	if not _is_our_pickup(self.pickup_name) then return end
	local parent = self.unit
	if not parent then return end
	mod:info("[cwv stick] extensions_ready fired (pickup=%s)", tostring(self.pickup_name))

	-- Clean rotation — orient the parent so the spear visual hangs off it
	-- pointing into the wall.
	local current_rot = Unit.world_rotation(parent, 0)
	local cleaned, did_clean = _clean_horizontal_rotation(current_rot)
	if did_clean then
		Unit.set_local_rotation(parent, 0, cleaned)
	end

	-- Spawn boar spear visual at parent's pose, pulled back along the
	-- forward (into-wall) axis so the spear doesn't sit too deep in the
	-- geometry. See _TJ_VISUAL_PULL_BACK_M for the offset.
	local world = self.world or (Managers.world and Managers.world:world("level_world"))
	if not world then return end
	local pos = Unit.world_position(parent, 0)
	local rot = Unit.world_rotation(parent, 0)
	if _TJ_VISUAL_PULL_BACK_M and _TJ_VISUAL_PULL_BACK_M ~= 0 then
		local fwd = Quaternion.forward(rot)
		pos = pos - fwd * _TJ_VISUAL_PULL_BACK_M
	end
	local ok_spawn, visual = pcall(World.spawn_unit, world, _TJ_BOAR_SPEAR_UNIT, pos, rot)
	if not ok_spawn or not visual then
		mod:warning("[cwv stick] failed to spawn boar spear visual: %s", tostring(visual))
		return
	end

	-- v0.1.175: do NOT link visual to parent. World.link_unit composes the
	-- child's transform with the parent's, so shrinking the parent to 0.001
	-- scale (below) made the boar spear inherit that scale and disappear
	-- too. For our use case the pickup is static (link_pickup attaches it
	-- to a wall via projectile_linker_system, parent doesn't move after
	-- spawn), so the visual doesn't need to track the parent. Spawn at
	-- parent's pose once, leave as free-standing world unit at scale 1.0.
	-- Edge case: javelins stuck in moving enemies won't have visual follow;
	-- revisit if that materializes in practice.

	-- v0.1.183: switched from scale-to-tiny hide to Unit.set_unit_visibility.
	-- Scale-to-0.001 also shrunk the OutlineExtension's silhouette target,
	-- killing the white tagged-pickup outline. Visibility is a render flag
	-- independent of physics — actors still detect interaction, mesh isn't
	-- drawn, and the outline shader may still compute on the hidden mesh
	-- (the shader's target rect is per-unit metadata, not directly tied to
	-- the rendered pass). If the outline is STILL missing after this change,
	-- the OutlineExtension genuinely needs a visible mesh and we'll need to
	-- attach it to the boar spear visual instead.
	pcall(Unit.set_unit_visibility, parent, false)

	self._cwv_visual_unit = visual
	self._cwv_world       = world
	_carrier_visuals[parent] = visual
	mod:info("[cwv stick] carrier visual attached: parent=%s child=%s", tostring(_TJ_PICKUP_UNIT), tostring(_TJ_BOAR_SPEAR_UNIT))
end

local function _detach_carrier_visual(self)
	if self.unit then _carrier_visuals[self.unit] = nil end
	if not self._cwv_visual_unit then return end
	local visual = self._cwv_visual_unit
	self._cwv_visual_unit = nil
	if Managers and Managers.state and Managers.state.unit_spawner then
		pcall(function() Managers.state.unit_spawner:mark_for_deletion(visual) end)
	elseif self._cwv_world then
		pcall(World.destroy_unit, self._cwv_world, visual)
	end
end

-- v0.1.248: mirror outline_unit calls from parent (hidden) → visual.
-- Why: `Unit.set_unit_visibility(parent, false)` (the hide path used by the
-- carrier pattern since v0.1.190) excludes the parent from every render pass,
-- including the outline pass. Tagged-pickup outlines stopped showing because
-- the engine outlines the parent throwing-axe unit, not our visual boar
-- spear. Forwarding every outline_unit call onto the visual gives it the
-- same outline state without needing the parent visible.
mod:hook("OutlineSystem", "outline_unit", function(func, self, unit, flag, channel, do_outline, apply_method, outline_settings)
	local visual = _carrier_visuals[unit]
	if visual and Unit.alive(visual) then
		pcall(func, self, visual, flag, channel, do_outline, apply_method, outline_settings)
	end
	return func(self, unit, flag, channel, do_outline, apply_method, outline_settings)
end)

mod:hook_safe("LimitedOwnedPickupUnitExtension", "extensions_ready", _attach_carrier_visual)
mod:hook_safe("LifeTimePickupUnitExtension",     "extensions_ready", _attach_carrier_visual)
mod:hook_safe("PlayerTeleportingPickupExtension","extensions_ready", _attach_carrier_visual)
mod:hook_safe("LimitedOwnedPickupUnitExtension", "destroy",          _detach_carrier_visual)
mod:hook_safe("LifeTimePickupUnitExtension",     "destroy",          _detach_carrier_visual)
mod:hook_safe("PlayerTeleportingPickupExtension","destroy",          _detach_carrier_visual)

-- Linker-extension branch (rare).
mod:hook("ProjectileLinkerSystem", "link_pickup", function(func, self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
	local ok, pickup_name = pcall(Unit.get_data, pickup_unit, "pickup_name")
	if ok and _is_our_pickup(pickup_name) then
		mod:info("[cwv stick] link_pickup fired (linker-extension branch, pickup=%s)", tostring(pickup_name))
		_log_quat("  input ", link_rotation)
		local cleaned, did = _clean_horizontal_rotation(link_rotation)
		if did then link_rotation = cleaned; _log_quat("  output", link_rotation) end
	end
	return func(self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
end)

local function _clone_inline_throw_profile(source_name, prefix, damage_mult)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	if DamageProfileTemplates[new_name] then return new_name end

	local clone = table.clone(source, true)

	-- thrown_javelin shape (verified against
	-- damage_profile_templates_dlc_woods.lua:263): default_target carries
	-- power_distribution_near / power_distribution_far, each with .attack
	-- (damage) and .impact (stagger). We multiply only .attack so "double
	-- damage" doesn't accidentally amp stagger too. Also handle the generic
	-- power_distribution case in case a future thrown profile uses it.
	local function scale_target(target)
		if type(target) ~= "table" then return end
		if target.power_distribution_near and target.power_distribution_near.attack then
			target.power_distribution_near.attack = target.power_distribution_near.attack * damage_mult
		end
		if target.power_distribution_far and target.power_distribution_far.attack then
			target.power_distribution_far.attack = target.power_distribution_far.attack * damage_mult
		end
		if target.power_distribution and target.power_distribution.attack then
			target.power_distribution.attack = target.power_distribution.attack * damage_mult
		end
	end

	scale_target(clone.default_target)
	if type(clone.targets) == "table" then
		for _, t in ipairs(clone.targets) do scale_target(t) end
	end

	DamageProfileTemplates[new_name] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, new_name)
		rawset(tbl, new_name, idx)
	end

	return new_name
end

-- Module-scope so it can't be re-created per call (Lua closure identity matters
-- for VMF hook bookkeeping, and the function is small enough to share).
local function _always_false() return false end

-- 3P body wield routing for Tuskgor Javelin (Kruber + Saltzpyre variants).
-- Each character body has a different "spear+shield" sub-graph in its master SM:
--   * Kruber  (empire-soldier 3P body): es_deus_01 — Empire Chaos Wastes spear+shield
--   * Saltzpyre wh_captain/bountyhunter/zealot (witch-hunter 3P body): no native
--     spear+shield SM, falls back to 1h_sword_shield (closest in-stance analog)
--   * Saltzpyre wh_priest: native 1h_hammer_shield (warrior priest stance)
-- Mappings sourced from weapon_tweaker.lua's _career_anim_redirect / _suffix_career_map
-- which already encodes the cross-character spear+shield routing rules.
local _tj_wield_3p_by_career = {
	es_mercenary      = "to_es_deus_01",
	es_huntsman       = "to_es_deus_01",
	es_knight         = "to_es_deus_01",
	es_questingknight = "to_es_deus_01",
	wh_captain        = "to_1h_sword_shield",
	wh_bountyhunter   = "to_1h_sword_shield",
	wh_zealot         = "to_1h_sword_shield",
	wh_priest         = "to_1h_hammer_shield",
}

-- 3P body event remap for Tuskgor Javelin. Routes the elf javelin template's
-- action events to events that are commonly authored across es_deus_01,
-- 1h_sword_shield, AND 1h_hammer_shield — so the same anim_event_3p plays
-- visibly regardless of which sub-graph the body wielded into. Verified
-- against the source templates: attack_swing_stab, attack_swing_charge_stab,
-- attack_swing_heavy_stab, attack_swing_heavy_left, attack_push, parry_pose
-- all appear in 1h_swords_shield.lua, es_deus_01.lua, and dual_wield_hammers_priest
-- families (the priest hammer+shield template uses these too).
--
-- TRADE-OFF: shield-stance SMs are MELEE-ONLY. attack_throw and throw_charge
-- have no equivalent — body stands still during the throw windup/release while
-- the projectile system fires the javelin from 1P. Throw mechanics still work
-- (projectile spawn / damage / pickup are separate from the 3P clip); just no
-- visible body throw motion. Same for `reload`. User-accepted trade vs.
-- keeping the elf javelin SM (which may not be authored on Kruber/Saltzpyre
-- 3P bodies, leading to silent wield failure).
--
-- 1P UNCHANGED: the source javelin SM remains the 1P state_machine and handles
-- all 1P playback (including throw windup) correctly via first_person_base.
local _tj_anim_remap = {
	-- Light combo chain: 3-step stab progression
	attack_chain_01          = "attack_swing_stab",
	attack_chain_02          = "attack_swing_heavy_left",   -- left-side strike for variety
	attack_chain_03          = "attack_swing_heavy_stab",   -- combo finisher
	-- Directional lights → stab-flavored events
	attack_swing_left        = "attack_swing_heavy_left",
	attack_swing_right       = "attack_swing_stab",
	attack_swing_up          = "attack_swing_heavy_stab",
	-- Charges/heavy stabs
	attack_swing_charge      = "attack_swing_charge_stab",
	attack_swing_stab_charge = "attack_swing_charge_stab",
	attack_swing_stab_02     = "attack_swing_heavy_stab",
	-- attack_swing_stab unchanged (universal across all three target SMs)
	-- attack_throw, throw_charge, reload: deliberately not remapped — see header
}

-- Careers that need the base-template wield-patch for the inventory previewer
-- (HeroPreviewer reads BASE javelin_template, not our clone — same pattern as
-- elven_sword_shield and imperial_dual_swords). Same set as the keys of
-- _tj_wield_3p_by_career, but kept ordered for the loop.
local _tj_kruber_saltzpyre_careers = {
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	"wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
}

-- ANIM ADDENDUM: this function only touches stats + (eventually) 3P fields.
-- 1P is universal across characters — see top-of-file ANIMATION ARCHITECTURE.
local function _create_tuskgor_javelin_template()
	if not Weapons or not Weapons.javelin_template then
		mod:warning("javelin_template not found — Tuskgor Javelin stat modifications unavailable")
		return
	end
	if Weapons.tuskgor_javelin_template then return end

	local template = table.clone(Weapons.javelin_template, true)

	-- Ammo system rewrite: finite stack, vanilla pickups refill.
	if template.ammo_data then
		template.ammo_data.max_ammo            = _TJ_MAX_AMMO
		template.ammo_data.block_ammo_pickup   = false
		template.ammo_data.unique_ammo_type    = false
		-- Keep ammo_per_clip / ammo_per_reload at 1 (vanilla) — those control
		-- how many javelins are "drawn" per reload anim, not pickup behaviour.
	end

	-- Disable the magic auto-catch reload (vanilla refills on-demand).
	if template.actions.weapon_reload and template.actions.weapon_reload.default then
		template.actions.weapon_reload.default.condition_func       = _always_false
		template.actions.weapon_reload.default.chain_condition_func = _always_false
	end

	-- Half throw speed: extend wind-up before the projectile fires.
	if template.attack_meta_data and template.attack_meta_data.minimum_charge_time then
		template.attack_meta_data.minimum_charge_time =
			template.attack_meta_data.minimum_charge_time * (1 / _TJ_SPEED_MULT)
	end

	for _, action_group in pairs(template.actions) do
		if type(action_group) == "table" then
			for _, sub_action in pairs(action_group) do
				if type(sub_action) == "table" then
					-- anim_time_scale (mostly a no-op for javelin — kept for parity
					-- with the other template clones in case a sub-action does set it)
					if sub_action.anim_time_scale then
						sub_action.anim_time_scale = sub_action.anim_time_scale * _TJ_SPEED_MULT
					end
					-- Slow the throw action: total_time + minimum_hold_time.
					-- fire_time stays put — moving it would desync the projectile
					-- spawn point on the animation.
					if sub_action.kind == "thrown_projectile" then
						if sub_action.total_time and sub_action.total_time ~= math.huge then
							sub_action.total_time = sub_action.total_time * (1 / _TJ_SPEED_MULT)
						end
						if sub_action.minimum_hold_time then
							sub_action.minimum_hold_time = sub_action.minimum_hold_time * (1 / _TJ_SPEED_MULT)
						end
						-- Projectile flight speed (sub_action.speed) — slower in-air
						-- velocity. Distinct from the action timing fields above:
						-- those control wind-up/recovery, this controls how fast the
						-- thrown javelin actually travels.
						if sub_action.speed then
							sub_action.speed = sub_action.speed * _TJ_PROJECTILE_SPEED_MULT
						end
						-- Throwing-axe-style stick + pickup. Vanilla javelin uses
						-- `link = true` + `wall_nail = true` + `flow_event_on_walls
						-- = "teleport_out"` (the magic auto-recall behavior). Strip
						-- those and replace with the throwing-axe combo:
						-- `link_pickup = true` + `pickup_settings = {...}`. The
						-- engine then spawns a pickup on the stuck projectile that
						-- the player can walk up to and grab for +1 ammo.
						-- Reference: 1h_throwing_axes.lua:80-89 / 163-172.
						if sub_action.impact_data then
							local imp = sub_action.impact_data
							imp.link                  = nil
							imp.wall_nail             = nil
							imp.flow_event_on_init    = nil
							imp.flow_event_on_walls   = nil
							imp.link_pickup           = true
							imp.no_stop_on_friendly_fire = true
							imp.pickup_settings       = {
								use_weapon_skin = true,
								link_hit_zones  = { "head", "neck", "torso" },
							}
							-- v0.1.123: vanilla javelin depth = 0.7 buries most of
							-- the spear shaft in the wall; user reports "sticks
							-- way too deep". Throwing axe uses 0.2; pick 0.25 for
							-- a long polearm so the tip + a bit of shaft penetrates
							-- while most of the shaft sticks out.
							imp.depth                 = 0.25
							imp.depth_offset          = -0.2
						end
					end
					-- Melee stab damage profiles use the PowerLevelTemplates
					-- string-key indirection — existing helper handles those.
					if sub_action.damage_profile then
						sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_tj_", {
							damage = _TJ_DAMAGE_MULT,
						})
					end
					-- Throw projectile damage profile is INLINE — needs the
					-- inline-clone helper, not the string-key one.
					if sub_action.impact_data and sub_action.impact_data.damage_profile then
						sub_action.impact_data.damage_profile = _clone_inline_throw_profile(
							sub_action.impact_data.damage_profile, "cwv_tj_", _TJ_DAMAGE_MULT
						)
					end
					-- 3P body anim remap: route elf javelin events to
					-- 1h_spear_shield-vocab events so Kruber/Saltzpyre's
					-- 3P bodies play visible spear stabs for the melee combo.
					-- Throw/reload events deliberately not remapped — see
					-- _tj_anim_remap header for rationale.
					if sub_action.anim_event and _tj_anim_remap[sub_action.anim_event] then
						sub_action.anim_event_3p = _tj_anim_remap[sub_action.anim_event]
					end
				end
			end
		end
	end

	-- 3P wield: route each cwv-javelin career into its character body's native
	-- spear+shield sub-graph (or closest analog for Saltzpyre, which has no
	-- native spear+shield SM). Elf careers (we_*) wielding the vanilla
	-- we_javelin keep their native to_javelin wield because we patch only
	-- the cwv-using careers below.
	template.wield_anim_3p = "to_es_deus_01"  -- default for unrecognised careers
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for career, wield in pairs(_tj_wield_3p_by_career) do
		template.wield_anim_career_3p[career] = wield
	end

	Weapons.tuskgor_javelin_template = template

	-- BASE TEMPLATE PATCH: HeroPreviewer (inventory character preview) reads
	-- the base javelin_template's wield_anim_career_3p, NOT our clone's, so
	-- the menu preview pose follows the vanilla javelin wield unless we
	-- patch the base. Scoped tightly to Kruber + Saltzpyre careers so elf
	-- careers fall through to the original wield_anim. Same pattern as
	-- _create_imperial_dual_swords_template / _create_elven_sword_shield_template.
	local base = Weapons.javelin_template
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for career, wield in pairs(_tj_wield_3p_by_career) do
			base.wield_anim_career_3p[career] = wield
		end
	end
	mod:info("Created tuskgor_javelin_template (max_ammo=%d, ammo_pickups=on, no auto-catch, link_pickup stick, %.0f%% dmg, %.0f%% action speed, %.0f%% projectile speed, 3p wield=es_*->to_es_deus_01, wh_*->to_1h_sword_shield, wh_priest->to_1h_hammer_shield)",
		_TJ_MAX_AMMO, _TJ_DAMAGE_MULT * 100, _TJ_SPEED_MULT * 100, _TJ_PROJECTILE_SPEED_MULT * 100)
end

_register_tuskgor_javelin_assets()
_create_tuskgor_javelin_template()

-- ============================================================
-- Rapier template (modified fencing_sword_template_1)
-- Saltzpyre's fencing-sword moveset cloned for Kruber. Pistol-shoot
-- weapon special (action_three, kind="handgun") disabled via
-- _always_false condition_func — keeps the action defined for
-- state-machine / network consistency but it never fires. Same pattern
-- as the tuskgor javelin auto-catch reload disable (v0.1.65).
--
-- 3P wield routes to Kruber's native to_1h_sword SM (the empire-soldier
-- body authors no fencing-sword wield), and per-action remap covers
-- fencing events not in 1h_sword's closed vocabulary.
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

-- 3P remap — source (fencing_sword_template_1) → target
-- (one_handed_swords_template_1, Kruber 1h sword vocabulary).
-- Closed list for to_1h_sword (verified against 1h_swords.lua):
--   charges:   attack_swing_charge_left, attack_swing_charge_right_pose,
--              attack_swing_charge_left_pose
--   strikes:   attack_swing_heavy, attack_swing_heavy_right,
--              attack_swing_left_diagonal, attack_swing_right,
--              attack_swing_down, attack_swing_right_diagonal
--   universal: attack_push, parry_pose
-- Source events already in target (attack_swing_right,
-- attack_swing_right_diagonal, attack_push, parry_pose) need no entry.
local _RAPIER_ANIM_REMAP_3P = {
	-- Stab charge → heavy charge (closest charge anim).
	attack_swing_stab_charge = "attack_swing_charge_left",
	-- Stab strike → right_diagonal (closest forward-leaning strike).
	attack_swing_stab        = "attack_swing_right_diagonal",
	-- Source has plain attack_swing_left; target has _left_diagonal only.
	attack_swing_left        = "attack_swing_left_diagonal",
}

local _rapier_kruber_wield_3p = {
	es_mercenary      = "to_1h_sword",
	es_huntsman       = "to_1h_sword",
	es_knight         = "to_1h_sword",
	es_questingknight = "to_1h_sword",
}

local function _create_rapier_template()
	if not Weapons or not Weapons.fencing_sword_template_1 then
		mod:warning("fencing_sword_template_1 not found — Rapier template unavailable")
		return
	end
	if Weapons.rapier_template then return end

	local template = table.clone(Weapons.fencing_sword_template_1, true)

	-- Disable the pistol-shoot action_three (kind="handgun"). Keep the
	-- action defined for state-machine/network consistency; just
	-- prevent it from ever firing. Same pattern as tuskgor_javelin_template's
	-- weapon_reload disable.
	if template.actions and template.actions.action_three then
		for _, sub_action in pairs(template.actions.action_three) do
			if type(sub_action) == "table" then
				sub_action.condition_func       = _always_false
				sub_action.chain_condition_func = _always_false
			end
		end
	end

	-- Override left_hand_attachment_node_linking. The base fencing template
	-- uses `AttachmentNodeLinking.pistol.left`, which has component
	-- bindings for `lock_hammer`, `trigger`, and `lock_lid` (nodes that
	-- exist on the pistol mesh `wpn_emp_pistol_01_t1`). Our variant
	-- replaces left_hand_unit with `wpn_invisible_weapon`, which does
	-- NOT have those nodes — so vanilla's `Unit.node(unit, "lock_hammer")`
	-- crashes with `[Script Error]: lock_hammer` on equip
	-- (GUID acb910d1-a625-49b1-b899-86d48d27462d, v0.1.183).
	-- Replace with a minimal binding: just attach the (invisible) left
	-- weapon to `j_leftweaponattach` at node 0, no component lookups.
	-- This is on the CLONE only — base template still has the full
	-- pistol bindings intact for native Saltzpyre wielders.
	template.left_hand_attachment_node_linking = {
		first_person = {
			wielded   = { { source = "j_leftweaponattach", target = 0 } },
			unwielded = { { source = "j_hips",             target = 0 } },
		},
		third_person = {
			display   = { { source = "j_leftweaponattach", target = 0 } },
			wielded   = { { source = "j_leftweaponattach", target = 0 } },
			unwielded = { { source = "j_hips",             target = 0 } },
		},
	}

	-- Per-action 3P remap on every sub-action whose anim_event has a
	-- substitute. 3P-only — never write anim_event (1P).
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table"
							and sub_action.anim_event
							and _RAPIER_ANIM_REMAP_3P[sub_action.anim_event] then
						sub_action.anim_event_3p = _RAPIER_ANIM_REMAP_3P[sub_action.anim_event]
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_1h_sword"
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for k, v in pairs(_rapier_kruber_wield_3p) do
		template.wield_anim_career_3p[k] = v
	end

	Weapons.rapier_template = template

	-- Patch the BASE template's wield_anim_career_3p so the inventory
	-- previewer (HeroPreviewer reads BASE template, not our clone — see
	-- feedback_cwv_previewer_template_lookup.md) shows the right wield
	-- pose for Kruber careers. Scoped to es_* only — Saltzpyre careers
	-- fall through to original behavior (his body has the fencing wield
	-- authored natively).
	local base = Weapons.fencing_sword_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(_rapier_kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	mod:info("Created rapier_template (pistol-shoot disabled, 3p anim remap: %d entries, wield_3p=to_1h_sword for es_*)",
		3)
end

_create_rapier_template()

-- NOTE: brace_repeater_template + cwv_es_brace_repeater variant moved to
-- weapon_tweaker in v0.1.187 (CWV-side). The functionality lives there
-- now as a 3P unit swap on Kruber's vanilla wh_brace_of_pistols
-- cross-access — no separate inventory item.

-- ============================================================
-- Optional mod detection
-- ============================================================

local function _detect_companion_mods()
	local wt = get_mod("wt")
	local ct = get_mod("cosmetics_tweaker")

	if wt then
		mod:info("weapon_tweaker detected")
	end
	if ct then
		mod:info("cosmetics_tweaker detected")
	end

	return wt, ct
end

-- ============================================================
-- Localization
-- ============================================================

local _display_names = {}

for _, def in ipairs(_variant_definitions) do
	_display_names[def.item_key .. "_name"] = def.display_name
	_display_names[def.item_key .. "_description"] = def.description
	if def.skin_display_name then
		_display_names[def.item_key .. "_skin_name"] = def.skin_display_name
	end
	-- item_type → display_name mapping. `_build_entry` sets
	-- `entry.item_type = def.item_type or def.item_key`, so vanilla UI calls
	-- `Localize(item_data.item_type)` always hit one of these keys.
	-- Without this mapping, those calls would fall through to vanilla's
	-- localization for the BASE weapon's item_type (e.g. "bw_dagger" →
	-- "Dagger") because cwv variants inherit `entry.name` / `entry.key` from
	-- the clone — see `feedback_cwv_clone_name_clobber.md`. The explicit
	-- override here ensures the cwv variant always displays its own name in
	-- weapon-type labels, loot drop banners, and the cosmetics inventory
	-- header.
	-- CLARIFY: Multiple variants can share def.item_type (e.g. all three
	-- Imperial Longsword entries share "cwv_imperial_longsword"). The last
	-- iteration wins; that's intentional — those variants share a display
	-- family ("Imperial Longsword").
	local effective_item_type = def.item_type or def.item_key
	_display_names[effective_item_type] = def.display_name
end

-- Pickup HUD popup strings. Vanilla pickup interaction code calls Localize()
-- on `pickup_settings.hud_description` (interactions.lua:1572 →
-- interaction_ui.lua:684). VMF's per-mod _localization.lua strings are
-- exposed via mod:localize(), NOT auto-registered into the global Localize —
-- so unrecognized keys come back as `<key>` from vanilla Localize. Translate
-- directly in this hook for any pickup loc key the mod defines.
local _pickup_hud_strings = {
	cwv_interaction_ammunition_javelin = "Tuskgor Javelin",
}

mod:hook(_G, "Localize", function(func, key)
	if _display_names[key] then
		return _display_names[key]
	end
	if _pickup_hud_strings[key] then
		return _pickup_hud_strings[key]
	end
	-- Vanilla mace+sword rename — gated on the user-facing toggle. The
	-- inventory/cosmetics UI uses the APPLIED SKIN's display_name key (not
	-- always the IML weapon's display_name), so we have to catch every
	-- `es_dual_wield_hammer_sword_skin_*_name` variant — skin_01, skin_02,
	-- skin_03, runed variants, magic variants, etc. Without the wildcard,
	-- a player who applied any non-default illusion (skin_02 etc.) would
	-- still see "Mace and Sword" because the displayed key is the skin's,
	-- not the weapon's. Pattern: anything starting with the weapon prefix
	-- and ending in `_name`.
	-- Toggle is read at hook fire so it responds to runtime changes without
	-- a mod reload.
	if type(key) == "string"
			and key:sub(1, 30) == "es_dual_wield_hammer_sword_skin"
			and key:sub(-5) == "_name"
			and mod:get("mace_sword_tweak") then
		return "Cudgel and Short Sword"
	end
	return func(key)
end)

-- ============================================================
-- Cross-character weapon unlocks (can_wield patches)
-- ============================================================

local _weapon_unlocks = {
	{
		item_key = "wh_1h_axe",
		add_careers = {
			"es_mercenary",
			"es_huntsman",
			"es_knight",
			"es_questingknight",
		},
	},
}

local function _apply_weapon_unlocks()
	for _, unlock in ipairs(_weapon_unlocks) do
		-- rawget: ItemMasterList __index crashifies on missing keys; defensive against
		-- future _weapon_unlocks entries referencing DLC-gated items the user lacks.
		local item = rawget(ItemMasterList, unlock.item_key)
		if item and item.can_wield then
			local existing = {}
			for _, career in ipairs(item.can_wield) do
				existing[career] = true
			end
			for _, career in ipairs(unlock.add_careers) do
				if not existing[career] then
					item.can_wield[#item.can_wield + 1] = career
					existing[career] = true
				end
			end
			mod:info("Unlocked %s for: %s", unlock.item_key, table.concat(unlock.add_careers, ", "))
		else
			mod:warning("Cannot unlock %s — not found in ItemMasterList", unlock.item_key)
		end
	end
end

_apply_weapon_unlocks()

-- ============================================================
-- Custom skin registration
-- ============================================================

-- Registry of cwv_es_dual_swords skin keys (default + the 17 Kruber 1h-sword
-- illusion clones registered by `_register_kruber_1h_sword_dual_illusions`).
-- INERT MARKER as of v0.1.145 — no runtime hook consumes it. Previously read by
-- a `BackendUtils.get_item_units` right→left mirror that worked around the skin
-- entries omitting `left_hand_unit`; the mirror and its callers were removed
-- when the skins gained `left_hand_unit` directly and switched to the
-- `display_dual_weapons` rig (see `J_LEFTWEAPONATTACH_INVESTIGATION.md`).
-- Kept declared here in case a future hook needs to filter on
-- cwv_es_dual_swords skin lineage; safe to remove if unused 6 months out.
local _kruber_1h_dual_skin_keys = {}

-- QUESTION: skin_only entries (e.g. cwv_es_longsword_nordland) are NOT skipped
-- here — only def.no_skin gates skin registration. That's deliberate: skin_only
-- entries exist precisely to provide a selectable cosmetic skin without giving
-- the player the inventory item itself. Documented for clarity.
local function _register_variant_skins()
	if not WeaponSkins then return end
	for _, def in ipairs(_variant_definitions) do
		if def.no_skin then goto skip_skin end
		local skin_key = def.item_key .. "_skin"
		-- ALWAYS overwrite (no `if not WeaponSkins.skins[skin_key]` guard) so
		-- partial reloads or earlier mod versions don't leave a stale skin entry
		-- without our newer fields (e.g. ammo_unit added in 0.1.60).
		--
		-- For ammo weapons (e.g. javelin variants) we MUST mirror ammo_unit
		-- into the skin entry. BackendUtils.get_item_units overwrites
		-- units.ammo_unit with skin_template.ammo_unit unconditionally when a
		-- skin is set, so an absent field on the skin nukes the inherited
		-- value from the base ItemMasterList entry. Downstream the previewer
		-- does `left_hand_unit = ammo_unit` for is_ammo_weapon items and then
		-- concatenates "_3p" — nil ammo_unit crashes that line. Fall back to
		-- def.left_hand_unit (the held model) when ammo_unit isn't set so the
		-- spear/javelin/etc. swap still drives the held + thrown visual.
		-- Defense in depth: BackendUtils.get_item_units overwrites a whole set
		-- of fields from skin_template, not just ammo_unit. Mirror them all from
		-- the base ItemMasterList entry when the variant doesn't override —
		-- prevents the throw projectile / pickup spawn paths from getting nil
		-- once the held-model crash is past.
		--
		-- v0.1.182: gated the def.left_hand_unit fallback on `base.ammo_unit`.
		-- For variants whose base weapon DOESN'T have ammo_unit (e.g. brace of
		-- pistols, repeating pistols — `wh_brace_of_pistols` has no
		-- ammo_unit), forcing one in via def.left_hand_unit triggers
		-- GearUtils.spawn_inventory_unit's `fassert(ammo_unit_attachment_node_linking)`
		-- — the brace template defines ammo_data with `ammo_hand = "right"`
		-- but no ammo_unit_attachment_node_linking (because vanilla
		-- never uses ammo_unit there). Crash GUID 2df233ae-80f6-40d3-aa58-e98417f2ad8f.
		-- Now: only default to def.left_hand_unit when base has ammo_unit;
		-- otherwise leave nil and let vanilla's no-ammo_unit path run.
		local base = (ItemMasterList and ItemMasterList[def.base_weapon]) or {}
		local ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)
		local hud_icon = def.hud_icon or "weapon_generic_icon_axe1h"
		local inventory_icon = def.inventory_icon or "icon_wpn_dw_shield_01_axe"
		local rarity = def.rarity or "exotic"
		-- display_unit is the LINK UNIT the LootItemUnitPreviewer spawns first
		-- as the spinning pivot in the weapon-customization preview pane. It's
		-- a vanilla "stage" mesh (e.g. `display_2h_swords` for greatswords).
		-- `_spawn_link_unit` reads `item_data.display_unit` then
		-- `WeaponSkins.skins[skin].display_unit` and bails with a warning if
		-- both are nil — the weapon units have nothing to attach to, so they
		-- don't render. Vanilla WEAPON entries (e.g. `es_bastard_sword` in
		-- `item_master_list_lake.lua:186`) DON'T carry `display_unit` on the
		-- weapon's row — only weapon_skin rows do (`es_bastard_sword_skin_01`
		-- has `display_unit = "units/weapons/weapon_display/display_2h_swords"`).
		-- v0.1.99 tried `base.display_unit` and got nil for every variant;
		-- the picker stayed invisible (log: "Couldn't find any display unit
		-- for item cwv_es_longsword_skin"). Resolve by scanning ItemMasterList
		-- for any vanilla weapon_skin whose `matching_item_key` matches our
		-- `base_weapon` and copying its `display_unit`. Per-variant
		-- `def.display_unit` overrides if set.
		local display_unit = def.display_unit
		if not display_unit and ItemMasterList then
			for _, entry in pairs(ItemMasterList) do
				if entry.item_type == "weapon_skin"
						and entry.matching_item_key == def.base_weapon
						and entry.display_unit then
					display_unit = entry.display_unit
					break
				end
			end
		end

		-- DUAL-WIELD DISPLAY RIG.
		-- The cosmetic illusion picker attaches each hand's weapon unit to a
		-- named node on the `display_unit` pivot. Single-sword rigs only author
		-- `j_rightweaponattach`; the previewer crashes with `[Script Error]:
		-- j_leftweaponattach` if it tries to attach the left hand against one.
		-- The lookup loop above can return a wrong-family rig (vanilla
		-- dual-wield IML weapon_skin entries often don't set display_unit, so
		-- the loop can fall through to a sibling skin's value), so override
		-- here per-variant.
		--
		-- `_force_display_unit` maps each cwv item_key to the dual-attach rig
		-- vanilla uses for the matching weapon family. All listed rigs are
		-- known to author both `j_rightweaponattach` and `j_leftweaponattach`
		-- (proven by the rig appearing in `weapon_skins.lua` for a vanilla
		-- weapon whose cosmetic picker is shipped + working). See
		-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem and
		-- `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
		-- for the rig-per-family table.
		local _force_display_unit = {
			-- Identical-mesh empire short-swords; vanilla precedent: we_dual_sword_skin_01 (`weapon_skins.lua:5750`)
			cwv_es_dual_swords    = "units/weapons/weapon_display/display_dual_weapons",
			-- Identical-mesh hatchets; vanilla precedent: dw_dual_axe_skin_01 (`weapon_skins.lua:2364`)
			cwv_es_dual_axes      = "units/weapons/weapon_display/display_dual_axes",
			-- Identical-mesh empire maces; vanilla precedent: dual_wield_hammers
			-- skins in `weapon_skins_bless.lua:395` use display_dual_hammers.
			cwv_es_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
			cwv_wh_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
			-- Identical-mesh wh_1h_hammer Skullsplitters dual-wielded; vanilla
			-- precedent: wh_dual_hammer in `dual_wield_hammers_priest.lua:1720`
			-- sets the same rig on the priest dual-hammers weapon template,
			-- and vanilla Saltzpyre wh_dual_hammer cosmetic preview is a
			-- shipped, working feature.
			cwv_es_dual_warpriest_hammers = "units/weapons/weapon_display/display_dual_hammers",
			-- Mixed-mesh sword (right) + mace (left); vanilla precedent:
			-- dual_wield_hammer_sword.lua:1572 sets the same rig on the
			-- weapon template, and vanilla Kruber mace+sword cosmetic
			-- preview is a shipped, working feature.
			cwv_es_sword_and_mace = "units/weapons/weapon_display/display_dual_weapons",
			-- Skullsplitter (right) + Empire shield (left); vanilla precedent:
			-- wh_hammer_shield in `1h_hammers_shield_priest.lua` uses
			-- display_shield_hammer. Same rig works for our variant since
			-- the right-hand mesh is also a hammer (the wh_1h_hammer_01
			-- Skullsplitter).
			cwv_es_warpriest_hammer_shield = "units/weapons/weapon_display/display_shield_hammer",
		}
		local skin_left_hand_unit = def.left_hand_unit
		local forced_rig = _force_display_unit[def.item_key]
		if forced_rig then
			display_unit = forced_rig
			-- Inert legacy registry — see declaration above.
			if def.item_key == "cwv_es_dual_swords" then
				_kruber_1h_dual_skin_keys[skin_key] = true
			end
		end

		WeaponSkins.skins[skin_key] = {
			display_name              = def.item_key .. "_skin_name",
			description               = def.item_key .. "_description",
			rarity                    = rarity,
			right_hand_unit           = def.right_hand_unit,
			left_hand_unit            = skin_left_hand_unit,
			ammo_unit                 = ammo_unit,
			ammo_unit_3p              = def.ammo_unit_3p or base.ammo_unit_3p,
			projectile_units_template = def.projectile_units_template or base.projectile_units_template,
			pickup_template_name      = def.pickup_template_name or base.pickup_template_name,
			link_pickup_template_name = def.link_pickup_template_name or base.link_pickup_template_name,
			hud_icon                  = hud_icon,
			inventory_icon            = inventory_icon,
			display_unit              = display_unit,
			template                  = nil,
		}
		mod:info("Registered custom skin: %s (ammo_unit=%s, projectile=%s, display_unit=%s)",
			skin_key, tostring(ammo_unit),
			tostring(def.projectile_units_template or base.projectile_units_template),
			tostring(display_unit))

		-- ItemMasterList registration for the skin entry. WITHOUT this,
		-- vanilla `HeroWindowItemCustomization._apply_skin_to_item` (the
		-- inventory illusion picker) does `ItemMasterList[skin_key]`, gets
		-- nil, and crashes with `attempt to index local 'item_data' (a nil
		-- value)` at the next field access. Same shape cosmetics_tweaker
		-- uses for its custom illusions (see `_register_custom_illusions`).
		-- The v0.1.87 default-rarity-skin gate exposed this latent bug:
		-- previously a default-rarity blacksmith never opened the illusion
		-- picker because the item was treated as locked, so the missing
		-- ItemMasterList entry was never reached.
		if ItemMasterList and not rawget(ItemMasterList, skin_key) then
			-- matching_item_key MUST resolve to an entry with a valid template:
			-- vanilla `_apply_skin_to_item` does
			-- `ItemHelper.get_template_by_item_name(matching_item_key)` and
			-- crashes on missing templates with "Requested template for item
			-- <key> which does not exist". Use `def.base_weapon` — the
			-- vanilla weapon every cwv variant clones from, always present in
			-- ItemMasterList with a real template (e.g. `bastard_sword_template`).
			-- DON'T use `def.item_key`: skin_only variants
			-- (e.g. cwv_es_longsword_nordland) skip the `_auto_register_all`
			-- mirror so their item_key is NOT in ItemMasterList. v0.1.91 used
			-- item_key and crashed when applying a skin_only variant's
			-- illusion (GUID ca46d7b2-65b8-41b2-b16b-d71b6dcb9be6).
			ItemMasterList[skin_key] = {
				-- Explicit `key` and `name`. Vanilla `parse_item_master_list`
				-- (`item_master_list.lua:109`) sets these on every entry at
				-- boot via `item.key = key; item.name = key`. We register
				-- AFTER boot, so without these explicit assignments
				-- `item_data.key` is nil and `LootItemUnitPreviewer._load_item_units`
				-- (line 254) `item_key = item_data.key or item.key` falls
				-- through to nil → `ItemMasterList[nil]` → silent failure
				-- chain ending in invisible preview.
				key               = skin_key,
				name              = skin_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = def.base_weapon,
				rarity            = rarity,
				display_name      = def.item_key .. "_skin_name",
				description       = def.item_key .. "_description",
				right_hand_unit   = def.right_hand_unit,
				left_hand_unit    = skin_left_hand_unit,
				-- display_unit is required by `LootItemUnitPreviewer._spawn_link_unit`
				-- (line 467, 472). The previewer reads it from the item_data
				-- AND from the WeaponSkins.skins entry — set it on both.
				-- Without it the link unit fails to spawn and weapon units have
				-- nothing to attach to, so the picker preview is empty.
				display_unit      = display_unit,
				hud_icon          = hud_icon,
				inventory_icon    = inventory_icon,
				information_text  = "information_weapon_skin",
				can_wield         = def.careers,
				template          = nil,
			}
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local idx = #NetworkLookup.weapon_skins + 1
			rawset(NetworkLookup.weapon_skins, idx, skin_key)
			rawset(NetworkLookup.weapon_skins, skin_key, idx)
			mod:info("Injected '%s' into NetworkLookup.weapon_skins at index %d", skin_key, idx)
		end

		-- Mirror the skin key into NetworkLookup.item_names too. Vanilla
		-- weapon-skin backend RPCs and equipment-grid widgets do
		-- `NetworkLookup.item_names[key]` on the skin key — without this, any
		-- network sync path that references the skin key crashes per the same
		-- v0.1.24 weapon-item issue documented in the changelog.
		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
			local idx = #NetworkLookup.item_names + 1
			rawset(NetworkLookup.item_names, idx, skin_key)
			rawset(NetworkLookup.item_names, skin_key, idx)
		end
		::skip_skin::
	end
end

_register_variant_skins()

local function _empty_skin_tiers()
	return {
		default   = {},
		plentiful = {},
		common    = {},
		rare      = {},
		exotic    = {},
		unique    = {},
	}
end

local function _register_cwv_skin_combinations()
	if not WeaponSkins or not WeaponSkins.skin_combinations then return end

	-- Each item_type gets its own skin_combination_table seeded with the
	-- variant's auto-generated `<item_key>_skin` entries. Cross-character
	-- illusion functions (e.g. `_register_kruber_1h_sword_dual_illusions`)
	-- append additional skin keys to these tables after seeding.
	local _seed_targets = {
		cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
		cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
		cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
		cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
		cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
		cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
		cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
		cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
		cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
		cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
		cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
		cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
		cwv_es_maul                    = "cwv_es_maul_skins",
		cwv_es_poleaxe                 = "cwv_es_poleaxe_skins",
		cwv_es_rapier                  = "cwv_es_rapier_skins",
		cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
		cwv_es_musket                    = "cwv_es_musket_skins",
		cwv_es_musket_old                = "cwv_es_musket_old_skins",
	}

	local seeded = {}
	for item_type, table_name in pairs(_seed_targets) do
		seeded[table_name] = _empty_skin_tiers()
		for _, def in ipairs(_variant_definitions) do
			if def.item_type == item_type then
				local skin_key = def.item_key .. "_skin"
				local rarity = def.rarity or "exotic"
				local tier = seeded[table_name][rarity]
				if tier then
					tier[#tier + 1] = skin_key
				end
			end
		end
		WeaponSkins.skin_combinations[table_name] = seeded[table_name]
		mod:info("Registered %s skin_combination_table", table_name)
	end
end

_register_cwv_skin_combinations()

-- ============================================================
-- Cross-character greatsword illusions
-- ============================================================

local _es_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local _wh_careers = { "wh_zealot", "wh_bountyhunter", "wh_captain" }

local _custom_illusions = {
	-- Saltzpyre greatsword models on Kruber's greatsword
	{ skin_key = "cwv_es_2h_sword_wh_01",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_01",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_03",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_03",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_02", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_02", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04_magic_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04_magic_01", can_wield = _es_careers },

	-- Kruber greatsword models on Saltzpyre's greatsword
	{ skin_key = "cwv_wh_2h_sword_es_01",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_01",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_02", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_02", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_03", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_03", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_05",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_05",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_06",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_06",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03_magic_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03_magic_01", can_wield = _wh_careers },

	-- Vanilla 2h-sword skins as illusions for the cwv Imperial Longsword
	-- (cwv_imperial_longsword_skins combo table). matching_weapon stays
	-- "es_bastard_sword" so the vanilla template lookup in
	-- `_apply_skin_to_item` resolves to bastard_sword_template (the
	-- Imperial Longsword's moveset). target_combo overrides the auto-resolved
	-- combo table so these skins land in the cwv picker instead of vanilla
	-- es_bastard_sword's. Initial display_name / description fall through
	-- to the source vanilla skin's localization keys — user will rename
	-- these as they review.
	-- Kruber greatsword (es_2h_sword) skins:
	{ skin_key = "cwv_il_es_01",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_02",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_03",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	-- Curated-variant mesh assignments (must NOT collide with vanilla clones):
	--   Recruit Longsword   → wpn_empire_2h_sword_04_t1 (= es_2h_sword_skin_05)
	--   Nordland Claymore   → wpn_empire_2h_sword_03_t2 (= es_2h_sword_skin_04)
	--   Black Guard Blade   → wpn_empire_2h_sword_03_t2 (= es_2h_sword_skin_04 — currently shares mesh with Nordland; user knows, will resolve elsewhere)
	-- Drop vanilla clones that duplicate a curated variant by mesh path:
	-- cwv_il_es_04 / cwv_il_es_05 / cwv_il_es_06 (the latter shares mesh with
	-- es_2h_sword_skin_06's wpn_greatsword — kept dropped as a conservative
	-- placeholder until user-directed). Runed variants are always kept since
	-- their rune detailing reads as visually distinct from the bare mesh.
	{ skin_key = "cwv_il_es_04_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_04_runed_02", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	-- Saltzpyre greatsword (wh_2h_sword) skins:
	{ skin_key = "cwv_il_wh_01",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_02",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_03",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_04",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_04",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05_runed_02", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },

	-- Kruber greathammer (es_2h_hammer) skins as illusions on the curated
	-- `cwv_es_warpriest_hammer` variant — give the rescaled 2H mesh as a
	-- cosmetic option for the new 1H priest-hammer Kruber clone. Sources used:
	-- skin_01, _02, _03, _04 (+_runed_01, _runed_02), _06 (+_runed_01) — 8
	-- entries. Single-hand variant, so no off-hand override needed.
	-- `matching_weapon = "wh_1h_hammer"` so vanilla `_apply_skin_to_item` finds
	-- a real template (`one_handed_hammer_priest_template`); `target_combo`
	-- routes the skin into the variant's curated picker.
	-- Note: 2H model in a 1H slot will read oversized in 3P — by design.
	-- HISTORICAL: in v0.1.151 these 8 sources were registered as 24 entries
	-- across `es_1h_mace`, `es_mace_shield`, and `es_dual_wield_hammer_sword`
	-- (with off-hand overrides to preserve the shield / sword). v0.1.154 moved
	-- them onto the new dedicated variant per user request.
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_01",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_02",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_03",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_02", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

	-- Same 8 greathammer sources mirrored onto cwv_es_dual_warpriest_hammers
	-- (dual Skullsplitters). `mirror_to_left = true` mirrors the source's
	-- right_hand_unit into left_hand_unit so each hand gets the same
	-- greathammer mesh. `display_unit_override = display_dual_hammers`
	-- forces the dual-attach rig (source's display_2h_swords single-rig
	-- would crash on left attach — see J_LEFTWEAPONATTACH_INVESTIGATION.md).
	-- Scale and offset applied to both hands; matching_weapon = wh_dual_hammer
	-- so vanilla _apply_skin_to_item resolves to dual_wield_hammers_priest_template.
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_01",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_02",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_03",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_02", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },

	-- Same 8 greathammer sources on cwv_es_warpriest_hammer_shield (Skullsplitter
	-- and Shield). Right hand = source greathammer mesh; left hand = Empire shield
	-- (preserved via override since the source skins have no left_hand_unit set).
	-- `display_unit_override = display_shield_hammer` matches the variant's
	-- forced rig and the vanilla wh_hammer_shield template default.
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_01",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_02",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_03",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_02", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

	-- Sigmarite Greathammer (cwv_es_priest_greathammer) — Kruber 2H mesh +
	-- Saltzpyre wh_2h_hammer (Warrior Priest) moveset. The variant has its
	-- own item_type/skin_combination_table so vanilla skins of either source
	-- don't bleed into their native pickers. Both source families are 2H
	-- greathammers of comparable size, so NO scale/offset overrides needed.
	-- matching_weapon = "wh_2h_hammer" so `_apply_skin_to_item` resolves to
	-- two_handed_hammer_priest_template (the variant's actual moveset).
	-- Kruber's es_2h_hammer skins:
	{ skin_key = "cwv_es_priest_es_01",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_02",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_03",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_06",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_06_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	-- Saltzpyre's wh_2h_hammer skins (Warrior Priest greathammer):
	{ skin_key = "cwv_es_priest_wh_01",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_01_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_01_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_05", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_05", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_magic_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
}

local _custom_skin_keys = {}

local function _register_custom_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	for _, illusion in ipairs(_custom_illusions) do
		local skin_key = illusion.skin_key
		if _custom_skin_keys[skin_key] then goto continue end

		local source = WeaponSkins.skins[illusion.source_skin]
		if not source then
			mod:warning("Source skin '%s' not found in WeaponSkins — skipping %s", illusion.source_skin, skin_key)
			goto continue
		end

		-- Hand-unit overrides: when the source skin's hand units don't match
		-- the matching_weapon's slot shape (e.g. greathammer source has only
		-- right_hand_unit but target is mace+shield which needs left_hand_unit),
		-- the illusion entry can specify explicit overrides. Use case: cross-
		-- type illusions where you want one half of the source's model but
		-- preserve the target's other half (a default shield for mace+shield,
		-- a default sword for mace+sword, etc.).
		--
		-- `mirror_to_left = true` is a convenience flag for identical-mesh
		-- dual-wield targets: sets left_hand_unit = right_hand_unit dynamically
		-- (since the source's right_hand_unit varies per source skin and can't
		-- be hardcoded in a static illusion entry). Mirrors the dual_swords/
		-- dual_axes/dual_maces patterns elsewhere in the mod.
		local right_unit = illusion.right_hand_unit_override or source.right_hand_unit
		local left_unit  = illusion.left_hand_unit_override  or source.left_hand_unit
		if illusion.mirror_to_left then left_unit = right_unit end

		-- `display_unit_override`: force a specific display rig on the cloned
		-- skin entry (vs inheriting from source). Required when the source's
		-- rig doesn't author both attach nodes for the target's slot shape —
		-- e.g. greathammer source uses display_2h_swords (right-only rig),
		-- but our cwv dual / shield targets need display_dual_hammers /
		-- display_shield_hammer respectively. See
		-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.
		local effective_display_unit = illusion.display_unit_override or source.display_unit

		local iml_entry = {
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = illusion.matching_weapon,
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = effective_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = right_unit,
			left_hand_unit    = left_unit,
			template          = source.template,
			can_wield         = illusion.can_wield,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[skin_key] = iml_entry

		local ws_entry = {
			description            = source.description,
			display_name           = source.display_name,
			display_unit           = effective_display_unit,
			hud_icon               = source.hud_icon,
			inventory_icon         = source.inventory_icon,
			rarity                 = source.rarity,
			right_hand_unit        = right_unit,
			left_hand_unit         = left_unit,
			template               = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[skin_key] = ws_entry

		-- target_combo: explicit override for the skin_combination_table this
		-- illusion gets appended to. Used when the illusion lives on a
		-- different weapon than its `matching_weapon` — e.g. vanilla 2h-sword
		-- skins added to `cwv_imperial_longsword_skins` while keeping
		-- `matching_weapon = "es_bastard_sword"` so vanilla template lookups
		-- still resolve to bastard_sword_template (the Imperial Longsword's
		-- moveset). Without this override, `_register_custom_illusions`
		-- would resolve the combo table from the matching_weapon's entry
		-- (e.g. es_bastard_sword_skins) which is the wrong target.
		local target_combo = illusion.target_combo
		if not target_combo then
			local weapon_data = ItemMasterList[illusion.matching_weapon]
			if weapon_data and weapon_data.skin_combination_table then
				target_combo = weapon_data.skin_combination_table
			end
		end
		if target_combo then
			local combos = WeaponSkins.skin_combinations[target_combo]
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = skin_key
				end
			end
		end

		-- REVIEW: NetworkLookup.weapon_skins has an error-throwing __index per
		-- CHANGELOG v0.1.12 — `tbl[#tbl + 1] = ...` and `tbl[skin_key] = ...` set
		-- new keys, which goes through __newindex (not __index) and is fine. But
		-- `tbl[skin_key] = #tbl` reads `#tbl` AFTER the previous assignment, so
		-- the reverse-lookup index points at the just-written entry — correct,
		-- but slightly fragile. Pattern at line 467-471 uses an explicit `idx`
		-- variable; using rawset there matches CHANGELOG guidance. Consider
		-- aligning these two code paths to use the same rawset-with-explicit-idx
		-- form.
		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local tbl = NetworkLookup.weapon_skins
			tbl[#tbl + 1] = skin_key
			tbl[skin_key] = #tbl
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, skin_key)
			rawset(tbl, skin_key, idx)
		end

		_custom_skin_keys[skin_key] = true
		mod:info("Registered custom illusion: %s (from %s) -> %s", skin_key, illusion.source_skin, illusion.matching_weapon)
		::continue::
	end
end

_register_custom_illusions()

-- ============================================================
-- Kruber 1h sword cosmetics → cwv_es_dual_swords illusions
-- ============================================================
-- Each vanilla `es_1h_sword_skin_*` is cloned into a new skin keyed
-- `cwv_es_dual_swords_es_1h_sword_skin_*` and registered as an illusion
-- option on `cwv_es_dual_swords`. The right-hand mesh is copied from the
-- source skin; the left hand mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_weapons"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_swords` —
-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). See `DEVELOPMENT.md` "Dual-wield variants
-- — display rig requirements" for the rule, and
-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem on the
-- ~20-version saga that surfaced it (v0.1.122 → v0.1.145).
--
-- `_kruber_1h_dual_skin_keys` retained as an inert registry marker (no
-- runtime consumer; kept in case a future hook needs to filter on
-- cwv_es_dual_swords skin lineage).

local function _register_kruber_1h_sword_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_1h_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_dual_swords_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		-- Mirror right_hand_unit → left_hand_unit so the picker (and
		-- in-game) renders two identical swords. Force display_unit to
		-- display_dual_weapons (the rig vanilla we_dual_sword_skin_*
		-- uses) — the source es_1h_sword skin's display_unit is
		-- display_1h_swords (single-sword rig with no j_leftweaponattach),
		-- which would crash the previewer on left attach.
		local dual_display_unit = "units/weapons/weapon_display/display_dual_weapons"
		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_dual_swords",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = dual_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			left_hand_unit    = source.right_hand_unit,
			template          = source.template,
			can_wield         = _es_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = dual_display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			left_hand_unit  = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		_kruber_1h_dual_skin_keys[new_key] = true

		local combos = WeaponSkins.skin_combinations.cwv_es_dual_swords_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Kruber 1h sword cosmetics as cwv_es_dual_swords illusions", registered)
end

_register_kruber_1h_sword_dual_illusions()

-- ============================================================
-- Saltzpyre 1h axe cosmetics → cwv_es_dual_axes illusions
-- ============================================================
-- Each vanilla `wh_1h_axe_skin_*` is cloned into a new skin keyed
-- `cwv_es_dual_axes_<source_key>` and registered as an illusion option on
-- `cwv_es_dual_axes`. The right-hand axe mesh is copied from the source
-- skin; the left hand mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_axes"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_axes` —
-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). Vanilla precedent: `dw_dual_axe_skin_01`
-- (`weapon_skins.lua:2364`) uses the same rig with both hands set.
-- See `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
-- for the full rule and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the
-- post-mortem on the rig requirement.

local function _register_saltzpyre_1h_axe_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "wh_1h_axe" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_dual_axes_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		-- Mirror right_hand_unit → left_hand_unit so the picker (and
		-- in-game) renders two identical axes. Force display_unit to
		-- display_dual_axes (single-axe `display_1h_axes` from the source
		-- lacks j_leftweaponattach and would crash the previewer).
		local dual_display_unit = "units/weapons/weapon_display/display_dual_axes"
		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_dual_axes",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = dual_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			left_hand_unit    = source.right_hand_unit,
			template          = source.template,
			can_wield         = _es_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = dual_display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			left_hand_unit  = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_dual_axes_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Saltzpyre 1h axe cosmetics as cwv_es_dual_axes illusions", registered)
end

_register_saltzpyre_1h_axe_dual_illusions()

-- ============================================================
-- Empire 1h-mace cosmetics → cwv_es_dual_maces + cwv_wh_dual_maces illusions
-- ============================================================
-- Each vanilla `es_1h_mace_skin_*` is cloned into TWO new skin keys —
-- `cwv_es_dual_maces_<source_key>` (Kruber's variant) and
-- `cwv_wh_dual_maces_<source_key>` (Saltzpyre's variant) — and each clone
-- is registered as an illusion option in the matching variant's picker.
-- The right-hand mace mesh is copied from the source skin; the left hand
-- mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_hammers"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_hammer` —
-- a single-hand rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). Vanilla precedent: Bardin's dual-hammer
-- skins in `weapon_skins_bless.lua:395` use the same rig with both
-- hands set. See `DEVELOPMENT.md` "Dual-wield variants — display rig
-- requirements" and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.

local function _register_es_1h_mace_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_1h_mace" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	-- Two-target registration: each source skin produces a clone for both
	-- variants, routed to the variant's curated picker via matching_item_key.
	-- Listed in the order the picker should display.
	local _targets = {
		{ prefix = "cwv_es_dual_maces_", matching = "cwv_es_dual_maces", combo = "cwv_es_dual_maces_skins", careers = _es_all_careers },
		{ prefix = "cwv_wh_dual_maces_", matching = "cwv_wh_dual_maces", combo = "cwv_wh_dual_maces_skins", careers = _wh_all_careers },
	}

	local total = 0
	for _, target in ipairs(_targets) do
		local registered = 0
		for _, source_key in ipairs(source_keys) do
			local new_key = target.prefix .. source_key
			if _custom_skin_keys[new_key] then goto continue end

			local source = WeaponSkins.skins[source_key]
			if not source or not source.right_hand_unit then goto continue end

			-- Mirror right_hand_unit → left_hand_unit so the picker (and
			-- in-game) renders two identical maces. Force display_unit to
			-- display_dual_hammers — single-hand `display_1h_hammer` from
			-- the source lacks j_leftweaponattach and would crash the
			-- previewer on left attach.
			local dual_display_unit = "units/weapons/weapon_display/display_dual_hammers"
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = target.matching,
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = dual_display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				left_hand_unit    = source.right_hand_unit,
				template          = source.template,
				can_wield         = target.careers,
			}
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry

			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = dual_display_unit,
				hud_icon        = source.hud_icon,
				inventory_icon  = source.inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				left_hand_unit  = source.right_hand_unit,
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry

			local combos = WeaponSkins.skin_combinations[target.combo]
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end

			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end

			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end

			_custom_skin_keys[new_key] = true
			registered = registered + 1
			total = total + 1
			::continue::
		end
		mod:info("Registered %d empire 1h mace cosmetics as %s illusions", registered, target.matching)
	end

	mod:info("Total: %d dual-mace illusion entries (%d source skins × %d variants)", total, #source_keys, #_targets)
end

_register_es_1h_mace_dual_illusions()

-- ============================================================
-- Empire mace+sword's mace meshes → cwv_es_maul illusions
-- ============================================================
-- The Maul's cosmetic options are the MACE HALF (right_hand_unit) of
-- vanilla `es_dual_wield_hammer_sword` (mace+sword) skins — NOT the
-- separate `es_1h_mace` skin pool. This gives the Maul a curated set
-- of 3-4 chunky mace heads that match the variant's identity (a 2H
-- maul cloned from the mace+sword's club), instead of the smaller
-- flanged maces from Kruber's 1H mace pool.
--
-- Mace+sword skin → mace mesh (right_hand_unit only):
--   skin_01           → wpn_emp_mace_04_t2 (rare; same as the Maul's default mesh)
--   skin_02           → wpn_emp_mace_05_t2 (exotic)
--   skin_02_runed_01  → wpn_emp_mace_05_t2_runed_01 (unique)
--   skin_02_magic_01  → wpn_emp_mace_04_t3_magic_01 (magic)
--
-- Single-handed (NOT mirrored) — the Maul wields one-handed via the
-- wizard mace template's right_hand_unit. left_hand_unit from the
-- source is DISCARDED (the sword half doesn't belong on a Maul).
-- Source display_unit is overridden to display_1h_hammer (single-rig)
-- because the source's mace+sword display_unit authors both attach
-- nodes and would try to spawn a non-existent left unit.

local function _register_macesword_mace_maul_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_dual_wield_hammer_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local single_hand_display = "units/weapons/weapon_display/display_1h_hammer"

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_maul_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_maul",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = single_hand_display,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			-- Deliberately no left_hand_unit — source's left is the
			-- sword half of the mace+sword, which doesn't belong on a
			-- single-handed Maul. nil here means
			-- BackendUtils.get_item_units leaves the equipped variant's
			-- own left (none, for Maul) intact.
			template          = source.template,
			can_wield         = _es_all_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = single_hand_display,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_maul_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d mace+sword mace meshes as cwv_es_maul illusions", registered)
end

_register_macesword_mace_maul_illusions()

-- ============================================================
-- Empire halberd cosmetics → cwv_es_poleaxe illusions (single-handed
-- harvest: each es_halberd_skin_* registered as an illusion option on
-- the Poleaxe variant).
-- ============================================================

local function _register_halberd_poleaxe_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_halberd" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_poleaxe_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_poleaxe",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = source.display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			template          = source.template,
			can_wield         = _es_all_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = source.display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_poleaxe_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d empire halberd cosmetics as cwv_es_poleaxe illusions", registered)
end

_register_halberd_poleaxe_illusions()

-- ============================================================
-- Saltzpyre fencing-sword cosmetics → cwv_es_rapier illusions
-- ============================================================
-- Each vanilla `wh_fencing_sword_skin_*` registered as an illusion on
-- the Rapier variant. Source skins always carry a pistol on
-- left_hand_unit; we FORCE left_hand_unit = invisible weapon on every
-- clone so the variant's "no pistol" identity holds across illusions.
--
-- Source's `display_fencing_swords` rig is preserved (it authors both
-- right + left attach nodes; the invisible left unit attaches but is
-- not visible).

local function _register_rapier_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	-- Illusions DELIBERATELY do not set `left_hand_unit`. Reason: the
	-- cosmetic picker's `_load_item_units` (line 281) only spawns a
	-- left-hand unit when `item_units.left_hand_unit` is truthy. With
	-- left_hand_unit nil on the illusion's skin entry,
	-- `BackendUtils.get_item_units` overwrites the inherited brace pistol
	-- with nil (line 174 of `backend_utils.lua` — the overwrite is
	-- unconditional, including nil), so the picker skips left-hand spawn
	-- entirely. No spawn → no `j_leftweaponattach` lookup → no crash.
	-- Crash GUID `962fe355-a0d4-43fd-9a29-bd64fca6a0ac` (v0.1.191).
	--
	-- The variant's DEFAULT skin (cwv_es_rapier_skin, set on equip when
	-- no illusion is applied) still carries `left_hand_unit = invisible_pistol`
	-- via the variant's IML entry — that's where the no-pistol identity is
	-- enforced. When an illusion IS applied, both the picker AND in-game
	-- skip the left spawn entirely (no invisible pistol attached, no
	-- visible difference since it was invisible anyway).

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "wh_fencing_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_rapier_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_rapier",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = source.display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			-- left_hand_unit DELIBERATELY omitted (see comment above).
			template          = source.template,
			can_wield         = _es_all_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = source.display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			-- left_hand_unit DELIBERATELY omitted (see comment above).
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_rapier_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d fencing-sword cosmetics as cwv_es_rapier illusions (pistol forced invisible)", registered)
end

_register_rapier_illusions()

-- ============================================================
-- Empire shield options → cwv_es_longsword_shield illusions
-- ============================================================
-- Imperial Longsword + Shield variant carries a curated set of Empire
-- shield + Imperial Longsword pairings. Each entry is a HARDCODED pair of
-- (Empire shield mesh, Imperial Longsword sword mesh) — no IML scan.
--
-- Why hardcoded: the previous implementation (v0.1.175 → v0.1.250) scanned
-- IML for `matching_item_key == "es_sword_shield"`, but that pool also
-- contains our `cwv_we_sword_shield` (elf wood-elf) variant's auto-
-- generated skin entries (they clone from the same base for template
-- reasons). Result: the picker showed elven shields among the Empire
-- options. v0.1.251 sidesteps the leak by enumerating Empire shield
-- meshes directly.
--
-- Pairing rationale (best-effort thematic without localization access):
--   * Plain state-issue shields (01_t1, 02) → Recruit Longsword
--     (wpn_2h_sword_04_t1) — both basic Reikland regiment kit.
--   * Mid-tier sealhide / coastal-style shields (03 + runed variant) →
--     Nordland Claymore (wpn_greatsword) — coastal regiment theme.
--   * Ornate / runed / magic shields (04, 04_magic_01, 05, 02_runed_01) →
--     Black Guard Blade (wpn_2h_sword_03_t2) — knightly / Knights of
--     Morr theme.
-- Adjust the pairings below if the in-game shield names suggest a
-- different match.

-- Imperial Longsword sword meshes (Empire `es_2h_sword` family that the
-- 2H cwv_es_longsword variants use as their default looks).
local _ILS_RECRUIT_SWORD    = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1"
local _ILS_NORDLAND_SWORD   = "units/weapons/player/wpn_greatsword/wpn_greatsword"
local _ILS_BLACKGUARD_SWORD = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2"

-- Saltzpyre's greatsword (`wh_2h_sword`) meshes — same family used by the
-- 2H cwv_imperial_longsword cross-character illusions (CHANGELOG v0.1.113).
-- All distinct from the Imperial mesh family above.
local _ILS_WH_SWORD_01      = "units/weapons/player/wpn_empire_2h_sword_02_t1/wpn_2h_sword_02_t1"           -- wh skin_01 (plentiful)
local _ILS_WH_SWORD_02      = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2"           -- wh skin_02 (rare)
local _ILS_WH_SWORD_02_RUNE = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2_runed_01"  -- wh skin_02_runed_01 (unique)
local _ILS_WH_SWORD_03      = "units/weapons/player/wpn_empire_2h_sword_02_t3/wpn_2h_sword_02_t3"           -- wh skin_03 (common)
local _ILS_WH_SWORD_04      = "units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2"           -- wh skin_04 (exotic)
local _ILS_WH_SWORD_05      = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1"           -- wh skin_05 (exotic)
local _ILS_WH_SWORD_05_RUNE = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01"  -- wh skin_05_runed_01 (unique)

-- Each entry: { left = shield mesh, right = paired sword, rarity = picker tier, suffix = unique key fragment }.
-- `suffix` differentiates entries that share a shield (multiple swords
-- pair against the same shield mesh — recruit vs wh_01, etc.). Without
-- it, the per-shield key would collide and only the first registers.
local _IMPERIAL_LONGSWORD_SHIELD_PAIRINGS = {
	-- ── Imperial sword family ─────────────────────────────────────
	-- Plentiful / basic: Recruit Longsword + plain Reikland shields.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
	-- Rare / mid-tier: Nordland Claymore + sealhide-style shields.
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_NORDLAND_SWORD,   rarity = "rare",      suffix = "nordland" },
	-- Exotic: Black Guard Blade + ornate shields.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
	-- Unique (red illusion tier): runed shields.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "unique",    suffix = "blackguard" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_NORDLAND_SWORD,   rarity = "unique",    suffix = "nordland" },
	-- Magic (weave-forged): scorpion DLC's magic Empire shield.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "magic",     suffix = "blackguard" },

	-- ── Saltzpyre wh_2h_sword family (added v0.1.254) ─────────────
	-- Same wh meshes used by cwv_imperial_longsword cross-character
	-- illusions per CHANGELOG v0.1.113. Paired with rotating Empire
	-- shields by rarity tier so each Saltzpyre sword appears alongside
	-- a shield it'd plausibly be carried with.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_WH_SWORD_01,      rarity = "plentiful", suffix = "wh_01" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_WH_SWORD_03,      rarity = "common",    suffix = "wh_03" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_WH_SWORD_02,      rarity = "rare",      suffix = "wh_02" },
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_WH_SWORD_04,      rarity = "exotic",    suffix = "wh_04" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_WH_SWORD_05,      rarity = "exotic",    suffix = "wh_05" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_WH_SWORD_02_RUNE, rarity = "unique",    suffix = "wh_02_runed" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_WH_SWORD_05_RUNE, rarity = "unique",    suffix = "wh_05_runed" },
}

local function _register_imperial_longsword_shield_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local registered = 0
	for _, pair in ipairs(_IMPERIAL_LONGSWORD_SHIELD_PAIRINGS) do
		-- Key = `cwv_es_longsword_shield_<shield_tail>__<sword_suffix>`.
		-- Both fragments are required because multiple swords pair against
		-- the same shield (e.g. emp_shield_02 + recruit AND emp_shield_02
		-- + wh_03). Without the sword suffix the second registration would
		-- collide with the first and silently skip.
		local mesh_tail = pair.left:match("([^/]+)$") or pair.left
		local sword_frag = pair.suffix or "default"
		local new_key = "cwv_es_longsword_shield_" .. mesh_tail .. "__" .. sword_frag
		if _custom_skin_keys[new_key] then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_longsword_shield",
			rarity            = pair.rarity,
			display_name      = "cwv_es_longsword_shield_skin_name",
			description       = "cwv_es_longsword_shield_description",
			display_unit      = "units/weapons/weapon_display/display_shield_sword",
			hud_icon          = "weapon_generic_icon_sword_and_sheild",
			inventory_icon    = "icon_wpn_empire_shield_02_sword",
			information_text  = "information_weapon_skin",
			right_hand_unit   = pair.right,
			left_hand_unit    = pair.left,
			template          = "one_handed_sword_shield_template_2",
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_longsword_shield_description",
			display_name    = "cwv_es_longsword_shield_skin_name",
			display_unit    = "units/weapons/weapon_display/display_shield_sword",
			hud_icon        = "weapon_generic_icon_sword_and_sheild",
			inventory_icon  = "icon_wpn_empire_shield_02_sword",
			rarity          = pair.rarity,
			right_hand_unit = pair.right,
			left_hand_unit  = pair.left,
			template        = "one_handed_sword_shield_template_2",
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_longsword_shield_skins
		if combos then
			local tier = combos[pair.rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Empire shield + Imperial Longsword pairings on cwv_es_longsword_shield", registered)
end

_register_imperial_longsword_shield_illusions()

-- ============================================================
-- Empire hatchet + shield options → cwv_es_axe_shield illusions
-- ============================================================
-- Same pattern as the longsword+shield pool above. Each entry is a
-- HARDCODED pair of (Empire shield mesh, Empire hatchet mesh) — no IML
-- scan, to keep the pool curated and avoid leak from sibling cwv
-- variants that share the dr_shield_axe base.
--
-- Hatchet meshes come from the `wh_1h_axe` skin family (Saltzpyre's
-- 1H axe pool — Empire-style hatchets, same family the default
-- cwv_es_axe_shield + veteran variants already use). Shield meshes
-- are the same Empire shield set the longsword+shield picker uses.
--
-- The default-rarity (blacksmith) cwv_es_axe_shield seeds itself into
-- the pool but its appearance is locked by the blacksmith hook —
-- applied illusions visually no-op on it. The unique-rarity veteran
-- (and any future non-blacksmith Empire axe+shield variants sharing
-- item_type = "cwv_es_axe_shield") visibly swap to the picked combo.

do  -- scope mesh-path locals so they don't count against the Lua 5.1 200-local main-chunk limit

local _EAS_AXE_02_T1   = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1"           -- wh_1h_axe_skin_01 (common)
local _EAS_AXE_02_T2   = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2"           -- wh_1h_axe_skin_02 (rare)
local _EAS_AXE_02_T2_R = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2_runed_01"  -- wh_1h_axe_skin_02_runed_01 (unique)
local _EAS_AXE_03_T1   = "units/weapons/player/wpn_axe_03_t1/wpn_axe_03_t1"           -- wh_1h_axe_skin_03 (exotic)
local _EAS_AXE_03_T2   = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2"           -- wh_1h_axe_skin_04 (exotic)
local _EAS_AXE_03_T2_R = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01"  -- wh_1h_axe_skin_04_runed_01 (unique)
local _EAS_HATCHET_T1  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1" -- wh_1h_axe_skin_05 (plentiful)
local _EAS_HATCHET_T2  = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2" -- wh_1h_axe_skin_06 (exotic)

-- Each entry: { left = shield mesh, right = paired hatchet, rarity = picker tier, suffix = unique key fragment }.
-- `suffix` differentiates entries that share a shield mesh.
local _AXE_SHIELD_PAIRINGS = {
	-- Plentiful: state-issue shields + plain hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_HATCHET_T1,  rarity = "plentiful", suffix = "hatchet_t1" },
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_AXE_02_T1,   rarity = "plentiful", suffix = "axe_02_t1" },
	-- Common: Reikland-issue shields + plain hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",          right = _EAS_HATCHET_T1,  rarity = "common",    suffix = "hatchet_t1" },
	-- Rare: mid-tier sealhide shields + tier-2 hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_AXE_02_T2,   rarity = "rare",      suffix = "axe_02_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_HATCHET_T2,  rarity = "rare",      suffix = "hatchet_t2" },
	-- Exotic: ornate shields + ornate hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T1,   rarity = "exotic",    suffix = "axe_03_t1" },
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_HATCHET_T2,  rarity = "exotic",    suffix = "hatchet_t2" },
	-- Unique (red illusion tier): runed shields + runed hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01", right = _EAS_AXE_02_T2_R, rarity = "unique",    suffix = "axe_02_t2_runed" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01", right = _EAS_AXE_03_T2_R, rarity = "unique",    suffix = "axe_03_t2_runed" },
	-- Magic (weave-forged): scorpion DLC's magic Empire shield.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01", right = _EAS_HATCHET_T2,  rarity = "magic",     suffix = "hatchet_t2" },
}

local function _register_axe_shield_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local registered = 0
	for _, pair in ipairs(_AXE_SHIELD_PAIRINGS) do
		-- Key = `cwv_es_axe_shield_<shield_tail>__<axe_suffix>`.
		-- Both fragments are required because multiple hatchets pair
		-- against the same shield mesh — without the axe suffix the
		-- per-shield key would collide and only the first registers.
		local mesh_tail = pair.left:match("([^/]+)$") or pair.left
		local axe_frag = pair.suffix or "default"
		local new_key = "cwv_es_axe_shield_" .. mesh_tail .. "__" .. axe_frag
		if _custom_skin_keys[new_key] then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_axe_shield",
			rarity            = pair.rarity,
			display_name      = "cwv_es_axe_shield_skin_name",
			description       = "cwv_es_axe_shield_description",
			display_unit      = "units/weapons/weapon_display/display_shield",
			hud_icon          = "weapon_generic_icon_axe_and_sheild",
			inventory_icon    = "icon_wpn_dw_shield_01_axe",
			information_text  = "information_weapon_skin",
			right_hand_unit   = pair.right,
			left_hand_unit    = pair.left,
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_axe_shield_description",
			display_name    = "cwv_es_axe_shield_skin_name",
			display_unit    = "units/weapons/weapon_display/display_shield",
			hud_icon        = "weapon_generic_icon_axe_and_sheild",
			inventory_icon  = "icon_wpn_dw_shield_01_axe",
			rarity          = pair.rarity,
			right_hand_unit = pair.right,
			left_hand_unit  = pair.left,
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_axe_shield_skins
		if combos then
			local tier = combos[pair.rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Empire shield + hatchet pairings on cwv_es_axe_shield", registered)
end

_register_axe_shield_illusions()

end  -- do (axe+shield illusion scope)

-- ============================================================
-- Musket cosmetic illusions (alternate handgun meshes)
-- ============================================================
-- Two cosmetic options for `cwv_es_musket`:
--   * Aunty Bessie — wpn_empire_handgun_t3 (es_handgun_skin_05)
--   * Von Meinkopt's Single-Shooter — wpn_empire_handgun_t2 (es_handgun_skin_04)
-- Both are vanilla `es_handgun` cosmetic skins. The variant ships with
-- the default rifle (wpn_empire_handgun_t1, "Reikland Repeater Rifle"
-- equivalent at base rarity); these illusions let the player swap to
-- the t2 / t3 silhouettes via the cosmetics picker.
--
-- Force-load the alternate handgun unit packages at mod init — same
-- Tuskgor pattern. Kruber's es_handgun loadout only auto-loads the t1
-- mesh; t2/t3 variants are skin-pool meshes that may not be in memory.
-- Without force-load, applying the illusion in-game would crash
-- "Resource not loaded" on first equip.

local _MUSKET_ILLUSIONS = {
	{
		key             = "cwv_es_musket_aunty_bessie",
		display_name    = "Aunty Bessie",  -- TODO: localize via mod display_names
		right_hand_unit = "units/weapons/player/wpn_empire_handgun_t3/wpn_empire_handgun_t3",
		inventory_icon  = "icon_wpn_empire_handgun_t3",
		rarity          = "exotic",
		source_skin     = "es_handgun_skin_05",
	},
	{
		key             = "cwv_es_musket_von_meinkopt_single_shooter",
		display_name    = "Von Meinkopt's Single-Shooter",
		right_hand_unit = "units/weapons/player/wpn_empire_handgun_t2/wpn_empire_handgun_t2",
		inventory_icon  = "icon_wpn_empire_handgun_t2",
		rarity          = "exotic",
		source_skin     = "es_handgun_skin_04",
	},
}

local function _force_load_musket_illusion_units()
	if not (Managers and Managers.package) then return end
	for _, illusion in ipairs(_MUSKET_ILLUSIONS) do
		local ok, err = pcall(function()
			Managers.package:load(illusion.right_hand_unit, "cwv_musket_illusion_" .. illusion.key, nil, true, true)
		end)
		if ok then
			mod:info("[cwv musket-illusion] force-loaded %s", illusion.right_hand_unit)
		else
			mod:warning("[cwv musket-illusion] failed to force-load %s: %s", illusion.right_hand_unit, tostring(err))
		end
		-- Also force-load _3p variant — handgun meshes have separate 3P units.
		local unit_3p = illusion.right_hand_unit .. "_3p"
		pcall(function()
			Managers.package:load(unit_3p, "cwv_musket_illusion_" .. illusion.key .. "_3p", nil, true, true)
		end)
	end
end

_force_load_musket_illusion_units()

local function _register_musket_handgun_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local display_unit = "units/weapons/weapon_display/display_1h_handguns"
	local registered = 0
	for _, illusion in ipairs(_MUSKET_ILLUSIONS) do
		local new_key = illusion.key
		if _custom_skin_keys[new_key] then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_musket",
			rarity            = illusion.rarity,
			-- Per-illusion display name — registered into _display_names
			-- below so the inventory shows "Aunty Bessie" / "Von Meinkopt's
			-- Single-Shooter" instead of the variant's generic name.
			display_name      = new_key .. "_name",
			description       = "cwv_es_musket_description",
			display_unit      = display_unit,
			hud_icon          = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
			inventory_icon    = illusion.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = illusion.right_hand_unit,
			template          = "musket_template",
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_musket_description",
			display_name    = new_key .. "_name",
			display_unit    = display_unit,
			hud_icon        = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
			inventory_icon  = illusion.inventory_icon,
			rarity          = illusion.rarity,
			right_hand_unit = illusion.right_hand_unit,
			template        = "musket_template",
		}

		-- Register display name so `Localize(<key>_name)` returns the
		-- human-readable name. The Localize hook earlier in the file reads
		-- _display_names[key].
		_display_names[new_key .. "_name"] = illusion.display_name

		local combos = WeaponSkins.skin_combinations.cwv_es_musket_skins
		if combos then
			local tier = combos[illusion.rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d musket handgun illusions on cwv_es_musket (Aunty Bessie + Von Meinkopt's Single-Shooter)", registered)
end

_register_musket_handgun_illusions()

-- ============================================================
-- Empire 1h sword + 1h mace → cwv_es_sword_and_mace illusions
-- ============================================================
-- Variant `cwv_es_sword_and_mace` is the inverse of vanilla mace+sword
-- (sword right, mace left). Cosmetic options pair each vanilla
-- `es_1h_sword` skin's mesh on the right hand with an `es_1h_mace`
-- skin's mesh on the left hand.
--
-- Both source pools have 8 skins each. We sort each by rarity
-- (common→plentiful→rare→exotic→unique→magic) then zip by index. The
-- distributions don't perfectly match (sword has 3 unique + 1 exotic,
-- mace has 2 unique + 2 exotic), so one pair (index 5) ends up
-- mismatched (sword unique × mace exotic). All 8 pair cleanly otherwise.
--
-- Display rig: `display_dual_weapons` is forced via the existing
-- `_force_display_unit[cwv_es_sword_and_mace]` entry on the variant's
-- auto-generated default skin. Each illusion clone here also explicitly
-- sets `display_unit` to `display_dual_weapons` (set on both IML and
-- WeaponSkins.skins entries — the previewer reads it via two chains and
-- needs it on both layers, per `feedback_cwv_dual_wield_display_rig.md`).

local _RARITY_ORDER = {
	common = 1, plentiful = 2, rare = 3, exotic = 4, unique = 5, magic = 6,
}

local function _register_sword_and_mace_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	-- Collect both source pools. We capture (skin_key, mesh, rarity) and
	-- sort by (rarity_priority, skin_key) for deterministic pairing order.
	local function _gather(matching_key)
		local pool = {}
		for skin_key, entry in pairs(ItemMasterList) do
			if type(entry) == "table"
					and entry.item_type == "weapon_skin"
					and entry.matching_item_key == matching_key
					and entry.right_hand_unit then
				pool[#pool + 1] = {
					skin_key = skin_key,
					mesh     = entry.right_hand_unit,  -- es_1h_mace stores mesh as right_hand_unit even though we put it on the left
					rarity   = entry.rarity or "exotic",
				}
			end
		end
		table.sort(pool, function(a, b)
			local ra, rb = _RARITY_ORDER[a.rarity] or 99, _RARITY_ORDER[b.rarity] or 99
			if ra ~= rb then return ra < rb end
			return a.skin_key < b.skin_key
		end)
		return pool
	end

	local swords = _gather("es_1h_sword")
	local maces  = _gather("es_1h_mace")

	-- Zip by index. If counts differ (currently both 8, but defensive
	-- against future vanilla DLC adding skins to one but not the other),
	-- iterate the smaller of the two; surplus on either side stays
	-- unpaired.
	local n = math.min(#swords, #maces)
	if n == 0 then return end

	local display_unit = "units/weapons/weapon_display/display_dual_weapons"

	local registered = 0
	for i = 1, n do
		local sword = swords[i]
		local mace  = maces[i]
		-- Compose a stable key from both source paths' mesh tail components.
		-- Pattern: cwv_es_sword_and_mace_<sword_mesh_tail>_<mace_mesh_tail>.
		local sword_tail = sword.mesh:match("([^/]+)/[^/]+$") or sword.mesh
		local mace_tail  = mace.mesh:match("([^/]+)/[^/]+$") or mace.mesh
		local new_key = "cwv_es_sword_and_mace_" .. sword_tail .. "_" .. mace_tail
		if _custom_skin_keys[new_key] then goto continue end

		-- Picker rarity inherits the sword's rarity (the right-hand "primary"
		-- of the pair). Mace rarity may differ for mismatched index pairs;
		-- sword's reads as the headline cosmetic.
		local rarity = sword.rarity

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_sword_and_mace",
			rarity            = rarity,
			-- Display name / description fall through to a generic
			-- "Sword and Mace" — auto-populated from the variant def's
			-- skin_display_name / description via _display_names registration.
			display_name      = "cwv_es_sword_and_mace_skin_name",
			description       = "cwv_es_sword_and_mace_description",
			display_unit      = display_unit,
			hud_icon          = "weapon_generic_icon_falken",
			inventory_icon    = "icon_es_dual_wield_hammer_sword_01",
			information_text  = "information_weapon_skin",
			right_hand_unit   = sword.mesh,
			left_hand_unit    = mace.mesh,
			template          = "sword_and_mace_template",
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_sword_and_mace_description",
			display_name    = "cwv_es_sword_and_mace_skin_name",
			display_unit    = display_unit,
			hud_icon        = "weapon_generic_icon_falken",
			inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
			rarity          = rarity,
			right_hand_unit = sword.mesh,
			left_hand_unit  = mace.mesh,
			template        = "sword_and_mace_template",
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_sword_and_mace_skins
		if combos then
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d sword+mace illusion pairs on cwv_es_sword_and_mace (1h sword right × 1h mace left, rarity-sorted zip)", registered)
end

_register_sword_and_mace_illusions()

mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
	local mirror = self._backend_mirror
	if not mirror or not mirror._unlocked_weapon_skins then return end
	for skin_key, _ in pairs(_custom_skin_keys) do
		mirror._unlocked_weapon_skins[skin_key] = true
	end
end)

-- ============================================================
-- Item creation helper (shared by give command)
-- ============================================================

local _registered_keys = {}

local function _build_entry(def, backend_id)
	-- rawget: every variant declares a base_weapon key that's expected to exist, but the
	-- crashify metamethod on a missing key would surface as an opaque crash here. Failing
	-- soft with a warning lets the mod skip variants whose base weapon isn't installed.
	local base = rawget(ItemMasterList, def.base_weapon)
	if not base then
		mod:warning("Base weapon '%s' not found in ItemMasterList", def.base_weapon)
		return nil
	end

	local entry = table.clone(base, true)

	-- `cwv_variant` is the cross-mod marker contract. Sibling mods
	-- (cosmetics_tweaker, weapon_tweaker, future) check `item_data.cwv_variant`
	-- in their hooks and SKIP item-name-keyed overrides when it's truthy. This
	-- exists because the clone inherits `entry.name` from the base weapon
	-- (e.g. cwv_es_longsword.name == "es_bastard_sword"), which would
	-- otherwise spuriously match a sibling mod's `_weapon_grip_offsets[name]`
	-- or `_breton_sword_thiccc` lookup.
	--
	-- WHY NOT just clobber entry.name/.key to def.item_key? Because vanilla
	-- code (e.g. world_hero_previewer.lua's equip_item at line 674) does
	-- `item_data = ItemMasterList[item.name]` for fallback lookups. Setting
	-- name = cwv_key meant the lookup returned nil and the equip path
	-- crashed in BackendUtils.get_item_units. See
	-- `feedback_cwv_clone_name_clobber.md` for the full incident log.
	entry.cwv_variant = true

	entry.display_name = def.item_key .. "_name"
	entry.description = def.item_key .. "_description"

	if def.right_hand_unit then
		entry.right_hand_unit = def.right_hand_unit
	end
	if def.left_hand_unit then
		entry.left_hand_unit = def.left_hand_unit
	end
	-- `no_left_hand = true` explicitly clears the inherited left_hand_unit
	-- from the clone. Used when the variant uses the BASE weapon's template
	-- (which mounts on a different hand than the variant) — e.g.
	-- `cwv_es_outrider_grenade_launcher` clones from `dr_deus_01` (Bardin
	-- trollhammer, left-hand-mount) but the cwv variant is right-hand-mount
	-- (blunderbuss). Without this flag, the inherited `left_hand_unit =
	-- "...wpn_dr_deus_01"` would render alongside our right-hand blunderbuss,
	-- giving Kruber TWO weapons in the preview. Distinct from
	-- `def.left_hand_unit = nil` (which the existing `if def.left_hand_unit`
	-- guard treats as "don't override" → inheritance kicks in).
	if def.no_left_hand then
		entry.left_hand_unit = nil
	end
	if def.inventory_icon then
		entry.inventory_icon = def.inventory_icon
	end
	if def.hud_icon then
		entry.hud_icon = def.hud_icon
	end
	if def.careers then
		entry.can_wield = def.careers
	end
	if def.template then
		entry.template = def.template
	end
	-- Always set entry.item_type to a unique cwv-prefixed key. Without this,
	-- the variant inherits the base's item_type (e.g. cwv_es_shortsword
	-- inherits "bw_dagger"), and any vanilla UI that does
	-- `Localize(item_data.item_type)` displays the BASE weapon's name
	-- ("Dagger") even though the variant is called "Shortsword". Setting
	-- entry.item_type to def.item_type (when explicit) or def.item_key (as
	-- fallback) ensures Localize hits the cwv-specific localization
	-- registered below in `_display_names`. See the "Naming flow for cwv
	-- variants" section in `DEVELOPMENT.md`.
	entry.item_type = def.item_type or def.item_key

	-- v0.1.311 tried `entry.slot_type = "cwv_dual"` (custom value) but the
	-- item then disappeared from both grids entirely — MIL or vanilla
	-- silently drops items with unrecognized slot_type. v0.1.312 reverts:
	-- the entry keeps its inherited slot_type ("ranged" for the musket).
	-- Cross-slot visibility comes from career-level "ranged" inclusion in
	-- slot_melee plus a post-filter on `get_filtered_items` that scopes
	-- which ranged items survive the melee filter (search "_CWV_CROSS_SLOT_PREFIXES").
	-- The `def.cross_slot` field on variants is still meaningful — it's
	-- used by the post-filter to identify allowlisted items.
	-- Per-item_type custom skin_combination_table. Each entry has its own
	-- table registered by `_register_cwv_skin_combinations` so the variant's
	-- cosmetics menu shows ONLY the curated set we wire up — vanilla skins
	-- of the base weapon don't bleed into the variant.
	local _item_type_to_skin_table = {
		cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
		cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
		cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
		cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
		cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
		cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
		cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
		cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
		cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
		cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
		cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
		cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
		cwv_es_maul                    = "cwv_es_maul_skins",
		cwv_es_poleaxe                 = "cwv_es_poleaxe_skins",
		cwv_es_rapier                  = "cwv_es_rapier_skins",
		cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
		cwv_es_musket                    = "cwv_es_musket_skins",
		cwv_es_musket_old                = "cwv_es_musket_old_skins",
	}
	if def.item_type and _item_type_to_skin_table[def.item_type] then
		entry.skin_combination_table = _item_type_to_skin_table[def.item_type]
	end
	-- CLARIFY: Clear required_dlc so non-DLC users (e.g. no "lake" DLC for
	-- bastard_sword-derived variants) can equip the variant. The actual model
	-- assets (wpn_empire_2h_sword_*, wpn_emp_gk_*) live in the base inventory
	-- package list, not in DLC-only packages, so the unit paths still resolve.
	-- POTENTIAL BUG: this is verified for the Empire greatsword units and
	-- es_sword_shield variants but NOT the Bretonnian units (wpn_emp_gk_shield_*)
	-- which DO require the lake DLC package to load. A non-lake-DLC user equipping
	-- a variant whose left/right unit lives only in lake's package would see the
	-- model fail to load.
	entry.required_dlc = nil

	local traits = def.traits or {}
	local properties = def.properties or {}
	local power_level = def.power_level or 300

	local traits_json = "["
	for i, t in ipairs(traits) do
		if i > 1 then traits_json = traits_json .. "," end
		traits_json = traits_json .. '"' .. t .. '"'
	end
	traits_json = traits_json .. "]"

	local props_json = "{"
	local first = true
	for k, v in pairs(properties) do
		if not first then props_json = props_json .. "," end
		props_json = props_json .. '"' .. k .. '":' .. tostring(v)
		first = false
	end
	props_json = props_json .. "}"

	entry.rarity = "default"

	entry.mod_data = {
		backend_id = backend_id,
		ItemInstanceId = backend_id,
		CustomData = {
			traits = traits_json,
			power_level = tostring(power_level),
			properties = props_json,
			rarity = "default",
		},
		rarity = "default",
		traits = table.clone(traits, true),
		power_level = power_level,
		properties = table.clone(properties, true),
	}

	-- Pre-apply the item's own illusion as the curated cosmetic ONLY for
	-- non-default-rarity variants. Exotic / unique CWV weapons ship with
	-- a fixed illusion as part of their curated identity. Default-rarity
	-- "blacksmith template" variants must NOT pre-apply a skin — vanilla
	-- blacksmith templates carry `mod_data.CustomData.skin = nil` and the
	-- forge requires that to treat the item as unlocked.
	--
	-- See the full recipe in `DEVELOPMENT.md` "Blacksmith Template
	-- Pattern" and `reference_cwv_blacksmith_template.md`. Default-rarity
	-- variants get their model from `entry.right_hand_unit` (set above);
	-- the `BackendUtils.get_item_units` cwv-override hook below ensures
	-- that mesh actually wins at render time regardless of which entry
	-- the upstream lookup resolved item_data to. The skin entry is still
	-- registered by `_register_variant_skins` so OTHER variants of the
	-- same item_type can apply this variant's look as an illusion.
	if not def.no_skin and def.rarity ~= "default" then
		local skin_key = def.item_key .. "_skin"
		entry.mod_data.CustomData.skin = skin_key
		entry.mod_data.skin = skin_key
	end

	return entry
end

-- ============================================================
-- Give command
-- ============================================================

local function _find_def(item_key)
	for _, def in ipairs(_variant_definitions) do
		if def.item_key == item_key then
			return def
		end
	end
	return nil
end

local function _register_item(def, backend_id)
	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		mod:warning("MoreItemsLibrary not found — cannot register %s", def.item_key)
		return false
	end

	local entry = _build_entry(def, backend_id)
	if not entry then return false end

	mil:add_mod_items_to_local_backend({entry}, "character_weapon_variants")

	-- MIL stores items in its private local-backend table, NOT in
	-- ItemMasterList. But vanilla `HeroPreviewer.equip_item`
	-- (world_hero_previewer.lua:674) does `item_data = ItemMasterList[item_name]`
	-- and then passes the result to `BackendUtils.get_item_units(item_data, ...)`
	-- — if item_data is nil the next line indexes nil and the game crashes.
	-- Mirror our entries into ItemMasterList so equip_item resolves them.
	-- Guarded with `not ItemMasterList[key]` to avoid clobbering anything
	-- another mod registered (or a previous session's entry that still lives
	-- across hot-reloads).
	if ItemMasterList and not ItemMasterList[def.item_key] then
		ItemMasterList[def.item_key] = entry
	end

	if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, def.item_key) then
		local idx = #NetworkLookup.item_names + 1
		rawset(NetworkLookup.item_names, idx, def.item_key)
		rawset(NetworkLookup.item_names, def.item_key, idx)
	end

	_registered_keys[def.item_key] = backend_id
	return true
end

local function _give_variant(item_key)
	local def = _find_def(item_key)
	if not def then
		mod:echo("Unknown variant: %s", item_key)
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end

	if _registered_keys[item_key] then
		mod:echo("%s is already in your inventory", def.display_name)
		return
	end

	local backend_id = def.item_key .. "_001"
	if not _register_item(def, backend_id) then
		mod:echo("Failed to register %s", def.display_name)
		return
	end

	if Managers and Managers.backend then
		local backend_items = Managers.backend:get_interface("items")
		if backend_items and backend_items._refresh then
			backend_items:_refresh()
		end

		local rarity = def.rarity or "exotic"
		if rarity ~= "default" and backend_items then
			local item = backend_items:get_item_from_id(backend_id)
			if item then
				item.rarity = rarity
				item.data.rarity = rarity
				item.CustomData.rarity = rarity
			end
		end
	end

	mod:echo("Gave %s", def.display_name)
end

-- ============================================================
-- Auto-registration (deferred until backend is ready)
-- ============================================================

local _auto_registered = false

local function _auto_register_all()
	if _auto_registered then return end

	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		mod:warning("MoreItemsLibrary not found — variant weapons will not be available")
		return
	end

	local entries = {}
	local pending_defs = {}
	for _, def in ipairs(_variant_definitions) do
		if def.skin_only then goto continue end
		-- v0.1.271: support `def.instances = N` to register N backend
		-- entries of the same variant with backend_ids `<key>_001`,
		-- `<key>_002`, ... Each entry is a unique inventory item the
		-- player can equip independently. Optional `def.instance_skins`
		-- array provides a pre-applied skin per instance (nil = use the
		-- variant's default auto-applied skin).
		local instance_count = def.instances or 1
		for i = 1, instance_count do
			local backend_id = string.format("%s_%03d", def.item_key, i)
			-- Skip if a backend_id for this slot is already registered.
			-- (Per-instance tracking uses backend_id as key; per-key
			-- tracking just stores the first registered backend_id.)
			if _registered_keys[backend_id] then goto next_instance end
			local entry = _build_entry(def, backend_id)
			if entry then
				-- Per-instance skin override (instance 2+ can pre-apply
				-- a different cosmetic illusion without a separate
				-- variant def).
				local instance_skin = def.instance_skins and def.instance_skins[i]
				if instance_skin and entry.mod_data then
					entry.mod_data.CustomData = entry.mod_data.CustomData or {}
					entry.mod_data.CustomData.skin = instance_skin
					entry.mod_data.skin = instance_skin
				end
				entries[#entries + 1] = entry
				pending_defs[#pending_defs + 1] = { def = def, backend_id = backend_id, instance = i }
				_registered_keys[backend_id] = backend_id
				-- Also store under the item_key for backward-compat with
				-- the per-key check elsewhere in the file (first instance wins).
				if not _registered_keys[def.item_key] then
					_registered_keys[def.item_key] = backend_id
				end
			end
			::next_instance::
		end
		::continue::
	end

	if #entries > 0 then
		mil:add_mod_items_to_local_backend(entries, "character_weapon_variants")

		-- See _register_item: HeroPreviewer.equip_item needs ItemMasterList[key]
		-- to be non-nil. MIL only stores in its private backend; mirror into
		-- ItemMasterList so vanilla equip paths can resolve our items.
		if ItemMasterList then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				if not ItemMasterList[key] then
					-- find this entry in `entries` (parallel to pending_defs order)
					for _, e in ipairs(entries) do
						if e.mod_data and e.mod_data.backend_id == pending.backend_id then
							ItemMasterList[key] = e
							break
						end
					end
				end
			end
		end

		-- CLARIFY: Per CHANGELOG v0.1.24, MIL.add_mod_items_to_local_backend does
		-- NOT inject into NetworkLookup.item_names (only add_mod_items_to_masterlist
		-- does). Without this manual injection, network serialization crashes when
		-- the item is referenced over the wire.
		if NetworkLookup and NetworkLookup.item_names then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				if not rawget(NetworkLookup.item_names, key) then
					local idx = #NetworkLookup.item_names + 1
					rawset(NetworkLookup.item_names, idx, key)
					rawset(NetworkLookup.item_names, key, idx)
				end
			end
		end

		local backend_items = Managers.backend:get_interface("items")
		if backend_items and backend_items._refresh then
			backend_items:_refresh()
		end

		for _, pending in ipairs(pending_defs) do
			local rarity = pending.def.rarity or "exotic"
			if rarity ~= "default" and backend_items then
				local item = backend_items:get_item_from_id(pending.backend_id)
				if item then
					item.rarity = rarity
					item.data.rarity = rarity
					item.CustomData.rarity = rarity
					mod:info("Set %s rarity to %s", pending.def.item_key, rarity)
				end
			end
		end

		mod:info("Registered %d variant weapons", #entries)
	end

	_auto_registered = true
end

-- CLARIFY: StateInGameRunning.on_enter fires on entering the keep AND on every
-- mission load. _auto_register_all() guards via _auto_registered flag so it
-- runs at most once per session. Backend is guaranteed live by this state per
-- DEVELOPMENT.md / CHANGELOG v0.1.17.
-- QUESTION: If a user joins a friend's lobby BEFORE entering the keep (e.g. via
-- direct lobby join), does StateInGameRunning fire? In practice the keep is
-- always the first state, so this should be fine — flagged here in case the
-- assumption breaks for future game-state changes.
mod:hook_safe("StateInGameRunning", "on_enter", function()
	_auto_register_all()
end)

-- Animation remapping handled entirely via template, 3P-only:
-- - anim_event_3p overrides in elven_sword_shield_template (attack anims)
-- - wield_anim_3p = "to_1h_spear_shield" (wield anim, 3P body)
-- 1P animations work universally across all characters and are never touched
-- by this mod — see top-of-file ANIMATION ARCHITECTURE for the rule.

-- ============================================================
-- Model scaling and grip offsets
-- ============================================================
--
-- Two layers, in precedence order:
--   1. Per-variant fields on the def (`right_hand_scale`, `right_hand_offset`,
--      `left_hand_scale`, `left_hand_offset`) — model-specific overrides.
--   2. Type-level entry in `_type_transforms[item_type]` — applies to every
--      variant sharing that item_type. This is how a "weapon type" gets
--      defined as a single tunable: each `cwv_*` item_type represents a new
--      conceptual weapon (e.g. cwv_imperial_longsword), and any change to
--      the type cascades to all variants of that type automatically.
--
-- A variant only needs the per-variant fields when it deviates from its type.
-- The type table is the canonical place to tune family-wide proportions /
-- grip behaviour, so a future "make Imperial Longswords thinner" change is
-- one edit, not three.

local _type_transforms = {
	-- Imperial Longsword family (Recruit Longsword, Nordland Claymore, Black Guard Blade).
	-- Y trims 20% off width (Imperial greatsword's wide axis is Y, not X like the
	-- Bretonian — this is independent of cosmetics_tweaker's `_breton_sword_thiccc`
	-- factor `{0.65, 1, 1}` on `wpn_emp_gk_sword_*`); Z trims 10% off blade length.
	-- Lateral X grip nudge so the hand sits on the hilt after Y-thinning. Sign per
	-- `feedback_grip_offset_sign.md`.
	cwv_imperial_longsword = {
		right_hand_scale  = { 1.0, 0.8, 0.9 },
		-- User-tuned along Z. The negative direction is correct for this model
		-- family (flipped from `feedback_grip_offset_sign.md`'s general
		-- "+Z = grip lower" rule — per-model authoring axes can invert it).
		right_hand_offset = { 0, 0, -0.065 },
	},
	-- Longsword + Shield: same right-hand sword mesh as the 2H Imperial
	-- Longsword family (`wpn_empire_2h_sword_04_t1`), per-perspective
	-- scaled. 3P body shows the smaller-feeling sword (better silhouette
	-- next to a shield, where a 2H greatsword reads too oversized),
	-- while 1P keeps the original 2H family scale because the held view
	-- looked too small at the shrunk values. Tuning history:
	--   v0.1.197 unified {1.0, 0.8, 0.9} — matches 2H family
	--   v0.1.206 unified {0.85, 0.65, 0.75} — −0.15 on every axis
	--   v0.1.210 SPLIT — 1P back to {1.0, 0.8, 0.9}, 3P stays at {0.85, 0.65, 0.75}
	-- Resolution: `_1p`/`_3p` variants override the unified field for
	-- that perspective only (per `_resolve_field`). Grip offset is
	-- unified — same Z=-0.065 works for both perspectives. Left hand
	-- (the shield) is untouched. Variant uses its own item_type (not
	-- cwv_imperial_longsword) so it can carry its own curated
	-- shield-illusion picker — that's why this is a separate entry
	-- rather than sharing the 2H family's type.
	cwv_es_longsword_shield = {
		right_hand_scale_1p = { 1.0, 0.8, 0.9 },     -- 1P held view: full 2H family scale
		right_hand_scale_3p = { 0.9, 0.7, 0.8 },  -- 3P body: shrunk for shield pairing (+0.05 each axis v0.1.309)
		right_hand_offset   = { 0, 0, -0.065 },
	},
	-- Maul: scale Kruber's 1H mace meshes (mace+sword mace + es_1h_mace
	-- skins) up to a 2H silhouette. User-tuned to {1.075, 1.075, 1.4}
	-- v0.1.171 (was {1.4, 1.4, 2.0} in v0.1.168 — too big). The lighter
	-- X/Y bump keeps the mace from looking inflated; Z +40% adds enough
	-- length to read as a 2H maul. Type-level so default + every illusion
	-- in cwv_es_maul_skins picker inherit.
	cwv_es_maul = {
		right_hand_scale  = { 1.0, 1.0, 1.6 },
		-- Grip offset Z lowers Kruber's hand toward the haft. Per
		-- `feedback_grip_offset_sign.md`, +Z lowers grip on this family.
		-- Tuning history: 0.5 (v0.1.176) → 0.35 (v0.1.213) — the original
		-- pulled the hand too far toward the bottom of the haft; this is
		-- a more moderate drop.
		right_hand_offset = { 0, 0, 0.2 },
	},
	-- Poleaxe: shrink Kruber's halberd Z so it reads as a shorter
	-- polearm instead of a full halberd. Grip offset Z+0.5 lowers the
	-- haft so Kruber's hand sits at the proper grip point — vanilla
	-- halberd grip rides too high after the Z-shrink (per
	-- `feedback_grip_offset_sign.md`, +Z lowers grip). Type-level so the
	-- default mesh + every es_halberd_skin_* illusion in
	-- cwv_es_poleaxe_skins inherits.
	-- Rapier: lightly broaden the fencing-sword mesh — X +5%, Y +15%,
	-- Z native. Tuning history:
	--   v0.1.187 {1.1, 1.25, 1.0} initial basket-hilt feel
	--   v0.1.191 {1.1, 1.45, 1.0} Y bump
	--   v0.1.196 {1.0, 1.75, 1.0} maximal Y for broadsword silhouette
	--   v0.1.212 {1.05, 1.15, 1.0} restored to a subtler bump per user —
	--     v0.1.196's 1.75 read as exaggerated; this is a lighter touch.
	-- Type-level so the default mesh + every wh_fencing_sword_skin_*
	-- illusion in cwv_es_rapier_skins inherits.
	cwv_es_rapier = {
		right_hand_scale = { 1.05, 1.15, 1.0 },
	},
	cwv_es_poleaxe = {
		right_hand_scale  = { 0.9, 0.9, 0.65 },
		right_hand_offset = { 0, 0, 0.5 },
	},
	-- Musket: stretch Kruber's rifle 1.35x along Y (length axis) and
	-- thin X/Z (barrel/cross-section). v0.1.250 dropped X/Z another 0.1
	-- (`0.9 → 0.8`). v0.1.256 split Y per perspective: 3P stays 1.35,
	-- 1P bumped to 1.5 (+0.15) per user "1P needs 0.15 longer on Y" —
	-- held view reads slightly short of where the muzzle should be.
	-- Per-perspective via `_resolve_field` precedence: `_1p` field
	-- overrides the unified `right_hand_scale` for 1P only.
	cwv_es_musket = {
		right_hand_scale    = { 0.8, 1.35, 0.8 },
		right_hand_scale_1p = { 0.8, 1.5,  0.8 },
	},
	-- Old Musket (cwv_es_musket_old): custom mesh is already the right
	-- shape (proportions baked into the FBX) — no Y stretch needed, no
	-- X/Z thinning. Leaving the transform empty here means
	-- `_resolve_field` returns nil for all axes, so the mesh renders at
	-- its native authored scale.
	cwv_es_musket_old = {},
}

-- Per-variant override > type-level default > nil.
local function _resolve_field(def, field)
	if def[field] ~= nil then return def[field] end
	local tt = def.item_type and _type_transforms[def.item_type]
	return tt and tt[field] or nil
end

local _transform_map = {}
local _skin_transform_map = {}
for _, def in ipairs(_variant_definitions) do
	-- Register if EITHER the def itself OR its type contributes any transform.
	-- This is what lets a variant with no per-variant scale fields still pick
	-- up the type-level entry — without it, _transform_map[item_key] is nil
	-- and `_resolve_cwv_def` returns nil at apply time.
	-- Includes the per-perspective `_1p` / `_3p` variants so a def that only
	-- sets a 1P-specific or 3P-specific transform is still registered.
	if _resolve_field(def, "right_hand_scale")
			or _resolve_field(def, "left_hand_scale")
			or _resolve_field(def, "right_hand_offset")
			or _resolve_field(def, "left_hand_offset")
			or _resolve_field(def, "right_hand_scale_1p")
			or _resolve_field(def, "left_hand_scale_1p")
			or _resolve_field(def, "right_hand_offset_1p")
			or _resolve_field(def, "left_hand_offset_1p")
			or _resolve_field(def, "right_hand_scale_3p")
			or _resolve_field(def, "left_hand_scale_3p")
			or _resolve_field(def, "right_hand_offset_3p")
			or _resolve_field(def, "left_hand_offset_3p") then
		_transform_map[def.item_key] = def
		if not def.no_skin then
			_skin_transform_map[def.item_key .. "_skin"] = def
		end
	end
end

-- Custom illusions with their own scale/offset fields (e.g. greathammer
-- skins applied to 1H mace targets need to scale the oversized 2H model
-- down). These aren't variant defs — they live in `_custom_illusions` —
-- but the apply path keys by skin_key, so we register them in
-- `_skin_transform_map` with a synthetic def carrying just the transform
-- fields. `_resolve_field` reads `def[field]` first, finds these directly.
for _, illusion in ipairs(_custom_illusions) do
	local has_transform = illusion.right_hand_scale or illusion.left_hand_scale
		or illusion.right_hand_offset or illusion.left_hand_offset
		or illusion.right_hand_scale_1p or illusion.left_hand_scale_1p
		or illusion.right_hand_scale_3p or illusion.left_hand_scale_3p
	if has_transform then
		_skin_transform_map[illusion.skin_key] = {
			item_key             = illusion.skin_key,  -- for log/identification
			right_hand_scale     = illusion.right_hand_scale,
			left_hand_scale      = illusion.left_hand_scale,
			right_hand_offset    = illusion.right_hand_offset,
			left_hand_offset     = illusion.left_hand_offset,
			right_hand_scale_1p  = illusion.right_hand_scale_1p,
			left_hand_scale_1p   = illusion.left_hand_scale_1p,
			right_hand_scale_3p  = illusion.right_hand_scale_3p,
			left_hand_scale_3p   = illusion.left_hand_scale_3p,
			right_hand_offset_1p = illusion.right_hand_offset_1p,
			left_hand_offset_1p  = illusion.left_hand_offset_1p,
			right_hand_offset_3p = illusion.right_hand_offset_3p,
			left_hand_offset_3p  = illusion.left_hand_offset_3p,
		}
	end
end

-- Inherit-from-variant pass for dynamically-registered cross-character
-- illusions (registered via _register_*_illusions functions, NOT via
-- _custom_illusions). Detection: skin_key starts with a known variant
-- item_key followed by "_". The dynamic illusion shares the variant's
-- type-level transform via the variant's def — `_resolve_field` falls
-- through to `_type_transforms[def.item_type]` when the def has no
-- per-field override, so this gives the dynamic illusion picker preview
-- the same scale the variant's default mesh uses in-game.
--
-- The in-game render path (`GearUtils.create_equipment` →
-- `_resolve_cwv_def`) already handles this via the backend_id fallback —
-- it resolves the cwv variant from the equipped item's backend_id and
-- finds the type-level transform there. The picker (`LootItemUnitPreviewer`)
-- doesn't have a backend_id on the previewed weapon_skin entry, so
-- without this pass it shows un-scaled illusions.
--
-- Per-illusion overrides in _custom_illusions take precedence (above
-- block), so a dynamic illusion that needs a different scale than its
-- variant should be moved to _custom_illusions with explicit scale fields.
--
-- LONGEST-MATCH RULE (v0.1.255): when multiple variant defs share a
-- prefix relationship (e.g. `cwv_es_longsword` is a prefix of
-- `cwv_es_longsword_shield`), the iterate-and-break loop used to pick
-- whichever def appeared FIRST in `_variant_definitions` — so
-- `cwv_es_longsword_shield_*` illusions inherited from the 2H Imperial
-- Longsword variant instead of the shield-specific one, applying the
-- wrong scale. Now we walk every variant, track the longest item_key
-- that's a prefix of the skin_key, and use that one.
for skin_key in pairs(_custom_skin_keys) do
	if not _skin_transform_map[skin_key] then
		local best_def = nil
		local best_len = 0
		for _, def in ipairs(_variant_definitions) do
			if _transform_map[def.item_key]
					and #def.item_key > best_len
					and skin_key:sub(1, #def.item_key + 1) == def.item_key .. "_" then
				best_def = def
				best_len = #def.item_key
			end
		end
		if best_def then
			_skin_transform_map[skin_key] = _transform_map[best_def.item_key]
		end
	end
end

local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

local function _apply_scale(unit, scale_tbl)
	if not unit or not _is_unit(unit) then return end
	pcall(Unit.set_local_scale, unit, 0, Vector3(scale_tbl[1], scale_tbl[2], scale_tbl[3]))
end

-- _apply_offset is additive (current + offset). MenuWorldPreviewer extends
-- HeroPreviewer and its _spawn_item super-calls the parent, so both hooks fire
-- per spawn for MenuWorldPreviewer instances and would double the offset. Guard
-- with a weak-keyed set so the second invocation is a no-op; the table cleans
-- itself up when the unit is GC'd. Scale is idempotent so it doesn't need this.
local _offset_applied = setmetatable({}, { __mode = "k" })

local function _apply_offset(unit, offset_tbl)
	if not unit or not _is_unit(unit) then return end
	if not Unit.alive(unit) then return end
	if _offset_applied[unit] then return end
	_offset_applied[unit] = true
	local current = Unit.local_position(unit, 0)
	local cx, cy, cz = Vector3.to_elements(current)
	Unit.set_local_position(unit, 0, Vector3(cx + offset_tbl[1], cy + offset_tbl[2], cz + offset_tbl[3]))
end

local function _transform_unit(unit, scale_tbl, offset_tbl)
	if scale_tbl then _apply_scale(unit, scale_tbl) end
	if offset_tbl then _apply_offset(unit, offset_tbl) end
end

-- Vanilla mace+sword cosmetic tweak (toggleable via "mace_sword_tweak"
-- setting, default ON). When the toggle is on:
--   * The vanilla `es_dual_wield_hammer_sword` item gets renamed to
--     "Cudgel and Short Sword" via the Localize hook below.
--   * The sword half (left_hand_unit = wpn_emp_sword_06_t1) is scaled to
--     {0.7, 0.7, 1.0} on the 3P body so the mace and sword visually match
--     the standalone Cudgel + Shortsword variants.
-- This is the VANILLA item, not the CWV `cwv_es_sword_and_mace` (Sword and
-- Mace) variant — that one is a separate weapon and is unaffected by this
-- toggle.
local _ES_MACE_SWORD_TWEAK_DEF = {
	item_key        = "es_dual_wield_hammer_sword",
	-- Right hand (mace, wpn_emp_mace_04_t2) keeps native scale.
	-- Left hand (sword, wpn_emp_sword_06_t1) shrinks to match the
	-- cwv_es_shortsword variant.
	left_hand_scale = { 0.7, 0.7, 1.0 },
}

local function _resolve_cwv_def(item_data, skin)
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin] end
	if not item_data then return nil end
	-- CLARIFY: backend_id resolution is the canonical path for cwv items per
	-- memory note feedback_cwv_backend_id_lookup.md — item_data.key/.name return
	-- the BASE weapon key, never the cwv_* key.
	local bid = item_data.backend_id
	if bid then
		local cwv_key = bid:match("^(cwv_.-)_001$")
		if cwv_key and _transform_map[cwv_key] then return _transform_map[cwv_key] end
	end
	-- Vanilla item key fallback (used by the mace_sword_tweak path below; cwv
	-- items don't reach here because backend_id resolution above takes over).
	local key = item_data.key or item_data.name
	if key and _transform_map[key] then return _transform_map[key] end
	-- Vanilla mace+sword cosmetic tweak — gated on the user-facing toggle so
	-- it can be disabled at runtime without a mod reload. Per
	-- feedback_cwv_backend_id_lookup.md, `item_data.key` returns the BASE
	-- weapon key for cwv variants too — so we must check the backend_id
	-- prefix to ensure we don't accidentally apply this to
	-- cwv_es_sword_and_mace (which shares the same base_weapon).
	if key == "es_dual_wield_hammer_sword" and mod:get("mace_sword_tweak") then
		local bid_str = item_data.backend_id
		local is_cwv_variant = bid_str and type(bid_str) == "string" and bid_str:sub(1, 4) == "cwv_"
		if not is_cwv_variant then
			return _ES_MACE_SWORD_TWEAK_DEF
		end
	end
	return nil
end

-- ============================================================
-- BackendUtils.get_item_units override
-- ============================================================
-- Force the cwv def's right_hand_unit / left_hand_unit overrides into the
-- result table when the call resolves to a cwv item AND no skin is being
-- applied. Fixes inventory preview rendering the BASE weapon's mesh on
-- default-rarity CWV blacksmith templates.
--
-- WHY this is needed:
-- The CWV entry inherits `entry.name` and `entry.key` from the base weapon
-- (per `feedback_cwv_clone_name_clobber.md` — clobbering them crashes
-- equip). Vanilla `BackendUtils.get_item_units` reads
-- `item_data.right_hand_unit` directly from whatever item_data was passed
-- in. If the upstream caller's lookup chain landed on the BASE entry
-- (e.g. via `ItemMasterList[item.name]` where item.name is the inherited
-- base name), `item_data.right_hand_unit` is the base mesh.
--
-- Pre-v0.1.87 we worked around this by pre-applying the cwv skin via
-- `mod_data.CustomData.skin = "<item_key>_skin"`, which forced
-- BackendUtils to use the skin's right_hand_unit (= the cwv mesh).
-- v0.1.87 removed that for default-rarity items so the forge would treat
-- them as unlocked blacksmith templates — but that exposed this latent
-- base-mesh-fallback bug.
--
-- The fix: detect cwv items by backend_id pattern (`cwv_<key>_001`) and,
-- when no skin ended up applied, replace the result's per-hand unit
-- paths with the variant def's overrides. When a skin IS applied (curated
-- exotic / unique cwv weapons that ship with their own illusion, OR a
-- user who manually applied a different cwv illusion via the cosmetic
-- menu), `result.skin` is non-nil and we leave it alone — the user's
-- chosen illusion wins.
if BackendUtils then
	mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
		local result = func(item_data, backend_id, skin, career_name)
		if not result then return result end

		-- HISTORICAL: this hook used to mirror right_hand_unit → left_hand_unit
		-- for `_kruber_1h_dual_skin_keys` skins. The mirror was needed back when
		-- those skin entries deliberately omitted `left_hand_unit` to avoid a
		-- `j_leftweaponattach` crash on a single-sword display rig. v0.1.145
		-- removed the mirror: skin entries now carry `left_hand_unit = right_hand_unit`
		-- directly AND use `display_dual_weapons` (the rig that authors both
		-- attach nodes), so vanilla `BackendUtils.get_item_units` populates
		-- `result.left_hand_unit` from the skin entry without our help, on both
		-- in-game and previewer call paths. See `J_LEFTWEAPONATTACH_INVESTIGATION.md`.

		if not backend_id then return result end

		-- Backend_id pattern matches `cwv_<key>_001`. Extract the cwv
		-- item_key and look up the def. Anything else passes through.
		local cwv_key = type(backend_id) == "string" and backend_id:match("^(cwv_.-)_001$")
		if not cwv_key then return result end
		local def = _find_def(cwv_key)
		if not def then return result end

		-- A skin was applied during the resolution (curated cwv item or
		-- user-selected illusion). The skin's per-hand units are already
		-- in `result`; don't trample them. `result.skin` is set by
		-- vanilla at backend_utils.lua:205 when a skin took effect.
		if result.skin and result.skin ~= "" then return result end

		-- No skin → vanilla fell back to item_data.right_hand_unit, which
		-- may be the base entry's path. Force the cwv override.
		if def.right_hand_unit then result.right_hand_unit = def.right_hand_unit end
		if def.left_hand_unit  then result.left_hand_unit  = def.left_hand_unit  end
		return result
	end)
end

-- NOTE: the per-perspective 1P/3P unit swap mechanism (previously used
-- for cwv_es_brace_repeater) was moved to weapon_tweaker in v0.1.187 —
-- it now hooks `GearUtils.spawn_inventory_unit` for vanilla
-- `wh_brace_of_pistols` on Kruber careers, swapping the 3P unit to
-- the repeater. No CWV variant currently uses the override mechanism;
-- if a future variant needs different 1P vs 3P meshes, restore the
-- hook here from git history.

mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	if not result then return result end

	local def = _resolve_cwv_def(item_data, result.skin)
	if not def then return result end

	mod:info("Applying transforms (slot=%s, skin=%s, item_key=%s, 3p_only=%s)",
		tostring(slot_name), tostring(result.skin), def.item_key, tostring(def.scale_3p_only or false))

	-- Per-perspective resolution: `_1p` / `_3p` variants override the unified
	-- field for that perspective only; if absent the unified field is used.
	-- scale_3p_only: skip 1P units (held first-person view) entirely but still
	-- apply 3P transforms (other players see this) and preview paths
	-- (HeroPreviewer / LootItemUnitPreviewer hooks below — 3P-style models).
	local right_scale     = _resolve_field(def, "right_hand_scale")
	local left_scale      = _resolve_field(def, "left_hand_scale")
	local right_offset    = _resolve_field(def, "right_hand_offset")
	local left_offset     = _resolve_field(def, "left_hand_offset")
	local right_scale_1p  = _resolve_field(def, "right_hand_scale_1p")  or right_scale
	local left_scale_1p   = _resolve_field(def, "left_hand_scale_1p")   or left_scale
	local right_offset_1p = _resolve_field(def, "right_hand_offset_1p") or right_offset
	local left_offset_1p  = _resolve_field(def, "left_hand_offset_1p")  or left_offset
	local right_scale_3p  = _resolve_field(def, "right_hand_scale_3p")  or right_scale
	local left_scale_3p   = _resolve_field(def, "left_hand_scale_3p")   or left_scale
	local right_offset_3p = _resolve_field(def, "right_hand_offset_3p") or right_offset
	local left_offset_3p  = _resolve_field(def, "left_hand_offset_3p")  or left_offset
	if not def.scale_3p_only then
		_transform_unit(result.right_unit_1p, right_scale_1p, right_offset_1p)
		_transform_unit(result.left_unit_1p,  left_scale_1p,  left_offset_1p)
	end
	_transform_unit(result.right_unit_3p, right_scale_3p, right_offset_3p)
	_transform_unit(result.left_unit_3p,  left_scale_3p,  left_offset_3p)

	return result
end)

local function _find_preview_slot_info(self, item_name)
	if not self._item_info_by_slot then return nil, nil end
	for slot_id, info in pairs(self._item_info_by_slot) do
		if info and info.name == item_name then
			return slot_id, info
		end
	end
	return nil, nil
end

local function _resolve_preview_def(self, item_name)
	local _, info = _find_preview_slot_info(self, item_name)
	local skin = info and info.skin_name
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin], info end

	if info and info.backend_id then
		-- v0.1.316: match ANY instance suffix (_001, _002, _003, ...). The
		-- earlier "^(cwv_.-)_001$" regex only matched instance 1, so for
		-- variants with `instances = 2` (e.g. cwv_es_musket_old) the second
		-- instance never resolved — `_cwv_spawn_item_post` returned early
		-- and the previewer-side texture binding never fired. Result: rifle
		-- appeared in the keep inventory previewer without textures.
		local matched = info.backend_id:match("^(cwv_.-)_%d%d%d$")
		if matched and _transform_map[matched] then return _transform_map[matched], info end
	end
	if _transform_map[item_name] then return _transform_map[item_name], info end
	return nil, info
end

local function _cwv_spawn_item_post(self, item_name)
	local def, info = _resolve_preview_def(self, item_name)
	if not def then
		-- v0.1.326: log when the resolver fails for a musket-shaped item_name
		-- so we can tell whether the regex / lookup is broken vs the hook
		-- never firing.
		if type(item_name) == "string" and item_name:find("musket", 1, true) then
			mod:info("[cwv preview] _resolve_preview_def returned nil for item_name=%s (info bid=%s)",
				tostring(item_name),
				tostring(info and info.backend_id))
		end
		return
	end

	local equip_units = self._equipment_units
	if not equip_units then return end

	-- KEY BRIDGE — DO NOT remove or refactor to a string-keyed loop.
	-- `info` came from `self._item_info_by_slot`, which vanilla
	-- `equip_item` (world_hero_previewer.lua:776) keys by STRING slot_type
	-- ("melee" / "ranged"). But `self._equipment_units` is keyed by NUMERIC
	-- `slot_index`. Looking up `equip_units[slot_type_string]` returns nil
	-- silently and the whole apply path no-ops — that's the bug v0.1.84
	-- fixed (and cosmetics_tweaker fixed in 0.7.88, see its CHANGELOG).
	-- Vanilla `equip_item` writes the numeric `slot_index` onto each
	-- `spawn_data[i]` (lines 704 / 728 of world_hero_previewer.lua), so
	-- read it from there to bridge the two keying conventions.
	-- The previous implementation had a "fall back: match by item_name"
	-- loop that iterated `self._item_info_by_slot` and stored the iterator
	-- key — that key is the STRING slot_type, which is exactly the wrong
	-- thing to look up `equip_units` with. Don't reintroduce.
	local slot_index = info and info.spawn_data and info.spawn_data[1]
			and info.spawn_data[1].slot_index
	if not slot_index then return end

	local slot = equip_units[slot_index]
	if type(slot) ~= "table" then return end

	-- Preview spawns 3P-style models; use _3p override if set, else unified.
	if slot.right and _is_unit(slot.right) then
		_transform_unit(slot.right,
			_resolve_field(def, "right_hand_scale_3p")  or _resolve_field(def, "right_hand_scale"),
			_resolve_field(def, "right_hand_offset_3p") or _resolve_field(def, "right_hand_offset"))
	end
	if slot.left and _is_unit(slot.left) then
		_transform_unit(slot.left,
			_resolve_field(def, "left_hand_scale_3p")  or _resolve_field(def, "left_hand_scale"),
			_resolve_field(def, "left_hand_offset_3p") or _resolve_field(def, "left_hand_offset"))
	end

	-- v0.1.293: bind cwv_es_musket_old textures + track for live tuning in the
	-- character-preview UI. v0.1.318: pass the stance mode so 3P-MELEE
	-- transforms apply when the player has the musket in melee stance.
	-- Mode is read from item_data.mod_data.cwv_musket_stance.
	-- v0.1.326: diagnostic logging to figure out why texture stays white
	-- in the inventory preview. Logs whether the hook reached this point,
	-- the unit's mesh/material counts, and each Material.set_texture result.
	if def.item_key == "cwv_es_musket_old" and slot.right and _is_unit(slot.right) then
		local _stance = "ranged"
		local item_data = info and info.item_data
		if item_data and item_data.mod_data and item_data.mod_data.cwv_musket_stance == "melee" then
			_stance = "melee"
		end
		mod:info("[cwv preview] firing for cwv_es_musket_old: unit=%s stance=%s", tostring(slot.right), _stance)
		-- Inline diagnostic texture binding (so we can SEE per-call results)
		local unit = slot.right
		local meshes_seen, mats_seen, tex_set_oks = 0, 0, 0
		local ok_nm, num_meshes = pcall(Unit.num_meshes, unit)
		if ok_nm and num_meshes then
			for i = 0, num_meshes - 1 do
				local mok, mesh = pcall(Unit.mesh, unit, i)
				if mok and mesh then
					meshes_seen = meshes_seen + 1
					local nok, num_mats = pcall(Mesh.num_materials, mesh)
					if nok and num_mats then
						for j = 0, num_mats - 1 do
							local matok, mat = pcall(Mesh.material, mesh, j)
							if matok and mat then
								mats_seen = mats_seen + 1
								local rok1 = pcall(Material.set_texture, mat, "texture_map_c0ba2942", "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo")
								local rok2 = pcall(Material.set_texture, mat, "texture_map_59cd86b9", "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal")
								local rok3 = pcall(Material.set_texture, mat, "texture_map_0205ba86", "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic")
								if rok1 and rok2 and rok3 then tex_set_oks = tex_set_oks + 1 end
							end
						end
					end
				end
			end
		else
			mod:info("[cwv preview] Unit.num_meshes failed: ok=%s num_meshes=%s", tostring(ok_nm), tostring(num_meshes))
		end
		mod:info("[cwv preview] textures applied: meshes=%d mats=%d ok_triples=%d", meshes_seen, mats_seen, tex_set_oks)
		if _track_old_musket_unit then
			_track_old_musket_unit(slot.right, "3p", _stance)
		end
		if _apply_old_musket_transform then
			_apply_old_musket_transform(slot.right, "3p", _stance)
		end
	elseif def.item_key == "cwv_es_musket_old" then
		mod:info("[cwv preview] cwv_es_musket_old gate failed: slot.right=%s _is_unit=%s",
			tostring(slot and slot.right), tostring(slot and slot.right and _is_unit(slot.right)))
	end
end

-- ============================================================
-- Cosmetic picker filter — strip vanilla skins from cwv variants
-- ============================================================
-- Vanilla `HeroWindowItemCustomization._setup_illusions` populates the
-- illusion list from `item_data.skin_combination_table` (which we set
-- correctly to `cwv_imperial_longsword_skins` etc., containing only our
-- cwv skins) and THEN appends `WeaponSkins.default_skins[item_key]` if not
-- already in the list (`hero_window_item_customization.lua:1586`). The
-- problem: cwv items inherit `entry.key = "es_bastard_sword"` from their
-- clone (per `feedback_cwv_clone_name_clobber.md`), so `item.ItemId`
-- resolves through that and the picker looks up
-- `WeaponSkins.default_skins.es_bastard_sword = "es_bastard_sword_skin_01"`
-- (the Bretonian default, defined in `weapon_skins_lake.lua:251`). The
-- Bretonian then gets added as a 4th option alongside our 3 cwv skins.
--
-- Filter `self._illusion_widgets` after vanilla runs: for cwv items, keep
-- only widgets whose skin_key starts with `cwv_`. Recompute the layout so
-- the remaining widgets are centered correctly.
local function _is_cwv_item(item)
	if not item then return false end
	local backend_id = item.backend_id or item.ItemId
	if type(backend_id) == "string" and backend_id:match("^cwv_.+_001$") then
		return true
	end
	-- Fallback: the cwv_variant marker on the entry (set in `_build_entry`).
	-- Won't catch backend-id-only paths but does catch any direct item-data
	-- inspection that lands here.
	local item_data = item.data
	return item_data and item_data.cwv_variant == true
end

mod:hook("HeroWindowItemCustomization", "_setup_illusions", function(func, self, item)
	func(self, item)

	if not _is_cwv_item(item) then return end

	local widgets = self._illusion_widgets
	if not widgets then return end

	-- Filter pass: keep only cwv_*_skin entries.
	local kept = {}
	for _, widget in ipairs(widgets) do
		local skin_key = widget.content and widget.content.skin_key
		if type(skin_key) == "string" and skin_key:match("^cwv_") then
			kept[#kept + 1] = widget
		end
	end

	if #kept == #widgets then return end -- nothing to strip

	-- Recompute horizontal layout (mirrors vanilla's loop at
	-- hero_window_item_customization.lua:1611-1618). Widget width is 51,
	-- spacing is -5; vanilla recenters around `total_width / 2`.
	local width = 51
	local spacing = -5
	local total_width = -spacing
	for _ = 1, #kept do
		total_width = total_width + spacing + width
	end
	local x_offset = width / 2
	for _, widget in ipairs(kept) do
		local offset = widget.offset
		offset[1] = -total_width / 2 + x_offset
		x_offset = x_offset + width + spacing
	end

	self._illusion_widgets = kept
end)

-- v0.1.328: UNCONDITIONAL logging for every preview-hook firing. The
-- conditional "if musket" filter in v0.1.326 may have hidden the actual
-- item_name (which could be "es_handgun" inherited from base, not
-- "cwv_es_musket"). Need to see every call to figure out what's happening.
mod:hook("HeroPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	mod:info("[cwv preview hook] HeroPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	_cwv_spawn_item_post(self, item_name)
	return result
end)

mod:hook("MenuWorldPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	mod:info("[cwv preview hook] MenuWorldPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	_cwv_spawn_item_post(self, item_name)
	return result
end)

-- Cosmetic picker / illusion browser preview pane.
--
-- IMPORTANT: this MUST be `mod:hook` (full wrapper), NOT `mod:hook_safe`.
-- Vanilla `LootItemUnitPreviewer:_spawn_items` calls `self:spawn_units(...)`
-- and only assigns `self._spawned_units = units` AFTER the method returns
-- (`loot_item_unit_previewer.lua:522`/`532`). A `hook_safe` post-hook fires
-- BEFORE the caller's assignment, so `self._spawned_units` is nil at that
-- point. Reading the return value of the wrapped call is the only way to
-- get the units. Cosmetics_tweaker hit the same problem and switched its
-- bret-thinning hook to `mod:hook` for exactly this reason — the user
-- remembered this when investigating why cwv scale wasn't applying in the
-- cosmetic picker. Don't refactor back to `hook_safe`.
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
	local units = func(self, spawn_data)

	local item = self._item
	if not item or not units then return units end
	local item_data = item.data
	local weapon_key = (item_data and item_data.key) or item.key
	if not weapon_key then return units end

	-- For cwv_* items, item_data.key returns the BASE weapon key (e.g.
	-- "es_bastard_sword"), NOT "cwv_es_longsword". Always resolve the cwv key
	-- from the backend_id (pattern documented in feedback_cwv_backend_id_lookup.md).
	-- The cwv-keyed transform map then takes precedence over the base-key map so
	-- variant-specific scales/offsets apply correctly.
	local def = _skin_transform_map[weapon_key] or _transform_map[weapon_key]
	local bid = item.backend_id
	if bid then
		local cwv_key = bid:match("^(cwv_.-)_001$")
		if cwv_key then
			def = _transform_map[cwv_key] or _skin_transform_map[cwv_key] or def
		end
	end
	if not def then return units end

	-- LootItemUnitPreviewer (illusion / cosmetic browser) spawns 3P-style models;
	-- prefer _3p override if set, else unified.
	local scale  = _resolve_field(def, "right_hand_scale_3p")  or _resolve_field(def, "left_hand_scale_3p")
	          or _resolve_field(def, "right_hand_scale")     or _resolve_field(def, "left_hand_scale")
	local offset = _resolve_field(def, "right_hand_offset_3p") or _resolve_field(def, "left_hand_offset_3p")
	          or _resolve_field(def, "right_hand_offset")    or _resolve_field(def, "left_hand_offset")
	if scale or offset then
		for _, unit in ipairs(units) do
			_transform_unit(unit, scale, offset)
		end
	end

	return units
end)

-- ============================================================
-- Init
-- ============================================================

local _wt, _ct = _detect_companion_mods()

mod:command("cwv", "Character Weapon Variants status", function()
	mod:echo("Character Weapon Variants v%s", MOD_VERSION)
	mod:echo("  Definitions: %d", #_variant_definitions)
	local count = 0
	for _ in pairs(_registered_keys) do count = count + 1 end
	mod:echo("  Registered items: %d", count)
	mod:echo("  weapon_tweaker: %s", tostring(_wt ~= nil))
	mod:echo("  cosmetics_tweaker: %s", tostring(_ct ~= nil))
	for _, d in ipairs(_variant_definitions) do
		local status = _registered_keys[d.item_key] and "registered" or "not registered"
		mod:echo("    %s — %s (%s)", d.item_key, d.display_name, status)
	end
end)

-- v0.1.293: Old Musket live-tune commands. Separate _1p / _3p variants since
-- the FBX needs different transforms in first-person view vs other players'
-- third-person view. State stored at top of file (search "_CWV_OLD_MUSKET_POS_1P"
-- etc); commands mutate globals and call `_reapply_old_musket_transforms_all`
-- which walks the weak-keyed `_CWV_OLD_MUSKET_UNITS_1P/3P` sets and re-applies
-- the local-space transforms. Compose-safe with vanilla's attachment_node_linking.
local function _parse3(a, b, c)
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	if a and b and c then return { a, b, c } end
	return nil
end

-- v0.1.295: 3-bucket commands — 1P RANGED, 1P MELEE, 3P. Convention:
-- _1p_r = first-person ranged stance (rifle), _1p_m = first-person melee
-- stance (polearm), _3p = third-person (shared across modes).
mod:command("cwv_om_pos_1p_r", "Old Musket 1P RANGED pos: /cwv_om_pos_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_r <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_POS_1P_RANGED = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_1p_m", "Old Musket 1P MELEE pos: /cwv_om_pos_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_m <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_POS_1P_MELEE = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_r", "Old Musket 3P RANGED pos: /cwv_om_pos_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_r <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_POS_3P_RANGED = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_m", "Old Musket 3P MELEE pos: /cwv_om_pos_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_m <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_POS_3P_MELEE = v; _reapply_old_musket_transforms_all()
end)
-- Rotation commands. Three operations per bucket:
--   cwv_om_rot_<bucket>      <ax> <ay> <az> <deg>  — SET (replace current with single axis-angle)
--   cwv_om_rotmul_<bucket>   <ax> <ay> <az> <deg>  — MULTIPLY current rotation by a new axis-angle
--   cwv_om_eul_<bucket>      <x_deg> <y_deg> <z_deg> — SET from Euler XYZ degrees
-- Buckets: _1p_r (1P ranged), _1p_m (1P melee), _3p.
-- Use _rotmul_ to compose rotations without solving the math — e.g., set a
-- base orientation via _rot_, then add a 90° barrel-roll via
-- `cwv_om_rotmul_1p_r 0 0 1 90` (try X / Y / Z axes; whichever rolls the gun
-- the way you want is the barrel axis after your base rotation).
-- v0.1.298: all commands box via QuaternionBox(...) for long-term storage.
-- MUL helpers unbox + multiply + re-box. See note at _CWV_OLD_MUSKET_ROT_*
-- declarations.
local function _q_aa(ax, ay, az, deg) return Quaternion.axis_angle(Vector3(ax, ay, az), math.rad(deg)) end
local function _unbox_or_identity(boxed) return boxed and boxed:unbox() or Quaternion.identity() end

mod:command("cwv_om_rot_1p_r", "SET 1P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_r <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_1p_m", "SET 1P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_m <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_r", "SET 3P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_r <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_m", "SET 3P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_m <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_rotmul_1p_r", "MUL 1P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_r <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_CWV_OLD_MUSKET_ROT_1P_RANGED), _q_aa(ax, ay, az, deg)))
	_reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_1p_m", "MUL 1P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_m <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_CWV_OLD_MUSKET_ROT_1P_MELEE), _q_aa(ax, ay, az, deg)))
	_reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_r", "MUL 3P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_r <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_CWV_OLD_MUSKET_ROT_3P_RANGED), _q_aa(ax, ay, az, deg)))
	_reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_m", "MUL 3P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_m <ax> <ay> <az> <degrees>"); return end
	_CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_CWV_OLD_MUSKET_ROT_3P_MELEE), _q_aa(ax, ay, az, deg)))
	_reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_eul_1p_r", "SET 1P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_r <x_deg> <y_deg> <z_deg>"); return end
	_CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_1p_m", "SET 1P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_m <x_deg> <y_deg> <z_deg>"); return end
	_CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_r", "SET 3P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_r <x_deg> <y_deg> <z_deg>"); return end
	_CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_m", "SET 3P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_m <x_deg> <y_deg> <z_deg>"); return end
	_CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_r", "Old Musket 1P RANGED scale: /cwv_om_scale_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_r <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_SCALE_1P_RANGED = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_m", "Old Musket 1P MELEE scale: /cwv_om_scale_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_m <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_SCALE_1P_MELEE = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_r", "Old Musket 3P RANGED scale: /cwv_om_scale_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_r <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_SCALE_3P_RANGED = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_m", "Old Musket 3P MELEE scale: /cwv_om_scale_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_m <x> <y> <z>"); return end
	_CWV_OLD_MUSKET_SCALE_3P_MELEE = v; _reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_show", "Echo current Old Musket transform values (rot as Euler XYZ deg)", function()
	local function _f3(v) return string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3]) end
	local function _fr(boxed)
		if not boxed then return "identity" end
		local x, y, z = Quaternion.to_euler_angles_xyz(boxed:unbox())
		return string.format("euler_xyz=(%.2f, %.2f, %.2f)°", x, y, z)
	end
	mod:echo("[cwv old-musket] 1P-RANGED pos=%s  rot=%s  scale=%s", _f3(_CWV_OLD_MUSKET_POS_1P_RANGED), _fr(_CWV_OLD_MUSKET_ROT_1P_RANGED), _f3(_CWV_OLD_MUSKET_SCALE_1P_RANGED))
	mod:echo("[cwv old-musket] 1P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_CWV_OLD_MUSKET_POS_1P_MELEE),  _fr(_CWV_OLD_MUSKET_ROT_1P_MELEE),  _f3(_CWV_OLD_MUSKET_SCALE_1P_MELEE))
	mod:echo("[cwv old-musket] 3P-RANGED pos=%s  rot=%s  scale=%s", _f3(_CWV_OLD_MUSKET_POS_3P_RANGED), _fr(_CWV_OLD_MUSKET_ROT_3P_RANGED), _f3(_CWV_OLD_MUSKET_SCALE_3P_RANGED))
	mod:echo("[cwv old-musket] 3P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_CWV_OLD_MUSKET_POS_3P_MELEE),  _fr(_CWV_OLD_MUSKET_ROT_3P_MELEE),  _f3(_CWV_OLD_MUSKET_SCALE_3P_MELEE))
end)

-- v0.1.303 probe: dump every musket item in the backend mirror, plus the
-- two related ItemMasterList entries (cwv_es_musket_old + cwv_es_musket).
-- Tells us at a glance what slot_type / template each item ended up with
-- and whether the variant was registered at all.
-- v0.1.306: dump ammo state of every alive cwv musket ammo extension
-- in the pool, plus the pool cap. Useful for verifying the shared-pool
-- behavior (chambered ammo per-item, reserve shared across items).
mod:command("cwv_musket_ammo_diag", "Dump shared-pool ammo state for all cwv muskets", function()
	if not _CWV_MUSKET_AMMO_EXTS then mod:echo("pool not initialized"); return end
	local count = 0
	for ext in pairs(_CWV_MUSKET_AMMO_EXTS) do
		local alive = ext.unit and Unit.alive(ext.unit)
		if alive then
			count = count + 1
			mod:echo("[#%d] unit=%s slot=%s curr=%s avail=%s shots_fired=%s max=%s clip=%s reloading=%s",
				count, tostring(ext.unit), tostring(ext.slot_name),
				tostring(ext._current_ammo), tostring(ext._available_ammo),
				tostring(ext._shots_fired), tostring(ext._max_ammo), tostring(ext._ammo_per_clip),
				tostring(ext._next_reload_time ~= nil))
		else
			mod:echo("[#?] dead member (cleanup pending)")
		end
	end
	if _cwv_musket_pool_cap then
		mod:echo("pool: members=%d  cap=%d  reserve_per_musket=%d",
			count, _cwv_musket_pool_cap(), _CWV_RESERVE_PER_MUSKET)
	end
end)

mod:command("cwv_musket_dump", "Dump all musket items + their slot_type / template", function()
	local backend_items = Managers and Managers.backend and Managers.backend:get_interface("items")
	if backend_items and backend_items.get_all_backend_items then
		local all = backend_items:get_all_backend_items()
		local count = 0
		for backend_id, item in pairs(all or {}) do
			local data = item.data or item.master_item or item
			local key = data and (data.key or data.name) or item.ItemId or backend_id
			if type(key) == "string" and key:match("^cwv_es_musket") then
				count = count + 1
				mod:echo("[BACKEND] backend_id=%s  key=%s  slot_type=%s  template=%s  rarity=%s",
					tostring(backend_id), tostring(key),
					tostring(data and data.slot_type),
					tostring(data and data.template),
					tostring(item.rarity or (data and data.rarity)))
			end
		end
		mod:echo("[BACKEND] total cwv musket items: %d", count)
	else
		mod:echo("[BACKEND] backend_items interface unavailable")
	end

	if ItemMasterList then
		for _, k in ipairs({ "cwv_es_musket_old", "cwv_es_musket", "es_handgun" }) do
			local e = ItemMasterList[k]
			if e then
				mod:echo("[IML] %s  slot_type=%s  template=%s  rarity=%s",
					k, tostring(e.slot_type), tostring(e.template), tostring(e.rarity))
			else
				mod:echo("[IML] %s = nil", k)
			end
		end
	end
	mod:echo("[WEAPONS] old_musket_template=%s  old_musket_template_melee=%s",
		tostring(Weapons and Weapons.old_musket_template ~= nil),
		tostring(Weapons and Weapons.old_musket_template_melee ~= nil))
end)

mod:command("cwv_probe_skins", "Dump skin keys + localized names matching a weapon: /cwv_probe_skins <matching_item_key>", function(matching_item_key)
	if not matching_item_key or matching_item_key == "" then
		mod:echo("Usage: /cwv_probe_skins <matching_item_key>  (e.g. es_2h_sword, es_bastard_sword)")
		return
	end
	if not ItemMasterList then mod:echo("ItemMasterList not loaded") return end
	local results = {}
	for key, item in pairs(ItemMasterList) do
		if item.item_type == "weapon_skin" and item.matching_item_key == matching_item_key then
			results[#results + 1] = key
		end
	end
	table.sort(results)
	mod:info("=== Skins for matching_item_key='%s' (%d) ===", matching_item_key, #results)
	for _, key in ipairs(results) do
		local item = ItemMasterList[key]
		local name = key
		if item.display_name then
			local ok, loc = pcall(Localize, item.display_name)
			if ok and loc then name = loc end
		end
		mod:info("%s | %s | %s | rarity=%s", key, name, tostring(item.right_hand_unit or "?"), tostring(item.rarity or "?"))
	end
	mod:echo("Dumped %d skins to log (search for 'Skins for')", #results)
end)

-- ============================================================
-- Unit probe — diagnostic tooling for pickup-asset investigation
-- ============================================================
-- Spawns a Stingray unit at the player's feet and dumps its asset-level
-- properties (actor count, actor names, collision filters, bounding box,
-- attached extensions) to mod:info. Used to compare known-good pickup units
-- (pup_dw_thrown_axe_01_t1, prj_we_javelin_01_3ps) against candidate units
-- (wpn_emp_boar_spear_01_3p, spear_3ps) so we can decide which assets can
-- legitimately serve as pickup units without going through the full
-- spawn-throw-fail iteration cycle.
--
-- Spawned probes persist until cwv_despawn_probes is called or level changes.
--
-- Suggested probe sequence for the Tuskgor Javelin pickup investigation:
--   cwv_probe_unit units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p
--   cwv_probe_unit units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1
--   cwv_probe_unit units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps
--   cwv_probe_unit units/weapons/player/spear_projectile/spear_3ps
--   cwv_despawn_probes
local _probe_units = {}

local function _safe_call(fn, ...)
	local ok, ret = pcall(fn, ...)
	if ok then return ret end
	return nil
end

local function _dump_actor(unit, idx)
	local actor = _safe_call(Unit.actor, unit, idx)
	if not actor then
		mod:info("  [%d] (nil actor)", idx)
		return
	end
	local name = _safe_call(Actor.name, actor) or "(unnamed)"
	local is_static    = _safe_call(Actor.is_static, actor)
	local is_kinematic = _safe_call(Actor.is_kinematic, actor)
	local is_dynamic   = _safe_call(Actor.is_dynamic, actor)
	local cfilter      = _safe_call(Actor.collision_filter, actor)
	mod:info("  [%d] name=%s static=%s kin=%s dyn=%s collision_filter=%s",
		idx, tostring(name),
		tostring(is_static), tostring(is_kinematic), tostring(is_dynamic),
		tostring(cfilter))
end

mod:command("cwv_probe_unit", "Spawn a unit and dump asset properties (/cwv_probe_unit <path>)", function(unit_path)
	if not unit_path or unit_path == "" then
		mod:echo("Usage: /cwv_probe_unit <unit_path>")
		mod:echo("Example paths to compare:")
		mod:echo("  units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p")
		mod:echo("  units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1")
		mod:echo("  units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps")
		mod:echo("  units/weapons/player/spear_projectile/spear_3ps")
		return
	end
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit yet (in-mission only)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local player_pos = Unit.world_position(player.player_unit, 0)
	local player_rot = Unit.world_rotation(player.player_unit, 0)
	local forward    = Quaternion.forward(player_rot)
	local spawn_pos  = player_pos + forward * 1.5 + Vector3.up(player_pos) * 1.0

	-- Pre-check loadability. Stingray's World.spawn_unit asserts in C++
	-- (resource_manager().can_get(...)) when the unit isn't in a loaded
	-- resource package — pcall CANNOT catch that assertion, the engine
	-- hard-crashes. Try to verify the unit is loaded before spawning.
	-- Application.can_get / has_resource APIs vary by Stingray version;
	-- best-effort with multiple fallbacks. If none confirm loadability,
	-- refuse to spawn rather than risk a crash.
	local can_check_apis = {
		function() return Application.can_get and Application.can_get("unit", unit_path) end,
		function() return Application.has_resource and Application.has_resource("unit", unit_path) end,
	}
	local loadable = nil
	for _, check in ipairs(can_check_apis) do
		local ok, result = pcall(check)
		if ok and result ~= nil then loadable = result; break end
	end
	if loadable == false then
		mod:echo("Refusing to spawn '%s' — unit not in loaded resource packages.", unit_path)
		mod:echo("  (would crash; this unit is only loaded when its host weapon is equipped in this lobby)")
		return
	end
	-- If loadable check returned nil, we couldn't verify; user assumes risk.

	local ok, unit = pcall(World.spawn_unit, world, unit_path, spawn_pos)
	if not ok or not unit then
		mod:echo("Spawn failed: %s", tostring(unit))
		mod:info("Spawn failed for %s: %s", unit_path, tostring(unit))
		return
	end

	_probe_units[#_probe_units + 1] = unit

	mod:info("=== PROBE: %s ===", unit_path)

	-- Node hierarchy
	local num_nodes = _safe_call(Unit.num_nodes, unit) or 0
	mod:info("nodes: %d", num_nodes)
	for i = 0, math.min(num_nodes - 1, 30) do
		local name = _safe_call(Unit.node_name, unit, i)
		local pos = _safe_call(Unit.local_position, unit, i)
		local rot = _safe_call(Unit.local_rotation, unit, i)
		local px, py, pz, qx, qy, qz, qw = "?", "?", "?", "?", "?", "?", "?"
		if pos then px, py, pz = string.format("%.2f", Vector3.x(pos)), string.format("%.2f", Vector3.y(pos)), string.format("%.2f", Vector3.z(pos)) end
		if rot then
			local fwd = _safe_call(Quaternion.forward, rot)
			if fwd then qx, qy, qz = string.format("%.2f", Vector3.x(fwd)), string.format("%.2f", Vector3.y(fwd)), string.format("%.2f", Vector3.z(fwd)) end
		end
		mod:info("  [%d] name=%s local_pos=(%s,%s,%s) local_fwd=(%s,%s,%s)",
			i, tostring(name or "?"), px, py, pz, qx, qy, qz)
	end

	-- Actors
	local num_actors = _safe_call(Unit.num_actors, unit) or 0
	mod:info("actors: %d", num_actors)
	for i = 0, num_actors - 1 do
		_dump_actor(unit, i)
	end

	-- Bounding box (asset extents) — different APIs in different SDK versions; try both
	local bmin, bmax = _safe_call(function() return Unit.box(unit) end), nil
	local ok_box, b1, b2 = pcall(Unit.box, unit)
	if ok_box and b1 and b2 then
		mod:info("box min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)",
			Vector3.x(b1), Vector3.y(b1), Vector3.z(b1),
			Vector3.x(b2), Vector3.y(b2), Vector3.z(b2))
	end

	-- Extensions — usually empty for raw World.spawn_unit (no entity_system pass);
	-- log anyway in case the unit auto-attaches anything via its asset metadata.
	local has_pickup = _safe_call(ScriptUnit.has_extension, unit, "pickup_system")
	local has_outline = _safe_call(ScriptUnit.has_extension, unit, "outline_system")
	local has_interaction = _safe_call(ScriptUnit.has_extension, unit, "interactable_system")
	mod:info("extensions: pickup=%s outline=%s interactable=%s",
		tostring(has_pickup ~= nil), tostring(has_outline ~= nil), tostring(has_interaction ~= nil))

	mod:echo("Probed '%s' (probe #%d). Walk around and inspect; cwv_despawn_probes when done. Log written to console.",
		unit_path, #_probe_units)
end)

-- Focused probe for the j_leftweaponattach investigation: spawns each
-- weapon-display rig and reports whether the named attach nodes exist.
-- See `J_LEFTWEAPONATTACH_INVESTIGATION.md` U1.
mod:command("cwv_probe_attach", "Spawn each display rig and check for j_leftweaponattach / j_rightweaponattach", function()
	local rigs = {
		"units/weapons/weapon_display/display_dual_weapons",
		"units/weapons/weapon_display/display_1h_weapon",
		"units/weapons/weapon_display/display_1h_swords",
		"units/weapons/weapon_display/display_dual_axes",
		"units/weapons/weapon_display/display_dual_daggers",
		"units/weapons/weapon_display/display_dual_hammers",
		"units/weapons/weapon_display/dual_wield_axe_falchion",
		"units/weapons/weapon_display/display_2h_weapon",
		"units/weapons/weapon_display/display_shield",
	}
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit (be in keep or mission)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local pos = Unit.world_position(player.player_unit, 0)
	local results = {}
	for _, path in ipairs(rigs) do
		local ok, unit = pcall(World.spawn_unit, world, path, pos)
		if not ok or not unit then
			results[#results + 1] = string.format("%s — SPAWN FAILED (%s)", path, tostring(unit))
		else
			local has_left  = pcall(Unit.node, unit, "j_leftweaponattach")
			local has_right = pcall(Unit.node, unit, "j_rightweaponattach")
			results[#results + 1] = string.format("%s — left=%s right=%s",
				path, tostring(has_left), tostring(has_right))
			pcall(World.destroy_unit, world, unit)
		end
	end

	mod:echo("=== display rig attach-node probe ===")
	for _, line in ipairs(results) do
		mod:info(line)
		mod:echo(line)
	end
	mod:echo("=== end ===")
end)

mod:command("cwv_despawn_probes", "Despawn all probe units spawned via cwv_probe_unit", function()
	local count = 0
	for _, unit in ipairs(_probe_units) do
		if unit and _safe_call(Unit.alive, unit) then
			local ok = pcall(function()
				Managers.state.unit_spawner:mark_for_deletion(unit)
			end)
			if ok then count = count + 1 end
		end
	end
	_probe_units = {}
	mod:echo("Despawned %d probe units", count)
end)

mod:command("cwv_give", "Give a variant weapon: cwv_give <item_key>", function(item_key)
	if not item_key or item_key == "" then
		mod:echo("Usage: cwv_give <item_key>")
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end
	_give_variant(item_key)
end)

mod:info("Character Weapon Variants v%s loaded", MOD_VERSION)
