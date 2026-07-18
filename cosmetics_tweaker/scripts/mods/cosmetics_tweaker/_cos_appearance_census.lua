-- _cos_appearance_census.lua -- retroactive appearance census (W0 gate, #660).
--
-- PURE DATA. No engine globals, no get_mod, no mod state: this file is loaded
-- via dofile() by qa/lua/tests/test_appearance_census.lua and by
-- qa/check_appearance_census.ps1, and must return the census table with no
-- side effects. Vocabulary (cells, edges) mirrors
-- tools/shared_lib/_lib_appearance_descriptor.lua exactly.
--
-- WHAT THIS IS. cosmetics_tweaker's appearance overrides grouped by PIPELINE
-- (family), each declaring for all 10 acceptance cells and all 8 lifecycle
-- edges whether the family is "implemented" or "unsupported". Every unsupported
-- CELL carries a one-line unsupported_fallback note saying why the degrade is
-- safe and which issue tracks the hole.
--
-- TRUTHFULNESS RULE (the whole point of W0). A cell is "implemented" ONLY when
-- a citable code path applies THIS family's override on THAT surface. A surface
-- that merely "probably works because a sibling surface works" is unsupported.
-- A false "implemented" recreates the whack-a-mole the standard exists to kill
-- (WEAPON_APPEARANCE_STANDARD.md §1). The census inventories TODAY's holes.
--
-- Citations below (file:line) are into cosmetics_tweaker.lua unless a _*.lua
-- module is named; line numbers are against the 2026-07-17 source and are
-- approximate after later OOP phases churn them -- match by function name.
-- Cross-checked against cosmetics_tweaker/ENGINE_SURFACE.md and LA_SYNC_MODEL.md §6.
--
-- FAMILIES (8):
--   la_hat_skin_clones      LA armoury hat + armor/body-skin clones (kind=texture
--                           & kind=unit); MoreItemsLibrary unlock surfacing +
--                           cos_la_apply per-peer husk replication + #513 score
--                           apply + #698 career-scoped records.
--   offhand_shield_swaps    Independent offhand/shield illusion+mesh picker
--                           (vanilla-mesh + LA shields) across 4 render paths;
--                           #416 vanilla-offhand husk store; #483 CWV dual mounts.
--   custom_weapon_illusions ct_* custom weapon-skin illusions injected into
--                           ItemMasterList / WeaponSkins / skin_combinations.
--   weapon_model_scale_grip Bretonnian-sword scale ("thiccc") + grip-offset
--                           apply layer (_cos_render.lua); unit-path/data-driven.
--   glow_overrides          Rune/magic glow template-mutation + per-peer
--                           cos_glow_apply broadcast (_cos_glow.lua).
--   authored_custom_cosmetics  Encarmine Helmet (#612) + Grail Knight
--                           Purpure/Azure set (#629): authored items over vanilla
--                           donor units, per-instance texture bindings.
--   weapon_poses            #485 social-wheel authored weapon-pose catalog
--                           (PingTypes.LOCAL_ONLY; owner 3P only).
--   cosmetic_projectile_fx  Moonfire-arrow impact puff (we_deus_01); owner-local
--                           world FX on projectile hit.
--
-- Note on the recurring "unsupported" surfaces:
--   * lobby       -- cosmetics has NO lobby-card/portrait previewer hook. Remote
--                    players co-located in the shared keep render through the
--                    husk cell; the matchmaking lobby portrait keeps vanilla.
--   * cim_preview -- the Athanor is crafting_in_modded's forge previewer;
--                    cosmetics installs no hook there.
--   * mod_disable_restore (edge) -- NO family runs an explicit restore reconciler
--                    on mod disable (the S3 reconciler is W2-pending). Per-unit
--                    overrides drop incidentally on the next respawn/full restart;
--                    injected ItemMasterList/NetworkLookup keys stay resident until
--                    restart. Declared unsupported everywhere -- honest for W0.

return {
	families = {

		-- ================================================================
		-- LA armoury hat + armor/body-skin clones
		-- owner_3p: AttachmentUtils.create_attachment (:9427) + LA paint;
		--   SimpleInventoryExtension.extensions_ready re-applies saved choice
		--   (_la_persistence.lua:256).
		-- husk: cos_la_apply broadcast + PlayerHuskAttachmentExtension.create_attachment
		--   pre-patch (§6.7) + SimpleHuskInventoryExtension._wield_slot re-key (:8709)
		--   + #698 career-scoped records (_cos_husk_identity.lua).
		-- score_team: TeamPreviewer._spawn_hero (:5454) + cb_hero_unit_spawned_skin_preview
		--   (:5501), human-only via _cos_score_identity.lua.
		-- ================================================================
		la_hat_skin_clones = {
			cells = {
				owner_1p          = "unsupported",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "implemented",
				inventory_preview = "implemented",
				illusion_browser  = "unsupported",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "implemented",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "implemented",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				owner_1p         = "Hats have no first-person view; LA armor/body paint targets the 3P mesh only, 1P arms keep the net-safe vanilla base skin. Safe (vanilla). Tracked as the 1P-outfit gap, #629-class.",
				bot              = "LA picks are per-peer human; bots share the owner peer with is_player_controlled=false and #698/#513 fails closed (_cos_husk_identity.lua:53). Bots render the default-loadout vanilla cosmetic. Safe by design.",
				illusion_browser = "The illusion browser (LootItemUnitPreviewer) previews weapon skins; hats/armor have no illusion-browser surface. n/a by surface.",
				cim_preview      = "The Athanor (crafting_in_modded) forges weapons; hats/armor have no forge-preview surface, and cosmetics installs no Athanor hook. n/a by surface.",
				lobby            = "No lobby-card/portrait previewer hook. Co-located keep rendering rides the husk cell; the matchmaking lobby portrait keeps vanilla. Tracked as the lobby-preview gap, #629-class.",
				hold_tab         = "Hold-Tab player cards show weapon-slot icons/names, not hat/armor cosmetics. n/a by surface.",
			},
		},

		-- ================================================================
		-- Independent offhand/shield illusion + mesh picker
		-- owner 1p/3p: GearUtils.create_equipment (:5110) result.left_unit_1p/3p +
		--   BackendUtils.get_item_units override (:4453) + _la_bridge paint.
		-- husk: #416 _offhand_mesh_by_peer store (:4373) read in the get_item_units
		--   husk branch (:4641) + cos_la_apply offhand_unit field (§6.9).
		-- inventory_preview: HeroPreviewer/MenuWorldPreviewer._spawn_item (:5694/:5695).
		-- illusion_browser: LootItemUnitPreviewer.spawn_units (:5824) row-2 picker.
		-- score_team: NOT applied -- TeamPreviewer apply covers slot_hat/slot_skin only.
		-- ================================================================
		offhand_shield_swaps = {
			cells = {
				owner_1p          = "implemented",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "implemented",
				inventory_preview = "implemented",
				illusion_browser  = "implemented",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "unsupported",
				peer_ready          = "implemented",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				bot         = "Offhand picks are keyed to the human wearer's per-backend_id _offhand_selection; bots wield the default loadout with no selection and render the base offhand. Safe (vanilla).",
				cim_preview = "The offhand row-2 picker lives in cosmetics' customization window (HeroWindowItemCustomization / LootItemUnitPreviewer), not the Athanor; cim's forge preview renders the base offhand. Tracked as the cim-preview offhand gap.",
				lobby       = "No lobby-card previewer hook; co-located keep rendering rides the husk cell. Matchmaking lobby portrait keeps vanilla. Tracked as the lobby-preview gap.",
				score_team  = "TeamPreviewer score apply covers slot_hat/slot_skin only (:5454,:5501); offhand/weapon meshes render the net-safe base on the score lineup. Tracked as the weapon-on-score gap, #513-class.",
				hold_tab    = "Hold-Tab reconstructs the item from the loadout snapshot with no backend_id, so the exact-instance offhand selection cannot resolve (WEAPON_APPEARANCE_STANDARD §2 snapshot rule); the card falls back to the reconstructed vanilla item. Tracked #233-class remote-card gap.",
			},
		},

		-- ================================================================
		-- ct_* custom weapon-skin illusions
		-- owner 1p/3p: skin resolves right/left 1p+3p via get_item_units +
		--   create_equipment; injected into WeaponSkins.skins (_cos_illusions.lua).
		-- inventory_preview/illusion_browser: get_unlocked_weapon_skins marks ct_*
		--   unlocked (_cos_illusions.lua); previewers spawn from the skin data.
		-- husk: WIRE-NULLED. Every skin sender nulls ct_* to "n/a"
		--   (_cos_wire_null_custom_skins, :6146) for #421 crash-safety, so remote
		--   husks -- even mod peers -- spawn the base weapon mesh (#233).
		-- ================================================================
		custom_weapon_illusions = {
			cells = {
				owner_1p          = "implemented",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "unsupported",
				inventory_preview = "implemented",
				illusion_browser  = "implemented",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "implemented",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				bot         = "Bots wield the default loadout and never carry a ct_* illusion selection; render vanilla. Safe by design.",
				husk        = "ct_* skin ids are nulled to 'n/a' on every wire sender for #421 crash-safety (_cos_wire_null_custom_skins, :6146); remote husks -- even mod peers -- spawn the base weapon mesh, not the custom illusion. Only a paired offhand mesh rides the #416 channel. Tracked #233 (custom illusion on client).",
				cim_preview = "ct_* illusions surface in the Athanor via the shared get_unlocked_weapon_skins unlock, but cosmetics installs no Athanor previewer hook and there is no in-game confirmation the forge renders the ct_* mesh/paint. Unverified; tracked as the cim-preview illusion gap.",
				lobby       = "No lobby-card previewer hook, and the wire-null means remote lobby husks show the base weapon anyway. Tracked as the lobby-preview gap / #233.",
				score_team  = "Score apply is hat/armor only; ct_* illusions are wire-nulled and not applied on the score lineup. Tracked #513-class weapon-on-score gap / #233.",
				hold_tab    = "ct_* skin is wire-nulled and Hold-Tab has no backend_id; remote cards render the reconstructed vanilla item. Tracked #233-class.",
			},
		},

		-- ================================================================
		-- Bretonnian-sword scale ("thiccc") + grip-offset apply layer
		-- owner 1p/3p + bot: unit-path-driven scale in GearUtils.create_equipment
		--   via _cos_render.lua (_scale_units :174 / _apply_unit_path_scale_hand
		--   :156-168), which fires for owner AND bot-owned units.
		-- husk: NOT applied -- husks spawn via SimpleHuskInventoryExtension /
		--   spawn_inventory_unit, which the scale layer never touches; remote
		--   husks render native scale.
		-- inventory_preview/illusion_browser: _spawn_item_post + spawn_units call
		--   mod._cos.scale_units.
		-- ================================================================
		weapon_model_scale_grip = {
			cells = {
				owner_1p          = "implemented",
				owner_3p          = "implemented",
				bot               = "implemented",
				husk              = "unsupported",
				inventory_preview = "implemented",
				illusion_browser  = "implemented",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "unsupported",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				husk        = "The scale/grip apply runs in GearUtils.create_equipment (owner/bot) and the two previewers; the husk wield path (SimpleHuskInventoryExtension._wield_slot / get_item_units husk branch) never re-applies scale, so remote husks render native scale. Tracked as the husk-transform gap (WEAPON_APPEARANCE_STANDARD §3 Transform/Husk).",
				cim_preview = "Scale apply is bound to cosmetics' three render hooks; the Athanor forge previewer is not among them and renders native scale. Tracked as the cim-preview transform gap.",
				lobby       = "No lobby-card previewer hook; the lobby portrait is 2D. Tracked as the lobby-preview gap.",
				score_team  = "Score lineup weapons are not scaled (score apply is hat/armor only). Tracked #513-class weapon-on-score gap.",
				hold_tab    = "Scale is a 3D mesh property; Hold-Tab shows 2D slot icons with no mesh. n/a by surface.",
			},
		},

		-- ================================================================
		-- Rune/magic glow overrides
		-- owner 1p/3p: apply_material_settings x3 template mutation is the only
		--   writer that paints 1p (_cos_glow.lua; GLOW_SYSTEM §12); re-paint at
		--   wield/visibility (SimpleInventoryExtension._wield_slot :10253 / :9875).
		-- husk: per-peer cos_glow_apply broadcast + _glow_by_peer cache paint
		--   (_cos_glow.lua:127-142).
		-- illusion_browser/cim_preview: glow re-key runs on the in-game +
		--   inventory-mannequin paths only; browser/forge show baked glow (#650).
		-- customize (edge): toggling a preset does NOT live-repaint a spawned
		--   weapon (GLOW_SYSTEM §Activation) -- needs a fresh wield.
		-- ================================================================
		glow_overrides = {
			cells = {
				owner_1p          = "implemented",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "implemented",
				inventory_preview = "implemented",
				illusion_browser  = "unsupported",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "implemented",
				equip               = "implemented",
				customize           = "unsupported",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				bot              = "Glow presets are keyed per exact backend item the owner configured; bots wield default-loadout items with no preset and render vanilla glow. Safe by design.",
				illusion_browser = "Glow re-key runs on create_equipment / _wield_slot / _spawn_item_unit (in-game + inventory mannequin); the LootItemUnitPreviewer illusion-browser path does not re-apply the per-item glow preset -- the browser shows the mesh's baked glow only. Tracked #650 (glow composition).",
				cim_preview      = "The Athanor forge previewer is not hooked for glow; renders baked glow only. Tracked #650.",
				lobby            = "No lobby-card previewer hook; the lobby portrait is 2D. Tracked as the lobby-preview gap.",
				score_team       = "Score apply is hat/armor only; weapon glow presets are not applied on the score lineup. Tracked #513-class / #650.",
				hold_tab         = "Glow is a 3D material property; Hold-Tab shows 2D slot icons. n/a by surface.",
			},
		},

		-- ================================================================
		-- Authored cosmetics: Encarmine Helmet (#612) + Grail Knight set (#629)
		-- owner_3p: M.apply_armor_to_owner (_cos_grail_knight_set.lua:270) +
		--   AttachmentUtils.create_attachment + Laurel controller install on
		--   PlayerUnitAttachmentExtension.create_attachment (#612).
		-- inventory_preview: M.apply_armor_to_hero_preview (:290) +
		--   HeroPreviewer.post_update #629 replay + _spawn_item_unit controller install.
		-- score_team: cb_hero_unit_spawned_skin_preview resolves authored via
		--   GK_SET.resolve_variant (:5501,:5506).
		-- husk: NO apply-to-husk path exists (only owner + preview + score
		--   resolvers); the authored per-instance paint does not travel (#629).
		-- ================================================================
		authored_custom_cosmetics = {
			cells = {
				owner_1p          = "unsupported",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "unsupported",
				inventory_preview = "implemented",
				illusion_browser  = "unsupported",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "implemented",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "unsupported",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "implemented",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				owner_1p         = "The authored hat has no 1P view; the #629 GK outfit declares a 1P mesh/textures (SKIN_FP_UNIT, _cos_grail_knight_set.lua:20,41) but the live owner-body paint (M.apply_armor_to_owner) targets the 3P body -- 1P-arm repaint is unverified. Vanilla 1P mesh renders meanwhile. Tracked #629.",
				bot              = "Authored cosmetics are player-equipped; bots use the default loadout and render vanilla. Safe by design.",
				husk             = "M.apply_armor_to_owner / apply_armor_to_hero_preview cover the owner body and preview surfaces only; no apply-to-husk path exists, so the authored per-instance texture paint does not travel to remote peers (the donor mesh syncs net-safe, colours stay vanilla). Tracked #629 (outfit remote visibility).",
				illusion_browser = "Hat/outfit have no illusion-browser surface; the authored GK shield skin previews via the offhand picker but authored kind=unit paint in LootItemUnitPreviewer is constrained by the null-material AV (LA_SYNC §6.4). Partial/unverified. Tracked #481/#629.",
				cim_preview      = "Authored cosmetics are not applied in the Athanor forge previewer. Tracked #629 / cim-preview gap.",
				lobby            = "No lobby-card previewer hook; co-located keep rendering rides the (unsupported) husk cell. Tracked as the lobby-preview gap / #629.",
				hold_tab         = "Hats/outfit are not weapon-slot cards; the authored GK shield card resolves only for the owner's exact instance -- remote Hold-Tab has no backend_id and falls back to vanilla. Tracked #629 / #233-class.",
			},
		},

		-- ================================================================
		-- #485 social-wheel authored weapon-pose catalog
		-- owner_3p: SocialWheelUI._gather_weapon_poses_by_parent_item substitution
		--   executes the pose locally on the wielder's 3P body (_cos_weapon_poses.lua;
		--   PingTypes.LOCAL_ONLY, social_wheel_ui.lua:1016-1034).
		-- Local-only inspect feature: no cross-peer surface participates.
		-- ================================================================
		weapon_poses = {
			cells = {
				owner_1p          = "unsupported",
				owner_3p          = "implemented",
				bot               = "unsupported",
				husk              = "unsupported",
				inventory_preview = "unsupported",
				illusion_browser  = "unsupported",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "unsupported",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "unsupported",
				mission_transition  = "unsupported",
				respawn             = "unsupported",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				owner_1p          = "Weapon poses are 3P-body inspect animations; the wearer's 1P view has no pose surface. n/a by surface.",
				bot               = "Bots have no social-wheel UI and never trigger a pose. n/a.",
				husk              = "Weapon poses execute PingTypes.LOCAL_ONLY (social_wheel_ui.lua:1016-1034); the pose is never networked, so remote husks never see it. By design (vanilla poses are also local); not a bug.",
				inventory_preview = "Poses are an in-world social-wheel action, not an inventory-preview surface. n/a.",
				illusion_browser  = "Poses have no illusion-browser surface. n/a.",
				cim_preview       = "Poses have no forge-preview surface. n/a.",
				lobby             = "Poses have no lobby surface. n/a.",
				score_team        = "Poses have no score/team surface. n/a.",
				hold_tab          = "Poses have no Hold-Tab surface. n/a.",
			},
		},

		-- ================================================================
		-- Moonfire-arrow impact puff (we_deus_01)
		-- owner 1p/3p + bot + husk: PlayerProjectileUnitExtension AND
		--   PlayerProjectileHuskExtension .hit_enemy/.hit_level_unit/.hit_non_level_unit
		--   are hooked (:10440), so any locally-simulated player projectile --
		--   owner, bot, or remote-husk -- spawns the decorative world-space puff
		--   at impact behind cos_moonfire_cosmetic_puff. FX package rides the
		--   equipped Moonfire Bow.
		-- All non-world surfaces (previews, lobby, score, hold_tab) are n/a: this
		--   is a transient world impact FX, not a rendered unit override.
		-- ================================================================
		cosmetic_projectile_fx = {
			cells = {
				owner_1p          = "implemented",
				owner_3p          = "implemented",
				bot               = "implemented",
				husk              = "implemented",
				inventory_preview = "unsupported",
				illusion_browser  = "unsupported",
				cim_preview       = "unsupported",
				lobby             = "unsupported",
				score_team        = "unsupported",
				hold_tab          = "unsupported",
			},
			edges = {
				instance_load       = "implemented",
				peer_ready          = "implemented",
				equip               = "implemented",
				customize           = "implemented",
				preview_open        = "unsupported",
				mission_transition  = "implemented",
				respawn             = "implemented",
				mod_disable_restore = "unsupported",
			},
			unsupported_fallback = {
				inventory_preview = "Projectile impact FX has no inventory-preview surface. n/a.",
				illusion_browser  = "Projectile FX has no illusion-browser surface. n/a.",
				cim_preview       = "Projectile FX has no forge-preview surface. n/a.",
				lobby             = "Projectile FX has no lobby surface. n/a.",
				score_team        = "Projectile FX has no score/team surface. n/a.",
				hold_tab          = "Projectile FX has no Hold-Tab surface. n/a.",
			},
		},

	},
}
