-- CWV weapon catalog. Keep this module data-only: registration and lifecycle
-- behavior remain owned by the entry module. Policy modules are injected so
-- their canonical model/career constants remain the single source of truth.
return function(ctx)
local _om = ctx.om
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
		careers         = _es_all_careers,
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
		careers         = _es_all_careers,
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
		display_name    = "Imperial Longsword",
		description     = "Standard-issue Imperial longsword of the Reikland state regiments. Forged in their thousands by the smithies of Altdorf - serviceable steel for the men who hold the line against beast and greenskin alike.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		-- #644: the Imperial Longsword model and style template both use Kruber's
		-- native Greatsword action graph; its balance and transform remain distinct.
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
		inventory_icon  = "icon_wpn_empire_2h_sword_04_t1",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Imperial Longsword",
		-- Retired #620 restore bridge. Native es_2h_sword now owns the
		-- Longsword Combat Style; CIM excludes promo/cwv_retired definitions.
		rarity          = "promo",
		skin_rarity     = "default",
		cwv_retired     = true,
		style_target_item = "es_2h_sword",
		-- Historical blacksmith-template power retained for lossless restoration;
		-- new crafting is retired and canonical Greatsword supplies real power.
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
		rarity          = "promo",
		skin_rarity     = "unique",
		cwv_retired     = true,
		style_target_item = "es_2h_sword",
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`.
	},
	{
		-- Imperial Longsword and Shield: Bretonnian sword+shield moveset
		-- (`one_handed_sword_shield_template_2`, native to es_questingknight)
		-- repurposed as Kruber's longsword+shield combo. Right hand uses the
		-- Imperial Longsword mesh (`wpn_2h_sword_04_t1`); left hand uses
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
		-- Issue #627: user-supplied custom launcher mesh (converted by
		-- tools/convert_launcher_assets.ps1). The single source of truth for the
		-- path is _cwv_launcher_family so the wire/preview package aliases match.
		-- Non-CWV peers still see the blunderbuss (family fallback anchor).
		right_hand_unit = _om.launcher_family.UNIT,
		-- STARTING transforms only. The imported FBX is normalized to two Blender
		-- units (barrel along +X) so it needs a scale-down plus the imported-FBX
		-- axis correction the Crowbill/Greataxe imports also needed. Per
		-- CROWBILL_ASSET_PIPELINE.md these are tuned in game (WT 3P Hold-Pose
		-- tuner) and baked here later. See TODO.md / CHANGELOG #627.
		right_hand_scale    = { 0.4, 0.4, 0.4 },
		right_hand_rotation = { -90, -90, -90 },
		-- Trollhammer is left-hand-mount (entry inherits left_hand_unit =
		-- wpn_dr_deus_01 from the clone). We're moving to right-hand-mount
		-- on the blunderbuss model — clear the inherited left so the preview
		-- doesn't render BOTH weapons.
		no_left_hand    = true,
		-- v0.1.365-dev (issue 279): also clear the inherited AMMO unit fields.
		-- dr_deus_01 carries ammo_unit / ammo_unit_3p (the trollhammer torpedo
		-- meshes, item_master_list_morris.lua:7-8), and our template clone keeps
		-- ammo_data with ammo_hand flipped to "right" — so any NO-SKIN resolution
		-- of this entry (a cim-CRAFTED copy has no pre-applied skin) attached the
		-- torpedo to the blunderbuss at wield (gear_utils.lua:164/169/248): the
		-- "crafted item renders merged with the Trollhammer" bug. The curated
		-- skin already declares ammo_unit = nil; this makes the bare entry agree.
		no_ammo_unit    = true,
		inventory_icon  = "icon_wpn_empire_blunderbuss_t1",
		hud_icon        = "weapon_generic_icon_blunderbuss",
		skin_display_name = "Outrider Grenade Launcher",
		rarity          = "exotic",
		template        = "outrider_grenade_launcher_template",
		-- #661: declare every runtime-effective template plus its canonical
		-- donor. Career-action integration consumes this family instead of
		-- assuming ItemMasterList.template is the only executable template.
		effective_templates = {
			{ name = "outrider_grenade_launcher_template",
				source_template = "dr_deus_01_template_1" },
		},
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_outrider_grenade_launcher",
	},
	{
		-- Saltzpyre crossbow ported onto all 4 Kruber careers. Cloned from
		-- wh_crossbow (template = crossbow_template_1). 3P body anims play the
		-- handgun (rifle) wield + idle so Kruber holds it naturally; firing
		-- and zoom-aim are vocab-shared with handgun so no per-action remap
		-- needed. 1P is universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE) — vanilla crossbow 1P with bolt visible.
		--
		-- Migrated from weapon_tweaker v0.12.94-dev (which carried the Kruber
		-- toggles + base-template wield_anim_career_3p patch + preview-time
		-- attachment-node substitution for the engine-fatal `a_unwielded_crossbow`
		-- node Kruber's body doesn't author). See CHANGELOG.
		--
		-- KNOWN POLISH ITEMS (see TODO.md):
		--   * 3P grip offsets need adjusting to fit Kruber's rifle animations
		--   * Smoke FX on shot should be removed (Saltzpyre's flavor, not Kruber's)
		--   * 3P weapon model missing the bolt — may require special offsets;
		--     uncertain whether it's achievable.
		item_key        = "cwv_es_crossbow",
		base_weapon     = "wh_crossbow",
		display_name    = "Crossbow",
		description     = "An imperial-issue crossbow taken up by Reikland state troopers — same Witch-Hunter-pattern weapon, shouldered like the standard handgun.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		inventory_icon  = "icon_wpn_empire_crossbow_t1",
		hud_icon        = "weapon_generic_icon_crossbow",
		skin_display_name = "Crossbow",
		rarity          = "default",
		item_type       = "cwv_es_crossbow",
		-- Inherits template = "crossbow_template_1" from the wh_crossbow IML
		-- clone. The Kruber-specific wield_anim_career_3p[es_*] entries are
		-- patched onto the BASE template (see `_patch_crossbow_template_for_kruber`
		-- below) because the inventory previewer reads template via item.name —
		-- which inherits to "wh_crossbow" — not via the variant's template
		-- override (same constraint as cwv_es_outrider — see its block above).
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
		-- The stance key swaps BackendUtils.get_item_template between these
		-- two templates. Both therefore own the complete live can_wield career
		-- action set, including Bounty Hunter's action_career_wh_2.
		effective_templates = {
			{ name = "old_musket_template",
				source_template = "handgun_template_1" },
			{ name = "old_musket_template_melee",
				source_template = "two_handed_heavy_spears_template" },
		},
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
		-- Save-compatible internal key. This illusion originally shipped under an
		-- invented Nordland identity, but CWV first catalogued this mesh as the
		-- Helmgart watch pattern. Keep the key so persisted cosmetics survive.
		display_name    = "Helmgart Watchsword",
		description     = "An Imperial longsword in the Helmgart watch pattern, carried by the soldiers who guard the mountain pass against raiders from the Reikwald and beyond.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_greatsword/wpn_greatsword",
		inventory_icon  = "icon_wpn_greatsword",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Helmgart Watchsword",
		rarity          = "exotic",
		style_target_item = "es_2h_sword",
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
		-- #597: exact Bardin Greataxe behavior on Kruber, rendered through
		-- converted third-party models declared in `_cwv_greataxe.lua`.
		-- The first usable manifest row owns the default mesh. Until one is
		-- present the cloned Bardin mesh is retained as a safe fallback.
		-- Keep this key literal so the repository name-map generator can ingest
		-- the runtime registration without evaluating Lua module constants.
		item_key        = "cwv_es_greataxe",
		base_weapon     = _om.greataxe.BASE_WEAPON,
		display_name    = "Greataxe",
		description     = "A heavy two-handed axe built for breaking shield walls and hewing through packed ranks.",
		character       = "empire_soldier",
		careers         = _om.greataxe.DEFAULT_CAREERS,
		right_hand_unit = (_om.greataxe.default_model() or {}).right_hand_unit,
		right_hand_scale_3p = (_om.greataxe.default_model() or {}).right_hand_scale_3p,
		right_hand_offset_3p = (_om.greataxe.default_model() or {}).right_hand_offset_3p,
		right_hand_rotation_3p = (_om.greataxe.default_model() or {}).right_hand_rotation_3p,
		inventory_icon  = (_om.greataxe.default_model() or {}).inventory_icon or "icon_wpn_dw_2h_axe_01_t1",
		hud_icon        = (_om.greataxe.default_model() or {}).hud_icon or "weapon_generic_icon_axe2h",
		skin_display_name = (_om.greataxe.default_model() or {}).display_name or "Greataxe Model 01",
		rarity          = "exotic",
		template        = _om.greataxe.TEMPLATE_KEY,
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = _om.greataxe.ITEM_TYPE,
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
		inventory_icon  = "icon_wpn_axe_hatchet_t1_dual_cwv",
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
		inventory_icon  = "icon_wpn_axe_hatchet_t1_dual_cwv",
		hud_icon        = "weapon_generic_icon_axe1h",
		skin_display_name = "Dual Axes",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- Saltzpyre's variant uses the same canonical wh_1h_axe cosmetic
		-- family as Kruber's twin-hatchet variant, in its own curated pool.
		item_type       = "cwv_wh_dual_axes",
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
		template        = "cwv_dual_maces_template",
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
		template        = "cwv_dual_maces_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- See cwv_es_dual_maces above for the item_type / display rig rationale.
		item_type       = "cwv_wh_dual_maces",
	},
	-- Issue #602: Dawi models with mace gameplay identities. The Bardin hammer
	-- meshes are resident placeholders only; the moveset/template is canonical.
	-- Reusing #599's existing mace template keys makes its modifier template-
	-- scoped and therefore impossible to compound across these three items.
	{
		item_key        = "cwv_dr_dawi_mace",
		base_weapon     = "es_1h_mace",
		template        = "one_handed_hammer_template_1",
		display_name    = "Dawi Mace",
		description     = "A compact Dawi striking weapon, balanced for forceful mace blows.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_ONE_HANDED,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		inventory_icon  = "icon_wpn_dw_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dawi Mace",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_mace",
	},
	{
		item_key        = "cwv_dr_dawi_mace_shield",
		base_weapon     = "es_mace_shield",
		template        = "one_handed_hammer_shield_template_1",
		display_name    = "Dawi Mace and Shield",
		description     = "A Dawi mace paired with a broad shield for holding the line.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_SHIELD,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		left_hand_unit  = _om.dawi_maces.PLACEHOLDER_SHIELD,
		inventory_icon  = "icon_wpn_dw_shield_01_hammer",
		hud_icon        = "weapon_generic_icon_hammer_and_sheild",
		skin_display_name = "Dawi Mace and Shield",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_mace_shield",
	},
	{
		item_key        = "cwv_dr_dawi_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		template        = "cwv_dual_maces_template",
		display_name    = "Dawi Dual Maces",
		description     = "A matched pair of Dawi maces for an unbroken rhythm of crushing blows.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_ONE_HANDED,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		left_hand_unit  = _om.dawi_maces.PLACEHOLDER_MACE,
		inventory_icon  = "icon_dr_dual_wield_hammers_01",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dawi Dual Maces",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_dual_maces",
	},
	-- Crowbill family: registration-only definitions use Sienna's resident
	-- vanilla Crowbill as a licence-safe placeholder. CIM owns acquisition;
	-- the isolated hammer-mode module consumes `crowbill_mode_family`.
	{
		item_key        = "cwv_es_imperial_crowbill",
		base_weapon     = _om.crowbill_family.SOURCE_ITEM,
		template        = _om.crowbill_family.SOURCE_TEMPLATE,
		display_name    = "Imperial Crowbill",
		description     = "An Imperial crowbill with a hooked face for armour and a hammer face for crushing blows.",
		character       = "empire_soldier",
		careers         = _om.crowbill_family.IMPERIAL_DEFAULTS,
		right_hand_unit = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).right_hand_unit
			or _om.crowbill_family.PLACEHOLDER_UNIT,
		inventory_icon  = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).inventory_icon
			or _om.crowbill_family.PLACEHOLDER_ICON,
		hud_icon        = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).hud_icon
			or "weapon_generic_icon_falken",
		skin_display_name = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).display_name
			or "Imperial Crowbill",
		item_type       = "cwv_es_imperial_crowbill",
		crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY,
	},
	{
		item_key        = "cwv_dr_dawi_crowbill",
		base_weapon     = _om.crowbill_family.SOURCE_ITEM,
		template        = _om.crowbill_family.SOURCE_TEMPLATE,
		display_name    = "Dawi Crowbill",
		description     = "A Dawi crowbill built to pierce plate or turn its hammer face against shield and bone.",
		character       = "dwarf_ranger",
		careers         = _om.crowbill_family.DAWI_DEFAULTS,
		right_hand_unit = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).right_hand_unit
			or _om.crowbill_family.PLACEHOLDER_UNIT,
		inventory_icon  = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).inventory_icon
			or _om.crowbill_family.PLACEHOLDER_ICON,
		hud_icon        = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).hud_icon
			or "weapon_generic_icon_falken",
		skin_display_name = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).display_name
			or "Dawi Crowbill",
		item_type       = "cwv_dr_dawi_crowbill",
		crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY,
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

return {
	es_all_careers = _es_all_careers,
	wh_all_careers = _wh_all_careers,
	bw_all_careers = _bw_all_careers,
	definitions = _variant_definitions,
}
end
