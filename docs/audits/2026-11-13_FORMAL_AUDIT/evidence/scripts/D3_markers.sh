#!/bin/bash
# D3: presence matrix of issue markers across dev / stable / tests. Read-only.
R=<repos>/vermintide-2-tweaker
cd "$R" || exit 1
chk() { # issue marker dirs...
  local iss="$1"; local pat="$2"; shift 2
  for d in "$@"; do
    local n first
    n=$(grep -rnE --include=*.lua -- "$pat" "$d" 2>/dev/null | wc -l)
    first=$(grep -rnE --include=*.lua -- "$pat" "$d" 2>/dev/null | head -1 | cut -c1-170)
    printf '#%s\t%s\t%s\t%s\t%s\n' "$iss" "$pat" "$d" "$n" "$first"
  done
}
CTD=chaos_wastes_tweaker_dev/scripts
CTS=chaos_wastes_tweaker/scripts
ET=enemy_tweaker/scripts
EV=event_tweaker/scripts
QA=qa/lua/tests
chk 60 'ct_chest_count_live_60' $CTD $CTS $QA
chk 60 'verify_ct_chest_cap' $CTD $CTS
chk 60 'cursed_chest_reconcile_132' $CTD $CTS $QA
chk 102 '_ct_altar_next_rarity_above|next_rarity_above' $CTD $CTS
chk 102 'issue102|altar_rarity_102|ct:102' $CTD $CTS $QA
chk 107 'issue107_' $CTD $CTS $QA
chk 144 'vauls_anvil_reconciler_installed' $CTD $CTS $QA
chk 146 'citadel145_force_finale_god_fix|ct_citadel_graph_readback_146' $CTD $CTS $QA
chk 146 'finale_approach_god' $CTD $CTS
chk 243 '_CURSE_MAP_BRIGHTNESS|curse_lighting_brightness' $CTD $CTS $QA
chk 252 'Reroll this weapon\?' $CTD $CTS $QA
chk 252 'reliquary_reroll_message_hook|ct_altar_prompt_readback_252' $CTD $CTS $QA
chk 256 'ct_meta_ammo_current_floor_256' $CTD $CTS $QA
chk 259 'issue259|morgrim.*free_grenade|free_grenade' $CTD $CTS $QA
chk 288 'anath_raema_registry_retry_288|ct_anath_raema_active_288' $CTD $CTS $QA
chk 289 'issue289_progressive_modifier_stack' $CTD $CTS $QA
chk 299 'ct299:move_before_free_v1|issue299_chest_revive_move_before_free' $CTD $CTS $QA
chk 322 'spawn_pickup_returns_both_values|ct_linked_pickup_identity_322' $CTD $CTS $QA
chk 323 'issue323|ct:323' $CTD $CTS $QA
chk 342 'boon_skulls_03_cooldown' $CTD $CTS $QA
chk 342 'parry_cooldown' $CTD $CTS $QA
chk 357 'issue357_' $CTD $CTS $QA
chk 358 'issue358_' $CTD $CTS $QA
chk 361 'issue361_miasma_customization_installed' $CTD $CTS $QA
chk 369 'issue369_' $ET $QA
chk 413 'issue413|wpn_shadow_gargoyle_head' $EV $QA
chk 1123 '\-0\.9|\-0\.8' event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua event_tweaker/scripts/mods/event_tweaker/event_tweaker_shadow_policy.lua
chk 1123 'issue1123' $EV $QA
chk 426 'ct_426_diag|issue426' $CTD $CTS $QA
chk 430 'issue430_' $EV $QA
chk 450 'issue450|verify_boss_balance' $ET $QA
chk 451 'issue451_' $ET $QA
chk 458 'ct_verify_start_shrine|issue458' $CTD $CTS $QA
chk 460 'verify_ct_progression|issue460' $CTD $CTS $QA
chk 467 'issue467|ct:467' $CTD $CTS $QA
chk 470 'issue470_sparse_rank8_backfill' $CTD $CTS $QA
chk 471 'ct_trial_placement_readback_471|verify_ct_trial_placement' $CTD $CTS $QA
chk 505 'single_mission_loader_redesign_505|0\.999' $CTD $CTS $QA
chk 571 'issue571_cw_tab_collectibles_safe_reflow' $CTD $CTS $QA
chk 802 'issue802_event_mission_area_scope' $EV $QA
chk 912 'ct_initial_coins_readback_912|verify_coins' $CTD $CTS $QA
chk 917 'issue917|adventure_illusion|preserve_adventure_illusions' $CTD $CTS $QA
chk 941 'issue941_prologue_solo_only_projection' $EV $QA
chk 1146 'issue1146|ct:1146' $CTD $CTS $QA
chk 1149 'issue1149_modifier_loc_icon_coverage' $EV $QA
chk 1497 'issue1497_local_host_hot_join_bypass' $ET $QA
chk 61 'issue61|et:61' $ET $QA
chk 249 'issue249_|verify_boon_ammo_hud' $CTD $CTS gui_tweaker_dev/scripts $QA
chk 52 'ct:skull52' $CTD $CTS
chk 141 'ct_resume_audit' $CTD $CTS
chk 251 'ct:251|_ct_book_spawner_census|book_spawner_census' $CTD $CTS
chk 253 'ct_weave_metal' $CTD $CTS $QA
chk 324 'issue324_' $ET $QA
chk 349 'ct:349' $CTD $CTS
chk 393 'event-inject:393' $EV
chk 453 'et_modifier_audit|et:453' $ET
chk 456 'ct:456|issue456' $CTD $CTS
chk 919 'ct_profile_audit|ct:919' $CTD $CTS gui_tweaker_dev/scripts
chk 1124 'ct:1124' $CTD $CTS
chk 1191 'wire_identity' $CTD $CTS
chk 1309 'issue1309_|et:1149t' $EV $QA
chk 465 'ct:465|policy=implicit' $CTD $CTS $QA
chk 466 'ct:466' $CTD $CTS
