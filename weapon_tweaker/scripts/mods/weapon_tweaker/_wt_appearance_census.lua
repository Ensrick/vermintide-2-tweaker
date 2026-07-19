-- weapon_tweaker appearance census (#660 W0) - PURE DATA, no engine globals.
--
-- Loadable via dofile; consumed by qa/lua/tests/test_appearance_census.lua and
-- qa/check_appearance_census.ps1. Enumerates, for every registered wt custom
-- appearance FAMILY, each acceptance cell (implemented | unsupported) and each
-- lifecycle edge (implemented | unsupported). This is a RETROACTIVE inventory of
-- today's holes, not a claim of visual verification. Contract vocabulary is
-- mirrored from tools/shared_lib/_lib_appearance_descriptor.lua (M.CELLS/M.EDGES).
--
-- TRUTHFULNESS: a cell/edge is "implemented" ONLY where a wt code path actively
-- produces (or, for 1P, actively preserves-by-design) the correct appearance,
-- with a file:line citation below. Everything else is "unsupported" with a
-- one-line fallback note stating why it is safe and which issue tracks it.
-- "implemented" here means the ADAPTER EXISTS; per APPEARANCE_UNIFICATION_PLAN
-- section 4, verify-fix still requires an in-game per-cell test - a green census
-- row is NOT a setter-success pass.
--
-- wt's live appearance surface is the owner (1P/3P), bots, remote husks, and the
-- keep inventory previewer. It has NO adapter on the illusion browser, the
-- CIM/Athanor craft preview, the pre-mission lobby, the end-of-mission score/team
-- previewer (only a crash-sanitize there), or the Hold-Tab scoreboard (icon-only
-- surface; wt registers no custom weapon icon - cross-access weapons keep their
-- authentic vanilla icon). No family restores already-spawned units on mod
-- disable: on_disabled (weapon_tweaker.lua:4029) reverts only availability, so
-- mod_disable_restore is unsupported for every family (the hooks stop firing and
-- state reverts on the next re-equip / mission reload).
--
-- FAMILIES (the four distinct wt appearance mechanisms; all four ride the same
-- spawn/wield/preview hook surface, hence the identical cell/edge pattern - they
-- differ in the code path each cell cites and in what is applied):
--   cross_character_port  - 3P anim-event + wield-pose remap so a foreign
--                           weapon's 3P events resolve to receiver-skeleton clips
--   model_substitute_queue- 3P mesh substitution (brace->repeater, longbow /
--                           Moonfire->crossbow, Skullsplitter+tome->1H sword)
--   grip_hold_override    - grip-offset + #569 rotation, durable per-frame reapply
--   per_receiver_scale    - per-career non-uniform scale overrides
--
-- KEY CITATIONS (owner-doc: weapon_tweaker/ENGINE_SURFACE.md):
--   funnel:   _wt_anim_remap.lua:608 (Unit.animation_event), :629 (1P early-return),
--             :973 (SimpleInventoryExtension.wield), :1032 (husk wield state)
--   wield:    wt_wield_patches.lua:46 (wield_anim_career_3p boot patch, 3P-only)
--   spawn:    weapon_tweaker.lua:2893 (GearUtils.spawn_inventory_unit 3P swap),
--             :955 (GearUtils.create_equipment, owner+bot, is_bot param)
--   husk:     weapon_tweaker.lua:1036 (SimpleHuskInventoryExtension._wield_slot ->
--             _scale_weapon_units :1048, _wt587 durable track :1049, _offset :1051,
--             #569 track :1058); mesh swap on husk via same spawn path :1086-1089
--   preview:  weapon_tweaker.lua:3542 (MenuWorldPreviewer.equip_item),
--             :3776 (MenuWorldPreviewer._spawn_item_unit + _resolve_preview_wield_event)
--   transform:weapon_tweaker.lua:658 (_offset_weapon_units), :778
--             (_reapply_durable_grip_offsets), :844 (#569 rotation track),
--             :461 (_scale_weapon_units - scales all 4 hand units incl. 1P);
--             backend driver weapon_tweaker_backend.lua:137 mod.update -> :163
--             durable offsets, :171 #569 rotation
--   restore:  weapon_tweaker.lua:4029 (mod.on_disabled - availability only)

local IMPLEMENTED = "implemented"
local UNSUPPORTED = "unsupported"

-- All four families share this cell verdict pattern (owner/bot/husk/keep-preview
-- covered; illusion/cim/lobby/score/hold-tab not). The fallback notes differ per
-- family and are attached below.
local function base_cells()
	return {
		owner_1p          = IMPLEMENTED,
		owner_3p          = IMPLEMENTED,
		bot               = IMPLEMENTED,
		husk              = IMPLEMENTED,
		inventory_preview = IMPLEMENTED,
		illusion_browser  = UNSUPPORTED,
		cim_preview       = UNSUPPORTED,
		lobby             = UNSUPPORTED,
		score_team        = UNSUPPORTED,
		hold_tab          = UNSUPPORTED,
	}
end

-- All four families re-derive their state at every spawn/wield, so every
-- lifecycle edge except a clean mod-disable restore is covered.
local function base_edges()
	return {
		instance_load       = IMPLEMENTED,
		peer_ready          = IMPLEMENTED,
		equip               = IMPLEMENTED,
		customize           = IMPLEMENTED,
		preview_open        = IMPLEMENTED,
		mission_transition  = IMPLEMENTED,
		respawn             = IMPLEMENTED,
		mod_disable_restore = UNSUPPORTED,
	}
end

return {
	families = {
		-- 3P anim-event + wield-pose remap. owner_3p: _wt_anim_remap.lua:608 funnel
		-- + wt_wield_patches.lua:46 + wield state :973. owner_1p: :629 unconditional
		-- 1P early-return keeps the universal first-person animation (never remapped).
		-- bot: owner-class wield+funnel (create_equipment is_bot weapon_tweaker.lua:955).
		-- husk: SimpleHuskInventoryExtension wield state (_wt_anim_remap.lua:1032);
		-- funnel reads career from the unit so the remote player's port remaps on
		-- THEIR career. inventory_preview: _resolve_preview_wield_event at
		-- weapon_tweaker.lua:3776. mission_transition/respawn: wield re-fires
		-- post-spawn (:973) and the funnel (:608) re-resolves - stateless per wield.
		cross_character_port = {
			cells = base_cells(),
			edges = base_edges(),
			unsupported_fallback = {
				illusion_browser = "No illusion-browser wield resolver; a cross-character port opened there falls back to the source template base wield_anim (missing-pose class). Weapon still renders; safe. Tracked #660.",
				cim_preview      = "No Athanor/CIM craft-preview wield resolver; preview shows the source template base stance, no crash. Tracked #660.",
				lobby            = "No pre-mission lobby previewer adapter; lobby wield pose is the source template base stance, no crash. Tracked #660.",
				score_team       = "Only crash-sanitize on LevelEndView/TeamPreviewer (weapon_tweaker.lua:4351,:4393); no wield resolver (previewer unit has no career_system). Renders source base stance; safe. Tracked #660.",
				hold_tab         = "Icon-only surface; wt registers no custom weapon icon, so the scoreboard shows the weapon authentic vanilla icon. Correct by construction; N/A.",
			},
		},

		-- 3P mesh substitution (brace->repeating handgun, longbow/Moonfire->crossbow,
		-- Skullsplitter+tome->1H). owner_3p/bot/husk: GearUtils.spawn_inventory_unit
		-- swap (weapon_tweaker.lua:2893); husks flow through the same spawn path
		-- (:1086-1089). owner_1p: swap is 3P-ONLY - the source weapon's 1P mesh is
		-- kept by design (e.g. the brace 1P at weapon_tweaker.lua:1071). preview:
		-- unit_name mutation at :3542 / :3776. instance_load: substitute unit
		-- packages force-loaded at mod init (:1093, :3826). mission_transition/
		-- respawn: spawn_inventory_unit re-fires on unit re-spawn (:2893).
		model_substitute_queue = {
			cells = base_cells(),
			edges = base_edges(),
			unsupported_fallback = {
				illusion_browser = "No illusion-browser mesh-swap adapter; the source weapon mesh renders instead of the substitute. Safe (valid vanilla mesh). Tracked #660.",
				cim_preview      = "No Athanor/CIM mesh-swap adapter; the source weapon mesh renders. Safe. Tracked #660.",
				lobby            = "No lobby mesh-swap adapter; the source weapon mesh renders in lobby. Safe. Tracked #660.",
				score_team       = "TeamPreviewer/LevelEndView hooks are crash-sanitize only; no mesh swap, so the source mesh renders on the score screen. Safe. Tracked #660.",
				hold_tab         = "Icon-only surface; mesh substitution has no icon effect; scoreboard shows the weapon authentic vanilla icon. N/A.",
			},
		},

		-- Grip-offset + #569 rotation with durable per-frame reapply (anim ticks
		-- stomp weapon node 0). owner_3p: _offset_weapon_units (weapon_tweaker.lua:658)
		-- + _reapply_durable_grip_offsets (:778) + #569 track (:844), driven by
		-- weapon_tweaker_backend.lua:137 mod.update (:163 offsets, :171 rotation).
		-- owner_1p: 3P-ONLY invariant (writes only *_unit_3p, :615/:675-679) leaves
		-- the universal 1P grip vanilla by design. bot: durable track covers local/
		-- bot/husk (:736). husk: _wield_slot applies offset+track+#569 at
		-- weapon_tweaker.lua:1048-1059. inventory_preview: unpaired transforms apply
		-- at _spawn_item_unit; paired hand-scoped transforms use the exact
		-- spawn_data.slot_index -> _equipment_units[left/right] bridge after
		-- _spawn_item (#735). mission_transition/respawn: per-frame reapply +
		-- re-track at each wield.
		grip_hold_override = {
			cells = base_cells(),
			edges = base_edges(),
			unsupported_fallback = {
				illusion_browser = "No illusion-browser transform adapter; grip/rotation offsets are not applied there. Renders at native grip (valid). Tracked #660.",
				cim_preview      = "No Athanor/CIM transform adapter; grip/rotation offsets not applied. Native grip; safe. Tracked #660.",
				lobby            = "No lobby transform adapter; grip/rotation offsets not applied in lobby. Native grip; safe. Tracked #660.",
				score_team       = "No transform application on the score/team previewer; weapon shows native grip. Safe. Tracked #660.",
				hold_tab         = "Icon-only surface; grip/rotation transforms have no icon effect. N/A.",
			},
		},

		-- Per-career non-uniform scale overrides (_weapon_scale_overrides). owner_1p
		-- AND owner_3p: _scale_weapon_units scales ALL FOUR hand units, 1P included
		-- (weapon_tweaker.lua:461) - unlike grip this family DOES touch 1P. bot: same
		-- spawn path. husk: _scale_weapon_units in _wield_slot (weapon_tweaker.lua:1048).
		-- inventory_preview: swapped mesh scaled in MenuWorldPreviewer._spawn_item_unit
		-- (weapon_tweaker.lua:3776; ENGINE_SURFACE previewer row (b)). mission_transition/
		-- respawn: scale re-applied on unit re-spawn.
		per_receiver_scale = {
			cells = base_cells(),
			edges = base_edges(),
			unsupported_fallback = {
				illusion_browser = "No illusion-browser scale adapter; the weapon renders at native scale there. Safe. Tracked #660.",
				cim_preview      = "No Athanor/CIM scale adapter; native scale renders. Safe. Tracked #660.",
				lobby            = "No lobby scale adapter; native scale renders in lobby. Safe. Tracked #660.",
				score_team       = "No scale application on the score/team previewer; native scale renders. Safe. Tracked #660.",
				hold_tab         = "Icon-only surface; per-receiver scale has no icon effect. N/A.",
			},
		},
	},
}
