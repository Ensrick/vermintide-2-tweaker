-- weapons_of_chaos appearance census (#660 W0) - PURE DATA, no engine globals.
--
-- Loadable via dofile; consumed by qa/lua/tests/test_appearance_census.lua and
-- qa/check_appearance_census.ps1. Enumerates, for the WOC custom-appearance
-- FAMILY, each acceptance cell (implemented | unsupported) and each lifecycle
-- edge (implemented | unsupported). Retroactive inventory of today's holes;
-- vocabulary mirrors tools/shared_lib/_lib_appearance_descriptor.lua.
--
-- TRUTHFULNESS: "implemented" ONLY where a WOC code path actively produces the
-- appearance for that cell, with a file:line citation below. "implemented" means
-- the ADAPTER EXISTS - it is NOT a claim that the pose is visually RETAINED.
-- WOC's owner/husk/character-preview transform carries the #712/#613 retention
-- caveat: the render-node pose is applied via WeaponAppearance.apply +
-- _woc_durable_transform.lua, but retention on linked node 0 is under active
-- in-game verification (a spawn-time pcall success is not retention proof -
-- DEVELOPMENT.md, v0.1.24-dev). Per APPEARANCE_UNIFICATION_PLAN section 4,
-- verify-fix still requires an in-game per-cell test; a green census row is not a
-- setter-success pass. The MESH IDENTITY (get_item_units re-key to the authored
-- Blightreaper unit) is the separate, working channel underneath that caveat.
--
-- FAMILY: enemy_weapon_relic - player characters wielding an enemy/keep-trophy
-- weapon via the duplicate-item approach. One registered member today, the
-- Blightreaper (weapons_of_chaos.lua). "any future enemy-weapon items as one
-- family" (task W0 scope): new enemy weapons ride the same registration + render
-- pipeline and extend this family, not a new one.
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

return {
	families = {
		enemy_weapon_relic = {
			cells = {
				-- Owner 1P and 3P, bots, and remote husks all receive the authored
				-- Blightreaper unit (get_item_units :1449/:1455) plus the canonical
				-- transform (spawn_inventory_unit :1491 -> _wa.apply :1522-1524).
				-- Husk re-key requires the local viewer to run WOC (same-mod sideband
				-- :1493-1509); a non-WOC viewer safely sees the base sword (wire safety).
				owner_1p          = IMPLEMENTED,
				owner_3p          = IMPLEMENTED,
				bot               = IMPLEMENTED,
				husk              = IMPLEMENTED,
				-- Character-preview surfaces: HeroPreviewer/MenuWorldPreviewer._spawn_item
				-- covers inventory, lobby, and score/end previews (comment :65);
				-- LootItemUnitPreviewer covers the illusion browser + Athanor + item
				-- preview (comment :84). Each applies TRANSFORM via appearance.apply.
				inventory_preview = IMPLEMENTED,
				illusion_browser  = IMPLEMENTED,
				cim_preview       = IMPLEMENTED,
				lobby             = IMPLEMENTED,
				score_team        = IMPLEMENTED,
				-- Icon surface only: the custom material is allow-listed to specific
				-- renderers and fails closed elsewhere.
				hold_tab          = UNSUPPORTED,
			},
			edges = {
				-- instance_load: one-shot registration at StateInGameRunning.on_enter
				--   (:838 -> :230), master-package residency owns the units.
				-- peer_ready: husk re-key + get_item_units canonical replay fire on the
				--   joining peer's loadout-sync (VMF sideband per loadout-sync edge).
				-- equip: get_item_units + spawn_inventory_unit fire on equip.
				-- customize: Blightreaper is immutable - get_item_units forces the
				--   authored unit regardless of skin (:1455), defending the appearance.
				-- preview_open: previewer hooks fire on preview open (_woc_mod_unit_preview).
				-- mission_transition: on_enter re-fires each mission (:838) + get_item_units
				--   canonical replay (:1449) + _woc_durable_transform retained-reapply.
				-- respawn: unit re-spawn re-runs get_item_units + spawn_inventory_unit.
				-- mod_disable_restore: UNSUPPORTED - on_disabled (:1592) clears transform
				--   tracking + audio but does not re-key already-spawned units to the base
				--   mesh; the authored mesh persists until the next re-equip / mission load.
				instance_load       = IMPLEMENTED,
				peer_ready          = IMPLEMENTED,
				equip               = IMPLEMENTED,
				customize           = IMPLEMENTED,
				preview_open        = IMPLEMENTED,
				mission_transition  = IMPLEMENTED,
				respawn             = IMPLEMENTED,
				mod_disable_restore = UNSUPPORTED,
			},
			unsupported_fallback = {
				hold_tab = "Custom icon icon_wpn_blightreaper is allow-listed to {ingame_ui,hero_view,loading_view,popup_manager} renderers (_woc_inventory_icons.lua:12-17); any other renderer (incl. an unproven Hold-Tab scoreboard) fails closed to the resident cloned vanilla sword icon. Safe. Tracked #660.",
			},
		},
	},
}
