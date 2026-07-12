# rt_textual_invariants.psd1 - needle manifest for qa/check_rt_textual_invariants.ps1
# (issue #516). Each entry is ONE source-text invariant that issue #511 moved out
# of an in-game `/<mod>_regression_test` check (the retail Stingray VM has no `io`
# library, so a source self-grep threw and false-failed). These are the genuinely
# TEXTUAL invariants the runtime markers cannot capture - a literal that must be
# PRESENT, a forbidden pattern that must be ABSENT, or a count invariant.
#
# Fields:
#   mod       - owning mod (for grouping/report)
#   file      - repo-relative path (forward slashes) of the file scanned
#   needle    - the string (literal) or .NET regex to look for
#   literal   - $true = ordinal substring match; $false = needle is a regex
#   polarity  - 'present' (must occur) or 'absent' (must NOT occur)
#   minCount  - present-only: minimum occurrences (default 1)
#   maxCount  - present-only: maximum occurrences (omit for no upper bound)
#   issueRef  - the issue the invariant locks
#   note      - human context: what breaks if this fails
#
# EVERY needle was verified against the CURRENT source on 2026-07-12 (present
# needles occur; absent needles do not). Two gt absence needles use a
# comment-excluding regex ((?!\s*--)) because _gt_debug_highlights.lua documents
# the invariant itself in a comment - a naive literal would false-fail.
#
# DO NOT add a needle without grepping the live source first. If a needle starts
# failing, the invariant text was reworded (adapt the needle) or the fix
# regressed (fix the source) - never silence it by deletion.

@{
  entries = @(

    # ============================ gt_dev ============================
    # Source: general_tweaker_dev/CHANGELOG.md v0.2.202-dev (issue 511 section),
    # the 15-item residual-static list. Needle literals recovered from the
    # pre-conversion rt-check bodies (commit 7e6661a) and re-verified live.

    # -- item 1: _gt_debug_highlights.lua must not read POSITION_LOOKUP (dead for
    #    the local player in mod.update; issue 337 class) nor call bare
    #    :local_player() (asserts pre-game; issue 508). Both use a comment-excluding
    #    regex: the file names both tokens in explanatory comments.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; needle='(?m)^(?!\s*--).*POSITION_LOOKUP\['; literal=$false; polarity='absent'; issueRef='#337'; note='dh must not index POSITION_LOOKUP[...] in code (dead in mod.update); comment mention allowed.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; needle='= POSITION_LOOKUP'; literal=$true; polarity='absent'; issueRef='#337'; note='dh must not assign from POSITION_LOOKUP; use _unit_pos live reads.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; needle='(?m)^(?!\s*--).*:local_player\(\)'; literal=$false; polarity='absent'; issueRef='#508'; note='dh must call local_player_safe(), never bare :local_player() (pre-game assert); comment mention allowed.' }

    # -- item 2: #139 aid veto = the contiguous conjunction, gated by the master
    #    (bot behavior improvements) + sub (aid priority) toggles.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='_gt_aid_priority_on() and _gt_any_side_teammate_needs_aid'; literal=$true; polarity='present'; issueRef='#139'; note='the aid-veto conjunction must stay contiguous (all bots converge on a downed ally).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='gt_bot_behavior_improvements'; literal=$true; polarity='present'; issueRef='#139'; note='master toggle that gates the aid-priority behavior.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='gt_bot_aid_priority'; literal=$true; polarity='present'; issueRef='#139'; note='sub toggle for the aid-priority behavior.' }

    # -- item 3: the aid scan is SIDE-scoped (reads side.PLAYER_UNITS), not
    #    follow-scoped (the #139 root cause). The "no follow" half was body-scoped
    #    in-game and cannot be expressed at file scope; adapted to the distinctive
    #    side-scoped read that proves the scoping.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='local punits = side and side.PLAYER_UNITS'; literal=$true; polarity='present'; issueRef='#139'; note='aid scan iterates side.PLAYER_UNITS (side-scoped), not the bot follow target.' }

    # -- item 4: #492 picker/veto wiring - suppress-pick flag + bailout veto.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='mod._gt492_should_suppress_pick'; literal=$true; polarity='present'; issueRef='#492'; note='aid-pursuit picker suppression hook must stay wired.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='not blackboard._gt492_bailout'; literal=$true; polarity='present'; issueRef='#492'; note='aid veto must respect the #492 bailout latch.' }

    # -- item 5: #383 split-branch follow_position writes still guard hold_position.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='_gt_fan_points_for_unit(self, nav_world, human'; literal=$true; polarity='present'; issueRef='#383'; note='FIX 9 fan-point follow spread must stay wired.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='group[k]].follow_position = p'; literal=$true; polarity='present'; issueRef='#383'; note='the split branch must write follow_position.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='not data.hold_position'; literal=$true; polarity='present'; issueRef='#383'; note='FIX 9 split branch must keep the hold_position guard.' }

    # -- item 6: #261 tighter-leash slider read + FIX 10 follow-range gates +
    #    improved-combat chase cap / path gate.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='gt_bot_follow_distance_m'; literal=$true; polarity='present'; issueRef='#261'; note='tighter-leash follow-distance slider read.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='allowed_to_take_health_pickup'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 greedy-pickup post-pass gate.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='max_pickup_range'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 pickup follow-range gate reference.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='max_pickup_dist_sq'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 pickup follow-range gate reference.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_improved_bot_combat.lua'; needle='CHASE_MAX_DIST_SQ'; literal=$true; polarity='present'; issueRef='#261'; note='improved-combat chase-distance cap.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_improved_bot_combat.lua'; needle='_enemy_path_allowed'; literal=$true; polarity='present'; issueRef='#261'; note='improved-combat enemy-path gate.' }

    # -- item 7: #142 the backward-teleport want is computed (ordering vs the aid
    #    veto is body-scoped; presence of both patterns is asserted, the veto
    #    conjunction under item 2).
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='want = _gt_backward_teleport_wants(blackboard)'; literal=$true; polarity='present'; issueRef='#142'; note='backward-teleport want must be computed before the aid veto (order body-scoped; presence asserted).' }

    # -- item 8: dev-tools sed-safe stream gate - the concatenated get_mod form so a
    #    promotion sed cannot silently rewrite it to the stable id.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev_data.lua'; needle='get_mod("gt" .. "_dev")'; literal=$true; polarity='present'; issueRef='#511'; note='dev-tools visibility gate uses the split "gt".."_dev" form (sed-safe).' }

    # -- item 9: _gt_bot_teleport_lab.lua identity/telemetry tags.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='running_nodes'; literal=$true; polarity='present'; issueRef='#511'; note='btlab behavior-tree running-nodes read.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='gt_devtools_bot_hud'; literal=$true; polarity='present'; issueRef='#511'; note='btlab dev-tools bot HUD toggle.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='[gt:btlab:breach]'; literal=$true; polarity='present'; issueRef='#511'; note='btlab breach telemetry prefix.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='[gt:btlab:tether]'; literal=$true; polarity='present'; issueRef='#511'; note='btlab tether telemetry prefix.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='if not IS_DEV_STREAM then return end'; literal=$true; polarity='present'; issueRef='#511'; note='btlab is dev-stream gated (inert in stable).' }

    # -- item 10: btlab installs ZERO class hooks (it drives via existing seams).
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='mod:hook(_safe)?\('; literal=$false; polarity='absent'; issueRef='#511'; note='btlab must register no mod:hook / mod:hook_safe.' }

    # -- item 11: btlab GUI creation is pre-filtered by can_get (the #293/#295
    #    create_screen_gui C-fatal guard).
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='can_get("material", GUI_MTRL)'; literal=$true; polarity='present'; issueRef='#293'; note='create_screen_gui pre-filtered by can_get (missing-material C-fatal guard).' }

    # -- item 12: #459 cached-LineObject cleanup is world-liveness gated (live == w)
    #    at BOTH sites (btlab + dh).
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; needle='if live == w then'; literal=$true; polarity='present'; issueRef='#459'; note='LineObject cleanup guarded by a live-world identity check (dead-world AV).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; needle='if live == w then'; literal=$true; polarity='present'; issueRef='#459'; note='LineObject cleanup guarded by a live-world identity check (dead-world AV).' }

    # -- item 13: #448 downed-bot Morrs-Protection gate - attribution + knocked-down.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='granted.attacker_unit == owner_unit'; literal=$true; polarity='present'; issueRef='#448'; note='#448 gate: only the owner-attributed grant, not any attacker.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='is_knocked_down'; literal=$true; polarity='present'; issueRef='#448'; note='#448 gate: a knocked-down bot must stop granting protection.' }

    # -- item 14: #62 the crash-prone IngameUI.handle_menu_hotkeys hook must NOT
    #    be reintroduced in the entry file.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua'; needle='mod:hook("IngameUI", "handle_menu_hotkeys"'; literal=$true; polarity='absent'; issueRef='#62'; note='the IngameUI handle_menu_hotkeys hook must never come back (mid-mission hotkey CTD).' }

    # -- item 15: #73 AI-takeover swaps locomotion override to the bot and back.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_ai_takeover.lua'; needle='locomotion_system:set_override_player(bot_player)'; literal=$true; polarity='present'; issueRef='#73'; note='swap-to-bot path sets the locomotion override player.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_ai_takeover.lua'; needle='locomotion_system:set_override_player(nil)'; literal=$true; polarity='present'; issueRef='#73'; note='swap-back path clears the locomotion override player.' }

    # ============================ ct_dev ============================
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.245-dev (issue 511 item).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='local spawned, go_id = func('; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook captures BOTH vanilla returns (linked-pickup client sync).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='return spawned, go_id'; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook re-returns BOTH values (multi-return collapse guard).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='saved_grenade_weights = {}'; literal=$true; polarity='present'; issueRef='#143'; note='Morgrim grenade-weight renorm fix keeps the saved-weights table.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='key == "description_deus_crit_chain_lightning"'; literal=$true; polarity='present'; issueRef='#133'; note='Manann tempest-trait cooldown-note Localize branch key.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_boon_scroll_setup(self, boon_widgets, 4)'; literal=$true; polarity='present'; issueRef='#115'; note='boon-offer scrollbar wired on the boon-widgets surface (4).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_boon_scroll_setup(self, self._power_up_widgets, 3)'; literal=$true; polarity='present'; issueRef='#114'; note='boon-offer scrollbar wired on the power-up-widgets surface (3).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_force_finale_god(result[1], config)'; literal=$true; polarity='present'; minCount=2; issueRef='#145'; note='force-finale-god wired at BOTH deus_populate_graph branches (>= 2 call sites).' }

    # ============================ gut_dev ============================
    # Source: gui_tweaker_dev/CHANGELOG.md 0.2.220-dev (issue 511). The two
    # source-only checks: mission_map_preview_backdrop (#336) reads _gt module the
    # mission-map file; cutscene_postskip_fade_swallow (#140).
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='resource_packages/levels/ui_inventory_preview'; literal=$true; polarity='present'; issueRef='#336'; note='mission-map preview-stage package path (backdrop load).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='_kick_preview_pkg_load'; literal=$true; polarity='present'; issueRef='#336'; note='async preview-package load kick.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='has_loaded(PREVIEW_PKG, MM_PKG_REF)'; literal=$true; polarity='present'; issueRef='#336'; note='def-swap gated on has_loaded (ungated mount = C-fatal, v0.2.190 lesson).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='level_name = PREVIEW_LEVEL'; literal=$true; polarity='present'; issueRef='#336'; note='tier-2 def mounts the preview level (backdrop present).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua'; needle='_skipped_cutscene_system == self and name == "fx_fade"'; literal=$true; polarity='present'; issueRef='#140'; note='post-skip fx_fade swallow guard (stray black fade on A Parting of the Waves).' }

    # ============================ cim_dev ============================
    # Source: crafting_in_modded_dev/CHANGELOG.md 0.8.57-dev (issue 511). The two
    # hook-registration checks whose source-text needles skip in retail.
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='BackendInterfaceWeavesPlayFab", "get_talent_required_forge_level"'; literal=$true; polarity='present'; issueRef='#71'; note='amulet/weave-properties crash guard hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='"HeroWindowWeaveProperties", "_populate_menu_option_widget"'; literal=$true; polarity='present'; issueRef='#239'; note='weave-forge cost-hide hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='widget.content.price_text = ""'; literal=$true; polarity='present'; issueRef='#239'; note='the price_text blank in the cost-hide hook (Cost:0 clutter removal).' }

    # ============================ WOC ============================
    # Source: weapons_of_chaos/CHANGELOG.md 0.1.10-dev (issue 511).
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='mod:hook(LoadoutUtils, "sync_loadout_slot"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#422'; note='wire-safety sender hook is a SINGLETON (VMF drops a 2nd; non-WOC peers CTD if 0).' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='key:sub(1, 4) ~= "woc_"'; literal=$true; polarity='present'; issueRef='#422'; note='wire guard keys off an unconditional woc_ prefix, not a mod:get toggle.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='Managers.package:load('; literal=$true; polarity='absent'; issueRef='#509'; note='WOC force-loads NOTHING: a raw package force-load on a unit path is a keep-entry C-fatal.' }

    # ============================ dcp ============================
    # Source: dynamic_cosmetic_portraits/CHANGELOG.md 0.1.18-dev (issue 511).
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_skin_portrait_map[skin_key]'; literal=$true; polarity='present'; issueRef='#511'; note='skin lookup precedes hat lookup (an outfit overrides the hat portrait).' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_hat_portrait_map[hat_key]'; literal=$true; polarity='present'; issueRef='#511'; note='hat lookup is the fallback after the skin lookup.' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_original_portrait_image = career.portrait_image'; literal=$true; polarity='present'; issueRef='#509'; note='save-before-swap: capture the vanilla portrait before overwriting (restore on unload).' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='career.portrait_image = _original_portrait_image'; literal=$true; polarity='present'; issueRef='#509'; note='restore writes the saved original back (no swapped portrait leak into non-dcp sessions).' }

  )
}
