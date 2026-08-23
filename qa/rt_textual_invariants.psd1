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
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='gt_bot_aid_priority'; literal=$true; polarity='present'; issueRef='#139'; note='the bot-aid owner retains the sub toggle for aid-priority behavior.' }

    # -- item 3: the aid scan is SIDE-scoped (reads side:player_units()), not
    #    follow-scoped (the #139 root cause). The "no follow" half was body-scoped
    #    in-game and cannot be expressed at file scope; adapted to the distinctive
    #    side-scoped read that proves the scoping.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='local punits = side and side.player_units and side:player_units()'; literal=$true; polarity='present'; issueRef='#139'; note='the bot-aid owner scans the unfiltered side player roster (side-scoped), not the bot follow target.' }

    # -- item 4: #492 picker/veto wiring - suppress-pick flag + bailout veto.
    #    v0.2.250-dev (#384): the veto no longer reads the bare latch; it computes
    #    bail_release from the latch + the stamped bail REASON + the errand pin, so
    #    a no-path bail releases while a no-progress bail holds a live errand.
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='mod._gt492_should_suppress_pick'; literal=$true; polarity='present'; issueRef='#492'; note='the bot-aid owner retains the aid-pursuit picker suppression hook.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='bail_release = blackboard._gt492_bailout'; literal=$true; polarity='present'; issueRef='#492'; note='aid veto must still consume the #492 bailout latch (now via the bail_release discrimination).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='blackboard._gt492_bailout_reason ~= "no-progress"'; literal=$true; polarity='present'; issueRef='#384'; note='bail release must discriminate no-path (release) from no-progress (hold while the errand pin is live).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'; needle='not _gt384_pin_live(blackboard)'; literal=$true; polarity='present'; issueRef='#384'; note='a no-progress bail may release the veto only when no errand pin is live.' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='blackboard._gt492_bailout_reason = reason'; literal=$true; polarity='present'; issueRef='#384'; note='the bot-aid watchdog must stamp WHICH signal bailed (no-path vs no-progress).' }

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
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='pcall(printf, "[gt:bot-rescue]'; literal=$true; polarity='present'; minCount=4; issueRef='#300'; note='all four bot-rescue evidence lines in the bot-aid owner route through pcall(printf, ...) (visible with mod logging OFF).' }
    @{ mod='gt_dev'; file='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua'; needle='mod:debug("[gt:bot-rescue]'; literal=$true; polarity='absent'; issueRef='#300'; note='no bot-rescue evidence line may regress to the invisible mod:debug channel.' }

    # ============================ wt ============================
    # #218: the CW trait widget groups were removed in a7012f3. Keep the stale
    # CIM strip/detection scaffold absent, while preserving three hidden,
    # default-true feature-flag labels that runtime code still reads.
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua'; needle='_has_cim|_cim_gated_groups|_strip_cim_widgets|cw_(?:melee|ranged)_traits'; literal=$false; polarity='absent'; issueRef='#218'; note='removed CW-trait widget groups must not regain their dead CIM detection/strip scaffold.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_backend_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true backend hook flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_ui_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true UI hook flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua'; needle='enable_weapon_animation_redirects ='; literal=$true; polarity='present'; issueRef='#218'; note='hidden default-true animation redirect flag still has a label; it is runtime-read despite having no widget.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data.lua'; needle='_has_cim|_cim_gated_groups|_strip_cim_widgets|cw_(?:melee|ranged)_traits'; literal=$false; polarity='absent'; issueRef='#218'; note='the Dev twin must not regain the removed CW-trait widget groups or dead CIM detection/strip scaffold.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_localization.lua'; needle='enable_weapon_backend_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='the Dev twin retains the runtime-backed hidden backend-hook label.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_localization.lua'; needle='enable_weapon_ui_hooks ='; literal=$true; polarity='present'; issueRef='#218'; note='the Dev twin retains the runtime-backed hidden UI-hook label.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_localization.lua'; needle='enable_weapon_animation_redirects ='; literal=$true; polarity='present'; issueRef='#218'; note='the Dev twin retains the runtime-backed hidden animation-redirect label.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua'; needle='for source, target in pairs(_3p_remap_billhook_to_polearm) do'; literal=$true; polarity='present'; issueRef='#290'; note='Billhook bake merges the complete receiver safety map before overlaying picks.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_anim_remap.lua'; needle='[wt:290] weapon=wh_2h_billhook'; literal=$true; polarity='present'; issueRef='#290'; note='friends-only bounded automatic diagnostic identifies the next actual Kruber Billhook attack.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='mod._wt.build_3p_template_remaps = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap_data")'; literal=$true; polarity='present'; issueRef='#2'; note='the manifest loads the split template catalog builder exactly once before the event-hot dispatch module.' }
    # Source: weapon_tweaker/CHANGELOG.md 0.12.299-beta (#1159 Moonfire AOE owner).
    # The #535 registration pair and the impact-hook loop moved verbatim out of
    # both entries into _wt_moonfire_aoe.lua. The needles follow the code, and
    # the paired absent rows keep a duplicate registration out of the entries -
    # VMF silently drops a second hook on the same Class/method pair.
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_moonfire_aoe.lua'; needle='ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE'; literal=$true; polarity='present'; issueRef='#535'; note='the AoE template stays registered for ExplosionUtils.get_template; without it area_damage_system nil-derefs on the buffer drain.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_moonfire_aoe.lua'; needle='rawset(lookup, _MOONFIRE_AOE_NAME, idx)'; literal=$true; polarity='present'; issueRef='#535'; note='forward NetworkLookup.explosion_templates append kept with the code (index determinism across wt peers).' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='local _MOONFIRE_AOE_TEMPLATE'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not re-declare the moved template; a second copy would register a divergent table under the same name.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='mod:hook_safe(cls, method_name,'; literal=$true; polarity='absent'; issueRef='#1159'; note='the projectile-impact hook loop is owned once by _wt_moonfire_aoe.lua; a re-add in the entry is silently dropped by VMF.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_moonfire_aoe.lua'; needle='ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE'; literal=$true; polarity='present'; issueRef='#535'; note='mirror stream carries the identical registration; parity gate rejects any drift between the two owners.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'; needle='mod:hook_safe(cls, method_name,'; literal=$true; polarity='absent'; issueRef='#1159'; note='mirror stream entry must stay free of the moved hook loop for the same VMF cardinality reason.' }
    # Source: weapon_tweaker/CHANGELOG.md 0.12.300-beta (#1159 template-patch +
    # rebalance owners). The cross-character source-template patchers and the
    # three toggle-gated rebalance rewrites moved verbatim out of both entries.
    # The needles follow the code; the paired absent rows keep a second copy out
    # of the entries, which for the two cloned damage profiles would append a
    # duplicate NetworkLookup index and desync the wire (BUG_CLASSES 64).
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_weapon_balance_patches.lua'; needle='rawset(tbl, key, idx)'; literal=$true; polarity='present'; issueRef='#431'; note='wt_authentic_pistol keeps its forward+reverse NetworkLookup.damage_profiles append with the code; without it every networked brace shot fatals on the missing key.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_weapon_balance_patches.lua'; needle='mod._wt431_custom_profile_fallback[key] = "shot_sniper"'; literal=$true; polarity='present'; issueRef='#431'; note='the clone source stays recorded as the wire-safe fallback the send floor coerces back to when a non-wt peer is present.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_weapon_balance_patches.lua'; needle='mod._wt431_custom_profile_fallback[PRIEST_PUNCH_PROFILE] = PRIEST_PUNCH_SRC'; literal=$true; polarity='present'; issueRef='#431'; note='same wire-safe fallback contract for the priest punch clone; the parity gate reads both entries out of this map.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='local function _wt_clone_shot_sniper_no_dropoff'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not re-declare the moved clone; a second registration would append a duplicate damage_profiles index.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'; needle='local function _patch_brace_template_for_kruber'; literal=$true; polarity='absent'; issueRef='#1159'; note='the cross-character source-template patchers are owned once by _wt_cross_char_template_patches.lua.' }
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_char_template_patches.lua'; needle='_3p_template_remaps.longbow_empire_template.wh_'; literal=$true; polarity='present'; issueRef='#210'; note='the longbow crossbow remap stays career-scoped in the runtime funnel; mutating the shared template globally broke Kruber native draw_bow.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_weapon_balance_patches.lua'; needle='mod._wt431_custom_profile_fallback[key] = "shot_sniper"'; literal=$true; polarity='present'; issueRef='#431'; note='mirror stream carries the identical fallback record; the parity gate rejects any drift between the two owners.' }
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'; needle='local function _wt_clone_shot_sniper_no_dropoff'; literal=$true; polarity='absent'; issueRef='#1159'; note='mirror stream entry must stay free of the moved clone for the same NetworkLookup index reason.' }

    # ============================ ct_dev ============================
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.245-dev (issue 511 item).
    # File retargeted by the #1159 pickup-spawn owner extraction: the _spawn_pickup
    # hook moved verbatim out of the entry into _ct_pickup_spawn_owner.lua. The
    # invariant itself is unchanged.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua'; needle='local spawned, go_id = func('; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook captures BOTH vanilla returns (linked-pickup client sync).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua'; needle='return spawned, go_id'; literal=$true; polarity='present'; issueRef='#322'; note='_spawn_pickup hook re-returns BOTH values (multi-return collapse guard).' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.327-dev (#1159 boon-grant owner).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner.lua'; needle='mod:hook("DeusRunController", "add_power_ups"'; literal=$true; polarity='present'; issueRef='#211'; note='universal grant choke point stays a single full hook in the boon-grant owner.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod:hook("DeusRunController", "add_power_ups"'; literal=$true; polarity='absent'; issueRef='#211'; note='a second registration on the pair is silently dropped by VMF; the entry must not re-add it.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner.lua'; needle='_ct_consolidated_try_buy_power_up_hook'; literal=$true; polarity='present'; issueRef='#458'; note='#458/#466/#467 still share ONE _try_buy_power_up hook, now owned here.' }
    # #1159 wave 10: the Morgrim renorm row follows populate_pickups into the
    # pickup-population owner, same literal needle, plus entry-side absence.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner.lua'; needle='saved_grenade_weights = {}'; literal=$true; polarity='present'; issueRef='#143'; note='Morgrim grenade-weight renorm fix keeps the saved-weights table.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='saved_grenade_weights'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry no longer renormalizes the grenade pool; a stray copy would mutate weights nothing restores.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner.lua'; needle='key == "description_deus_crit_chain_lightning"'; literal=$true; polarity='present'; issueRef='#133'; note='Manann tempest-trait cooldown-note Localize branch key remains with adventure presentation.' }
    # #1159 wave 9: the two scrollbar wiring rows follow the code into the
    # boon-offer view owner, same literal needles, plus entry-side absence.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner.lua'; needle='mod._ct_boon_scroll_setup(self, boon_widgets, 4)'; literal=$true; polarity='present'; issueRef='#115'; note='boon-offer scrollbar wired on the boon-widgets surface (4).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner.lua'; needle='mod._ct_boon_scroll_setup(self, self._power_up_widgets, 3)'; literal=$true; polarity='present'; issueRef='#114'; note='boon-offer scrollbar wired on the power-up-widgets surface (3).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_boon_scroll_setup'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry no longer wires or defines the scroll seam; a stray copy would call a setup the owner never published.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner.lua'; needle='(?m)^mod:hook_safe\("(DeusShopView", "_create_ui_elements|DeusCursedChestView", "create_ui_elements)"'; literal=$false; polarity='present'; minCount=2; issueRef='#1159'; note='both boon-offer view BUILD hooks are owned here; VMF silently drops a duplicate pair.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^\s*mod:hook(_safe)?\("(DeusShopView", "(_create_ui_elements|update)|DeusCursedChestView", "(create_ui_elements|update))"'; literal=$false; polarity='absent'; issueRef='#1159'; note='all four layout hooks moved with the code that reads them; a second registration in the entry would be silently dropped and the scrollbar would ship dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='fix_arc_nan'; literal=$true; polarity='absent'; issueRef='#1159'; note='the degenerate-arc repair moved with the two build hooks that are its only callers.' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.328-dev (#1159 campaign-graph owner).
    # File retargeted by that extraction: the deus_populate_graph hook and the #145
    # fix moved verbatim out of the entry into _ct_campaign_graph_owner.lua. The
    # invariants themselves are unchanged; the needles are byte-identical.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner.lua'; needle='mod._ct_force_finale_god(result[1], config)'; literal=$true; polarity='present'; minCount=2; issueRef='#145'; note='force-finale-god wired at BOTH deus_populate_graph branches (>= 2 call sites).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod._ct_force_finale_god(result[1], config)'; literal=$true; polarity='absent'; issueRef='#145'; note='the entry no longer owns the generator branches; a stray copy here would run outside the owner.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner.lua'; needle='mod:hook(_G, "deus_populate_graph"'; literal=$true; polarity='present'; issueRef='#1159'; note='the CW graph generator stays a single full hook, owned here.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='mod:hook(_G, "deus_populate_graph"'; literal=$true; polarity='absent'; issueRef='#1159'; note='a second registration on the pair is silently dropped by VMF; the entry must not re-add it.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_host_state_transport_owner.lua'; needle='mod:network_register("ct_graph_snapshot_chunk"'; literal=$true; polarity='present'; issueRef='#1159'; note='the graph-snapshot RPC transport stays in the host-state transport owner, NOT in the campaign-graph owner.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner.lua'; needle='mod:network_register('; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner may CALL the broadcast/apply helpers but must never own an RPC receiver.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner.lua'; needle='_ct_host_graph_snapshot'; literal=$true; polarity='absent'; issueRef='#1159'; note='snapshot STATE stays an entry file-local; reading it from another chunk would capture a stale nil.' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.329-dev (#1159 altar-reuse owner).
    # File retargeted by that extraction: the whole reusable-altar block moved
    # verbatim out of the entry into _ct_altar_reuse_owner.lua. The invariants
    # themselves are unchanged; the needles are byte-identical, only `file` moved.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'; needle='CT_RELIQUARY_REROLL_PROMPT = "Reroll this weapon?"'; literal=$true; polarity='present'; maxCount=1; issueRef='#252'; note='the approved short same-tier reroll prompt is defined exactly once, in the altar-reuse owner.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='CT_RELIQUARY_REROLL_PROMPT'; literal=$true; polarity='absent'; issueRef='#252'; note='the entry must not redefine or re-read the prompt global; _ct_regression.lua reads it at runtime.' }
    # These two use a line-anchored REGEX, not a literal: the owner's own comments
    # quote the open_chest pair verbatim (the "DO NOT add a second hook" warning
    # that exists because v0.7.129/.130 shipped dead inside a duplicate), so a
    # literal absence needle would match prose and false-fail.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'; needle='(?m)^mod:hook\("DeusChestExtension", "get_purchase_cost"'; literal=$false; polarity='present'; maxCount=1; issueRef='#61'; note='the mult^uses price curve stays a single full hook, owned here.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^mod:hook(_safe)?\("DeusChestExtension"'; literal=$false; polarity='absent'; issueRef='#1159'; note='every DeusChestExtension hook now lives in an owner (reuse readers in _ct_altar_reuse_owner, the open_chest write seam in _ct_bot_weapon_chest_owner); VMF silently drops a duplicate pair, which is how v0.7.129/.130 shipped dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'; needle='(?m)^mod:hook\("DeusChestExtension", "open_chest"'; literal=$false; polarity='absent'; issueRef='#1159'; note='the single consolidated open_chest write seam belongs to _ct_bot_weapon_chest_owner; a copy here would be silently dropped.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'; needle='local _altar_uses_by_go_id = {}'; literal=$true; polarity='present'; maxCount=1; issueRef='#1159'; note='the use ledger is a single owner file-local; the entry reaches it only through the exported accessor.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='_altar_uses_by_go_id'; literal=$true; polarity='absent'; issueRef='#1159'; note='a second ledger in the entry would silently diverge from the one every reuse hook reads.' }
    # Retargeted by the #1159 run-creation owner extraction (ct_dev 0.7.336-dev):
    # the DeusRunController.setup_run hook that holds the wipe moved verbatim into
    # _ct_run_creation_owner.lua. Needle byte-identical; only `file` moved, and the
    # entry-side absence row below is what catches a stray second wipe.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='_ct_altar_reuse.reset_uses()'; literal=$true; polarity='present'; maxCount=1; issueRef='#1159'; note='run start still wipes the ledger exactly once, from the DeusRunController.setup_run hook.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='_ct_altar_reuse.reset_uses()'; literal=$true; polarity='absent'; issueRef='#1159'; note='a second wipe in the entry would clear a rebound table no reuse hook reads.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'; needle='_ct_host_settings'; literal=$true; polarity='absent'; issueRef='#1159'; note='settings-sync STATE stays an entry file-local; this owner reads settings only through the injected late-binding wrapper.' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.330-dev (#1159 chest-revive owner).
    # File retargeted by that extraction: Chest of Trials completion recovery
    # moved verbatim out of the entry into _ct_chest_revive_owner.lua. Needles
    # are byte-identical to the pre-extraction text; only `file` moved.
    # The entry-side absence needle is a line-anchored REGEX scoped to _set_state,
    # not the bare class name: the entry still legitimately hooks
    # DeusCursedChestExtension.extensions_ready (#132 census) and names the class
    # in prose, so a literal would false-fail.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner.lua'; needle='(?m)^mod:hook_safe\("DeusCursedChestExtension", "_set_state"'; literal=$false; polarity='present'; maxCount=1; issueRef='#1159'; note='the completion detector is a single hook_safe, owned here; VMF silently drops a duplicate pair.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^mod:hook(_safe)?\("DeusCursedChestExtension", "_set_state"'; literal=$false; polarity='absent'; issueRef='#1159'; note='a second _set_state registration in the entry would be silently dropped and the revive would ship dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^mod:hook(_safe)?\("(PlayerUnitHealthExtension", "sync_health_state|RespawnHandler", "_respawn_player)"'; literal=$false; polarity='absent'; issueRef='#1159'; note='both post-respawn compensations moved with the marker they read; a copy left here would read a table that no longer exists.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner.lua'; needle='local pending_chest_respawn = {}'; literal=$true; polarity='present'; maxCount=1; issueRef='#1159'; note='the per-run dead-at-chest-open marker is a single owner-scope local shared by all three hooks.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='pending_chest_respawn'; literal=$true; polarity='absent'; issueRef='#1159'; note='a second marker table in the entry would arm compensations the owner never clears.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_host_state_transport_owner.lua'; needle='mod._ct_chest_teleport_tick(dt)'; literal=$true; polarity='present'; maxCount=1; issueRef='#299'; note='the deferred rescue pass is still driven once per frame from the transport owner mod.update; without this reader the armed job never runs.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner.lua'; needle='if lookup and lookup[unit] then lookup[unit] = Vector3(x, y, z) end'; literal=$true; polarity='present'; maxCount=1; issueRef='#299'; note='POSITION_LOOKUP is refreshed in place only when the engine already maintains the entry; seeding one flips ALIVE[unit] truthy and leaves dead frame-pool userdata (BUG_CLASSES section 21).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='POSITION_LOOKUP'; literal=$true; polarity='absent'; issueRef='#299'; note='the entry no longer touches the lookup at all; every read re-derives live positions via Unit.world_position inside the owner.' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.298-dev (fable-fix-wave clusters).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner.lua'; needle='buff_system:add_buff(unit, stack_name, unit, true)'; literal=$true; polarity='present'; issueRef='#249'; note='meta-boon stack grant is server-controlled (replicates to clients; issue 289 evidence).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner.lua'; needle='CT_META_AMMO_SERVER_AUTH_MARKER = AmmoGuardCore.MARKER'; literal=$true; polarity='present'; issueRef='#249'; note='server-authoritative grant marker sourced from the pure kernel.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner.lua'; needle='AmmoGuardCore.clamp_value(max_ammo, ax._available_ammo)'; literal=$true; polarity='present'; issueRef='#256'; note='issue 256 clamp routes through the offline-tested pure kernel.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'; needle='M.RECONCILE_MARKER = "CT_CHEST132_RECONCILE_PRUNE_v0.7.298"'; literal=$true; polarity='present'; issueRef='#132'; note='settled cross-path chest reconcile (prune side) present.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'; needle='Managers.state.unit_spawner:mark_for_deletion(u)'; literal=$true; polarity='present'; issueRef='#132'; note='prune uses the engine pickup delete path (pickup_system.lua:1451-1455).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool.lua'; needle='"normal", "hard", "harder", "hardest", "cataclysm", "cataclysm_2", "cataclysm_3"'; literal=$true; polarity='present'; issueRef='#251'; note='injected pickup_settings cover every reachable difficulty key (no engine fallback).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'; needle='multiplier  = -0.5'; literal=$true; polarity='present'; issueRef='#464'; note='Anath Raema permanent reload buff stays NEGATIVE (reload_speed is inverse).' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.333-dev (#1159 level-load owner).
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner.lua'; needle='(?m)^mod:hook\("MutatorHandler", "tweak_pack_spawning_settings", function\(func, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings\)'; literal=$false; polarity='present'; maxCount=1; issueRef='#356'; note='the strip hook is STATIC - four positional params, no leading self. A re-added self shifts every arg and the SIGNATURE-zone list rides in unfiltered (host CTD guid 4c84c68a).' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner.lua'; needle='CT_NO_ROAMERS_ARITY_FIX_MARKER = "no_roamers_hook_static_arity_no_self_v0.7.241"'; literal=$true; polarity='present'; maxCount=1; issueRef='#356'; note='the arity marker _ct_regression reads is set exactly once, by the owner, at the original load position.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='CT_NO_ROAMERS_ARITY_FIX_MARKER = '; literal=$true; polarity='absent'; issueRef='#1159'; note='a second assignment in the entry would make the marker say the fix is live wherever it was assigned LAST.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^\s*mod:hook(_safe)?\("(EnemyPackageLoader", "setup_startup_enemies|MutatorHandler", "tweak_pack_spawning_settings|GameModeDeus", "local_player_game_starts)"'; literal=$false; polarity='absent'; issueRef='#1159'; note='all three level-load hooks moved with the code they gate; VMF silently drops a duplicate pair, so a copy left here would ship one of them dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner.lua'; needle='(?m)^\s*mod:hook(_safe)?\("CameraManager"'; literal=$false; polarity='absent'; issueRef='#1159'; note='the curse SKY belongs to _ct_curse_lighting_owner and its single CameraManager.shading_callback hook; this owner does the per-unit Light.set_color tint only. The header NAMES CameraManager on purpose, so the needle pins the hook site, not the word.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner.lua'; needle='mod:network_register('; literal=$true; polarity='absent'; issueRef='#1159'; note='the level-load seam owns no RPC; the settings-sync / graph-snapshot / peer-manifest transports stay entry-owned.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='function _dump_pickup_system_state(prefix, also_echo)'; literal=$true; polarity='absent'; issueRef='#1159'; note='the census bodies live in the owner; a second definition in the entry would overwrite the slot the owner already filled.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner.lua'; needle='_dump_pickup_system_state     = _ct_level_load_owner.dump_pickup_system_state'; literal=$true; polarity='present'; maxCount=1; issueRef='#1159'; note='the adventure owner forward-declared slot is filled from the level-load owner exports; without it the population owner wrappers and the _ct_regression by-value bind both read nil.' }
    # Source: chaos_wastes_tweaker_dev/CHANGELOG.md 0.7.336-dev (#1159 run-creation owner).
    # The run-CREATION seam moved verbatim out of the entry: the setup_run hook and
    # its host-side rpc_deus_set_initial_soft_currency partner, the
    # get_run_difficulty ramp, and the generate_random_power_ups roll whose
    # per-run no-repeat ledger setup_run creates.
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='(?m)^mod:hook\("DeusRunController", "setup_run"'; literal=$false; polarity='present'; maxCount=1; issueRef='#1159'; note='one consolidated setup_run hook; the v0.7.95 host broadcast was folded into it precisely because a second registration on the pair is silently dropped.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^\s*mod:hook(_safe)?\("DeusRunController", "(setup_run|get_run_difficulty|rpc_deus_set_initial_soft_currency)"'; literal=$false; polarity='absent'; issueRef='#1159'; note='all three run-creation hooks moved with the state they establish; VMF silently drops a duplicate pair, so a copy left here would ship one of them dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='(?m)^\s*mod:hook\("DeusPowerUpUtils", "generate_random_power_ups"'; literal=$false; polarity='absent'; issueRef='#1159'; note='the roll moved with the boon-altar no-repeat ledger it filters against; a second registration here would be silently dropped and the pool strip would ship dead.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='CT_PROGRESSIVE_DIFFICULTY_MARKER = "progressive_difficulty:per_controller_start_hotjoin_sync_contiguous_tiers_v3"'; literal=$true; polarity='present'; maxCount=1; issueRef='#460'; note='the marker _ct_regression reads is still assigned exactly once, as a global, at the original load position.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='CT_PROGRESSIVE_DIFFICULTY_MARKER = '; literal=$true; polarity='absent'; issueRef='#1159'; note='a second assignment in the entry would make the marker say the ramp is live wherever it was assigned LAST.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'; needle='local _starting_coins_applied_for_run'; literal=$true; polarity='present'; maxCount=1; issueRef='#1159'; note='ONE storage slot. The owner writes it through an injected accessor and the inline starting_coins_value_matches_setting check reads it as an upvalue; a second declaration in either file makes that check a permanent no-op PASS.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='local _starting_coins_applied_for_run'; literal=$true; polarity='absent'; issueRef='#1159'; note='re-declaring the slot here would split it in two and silently disarm the entry-side runtime verify.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='mod:network_register('; literal=$true; polarity='absent'; issueRef='#1159'; note='the run-creation seam registers no RPC of its own; it hooks vanilla RPC METHODS only, and the settings-sync / graph-snapshot / peer-manifest transports stay entry-owned.' }
    @{ mod='ct_dev'; file='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua'; needle='mod:command'; literal=$true; polarity='absent'; issueRef='#1159'; note='commands stay on the entry / _ct_command_owner surfaces.' }

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
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_transport.lua'; needle='state_pull = "piggyback_cos_la_state_req"'; literal=$true; polarity='present'; issueRef='#574'; note='join recovery reuses the acknowledged post-ingame state pull.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_transport.lua'; needle='retry_network = false'; literal=$true; polarity='present'; issueRef='#574'; note='the bounded join retry repaints locally and cannot create an RPC stream.' }

    # -- #697: a genuine LA-hat husk paint failure must NAME the hat through the
    #    printf-backed _dbg_alert channel. The key-bearing _dbg line beside it is
    #    mod:debug (invisible with mod logging OFF), so without the key on the
    #    alert line a residual failure stays anonymous.
    #    #1159: the husk-hat create seam moved verbatim into
    #    _cos_attachment_spawn_sync.lua, so the needle follows the code and the
    #    entry gains the matching ABSENCE row below.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='_dbg_alert("[husk-hat-create] paint err key=%s vanilla=%s: %s"'; literal=$true; polarity='present'; issueRef='#697'; note='the husk-hat paint failure line carries the armoury key + vanilla variant on the visible alert channel.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='if not pcall(printf, "[cosmetics:dbg] " .. fmt, ...) then'; literal=$true; polarity='present'; issueRef='#697'; note='_dbg_alert stays printf-backed (lands in console log with mod logging OFF); rerouting it blinds every alert.' }

    # -- #1159: the HeroWindowItemCustomization view lifecycle owner. The three
    #    hooks below moved verbatim out of the entry into
    #    _cos_customization_view_lifecycle.lua. VMF silently drops a second
    #    registration on the same (Class, method) pair per mod, so the entry-side
    #    ABSENCE rows are what keep a future re-inline from shadowing the owner.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"HeroWindowItemCustomization", "_create_preview_widget"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the mount-side preview-world guard belongs to _cos_customization_view_lifecycle; a second entry registration would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"HeroWindowItemCustomization", "_update_environment"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the #228 blend-variation hook belongs to _cos_customization_view_lifecycle; re-inlining it re-opens the ShadingEnvironment.blend AV.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"HeroWindowItemCustomization", "on_exit"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the screen-exit teardown belongs to _cos_customization_view_lifecycle; a second entry registration would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua'; needle='mod:hook_safe("HeroWindowItemCustomization", "_create_preview_widget"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#235'; note='the mission preview world is re-pointed to the studio-lit resident env exactly once per mount.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua'; needle='World.set_data(world, "cos_preview_env_repointed", true)'; literal=$true; polarity='present'; issueRef='#235'; note='the re-point flag is what lets _update_environment allow the vanilla weapons_default_01 variation instead of pinning "default".' }
    # -- #1159: `_send_la_apply` is FORWARD-DECLARED in the entry and only assigned
    #    ~2400 lines below this install call. Handing the sender over BY VALUE here
    #    would capture nil and silently kill the exit-time deferred LA emit drain,
    #    so the entry must pass a getter and the owner must call it at drain time.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='get_send_la_apply = function() return _send_la_apply end,'; literal=$true; polarity='present'; issueRef='#1159'; note='the LA sender crosses the chunk boundary as a late-bound getter, never as an install-time value.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua'; needle='LA_PERSIST, _get_send_la_apply(), function(unit) return Unit.alive(unit) end)'; literal=$true; polarity='present'; issueRef='#1159'; note='the drain resolves the forward-declared sender at call time; a captured upvalue would be nil.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua'; needle='local _send_la_apply'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the entry-owned sender with a local of its own.' }

    # -- #1159: the attachment-slot LA spawn/sync owner. All four seams below moved
    #    verbatim out of the entry into _cos_attachment_spawn_sync.lua. VMF silently
    #    drops a second registration on the same (Class, method) pair per mod, so the
    #    entry-side ABSENCE rows are what keep a future re-inline from shadowing the
    #    owner. AttachmentUtils is a PLAIN TABLE, so its registration must stay in the
    #    table-form-plus-nil-guard shape - the string form never registers at all.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"PlayerHuskAttachmentExtension", "create_attachment"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the husk hat spawn seam belongs to _cos_attachment_spawn_sync; a second entry registration would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"PlayerUnitAttachmentExtension", "game_object_initialized"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the local go-init name substitution belongs to _cos_attachment_spawn_sync; re-inlining it drops one of the two registrations.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"PlayerUnitAttachmentExtension", "spawn_resynced_loadout"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the resync name substitution belongs to _cos_attachment_spawn_sync; a second entry registration would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(AttachmentUtils, "hot_join_sync"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the hot-join seam belongs to _cos_attachment_spawn_sync; the sibling create_attachment seam belongs to _cos_spawn_boundary.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='_dbg_alert("[husk-hat-create]'; literal=$true; polarity='absent'; issueRef='#1159'; note='the husk-hat alert channel travels with its hook; an entry copy would mean the seam was re-inlined.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='mod:hook("PlayerHuskAttachmentExtension", "create_attachment"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the husk hat spawn seam is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='if AttachmentUtils then'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='AttachmentUtils is a plain table: the nil-guarded table-form registration is load-bearing and must survive the move.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='_net_safe_hook_status.PUAE = true'; literal=$true; polarity='present'; issueRef='#1159'; note='the owner still records its registrations on the entry-owned status table the startup verification reads.' }
    # -- #1159: `_la_pending_apply` is REBOUND by the entry at both drain sites
    #    (`_la_pending_apply = kept`). Handing the queue over BY VALUE would leave the
    #    husk-hat skeleton deferral appending to the table the first drain discarded,
    #    so the entry passes a getter and the owner resolves it at enqueue time.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='get_la_pending_apply = function() return _la_pending_apply end,'; literal=$true; polarity='present'; issueRef='#1159'; note='the rebound LA retry queue crosses the chunk boundary as a getter, never as an install-time value.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='local _pending = _get_la_pending_apply()'; literal=$true; polarity='present'; issueRef='#1159'; note='the deferral resolves the rebound queue at enqueue time; a captured upvalue would go stale after the first drain.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua'; needle='local _la_pending_apply'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the entry-owned retry queue with a local of its own.' }

    # -- #1159 Wave 19: attachment/preview spawn and Moonfire impact owners.
    #    The entry-side absence rows prevent a later re-inline from competing for
    #    the same VMF registration. The owner-side rows pin exact cardinality.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(AttachmentUtils, "create_attachment"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the optional-headpiece residency gate belongs exclusively to _cos_spawn_boundary.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_spawn_boundary.lua'; needle='mod:hook(attachment_utils, "create_attachment"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the plain-table attachment spawn choke point is registered exactly once by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook("HeroPreviewer", "_spawn_item_unit"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the base preview spawn seam belongs exclusively to _cos_spawn_boundary.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook("MenuWorldPreviewer", "_spawn_item_unit"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the derived preview spawn seam belongs exclusively to _cos_spawn_boundary.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_spawn_boundary.lua'; needle='mod:hook("HeroPreviewer", "_spawn_item_unit", spawn_item_unit_combined)'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the combined hook owns the base preview spawn seam exactly once.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_spawn_boundary.lua'; needle='mod:hook("MenuWorldPreviewer", "_spawn_item_unit", spawn_item_unit_combined)'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the same combined hook owns the derived preview seam exactly once.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='PlayerProjectileUnitExtension'; literal=$true; polarity='absent'; issueRef='#1159'; note='the Moonfire cosmetic impact surface belongs exclusively to _cos_moonfire_puff_runtime.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_moonfire_puff_runtime.lua'; needle='"PlayerProjectileUnitExtension"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the owner declares the local projectile family exactly once; method fan-out stays bounded in one loop.' }
    # -- #1159: the live equipment-assembly seam. GearUtils.create_equipment and the
    #    BackendUtils.get_item_units resolution it brackets moved out of the entry as
    #    ONE owner because `_in_create_equipment` (#150) is written by the first and
    #    read by the second and by nothing else. BackendUtils is a PLAIN TABLE, so its
    #    registration must keep the table-form-plus-nil-guard shape - the string form
    #    never registers at all. The entry-side ABSENCE rows are what keep a future
    #    re-inline from silently shadowing the owner.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(BackendUtils, "get_item_units"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the item unit-table resolution belongs to _cos_equipment_assembly; a second entry registration would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook("GearUtils", "create_equipment"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the live-body assembly seam belongs to _cos_equipment_assembly; re-inlining it shadows the owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local _in_create_equipment'; literal=$true; polarity='absent'; issueRef='#1159'; note='the create_equipment bracket flag is private to the assembly owner; an entry copy means the hook pair was split.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='mod:hook(BackendUtils, "get_item_units"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the item unit-table resolution is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='mod:hook("GearUtils", "create_equipment"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the live-body assembly seam is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='if BackendUtils then'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='BackendUtils is a plain table: the nil-guarded table-form registration is load-bearing and must survive the move.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='local _in_create_equipment = false'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the bracket flag has exactly one declaration and it lives with the only two hooks that use it.' }
    # -- #1159: `_current_husk_wield` is REBOUND stack-style by the remote-husk
    #    _wield_slot wrap, and `_active_customization_backend_id` is written by both
    #    the view-lifecycle owner and the offhand picker. Both cross as getters and
    #    are resolved once per hook call at their original first-read points.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='return HUSK_WIELD_RUNTIME.current(mod)'; literal=$true; polarity='present'; issueRef='#1159'; note='the rebound husk-wield context crosses the chunk boundary through its owner accessor, never as an install-time value.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not reclaim the remote husk wield transaction.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime.lua'; needle='mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the remote husk wield transaction has exactly one owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime.lua'; needle='state.current = previous'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the stack-style husk context is restored after the protected vanilla call.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook_safe("SimpleHuskInventoryExtension", "init"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not reclaim the remote husk initialization edge.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_husk_identity_runtime.lua'; needle='mod:hook_safe("SimpleHuskInventoryExtension", "init"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the LA husk identity owner exclusively owns the remote initialization edge.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='local _current_husk_wield = _get_current_husk_wield()'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the husk lanes resolve the rebound context per call; a captured upvalue would freeze the nil it holds at load.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='local _current_husk_wield = nil'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the runtime-owned husk-wield context with a declaration of its own.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='_get_active_customization_backend_id()'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the mutable customization backend id is resolved per call, so one entry slot stays authoritative.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'; needle='local _active_customization_backend_id = nil'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the entry-owned customization backend id with a declaration of its own.' }
    # -- #1159 (wave 10): the LA apply / revert / reconcile runtime. This owner
    #    registers NOTHING, which is exactly why the move could not perturb hook
    #    order, so the rows below pin the moved DEFINITIONS instead of hooks. The
    #    retry queue is the only rebound crossing and it needs BOTH halves of the
    #    accessor pair: the entry rebinds it in mod.update's drain, the owner
    #    rebinds it in the revert purge.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local function _apply_la_on_unit('; literal=$true; polarity='absent'; issueRef='#1159'; note='the unified LA apply core belongs to _cos_la_apply_runtime; an entry copy would shadow the owner and split the #518 deus gate.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod._la_reconcile = function'; literal=$true; polarity='absent'; issueRef='#1159'; note='the single render-reconcile entry point belongs to _cos_la_apply_runtime; a later entry definition would silently replace the owner closure.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod._la_apply_revert_recv = function'; literal=$true; polarity='absent'; issueRef='#1159'; note='the revert receiver belongs to _cos_la_apply_runtime; splitting it from the apply core strands the shared pulse-cooldown table.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local _offhand_reswap_state'; literal=$true; polarity='absent'; issueRef='#1159'; note='the per-owner pulse cooldown table is private to the apply/revert owner; an entry copy means the mesh pulse and the native pulse stopped sharing one rate limit.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='local function _apply_la_on_unit('; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the apply core is declared exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='mod._la_reconcile = function'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the render-reconcile entry point is defined exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='local _offhand_reswap_state = setmetatable({}, { __mode = "k" })'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the pulse cooldown table stays one weak-keyed table shared by the mesh pulse and the native pulse.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='set_la_pending_apply = function(t) _la_pending_apply = t end,'; literal=$true; polarity='present'; minCount=2; maxCount=2; issueRef='#1159'; note='both queue-rebinding owners receive the same entry setter: apply/revert propagates its purge and the frame scheduler propagates its bounded drain.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='_set_la_pending_apply(_la_pending_apply)'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the revert purge propagates its rebind back to the entry immediately after the untouched original assignment.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='local _la_pending_apply = _get_la_pending_apply()'; literal=$true; polarity='present'; minCount=3; maxCount=3; issueRef='#1159'; note='every read of the rebound retry queue resolves at call time; a captured upvalue would append to a table the drain discarded.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua'; needle='local _la_pending_apply = {}'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the entry-owned retry queue with a declaration of its own.' }

    # -- #1159 (wave 12): the cos_la_* peer-sync transport. Unlike wave 10 this
    #    owner DOES register - four mod:network_register handlers and the
    #    PlayerManager remove_player / add_remote_player hook_safe pair - so the
    #    rows below pin the registrations to the owner AND assert entry-side
    #    absence: a resurrected entry copy of any RPC name would silently win or
    #    lose depending on load order, and a duplicate (Class, method) hook_safe
    #    is dropped by VMF without a word. The send/receive halves install in two
    #    phases from ONE dofile, which is what keeps registration ORDER identical;
    #    the phase-2 call site is pinned so a future slice cannot fold it into
    #    phase 1 and quietly move six registrations ~800 lines earlier.
    # The `, function(` tail is deliberate: the moved block carries a v0.9.0.7
    # comment that names the cos_la_apply_req register in prose, so a bare channel
    # needle would count two and a maxCount of 2 would stop policing duplicates.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:network_register("cos_la_apply_req", function('; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the host-authoritative equip-request receiver is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:network_register("cos_la_apply", function('; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the authoritative apply broadcast receiver is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:network_register("cos_la_state_req", function('; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the hot-join pull-on-ready responder is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:network_register("cos_la_state_ack", function('; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the pull acknowledgement receiver is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:hook_safe(PlayerManager, "remove_player"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the deferred peer purge scheduler must stay a single hook_safe in its owner; a second registration anywhere is silently dropped by VMF.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:hook_safe(PlayerManager, "add_remote_player"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the purge-cancel + peer-ready replay edge must stay a single hook_safe in its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:network_register("cos_la_'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not re-register any cos_la_* channel beside the transport owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook_safe(PlayerManager,'; literal=$true; polarity='absent'; issueRef='#1159'; note='the peer lifecycle hooks belong to the transport owner; an entry copy would be the duplicate VMF drops.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='LA_SYNC.install_receivers()'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='phase 2 runs exactly once, at the line the first cos_la_* register used to occupy; folding it into phase 1 would move six registrations ~800 lines earlier.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='assert(owner.receivers_installed == false,'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the one-shot guard is what makes the registering phase machine-checked rather than comment-checked.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='_send_la_apply = function(unit, slot_name, kind,'; literal=$true; polarity='absent'; issueRef='#1159'; note='the LA apply sender belongs to the transport owner; an entry definition would shadow the export and split the emit-dedup window from the deferred queue.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='local _last_emit_at = {}'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='one dedup table serves all three senders and the per-peer purge sweep; a second copy means a purge that cannot clear the window it is supposed to clear.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local _last_emit_at'; literal=$true; polarity='absent'; issueRef='#1159'; note='the emit-dedup window is private to the transport owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='local _la_pending_apply = _get_la_pending_apply()'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the receiver resolves the rebound retry queue at call time; a captured upvalue would append to a table the drain discarded.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='local _la_pending_apply = {}'; literal=$true; polarity='absent'; issueRef='#1159'; note='the owner must never shadow the entry-owned retry queue with a declaration of its own.' }

    # LA loadout state + the two vanilla-RPC net-safe senders (#1159 wave 14).
    # Six hooks moved verbatim; the sender crosses as a getter; the net-safe
    # status table deliberately did NOT move and stays entry-brokered.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='mod:hook(CosmeticUtils, "update_cosmetic_slot"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the fa479a72 net-safe sender swap is a SINGLETON in its owner; VMF drops a second registration, so a duplicate reads as "peers crash again".' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(CosmeticUtils, "update_cosmetic_slot"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the GameSession sender belongs to _cos_la_loadout_safety; an entry copy would be the duplicate VMF silently drops.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='mod:hook(LoadoutUtils, "sync_loadout_slot"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the rpc_sync_loadout_slot shadow substitution is a SINGLETON in its owner (same crash class on a second channel).' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(LoadoutUtils, "sync_loadout_slot"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the loadout-slot sender belongs to _cos_la_loadout_safety; an entry copy would be silently dropped.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='mod:hook(BackendUtils, "set_loadout_item"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the #520 user-intent equip chokepoint (cache + authoritative persist) is registered exactly once, by its owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(BackendUtils, "set_loadout_item"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the loadout equip capture belongs to _cos_la_loadout_safety; an entry copy would shadow the persist path.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='if not is_bot and mod.loadout_cache[career_name]'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the bot-loadout guard travels with its hook: without it every bot resolves the HOST loadout and clones the host gear (wt v0.12.115 fix).' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local function _install_skin_loadout_safety()'; literal=$true; polarity='absent'; issueRef='#1159'; note='the deferred loadout-safety installer belongs to its owner; an entry copy would shadow the export the mod.update call site resolves.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local _install_skin_loadout_safety = LA_LOADOUT_SAFETY.install_skin_loadout_safety'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the entry re-binds the owner export so the existing mod.update call site keeps resolving the same function object.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='local _send_la_apply = _get_send_la_apply()'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the owner installs ABOVE the entry sender assignment, so the sender resolves at hook-fire time; an install-time by-value capture freezes nil and no peer is ever told about the LA cosmetic.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety.lua'; needle='(?m)^(?!\s*--).*_net_safe_hook_status'; literal=$false; polarity='absent'; issueRef='#1159'; note='the net-safe status table stays ENTRY-owned: the entry declares it, brokers it to _cos_attachment_spawn_sync and reads it back; this owner must not become a third party to it. Comment-excluding regex - the owner NOT-OWNED-HERE header names it on purpose.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='local _net_safe_hook_status = {'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the startup verification and the attachment-spawn owner share exactly one status table, declared here.' }

    # #1159 wave 18: exact-item presentation is one two-phase runtime owner.
    # The UIUtils hook moves in phase 1; the contextual Hold-Tab adapter is
    # published from the same owner after LA receivers install.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='"scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime").install(mod, {'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the exact-item presentation owner is installed exactly once at its historical resolver boundary.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod:hook(UIUtils, "get_ui_information_from_item"'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not re-register the UIUtils presentation hook; VMF would silently drop one owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime.lua'; needle='mod:hook(UIUtils, "get_ui_information_from_item"'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the exact-instance item-card hook is registered exactly once by its runtime owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='mod._cos.resolve_peer_item_presentation = function'; literal=$true; polarity='absent'; issueRef='#1159'; note='the entry must not re-inline the Hold-Tab peer adapter beside its two-phase owner.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime.lua'; needle='mod._cos.resolve_peer_item_presentation = function'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='the contextual peer-cache adapter is published exactly once from phase 2.' }
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; needle='_cos_item_presentation_runtime.install_peer({'; literal=$true; polarity='present'; minCount=1; maxCount=1; issueRef='#1159'; note='phase 2 remains an explicit one-shot call after LA_SYNC.install_receivers; executable tests pin the order.' }

    # ============================ cim_dev ============================
    # Source: crafting_in_modded_dev/CHANGELOG.md 0.8.57-dev (issue 511). The two
    # hook-registration checks whose source-text needles skip in retail.
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_weave_economy.lua'; needle='BackendInterfaceWeavesPlayFab", "get_talent_required_forge_level"'; literal=$true; polarity='present'; issueRef='#71'; note='extracted amulet/weave-properties crash guard hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='"HeroWindowWeaveProperties", "_populate_menu_option_widget"'; literal=$true; polarity='present'; issueRef='#239'; note='extracted weave-forge cost-hide hook must stay installed.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='widget.content.price_text = ""'; literal=$true; polarity='present'; issueRef='#239'; note='the extracted cost-hide adapter must blank the Cost:0 label.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua'; needle='price_icon.color[1] = 0'; literal=$true; polarity='present'; issueRef='#239'; note='the extracted cost-hide adapter must also hide the separate price icon.' }
    # v0.8.120-dev (#1159): the ten MUTABLE BackendInterfaceWeavesPlayFab loadout
    # hooks and the #86/#244 bubble-cap math moved out of the entry byte-identical.
    # Pin them to the owner AND assert entry-side absence so a later slice cannot
    # resurrect a second copy that VMF would silently drop as a duplicate hook.
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner.lua'; needle='mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_property"'; literal=$true; polarity='present'; issueRef='#86'; note='the mutable weave write chokepoint must stay installed in its owner.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='mod:hook("BackendInterfaceWeavesPlayFab"'; literal=$true; polarity='absent'; issueRef='#86'; note='the entry must not re-register any weave loadout hook beside the owner.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner.lua'; needle='_cap_grid_property_arrays(data.properties, item_backend_id)'; literal=$true; polarity='present'; issueRef='#86'; note='the read-chokepoint trim must stay on the get_loadout_properties path; the write cap alone never fixed the grid over-occupancy.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='mod:hook("BackendManagerPlayFab", "commit"'; literal=$true; polarity='present'; issueRef='#1159'; note='the EAC commit suppression covers BOTH craft surfaces and must never move behind the weave-loadout owner install.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'; needle='_bubble_cap = _WEAVE_LOADOUT_OWNER.bubble_cap'; literal=$true; polarity='present'; issueRef='#1159'; note='_cim_weave_economy installs above the seam and resolves this upvalue at callback time; unbound it reads a nil global and the Athanor crashes on the first property-cost query.' }

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
    @{ mod='wt'; file='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_character_safety.lua'; needle='variable_value, skip_sync)'; literal=$true; polarity='present'; minCount=2; issueRef='BC19'; note='BUG_CLASSES 19: skip_sync threaded through the anim_event_with_variable_float hook signature AND the func() forward (>=2 occurrences); dropping either re-arms the anim-event RPC feedback loop. Memory reference_vmf_hook_drops_skip_sync_rpc_loop.' }

    # -- BUG_CLASSES 27: husk resolves the BASE item_data. Husk fixes must live on the
    #    husk-reachable paths - the SimpleHuskInventoryExtension.start_weapon_fx crash
    #    floor (issue 280) and the GearUtils.spawn_inventory_unit block gated on
    #    `not owner_unit_1p`. An owner-only (create_equipment) fix never reaches a husk.
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_residency_owner.lua'; needle='mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'; literal=$true; polarity='present'; issueRef='#280'; note='BUG_CLASSES 27: durable husk start_weapon_fx nil-slot crash floor (non-source-character client CTD). Moved from the entry to the husk-residency owner by the #1159 slice; the guard sits beside the force-loads it backs up.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'; needle='mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'; literal=$true; polarity='absent'; issueRef='#280'; note='BUG_CLASSES 27: the crash floor lives in _cwv_husk_residency_owner. A second registration in the entry would be silently dropped by VMF and shadow the owner, so the entry must stay clear of this pair.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_equip_surface.lua'; needle='if not owner_unit_1p and'; literal=$true; polarity='present'; minCount=2; issueRef='#392'; note='BUG_CLASSES 27: the spawn_inventory_unit husk branch is gated on the no-1P-rig discriminator, once for the pre-spawn adapter and once for the post-spawn adapter (v0.1.461 added the second conjunct on each); removing either strands every husk-side transform/strip fix. The hook moved verbatim from the entry to the musket equip-surface owner in the #1159 slice because the bayonet attach and the melee-stance transform are applied inline in the same hook body; the husk branch itself is unchanged and still dispatches to _cwv_husk_path through _om.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'; needle='mod:hook("GearUtils", "spawn_inventory_unit"'; literal=$true; polarity='absent'; issueRef='#392'; note='BUG_CLASSES 27: the sole spawn chokepoint lives in _cwv_musket_equip_surface. A second registration in the entry would be silently dropped by VMF and shadow the owner, taking the husk adapter down with it, so the entry must stay clear of this pair.' }

    # -- SILENT-DEGRADATION class (no crash, no log): a variant that never enters
    #    `_transform_map` resolves a nil def, so its mesh swap still happens while
    #    scale/grip/rotation and texture bail at the nil-def guard. Two gate signals
    #    decide membership and both live in the weapon-transform owner: issue 409's
    #    per-item `force_register` crutch and the issue 417 generalization that
    #    registers on hand-unit override presence (mesh-bearing => def-resolving).
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner.lua'; needle='_resolve_field(def, "force_register")'; literal=$true; polarity='present'; issueRef='#409'; note='issue 409: the Old Musket carries no generic scale/offset, so only force_register puts it in _transform_map. Without it every resolver-driven render path early-returns at the nil-def guard and the bespoke pose/textures never apply.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner.lua'; needle='_resolve_field(def, "right_hand_unit")'; literal=$true; polarity='present'; issueRef='#417'; note='issue 417: registering on hand-unit override presence keeps mesh-bearing variants def-resolving. Dropping it re-arms the silent split where _find_def swaps the mesh but transform and texture bail, which is what forced the per-item force_register crutch.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'; needle='local function _resolve_field(def, field)'; literal=$true; polarity='absent'; issueRef='#1159'; note='#1159: the per-variant-over-type precedence resolver has exactly one owner. A second copy in the entry would shadow the registries built against the first and split transform resolution across two tables.' }

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
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua'; needle='local function wire_safe_rarity(rarity)'; literal=$true; polarity='present'; issueRef='#278'; note='BUG_CLASSES 31: the loadout-wire owner keeps the wire-safe rarity helper pure and takes ONLY rarity (no toggle arg), so it cannot be feature-gated; a 2nd param re-exposes the non-mod-peer CTD.' }
    @{ mod='cim_dev'; file='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua'; needle='if rarity == "modded" then return "unique" end'; literal=$true; polarity='present'; issueRef='#278'; note='BUG_CLASSES 31: the loadout-wire owner keeps the "modded"->"unique" coercion on the sender path; without it a non-mod peer nil-derefs RaritySettings on a vanilla RPC.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='parity:require_peer(peer_id)'; literal=$true; polarity='present'; minCount=2; issueRef='#424'; note='BUG_CLASSES 31: both transient-package loading and pre-GameSession object sync must synchronously disable Tuskgor Javelin behavior.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='_cwv424_actionutils_sender_guard_installed = true'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: the dormant grenade-slot item has a separate ActionUtils lookup encoder that must stay guarded before any future re-enable.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='_cwv424_throw_gate_installed = true'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: already-equipped Tuskgor Javelins must stop before projectile creation when peer capability is unproven.' }
    @{ mod='cwv'; file='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua'; needle='if rejected_peers[peer_id] then return false end'; literal=$true; polarity='present'; issueRef='#424'; note='BUG_CLASSES 31: cleanup failure must hold the joining peer outside GameSession because PeerStates ignores set_peer_synchronizing return values.' }

    # -- BUG_CLASSES 24: PlayerManager.remove_player fires on LEVEL TRANSITIONS. A
    #    per-peer store must NOT purge synchronously in remove_player; the deferred
    #    purge is canceled by the add_remote_player hook_safe (transitions re-add within
    #    seconds, disconnects never do). Losing the cancel wipes every peer's cosmetic
    #    store on every keep<->mission change. Recurs via classes 43 and 61.
    # #1159 wave 12: the peer lifecycle pair moved verbatim into
    # _cos_la_sync_transport with the rest of the cos_la_* transport. The BC24
    # invariant is unchanged, measured where the hook now lives; the entry-side
    # absence half lives with the wave-12 rows above.
    @{ mod='cosmetics_tweaker'; file='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_sync_transport.lua'; needle='mod:hook_safe(PlayerManager, "add_remote_player"'; literal=$true; polarity='present'; issueRef='BC24'; note='BUG_CLASSES 24: the add_remote_player hook_safe cancels the deferred peer purge; without it, remove_player-on-transition wipes the per-peer LA store every map change.' }

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

    # ============================ WOC #934 shared-relic lease ============================
    # Source: the load-bearing rows of the retired ~100-line grep tail in
    # qa/lua/tests/test_woc_shared_relic.lua (#1308). The behavioral halves stay
    # executable in that suite; these are the genuinely textual invariants: the
    # three lease RPC channels each register exactly once, the four native equip
    # seams each hook exactly once (VMF silently drops a second hook on the same
    # Class/method pair), and three forbidden tokens stay gone.
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:network_register("woc_relic_lease_intent_v1"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the claim-intent RPC channel registers exactly once, in the runtime owner.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:network_register("woc_relic_lease_state_v1"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the authority-snapshot RPC channel registers exactly once, in the runtime owner.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:network_register("woc_relic_lease_query_v1"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the snapshot-query RPC channel registers exactly once, in the runtime owner.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:hook(BackendUtils, "set_loadout_item"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the durable-equip denial gate hooks the BackendUtils seam exactly once.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:hook("HeroViewStateOverview", "_set_loadout_item"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the native Hero caller ignores BackendUtils return values, so its own seam carries the same denial gate.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:hook("SimpleInventoryExtension", "create_equipment_in_slot"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='direct live equipment creation carries the same denial gate.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='mod:hook("KeepDecorationTrophyExtension", "_load_trophy"'; literal=$true; polarity='present'; maxCount=1; issueRef='#934'; note='the keep trophy substitution seam hooks exactly once.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='woc_blightreaper_identity'; literal=$true; polarity='absent'; issueRef='#934'; note='clients must have no independent render-identity write channel; identity is applied only from the host snapshot.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='woc_blightreaper_identity'; literal=$true; polarity='absent'; issueRef='#934'; note='the retired client-authored identity channel must not come back in the entry either.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='_lease_find_base_backend_id'; literal=$true; polarity='absent'; issueRef='#934'; note='a pre-equipped losing peer restores its exact prior item or fails closed; it never guesses an inventory fallback.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='"verified-live-sync"'; literal=$true; polarity='absent'; issueRef='#934'; note='a LoadoutUtils sync payload must never prove rollback completion; only exact backend readback does.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'; needle='"hub_trophy_empty"'; literal=$true; polarity='absent'; issueRef='#934'; note='trophy ids stay single-sourced in _woc_shared_relic.lua (policy); the runtime resolves them through policy.trophy_for.' }
    @{ mod='WOC'; file='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'; needle='"hub_trophy_empty"'; literal=$true; polarity='absent'; issueRef='#934'; note='trophy ids stay single-sourced in the policy module; the entry never inlines one.' }

    # #1308: the wt/wt_dev moved-local spelling lists left the offline suite;
    # this is the one entry-side absence from those lists that is load-bearing
    # for wt_dev and was not already pinned above (a re-declared template
    # patcher in the entry would re-run the brace rewrite outside the owner).
    @{ mod='wt_dev'; file='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'; needle='local function _patch_brace_template_for_kruber'; literal=$true; polarity='absent'; issueRef='#1159'; note='mirror stream entry must stay free of the moved cross-character template patcher.' }

  )
}
