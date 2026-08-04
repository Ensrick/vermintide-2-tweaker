-- Retroactive appearance census for character_weapon_variants (CWV).
-- ============================================================================
-- W0 gate of docs/APPEARANCE_UNIFICATION_PLAN.md. This is a machine-readable
-- INVENTORY OF TODAY'S REALITY, holes included - NOT a wish list. A false
-- "implemented" recreates the whack-a-mole this gate exists to kill, so the
-- rule enforced here is deliberately strict:
--
--   * A pair is "implemented" only when a real code path applies appearance on
--     that surface, at that lifecycle edge, for that family (the citations live
--     in the W0 report and in the per-family comments below).
--   * A pair that is unsure, partially wired, or tracked by an open husk/preview
--     issue is "unsupported" WITH an honest note naming why it is safe (which
--     resident vanilla presentation it degrades to) and the issue that tracks it.
--
-- SCHEMA v2 - SURFACE x EDGE MATRIX (re-keyed 2026-08-04, issue 1157).
-- Until 2026-08-04 a family declared surfaces and lifecycle edges as two
-- INDEPENDENT vectors, so "husk = implemented" and "mission_transition =
-- unsupported" could coexist with no way to say "husk AT mission transition is
-- the thing that breaks" - which is the exact recurring failure class (issues
-- 914, 476, 738). Every (surface, edge) PAIR is now declared. Authoring is
-- compact: one row per surface stating its default EXPLICITLY, plus per-edge
-- overrides; tools/shared_lib/_lib_appearance_descriptor.lua expands it to the
-- full matrix and FAILS on any pair it cannot resolve. Nothing is implicit.
--
-- CONVERSION RULE APPLIED 2026-08-04 (conservative, never optimistic):
--   1. base state = min(old surface state, old edge state) - implemented only
--      where BOTH were implemented;
--   2. any pair with a known open issue or documented doubt is FORCED
--      unsupported with the issue named, even where step 1 allowed
--      implemented. Applied here: husk x peer_ready, husk x customize, and
--      husk x mission_transition on every family; lobby and score_team on
--      every family except crowbill;
--   3. the six surfaces added by 1157 (specials, remote_audio, hud_panels,
--      portraits, item_card_2d, inventory_tooltip) start unsupported unless
--      concrete code evidence shows the family implements one. Two exceptions
--      earned evidence here: crowbill specials and dual_axes item_card_2d.
--
-- Vocabulary is fixed by tools/shared_lib/_lib_appearance_descriptor.lua
-- (M.CELLS / M.EDGES); qa/lua/tests/test_appearance_census.lua validates it.
--
-- PURE DATA: this module touches no engine globals and no get_mod; it is loaded
-- with dofile() by the validator and returns { families = { ... } } directly.
-- The builder locals below are plain-Lua table constructors, not runtime state.
--
-- ---------------------------------------------------------------------------
-- Methodology (how each baseline classification was reached)
-- ---------------------------------------------------------------------------
-- Line citations are into character_weapon_variants.lua unless noted; they are
-- against the 2026-07-17 source and should be matched by FUNCTION NAME, not a
-- fixed line, after any edit (same rule as ENGINE_SURFACE.md).
--
-- owner_1p / owner_3p / bot   IMPLEMENTED at the spawn/equip/preview edges for
--   every family. The owner + bot spawn path GearUtils.create_equipment (:11830)
--   resolves per-hand units at the data level through the BackendUtils.
--   get_item_units hook (:11136), and WeaponAppearance (WA) applies
--   transform_1p/transform_3p per perspective. Bots ride the same host-local
--   create_equipment path (is_bot), so they never diverge from owner_3p.
--
-- inventory_preview           IMPLEMENTED baseline. Path 3 (MenuWorldPreviewer):
--   mesh-swap pre-pass MenuWorldPreviewer.equip_item (:1765) ->
--   _cwv_preview_meshswap_apply (:8971); transform via MenuWorldPreviewer.
--   _spawn_item (:12264) -> _cwv_spawn_item_post.
--
-- illusion_browser / cim_preview   IMPLEMENTED baseline. Path 4 + Athanor both
--   ride LootItemUnitPreviewer.spawn_units (:11481) -> _cwv_browser_meshswap_apply
--   (:9010, base_identity adapter) which resolves the 482 crafted-UUID ladder
--   against self._item; transform in the same hook body.
--
-- husk                        UNSUPPORTED at every edge. The re-key path exists -
--   SimpleHuskInventoryExtension._wield_slot (:3705), the single decision point
--   _husk_resolve_display_def (:10646), 478 hand preselect (:10709) - and it
--   CLOSES the burned cells for skin-carrying wields. But skinless parity under
--   weapon_tweaker's runtime can_wield expansion still needs the per-wearer
--   marker (392 umbrella / 474 / 579), the 660 identity ledger that would
--   prove it is diagnostics-armed + coop-required, and every family carries an
--   open husk issue. Partially wired -> unsupported. Safe fallback everywhere:
--   the loadout wire substitutes the vanilla base key (278/495) so a husk that
--   fails to re-key shows the RESIDENT vanilla base weapon, never a crash/void.
--
-- lobby / score_team          UNSUPPORTED baseline. Transform rides the shared
--   HeroPreviewer._spawn_item seam (:12256, used by team_previewer), but the
--   mesh-swap pre-passes do NOT fire on that previewer and lobby/score weapon
--   appearance is unverified (513 isolated only the score wearer identity).
--   The crowbill family is the sole exception - it wires both surfaces.
--
-- hold_tab                    UNSUPPORTED for ALL families. The player-list card
--   is rebuilt from rpc_sync_loadout_slot with NO backend ID; CWV deliberately
--   substitutes the vanilla base key on that wire (278/495), so the card shows
--   the resident vanilla base weapon. No custom UI identity ships (638/641).
--
-- specials                    UNSUPPORTED except crowbill. CWV owns no generic
--   weapon-special transform channel; crowbill is the one family whose
--   pick/hammer face is a weapon-special toggle (_cwv_crowbill_family.lua:39)
--   driving a real rotation owner across 9 surfaces
--   (_cwv_crowbill_presentation.lua:13-23).
--
-- remote_audio                UNSUPPORTED for ALL families - open issue 398
--   (CWV sounds absent for remote players); 474 adds the Old Musket remote shot.
--
-- hud_panels                  UNSUPPORTED for ALL families. CWV projects no
--   career HUD/ability panel state for its variants (807 class).
--
-- portraits                   UNSUPPORTED for ALL families. Portrait rendering
--   belongs to dynamic_cosmetic_portraits, which CWV does not drive (925 class).
--
-- item_card_2d                UNSUPPORTED except dual_axes. Only the paired dual
--   axe icons have a CWV-owned atlas (_cwv_inventory_icons.lua); every other
--   family deliberately reuses its authentic vanilla icon.
--
-- inventory_tooltip           UNSUPPORTED for ALL families. CWV supplies no
--   tooltip-side appearance identity (660).
--
-- EDGES. instance_load (boot _auto_register_all on StateInGameRunning.on_enter),
--   equip (game_object_initialized / _spawn_resynced_loadout / create_equipment),
--   peer_ready (GearUtils.hot_join_sync :11677 + cwv_item_identity channel),
--   customize (equip_item mesh-swap + skin persistence), and preview_open
--   (previewer hooks) are IMPLEMENTED baseline on the owner-side surfaces.
--   mission_transition, respawn, and mod_disable_restore are UNSUPPORTED on
--   every surface: the S3 bounded lifecycle reconciler is W2-pending, respawn is
--   recorded deferred in the plan's initial registry (section 8a), and no
--   dedicated mod-disable appearance-restore path exists (it relies on the same
--   vanilla-base wire fallback). Identity re-publishes on transition, but the
--   transform/material/pose replay that recurs as regressions (416/483) is
--   feature-owned, not a proven single-generation reconciler.
-- ============================================================================

local IMPL = "implemented"
local UNSUP = "unsupported"

-- row(default, note, edge_overrides, edge_notes) - `default` is mandatory and
-- explicit; `note` covers every unsupported pair in the row that has no
-- per-edge note of its own.
local function row(default, note, edge_overrides, edge_notes)
	return { default = default, note = note, edges = edge_overrides, notes = edge_notes }
end

-- Shallow merge into a NEW table so the shared constants below stay immutable.
local function plus(base, extra)
	local t = {}
	if base then for k, v in pairs(base) do t[k] = v end end
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

-- The three lifecycle edges CWV has never owned, applied to every surface that
-- is otherwise implemented (step 1 of the conversion rule).
local OPEN_LIFECYCLE = {
	mission_transition = UNSUP, respawn = UNSUP, mod_disable_restore = UNSUP,
}
local FB_TRANSITION = "The S3 bounded lifecycle reconciler is W2-pending: identity re-publishes across a mission transition but the transform/material/pose replay is feature-owned per surface, not a proven single-generation replay (416/483). Degrades to the resident vanilla base presentation."
local FB_RESPAWN = "Respawn replay is recorded deferred in the plan's initial registry (section 8a); a respawned unit re-derives from the spawn path with no dedicated appearance replay. Degrades to the resident vanilla base presentation."
local FB_DISABLE = "No dedicated mod-disable appearance-restore path exists; already-spawned units keep their applied presentation until the next re-equip or mission load, and the loadout wire's vanilla-base substitution (278/495) carries the safety. Degrades to the resident vanilla base presentation."
local OPEN_LIFECYCLE_NOTES = {
	mission_transition = FB_TRANSITION,
	respawn = FB_RESPAWN,
	mod_disable_restore = FB_DISABLE,
}

-- Husk is unsupported at every edge (see methodology). These three pairs carry
-- their own class citation because they are the recurring failures 1157 exists
-- to make nameable.
local HUSK_EDGE_NOTES = plus(OPEN_LIFECYCLE_NOTES, {
	peer_ready = "Hot-join: the observer joins after the wearer already equipped, so the identity must arrive by replay rather than by an equip event (476 Imperial Sword and Shield, 738 musket replay audit, 914 dual-axe illusion). Degrades to the resident vanilla base key the loadout wire substitutes (278/495).",
	customize = "A live customization change on the wearer is not replayed to an already-spawned husk; the 1145 per-wearer re-wield coalescer bounds the re-wield storm but the resulting husk cells are unverified. Degrades to the previously resolved presentation, then to the resident vanilla base key (278/495).",
	mission_transition = "Husk identity across a mission transition is the 914 replay class: the joining/persisting observer rebuilds from the loadout wire, which carries the vanilla base key (278/495), not the variant. Degrades to the resident vanilla base weapon.",
})

local FB_LOBBY = "Transform rides the shared HeroPreviewer._spawn_item seam (:12256) but the mesh-swap pre-pass never fires on the lobby previewer and full lobby weapon parity is unverified; degrades to the data-level get_item_units mesh over the resident vanilla base (513)."
local FB_SCORE = "End-of-mission TeamPreviewer reconstructs from the score snapshot; CWV weapon appearance is not wired to the score lineup (513 isolated wearer identity only); degrades to the resident vanilla base mesh."
local FB_HOLDTAB = "Player-list card is rebuilt from rpc_sync_loadout_slot with no backend ID; CWV substitutes the vanilla base key on the loadout wire for cross-peer safety (278/495), so the card shows the resident vanilla base weapon; no custom UI identity shipped (638/641)."

-- Surfaces added by 1157. Unsupported for every family unless a family overrides
-- the whole row with cited code evidence.
local FB_SPECIALS = "CWV owns no generic weapon-special transform channel; a weapon special renders the base template's own special presentation. Safe (vanilla). Tracked 660."
local FB_REMOTE_AUDIO = "CWV sounds are not reproduced for remote players - open issue 398 (474 adds the Old Musket remote shot). Remote peers hear the resident vanilla base weapon audio. Safe (vanilla)."
local FB_HUD = "CWV projects no career HUD or ability-panel presentation for its variants; the receiving career's native HUD renders unchanged. Safe (vanilla). Tracked 807 class."
local FB_PORTRAITS = "Portrait rendering belongs to dynamic_cosmetic_portraits, which CWV neither drives nor supplies identity to; portraits render the vanilla career art. Safe (vanilla). Tracked 925 class."
local FB_ITEM_CARD = "This family registers no CWV-owned icon and deliberately reuses its authentic vanilla icon on the 2D item card. Correct by construction; no custom identity to lose. Tracked 660 / 638 / 641."
local FB_TOOLTIP = "CWV supplies no tooltip-side appearance identity (mesh, transform, or material); the tooltip renders the cloned base template's vanilla text and icon. Safe (vanilla). Tracked 660."

local function new_surface_rows()
	return {
		specials          = row(UNSUP, FB_SPECIALS),
		remote_audio      = row(UNSUP, FB_REMOTE_AUDIO),
		hud_panels        = row(UNSUP, FB_HUD),
		portraits         = row(UNSUP, FB_PORTRAITS),
		item_card_2d      = row(UNSUP, FB_ITEM_CARD),
		inventory_tooltip = row(UNSUP, FB_TOOLTIP),
	}
end

-- Fresh row set per call so no two families share a mutable reference.
-- `husk_note` is the family's own husk fallback; `overrides` replaces whole rows.
local function matrix(husk_note, overrides)
	local m = new_surface_rows()
	m.owner_1p          = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.owner_3p          = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.bot               = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.husk              = row(UNSUP, husk_note, nil, HUSK_EDGE_NOTES)
	m.inventory_preview = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.illusion_browser  = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.cim_preview       = row(IMPL, nil, OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES)
	m.lobby             = row(UNSUP, FB_LOBBY)
	m.score_team        = row(UNSUP, FB_SCORE)
	m.hold_tab          = row(UNSUP, FB_HOLDTAB)
	if overrides then for k, v in pairs(overrides) do m[k] = v end end
	return m
end

local families = {}

-- Combat-Style / greatsword-family illusions -------------------------------
-- cwv_es_longsword, cwv_es_longsword_blackguard, cwv_es_longsword_nordland.
-- item_type cwv_imperial_longsword; retired (cwv_retired) + promo, now carried
-- as a Combat Style / illusion on native es_2h_sword (620/644). Owner renders
-- the longsword mesh through the style+skin on the native greatsword.
-- FORCED at customize on every owner-side surface: 657 and 786/692 show style
-- model/template replay is NOT part of the generic appearance lifecycle.
local STYLE_CUSTOMIZE_NOTE = "Selecting a different Combat Style re-keys the model and template outside the generic appearance lifecycle (657); the remote and cross-surface replay of that switch is unproven (786 remote style transition, 692 style offsets). Degrades to the previously applied style, then to the resident native es_2h_sword greatsword."
local STYLE_EDGES = plus(OPEN_LIFECYCLE, { customize = UNSUP })
local STYLE_NOTES = plus(OPEN_LIFECYCLE_NOTES, { customize = STYLE_CUSTOMIZE_NOTE })
families.imperial_longsword = {
	matrix = matrix(
		"396 (Imperial Longsword invisible on husk, residency). Now a Combat Style on native es_2h_sword, so the husk resolves the native greatsword wire; the variant-mesh re-key via _husk_resolve_display_def (:10646) is coop-unverified. Degrades to the resident native es_2h_sword greatsword mesh.",
		{
			owner_1p          = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
			owner_3p          = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
			bot               = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
			inventory_preview = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
			illusion_browser  = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
			cim_preview       = row(IMPL, nil, STYLE_EDGES, STYLE_NOTES),
		}),
}

-- cwv_es_longsword_shield: Bretonnian one_handed_sword_shield_template_2 as
-- Kruber longsword + Empire shield (base es_sword_shield_breton).
families.imperial_longsword_shield = {
	matrix = matrix(
		"396/415 husk residency for the shield offhand; base+career re-key (:3705/:10646) exists but the left-hand shield attach on a remote peer is coop-unverified, and 476 tracks the hot-join case directly. Degrades to the resident vanilla es_sword_shield_breton base."),
}

-- Sword/axe + shield families ----------------------------------------------
-- cwv_es_axe_shield + _veteran: item_type cwv_es_axe_shield (base dr_shield_axe).
families.empire_axe_shield = {
	matrix = matrix(
		"401 (husk reverts to dwarf base, wrong units force-loaded) + 415 (host shield offhand). The data-driven residency pass + re-key (:3705/:10646) exist but remain coop-unverified. Degrades to the resident vanilla dr_shield_axe base."),
}

-- cwv_we_sword_shield + _veteran: elven_sword_shield_template (base es_sword_shield).
-- Path-3 preview mesh-swap (_cwv_preview_meshswap_apply) originated here (237).
families.elven_sword_shield = {
	matrix = matrix(
		"401-class shield residency on the husk (left-hand Athel Loren shield); base+career re-key (:10646) is coop-unverified. Degrades to the resident vanilla es_sword_shield base."),
}

-- Warrior-Priest hammer families (Skullsplitter mesh pipeline) --------------
-- cwv_dr_priest_greathammer + cwv_es_priest_greathammer: two_handed_hammer_priest
-- _template, base wh_2h_hammer, dwarf/empire 2H hammer meshes.
families.priest_greathammer = {
	matrix = matrix(
		"392 umbrella husk: base wh_2h_hammer re-key via _husk_resolve_display_def (:10646); skinless parity under wt-expanded can_wield is coop-unverified, and the dwarf variant's 3P pose coverage is itself unverified. Degrades to the resident vanilla wh_2h_hammer base."),
}

-- cwv_es_warpriest_hammer (1H), cwv_es_dual_warpriest_hammers (dual),
-- cwv_es_warpriest_hammer_shield (hammer+shield). All Skullsplitter
-- wpn_wh_1h_hammer_01 mesh + {0,0,0.15} grip; distinct bases
-- (wh_1h_hammer / wh_dual_hammer / wh_hammer_shield).
families.warpriest_hammers = {
	matrix = matrix(
		"392 husk: Skullsplitter mesh re-key via _husk_resolve_display_def (:10646); skinless parity coop-unverified and the shield variant adds the 401-class left-hand attach. Degrades to the resident vanilla wh_1h_hammer / wh_dual_hammer / wh_hammer_shield base."),
}

-- Single-hand moveset swaps on Empire meshes -------------------------------
-- cwv_es_maul: bw_1h_mace morningstar moveset, Empire mace mesh, fire-DoT scrub.
families.maul = {
	matrix = matrix(
		"392/397 husk (mesh + transform): bw_1h_mace re-key via _husk_resolve_display_def (:10646) is coop-unverified. Degrades to the resident vanilla bw_1h_mace base."),
}

-- cwv_es_cudgel: es_1h_mace falchion-to-blunt moveset, Empire mace mesh.
families.cudgel = {
	matrix = matrix(
		"392 husk: es_1h_mace re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla es_1h_mace base."),
}

-- cwv_es_shortsword: bw_dagger moveset (DoT scrubbed), Empire sword mesh.
families.shortsword = {
	matrix = matrix(
		"392 husk: bw_dagger re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla bw_dagger base."),
}

-- cwv_es_rapier: wh_fencing_sword, pistol disabled, no_left_hand.
families.rapier = {
	matrix = matrix(
		"392 husk: wh_fencing_sword re-key via _husk_resolve_display_def (:10646); the no_left_hand pistol strip on a remote peer is coop-unverified. Degrades to the resident vanilla wh_fencing_sword base.",
		{
			-- 807 is the Rapier's own HUD-panel issue (pistol-less contract in
			-- the secondary melee slot), so this family cites it directly.
			hud_panels = row(UNSUP, "807: the pistol-less Rapier contract governs what the career HUD reports for the secondary melee slot; CWV supplies no HUD-panel presentation of its own and the native panel renders the base wh_fencing_sword state. Safe (vanilla)."),
		}),
}

-- Dual-wield families -------------------------------------------------------
-- cwv_es_dual_swords: we_dual_wield_swords moveset, Empire sword both hands.
families.imperial_dual_swords = {
	matrix = matrix(
		"392 husk: we_dual_wield_swords re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla we_dual_wield_swords base."),
}

-- cwv_es_sword_and_mace: es_dual_wield_hammer_sword inverse layout (per-hand
-- damage swap is gameplay, not appearance).
families.sword_and_mace = {
	matrix = matrix(
		"392 husk: es_dual_wield_hammer_sword re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla es_dual_wield_hammer_sword base."),
}

-- cwv_es_dual_axes + cwv_wh_dual_axes: dual_wield_axes_template_1, Saltzpyre
-- hatchet mesh both hands, per-character 3P wield route. This is the ONE family
-- with a CWV-owned 2D icon atlas (paired dual-axe icons).
families.dual_axes = {
	matrix = matrix(
		"392 husk: dr_dual_wield_axes re-key via _husk_resolve_display_def (:10646) coop-unverified; 579 recorded an offline PASS against a live co-op FAIL and 914 tracks the per-axe illusion pair on hot-join. Degrades to the resident vanilla dr_dual_wield_axes base.",
		{
			-- item_card_2d IMPLEMENTED: _cwv_inventory_icons.lua declares the
			-- private atlas materials/character_weapon_variants/cwv_weapon_icons
			-- with the paired *_dual_cwv icon ids and a per-icon vanilla FALLBACKS
			-- map; resolve() is wired at character_weapon_variants.lua:66/:69.
			item_card_2d = row(IMPL,
				"Renderers outside the allow-list {ingame_ui, hero_view, loading_view, popup_manager} fail closed to the per-icon vanilla FALLBACKS entry (_cwv_inventory_icons.lua), so the card always renders a resident icon.",
				OPEN_LIFECYCLE, OPEN_LIFECYCLE_NOTES),
		}),
}

-- cwv_es_dual_maces + cwv_wh_dual_maces: cwv_dual_maces_template, Empire mace
-- both hands, display_dual_hammers rig forced in _force_display_unit.
families.dual_maces = {
	matrix = matrix(
		"392 husk: dr_dual_wield_hammers re-key via _husk_resolve_display_def (:10646); the display_dual_hammers rig residency on a remote peer is coop-unverified. Degrades to the resident vanilla dr_dual_wield_hammers base."),
}

-- cwv_dr_dawi_mace / _mace_shield / _dual_maces: mace gameplay identities on
-- Bardin hammer PLACEHOLDER meshes (602), resident vanilla bases.
families.dawi_maces = {
	matrix = matrix(
		"602/392 husk: placeholder Bardin hammer meshes re-key via _husk_resolve_display_def (:10646) coop-unverified; the shield member adds the 401-class left-hand attach. Degrades to the resident vanilla es_1h_mace / es_mace_shield / dr_dual_wield_hammers base."),
}

-- Ranged / thrown families --------------------------------------------------
-- cwv_es_javelin + cwv_wh_javelin: tuskgor_javelin_template, boar-spear held
-- mesh (left hand), invisible right, ammo + projectile + pickup path.
families.tuskgor_javelin = {
	matrix = matrix(
		"399 (thrown-weapon ammo strip on the husk). Boar-spear held mesh re-keys via _husk_resolve_display_def (:10646), but the ammo-unit strip + projectile identity on a remote peer are coop-unverified. Degrades to the resident vanilla we_javelin base.",
		{
			remote_audio = row(UNSUP, "398: remote players do not hear CWV weapon sounds; a thrown javelin's release and impact audio fall back to the resident vanilla we_javelin cues on every observing peer. Safe (vanilla)."),
		}),
}

-- cwv_es_crossbow: wh_crossbow ported to Kruber (rifle 3P anims), preview-time
-- a_unwielded_crossbow attachment-node substitution.
families.imperial_crossbow = {
	matrix = matrix(
		"392 husk: wh_crossbow re-key via _husk_resolve_display_def (:10646); the a_unwielded_crossbow node that Kruber's body lacks is only guarded on the previewer, so the remote husk edge is coop-unverified. Degrades to the resident vanilla wh_crossbow base."),
}

-- Custom / imported-mesh families -------------------------------------------
-- cwv_es_outrider_grenade_launcher: resident vanilla Kruber blunderbuss visual,
-- Trollhammer behavior, no_ammo_unit, no_left_hand (762/279).
families.outrider_grenade_launcher = {
	matrix = matrix(
		"399 (torpedo/ammo on husk) + 279 (crafted copy merges with the Trollhammer). The 762 visual is the resident vanilla wpn_empire_blunderbuss_t1 unit; only the ammo strip remains coop-unverified. Degrades to the resident vanilla dr_deus_01 Trollhammer/blunderbuss base."),
}

-- cwv_es_musket_old: LA-pattern custom mesh (mat_to_use vanilla material),
-- cross-slot stance toggle, NetworkLookup.inventory_packages alias (:4358).
families.old_musket = {
	matrix = matrix(
		"474 (Old Musket husk custom mesh + remote shot audio). _husk_custom_bundle_unit (:4326) makes the LA-pattern mesh resident, but husk parity is diagnostics-armed + coop-required and 738 audited the pre-join replay case. Degrades to the resident vanilla es_handgun rifle.",
		{
			-- cim_preview stays IMPLEMENTED: 617's resource-gated painter
			-- (:12103, verified Athanor closure) binds the custom textures.
			illusion_browser = row(UNSUP,
				"227 (Old Musket illusion entry renders red/transparent in the cosmetic browser). The mesh spawns via _cwv_browser_meshswap_apply (:9010) and 617's shared per-unit painter should close the texture, but the illusion-browser pane is not yet verified. Degrades to the base es_handgun rifle mesh."),
			remote_audio = row(UNSUP,
				"474: the Old Musket's authored shot audio is not reproduced for remote players (398 class); observing peers hear the resident vanilla es_handgun report. Safe (vanilla)."),
		}),
}

-- cwv_es_greataxe: converted third-party models (_cwv_greataxe.lua, 597); until
-- a manifest model is present the cloned Bardin greataxe mesh is the fallback.
families.greataxe = {
	matrix = matrix(
		"597 husk for the converted custom models: base+career re-key via _husk_resolve_display_def (:10646) plus the mod_unit_preview fallback are coop-unverified on the husk. Degrades to the resident Bardin dwarf greataxe base mesh."),
}

-- cwv_es_imperial_crowbill + cwv_dr_dawi_crowbill: converted models with a
-- hammer-mode toggle (crowbill_mode_family); CIM owns acquisition. This is the
-- ONE family that wires lobby + score presentation (604 TeamPreviewer bridge)
-- and the ONE family with a weapon-special transform channel.
-- 719 (client sees the Sienna crowbill for the Kruber variant) forces every
-- remote-facing pair on this family down at peer_ready.
local CROWBILL_REMOTE_NOTE = "719: a client resolved the wrong (Sienna placeholder) crowbill for the Kruber variant, so remote-facing identity at hot-join is disproven, not merely unverified. Degrades to the resident Sienna Crowbill placeholder mesh."
local CROWBILL_EDGES = plus(OPEN_LIFECYCLE, { peer_ready = UNSUP })
local CROWBILL_NOTES = plus(OPEN_LIFECYCLE_NOTES, { peer_ready = CROWBILL_REMOTE_NOTE })
families.crowbill = {
	matrix = matrix(
		"Husk mesh + hammer-mode ride crowbill_runtime.on_husk_wield (:3740), but custom-model residency plus cross-peer mode sync on the husk are coop-unverified and 719 recorded a wrong-variant resolve on the client. Degrades to the resident Sienna Crowbill placeholder mesh.",
		{
			-- lobby/score_team IMPLEMENTED: _apply_crowbill_presentation (:9974) is
			-- driven for the lobby_preview / score_preview surfaces (:12051-12057)
			-- with the wearer peer resolved via _crowbill_team_peer (:12141) /
			-- resolve_score_peer (_cwv_crowbill_presentation.lua:47) and
			-- identity_for_peer (_cwv_crowbill_runtime.lua:148).
			lobby      = row(IMPL, nil, CROWBILL_EDGES, CROWBILL_NOTES),
			score_team = row(IMPL, nil, CROWBILL_EDGES, CROWBILL_NOTES),
			-- specials IMPLEMENTED: the pick/hammer face is a weapon-special
			-- toggle (_cwv_crowbill_family.lua:39) composed as one exact local-axis
			-- 180-degree rotation over the authored base pose, applied through the
			-- presentation owner's 9-surface contract (_cwv_crowbill_presentation
			-- .lua:13-23) and replayed bounded via reapply/reapply_all.
			specials   = row(IMPL, nil, CROWBILL_EDGES, CROWBILL_NOTES),
		}),
}

return { schema_version = 2, families = families }
