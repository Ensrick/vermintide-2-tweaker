-- weapons_of_chaos appearance census (#660 / #613) - PURE DATA, no engine globals.
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
--      unsupported with the reason named. The historical conversion forced
--      lobby/score identity plus husk peer-ready/customize unsupported; #613
--      now supplies exact authenticated consumers for those gaps. It still
--      forces husk x mission_transition; and
--      mission_transition on every transform-carrying surface, because the
--      712/613 render-node retention caveat below is exactly a replay doubt;
--   3. the six surfaces added by 1157 start unsupported unless concrete code
--      evidence shows the family implements one. One exception earned
--      evidence: item_card_2d (_woc_inventory_icons.lua, wired through the
--      inventory/icon renderer adapters in weapons_of_chaos.lua).
--   4. crafting_preview, added by 1198, starts unsupported on every edge.
--      Vanilla's ordinary forge layout does not instantiate
--      LootItemUnitPreviewer, so the generic item-preview hook is not evidence
--      for this distinct bench surface.
--
-- TRUTHFULNESS: "implemented" ONLY where a WOC code path actively produces the
-- appearance for that pair, with a file:line citation below. "implemented"
-- means the ADAPTER EXISTS - it is NOT a claim that the pose is visually
-- RETAINED. WOC's owner/husk/preview transform carries the 712/613 retention
-- caveat: gameplay uses measured weak repair and Hero/Menu previews now retain
-- weak absolute targets for post-animation event replay/readback, but those
-- paths remain under active in-game visual verification. Per
-- APPEARANCE_UNIFICATION_PLAN section 4,
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
--   mesh id:  weapons_of_chaos.lua BackendUtils.get_item_units canonical replay
--             forces the authored right-hand unit regardless of skin.
--   owner/bot:weapons_of_chaos.lua GearUtils.spawn_inventory_unit adapter;
--             surface classification lives in _woc_durable_transform.lua.
--   husk:     GearUtils uses the accepted host lease cache from
--             _woc_shared_relic_runtime.lua; peer-ready queries replay the full
--             authenticated snapshot and re-wield changed remote peers.
--   preview:  _woc_mod_unit_preview.lua resolves exact TeamPreviewer wearers,
--             consumes the same authenticated snapshot, retains weak preview
--             transforms, and marks Athanor only at its exact vararg factory.
--   register: StateInGameRunning.on_enter calls _register_blightreaper once for
--             the keep and again for each mission state.
--   durable:  _woc_durable_transform.lua (retained-check-then-reapply on animated
--             1P/3P gameplay units)
--   restore:  weapons_of_chaos.lua mod.on_disabled clears transform ownership +
--             stops audio; does NOT re-key already-spawned units to the base mesh)
--   icon:     _woc_inventory_icons.lua SAFE_RENDERERS allow-list; other
--             renderers fail closed to the resident cloned vanilla sword icon)

local IMPLEMENTED = "implemented"
local UNSUPPORTED = "unsupported"

-- row(default, note, edge_overrides, edge_notes) - `default` is mandatory and
-- explicit; `note` covers every unsupported pair in the row without its own note.
local function row(default, note, edge_overrides, edge_notes)
	return { default = default, note = note, edges = edge_overrides, notes = edge_notes }
end

local FB_DISABLE = "mod.on_disabled clears transform tracking and stops audio but does not re-key already-spawned units to the base mesh; the authored mesh persists until the next re-equip or mission load. Degrades to the resident cloned vanilla sword."
local FB_TRANSITION = "712/613: retention of the authored pose on the named render node is still awaiting in-game visual verification, and a mission transition re-spawns every unit, so transform replay across the transition remains unproven. Mesh identity still re-keys through the get_item_units canonical replay. Degrades to the authored mesh at its native pose."

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
				-- (get_item_units canonical replay) plus the canonical transform
				-- (spawn_inventory_unit -> _wa.apply).
				owner_1p = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				owner_3p = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				bot      = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),

				-- Husk re-key requires the local viewer to run WOC; a non-WOC
				-- viewer safely sees the base sword. The cache is derived only from
				-- the host lease snapshot, queried at peer-ready, and survives an
				-- immutable cosmetic rewield. Mission-transition visuals remain open.
				husk = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),

				-- Character-preview surfaces. _woc_mod_unit_preview.lua hooks
				-- HeroPreviewer/MenuWorldPreviewer._spawn_item and
				-- LootItemUnitPreviewer; each applies TRANSFORM via appearance.apply.
				inventory_preview = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				illusion_browser  = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				cim_preview       = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				crafting_preview  = row(UNSUPPORTED,
					"Vanilla's ordinary PC forge does not instantiate LootItemUnitPreviewer: its layout constructs only HeroWindowCrafting, HeroWindowInventory, and options (hero_window_layout.lua:72-78), and neither the crafting window nor any craft page creates that previewer. WOC therefore has no bench-specific spawned-unit adapter to transform. The generic item-preview hook is not evidence for this distinct surface; the bench retains its native card and tooltip presentation. Tracked 1198."),

				-- #613 exact TeamPreviewer bridge. Live lobby rows resolve an exact
				-- human profile+career; score rows require an exact player-controlled
				-- immutable snapshot row. Both consume only the accepted host lease
				-- identity. Late generations enqueue one consumer-bound replay; stale
				-- generations and destroyed preview sessions fail closed. This is
				-- structural coverage, not an in-game visual-pass claim.
				lobby = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),
				score_team = row(IMPLEMENTED, nil, TRANSFORM_HOLES, TRANSFORM_HOLE_NOTES),

				-- Icon surface only: the custom material is allow-listed to specific
				-- renderers and fails closed elsewhere.
				hold_tab = row(UNSUPPORTED,
					"Custom icon icon_wpn_blightreaper is allow-listed to {ingame_ui, hero_view, loading_view, popup_manager} renderers (_woc_inventory_icons.lua SAFE_RENDERERS); any other renderer (incl. an unproven Hold-Tab scoreboard) fails closed to the resident cloned vanilla sword icon. Safe. Tracked 660."),

				-- Surfaces added by 1157.
				specials = row(UNSUPPORTED,
					"The Blightreaper clones a player base template and swaps the held mesh; WOC installs no weapon-special transform channel, so a weapon special plays the cloned template's own special presentation. Safe (vanilla). Tracked 660."),
				remote_audio = row(UNSUPPORTED,
					"WOC owns authored audio for the relic (mod.on_disabled stops it) but publishes no audio identity to observers, and 747 is the open cross-mod diagnostic covering a Blightreaper carried alongside CWV and vanilla weapons. Remote peers hear the cloned vanilla sword cues. Safe (vanilla). Tracked 398 class / 747."),
				hud_panels = row(UNSUPPORTED,
					"WOC projects no career HUD or ability-panel presentation for the relic; the wielding career's native HUD renders unchanged. Safe (vanilla). Tracked 807 class."),
				portraits = row(UNSUPPORTED,
					"Portrait rendering belongs to dynamic_cosmetic_portraits, which WOC supplies no identity to; portraits render the vanilla career art. Safe (vanilla). Tracked 925 class."),

				-- item_card_2d IMPLEMENTED: _woc_inventory_icons.lua declares the
				-- authored material with a renderer allow-list and a resident
				-- vanilla fallback, and resolve() is wired through the item-card and
				-- exact Athanor preview call sites in weapons_of_chaos.lua.
				item_card_2d = row(IMPLEMENTED,
					"Renderers outside the SAFE_RENDERERS allow-list fail closed to the resident cloned vanilla sword icon (_woc_inventory_icons.lua), so the card always renders a resident icon.",
					DISABLE_ONLY, DISABLE_ONLY_NOTES),

				inventory_tooltip = row(UNSUPPORTED,
					"WOC supplies no tooltip-side appearance identity; the tooltip renders the cloned base template's vanilla text alongside the allow-listed icon. Safe (vanilla). Tracked 660."),
			},
		},
	},
}
