-- weapon_tweaker appearance census (660 W0) - PURE DATA, no engine globals.
--
-- Loadable via dofile; consumed by qa/lua/tests/test_appearance_census.lua.
-- Enumerates, for every registered wt custom appearance FAMILY, every
-- (surface, edge) PAIR as implemented or unsupported. This is a RETROACTIVE
-- inventory of today's holes, not a claim of visual verification. Contract
-- vocabulary is mirrored from tools/shared_lib/_lib_appearance_descriptor.lua
-- (M.CELLS / M.EDGES).
--
-- SCHEMA v2 - SURFACE x EDGE MATRIX (re-keyed 2026-08-04, issue 1157).
-- Until 2026-08-04 a family declared surfaces and edges as two INDEPENDENT
-- vectors, so "husk = implemented" plus "peer_ready = implemented" read as a
-- claim wt has never been able to make: wt owns NO appearance replication
-- channel at all. Declaring the pair removes that blind spot. Authoring is
-- compact - one row per surface stating its default EXPLICITLY, plus per-edge
-- overrides - and the descriptor library FAILS on any pair it cannot resolve.
--
-- CONVERSION RULE APPLIED 2026-08-04 (conservative, never optimistic):
--   1. base state = min(old surface state, old edge state);
--   2. any pair with a known open issue or documented doubt is FORCED
--      unsupported with the reason named. Applied here: the ENTIRE husk row.
--      wt has no wire of its own; every observer re-derives the remapped
--      animation, substituted mesh, grip and scale locally from the wielded
--      item, so nothing is replicated and nothing is replayed at any edge;
--   3. the six surfaces added by 1157 start unsupported unless concrete code
--      evidence shows the family implements one. One exception earned
--      evidence: cross_character_port owns hud_panels (388 overcharge).
--   4. crafting_preview, added by 1198, starts unsupported for every family:
--      wt has no ordinary crafting-bench adapter, and the bench cannot inherit
--      inventory-preview support by inference.
--
-- TRUTHFULNESS: a pair is "implemented" ONLY where a wt code path actively
-- produces (or, for 1P, actively preserves-by-design) the correct appearance,
-- with a file:line citation below. Everything else is "unsupported" with a
-- note stating why it is safe and which issue tracks it. "implemented" here
-- means the ADAPTER EXISTS; per APPEARANCE_UNIFICATION_PLAN section 4,
-- verify-fix still requires an in-game per-cell test - a green census row is
-- NOT a setter-success pass.
--
-- wt's live appearance surface is the owner (1P/3P), bots, and the keep
-- inventory previewer. It has NO adapter on the illusion browser, the
-- CIM/Athanor craft preview, the ordinary crafting-bench preview, the
-- pre-mission lobby, the end-of-mission
-- score/team previewer (only a crash-sanitize there), or the Hold-Tab
-- scoreboard (icon-only surface; wt registers no custom weapon icon -
-- cross-access weapons keep their authentic vanilla icon). No family restores
-- already-spawned units on mod disable: on_disabled (weapon_tweaker.lua:4029)
-- reverts only availability, so mod_disable_restore is unsupported for every
-- family (the hooks stop firing and state reverts on the next re-equip /
-- mission reload).
--
-- FAMILIES (the four distinct wt appearance mechanisms; all four ride the same
-- spawn/wield/preview hook surface, hence the identical row pattern - they
-- differ in the code path each pair cites and in what is applied):
--   cross_character_port  - 3P anim-event + wield-pose remap so a foreign
--                           weapon's 3P events resolve to receiver-skeleton clips
--   model_substitute_queue- 3P mesh substitution (brace->repeater, longbow /
--                           Moonfire->crossbow, Skullsplitter+tome->1H sword)
--   grip_hold_override    - grip-offset + 569 rotation, durable per-frame reapply
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
--             569 track :1058); mesh swap on husk via same spawn path :1086-1089.
--             NOTE: this is LOCAL re-derivation on each observer, not replication.
--   preview:  weapon_tweaker.lua:3542 (MenuWorldPreviewer.equip_item),
--             :3776 (MenuWorldPreviewer._spawn_item_unit + _resolve_preview_wield_event)
--   transform:weapon_tweaker.lua:658 (_offset_weapon_units), :778
--             (_reapply_durable_grip_offsets), :844 (569 rotation track),
--             :461 (_scale_weapon_units - scales all 4 hand units incl. 1P);
--             backend driver weapon_tweaker_backend.lua:137 mod.update -> :163
--             durable offsets, :171 569 rotation
--   hud:      weapon_tweaker_backend.lua:54 -> _wt_overcharge_presentation.lua ->
--             _wt_overcharge_presentation_policy.lua (388 Deepwood overcharge
--             profile projected onto the receiving career's HUD/screen FX)
--   restore:  weapon_tweaker.lua:4029 (mod.on_disabled - availability only)

local IMPLEMENTED = "implemented"
local UNSUPPORTED = "unsupported"

-- row(default, note, edge_overrides, edge_notes) - `default` is mandatory and
-- explicit; `note` covers every unsupported pair in the row without its own note.
local function row(default, note, edge_overrides, edge_notes)
	return { default = default, note = note, edges = edge_overrides, notes = edge_notes }
end

-- Every family re-derives its state at every spawn/wield, so the only lifecycle
-- hole on the owner-side surfaces is a clean mod-disable restore.
local DISABLE_ONLY = { mod_disable_restore = UNSUPPORTED }
local FB_DISABLE = "mod.on_disabled (weapon_tweaker.lua:4029) reverts availability only; already-spawned units keep the applied remap/mesh/grip/scale until the next re-equip or mission reload, at which point the hooks no longer fire. Degrades to the resident vanilla presentation."
local DISABLE_ONLY_NOTES = { mod_disable_restore = FB_DISABLE }

-- FORCED (1157): wt owns no appearance replication channel. The husk path at
-- weapon_tweaker.lua:1036 is the OBSERVER re-deriving locally from the wielded
-- item, so it is correct only when that observer also runs wt with the same
-- settings, and it is never replayed for a peer that joined late or for a
-- wearer whose selection changed. Unsupported at every edge, on every family.
local FB_HUSK = "wt ships no appearance replication channel: the husk path (weapon_tweaker.lua:1036 -> :1048-1059, mesh swap :1086-1089) is each observer re-deriving locally from the wielded item, so it holds only when that observer also runs wt with matching settings, and nothing is replayed on hot-join or after a wearer-side change. An observer without wt, or with different toggles, renders the authentic vanilla weapon. Safe (vanilla). Tracked 660."
local FB_CRAFTING = "wt has no ordinary crafting-bench preview adapter; the bench is distinct from both the inventory previewer and CIM Athanor, so it retains the source weapon's authentic vanilla presentation. Safe (vanilla). Tracked 1198 / 660."

local function base_matrix(fallbacks, overrides)
	local m = {
		owner_1p          = row(IMPLEMENTED, nil, DISABLE_ONLY, DISABLE_ONLY_NOTES),
		owner_3p          = row(IMPLEMENTED, nil, DISABLE_ONLY, DISABLE_ONLY_NOTES),
		bot               = row(IMPLEMENTED, nil, DISABLE_ONLY, DISABLE_ONLY_NOTES),
		husk              = row(UNSUPPORTED, FB_HUSK),
		inventory_preview = row(IMPLEMENTED, nil, DISABLE_ONLY, DISABLE_ONLY_NOTES),
		illusion_browser  = row(UNSUPPORTED, fallbacks.illusion_browser),
		cim_preview       = row(UNSUPPORTED, fallbacks.cim_preview),
		crafting_preview  = row(UNSUPPORTED, FB_CRAFTING),
		lobby             = row(UNSUPPORTED, fallbacks.lobby),
		score_team        = row(UNSUPPORTED, fallbacks.score_team),
		hold_tab          = row(UNSUPPORTED, fallbacks.hold_tab),
		specials          = row(UNSUPPORTED, fallbacks.specials),
		remote_audio      = row(UNSUPPORTED, fallbacks.remote_audio),
		hud_panels        = row(UNSUPPORTED, fallbacks.hud_panels),
		portraits         = row(UNSUPPORTED, fallbacks.portraits),
		item_card_2d      = row(UNSUPPORTED, fallbacks.item_card_2d),
		inventory_tooltip = row(UNSUPPORTED, fallbacks.inventory_tooltip),
	}
	if overrides then for k, v in pairs(overrides) do m[k] = v end end
	return m
end

-- Notes shared by every family for the six surfaces 1157 added.
local FB_SPECIALS = "wt remaps 3P animation events and substitutes meshes; it installs no weapon-special transform channel, so a weapon special plays the effective template's own special presentation. Safe (vanilla). Tracked 660."
local FB_REMOTE_AUDIO = "wt re-keys 3P animation and mesh but never re-keys weapon audio, so every peer (including the wearer's own observers) hears the source weapon's authentic vanilla cues. Correct by construction for cross-access; tracked 398 class."
local FB_PORTRAITS = "Portrait rendering belongs to dynamic_cosmetic_portraits; wt supplies it no weapon identity and portraits render the vanilla career art. Safe (vanilla). Tracked 925 class."
local FB_ITEM_CARD = "wt registers no custom weapon icon; cross-access weapons keep their authentic vanilla icon on the 2D item card. Correct by construction. Tracked 660 / 638 / 641."
local FB_TOOLTIP = "wt supplies no tooltip-side appearance identity; the tooltip renders the effective template's vanilla text and icon. Safe (vanilla). Tracked 660."
local FB_HUD_GENERIC = "This family applies no HUD-panel presentation; the receiving career's native HUD renders unchanged. Safe (vanilla). Tracked 807 class."

return {
	schema_version = 2,
	families = {
		-- 3P anim-event + wield-pose remap. owner_3p: _wt_anim_remap.lua:608 funnel
		-- + wt_wield_patches.lua:46 + wield state :973. owner_1p: :629 unconditional
		-- 1P early-return keeps the universal first-person animation (never remapped).
		-- bot: owner-class wield+funnel (create_equipment is_bot weapon_tweaker.lua:955).
		-- inventory_preview: _resolve_preview_wield_event at weapon_tweaker.lua:3776.
		-- mission_transition/respawn: wield re-fires post-spawn (:973) and the funnel
		-- (:608) re-resolves - stateless per wield, so no replay is owed.
		-- hud_panels: 388 projects the Deepwood overcharge profile onto the receiving
		-- career (weapon_tweaker_backend.lua:54 -> _wt_overcharge_presentation.lua),
		-- which is a real HUD/screen-FX presentation adapter owned by this family.
		cross_character_port = {
			matrix = base_matrix({
				illusion_browser = "No illusion-browser wield resolver; a cross-character port opened there falls back to the source template base wield_anim (missing-pose class). Weapon still renders; safe. Tracked 660.",
				cim_preview      = "No Athanor/CIM craft-preview wield resolver; preview shows the source template base stance, no crash. Tracked 660.",
				lobby            = "No pre-mission lobby previewer adapter; lobby wield pose is the source template base stance, no crash. Tracked 660.",
				score_team       = "Only crash-sanitize on LevelEndView/TeamPreviewer (weapon_tweaker.lua:4351,:4393); no wield resolver (previewer unit has no career_system). Renders source base stance; safe. Tracked 660.",
				hold_tab         = "Icon-only surface; wt registers no custom weapon icon, so the scoreboard shows the weapon's authentic vanilla icon. Correct by construction.",
				specials         = FB_SPECIALS,
				remote_audio     = FB_REMOTE_AUDIO,
				hud_panels       = FB_HUD_GENERIC,
				portraits        = FB_PORTRAITS,
				item_card_2d     = FB_ITEM_CARD,
				inventory_tooltip = FB_TOOLTIP,
			}, {
				hud_panels = row(IMPLEMENTED,
					"388: the overcharge profile is captured and restored by the runtime around the port; on mod disable the capture is not replayed, so the panel reverts on the next player creation. Degrades to the receiving career's native overcharge state.",
					DISABLE_ONLY, DISABLE_ONLY_NOTES),
			}),
		},

		-- 3P mesh substitution (brace->repeating handgun, longbow/Moonfire->crossbow,
		-- Skullsplitter+tome->1H). owner_3p/bot: GearUtils.spawn_inventory_unit swap
		-- (weapon_tweaker.lua:2893). owner_1p: swap is 3P-ONLY - the source weapon's
		-- 1P mesh is kept by design (e.g. the brace 1P at weapon_tweaker.lua:1071).
		-- preview: unit_name mutation at :3542 / :3776. instance_load: substitute
		-- unit packages force-loaded at mod init (:1093, :3826). mission_transition/
		-- respawn: spawn_inventory_unit re-fires on unit re-spawn (:2893).
		model_substitute_queue = {
			matrix = base_matrix({
				illusion_browser = "No illusion-browser mesh-swap adapter; the source weapon mesh renders instead of the substitute. Safe (valid vanilla mesh). Tracked 660.",
				cim_preview      = "No Athanor/CIM mesh-swap adapter; the source weapon mesh renders. Safe. Tracked 660.",
				lobby            = "No lobby mesh-swap adapter; the source weapon mesh renders in lobby. Safe. Tracked 660.",
				score_team       = "TeamPreviewer/LevelEndView hooks are crash-sanitize only; no mesh swap, so the source mesh renders on the score screen. Safe. Tracked 660.",
				hold_tab         = "Icon-only surface; mesh substitution has no icon effect; scoreboard shows the weapon's authentic vanilla icon.",
				specials         = FB_SPECIALS,
				remote_audio     = FB_REMOTE_AUDIO,
				hud_panels       = FB_HUD_GENERIC,
				portraits        = FB_PORTRAITS,
				item_card_2d     = FB_ITEM_CARD,
				inventory_tooltip = FB_TOOLTIP,
			}),
		},

		-- Grip-offset + 569 rotation with durable per-frame reapply (anim ticks
		-- stomp weapon node 0). owner_3p: _offset_weapon_units (weapon_tweaker.lua:658)
		-- + _reapply_durable_grip_offsets (:778) + 569 track (:844), driven by
		-- weapon_tweaker_backend.lua:137 mod.update (:163 offsets, :171 rotation).
		-- owner_1p: 3P-ONLY invariant (writes only *_unit_3p, :615/:675-679) leaves
		-- the universal 1P grip vanilla by design. bot: durable track covers local
		-- and bot units (:736). inventory_preview: unpaired transforms apply at
		-- _spawn_item_unit; paired hand-scoped transforms use the exact
		-- spawn_data.slot_index -> _equipment_units[left/right] bridge after
		-- _spawn_item (735). mission_transition/respawn: per-frame reapply +
		-- re-track at each wield.
		grip_hold_override = {
			matrix = base_matrix({
				illusion_browser = "No illusion-browser transform adapter; grip/rotation offsets are not applied there. Renders at native grip (valid). Tracked 660.",
				cim_preview      = "No Athanor/CIM transform adapter; grip/rotation offsets not applied. Native grip; safe. Tracked 660.",
				lobby            = "No lobby transform adapter; grip/rotation offsets not applied in lobby. Native grip; safe. Tracked 660.",
				score_team       = "No transform application on the score/team previewer; weapon shows native grip. Safe. Tracked 660.",
				hold_tab         = "Icon-only surface; grip/rotation transforms have no icon effect.",
				specials         = FB_SPECIALS,
				remote_audio     = FB_REMOTE_AUDIO,
				hud_panels       = FB_HUD_GENERIC,
				portraits        = FB_PORTRAITS,
				item_card_2d     = FB_ITEM_CARD,
				inventory_tooltip = FB_TOOLTIP,
			}),
		},

		-- Per-career non-uniform scale overrides (_weapon_scale_overrides). owner_1p
		-- AND owner_3p: _scale_weapon_units scales ALL FOUR hand units, 1P included
		-- (weapon_tweaker.lua:461) - unlike grip this family DOES touch 1P. bot: same
		-- spawn path. inventory_preview: swapped mesh scaled in MenuWorldPreviewer.
		-- _spawn_item_unit (weapon_tweaker.lua:3776; ENGINE_SURFACE previewer row (b)).
		-- mission_transition/respawn: scale re-applied on unit re-spawn.
		per_receiver_scale = {
			matrix = base_matrix({
				illusion_browser = "No illusion-browser scale adapter; the weapon renders at native scale there. Safe. Tracked 660.",
				cim_preview      = "No Athanor/CIM scale adapter; native scale renders. Safe. Tracked 660.",
				lobby            = "No lobby scale adapter; native scale renders in lobby. Safe. Tracked 660.",
				score_team       = "No scale application on the score/team previewer; native scale renders. Safe. Tracked 660.",
				hold_tab         = "Icon-only surface; per-receiver scale has no icon effect.",
				specials         = FB_SPECIALS,
				remote_audio     = FB_REMOTE_AUDIO,
				hud_panels       = FB_HUD_GENERIC,
				portraits        = FB_PORTRAITS,
				item_card_2d     = FB_ITEM_CARD,
				inventory_tooltip = FB_TOOLTIP,
			}),
		},
	},
}
