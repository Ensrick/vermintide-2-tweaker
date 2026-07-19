-- Retroactive appearance census for character_weapon_variants (CWV).
-- ============================================================================
-- W0 gate of docs/APPEARANCE_UNIFICATION_PLAN.md. This is a machine-readable
-- INVENTORY OF TODAY'S REALITY, holes included - NOT a wish list. A false
-- "implemented" recreates the whack-a-mole this gate exists to kill, so the
-- rule enforced here is deliberately strict:
--
--   * A cell is "implemented" only when a real code path applies appearance on
--     that surface for that family (the citations live in the W0 report and in
--     the per-family comments below).
--   * A cell that is unsure, partially wired, or tracked by an open husk/preview
--     issue is "unsupported" WITH an honest unsupported_fallback note naming why
--     it is safe (which resident vanilla presentation it degrades to) and the
--     issue that tracks the hole.
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
-- owner_1p / owner_3p / bot   IMPLEMENTED for every family. The owner + bot
--   spawn path GearUtils.create_equipment (:11830) resolves per-hand units at
--   the data level through the BackendUtils.get_item_units hook (:11136), and
--   WeaponAppearance (WA) applies transform_1p/transform_3p per perspective.
--   Bots ride the same host-local create_equipment path (is_bot), so they never
--   diverge from owner_3p.
--
-- inventory_preview           IMPLEMENTED baseline. Path 3 (MenuWorldPreviewer):
--   mesh-swap pre-pass MenuWorldPreviewer.equip_item (:1765) ->
--   _cwv_preview_meshswap_apply (:9181); transform via MenuWorldPreviewer.
--   _spawn_item (:12264) -> _cwv_spawn_item_post.
--
-- illusion_browser / cim_preview   IMPLEMENTED baseline. Path 4 + Athanor both
--   ride LootItemUnitPreviewer.spawn_units (:12284) -> _cwv_browser_meshswap_apply
--   (:9221, base_identity adapter) which resolves the #482 crafted-UUID ladder
--   against self._item; transform in the same hook body.
--
-- husk                        UNSUPPORTED baseline. The re-key path exists -
--   SimpleHuskInventoryExtension._wield_slot (:3705), the single decision point
--   _husk_resolve_display_def (:10646), #478 hand preselect (:10709) - and it
--   CLOSES the burned cells for skin-carrying wields. But skinless parity under
--   weapon_tweaker's runtime can_wield expansion still needs the per-wearer
--   marker (#392 umbrella / #474 / #579), the #660 identity ledger that would
--   prove it is diagnostics-armed + coop-required, and every family carries an
--   open husk issue. Partially wired -> unsupported. Safe fallback everywhere:
--   the loadout wire substitutes the vanilla base key (#278/#495) so a husk that
--   fails to re-key shows the RESIDENT vanilla base weapon, never a crash/void.
--
-- lobby / score_team          UNSUPPORTED baseline. Transform rides the shared
--   HeroPreviewer._spawn_item seam (:12256, used by team_previewer), but the
--   mesh-swap pre-passes do NOT fire on that previewer and lobby/score weapon
--   appearance is unverified (#513 isolated only the score wearer identity).
--   The crowbill family is the sole exception - it wires both surfaces.
--
-- hold_tab                    UNSUPPORTED for ALL families. The player-list card
--   is rebuilt from rpc_sync_loadout_slot with NO backend ID; CWV deliberately
--   substitutes the vanilla base key on that wire (#278/#495), so the card shows
--   the resident vanilla base weapon. No custom UI identity ships (#638/#641).
--
-- EDGES. instance_load (boot _auto_register_all on StateInGameRunning.on_enter),
--   equip (game_object_initialized / _spawn_resynced_loadout / create_equipment),
--   peer_ready (GearUtils.hot_join_sync :11677 + cwv_item_identity channel),
--   customize (equip_item mesh-swap + skin persistence), and preview_open
--   (previewer hooks) are IMPLEMENTED baseline. mission_transition, respawn, and
--   mod_disable_restore are UNSUPPORTED baseline: the S3 bounded lifecycle
--   reconciler is W2-pending, respawn is recorded deferred in the plan's initial
--   registry (§8a), and no dedicated mod-disable appearance-restore path exists
--   (it relies on the same vanilla-base wire fallback). Identity re-publishes on
--   transition, but the transform/material/pose replay that recurs as regressions
--   (#416/#483) is feature-owned, not a proven single-generation reconciler.
-- ============================================================================

local IMPL = "implemented"
local UNSUP = "unsupported"

-- Fresh baseline tables per call so no two families share a mutable reference.
local function cells(overrides)
	local c = {
		owner_1p = IMPL, owner_3p = IMPL, bot = IMPL,
		husk = UNSUP,
		inventory_preview = IMPL, illusion_browser = IMPL, cim_preview = IMPL,
		lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
	}
	if overrides then for k, v in pairs(overrides) do c[k] = v end end
	return c
end

local function edges(overrides)
	local e = {
		instance_load = IMPL, peer_ready = IMPL, equip = IMPL,
		customize = IMPL, preview_open = IMPL,
		mission_transition = UNSUP, respawn = UNSUP, mod_disable_restore = UNSUP,
	}
	if overrides then for k, v in pairs(overrides) do e[k] = v end end
	return e
end

-- Notes shared by every baseline-unsupported surface. Per-family husk notes are
-- passed in because the tracking issue differs; extra notes on cells that a
-- family later marks implemented are harmless (the validator only checks notes
-- on cells that are actually "unsupported").
local FB_LOBBY = "Transform rides the shared HeroPreviewer._spawn_item seam (:12256) but the mesh-swap pre-pass never fires on the lobby previewer and full lobby weapon parity is unverified; degrades to the data-level get_item_units mesh over the resident vanilla base (#513)."
local FB_SCORE = "End-of-mission TeamPreviewer reconstructs from the score snapshot; CWV weapon appearance is not wired to the score lineup (#513 isolated wearer identity only); degrades to the resident vanilla base mesh."
local FB_HOLDTAB = "Player-list card is rebuilt from rpc_sync_loadout_slot with no backend ID; CWV substitutes the vanilla base key on the loadout wire for cross-peer safety (#278/#495), so the card shows the resident vanilla base weapon; no custom UI identity shipped (#638/#641)."

local function fb(husk_note, overrides)
	local t = { husk = husk_note, lobby = FB_LOBBY, score_team = FB_SCORE, hold_tab = FB_HOLDTAB }
	if overrides then for k, v in pairs(overrides) do t[k] = v end end
	return t
end

local families = {}

-- ── Combat-Style / greatsword-family illusions ──────────────────────────────
-- cwv_es_longsword, cwv_es_longsword_blackguard, cwv_es_longsword_nordland.
-- item_type cwv_imperial_longsword; retired (cwv_retired) + promo, now carried
-- as a Combat Style / illusion on native es_2h_sword (#620/#644). Owner renders
-- the longsword mesh through the style+skin on the native greatsword.
families.imperial_longsword = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#396 (Imperial Longsword invisible on husk, residency). Now a Combat Style on native es_2h_sword, so the husk resolves the native greatsword wire; the variant-mesh re-key via _husk_resolve_display_def (:10646) is coop-unverified. Degrades to the resident native es_2h_sword greatsword mesh."),
}

-- cwv_es_longsword_shield: Bretonnian one_handed_sword_shield_template_2 as
-- Kruber longsword + Empire shield (base es_sword_shield_breton).
families.imperial_longsword_shield = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#396/#415 husk residency for the shield offhand; base+career re-key (:3705/:10646) exists but the left-hand shield attach on a remote peer is coop-unverified. Degrades to the resident vanilla es_sword_shield_breton base."),
}

-- ── Sword/axe + shield families ─────────────────────────────────────────────
-- cwv_es_axe_shield + _veteran: item_type cwv_es_axe_shield (base dr_shield_axe).
families.empire_axe_shield = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#401 (husk reverts to dwarf base, wrong units force-loaded) + #415 (host shield offhand). The data-driven residency pass + re-key (:3705/:10646) exist but remain coop-unverified. Degrades to the resident vanilla dr_shield_axe base."),
}

-- cwv_we_sword_shield + _veteran: elven_sword_shield_template (base es_sword_shield).
-- Path-3 preview mesh-swap (_cwv_preview_meshswap_apply) originated here (#237).
families.elven_sword_shield = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#401-class shield residency on the husk (left-hand Athel Loren shield); base+career re-key (:10646) is coop-unverified. Degrades to the resident vanilla es_sword_shield base."),
}

-- ── Warrior-Priest hammer families (Skullsplitter mesh pipeline) ────────────
-- cwv_dr_priest_greathammer + cwv_es_priest_greathammer: two_handed_hammer_priest
-- _template, base wh_2h_hammer, dwarf/empire 2H hammer meshes.
families.priest_greathammer = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 umbrella husk: base wh_2h_hammer re-key via _husk_resolve_display_def (:10646); skinless parity under wt-expanded can_wield is coop-unverified, and the dwarf variant's 3P pose coverage is itself unverified. Degrades to the resident vanilla wh_2h_hammer base."),
}

-- cwv_es_warpriest_hammer (1H), cwv_es_dual_warpriest_hammers (dual),
-- cwv_es_warpriest_hammer_shield (hammer+shield). All Skullsplitter
-- wpn_wh_1h_hammer_01 mesh + {0,0,0.15} grip; distinct bases
-- (wh_1h_hammer / wh_dual_hammer / wh_hammer_shield).
families.warpriest_hammers = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: Skullsplitter mesh re-key via _husk_resolve_display_def (:10646); skinless parity coop-unverified and the shield variant adds the #401-class left-hand attach. Degrades to the resident vanilla wh_1h_hammer / wh_dual_hammer / wh_hammer_shield base."),
}

-- ── Single-hand moveset swaps on Empire meshes ──────────────────────────────
-- cwv_es_maul: bw_1h_mace morningstar moveset, Empire mace mesh, fire-DoT scrub.
families.maul = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392/#397 husk (mesh + transform): bw_1h_mace re-key via _husk_resolve_display_def (:10646) is coop-unverified. Degrades to the resident vanilla bw_1h_mace base."),
}

-- cwv_es_cudgel: es_1h_mace falchion-to-blunt moveset, Empire mace mesh.
families.cudgel = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: es_1h_mace re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla es_1h_mace base."),
}

-- cwv_es_shortsword: bw_dagger moveset (DoT scrubbed), Empire sword mesh.
families.shortsword = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: bw_dagger re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla bw_dagger base."),
}

-- cwv_es_rapier: wh_fencing_sword, pistol disabled, no_left_hand.
families.rapier = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: wh_fencing_sword re-key via _husk_resolve_display_def (:10646); the no_left_hand pistol strip on a remote peer is coop-unverified. Degrades to the resident vanilla wh_fencing_sword base."),
}

-- ── Dual-wield families ─────────────────────────────────────────────────────
-- cwv_es_dual_swords: we_dual_wield_swords moveset, Empire sword both hands.
families.imperial_dual_swords = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: we_dual_wield_swords re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla we_dual_wield_swords base."),
}

-- cwv_es_sword_and_mace: es_dual_wield_hammer_sword inverse layout (per-hand
-- damage swap is gameplay, not appearance).
families.sword_and_mace = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: es_dual_wield_hammer_sword re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla es_dual_wield_hammer_sword base."),
}

-- cwv_es_dual_axes + cwv_wh_dual_axes: dual_wield_axes_template_1, Saltzpyre
-- hatchet mesh both hands, per-character 3P wield route.
families.dual_axes = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: dr_dual_wield_axes re-key via _husk_resolve_display_def (:10646) coop-unverified. Degrades to the resident vanilla dr_dual_wield_axes base."),
}

-- cwv_es_dual_maces + cwv_wh_dual_maces: cwv_dual_maces_template, Empire mace
-- both hands, display_dual_hammers rig forced in _force_display_unit.
families.dual_maces = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: dr_dual_wield_hammers re-key via _husk_resolve_display_def (:10646); the display_dual_hammers rig residency on a remote peer is coop-unverified. Degrades to the resident vanilla dr_dual_wield_hammers base."),
}

-- cwv_dr_dawi_mace / _mace_shield / _dual_maces: mace gameplay identities on
-- Bardin hammer PLACEHOLDER meshes (#602), resident vanilla bases.
families.dawi_maces = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#602/#392 husk: placeholder Bardin hammer meshes re-key via _husk_resolve_display_def (:10646) coop-unverified; the shield member adds the #401-class left-hand attach. Degrades to the resident vanilla es_1h_mace / es_mace_shield / dr_dual_wield_hammers base."),
}

-- ── Ranged / thrown families ────────────────────────────────────────────────
-- cwv_es_javelin + cwv_wh_javelin: tuskgor_javelin_template, boar-spear held
-- mesh (left hand), invisible right, ammo + projectile + pickup path.
families.tuskgor_javelin = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#399 (thrown-weapon ammo strip on the husk). Boar-spear held mesh re-keys via _husk_resolve_display_def (:10646), but the ammo-unit strip + projectile identity on a remote peer are coop-unverified. Degrades to the resident vanilla we_javelin base."),
}

-- cwv_es_crossbow: wh_crossbow ported to Kruber (rifle 3P anims), preview-time
-- a_unwielded_crossbow attachment-node substitution.
families.imperial_crossbow = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#392 husk: wh_crossbow re-key via _husk_resolve_display_def (:10646); the a_unwielded_crossbow node that Kruber's body lacks is only guarded on the previewer, so the remote husk edge is coop-unverified. Degrades to the resident vanilla wh_crossbow base."),
}

-- ── Custom / imported-mesh families ─────────────────────────────────────────
-- cwv_es_outrider_grenade_launcher: resident vanilla Kruber blunderbuss visual,
-- Trollhammer behavior, no_ammo_unit, no_left_hand (#762/#279).
families.outrider_grenade_launcher = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#399 (torpedo/ammo on husk) + #279 (crafted copy merges with the Trollhammer). The #762 visual is the resident vanilla wpn_empire_blunderbuss_t1 unit; only the ammo strip remains coop-unverified. Degrades to the resident vanilla dr_deus_01 Trollhammer/blunderbuss base."),
}

-- cwv_es_musket_old: LA-pattern custom mesh (mat_to_use vanilla material),
-- cross-slot stance toggle, NetworkLookup.inventory_packages alias (:4358).
families.old_musket = {
	cells = cells({ illusion_browser = UNSUP }),
	edges = edges(),
	unsupported_fallback = fb(
		"#474 (Old Musket husk custom mesh + remote shot audio). _husk_custom_bundle_unit (:4326) makes the LA-pattern mesh resident, but husk parity is diagnostics-armed + coop-required. Degrades to the resident vanilla es_handgun rifle.",
		{
			-- cim_preview stays IMPLEMENTED: #617's resource-gated painter
			-- (:12103, verified Athanor closure) binds the custom textures.
			illusion_browser = "#227 (Old Musket illusion entry renders red/transparent in the cosmetic browser). The mesh spawns via _cwv_browser_meshswap_apply (:9221) and #617's shared per-unit painter should close the texture, but the illusion-browser pane is not yet verified. Degrades to the base es_handgun rifle mesh.",
		}),
}

-- cwv_es_greataxe: converted third-party models (_cwv_greataxe.lua, #597); until
-- a manifest model is present the cloned Bardin greataxe mesh is the fallback.
families.greataxe = {
	cells = cells(),
	edges = edges(),
	unsupported_fallback = fb(
		"#597 husk for the converted custom models: base+career re-key via _husk_resolve_display_def (:10646) plus the mod_unit_preview fallback are coop-unverified on the husk. Degrades to the resident Bardin dwarf greataxe base mesh."),
}

-- cwv_es_imperial_crowbill + cwv_dr_dawi_crowbill: converted models with a
-- hammer-mode toggle (crowbill_mode_family); CIM owns acquisition. This is the
-- ONE family that wires lobby + score presentation (#604 TeamPreviewer bridge).
families.crowbill = {
	cells = cells({ lobby = IMPL, score_team = IMPL }),
	edges = edges(),
	unsupported_fallback = fb(
		"Husk mesh + hammer-mode ride crowbill_runtime.on_husk_wield (:3740), but custom-model residency plus cross-peer mode sync on the husk are coop-unverified. Degrades to the resident Sienna Crowbill placeholder mesh."),
	-- lobby/score_team IMPLEMENTED: _apply_crowbill_presentation (:9974) is driven
	-- for the lobby_preview / score_preview surfaces (:12051-12057) with the wearer
	-- peer resolved via _crowbill_team_peer (:12141) / resolve_score_peer
	-- (_cwv_crowbill_presentation.lua:47) and identity_for_peer
	-- (_cwv_crowbill_runtime.lua:148). hold_tab remains unsupported (no backend ID).
}

return { families = families }
