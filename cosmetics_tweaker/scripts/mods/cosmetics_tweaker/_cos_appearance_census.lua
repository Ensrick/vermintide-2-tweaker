-- _cos_appearance_census.lua -- retroactive appearance census (W0 gate, 660).
--
-- PURE DATA. No engine globals, no get_mod, no mod state: this file is loaded
-- via dofile() by qa/lua/tests/test_appearance_census.lua and must return the
-- census table with no side effects. Vocabulary (surfaces, edges) mirrors
-- tools/shared_lib/_lib_appearance_descriptor.lua exactly.
--
-- WHAT THIS IS. cosmetics_tweaker's appearance overrides grouped by PIPELINE
-- (family), each declaring, for all 17 acceptance surfaces x all 8 lifecycle
-- edges, whether that exact PAIR is "implemented" or "unsupported". Every
-- unsupported pair carries a fallback note saying why the degrade is safe and
-- which issue tracks the hole.
--
-- SCHEMA v2 - SURFACE x EDGE MATRIX (re-keyed 2026-08-04, issue 1157).
-- Until 2026-08-04 a family declared surfaces and edges as two INDEPENDENT
-- vectors, so "husk = implemented" plus "mission_transition = implemented"
-- could not express "husk AT mission transition is the thing that breaks" -
-- the exact recurring failure class (233 LA replay, 738 pre-join replay).
-- Authoring is compact: one row per surface stating its default EXPLICITLY,
-- plus per-edge overrides. The descriptor library expands it to the full
-- matrix and FAILS on any pair it cannot resolve. Nothing is implicit.
--
-- CONVERSION RULE APPLIED 2026-08-04 (conservative, never optimistic):
--   1. base state = min(old surface state, old edge state);
--   2. any pair with a known open issue or documented doubt is FORCED
--      unsupported with the issue named. Applied here: husk x peer_ready,
--      husk x customize and husk x mission_transition on every family;
--   3. the six surfaces added by 1157 start unsupported unless concrete code
--      evidence shows the family implements one. One exception earned
--      evidence: item_card_2d for the two icon-owning families.
--   4. crafting_preview, added by 1198, starts unsupported for every family:
--      the ordinary crafting bench has no proven cosmetics adapter and must not
--      be inferred from the illusion browser or CIM Athanor preview paths.
--
-- TRUTHFULNESS RULE (the whole point of W0). A pair is "implemented" ONLY when
-- a citable code path applies THIS family's override on THAT surface at THAT
-- edge. A surface that merely "probably works because a sibling surface works"
-- is unsupported. A false "implemented" recreates the whack-a-mole the standard
-- exists to kill (WEAPON_APPEARANCE_STANDARD.md section 1).
--
-- Citations below (file:line) are into cosmetics_tweaker.lua unless a _*.lua
-- module is named; line numbers are against the 2026-07-17 source and are
-- approximate after later OOP phases churn them -- match by function name.
-- Cross-checked against cosmetics_tweaker/ENGINE_SURFACE.md and LA_SYNC_MODEL.md
-- section 6.
--
-- FAMILIES (8):
--   la_hat_skin_clones      LA armoury hat + armor/body-skin clones (kind=texture
--                           & kind=unit); MoreItemsLibrary unlock surfacing +
--                           cos_la_apply per-peer husk replication + 513 score
--                           apply + 698 career-scoped records.
--   offhand_shield_swaps    Independent offhand/shield illusion+mesh picker
--                           (vanilla-mesh + LA shields) across 4 render paths;
--                           416 vanilla-offhand husk store; 483 CWV dual mounts.
--   custom_weapon_illusions ct_* custom weapon-skin illusions injected into
--                           ItemMasterList / WeaponSkins / skin_combinations.
--   weapon_model_scale_grip Bretonnian-sword scale ("thiccc") + grip-offset
--                           apply layer (_cos_render.lua); unit-path/data-driven.
--   glow_overrides          Rune/magic glow template mutation/read/paint
--                           (_cos_glow.lua) + per-peer cos_glow_apply
--                           transport/replay (_cos_glow_transport.lua).
--   authored_custom_cosmetics  Encarmine Helmet (612) + Grail Knight
--                           Purpure/Azure set (629): authored items over vanilla
--                           donor units, per-instance texture bindings.
--   weapon_poses            485 social-wheel authored weapon-pose catalog
--                           (PingTypes.LOCAL_ONLY; owner 3P only).
--   cosmetic_projectile_fx  Moonfire-arrow impact puff (we_deus_01); owner-local
--                           world FX on projectile hit.
--
-- Note on the recurring "unsupported" surfaces:
--   * lobby       -- cosmetics has NO lobby-card/portrait previewer hook except
--                    the authored-set path. Remote players co-located in the
--                    shared keep render through the husk surface; the
--                    matchmaking lobby portrait keeps vanilla.
--   * cim_preview -- the Athanor is crafting_in_modded's forge previewer. The
--                    exact #481 adapter implements only backend-owned offhand
--                    material/unit selection at the census' preview_open edge;
--                    the fuller appearance contract separately covers reopen;
--                    every
--                    other family/edge remains unsupported unless stated.
--   * mod_disable_restore (edge) -- NO family runs an explicit restore reconciler
--                    on mod disable (the S3 reconciler is W2-pending). Per-unit
--                    overrides drop incidentally on the next respawn/full restart;
--                    injected ItemMasterList/NetworkLookup keys stay resident until
--                    restart. Unsupported on every surface -- honest for W0.
--   * portraits   -- split out to dynamic_cosmetic_portraits (925 class);
--                    cosmetics supplies that mod no appearance identity.

local IMPL = "implemented"
local UNSUP = "unsupported"

-- row(default, note, edge_overrides, edge_notes) - `default` is mandatory and
-- explicit; `note` covers every unsupported pair in the row without its own note.
local function row(default, note, edge_overrides, edge_notes)
	return { default = default, note = note, edges = edge_overrides, notes = edge_notes }
end

-- Shallow merge into a NEW table so the shared constants stay immutable.
local function plus(base, extra)
	local t = {}
	if base then for k, v in pairs(base) do t[k] = v end end
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

-- ---------------------------------------------------------------------------
-- Shared edge holes (step 1 of the conversion: the pre-1157 edge vector)
-- ---------------------------------------------------------------------------
local FB_DISABLE = "No family runs an explicit restore reconciler on mod disable (S3 is W2-pending); per-unit overrides drop incidentally on the next respawn or full restart, and injected ItemMasterList/NetworkLookup keys stay resident until restart. Degrades to the resident vanilla presentation on the next re-equip."
local DISABLE_ONLY = { mod_disable_restore = UNSUP }
local DISABLE_ONLY_NOTES = { mod_disable_restore = FB_DISABLE }

-- ---------------------------------------------------------------------------
-- Forced-honest husk pairs (step 2 of the conversion), applied to every family
-- ---------------------------------------------------------------------------
local HUSK_FORCED = { peer_ready = UNSUP, customize = UNSUP, mission_transition = UNSUP }
local HUSK_FORCED_NOTES = {
	peer_ready = "Hot-join: the observer joins after the wearer already equipped, so the cosmetic must arrive by replay rather than by a live change. 233 recorded exactly this (persisted pre-equipped state absent until a live change) and 738 audited the pre-join replay case. Degrades to the resident vanilla default-loadout cosmetic.",
	customize = "A live customization change on the wearer is not proven to replay onto an already-spawned husk; the 1145 per-wearer re-wield coalescer bounds the resulting re-wield storm but the husk cells themselves are unverified. Degrades to the previously resolved cosmetic, then to vanilla.",
	mission_transition = "Husk cosmetic identity across a mission transition is the 233 replay class: the observing peer rebuilds from the loadout snapshot, which carries no mod-owned cosmetic identity. Degrades to the resident vanilla default-loadout cosmetic.",
}

local function husk_row(open_edges, open_notes, note)
	return row(IMPL, note,
		plus(open_edges, HUSK_FORCED), plus(open_notes, HUSK_FORCED_NOTES))
end

-- ---------------------------------------------------------------------------
-- Surfaces added by 1157 - unsupported unless a family overrides with evidence
-- ---------------------------------------------------------------------------
local FB_SPECIALS = "Cosmetics owns no weapon-special transform channel; a weapon special renders the base template's own special presentation over whatever mesh/material this family applied. Safe (vanilla). Tracked 660."
local FB_REMOTE_AUDIO = "This family ships no audio identity, so nothing is expected on the remote audio channel; remote peers hear the resident vanilla cues. Correct by construction. Tracked 398 class / 660."
local FB_HUD = "Cosmetics projects no career HUD or ability-panel presentation; the native HUD renders unchanged. Safe (vanilla). Tracked 807 class."
local FB_PORTRAITS = "Portrait rendering was split out to dynamic_cosmetic_portraits, which resolves its own hat/skin identity; cosmetics_tweaker supplies it no appearance descriptor, so a cosmetic this family applies is not guaranteed to be reflected in the portrait. Degrades to the vanilla or dcp-resolved portrait. Tracked 925 class."
local FB_ITEM_CARD = "This family registers no cosmetics-owned icon; the 2D item card renders the donor/base item's authentic vanilla icon. Correct by construction. Tracked 660 / 638 / 641."
local FB_TOOLTIP = "Cosmetics supplies no tooltip-side appearance identity; the tooltip renders the base item's vanilla text and icon. Safe (vanilla). Tracked 660."
local FB_CRAFTING = "The ordinary crafting-bench preview is distinct from the cosmetics customization browser and CIM Athanor; no family has a proven bench adapter, so the resident base-item presentation is retained. Safe (vanilla). Tracked 1198 / 660."

local function new_surface_rows()
	return {
		crafting_preview  = row(UNSUP, FB_CRAFTING),
		specials          = row(UNSUP, FB_SPECIALS),
		remote_audio      = row(UNSUP, FB_REMOTE_AUDIO),
		hud_panels        = row(UNSUP, FB_HUD),
		portraits         = row(UNSUP, FB_PORTRAITS),
		item_card_2d      = row(UNSUP, FB_ITEM_CARD),
		inventory_tooltip = row(UNSUP, FB_TOOLTIP),
	}
end

-- item_card_2d IMPLEMENTED only where a cosmetics-owned icon adapter is wired:
-- _cos_composite_icons.lua (composite hat/armor cards, cosmetics_tweaker.lua:63/65)
-- and the LA icon provider (_cos_la_inventory_icon.lua, :79).
local function icon_row(open_edges, open_notes)
	return row(IMPL, nil, open_edges, open_notes)
end

-- build(states, notes, open_edges, open_notes, per_surface)
--   states     : surface -> default state; MUST name every surface it does not
--                leave to new_surface_rows()
--   notes      : surface -> row note (required for every unsupported default)
--   open_edges : the family's lifecycle holes, applied to every implemented row
--   per_surface: whole-row replacements
local function build(states, notes, open_edges, open_notes, per_surface)
	local m = new_surface_rows()
	for surface, state in pairs(states) do
		if state == IMPL then
			m[surface] = row(IMPL, notes[surface], open_edges, open_notes)
		else
			m[surface] = row(UNSUP, notes[surface])
		end
	end
	if per_surface then for k, v in pairs(per_surface) do m[k] = v end end
	return m
end

return {
	schema_version = 2,
	families = {

		-- ================================================================
		-- LA armoury hat + armor/body-skin clones
		-- owner_3p: AttachmentUtils.create_attachment (_cos_spawn_boundary.lua) + LA paint;
		--   SimpleInventoryExtension.extensions_ready re-applies saved choice
		--   (_la_persistence.lua:256).
		-- husk: cos_la_apply broadcast + PlayerHuskAttachmentExtension.create_attachment
		--   pre-patch (section 6.7) + SimpleHuskInventoryExtension._wield_slot re-key
		--   (:8709) + 698 career-scoped records (_cos_husk_identity.lua). FORCED
		--   unsupported at peer_ready/customize/mission_transition (233/738/1145).
		-- score_team: TeamPreviewer._spawn_hero (:5454) + cb_hero_unit_spawned_skin_preview
		--   (:5501), human-only via _cos_score_identity.lua. This is one of the two
		--   score/lobby one-offs 1157 kept implemented (730 authored-set replay).
		-- item_card_2d: composite hat/armor icon cards (_cos_composite_icons.lua).
		-- ================================================================
		la_hat_skin_clones = {
			matrix = build(
				{
					owner_1p = UNSUP, owner_3p = IMPL, bot = UNSUP,
					inventory_preview = IMPL, illusion_browser = UNSUP, cim_preview = UNSUP,
					lobby = UNSUP, score_team = IMPL, hold_tab = UNSUP,
				},
				{
					owner_1p         = "Hats have no first-person view; LA armor/body paint targets the 3P mesh only, 1P arms keep the net-safe vanilla base skin. Safe (vanilla). Tracked as the 1P-outfit gap, 629-class.",
					bot              = "LA picks are per-peer human; bots share the owner peer with is_player_controlled=false and 698/513 fails closed (_cos_husk_identity.lua:53). Bots render the default-loadout vanilla cosmetic. Safe by design.",
					illusion_browser = "The illusion browser (LootItemUnitPreviewer) previews weapon skins; hats/armor have no illusion-browser surface. Not applicable by surface.",
					cim_preview      = "The Athanor (crafting_in_modded) forges weapons; hats/armor have no forge-preview surface, and cosmetics installs no Athanor hook. Not applicable by surface.",
					lobby            = "No lobby-card/portrait previewer hook. Co-located keep rendering rides the husk surface; the matchmaking lobby portrait keeps vanilla. Tracked as the lobby-preview gap, 629-class.",
					hold_tab         = "Hold-Tab player cards show weapon-slot icons/names, not hat/armor cosmetics. Not applicable by surface.",
				},
				DISABLE_ONLY, DISABLE_ONLY_NOTES,
				{
					husk = husk_row(DISABLE_ONLY, DISABLE_ONLY_NOTES),
					item_card_2d = icon_row(DISABLE_ONLY, DISABLE_ONLY_NOTES),
				}),
		},

		-- ================================================================
		-- Independent offhand/shield illusion + mesh picker
		-- owner 1p/3p: GearUtils.create_equipment (:5110) result.left_unit_1p/3p +
		--   BackendUtils.get_item_units override (:4453) + _la_bridge paint.
		-- husk: 416 _offhand_mesh_by_peer store (:4373) read in the get_item_units
		--   husk branch (:4641) + cos_la_apply offhand_unit field (section 6.9).
		-- inventory_preview: HeroPreviewer/MenuWorldPreviewer._spawn_item (:5694/:5695).
		-- illusion_browser: LootItemUnitPreviewer.spawn_units (:5824) row-2 picker.
		-- cim_preview: CIM's three constructor scopes + returned-instance marker
		--   feed exact identity into equipment resolution, then a generation-safe
		--   bounded material reconcile at preview_open (#481); the separate
		--   appearance contract carries preview_reopen, absent from census v2.
		-- score_team: NOT applied -- TeamPreviewer apply covers slot_hat/slot_skin only.
		-- instance_load: the picker's selection is applied on equip/customize, not
		--   at module load, so instance_load was already a hole in the edge vector.
		-- ================================================================
		offhand_shield_swaps = {
			matrix = (function()
				local open = { instance_load = UNSUP, mod_disable_restore = UNSUP }
				local open_notes = {
					instance_load = "The offhand selection is applied on equip/customize through the render hooks, not at module load; a unit spawned before the first selection resolves renders the base offhand. Degrades to the resident vanilla offhand.",
					mod_disable_restore = FB_DISABLE,
				}
				return build(
					{
						owner_1p = IMPL, owner_3p = IMPL, bot = UNSUP,
						inventory_preview = IMPL, illusion_browser = IMPL, cim_preview = UNSUP,
						lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
					},
					{
						bot         = "Offhand picks are keyed to the human wearer's per-backend_id _offhand_selection; bots wield the default loadout with no selection and render the base offhand. Safe (vanilla).",
						cim_preview = "Only preview_open is implemented in census v2 by #481's exact CIM context (the appearance contract separately covers preview_reopen). Synthetic/backendless, foreign, stale, nonresident, or timed-out identities retain the resident base offhand; other lifecycle edges remain unsupported pending in-game proof.",
						lobby       = "No lobby-card previewer hook; co-located keep rendering rides the husk surface. Matchmaking lobby portrait keeps vanilla. Tracked as the lobby-preview gap.",
						score_team  = "TeamPreviewer score apply covers slot_hat/slot_skin only (:5454,:5501); offhand/weapon meshes render the net-safe base on the score lineup. Tracked as the weapon-on-score gap, 513-class.",
						hold_tab    = "Hold-Tab reconstructs the item from the loadout snapshot with no backend_id, so the exact-instance offhand selection cannot resolve (WEAPON_APPEARANCE_STANDARD section 2 snapshot rule); the card falls back to the reconstructed vanilla item. Tracked 233-class remote-card gap.",
					},
					open, open_notes,
					{
						husk = husk_row(open, open_notes,
							"373 (Loremaster skins on Weavebound shields) has a failing host/client verification, so the offhand husk channel is disproven for at least the LA-shield case; the 416 _offhand_mesh_by_peer store carries the vanilla-mesh case. Degrades to the resident vanilla offhand."),
						cim_preview = row(UNSUP,
							"#481 is deliberately limited to exact Athanor preview construction. Non-preview edges and unproven identity/readiness retain the resident base offhand.",
							{ preview_open = IMPL }),
					})
			end)(),
		},

		-- ================================================================
		-- ct_* custom weapon-skin illusions
		-- owner 1p/3p: skin resolves right/left 1p+3p via get_item_units +
		--   create_equipment; injected into WeaponSkins.skins (_cos_illusions.lua).
		-- inventory_preview/illusion_browser: get_unlocked_weapon_skins marks ct_*
		--   unlocked (_cos_illusions.lua); previewers spawn from the skin data.
		-- husk: every vanilla sender still nulls ct_* to "n/a" for 421 safety;
		--   _cos_send_custom_skin_hands publishes exact authored hand units over
		--   the 416 semantic channel for Cosmetics peers. Non-mod peers keep base.
		-- ================================================================
		custom_weapon_illusions = {
			matrix = build(
				{
					owner_1p = IMPL, owner_3p = IMPL, bot = UNSUP,
					inventory_preview = IMPL, illusion_browser = IMPL, cim_preview = UNSUP,
					lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
				},
				{
					bot         = "Bots wield the default loadout and never carry a ct_* illusion selection; render vanilla. Safe by design.",
					cim_preview = "ct_* illusions surface in the Athanor via the shared get_unlocked_weapon_skins unlock, but cosmetics installs no Athanor previewer hook and there is no in-game confirmation the forge renders the ct_* mesh/paint. Unverified; tracked as the cim-preview illusion gap.",
					lobby       = "No lobby-card previewer hook, and the wire-null means remote lobby husks show the base weapon anyway. Tracked as the lobby-preview gap / 233.",
					score_team  = "Score apply is hat/armor only; ct_* illusions are wire-nulled and not applied on the score lineup. Tracked 513-class weapon-on-score gap / 233.",
					hold_tab    = "ct_* skin is wire-nulled and Hold-Tab has no backend_id; remote cards render the reconstructed vanilla item. Tracked 233-class.",
				},
				DISABLE_ONLY, DISABLE_ONLY_NOTES,
				{
					husk = husk_row(DISABLE_ONLY, DISABLE_ONLY_NOTES,
						"421 mixed-lobby safety strips ct_* from every vanilla sender, so the authored hand units reach only peers that also run Cosmetics over the 416 semantic channel; a non-Cosmetics observer is expected to render the base weapon. Degrades to the resident vanilla base weapon."),
				}),
		},

		-- ================================================================
		-- Bretonnian-sword scale ("thiccc") + grip-offset apply layer
		-- owner 1p/3p + bot: unit-path-driven scale in GearUtils.create_equipment
		--   via _cos_render.lua, whose #420 adapter delegates one-shot transform
		--   composition to the shared WeaponAppearance instance. The surrounding
		--   equipment owner fires for owner AND bot-owned units.
		-- husk: NOT applied -- husks spawn via SimpleHuskInventoryExtension /
		--   spawn_inventory_unit, which the scale layer never touches; remote
		--   husks render native scale.
		-- inventory_preview/illusion_browser: _spawn_item_post + spawn_units call
		--   mod._cos.scale_units.
		-- peer_ready: no scale replication channel exists at all.
		-- ================================================================
		weapon_model_scale_grip = {
			matrix = (function()
				local open = { peer_ready = UNSUP, mod_disable_restore = UNSUP }
				local open_notes = {
					peer_ready = "The scale/grip layer has no replication channel; a peer becoming ready receives no scale state and each viewer re-derives from the unit path it can see locally. Degrades to native scale.",
					mod_disable_restore = FB_DISABLE,
				}
				return build(
					{
						owner_1p = IMPL, owner_3p = IMPL, bot = IMPL, husk = UNSUP,
						inventory_preview = IMPL, illusion_browser = IMPL, cim_preview = UNSUP,
						lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
					},
					{
						husk        = "The scale/grip apply runs in GearUtils.create_equipment (owner/bot) and the two previewers; the husk wield path (SimpleHuskInventoryExtension._wield_slot / get_item_units husk branch) never re-applies scale, so remote husks render native scale. Tracked as the husk-transform gap (WEAPON_APPEARANCE_STANDARD section 3 Transform/Husk).",
						cim_preview = "#481 classifies the exact Athanor surface but deliberately bypasses the generic customization 2.0 scale path; it renders native neutral scale pending visual proof. Tracked as the cim-preview transform gap.",
						lobby       = "No lobby-card previewer hook; the lobby portrait is 2D. Tracked as the lobby-preview gap.",
						score_team  = "Score lineup weapons are not scaled (score apply is hat/armor only). Tracked 513-class weapon-on-score gap.",
						hold_tab    = "Scale is a 3D mesh property; Hold-Tab shows 2D slot icons with no mesh. Not applicable by surface.",
					},
					open, open_notes)
			end)(),
		},

		-- ================================================================
		-- Rune/magic glow overrides
		-- owner 1p/3p: apply_material_settings x3 template mutation is the only
		--   writer that paints 1p (_cos_glow.lua; GLOW_SYSTEM section 12); re-paint
		--   at wield/visibility (SimpleInventoryExtension._wield_slot :10253 / :9875).
		-- husk: per-peer cos_glow_apply transport/replay
		--   (_cos_glow_transport.lua) + _glow_by_peer cache paint
		--   (_cos_glow.lua).
		-- illusion_browser/cim_preview: glow re-key runs on the in-game +
		--   inventory-mannequin paths only; browser/forge show baked glow (650).
		-- customize (edge): toggling a preset does NOT live-repaint a spawned
		--   weapon (GLOW_SYSTEM section Activation) -- needs a fresh wield.
		-- lobby/score_team stay unsupported: 1147 tracks the glow one-off there
		--   and no shipped adapter drives either surface today.
		-- ================================================================
		glow_overrides = {
			matrix = (function()
				local open = { customize = UNSUP, mod_disable_restore = UNSUP }
				local open_notes = {
					customize = "Toggling a glow preset does not live-repaint an already-spawned weapon (GLOW_SYSTEM section Activation); the new preset takes effect on the next wield. Degrades to the previously painted glow.",
					mod_disable_restore = FB_DISABLE,
				}
				return build(
					{
						owner_1p = IMPL, owner_3p = IMPL, bot = UNSUP,
						inventory_preview = IMPL, illusion_browser = UNSUP, cim_preview = UNSUP,
						lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
					},
					{
						bot              = "Glow presets are keyed per exact backend item the owner configured; bots wield default-loadout items with no preset and render vanilla glow. Safe by design.",
						illusion_browser = "Glow re-key runs on create_equipment / _wield_slot / _spawn_item_unit (in-game + inventory mannequin); the LootItemUnitPreviewer illusion-browser path does not re-apply the per-item glow preset -- the browser shows the mesh's baked glow only. Tracked 650 (glow composition) and 796 (exact glow preview ownership).",
						cim_preview      = "The Athanor forge previewer is not hooked for glow; renders baked glow only. Tracked 650.",
						lobby            = "No lobby-card previewer hook; the lobby portrait is 2D. Tracked 1147 (glow one-off on the lobby/score surfaces) and the lobby-preview gap.",
						score_team       = "Score apply is hat/armor only; weapon glow presets are not applied on the score lineup. Tracked 1147 and 513-class / 650.",
						hold_tab         = "Glow is a 3D material property; Hold-Tab shows 2D slot icons. Not applicable by surface.",
					},
					open, open_notes,
					{
						husk = husk_row(open, open_notes,
							"The per-peer cos_glow_apply transport (_cos_glow_transport.lua) paints from the _glow_by_peer cache through _cos_glow.lua; a peer without Cosmetics, or a paint that lands before the mesh is resident, renders the mesh's baked glow. Degrades to the resident vanilla baked glow."),
					})
			end)(),
		},

		-- ================================================================
		-- Authored cosmetics: Encarmine Helmet (612), Grail Knight set (629),
		-- and provider-backed Foot Knight body variants (656).
		-- owner_1p/3p: M.apply_armor_to_owner (_cos_grail_knight_set.lua) +
		--   AttachmentUtils.create_attachment + Laurel controller install on
		--   PlayerUnitAttachmentExtension.create_attachment (612).
		-- inventory_preview: M.apply_armor_to_hero_preview (:290) +
		--   HeroPreviewer.post_update 629 replay + _spawn_item_unit controller install.
		-- score_team/lobby: the 730 shared post-visibility mesh+variant adapter
		--   retains the provider-owned authored armor key through
		--   cb_hero_unit_spawned_skin_preview and HeroPreviewer.post_update. These
		--   are the two score/lobby one-offs 1157 kept implemented; both are still
		--   FORCED unsupported at peer_ready (a peer arriving before the broadcast).
		-- husk: the mod-owned armor descriptor travels through cos_la_apply;
		--   _apply_la_on_unit(kind=armor) resolves the same provider and calls
		--   M.apply_armor_to_owner on the exact career-scoped wearer (698).
		-- item_card_2d: composite/LA icon cards resolve the authored set.
		-- ================================================================
		authored_custom_cosmetics = {
			matrix = (function()
				local open, open_notes = DISABLE_ONLY, DISABLE_ONLY_NOTES
				local preview_peer = plus(open, { peer_ready = UNSUP })
				local preview_peer_notes = plus(open_notes, {
					peer_ready = "A peer that becomes ready before the cos_la_apply broadcast lands has no authored-armor key to retain, so the 730 post-visibility adapter replays the vanilla donor state for that wearer. Degrades to the resident vanilla career armor.",
				})
				return build(
					{
						owner_1p = IMPL, owner_3p = IMPL, bot = UNSUP,
						inventory_preview = IMPL, illusion_browser = UNSUP, cim_preview = UNSUP,
						hold_tab = UNSUP,
					},
					{
						bot              = "Authored cosmetics are player-equipped; bots use the default loadout and render vanilla. Safe by design.",
						illusion_browser = "Hat/outfit have no illusion-browser surface; the authored GK shield skin previews via the offhand picker but authored kind=unit paint in LootItemUnitPreviewer is constrained by the null-material AV (LA_SYNC section 6.4). Partial/unverified. Tracked 481/629.",
						cim_preview      = "Authored cosmetics are not applied in the Athanor forge previewer. Tracked 629 / cim-preview gap.",
						hold_tab         = "Hats/outfit are not weapon-slot cards; the authored GK shield card resolves only for the owner's exact instance -- remote Hold-Tab has no backend_id and falls back to vanilla. Tracked 629 / 233-class.",
					},
					open, open_notes,
					{
						husk         = husk_row(open, open_notes),
						lobby        = row(IMPL, nil, preview_peer, preview_peer_notes),
						score_team   = row(IMPL, nil, preview_peer, preview_peer_notes),
						item_card_2d = icon_row(open, open_notes),
					})
			end)(),
		},

		-- ================================================================
		-- 485 social-wheel authored weapon-pose catalog
		-- owner_3p: SocialWheelUI._gather_weapon_poses_by_parent_item substitution
		--   executes the pose locally on the wielder's 3P body (_cos_weapon_poses.lua;
		--   PingTypes.LOCAL_ONLY, social_wheel_ui.lua:1016-1034).
		-- Local-only inspect feature: no cross-peer surface participates, and the
		-- pose does not survive a transition, a respawn, or a preview open.
		-- ================================================================
		weapon_poses = {
			matrix = (function()
				local open = {
					peer_ready = UNSUP, preview_open = UNSUP,
					mission_transition = UNSUP, respawn = UNSUP, mod_disable_restore = UNSUP,
				}
				local open_notes = {
					peer_ready = "Poses execute PingTypes.LOCAL_ONLY and are never networked, so a peer becoming ready receives no pose state. By design (vanilla poses are also local); not a bug.",
					preview_open = "Poses are an in-world social-wheel action; opening a previewer does not carry the pose. Not applicable by surface.",
					mission_transition = "A pose is a transient local animation on the wielder's 3P body; it does not survive a mission transition and is not replayed. By design.",
					respawn = "A respawned body starts from the native wield pose; the social-wheel pose is not replayed. By design.",
					mod_disable_restore = FB_DISABLE,
				}
				return build(
					{
						owner_1p = UNSUP, owner_3p = IMPL, bot = UNSUP, husk = UNSUP,
						inventory_preview = UNSUP, illusion_browser = UNSUP, cim_preview = UNSUP,
						lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
					},
					{
						owner_1p          = "Weapon poses are 3P-body inspect animations; the wearer's 1P view has no pose surface. Not applicable by surface.",
						bot               = "Bots have no social-wheel UI and never trigger a pose. Not applicable.",
						husk              = "Weapon poses execute PingTypes.LOCAL_ONLY (social_wheel_ui.lua:1016-1034); the pose is never networked, so remote husks never see it. By design (vanilla poses are also local); not a bug.",
						inventory_preview = "Poses are an in-world social-wheel action, not an inventory-preview surface. Not applicable.",
						illusion_browser  = "Poses have no illusion-browser surface. Not applicable.",
						cim_preview       = "Poses have no forge-preview surface. Not applicable.",
						lobby             = "Poses have no lobby surface. Not applicable.",
						score_team        = "Poses have no score/team surface. Not applicable.",
						hold_tab          = "Poses have no Hold-Tab surface. Not applicable.",
					},
					open, open_notes)
			end)(),
		},

		-- ================================================================
		-- Moonfire-arrow impact puff (we_deus_01)
		-- owner 1p/3p + bot + husk: PlayerProjectileUnitExtension AND
		--   PlayerProjectileHuskExtension .hit_enemy/.hit_level_unit/.hit_non_level_unit
		--   are hooked (_cos_moonfire_puff_runtime.lua), so any locally-simulated player projectile --
		--   owner, bot, or remote-husk -- spawns the decorative world-space puff
		--   at impact behind cos_moonfire_cosmetic_puff. FX package rides the
		--   equipped Moonfire Bow.
		-- All non-world surfaces (previews, lobby, score, hold_tab) are not
		--   applicable: this is a transient world impact FX, not a rendered unit.
		-- ================================================================
		cosmetic_projectile_fx = {
			matrix = (function()
				local open = { preview_open = UNSUP, mod_disable_restore = UNSUP }
				local open_notes = {
					preview_open = "A previewer spawns no projectiles, so there is no impact to decorate. Not applicable by surface.",
					mod_disable_restore = FB_DISABLE,
				}
				return build(
					{
						owner_1p = IMPL, owner_3p = IMPL, bot = IMPL,
						inventory_preview = UNSUP, illusion_browser = UNSUP, cim_preview = UNSUP,
						lobby = UNSUP, score_team = UNSUP, hold_tab = UNSUP,
					},
					{
						inventory_preview = "Projectile impact FX has no inventory-preview surface. Not applicable.",
						illusion_browser  = "Projectile FX has no illusion-browser surface. Not applicable.",
						cim_preview       = "Projectile FX has no forge-preview surface. Not applicable.",
						lobby             = "Projectile FX has no lobby surface. Not applicable.",
						score_team        = "Projectile FX has no score/team surface. Not applicable.",
						hold_tab          = "Projectile FX has no Hold-Tab surface. Not applicable.",
					},
					open, open_notes,
					{
						-- The husk branch is locally simulated, so no replication is
						-- needed - but the FX package rides the equipped Moonfire Bow,
						-- and that package's residency on a hot-joining observer is
						-- exactly the class 1157 forces honest.
						husk = husk_row(open, open_notes,
							"The puff is spawned by the locally-simulated husk projectile extension (_cos_moonfire_puff_runtime.lua), so no replication is required, but the FX package rides the wearer's equipped Moonfire Bow and its residency on the observing peer is unproven at the moment of the first remote shot. Degrades to the vanilla impact FX."),
					})
			end)(),
		},

	},
}
