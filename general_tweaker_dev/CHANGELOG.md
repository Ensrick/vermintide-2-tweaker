# General Tweaker Changelog

## v0.2.172-dev (2026-07-02) -- /catchup command (alias of /unstuck)

- **New chat command `/catchup`** (user request): teleports you to the nearest living teammate, preferring humans - identical behavior to `/unstuck`. Implemented by extracting the existing `/unstuck` body into a shared local (`_gt_unstuck_to_teammate` in `_gt_godmode_qol.lua`) and registering both command names against it; no behavior change to `/unstuck`. Collision pre-flight: repo-wide grep found no other mod registering `catchup`.

## v0.2.171-dev (2026-07-02) -- #222 loc sweep: drop leading option-title restatement from tooltips

- **#222 loc sweep: removed leading option-title restatement from 3 option tooltips so the popup body no longer repeats the orange header.** VMF draws each option's title as the popup header automatically, so a body that reopened with that same title showed the name twice.
  - `gt_btlab_enabled_tooltip`: dropped "Master switch for the Bot Teleport Lab, ..." opener; now opens with the behavior ("A set of tools for watching and fixing bots that teleport away from you."), master-switch role kept in the second sentence.
  - `base_crit_chance_tooltip`: "Sets your current career's base critical hit chance." -> "Sets how often your current career lands a critical hit." (paraphrase instead of restating "Base Crit Chance").
  - `gt_fall_damage_enabled_tooltip`: "Turns on the fall damage multiplier below; ..." -> "Turns on the multiplier below; ..." (drops the verbatim title phrase). All magnitude numbers, host-scope claims, and mechanics preserved.

## v0.2.170-dev (2026-07-01) -- Settings menu: sort A->Z, nest verified fine-tunes, mirror the loc file to the tree

Menu reorganization only. No functional changes: no setting added, removed, renamed, or re-defaulted; every one of the 144 widget setting_ids is preserved. Data-file widget defaults, ranges, decimals, keybind function_names, and dropdown option values/show_widgets are all unchanged. Localization strings are preserved verbatim except one meta-language fix (below).

- **Within-group A->Z sorting by display label** (status tags like "[untested]" ignored when sorting):
  - **Bots**: loose options re-sorted (AFK Bot Takeover, Allow Bots in Keep, Announce guard breaks, Bot Behavior Improvements, Bot follow mode, Bot Takeover, Bots drink potions, Bots rescue awaiting, Disable Bots, Faster bot reactions, Follow snap-back distance, Improved Bot Combat). Bot Teleport Lab nested group stays first.
  - **Cheats and Debug**: loose primitives A->Z (Clear Enemy Spawns, Disable Enemy Spawns, Godmode, Noclip, Noclip Toggle), then the five nested sub-groups A->Z (Buffs & Stats, Level Control, Spawners, Time & Pause, Ult). Buffs & Stats, Ult, and Level Control leaves re-sorted A->Z.
  - **Info**: Assassin, Boss path progress, Packmaster.
  - **Visuals and Audio**: Assassin/Packmaster VO, Disable fog, Disable mutator explosions, Disable sun shadows, Disable ult VO, Draw boss spheres, Max Ragdolls.
  - **Host-Side Lobby Controls**: Modded Lobby Manifest members A->Z (Broadcast, Send MOTD, Show missing mods); Prioritize Specials sub-toggles A->Z (Deepwood, Soulstealer, Tagging).
- **Nested three verified-gated fine-tune clusters under their existing master checkbox** (code already gates them, so hiding while off is purely visual, no behavior change):
  - `noclip_speed` + `noclip_boost_multiplier` under `noclip_enabled` (read only inside the active movement hook). The `noclip_hotkey` binding stays a loose sibling: it is what turns noclip on, so it must remain visible while noclip is off.
  - `gt_lobby_kick_idle_threshold_minutes` + `gt_lobby_ki_warn_seconds` under `gt_lobby_kick_idle_enabled` (idle tick reads them only past the enable gate).
  - `gt_lobby_motd_send_chat` + `gt_lobby_motd_send_popup` + `gt_lobby_motd_once_per_peer_per_session` under `gt_lobby_motd_enabled` (join handler reads them only past the enable gate).
- **Deliberate orders kept (not A->Z), each noted in a code comment:** Bot Teleport Lab D1..D10 / F1..F10 (numeric, maps to `_gt_bot_teleport_lab.lua`); Creature Spawner grudge sub_widgets (INDEX-LOCKED -- the dropdown's `show_widgets = {1}` / `{2..14}` reveal arrays reference sub_widget positions); Creature Spawner (spawn workflow + saved slots 1/2/3); Item Spawner (next/prev/spawn workflow); Time & Pause (scale then faster/slower then pause); Grail Knight quests 1/2/3 (numbered). Cheats and Debug intentionally lists loose headline cheats above its detail sub-groups so the most-used toggles stay surfaced.
- **Localization file reordered to mirror the widget tree** with a `-- ====` banner per top-level group and blank lines between groups; code-referenced strings that have no widget (MOTD popup title/text buffer, failed-join reveal text, bot guard-break chat line) moved to a trailing section.
- **One style fix:** `gt_bot_toggle_hotkey_tooltip` dropped its "Toggles whether..." meta-language preamble ("Allows or blocks bots on the current level..."); the mechanic and rare-crash caveat are preserved.
- **Suspected orphans (reported, NOT removed):** `gt_lobby_motd_text` + `gt_lobby_motd_text_tooltip` are left over from the removed MOTD text-input widget; the MOTD text is now set via `/lobby_motd_set` and read with `mod:get`, so these two labels are unused.

## v0.2.169-dev (2026-07-01) -- Passive diagnostic probes: #198 training-dummy multi-hit + #139 bot-teleport decision

Two default-on, printf-based diagnostic probes (visible with mod-logging off). No gameplay change, no setting gate, no new user-facing strings.

- **#198 (training dummy hit many times by one attack) -- new probe `_gt_probe_dummy_hits.lua`.** Hooks `TrainingDummyHealthExtension.add_damage` (`hook_safe`, observe-only) -- the exact vanilla function that both applies dummy damage and draws the floating damage number (`add_unit_floating_damage_numbers`, training_dummy_health_extension.lua:70), so one call equals one stacked number in the report screenshot. Events are bucketed per (dummy unit, attacker, damage source) and flushed one line per swing once the swing goes quiet for 0.2s (idle-flush registered on gt's shared `mod._gt_register_update` dispatcher, so `mod.update` is untouched). Emits `[198:dummy] attacker=<career> attack=<damage_source> hits_this_swing=<n> zones=<hit_zones> dmg_total=<x> crit=<bool> t=<time>`. A line with `hits_this_swing > 1` is a single swing landing multiple times on the one dummy; `zones=` distinguishes a re-application bug (same zone repeated) from a multi-actor sweep. Nothing else in gt_dev hooks `TrainingDummyHealthExtension`, so this is a fresh singleton hook (no VMF duplicate-hook drop).
- **#44 (AI-control RPC schema gate) -- schema-mismatch log switched to engine `printf`.** The drop-path log in `_gt_ai_takeover.lua`'s `gt_ai_toggle_request` receiver was `mod:info` (mirrored from the godmode receiver), which is invisible with mod-logging off. A schema mismatch means a peer on an incompatible gt_dev build was silently dropped -- the reason their AI-takeover won't sync -- so it must be visible in the user's normal (logging-off) sessions. Now `printf` (rawget-guarded), same `[rpc:schema]` tag and message. The other `mod:info` traces in that file are ordinary debug chatter and stay as-is.
- **#139 (bots teleport to a newly-downed player instead of reviving) -- merged into the existing bot-teleport hooks in `_gt_bot_fixes.lua`.** No new hook (VMF drops a 2nd hook on an already-hooked pair): the `BTConditions.should_teleport` hook now stamps `blackboard._gt139_tp_reason` (`vanilla_40m` / `tighter_leash` / nil), and the `BTBotTeleportToAllyAction.run` hook emits, once per teleport that fires while a teammate is down or awaiting rescue, `[139:bot_tp] bot=<career> dist_to_downed=<m> reason=<branch> post_dist=<m> target=<x,y,z> t=<time>`. `dist_to_downed` is the pre-teleport distance to the nearest downed/awaiting-rescue teammate; `post_dist` near 0 proves the bot snapped ONTO the downed player (the reported bug), while a large `post_dist` means it leashed to a living follow while a different teammate stayed down. Two helpers added (`_gt_unit_needs_aid_or_rescue`, `_gt_nearest_needing_aid`); `ready_for_assisted_respawn` read as a plain field per generic_status_extension.lua:1329. The prior `[gt_bot:139]` executed/suppressed lines are preserved.

## v0.2.168-dev (2026-07-01) -- Loc: fix tooltip markers + rewrite every option description in plain English

Localization-only pass, no gameplay change.

- **Fixed the "<...>" marker bug on tooltips.** Every widget in the data file wrote its tooltip as `tooltip = mod:localize("key")`, but VMF already localizes each widget's tooltip itself at menu-build time. That double-localization fed the finished English sentence back in as a lookup key, missed, and wrapped the whole tooltip in angle brackets in-game. Converted all **129** eager `tooltip = mod:localize("key")` calls to raw keys (`tooltip = "key"`) so VMF resolves them once. The one correct eager-localize, the top-level `description = mod:localize("mod_description")`, is left as-is.
- **Rewrote every option description.** All ~130 `_tooltip` values plus `mod_description` were rewritten into plain, player-facing English (max two sentences each), dropping internal jargon (function names, engine terms, file references) in favor of what the option actually does in the game. No wording implies behavior the old text did not state; percent signs stay escaped (`%%`), no em dashes, no angle brackets.
- **Key coverage verified:** all 144 widget setting_ids, 129 tooltip keys, and 21 dropdown option-text keys resolve against the loc table; no keys were added, renamed, or removed. No widget defaults, ranges, or structure changed.

## v0.2.167-dev (2026-07-01) -- Net-hardening: RPC schema versioning on the AI Takeover RPC (#44)

Applies the VMF_RECIPES § 10 RPC schema-version pattern to the last unversioned gt RPC — the AI Takeover client->host request (`gt_ai_toggle_request`, sender + receiver both in `_gt_ai_takeover.lua`). Mirrors the existing `mod.GT_LOBBY_RPC_SCHEMA` (lobby MOTD) and `_GT_GODMODE_RPC_SCHEMA` (godmode state) gates.

- **New constant `mod.GT_AI_RPC_SCHEMA = 1`** (defined in `general_tweaker_dev.lua` alongside `GT_LOBBY_RPC_SCHEMA`). Bump only when the `gt_ai_toggle_request` payload shape changes.
- **Sender** (`_gt_ai_takeover.lua`, `_ai_consume_pending_client_send`): prepends `mod.GT_AI_RPC_SCHEMA` as the first positional arg, before the existing `{ peer_id, local_player_id, want_bot }` table.
- **Receiver** (`mod:network_register("gt_ai_toggle_request", ...)`): now `function(sender_peer_id, schema, payload)`; drops the request when `schema ~= mod.GT_AI_RPC_SCHEMA` (or `sender_peer_id == nil`) with a `[rpc:schema] ... mismatch ... Dropping.` `mod:info` line. Graceful degradation — no swap, no crash. A peer on a different/older gt_dev build (older builds send no schema arg, so their payload table lands in `schema` and fails the match) is ignored rather than mis-parsed. No behavior change for matched-version peers; the takeover itself remains disabled pending the keep-slot redesign, so this is forward-looking net-hardening only.
- **Regression check** `gt_ai_rpc_schema_present` (mirrors `gt_lobby_rpc_schema_present`): asserts `mod.GT_AI_RPC_SCHEMA` is a number >= 1.

Also re-verified two previously-shipped fixes against the vanilla decompile (no code change this release):

- **#194 (Disable Bots / `gt_no_bots`)** — fixed in v0.2.143-dev (rawget `_G.script_data` + per-tick `_handle_bots` enforce hooks on Adventure/Deus/Weave). Confirmed against `game_mode_adventure.lua:371` / `game_mode_deus.lua:527` / `game_mode_weave.lua:462`: each mode's `_handle_bots` reads `script_data.ai_bots_disabled` and calls `self:_clear_bots(true)` + early-returns. Mechanism correct; pending host-side in-game confirmation.
- **#59 (Drachenfels boss BT crash)** — fixed in v0.2.149-dev (level-family prefix match + `BTConditions.at_*_health` nil-guards, `_gt_creature_spawner.lua`). Still present and marker-guarded.

## v0.2.166-dev (2026-07-01) -- NEW: Bot Teleport Lab -- 10 diagnostics + 10 fixes for "bots teleport away from the player"

A full in-game toolkit to observe, diagnose, and fix bots teleporting away. New module `_gt_bot_teleport_lab.lua`. Lives in a nested **"Bot Teleport Lab"** group inside **Bots**, gated by a master toggle `gt_btlab_enabled` (default off); everything under it defaults off and is host-side (bot AI is server-side). All logging is engine `printf` (visible with mod-logging off), tagged `[gt:btlab:...]`.

**Mechanics (source-verified):** a bot teleports when it falls >= 40 units from its `follow_unit` (`BTConditions.should_teleport`, `FOLLOW_TELEPORT_DISTANCE_SQ=1600`); the snap executes in `BTBotTeleportToAllyAction.run` (`locomotion:teleport_to`); `follow_unit` is assigned in `AIBotGroupSystem._assign_destination_points`. If a bot's follow_unit is a *different* player/host, it snaps toward them -- i.e. away from you.

**Architecture:** merge-dispatch. The lab adds ZERO new hooks on already-hooked pairs (VMF drops duplicate hooks); instead it exposes `mod._gt_btlab_*` fns called from gt's existing `should_teleport` / `BTBotTeleportToAllyAction.run` (converted hook_safe->hook to capture pre/post position) / `PlayerBotBase.update` / `_assign_destination_points` (FIX 9) hooks. Lint confirms 0 duplicate hooks; each merge-point pair is hooked exactly once. FIX 7 tighter-leash + the #139 guards are preserved verbatim.

**10 diagnostics** (`gt_btlab_d1..d10`): teleport-event log (bot/career/from->to/follow_unit/distance/trigger/toward-or-away-from-you delta); follow-unit change tracker; live distance readout (bot->follow vs bot->you); segment-gate probe; aid-exception probe; on-screen bot HUD; 3D leash-line draw (bot->follow yellow, bot->you cyan); teleport counter (`/bot_tp_dump`); has_teleported lifecycle; snapshot ring buffer (`/bot_tp_snap`).

**10 fixes** (`gt_btlab_f1..f10`, each independent, each logs SUPPRESSED/REDIRECTED so you can prove it): F1 follow you, F2 block away-teleports, F3 teleport to you instead, F4 proximity veto (`f4_radius` def 25), F5 follow nearest human, F6 stuck-only teleport, F7 raise threshold (`f7_distance` def 80), F8 combat hold (`f8_radius` def 15), F9 post-teleport cooldown (`f9_seconds` def 3), F10 direction-aware (no backward yank). Vetoes OR together (first firing logs + blocks, F-number order); F1 beats F5; F3 acts in `.run`.

**Not yet runtime-verified** -- compiles + lint-clean and follows source-verified patterns, but each fix's real behavior needs host-side in-game confirmation via its `[gt:btlab:fNN]` log line. Heuristics flagged: F6 off-navmesh proxy, F8 enemy broadphase, F10 heading source -- all pcall-guarded to degrade to "no veto" on a bad read.

## v0.2.165-dev (2026-07-01) -- FIX: Auto-restart on team wipe now works in Chaos Wastes and Weaves

**Symptom (user, in a Chaos Wastes run):** wiped, wanted to restart the map to keep testing; `/gt_win` did nothing and it "failed 3× with an info popup".

**Diagnosis:** two things. (1) `/win` (`/gt_win`) calls `GameModeManager:complete_level()`, which **cannot override a team wipe** — once the "lost" end-condition latches, force-complete is a no-op, and afterward you're in the keep where level commands are refused ("Can't do that in the keep"). It's the wrong tool for surviving a wipe. (2) The **"Auto-restart on team wipe"** toggle — which *is* the right tool — only hooked `GameModeAdventure.evaluate_end_conditions`, so in **Chaos Wastes** (`GameModeDeus`) and **Weaves** (`GameModeWeave`) it never fired. The log showed an active `deus_run_state`, i.e. Chaos Wastes.

**Fix (`_gt_solo_qol.lua`):** the auto-restart handler is now a shared function hooked on all three mission modes — `GameModeAdventure` / `GameModeDeus` / `GameModeWeave` — each a distinct `(Class, method)` pair (no VMF collision; mirrors `_gt_bots_keep`'s `_handle_bots` hooks). Returning `"reload"` is a valid end reason for all three (`adventure_mechanism.lua:427`, `deus_mechanism.lua:539/545`). Also fixed a latent multi-return drop: the hook now captures and passes through the vanilla third return (`reason_data`) instead of collapsing it. Feature is still off by default; enable "Auto-restart on team wipe" (Host-Side Lobby Controls) and a wipe reloads the current map in place. `/inn` still bails to the keep.

## v0.2.164-dev (2026-07-01) -- Simplify: strip the "gt_" prefix from all chat commands

Renamed **49** chat commands to drop the `gt_` prefix (e.g. `/gt_pause` -> `/pause`, `/gt_win` -> `/win`, `/gt_lobby_reserve` -> `/lobby_reserve`, `/gt_spawncreature` -> `/spawncreature`). Updated all 81 in-code / tooltip references to match, and refreshed `COMMANDS.md`.

- **One exception:** `/gt_regression_test` keeps its prefix — bare `regression_test` collides with GUI Tweaker's command (VT2 chat commands are global; first mod to register wins). Per-mod regression-test names are intentionally prefixed.
- `lobby_*` commands keep their `lobby_` prefix (only `gt_` was removed): `/lobby_reserve`, `/lobby_ignore`, `/lobby_motd_set`, etc.
- **Collision check:** verified against every other mod in the repo — the only clashes were `regression_test` (kept prefixed) and `win` (clashes only with the frozen, non-loadable legacy `tweaker` mod, so safe; gt already uses bare `god`/`unstuck` the same way). Keybind `function_name`s and setting_ids are unchanged — only the chat-command names.
- Note: gt_dev's Workshop **description** still lists old `/gt_*` command names (and references removed features) — a separate refresh is pending.

## v0.2.163-dev (2026-06-30) -- Gameplay menu: sort + convert Prioritize Specials / Grail Knight Quests to master toggles

Menu restructure with one behavior change (the new Prioritize Specials master gate).

- **Prioritize Specials is now a master toggle** (`gt_prio_specials_enabled`, default off) named **"Prioritize Specials (Tagging, Deepwood and Soulstealer)"**, replacing the plain `gt_prio_specials_group`. Its three context sub-toggles — **Tagging**, **Deepwood Staff**, **Soulstealer Staff** (relabelled, dropping the redundant "Prioritize Specials --" prefix) — now default **ON**, so flipping the master on activates all three at once. `_gt_prioritize_specials.lua` gates each hook on `master AND sub` via a new `_prio_on()` helper. **Migration:** the master defaults off (feature stays off by default, as before); a user who had previously enabled a sub-toggle must now also enable the master for it to take effect.
- **Choose Grail Knight Quests unwrapped.** Removed the redundant single-item `gt_gk_group` collapsible (both it and its only child read "Choose Grail Knight Quests"); `gt_gk_quests_enabled` is now a direct master toggle in Gameplay.
- **Gameplay sorted** per the standing rule. With both former groups now master toggles, Gameplay has no nested groups, so all members are loose options alphabetical by label: Choose Grail Knight Quests · Disable Friendly Fire · Healer's Touch… · Prioritize Specials…

(Cheats and Debug still has its nested groups at the bottom — that one's still pending in the full-mod sorting pass.)

## v0.2.162-dev (2026-06-30) -- Loc: remove em dashes from all menu strings

Localization-only style pass. Replaced every em dash (`—`) in the menu labels/tooltips with the file's existing ASCII `--` convention (per user preference — no more em dashes in GT menus). No wording or behavior changes.

## v0.2.161-dev (2026-06-30) -- Loc: rename the "Bot Options" group to "Bots"

Localization-only. The `gt_bot_options_group` label is now **"Bots"** (was "Bot Options"). Still sorts first among the top-level groups (Bots · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals and Audio).

## v0.2.160-dev (2026-06-30) -- "More Corpses" → single "Max Ragdolls" slider (no toggle); drop "(debug)" from Draw boss-event spheres

- **More Corpses reworked into a single "Max Ragdolls" slider.** Dropped the `gt_more_corpses_enabled` enable toggle and the nested sub-widget. `gt_more_corpses_count` is now a standalone, always-live numeric labelled **"Max Ragdolls"**, default **24** (vanilla cap), range **1–300** (was 1–500 nested under the toggle). `_gt_godmode_qol.lua`'s apply function no longer gates on the removed toggle — it always pins both `RagdollSettings.max_num_ragdolls` and `min_num_ragdolls` to the slider value (holds a steady count rather than sawtoothing to vanilla's min of 10). on_setting_changed branch narrowed to `gt_more_corpses_count`. setting_id preserved, so existing values carry over. Note: default 24 now pins min=max=24, marginally more corpses than pure vanilla (min 10) — set lower if you want fewer.
- **"Draw boss-event spheres (debug)" → "Draw boss-event spheres".** Dropped the "(debug)" suffix.

## v0.2.159-dev (2026-06-30) -- Simplify bot follow distance: drop the enable toggle, slider is the sole control (default 40 = off)

Removed the **"Tighter bot follow distance"** enable toggle (`gt_bot_follow_distance_enabled`) — the widget, both loc keys, and the gate in FIX 7 (`_gt_bot_fixes.lua`, `BTConditions.should_teleport`). The **"Follow snap-back distance (meters)"** slider (`gt_bot_follow_distance_m`) is now the sole control, defaulting to **40** — which is vanilla's own teleport gate, so 40 (or above) is a no-op (off). Lower the slider to tighten the leash. Per-distance behavior is unchanged; this just collapses two widgets into one.

- `gt_bot_follow_distance_m` setting_id preserved, so existing values carry over. Untouched users get the new default 40 (= off, same as the old toggle-off default). Edge case: a user who had explicitly lowered the slider *while leaving the old toggle off* will now have that distance take effect — re-set to 40 to disable.

## v0.2.158-dev (2026-06-30) -- Remove duplicate "Disable level intro audio" (GUI Tweaker owns it)

Removed gt's `gt_solo_disable_intro_audio` toggle entirely — the widget (from the Visuals and Audio group), both loc keys, and the `StateLoading._trigger_sound_events` hook in `_gt_solo_qol.lua`. It duplicated GUI Tweaker's **"Disable Level Intro Audio"** (gut's HideBuffs fork, `hb/level_loading_screen.lua`, same hook target). Use the gut toggle instead. No other gt code referenced the setting.

## v0.2.157-dev (2026-06-30) -- FIX invalid-format crash on the save-item slider; lobby menu reorg + sorting rule

### FIX -- "invalid string format" error on the save-item proc-chance slider

v0.2.156's rename put a literal `%` in `gt_adventure_save_trait_chance` ("...Grenadier % Chance"). VMF's `mod:localize` runs every string through `string.format` (safe_string_format), so the bare `%` was read as a format spec (`% C` -> "invalid option to 'format'") and errored on every menu render. It was **not** the commas. Fixed by escaping to `%%` (renders as a literal `%`).

**Test gap closed:** the pre-ship static guard `qa/check_localization.ps1` (Find-UnescapedPercent) already had an unescaped-`%` check, but its logic wrongly treated `% ` (percent-space) as safe, so the bad string shipped in .156. Rewrote it to strip `%%` pairs first, then flag any remaining `%` that doesn't begin a valid Lua format directive. The runtime twin (`localization_format_safe` regression test) already covered this. RULE: any literal `%` in a loc string must be doubled to `%%`.

### Menu reorg
- **Allow Duplicate Careers + Unlock All Ranked Weaves → Host-Side Lobby Controls** (moved out of Gameplay). Allow Duplicate Careers re-tagged **[confirmed working]**.
- **Modded Lobby Manifest → top of Host-Side Lobby Controls**; the group's loose options are now alphabetical by label.

### Sorting rule (now standing convention for this mod)
Within every settings group: **nested sub-groups first (top)**, then **loose options alphabetical by display label** (status tags like `[untested]` ignored for the sort), except where a deliberate order is specified. Dependent sub-options (e.g. idle threshold/warn under Auto-kick) stay directly beneath their parent. Applied to Host-Side Lobby Controls this release; other groups (Cheats and Debug, Gameplay) still have their nested groups at the bottom — a full-mod pass is pending.

## v0.2.156-dev (2026-06-30) -- Menu/loc: Bot Takeover toggles → Bot Options; rename the adventure save-item slider

No behavior change — all setting_ids preserved.

- **Bot Takeover + AFK Bot Takeover → Bot Options.** `ai_takeover_enabled` ("Bot Takeover") and `gt_ai_afk_takeover` ("AFK Bot Takeover") moved out of Gameplay into the Bot Options group — handing your hero to bot AI is a bot-control feature. `/ai` chat command unchanged.
- **Adventure save-item slider renamed.** `gt_adventure_save_trait_chance` label is now **"Healer's Touch, Home Brewer, Grenadier % Chance"** (was "Adventure save-item trait chance (percent)") — names the three traits it controls. range / behavior / tooltip unchanged.

## v0.2.155-dev (2026-06-30) -- Menu reorg: enemy-spawn toggles → Cheats and Debug; MOTD → Modded Lobby Manifest

Pure menu placement — no behavior change, all widget setting_ids preserved.

- **Disable Enemy Spawns + Clear Enemy Spawns → Cheats and Debug.** `disable_enemy_spawns` and the `clear_enemies_hotkey` keybind moved out of Gameplay into Cheats and Debug, beside godmode / noclip (they're cheat-style combat toggles).
- **Message of the Day → Modded Lobby Manifest sub-group.** `gt_lobby_motd_enabled` ("Send MOTD to joiners"), `gt_lobby_motd_send_chat` ("Send via chat"), `gt_lobby_motd_send_popup` ("Send via popup") moved out of the parent Host-Side Lobby Controls into the nested **Modded Lobby Manifest** group. The `gt_lobby_motd_once_per_peer_per_session` sub-option came along so the MOTD block stays together (would otherwise be orphaned in the parent). Both MOTD and the mod-list manifest are host→joiner broadcasts.

## v0.2.154-dev (2026-06-30) -- Menu/loc: auto-restart → Lobby Controls; "Visuals" → "Visuals and Audio"; "AI Takeover" → "Bot Takeover"

Pure menu/labeling changes — no behavior change, all widget setting_ids preserved so existing user settings and `mod:get(...)` reads keep working.

- **Auto-restart on team wipe → Host-Side Lobby Controls.** `gt_solo_auto_restart_on_wipe` moved out of the Visuals group into Host-Side Lobby Controls (beside Ready Up) — it's a host-side match-flow control, not a visual. setting_id unchanged; `_gt_solo_qol.lua` reads it the same way.
- **"Visuals" → "Visuals and Audio".** `gt_solo_group` display label updated (setting_id preserved) — the group also holds the VO / intro-audio toggles, so the name now reflects its contents.
- **"AI Takeover" → "Bot Takeover".** `ai_takeover_enabled` is now **"Bot Takeover"** (dropped the redundant "(bot controls your character)" parenthetical, consistent with the .151/.153 de-parenthetical pass); `gt_ai_afk_takeover` is now **"AFK Bot Takeover"**. Tooltip self-reference updated to match. Chat command `/ai` unchanged.
- **Note — More Corpses duplicate:** the duplicate "More Corpses" toggle (the standalone `gt_corpses_group` that wrapped a same-named checkbox) was already removed in **v0.2.151-dev** when More Corpses merged into Visuals. This build carries that fix for anyone still running a pre-.151 bundle.

Top-level menu order unchanged: Bot Options · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals and Audio · [Debug Logging].

## v0.2.153-dev (2026-06-30) -- Loc: drop "(AI Teammates)" suffix from the Bot Options group label

Cosmetic localization-only change. The top-level settings group `gt_bot_options_group` now reads **"Bot Options"** instead of "Bot Options (AI Teammates)" — the parenthetical was redundant. No widgets, settings, or behavior changed.

## v0.2.152-dev (2026-06-29) -- FIX: bots no longer leash AWAY from a downed teammate (#139 sibling case) + new "Bot follow mode" dropdown

Two bot-fixes shipping together — they were diagnosed together when the user reported "bots teleport away when a player is downed", and the menu consolidation made the diagnosis easier to explain.

### Fix — leash no longer pulls bots away from a downed teammate

**Symptom (user report 2026-06-29):** a teammate goes down and bots **teleport over to a living player** instead of helping. They then have to walk back from far away, often arriving too late.

**Root cause — sibling of #139, not yet covered by the v0.2.148-dev fix.** The tighter leash (FIX 7, `BTConditions.should_teleport`) teleports a bot to its `follow_unit`. FIX 3b's aid-priority exemption only fires after `target_ally_need_type` is set, which the aid-picker only assigns once per BT tick. On the frame a teammate is newly downed, the bot's `follow_unit` is still a LIVING far-away player → the leash fires → bot teleports AWAY from the downed teammate. The v0.2.148-dev #139 fix only suppressed the leash when `follow_unit` itself was downed; it didn't cover the case where `follow_unit` is alive but a different teammate needs aid. This sibling case is what the user was reporting.

**Fix (`_gt_bot_fixes.lua`, FIX 7):** added `_gt_any_side_teammate_needs_aid(self_unit)` helper that walks `side.PLAYER_UNITS` and returns the first knocked-down / hooked / ledge-hanging ally found. The `should_teleport` hook now suppresses the tighter leash whenever this helper returns non-nil — so if anyone on the bot's side needs aid the leash sits out, and FIX 3b's aid-priority gets the chance to assign `target_ally_need_type` so the bot paths in to help instead of teleporting away. Marker `GT_BOT139_LEASH_AID_SIDEAID_MARKER_v0_2_152` + regression test `bot_leash_no_teleport_away_from_side_aid_marker_present`.

**Diagnostics (printf, mod-logging off visible, prefix `[gt_bot:139s]`):** one line per save: `tighter-leash teleport SUPPRESSED -- teammate needs aid (bot will path to help instead of leashing away)`. Per-blackboard dedupe so it doesn't spam.

### New "Bot follow mode" dropdown

The previous two checkboxes — `gt_bot_split_among_players` and `gt_bot_follow_host` — were opposite strategies with implicit precedence (`follow_host` won when both were on). Consolidated into one tri-state dropdown `gt_bot_follow_mode`:

- **Default** — vanilla bot follow behaviour (cluster around whoever is moving, swap after ~20s of standstill).
- **Follow Host** — every bot leashes to the host regardless of party position.
- **Split** — round-robin one bot per human, host first (former `gt_bot_split_among_players`).

Default value: `"default"`. The `_assign_destination_points` hook reads the new dropdown via `mod._gt_resolve_follow_mode()`, which falls back to the legacy `gt_bot_follow_host` / `gt_bot_split_among_players` checkbox values when the dropdown setting hasn't been written yet — so existing user state migrates on first read without a forced reset. Old loc keys retained for documentation; the widgets are gone from the menu. Marker `GT_BOT_FOLLOW_MODE_DROPDOWN_MARKER_v0_2_152` + regression test `bot_follow_mode_dropdown_consolidated`.

**Needs host in-game verification:**
1. Pick **Follow Host**, split the party, down a non-host teammate at distance → bots should walk in to revive, NOT teleport to the host first.
2. Pick **Split**, same scenario → same result.
3. Each mode should still behave as before in steady-state (Follow Host: all bots near host; Split: one bot per human; Default: vanilla).

## v0.2.151-dev (2026-06-29) -- Menu reorg: Ready Up + Manifest into Lobby Controls; More Corpses + Solo merged into Visuals; new "Info" group; "Disable Bots (Solo)" → "Disable Bots"

Pure menu/labeling reorganization, no behavior changes. All widget setting_ids preserved so existing user settings carry over and code reads against `mod:get(...)` keep working unchanged.

- **Ready Up → Host-Side Lobby Controls.** The `gt_readyup_group` ("Ready Up") section is gone; its two widgets (`gt_ready_up_hotkey` keybind, `gt_auto_ready_on_vote_pass` checkbox) now sit at the bottom of Host-Side Lobby Controls. Both are host-side lobby-flow controls, so co-locating them with slot reservations / kick-on-idle / MOTD / etc. makes the menu easier to scan.
- **Modded Lobby Manifest → nested collapsible inside Host-Side Lobby Controls.** The two manifest-related widgets (`gt_lobby_manifest_broadcast_enabled` host-side broadcast, `gt_lobby_manifest_failnotify_enabled` client-side failed-join reveal) are now wrapped in a `gt_lobby_manifest_group` collapsible sub-group inside the parent Host-Side Lobby Controls. Declutters the parent menu; both widgets reachable in one click.
- **More Corpses merged into Visuals.** The standalone `gt_corpses_group` ("More Corpses") top-level menu is gone; its single feature (`gt_more_corpses_enabled` with its `gt_more_corpses_count` sub-slider) now lives at the bottom of the `gt_solo_group` section. The corpse cap is a visual feature, so co-locating it with the other visual toggles (disable fog / sun shadows / mutator explosions / draw boss spheres) consolidates a one-item top-level menu.
- **"Solo & QoL (from True Solo)" → "Visuals".** The `gt_solo_group` display label is renamed (setting_id preserved). Three on-screen-text widgets split out (see next bullet) leaving a section that's primarily visual toggles.
- **New "Info" top-level group.** On-screen text readouts split out of the old Solo group into a focused `gt_info_group`: `gt_solo_assassin_text_warning`, `gt_solo_packmaster_text_warning`, `gt_solo_boss_path_progress`. Widget IDs preserved (still `gt_solo_*`) so the `_gt_solo_qol.lua` reads keep working — only the menu placement moves.
- **"Disable Bots (Solo)" → "Disable Bots".** The trailing parenthetical was redundant (the tooltip already covers the host-only / solo-friendly use case). `gt_no_bots` setting_id unchanged.

Top-level menu order (alphabetical, with Debug Logging pinned last per convention) is now: Bot Options · Cheats and Debug · Gameplay · Host-Side Lobby Controls · Info · Visuals · [Debug Logging].

## v0.2.150-dev (2026-06-29) -- MIGRATE OUT to gui_tweaker: Floating Damage Numbers, Main Menu & Startup (#190), 3rd-Person Camera (#191), Loading-Screen Monologues (#192)

Four features moved out of gt and into `gui_tweaker` (gut), which now owns them. Removed from gt: the options widgets, loc keys, handlers, dispatch branches, and the related regression tests. No behaviour change to anything that stays in gt.

- **Floating Damage Numbers** removed (`gt_damage_numbers_group`). The two `DamageUtils.add_damage_network` / `add_damage_network_player` hooks STAY in gt as **pure godmode** again — only the floating-damage-number feed lines were stripped from them, and the `_gt_damage_numbers.lua` dofile was removed (file → `.bak.v0.2.149-dev`). gut registers its own clean hooks on those methods (different mod, so VMF chains across mods — no conflict).
- **Main Menu & Startup (#190)** removed (`gt_menu_qol_group`: `gt_skip_start_screen`, `gt_return_to_menu_quits`). Dropped the on_setting_changed / on_disabled dispatch, the `/gt_quit` command, `_gt_menu_qol.lua` (→ `.bak`), and the `menu_qol_settings_registered` + `menu_qol_return_quits_roundtrips` regression tests.
- **3rd-Person Camera (#191)** removed (`tp_camera_group` + all `tp_*` settings, `/tp` command, `_gt_camera.lua` → `.bak`). **Care point:** `_gt_camera.lua`'s `PlayerUnitFirstPerson.extensions_ready` hook *also* triggered the godmode/noclip post-spawn re-apply (`mod._gt_schedule_post_spawn_reapply`). Since VMF forbids a 2nd hook on the same pair, a **slim copy of that hook** (only the schedule call) was relocated into the main chunk beside the scheduler, so godmode/noclip re-apply still fires on spawn. Removed the camera on_setting_changed / on_disabled / on_game_state_changed dispatch and the `tp_camera_yields_to_cutscene` regression test.
- **Disable Loading-Screen Monologues (#192)** removed (`gt_cutscenes_group`, now empty after cutscene-skip migrated in #106). Stripped the on_setting_changed branch, the `_gt_godmode_qol.lua` monologue block + `/gt_intromono` command. gut owns `gut_disable_intro_monologue` + `/gut_intromono`.

## v0.2.149-dev (2026-06-29) -- HARDEN: nil-guard BTConditions.at_*_health family (#59 belt-and-suspenders)

**Issue #59** had two suggested fixes: (1) match the `dlc_castle` level family by prefix so CW theme variants (`dlc_castle_slaanesh_path1`, etc.) hit the vanilla Drachenfels boss path instead of gt's arena-less fallback — **already shipped** (`_gt_creature_spawner.lua`, `_gt_cs_is_in_level` with underscore-boundary match) — and (2) **defensively nil-guard** the `BTConditions.at_*_health` family so any first-tick race (boss spawned + BT evaluates a health condition before `AISystem.update_blackboard_health` writes `blackboard.current_health_percent`) biases to FALSE rather than crashing on `nil <= number`. This release ships fix #2.

**Fix (`_gt_creature_spawner.lua`):** wrap each of the eight blackboard-health conditions in a nil-guard helper. Two helpers, one for the seven that read `current_health_percent` and one for the lone `less_than_one_health` that reads raw `current_health`. The guard biases to FALSE (boss has not yet hit the threshold) when the field is nil — the next tick `update_blackboard_health` writes the real value and vanilla logic resumes. Hooks added: `at_half_health`, `at_one_third_health`, `at_two_thirds_health`, `at_one_fifth_health`, `at_three_fifths_health`, `can_transition_half_health`, `can_transition_one_third_health`, `less_than_one_health`. Each is a distinct `(BTConditions, <method>)` pair — no duplicate-hook collision with the existing `transitioned_one_third_health` hook (different method).

**Diagnostics (printf — visible with mod-logging off, per `[gt_bt:#59]` prefix):** the first time the guard saves each `(breed, condition)` pair, it logs one line: `nil-guard suppressed at_one_fifth_health on breed=chaos_exalted_sorcerer_drachenfels (current_health_percent uninitialized -- first-tick race)`. Per-pair dedupe (`_gt_bt_health_nil_seen[breed|cond] = true`) so the BT tick loop doesn't spam — one line per real save. **If you ever see one of these in a log, the race is real** and the guard is doing its job. New regression marker `GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149` + `bt_health_conditions_nilguarded_marker_present` check.

Covers Drachenfels (Chaos Sorcerer) — and now also any other boss BT (Skarrik, Nurgloth, Bödvarr, etc.) that ever races a health-condition tick against blackboard init. No behavior change for the steady-state read; only the first-tick nil window is suppressed.

## v0.2.148-dev (2026-06-29) -- FIX: bots no longer teleport onto a newly-downed teammate when the team is split (#139)

**Symptom (#139):** when a player goes down while the team is split up, bots **teleport onto the downed player** instead of pathing in to revive — abandoning their split position.

**Root cause:** gt's tighter follow-leash (FIX 7, `BTConditions.should_teleport`, default 12 m vs vanilla 40 m) teleports a bot to its `follow_unit`. FIX 7 already exempts a bot that has `target_ally_need_type` set (it's heading to an aid target), but on the frame a split teammate is *newly* downed — **before** the aid-picker assigns that target — the bot is still in follow mode pointed at that teammate. So the tighter leash fires and snaps the bot onto the downed player rather than letting it walk in and revive.

**Fix (`_gt_bot_fixes.lua`, FIX 7):** added a guard — if the leash would fire and the `follow_unit` currently needs aid (knocked down / hook / ledge, via new `_gt_unit_needs_aid` helper), suppress the GT tighter-leash teleport and let the bot path in to revive. Vanilla's 40 m teleport (the wrapped `func()` call at the top of the hook) still applies as a last-resort catch for truly-far cases, so a genuinely stranded bot isn't left behind.

**Diagnostics (printf — visible with mod-logging off):** `[gt_bot:139] tighter-leash teleport SUPPRESSED …` when the guard fires, and `[gt_bot:139] TELEPORT executed (follow downed=…)` on every actual teleport. If the latter ever reports `follow downed=true` after this build, the snap came from vanilla's 40 m path and the fix needs extending to gate that too.

New regression marker `GT_BOT139_LEASH_AID_GUARD_MARKER_v0_2_148` + `bot_leash_no_snap_to_downed_marker_present` check. No new hooks (modified FIX 7's existing `should_teleport` body + enriched the existing `BTBotTeleportToAllyAction.run` probe) — no duplicate-hook risk. **Needs host in-game verification: split the team, down a teammate, confirm bots WALK to revive instead of snapping.**

## v0.2.147-dev (2026-06-29) -- FIX: necromancer bot can raise skeletons in the keep (Bots in Keep sub-feature)

**Symptom (user report 2026-06-29):** with **Allow Bots in Keep** on, a Necromancer bot "keeps trying over and over but can't raise skeletons."

**Root cause:** Fatshark forbids necromancer pets in the hub by design — a necromancer (player *or* bot) can't raise skeletons in the keep / CW hub. The gate is `PassiveAbilityNecromancerCharges._pets_forbidden_in_level`, computed in `_on_talents_changed` as `script_data.pets_forbidden_in_hub and is_in_inn_level` (`passive_ability_necromancer_charges.lua:108-110`). Both `spawn_pet` (line 202) and `_update_pets_server` (line 327) early-return when it's true. The bot's raise-dead AI keeps firing its action, but every `spawn_pet` hits that early-return → endless no-op loop.

**Fix (`_gt_bots_keep.lua`):** when **Bots in Keep** is active, post-hook `_on_talents_changed` (the method where vanilla *sets* the flag, fired as the bot's passive ability initializes on keep entry) and clear `_pets_forbidden_in_level` for **bot necromancers only** (`player.bot_player == true` via `Managers.player:owner`). Human-player keep behavior is left exactly as vanilla. The real spawn path (`_spawn_pet_server` → `Managers.state.conflict:spawn_queued_unit`) uses systems the keep has (conflict director — gt already hooks it; side system; ai_system nav_world — our bots navigate it), and `warm_up_skeletons` preloads the breed packages for the bot on the host, so skeletons can actually spawn once the gate is lifted.

`hook_safe` (post): vanilla computes the flag first, then we clear it. No duplicate-hook risk — grepped gt_dev, this is the only hook on `PassiveAbilityNecromancerCharges`; VMF hook_safe chains across mods. New regression marker `GT_BIK_NECRO_KEEP_PETS_MARKER_v0_2_147` + `bots_in_keep_necro_pets_marker_present` check. **EXPERIMENTAL — needs host in-game verification (keep → bot necromancer raises skeletons, no crash/clutter). If skeletons in the keep prove unstable, fall back to suppressing the bot's raise-dead loop instead.**

## v0.2.146-dev (2026-06-29) -- ENABLE: 'Allow Bots in Keep' revived + both crash classes fixed (#65)

Un-kill-switched **Allow Bots in Keep** (`gt_bots_in_keep`), disabled since v0.2.74-dev. The two crash classes from #65 are fixed structurally by porting the proven inn-bot lifecycle from the **Photo Mode** mod (workshop 3743797855), verified against the decompiled source:

- **Bug 1 — stat-leak fassert on keep exit** (`"Stat id <peer>:<lpid> not unregistered"`, GUID `70b90096…`): bots are now torn down from a `hook_safe` on `GameModeInn`/`GameModeInnDeus.cleanup_game_mode_units`. `StateIngame.on_exit` calls that at `state_ingame.lua:1911` — **before** `check_venture_end` (2119) destroys the venture stats manager — and `_remove_bot_instant` unregisters each bot's stat there, while Player refs are valid. The old `_bik_reset_bookkeeping` (which only dropped the Lua tracking table without unregistering) is now a no-op so it can't race the cleanup hook.
- **Bug 2 — `"No empty slot in party heroes"` on host join** (GUID `faed01a7…`): fill is now driven from the inn mode's `server_update` (only ticks once the session is running) **and** gated on `_bik_host_in_party1()`, so bots are never added until the host already holds its party-1 slot. Fill only ever takes OPEN slots, so it can't claim the host's slot.

Implementation (`_gt_bots_keep.lua`): replaced the old generic per-frame fill tick with `hook_safe` on `GameModeInn`/`InnDeus` `server_update` (fill) + `cleanup_game_mode_units` (teardown). `_bik_active()` now returns the live `gt_bots_in_keep` setting (kill-switch removed). Added engine `printf` on fill. New regression marker `GT_BIK_CRASHFIX_MARKER_v0_2_146` + `bots_in_keep_crashfix_marker_present` check. No duplicate-hook collisions (grepped). VMF hooks chain across mods, so this coexists with Photo Mode if both are installed. **Host-only; needs host in-game verification (keep load → bots fill, keep exit → no crash).**

## v0.2.145-dev (2026-06-29) -- Menu: move bot-roster toggles into Bot Options

Moved **Disable Bots (Solo)** (`gt_no_bots`) and **Allow Bots in Keep** (`gt_bots_in_keep`) out of the **Gameplay** group and into **Bot Options**, where they belong (both are bot-roster controls). Placed at the top of Bot Options — roster presence (whether bots exist / where) before the behavior tweaks (combat, follow, reactions). No behavior change; widget IDs unchanged so existing user settings carry over. `gt_bots_in_keep` is still runtime kill-switched (#65).

## v0.2.144-dev (2026-06-29) -- FIX: `_dbg_on` nil-global error spam (orphaned v0.2.142-dev refactor)

**Symptom (from the 2026-06-29 console log):** `_gt_debug_probes.lua:893: attempt to call global '_dbg_on' (a nil value)` fired on every `StateIngame` enter, and `:744` on unit relinquish.

**Root cause:** the v0.2.142-dev "gate removed; routes through VMF logging" refactor dropped the `_dbg_on` predicate from the logger but left **5 call sites** still gating the heavy AI/menu *dump triggers* on `_dbg_on()` (lines ~724/744/857/863/893). `_dbg_on` was then undefined anywhere in the mod (`mod._dbg_on` was referenced by comments + `_gt_ai_takeover.lua` but never assigned). Caught by VMF's event pcall, so it didn't crash, but it spammed errors and silently killed the AI/menu dump probes. (This is why the orphaned `.142` bump carried no CHANGELOG entry — it was a half-finished refactor.)

**Fix (`_gt_debug_probes.lua`):** restored `_dbg_on` as a file-local predicate gating on `enable_debug_logging`, and exposed it as `mod._dbg_on`. The logger (`_dbg`/`_dbg_log`) correctly stays ungated (routes through VMF `mod:debug`); only the expensive dump triggers use the gate. Pre-existing bug, independent of the #194 no_bots fix.

## v0.2.143-dev (2026-06-28) -- FIX: 'Disable Bots (Solo)' (gt_no_bots) now actually disables bots (#194)

**Symptom:** the **Disable Bots (Solo)** toggle (`gt_no_bots`) did nothing in-game — bots were never despawned or blocked. (`bots_in_keep` remains separately kill-switched, #65 — unchanged here.)

**Root cause:** `mod._gt_apply_no_bots` did `script_data = script_data or {}` — writing the bare `script_data` global *name*. Under VMF's mod environment that rawsets `script_data` into the mod env table; because this file applies the setting once at mod load, if `_G.script_data` wasn't populated yet at that first call it cached a **private empty table** that then permanently shadowed the real `_G.script_data` the game's `_handle_bots` reads. So the `ai_bots_disabled` flag the engine checks every server tick never flipped. The proven no-bots mods (SpawnTweaks / TrueSoloQoL) only ever *field-mutate* `script_data`, never assign the name — which is exactly why they work.

**Fix (`_gt_bots_keep.lua`):**
- `_gt_apply_no_bots` now mutates the **real engine global** via `rawget(_G, "script_data")` and never writes the `script_data` name. If the global isn't up yet at load, it no-ops and lets the enforce hooks / StateIngame re-apply set it.
- **Enforcement hooks (belt-and-suspenders, the proven mechanism):** hook `_handle_bots` on `GameModeAdventure` / `GameModeDeus` / `GameModeWeave` and re-assert `script_data.ai_bots_disabled = true` from the live `gt_no_bots` setting every server tick. Mirrors SpawnTweaks / TrueSoloQoL; immune to any flag-reset / load-order / first-frame timing race. Covers Adventure + Chaos Wastes (Deus) + Weave. Host-only by nature (only the host runs `_handle_bots`).
- **Crash guard:** `pcall` `AdventureSpawning.force_update_spawn_positions` while `gt_no_bots` is on — the proven mods do this ("Prevent a crash with disabled bots"). The crash was latent pre-fix because bots were never actually suppressed.
- **Diagnostics:** added engine `printf` on apply + first enforce tick (`[gt_no_bots] ...`) so the host path is confirmable with mod-logging off. (Remove once verified in-game.)

No duplicate-hook risk: grepped gt_dev — nothing else hooks `_handle_bots` on the three game modes or `AdventureSpawning.force_update_spawn_positions`. **Needs host in-game verification.**

## v0.2.142-dev (2026-06-28) -- Removed per-mod debug toggle; diagnostics routed through VMF logging (#169)

Removed the `enable_debug_logging` per-mod checkbox. All diagnostic calls now go through VMF's built-in logging channels (`mod:debug` / `mod:warning`), gated by VMF's own **output_mode_debug** / **output_mode_warning** settings.

- Removed `enable_debug_logging` widget from data + localization.
- `_dbg` helper → `mod:debug(...)`. `_dbg_alert` helper → `mod:warning(...)`.
- `_log_settings_snapshot` early-return guard removed; inner `mod:info` → `mod:debug`. Command description simplified.
- `_gt_debug_probes.lua`: removed `_dbg_on()` gating function; removed 4 temp-force-enable patterns from the `gt_ai_slotdump` / `gt_bot_loadout_dump` auto-dump commands.
- `_gt_bot_fixes.lua`: ~13 inline `mod:get("enable_debug_logging")` gates dropped; `mod:info` → `mod:debug` throughout.
- `_gt_lobby_motd.lua`: fallback `_dbg_alert` branch simplified.
- Regression test `dbg_helpers_two_channel` updated (remove toggle-save/restore lines).

## v0.2.141-dev (2026-06-28) -- 3rd-person camera distance min lowered 1.0 -> -3.0

`tp_distance` slider range is now `{ -3.0, 10.0 }` (was `{ 1.0, 10.0 }`) so the camera can pull in closer / over-the-shoulder, per user request.

## v0.2.140-dev (2026-06-25) -- Skip Cutscenes moved out to gui_tweaker (gut), issue #106 migration

**Feature MOVED OUT — no behavior change for gt's other features.**

- **Skip Cutscenes migrated to gui_tweaker (gut).** The "Skip Cutscenes" / "Auto-skip Cutscenes" feature (Aussiemon "Skip Cutscenes" port) moved out of gt and into gut as part of issue #106 (the Blood-in-the-Darkness / `dlc_castle` stuck-cutscene investigation — gut adds a printf diagnostic that survives mod-logging-off, which gt's `mod:info` lines did not). Removed from gt:
  - `_gt_cutscenes.lua` (renamed to `_gt_cutscenes.lua.bak.v0.2.139`, not deleted) — owned the `CutsceneSystem.flow_cb_cutscene_effect` / `flow_cb_activate_cutscene_logic` / `skip_pressed` + `ShowCursorStack.pop` hooks, the `cutscene_auto_skip` deferred update consumer, `/gt_skipcutscenes`, and `mod.gt_skip_cutscenes_toggle`.
  - the `on_setting_changed` branch for `gt_skip_cutscenes_enabled` (which set `script_data.skippable_cutscenes`).
  - the `gt_skip_cutscenes_enabled` / `gt_skip_cutscenes_auto` data widgets + their localization keys (the `gt_cutscenes_group` group is retained for the loading-screen monologue toggle, which stays in gt).
  - the two regression checks `cutscene_auto_skip_deferred` / `cutscene_skip_setting_id_present` (now live in gut).
- **Kept in gt:** the Third-Person Camera cutscene-yield fix (v0.2.139-dev, `PlayerUnitFirstPerson.set_first_person_mode` in `_gt_camera.lua`) — it only READS the cutscene system (`is_active()`), never hooks it, so it is a separate feature and unaffected. Its `tp_camera_yields_to_cutscene` regression check stays.

## v0.2.139-dev (2026-06-24) -- FIX: Third-Person Camera no longer breaks the view after a cutscene

**Symptom:** with the Third-Person Camera enabled, the camera was left **broken after a cutscene played** -- reported on "Blood in the Darkness" / `dlc_bastion` when injected as a Chaos Wastes map (cutscenes also fire in other campaign missions; this is not bastion-specific).

**Root cause (source-cited).** At a cutscene's END, vanilla `CutsceneSystem.flow_cb_deactivate_cutscene_cameras` calls `self:set_first_person_mode(true)` (`Vermintide-2-Source-Code/scripts/entity_system/systems/cutscene/cutscene_system.lua:154`), which forwards to `first_person_extension:set_first_person_mode(true)` (cutscene_system.lua:123) with `override == nil` to RESTORE the player's first-person view. gt's Third-Person Camera hook on `PlayerUnitFirstPerson.set_first_person_mode` (`_gt_camera.lua`) blocks any `active and not override` call while TP is on (it exists to stop inspect/other systems from yanking the player back to 1P). The cutscene-end restore matches that exact shape (`active == true`, `override == nil`), so the hook **swallowed it** and the camera was never restored. `_tp_enabled` only clears on a game-state change (`general_tweaker_dev.lua` `on_game_state_changed`); a cutscene start/end is NOT a state change, so the block stayed live across the cutscene.

**Fix.** While a cutscene owns the camera, **yield** the block so the 1P restore goes through. The hook now bails out of the block when `CutsceneSystem:is_active()` is true (`is_active()` == `self.active_camera ~= nil`, cutscene_system.lua:83-85), looked up via `Managers.state.entity:system("cutscene_system")` (canonical access pattern, `flow_callbacks.lua:1050`) and pcall-guarded (the cutscene system isn't present at all times). This is robust at BOTH ends of the cutscene:
- During the cutscene, the per-frame `CutsceneSystem.update` calls `set_first_person_mode(false)` (cutscene_system.lua:64) -- `active == false`, which this block never matched, so nothing changes there.
- At deactivate, vanilla calls the 1P restore (cutscene_system.lua:154) BEFORE clearing `self.active_camera` (:156), so `is_active()` is still true at the exact moment our hook fires -> the restore passes through. The block self-heals the instant the cutscene camera goes away; no persistent state to leak (deliberately NOT clearing `_tp_enabled`, which is only re-armed on player spawn and would turn TP off permanently if flipped on cutscene end).

Normal TP-camera behavior is unchanged: during regular gameplay `is_active()` is false, so the spurious 1P restore (inspect, etc.) is still blocked exactly as before -- the yield is cutscene-only. SOLE hook on `PlayerUnitFirstPerson.set_first_person_mode` (existing hook body modified, no second hook added).

**Regression guard:** new `/gt_regression_test` check `tp_camera_yields_to_cutscene` -- source-pattern guard anchored on `mod._gt_apply_tp` (reads `_gt_camera.lua`) that FAILS if the `set_first_person_mode` hook no longer calls `_gt_cutscene_owns_camera()`, or if that helper no longer queries `cutscene_system` / `is_active`. Needle assembled from two literals so the check doesn't self-match.

## v0.2.138-dev (2026-06-24) -- FIX 1 give-half completion: Necromancer bot no longer gets stuck trying to pass a potion

**Symptom:** the Necromancer (`bw_necromancer`) bot would get **stuck trying to pass a potion but never complete the handoff**, looping in place.

**Root cause (source-cited).** FIX 1 in `_gt_bot_fixes.lua` already solved the *scoring* half: the Necromancer carries a non-droppable "skull" (`bw_necromancer_career_utility_weapon`, `slot_type="potion"`, `is_not_droppable=true`) that occupies the PRIMARY `slot_potion`, so a real potion picked up later lands in ADDITIONAL storage (`_additional_items["slot_potion"].items`). Every vanilla bot potion check reads only the PRIMARY slot:
- scoring `player_bot_base.lua:882-888` (`can_give_potion_to_other` off the primary template), and
- the give interaction `interactions.lua` `give` (`set_interactor_data`:1707-1711 captures `get_wielded_slot_name()`; the transfer `stop`:1640-1664 reads `get_slot_data(item_slot_name)` and gates on `template.can_give_other`:1646).

FIX 1's promote (swap the real potion to primary) is the right mechanism for BOTH halves — once the potion is primary, scoring, the give interaction, and self-drink all just work. **But the promote targeted the wrong storage occupant.** It scanned storage for *a* giveable potion, then called `swap_equipment_from_storage("slot_potion", SwapFromStorageType.First, ...)`. `SwapFromStorageType.First` promotes storage index 1 unconditionally (`get_additional_item_swap_id` returns `item_id=1`, ignoring the compare arg — `simple_inventory_extension.lua:2364-2365`). `slot_potion` storage is **not** potion-only: the **grimoire** also lives in `slot_potion` (`is_grimoire`, no `can_give_other` — `grimoire.lua:62`; bots stash it there — `bt_bot_conditions.lua:1244-1259` `should_drop_grimoire`), and the demoted skull lands there too. So with storage `= {grimoire, real_potion}` (or `{skull, ...}`), the First-swap promoted the grimoire/skull to primary, leaving primary STILL non-giveable. The give interaction could never resolve the real potion, and the bot looped "trying to pass but can't."

**Fix.** Locate the giveable potion's exact `item_data` reference (it lives in the live storage array we already iterate) and promote it **by identity** via `SwapFromStorageType.Same`, passing that `item_data` as the compare item — `get_additional_item_swap_id(Same)` returns the index where `stored_items[i] == compare_item` (`simple_inventory_extension.lua:2374-2385`). The REAL potion now lands in primary regardless of storage ordering; the grimoire/skull are never mis-promoted. Once the potion is primary, the whole vanilla give chain (and the bot drinking its own potion, REPLICANT PORT 2) just works. Necromancer-scoped (gated on `career_name() == "bw_necromancer"`), throttled ~1s, idempotent. No new hook (the existing single `PlayerBotBase.update` consolidation site drives the tick); no RPC; host-side only.

**Regression guard:** new `/gt_regression_test` check `necro_potion_give_half_targeted_promote` pins the `GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138` source-pattern marker AND asserts `SwapFromStorageType.Same` exists, so a refactor back to a blind First-swap (or a vanilla enum drop) is caught.

## v0.2.137-dev (2026-06-24) -- In-mission inventory MIGRATED out to gui_tweaker (gut)

The in-mission inventory feature moved out of gt and into **gui_tweaker (gut)**, which now owns it. Removed here:
- **Deleted** `_gt_mission_ui.lua` (Open Inventory In Mission + the `HeroWindowLoadoutConsole._customize_item` cim crash-gate + the `HeroWindowPanelConsole.on_enter` tab-strip restore) and `_gt_keep_menus.lua` (the InventorySettings loadout-access patch + ESC-menu "Open Inventory" entry). Their two `mod:dofile` lines are gone.
- **Removed** the `mission_inventory_enabled` branch from `on_setting_changed` and the `mod._gt_apply_keep_menus()` re-apply from `on_game_state_changed`.
- **Removed** the `mission_inventory_group` settings group (`mission_inventory_enabled` / `gt_mission_menu_tabs` / `gt_open_inv_hotkey`) from `_data.lua` and its loc keys (incl. tooltips) from `_localization.lua`. The `/gt_inv` command + `mod.gt_open_mission_inventory` field are gone (replaced by `/gut_inv` in gut).

**Kept intentionally:** the `gt_no_mission_hotkey_flip` regression test (Issue #62) stays — it guards against the removed `IngameUI.handle_menu_hotkeys` hotkey-flip hook being reintroduced, which is still a gt concern independent of where the inventory feature lives. It anchors on `mod.on_setting_changed` (a main-file field), so it still reads `general_tweaker_dev.lua` correctly. No other gt feature touched. Stale comment blocks describing the removed feature were updated to migration notes.

## v0.2.136-dev (2026-06-23) -- "Cap Bot Ult Cooldown" default hardening (no longer ults bots constantly the instant you enable it)

`ult_bot_cap_value` defaulted to `0`, and the clamp at `_gt_hacks.lua:207` (gated on `ult_bot_cap_enabled` + bot-only) sets every bot ability's remaining cooldown to that cap each `CareerExtension.update` tick — so `0` meant **bots ult constantly** the moment the toggle was switched on. That matched the loc ("0 = bots ult constantly") but is a footgun: a user enabling the toggle to "see bots ult more aggressively" got nonstop ults with no obvious cause. Changed the default to **20s** (aggressive but not unlimited; the loc's stated intent). No logic change — the clamp + gating are unchanged and correct; users can still set `0` explicitly for constant ulting. `ult_player_cap_value` left at `0` (a deliberate self-applied "always ready" cheat, off by default).

## v0.2.135-dev (2026-06-20) -- refactor (Phase 4, final): extract the three largest / highest-coupling feature blocks to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 4, the final phase of the main-file split begun in v0.2.132-dev). Carves ~2499 more lines out of `general_tweaker_dev.lua` (4506 -> 2007 lines) into three new `_gt_*` modules, loaded via the existing `mod:dofile` chain. Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules before the move. Dispatchers (`on_setting_changed` / `on_disabled` / `on_game_state_changed`) stay in main and resolve each moved feature through a `mod._gt_*` / `mod._gt_cs_*` / `mod._gt_ai_*` field at call time. The `/gt_regression_test` block stays in main; every check that referenced a moved symbol was repointed to the matching `mod._*` exposure (all 29 checks preserved, byte-identical name list to the pre-phase file). Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_creature_spawner.lua`** -- the Aussiemon CreatureSpawner port (Workshop 1395132559), ~983 lines, ~28 hooks. Every hook is a singleton (verified across main + all modules): the keep-spawn `ConflictDirector.update` strip-down (a DIFFERENT method from the consolidated `ConflictDirector.spawn_queued_unit` hook, which STAYS in main), `StateIngame.update`, `AISystem.update_brains`, `AIGroupSystem.update`, `AiBreedSnippets.reward_boss_kill_loot`, `AiUtils.update_aggro`, `ProjectileEtherealSkullLocomotionExtension.init`, `BTEnterHooks.warlord_defensive_on_enter`, `BTSpawnAllies.{enter,run,leave,find_spawn_point}`, `Breeds.chaos_exalted_sorcerer_drachenfels.{run_on_spawn,run_on_death}`, `BTConditions.transitioned_one_third_health`, `BTLootRatFleeAction.{enter,run,leave}`, `NavigationGroupManager.a_star_cached_between_positions`, `LocomotionUtils.pos_on_mesh`, `GwNavQueries.inside_position_from_outside_position`, `Unit.create_actor` (DISTINCT method from `Unit.get_data` in `_gt_hacks.lua`), `BTSkulkAroundAction.get_new_skulk_goal`, `Utility.get_action_utility`, `BuffSystem.add_buff`, `World.spawn_unit`, `EnemyPackageLoader.request_breed`. The two forward-declared file-local callbacks (`_gt_cs_on_setting_changed` / `_gt_cs_on_game_state_changed`, consumed by the main `on_setting_changed` / `on_game_state_changed` DISPATCHERS) were promoted to `mod._gt_cs_*` fields; the helper `_gt_cs_is_in_level` was exposed as `mod._gt_cs_is_in_level` and the `gt_cs_is_in_level_prefix_match` regression check repointed to it. Self-contained otherwise (own `gt_cs_*` settings + commands).
- **New `_gt_ai_takeover.lua`** -- AI Takeover (hand your character to a bot) + AFK->AI takeover, ~615 lines. The destructive swap remains DISABLED pending the keep-slot redesign (`mod._gt_ai_takeover_disabled` -- behavior unchanged; every entry point still bails). The only `(Class, method)` registration is the `_AI_RPC` (`gt_ai_toggle_request`) VMF network event (`mod:network_register`, not a `mod:hook`). **Forward-decl promotions:** the cross-boundary file-locals shared with main's DISPATCHERS / debug dump / regression block were promoted from main file-locals to `mod._gt_ai_*` fields (seeded at the top of main; assigned/used by the module) so both sides resolve them at call time: `mod._gt_ai_pending_client_send`, `_pending_host_toggle`, `_suppress_setting_callback`, `_saved_state`, `_handle_toggle_change`, `_takeover_disabled`, and `_afk_took_over` / `_afk_idle_t` / `_afk_input_stamp` / `_afk_grace_until`. **`ai_pending` consumer decision:** now that those locals are `mod._gt_ai_*` fields, the deferred-consumer half that Phase 3 left in main (split out of the old merged `infinite_ammo_and_ai_pending`) **moved INTO this module** alongside the `_ai_consume_*` drains it calls -- it registers via `mod._gt_register_update` (along with the `afk_autobot` consumer). The `_AI_CLIENT_SEND_*` tuning constants moved here too (they were forward-declared in main but only consumed by the send queue). `_ai_swap_human_to_bot` was exposed as `mod._gt_ai_swap_human_to_bot` for the `ai_locomotion_override_set_and_cleared` source-pattern regression check (which `debug.getinfo`s it -> now reads THIS module's source, where the `set_override_player(bot_player)` / `(nil)` call-pair moved). The two AI marker constants (`CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52` / `CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73`) STAY in main with their regression checks. The always-on `AICommanderExtension._update_units` crash guard is a SEPARATE feature and STAYS in main (per the spec). The module's debug-toggle dump wrap calls `mod._gt_dump_ai_now` (exposed by `_gt_debug_probes.lua`, nil-guarded, call-time resolved).
- **New `_gt_debug_probes.lua`** -- Debug Mode (auto-dump on key events) + observation/probe hooks + the burning-enemy fire VFX probe, ~951 lines. Gated on `mod:get("enable_debug_logging")` (preserved). **Every observation hook is a singleton and is debug-exclusive** -- the whole-mod `(Class, method)` audit confirmed NONE of `HeroView.{on_enter,on_exit}` / `HeroWindowItemCustomization.{on_enter,on_exit}` / `IngameUI.handle_transition` / `LevelTransitionHandler.load_current_level` / `BackendInterfaceItemPlayfab.refresh_bot_loadouts` / `PlayerManager.{add_remote_player,remove_player,relinquish_unit_ownership}` / `CharacterStateHelper.change_camera_state` / `HeroViewStateOverview.{set_layout_by_name,on_enter,_change_window}` is hooked by any other gt feature (the mission-UI module hooks `HeroWindowLoadoutConsole` / `HeroWindowPanelConsole`, NOT these), so ALL moved (none stayed behind as shared). Exposes `mod._dbg_on` / `mod._dbg_log` (consumed by the mission-UI `_customize_item` hook + the AI Takeover debug wrap), `mod._dbg_alert`, and `mod._gt_dump_ai_now` (consumed by the AI Takeover debug-toggle wrap). Consumes the `mod._gt_ai_*` state fields for the AI dump. The two `mod.on_game_state_changed` observation wraps + the `mod.update` deferred-dump wrap are additive (`prev()` first), so re-wrapping at module-load (loaded first of the modules, closest to original chunk order) is behavior-neutral. The main file retains its OWN top-of-file `_dbg` / `_dbg_alert` pair (which the `dbg_helpers_two_channel` regression check resolves -- the moved debug-block pair previously shadowed it; both are functionally identical, same gate + channels).

### Notes
- **Update-consumer registration order:** `ai_pending` + `afk_autobot` now register when `_gt_ai_takeover.lua` loads (mid-module-chain) rather than interleaved in the original main-file position. They are independent of the other consumers and decoupled across frames via the persistent send/AFK queues, so same-frame ordering does not matter -- behavior is neutral.
- **Final main-file size:** `general_tweaker_dev.lua` is now 2007 lines (bootstrap + `mod._gt_ai_*` seeds + the godmode body + the `_GT_GODMODE_RPC` + the Disable/Clear Enemy Spawns spawns-control block incl. the consolidated `ConflictDirector.spawn_queued_unit` hook + the `AICommanderExtension._update_units` guard + the `on_setting_changed` / `on_disabled` / `on_game_state_changed` DISPATCHERS + the 29-check `/gt_regression_test` block + the `mod:dofile` loader manifest). The whole mod now spans 30 `_gt_*` feature modules.

## v0.2.134-dev (2026-06-20) -- refactor (Phase 3): extract medium / shared-table-hook features to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 3 of the main-file split begun in v0.2.132/.133-dev). Carves ~1247 more lines out of `general_tweaker_dev.lua` (5753 -> 4506 lines) into five new `_gt_*` modules, loaded via the existing `mod:dofile` chain at the bottom of the main file. Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules (and against `_gt_lobby_slot_reservations.lua` / `_gt_solo_qol.lua` specifically) before the move. Dispatchers (`on_setting_changed` / `on_disabled` / `on_game_state_changed`) stay in main and resolve each moved feature through a `mod._gt_*` / `mod.gt_*` field at call time. Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_mission_ui.lua`** -- in-mission hero-view access (3 features, all singleton hooks): Open Inventory In Mission (`mod.gt_open_mission_inventory` + `/gt_inv`; no hook -- drives `Managers.ui:handle_transition("hero_view_force")` directly), Mission Customize gear-icon cim-gate (`HeroWindowLoadoutConsole._customize_item`), and Show menu tabs in-mission (`HeroWindowPanelConsole.on_enter`). `gt_open_mission_inventory` stays a `mod.` field so the VMF keybind + `/gt_inv` resolve it. The `mission_inventory_enabled` InventorySettings/ESC-menu patch did **not** move here (see `_gt_keep_menus.lua`). The `gt_no_mission_hotkey_flip` Issue-#62 regression test was re-anchored from `mod.gt_open_mission_inventory` to `mod.on_setting_changed` so it keeps reading the MAIN file's source (where the removed `IngameUI.handle_menu_hotkeys` hook lived).
- **New `_gt_bots_keep.lua`** -- two host-side bot-roster features, neither with a `(Class, method)` hook: Bots in Keep (`mod._bik_fill`/`_clear`/`_active`/`_reset_bookkeeping` + the `bots_in_keep` update consumer; still kill-switched in source) and Disable Bots (Solo) (`mod._gt_apply_no_bots`). The forward-declared file-local `_gt_apply_no_bots` was retired in favor of the `mod._gt_apply_no_bots` field; `on_game_state_changed` (StateIngame-enter re-apply) + `on_setting_changed` (`gt_no_bots`) + the `no_bots_apply_sets_ai_bots_disabled` regression test were all repointed to it. The `_bik_*` regression tests already read `mod._bik_*` fields.
- **New `_gt_level_control.lua`** -- co-locates everything between the original "Level Control" and "AI Toggle" sections so the ProfileSynchronizer singleton audit is local: Level Control (win/fail/restart host-exec + client->host RPC), the End-of-level profile fallback / score-screen fix, `gt_kill_bots` / `gt_die`, `/gt_respawn` (client->host RPC), `gt_fix_sound`, `gt_bot_toggle`, and Duplicate Careers. Holds **four DISJOINT** ProfileSynchronizer hooks (`get_persistent_profile_index_reservation` for the score-screen fix vs `get_profile_index_reservation` / `try_reserve_profile_for_peer` / `is_free_in_lobby` for Duplicate Careers) plus `StateInGameRunning._award_end_of_level_rewards`. Verified the gt lobby slot-reservations feature does NOT hook ProfileSynchronizer (no cross-module collision). The block was fully self-contained (own RPC names + helper locals); every keybind-bound callable stays a `mod.` field, so no main-file dispatcher needed repointing.
- **New `_gt_keep_menus.lua`** -- Keep Menus in Missions (the `InventorySettings.inventory_loadout_access_supported_game_modes` patch + the ESC-menu "Open Inventory" entry). Pure data-table mutation, NO hook (the legacy `IngameUI.handle_menu_hotkeys` hook was already removed in v0.2.82-dev). Exposes `mod._gt_apply_keep_menus`; per the dispatcher rule the `on_game_state_changed` + `on_setting_changed` (`mission_inventory_enabled`) DISPATCHERS stay in main and call it at the same points the file-local `_patch_inventory_access()` was called. Applied once at the module's own load (mirrors the original load-time call).
- **New `_gt_hacks.lua`** -- the Janoti "Hacks" port Groups B/C/D/F, co-located for a local singleton audit: Time & Pause (B), Ult Controls (C, `CareerExtension.update`), Buffs & Stat Tweaks (D -- infinite ammo/stamina/`GenericStatusExtension.add_fatigue_points`, giga power, base crit + `ProfileRequester.request_profile`/`GameModeInn._cb_start_menu_closed`, movement speed, fall damage), and the Engine error nil-guards (F -- `VolumetricsFlowCallbacks.unregister_fog_volume`, `Unit.get_data`, `PlayerWhereaboutsExtension.update`, `RoundStartedSystem._players_left_start_area`). The pause flag (was forward-declared file-local `_pause_active`) became the shared `mod._gt_pause_active` field so the `on_game_state_changed` dispatcher's per-transition clear and the toggle's read path see the same value. `gt_time_apply` / `gt_apply_crit_chance` / `gt_apply_move_speed` / `gt_apply_fall_damage` stay `mod.` fields for the `on_setting_changed` branches + the fall-damage regression test. The original merged `infinite_ammo_and_ai_pending` update consumer was **split**: the infinite-ammo refresher half registers here as `infinite_ammo` (via `mod._gt_register_update`); the AI-takeover deferred-consumer half stays in main as `ai_pending` (it references AI-takeover file-locals). The two halves share no state, so the split is behavior-neutral. The always-on `AICommanderExtension._update_units` crash guard (a separate AI-takeover guard) stays in main near the AI Takeover code.

### Not moved (reported)
- **Disable Enemy Spawns + Clear Enemy Spawns** (the planned `_gt_spawns_control.lua`) were **left in the main file**. Disable Enemy Spawns gates inside `ConflictDirector.spawn_queued_unit`, which is a CONSOLIDATED multi-mod hook in main also serving `_gt_solo_qol.lua` (`mod._gt_solo_on_spawn_queued`) and the necro-pet probe -- so per the singleton rule that hook cannot move, and fragmenting half the feature into a module while its primary gate stays in main would add confusion for no benefit. `ConflictDirector.update` (Creature Spawner, Phase 4) is a DIFFERENT method (disjoint, irrelevant here). `_apply_script_data_no_enemies` + `/no_enemies` + Clear Enemy Spawns (`mod.gt_clear_enemies` + `/clear_enemies`) stay alongside it.

## v0.2.133-dev (2026-06-20) -- refactor (Phase 2): extract 5 single-hook self-contained features to modules -- no behavior change

Pure code-reorganization, **no behavior change** (Phase 2 of the main-file split that began in v0.2.132-dev). Carves ~764 more lines out of `general_tweaker_dev.lua` (6517 -> 5753 lines) into five new `_gt_*` modules, loaded via the existing `mod:dofile` chain (the `.mod` package's `lua = ["scripts/mods/general_tweaker_dev/*"]` wildcard auto-bundles them). Each module was lint+build-gated individually; every moved `(Class, method)` hook was grep-verified as a singleton across main + all `_gt_*` modules before the move. Lint PASS (0 dup-hook / 0 forward-ref / 0 late-local) and build exit 0 after every step.

### Changed (internal only)
- **New `_gt_camera.lua`** -- Third-Person Camera. Hooks `PlayerUnitFirstPerson.set_first_person_mode` + `.extensions_ready`; registers its own `tp_camera` `mod.update` consumer. Exposes `mod._gt_apply_tp` / `_gt_patch_camera_offset` / `_gt_restore_camera_offset` (read by the main `on_setting_changed` AND `on_disabled`) + `mod._gt_tp_reset_enabled` (read by `on_game_state_changed`). The shared `extensions_ready` hook ALSO scheduled the godmode/noclip post-spawn re-apply; that timer + its `post_spawn_reapply` consumer stay in main (godmode is not moved), so the hook now calls the new main-file `mod._gt_schedule_post_spawn_reapply()`. Loaded first of the five so its `tp_camera` consumer registers ahead of `cutscene_auto_skip` (original relative order).
- **New `_gt_noclip.lua`** -- Noclip. Hooks `PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`; owns the `/noclip` command + `mod.gt_noclip_toggle` (the keybind `function_name`). Exposes `mod._gt_apply_noclip` (read by `on_setting_changed` + the shared `post_spawn_reapply` consumer that re-arms godmode AND noclip), `mod._gt_noclip_heartbeat` (per-frame locomotion-state re-assert, called from that same shared consumer), and `mod._gt_noclip_reset_active` (read by `on_game_state_changed`). The `post_spawn_reapply` consumer + `_post_spawn_reapply_timer` stay in main.
- **New `_gt_cutscenes.lua`** -- Skip Cutscenes (Group G). Hooks `CutsceneSystem.flow_cb_cutscene_effect` / `.flow_cb_activate_cutscene_logic` / `.skip_pressed` + `ShowCursorStack.pop`; registers its own `cutscene_auto_skip` consumer via `mod._gt_register_update`; exposes `mod.gt_skip_cutscenes_toggle`. The `on_setting_changed` branch for `gt_skip_cutscenes_enabled` sets `script_data.skippable_cutscenes` inline (no cross-file call), so dispatch is unchanged. The two `/gt_regression_test` cutscene checks stay in main (they read a marker string + `mod:get()`, never a moved function).
- **New `_gt_misc_features.lua`** -- three small features: Choose Grail Knight Quests (`PassiveAbilityQuestingKnight._generate_quest_pool`), Ready Up! (`VoteManager.rpc_client_complete_vote` + `mod.gt_ready_up_now` host shortcut / keybind), and the Adventure save-consumable trait odds (load-time data mutation, no hook; exposes `mod._gt_apply_adv_save_traits`, resolved at call time from `on_setting_changed`). The `gk_quest_dropdowns_dont_share_options` regression check stays in main (it inspects the DATA file).
- **New `_gt_godmode_qol.lua`** -- the QoL/cheat bundle (explicitly NOT the godmode body): Unstuck (`/unstuck`), Friendly Fire Toggle (`DamageUtils.allow_friendly_fire_ranged`/`_melee` -- DISTINCT methods from the godmode `add_damage_network*` hooks that stay in main, so no duplicate-hook collision), Player-state toggles (inn-damage / cloak / unkillable commands), Disable Loading-Screen Monologues, and More Corpses (`RagdollSettings` cap; exposes `mod.gt_apply_corpse_count`, resolved at call time from `on_setting_changed`). The godmode invisibility + `add_damage_network*` damage-blocking body remains in the main file (shared with the floating-damage-numbers feature).

## v0.2.132-dev (2026-06-20) -- refactor: extract dump commands + item spawner to modules -- no behavior change

Pure code-reorganization, **no behavior change**. Carves ~830 lines of command-only code out of the main `general_tweaker_dev.lua` (7529 -> 6515 lines) into two new self-contained `_gt_*` modules, loaded via the existing `mod:dofile` chain (the `.mod` package's `lua = ["scripts/mods/general_tweaker_dev/*"]` wildcard auto-bundles them). Relieves the main chunk's 200-locals pressure and the file-size budget. All moved blocks were verified hook-free before extraction.

### Changed (internal only)
- **New `_gt_dumps.lua`** -- the read-only console dump commands: `/dump_level` (the ~536-line verbose level/world/pickups/breeds/UI snapshot, with its verbose doctrine comment trimmed to 3 bullets), `/dump_glossary`, `/dump_cosmetics`, `/dump_items_by_slot`, `/gt_dump_hero_view`. The shared `_write_dump` log helper moved here too (all four of its callers moved with it), so it's no longer a main-file local.
- **New `_gt_item_spawner.lua`** -- the pickup Item Spawner (`/gt_spawnitem`, `/gt_nextitem`, `/gt_previtem` + the `mod.gt_is_*` helpers and the `_gt_is_*` file-locals). Ported-from-ItemSpawner block lifted verbatim. The `/gt_regression_test` `gt_pickup_lookup_uses_rawget` check and its marker constant `CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48` stay in the main file (the check reads the marker + probes `NetworkLookup.pickup_names` at runtime; it never calls the moved code), so it remains resolvable.

## v0.2.131-dev (2026-06-20) -- Replicant Bots ports, grudge-mark in-game names, A-Z menu sort

### Added (Bot Options -- three Replicant Bots ports, all host-side, default OFF, `[untested]`)
- **Faster bot reactions** (`gt_bot_fast_reactions`). Ported from "Replicant Bots - Different Bots Experimental Branch" (`DifferentBots.lua:273-306` + `:3056-3058`). On enable: overwrites `BotConstants.default.OPPORTUNITY_TARGET_REACTION_TIMES` with `{min=0.2, max=0.5}` for every difficulty the vanilla table defines, and makes `AiUtils.calculate_bot_threat_time` return the raw `bot_threat.start_time, bot_threat.duration` (no random start-delay) so bots react to telegraphed attacks immediately. The source mod's `on_disabled` is author-flagged broken, so gt does a **real** snapshot/restore: the vanilla reaction table is deep-copied on first apply and written back verbatim on toggle-off (wired into `on_setting_changed` + `on_disabled`, plus a boot-time apply if already on). The per-breed `BreedActions` retuning was deliberately skipped. New `mod:hook("AiUtils", "calculate_bot_threat_time", ...)` -- a fresh `(Class, method)` pair (the only other `AiUtils` hook in the repo is `_gt_solo_qol.lua`'s `generic_mutator_explosion`).
- **Bots drink potions when in danger** (`gt_bot_drink_potions_in_danger`). A throttled per-bot tick (gt idiom, mirrors `_gt_ladder_unstick_tick` etc.; NOT a copy of Replicant's `bt_bot_drink_pot_action` BT node) driven from the single consolidated `PlayerBotBase.update` hook. When a bot holds a giveable potion in `slot_potion` AND a danger is within ~18 m -- a `breed.boss` monster/lord, or a cluster of >= 3 `breed.elite` units (a roaming patrol) -- it wields `slot_potion` and holds the use input until the potion is consumed (the same drink primitive `BTBotHealAction` uses). Reads **live** breed data each scan (`Unit.get_data(enemy, "breed")` off `Side:enemy_units()`), not a static name roster. Host-side (bots are host-only).
- **Announce when a bot's guard breaks** (`gt_bot_guard_break_msg`, dropdown: Off / Host only / Host + clients). Ported from `DifferentBots.lua:2443-2472`. Hooks `GenericStatusExtension.set_block_broken`; on the rising edge (was unbroken, now breaking) for a BOT-owned unit, posts a chat line -- `add_local_system_message` for host-only, `send_chat_message` for the whole lobby. New `(Class, method)` pair (the only other gt hook on `GenericStatusExtension` is `update_falling` in the main file).

### Changed
- **Grudge-mark labels -> official in-game names** (Creature Spawner manual toggles). Converted the `gt_cs_grudge_*` labels from internal names to the player-facing in-game display names, verified against Fatshark's "All About Grudge Marks" article cross-checked with the buff mechanics in `scripts/settings/dlcs/grudge_marks/buff_settings_grudge_marks.lua`: `warping`->**Shadow-Step**, `intangible`->**Illusionist** (summons 3 mirror images), `unstaggerable`->**Relentless**, `raging`->**Mighty**, `vampiric`->**Vampiric**, `ranged_immune`->**Rampart** (confirmed), `periodic_shield`->**Invincible** (periodic `buff_perks.invulnerable`), `crippling`->**Crippling**, `crushing`->**Shield-Shatter**, `regenerating`->**Regenerating**, `periodic_curse`->**Cursed Aura**. Internal name kept in parentheses on each label + tooltip for cross-reference. (Note: the two earlier swaps -- `intangible` is the mirror-image "Illusionist", and `periodic_shield` is the invulnerability "Invincible" -- were verified against the buff `update_func`/`perks`, not assumed from the internal name.) `commander` and `frenzy` were outside the requested set and left unchanged.
- **Top-level menu categories sorted A->Z** by display label (standing reorder rule): Bot Options (AI Teammates), Cheats and Debug, Cutscenes & Monologues, Floating Damage Numbers, Gameplay, Host-Side Lobby Controls, Keep Menus in Missions, Main Menu / Startup, More Corpses, Ready Up, Solo & QoL, Third-Person Camera -- with **Debug Logging pinned last** (convention) and the intra-camera distance/height/offset ordering preserved. No widgets or settings changed; only the top-level group order.

## v0.2.130-dev (2026-06-20) -- Hide UI migrated to GUI Tweaker (gut)

### Changed
- **Hide UI (off/partial/complete/camera) moved to GUI Tweaker (`gut`).** The feature, its `gt_hud_mode` dropdown + `gt_hud_cycle_hotkey` keybind, the `/gt_hud` command, and its localization were removed from gt and now live in gut as `gut_hud_*` + `/gut_hud`. Two latent bugs were fixed in the move (the HUD-disable hook now hits the derived game-mode classes, and the force-hide reads the correct `Managers.ui._ingame_ui.ingame_hud` path). Conceptually it belongs with the GUI mod alongside the other HUD/UI tooling.

## v0.2.129-dev (2026-06-20) -- Crash fix: bot melee node hard-crashes on nil slot_data when a bot is given a weapon

Hard-crash fix (HOST, GUID 35c69dda, reported 2026-06-20): `bt_bot_melee_action.lua:83 attempt to index local 'slot_data' (a nil value)` in `BTBotMeleeAction.enter`. When a bot's wielded slot is transient/empty for a frame -- e.g. the bot was just **given a weapon** (CW bot-weapon mirror / cim / wt bot loadout / a vanilla bot inventory re-equip) and the slot has no data yet -- vanilla `enter` (`bt_bot_melee_action.lua:82-83`) reads `inventory_ext:get_slot_data(wielded_slot)` (nil) then immediately derefs `slot_data.item_data` and fatals.

Guarding `enter` alone is insufficient: `enter` writes `blackboard.wielded_item_template` (nil in the empty-slot case) and the **whole** melee node derefs it the same frame -- `_update_melee` (`:418`) -> `_choose_attack` (`:220`), `_defend.defense_meta_data` (`:499`), `_can_stagger_target.actions` (`:562`), `_time_to_next_attack`/`_attack` `.attack_meta_data/.actions/.name` (`:584-600`). So the node must not run a frame with a nil weapon. Two-part fix:

- **`_gt_bot_fixes.lua` -- new ungated hook on `BTBotMeleeAction.enter`.** When the wielded slot has no data, replicate vanilla's always-safe early blackboard setup (`node_timer`, the `melee` table, `set_aiming`) ourselves and leave `wielded_item_template = nil`, skipping the crashing `:83` deref. (Vanilla `func` is never called on the empty-slot path, so `:83` can't run.) When the slot IS populated, vanilla runs unchanged.
- **`_gt_improved_bot_combat.lua` -- consolidated the existing `(BTBotMeleeAction, "run")` hook.** It was a `hook_safe` (ping-the-attacking-elite feature). VMF allows only one hook per `(Class, method)` per mod, so the crash guard was folded INTO it and it was converted to a full `mod:hook`: it now bails the node `("done","evaluate")` whenever `blackboard.wielded_item_template == nil`, so `_update_melee` never derefs the nil weapon, then otherwise calls the original and runs the (gated) ping logic. The bot leaves melee for one frame and the BT re-selects next frame once the slot is populated.

Both halves are **ungated** (the crash guard fires regardless of the `gt_improved_bot_combat` toggle -- it's a crash fix, not the smarter-combat feature). Host-side only (bots are host-only); no RPC, so inert/crash-safe on clients. No new menu toggle. Verified line-for-line against the decompiled vanilla source (`scripts/entity_system/systems/behaviour/nodes/bot/bt_bot_melee_action.lua`).

## v0.2.128-dev (2026-06-20) -- Menu restructure: Cheats and Debug category, bot bundle, flies moved to enemy_tweaker

Large menu reorganization (no behavior change to kept features beyond the bot-toggle bundling):

- **Bot Behavior Improvements bundle.** The eight individual Bot Options toggles -- Necromancer potion handoff, don't-fail-while-a-bot-is-alive, auto ledge pull-up (+delay), ladder unstick (+delay), instant grab targeted items, prioritize revive, allow revive during ult, rescue ledge/hooked/disabled allies -- are now a SINGLE `[confirmed working]` checkbox **Bot Behavior Improvements** (`gt_bot_behavior_improvements`). The two former delay sliders are gone; the delays are hard-coded (ledge pull-up 3s, ladder unstick 4s). Every `_gt_bot_fixes.lua` site that read one of the eight ids (the `PlayerBotBase.update` dispatch, `BTConditions.can_activate_ability` Ironbreaker gate, the `_select_ally_by_utility` revive/rescue-priority gates, and `GameModeHelper.side_is_dead` fail-prevention) now reads the bundled id. **Kept as separate toggles:** Improved Bot Combat, Bots rescue allies awaiting respawn, Split bots among players, Bots always follow host, Tighter bot follow distance (+ its meters slider).
- **New "Cheats and Debug" category** (`cheats_debug_group`). Godmode and the noclip cluster (enable/speed/boost/hotkey) moved out of Gameplay into it; the formerly top-level **Buffs & Stats**, **Ult**, **Time & Pause**, **Level Control**, and **Spawners** groups are now nested sub-groups of it.
- **Removed "Player State Toggles" group** (it held only the Cloak/invisibility hotkey widget). The `/cloak` chat command and `gt_cloak_toggle` function are unchanged -- only the menu widget is gone.
- **Prioritize Specials (targeting)** and **Choose Grail Knight Quests** are now nested under **Gameplay** (were top-level groups).
- **Flies-disable feature moved to enemy_tweaker** (`gt_fly_disable_mult` -> `et_fly_disable_mult`). The Boss Mechanic Tweaks group and `_gt_boss_tweaks.lua` flies logic are removed from gt_dev (file renamed `.bak.v0.2.127-dev`; its `mod:dofile` line dropped).
- **Test-status:** all `gt_cutscenes_group` (Skip Cutscenes, Auto-skip, Disable Loading-Screen Monologues) and `gt_readyup_group` (Ready Up, Auto-start On Vote Pass) labels flipped `[untested]` -> `[confirmed working]`.
- **Debug Logging** moved to the very bottom of the menu (after Main Menu / Startup).

## v0.2.127-dev (2026-06-20) -- Bundle: Creature Spawner + Item Spawner under a "Spawners" menu

Menu organization (start of the dev-side toggle bundling, see memory [[project_dev_granular_live_bundled]]): the **Creature Spawner** (`gt_cs_group`) and **Item Spawner** (`gt_is_group`) groups are now nested inside a new collapsible parent group **"Spawners"** (`gt_spawners_group`). No settings changed -- both spawner sub-menus keep their own labels, toggles, and keybinds; they're just grouped one level deeper so the top-level menu is tidier. VMF nested-group collapsibles (the same pattern career_tweaker's BR menu used).

## v0.2.126-dev (2026-06-20) -- Test-status: godmode + prioritize-specials-when-tagging confirmed

`[confirmed working]`: **Godmode** (`godmode_enabled`) and **Prioritize Specials When Tagging** (`gt_prio_special_tag`, tag specials through enemies/pickups) -- both user-confirmed in-game 2026-06-20. (The ct_dev 0.7.154 tome-in-Adventure fix was also confirmed working in the same session.)

## v0.2.125-dev (2026-06-20) -- Bot-loadout probe: fire under Loremaster's Armoury (LA clone-backend)

The v0.2.123 bot-loadout probe never fired in the field: a session log showed 14 vanilla `refresh_bot_loadouts` runs (18:08:10-18:16:27) with the gt_dev class hook installed at 18:07:57, yet ZERO `[bot_loadout:]` lines -- because Loremaster's Armoury (active) replaces the live item interface with a **clone whose methods are copied**, so a hook on the `BackendInterfaceItemPlayfab` *class* method is bypassed (the documented LA clone-backend dispatch caveat, CROSS_MOD_ARCHITECTURE.md). This is very likely also WHY the designated bot loadout is ignored -- the LA-cloned `refresh_bot_loadouts` path isn't applying `bot_equipment`. Fix: the probe now resolves the **live** interface via `Managers.backend:get_interface("items")` (the accessor cim/CWV use) and table-hooks that instance (LA-safe). Run **`/gt_bot_loadout_dump` in the keep** after configuring bots -- it dumps immediately AND wires auto-dump for subsequent refreshes. The non-LA class hook is retained for setups without LA.

## v0.2.124-dev (2026-06-20) -- Necro-ult / patrol-crash trace (name the crashing unit)

Instrument for the reported Necromancer-bot-ult crash, which so far only ever logs as the vanilla patrol crash (`ai_group_templates_patrol.lua update_units -> Vector3_distance_squared`, "Vector3 expected, got userdata"). Two host-side probes, both unconditional `mod:info` (land with Debug Logging OFF), log-only (no guard, so the crash still yields its backtrace):

- **`[patrol_probe]`** -- table-hooks `AIGroupTemplates.spline_patrol.update` and, each tick, scans the group's `indexed_members`; emits a line naming any member whose `POSITION_LOOKUP` is missing or not a valid `Vector3` (the exact arg that crashes `update_units`) **with its breed** -- so the next crash names the offending unit. If that breed is `pet_skeleton_*`, the Necromancer pets are entering patrol groups (would refute the source analysis that says they can't); if `skaven_*`/`chaos_*`, it's the oversized-patrol path covered by enemy_tweaker 0.7.13's row cap. Only emits on a bad member, so no per-frame spam.
- **`[necro_probe]`** -- folded into the existing `ConflictDirector.spawn_queued_unit` hook (no new hook): logs Necromancer pet-skeleton (`pet_skeleton*`) spawns for timeline correlation with the crash.

Grep `[patrol_probe]` / `[necro_probe]` in the console log. Pre-flight: the patrol hook is a new table-hook on `AIGroupTemplates.spline_patrol` (zero prior gt_dev hooks there); the pet log extends the existing `spawn_queued_unit` hook rather than adding a second.

## v0.2.123-dev (2026-06-20) -- Bot-loadout resolution probe (bots using host's weapons)

Diagnostic for the report that AI bots spawn with the host's last-equipped loadout instead of the loadout the host designated as the bot loadout (via the loadout-slot UI / "Modern UI"). New host-side probe re-derives vanilla `BackendInterfaceItemPlayfab.refresh_bot_loadouts` resolution **read-only** and auto-dumps (forced output, no command / no Debug Logging) on every refresh, logging per career which branch fired: `NO_ASSIGNMENT` (the UI mod's bot-loadout assignment never reached `PlayerData.loadout_selection.bot_equipment`), `ASSIGNED_BUT_MISSING_IN_MIRROR` (`backend_mirror:has_loadout` failed -> assignment cleared), or `OK_DESIGNATED` -- plus a `clones_host_current` flag (the bug signature) and a summary line. Manual: `/gt_bot_loadout_dump`. Grep `[bot_loadout:` in the console log. (Pre-flight: zero prior gt_dev hooks on `BackendInterfaceItemPlayfab`/`refresh_bot_loadouts`.)

## v0.2.122-dev (2026-06-20) -- Migrate "Bot Improvements - Combat Returns" into one "Improved Bot Combat" toggle (+ its crash fix)

### Added — `gt_improved_bot_combat` (Bot Options group, default OFF)
A from-scratch reimplementation (new file `_gt_improved_bot_combat.lua`) of the **non-conflicting** combat features from the "Bot Improvements - Combat Returns" Workshop mod (3560390486), folded into a single host-side toggle:
- **Smarter melee attack choice** — bots prefer the penetrating/wide attack vs armour or crowds, the fast attack otherwise (`BTBotMeleeAction._choose_attack`). **Includes the crash fix:** the standalone mod read `inventory:get_slot_data(wielded_slot):item_data` with no nil-check and fataled (`BotImprovementsCombatReturns.lua:49: attempt to index local 'slot_data' (a nil value)`) when a bot's wielded slot was transient/empty — e.g. a just-swapped **AI-Takeover** bot; the reimplementation nil-guards and falls back to vanilla.
- **Ping attacking elites** — a bot pings the elite that's targeting it (`PingTargetExtension.set_pinged` + `BTBotMeleeAction/BTBotShootAction.run`, LoS-checked, 2 s cooldown).
- **Stop chasing far specials** (`PlayerBotBase._enemy_path_allowed`, ~7 m cap).
- **Ignore distant gunner line-of-fire** — only take cover from close shooters (`PlayerBotBase._in_line_of_fire`).
- **Don't over-focus bosses** — only treat a boss as urgent when close and not mid-crowd (`AIBotGroupSystem._update_urgent_targets`).
- **Smarter ult timing** for Mercenary / Huntsman / Maidenguard / Shade / Captain / Unchained (`BTConditions.can_activate.<career>`).

### Excluded (conflict with gt, or no-op as a single toggle)
- **Ironbreaker ult** → gt's `gt_bot_ironbreaker_revive_in_ult` owns it.
- **Better-revive** (`can_revive` + behaviour-tree edit) → overlaps gt's revive-priority / rescue-awaiting / ironbreaker-revive.
- **Heal-threshold dropdowns** → preference settings that no-op at default; the other/zealot ones hook `PlayerBotBase._select_ally_by_utility`, which gt already owns.

### Note
All migrated hooks are on distinct methods from `_gt_bot_fixes` (no duplicate-hook collision). **If you run the standalone "Bot Improvements - Combat Returns", disable it while this toggle is on** — both hook the same methods and would double-apply.

## v0.2.121-dev (2026-06-19) -- AI-takeover probe: hands-free auto-dump on death/respawn

The instrument-pass slot dump (`/gt_ai_slotdump`) now ALSO **auto-fires** — forced output, **no command and no Debug Logging needed** — on every death (`PlayerManager.relinquish_unit_ownership`) and every camera transition into `observer` (death) or `follow` (respawn). Just play Chaos Wastes normally; dying + respawning captures the full slot / camera-state / ownership cycle the takeover redesign needs, hands-free. Re-entrancy-guarded + pcall-wrapped (restores the debug gate even if the dump throws). Grep `[ai_slotdump:` in the console log.

## v0.2.120-dev (2026-06-19) -- Test-status: bots-rescue-awaiting-respawn confirmed

`[confirmed working]`: Bots rescue allies awaiting respawn (`gt_bot_rescue_awaiting`).

## v0.2.119-dev (2026-06-19) -- Test-status: flies disable confirmed

`[confirmed working]`: Fly disable multiplier (`gt_fly_disable_mult` — Halescourge/Nurgloth fly-swarm disable duration).

## v0.2.118-dev (2026-06-19) -- Split-bots spacing fix + "Bots always follow host" toggle

### Fixed
- **Split bots stood on top of you / blocked shots** (`gt_bot_split_among_players`): FIX 9 was overwriting each bot's `follow_position` with the leader's EXACT position (`POSITION_LOOKUP[human]`), clobbering vanilla's fanned-out spread destination (`ai_bot_group_system.lua:1115`, computed via `_find_points` with range 3 / 1-per-player spacing). Now it re-points only `follow_unit` and leaves vanilla's spaced follow-position intact, so bots keep a comfortable off-shot-line distance while still splitting per-player. (Workflow-diagnosed; `_gt_bot_fixes.lua` ~770.)

### Added
- **`gt_bot_follow_host` — "Bots always follow host"** (Bot Options, default off, `[untested]`): all bots leash to the host instead of spreading out / splitting. Routes through the same `_assign_destination_points` assignment and sets only `follow_unit`, so it inherits the spacing fix — no crowding the host or blocking shots. Takes **precedence** over `gt_bot_split_among_players` if both are on (precedence rather than a mutex avoids the VMF checkbox visual-refresh bug, `reference_vmf_checkbox_cached_display_state`). Bails to vanilla if the host has no live unit. Host-side only.

## v0.2.117-dev (2026-06-19) -- Bot ladder unstick confirmed; removed dev diagnostics

### Confirmed working
- **`gt_bot_ladder_unstick`** (+ its delay setting) is confirmed working in-game and relabeled `[confirmed working]` in the menu. Bots that hang at the foot/top of a ladder now get unstuck on the configured delay.

### Removed (dev diagnostics)
- **Auto-dump vanilla item names** (`gt_auto_name_dump` + the `_gt_name_dump` module). The self-refreshing loc_key->English console dump (and its `/gt_dump_names` force command) that fed `tools/gen-name-map` is gone — the menu checkbox, its loc keys, the `mod:dofile` load, and the feature file are all removed from the bundle. The feature file is preserved out-of-bundle at the mod root as `_gt_name_dump.lua.bak.v0.2.116`.
- **GC mitigation** (`gc_mitigation_enabled` + `gc_full_collect_sec`) and the **Lua memory watchdog** (`memwatch_interval`, plus the `/gt_mem` snapshot command). These leak-hunt instruments (added v0.2.77–v0.2.79 during the 2026-06-06 OOM investigation) are removed: the per-frame `_register_update` consumers, the widgets, and the loc keys are all gone.

## v0.2.116-dev (2026-06-19) -- AI takeover disabled + instrument pass for keep-slot redesign

### Disabled (pending rebuild)
**The convert-in-place AI takeover is disabled** behind a single module-level flag (`_AI_TAKEOVER_DISABLED = true`). It was producing **owner-less player units** (the client kept controlling a unit the host orphaned -> `owner_player` nil in the health extension), **host/client ownership desync** (reload-icon-on-wrong-portrait class), and a string of despawn-race crashes (0.2.113 AICommander, 0.2.114 whereabouts, 0.2.115 round-started). Root cause confirmed by a 4-agent research workflow (`wkcu0v4as`): the old code did only the HOST half of the swap (`player:despawn` host-side + `remove_peer_from_party` + `_add_bot_to_party`) and never told the CLIENT to relinquish its own unit -- and `RemotePlayer.despawn` is a host-side no-op, so the client's unit stayed live and owner-less.

Every takeover ENTRY point now bails before anything destructive runs -- `_ai_handle_toggle_change` (manual `/ai` + VMF checkbox), the `gt_ai_toggle_request` network handler (host receives client requests), the deferred host-self toggle consumer, and the AFK auto-takeover driver -- plus an innermost hard-stop guard inside `_ai_swap_human_to_bot` / `_ai_swap_bot_to_human` themselves, so **no `player:despawn` / `pm:remove_player` / `remove_peer_from_party` / `_add_bot_to_party` / `set_override_player` can execute** while disabled. User-initiated toggles echo `[gt] AI takeover is temporarily disabled while it's rebuilt (v0.2.116-dev).` once and revert the checkbox via the existing `_ai_suppress_setting_callback` path so it can't stick "on"; the per-frame AFK driver returns silently (no per-frame echo). The Group-F nil-guards (whereabouts / AICommander / RoundStartedSystem) and the position-keepalive are untouched and stay active.

### Added (debug-gated probes)
Instrument-only, behind the existing **Debug Logging** (`enable_debug_logging`) toggle; silent in normal play. These capture the vanilla dead/respawn/camera/slot machinery the rewrite will reuse, so the user can reproduce and we diagnose before mitigating:

- **`/gt_ai_slotdump`** chat command -- for every party slot, logs one parseable line with `slot_id` / `peer_id` / `local_player_id` / `is_bot` / `has_unit` / `unit_alive` / `spawn_state` / `health_state` (read from the slot's `player_status.game_mode_data`), plus per-party `num_used_slots` / `num_slots`, and the LOCAL player's live **camera state-machine state** (read off the player's separate `camera_follow_unit`, not `player_unit` -- that unit survives unit despawn, which is why the observer cam works with no controlled unit). Every lookup is nil-guarded (runs with units mid-teardown). The explicit command forces output even with Debug Logging off (mirrors `/gt_dump_ai`).
- **`hook_safe` on `CharacterStateHelper.change_camera_state`** -- logs `player name -> new camera state`, automatically capturing observer entry on death and the return to follow on respawn (bots early-return in vanilla, so they never log a real transition).
- **`hook_safe` on `PlayerManager.relinquish_unit_ownership`** -- logs the owning player + that `player_unit` was nulled (the clean relinquish the rewrite needs the CLIENT to perform on its OWN unit). Both new hooks were grep-verified against the file as the SOLE hook on their `(Class, method)` pair before registration (VMF duplicate-hook rule).

### The confirmed redesign (not implemented here)
Engine-native **keep-slot**: keep the human's Player + party slot intact, despawn ONLY the unit, push the client into the vanilla `observer` camera (the same flow every hero death uses), let a REAL host bot fill a FREE slot, and reclaim via the normal respawn handshake (`rpc_to_client_spawn_player`). This structurally eliminates the owner-less-unit crash, the portrait/reload-icon desync, and the player/peer churn -- all three were artifacts of doing only the host half and re-creating players. Hard constraint: a party has 4 slots, so the bot needs a FREE slot (refuse if the party is full). Adventure-only verified; full plan in research `wkcu0v4as`.

## v0.2.115-dev (2026-06-19) -- Crash fix: AI takeover round-started despawn race (third site)

### Fixed (crash)
**AI takeover crashed via the round-start check (GUID 6fac3e46):** `round_started_system.lua:111 (runtime): bad argument #3 to 'is_point_inside_volume' (userdata expected, got nil)`. Third site of the same despawn-race class (after 0.2.113 AICommander + 0.2.114 whereabouts). `RoundStartedSystem._players_left_start_area` iterates `self._units`, reads `pos = POSITION_LOOKUP[unit]` (`:117`), and feeds it to `Level.is_point_inside_volume(level, volume_name, pos)` (`:119`) with no nil-guard. A unit despawned mid-frame by the takeover (or a disconnect during the round-start window) is gone from `POSITION_LOOKUP` but lingers in `self._units` for a tick → nil pos → crash. Pre-guard: if any tracked unit lacks a position, bail the check this frame (`return false` = "round not started yet"); the despawned unit drops out within a tick and the next call runs vanilla normally — no premature round start.

> A background sweep is enumerating any remaining `POSITION_LOOKUP`-on-despawning-unit sites so the whole finite set can be guarded at once instead of one crash at a time.

## v0.2.114-dev (2026-06-19) -- Crash fix: AI takeover whereabouts despawn race (client) — companion to 0.2.113

### Fixed (crash)
**AI takeover crashed via the whereabouts extension (GUID 955c4549):** `player_whereabouts_extension.lua:200 (runtime): bad argument #2 to 'triangle_from_position' (userdata expected, got nil)`. This is a SECOND, distinct crash site from 0.2.113's AICommander `__add` fix — **same despawn-race cause, different vanilla extension**. `_ai_swap_human_to_bot`'s `player:despawn()` removes the unit from `POSITION_LOOKUP`, and `PlayerWhereaboutsExtension.update` ticks once more before teardown, reading `pos = POSITION_LOOKUP[unit]` (now nil) and feeding it to `GwNavQueries.triangle_from_position` (arg #2 requires userdata) → hard engine crash. Added a Group-F nil-guard on `PlayerWhereaboutsExtension.update` that bails when the unit has no position. One class covers local/husk/bot units.

Adversarially verified (4-agent workflow): the bot→human swap-BACK needs NO guard — `POSITION_LOOKUP[unit]` is written in `spawn_local_unit` (`unit_spawner.lua:302`) strictly before the extension's `init`/`_setup` runs (`:331`), so no nil window on respawn. With this + 0.2.113's AICommander guard, every per-frame nil-`POSITION_LOOKUP` surface in the takeover despawn path is closed on both host and client.

### IMPORTANT — every peer needs this build
The whereabouts crash fires inside the **client's OWN** extension on the client's about-to-be-despawned unit (which is why it surfaced "on client"). The guard runs on whichever machine runs gt_dev, so **every peer must run gt_dev v0.2.114-dev+**. 0.2.113's AICommander guard is host-side; this one protects the client — you need this build on BOTH machines.

## v0.2.113-dev (2026-06-19) -- CRITICAL: fix AI-Takeover host crash; remove broken Free Camera; test-status updates

### Fixed (CRITICAL host crash)
- **A client using AI Takeover hard-crashed the host** with `ai_commander_extension.lua: bad argument #1 to '__add' (userdata expected, got nil)` (host session a81cfea2, 2026-06-19). Root cause is a vanilla bug in `AICommanderExtension._update_units`: it reads `commander_unit_pos = POSITION_LOOKUP[self._unit]` then does `commander_unit_pos + avg_velocity` **without nil-checking the commander's own position** (it only guards the *controlled* unit's position a few lines later). AI Takeover despawns/recreates a player unit mid-frame (human→bot swap), leaving a commander unit with no `POSITION_LOOKUP` entry for a tick → the unguarded `+` fatals on the host. Fix: a symmetric nil-guard hook on `AICommanderExtension._update_units` that skips the tick until the commander has a position again (same behaviour vanilla already uses for the controlled unit). Always-on, host-side. The AI Takeover swap itself completes normally.

### Removed
- **Free Camera** (`freecam_enabled` toggle, `/freecam` command, the `FreeFlightManager._exit_free_flight` hook, all helpers + the localization/data entries) — it didn't work (player walked with the detached cam; later froze locomotion) and is removed for now. Noclip remains the working fly tool.

### Test-status
- `[confirmed working]`: **Unlock All Ranked Weaves** (`gt_unlock_all_weaves`) and **Disable Friendly Fire** (`disable_friendly_fire`) — both confirmed in-game.

## v0.2.112-dev (2026-06-19) -- Test-status: noclip confirmed

`[confirmed working]`: all noclip features (`noclip_enabled`, `noclip_speed`, `noclip_boost_multiplier`, `noclip_hotkey`).

## v0.2.111-dev (2026-06-19) -- Freecam crash fix + test-status confirmations

### Fixed (crash)
- **Free Camera crashed on activate** (GUID 12cb4bfd): `locomotion_templates_player.lua:368 attempt to call field 'run_func' (a nil value)`. `_freecam_freeze_player` disabled the player's locomotion via `set_disabled(freeze, nil, nil, true)` — but `PlayerUnitLocomotionExtension` adds disabled units to `all_disabled_units`, and `update_disabled_units` calls `extension.run_func(unit, dt, extension)` **every frame with no nil-check**. So `run_func=nil` crashed the next frame in the engine update loop (the `pcall` around `set_disabled` can't catch it — the crash is a frame later). Fix: pass a no-op `run_func` when freezing (keeps the player frozen in place without crashing).

### Test-status
- `[confirmed working]`: third-person camera + distance/height/side-offset/disable-zoom-in (`tp_camera_enabled`, `tp_distance`, `tp_height`, `tp_side_offset`, `tp_disable_zoom_in`); `gt_bot_instant_pickup`. `freecam_enabled` stays `[untested]` pending re-test of the fix above.

## v0.2.110-dev (2026-06-19) -- Test-status labels on all menu entries

Prefixed every VMF menu widget with `[untested]` so we know what's safe to promote to stable `gt`. Tooltips, group headers, dropdown options, and `enable_debug_logging` are not labeled. Two features the user confirmed in-game flipped to `[confirmed working]`: **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`) and **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). Flip the rest as verified. See `TESTING_STATUS.md`.

## v0.2.109-dev (2026-06-19) -- "AFK → AI takeover" toggle (per-client, input resumes control)

### Added
- **`gt_ai_afk_takeover`** (Bot Options, default off, per-client) — when on, 20 seconds of no input (keyboard / mouse / gamepad) hands your character to gt's AI takeover; the instant you give any input, you resume control. Per-client: each peer measures its own local input and drives only its own character (host on → host's char; client on → client's char), reusing the existing `ai_takeover_enabled` dispatch (host self-swap / client→host RPC). Manual `/ai` (or the manual checkbox) is NOT cancelled by input — only AFK-caused takeovers yield, tracked by an `_afk_took_over` discriminator flag.
  - **Input detection** uses `Managers.input.last_active_time` (the engine stamps it device-level on any press / non-cursor axis move, `input_manager.lua:769-770`) plus a raw `Keyboard`/`Mouse`/gamepad fallback — both independent of the player input controller, so they keep working while the local Player object is despawned during takeover. The `"cursor"` (absolute pointer) axis is excluded and a gamepad-stick deadzone applied so rest-drift doesn't count.
  - **Guards:** mode pre-gate (`_ai_can_swap_in_current_mode`, refused in Versus/keep), host-self-refusal cleared, a 0.25s re-arm grace after trigger/cancel so a held key can't flap the swap, and a full reset of the flag/timers in `on_game_state_changed`. Registered via `_register_update` (no new hook, no `mod.update` clobber).
  - **Note:** inherits the takeover swap's loadout reset — consumables/ammo don't persist across an AFK→return cycle.

## v0.2.108-dev (2026-06-19) -- "Unlock All Ranked Weaves" toggle

### Added
- **`gt_unlock_all_weaves`** (Gameplay, default off, client-side) — unlocks every ranked weave in the Winds of Magic ladder so the player can pick and play any weave without grinding the progression. New module `_gt_weave_unlock.lua` hooks `LevelUnlockUtils.weave_unlocked` (`level_unlock_settings.lua:490`) — the single gate every weave surface routes through (host weave picker `start_game_window_weave_list.lua:504`, selected-weave confirm `start_game_state_settings_overview.lua:132`, lobby-browser join `start_game_window_lobby_browser.lua:1229`, lobby-list entries `lobby_item_list.lua:580`), so one hook covers both hosting and joining. When on, returns `true` for any weave whose DLC the player **owns** — it replicates vanilla's own DLC gate (`:503-509`) so Winds of Magic ownership is still enforced (unlocks progression, never paid content; repo CLAUDE.md "DLC Ownership Gate"). Off → pure vanilla passthrough. Source-verified 2026-06-19; single-hook pre-flight confirmed gt had 0 prior hooks on `weave_unlocked`.

## v0.2.107-dev (2026-06-19) -- "Split bots among players" toggle (one bot per human)

### Added
- **`gt_bot_split_among_players`** (Bot Options, default off, host-side) — distributes bots one-per-human instead of every bot piling onto a single player. 2 players + 2 bots → one bot follows the host, the other the client; 3 players + 1 bot → that bot follows the host (round-robin, host first, when bots outnumber humans). Implemented as FIX 9 — a `hook_safe` on `AIBotGroupSystem._assign_destination_points` (the single per-frame chokepoint where each bot's `data.follow_unit` is written, `ai_bot_group_system.lua:1085`/`:1117-1123`); we stamp last so we override both the engine's scalar "all bots on one human" write AND the ~20s stand-still re-targeting (`AFK_TIME_LIMIT = 20`, `:652`) — a bot stays on its assigned human even when that human is idle. Filters to real humans (`Managers.player:human_players()`, not `side.PLAYER_UNITS` which includes bots), skips vortex/disabled targets, respects parked (hold-position) bots, and re-validates with `HEALTH_ALIVE` each frame so a dead/left human never strands a bot. Deterministic `tostring`-keyed sort so the mapping doesn't oscillate. Composition: follow target ≠ aid target, so the revive/rescue-priority toggles (FIX 3/3b) still preempt follow — a bot assigned to the client still breaks off to revive the host, then returns. FIX 5/7 read the same `follow_unit`, so ladder-unstick + leash retarget to each bot's assigned human.

## v0.2.106-dev (2026-06-19) -- Bot revive-priority + rescue-priority toggles

### Added
Two Bot Options checkboxes (default off, host-side) that make aiding a downed/disabled ally the bot's top priority, ignoring the snap-back leash. Folded into the existing `PlayerBotBase._select_ally_by_utility` wrapper (FIX 3) — no second hook.
- **`gt_bot_revive_priority`** — force-selects the nearest **pathable** knocked-down ally as the top-priority aid target, so the bot leaves the group and walks the whole way to revive.
- **`gt_bot_rescue_priority`** — same for the **rescue** states (`get_is_ledge_hanging` and `is_hanging_from_hook`).
- With both on, bots leave the team the moment a path to the downed player exists. The picker already credits a downed ally `utility=200` (a 200m closeness handicap, no max-aid-distance cap, `player_bot_base.lua:991/909-917`), and FIX 7's leash already exempts a bot once `target_ally_need_type` is set — so the toggles just make the *choice* explicit and distance-independent. Guards: mandatory engine `_ally_path_allowed` gate (no stranding on unreachable allies), 3m sticky-target hysteresis (no flip-flop), position nil-guards. Composes with FIX 3 (awaiting-respawn rescue) and the Ironbreaker ult-yield (which already keys on these need_types).

## v0.2.105-dev (2026-06-18) -- Fix bot snap-back distance (slider dead-band)

### Fixed
- **Bot follow snap-back distance (`gt_bot_follow_distance_m`) appeared to do nothing.** Verified against the decompile: the `BTConditions.should_teleport` hook (FIX 7) is a faithful, live mirror of vanilla and the teleport action has no second distance gate, so the mechanism is sound. The real bug was a **slider dead-band**: the slider ranged `{10, 50}` with a default of `40`, but FIX 7 treats **any value ≥ 40 as a no-op** (40 is vanilla's own leash). So the entire 40–50 half of the slider — and the default — did nothing; enabling the feature and leaving the slider at/above 40 (or raising it toward 50 expecting a *sooner* leash) was silently inert. **Fix:** slider now ranges `{10, 40}` with `default = 20`, so enabling it has visible effect and no value is in a dead band. Tooltip rewritten (40 = max/vanilla, ~15–20m practical floor, host-side only).
- Added debug-gated logging (`[gt:bot-leash] should_teleport TRUE …` + a `BTBotTeleportToAllyAction.run` confirmation) so a log can verify the leash firing + the actual teleport, in case of a host-authority or BT-priority edge.

### Note
- Did **not** add a teleport cooldown: vanilla's `has_teleported` latch (one snap per follow-state entry, re-armed in `BTBotFollowAction.enter`) is already the anti-thrash mechanism and FIX 7 honors it. This is also why a very tight distance can "rarely catch" — the bot snaps once, lands ~5m behind, and won't re-snap until it re-enters follow.

## v0.2.104-dev (2026-06-18) -- Block in-mission inventory in Chaos Wastes + fix auto-skip blackscreen fade

### Changed
- **In-mission inventory is now Adventure-EXCLUSIVE — fully blocked in Chaos Wastes** (hub AND mission). Opening the hero view or changing items/talents during a CW run crashes (CW is loadout-locked via the deus boon system). A 2026-05-25 change had narrowed the block to the CW *hub* only, on the assumption cim's mid-mission fix made the mission case safe — it still crashes, so this reverses that: `gt_open_mission_inventory` (the `/gt_inv` command + `gt_open_inv_hotkey` keybind) now bails on `mech == "deus"`; `_patch_inventory_access` never grants `modes.deus` loadout access and doesn't add the in-mission "Open Inventory" ESC-menu button while in a CW run.

### Fixed
- **Auto-skip cutscenes showed a blackscreen fade in/out in Chaos Wastes.** The v0.2.102 CW auto-skip path stopped setting `_skip_next_fade` (to avoid touching author-locked boss cinematics), so the fades that bracket an ordinary CW cutscene were no longer swallowed. Now both the activation hook (fade-IN) and the deferred processor (fade-OUT) set `_skip_next_fade` **when the cutscene will actually skip** (`script_data.skippable_cutscenes` true after the optional force-unlock) — so auto-skipped cutscenes are clean again, while an author-locked CW boss cinematic (read as not-skippable) keeps its own fade untouched.

## v0.2.103-dev (2026-06-18) -- HOTFIX: score-screen crash (nil hero in experience lookup) after host /gt_win

### Fixed (crash)
- **The v0.2.101 score-screen fix exposed a second nil-profile crash INSIDE the score screen** (GUID `f32490ac`: `backend_interface_hero_attributes_playfab.lua:93: attempt to concatenate local 'hero' (a nil value)`). The client's profile reservation races to nil/0 after a host `/gt_win`, and vanilla reads it in **two** end-of-level places — `_award_end_of_level_rewards` (`:768`, which v0.2.101 shimmed) **and** `_setup_end_of_level_UI` (`:266-280`), which runs *later* (after the shim was restored). The latter left `level_end_view_context.local_player_hero_name = nil` → `EndViewStateSummary._hero_name = nil` → `get_experience(nil)` → `BackendInterfaceHeroAttributes.get` → `nil .. "_experience"` crash. **Fix:** replaced the temporary shim with a **permanent fallback hook on `ProfileSynchronizer.get_persistent_profile_index_reservation`** — when the reservation is stale for our own peer, it returns the local player's real profile (which survives the race). This resolves a real hero for **every** end-of-level consumer (reward + score-screen UI + experience), not just the reward. Healthy reservations pass through untouched; the override only fires when the reservation is nil/0 and we have a valid local profile, so it's semantically correct and client-local (no host desync). The `_award_end_of_level_rewards` hook is now just a last-resort pcall net.

## v0.2.102-dev (2026-06-18) -- Auto-skip cutscenes again in Chaos Wastes (without desyncing boss cinematics)

### Fixed
- **Auto-skip cutscenes stopped auto-skipping in Chaos Wastes runs.** The v0.2.95 Nurgloth fix disabled auto-skip for the *entire* deus run to avoid desyncing author-locked boss cinematics — too broad: it also killed auto-skip for ordinary CW cutscenes like the `forest_ambush_belakor_path1` path intro (`cs_01_skip`), which is author-*skippable* (manual spacebar worked; auto-skip didn't). **Fix:** auto-skip now runs in CW too, but as a plain "auto-press skip" — it defers to vanilla `skip_pressed` **without** force-unlocking, so the engine's own `script_data.skippable_cutscenes` check decides: author-skippable CW cutscenes auto-skip, while author-locked boss/phase cinematics (Nurgloth on Enchanter's Lair) are still left alone (skipping them desyncs the fight). Outside CW it force-unlocks + skips everything, exactly as before. With Debug Logging on, the deferred-skip log now shows `force_unlock=false` in CW vs `true` elsewhere.

## v0.2.101-dev (2026-06-18) -- Fix: client sees the score screen after host /gt_win (was black-loading to keep)

### Fixed
- **A client got no end-of-level score screen after the host force-won via `/gt_win`** — it black-loaded straight back to the keep. The v0.2.89 crash guard prevented a vanilla nil-profile crash by **skipping the entire `_award_end_of_level_rewards`**, but that function is what sets `self.chests_package_name` (`state_ingame_running.lua:785`) and flips `self.rewards:rewards_generated()` true (`:778`) — **both required terms of the `rewards_ready` gate** that `StateInGameRunning.update` checks before calling `_setup_end_of_level_UI` (the results view). Skipping it starved the gate, so the screen never built. **Fix:** instead of skipping, when the client's profile reservation races to nil/0, resolve the client's *real* profile from the cached local-player object (`BulldozerPlayer:profile_index()`, which survives the race), temporarily shim `get_persistent_profile_index_reservation` so vanilla's internal read resolves, and run the **full** vanilla body (building the score screen) — then always restore. Healthy reservations run untouched vanilla; a genuinely-unresolvable profile still falls back to the old safe skip (crash avoidance). Single hook preserved, client-local (no host desync).

## v0.2.100-dev (2026-06-18) -- "Prioritize Specials" targeting toggles (tag / Deepwood Staff / Soulstealer)

### Added (new module `_gt_prioritize_specials.lua`)
Three independent, **default-OFF, client-side** toggles that bias a target picker toward `breed.special` enemies in your aim direction. All are per-local-player (no host install, no RPC, no version-sync) — they only change what *your* tag/shot points at. Every hook body is pcall-guarded (degrades to vanilla, never crashes); each is a single clean hook (pre-flight grep confirmed no existing gt hooks on these methods).
- **Prioritize Specials When Tagging** (`gt_prio_special_tag`) — hooks `ContextAwarePingExtension._check_raycast`. Re-walks the same tag ray; if an alive enemy Special is on it, tags that Special even when it's behind an elite or a pickup/item the crosshair is directly on.
- **Prioritize Specials — Deepwood Staff** (`gt_prio_special_deepwood`) — hooks `PlayerUnitSmartTargetingExtension.update_opt2` (the Deepwood seeking bolt is aim-assist smart-targeting, not trueflight). Gated to the wielded `staff_life`; after the vanilla pick, if it isn't a Special, redirects `targeting_data` to an alive enemy Special inside the ~36° aim cone (broadphase), else leaves vanilla aim.
- **Prioritize Specials — Soulstealer Staff** (`gt_prio_special_soulstealer`) — hooks `ActionTrueFlightBowAim.client_owner_post_update`. Gated to the wielded `staff_death` (so it does NOT also bias Kerillian's shared trueflight career class); overlays the action's `prioritized_breeds` with a metatable that gives any `breed.special` a high priority for the call, so a Special on the aim ray outranks a closer non-Special. Restores the table after.

### To verify (in-game, helpers)
Enable each toggle and confirm: tagging prefers specials behind elites; Deepwood bolt curves to an in-cone special; Soulstealer locks specials first; and each is inert when its weapon isn't wielded / the toggle is off. (Default-off, so zero behavior change until enabled.)

## v0.2.99-dev (2026-06-18) -- Clients can use gt_win / gt_fail / gt_restart

### Changed
- **`/gt_win`, `/gt_fail`, `/gt_restart` are now client-usable.** Level control is host-authoritative (`GameModeManager:complete_level/fail_level/retry_level` assert `is_server`), so previously a client got "Only the host can…". Now a client **requests** the action via a `gt_level_control` RPC and the host performs it for the lobby — mirroring the existing `gt_respawn` client→host pattern (VMF re-handshake + resolve the real host peer via `Managers.mechanism:server_peer_id()`, not the literal `"server"` recipient). The host still runs the command directly. Refactored the three commands onto one executor (`_gt_host_exec_level_control`) + one request helper; the host-only gate is gone. Any peer can trigger it (no extra permission gate — fine for co-op testing; a host opt-out toggle can be added later). Host logs `[gt:level-control-rpc] from=… verb=…`.

## v0.2.98-dev (2026-06-18) -- Fall damage multiplier slider (0–5x)

### Added
- **Fall damage multiplier** (`gt_fall_damage_enabled` checkbox + `gt_fall_damage_mult` slider, in the Buffs group). Slider range **0–5, default 1.0**: `1` = vanilla, `0` = no fall damage, up to `5` = 5× (tall falls become lethal). Off by default; the slider only applies while the checkbox is on.
  - **How:** fall damage is host-authoritative — `HealthSystem.rpc_take_falling_damage` computes `clamp(delta * FALL_DAMAGE_MULTIPLIER, max_health*MIN_%, max_health*MAX_%)` from `PlayerUnitMovementSettings.fall.heights` (vanilla `14 / 0 / 1`; `health_system.lua:657-664`). Scaling all three fields by the multiplier scales the clamped result linearly. We do **not** touch `MIN_FALL_DAMAGE_HEIGHT` (the client-side trigger threshold), so the same falls still register — only the dealt amount changes.
  - **Per-unit clones handled:** the engine deep-clones `PlayerUnitMovementSettings` per unit at spawn (`register_unit` → recursive `table.clone`), so `gt_apply_fall_damage` rewrites the base table **and** every live per-unit snapshot via the same `debug.getupvalue(unregister_unit, 1)` trick as the movement-speed slider. Vanilla values captured once → re-applies recompute from vanilla (no compounding); disabling or setting `1.0` restores vanilla.
  - **Host-side:** the host applies fall damage for everyone, so the host's value governs the whole lobby. Per-session (game restart restores vanilla).

### Tests
- `_rt_register("fall_damage_widgets_and_scaling")` — both widgets exist, the apply fn is callable, a standalone math probe confirms `m=0 → 0` and linearity (`fall_dmg(2) == 2·fall_dmg(1)`), and re-applying leaves a non-negative numeric multiplier.

## v0.2.97-dev (2026-06-18) -- Migrate "Straight to Keep & Quit Game" into gt (Main Menu / Startup)

### Added
- New **Main Menu / Startup** settings group reimplementing the two behaviours of the "Straight to Keep & Quit Game" Workshop mod (internal id "Goodbye Menu", by Amia) as independent gt toggles, both **default OFF**:
  - **Skip start screen (straight to the keep)** (`gt_skip_start_screen`) — bypasses the "press any key" start/title screen on launch so you land at the main menu (keep hub) directly. Sets `GameSettingsDevelopment.skip_start_screen` (read by `state_title_screen` / `state_splash_screen` / `state_ingame` during boot, so it takes effect on the **next launch**). Captures and restores the vanilla value.
  - **"Return to Main Menu" quits to desktop** (`gt_return_to_menu_quits`) — remaps the in-game ESC menu's `return_to_title_screen` (and its confirm-action `do_return_to_title_screen`) transitions to `quit_game` (`scripts/ui/views/ingame_ui_settings.lua:70/104/291`), so that menu entry exits to desktop instead — still behind the vanilla exit-confirmation popup. Applies live, captures originals, and restores on toggle-off **and** on mod-disable.
- **`/gt_quit`** — instant quit to desktop (no confirmation), via the engine's own `Application.quit()`. On-theme bonus with the migration.

### Why
User request: decompile the "Straight to the Keep and Quit Game" Workshop mod (3214214805) and migrate its features into General Tweaker. The original applies both changes unconditionally at load; gt exposes each as its own opt-in toggle with capture/restore. These are plain engine-data reassignments (not hooks), so there's no VMF duplicate-hook concern. The decompiled reference lives at `misc-vermintide-mods/_scratch/3214214805/`.

### Tests
- `_rt_register("menu_qol_settings_registered")` — both new checkboxes exist in the widget tree.
- `_rt_register("menu_qol_return_quits_roundtrips")` — `_gt_apply_return_quits(true)` remaps the return-to-title transitions to `quit_game` and `(false)` restores the originals (skips cleanly when the transitions table isn't loaded yet).

## v0.2.96-dev (2026-06-18) -- Fix Choose Grail Knight Quests dropdowns showing `<<<...>>>`

### Why
Workshop report (Level12Lobster): "Choose Grail Knight Quests have `<<< Quest Name >>>` on all the text." Root cause is the repo's known `vmf-dropdown-options-mutated` bug class: all three quest dropdowns (`gt_gk_quest1/2/3`) shared one `GT_GK_QUEST_OPTIONS` table. VMF's `localize_dropdown_data` mutates each option's `text` **in place** (`option.text = mod:localize(option.text)`), so the 2nd dropdown localized the already-localized strings and the 3rd localized those again — each pass through the missing-key fallback adds an angle-bracket pair, producing the `<<...>>` / `<<<...>>>` cascade. The option `text` values were also plain English ("Random (vanilla)") rather than loc keys.

### Fixed
- **Choose Grail Knight Quests dropdowns no longer render `<<<...>>>`.** Replaced the shared `GT_GK_QUEST_OPTIONS` table with a `_gt_gk_quest_options()` factory that returns a **fresh** table for each of the three dropdowns, so VMF mutates a distinct table per dropdown (no cross-dropdown re-localization). Option `text` is now a real loc key (`gt_gk_opt_*`, defined in `general_tweaker_dev_localization`) that resolves to the display name instead of falling through the `<...>` missing-key fallback. Matches the crt `_talent_swap_options()` / enemy_tweaker dropdown-factory fix for the same bug class.

### Tests
- New `_rt_register("gk_quest_dropdowns_dont_share_options")` — walks the data tree and fails if any two of the three quest dropdowns share an options-table identity, or if option `text` isn't a bare loc key (contains a space/period). Pins the fix so a future refactor can't silently re-share the table.

### Notes (stable-gt feedback also addressed in dev already)
The same Workshop comment thread reported two items that **dev already carries** and that will reach players on the next stable (`gt`) promotion: (1) "No bots toggle doesn't remove bots mid-mission" — dev's `gt_no_bots` ("Disable Bots (Solo)") sets `script_data.ai_bots_disabled`, which `_handle_bots` re-reads each server tick to despawn existing bots and block refill (the old `/gt_bottoggle` → `no_bots_allowed` path can't despawn mid-mission); it's persistent and re-applied on every mission start, so leaving it on also gives a bot-free party from the first frame (the requested "disable by default" / true-solo behaviour). (2) "More Corpses should default to 24 not 100" — dev's `gt_more_corpses_count` default is already 24.

## v0.2.95-dev (2026-06-18) -- Cutscene-skip no longer breaks Chaos Wastes bosses (Nurgloth / Belakor)

### Why
Reported + corrected from user testing: with cutscene-skip on, **Nurgloth on Enchanter's Lair skipped to his final phase and deadlocked.** I was wrong to clear gt earlier — a prior subagent grepped the *breed* code and found no cutscene, but the boss's intro/phase cinematic lives in the **level flow** (the Enchanter's Lair bundle), not the decompiled breed scripts. Traced through source: `CutsceneSystem.skip_pressed` fires the cutscene's `event_on_skip` **level-flow event** early (`cutscene_system.lua:97-105`), and on a boss level that flow event drives the boss's phase/state — so skipping it (especially gt's auto-skip, which fires without the player choosing, AND gt's force-unlock of the author "non-skippable" lock that boss cutscenes carry on purpose) jumps the boss ahead and deadlocks the fight.

### Fixed
- New `_gt_in_deus()` gate (detects a CW run via the deus run controller). In a CW run, gt now **does not auto-skip** cutscenes and **does not force-unlock** author-locked ones — so boss intro/phase cinematics play normally. Outside CW (regular Adventure, etc.) cutscene-skip is unchanged. Author-*skippable* cutscenes can still be skipped manually in CW via vanilla ESC; only the auto-skip and the unskippable-override are disabled there. The `[gt:cutscene]` activation log is kept (and its stale "boss has no cutscene" comment corrected). -- /gt_respawn command (force yourself back in when dead or awaiting rescue)

### Added
- **`/gt_respawn`** -- forces you back into the game when you're DEAD (in the respawn queue) or AWAITING RESCUE (hanging at a beacon). Respawn is server-authoritative, so: as host it runs directly; as **client** it sends a request to the host (re-handshakes VMF first via `ping_vmf_users`, then sends to the resolved `Managers.mechanism:server_peer_id()` -- so it works for you even when nicho hosts). Awaiting-rescue -> `StatusUtils.set_respawned_network(unit, true, helper)` (the same call the assisted_respawn interaction makes); dead/queued -> zeroes *your* `respawn_timer` so the host's `RespawnHandler.server_update` spawns you next pass (per-player, not the whole team). If a client send doesn't land first try (host link just re-synced), run it again. EXPERIMENTAL -- verify in-game. -- Diagnostics: Nurgloth cutscene logging + burning-enemy fire-opacity probe

### Added (diagnostics / probe)
- **Nurgloth / Enchanter's Lair cutscene logging** (`[gt:cutscene]`, ungated). The existing `CutsceneSystem.flow_cb_activate_cutscene_logic` hook now logs every cutscene activation (`on_activate` / `on_skip` event names + level + whether auto-skip is on), and the deferred auto-skip processor logs when it fires. Source proves the Drachenfels boss is BT/animation-driven (no `CutsceneSystem` cutscene in its code), so if **no** `[gt:cutscene]` line appears on Enchanter's Lair near the boss, gt's cutscene-skip is conclusively not the cause of the boss skipping to final phase / deadlocking — it's a vanilla CW AI desync. Quick test regardless: host turns OFF *Auto-skip cutscenes* and re-runs.
- **Burning-enemy fire-opacity probe** (`/gt_fire_probe <cloud> <variable> <value>`). Wraps the `burning` StatusEffect's `on_applied` (and its balefire/elven/warpfire/death variants) to capture the live fire particle ids, and the command pushes `World.set_particles_material_scalar` to every burning enemy so we can discover which material variable controls the fire's opacity (the source only names a color-*tint* variable). Light an enemy on fire, try candidates (e.g. `/gt_fire_probe fire intensity 0.2`), watch which dims the flames — then the real 0–100% opacity slider gets wired to that variable. Client-side/visual only.

## v0.2.92-dev (2026-06-18) -- Adventure save-item trait chance slider (moved here from Chaos Wastes Tweaker)

### Added
- **Adventure save-item trait chance (percent)** (`gt_adventure_save_trait_chance`, in the Gameplay group; slider 1–75, default 25 = vanilla). Sets the proc chance of the Adventure charm traits Home Brewer / Healers Touch / Grenadier (the chance to NOT consume the potion / healing item / grenade), via `WeaponTraits.buff_templates.{trait_ring_not_consume_potion, trait_necklace_not_consume_healing, trait_trinket_not_consume_grenade}.buffs[1].proc_chance` (vanilla 0.25; `weapon_traits.lua:69/84/104`). Absolute load-time data mutation re-applied on setting change; each peer applies its own value to its own data (no host-sync). Adventure-only — Chaos Wastes boons are a separate system and are untouched. **This was mistakenly added to Chaos Wastes Tweaker in ct v0.7.140; it's removed from ct (v0.7.141) and lives here now**, since it's not a CW feature.

## v0.2.91-dev (2026-06-18) -- Godmode: stop it affecting bots + make client godmode actually reach the host; log /gt_win

### Fixed
- **REGRESSION: host godmode made the host's BOTS invincible.** The v0.2.89 MP godmode check (`_gt_godmode_active`) keyed off a unit's owning peer, but bots are owned by the HOST's peer_id -- so with the host's godmode on, every host bot read as god-moded and took no damage. Now gated on `owner:is_player_controlled()` (true for humans, false for bots), so godmode only ever affects actual players.
- **Client godmode was ignored by the host.** Damage to a player is applied on the host; a client's godmode is only honored if its broadcast reaches the host. It wasn't: VMF silently drops the host from a client's `_vmf_users` when the host's bots churn at mission load (VMF_RECIPES §3a, the same bug that bit gt's AI-RPC in v0.2.52). Fix: the godmode broadcast now calls `get_mod("VMF").ping_vmf_users()` to re-handshake before sending, exactly like gt's AI-RPC path. The 3s heartbeat in `mod.update` re-handshakes + resends so it converges within a few seconds even if the first send races the async pong.
- **Godmode-off now expires reliably.** Synced peers are stored with a timestamp and expire after ~9s without a heartbeat, so turning godmode off (or disconnecting) can't leave a remote player stuck invincible even if the explicit "off" send is lost.

### Added
- **`/gt_win` `/gt_fail` `/gt_restart` now log + echo when used** (host). Previously they ran silently, so a force-win was invisible in the console log. The host's log now records `[gt:level-control] /gt_win -> ...complete_level()`.

### Notes (no code change)
- **A reported "/gt_win stuck me on a loading screen" was diagnosed as NOT a gt bug.** Log analysis (2026-06-18): the host force-won, everyone loaded into the victory keep fine, then the HOST quit the game ~70s later -> the client got `remote_disconnected` -> vanilla host-migration hung on its load. That host-migration screen is the "stuck loading", caused by the host closing the game, not by `complete_level`.
- **Fly-disable duration is already host-authoritative lobby-wide** (verified): the boss runs on the host and the fly cloud's lifetime is set from the host's `BreedActions` / `TrueFlightTemplates` data, so the host's value governs every player; clients never read their own value for it. No sync needed.

## v0.2.90-dev (2026-06-18) -- Show the hero-view tab strip in-mission (Inventory/Talents/Cosmetics)

All source citations verified against the decompiled vanilla source 2026-06-18.

### Why
Reported: opening the inventory mid-mission showed NO clickable tabs up top -- you couldn't switch to Talents/Cosmetics. Root cause (verified): on PC, when Options -> "Use PC menu layout" is OFF (the default), the hero view renders the console-style "new GUI" tab strip `HeroWindowPanelConsole`, which **hides and input-disables the entire tab strip in a mission** -- both its draw (`hero_window_panel_console.lua:496`) and its title-button input loop (`:360`) are gated on `self.is_in_inn` (false mid-mission), and `on_enter`'s else-branch (`:87-95`) skips the strip's `_setup_text_buttons_width` / `_setup_input_buttons`. Only system/back/close remain.

### Added
- **"Show menu tabs in-mission (Inventory/Talents/Cosmetics)"** (`gt_mission_menu_tabs`, default OFF, under the Mission Inventory group). New `mod:hook_safe("HeroWindowPanelConsole", "on_enter", ...)` (pre-flight: no prior hook on that class). Mid-mission, when the toggle is on, it flips the instance's `is_in_inn` to true so the strip's setup/draw/input branches run, calls the two setup methods vanilla skipped, and parks `_sync_delay` far in the future so `_sync_news` never runs its keep-leaning news work (the "new" badges just don't refresh; tabs still draw + click). The title-button widgets are always built in `create_ui_elements` (`:132-150`) regardless of `is_in_inn`, so nothing needs re-creating.
  - **Forge tab gated** OFF unless `cim` is loaded -- its item-customization sub-path is the `levels/ui_store_preview/world` crash already guarded by the existing `HeroWindowLoadoutConsole._customize_item` hook (belt-and-suspenders). Loot is not a tab on this strip.
  - **PC console-layout only.** With "Use PC menu layout" ON (`HeroWindowOptions`), the strip already draws in-mission, so that layout needs nothing here.
  - **Caveat:** changing a talent mid-mission applies to your live character immediately (vanilla behavior).

### To verify (in-game)
- Enable the toggle, open `/gt_inv` in a mission: the top tabs (Inventory / Talents / Cosmetics) now render and switch. Forge is greyed unless Crafting in Modded is loaded.

## v0.2.89-dev (2026-06-18) -- Bots rescue awaiting-respawn allies (real fix); MP godmode; gt_win host-gate + results-crash guard

All source citations verified against the decompiled vanilla source 2026-06-18.

### Why
Four issues reported from live MP play (danjo client in nicho's lobby, 2026-06-18):
1. **Bots never rescue allies awaiting (assisted) respawn**, even with the toggle ON for the host. The v0.2.84-dev "rescue trick" was correct *downstream* but scanned the wrong roster.
2. **Godmode doesn't make a CLIENT invincible** (works only when hosting/solo).
3. **The host force-winning via `/gt_win` crashed a client** at the results screen.
4. (`/gt_win` itself was also unguarded for clients.)

### Fixed
- **Bots rescue awaiting-respawn allies (`_gt_bot_fixes.lua`)** — ROOT CAUSE: the FIX 3 wrapper iterated `side.PLAYER_AND_BOT_UNITS`, but `SideManager._update_frame_tables` rebuilds that list every frame and only keeps units where `is_valid(unit)` is true, and `is_valid` (`side_manager.lua:338-339`) is `unit_alive(unit) and not status:is_ready_for_assisted_respawn()` — so an awaiting-rescue ally is **always filtered out** of that list. The wrapper saw `considered = 0` forever and never rescued anyone. Fix: iterate the **unfiltered** `side:player_units()` (`side.lua:222`, the raw `_player_units` roster, which keeps the awaiting unit). The per-candidate gates (ready / health-alive / aid-path) are unchanged, so only a genuine awaiting+reachable ally is picked, then relabeled `knocked_down` so the existing revive branch drives the contextual `assisted_respawn` interaction. Added a nil-guard on the candidate position (a just-spawned remote awaiting unit can briefly lack a `POSITION_LOOKUP` entry).
- **Extra rescue logging (`enable_debug_logging`)** — a throttled `[gt:bot-rescue] scan roster=N` heartbeat (proves the wrapper runs and shows the roster size, fires even when nothing is found), a per-candidate line (`ready / health_alive / aid_path / has_pos`), the existing summary, and a `[gt:bot-rescue] RESCUE picked …` line at the relabel. A future repro now shows exactly where the path stops.
- **Godmode multiplayer sync (`general_tweaker_dev.lua`)** — damage to a player is applied on whatever machine is authoritative for that unit (the HOST for a client's unit), where the old hook saw a remote unit and `_is_local_player_unit()` was false — so a client took full damage. Now each peer broadcasts its godmode state (`gt_godmode_state` VMF event, schema-validated) and the HP-damage hooks (`DamageUtils.add_damage_network` / `add_damage_network_player`) block damage to any unit whose **owning peer** has godmode on (`_gt_godmode_active`). Fire-and-forget + pcall-guarded; VMF drops the event for non-gt / older-gt peers, so no mixed-lobby crash, and host-self still works via the local fast path even if the broadcast fails (no regression). A throttled rebroadcast (~3s while godmode is on) self-heals against a dropped client→host send before the VMF handshake settles. Both peers in a lobby need this build for a client's godmode to be honored.
- **`/gt_win` `/gt_fail` `/gt_restart` host-only gate** — `complete_level`/`fail_level`/`retry_level` are server-authoritative (only the host runs `GameModeManager.server_update` → `evaluate_end_conditions`, `state_ingame.lua:982-983`; the engine's own `flow_callback_complete_level` guards with `if Managers.player.is_server`). A client calling them set a flag nothing reads and fired `trigger_end_level_area_events` out of band → client-side flow desync/crash. Now gated to the host with a friendly echo (`_gt_host_only_level_control`).
- **Results-screen crash guard** — `StateInGameRunning._award_end_of_level_rewards` reads `SPProfiles[profile_synchronizer:get_persistent_profile_index_reservation(peer_id)].display_name`; when a level ends abruptly (host force-win, or any race) the local peer's reservation can come back `0`/nil → `SPProfiles[0]` nil → vanilla crash at the results screen (exactly what killed danjo as a client). New guard hook skips the reward award (which doesn't persist on modded realm) when the profile won't resolve, instead of crashing. Strict no-op when the profile is valid.

### Also
- **Clarified the fly-disable label/tooltip** (`gt_fly_disable_mult`, no behavior change) — it's a MULTIPLIER (× vanilla), not seconds: 1.0 = vanilla (Halescourge missile 10s / Nurgloth swarm 8s), 0.5 = half, 0 = near-instant. Tooltip now spells out that it's host-only (the boss runs on the host, so only the host's value applies), that the two attacks have different baselines (so one multiplier can't set both to an exact second count), and that the cloud is finite/killable regardless.

### To verify (in-game)
- Host with the **Bots rescue allies awaiting respawn** toggle ON: let a human die and reach the awaiting-respawn (hanging) state; a bot should path over and free them. With `enable_debug_logging` on, watch for `[gt:bot-rescue] scan roster=…` then `RESCUE picked awaiting ally`.
- As a CLIENT in a lobby where the host also runs v0.2.89-dev, toggle godmode and take a hit — no damage.
- As a CLIENT, `/gt_win` now echoes "Only the host can complete the level." As host, `/gt_win` completes as before and the client no longer crashes at results.

## v0.2.88-dev (2026-06-17) -- Solo & QoL: port of True Solo QoL Tweaks (error-free)

### Why
Reimplement the useful features of the third-party "True Solo QoL Tweaks" (workshop 1384087820, last updated 2021) as native gt toggles, so it can be dropped. Bonus: the original logs a CareerSettings error every launch (it indexes `career.activated_ability.ability_class` with no nil-check; VT2's Versus entries `vs_undecided`/`spectator` have no `activated_ability`). This port fixes that with a proper nil-guard. New file `_gt_solo_qol.lua`; new "Solo & QoL (from True Solo)" group, all toggles default OFF; Penlight dependency dropped (plain string fns).

### Added (toggles)
- **Auto-restart mission on team wipe** (`gt_solo_auto_restart_on_wipe`) — on a "lost" end-condition, return `"reload"` instead of going to the keep. `/gt_inn` bails to the keep manually.
- **Assassin / Packmaster spawn text warnings** (`gt_solo_assassin_text_warning`, `gt_solo_packmaster_text_warning`) — colored ASS!/PACK! count callout in the area-indicator banner. The spawn detector is **merged into the existing `ConflictDirector.spawn_queued_unit` hook** (no duplicate) via `mod._gt_solo_on_spawn_queued`; also hooks `Localize` / `PlayerHud.set_current_location` / `AreaIndicatorUI.update`.
- **Assassin/Packmaster hero voice callout** (`gt_solo_assassin_hero_vo`) — forces the hero's "I hear a Gutter Runner" / "I see a Skaven slaver" line on spawn.
- **Disable ult voice line** (`gt_solo_disable_ult_vo`) — the crash-fixed feature. Loops `CareerSettings` with `local aa = career.activated_ability; if aa and aa.ability_class …` (the nil-guard), de-dupes shared ability classes, skips `empire_soldier_tutorial`.
- **Disable mutator death explosions** (`gt_solo_disable_mutator_explosions`), **disable level intro audio** (`gt_solo_disable_intro_audio`), **disable fog** (`gt_solo_disable_fog`), **disable sun shadows** (`gt_solo_disable_sun_shadows`).
- **Draw boss-event spheres** (`gt_solo_draw_boss_spheres`) + **boss path progress** (`gt_solo_boss_path_progress`, StreamingInfo-guarded) — share one `EnemyRecycler.update` hook; sphere LineObject recreated on world change (no stale handle, no `on_game_state_changed` clobber).

### Not ported
- **AUTO_KILL_BOTS** — gt already has "Disable Bots (Solo)" (`gt_no_bots`).

### Notes
Pre-flight confirmed the only existing-hook collision was `ConflictDirector.spawn_queued_unit` (merged). All other hooks are fresh `(Class, method)` pairs. All feature bodies are pcall-guarded and gate on their toggle (no cost when off).

## v0.2.87-dev (2026-06-17) -- Fly-disable tweak corrected to cover BOTH bosses + both attack paths

Correction to the v0.2.86 fly tweak after deeper source review (user report: Halescourge also has a fly disable). The earlier version only scaled Nurgloth's melee swarm and wrongly claimed Halescourge had no fly attack.

- **Replaced** `gt_nurgloth_fly_stun_sec` (Nurgloth-only seconds slider) with **`gt_fly_disable_mult`** (multiplier, default 1.00 = vanilla) that scales BOTH "cloud of flies" disable paths used by Burblespue Halescourge AND Nurgloth the Eternal:
  - Nurgloth's close-range fly-swarm BT action — `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (vanilla 8s; bt_swarm_action.lua:73).
  - The rare seeking **insect-swarm bomb missile** both bosses fire (`seeking_bomb_missile` -> projectile `insect_swarm_missile_01` -> explosion `chaos_slow_bomb_missile` / `_new` "fly_bomb") — `TrueFlightTemplates.sorcerer_slow_bomb_missile.attached_life_time` (vanilla 10s; true_flight_templates.lua:121, ai_breed_snippets.lua:1091, penny_ai_breed_snippets.lua:178, explosion_templates.lua:1325/1355).
  - A multiplier (not seconds) because the two paths have different vanilla durations (8 vs 10); 1.00 reproduces vanilla exactly. Both fly-blobs keep health 5, so the disable can still be ended early by killing the cloud — this only scales the max length.

## v0.2.86-dev (2026-06-17) -- Five new bot options + Nurgloth fly-swarm tweak

Five new bot toggles + one boss-mechanic slider, all default OFF, host-side only (bots/wipe checks run on the host), no network registration. New per-frame bot logic is consolidated into the SINGLE existing `PlayerBotBase.update` hook in `_gt_bot_fixes.lua` (no duplicate hook); new standalone hooks are on distinct `(Class, method)` pairs. All source citations verified against the decompiled vanilla source 2026-06-17.

### Bot Options (added to the existing group)
- **Don't fail the mission while a bot is alive** (`gt_bot_mission_fail_prevention`) — vanilla's wipe check `GameModeHelper.side_is_dead("heroes", ignore_bots=true)` (game_mode_adventure.lua:92) ignores bots, so the run ends when all *humans* are down. Hook forces `ignore_bots=false` for the heroes side so a living bot keeps the run going. Pairs with rescue-awaiting. Experimental.
- **Bots auto pull-up from ledges** (`gt_bot_ledge_pullup` + delay) — no vanilla self-rescue exists (player_character_state_ledge_hanging.lua:91-111); after the delay we call `StatusUtils.set_pulled_up_network(bot, true, helper)` (status_utils.lua:84), crediting the nearest living ally as helper.
- **Bots unstick from ladders** (`gt_bot_ladder_unstick` + delay) — detects a stuck ladder transition (`PlayerBotNavigation._current_transition.type == "ladder"`, player_bot_navigation.lua:276-339) and teleports the bot to the followed teammate via the vanilla teleport primitives (bt_bot_teleport_to_ally_action.lua:82-98).
- **Tighter bot follow distance** (`gt_bot_follow_distance_enabled` + meters) — vanilla snaps a bot back only at >=40 m (`FOLLOW_TELEPORT_DISTANCE_SQ=1600`, bt_bot_conditions.lua:1206). Faithful re-implementation of `BTConditions.should_teleport` with a configurable distance (default 40, set 10 to keep bots close); preserves the go-for-revive exception.
- **Bots instantly grab targeted items** (`gt_bot_instant_pickup`) — points `interaction_unit`/`forced_pickup_unit` at the bot's live pickup candidate so vanilla's `is_forced_pickup` path in `BTConditions.can_loot` (bt_bot_conditions.lua:877-890) bypasses the 3.2 m walk-up gate. Skipped while aiding. Experimental.

### Boss Mechanic Tweaks (new group)
- **Nurgloth fly-swarm disable (seconds)** (`gt_nurgloth_fly_stun_sec`) — slider, default = vanilla 8 s. Mutates `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (breed_chaos_exalted_sorcerer_drachenfels.lua:2018; the disable is the overpowering-blob "cloud of flies", bt_swarm_action.lua:71-77, breakable by killing the blob). Nurgloth-only — Halescourge's signature attack is the vortex, not flies. New module `_gt_boss_tweaks.lua`.

## v0.2.85-dev (2026-06-17) -- Settings logging + bot-rescue diagnostics

Diagnostics only, no gameplay change; all logging debug-gated. (Same change promoted to stable gt v0.2.71-alpha.)
- **Settings snapshot at load** (`[gt:settings@load] …`) + `/gt_dump_settings` — logs every `setting_id = value` so toggle states (incl. bot toggles) are visible in the console log.
- **Per-change setting log** (`[gt:setting-changed] <id> = <value>`) in `on_setting_changed`.
- **Bot-rescue scan diagnostics** (`_gt_bot_fixes.lua`): per-candidate `ready / health_alive / aid_path` + throttled summary (`awaiting=N picked=… not_health_alive=N path_blocked=N`) to pinpoint why a rescue doesn't fire. Verified CW uses `is_ready_for_assisted_respawn` (`deus_spawning.lua:203`, `respawn_handler.lua:502`) and awaiting allies are `HEALTH_ALIVE` (`side_manager.lua:363`), so the repro log reveals which gate fails.
- **Ironbreaker fix log** when it releases the ult-hold to revive.

## v0.2.84-dev (2026-06-16) -- Bot Options: three AI-teammate behavior fixes

### Why
Three long-standing bot AI gaps, requested as toggles. All default OFF, host-side only (bots only exist on the host), and none registers a network event or sends an RPC, so none can affect non-modded lobby members. New code in `_gt_bot_fixes.lua`, grouped under a new "Bot Options (AI Teammates)" settings group. Source citations are into the decompiled vanilla source (verified 2026-06-16).

### Fixes
- **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`). Her career skull (`bw_necromancer_career_utility_weapon`, `is_not_droppable`, `slot_type="potion"`) becomes the PRIMARY item in `slot_potion` at spawn (`simple_inventory_extension.lua:143-154`), so a picked-up potion lands in ADDITIONAL storage. Every handoff check reads only the primary (scoring `player_bot_base.lua:881-888`; give interaction `interactions.lua:1640-1705`), and the skull has no `can_give_other` -> bot never offers. A human swaps past the skull by tapping the potion key; the bot can't. Fix: a throttled `PlayerBotBase.update` hook promotes a stored giveable potion to primary (`swap_equipment_from_storage`, `simple_inventory_extension.lua:2434`) for Necromancer bots, so all vanilla logic works. Gated to real potions (`can_give_other`) so grimoires aren't promoted.
- **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). The IB bot ult holds a `wait_action` (block) for the buff's whole duration (`player_bots_settings.lua` dr_ironbreaker), and `BTConditions.can_activate_ability` short-circuits on `is_using_ability` (`bt_bot_conditions.lua:628`), parking the BT selector on the ability node so the higher-priority revive node (`bt_bot.lua:14-32`) never runs. Fix: hook `can_activate_ability` to return false for an Ironbreaker mid-ult when an ally needs aid, so the bot yields to revive. The ult is a timed buff and keeps running -- not wasted; ability is on cooldown so it won't re-pop.
- **Bots rescue allies awaiting respawn** (`gt_bot_rescue_awaiting`). `PlayerBotBase._select_ally_by_utility:903` excludes `is_ready_for_assisted_respawn` allies from aid entirely, with no branch to handle them. Fix: wrap the picker; when it finds nothing more urgent, scan for a reachable awaiting-respawn ally and return it relabeled `"knocked_down"`. The revive bot-action has no forced `input` (`player_bots_settings.lua` revive), so the interact fires the CONTEXTUAL interaction, which the engine resolves to `assisted_respawn` (`interactions.lua:562`). The wrapper calls the original first, so it composes with other bot mods. Experimental -- verify in-game.

### To verify
- **Necromancer:** play/spectate a Necromancer bot, let it pick up a potion; confirm it can hand it to a player who needs one (and isn't permanently holding the skull).
- **Ironbreaker:** down a teammate while an IB bot's ult is active; the bot should break off to revive instead of standing and blocking.
- **Rescue:** die and reach the awaiting-respawn state with bots free; a bot should path over and perform the assist-respawn.

## v0.2.83-dev (2026-06-14) -- Floating Damage Numbers (client-side; replaces the crash-prone third-party damage mod)

### Why
The third-party floating-damage-numbers mod crashed any lobby that contained a player who didn't have it — the classic signature of a mod that registers a VMF network event / sends RPCs to peers with no matching handler. Rather than decompile and patch it, the capability is rebuilt inside gt, networking-free, so it can't crash non-modded lobby members.

### How it works (all engine-native, no custom GUI)
- **Display:** reuses `DamageNumbersUI` (`scripts/ui/hud_ui/damage_numbers_ui.lua`), which already does world→screen projection + float/crit/fade animation. It's already in the **Adventure** HUD component list, but its `validation_function` only activates it in a mission when `script_data.debug_show_damage_numbers` is set — so we set that flag.
- **Feed:** reuses `DamageUtils.add_unit_floating_damage_numbers` (`damage_utils.lua:3942`) for color/crit/dot/size + the `add_damage_number` event.
- **Capture:** merged into the **existing** godmode `DamageUtils.add_damage_network` / `add_damage_network_player` hooks (the no-duplicate-hook rule forbids a second hook on the same `Class.method`), filtered to the local player as attacker.
- **Why it's crash-proof:** `add_damage_network_player` computes `damage_amount` locally (via `calculate_damage` + `apply_buffs_to_damage`, *before* the `is_server` branch) on host AND client, so accurate numbers need no host round-trip. Feature registers **no** network handlers and sends **no** RPCs.

### Added
- New module `_gt_damage_numbers.lua` (activation-flag sync + `mod._gt_dn_show` trigger; wraps `on_setting_changed` / `on_game_state_changed` via the chain pattern).
- Settings group **Floating Damage Numbers**: `gt_damage_numbers_enabled` (default off) with sub-toggle `gt_damage_numbers_include_dots` (default on — also shows DoT ticks & explosions via the `add_damage_network` path).

### Changed
- The two godmode `DamageUtils` hooks are now consolidated (godmode + damage-number feed) and capture the function's single return `damage_amount`. Behavior-identical for godmode.

### To verify (in-game)
- Enable the setting, **load a mission** (activation is evaluated at HUD build, so it takes effect on the next map), and confirm numbers float over enemies you hit (crit/headshot emphasized, DoT/explosion numbers grey when the sub-toggle is on).
- Join/host a lobby with a player who does **not** have gt and confirm no crash (this is the whole point — there is no network traffic from this feature).
- Toggle the sub-toggle off and confirm only direct weapon hits show numbers.

## v0.2.82-dev (2026-06-13) -- Fix keep-menu-hotkey mid-mission crash (Issue #62) + table-form hook nil-guards (Issue #70.1)

### Why
Multi-agent audit 2026-06-13.

**Issue #62 (crash) — "Keep Menus in Mission hotkeys causes crash".** The "Keep Menus in Missions" feature used three patches; patch (2) hooked `IngameUI.handle_menu_hotkeys` and unconditionally force-flipped the hotkeys-enabled arg to `true` whenever `mission_inventory_enabled` was on. That enabled EVERY keep hotkey mid-mission, not just inventory — Hero Select / Map / Achievements / Weave Forge / Store each transition to a view that spawns a dedicated `levels/ui_*/world` preview level which is NOT in a mission's package set, so pressing those keys fataled with "Level not loaded" + the `c_api_world.cpp:691` assert (confirmed against the attached crash log; same bug class as the closed cim Issue #50). The flip never reliably opened the inventory either (vanilla `can_interact`/transition gates still blocked it) — the working in-mission inventory path is the separate `/gt_inv` command + `gt_open_inv_hotkey` keybind (direct `handle_transition("hero_view_force")`), which does not depend on this hook.

**Issue #70.1 (hygiene).** Four table-form hooks were registered without an existence guard, inconsistent with the rest of the repo (cf. `career_tweaker_balance.lua:2472`). The targets are boot-loaded vanilla class globals so the unguarded form works in practice; the guard is latent load-order safety only.

### Changed
- **Removed** the `IngameUI.handle_menu_hotkeys` hotkey-flip hook (Issue #62). `mission_inventory_enabled` still drives the `InventorySettings` game-mode patch (1) and the ESC-menu "Open Inventory" entry (3) — only the crash-causing patch (2) is gone. The feature-overview comment block was updated accordingly.
- **Nil-guarded** four table-form hooks (Issue #70.1): `CareerExtension.update` (`:3272`), `GenericStatusExtension.add_fatigue_points` (`:3385`), `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed` (`:3456-3457`) now wrap in `if X and X.method then ... end`. Behavior-identical (targets always loaded).

### Tests
- New `/gt_regression_test` check `gt_no_mission_hotkey_flip` — source-pattern guard that FAILS if the `IngameUI.handle_menu_hotkeys` hook is reintroduced (needle split across two string literals to avoid self-match; degrades to no-op when source introspection is unavailable).

### To verify (in-game — behavior-changing)
- Mid-mission, press each keep-menu hotkey (Hero Select / Map / Achievements / Weave Forge / Store) and confirm **no crash** (they now no-op, as in vanilla).
- Confirm `/gt_inv` (and the `gt_open_inv_hotkey` keybind) still opens the inventory mid-mission, and the ESC-menu "Open Inventory" entry still works.

## v0.2.81-dev (2026-06-08) -- Failnotify hardening (Issue #72): leaving_game guard, unknown-result teardown, ungated F17 warning, test backfill

### Why
The 2026-06-08 post-ship re-review of v0.2.80 verified all four lobby fixes correct but flagged hardening gaps (filed as Issue #72). This closes them.

### Changed (`_gt_lobby_failed_join_reveal.lua`)
- **leaving_game guard:** the `create_popup` hook now defers to vanilla when `Managers.account:leaving_game()` — vanilla's own create_popup is a no-op in that window (state_loading.lua:2448-2450), so the mod no longer queues an enriched popup against a dying state object.
- **Unknown popup result:** `_consume_results` (factored out of the update callback, parameterized on popup_mgr for testability) grew an `else` branch — an unrecognized result logs via **ungated `mod:warning`** and still drives the restart_as_server teardown so the user is never stranded on the loading screen. Mirrors vanilla's logging of unknown results (state_loading.lua:1588). Unreachable today (only two button actions exist); defensive.
- **F17 warning ungated:** the popup-already-up soft-defer now logs via `mod:warning` (was debug-gated `_dbg_alert`); decision routed through exported `M._should_defer_for_existing_popup`.

### Tests (Issue #72 backfill)
- `gt_lobby_failnotify_unknown_result_drives_teardown` — injects a synthetic pending popup, drives the real consumer with a stub manager returning an unknown action, asserts the entry is consumed AND teardown fields are set.
- `gt_lobby_failnotify_popup_up_soft_defers` — pins the F17 guard's truth table; raises (instead of soft-deferring) fail the test.
- `gt_lobby_failnotify_unpack_preserves_leading_nils` — replica of the `3 + select("#", ...)` forward idiom under all-nil leading args + trailing format varargs (the state_loading.lua:1084 shape).
- Test exports: `mod._gt_failnotify_consume_results`, `mod._gt_failnotify_pending_popups`, `mod._gt_failnotify_should_defer`.

## v0.2.80-dev (2026-06-07) -- Lobby join-event clobber + failed-join popup race fixes

### Why
Audit 2026-06-07 found four correctness bugs in the `gt_lobby_*` modules:

- **F3 (HIGH) -- event-registration clobber.** `slot_reservations`, `session_ignore`, and `motd` each registered the SAME `(mod, "on_player_joined_party")` pair on `Managers.state.event`. Stingray's `EventManager` keys callbacks by `(object, event_name)` (`foundation/.../event_manager.lua:18-21`), so registering the same pair is last-writer-wins -- only ONE of the three handlers ever fired on a player join; the other two silently never ran. (Separately, every handler was mis-threaded: `EventManager.trigger` calls `object[name](object, ...)` at `event_manager.lua:42`, prepending `mod` as the first arg, so the handlers' `peer_id` param was actually `mod` -- meaning even the surviving handler was operating on the wrong value.)
- **F4 (HIGH) -- double consume-once popup race.** The enriched failed-join popup id was assigned to `state_loading_self._popup_id` AND polled by the mod's own update consumer, while vanilla `StateLoading._try_next_state` -> `_handle_popup` (`state_loading.lua:1308-1310`/`1565-1566`) ALSO polls/consumes the same id. `query_result` is consume-once, so one poller gets the result and the other sees `nil` -- if the mod won the read, vanilla never ran its `restart_as_server` teardown and the loading screen could hang.
- **F17 (LOW) -- hard assert in hook.** `assert(self._popup_id == nil, ...)` inside the `create_popup` hook could hard-crash if a popup was already up at intercept time.
- **unpack-safety.** The vanilla-fallback built `args = { header, action, right_button, ... }` (leading three often nil, trailing format varargs present) and `unpack(args)`'d it -- a bare `#args` boundary search over an array with nil holes truncates non-deterministically (VMF_RECIPES § 2a), silently dropping vanilla's `string.format` args.

### Changed
- `general_tweaker_dev.lua:6191-6249` -- NEW shared `on_player_joined_party` dispatcher. Defines `mod._gt_lobby_join_handlers`, `mod._gt_lobby_register_join_handler(name, fn)`, and the single registered method `mod.gt_lobby_on_player_joined_party` (swallows the EventManager-prepended `self`, then pcall-invokes every appended handler in order). Owns the ONE `(mod, "on_player_joined_party")` registration plus the per-state-transition re-register via `_gt_register_update`. (F3)
- `_gt_lobby_session_ignore.lua:111-120` -- dropped the module's own `em:register` + `on_game_state_changed` wrap; now `mod._gt_lobby_register_join_handler("session_ignore", _on_player_joined_party)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_slot_reservations.lua:202-217` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("slot_reservations", ...)`. (F3)
- `_gt_lobby_motd.lua:213-226` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("motd", ...)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_failed_join_reveal.lua:240-266` -- `_queue_enriched_popup` no longer assigns `state_loading_self._popup_id`; the enriched popup lives ONLY in `_pending_popups` (now also stashing the StateLoading instance as `entry.sl`). (F4)
- `_gt_lobby_failed_join_reveal.lua:277-315` -- new `_drive_restart_as_server_teardown(sl)` mirrors vanilla `_handle_popup`'s `restart_as_server` branch (`state_loading.lua:1570-1577`); the mod poller is now the SOLE owner of both popup actions and drives the teardown itself. Exposed as `mod._gt_failnotify_drive_teardown` (line 408) for the regression test. (F4)
- `_gt_lobby_failed_join_reveal.lua:365-368` -- replaced `assert(self._popup_id == nil, ...)` with a soft guard: `_dbg_alert` + fall through to vanilla. Added a local `_dbg_alert` (line 43) deferring to `mod._gt_dbg_alert`. (F17)
- `_gt_lobby_failed_join_reveal.lua:323-334` -- captured true arity via `local n = 3 + select("#", ...)` and pass `unpack(args, 1, n)` in the vanilla fallback. (unpack-safety)

### Tests
- `general_tweaker_dev.lua` `/gt_regression_test` adds:
  - `gt_lobby_join_dispatch_consolidated` -- all three join-handlers (`session_ignore`, `slot_reservations`, `motd`) are reachable from the single `mod._gt_lobby_join_handlers` list and the single registered method exists. FAILS if any module reverts to self-registration.
  - `gt_lobby_join_dispatch_pcall_isolated` -- drives the dispatcher with two synthetic handlers (first raises, second records); asserts the second still runs (pcall isolation) and receives the true `peer_id` (object-prepend stripped).
  - `gt_lobby_failnotify_teardown_driver` -- runs the F4 teardown driver against a synthetic StateLoading and asserts it sets `_teardown_network=true`, `_permission_to_go_to_next_state=true`, and `force_done()`s the first-time view; tolerates a nil sl.

### To verify
- Host a modded lobby with `slot_reservations`, `session_ignore`, AND `motd` all enabled; have a non-reserved/ignored peer join -- all three behaviors should now fire (kick-if-reserved / kick-if-ignored / MOTD send) rather than only one.
- Attempt to join a modded host with a missing/mismatched mod set: the enriched failed-join popup appears; clicking "Open Workshop" opens the URL AND leaves the loading screen cleanly; clicking "Close" (restart_as_server) returns to title without a hang.
- `/gt_regression_test` -- all three new checks PASS.

## v0.2.79-dev (2026-06-06) -- Memory Watchdog rides Debug Logging (drop redundant toggle)

The Lua Memory Watchdog (v0.2.77) had its own `memwatch_enabled` checkbox, separate from the universal `enable_debug_logging` toggle. That was the wrong call — the heap curve is a debug diagnostic like every other, and a separate switch to remember just meant a leak session got missed (the watchdog defaulted off, so the 2026-06-06 OOM logs had zero `[memwatch]` lines despite the mod being installed).

**Fix:** the watchdog now gates on `enable_debug_logging` — it runs automatically whenever Debug Logging is on (which is already on during any data-gathering session). Removed the `memwatch_enabled` checkbox + its loc keys; kept `memwatch_interval`. The `[memwatch]` log prefix stays greppable, so it's trivially separated from the rest of the debug stream when reading the log. `/gt_mem` on-demand snapshot unchanged.

## v0.2.78-dev (2026-06-06) -- GC mitigation to survive long sessions despite the leak

### Why
A Chaos Wastes expedition runs ~1 hour, but the Lua heap OOM'd at 26 minutes (v0.2.77 investigation). "Restart between missions" loses the run — not viable. This adds runtime GC mitigation so a full run can complete while the leaking mod is still being isolated + fixed.

### What this adds (two settings, under the watchdog toggles)
- **`gc_mitigation_enabled`** (checkbox, default off): tightens Lua's incremental GC — `setpause` 200→110 and `setstepmul` 200→400. Lua's default waits until the heap doubles before collecting; under heavy churn the collector falls behind and the heap climbs even though much of it is COLLECTABLE. Tightening keeps the heap near the true live set. On disable, restores the 200/200 defaults.
- **`gc_full_collect_sec`** (numeric 0-120, default 0=off): when aggressive GC is on, force a complete `collectgarbage("collect")` this often. Reclaims everything the incremental collector hasn't between cycles. Each collect is a brief frame hitch (bigger heap = longer) — but a short stutter beats a hard crash. Logs `[gc_mit] full collect: X KB -> Y KB (freed Z KB)` so you can see how much it reclaims (large freed = collectable garbage that was piling up = mitigation working; near-zero freed = true reference leak, only fixable in the offending mod).

### Honest caveat
If the growth is a TRUE reference leak (objects stay reachable), neither lever reclaims them — only fixing the offending mod does. These buy time when the growth is collectable garbage / GC-falling-behind, which the thrashing-GC signature in the crash log suggests is at least part of it. Pair with the Memory Watchdog (v0.2.77) to confirm the heap actually stays lower — and the `freed` number on each full collect tells you directly whether it's helping.

### Recommended for a long run tonight
1. Turn ON "Aggressive GC", set "Force Full GC Every" to 45-60s.
2. Turn ON "Lua Memory Watchdog" (interval 10s) to capture the curve.
3. Turn OFF Debug Logging on all -dev mods (cim_dev, cosmetics_tweaker, wt, ct_dev, gt_dev) — removes a large allocation source.

## v0.2.77-dev (2026-06-06) -- Lua Memory Watchdog (leak-hunt instrumentation)

### Why
User hit a hard Lua heap OOM crash on 2026-06-06 (`cemetery_belakor_path1`, GUID 2b762ad3): `Not enough memory reserved for heap lua_heap` — the 1 GB Lua scripting heap filled in 26 minutes with the GC thrashing (repeated 286-692ms full collections that couldn't reclaim enough = ~1 GB of LIVE Lua objects = a true reference leak). Static audit of the weapon-spawn-path mods (ct / wt / cosmetics_tweaker / Loremaster's Armoury) found them all independently leak-clean: cosmetics uses weak-keyed (`__mode="k"`) per-unit tables, wt's safe/traced_hook only allocates transient garbage, LA flushes its queue every frame, ct isn't in the per-frame path. The leak is in a not-yet-audited mod and can't be pinned by reading logs alone — it needs runtime memory instrumentation.

### What this adds
A **Lua Memory Watchdog**: logs the live Lua heap size every N seconds so a leak session shows the growth curve directly.

- **Settings** (under the debug toggles, top-level): `memwatch_enabled` (checkbox, default off) + `memwatch_interval` (numeric 2-60s, default 10). Independent of `enable_debug_logging` on purpose — a leak hunt wants the memory curve WITHOUT the rest of gt's per-event debug spam (which is itself allocation churn that muddies the signal).
- **Per-frame consumer** registered via the existing `_register_update` registry (pcall-isolated like every other gt update consumer). Accumulates `dt`; every interval logs:
  ```
  [memwatch] lua_kb=487213 (475.8 MB, 46.5% of 1GB cap) delta=+8420 peak_kb=487213 level=cemetery_belakor_path1 units=1842 t=600s
  ```
  `collectgarbage("count")` is the KB ground-truth for the same `lua_heap` the engine caps at 1 GB. `delta` per window is the leak rate; the window where `delta` spikes pins the trigger (which level, after which action). `pct` shows proximity to the OOM ceiling. Reading the counter does NOT force a collection — it's cheap.
- **`/gt_mem` command** — on-demand snapshot to chat regardless of the toggle, for quick before/after marks around a suspected leaky action.

### How to use it (next session)
1. Enable "Lua Memory Watchdog" in gt settings (leave Debug Logging OFF for a clean signal).
2. Play until the leak manifests (or just play a full session).
3. Read the `[memwatch]` lines in the console log. Monotonic `lua_kb` climb with a positive `delta` every window = leak confirmed; the level/timeframe where `delta` jumps is the trigger.
4. Bisect the modlist across runs (disable half, repeat) to isolate the single offending mod, then audit + fix THAT mod so it's independently leak-clean.

### Cost
Enabled: one `collectgarbage("count")` (counter read, no collection) + one log line per interval — negligible. Disabled: a single dt-accumulate + early return — free.

## v0.2.76-dev (2026-06-02) -- Add "Disable Bots (Solo)" toggle; fix that bots weren't removed mid-mission

### Why
User report: the existing "no bots" path didn't remove bots mid-mission, and there was no way to start a mission bot-free (wanted for true solo runs / speedruns). The only bot-off control was the `/gt_bottoggle` chat command, which flips `level_settings.no_bots_allowed` — a load-time gate with **no despawn path**, so existing bots stayed in the party and it isn't re-read per server tick. Confirmed against `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371): the per-tick gate the engine actually honors is `script_data.ai_bots_disabled`, not `no_bots_allowed`.

### Mechanic
`script_data.ai_bots_disabled` is checked inside `_handle_bots` on every `server_update` across all three mission modes:
- `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371)
- `GameModeDeus._handle_bots` (game_mode_deus.lua:527)
- `GameModeWeave._handle_bots` (game_mode_weave.lua:462)

When the flag is true and bots exist, vanilla runs `self:_clear_bots(true)` then returns early — so:
- Flipping it **ON mid-mission** despawns the current bots on the next tick AND blocks the delta-fill that would re-add them.
- Leaving it **ON** keeps the party bot-free from the first frame of every subsequent mission.
- Flipping it **OFF** lets the normal top-up logic refill on the next tick.

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_no_bots` checkbox appended to `gameplay_group` (after `gt_bots_in_keep`).
- **`general_tweaker_dev_localization.lua`**: `gt_no_bots` ("Disable Bots (Solo)") + tooltip.
- **`general_tweaker_dev.lua`**:
  - New "Disable Bots (Solo)" section with `_gt_apply_no_bots(enabled)` → sets `script_data.ai_bots_disabled = enabled and true or nil`. Forward-declared near the top (both `on_setting_changed` and `on_game_state_changed` reference it before its definition).
  - `on_setting_changed("gt_no_bots")` → apply immediately (instant mid-mission despawn / re-enable).
  - `on_game_state_changed` StateIngame-enter → re-apply so "no bots from mission start" survives level transitions and the game's own `ai_bots_disabled` resets.
  - Applied once at load so a persisted ON survives a mod reload.
  - Chat alias `/gt_no_bots`.

### Compatibility
- Host-only effective: bots are server-managed and `script_data` is local, so the flag only does anything on the host. Tooltip says so. Set locally on clients too (harmless).
- Independent of `gt_bots_in_keep` (keep-fill) — that feature calls `_add_bot_to_party` directly in inn modes, which don't run `_handle_bots`, so the two don't fight. Running both ON means bots in the keep for preview, none in missions.
- The old `/gt_bottoggle` (level `no_bots_allowed` flip) is left in place for its keep-spawn use; the new toggle is the correct mission-facing control.

### Regression tests (`/gt_regression_test`)
- `no_bots_setting_registered` — `gt_no_bots` widget exists in the data tree.
- `no_bots_apply_sets_ai_bots_disabled` — `_gt_apply_no_bots(true)` sets `script_data.ai_bots_disabled = true`, `(false)` clears it. Pins the correct engine flag so a future refactor can't silently regress to the no-despawn `no_bots_allowed` path. Saves/restores the live flag value around the probe.

## v0.2.75-dev (2026-05-30) -- Self-refreshing vanilla-name localization dump (feeds tools/gen-name-map)

### Why
`tools/gen-name-map/gen-name-map.ps1` resolves every mod-created display name from repo data but leaves ~3,010 VANILLA names `unresolved`: their English strings live in undumped `.package` bundles, not in the decompiled source. The only place those strings exist resolved is the running game (`Localize(loc_key)`). The maintainer wanted the vanilla half captured the same way the boon dump already is -- but **automatically, with no command to remember**.

### What
New sibling module `_gt_name_dump.lua`:
- On **keep/inn entry** (`StateIngame` enter), **once per game build** (gated on `Application.build_identifier()` stored in VMF settings; re-fires only after a game patch -- exactly when vanilla names could change), **silently** walks the in-memory `ItemMasterList` (`display_name` + `description`), `SPProfiles` (careers/heroes), and `Breeds`, calls `Localize()` on each loc key, and emits `[gt:name_dump] <loc_key>\t<English>` lines (same tab-separated shape as `dumps/boon_loc_dump.txt`) to the console log.
- **Output is the console log, not a file.** PHASE-0 FINDING (confirmed against the existing `/dump_level` code): VMF mods cannot write arbitrary files -- `io.open(...,"w")`, `mod:get_temp_data_directory`, and `Application.save_user_settings_to_file` are all unavailable from sandboxed mod code. The console-log + repo-side-grep route is the established gt dump doctrine.
- New VMF setting `gt_auto_name_dump` (checkbox, **default ON**) gates the auto-fire; new `/gt_dump_names` command forces a re-dump on demand (bypasses the build gate).
- Logging per PROJECT_STANDARDS § 3.6: payload via `mod:info` (operational telemetry, always logged); the "dump complete" confirmation is `_dbg` (log only); a dump FAILURE is `_dbg_alert` (chat+log, gated on debug logging). Applied marker untouched.

The generator side (`tools/gen-name-map/gen-name-map.ps1`) now auto-discovers and ingests the freshest dump with no flags (repo `dumps/name_loc_dump.txt` -> Fatshark user-dir file -> newest `console_logs/*.log` with `[gt:name_dump]` lines), fills any still-`unresolved` vanilla entry whose loc_key the dump knows (`display_name_source = "game_dump"`), and records the dump path/build/counts in the generated headers. No dump -> vanilla stays unresolved (never fabricated). Loop documented in `docs/generated/README.md`.

### Verify
Fixture (`dumps/name_loc_dump.SAMPLE.txt`, real vanilla loc_keys) flips 5 entries unresolved->resolved with `display_name_source = game_dump`; no-dump baseline returns to all-vanilla-unresolved. Requires a ship signal before Workshop upload.

## v0.2.73-dev (2026-05-27) -- Fix Issue #60: Host AI Takeover crashes `LocomotionSystem.update_animation_lods` next frame

### Why
User crash 2026-05-27 15:31:22 (session `7409d362-369e-43aa-a8e7-35b789b3b79d`). Crashify-tagged with "AI takeover crash". Engine reported `locomotion_system.lua:242: attempt to index local 'player' (a nil value)` in `update_animation_lods`. Stack contains no gt frames — vanilla `LocomotionSystem.update` called directly from `entity_system_bag.lua:62`. Lua locals at frame [1] show `player = nil`.

### Mechanic
Vanilla `LocomotionSystem.update_animation_lods` (in our decompile around line 227, in the shipped binary at the line the engine reports):

```lua
local player = self._override_player or Managers.player:local_player()
local viewport_name = player.viewport_name  -- crash here
```

Gt's host AI Takeover path (`_ai_swap_human_to_bot`) destroys the host's local Player object as part of the swap (line 2401: `pm:remove_player(peer_id, local_player_id)`). After that:
- `Managers.player:local_player()` returns nil (no local human exists).
- `self._override_player` is nil (gt never set it).
- `nil or nil` = nil → next frame crashes on `player.viewport_name`.

The crash fires ~0.6 s after the swap (`15:31:22.239 [ai_toggle:host] human->bot: ok` → `15:31:22.858` Lua Error). Confirmed reproducible — any host using `/ai` or the AI Takeover checkbox while in a mission will hit this.

Vanilla has a parallel case in benchmark mode where the human is replaced by a bot. The fix lives at `scripts/utils/benchmark/benchmark_handler.lua:423`:
```lua
locomotion_system:set_override_player(bot_player)
```

We mirror it.

### Changed
- **`general_tweaker_dev.lua`** `_ai_swap_human_to_bot`:
  - Captured the bot Player from `game_mode:_add_bot_to_party(...)` return value.
  - For host self-toggle (`not player.remote`), looks up `Managers.state.entity:system("locomotion_system")` and calls `set_override_player(bot_player)`. Bot reuses the host's slot, so `bot_player.viewport_name` is `"player_1"` (same as the host had). Vanilla's `update_animation_lods` now finds a valid viewport.
- **`general_tweaker_dev.lua`** `_ai_swap_bot_to_human`:
  - Before re-adding the human Player (or, in the remote-toggle case, returning to caller), clears the override: `locomotion_system:set_override_player(nil)`. Otherwise the override would dangle on the now-removed bot Player object and `update_animation_lods` would read `viewport_name` from a destroyed instance.
- **New marker** `CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73 = "gt-ai-locomotion-override-on-host-swap"` near the top of the file alongside the other AI Takeover markers.

### Regression tests (`/gt_regression_test`)
Two new checks:
- `ai_locomotion_override_marker_present` — marker constant unchanged. Belt-and-suspenders for refactors that drop the source-pattern check.
- `ai_locomotion_override_set_and_cleared` — reads the on-disk file via `debug.getinfo` source introspection and asserts the swap path contains `locomotion_system:set_override_player(bot_player)` AND the swap-back path contains `locomotion_system:set_override_player(nil)`. Catches partial reverts that keep the marker but drop one of the two calls. Degrades gracefully (no failure) when the install path doesn't expose the source for introspection.

### Stable status
The same bug exists in public `general_tweaker/` v0.2.69-alpha — host AI Takeover was added there in v0.2.52 and has the same `pm:remove_player` call with no `set_override_player` follow-up. Any host on stable using `/ai` mid-mission will crash. Per the dev-stream rule, we hold the merge until the user signs off, but flag it as a crash-class candidate for fast-tracking alongside the Issue #59 prefix-match fix.

## v0.2.72-dev (2026-05-26) -- Fix Issue #59: Drachenfels boss BT crash on CW dlc_castle_*_path1 (bt_conditions.lua:309)

### Why
Host crash 2026-05-26 in a CW Drachenfels run on level `dlc_castle_slaanesh_path1` (host running stable gt v0.2.69-alpha, same `_gt_cs_is_in_level` code as dev). `<<Script Error>> bt_conditions.lua:309: attempt to compare nil with number`. The crashed BT condition was `at_one_fifth_health`, called from the chaos_exalted_sorcerer_drachenfels `final offense phase` selector. Stack frame [6] = `general_tweaker.lua:4127` (the `AISystem.update_brains` hook) — gt was on the stack because every BT update routes through that pass-through gate, but the bug was downstream of it.

### Mechanic
1. gt hooks `BTConditions.transitioned_one_third_health` and biases the return to `true` when **outside** `dlc_castle` (the comment says "so the boss skips its arena-specific defensive phase outside its arena"). The hook body is `(_gt_cs_is_in_level("dlc_castle") and func(...)) or true`.
2. `_gt_cs_is_in_level(level_name)` previously did **exact-match**: `return level_key == level_name`. In CW, the Drachenfels arena loads under the level key `dlc_castle_slaanesh_path1` (or `_khorne_path1` / `_chaos_boss_path1` / etc. depending on the CW path). Exact-match against `"dlc_castle"` returned **false**.
3. With the gate false, the hook returned `true` without calling vanilla. The BT believed the boss had transitioned to one-third-health and entered the `final offense phase` branch.
4. Phase-init for that branch normally runs as part of vanilla `transitioned_one_third_health` — which we skipped. So `blackboard.current_health_percent` was never populated.
5. The first child condition in the offense-phase branch is `at_one_fifth_health` at bt_conditions.lua:309: `return blackboard.current_health_percent <= 0.2`. nil <= 0.2 → fatal compare. Host drops, everyone disconnects.

The bug existed on every CW variant of dlc_castle for as long as the exact-match gate has been in place. Bookmark Issue #59.

### Changed
- **`general_tweaker_dev.lua`**: `_gt_cs_is_in_level` now matches `level_key == level_name` OR `string.sub(level_key, 1, #level_name + 1) == (level_name .. "_")`. The underscore-boundary check prevents false positives against hypothetical levels with a shared word stem (e.g. a `dlc_castled_*` map). Three other gt_cs hooks call this helper (run_on_spawn arena init, level_analysis skip, the BT condition itself) — all benefit identically from the prefix match.

### Regression test (`/gt_regression_test`)
- `gt_cs_is_in_level_prefix_match` — table-driven assertion over seven cases: exact match, vanilla path variant, **Issue #59 CW theme variant**, CW boss variant, unrelated level, shared-prefix-without-underscore, keep level. Stubs `Managers.state.game_mode:level_key()` to drive each case, restores state on exit. Catches a refactor that reverts the prefix-match OR changes the underscore-boundary semantics.

### Stable status
The same bug exists in the public `general_tweaker/` v0.2.69-alpha (`_gt_cs_is_in_level` at line 3767 — identical exact-match code). Any host on stable will keep crashing on CW dlc_castle_*_path1 runs until we merge this fix down. Per the dev-stream rule we hold here until the user signs off on a stable release.

## v0.2.71-dev (2026-05-26) -- Add "Allow Bots in Keep" toggle (gameplay_group)

### Why
User direction 2026-05-26: vanilla VT2 doesn't spawn bots in the keep / Chaos Wastes hub / Versus inn, so the party visually reads as one-player even when the host has reserved an empty 4-slot lobby. Friends use the lobby state to preview party composition before launching a mission — empty slots make this confusing. Reproducing the adventure-mode bot-fill against the inn party gives the host a populated lobby for testing and visual continuity. Dev-stream first; merges to stable after a stability cycle.

### Mechanic
- **Why vanilla skips it.** `GameModeInn` / `GameModeInnDeus` / `GameModeInnVs` are distinct game-mode classes (not `GameModeAdventure`); their `server_update` deliberately omits the `_handle_bots()` call adventure mode runs. But `_add_bot_to_party` and `_remove_bot_instant` are defined on `GameModeBase` and inherited — they're callable on every inn mode, just never invoked.
- **What we do.** Register a 1Hz `mod.update` consumer (`_register_update("bots_in_keep", ...)`) that, while the toggle is on AND host AND `DamageUtils.is_in_inn`, tops party 1 up to its `num_slots`. Profile picking mirrors `GameModeAdventure._get_first_available_bot_profile` exactly: walk `PROFILES_BY_AFFILIATION.heroes`, filter by `profile_synchronizer:is_profile_in_use`, sort by `PlayerData.bot_spawn_priority` (or `ProfileIndexToPriorityIndex` as the vanilla fallback), then read `bot_career_index` off `hero_attributes`. No engine-internal field reads — every input is a global.
- **Bookkeeping.** `_bik_spawned` (Player table → true) tracks the bots we added so toggle-off / leave-keep can clear only ours without disturbing anything vanilla logic might have left behind. State-shutdown destroys bot units; `on_game_state_changed` calls `_bik_reset_bookkeeping()` (table-only reset, no engine calls on torn-down references).

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_bots_in_keep` checkbox appended to `gameplay_group` (alongside `ai_takeover_enabled`).
- **`general_tweaker_dev_localization.lua`**: `gt_bots_in_keep` ("Allow Bots in Keep") + `gt_bots_in_keep_tooltip` entries.
- **`general_tweaker_dev.lua`**:
  - New "Bots in Keep" section after the AI Toggle block. Provides `_bik_in_inn` / `_bik_is_host` / `_bik_game_mode` / `_bik_active` gates, `_bik_pick_next_bot` (priority-aware profile selector), `_bik_fill` (top up party 1), `_bik_clear` (remove our bots), `_bik_reset_bookkeeping` (drop tracking table). Exposed as `mod._bik_*` so the early `on_setting_changed` / `on_game_state_changed` closures can drive them (table-field reads resolve at call time, no forward-decl needed).
  - `on_setting_changed("gt_bots_in_keep")` → immediate fill on ON / clear on OFF (responsive UX; the 1Hz tick is the steady-state backstop).
  - `on_game_state_changed` → `_bik_reset_bookkeeping` on every state transition (prevents dangling Player references from the previous session).
  - Chat alias `/gt_bots_in_keep`.

### Compatibility
- Host-only behavior; clients see whatever bots the host spawned via the standard `_add_bot_to_party` path. No new RPC.
- Doesn't interact with `ai_takeover_enabled` directly — they target different game-mode contexts (`gt_bots_in_keep` requires `is_in_inn`; `ai_takeover_enabled` is refused in inn modes).
- DLC gate: `_add_bot_to_party` itself doesn't enforce DLC ownership, but `is_profile_in_use` covers any human-reserved profile and the bot profile list comes from `PROFILES_BY_AFFILIATION.heroes` which already respects which careers vanilla considers playable. No additional gate needed.

### Regression tests (`/gt_regression_test`)
Four new checks pin the feature's invariants — surfaced by post-deploy log scour 2026-05-26:
- `bots_in_keep_helpers_exposed` — `mod._bik_fill` / `_clear` / `_active` / `_reset_bookkeeping` are all functions. Catches a refactor that drops the `mod._bik_*` exposure (would silently no-op `on_setting_changed` and `on_game_state_changed`).
- `bots_in_keep_active_default_false` — `_bik_active()` returns false with the toggle off (default install state). Catches inverted gates and raises from missing dependencies.
- `bots_in_keep_reset_bookkeeping_safe` — `_bik_reset_bookkeeping` is idempotent and never raises (it fires on every state transition).
- `bots_in_keep_setting_registered` — walks the data widget tree and asserts `gt_bots_in_keep` exists. Catches a refactor that drops the checkbox from `gameplay_group` without updating the feature module.

## v0.2.70-dev — 2026-05-26

- **FORK POINT**: friends-only dev stream for in-flight gt work. Parent `general_tweaker/` (Workshop ID 3713619122) remains the public stable stream.
- Mod_id renamed `gt` → `gt_dev`. Scripts dir renamed `general_tweaker` → `general_tweaker_dev`. itemV2.cfg: visibility friends_only, published_id cleared.
- **RPC schema caveat**: `GT_LOBBY_RPC_SCHEMA` is per-mod-id; gt_dev clients can't sync lobby state with gt-stable clients (different mod_id, different network channel). Dev cohort should pin to one stream.

## v0.2.66-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("General Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `general_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gt] v<MOD_VERSION> loaded")` runs once.

## v0.2.62-dev (2026-05-25) -- Add /gt_lobby_motd_set + /gt_lobby_motd_clear chat commands (replaces the invalid VMF text_input widget removed in v0.2.61)

### Why
v0.2.61-dev inlined a fix to `general_tweaker_data.lua` that REMOVED the `gt_lobby_motd_text` widget — it had `type = "text_input"`, which is not a valid VMF widget type, and caused widget#103 to fail VMF validation and break gt options init entirely on 2026-05-25. Removing the widget eliminated the only authoring surface for the MOTD body, so this version restores host authoring via chat commands instead.

### Changed
- **`_gt_lobby_motd.lua`:** Added two chat commands.
  - `/gt_lobby_motd_set <text>` — writes `mod:set("gt_lobby_motd_text", text)`. With no arg, prints the currently-stored MOTD (or `(empty)`) and a usage hint. Echoes a confirmation and logs an info line on set.
  - `/gt_lobby_motd_clear` — clears the stored MOTD (sets to empty string).
- **`general_tweaker.lua`:** `MOD_VERSION` bumped `0.2.60-dev` -> `0.2.62-dev` (skips `0.2.61-dev`, which was the inline widget-removal fix landed without a CHANGELOG entry; see "Notes" below).
- **`itemV2.cfg`:** Title suffix refreshed to `v0.2.62-dev` (will be re-stamped on next upload by VMBLauncher anyway).

### Compatibility
The send/receive RPC path is unchanged — `_on_player_joined_party` still reads `mod:get("gt_lobby_motd_text")` and `_send_motd_to_peer` still chunks + sends with the same schema. Whether the text got there via the old widget (pre-0.2.61) or the new chat command (0.2.62+), the read path is identical. No bump to `mod.GT_LOBBY_RPC_SCHEMA` required.

### Notes
v0.2.61-dev was an inline fix to `general_tweaker_data.lua` removing the broken `gt_lobby_motd_text` widget; the MOD_VERSION constant in `general_tweaker.lua` was not bumped at the time. This 0.2.62 bump reconciles MOD_VERSION with the on-disk widget state.

The orphaned `gt_lobby_motd_text` / `gt_lobby_motd_text_tooltip` localization keys (general_tweaker_localization.lua:529-530) are harmless — VMF resolves them only when a widget references the setting_id, which no longer happens. Left in place against the possibility of a future custom widget type or HeroView authoring UI.

## 0.2.60-dev (2026-05-25) -- Absorb lobby_tweaker (slot reservations, session ignore, kick-idle, MOTD, failed-join mod-list reveal); add GT_LOBBY_RPC_SCHEMA versioning (closes Issue #43)

### Why
User direction 2026-05-25: "I deleted lobby tweaker, merge its features into general tweaker." Following the same archive-not-delete pattern used for `la_prefix_patch` earlier the same day. Issue #43 -- "Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)" -- becomes gt's responsibility on absorption and is closed simultaneously.

### Changed
- **New files:** Seven `_gt_lobby_*.lua` modules under `general_tweaker/scripts/mods/general_tweaker/` migrated 1:1 from lt v0.1.7-dev:
  - `_gt_lobby_slot_reservations.lua` (was `lobby_tweaker/_slot_reservations.lua`)
  - `_gt_lobby_session_ignore.lua` (was `_session_ignore.lua`)
  - `_gt_lobby_kick_idle.lua` (was `_kick_idle.lua`; warn-lead-time hardcoded constant promoted to live read of `gt_lobby_ki_warn_seconds` setting)
  - `_gt_lobby_motd.lua` (was `_motd.lua`; RPC renamed `lt_motd_show` -> `gt_lobby_motd_show`; **NEW:** schema-versioned per VMF_RECIPES § 10)
  - `_gt_lobby_modded_manifest.lua` (was `_modded_manifest.lua`; lobby-data key prefix `ltw_` RETAINED for cross-mod compat with peers still on lt)
  - `_gt_lobby_failed_join_reveal.lua` (was `_failed_join_reveal.lua`; popup action key `lt_open_workshop` -> `gt_lobby_open_workshop`)
  - `_gt_lobby_known_mods.lua` (was `_known_mods.lua`; dropped retired `lobby_tweaker` and `la_prefix_patch` entries; `gt` retagged "C")
- **`general_tweaker.lua`:**
  - `MOD_VERSION = "0.2.60-dev"` (bumped from `0.2.59-dev`).
  - **NEW:** `mod.MOD_VERSION` exposed as a public field on the gt mod table (mirroring lt convention; consumed by bt's `/bug_report` walker and the new gt_lobby manifest broadcaster).
  - **NEW:** `mod.GT_LOBBY_RPC_SCHEMA = 1` declared near MOD_VERSION per VMF_RECIPES § 10. First positional arg of every `mod:network_send` on `gt_lobby_motd_show`; receiver gates on the value and drops with `_dbg_alert` on mismatch.
  - **NEW:** `mod._gt_register_update` exposed so `_gt_lobby_*` modules can plug into gt's central per-frame tick (gt Issue #16's update-consumer registry) instead of using the old `_prev_update = mod.update; mod.update = function(dt) ... end` chain.
  - **NEW:** `mod._gt_dbg` / `mod._gt_dbg_alert` exposed for sibling-file consistency.
  - Six `mod:dofile` calls at the bottom load the new `_gt_lobby_*` modules.
  - **NEW:** `_rt_register("gt_lobby_rpc_schema_present", ...)` regression test verifies `mod.GT_LOBBY_RPC_SCHEMA` is a number >= 1 (matches the ct pattern from v0.7.114-dev).
- **`general_tweaker_data.lua`:** New top-level group `gt_lobby_controls_group` with 12 sub-widgets (slot-reservations / session-ignore / 3x kick-idle / 5x MOTD / 2x manifest), inserted above the universal `enable_debug_logging` toggle.
- **`general_tweaker_localization.lua`:** ~30 new keys for the new group + sub-widget tooltips + the failed-join popup body strings.
- **`itemV2.cfg`:** Updated title (auto-managed via MOD_VERSION suffix) and description (mention "now includes Tweaker: Lobby's host-side controls").

### Chat-command rename
| Old (`lt`) | New (`gt`) |
|---|---|
| `/lt_reserve` / `/lt_unreserve` / `/lt_reservations` | `/gt_lobby_reserve` / `/gt_lobby_unreserve` / `/gt_lobby_reservations` |
| `/lt_ignore` / `/lt_ignore_persist` / `/lt_unignore` / `/lt_ignored` / `/lt_ignore_last` | `/gt_lobby_ignore` / `/gt_lobby_ignore_persist` / `/gt_lobby_unignore` / `/gt_lobby_ignored` / `/gt_lobby_ignore_last` |
| `/lt_idle_whitelist` / `/lt_idle_unwhitelist` / `/lt_idle_status` | `/gt_lobby_idle_whitelist` / `/gt_lobby_idle_unwhitelist` / `/gt_lobby_idle_status` |
| `/lt_motd_test` | `/gt_lobby_motd_test` |
| `/lt_manifest_dump` / `/lt_manifest_probe` | `/gt_lobby_manifest_dump` / `/gt_lobby_manifest_probe` |

### Settings migration note
Settings carry NEW keys (`gt_lobby_*`) under the gt mod-id, NOT under lt's mod-id. Previously-saved lt settings (`%APPDATA%\Fatshark\Vermintide 2\user_settings.config` -> lobby_tweaker entries) are NOT carried over -- users will see defaults on first load and need to re-enable any features they were using. The user_settings.config lt block becomes inert; it can be hand-deleted but is otherwise harmless.

### Archive
- `lobby_tweaker/` moved to `_archive/lobby_tweaker_v0.1.7-dev/` via `Move-Item` (per the global "no recursive-delete" rule + la_prefix_patch precedent).
- `_archive/lobby_tweaker_v0.1.7-dev/_ARCHIVED.md` documents the merge with full feature-inventory mapping table.
- Workshop item `3729845515` left in place on Steam (user can mark private / hidden via Steam web when convenient).
- GitHub release `mods-2026-05-24` still ships `lobby_tweaker.zip` -- left intentionally so existing vt2-mod-updater consumers don't break. Will fall out of next release tag (lt entry removed from `tools/publish-release/publish-release.ps1`).

### Dereferenced
- `CLAUDE.md` -- removed the lobby_tweaker row from the Mod Directory; gt row expanded to list the absorbed features. Mod count: 17 -> 15 active (la_prefix_patch + lobby_tweaker both retired today).
- `MOD_OWNERSHIP.md` -- removed lt row; added the second NOTE at the bottom (alongside the la_prefix_patch one).
- `tools/publish-release/publish-release.ps1` -- removed lt entry from `$mods`.
- `COMMANDS.md` -- gt section expanded with the 14 new `/gt_lobby_*` commands; snapshot-date note updated.

### Build
`VMBLauncher.exe build general_tweaker` -- OK, 4 bundles, 1.72s. NOT deployed, NOT uploaded (per 2026-05-25 EOD doctrine: no Workshop pushes without per-build user approval).

### Closes
- GitHub Issue #43 (Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)) -- resolved by merge.

## 0.2.59-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[gt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- general_tweaker.lua -- removed the load-time `mod:echo("general_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[gt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("general_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.58-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- general_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- general_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.57-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `general_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.57-dev.

## 0.2.56-dev (2026-05-25) — Three-issue audit bundle (Issues #13 / #15 / #16)

### Why
Three open audit issues against `general_tweaker.lua` resolved in a single version bump to avoid churn.

### Issue #13 — `_pause_active` forward-ref bug (one-line fix)
`on_game_state_changed` at line ~688 writes `_pause_active = false`, but the file-local `local _pause_active = false` lived at line ~2153 — well below the closure's compile point. Lua name resolution happens at function compile time, so the assignment was binding to a **global** `_pause_active` instead of the file-local that the pause/time-scale toggle (`gt_pause_toggle` / `gt_time_apply`) reads. After a level transition while paused, the next `/gt_pause` toggle desynced from the engine's actual pause state (off-by-one).

**Fix:** added `local _pause_active` forward declaration alongside the existing `_apply_godmode` / `_ai_handle_toggle_change` forward-decls near the top of the file. Changed the line ~2153 declaration from `local _pause_active = false` to `_pause_active = false` (no `local`) so it reuses the forward-decl slot instead of shadowing it.

### Issue #15 — `on_disabled` leaves global mutations behind
The mod has `is_togglable = true` but `on_disabled` previously only restored the camera offset. Every other mutation (script_data flags, RagdollSettings, BuffTemplates.power_level_unbalance, CareerSettings[*].attributes.base_critical_strike_chance, PlayerUnitMovementSettings.move_speed + closed-upvalue per-unit copy, InventorySettings, DamageUtils.is_in_inn, GameSettingsDevelopment.disable_free_flight, ESC-menu inventory entry) persisted after disable.

**Choice:** documented the limitation rather than authoring a snapshot-on-enable + restore-on-disable refactor across every mutated table. Cheap and honest; full unwind deferred as a larger refactor.

**Fix:**
- `on_disabled` now `mod:echo`s a one-line warning: *"Disable does not fully unwind active mutations. Restart the game for a clean vanilla state."*
- `itemV2.cfg` description's **Compatibility** section gained the same caveat as a bullet so users see it before subscribing / disabling.

### Issue #16 — Layered `mod.update` chain (5 rewraps, no registry)
`general_tweaker.lua` previously rewrapped `mod.update` five separate times using the `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` chain idiom (lines 287/522/2486/2693/3027). No central registry, no inline `-- consumer #N: <feature>` header, no per-consumer error isolation. A single accidental edit `mod.update = function(dt) ... end` without preserving `_orig` would silently drop every earlier consumer — invisible until the dropped feature stopped working.

**Fix:** added a `_update_consumers` registry near the top of the file (after the `mod:echo` load banner). Single `mod.update = function(dt)` body iterates the consumer list and pcalls each consumer. Converted all 5 sites to `_register_update("<feature>", function(dt) ... end)` with these feature names (registration order preserved so dependencies still run in the original order):
1. `tp_camera` — `_tp_reapply_timer` countdown
2. `post_spawn_reapply` — `_post_spawn_reapply_timer` countdown + noclip locomotion heartbeat
3. `infinite_ammo_and_ai_pending` — 1Hz infinite-ammo refresh + AI takeover queue consumers
4. `cutscene_auto_skip` — deferred auto-skip processor
5. `hide_ui` — per-frame HUD mode enforcement

**Bonus:** pcall isolation per-consumer — one consumer error no longer kills the others. Errors surface as `mod:error("[gt:update] consumer '<name>' raised: ...")`.

### Changed
- `scripts/mods/general_tweaker/general_tweaker.lua`:
  - `MOD_VERSION` → `0.2.56-dev`.
  - Added `local _pause_active` forward declaration (Issue #13).
  - Dropped `local` from the line ~2153 `_pause_active = false` assignment (Issue #13).
  - Added `mod:echo` warning to `on_disabled` (Issue #15).
  - Added `_update_consumers` registry + single `mod.update` dispatcher near top of file (Issue #16).
  - Converted 5 `mod.update = function(dt) ...` rewrap sites to `_register_update("<feature>", function(dt) ...)` (Issue #16).
- `itemV2.cfg` — title bumped to v0.2.56-dev; description gained the disable-caveat bullet (Issue #15).

## 0.2.55-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `general_tweaker.lua` — installed `_dbg_alert` helper alongside both existing `_dbg` definitions (the top-of-file one at line ~9 and the second observation-hooks one at line ~773 which lexically shadows the first). Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing six gt regression checks.
- `itemV2.cfg` — bumped to v0.2.55-dev.

### Notes
- 0 of the existing 7 `_dbg(...)` call sites reclassified to `_dbg_alert` — all are state/transition tracking (e.g. `[state] X | ctx | cim=Y`, `[hero_view] on_enter | ctx`, `[transition] X | ctx`). None match the alert signature words.
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/gt_*` / `/dump_*` chat command bodies (user-operational, leave alone) or the unconditional load banner.

## 0.2.54-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). gt previously had `gt_debug_mode` nested in `gt_debug_group` — renamed and un-nested.

### Changed
- `general_tweaker_data.lua` — removed `gt_debug_group` wrapper; `gt_debug_mode` renamed to `enable_debug_logging` at top-level bottom of `options.widgets`.
- `general_tweaker_localization.lua` — removed `gt_debug_group` / `gt_debug_mode` / `gt_debug_mode_tooltip`; added `enable_debug_logging` + `enable_debug_logging_tooltip`.
- `general_tweaker.lua`:
  - `_dbg_on()` now reads `mod:get("enable_debug_logging")` (was `gt_debug_mode`). All existing call sites untouched (they go through the helper).
  - Added file-local `_dbg(fmt, ...)` helper at top of file for new call sites. Output prefix `[gt:dbg]`.
- `itemV2.cfg` — title bumped to v0.2.54-dev.

### Notes
- **Migration**: the saved value of `gt_debug_mode` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

## 0.2.53-dev (2026-05-25) — Stop `_ctx_str` from ERRORing on boot/title state transitions (Network backend has not been set)

### Why
Every session logged 4 ERROR-level entries during boot and title-screen transitions:

```
[Lua] Error: scripts/managers/player/player_manager.lua:559: Network backend has not been set
  [3] @scripts/managers/player/player_manager.lua:559: in function local_player
  [4] @scripts/mods/general_tweaker/general_tweaker.lua:784: in function _ctx_str
  [5] @scripts/mods/general_tweaker/general_tweaker.lua:812: in function <810>
  ...
  event_name = "on_game_state_changed"; _ = "gt"
[MOD][gt][ERROR] (event) on_game_state_changed: scripts/managers/player/player_manager.lua:559: Network backend has not been set
```

Not crash-causing, but log noise that hides real warnings.

Root cause: vanilla `PlayerManager:local_player()` (`player_manager.lua:559`) calls `self.network_manager.peer_id()` and asserts when `network_manager` is nil. `_ctx_str`'s existing guard only checked that the `local_player` method EXISTS on `Managers.player`, not that the network backend had been wired up via `PlayerManager.set_is_server(...)`. During the boot transition through `StateTitleScreen` and the 3 follow-on state-machine churns, the manager exists but `network_manager` is still nil.

### Changed
- `general_tweaker.lua` `_ctx_str` — added a precise pre-check for `Managers.player.network_manager ~= nil` alongside the existing method-presence check before calling `Managers.player:local_player()`. When the backend isn't up yet, `profile`/`career` fall back to `<pre-backend>` so the calling `_dbg("[state] ...")` debug log still gets a complete formatted string. Picked the structural pre-check (Option C in the task brief) over `pcall` because it handles future state additions automatically without depending on the engine-level assert being catchable from Lua, and over the state-name skip (Option B) because that would only fix the 4 documented firings.

### Verification
- Boot the game and watch the log: zero `[MOD][gt][ERROR] (event) on_game_state_changed: ... Network backend has not been set` lines.
- `[MOD][gt][DEBUG] [state] exit StateTitleScreen | mech=? level=? in_keep=false view=? profile=<pre-backend> career=<pre-backend> | cim=...` is the expected pre-backend shape; once the network manager is wired the fields populate normally.

## 0.2.52-dev (2026-05-24) — Force VMF re-handshake before AI Takeover client send (vmf_users bot-churn drop)

### Why
v0.2.50 used the correct API path to resolve the host peer_id but the send still silently dropped. Diffing PC-A's `console-2026-05-24-23.07.16*.log` against PC-B's `console-2026-05-24-23.08.54*.log` revealed the actual mechanic:

```
PC-B 23:10:11.110 [MOD][VMF][INFO] Added 11000010ef3befb to the VMF users list.
PC-B 23:10:11.112 [MOD][VMF][INFO] Removed 11000010ef3befb from the VMF users list.
PC-B 23:10:58.511 [MOD][gt][INFO] [ai_toggle emit] CLIENT->req host=11000010ef3befb want_bot=true
PC-A 23:07:53 +   (no [ai_toggle recv] line ever)
```

VMF's `PlayerManager.remove_player` hook (upstream `vmf/scripts/mods/vmf/modules/core/network.lua:375-404`) has a logic bug: when ANY player owned by peer_id is removed AND that peer still has a human_player on the same peer_id, it removes the WHOLE peer from `_vmf_users`. Host bot churn at mission load fires `remove_player(host_peer, bot_local_id)`; the host's own human player matches the "still has human_player" loop check, so VMF drops the host. Once dropped, `convert_names_to_numbers` returns nil and every `mod:network_send(..., host_peer, ...)` silently no-ops.

### Changed
- `general_tweaker.lua` — client toggle path now calls `get_mod("VMF").ping_vmf_users()` to force a VMF re-handshake before each send (pong round-trip ~50–300 ms on Steam P2P repopulates `_vmf_users[host_peer]`).
- Replaced inline send with `_ai_pending_client_send` queue + `_ai_consume_pending_client_send` drainer wired into the existing mod.update chain. Queue retries the send up to `_AI_CLIENT_SEND_MAX_RETRIES = 3` times with `_AI_CLIENT_SEND_DELAY_RETRY = 0.4 s` between attempts, re-pinging VMF each time. Idempotent — the host's RPC handler no-ops if state already matches.

### Regression tests (run `/gt_regression_test` in game)
- `ai_takeover_vmf_ping_api_available` — pins `get_mod("VMF").ping_vmf_users` as a callable function. If VMF ever renames or removes this entry point, our workaround silently no-ops via the pcall and every client toggle would silently drop again. Both the mod presence and the function shape are asserted.
- `ai_takeover_client_send_queue_wired` — synthetic enqueue with an already-elapsed `next_at`, then drives one mod.update tick and asserts the queue drained. Catches "consumer not wired into mod.update" regressions.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover (`/ai` or checkbox).
3. PC-B chat shows "AI ON (requested from host)." and PC-B log shows `[ai_toggle queue] CLIENT host=<pca> want_bot=true retries=3` followed by `[ai_toggle emit] CLIENT->req ... (attempt 1 of 3)`.
4. PC-A log shows `[ai_toggle recv] HOST<-req sender=<pcb> payload=table` followed by `[ai_toggle] human->bot for <pcb>: ok`.
5. PC-B character is bot-controlled. Toggle off → bot removed, human restored.
6. `/gt_regression_test` reports `PASS: ai_takeover_vmf_ping_api_available` and `PASS: ai_takeover_client_send_queue_wired`.

## 0.2.50-dev (2026-05-24) — Fix wrong server_peer_id path in v0.2.49 AI Takeover fix

### Why
v0.2.49-dev resolved the host peer_id via `Managers.state.network.server_peer_id`. That field doesn't exist on `GameNetworkManager` (which IS `Managers.state.network`, set in `state_ingame.lua:2194`). The lookup always returned nil, so every client toggle refused with "AI toggle: host peer_id not yet known (session still loading?)". PC-B log `console-2026-05-24-15.58.17*.log` lines 7570/7609/7612 — three rejected attempts at 16:00:43–16:00:51, well after the session-join handshake at 15:59:57.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve via the canonical `Managers.mechanism:server_peer_id()` (verified in vanilla at `imgui_career_debug.lua:153` + `versus_mechanism.lua:1845`). Falls back to `Managers.state.network.network_client.server_peer_id` (client) / `.network_server.server_peer_id` (host) for the brief window where mechanism hasn't published yet.
- `VMF_RECIPES.md` § 3 — fixed the (wrong) recipe that v0.2.49 followed. The published recipe now uses `Managers.mechanism:server_peer_id()` with the same fallback chain.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover. PC-B's chat shows "AI ON (requested from host).".
3. PC-B's log has `[ai_toggle emit] CLIENT->req host=<pca-peer> want_bot=true`.
4. PC-A's log has `[ai_toggle recv] HOST<-req sender=<pcb-peer> payload=table` followed by `[ai_toggle] human->bot for <pcb-peer>: ok`.
5. PC-B is now bot-controlled. Toggle off restores the human Player.

## 0.2.49-dev (2026-05-24) — Fix AI Takeover from client (RPC was silently dropped)

### Why
PC-B (client) toggled "AI Takeover" mid-mission. The chat echo printed ("AI ON (requested from host).") but PC-A (host) never received the RPC — the client's character stayed under player control, no bot ever spawned. PC-A's `console-2026-05-24-15.13.52*.log` shows zero `[ai_toggle]` lines; PC-B's `console-2026-05-24-15.09.09*.log` shows the local echo at 15:29:13/25/30 but no corresponding host-side receipt.

Root cause: `_ai_handle_toggle_change` called `mod:network_send(_AI_RPC, "server", ...)`. VMF's `convert_names_to_numbers` accepts exactly four recipient forms — `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` falls through the lookup, is treated as a literal peer_id, fails `_vmf_users[peer_id]`, and returns silently with no error and no wire activity. Documented in `VMF_RECIPES.md` § 3 — same gotcha that burned `cosmetics_tweaker` v0.8.67 → v0.9.0.15.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve the host's real peer_id from `Managers.state.network.server_peer_id` before sending. If the field is nil (transient during host migration / level transition), return `(false, "host peer_id not yet known...")` so the checkbox auto-reverts via the existing failure-revert path.
- Added emit/recv diagnostic `mod:info("[ai_toggle emit] CLIENT->req ...")` at the client send site and `mod:info("[ai_toggle recv] HOST<-req ...")` at the top of the `network_register` handler. Per the VMF_RECIPES detection recipe — if recv ever stops firing again, the asymmetry is now visible in a single grep.

### Verification
1. Host VT2 on PC-A with General Tweaker v0.2.49-dev. Join from PC-B as client.
2. Start any adventure / weave / deus mission.
3. On PC-B, toggle "AI Takeover" in Mod Settings → General Tweaker (or `/ai`).
4. PC-B chat shows "AI ON (requested from host).".
5. PC-A's console log gets a fresh `[ai_toggle recv] HOST<-req sender=<pc-b peer> payload=table` line followed by `[ai_toggle] human->bot for <pc-b peer>: ok`.
6. PC-B's player is now controlled by a bot. Toggle off → bot is removed and the human Player is re-added.

## 0.2.48-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.2.47 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 2: the v0.2.47 `NetworkLookup.pickup_names` rawget conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test.

### Added
- Source-pattern marker constant `CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = "gt-pickup-lookup-rawget-hardened"` near the top of `general_tweaker.lua`.
- `_rt_register("gt_pickup_lookup_uses_rawget", ...)` at the bottom of `general_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value.
  2. `rawget(NetworkLookup.pickup_names, <known-bad-key>)` returns `nil` without raising.

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/gt_regression_test` in chat. Expect `PASS: gt_pickup_lookup_uses_rawget` alongside the pre-existing checks.

## 0.2.47-dev (2026-05-23) — Convert 1 NetworkLookup lookup to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged the `/spawn`-pickup site as latent: the key currently comes from the curated `_gt_is_pickup_names` list (all vanilla-registered), so it never misses today, but is a latent bomb if anything changes the surrounding data flow.

### Changed
- `general_tweaker.lua` (`_gt_is_spawn`) — converted `NetworkLookup.pickup_names[pickup_name]` to `rawget(NetworkLookup.pickup_names, pickup_name)` with a guard that echoes "Unknown pickup name" and returns instead of crashing the strict-lookup path.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — site no longer appears in `strict-table-lookup` findings.

## 0.2.46-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `general_tweaker.lua` — renamed `regression_test` → `gt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/gt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.2.32-alpha (2026-05-19)

### Fixed: Command-name collisions with Janoti's "Hacks" mod

The v0.2.26 → v0.2.31 port copied 11 command names verbatim from Hacks (Helpers 2). VMF only allows one global registration per command name; the first mod to load wins the slot and the other's registration is silently dropped with an error in console. Gt was loading before Hacks (alphabetical), so Hacks lost `/pause`, `/win`, `/fail`, `/restart`, `/kill_bots`, `/die`, `/ult_reset`, `/infinite_stamina`, `/giga_power`, `/inn_dmg`, and `/unkillable` entirely. Renaming gt's claims here releases all 11 slots back to Hacks.

| Old gt name | New gt name |
|---|---|
| `/pause` | `/gt_pause` |
| `/win` | `/gt_win` |
| `/fail` | `/gt_fail` |
| `/restart` | `/gt_restart` |
| `/kill_bots` | `/gt_killbots` |
| `/die` | `/gt_die` |
| `/ult_reset` | `/gt_ultreset` |
| `/infinite_stamina` | `/gt_stamina` |
| `/giga_power` | `/gt_gigapower` |
| `/inn_dmg` | `/gt_inndmg` |
| `/unkillable` | `/gt_unkillable` |

Hotkey widgets unchanged (they bind to `mod.gt_*` functions which were always gt-namespaced). Settings UI labels unchanged. Tooltips updated to reference the new command names.

`/win` had been a gt command since before the port too (renamed alongside the others — same collision).

## 0.2.31-alpha (2026-05-19)

### Changed: Disable Enemy Spawns now also flips the `script_data.ai_*` flag set
### Added: Engine-error nil-guards from Janoti's "Hacks" (Group F — final port batch)

**Broadened `/no_enemies` toggle:** the two `ConflictDirector` hooks still catch every spawn call, but the toggle now ALSO flips the same `script_data.ai_*_disabled` flag set Hacks uses (mini_patrol, critter, horde, roaming, boss, rush_intervention, specials, pacing, outside_navmesh_intervention). The script_data path aborts spawns earlier in the pacing/intervention pipelines so the spawner doesn't even queue work. Per `feedback_redundant_safeguards_ok` redundancy is welcome here — cost is nine boolean writes per toggle, missed-path failure (an enemy slipping through) is silent. `_apply_script_data_no_enemies` is forward-declared at the top of the file because `on_setting_changed` (which lives above the no_enemies section) needs to call it.

**Engine-error nil-guards (passive):** two `mod:hook` wrappers that no-op the call when the target unit is dead/nil, copied from Hacks:

- `VolumetricsFlowCallbacks.unregister_fog_volume(params, ...)` — bails if `params.unit` is nil or `not Unit.alive(params.unit)`. Suppresses the red `[Engine Error]` spam that occasionally shows up when a fog volume's owner unit was already collected.
- `Unit.get_data(unit, ...)` — bails if `unit` is nil. Suppresses error spam from systems that hand stale unit handles back to the engine during cleanup.

Both guards are pure pre-checks — the original function runs unchanged when inputs are valid.

This concludes the Janoti "Hacks" feature port (Groups A–F across v0.2.26 → v0.2.31). All 17 missing features ported plus 2 expansions to existing gt features.

## 0.2.30-alpha (2026-05-19)

### Added: Player State Toggles group — port from Janoti's "Hacks" (Group E)

Three small toggles kept distinct from gt's existing `god` umbrella:

- **`/inn_dmg`** — host-only flip of `DamageUtils.is_in_inn`. When the inn flag is off, the keep behaves like a mission (damage taken normally). Useful for sparring with bots in the keep without flipping all of godmode.
- **`/cloak`** + hotkey — visual invisibility (model hidden + invisible to AI). Uses `set_invisible(true, false, "gt_cloak")` with its own reason namespace so toggling cloak doesn't clobber godmode's invisibility (which uses `"gt_godmode"`) and vice versa.
- **`/unkillable`** — flips `script_data.player_unkillable`. You take damage normally, you can be grabbed by disablers, but the engine refuses to drop you below 1 HP. Different intent from `god` — this is "I want to feel hits while testing".

Only `cloak` gets a hotkey widget; the other two are command-only since they're niche toggles.

## 0.2.29-alpha (2026-05-19)

### Added: Buffs & Stats group — port from Janoti's "Hacks" (Group D)

New "Buffs & Stats" settings group + three chat commands + two sliders:

- **`/infinite_ammo`** — toggle infinite ammo + zero overheat. Applies the vanilla `twitch_no_overcharge_no_ammo_reloads` buff to the local player; if you're the host, also pushes it to every other player. Periodic re-apply every 1 second via the shared `mod.update` chain keeps the buff refreshed if anything tries to strip it.
- **`/infinite_stamina`** — toggle infinite stamina. Hooks `GenericStatusExtension.add_fatigue_points` and short-circuits the call when the flag is on, so stamina-cost actions (block, push, dodge-cost) never deplete the bar.
- **`/giga_power`** — multiply the Enhanced Power talent buff by 1000x. Snapshots the original `BuffTemplates.power_level_unbalance.buffs[1].multiplier` on first activation and restores it on toggle-off. Requires re-equipping the talent for the buff to refresh.
- **Base Crit Chance slider (0–100%)** — rewrites the current career's `CareerSettings[name].attributes.base_critical_strike_chance`. Auto-snaps back to that career's vanilla value when you switch careers (hooks `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed`). Per-session — game restart restores defaults.
- **Movement Speed slider (0–30 m/s)** — rewrites `PlayerUnitMovementSettings.move_speed` plus every per-unit override already snapshotted by the engine (reached via `debug.getupvalue(unregister_unit, 1)` since the per-unit table is a closure local). Per-session.

The infinite-stamina hook is always-registered (toggling on/off flips a flag inside the closure) to avoid VMF's duplicate-registration error.

## 0.2.28-alpha (2026-05-19)

### Added: Ult Controls group — port from Janoti's "Hacks" (Group C)

New "Ult" settings group with three features, all driven through `CareerExtension`:

- **`/ult_reset`** + hotkey — one-shot reset. Walks `_num_abilities` and calls `:reduce_activated_ability_cooldown_percent(i, 1)` on each, dropping every charge to 0 cooldown. Same primitive ThePageMan's "No Ult Cooldown" mod uses.
- **Cap Player Ult Cooldown** (toggle + 0–120s slider) — clamps every player-controlled career ability's remaining cooldown to at most the configured value, every `CareerExtension.update` tick. Effectively a configurable "short ult" without burning a talent slot.
- **Cap Bot Ult Cooldown** (toggle + 0–120s slider) — same idea but for AI-controlled units. Useful in solo-with-bots to see bots ult more aggressively.

Both caps share `mod._gt_clamp_cooldowns` which walks the ability's `cooldowns` array from the decaying-charge index downward, trims each entry, then re-runs the engine's `cooldown_paused` / `set_activated_ability_cooldown_unpaused` housekeeping so the ability HUD overlay stays in sync. This is the iteration pattern the engine expects — replicating it any other way desyncs the UI.

## 0.2.27-alpha (2026-05-19)

### Added: Time & Pause group — port from Janoti's "Hacks" (Group B)

New "Time & Pause" settings group with five widgets + three chat commands. Both features use the same engine primitive: `Managers.state.debug:set_time_scale(index)` where `index` selects an entry in `debug_manager.lua`'s `time_scale_list` (24 multipliers, index 13 = 1.0x).

- **Time Scale slider (1–24)** — change live; the new value is applied immediately and re-applied on every `StateIngame` entry (vanilla wipes the engine time scale on level transitions).
- **`/time_faster` / `/time_slower`** + bindable hotkeys — step the slider up/down by 1.
- **`/pause`** + hotkey + Pause Speed slider (1–24, default 1) — host-only toggle between the configured pause speed and normal. VT2 has no true freeze primitive; `set_time_scale(1)` is the closest thing (UI still updates). Clients see the change since time scale is server-driven.

The pause feature and the time slider share the same engine setter; if both are touched in the same session, the last write wins. We keep them as separate widgets matching Hacks's UX. Setting the slider while paused updates the post-unpause target but doesn't override the active pause speed.

## 0.2.26-alpha (2026-05-19)

### Added: Level Control group — port from Janoti's "Hacks" (Group A)

New "Level Control" settings group + six chat commands + six bindable hotkeys, sourced from the corresponding features in Janoti's [Hacks](https://steamcommunity.com/sharedfiles/filedetails/?id=3266071368) (uploaded as "Helpers 2"):

- **`/fail`** + hotkey — fail the current mission (`Managers.state.game_mode:fail_level()`).
- **`/restart`** + hotkey — retry the current mission (`Managers.state.game_mode:retry_level()`).
- **`/kill_bots`** + hotkey — kill every bot in the party. On EAC-secure realm only allowed pre-round (vanilla anti-cheat would flag mid-round bot kills); unrestricted on modded realm.
- **`/die`** + hotkey — kill your local character (`death_system:kill_unit`).
- **`/fix_sound`** + hotkey — stop the looping vortex SFX that gets stuck after restarting mid-storm. Fires `sfx_player_in_vortex_false` on the local first-person extension, same trick Craven's script uses.
- **`/win`** also gets a hotkey (the command itself already existed in v0.2.25).

All five level-flow commands no-op in the keep with a friendly echo so a mis-press while sorting loadout doesn't yank you out of the inn state machine. The `mod.gt_*` functions are exposed as named members (not just locals) so VMF's `keybind_type = "function_call"` resolver can find them via the `function_name` string.

## 0.2.24-alpha (2026-05-17)

### Added: Skip Intro Splash Screens toggle

New "Startup" group with a single checkbox: **Skip Intro Splash Screens**. Same end result as bIbIbI's [Skip Intro mod](https://steamcommunity.com/sharedfiles/filedetails/?id=1395453301) — skips the Fatshark/engine logo splash sequence at game launch.

Implementation uses the canonical vanilla bypass: `StateSplashScreen.on_enter` (state_splash_screen.lua:92-110) checks a set of `Development.parameter` flags including `"skip_splash"` — if any are set, `self._skip_splash = true` and the splash sequence is bypassed. Same mechanism as the `-skip-splash` command-line argument.

`Development.set_parameter()` is a no-op in release builds, so we write directly to `Development._hardcoded_dev_params.skip_splash` (same trick the third-person camera section uses for `third_person_mode`). Done at mod load time, which runs before `StateSplashScreen.on_enter`, so the flag is in place when the check fires.

**Note:** changing the setting mid-session shows no immediate change — the splash for the current boot has already run. The flag is still updated so the next launch reflects the new setting.

## 0.2.23-alpha (2026-05-17)

### Added: AI Takeover VMF widget

The `/ai` command from v0.2.22 is now also exposed as a checkbox in the Gameplay group ("AI Takeover (bot controls your character)"). Chat command and checkbox stay in lockstep — the command just flips the setting, and `on_setting_changed` runs the same RPC pipeline. Auto-resets to off on game state change (level transition / leaving a mission) so the checkbox never persists a stale "on" across runs that didn't actually swap.

Same v1 scope as v0.2.22: client-only, refused on host self-toggle, refused in versus and the keep.

## 0.2.22-alpha (2026-05-17)

### Added: AI Toggle (`/ai`) — hand off control to a bot mid-mission

New chat command `/ai` lets a **client** hand their character over to bot AI (and toggle back). Useful for multiplayer testing where the mod author hosts on one machine and wants the second machine's player to behave as a bot, and as a general "stepping away" utility for clients who need to leave mid-run.

VT2 has no hot-swap path between human and bot units — they use different `go_type`s with incompatible extension stacks. So toggling means despawn-human + add-bot (and the reverse). Both halves of the dance exist in vanilla (see `GameModeBase._add_bot_to_party` / `_remove_bot_instant` and `GameModeAdventure.player_entered_game_session`); we compose them and wire them to a player-driven trigger.

Server-driven by necessity — `ProfileSynchronizer` and `PartyManager` mutation APIs all assert `is_server`. Client sends a VMF network request (`gt_ai_toggle_request`) and the host runs the swap. Host saves the original peer/profile metadata; toggling again recreates the human Player object via `add_remote_player`, re-claims the slot via `assign_peer_to_party`, and re-assigns the profile via `assign_full_profile(..., is_bot=false)`. Spawning system picks them up next tick.

**v1 scope:**
- Client (remote peer) self-toggle: supported.
- Host self-toggle: refused with a message — destroying the host's local Player object mid-mission would tear down camera/HUD/input bindings that aren't trivial to recreate.
- Versus: refused (heroes have no bot AI in versus).
- Keep / inn: refused (no spawning system running).

**Known rough edges (acceptable for v1, will iterate based on testing):**
- Inventory / current ammo / temporary buffs don't persist across the swap — the bot inherits the profile's default loadout from the spawning system.
- Client-side camera transition when their unit despawns is whatever vanilla does for "your player_unit just got removed" (likely spectator-style); untested.

## 0.2.21-alpha (2026-05-16)

### Added: Disable Enemy Spawns toggle

New checkbox in the Gameplay group + `/no_enemies` chat command. When on, every enemy spawn — hordes, specials, bosses, patrols, and pre-placed level-load enemies — is refused. Every enemy in VT2 funnels through `ConflictDirector`'s two public entry points (`spawn_queued_unit` for the pacing-system queue, `spawn_unit_immediate` for terror events / scripted triggers); hooks on both refuse the call when the setting is on.

Existing enemies are NOT despawned — the toggle affects future spawns only. Combine with `/god` to walk past anything already alive when toggling mid-mission.

Tooltip + Workshop description updated. Chat-command bullet line in the Workshop description extended with `/no_enemies`.

## 0.2.20-alpha (2026-05-15)

### Changed: Godmode now also makes the player invisible to enemy AI

Uses the engine's own canonical signal — `GenericStatusExtension:set_invisible(true, false, "gt_godmode")` — which AI perception explicitly skips (`perception_utils.lua:381`). Same primitive Shade's Shadowfall ult uses, just with a `reason = "gt_godmode"` namespace so it doesn't clobber other invisibility sources.

`skip_third_person=false` so the 3P body fades as a visual cue that godmode is on. First-person view (1P weapon arms) is unaffected since those are a separate unit.

Belt-and-suspenders re-apply on each `GenericStatusExtension.extensions_ready` — `self.invisible` is reset to `{}` on extension init, so a level transition while godmode is on would otherwise leave the new player unit visible to AI.

Tooltip + Workshop description updated. Forward-declared `_apply_godmode` at the top of the file so `on_setting_changed` (defined before the godmode section) can bind to the local instead of a nil global — see `feedback_lua_forward_reference.md`.

## 0.2.19-alpha (2026-05-15)

### Changed: Godmode now also blocks disablers

The two `DamageUtils` hooks (add_damage_network, add_damage_network_player) stop hp damage but disablers (gutter runner / assassin pounce, packmaster hook, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the damage pipeline entirely — they push the character state machine directly into the disabler state.

Hook `GenericStateMachine.change_state` (the chokepoint every `csm:change_state(state_name, params)` call funnels through) and drop the transition when (a) godmode is on AND (b) the unit is the local player AND (c) the requested state is one of: `pounced_down`, `grabbed_by_pack_master`, `grabbed_by_chaos_spawn`, `grabbed_by_corruptor`, `grabbed_by_tentacle`, `in_hanging_cage`. Normal gameplay states (`stunned`, `ledge_hanging`, `overpowered`, `knocked_down`, `dead`) are NOT touched.

Godmode tooltip + Workshop description updated to advertise the broader behaviour.

## 0.2.18-alpha (2026-05-14)

### Fixed: Free camera now actually freezes the player

The free camera (`/freecam`) was supposed to detach the camera while leaving the character in place — but WASD was still moving the character alongside the camera. The engine's `_enter_free_flight` calls `input_manager:block_device_except_service("FreeFlight", "keyboard", ...)` which is meant to stop the Player input service from receiving keyboard input, but empirically that block doesn't reliably stop the character state machine from reading movement.

Belt-and-suspenders fix: while freecam is active, also call `loco:set_disabled(true)` on the local player's locomotion extension. That yanks the unit out of the locomotion update list entirely — character state machine still ticks (animation pose, etc.) but no movement can be applied regardless of what the Player input service produces. On freecam exit (toggle off, F8 press, or level transition via the `_exit_free_flight` hook), `loco:set_disabled(false)` re-enables the character cleanly. `pcall`-wrapped to survive engine API drift.

## 0.2.17-dev — first public Workshop release (2026-05-14)

### Changed: Workshop visibility flipped private → public

gt was uploaded as `friends_only` from its inception. After the noclip feature landed and verified working in 0.2.17-dev, the user flagged the mod ready for a public release. `itemV2.cfg`:

- `visibility`: `"friends_only"` → `"public"`
- `title`: `"Tweaker: General (WIP)"` → `"Tweaker: General"`
- `description`: replaced the one-liner with a sectioned feature description matching ct/cim/the rest of the Tweaker series — Third-Person Camera, Noclip, Keep Menus in Missions, Gameplay toggles, Chat commands, Compatibility — plus the canonical BMC block.
- `preview.jpg`: replaced with the Tweaker General artwork (1024×1024, JPG q=85, 215 KB).

`upload_gt.ps1`'s visibility guard updated `friends_only` → `public` and `--allow-public` added so the launcher's safety gate is satisfied. Upload pushed via `vmblauncher upload general_tweaker --allow-public`; verified live via `ISteamRemoteStorage/GetPublishedFileDetails`: `visibility=0`, `file_size=1346271` (matches `bundleV2/` byte-for-byte).

## 0.2.17-dev (2026-05-14)

### Fixed: Noclip chat command now applies immediately

`/noclip` previously relied on `mod.on_setting_changed` firing after `mod:set("noclip_enabled", ...)` to actually flip the locomotion state. That worked from the VMF settings menu but was unreliable when toggled from the chat command. Added an explicit `_apply_noclip(new_val)` call after the `mod:set`, mirroring the same belt-and-suspenders pattern `/tp` already uses.

Also added `mod:info` diagnostic lines in `_apply_noclip` — every toggle now logs `[noclip] ON — loco.state now '...'` or `[noclip] no locomotion extension yet ...` so post-mortem debugging of "didn't work" reports is one log-grep instead of a re-build cycle.

## 0.2.16-dev (2026-05-14)

### Added: Noclip (player flies through walls)

New "Noclip" toggle in the Gameplay group plus a `/noclip` chat command. Unlike the existing detached freecam, noclip moves the **player body** through walls — WASD flies in look direction, Space/Ctrl for up/down, Left Shift for a speed boost. Two new numeric sliders (`noclip_speed` default 15 m/s, `noclip_boost_multiplier` default 3.0x) tune the base and boost speed.

Built on the engine's `script_driven_no_mover` locomotion state (used by chaos-spawn-grab and tentacle-grab), which teleports the unit by `velocity_wanted * dt` each tick without touching the mover — so static geometry, props, and enemies are all bypassed. The dead-simple `Mover.set_collision_disabled` / `set_mover_disable_reason("noclip", true)` paths don't work for players: the locomotion templates and `PlayerUnitLocomotionExtension` call `Mover.flying_frames(mover)` and `Mover.move(mover, ...)` without nil-guarding the mover, so nuking it fatals immediately. The no-mover *state* path bypasses both calls without touching the mover handle.

Three hooks make it stick:

1. **`PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`** — when noclip is on for the local player, ignore whatever velocity the character state machine wrote (walking writes ground-plane velocity, falling writes gravity) and compute our own from W/A/S/D + Space/Ctrl projected through the first-person camera rotation.
2. **`mod.update` heartbeat** — re-asserts `loco.state = "script_driven_no_mover"` each tick. Basic states (standing/walking/jumping/falling) don't touch `locomotion.state`, but transitions into ledge-hang / ladder / knockdown call `enable_script_driven_movement()` which would hand us back to the wall-respecting mover update.
3. **`PlayerUnitLocomotionExtension.extensions_ready`** — re-arms noclip on each player spawn (mission entry, respawn) if the persisted VMF setting is on. Without this, the setting stays "on" while the actual locomotion state is whatever the engine initialised it to (usually `script_driven`).

On toggle-off, the mover is snapped to the player's current position before handing control back, otherwise the mover stays at the entry point and the next `Mover.move()` yanks the player back there.

Caveats baked into the tooltip: toggling off mid-air drops you, and special states (ledge-hang/ladder/career-ability/knockdown) may briefly fight the mode.

## 0.2.10-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`gt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`general_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3713619122` and internal mod ID `"gt"` preserved — existing user settings are unaffected.

`itemV2.cfg` set to `visibility = "private"` (overriding the prior local `upload/item.cfg` which had `"public"` — never re-asserted on Workshop because no upload was performed during the migration).
