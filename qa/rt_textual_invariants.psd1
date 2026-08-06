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

    # Issue #72 / F4-half: GT is the sole consumer of its enriched failed-join
    # popup. Assigning that id to StateLoading revives the consume-once race.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_lobby_failed_join_reveal.lua'; needle='(?m)^(?!\s*--).*\b(?:self|state_loading_self)\._popup_id\s*='; literal=$false; polarity='absent'; issueRef='#72'; note='enriched popup id must stay in GT pending registry; StateLoading ownership creates a double-consume hang.' }

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

    # -- item 3: the aid scan is SIDE-scoped (reads side:player_units()), not
    #    follow-scoped (the #139 root cause). The "no follow" half was body-scoped
    #    in-game and cannot be expressed at file scope; adapted to the distinctive
    #    side-scoped read that proves the scoping.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='local punits = side and side.player_units and side:player_units()'; literal=$true; polarity='present'; issueRef='#139'; note='aid scan iterates the unfiltered side player roster (side-scoped), not the bot follow target.' }

    # -- item 4: #492 picker/veto wiring - suppress-pick flag + bailout veto.
    #    v0.2.250-dev (#384): the veto no longer reads the bare latch; it computes
    #    bail_release from the latch + the stamped bail REASON + the errand pin, so
    #    a no-path bail releases while a no-progress bail holds a live errand.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='mod._gt492_should_suppress_pick'; literal=$true; polarity='present'; issueRef='#492'; note='aid-pursuit picker suppression hook must stay wired.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='bail_release = blackboard._gt492_bailout'; literal=$true; polarity='present'; issueRef='#492'; note='aid veto must still consume the #492 bailout latch (now via the bail_release discrimination).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='blackboard._gt492_bailout_reason ~= "no-progress"'; literal=$true; polarity='present'; issueRef='#384'; note='bail release must discriminate no-path (release) from no-progress (hold while the errand pin is live).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='not _gt384_pin_live(blackboard)'; literal=$true; polarity='present'; issueRef='#384'; note='a no-progress bail may release the veto only when no errand pin is live.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='blackboard._gt492_bailout_reason = reason'; literal=$true; polarity='present'; issueRef='#384'; note='the #492 watchdog must stamp WHICH signal bailed (no-path vs no-progress).' }

    # -- item 5: #383 split-branch follow_position writes still guard hold_position.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='_gt_fan_points_for_unit(self, nav_world, human'; literal=$true; polarity='present'; issueRef='#383'; note='FIX 9 fan-point follow spread must stay wired.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='group[k]].follow_position = p'; literal=$true; polarity='present'; issueRef='#383'; note='the split branch must write follow_position.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='not data.hold_position'; literal=$true; polarity='present'; issueRef='#383'; note='FIX 9 split branch must keep the hold_position guard.' }

    # -- item 6: #261 tighter-leash slider read + FIX 10 follow-range gates +
    #    improved-combat chase cap / path gate.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='gt_bot_follow_distance_m'; literal=$true; polarity='present'; issueRef='#261'; note='tighter-leash follow-distance slider read.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'; needle='allowed_to_take_health_pickup'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 greedy-pickup post-pass gate.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'; needle='max_pickup_range'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 pickup follow-range gate reference.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'; needle='max_pickup_dist_sq'; literal=$true; polarity='present'; issueRef='#261'; note='FIX 10 pickup follow-range gate reference.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_improved_bot_combat.lua'; needle='_distance_sq("gt_ibc_special_chase_distance", math.sqrt(50))'; literal=$true; polarity='present'; issueRef='#261'; note='improved-combat chase-distance cap is sourced from the live bounded setting.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_improved_bot_combat.lua'; needle='_enemy_path_allowed'; literal=$true; polarity='present'; issueRef='#261'; note='improved-combat enemy-path gate.' }

    # -- item 6b: #364 reserves only Bardin's exact Survival Ale pickup identity.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'; needle='return pickup_name == "bardin_survival_ale"'; literal=$true; polarity='present'; issueRef='#364'; note='bot reservation must remain exact-name scoped, not exclude every level-event pickup.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_consumables.lua'; needle='mod._gt_bot_pickup_is_reserved(mule_pickup)'; literal=$true; polarity='present'; issueRef='#364'; note='instant-pickup path must honor the shared Survival Ale reservation.' }

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

    # -- item 15: #247 supersedes #73 by retaining the human Player.  The old
    #    locomotion override and identity-destructive operations must stay gone.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_ai_takeover.lua'; needle='gt-247-keep-slot-v1'; literal=$true; polarity='present'; issueRef='#247'; note='keep-slot takeover marker remains present.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_ai_takeover.lua'; needle='remove_peer_from_party|unassign_profiles_of_peer|set_override_player'; literal=$false; polarity='absent'; issueRef='#247'; note='retired owner-destructive takeover operations remain absent.' }

    # -- #300: the four [gt:bot-rescue] evidence lines must emit via engine
    #    printf (pcall-guarded), never mod:debug -- the reporting user config
    #    drops the [DEBUG] channel entirely (1931 [INFO] lines, zero [DEBUG]
    #    in the newest log), so mod:debug evidence never lands in the console
    #    log the pinned card reads. Runtime twin: the io-nil note inside
    #    issue300_rescue_awaiting_range_policy (_gt_regression_checks.lua).
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='pcall(printf, "[gt:bot-rescue]'; literal=$true; polarity='present'; minCount=4; issueRef='#300'; note='all four bot-rescue evidence lines route through pcall(printf, ...) (visible with mod logging OFF).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='mod:debug("[gt:bot-rescue]'; literal=$true; polarity='absent'; issueRef='#300'; note='no bot-rescue evidence line may regress to the invisible mod:debug channel.' }

    # ============================ wt ============================
    # #218: the CW trait widget groups were removed in a7012f3. Keep the stale
    # CIM strip/detection scaffold absent, while preserving three hidden,
    # default-true feature-flag labels that runtime code still reads.
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua'; needle='_has_cim|_cim_gated_groups|_strip_cim_widgets|cw_(?:melee|ranged)_traits'; literal=$false; polarity='absent'; issueRef='#218'; note='removed CW-trait widget groups must not regain their dead CIM detection/strip scaffold.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_backend_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true backend hook flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_ui_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true UI hook flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_animation_redirects ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true animation redirect flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua'; needle='for source, target in pairs(_3p_remap_billhook_to_polearm) do'; literal=$true; polarity='present'; issueRef='#290'; note='Billhook bake merges the complete receiver safety map before overlaying picks.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_anim_remap.lua'; needle='[wt:290] weapon=wh_2h_billhook'; literal=$true; polarity='present'; issueRef='#290'; note='friends-only bounded automatic diagnostic identifies the next actual Kruber Billhook attack.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='mod._wt.build_3p_template_remaps = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap_data")'; literal=$true; polarity='present'; issueRef='#2'; note='the manifest loads the split template catalog builder exactly once before the event-hot dispatch module.' }

    # ============================ ct_dev ============================
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.245-dev (issue 511 item).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='local spawned, go_id = func('; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook captures BOTH vanilla returns (linked-pickup client sync).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='return spawned, go_id'; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook re-returns BOTH values (multi-return collapse guard).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='saved_grenade_weights = {}'; literal=$true; polarity='present'; issueRef='#143'; note='Morgrim grenade-weight renorm fix keeps the saved-weights table.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='key == "description_deus_crit_chain_lightning"'; literal=$true; polarity='present'; issueRef='#133'; note='Manann tempest-trait cooldown-note Localize branch key.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_boon_scroll_setup(self, boon_widgets, 4)'; literal=$true; polarity='present'; issueRef='#115'; note='boon-offer scrollbar wired on the boon-widgets surface (4).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_boon_scroll_setup(self, self._power_up_widgets, 3)'; literal=$true; polarity='present'; issueRef='#114'; note='boon-offer scrollbar wired on the power-up-widgets surface (3).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_force_finale_god(result[1], config)'; literal=$true; polarity='present'; minCount=2; issueRef='#145'; note='force-finale-god wired at BOTH deus_populate_graph branches (>= 2 call sites).' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.298-dev (fable-fix-wave clusters).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua'; needle='buff_system:add_buff(unit, stack_name, unit, true)'; literal=$true; polarity='present'; issueRef='#249'; note='meta-boon stack grant is server-controlled (replicates to clients; issue 289 evidence).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua'; needle='CT_META_AMMO_SERVER_AUTH_MARKER = AmmoGuardCore.MARKER'; literal=$true; polarity='present'; issueRef='#249'; note='server-authoritative grant marker sourced from the pure kernel.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua'; needle='AmmoGuardCore.clamp_value(max_ammo, ax._available_ammo)'; literal=$true; polarity='present'; issueRef='#256'; note='issue 256 clamp routes through the offline-tested pure kernel.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'; needle='M.RECONCILE_MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298"'; literal=$true; polarity='present'; issueRef='#132'; note='settled cross-path chest reconcile (prune side) present.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'; needle='Managers.state.unit_spawner:mark_for_deletion(u)'; literal=$true; polarity='present'; issueRef='#132'; note='prune uses the engine pickup delete path (pickup_system.lua:1451-1455).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool.lua'; needle='"normal", "hard", "harder", "hardest", "cataclysm", "cataclysm_2", "cataclysm_3"'; literal=$true; polarity='present'; issueRef='#251'; note='injected pickup_settings cover every reachable difficulty key (no engine fallback).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'; needle='multiplier  = -0.5'; literal=$true; polarity='present'; issueRef='#464'; note='Anath Raema permanent reload buff stays NEGATIVE (reload_speed is inverse).' }

    # ============================ gut_dev ============================
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua'; needle='backend_id:match("^cwv_.+_%d%d%d$")'; literal=$true; polarity='present'; issueRef='#287'; note='readonly overlay accepts only exact CWV backend-instance identity.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua'; needle='Policy.readonly_action(slot, v) == "preserve"'; literal=$true; polarity='present'; issueRef='#287'; note='whole-loadout reads use the same mod-owned predicate as single-slot reads/writes.' }
    # Source: gui_tweaker_dev/CHANGELOG.md 0.2.220-dev (issue 511). The two
    # source-only checks: mission_map_preview_backdrop (#336) reads _gt module the
    # mission-map file; cutscene_postskip_fade_swallow (#140).
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='resource_packages/levels/ui_inventory_preview'; literal=$true; polarity='present'; issueRef='#336'; note='mission-map preview-stage package path (backdrop load).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='_kick_preview_pkg_load'; literal=$true; polarity='present'; issueRef='#336'; note='async preview-package load kick.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='has_loaded(PREVIEW_PKG, MM_PKG_REF)'; literal=$true; polarity='present'; issueRef='#336'; note='def-swap gated on has_loaded (ungated mount = C-fatal, v0.2.190 lesson).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_map.lua'; needle='level_name = PREVIEW_LEVEL'; literal=$true; polarity='present'; issueRef='#336'; note='tier-2 def mounts the preview level (backdrop present).' }
    # -- #140/#257/#274 ROUND 3 (0.2.294-dev): the fixed-order guard expression
    #    was replaced by the per-episode order-independent skip window
    #    (_gut_cutscene_skipwindow.lua). Pin the classification sites + the
    #    intro-only skip policy that the rework must preserve (issue 275).
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua'; needle='_gut_cutscene_fade_swallow_site'; literal=$true; polarity='present'; issueRef='#140'; note='fx_fade swallow classification site marker (stray black fade on A Parting of the Waves; ROUND 3 rework).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua'; needle='_skipwindow.classify_fade(_sw_state, self, pending, auto, _sw_now)'; literal=$true; polarity='present'; issueRef='#257'; note='order-independent fade classification against the per-system cutscene episode (pending/window/intro-watch).' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua'; needle='_skipwindow.classify_camera(_sw_state, self, self.event_on_skip, _sw_now)'; literal=$true; polarity='present'; issueRef='#274'; note='camera activations classify per episode with identity-based release; a legitimate later cutscene must pass.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_policy274.lua'; needle='M.INTRO_SKIP_EVENT = "cs_01_skip"'; literal=$true; polarity='present'; issueRef='#274'; note='issue 275/274 skip policy: only the authored mission-intro event is skippable; nil on_skip never skips (boss desync guard).' }

    # -- #517: retail exposes no arbitrary file-read channel. Keep the useful
    #    settings export, but never resurrect the nonfunctional read/apply half.
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_config_file.lua'; needle='mod:command("reload_config"'; literal=$true; polarity='absent'; issueRef='#517'; note='retail cannot read the TOML; do not advertise a reload command that always no-ops.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_config_file.lua'; needle='io_open('; literal=$true; polarity='absent'; issueRef='#517'; note='the impossible retail file-read/apply half remains retired; export is log-only.' }

    # -- #530: the in-mission tab strip is Adventure-only. Holseher's Map
    #    (dlc_morris_map) opens hero_view NATIVELY, so the HeroWindowPanelConsole
    #    on_enter hook must suspend on mechanism "deus" or the strip (incl. the
    #    Crafting tab) un-gates across the whole CW run. Fixed gut_dev 0.2.223-dev.
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_inventory.lua'; needle='[gut:530] in-mission tab strip suspended'; literal=$true; polarity='present'; issueRef='#530'; note='deus suspend evidence line: on_enter must bail before un-gating the strip in a CW run.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_inventory.lua'; needle='if mech == "deus" then'; literal=$true; polarity='present'; issueRef='#530'; note='mechanism gate ahead of the is_in_inn flip (Holseher''s Map opens hero_view natively).' }

    # -- #575: pure tests lock geometry; both live presentations must retain
    #    click-to-nearest-measured-boundary wiring and native scaled metrics.
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions.lua'; needle='pcall(UIFontByResolution, value_style)'; literal=$true; polarity='present'; issueRef='#575'; note='numeric caret measures with the native resolution-scaled font contract.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions.lua'; needle='scaled_size, value_style.font_type'; literal=$true; polarity='present'; issueRef='#575'; note='UIRenderer.text_size receives the authored font identity; material-only proxy widths drift.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view_interaction.lua'; needle='pcall(defs.numeric_caret_index'; literal=$true; polarity='present'; minCount=2; issueRef='#575'; note='standalone interaction owner wires measured placement at initial and active-field clicks.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state_interaction.lua'; needle='pcall(defs.numeric_caret_index'; literal=$true; polarity='present'; minCount=2; issueRef='#575'; note='state interaction owner wires measured placement at initial and active-field clicks.' }

    # -- #574: exact variant persistence plus bounded hot-join convergence.
    #    Behavioral runtime checks exercise matching; these source gates retain
    #    the durable identity and no-network-retry lifecycle at ship time.
    # #48: the exact-instance key builder moved into the shared policy module so
    # the picker and the renderer cannot drift apart. Same invariant, new owner,
    # plus a gate proving the picker delegates instead of re-deriving.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy.lua'; needle='return string.format("backend:%s|skin:%s", tostring(backend_id), tostring(skin or ""))'; literal=$true; polarity='present'; issueRef='#574'; note='per-item glow identity cannot collapse distinct inventory instances or illusions.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua'; needle='return INSTANCE_POLICY.identity_key(backend_id, slot_data)'; literal=$true; polarity='present'; issueRef='#48'; note='the picker delegates exact-instance identity to the shared policy module.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy.lua'; needle='if expected_skin == nil then return false end'; literal=$true; polarity='present'; issueRef='#48'; note='an unconstrained peer payload fails closed instead of matching every glow-capable unit on the wearer.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua'; needle='if not GlowPicker._open or not GlowPicker._dirty then return false end'; literal=$true; polarity='present'; issueRef='#574'; note='Apply remains the sole dirty transaction and repeated Apply stays a no-op.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='state_pull = "piggyback_cos_la_state_req"'; literal=$true; polarity='present'; issueRef='#574'; note='join recovery reuses the acknowledged post-ingame state pull.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='retry_network = false'; literal=$true; polarity='present'; issueRef='#574'; note='the bounded join retry repaints locally and cannot create an RPC stream.' }

    # -- #697: a genuine LA-hat husk paint failure must NAME the hat through the
    #    printf-backed _dbg_alert channel. The key-bearing _dbg line beside it is
    #    mod:debug (invisible with mod logging OFF), so without the key on the
    #    alert line a residual failure stays anonymous.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='_dbg_alert("[husk-hat-create] paint err key=%s vanilla=%s: %s"'; literal=$true; polarity='present'; issueRef='#697'; note='the husk-hat paint failure line carries the armoury key + vanilla variant on the visible alert channel.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='if not pcall(printf, "[cosmetics:dbg] " .. fmt, ...) then'; literal=$true; polarity='present'; issueRef='#697'; note='_dbg_alert stays printf-backed (lands in console log with mod logging OFF); rerouting it blinds every alert.' }

    # ============================ cim_dev ============================
    # Source: crafting_in_modded_dev/CHANGELOG.md 0.8.57-dev (issue 511). The two
    # hook-registration checks whose source-text needles skip in retail.
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='BackendInterfaceWeavesPlayFab", "get_talent_required_forge_level"'; literal=$true; polarity='present'; issueRef='#71'; note='amulet/weave-properties crash guard hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='"HeroWindowWeaveProperties", "_populate_menu_option_widget"'; literal=$true; polarity='present'; issueRef='#239'; note='extracted weave-forge cost-hide hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='widget.content.price_text = ""'; literal=$true; polarity='present'; issueRef='#239'; note='the extracted cost-hide adapter must blank the Cost:0 label.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='price_icon.color[1] = 0'; literal=$true; polarity='present'; issueRef='#239'; note='the extracted cost-hide adapter must also hide the separate price icon.' }

    # ============================ mp ============================
    # #589: un-gating StoreLoginRewardsPopup without owning the authenticated
    # claimStoreRewards request forced modded players out via EAC/backend 511.
    @{ mod='mp'; file='modded_progression/scripts/mods/modded_progression/modded_progression.lua'; needle='mod:hook("StoreLoginRewardsPopup", "_claim_rewards"'; literal=$true; polarity='present'; issueRef='#589'; note='UI claim action is intercepted before it enters the backend-wait state.' }
    @{ mod='mp'; file='modded_progression/scripts/mods/modded_progression/modded_progression.lua'; needle='mod:hook("BackendInterfacePeddlerPlayFab", "claim_login_rewards"'; literal=$true; polarity='present'; issueRef='#589'; note='request-boundary guard prevents every modded caller from enqueueing claimStoreRewards.' }

    # ============================ WOC ============================
    # Source: weapons_of_chaos/CHANGELOG.md 0.1.10-dev (issue 511).
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='mod:hook(LoadoutUtils, "sync_loadout_slot"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#422'; note='wire-safety sender hook is a SINGLETON (VMF drops a 2nd; non-WOC peers CTD if 0).' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_wire_policy.lua'; needle='key:sub(1, 4) == "woc_"'; literal=$true; polarity='present'; issueRef='#422'; note='wire-policy owner keys off an unconditional woc_ prefix, not a mod:get toggle.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='Managers.package:load('; literal=$true; polarity='absent'; issueRef='#509'; note='WOC force-loads NOTHING: a raw package force-load on a unit path is a keep-entry C-fatal.' }

    # ============================ dcp ============================
    # Source: dynamic_cosmetic_portraits/CHANGELOG.md 0.1.18-dev (issue 511).
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_skin_portrait_map[skin_key]'; literal=$true; polarity='present'; issueRef='#511'; note='skin lookup precedes hat lookup (an outfit overrides the hat portrait).' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_hat_portrait_map[hat_key]'; literal=$true; polarity='present'; issueRef='#511'; note='hat lookup is the fallback after the skin lookup.' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='_original_portrait_image = career.portrait_image'; literal=$true; polarity='present'; issueRef='#509'; note='save-before-swap: capture the vanilla portrait before overwriting (restore on unload).' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='career.portrait_image = _original_portrait_image'; literal=$true; polarity='present'; issueRef='#509'; note='restore writes the saved original back (no swapped portrait leak into non-dcp sessions).' }

    # -- #526: hud-size portrait alpha must conform to the vanilla octagonal
    #    silhouette or portraits bleed outside the frame on the mission-
    #    completion score screen. Texture alpha is not lint-able, so the lock
    #    is on the pipeline gate in add_portrait.ps1 (canonical mask reference
    #    + conformance check). Fixed dcp 0.1.20-dev.
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/tools/add_portrait.ps1'; needle='vanilla_hud_alpha_mask_86x108.png'; literal=$true; polarity='present'; issueRef='#526'; note='add_portrait.ps1 must reference the canonical vanilla hud silhouette mask.' }
    @{ mod='dcp'; file='dynamic_cosmetic_portraits/tools/add_portrait.ps1'; needle='silhouette conformance'; literal=$true; polarity='present'; issueRef='#526'; note='the HUD silhouette conformance gate (opaque-outside-mask => throw) must stay in the pipeline.' }

    # =========================================================================
    #  SOURCE-ANCHOR BUG_CLASSES executable twins (added 2026-07-18)
    #  Each needle below locks the concrete hook edge / API / helper named in a
    #  docs/BUG_CLASSES.md fix template, for a class that its own text records as
    #  having BURNED TWICE OR MORE. If the documented pattern disappears from the
    #  cited source file, the needle FAILS (blocking), so a guard doc and its live
    #  source can never silently diverge. Section numbers reference
    #  docs/BUG_CLASSES.md; issueRef 'BC<n>' marks a class with no single GH issue.
    # =========================================================================

    # -- BUG_CLASSES 35: MH donor packages back native renderer consumers whose
    #    lifetime has no proven Lua teardown boundary. Fatal #927/#937/#940 all
    #    reached the old post-StateIngame release-complete/postcondition-ok state
    #    before PatchedResourcePackage stalled. Any StateIngame manual-release hook
    #    re-opens #282; one bounded process-session ref is released only by
    #    PackageManager.destroy.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook_safe("StateIngame", "on_exit"'; literal=$true; polarity='absent'; issueRef='#282'; note='BUG_CLASSES 35: no StateIngame callback may manually release the renderer-backed MH donor graph.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle.lua'; needle='mod:hook_safe("StateIngame", "on_exit"'; literal=$true; polarity='absent'; issueRef='#282'; note='BUG_CLASSES 35: the extracted lifecycle owner adds no StateIngame hook or renderer-backed MH release.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle.lua'; needle='teardown_owner=PackageManager.destroy'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#282'; note='BUG_CLASSES 35: transition diagnostics preserve bounded session ownership without mutating package state.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'; needle='manager_package(?:\.|:)unload'; literal=$false; polarity='absent'; issueRef='#282'; note='BUG_CLASSES 35: the MH embed exposes no direct manual unload seam; PackageManager.destroy is the sole release owner.' }
    # -- BUG_CLASSES 35: the force-load reference name must be mod-owned
    #    ("cosmetics_tweaker_mh"), never the shared "global" ref no consumer can
    #    safely unload.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'; needle='MH_PKG_REF = "cosmetics_tweaker_mh"'; literal=$true; polarity='present'; issueRef='#282'; note='BUG_CLASSES 35: MH session ownership uses a mod-owned reference name, not the shared "global" refcount.' }

    # -- BUG_CLASSES 3: Lua 5.1 unpack nil-hole truncation. safe_hook MUST pass an
    #    explicit j to unpack so nil holes survive. Burned wt v0.12.77 -> .78
    #    (unpack(results, 2) with no j, still broken) -> .79 (unpack(results, 2, n)).
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua'; needle='return unpack(results, 2, n)'; literal=$true; polarity='present'; issueRef='#36'; note='BUG_CLASSES 3: safe_hook returns unpack(results, 2, n) with the explicit j; dropping n reintroduces the non-deterministic #table truncation.' }

    # -- BUG_CLASSES 19: hooked networked fn drops a trailing sync param -> RPC loop.
    #    The AnimationSystem.anim_event_with_variable_float hook MUST name skip_sync in
    #    BOTH its signature AND the func() forward, or husk replays re-broadcast and
    #    every player's 3P anim loops in a 2+ human game. Burned wt v0.12.128 -> .132.
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='variable_value, skip_sync)'; literal=$true; polarity='present'; minCount=2; issueRef='BC19'; note='BUG_CLASSES 19: skip_sync threaded through the anim_event_with_variable_float hook signature AND the func() forward (>=2 occurrences); dropping either re-arms the anim-event RPC feedback loop. Memory reference_vmf_hook_drops_skip_sync_rpc_loop.' }

    # -- BUG_CLASSES 27: husk resolves the BASE item_data. Husk fixes must live on the
    #    husk-reachable paths - the SimpleHuskInventoryExtension.start_weapon_fx crash
    #    floor (issue 280) and the GearUtils.spawn_inventory_unit block gated on
    #    `not owner_unit_1p`. An owner-only (create_equipment) fix never reaches a husk.
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'; needle='mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'; literal=$true; polarity='present'; issueRef='#280'; note='BUG_CLASSES 27: durable husk start_weapon_fx nil-slot crash floor (non-source-character client CTD).' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'; needle='if not owner_unit_1p and'; literal=$true; polarity='present'; issueRef='#392'; note='BUG_CLASSES 27: the spawn_inventory_unit husk branch is gated on the no-1P-rig discriminator (v0.1.461 husk adapter added a second conjunct); removing it strands every husk-side transform/strip fix.' }

    # -- BUG_CLASSES 29: client-side buff proc calls the server-only heal_network. The
    #    Fires-from-Ash THP heal MUST sit behind the Managers.player.is_server gate or
    #    a client hard-CTDs on the "Only server can heal" fassert. Burned crt (#405)
    #    and ct (#406) the same day. The regex requires the gate to immediately
    #    precede the heal call.
    @{ mod='crt'; file='career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'; needle='is_server\) then return end\s+if DamageUtils and DamageUtils\.heal_network'; literal=$false; polarity='present'; issueRef='#405'; note='BUG_CLASSES 29: heal_network stays behind the Managers.player.is_server gate; ungating CTDs clients on the server-only heal fassert.' }

    # -- BUG_CLASSES 23: keep-only Gui material drawn mid-mission. The inject-when-
    #    resident guard is ONE consolidated UIRenderer.create hook. Burned pose atlas
    #    (155), store atlas (363), area videos (336). A 2nd hook on the pair is dropped
    #    by VMF (class 1), so it must stay a singleton.
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_gui_material_guard.lua'; needle='mod:hook("UIRenderer", "create"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#336'; note='BUG_CLASSES 23: the keep-only-material inject-when-resident guard is the single consolidated UIRenderer.create hook (one per mod; VMF drops a 2nd).' }

    # -- BUG_CLASSES 31: cross-peer wire crash-safety coupled to a feature toggle. The
    #    modded->vanilla rarity coercion MUST be a PURE helper taking ONLY rarity
    #    (structurally ungateable), called unconditionally on the send path. Burned as
    #    the #278 recurrence when a refactor bundled the safety behind a toggle.
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='local function _cim_wire_safe_rarity(rarity)'; literal=$true; polarity='present'; issueRef='#278'; note='BUG_CLASSES 31: the wire-safe rarity helper takes ONLY rarity (no toggle arg), so it cannot be feature-gated; a 2nd param re-exposes the non-mod-peer CTD.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='if rarity == "modded" then return "unique" end'; literal=$true; polarity='present'; issueRef='#278'; note='BUG_CLASSES 31: the "modded"->"unique" coercion must stay on the sender path; without it a non-mod peer nil-derefs RaritySettings on a vanilla RPC.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='parity:require_peer(peer_id)'; literal=$true; polarity='present'; minCount=2; issueRef='#424'; note='BUG_CLASSES 31: both transient-package loading and pre-GameSession object sync must synchronously disable Tuskgor Javelin behavior.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='_cwv424_actionutils_sender_guard_installed = true'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: the dormant grenade-slot item has a separate ActionUtils lookup encoder that must stay guarded before any future re-enable.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='_cwv424_throw_gate_installed = true'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: already-equipped Tuskgor Javelins must stop before projectile creation when peer capability is unproven.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='if rejected_peers[peer_id] then return false end'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: cleanup failure must hold the joining peer outside GameSession because PeerStates ignores set_peer_synchronizing return values.' }

    # -- BUG_CLASSES 24: PlayerManager.remove_player fires on LEVEL TRANSITIONS. A
    #    per-peer store must NOT purge synchronously in remove_player; the deferred
    #    purge is canceled by the add_remote_player hook_safe (transitions re-add within
    #    seconds, disconnects never do). Losing the cancel wipes every peer's cosmetic
    #    store on every keep<->mission change. Recurs via classes 43 and 61.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook_safe(PlayerManager, "add_remote_player"'; literal=$true; polarity='present'; issueRef='BC24'; note='BUG_CLASSES 24: the add_remote_player hook_safe cancels the deferred peer purge; without it, remove_player-on-transition wipes the per-peer LA store every map change.' }

    # ==================== issue #511: no live io.open in converted surfaces ====================
    # The retail Stingray VM registers no `io` into the shared _G that mods are
    # loadstring'd into (scripts/managers/mod/mod_manager.lua:375; `os` IS present -
    # os.date runs unguarded at :312 - but `io` is not). Every in-game source
    # self-grep therefore threw "attempt to index global 'io'" and FALSE-FAILED
    # healthy code. Issue #511 converted every active-stream runtime check to
    # load-time markers / runtime assertions; these ABSENCE needles forbid a live
    # `io.open(` from re-entering the converted surfaces. Comment-excluding regex:
    # every file documents the io-nil trap in comments. Stable clones
    # (general_tweaker lines 1597/1620/1685/1713) ride promotion and are NOT
    # pinned here - add their needles when the promotion lands the conversion.
    @{ mod='enemy_tweaker'; file='enemy_tweaker/scripts/mods/enemy_tweaker/_et_pacing.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='io is nil in the retail sandbox; the #479 checks assert wrap-registry provenance instead of reading source.' }
    @{ mod='enemy_tweaker'; file='enemy_tweaker/scripts/mods/enemy_tweaker/_et_protect.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='io is nil in the retail sandbox; provenance lives in ET.wrap_registry set at hook install.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='all 22 gt source self-greps were converted (v0.2.202-dev); a live io.open would false-FAIL every /gt_regression_test in retail.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='ct conversion rode 0.7.245-dev; runtime checks must stay marker-based.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_regression.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='ct regression module must stay marker-based; io is nil in the retail sandbox.' }
    @{ mod='gut_dev'; file='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='gut conversion rode 0.2.220-dev; the TOML config READ was a retail-broken feature tracked separately.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='cim conversion rode 0.8.57-dev; runtime checks must stay marker-based.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='WOC conversion rode 0.1.10-dev; runtime checks must stay marker-based.' }
    @{ mod='dynamic_cosmetic_portraits'; file='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; needle='(?m)^(?!\s*--).*\bio\.open\s*\('; literal=$false; polarity='absent'; issueRef='#511'; note='dcp conversion rode 0.1.18-dev; runtime checks must stay marker-based.' }

  )
}
