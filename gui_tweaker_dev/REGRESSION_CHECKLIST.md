# Regression Checklist — gui_tweaker_dev

## Equipment DEFAULT transaction (#1002)

- [ ] In Mod Tweaker, open **Equipment**, press **DEFAULT**, confirm, then press
  **APPLY**. The game remains responsive and does not exhaust the Lua heap.
- [ ] The log contains one `[gut:560]` commit for each non-empty Equipment owner
  and one `[wt:1002]` line with `availability_applies=1 action_applies=1`.
  Cosmetics/CIM/CWV each emit at most one corresponding `:1002` line.
- [ ] Reopen Equipment and confirm every current setting matches its declared
  first-use default. Restart once and confirm those values persisted.
- [ ] Change one Weapon Availability master without changing its advanced
  children; Apply must still cascade. DEFAULT must restore mixed per-weapon
  defaults rather than flattening them to the master's boolean.
- [ ] `qa/check_lua_unit_tests.ps1` passes the multi-owner transaction and both
  WT master-reconciliation cases.

## Detached bot loadouts (#954)

- **Status:** source-only regression candidate; do not apply a tester lifecycle
  label until this exact candidate is committed, built, deployed, and identified
  by banner, Workshop manifest, and archive hash in a new live-test card.
- The candidate reconciles the detached persisted snapshot at the shared
  `get_bot_loadout` read boundary. This covers a backend cache built before the
  post-refresh hook became eligible and same-table drift after a successful
  refresh. The wrapper preserves every native getter argument.
- Wide, deep, cyclic, or over-cap stores must fail open to the native cache,
  leave both persisted and runtime owners unchanged, and retry recoverable
  persistence failures on the next read.
- A mixed store containing one valid legacy designation plus one corrupt
  designation must commit neither row until the corrupt value is removed.
- [ ] Prepare a Warrior Priest saved row with visibly distinct melee and ranged
  weapons, assign that row to the bot, then switch to another player loadout.
- [ ] Change the player's weapons. Refresh/respawn the Warrior Priest bot and
  confirm its designated weapons remain unchanged.
- [ ] Restart the game and repeat the player edit and bot refresh; both the bot
  snapshot and player row must retain their independent values.
- [ ] Run `/gut_regression_test` and require
  `issue954_bot_loadout_snapshot` to pass.

If this candidate fails, use exactly one evidence-selected fallback:

1. If the persisted snapshot is absent after restart, move the migration to the
   store-load boundary and record the serialized `bot_loadout` readback.
2. If a later engine writer changes `_bot_loadouts`, identify that writer from
   the bounded reconcile reason and compose it into the singleton cache owner.
3. If explicit bot editing is required, add a bot-only edit transaction that
   writes `bot_loadout`; never route it through a player saved row.

## Hidden career passives (#153)

- [ ] Enable **Surface Hidden Career Passives** and open Witch Hunter Captain's Talents screen.
- [ ] **Power of Sigmar** and **Sigmar's Charm** render under **Perks**, never inside the Witch Hunt passive description.
- [ ] The six-row/console layout shows two independent rows; the compact three-slot PC layout shows one combined row whose tooltip contains both exact bonuses.
- [ ] Disable the option and reopen the screen; only the two vanilla WHC perks remain.
- [ ] Switch careers; no uncatalogued, duplicated, selectable, or gameplay-changing perk appears.
- [ ] `/gut_regression_test` passes `issue153_hidden_passives_display_only`; offline `test_gut_hidden_passives.lua` passes.

## Mutually exclusive controls (#446)

- [ ] A presented exclusive group renders as one collapsible with radio bubbles, not separate ON/OFF steppers.
- [ ] `None [Default]` clears every real member; selecting A/B moves the filled bubble immediately and stages exactly one true member.
- [ ] APPLY persists the selection across restart; stock VMF options remain ordinary compatible checkboxes.
- [ ] `/gut_regression_test` passes `mod_tweaker_exclusive_group_api`.

## Mod Tweaker DX12 fence diagnostics (#630)

- [ ] Open Mod Tweaker in the keep, select Weapons, change window focus once, return, and close the menu normally.
- [ ] `[gut:630]` reports `presentation=standalone`, the `gut_equipment` tab edge plus `equipment_state=...weapons:expanded-stored...`, `focus=false`/`focus=true` edges, and an exit summary with `balance=0`.
- [ ] The issue probe emits no per-frame line; its process-wide output never exceeds 48 records.
- [ ] If the native fence timeout recurs, retain the complete console log and matching dump. A final `first_draw_end`/balanced close edge versus a missing `after_draw` separates an engine-frame stall from an unmatched Mod Tweaker pass.
- [ ] Repeat the focus transition in a vanilla Hero/Inventory view as a control; do not add a renderer/focus workaround unless the two signatures establish the boundary.
- [ ] `/gut_regression_test` passes `issue630_dx12_fence_probe`; offline `test_gut_dx12_fence630.lua` passes.

## Mod Tweaker module extraction / file-size gate

- [ ] Standalone and HeroView Mod Tweaker open, draw, accept mouse/controller input, edit numeric values, search, switch profiles, Apply, and Default exactly as before.
- [ ] Dialogue rows in dev still recycle, play/pause, report progress, and stop on view cleanup; stable contains no Dialogue dependency.
- [ ] Each owner loads and installs its interaction/contracts module once; no extracted module owns an engine hook, command, or lifecycle callback.
- [ ] `qa/check_file_sizes.ps1` reports no hard-limit error for the six GUI owner files; do not update `qa/baselines/file_sizes.json` for this split.
- [ ] `test_gut_module_extraction.lua`, the complete offline Lua suite, Quick QA, and both GUI mod-lint runs pass.

## Character Dialogue media controls (#605)

- [ ] An open character section closes on its next mouse/controller activation;
      its virtual line rows disappear and owned preview audio stops.
- [ ] Per-line state cycles Default -> Enabled -> Disabled -> Default without
      skipping the false/Disabled state.
- [ ] Every visible dialogue row has one fixed media button, not separate Play and Pause buttons.
- [ ] Stopped/paused displays a play triangle; active playback displays two pause bars.
- [ ] The active-row progress track advances, freezes while paused, resumes, and resets on replacement/cleanup.
- [ ] Wwise preview state is polled once per frame, never once per visible row; virtual row count remains bounded.
- [ ] Mouse/controller focus remains on the same media button across play/pause changes.
- [ ] `/cd_regression_test`, `/gut_regression_test`, and offline `test_character_dialogue.lua` pass.

## Mission Select custom-career statistics (#649)

- [ ] With a custom career whose `completed_career_levels` definition is absent, open Custom Game > Helmgart; the mission list opens without a StatisticsDatabase crash.
- [ ] Fully defined profiles delegate to the exact vanilla method with their original table identity.
- [ ] The compatibility path shallow-copies only the profile container, omits only careers missing an exact level/difficulty definition, and never mutates the live profile or its career rows.
- [ ] StatisticsDatabase is not hooked or protected globally; errors for defined paths still propagate.
- [ ] `/verify_gut_mission_completion` reports `guard=true` and `PASS`; `/gut_regression_test` passes `issue649_mission_completion_definition_guard`; offline `test_gut_mission_completion_policy.lua` passes.

## Foot Knight secondary melee compatibility (#619)

- [ ] With Career Tweaker's secondary-melee toggle enabled, GUT restores an `es_knight` saved loadout containing melee weapons in both `slot_melee` and `slot_ranged`.
- [ ] Disabling the Career Tweaker toggle immediately causes a later restore of that row to reject the secondary melee without deleting or rewriting the saved identity.
- [ ] Slayer and Grail Knight secondary-melee loadouts still restore; careers whose live slot map lacks the capability still reject melee in `slot_ranged`.
- [ ] Vanilla, WT, and CWV melee items use the same live `slot_type`/`can_wield` decision with no key allowlist or cloned backend identity.
- [ ] `/gut_regression_test` passes `issue619_saved_loadout_live_slot_capability`; offline `test_gut_loadout_slot_policy.lua` passes hot enable/disable and negative-path coverage.

## Career-themed HUD holders (#442)

- [ ] Startup emits exactly two `[gut:442]` lines: 20 careers, two dedicated holders, eighteen fallbacks, zero malformed entries.
- [ ] Dedicated careers are exactly `dr_engineer` and `wh_priest`; their texture ids remain distinct.
- [ ] `/gut_regression_test` passes `issue442_career_hud_holder_capability`; offline holder-policy tests pass.
- [ ] Before implementation, every new atlas asset satisfies the size, transparency, clear-zone, resolution, gamepad, and package-lifetime contract in `CAREER_HUD_HOLDER_RESEARCH_442.md`.

## Adventure disconnect scoreboard retention (#437)

- [ ] Host an Adventure mission; a client earns nonzero scoreboard statistics, disconnects, rejoins, and keeps the pre-disconnect totals at mission end.
- [ ] Post-rejoin progress adds normally and no statistic is doubled.
- [ ] `[gut:437]` reports one bounded capture and restore for the same `stats_id`; output never exceeds 16 records.
- [ ] Disabling the option restores vanilla behavior, and changing/ending the mission clears retained data.
- [ ] Chaos Wastes, Weaves, Versus, clients, backend/progression statistics, and network traffic are untouched.
- [ ] `/gut_regression_test` passes `issue437_adventure_scoreboard_retention`; offline scoreboard tests pass.

## Scoreboard capability inventory (#272)

- [ ] On load, `[gut:272]` reports 11 topics, 11 grouped references, and zero malformed, duplicate, or unresolved entries.
- [ ] Hot-join classification reports ten covered topics and only `damage_dealt_bosses` as a gap.
- [ ] In an Adventure mission, the automatic probe or `/gut_scoreboard_probe` reports a ready snapshot with numeric scores and no malformed player rows.
- [ ] The loaded-state flag for external Tab Scoreboard matches the active mod list; GUT neither requires nor mutates that mod.
- [ ] Probe output remains capped at four records per process and never logs per frame.
- [ ] `/gut_regression_test` passes `issue272_scoreboard_inventory_diagnostics`; offline `test_gut_scoreboard_diagnostics.lua` passes.

## On Yer Feet revive attribution (#438)

- [ ] Mercenary with `markus_mercenary_activated_ability_revive` revives one downed bot by Morale Boost and gains exactly one scoreboard revive.
- [ ] An ordinary manual revive still gains exactly one, not two.
- [ ] `[gut:438] credited` emits once for the repaired ability revive and remains capped at 16 records per process.
- [ ] `/gut_regression_test` passes `issue438_on_yer_feet_revive_credit`.

Subset of the monorepo [REGRESSION_CHECKLIST.md](../docs/REGRESSION_CHECKLIST.md) for Tweaker: GUI dev.

Last updated: 2026-07-17.

## In-mission mission-vote client popup (#700)

- [ ] Host and client both load GUT dev v0.2.291-dev, enter an Adventure mission, and the host selects another mission from the in-mission map.
- [ ] The client sees the vanilla accept/decline HUD vote, accepts, and the selected mission starts without waiting for the 30-second timeout.
- [ ] The HUD title is localized player-facing text; it must not display the internal `game_settings_vote` key or any underscore-delimited identifier.
- [ ] Keep mission selection remains vanilla; unrelated kick/continue votes retain their original classification.
- [ ] Both peers log one `[gut:700] mission vote promoted to localized IngameVotingUI` line for the active vote.
- [ ] `/verify_gut_mission_vote` reports `hooks=true policy=true ... result=PASS`; `/gut_regression_test` passes `issue700_mission_vote_client_popup`; offline `test_gut_mission_vote_policy.lua` passes.

## Cosmetics-only in-mission customization mount (#89)

- [ ] With Cosmetics installed and CIM absent, the Adventure in-mission gear icon is enabled and opens `HeroWindowItemCustomization`.
- [ ] GUT's `_create_item_preview_widget_definition` substitute contains no keep-only `level_name`/`object_sets`, and `_register_object_sets` seeds an empty object-set ledger.
- [ ] The keep path delegates unchanged; CIM/CIM-dev paths delegate to CIM's existing mount owner.
- [ ] Cosmetics' `_create_preview_widget` mission hook repoints the level-free preview to the resident store-preview shading environment, so the weapon is rendered rather than black/blank.
- [ ] `/gut_regression_test` passes `issue89_cosmetics_only_customize_mount`; offline `test_gut_cosmetics_mission_mount.lua` passes.
- Lifecycle: close-ready as the #84 implementation superseded #89's proposed ownership location without reducing the requested capability.

## Localization lifecycle sync (#345)

- [ ] Third-Person Camera (#209) and Allow crafting bench in mission (#80) display `[verify-fix]` with their issue number.
- [ ] Toggle Skip Cutscenes (#126) and Use non-modded loadouts (#287) do not display `[diag]` unless diagnostics are armed again on GitHub.
- [ ] Enable In-Mission Inventory Access names open #87 only; closed crash #193 and its crash tag are absent.
- [ ] `pwsh -NoProfile -File qa/check_loc_tags.ps1` reports no player-facing lifecycle metadata.

## Original temporary-health talent names (#352)

- [ ] The option is off by default; all careers retain the game's current shared THP names until enabled.
- [ ] With the option enabled, each hero's four careers show their distinct original names on the level-five talent row.
- [ ] Talent titles are readable names such as `Drillmaster`, never internal IDs with underscores inside `<...>`.
- [ ] Existing talent selections, descriptions, icons, buffs, and mechanics do not change when toggling either direction.
- [ ] Disabling the option restores the exact shared display keys captured at load; no career-specific name leaks onto another career or a modded talent.
- [ ] A language/localizer re-init does not drop the restored names; all 60 mod-owned backend localization keys are re-supplied.
- [ ] `/gut_regression_test` passes `issue352_original_thp_names_exact_identity` and reports all 60 canonical records; the offline Lua suite passes the explicit-name and re-init coverage.

## WT cross-character loadout lifecycle trace (#354)

- [ ] Equip an enabled WT cross-character weapon into the active modded loadout; one `[gut:354] phase=capture ... result=stored` record names the exact backend ID and item key.
- [ ] Exit and relaunch; the selected row emits one deduplicated `phase=apply` outcome with the same ID or an explicit fallback result.
- [ ] Capture both a persisting and a dropping cycle, attaching all `[gut:354]` lines from the pre-exit and post-launch logs.
- [ ] Ordinary resolved weapons, inactive WT unlocks, non-selected rows, and non-weapon slots emit no #354 records. A missing selected weapon ID may emit `<unresolved>` while WT is installed; total records never exceed 24 per process.
- [ ] `/gut_regression_test` passes `issue354_wt_loadout_lifecycle_trace`.

---

## LA cosmetics in native saved loadouts (#353)

- [ ] In the modded realm with LA enabled, save different LA cosmetics in two native loadout rows and switch between them.
- [ ] Weapon illusion, hat, frame, and pose each restore after switching rows, reopening hero view, and restarting the game.
- [ ] With **Use non-modded loadouts** enabled, official gameplay gear remains read-only while LA cosmetics persist in GUT's modded overlay.
- [ ] Re-enter the official realm and confirm its loadout rows were not changed by the modded test.
- [ ] `/gut_regression_test` passes `native_loadouts_la_cosmetic_outer_capture`; the log contains no `BU cosmetic capture SKIP` for successfully equipped LA cosmetics.

## CKC vanilla Options isolation (#528)

- [ ] With CKC installed, Options > Gameplay renders the stock Crosshair Kill Confirmation row exactly as it does without GUT.
- [ ] No CKC gear, checkbox conversion, redirect, row suppression, or native-setting overwrite appears in vanilla Options.
- [ ] CKC's own VMF page and Mod Tweaker > Interface > HUD > Crosshair Kill Confirmation remain editable.
- [ ] `/gut_regression_test` passes `issue528_ckc_vanilla_options_isolated`.

---

## HUD edit drag geometry (#547)

- [ ] Enter HUD edit mode and inspect all ten registered HUD elements at the current resolution.
- [ ] Each overlay rectangle sits on its visible element and hover starts only inside that rectangle.
- [ ] Drag pivot-based equipment, buffs, boss health, duties, books, and news-feed elements; the rectangle follows the moved element without an offset.
- [ ] Edge confinement still uses the visible rectangle, and offsets survive closing/reopening the HUD.
- [ ] `/gut_regression_test` passes `hud_drag_geometry_uses_render_bounds`.

## HUD editor live coverage (#310)

- [ ] Enter HUD edit mode once in a mission and confirm exactly ten `[gut:310] HUD coverage id=...` rows plus one summary are emitted; no coverage rows repeat while the mode remains active.
- [ ] `career_ability_bar` reports `scenegraph=_ui_scenegraph` when its live view exists and receives a correctly aligned drag box instead of being silently omitted.
- [ ] Exit and re-enter edit mode; one fresh bounded snapshot is emitted, allowing a changed career/HUD state to be compared.
- [ ] Missing or naturally inactive HUD classes report a named status and do not raise or prevent other elements from being edited.
- [ ] `/gut_regression_test` passes `issue310_hud_scenegraph_alias_coverage`.

## Mod Tweaker settings-tree ordering (#557)

- [ ] Open tabs with mixed top-level groups and loose settings; groups appear first and each partition is alphabetical by localized label.
- [ ] Expand groups with mixed nested children; the same rule applies at each sibling level and no descendant moves outside its parent.
- [ ] Confirm authored header sections retain their sequence.
- [ ] Confirm Equipment remains Cosmetics, Crafting, Weapons, then nested CWV rather than being alphabetized.
- [ ] Exercise both keep and in-mission Mod Tweaker presentations.
- [ ] `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes the ordering suite.

## Well of Dreams cutscene trace (#257)

- [ ] Enable GUT Skip Cutscenes and Auto-skip; disable any standalone cutscene-skip mod.
- [ ] Run The Well of Dreams (`dlc_termite_3`) once and record whether any fade remains visible.
- [ ] Attach all `[gut:257]` lines. Confirm they include activation/skip event names, fade durations, callback order, and a fade disposition.
- [ ] Confirm no `[gut:257]` lines appear on another mission.
- [ ] Confirm the trace stops after at most 32 callback records and one `phase=cap` marker for one CutsceneSystem instance.
- [ ] `/gut_regression_test` passes `issue257_well_of_dreams_cutscene_probe`.

## Simple UI compatibility (#314)

- [ ] With Simple UI and UI Tweaks enabled, drag fitted windows through every screen edge; each remains wholly visible.
- [ ] Resize a window larger than the viewport; its left edge and top title/drag handle remain reachable.
- [ ] Change resolution/UI scale; existing windows recover into the new bounds without replacing their position tables.
- [ ] Without Simple UI installed/enabled, GUT behavior and logs are unchanged.
- [ ] `/gut_regression_test` passes `issue314_simple_ui_window_confinement`.

## Native options

### issue292-video-profiles-native-apply — saved graphics presets bypass engine apply

| Field | Value |
|-------|-------|
| Symptom | Rebuilding a screenshot/performance configuration requires manually changing every Video option. |
| Root cause | The native menu has one pending-settings transaction but no reusable local snapshots. Direct `Application.set_user_setting` writes would bypass its reload/restart and timed-revert lifecycle. |
| Fix version(s) | gui_tweaker_dev v0.2.244-dev (#292) |
| Category | UNIT / UI INTEGRATION / PERSISTENCE |
| Repro | Save two visibly different Video profiles, switch slots, Apply, keep/revert, reopen, restart, rename, and delete. Include a resolution unavailable to a second display or a capability-specific option when possible. |
| Expected post-fix | Selection replays native widget callbacks into `changed_user_settings` / `changed_render_settings`; native Apply activates the profile. Unsupported values skip safely. Five flat VMF-persisted slots survive restart. |
| Detection | Offline `test_gut_video_profiles.lua`; `/gut_regression_test`: `issue292_native_video_profile_pipeline`; bounded `[gut:292]` save/stage/delete lines. |

---

## Mod Tweaker

### issue525-progression-tab-label — readable name leaks into compact chrome

| Field | Value |
|-------|-------|
| Symptom | Modded Progression's generated top tab uses or truncates `Modded Progression` instead of reading `Progression`. |
| Root cause | Both Mod Tweaker presentations derived compact tab chrome directly from each VMF mod's readable name; their exact-label tables were duplicated and had already drifted. |
| Fix version(s) | gui_tweaker_dev v0.2.248-dev (not deployed) |
| Category | UNIT / UI INTEGRATION |
| Repro | Enable Modded Progression, then open Mod Tweaker in the keep and in a mission. |
| Expected post-fix | The existing Modded Progression category renders as the exact `PROGRESSION` top-tab label in both presentations. Its settings and VMF identity are unchanged. |
| Detection | Offline `test_mod_tweaker_tab_labels.lua`; `/gut_regression_test`: `issue525_progression_tab_label`; solo visual confirmation required after deployment. |

### issue318-disabled-integrations-in-place — disabled mod escapes or disappears

| Field | Value |
|-------|-------|
| Symptom | VMF-disabled CWV appears as a blacked-out top-level tab or disappears instead of remaining in its normal Equipment > Weapons section. |
| Root cause | Category enumeration first hid disabled mods, while the earlier merge counted only enabled members; neither preserved installed layout identity separately from edit authority. |
| Fix version(s) | gui_tweaker_dev v0.2.244-dev (not deployed) |
| Category | UNIT / UI INTEGRATION |
| Repro | Install WT and CWV, disable CWV in VMF, then open Mod Tweaker in Keep and mission. Repeat with stock UI Tweaks disabled. |
| Expected post-fix | CWV and UI Tweaks retain their normal grey section header with `Disabled in VMF` on hover. Disabled sections do not expand, expose rows, stage values, participate in profiles/DEFAULT, or receive Apply writes. Re-enabling restores the same section in place. |
| Detection | Offline `test_mod_tweaker_disabled_sections.lua`; `/gut_regression_test`: `issue318_disabled_integrations_keep_normal_sections`; solo visual/hover confirmation required after deployment. |

### issue636-wt-dev-equipment-collapsible — Weapons Dev rows disappear

| Field | Value |
|-------|-------|
| Symptom | With the friends-only Tweaker: Weapons Dev stream enabled, Mod Tweaker has no accessible Weapons section even though the mod is registered and running. |
| Root cause | Both Mod Tweaker presentations duplicated an authored-mod whitelist and Equipment role map that knew only the public-beta `wt` namespace, so VMF's `wt_dev` widget list was filtered out before Equipment synthesis. |
| Fix version(s) | gui_tweaker_dev v0.2.279-dev (#636) |
| Category | UNIT / UI INTEGRATION / CROSS-MOD |
| Repro | Enable Tweaker: GUI Dev, Tweaker: Weapons Dev, and CWV; leave public-beta WT disabled or absent. Open Mod Tweaker in the keep and in a mission. |
| Expected post-fix | Equipment contains one Weapons collapsible populated by the enabled `wt_dev` rows, including Weapon Availability, Development Animation Picker, and Development Weapon Hold-Pose Tuner. CWV remains nested beneath Weapons. The `wt_dev` identity, friends-only Workshop visibility, and preview remain unchanged. |
| Detection | Offline `test_mod_tweaker_disabled_sections.lua`; `/gut_regression_test`: `issue636_wt_dev_equipment_collapsible`; solo visual confirmation required after deployment. |

### issue572-search-magnifier-focus-geometry — icon crowds text or remains while typing

| Field | Value |
|-------|-------|
| Symptom | The native magnifier appears too large and to the left of Mod Tweaker's field; its generic prompt does not identify the active tab. |
| Root cause | Vanilla's negative icon offset belongs to a separate filter-control region, but was copied onto Mod Tweaker's full-width field; the prompt was hard-coded. |
| Fix version(s) | gui_tweaker_dev v0.2.243-dev, v0.2.271-dev (#572) |
| Category | UNIT / UI INTEGRATION |
| Repro | Open Mod Tweaker in Keep and mission, inspect the empty field, click anywhere in it, type, then leave focus; repeat at a non-default UI scale. |
| Expected post-fix | The 95px padded tile (15% smaller than 112px) places its visible glyph approximately at x=8..32 inside the unfocused field, disappears while focused, and returns after focus leaves. The prompt reads `Search <current tab name>`; text begins at x=47 and the full-field hotspot and search transactions do not change. |
| Detection | Offline `test_mod_tweaker_search.lua`; `/gut_regression_test`: `issue572_mod_tweaker_native_search_icon`; in-game visual/focus confirmation while issue #572 carries `verify-fix`. |

### issue575-numeric-caret-native-metrics — caret follows proportional glyph boundaries

| Field | Value |
|-------|-------|
| Symptom | Clicking a slider's numeric value places the caret roughly one character left, with error varying by glyph and UI scale. |
| Root cause | Mod Tweaker measured an unscaled material proxy, omitted `font_type`, and centered width without subtracting the renderer's glyph origin. |
| Fix version(s) | gui_tweaker_dev v0.2.240-dev (#575; user verified 2026-07-13) |
| Category | UNIT / UI INTEGRATION |
| Repro | Edit one/multi-digit, negative, and decimal slider values; click every boundary and use Left/Right/Home/End plus insert/delete at multiple UI scales. |
| Expected post-fix | The caret uses `UIFontByResolution` and `UIRenderer.text_size` full/prefix metrics, remains at the intended insertion boundary, and commit/cancel/highlight behavior is unchanged. |
| Detection | `/gut_regression_test`: `mod_tweaker_numeric_caret_geometry`; offline `test_mod_tweaker_numeric_editor.lua`; tier-a manifest locks native metric resolution and both `_mod_tweaker_view` / `_mod_tweaker_state` click call sites. |

### issue340-all-language-glyph-diagnostics — distinguish bytes from atlas coverage

| Field | Value |
|-------|-------|
| Symptom | Non-Latin player names and chat can render as square blocks even when their UTF-8 bytes reach the UI intact. |
| Root cause | Vanilla chat copies sender/message strings into a UTF-8-aware widget, but the active font material only renders glyphs present in its compiled atlas. The reference mod supplies a proprietary custom atlas that this repository cannot redistribute. |
| Fix version(s) | Pending next gui_tweaker_dev diagnostic bundle (#340) |
| Category | UI / FONT RESOURCE / DIAGNOSTICS |
| Repro | Run `/gut_all_languages_status` with and without the standalone Support All Languages mod enabled. |
| Expected post-fix | The command reports all eight font rows, prints six visual language-family samples, and logs bounded per-player UTF-8 metrics without logging or rewriting names. |
| Detection | Offline `test_gut_all_languages_diagnostics.lua`; `/gut_regression_test`: `all_languages_defer_340`; solo visual confirmation required after deployment. |
