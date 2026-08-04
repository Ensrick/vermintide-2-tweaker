-- weapons_of_chaos appearance census (660 W0) - PURE DATA, no engine globals.
--
-- Loadable via dofile; consumed by qa/lua/tests/test_appearance_census.lua.
-- Enumerates, for the WOC custom-appearance FAMILY, every (surface, edge) PAIR
-- as implemented or unsupported. Retroactive inventory of today's holes;
-- vocabulary mirrors tools/shared_lib/_lib_appearance_descriptor.lua.
--
-- SCHEMA v2 - SURFACE x EDGE MATRIX (re-keyed 2026-08-04, issue 1157).
-- Until 2026-08-04 surfaces and edges were declared as two INDEPENDENT
-- vectors, which let "husk = implemented" plus "mission_transition =
-- implemented" stand in for a claim that was never separately evidenced.
-- Authoring is compact - one row per surface stating its default EXPLICITLY,
-- plus per-edge overrides - and the descriptor library FAILS on any pair it
-- cannot resolve. Nothing is implicit.
--
-- CONVERSION RULE APPLIED 2026-08-04 (conservative, never optimistic):
--   1. base state = min(old surface state, old edge state);
--   2. any pair with a known open issue or documented doubt is FORCED
--      unsupported with the reason named. Applied here: lobby and score_team
--      on the whole family (the old "implemented" was inferred from a shared
--      previewer hook comment, not from a per-surface verification); husk x
--      peer_ready, husk x customize and husk x mission_transition; and
--      mission_transition on every transform-carrying surface, because the
--      712/613 render-node retention caveat below is exactly a replay doubt;
--   3. the six surfaces added by 1157 start unsupported unless concrete code
--      evidence shows the family implements one. One exception earned
--      evidence: item_card_2d (_woc_inventory_icons.lua, wired at
--      weapons_of_chaos.lua:217/:505/:551/:1276).
--
-- TRUTHFULNESS: "implemented" ONLY where a WOC code path actively produces the
-- appearance for that pair, with a file:line citation below. "implemented"
-- means the ADAPTER EXISTS - it is NOT a claim that the pose is visually
-- RETAINED. WOC's owner/husk/character-preview transform carries the 712/613
-- retention caveat: the render-node pose is applied via WeaponAppearance.apply
-- + _woc_durable_transform.lua, but retention on linked node 0 is under active
-- in-game verification (a spawn-time pcall success is not retention proof -
-- DEVELOPMENT.md, v0.1.24-dev). Per APPEARANCE_UNIFICATION_PLAN section 4,
-- verify-fix still requires an in-game per-cell test; a green census row is not
-- a setter-success pass. The MESH IDENTITY (get_item_units re-key to the
-- authored Blightreaper unit) is the separate, working channel underneath that
-- caveat.
--
-- FAMILY: enemy_weapon_relic - player characters wielding an enemy/keep-trophy
-- weapon via the duplicate-item approach. One registered member today, the
-- Blightreaper (weapons_of_chaos.lua). "any future enemy-weapon items as one
-- family" (task W0 scope): new enemy weapons ride the same registration +
-- render pipeline and extend this family, not a new one.
--
-- KEY CITATIONS (owner-doc: weapons_of_chaos/ENGINE_SURFACE.md, DEVELOPMENT.md):
--   mesh id:  weapons_of_chaos.lua:1449 (BackendUtils.get_item_units canonical
--             replay - keep/mission/preview owner; forces authored right_hand_unit
--             at :1455 regardless of skin)
--   owner/bot:weapons_of_chaos.lua:1491 (GearUtils.spawn_inventory_unit) -> _wa.apply
--             3P :1522, 1P :1523-1524; surface classified _woc_durable_transform.lua:29
--   husk:     weapons_of_chaos.lua:1493-1509 (husk branch re-keys via the WOC
--             same-mod sideband _remote_blightreaper[peer]) -> transform :1514-1527
--   preview:  _woc_mod_unit_preview.lua:81-82 (HeroPreviewer/MenuWorldPreviewer
--             ._spawn_item = inventory + lobby + score/end, comment :65); :85-116
--             (LootItemUnitPreviewer = illusion browser + Athanor + item preview,
--             comment :84)
--   register: weapons_of_chaos.lua:838 (StateInGameRunning.on_enter -> one-shot
--             _register_blightreaper :230; re-fires on keep AND each mission load)
--   durable:  _woc_durable_transform.lua (retained-check-then-reapply on animated
--             1P/3P gameplay units)
--   restore:  weapons_of_chaos.lua:1592 (mod.on_disabled - clears transform owner +
--             stops audio; does NOT re-key already-spawned units to the base mesh)
--   icon:     _woc_inventory_icons.lua:12-17 (SAFE_RENDERERS allow-list; other
--             renderers fail closed to the resident cloned vanilla sword icon)

local IMPLEMENTED = "implemented"
local UNSUPPORTED = "unsupported"

-- row(default, note, edge_overrides, edge_notes) - `default` is mandatory and
-- explicit; `note` covers every unsupported pair in the row without its own note.
local function row(default, note, edge_overrides, edge_notes)
	return { default = default, note = note, edges = edge_overrides, notes = edge_notes }
end

local function plus(base, extra)
	local t = {}
	if base then for k, v in pairs(base) do t[k] = v end end
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

local FB_DISABLE = "mod.on_disabled (weapons_of_chaos.lua:1592) clears transform tracking and stops audio but does not re-key already-spawned units to the base mesh; the authored mesh persists until the next re-equip or mission load. Degrades to the resident cloned vanilla sword."
local FB_TRANSITION = "712/613: retention of the authored pose on linked render node 0 is under active in-game verification, and a mission transition re-spawns every unit, so the transform replay across the transition is exactly the unproven case. Mesh identity still re-keys via the get_item_units canonical replay (:1449). Degrades to the authored mesh at its native pose."

-- Applied to every surface that carries the authored transform.
local TRANSFORM_HOLES = { mission_transition = UNSUPPORTED, mod_disable_restore = UNSUPPORTED }
local TRANSFORM_HOLE_NOTES = { mission_transition = FB_TRANSITION, mod_disable_restore = FB_DISABLE }

-- Surfaces that carry only identity/icon, not the render-node pose.
local DISABLE_ONLY = { mod_disable_restore = UNSUPPORTED }
local DISABLE_ONLY_NOTES = { mod_disable_restore = FB_DISABLE }

return {
	schema_version = 2,
	families = {
		enemy_weapon_relic = {
			matrix = {
				-- Owner 1P and 3P and bots receive the authored Blightreaper unit
				-- (get_item_units :1449/:1455) plus the canonical transform
				-- (spawn_inventory_unit :1491 -> _wa.apply :1522-1524).
				owner_1p = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				owner_3p = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				bot      = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),

				-- Husk re-key requires the local viewer to run WOC (same-mod
				-- sideband :1493-1509); a non-WOC viewer safely sees the base
				-- sword (wire safety). FORCED unsupported at the three replay
				-- edges - the sideband is published on equip and is not replayed.
				husk = row(IMPLEMENTED, nil,
					plus(TRANSFORM_HOLES, {
						peer_ready = UNSUPPORTED, customize = UNSUPPORTED,
					}),
					plus(TRANSFORM_HOLE_NOTES, {
						peer_ready = "Hot-join: _remote_blightreaper[peer] is published over the same-mod sideband when the wearer equips, so an observer that becomes ready afterwards has no entry to re-key from and is not sent one. Degrades to the resident cloned vanilla sword (wire safety).",
						customize = "The Blightreaper itself is immutable (get_item_units forces the authored unit regardless of skin, :1455), but a customization-driven re-wield on the wearer does not re-publish the sideband entry, so an observer that missed the original publish stays un-re-keyed. Degrades to the resident cloned vanilla sword.",
					})),

				-- Character-preview surfaces. _woc_mod_unit_preview.lua:81-82 hooks
				-- HeroPreviewer/MenuWorldPreviewer._spawn_item and :85-116 hooks
				-- LootItemUnitPreviewer; each applies TRANSFORM via appearance.apply.
				inventory_preview = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				illusion_browser  = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				cim_preview       = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),

				-- FORCED unsupported (1157). The pre-1157 "implemented" for these
				-- two came from the shared _spawn_item hook's own comment listing
				-- lobby and score among the surfaces it covers - an inference from
				-- a sibling surface, which the truthfulness rule bans. Neither has
				-- a per-surface verification and neither resolves a wearer identity
				-- the way the crowbill bridge does.
				lobby = row(UNSUPPORTED,
					"The lobby previewer shares HeroPreviewer/MenuWorldPreviewer._spawn_item (_woc_mod_unit_preview.lua:81-82), but WOC resolves no lobby wearer identity there and the surface has never been verified separately; a lobby row for a peer without WOC cannot re-key at all. Degrades to the resident cloned vanilla sword. Tracked 660."),
				score_team = row(UNSUPPORTED,
					"The end-of-mission lineup shares the same _spawn_item hook but WOC resolves no score-row wearer identity (no equivalent of the CWV crowbill score bridge), so a remote wearer's Blightreaper is not proven to render. Degrades to the resident cloned vanilla sword. Tracked 660 / 513-class."),

				-- Icon surface only: the custom material is allow-listed to specific
				-- renderers and fails closed elsewhere.
				hold_tab = row(UNSUPPORTED,
					"Custom icon icon_wpn_blightreaper is allow-listed to {ingame_ui, hero_view, loading_view, popup_manager} renderers (_woc_inventory_icons.lua:12-17); any other renderer (incl. an unproven Hold-Tab scoreboard) fails closed to the resident cloned vanilla sword icon. Safe. Tracked 660."),

				-- Surfaces added by 1157.
				specials = row(UNSUPPORTED,
					"The Blightreaper clones a player base template and swaps the held mesh; WOC installs no weapon-special transform channel, so a weapon special plays the cloned template's own special presentation. Safe (vanilla). Tracked 660."),
				remote_audio = row(UNSUPPORTED,
					"WOC owns authored audio for the relic (mod.on_disabled stops it, :1592) but publishes no audio identity to observers, and 747 is the open cross-mod diagnostic covering a Blightreaper carried alongside CWV and vanilla weapons. Remote peers hear the cloned vanilla sword cues. Safe (vanilla). Tracked 398 class / 747."),
				hud_panels = row(UNSUPPORTED,
					"WOC projects no career HUD or ability-panel presentation for the relic; the wielding career's native HUD renders unchanged. Safe (vanilla). Tracked 807 class."),
				portraits = row(UNSUPPORTED,
					"Portrait rendering belongs to dynamic_cosmetic_portraits, which WOC supplies no identity to; portraits render the vanilla career art. Safe (vanilla). Tracked 925 class."),

				-- item_card_2d IMPLEMENTED: _woc_inventory_icons.lua declares the
				-- authored material with a renderer allow-list and a resident
				-- vanilla fallback, and resolve() is wired at weapons_of_chaos.lua
				-- :217/:505/:551 with the Athanor call site at :1276.
				item_card_2d = row(IMPLEMENTED,
					"Renderers outside the SAFE_RENDERERS allow-list fail closed to the resident cloned vanilla sword icon (_woc_inventory_icons.lua:12-17), so the card always renders a resident icon.",
					DISABLE_ONLY, DISABLE_ONLY_NOTES),

				inventory_tooltip = row(UNSUPPORTED,
					"WOC supplies no tooltip-side appearance identity; the tooltip renders the cloned base template's vanilla text alongside the allow-listed icon. Safe (vanilla). Tracked 660."),
			},
		},
	},
}
