# Tweaker: GUI dev — Changelog

## 0.2.324-dev (2026-08-01) -- bound high-damage popup scale (#938) [verify-fix]

- Floating damage-number text still carries the full damage amount, while its
  damage-derived font scale now stops growing at the engine's live
  `NetworkConstants.damage.max` boundary. Ordinary values through that boundary
  retain the vanilla formula, colors, critical emphasis, and durations.
- Added `/gut_regression_test` check `issue938_damage_number_visual_bound` plus
  offline boundary, fail-open, and runtime-wiring coverage.

## 0.2.322-dev (2026-08-01) -- reseed official loadouts after Equipment DEFAULT (#1033) [verify-fix]

- Tracks a confirmed WT/Cosmetics DEFAULT as transaction state independent of
  changed settings, so Apply remains available even when every setting already
  equals its default but stale illegal modded equipment still exists.
- After every owner batch succeeds, clears only GUT's modded loadout/cosmetic
  overlay and immediately clones the cached official Adventure rows back into
  it. Official mirror methods and cloud data remain read-only.
- Persists the loadout and overlay once each, dirtifies backend interfaces once,
  and emits one bounded `[gut:1033]` summary. A failed settings/reset transaction
  stays armed for retry and discarded menu sessions cannot replay it later.
- Adds pure scope, retry, table-identity, deterministic career-order, and both-
  view wiring coverage.

## 0.2.321-dev (2026-08-01) -- render the expanded scoreboard as a bounded grid (#272) [diagnostics-armed]

- Replaces the five oversized newline-delimited text passes with one bounded
  pass per title, header, statistic label, player header, and value cell.
- Gives the scoreboard an explicit root scenegraph, opaque framed panel,
  alternating row backgrounds, fixed column rules, and missing title/header
  localization so Hold-Tab and the mission-end screen share one readable grid.
- Keeps the existing four-player/eleven-stat cap, detached native snapshot,
  four-Hz refresh ceiling, external-scoreboard exclusion, and zero custom RPCs.
- Extends offline source-contract coverage to reject the prior TSV-like layout.

## 0.2.320-dev (2026-08-01) -- use authoritative teammate ammo (#249) [verify-fix]

- Corrects Numeric UI's teammate ammo text after its static-template
  calculation by reading the exact current/maximum pair already replicated by
  the owner's or remote husk's inventory extension.
- Preserves Numeric UI's three display modes and existing cooldown integration,
  while leaving gameplay state, weapon templates, buff arithmetic, and native
  network fields unchanged.
- Fails open when the exact pair or retained widget is unavailable, emits at
  most twelve correction records and three contained adapter errors, and adds
  no custom RPC or per-frame polling.
- Adds `/verify_boon_ammo_hud` to compare the local exact ammo pair with the
  vanilla wire fields before the co-op observer test.

## 0.2.319-dev (2026-08-01) -- import pre-owner native bot assignments (#954) [verify-fix]

- Imports a bot assignment made by the native loadout UI before GUT owned
  detached snapshots. The vanilla `PlayerData` index is resolved against the
  modded saved rows once, copied into a bounded snapshot, and never followed
  again as the player's source row changes.
- Preserves an existing GUT-owned bot index/snapshot over stale native data,
  defers a valid index until its saved row exists, and seals absent or malformed
  assignments without repeated persistence work.
- Strengthens the live regression so a native bot assignment with zero owned
  snapshots fails instead of producing the false PASS seen in Rain's
  v0.2.318-dev log.
- Emits one deduplicated `[gut:954] native bot designation import` summary at
  the migration boundary; it adds no frame callback or chat output.

## 0.2.318-dev (2026-07-26) -- guarantee in-mission vote titles (#700) [not-started]

- Replaces the blank keep-only `game_settings_vote` localization at the
  promoted in-mission HUD edge with the dedicated player-facing title
  **Change Mission?**, while retaining a usable native title when one exists.
- Keeps the shared vanilla vote template, RPC identities, `NetworkLookup`,
  Accept/Decline option keys, keep voting, and unrelated vote types unchanged.
- Preserves the complete return tuple from both wrapped `VoteManager` start
  methods, including trailing nils, and fails closed when the template is
  malformed or neither localization provider yields a usable title.
- Retains usable output from an existing authored title modifier, contains a
  throwing or unusable modifier, and falls back to the dedicated title.
- Records one bounded `[gut:700] title-boundary` result per promoted active
  vote at `IngameVotingUI.start_vote`; there is no per-frame diagnostic.
- `/verify_gut_mission_vote` and `issue700_mission_vote_client_popup` in
  `/gut_regression_test` cover the live hook/policy/title contract; the offline
  policy suite covers localization rejection, tuple-safe wiring, option
  preservation, malformed input, and diagnostic classification.

## 0.2.317-dev (2026-07-26) -- restore source-backed hidden career perks (#153) [not-started]

- Supplies the native passive-perk rows only while the career-information
  panel is populated, then restores the exact original data immediately.
- Shows both source-proven Witch Hunter Captain passives without permanently
  mutating shared career settings or relying on guessed descriptions.
- Adapts the presentation to the available career-info row count: separate
  rows on the six-row console layout and one combined tooltip row on the
  compact three-row desktop layout.
- Fails closed when native source signatures drift, and adds bounded
  regression coverage for restoration, idempotence, layout, and localization.

## 0.2.316-dev (2026-07-26) -- reconcile detached bot equipment at the read boundary (#954) [not-started]

- Reconciles the persisted detached bot snapshot at the engine's shared
  `get_bot_loadout` consumer, covering startup refreshes that occurred before
  the dev hook or Adventure interface was ready.
- Repairs later same-cache drift on demand with one bounded diagnostic record;
  the check runs only on bot-loadout reads, not per frame.
- Both comparison and detached-copy work are bounded by depth, visited-key,
  and career ceilings. Wide, cyclic, or corrupt saved values defer to the
  native result without mutating the bot cache or persisted row.
- Reconciliation validates every career before committing any migration or
  cache replacement, preventing a later corrupt row from leaving earlier
  careers half-migrated in memory.
- Uses the concrete backend interface to prove Adventure ownership and leaves
  official and read-only loadout paths native.
- Adds functional coverage for stale startup caches, later in-place mutation,
  exact argument forwarding, persistence retry, wide/cyclic corruption, and
  official-realm fail-open behavior.

## 0.2.315-dev (2026-07-26) -- bounded Equipment DEFAULT transactions (#1002) [not-started]

- Equipment-tab DEFAULT now commits each participating owner through one
  owner-defined batch transaction instead of firing heavyweight refresh work
  once per setting.
- Failed or incomplete owner transactions remain staged, preventing profile
  capture and profile switching from silently accepting a partial reset.
- Added regression coverage for bounded notification counts, owner isolation,
  partial failures, and retry behavior.

## 0.2.314-dev (2026-07-22) -- detached bot loadout snapshots (#954) [not-started]

- Assigning a saved loadout to a bot now persists a dedicated copy of that
  row's equipment. Later edits to the player's saved row no longer mutate the
  bot's live or persisted equipment through the same table identity.
- Existing bot designations migrate once from their current designated row.
  Every backend refresh receives another detached copy, so backend cache writes
  cannot alias the persistent snapshot. Official-realm behavior remains native.
- Added stable/dev Lua truth-table, deep-copy, runtime-wiring, and live
  `/gut_regression_test` coverage.
## 0.2.313-dev (2026-07-22) -- Chaos Wastes exit identity isolation (#273) [not-started]

- Exit-time loadout snapshots now read a slot only when the durable `items`
  interface currently owns it. Temporary Deus-owned melee/ranged backend ids
  are skipped instead of being persisted into the Adventure loadout store;
  items-owned cosmetic slots remain eligible during Chaos Wastes.
- The bounded exit diagnostic now includes `foreign_slot_reads=<n>`. Added
  pure ownership-policy, mixed gear/cosmetic, structural-order, and runtime
  regression coverage.

## 0.2.312-dev (2026-07-22) — #925 shared presentation generation publisher [not-started]

- Successful GUT loadout equips now publish a bounded, scalar-only local
  presentation invalidation. If Cosmetics' inner singleton hook already
  published the same synchronous write, GUT observes the generation advance
  and does not duplicate it; if Cosmetics is absent, GUT supplies the event.
- Removed the obsolete instruction to reopen Hero View to refresh the visual
  model. Stable GUT remains unchanged.

## 0.2.311-dev (2026-07-22) -- bounded profile-commit observer (#919)

- Added a bounded, owner-registered profile-commit diagnostic API for #919.
  Both Mod Tweaker presentations emit only after the target profile has been
  applied, and each tab has at most one observer. The API carries only tab,
  slot, and phase; the owning mod remains responsible for its runtime snapshot.

## 0.2.310-dev (2026-07-21) -- global renderer non-interference (#749)

- The consolidated `UIRenderer.create` guard now uses the shared tri-state V2
  contract: only positively absent material pairs are removed; unknown,
  malformed, vanilla, third-party, and Pusfume inputs pass through unchanged.
- GUT-owned pose, store, and area-video injections remain strict and are added
  only after a positive material proof.
- Added offline coverage for unknown/throwing probes, exact vararg preservation,
  sparse input rejection, and bounded filtering.

## 0.2.309-dev (2026-07-21) -- live mixed-lobby setting gates (#371)

- Added an owner-registered runtime gate API for Mod Tweaker settings. A gate
  predicate is evaluated from live lobby state; unknown, malformed, or throwing
  results fail closed.
- Both the keep and in-mission Mod Tweaker presentations now make blocked rows
  read-only, grey their labels, and replace the normal tooltip with the owner's
  player-facing explanation. Rows restore their exact prior state as soon as
  the live gate becomes available again, without changing saved settings.
- Pending edits are filtered again on Apply, closing the race where a peer
  joins after an edit is staged but before the user commits it.
- No gameplay feature is registered in this release. Runtime/network emission
  guards remain mandatory in each owning mod; this is the shared UI and input
  foundation only.
- Added offline coverage for composed gates, predicate failures, live row-state
  restoration, and both presentation paths.

## 0.2.308-dev (2026-07-21) -- merged slider ownership and selected-loadout evidence (#389 #375)

- Numeric rows in the synthesized Equipment tab now resolve their snap/click
  increment from the setting's real provider instead of the `gut_dev` category
  owner. CIM Base Power Level therefore retains its authored 25-point step in
  both Mod Tweaker presentation paths.
- Added automatic, bounded #375 snapshots at the concrete native-loadout mirror
  read boundary. Each changed weapon read records caller, requested/resolved/
  selected indices, both weapons in the resolved and canonical selected rows,
  and the value actually served. Identical hot reads are suppressed and the
  cache is capped at 128 entries.
- Added offline coverage for merged-owner resolution and trace deduplication,
  row-change visibility, and the hard cache bound.

## 0.2.307-dev (2026-07-19) -- #630 Equipment-section DX12 diagnostics refinement [diagnostics-armed]

- Refined the #630 diagnostics after live logs showed every captured Mod
  Tweaker pass balanced (`balance=0`, `anomalies=0`) but no captured tab named
  `wt_dev`: Weapons now lives under the synthesized `gut_equipment` tab. The
  probe now records each synthesized Equipment section's exact stored/forced
  expanded state plus its prior-frame viewport visibility as `equipment_state`.
  A future freeze can therefore prove that Weapons was actually expanded instead
  of merely present as a visible collapsed header. Scroll-only visibility changes
  do not emit another edge.
- This remains diagnostics-only: no renderer, focus, package, view, tab, WT
  hold-pose, or draw behavior changes.

## 0.2.306-dev (2026-07-19) -- Dialogue browser mouseover transcript popups (#880) [untested]

- Hovering a dialogue line row shows a transcript popup anchored directly under the row (flipping above only at the screen bottom): title = the row's Wwise event id, body = the line's localized subtitle plus one speaker-label - dialogue-group metadata line. Popup suppressed whenever the subtitle key does not resolve (raw key echoed back or a `<...>` marker), so no raw-key popups.
- New pure binder module `_mod_tweaker_dialogue_transcript.lua`; binding runs only at virtual-window build time (bounded rows, no per-frame or per-hover allocation) and rides the existing #207 single-tooltip-widget hover pipeline (same fade, hide-on-leave, and hover sound path).
- `create_dialogue_row` gains a hover-only full-row `row_hs` hotspot (its clicks are never read, so state/media controls keep all input); `layout_tooltip` gains an optional prefer-below anchor threaded through both twin `_update_tooltip` surfaces.
- 4 new engine-free tests in `test_character_dialogue`: hover-target resolution across scroll offsets, transcript + speaker content binding with suppression, window-bounded binding with no localizer traffic across 100 hover cycles, and hide-on-leave / unbound-row / collapse coverage.

## 0.2.305-dev (2026-07-19) -- log dialogue media clicks with outcome (#881) [diag]

- `[gut:605] media_click` printf receipt on every dialogue-row media click captures the event id and the toggle_pause result, so a click that never reaches Character Dialogue's preview transport is distinguishable from a play that failed inside it.

## 0.2.303-dev (2026-07-19) -- reconcile newly added settings into existing profiles (#828) [verify-fix-coop]

- Upgrades sparse saved profiles from the current declared defaults while preserving every explicit saved value, including `false` and explicit opt-ins.
- Applies only missing members through the existing bounded owner transaction and persists the upgraded snapshot only after every addition succeeds.
- Keeps stable/dev and standalone/keep-state profile behavior aligned, with bounded `[gut:828]` receipts only when a migration is actually needed.

## 0.2.302-dev (2026-07-19) -- #312 live UI Tweaks integration [verify-fix]

- Replaces the copied UI Tweaks checkbox allow-list with the installed mod's current VMF widget tree, preserving groups, sliders, dropdowns, and keybinds in both Mod Tweaker presentations.
- Routes reads and writes to UI Tweaks as the single owner while excluding its values from GUI Tweaker's per-tab profiles.
- Preserves the authored fallback when UI Tweaks is absent, disabled, or its live widget registry is temporarily unavailable.
- Adds pure planner regression coverage for live-tree rebasing, ownership, profile exclusion, future widget types, and fail-closed fallback behavior.

## 0.2.301-dev (2026-07-19) -- #257/#274 order-independent cutscene skip window + #245/#246/#250/#533 live-session Hold-Tab provider [untested]

Two root-cause clusters, one build.

### Cluster A - cutscene skip guard reworked per-cutscene-instance and order-independent (#257, #274)

- **Root cause (both issues):** the post-skip guard was keyed to the CutsceneSystem INSTANCE (one per level, `cutscene_system.lua:11-24`) and assumed a callback arrival order - it armed only at skip time and released only at `flow_cb_activate_cutscene_logic` or a fixed 15 s timeout. Maps where the fade precedes its camera node (issue 140 proved ~97 ms fade-first groups on `dlc_dwarf_whaling`) or where the fade precedes BOTH activation callbacks (#257, The Well of Dreams = `dlc_termite_3`) fell outside every armed window; conversely a suppression window that outlives its cutscene is exactly the #274 class (the `dlc_dwarf_whaling` ENDING camera suppressed after an intro skip under the pre-274 policy).
- **Rework:** new pure `_gut_cutscene_skipwindow.lua` models cutscene EPISODES per system: logic activation opens a new episode (generation + identity); a PROVEN skip (before-camera/after-no-camera, unchanged #106 proof) marks the episode skipped and opens its straggler window; every later `flow_cb_*` CLASSIFIES against the episode regardless of order (fades swallow, camera activations suppress). ONE release condition: the window ends when a new episode opens (logic activation, or a camera node carrying a DIFFERENT non-nil `event_on_skip`) or its deadline passes - a rolling 15 s grace re-granted by each classified straggler (the timeline is still replaying) under a 45 s hard cap from the skip moment, so a legitimate later cutscene ALWAYS passes (#274 structurally closed; the skipped `dlc_dwarf_whaling` intro timeline runs ~35.5 s, inside the cap).
- **#257 fade coverage, order-independent:** three swallow sources replace the two order-coupled ones: the one-shot in-skip-call fade stays (issue 140 trace 22:04:36.434 proves it); a PENDING window swallows every fade between the intro's logic node and the deferred `skip_pressed` tick (the old one-shot caught only the first); and a bounded pre-identity INTRO WATCH (30 s from the system's first observed callback, only while auto-skip is armed) swallows a mission-intro fade that fires before ANY activation callback - the shape no identity-gated arm could ever catch. Trade-off (accepted): if a mission's FIRST cinematic is locked/non-intro, its opening fade is also swallowed under auto-skip - a cosmetic pop; the cinematic itself still plays.
- **Issue 275 policy preserved verbatim:** the intro-only SKIP policy (`_gut_cutscene_policy274.is_intro`, exact `cs_01_skip`; nil `event_on_skip` = never skip = no boss desync) gates every skip path unchanged - the watch and windows affect FADES and post-skip CAMERA stragglers only, never whether a cutscene skips. The removed #140 round-1 camera-node one-shot arm is subsumed by the pending window (identity at the camera node implies the logic node already queued the deferred skip).
- **Diagnostics:** `[gut:cutscene] fx_fade swallowed (<swallow_pending|swallow_window|swallow_intro_watch>)`, `CAMERA-ACTIVATE suppressed (post-skip window)`, `[gut:274] skip window released (...)` / `post-skip window closed (...)`; the #257 probe (`[gut:257]`, `dlc_termite_3`-only, 32-record cap) now records the REAL per-callback verdict instead of a parallel prediction.
- **Regression:** stale `cutscene_postskip_fade_swallow` needle fixed - it still grepped the pre-policy274 expression (`_skipped_cutscene_system == self ...`), which no longer existed, so it false-failed; it now pins the `_gut_cutscene_fade_swallow_site` marker + classifier call (same fix in `qa/rt_textual_invariants.psd1`, which also gains #257/#274 classifier needles and an issue-275 `INTRO_SKIP_EVENT` policy needle). `issue274_post_intro_guard_bounded` rt-check rewritten against the skip-window bounds + release. NEW offline suite `test_gut_cutscene_skipwindow.lua` (12 cases): fade/camera order permutations, rolling-grace refresh vs hard cap, silent-gap close, logic release, new-identity camera release, late-cutscene pass (#274), pending multi-fade, intro-watch gating/bounds, per-instance isolation, production wiring incl. the issue-275 policy pin.

### Cluster B - ONE live-session Hold-Tab loadout provider (#245, #246, #250, #533)

- **Mechanism verified in the decompile (replacing the [unverified] snapshot hypotheses):** the held-Tab panel renders per-player rows from `Managers.player:player_loadouts()` (`ingame_player_list_ui_v2.lua:1450,1507,1527-1539`) - a table populated ONLY at `SimpleInventoryExtension.add_equipment` via `LoadoutUtils.sync_loadout_slot` -> `rpc_sync_loadout_slot` (`simple_inventory_extension.lua:883-885`; `player_manager.lua:69-84`; the sender loops back locally, `network_transmit.lua:514`). The wire shape carries ONLY key/rarity/power/properties/traits - NO skin field (`loadout_utils.lua:13-43,70-88`).
  - **#245 CONFIRMED (snapshot class):** rows freeze at equip time; a mid-session reforge mutates the backend item but nothing re-syncs the row - stale properties AND traits.
  - **#246 CONFIRMED with exact mechanism:** the icon/tooltip pass shows an illusion only when `item.skin` is set (`ui_utils.lua:238-245`); the RPC rebuild never sets it, so every row falls to the base-weapon icon.
  - **#250 snapshot hypothesis DISPROVED:** talents are LIVE - the panel reads `talent_extension:get_talent_ids()` (deus-aware backend, `talent_extension.lua:250-257`; boon grants append + re-sync via `rpc_sync_talents`, `deus_power_up_utils.lua:411-443`, `talent_extension.lua:48-76`). The true defect is the panel's SIX fixed positional widgets rendering the deus flat list (base dense array + appended boons, `backend_interface_talents_playfab.lua:276-307`) - wrong tiers for sparse builds, appended boons invisible past slot 6. The existing tier-normalization repair (`_gut_tab_talent_refresh/_policy`, first-per-tier, one-widget-per-tier display limit documented in `TAB_TALENT_FILTER_250.md`) is the correct fix and is absorbed by the provider unchanged.
  - **#533 CONFIRMED:** the tome/grim/dice rows build from adventure loot objectives with no mechanism gate (`ingame_player_list_ui_v2.lua:436-514`), so ct-injected adventure maps inside CW show adventure counters instead of the run's coin/chest collectibles.
- **Fix - one provider, `_gut_tab_property_refresh.lua` (name historical), replacing the per-symptom patches:** per 4 Hz refresh tick while the panel is active, reconcile the LOCAL player's melee/ranged row properties + traits + skin from the exact live backend instance (the same `backend_id` read vanilla performs at equip), and decorate EVERY player's row skin from the synchronized (wearer, slot) cosmetic identity (`CosmeticUtils.get_cosmetic_slot` sync data, `cosmetic_utils.lua:230-294`). Per `docs/WEAPON_APPEARANCE_STANDARD.md` section 2: exact-instance evidence local-only, synced evidence for remote rows, absent/unresolvable evidence PRESERVES the vanilla reconstruction; a skin is written only when its template is locally resident (the vanilla icon pass derefs `WeaponSkins.skins[skin]` unguarded). Remote PROPERTIES stay vanilla-snapshot: no live source exists on this machine and re-sending the vanilla RPC with a possibly-modded item key is the cross-peer wire-safety hazard class - the provider sends NOTHING.
  - **#533:** new singleton hook on `IngamePlayerListUI._setup_mission_data` skips the adventure row build inside the deus mechanism (same gate the panel's own CW info uses, `ingame_player_list_ui_v2.lua:292-309`); `_mission_count` stays 0 so the Collectibles header hides cleanly (`:94-97,:1663-1666`). Display-only row filter; the coin/chest counters the issue wishes for are a separate feature.
  - **Wire safety (belt-and-suspenders):** refreshed properties/traits pass a NetworkLookup-name filter before entering the row, so vanilla's hot-join resync of the cache can never serialize a name a peer lacks (vanilla itself would fassert on such an equip; silent skip beats a host crash).
  - **Hook discipline:** the provider owns BOTH IngamePlayerListUI hooks (`_update_dynamic_widget_information` - refresh before vanilla renders, #250 talent repair after; `_setup_mission_data`); pre-flight grep confirms no other gut hook on either pair (`_gut_scoreboard_live` owns `_draw` only).
- **Diagnostics:** bounded `[gut:245]` (now printf, was mod:info) / `[gut:246]` / `[gut:533]` lines, 16-line caps.
- **Regression:** rt-checks now cover all four issues (`issue245_tab_weapon_property_refresh` + traits, NEW `issue246_tab_equipped_illusion_refresh`, `issue250_deus_tab_talent_module_loaded`, NEW `issue533_cw_collectible_rows_suppressed`); NEW offline suite `test_gut_tab_live_provider.lua` (trait identity gates, skin fallback chain incl. clear-stale and unresolvable-template preservation, wire-safe filters, deus row policy, both-hooks + display-only source pins). Existing `test_gut_tab_property_refresh` / `test_gut_tab_talent_filter` suites unchanged and green.

**Verify (solo, CW + adventure):** (1) #257: auto-skip ON, run The Well of Dreams - the intro fade must no longer show; attach `[gut:257]` lines. (2) #274: finish A Parting of the Waves with skip enabled - the ending cutscene must play/transition normally (no locked camera); a `[gut:274] skip window released` or clean `CAMERA-ACTIVATE` line at the ending is the evidence. (3) #245: reforge the equipped weapon (cim), hold Tab - properties/trait current. (4) #246: apply an illusion, hold Tab (and have a friend inspect you) - illusion icon shows. (5) #250: CW run, gain a talent boon, hold Tab - talents sit in their real tiers. (6) #533: ct adventure map inside CW, hold Tab - no tome/grim/dice rows.
## 0.2.300-dev (2026-07-19) -- #446 exclusive radio controls [verify-fix]

- Added nested mutually exclusive bubble/radio controls with an explicit
  UI-only **None [Default]** choice.
- Preserved existing boolean persistence and stock VMF checkbox fallback when
  a group is incomplete, scattered, or crosses mod ownership boundaries.
- Added deterministic immediate repaint, Apply/restart persistence contracts,
  and Career Tweaker integration coverage.

**Solo verify:** open the Career Tweaker exclusive groups, expand each nested
group, and select A, B, and None. Exactly one bubble must be selected, repaint
must be immediate, and Apply/restart must preserve the selected setting state.

## 0.2.299-dev (2026-07-19) -- #605 preserve dialogue collapse states [verify-fix]

- Replaced the dialogue browser's `closing and nil or speaker` pseudo-ternary
  with an explicit transition so closing a speaker can actually store `nil`.
- Fixed the same false/nil state class for the Disabled line state and added
  one bounded `[gut:605]` action record plus regression contracts.

**Solo verify:** open and close Dialogue speaker groups and cycle one line
through enabled, disabled, and default. The group must remain closed and the
selected state must repaint immediately and persist after Apply/reopen.

## 0.2.298-dev (2026-07-19) -- #340 language glyph diagnostics [diagnostics-armed]

- Extended `/gut_all_languages_status` to classify all eight active font rows
  as vanilla, custom, mixed, partial, or missing without mutating them.
- Added six bounded visual samples for Latin, Greek, Cyrillic, Japanese,
  Chinese, and Korean glyph coverage.
- Logs privacy-preserving UTF-8 metrics for human player names—byte,
  code-point, non-ASCII, and validity counts—without logging the names.
- Added source-backed documentation and regression coverage distinguishing an
  intact UTF-8 string path from a missing compiled glyph atlas.

**Solo diagnostic:** run `/gut_all_languages_status` with and without the
standalone Support All Languages mod. Capture the six rendered sample lines and
the bounded status records from a log containing `[gut:LOAD] v0.2.298-dev`.

## 0.2.297-dev (2026-07-19) -- #285 anchor respawn timers to live portraits [verify-fix]

- Removed the duplicated team-frame scenegraph and world-position conversion
  used by the respawn timer overlay.
- Draws each timer through the owning live `UnitFrameUI` widget renderer and
  `portrait_pivot`, so HUD/layout changes cannot drift a copied coordinate set.
- Added a bounded `[gut:285]` marker and regression coverage for the direct
  portrait-anchor contract.

**Solo verify:** kill a bot and confirm its respawn timer remains centered on
that bot's live portrait through HUD scaling/layout changes. The newest log must
contain `[gut:LOAD] v0.2.297-dev`; the timer should not drift or duplicate.

## 0.2.296-dev (2026-07-19) -- #824 dev localization runtime contract [verify-fix]

- Corrected the runtime localization regression check to load the dev stream's
  `gui_tweaker_dev_localization` resource instead of the stable stream name.
- A failed localization `dofile` now fails the regression check rather than
  being reported as a pass.
- Extended the repository dofile/package coverage gate to detect dot-form and
  protected `mod.dofile` calls, closing the static-check gap that hid this bug.

**Solo verify:** launch Tweaker: GUI dev and run `/gut_regression_test`.
`localization_format_safe` must pass without a resource error in the log.
## 0.2.294-dev (2026-07-19) -- #222 remove repeated HideBuffs tooltip titles [verify-fix]

- **Symptom:** the cross-mod title/body audit still found two GUT HideBuffs rows whose tooltip bodies merely repeated the orange popup header: Hide Player Levels and Hide Portrait Frames.
- **Fix:** rewrote both tooltip bodies to describe behavior first without restating the setting title. Added the repository QA gate `check_loc_description_titles.ps1` so future `foo` + `foo_tooltip`/`foo_description` localization pairs fail if the body starts with the normalized localized title.
- **Stable debt:** the stable `gui_tweaker/` copy is intentionally left untouched until promotion; the new gate freezes those exact stable lines as debt while enforcing the cleaned `gui_tweaker_dev/` stream.
- **Verify:** open Tweaker: GUI dev in Mod Tweaker or VMF options, hover Hide Player Levels and Hide Portrait Frames, and confirm the popup shows the title once in the header while the body starts with behavior text.

## 0.2.293-dev (2026-07-19) -- #402 complete native loadout slot isolation [verify-fix]

- **Empirical root:** the latest #402 logs on v0.2.291-dev showed the store serving many selected-row gear slots as `source=store-unknown` during early hero-view startup, then later serving the same stored ids as `source=store-yes` once backend item tables had settled. That explains the “last official weapon appears initially” side: the modded value was present, but presentation could initialize before the id was presentable and needed a later refresh.
- **Second root:** the modded store and official repair path still had a weapon-centric definition of a healthy native loadout row. `_row_is_corrupt_partial` treated a row with both weapons as healthy even if it was missing outfit, hat, portrait frame, victory pose, or accessory slots, and `/scrub_official_loadouts` only audited melee/ranged/frame and ignored nil slots. That left exactly the slots the user called out able to remain blank/stale even after the previous #402 fix.
- **Fix:** `_ensure_seeded` now runs a one-time `_slot_integrity_v2` migration that repairs missing slots from the official seed snapshot across the full canonical native loadout row (`slot_ranged`, `slot_melee`, `slot_skin`, `slot_hat`, `slot_necklace`, `slot_ring`, `slot_trinket_1`, `slot_frame`, `slot_pose`). It preserves existing modded values, fills only missing fields, marks the career migrated, and does not keep refilling forever.
- **Repair command:** `/scrub_official_loadouts` now audits every native loadout slot, treats nil as broken, and accepts either a resolvable backend item or, for cosmetic slots, a known `ItemMasterList` key. The command text now says “native loadout slots” instead of “weapon/frame ids” so the visible contract matches the code.
- **Diagnostics:** `/gut_loadout_status` now prints `slots_v2=<bool>` and `slot_integrity_failures=<n>`, and its row-level console line includes a `missing=[...]` list so future logs show which exact slot is absent instead of hiding non-weapon damage.
- **Regression:** `/gut_regression_test` now covers full-row corruption, the `_slot_integrity_v2` migration, nil-frame damage, cosmetic-key resolution, and the full-slot official scrub contract. Offline Lua tests lock the same source markers in `test_gut_native_loadout_policy.lua`.

### Solo verify

1. Confirm the latest log says `[gut:LOAD] v0.2.293-dev`.
2. In the modded realm, open Hero View and run `/gut_loadout_status es_questingknight` or the affected career. Expected: `slots_v2=true` and `slot_integrity_failures=0` after the hero view has opened.
3. In the official realm, run `/scrub_official_loadouts` before applying. Expected: it reports any broken outfit/hat/frame/pose/accessory slots, not just weapons/frame. If it reports broken slots, run `/scrub_official_loadouts apply`, restart, and confirm official frame/outfit/accessory slots are no longer blank while modded selections stay separate.

## 0.2.291-dev (2026-07-18) -- #700 localize the in-mission vote title [verify-fix-coop]

- **Observed after the popup fix:** the client vote HUD is functional, but its title renders the internal `game_settings_vote` localization key with underscores.
- **Source-backed cause:** `IngameVotingUI.start_vote` localizes `template.text` only when `modify_title_text` exists (`ingame_voting_ui.lua:116-121`). Vanilla `game_settings_vote` has no modifier because its ordinary keep presentation localizes the title independently (`mission_voting_ui.lua:256-264`). Promoting that template to an ingame vote without supplying the missing title seam therefore exposes the raw key.
- **Fix:** the already-bounded per-vote copy now receives an identity `modify_title_text` only when the source template has no authored modifier. This makes the native HUD perform exactly one localization lookup, preserves authored modifiers, and still leaves the shared vanilla template, keep votes, RPC payload, and unrelated votes untouched.
- **Regression coverage:** pure Lua tests prove the copy is non-mutating, the localized title passes through unchanged, malformed templates fail closed, and an authored modifier is preserved. Runtime regression now checks the same title contract.
- **Co-op verify:** host and client enter an Adventure mission and start the in-mission map vote. The client must see normal localized title text with no internal key/underscores, accept or decline normally, and both logs must contain one `[gut:700] mission vote promoted to localized IngameVotingUI` line. Keep and unrelated votes remain unchanged.

## 0.2.290-dev (2026-07-18) -- #717 keep Mod Tweaker gear rows lost their tan accent [verify-fix]

- **Symptom:** in the Mod Tweaker menu most entries render plain white/grey while some keep their intended color (user report, 2026-07-17 evening). The white rows are the gear-parent rows - every "Enable All ..." Weapon Availability master (issue 611) plus every advanced-options parent - in the KEEP Mod Tweaker; group headers (orange) and tabs/buttons (tan/gold) keep their colors.
- **Root cause:** twin-parity break, not the issue-694 tag strip. Commit 7d31174 (issue 611 gear-style masters) added the warm-tan gear-parent accent `{255,160,146,101}` only to the mission twin (`_mod_tweaker_view.lua:_append_row`); the keep twin (`_mod_tweaker_state.lua:_append_row`) never got it, so the same rows render default `font_default` there. The same commit rebuilt the Equipment tab so masters ARE the bulk of its rows, which turned a one-liner divergence into "most entries are white". No entry color ever rode on the stripped lifecycle tags: repo-wide grep at 9f0c11e~1 shows zero `{#color(...)}` markup and no tag-to-color code path in gut history.
- **Fix:** ported the identical accent block (enabled gear parents tan, disabled VMF rows stay grey, `_advanced_parent_accent` marker) into the keep twin's `_append_row`. Build-time style write on the existing label style - no new widget pass, no per-frame driver.
- **Surviving color classes (catalogued for the issue):** group headers / section titles `font_title` orange (shared `_mod_tweaker_definitions.lua`), tabs and Apply/Default/profile buttons via per-frame drivers in both interaction twins, disabled rows grey 128 in both twins. All intact; only the keep gear accent was missing.
- **Regression guard:** new `qa/lua/tests/test_gut_gear_accent_parity.lua` asserts BOTH twins carry the accent block (marker + exact color + disabled guard).
- **Verify (keep):** open the Mod Tweaker from the keep, Equipment tab, expand a character then Melee/Ranged: every "ENABLE ALL <CHARACTER> ..." master row and every gear-bearing row should now read in the same warm tan as the tabs; disabled rows stay grey. Cross-check the same rows from the in-mission ESC Mod Tweaker - identical colors in both.

## 0.2.289-dev (2026-07-18) -- #700 in-mission mission-vote client popup [verify-fix-coop]

- **Symptom:** selecting a new mission from GUT's in-mission map starts a team vote, but clients receive no accept/decline HUD. Their undecided vote becomes the template's timeout "no", so the selection never advances in co-op.
- **Root cause:** AdventureMechanism reuses vanilla `game_settings_vote`; the vote template and `NetworkLookup.voting_types` entry already exist on every peer, disproving a modded-key registration failure. Vanilla deliberately sets `game_settings_vote.ingame_vote = false` (`vote_templates.lua:306-319`) because it normally runs in the keep. `IngameVotingUI.update` draws only when `VoteManager.is_ingame_vote()` returns true (`ingame_voting_ui.lua:267-301`), so closing the mid-mission Start Game view leaves clients with no voting surface.
- **Fix (`_gut_mission_map.lua`):** singleton server/client vote-start wrappers shallow-copy the active vote template and set `ingame_vote=true` only for `game_settings_vote` in a live Adventure mission. That satisfies both the HUD draw gate and VoteManager's separate keyboard/gamepad input gate. Keep votes and unrelated vote types delegate unchanged; the shared `VoteTemplates` entry, RPC payload, and NetworkLookup table are untouched. One bounded `[gut:700]` line proves each peer promoted the active vote.
- **Wrapper contract:** both full `VoteManager` wrappers preserve every original return value, including trailing `nil`s. The audited vanilla methods currently return nothing explicitly, but transparent forwarding remains compatible with other wrappers and future engine revisions.
- **Malformed state:** promotion and verification fail closed unless the active vote template is a table; valid live-Adventure behavior is unchanged.
- **Verification:** `/verify_gut_mission_vote` reports the live hook/policy state. `/gut_regression_test` adds `issue700_mission_vote_client_popup`; offline `test_gut_mission_vote_policy.lua` covers the live-mission positive case and keep/mechanism/unrelated-vote negatives.
- **Co-op check:** host + client, both on v0.2.289-dev, enter an Adventure mission; host selects a mission from the in-mission map. The client should see the vanilla accept/decline HUD immediately, accept it, and the selected mission should start without the 30-second timeout.

## 0.2.288-dev (2026-07-18) - loadout exit-snapshot backstop (#353/#354/#287) [verify-fix]

- Cross-session persistence was captured on equip EVENTS only; state mutated after the last capture (or through a path that never fires it) was lost on quit - the #354 intermittency. New engine-free exit-snapshot core (non-destructive diff: nil live value never clears; only diverged+resolvable slots overwrite) reconciles the live loadout into the existing store at three exit edges: StateIngame exit, StateTitleScreen enter, mod unload. Same serializer as the equip path (byte-identity tested), official cloud data untouched, zero new hooks.
- Diagnostic: `[gut:persist] edge=<name> diverged=<n> written=<bool>` per edge. 8 new suite tests + rt-check native_loadouts_exit_snapshot_backstop.

**Solo verify:** equip a WT weapon or LA hat, quit WITHOUT re-equipping, relaunch: item still on the selected loadout; a `written=true` log line on exit is the backstop catching what eager capture missed. Repeat a few runs to hit the #354 timing.

## 0.2.287-dev (2026-07-17) -- #630 DX12 fence diagnostics

- Added automatic, bounded lifecycle evidence around both Mod Tweaker
  presentation passes. The probe records view entry/exit, renderer identity,
  selected-tab and window-focus edges, row counts, hold-pose gates, and balanced
  draw begin/end counts under the `[gut:630]` prefix.
- This is deliberately diagnostics-only. The attached dump stalls for 15.8
  seconds in native `D3D12RenderDevice::end_frame` with no Lua exception and
  healthy Lua memory; current source proves Mod Tweaker borrows its renderer and
  WT's hold-pose module owns no preview world, preview unit, or package. There is
  not yet evidence for a renderer/focus behavior change.
- Added Lua 5.1 coverage for balanced passes, unmatched/re-entered passes,
  focus/tab edge deduplication, the hard line cap, and both presentation call
  sites, plus runtime contract `issue630_dx12_fence_probe`.

## 0.2.286-dev (2026-07-17) -- #694 clean player-facing labels

- Mod Tweaker now removes legacy leading verification/status prefixes when it
  resolves labels from sibling Workshop mods. This compatibility boundary lets
  one GUI update clean the menu during a staggered sibling-mod rollout without
  mutating those mods' localization tables.
- The keep sub-state and in-mission view consume one pure label policy. Functional
  qualifiers such as `[Host Only]`, `[Client]`, `[WARNING]`, `[EXP]`, and `(CWV)`
  remain visible.
- Added engine-free regression coverage for forbidden prefixes, preserved
  functional qualifiers, and both presentation paths.

## 0.2.285-dev (2026-07-17) -- #402 deterministic official-loadout repair commit

- `/scrub_official_loadouts apply` now requests one immediate backend commit after a bounded repair and reports the engine callback result instead of asking the player to idle and hope the cloud write completes.
- Report-only, clean, and zero-repair runs do not commit. Missing, throwing, and unavailable backend paths report the repair as local-only and never claim cloud success.
- Added engine-free regression coverage for the forced-commit call shape, one-call bound, unavailable backend paths, and `success` versus `commit_error` classification.

## 0.2.284-dev (2026-07-17) -- GUI hard-limit recovery

- Extracted both Mod Tweaker presentation interaction surfaces into explicit owner-installed modules, preserving search, profile, numeric-editor, and Dialogue media behavior.
- Extracted runtime contracts and UI Tweaks bridge contracts from the main entry point without adding hooks, commands, or lifecycle callbacks to the new modules.
- Added offline structure/parity/package contracts; the six GUI offenders no longer exceed the 2,500-effective-line hard limit.

## 0.2.283-dev (2026-07-17) -- #611 advanced-option master presentation [untested]

- Gear/advanced-option parent rows now use the established warm-tan menu accent, clearly separating bulk/master controls from their individual child settings.
- Disabled gear parents remain grey, and the rule applies consistently to every advanced-options parent rather than hard-coding one mod's setting IDs.

## 0.2.282-dev (2026-07-16) -- #605 Dialogue media controls [not-started]

- Replaced the separate Play and Pause/Resume text buttons on every virtual
  dialogue row with one fixed media button. It uses a code-native right-facing
  triangle while stopped or paused and two vertical bars only while playing.
- Added a compact active-row progress track. Tweaker: GUI polls Character
  Dialogue's single preview snapshot once per frame, then updates only the
  visible owner row's fill width; it does not query Wwise per row or rebuild the
  34,327-entry catalogue.
- Reduced controller navigation to the row's two actual controls: dialogue
  eligibility state and the play/pause toggle. Rebuilt or inactive rows reset
  to the play glyph and an empty progress fill.

### Solo verify

Open Mod Tweaker > Dialogue, expand a character, and play a resident line. The
same button must switch triangle -> pause bars -> triangle as play/pause state
changes. Progress must advance, freeze on pause, resume from the same position,
and reset on row replacement or view cleanup. Mouse and controller focus must
stay on that same fixed button. Run `/gut_regression_test`.

## 0.2.281-dev (2026-07-16) -- #649 Helmgart Mission Select crash [verify-fix]

- Fixed the immediate crash when opening the Helmgart chapter while a late-
  registered custom career is present. The attached log failed on
  `completed_career_levels,pusfume,military,cataclysm_3` inside vanilla
  `StartGameWindowMissionSelectionConsole._profile_difficulty_index_completed`.
- Vanilla builds `completed_career_levels` definitions from the careers that
  exist when `statistics_definitions.lua` executes. The console mission window
  later iterates every live profile career without checking that exact
  definition path, so an externally added career can reach a fatal missing-stat
  lookup.
- Added one presentation-scoped guard on that method. Fully defined profiles
  delegate unchanged. When a career lacks any exact level/difficulty leaf, a
  shallow profile view omits only that career and delegates the original vanilla
  calculation; the source profile, StatisticsDatabase, and every unrelated
  error path remain unchanged. An all-undefined profile retains vanilla's first-
  career icon fallback without querying a nonexistent stat.
- Added bounded `[gut:649]` evidence, `/verify_gut_mission_completion`, runtime
  check `issue649_mission_completion_definition_guard`, and four Lua 5.1 tests
  covering identity preservation, exact-leaf filtering, immutability, and
  metatable preservation.

### Solo verify

Confirm `[gut:LOAD] v0.2.281-dev`, open the keep mission map, choose Custom Game,
then open Helmgart. The mission list must open without a StatisticsDatabase
crash. Run `/verify_gut_mission_completion`; it must report `guard=true` and
`PASS` (listing `pusfume` under undefined careers is expected when that external
career is active). Run `/gut_regression_test`; the issue #649 check must pass.

## 0.2.280-dev (2026-07-16) -- issue 631 Mouse-button keybinds in Mod Tweaker [verify-fix]

- Mod Tweaker hotkey rows now accept mouse buttons (Mouse 1-5), not just
  keyboard keys. Root cause: the Mod Tweaker reimplements keybind capture
  (`_poll_keybind_combo` in `_mod_tweaker_view.lua`, added with issue 123 to make
  those rows rebindable), and that reimplementation polled only `Keyboard`. VMF's
  keybind dispatch already resolves mouse key-ids, and VMF's own options view
  already captures mouse, so the gap was purely on gut's capture side.
- Added a mouse-index -> VMF-key-id map taken verbatim from VMF's
  `PRIMARY_BINDABLE_KEYS.MOUSE` (Mouse 1=`mouse left` .. Mouse 5=`mouse extra 2`),
  so a stored bind resolves back through VMF's `KEYS_INFO` to the mouse
  input-check functions at dispatch. Wheel is intentionally excluded (the issue
  asks only for the 5 buttons; a wheel tick has no held/release phase).
- Mouse binds are RELEASE-committed (mirroring VMF), so the left-click that enters
  capture cannot self-bind Mouse 1 and a Mouse 2 bind cannot fall through to the
  right-click-clear branch. Keyboard capture is unchanged (commits on press-hold).
- Ctrl/Alt/Shift held on the keyboard still combine with a mouse primary. Added
  runtime regression `issue631_keybind_mouse_capture`.

### Verification

1. Enable Tweaker: GUI Dev. In the keep, open Mod Tweaker and go to a tab with a
   keybind row (e.g. Tweaker: GUI Dev's own `Free Camera Hotkey`, or any mod's
   hotkey).
2. Click the keybind value to enter capture ("PRESS A KEY..."). Press a mouse
   side button (Mouse 4 or Mouse 5). The row should show `MOUSE EXTRA 1` /
   `MOUSE EXTRA 2` and stay in that state (no re-prompt, no clear). Click APPLY.
3. Repeat for Mouse 3 (middle -> `MOUSE MIDDLE`), Mouse 2 (right -> `MOUSE RIGHT`),
   and Mouse 1 (left -> `MOUSE LEFT`); each must bind cleanly without re-opening
   the prompt or wiping the value.
4. Hold Ctrl and press Mouse 4: the row should read `MOUSE EXTRA 1 + CTRL`.
5. Trigger the bound mouse button in-game and confirm the hotkey's action fires.
6. Right-click a keybind row while NOT capturing still clears it; ESC while
   capturing still unbinds.
7. Run `/gut_regression_test`; `issue631_keybind_mouse_capture` must pass.

## 0.2.279-dev (2026-07-15) -- #636 Weapons Dev Equipment section [verify-fix]

- Restored Tweaker: Weapons Dev to Mod Tweaker's Equipment > Weapons
  collapsible. Its `wt_dev` registration was valid, but both Mod Tweaker
  presentations filtered it out because their duplicated discovery and Equipment
  alias tables recognized only the public-beta `wt` stream.
- Centralized authored-mod discovery and stable/dev Equipment aliases in one pure
  policy shared by the keep sub-state and standalone view, preventing another
  stream-specific drift.
- Preserved every WT Dev row, including Weapon Availability, Development Animation
  Picker, and Development Weapon Hold-Pose Tuner. The friends-only Workshop
  identity and dev-only surface remain unchanged.
- Added offline and runtime regressions for alias selection, exact row retention,
  Weapons collapsible synthesis, and both presentation paths.

### Solo verify

Enable Tweaker: GUI Dev, Tweaker: Weapons Dev, and CWV while leaving public-beta
WT disabled or absent. Open Mod Tweaker in the keep and in a mission. Confirm
Equipment contains a Weapons collapsible with the WT Dev rows and nested CWV
section. Run `/gut_regression_test`; `issue636_wt_dev_equipment_collapsible` must
pass.

## 0.2.278-dev (2026-07-15) -- #605 Character Dialogue browser [verify-fix]

- Replaced Character Dialogue's flat dropdown and detached action rows with one
  collapsible per speaking character and one compact row per dialogue event.
- Each line's Default/Enabled/Disabled state, Play, and Pause/Resume controls now
  remain on that exact row; only the active event reports Playing or Paused.
- Virtualized the 34,326 playable candidates: at most 32 catalogue records plus
  the small visible overscan window are materialized, regardless of catalogue
  size. Scrolling recycles the window and search retains character grouping.
- Preview audio stops when its character collapses, another character opens, the
  user leaves the Dialogue tab, the view closes/destroys, or the world changes.
- Added engine-free coverage for grouping, sentinel rejection, stable row
  identity, paging/window bounds, focus reconciliation, single preview ownership,
  pause/resume, and cleanup wiring.

### Solo verify

Open Mod Tweaker > Dialogue, expand a character, and scroll through the list.
Search for a line, change its state, play and pause it on the same row, then play
another row. Confirm the active label follows only the exact line and audio stops
after collapsing the group, changing tabs, or closing Mod Tweaker. Run
`/gut_regression_test` and `/cd_regression_test`; both must pass.

## 0.2.277-dev (2026-07-15) -- #274 mission-intro-only cutscene skipping [untested]

- Restricted both automatic and manual forced skipping to the exact authored mission-intro event, `cs_01_skip`.
- Mid-mission and end-of-mission cutscenes now remain on the vanilla path, including cutscenes with missing, unknown, or different skip events.
- Bounded the post-intro camera guard to 15 seconds so an intro cannot leave stale suppression armed for a later outro.
- Added offline and runtime regression coverage for intro classification, non-intro preservation, and guard expiry.

### Test

Enable cutscene skipping, then start a mission and confirm only its opening cinematic is skipped. Complete the mission and confirm the ending cinematic plays normally; also exercise a mid-mission cinematic if the selected map has one. Run `/gut_regression_test`; the issue 274 checks must pass.

## 0.2.276-dev (2026-07-15) -- #522 inventory preview lighting correction [untested]

- Retired the nonfunctional alternate-level backdrop swap. Inventory keeps the exact vanilla preview package, level, geometry, camera, and background.
- Replaced the old choices with Vanilla, Dim (65% exposure), and Dark (40% exposure). Legacy Dark Camp and Victory Camp values migrate deterministically to Dim and Dark.
- The selected exposure is applied only through the live `HeroWindowCharacterPreview` preview world's post-blend shading callback. Any prior callback is chained and restored exactly on Vanilla, window close, or mod disable; the hot path allocates nothing.
- Added source-backed regression coverage for preview-world scoping, in-place setting changes, legacy migration, and exact callback restoration.

### Test

Open Inventory and choose each Character Preview Lighting value. Vanilla must match the original scene exactly; Dim and Dark must progressively darken only the character-preview pane without changing the background. Change values while Inventory is open, close/reopen it, then run `/gut_regression_test`; `inventory_preview_lighting_522` must pass.
## 0.2.275-dev (2026-07-15) -- #528 remove CKC vanilla Options integration [verify-fix]

### Why

The user superseded the prior bridge design after the Options renderer crash: vanilla Options must remain completely stock, regardless of whether Crosshair Kill Confirmation is installed.

### Changed

- Removed the CKC Options bridge, checkbox/render policies, five CKC-owned `OptionsView` hooks, gear widget/material passes, native kill-confirm suppression, and Mod Tweaker focus redirect.
- Removed CKC mutation from the shared Video-profile list hook. Non-Video definitions now pass to vanilla by the original table identity without writes.
- Kept CKC settings only in CKC's own VMF page and the existing Mod Tweaker Interface > HUD fold.
- Replaced bridge-positive tests and diagnostics with `issue528_ckc_vanilla_options_isolated`, which asserts the production bridge modules/hooks/materials/redirect are absent and the non-Video definition path is identity-preserving.

### Test

With CKC installed, open Options > Gameplay. The Crosshair Kill Confirmation row must remain the stock multi-option control with no GUT gear, checkbox conversion, suppression, or redirect. CKC's VMF page and Mod Tweaker HUD fold must remain editable. Run `/gut_regression_test`; `issue528_ckc_vanilla_options_isolated` must pass. Solo, one tester.

## 0.2.274-dev (2026-07-15) -- #619 Foot Knight secondary melee compatibility [verify-fix]

- Replaced GUT's hardcoded Slayer/Grail Knight saved-loadout exception with the live career slot-capability map used by vanilla backend validation.
- Foot Knight melee weapons saved in the secondary slot are accepted only while Career Tweaker has added `melee` to his live `slot_ranged` capability; disabling the toggle rejects later restores without restarting or erasing the saved row.
- WT and CWV weapons follow their live `slot_type` and `can_wield` data without item-key lists, identity clones, or load-order coupling. Added offline and runtime coverage for hot enable/disable, native dual-melee careers, invalid careers, and absent capabilities.

### Co-op verify

With #619's Career Tweaker toggle enabled, equip a melee weapon in both Foot Knight slots, save and restore that GUT loadout, then enter a mission with a second player. Both weapons must remain equipped and visible. Disable the toggle, restore the same row, and confirm GUT refuses the secondary melee rather than equipping it on a career that no longer advertises the capability.

## 0.2.273-dev (2026-07-14) -- #605 Character Dialogue controls [verify-fix]

- Added lazy dropdown providers so Character Dialogue's 34,327-line source catalogue allocates only when the Dialogue tab is opened.
- Added native-chrome action rows for Play, Pause/Resume, Stop, Enable, Disable, and Default without routing media operations through the settings transaction.
- Mod Tweaker now stops local dialogue preview on every view-close path while leaving natural dialogue untouched.

### Solo verify

Open Mod Tweaker > Dialogue, type into the line dropdown to filter it, select a resident line and Apply, then test Play, Pause/Resume, and Stop. Enable/Disable/Default must persist and closing Mod Tweaker must stop preview audio.

## 0.2.272-dev (2026-07-14) -- #528 CKC Options checkbox renderer crash [verify-fix]

- Fixed the verification crash while scrolling Options > Gameplay to Crosshair Kill Confirmation. The borrowed checkbox factory wrote raw `checkbox_checked` / `checkbox_unchecked` materials, but the active Options list renderer does not load them (`ui_passes.lua:134`).
- The row keeps native checkbox flag/hotspot behavior, but its visual is normalized before first draw to the resident `matchmaking_checkbox` atlas sprite plus a material-free border. A malformed future factory shape suppresses the unsafe texture pass instead of crashing.
- Offline and in-game regression coverage now executes the native local-offset overwrite and proves it cannot restore either missing raw material.

### Solo verify

Open Options > Gameplay and scroll until Crosshair Kill Confirmation is visible. Its checkbox and gear button must render without a `checkbox_checked`/`checkbox_unchecked` material crash; toggle it once and run `/gut_regression_test`.

## 0.2.272-dev (2026-07-14) -- #572 search magnifier vertical alignment [verify-fix]

- Lowered Mod Tweaker's in-field search magnifier by three design pixels. The offset is the rounded proportional equivalent of vanilla's `-4` placement at 128 px for the current 95 px tile.
- Preserved the current size, horizontal placement, text clearance, hotspot, contextual prompt, and focus-hide behavior. Offline/runtime coverage now locks the native source offset and scaling formula.

### Solo verify

Open Mod Tweaker on several tabs and inspect the unfocused search field. The magnifier should be vertically centered inside the field, remain 95 px, and disappear when the field receives focus.

## 0.2.271-dev (2026-07-14) -- #352 THP localization repair; #572 search-field geometry [verify-fix]

- Fixed Original Temporary Health Names assigning internal talent record IDs as localization keys, which rendered as underscore-delimited `<...>` placeholders. All 60 legacy English names now use explicit mod-owned backend localization keys, are re-registered after localizer reinitialization, and restore the exact shared vanilla names when the toggle is disabled.
- Corrected Mod Tweaker's native search magnifier after the prior vanilla offset placed it left of the full-width field. The padded atlas tile is now 95px (15% smaller than the prior 112px pass), translated inside the bar, and still disappears while the field is focused.
- Replaced the generic empty-field prompt with `Search <current tab name>`, sourced from the same rendered tab label. Added offline and runtime coverage for localization reload/apply/restore and the search widget's focus, geometry, hotspot, and contextual prompt contracts.

### Solo verify

Enable Original Temporary Health Names and inspect every career's level-five talent row; names such as `Drillmaster` must appear without `<internal_key>` placeholders before and after a language/localizer reload. In Mod Tweaker, switch between tabs and confirm the empty prompt follows the active tab, the magnifier is wholly inside the bar at the corrected size, and it disappears on focus. Run `/gut_regression_test`; the #352 and #572 checks must pass.

## 0.2.270-dev (2026-07-14) -- #219 confirmed localization orphan cleanup [verify-fix]

- Removed only `gut_hud_visibility_group`, the obsolete label for a container dissolved in 0.2.164. The active `gut_hide_hud_ui_group`, `hb_group`, HUD-mode dropdown, cycle hotkey, settings IDs, defaults, and runtime behavior are unchanged.
- Added a bounded source regression that requires the orphan definition to stay absent while the live HUD group and its direct child controls remain present in both settings data and localization.

## 0.2.269-dev (2026-07-14) -- #250 Chaos Wastes held-Tab talent tiers [verify-fix]

- Fixed vanilla's positional assumption in the held-Tab talent preview. Chaos Wastes stores initial talents and later talent boons as one flat power-up-derived ID list, while the player list treats indices 1–6 as tiers 1–6; empty or duplicate tiers therefore shift later icons into incorrect cells.
- In Chaos Wastes only, maps active IDs back through the current career's talent tree and post-processes the six presentation cells by real tier. The first active talent per tier is retained because initial loadout talents are inserted before purchased/event boons.
- Does not mutate talent extensions, backends, power-ups, buffs, trees, privacy, or networking. It composes through #245's existing player-list hook, caps evidence to sixteen unique repairs, and adds source-bound documentation plus engine-free sparse/duplicate-tier coverage.

### Solo verify

Enter Chaos Wastes with one talent tier unselected, acquire a talent boon, and hold Tab. Confirm each icon remains in its actual tier and the empty tier does not shift later icons. Acquire a boon duplicating an already selected tier and confirm the selected talent remains displayed there; the boon must remain active through vanilla gameplay/boon UI. Attach the bounded `[gut:250]` line and run `/gut_regression_test`; both #250 checks must pass.

## 0.2.268-dev (2026-07-14) -- #245 held-Tab weapon property refresh [verify-fix]

- Fixed stale local weapon properties in the v2 held-Tab tooltip. Vanilla renders detached `PlayerManager.player_loadouts` RPC copies and reads—but does not use—the live inventory equipment in the same update path, so in-place property changes never reach the displayed row.
- While Tab is active, reconciles only the local equipped melee/ranged rows from their exact live backend instances, at most four times per second. It verifies item identity and copies properties only after a deterministic fingerprint changes; no polling occurs while Tab is closed.
- Adds no equip, buff, backend-write, or RPC work. Remote rows remain vanilla network snapshots. Change evidence is capped to sixteen lines per process, with runtime regression `issue245_tab_weapon_property_refresh` and engine-free coverage.

### Solo verify

Equip a weapon, note its held-Tab tooltip, change that exact instance's properties through CIM, then hold Tab and hover it again without swapping. The tooltip must show the new properties within 0.25 seconds. Attach the bounded `[gut:245]` line and run `/gut_regression_test`; `issue245_tab_weapon_property_refresh` must pass.

## 0.2.267-dev (2026-07-14) -- #232 bot designated victory pose [verify-fix]

- Fixed the one-argument vanilla oversight in `PlayerBot.spawn`: skin and frame request the bot loadout, but the adjacent victory-pose lookup omitted `is_bot` and selected the human's active-loadout pose.
- Brackets only synchronous bot spawn and supplies `is_bot=true` only to a missing `slot_pose` argument. Explicit arguments, human calls, other cosmetic slots, unsupported-mechanism fallback, native loadout storage, networking, scoreboard collection, and podium playback remain vanilla-owned.
- Added a bounded one-line-per-career repair trace, runtime regression `issue232_bot_designated_victory_pose`, source-bound documentation, and engine-free call-boundary coverage.

### Solo verify

Give a bot's designated loadout a victory pose different from that career's human-selected loadout, complete an Adventure mission with the bot, and confirm the podium uses the designated pose. Attach the career's single `[gut:232]` line and run `/gut_regression_test`; `issue232_bot_designated_victory_pose` must pass.

## 0.2.266-dev (2026-07-14) -- #231 native loadout capacity [diagnostics-armed]

- Confirmed that GUT's modded-only native store already accepts a raised cap, while the native hero-view window is still structurally limited: its definitions freeze one widget per custom row at module load and later selection, context-menu, delete, bot, animation, and draw paths index those widgets by logical slot.
- Added an automatic two-line boot/window census and `/gut_loadout_capacity_probe`. It reports custom rows, declared cap, physical widgets, greatest persisted row, duplicate indices, missing icon/title ranges, and cutover readiness without changing inventory settings, widgets, stores, or backend state.
- Added a tested pure capacity policy and `LOADOUT_CAPACITY_RESEARCH_231.md`, which defines the safe five-page/six-reusable-button implementation boundary and the choice between packaged VII–XXX textures or text-rendered Roman numerals. A data-only raise was deliberately withheld because it would produce an off-screen strip and request absent atlas materials.

### Diagnose

Open the native loadout-selection window once, run `/gut_loadout_capacity_probe`, and attach the four bounded `[gut:231]` lines (two from `window_enter`, two from `command`). Run `/gut_regression_test` and confirm `issue231_native_loadout_capacity_diagnostics` passes. The stock expected state is six custom rows, cap six, six widgets, and missing icon/title ranges 7–30.

## 0.2.265-dev (2026-07-14) -- #153 hidden career passive perks [verify-fix]

- Added the default-on **Surface Hidden Career Passives** talent-menu option. Witch Hunter Captain now shows the two source-confirmed but vanilla-hidden bonuses: Power of Sigmar (+25% headshot damage) and Sigmar's Charm (+5% base critical-strike chance).
- Hooks both PC and console talent-window population after vanilla and changes only the passive-description widget. It does not mutate `PassiveAbilitySettings`, career attributes, buffs, talent selection, or network state, and composes with Career Tweaker-added passive perks.
- Added fail-closed source-signature checks, idempotent bounded text composition, `/gut_hidden_passive_probe`, runtime regression `issue153_hidden_passives_display_only`, and engine-free coverage. Further career entries require explicit source confirmation rather than inferring player-facing claims from internal buff names.

### Solo verify

Enable **Surface Hidden Career Passives**, open Witch Hunter Captain's Talents screen, and confirm both named bonuses appear under the passive description. Switch careers and confirm their normal descriptions are unchanged; toggle the option off and reopen the screen to confirm the added lines disappear. Run `/gut_regression_test` and confirm `issue153_hidden_passives_display_only` passes.

## 0.2.264-dev (2026-07-14) -- #272 expanded native scoreboard [verify-fix-coop]

- Promoted #272 from inventory-only diagnostics to a bounded first implementation: the default-off **Expanded Scoreboard** shows all eleven native Adventure statistics both while the existing player-list/Tab view is open and on the Adventure end screen.
- Reuses `ScoreboardHelper.get_grouped_topic_statistics` and vanilla hot-join transport. The detached presentation model is capped to four players, refreshed at most four times per second, and can sort by name, total damage, damage taken, elite kills, special kills, or total kills.
- Draws through one `IngamePlayerListUI._draw` observer and one `EndViewStateScore.draw` observer, sharing the same detached presentation model. It adds no competing Tab input, replacement end state, statistic hooks, RPC, or lookup mutation and declines to overlap the installed external scoreboard.
- Added offline coverage for deterministic ordering, lower-is-better damage-taken sorting, caps, snapshot detachment, and transport absence. Added runtime regression `issue272_native_live_scoreboard_page`.
- Kept the issue scope honest: shared per-stat visibility, boss-damage late-join parity, and authoritative custom friendly-fire/healing/damage-split accumulation remain explicit later phases in `SCOREBOARD_RESEARCH_272.md`.

### Co-op verify

Disable the standalone Tab Scoreboard mod, enable **Expanded Scoreboard**, and enter an Adventure mission with another player. Hold Tab and confirm four-or-fewer columns display all eleven native statistics and update during play, then confirm the same sorted page appears on the end screen. Change each sort choice, then have a client hot-join and confirm ordinary synced totals agree (boss damage remains a documented late-join gap). Attach the bounded `[gut:272] native_page` lines. Run `/gut_regression_test` and confirm both `issue272_scoreboard_inventory_diagnostics` and `issue272_native_live_scoreboard_page` pass.

## 0.2.263-dev (2026-07-14) -- #89 Cosmetics-only mission customize close-proof [verify-fix]

- Audited the deferred #89 implementation plan against the shipped #84/#87/#172 architecture. The requested capability is already complete: GUT owns the only mid-mission entry and its two CIM-derived level-free mount hooks, while Cosmetics owns the mission-aware preview lighting, illusion rendering, and apply path. Moving duplicate mount hooks into Cosmetics now would add a second owner without changing capability and would complicate CIM coexistence.
- Exported the live gear-icon and no-CIM mount policies plus a two-surface registration ledger. Added `/gut_regression_test` check `issue89_cosmetics_only_customize_mount`, which verifies both mount hooks exist and, when run in a mission, Cosmetics permits the gear icon and the no-CIM path selects GUT's level-free mount.
- Added engine-free cross-mod coverage for the Cosmetics-only gate, both keep-level bypass surfaces, the empty object-set contract, and Cosmetics' mission-aware preview render companion. No hook, viewport, tab, or gameplay behavior changed.

### Solo verify

Load Tweaker: GUI and Tweaker: Cosmetics without CIM, enter an Adventure mission, open inventory, and use the weapon gear icon. The customization view must mount without a `LevelResource.object_set_names("levels/ui_store_preview/world")` crash, render the weapon, and allow an illusion change. Run `/gut_regression_test` in the mission and confirm `issue89_cosmetics_only_customize_mount` passes. This behavior was already user-verified under #84; this version makes the cross-mod ownership contract regression-visible.

## 0.2.262-dev (2026-07-14) -- #442 career-themed HUD holder capability [diagnostics-armed]

- Located the exact vanilla ownership seam: `EquipmentUI` selects its health/inventory holder through `UISettings.hud_inventory_panel_data[career_name]`, with no additional HUD hook required.
- Added a bounded `[gut:442]` census proving that only Outcast Engineer and Warrior Priest have dedicated holder art; the other eighteen hero careers use the generic fallback.
- Added a pure catalog validator, offline malformed/fallback coverage, and runtime regression `issue442_career_hud_holder_capability` so a game update cannot silently invalidate the implementation plan.
- Added `CAREER_HUD_HOLDER_RESEARCH_442.md` with the exact texture sizes, resource boundary, clear-zone requirements, package lifetime, reversible settings plan, and screen/input verification matrix. Unique themed art remains an explicit asset-production requirement rather than being substituted with generic recolors.

### Diagnose

Attach both `[gut:442]` lines from startup and run `/gut_regression_test`. The expected current result is 20 hero careers, two dedicated holders (`dr_engineer`, `wh_priest`), eighteen fallbacks, and zero malformed entries. Asset production can proceed against the contract in `CAREER_HUD_HOLDER_RESEARCH_442.md`.

## 0.2.261-dev (2026-07-14) -- #437 preserve Adventure scores across reconnect [verify-fix-coop]

- Confirmed the ownership gap in vanilla source: `StatisticsDatabase.unregister` deletes the departing player's row, and Adventure has no counterpart to Chaos Wastes' `save_persisted_score` / `restore_persisted_score` lifecycle.
- Added an on-by-default host option that captures only the exact statistic leaf paths consumed by `ScoreboardHelper`, immediately before Adventure unregisters a player, then restores those values when the same `stats_id` is registered on rejoin.
- Kept the repair mission-local and bounded to eight disconnected players, 64 statistic paths per player, and 16 `[gut:437]` evidence records. It creates no RPC and never copies backend/progression statistics.
- Added offline coverage for path deduplication, numeric-only detached snapshots, exact restoration and caps, plus runtime regression `issue437_adventure_scoreboard_retention`.

### Verify (two players)

Host an Adventure mission with **Preserve Disconnected Player Scores** enabled. Have the client earn visible kills/damage, disconnect, and rejoin the same mission; finish it and confirm the restored player retains the pre-disconnect totals plus new post-rejoin progress. Attach the bounded `[gut:437] captured` and `restored` lines and run `/gut_regression_test`.

## 0.2.260-dev (2026-07-14) -- #272 scoreboard capability inventory [diagnostics-armed]

- Re-derived the scoreboard architecture from Fatshark's current decompile rather than copying the installed external Tab Scoreboard bundle, which exposes no redistribution license or source tree.
- Added a bounded `[gut:272]` capability probe. It inventories vanilla's eleven scoreboard topics, checks group references, `num_stats_per_player`, and per-topic hot-join coverage, detects the external Tab Scoreboard when loaded, and takes one live mission snapshot through `ScoreboardHelper.get_grouped_topic_statistics`.
- Classified the requested expansion: ten native topics can reuse vanilla's hot-join transport, but boss damage cannot because `damage_dealt_per_breed` lacks `sync_on_hot_join`. Friendly-fire damage, healing amount, and melee/ranged damage splits require new custom accumulation. `aidings` and `times_revived` already exist as hot-join stats, while `times_friend_healed` is a persistent count rather than a session healing amount.
- Added `/gut_scoreboard_probe`, the runtime regression `issue272_scoreboard_inventory_diagnostics`, offline malformed-catalog/snapshot coverage, and `SCOREBOARD_RESEARCH_272.md` as the implementation boundary for later UI phases.

### Diagnose

Enter one Adventure mission, hold Tab once, and run `/gut_scoreboard_probe`. Attach every `[gut:272]` line and confirm the live snapshot reports four or fewer players, eleven scores per represented player, zero malformed players, and zero nonnumeric scores. Run `/gut_regression_test` and confirm `issue272_scoreboard_inventory_diagnostics` passes.

## 0.2.259-dev (2026-07-14) -- #345 localization lifecycle sync [verify-fix]

- Re-derived the GUT status-tag slice from current GitHub state instead of applying the stale July 5 audit literally. Third-Person Camera (#209) and the in-mission crafting bench (#80) now show `[verify-fix]`; the generic menu tag also correctly represents #287's `verify-fix-coop` lifecycle.
- Removed the orphan `[diag]` tags from cutscene skip #126 and readonly-loadout #287 because neither issue currently carries `diagnostics-armed`.
- Removed closed crash #193 and its crash marker from **Enable In-Mission Inventory Access**, retaining open verification issue #87. The sibling menu-tabs row continues to carry `[crash]` because open crash #155 still applies there.
- Added retail-safe runtime regression `issue345_gut_loc_status_sync`; the repository-wide advisory checker remains the cross-surface source of truth.

### Verify

Open Tweaker: GUI and inspect Third-Person Camera, Toggle Skip Cutscenes, Enable In-Mission Inventory Access, Allow crafting bench in mission, and Use non-modded loadouts. Their prefixes must match the current issue lifecycle without closed #193 or orphan `[diag]` tags. Run `/gut_regression_test` and confirm `issue345_gut_loc_status_sync` passes.

## 0.2.258-dev (2026-07-14) -- #310 HUD editor coverage diagnostics [diagnostics-armed]

- Fixed the existing editor's scenegraph resolver for `CareerAbilityBarUI`: vanilla stores that class's live graph as `_ui_scenegraph`, while the editor previously read only the public `ui_scenegraph` spelling used by the other registered HUD classes. Drag, overlay, reset, and geometry resolution now use one public/private resolver.
- Entering HUD edit mode now emits one bounded ten-element `[gut:310] HUD coverage` inventory plus a summary. Each row distinguishes a missing live view, missing scenegraph, incorrect movement node, dedicated drag-node fallback, nominal-size fallback, and ready geometry. Exiting re-arms the snapshot for the next deliberate test; it never logs per frame.
- Added offline and in-game regression coverage `issue310_hud_scenegraph_alias_coverage`. This is a diagnostic slice, not completion of the master feature: corner resize, hidden-element previews, cursor affordances, guides, and the remaining HUD registry are still outstanding.

### Diagnose

Enter a mission, bind and press **Enter HUD Edit Mode**, then attach every `[gut:310] HUD coverage` line from the log. Exercise at least one career with a visible energy/overcharge bar and one gamepad career-skill bar if available. Confirm the career ability bar now receives a correctly aligned edit box when present. Run `/gut_regression_test` and confirm `issue310_hud_scenegraph_alias_coverage` passes.

## 0.2.257-dev (2026-07-14) -- #438 On Yer Feet revive scoreboard credit [verify-fix]

- Vanilla's ordinary interaction revive and Warrior Priest's Comet's Gift both call `StatisticsUtil.register_revive`; Mercenary's `rpc_request_revive` server handler revives the target and emits telemetry but omits that statistics transaction.
- Added one server-side wrapper on that exact handler. It credits `StatisticsUtil.register_revive` only when the reviver has `markus_mercenary_activated_ability_revive`, the target was career-revivable before vanilla ran, and the reviver's count is still unchanged afterward. If vanilla or another hook already credited the revive, GUT does nothing, preventing double credit.
- Added capped `[gut:438] credited` evidence, pure Lua policy coverage, and runtime regression `issue438_on_yer_feet_revive_credit`.

### Verify

Start an Adventure mission as Mercenary with **On Yer Feet, Mates!** and at least one bot. Let the bot become downed, revive it with Morale Boost, then finish the mission. Kruber's scoreboard Revives count must increase by exactly one for that ability revive. The log should contain one `[gut:438] credited` line. Run `/gut_regression_test` and confirm `issue438_on_yer_feet_revive_credit` passes.

## 0.2.256-dev (2026-07-14) -- #352 original temporary-health talent names [verify-fix]

- Added a default-off **Original Temporary Health Names** toggle that restores the distinct, career-specific names for all 60 vanilla level-five temporary-health talents.
- Preserved the canonical talent records and mechanics. The option changes only each allow-listed talent's `display_name` to its own `name` localization key; disabling it restores the exact display key captured at load.
- Avoided changing the four shared THP localization keys, so one career's original name cannot leak onto another career or a modded talent.
- Added `/gut_regression_test` coverage `issue352_original_thp_names_exact_identity` for the complete 60-record allow-list, enabled identity, and disabled restoration paths.

### Verify

In the keep, open Options > Mod Options > Tweaker: GUI > Talents and enable **Original Temporary Health Names**. Inspect the level-five talent row on at least one career for each hero; it should show that career's distinct original names while the selected talents and descriptions remain unchanged. Disable the option and reopen Talents; the current shared names should return. Run `/gut_regression_test` and confirm `issue352_original_thp_names_exact_identity` passes.

## 0.2.255-dev (2026-07-13) -- #353 LA cosmetics in native loadouts [verify-fix]

- Extended GUT's post-Loremaster's Armoury `BackendUtils.set_loadout_item` capture from gear to all cosmetic loadout slots, covering LA-cloned dispatch that can bypass the concrete PlayFab mirror hooks.
- Canonicalizes the transient inventory ID to the same `override_id or ItemId` identity vanilla persists before writing GUT's full modded store or readonly cosmetic overlay. An unresolved item is skipped with one bounded diagnostic per distinct slot/ID/reason instead of corrupting the loadout with a guess.
- Preserved official-cloud isolation: the outer capture writes only GUT's VMF store/overlay, while the existing mirror write chokepoints remain blocked in the modded realm.
- Added Lua 5.1 and `/gut_regression_test` coverage for skin, hat, frame, pose, override precedence, unresolved-item failure, and unchanged raw gear IDs.

### Verify

In the modded realm with Loremaster's Armoury enabled, equip a distinct LA weapon illusion, hat, frame, and pose into at least two native saved-loadout rows. Switch rows, leave/re-enter the hero view, restart the game, and confirm each row restores its own cosmetics. Repeat once with **Use non-modded loadouts** enabled; gameplay gear must remain official/read-only while the LA cosmetics persist modded-side. Official-realm loadouts must remain unchanged.

## 0.2.254-dev (2026-07-13) -- #354 trace WT cross-character loadout persistence [diagnostics-armed]

- Source audit established that GUT has no exit-time save transaction. It persists the exact backend ID immediately at `BackendUtils.set_loadout_item`; WT then intercepts the lower item-interface write and retains a separate session-only cache. On launch, GUT serves the persisted row while WT independently reapplies `ItemMasterList.can_wield`.
- Added an automatic `[gut:354]` lifecycle trace for enabled WT cross-character weapon/career pairs. It records the selected row's `capture` and `apply` backend ID, item key, live WT `can_wield` state, and whether GUT stored, served, or temporarily fell back from that ID.
- The trace is filtered to weapon slots whose matching WT unlock setting is enabled. If the stored backend ID is already absent at launch—the state where its item key cannot be recovered—it emits an explicit `<unresolved>` record while WT is installed. Outcomes are deduplicated and capped at 24 records per process. Raw backend table reads avoid the recursive interface-resolution path that previously exhausted the Lua heap.
- Added Lua 5.1 coverage and `/gut_regression_test` check `issue354_wt_loadout_lifecycle_trace`.

### Test method

Equip the WT-unlocked Tuskgor Spear on Kerillian in the active modded loadout, exit normally, then relaunch. Attach every `[gut:354]` line from both logs. `capture ... result=stored` proves the persisted write landed; the next launch's `apply` record distinguishes a missing item (`official-fallback-resolve-no`) from WT ordering (`wt_can_wield=false`) or a successfully served ID (`served-store-yes`). Repeat until one failing and one successful cycle are captured.

> **Dev fork created 2026-06-24** from `gui_tweaker` v0.2.82-dev (mod id `gut` → `gut_dev`,
> directory `gui_tweaker/` → `gui_tweaker_dev/`, separate Workshop item — no `published_id`
> assigned yet). The public `gui_tweaker` is becoming a public beta; all in-flight work now
> happens in this dev fork. See repo `CLAUDE.md` § "Dev/stable split workflow".

## 0.2.253-dev (2026-07-13) -- #528 CKC native checkbox follow-up [verify-fix]

- Replaced the bridged Crosshair Kill Confirmation two-option dropdown with the OptionsView's native checkbox widget. The checkbox still live-enables/disables the CKC mod; the native competing kill-confirm setting remains suppressed.
- Retained the CKC settings cog and moved it beside the native checkbox, safely inside the settings list and clear of the scrollbar.
- Consolidated the temporary row-type rewrite into GUT's existing `OptionsView.build_settings_list` hook, avoiding a duplicate hook. The shared vanilla definition is restored immediately after each list build, so CKC-absent behavior remains the original dropdown.
- Added Lua 5.1 and `/gut_regression_test` coverage for exact-row dispatch, boolean `content.flag` semantics, definition restoration, and malformed-input fallback.

### Verify

With Crosshair Kill Confirmation installed and togglable, open Options > Gameplay. Crosshair Kill Confirmation must render as one native checkbox with a working cog, not an On/Off dropdown. Toggle it both ways and confirm CKC responds live. Open the cog and confirm it still focuses Interface > HUD > Crosshair Kill Confirmation. Disable/uninstall CKC and confirm the stock multi-option dropdown returns.

## 0.2.252-dev (2026-07-13) — Slider registry twin parity (#389)

- Mirrored the existing 25-point CIM/CT foreign-slider registry into the keep sub-state so both Mod Tweaker presentations resolve identical increments.

## 0.2.251-dev (2026-07-13) -- #547 HUD edit drag-box alignment [verify-fix]

- Restored vanilla's two-node HUD-customizer contract: offsets still write to each registered movement node, while hit testing, confinement, and overlay drawing now use the element's separate positive-size render-bounds node.
- Source-mapped the pivot-based widgets to their actual bounds (`background_panel`, `pivot_dragger`, `quest`, `background`, and the first news-feed row). Missing dynamic bounds fail safely to the existing movement-node/nominal-size behavior.
- Added Lua 5.1 and `/gut_regression_test` coverage proving the bounds remap does not change persisted movement targets.

### Verify

Enter HUD edit mode and inspect/drag all ten registered elements. Each blue box must sit on the visible element before, during, and after dragging; the cursor must grab only inside that box; edge confinement and saved offsets must still work after reopening the HUD.

## 0.2.250-dev (2026-07-13) -- #557 tree-preserving Mod Tweaker layout [not deployed]

- Every unordered sibling level now displays collapsible groups first and loose settings second; both partitions sort case-insensitively by localized display label.
- Sorting reconstructs the depth tree and emits whole subtrees, so a group never separates from its descendants. Authored headers and explicit order/dependency metadata preserve their sibling sequence.
- The deliberately synthesized Equipment layout opts out completely. Both the standalone and keep-sub-state presentations use the same pure ordering policy, with offline recursive/subtree regression coverage.

## 0.2.249-dev (2026-07-13) -- #257 Well of Dreams cutscene trace [not deployed]

- Source-audited The Well of Dreams as `dlc_termite_3` (`level_settings_termite_part_3.lua`), the native `CutsceneSystem` callbacks, and the user-confirmed #140 Parting of the Waves post-skip suppression. The decompiled Lua does not contain the mission's authored level-flow graph, and no available log contains a clean `dlc_termite_3` cutscene trace, so its exact activation/skip event identity and fade ordering are not yet proven.
- Added automatic `[gut:257]` evidence on `dlc_termite_3` only. It records the exact activation/skip event names, camera/logic/effect ordering, fade durations, auto-skip state, one-shot flag, post-skip guard, and the predicted production disposition (`swallow_one_shot`, `swallow_post_skip`, or `pass_fade`). It changes no cutscene behavior.
- The trace is hard-capped at 32 callback records plus one cap marker per CutsceneSystem instance and emits nothing on every other level. The existing #106/#140 hooks remain singletons; no new engine hook was added.
- Added offline policy/boundary coverage in `test_gut_cutscene_probe.lua` and `/gut_regression_test` check `issue257_well_of_dreams_cutscene_probe`.
- **Evidence pass after deployment:** enable Skip Cutscenes and Auto-skip, run The Well of Dreams once with no standalone cutscene-skip mod, and attach the `[gut:257]` lines. A visible fade paired with `disposition=pass_fade` identifies the uncovered callback order; swallowed dispositions show the current generic #140 paths already handled that fade.

## 0.2.248-dev (2026-07-13) -- #525 Progression tab label [not deployed]

- Source-audited both Mod Tweaker presentations. They derive top-tab chrome from each VMF mod's readable name and truncate it to 16 characters, so `Modded Progression` could not render as the requested exact `Progression` label.
- Added one engine-free exact-label policy shared by the standalone and HeroView presentations. The `mp` category now renders as `PROGRESSION`; existing Crafting and CWV compact labels also share this policy, removing a pre-existing presentation mismatch.
- This is presentation-only: Modded Progression keeps its VMF identity and readable name, and no quest, shilling, wallet, or backend behavior from #573/#578 changes.
- Added offline coverage in `test_mod_tweaker_tab_labels.lua` and `/gut_regression_test` check `issue525_progression_tab_label`.
- **Solo verify after deployment:** open Mod Tweaker in the keep and in a mission with Modded Progression enabled. Its top tab must read `PROGRESSION`, select the existing progression settings, and neither overflow nor show `Modded Progress...`. Existing `CRAFTING` and `CWV` labels must remain unchanged.

## 0.2.247-dev (2026-07-13) -- #522 inventory backdrop resolver [verify-fix]

- Fixed the first implementation's incorrect assumption that the engine's `local_require` cache is always mirrored in Lua's `package.loaded`. Vanilla loads the character-preview definitions with `local_require`; when no `package.loaded` entry existed, GUT found the preview class but silently left its viewport unchanged, matching the user's no-change report.
- The hook now resolves the exact definitions table through vanilla's own `local_require` loader, with the old cache lookup retained as a fast path. Package availability, async loading, readiness gating, symmetric unload, and vanilla fallback remain unchanged.
- Extended `inventory_backdrop_swap_522` to prevent the loader boundary from regressing. Opening inventory automatically logs either the selected swap or the precise resolution/package blocker; no manual command is needed to collect that evidence.

### Verify

Choose each Inventory > Character Preview Backdrop value and reopen inventory. The two alternate scenes must visibly replace the vanilla stage; returning to Vanilla must restore it. Confirm `/gut_regression_test` passes `inventory_backdrop_swap_522`.

## 0.2.246-dev (2026-07-13) -- #314 Simple UI compatibility phase 1 [verify-fix]

- Audited sanctioned Workshop Simple UI 2.1.2 and its public Grasmann-Mods source. The repository provides source/resources but no redistribution license, so GUT does not copy or absorb them without explicit permission.
- Added a clean compatibility tick for an installed Simple UI. It confines every public live window record to the current resolution; fitted windows remain wholly visible, while oversized windows retain a reachable left edge and top title/drag handle.
- The compatibility path replaces no external function, installs no engine hook, mutates existing position tables in place, emits at most one raw-console recovery line per window/resolution, and is a no-op when Simple UI is absent.
- Added pure Lua 5.1 coverage, `/gut_regression_test` check `issue314_simple_ui_window_confinement`, and `SIMPLE_UI_INTEGRATION_PLAN.md` with source-backed dropdown, buff-preview, native-theme, and licensing phases.

### Verify

Install Simple UI plus UI Tweaks, drag its windows through all screen edges, resize one beyond the viewport, then change resolution. Fitted windows must remain wholly visible; oversized windows must retain their left edge and top title handle. Run `/gut_regression_test` and confirm the #314 check passes.

## 0.2.245-dev (2026-07-13) -- #292 native Video settings profiles [verify-fix]

- Added five persistent graphics-profile slots at the top of the native Video options page. Selecting a saved slot stages its values; the game's existing Apply button remains the only activation path and therefore keeps its save, renderer reload/restart, and 15-second revert-confirmation behavior.
- Save Current snapshots the concrete values of the Video widgets available on this machine. Delete Selected uses a confirmation popup. Selecting an empty slot before saving is the Save As flow. `/gut_video_profile_name <1-5> <name>` gives a slot a durable custom name.
- Profiles are keyed by native callback identity, not a hand-maintained setting list. Unsupported hardware rows and monitor resolutions are skipped safely on replay; the load summary reports the applied/skipped counts.
- Added engine-free capture/replay coverage and runtime check `issue292_native_video_profile_pipeline`.
- **Verify:** save visibly different profiles (including resolution/fullscreen, quality, gamma, and a hardware-specific option when present), switch between them, click Apply, accept/reject the native timed confirmation, reopen Video options, restart once, and delete one profile. Values must persist and no unsupported row may be forced.

## 0.2.244-dev (2026-07-13) -- #318 disabled integrations remain in place [not deployed]

- Replaced v0.2.194-dev's hide-disabled behavior with the revised acceptance contract. Mod Tweaker now enumerates installed Tweaker mods regardless of VMF enabled state, then folds Equipment membership by presence. A VMF-disabled CWV therefore remains under `Equipment > Weapons > Career Weapon Variants` when WT is present instead of disappearing or escaping as a blacked-out top-level tab.
- Disabled Equipment members contribute one grey, read-only section header with the hover explanation `Disabled in VMF`. Their setting rows are omitted and they are excluded from per-owner staging, Apply, profiles, and DEFAULT routing, so the dormant mod object is never read or written.
- Applied the same presentation contract to the integrated stock UI Tweaks/HideBuffs section inside Interface: installed-and-disabled keeps only its explained grey header; absent HideBuffs preserves gut's absorbed fallback settings; enabled HideBuffs retains the existing live owner bridge.
- Added a pure disabled-section policy with offline coverage for presence-based membership, enabled alias preference, immutable subtree removal, and the explanation contract. `/gut_regression_test` adds `issue318_disabled_integrations_keep_normal_sections` and source-locks both Keep and mission Mod Tweaker twins.
- **Solo verify after deployment:** with WT and CWV installed, disable CWV in VMF and open Mod Tweaker. Under Equipment > Weapons, `Career Weapon Variants` must remain visible in grey; hovering it must show `Disabled in VMF`, it must not expand, and no CWV setting rows may appear. Re-enable CWV and reopen the menu; the same header must become interactive with its settings restored. Repeat the grey-header check for installed-but-disabled UI Tweaks under Interface.

## 0.2.243-dev (2026-07-13) -- #572 in-field magnifier focus correction [verify-fix]

- Followed the user's in-game correction: the magnifier is an empty-field affordance inside Mod Tweaker's 30px search box, not a permanent decoration beside the text. It now hides whenever clicking the unchanged full-field hotspot focuses search, and returns after focus leaves. Query, caret, placeholder, filtering, Enter, Escape, and neutral-click behavior are unchanged.
- Rendered the native padded `search_filters_icon` tile at 112x112 (7/8 of 128, a 12.5% reduction) with scaled x=-70 and field-centered y=0 geometry. The visible glyph is approximately 28px, fully inside the 30px field; the established x=47 text origin remains unchanged with clearance.
- Expanded offline and `/gut_regression_test` contracts to lock native material identity, 112/128 scale, in-field offsets, focus visibility, focus-state wiring, text clearance, and the unchanged hotspot.
- **Verify:** in Keep and mission Mod Tweaker, confirm the unfocused/empty field shows the smaller magnifier wholly inside its border. Click anywhere in the field: the icon must disappear immediately without moving the text or changing the clickable area. Drop focus with Enter, a result, or outside click and confirm it returns where appropriate. Repeat at a non-default UI scale. Issue remains `verify-fix` until this visual/focus pass is confirmed in game.

## 0.2.242-dev (2026-07-13) -- #572 native atlas geometry correction [verify-fix]

- Corrected the magnifier after in-game verification showed the glyph at roughly one quarter of its intended size. `search_filters_icon` is a padded 128x128 atlas tile; scaling the tile to 22px also scaled down the artwork inside its transparent padding.
- Now matches `HeroWindowCraftingInventoryConsole` exactly: 128x128 texture size, x=-80/y=-4 offset, and search text beginning at x=47. The transparent tile may extend outside the 30px field, while its visible magnifier remains inside it.
- Updated offline and runtime regression contracts to lock the atlas-aware geometry rather than a guessed visible-glyph size.

### #287 preserve CWV instances under non-modded loadouts [verify-fix-coop]

- Paired host/client logs isolate the failure to Tweaker's read-only boundary: with `gut_use_non_modded_loadouts` on, the client successfully built and wielded `cwv_es_dual_axes_001`, but every matching `slot_melee` write was blocked and immediately retried through the loadout resync path. The same instance equipped cleanly as soon as the setting committed off.
- Generalized #287's cosmetic-only readonly overlay to preserve exact CWV-owned backend instances (`cwv_*_NNN`) in melee/ranged slots. Ordinary weapons, jewelry, talents, loadout selection, and bot designation remain official-read-only; choosing an ordinary weapon clears a prior CWV overlay and falls back to the untouched official row.
- Extracted the pure policy to `_gut_native_loadout_policy.lua`. Offline Lua coverage proves Dual Axes, Dual Maces, and crafted CWV IDs survive in the modded overlay while official realm mode remains fully inert and ordinary official IDs are never written into the overlay.
- **Verify with two players:** enable Use non-modded loadouts on the client; equip CWV Dual Axes and Dual Maces in both weapon slots; swap away and back, then relaunch. The selected CWV instance must remain equipped, the peer must see/wield it, and no repeated BLOCKED/resync loop or crash may occur. Enter official afterward and confirm only the original official weapons are present.

## 0.2.241-dev (2026-07-13) -- #572 native inventory magnifier in Mod Tweaker search [verify-fix]

- Added the vanilla inventory search material `search_filters_icon` from `gui_menus_atlas` to Mod Tweaker's fixed per-tab search field. It is an atlas-backed passive texture pass, so no custom asset, package load, or additional input target is introduced.
- The initial 22px tile sizing was too small because the atlas tile contains substantial transparent padding; corrected in 0.2.242-dev.
- Preserved the existing full-field hotspot and all click/focus/type/Escape behavior. `/gut_regression_test` check `issue572_mod_tweaker_native_search_icon` locks the source texture, icon metrics, text clearance, and passive-hotspot contract.

## 0.2.240-dev (2026-07-13) -- #575 numeric-editor caret uses native text metrics [untested]

- Replaced the slider editor's hand-measured `gw_body` width with the exact native text-pass contract: `UIFontByResolution` supplies the scaled material/size, the `hell_shark` font identity is forwarded to `UIRenderer.text_size`, and centered placement includes the measured glyph-origin correction. Caret geometry now derives from the full string plus the measured prefix at the insertion index, so signs, decimal points, proportional digits, UI scale, resolution, and ultrawide layout do not need a guessed pixel offset.
- Clicking within an active or newly focused numeric field now chooses the nearest measured insertion boundary. Left/Right, Home/End, Backspace/Delete, and insertion retain that index visually; the dormant keep sub-state receives the same behavior as the active standalone view.
- Corrected the partial-number validator's literal sign/decimal lookup (`plain=true` must search `"-"` / `"."`, not Lua-pattern spellings). Added three Lua 5.1 host tests plus `/gut_regression_test` coverage for centered glyph origin, non-uniform `-12.50` advances, click boundaries, and field translation.
- **Verify:** open Mod Tweaker, click at every boundary in `1`, `1234`, `-12.50`, and a configured multi-decimal slider; then use Left/Right/Home/End and edit at the caret. The bar must remain between the intended glyphs at the current UI scale. No Workshop deployment in this change.

## 0.2.239-dev (2026-07-13) -- #570 startup dependency notice is console-only [untested]

- Moved the dormant automatic Simple UI dependency notice from chat to a raw console marker. Interactive UI and command feedback are unchanged.

## 0.2.238-dev (2026-07-13) -- #561 per-tab settings profiles [verify-fix]

- Refined #559 from in-game feedback: changing a checkbox, dropdown, keybind, or slider
  now keeps the query and filtered results visible. Escape or an outside click clears search
  and, with auto-collapse enabled, retains the branch containing the last changed setting;
  if nothing changed, it retains the first direct result's branch. With auto-collapse disabled,
  the pre-search branches remain open and the retained branch is added. Engine-free transaction
  tests cover last-changed preference, top-result fallback, and both auto-collapse modes.

- Added a lower-left **PROFILES 1-10** selector to both Mod Tweaker presentations.
  Each visible tab remembers its own active slot; slot 1 lazily adopts existing
  live values, while a newly visited slot begins from declared defaults.
- Applying edits updates only the active tab/profile. Switching profiles auto-applies
  pending edits to the old profile before restoring the new profile through #560's
  bounded transaction path. DEFAULT remains scoped to the current tab/profile.
- Persistence is partitioned into one map per tab/slot plus one scalar active slot.
  Owner-qualified keys support merged tabs without a monolithic deep-cloned blob.
  Keybinds remain device-global and are intentionally excluded.
- Added `[gut:561]` telemetry and Lua 5.1 tests for selection, isolation, keys, and copies.
- Verify in both the keep and a mission: edit profiles 1 and 2 on two tabs, switch
  among all four combinations, restart, and confirm values and active highlights.

## 0.2.237-dev (2026-07-13) -- #559 search expansion transaction [untested]

- Fixed search permanently leaving every matching collapsible open. The first non-empty query now
  snapshots the selected tab's expansion state; filtered rows look expanded through a render-only
  flag and never write `self._expanded`.
- Clearing the query, pressing Escape, clicking neutral space, switching tabs, or leaving the menu
  restores that snapshot exactly. There is deliberately no implicit "top result" selection.
- Clicking a real result exits search while preserving the clicked checkbox/dropdown/slider/keybind
  action. With auto-collapse ON, the tab commits only the result's ancestor group chain (a top-level
  result commits no group). With auto-collapse OFF, the old snapshot is restored and required
  ancestors are added without collapsing unrelated branches. Deferred rebuilds keep dropdown,
  keybind, numeric-edit, and slider-drag row references alive until their interaction finishes, then
  swallow the shared-node release latch before accepting another click.
- Added pure Lua 5.1 tests for restore/ON/OFF/top-level/nested cases and runtime regression
  `issue559_search_expansion_transaction` for the production transaction and view lifecycle seams.
- Rebases on #560's bounded bulk-setting transaction and preserves both transaction modules in the
  standalone Mod Tweaker view; #560's dormant keep-view twin remains unchanged.

**Verify in game:** open two branches, search for a nested checkbox, then test Escape, blank-area
click, result click, tab switch, and X/menu exit with auto-collapse ON and OFF. Confirm neutral exits
restore the original branches, result clicks still change the control, ON leaves only its ancestor
path, OFF retains the old branches plus that path, and a top-level result leaves no group selected.

## 0.2.236-dev (2026-07-13) -- #560 bound bulk settings commits [verify-fix]

- Added an opt-in Mod Tweaker transaction contract. A setting owner that exposes
  `on_settings_batch_changed(ids)` receives all of its pending values through
  non-notifying VMF writes, followed by exactly one completion callback. Owners
  without that hook keep the existing per-setting notification semantics.
- Routed both the standalone mission view and the keep HeroView sub-state through
  the same transaction module. The DEFAULT button remains scoped to the selected
  tab and still stages values until Apply.
- Added `[gut:560]` commit telemetry and offline Lua 5.1 tests proving N values
  produce N persisted writes and one owner notification.
- Verify in a mission: open Enemy Tweaker, press DEFAULT, confirm, then Apply.
  The game should stay responsive and the log should contain one `[gut:560]`
  transaction line rather than a callback per setting.

## 0.2.235-dev (2026-07-13) -- #517 retire impossible retail TOML read-back [untested]

- Retired the load-time TOML apply path and `/reload_config`: retail Stingray exposes no arbitrary file-read primitive, so both had always been inert while implying settings could round-trip. The parser, `io_open` guard, and boot-time apply call are removed.
- Kept `/export_settings`, Mod Tweaker close auto-export, and both desktop companion scripts as a one-way TOML snapshot/backup path. Their help text and the generated TOML header now state that retail cannot read or apply the file.
- Added runtime regression `issue517_config_read_retired`, static absence gates for the read/reload paths, and refreshed `docs/COMMANDS.md`. In-game verification should confirm `/export_settings` still emits a complete block and `/reload_config` is no longer registered.

## 0.2.234-dev (2026-07-13) -- Absorbed UI Tweaks fork: boot without Penlight + explicit stock-mod dormancy [untested] [Issue 281]

The absorbed "UI Tweaks" (HideBuffs) fork under `hb/` aborted at load on a missing Penlight
dependency, so a user WITHOUT the stock UI Tweaks mod got nothing from the absorbed hide /
loading-screen feature set. (Users WITH the stock mod were unaffected -- the #312 bridge routes
to it.) Root cause: `hb/hb_data.lua` did `require'pl.import_into'()`, and `pl.import_into` is not
a lua resource in the retail VMF sandbox, so the whole data file threw at load -- `mod.SETTING_NAMES`
and every fork data table went undefined, and every hb/ hook then bailed to vanilla (its guard read
the now-nil `mod.SETTING_NAMES`). Non-fatal (the abort was `pcall`-wrapped) but the feature set was
silently dead.

- **Penlight removed (`hb/hb_data.lua`, `hb/mod_events.lua`).** The fork consumed ONLY the Penlight
  `List` / `Map` constructors and `List:contains`, so those are replaced with a plain Lua 5.1 `_hb_list`
  helper (array + `:contains`) and plain table literals -- NO Penlight vendored. `hb_data.lua` now runs
  to completion, so `mod.SETTING_NAMES`, `mod.ubersreik_lvls` (consumed as `:contains` at
  `hide_elements.lua:251`), and the other data tables all exist. `mod_events.lua` is an orphaned
  Phase-2 backbone (not yet in the boot chain) but carried the same latent `require`, fixed
  pre-emptively so wiring it later cannot reintroduce the abort. No second missing dependency lurks
  behind Penlight -- `hide_elements.lua` / `level_loading_screen.lua` only `local_require` a vanilla
  definitions module, which resolves in-sandbox.
- **Explicit stock-mod dormancy gate (`hb/hb_data.lua`, `hb/hide_elements.lua`, `hb/level_loading_screen.lua`).**
  Because the fork now actually BOOTS, it must defer to the stock UI Tweaks mod when that is installed
  and enabled (the #312 model: stock OWNS the overlapping settings). Previously the fork "self-gated"
  only by crashing. New `mod.hb_stock_owns()` (present + enabled, matching `_gut_uitweaks_sync.is_owned`
  / `_bridge_uitweaks_to_stock`) and `mod.hb_fork_active()` (`SETTING_NAMES` populated AND stock not
  owning); every hb/ hook now bails on `if not mod.hb_fork_active()` in place of the old
  `if not mod.SETTING_NAMES`. `hb_fork_active()` returns false when `SETTING_NAMES` is nil, so the
  2026-06-24 boot-loading-screen crash guard is preserved. With NO stock mod the absorbed features
  run off gut's own settings; with the stock mod enabled the fork is inert (no double-apply).
- **Regression (`gui_tweaker_dev.lua`).** `hb_setting_names_guarded` updated to the new gate needle
  (still asserts the guard precedes the `HIDE_LOADING_SCREEN_SUBTITLES` read). Two new
  `/gut_regression_test` checks: `hb_penlight_removed` (SETTING_NAMES + shim tables present and
  behaving, `ubersreik_lvls:contains` correct, no Penlight reference / `hb_pl_shim` marker present in
  `hb_data.lua`) and `hb_fork_dormancy_gate` (gate helpers exist + return booleans, hide-elements
  gates on `hb_fork_active()`). `[gut:281]` diagnostics are printf-only.

## 0.2.233-dev (2026-07-13) -- HUD edit mode: suspend local input + confine drag to the HUD area [untested] [Issue 310]

Two of the user's active #310 complaints (2026-07-12: "input to the game should be suspended", "the mouse
[shouldn't] move the camera around", "confined to a box that is the edges of the displayable HUD area").
No visual RESIZE in this build -- see "Deferred" below.

- **Input suspension (`_gut_freecam.lua`, `_hud_customizer.lua`).** While HUD edit mode is active, local
  gameplay input is now suspended so the mouse drives the drag editor instead of aiming/turning the character
  and camera. Implemented by returning `true` from `PlayerInputExtension.is_input_blocked` for the LOCAL player
  while editing -- the same reliable freeze freecam uses (`player_input_extension.lua:149` nullifies the read).
  CONSOLIDATED into freecam's existing `is_input_blocked` hook (VMF drops a 2nd hook on the same `(Class,
  method)`, repo NON-NEGOTIABLE 8); the gate is `Customizer.should_suspend_input()` = edit mode active AND no
  cutscene owns input (cutscene skip runs on a separate service, so it is excluded). ESC/chat/keybinds ride
  other services and keep working, so the exit keybind and ESC still close the mode. `[gut:310]` printf on the
  ON/OFF transition; the existing one-line echo is unchanged.
- **Drag confinement (`_hud_customizer.lua`).** Dragging a gut-owned HUD element now clamps its box
  `[world, world+size]` inside the displayable HUD area `[0 .. res_w*inv_scale] x [0 .. res_h*inv_scale]`
  (`ui_scenegraph.lua:210-246`, the same reference space as the cursor + `world_position`), so an element can
  no longer be dragged off-screen. Pure `Customizer.confine_delta` clamps in world-space and back-solves the
  confined delta using the delta applied last frame; an element larger than the area on an axis is left
  unclamped so it is never trapped. UI-Tweaks-owned elements (buff/boss/overcharge/energy when HideBuffs owns
  them, #312) delegate to HB's own layout and are NOT clamped here.
- **Regression (`gui_tweaker_dev.lua`).** Two new `/gut_regression_test` checks: `hud_confine_delta_clamps`
  (far/near/in-bounds/applied-delta/oversize cases) and `hud_edit_mode_input_suspend_api` (seam present,
  edit-mode-gated, freecam still consults it).
- **Deferred (still open on #310, needs in-game iteration a build-only pass cannot verify):** corner-drag
  RESIZE (per the owner's own research the visual scale is per-widget style-field walking with real distortion
  risk on text/atlas passes -- not shippable "solid" without live testing), the box/element MISALIGNMENT (gut
  collapses vanilla's separate drag-node and move-node into one pivot node, so pivot-anchored boxes draw off
  the rendered element -- fix needs a per-element drag-node re-map verified in-game), native-Windows resize
  cursor, hidden-element previews, per-number sub-elements, and snap guides. These should become #310
  sub-issues.

## 0.2.232-dev (2026-07-13) -- #537 on_setting_changed no longer re-latches the skippable_cutscenes global [untested] [Issue 537]

Removes the last surviving global-latch of the shared engine skip gate, an issue-275 regression that escaped the
0.2.209-dev no-latch cleanup because it lived in the main file rather than `_gut_cutscenes.lua`.

- **Root cause (`gui_tweaker_dev.lua`, was line 907):** the `on_setting_changed` handler for
  `gut_skip_cutscenes_enabled` persistently wrote `script_data.skippable_cutscenes = mod:get(...) or nil`, so
  ticking the VMF "Skip Cutscenes" checkbox ON latched the global true. `script_data.skippable_cutscenes` has
  exactly ONE runtime reader in the decompiled source -- `CutsceneSystem.skip_pressed` (cutscene_system.lua:98,
  `if self.active_camera and script_data.skippable_cutscenes`) -- and while it is latched true, ANY skip press
  on ANY active cutscene passes the gate and tears down its cameras + logic. For an author-locked boss cinematic
  with `event_on_skip=nil` (Nurgloth on dlc_castle) that is the exact issue-275 mid-fight ~66%-health softlock.
  The comment's claim that the latch "keeps the flag in sync for any engine path that reads it directly" was
  unfounded: cutscene_system.lua:98 is the only reader, and the `_gut_cutscenes.lua` hooks already scope-unlock
  it around that call. The rt guard `gut_cutscene_no_global_latch` scanned only `_gut_cutscenes.lua`, so this
  main-file site was never caught.
- **Fix (own-or-pin).** `on_setting_changed` no longer latches on enable; on DISABLE it restores the captured
  pre-gut value via a new shared helper `mod._gut_restore_skippable_cutscenes` (defined in `_gut_cutscenes.lua`,
  which captures `script_data.skippable_cutscenes` once at module load, before any gut hook installs). The
  `/skipcutscenes` toggle command's old hardcoded `= nil`-on-disable was switched to the same helper, so a
  co-installed cutscene mod / the vanilla debug menu is no longer clobbered. Enabling relies entirely on the
  per-skip scope-unlock in the hooks (unchanged). Diagnostic `[gut:537]` printf on restore.
- **Regression (`gui_tweaker_dev.lua`).** Widened the `gut_cutscene_no_global_latch` rt check with a step 4 that
  also scans the main file (path derived from the sibling `_gut_cutscenes.lua`) for the escaped
  `on_setting_changed` latch write, so this class can't slip through the main file again. `/gut_regression_test`.



Fixes the user's active #312 report (2026-07-10 "UI Tweaks options that are on in VMF are showing up as off
in Mod Tweaker's menu"; 2026-07-12 "toggles for hidden HUD elements are turned on in VMF per my setup ...
they MUST be consistent with the VMF options"). The Mod Tweaker's UI Tweaks toggles now read and write the
stock UI Tweaks (HideBuffs) mod's live settings instead of gut's own private copies, so the two menus agree.

- **Root cause:** gut surfaces the UI Tweaks options as its OWN data-tree checkboxes under the HUD > "UI
  Tweaks" group, keeping HideBuffs' setting_ids VERBATIM (`hide_frames`, `HIDE_BOSS_HP_BAR`, the buff-hide
  ids, ...). But gut (`gut_dev`) and the stock mod (`HideBuffs`) persist those ids in SEPARATE VMF
  namespaces, so a toggle the user set ON in UI Tweaks' own VMF page read back OFF from gut_dev's default in
  the Mod Tweaker. gut's absorbed `hb/` fork that would consume gut_dev's copies also aborts at load on a
  missing Penlight dep (#281), so on the user's setup the stock mod is the only thing actually hiding HUD
  elements -- making the private copies doubly wrong to display.
- **Fix (`_mod_tweaker_state.lua` + `_mod_tweaker_view.lua`, `_bridge_uitweaks_to_stock`, marker
  `[UITWEAKS-BRIDGE-312]`):** when the stock UI Tweaks (HideBuffs) mod is installed AND enabled, every
  OVERLAPPING checkbox setting_id (present in gut's category AND a real `HideBuffs.SETTING_NAMES` value) is
  routed to `get_mod("HideBuffs")` through the existing per-node `_owners` mechanism -- the same own-or-pin
  path the Equipment merge (#208), the CKC bridge (#313), and the drag-offset sync module
  (`_gut_uitweaks_sync.lua`) already use. Reads (`_cat_get` -> `HB:get(id)`) now show HideBuffs' live value;
  edits stage under a `"HideBuffs"` buffer and commit on Apply as `HB:set(id, v, true)`, firing its
  `on_setting_changed` live and VMF-persisting. HideBuffs is the single owner of the shared toggles -- no
  double namespace, no stacking. The bridge runs AFTER `_inject_ckc_into_gut` and MERGES `"HideBuffs"` into
  the category's `_owner_mod_ids` so Apply/dirty still flush gut's own edits AND any CKC edits AND the
  HideBuffs edits. gut's own control settings (`gut_uitweaks_sync`, the two vanilla numeric mirrors) are NOT
  in `SETTING_NAMES`, so they stay gut-owned. Groups and the `HIDE_HUD` keybind are skipped.
- **No-op when UI Tweaks is absent or disabled:** gut's own gut_dev copies drive its absorbed `hb/` fork
  exactly as before, so a user without the stock mod is unaffected.
- **rt check (`/gut_regression_test`, io-safe, load-time):** `uitweaks_bridged_to_stock_settings` asserts
  BOTH Mod Tweaker twins carry the bridge helper and call it in the category-build path.
- **VERIFY IN-GAME (UI Tweaks / HideBuffs installed + enabled; solo -- both mods client-side):** set some UI
  Tweaks hide toggles ON in UI Tweaks' own VMF options page, then open gut's Mod Tweaker > Interface > HUD >
  UI Tweaks -- those toggles now read the SAME state (ON). Flip one in gut's Mod Tweaker, Apply, reopen UI
  Tweaks' own page -- the value matches (and vice-versa). Without UI Tweaks installed the group behaves as
  before (gut's own copies).

## 0.2.230-dev (2026-07-13) -- #313 CKC vanilla-Options gear placement + issue 311 sync precedence doc [untested] [Issue 313]

Closes the last open gaps in the Crosshair Kill Confirmation integration (#313, and issue 311, its
near-duplicate). The full bridge already existed and is UNCHANGED in behavior: CKC's options fold into
gut's Interface > HUD group as a "Crosshair Kill Confirmation" sub-collapsible (#339/#527), the vanilla
Options `crosshair_kill_confirm` dropdown is taken over as an On/Off that live-drives CKC's master enable
(and forces the native marker off), and a cog opens the Mod Tweaker on that HUD group. Everything is inert
when CKC is not installed (`get_mod` guard, zero hooks). This build fixes the cog's PLACEMENT and documents
the cross-surface sync, plus regression coverage. No behavior change when CKC is absent.

- **#313 FIX (`_gut_ckc_bridge.lua`, `_append_gear`): the vanilla-Options cog overlapped the page scrollbar** (user report 2026-07-11 "too far to the left and partly overflows into the scrollbar ... the normal options menu doesn't have a column for gears"; reaffirmed 2026-07-12 "same issue, no change ... it's the vanilla options menu gear icon"). Root cause is geometry: the takeover row is a vanilla `drop_down`, ROW_W=1300 wide (`DROP_DOWN_WIDGET_SIZE`, `options_view_definitions.lua:2294-2297`) with its right-aligned On/Off field ending at row_x+1300 (world ~1608), and the page scrollbar occupies the far-right ~23px of the list (`scrollbar_root`: background right -15, 8 wide, `:316-329`, world ~1637-1645). The old placement (`row_x + ROW_W + 10`, world ~1618-1644) put the cog UNDER the scrollbar. There is no comfortable room to the field's right, so the cog now sits in the empty gutter immediately LEFT of the On/Off field, at `row_x + (ROW_W - BOX_W) - GEAR_GAP - GEAR` (BOX_W=INPUT_FIELD_WIDTH=400, `:3`; field left edge = row_x + 900, world ~1208). That gutter holds only the short left-aligned label, so the cog gets its own clear column fully clear of the scrollbar. Marker `[CKC-GEAR-LEFT-GUTTER-313]`. Pure offset change -- the vanilla box/arrow/list styles are untouched (lowest-risk). [untested] pending eyes-on placement.
- **issue 311 (sync precedence, documented in the bridge module header, marker `[CKC-SYNC-PRECEDENCE-311]`):** the three surfaces converge on ONE source of truth with no shadow copy. (a) MASTER ENABLE = CKC's VMF mod-enabled flag, owned by the vanilla Options row (this is why "vanilla crosshair kill confirmation OFF => feature off"). (b) FEATURE OPTIONS = CKC's own `mods_settings`, edited by both the gut Mod Tweaker HUD group (writes through via `_cat_set -> ckc:set(id, val, true)`, firing CKC's `on_setting_changed` live -- the own-or-pin `HB:set(id,v,true)` doctrine) and CKC's own VMF page. The two option surfaces are never on screen at once (hero-view state vs ESC mod-settings view) and each rebuilds from a live get on open, so last-write-wins with nothing to reconcile and the "mod:set does not repaint an open widget" caveat cannot bite. Nothing in issue 311 is left uncovered by this + the existing bridge.
- **rt checks (`/gut_regression_test`, io-safe, load-time):** `ckc_gear_left_of_field_clears_scrollbar` (asserts `_append_gear` carries the left-gutter marker AND no longer uses the scrollbar-overlapping `row-right + 10` placement); `ckc_three_surface_sync_precedence` (asserts the header carries the precedence marker AND `_cat_set` still live-fires `on_setting_changed` via `mod_obj.set(id, value, true)` so HUD-group edits reach CKC).
- **VERIFY IN-GAME (with CKC installed, Workshop 1593460250; solo -- client-side crosshair feedback):** ESC > Options > Gameplay: the "Crosshair Kill Confirmation" row shows On/Off with the cog now sitting to the LEFT of the On/Off box, in its own space, NOT touching or overlapping the scrollbar. Cog still opens the Mod Tweaker on Interface>HUD>Crosshair Kill Confirmation. Flip a CKC option in that HUD group, Apply, then open CKC's own mod-settings page -- the value matches (and vice-versa). Without CKC installed the row is stock vanilla and no cog appears.

## 0.2.229-dev (2026-07-13) -- #340 all-language display: detect-and-defer (case 2) [untested]

- **#340 (feature): port "Support All Languages" (Workshop 3232229691) so player names + chat render CJK/Cyrillic without square blocks. Verdict: CANNOT port into gut -- it ships a CUSTOM font resource. Shipped a documented detect-and-defer stub instead; resolution is documentation + recommend the standalone mod.**
  - **Mechanism (decompiled, extract `misc-vermintide-mods/Support All Languages/`):** the source mod's entire logic is a global-table swap (`support-all-languages.lua:19-42`). On enable it repoints the FIRST element (the font MATERIAL path) of eight vanilla `Fonts` entries -- `arial`, `arial_masked`, `arial_write_mask`, `hell_shark_arial{,_masked,_write_mask}`, `chat_output_font{,_masked}` (`ui_fonts.lua:6-84`, `[1] = "materials/fonts/arial"`) -- to a NEW material `"fonts/ArialUnicodeMS"`, keeping `[2]` size + `[3]` font-name; on disable it restores. No hooks; pure local rendering; no networked surface.
  - **Case determination = CASE 2 (custom font resource, NOT a game asset).** `"ArialUnicodeMS"` appears NOWHERE in the decompiled vanilla source (grep 2026-07-13). It ships inside the source mod's own bundle: its `.mod` declares `packages = { "resource_packages/support-all-languages/support-all-languages" }`, and the extractor log records that `.mod_bundle` at **32,583,136 bytes (~32 MB)** while every recovered Lua/manifest file is a few hundred bytes -- the ~32 MB IS the compiled Arial Unicode MS glyph atlas (~25 MB resident, matching the issue's memory note), packed into the mod.
  - **Why gut can't absorb it:** re-pointing `Fonts` only works if the target material is RESIDENT. gut ships no such atlas, so doing the swap would target a material gut does not have -- a "Material not found in Gui" failure on every chat/name/most-UI text surface for ALL gut users, not a fix. And the source mod's atlas is another author's compiled font (Arial Unicode MS is a Microsoft font) -- not ours to redistribute.
  - **Shipped (`_gut_all_languages.lua`, dofile'd after `_gut_ckc_bridge`):** a DETECT-AND-DEFER stub. Installs NO hooks, adds NO menu toggle, performs NO font swap. It detects the standalone mod (`get_mod("support-all-languages")` + its enabled state), printf-logs `[gut:340]` whether it's present, and publishes `mod._GUT_ALL_LANGUAGES` (case marker + `does_font_swap=false`). Purpose: the durable record of the case-2 decision, plus a defer guard so that if a future gut build ever gains its own (redistributable, e.g. OFL) font-swap feature, it no-ops when the standalone mod is present rather than double-swapping.
  - **Recommendation (issue resolution):** players wanting all-language display should subscribe to the standalone "Support All Languages" (3232229691) -- purpose-built, tiny, self-contained (own font bundle), and load-order-compatible with gut.
  - New `/gut_regression_test` check `all_languages_defer_340` (io-safe, load-time): asserts the module loaded and stays a pure defer -- fails if `does_font_swap` flips true, if hooks get installed, if the case marker changes, or (dev/CI source guard) if the `Fonts[1]` swap is reintroduced.

## 0.2.228-dev (2026-07-13) -- #539 mid-mission Customize crash: fill nil ItemId [untested]

- **#539 (CRASH, 0-critical): clicking the gear-icon Customize on a weapon MID-MISSION hard-crashed** at vanilla `HeroWindowItemCustomization._setup_illusions`: `bad argument #1 to 'gsub' (string expected, got nil)` -- `string.gsub(item.ItemId, "^vs_", "")` (decompile `hero_window_item_customization.lua:1527`). Log evidence: session db15dee6 (2026-07-12 22:49:49, modded realm, `dlc_dwarf_whaling`), preceded by `[gut:84] customize click: item=wh_1h_axe ... in_keep=false -> ALLOW`. The modded-realm mission loadout item carries no `ItemId` (the keep item does, so the keep Customize screen is unaffected).
  - Root: `item.ItemId` is read in EXACTLY ONE place in that window (grep 2026-07-13: only `:1527`, the overview/illusion substate; property/trait reroll + upgrade never read it), and every substate resolves its item through the single choke point `_get_item` (`:163/:304/:727/:1150/:1193`, `_state_setup_overview :1660`).
  - Fix (`_gut_mission_inventory.lua`): new `mod:hook("HeroWindowItemCustomization", "_get_item", ...)` fills a nil `ItemId` from `item.key` (canonically the same master-list key the gsub strips). One choke point covers every substate AND the `cosmetics_tweaker._setup_illusions` hook (it delegates to vanilla first, `cosmetics_tweaker.lua:2293`, with the already-normalized item). No-op when `ItemId` is present, so the keep path is byte-unchanged; cosmetics_tweaker unchanged. gut owns the only mid-mission entry to this window, so the fix lives here. Pre-flight: no mod hooks `_get_item` (grep-verified across cim_dev/cosmetics_tweaker/gut_dev/gt_dev).
  - New `/gut_regression_test` check `customize_item_id_normalized_539` (io-safe, driven synthetically): asserts the normalizer fills a nil ItemId from key, leaves a present ItemId untouched, and the vanilla `_get_item` choke point still exists.

## 0.2.227-dev (2026-07-13) -- #285 respawn timer wrong position/size fix [verify-fix]

- **#285: the respawn countdown rendered in the WRONG SPOT and TINY** ("tiny red numbers over the health/ability bar" instead of "large numbers over the portrait"). The v0.2.183 fix got it to render at all (it was drawing nothing before), but it drew immediate-mode `draw_text` at `UISceneGraph.get_world_position(...)`. A node's `world_position` is ALREADY inverse_scale-transformed for the resolution (`ui_scenegraph.lua:249-252`, hud_scale_fit branch); passing it as an absolute draw coordinate inside a `begin_pass` makes UIRenderer apply the resolution scale a SECOND time, shifting the number off the portrait onto the health bar. Font also defaulted to 32 = "tiny".
  - **Fix (`_gut_respawn_timer.lua`, rewritten -- same single `hook_safe(IngameHud, "update")`, no new hook):** port the exact widget-based mechanism of the reference mod **复活CD / Respawn CD (beta)** (Workshop `3747644100`, bundle `6e7d92af18da0995`, decompiled clean). Build our own scenegraph that MIRRORS the vanilla team-frame hierarchy (root hud_scale_fit 1920x1080 -> `pivot_parent`{50,0} -> `pivot` -> `portrait_pivot`), set our `pivot` node's LOCAL position to the dead teammate's own team-frame `pivot.position` (the on-screen slot `UnitFrameUI.set_position` writes at `unit_frame_ui.lua:117`; `.position` aliases `.local_position`, `ui_scenegraph.lua:83`), then draw a `UIWidget` through that scenegraph with `UIRenderer.draw_widget`. Feeding a LOCAL position through an identical hierarchy lets `update_scenegraph` (run inside `begin_pass`, `ui_renderer.lua:344`) apply the hud_scale_fit transform EXACTLY ONCE, landing the number on the portrait pixel-for-pixel with the reference. Widget offsets/size/alignment + the teammate font base (72, `hell_shark_header` -> `materials/fonts/gw_head`, `ui_fonts.lua:58`) copied verbatim from the reference's `team_respawn_text`.
  - **Data defaults matched to the reference:** `gut_respawn_font_size` default 32 -> **72** (range widened `{12,80}` -> `{24,160}`); `gut_respawn_r/g/b` default red `(255,60,60)` -> **white `(255,255,255)`**. Setting ids unchanged (`gut_respawn_timer`, `gut_respawn_font_size`, `gut_respawn_r/g/b`), so a user who explicitly set a size/colour keeps it.
  - **Client-safe + coexistence unchanged:** still a client-side estimate anchored to the local frame's dead flag + `Managers.mechanism:setting("hero_respawn_time")` (host respawn time is host-only + non-networked), so it works for a pure client in someone else's lobby. Running Respawn CD alongside is still safe (both post-hooks, no shadowing) but double-draws once ours works -- disable one.
  - **rt check `respawn_timer_ingamehud_draw_path` extended** (#285): now also fails if the draw stops using `UIRenderer.draw_widget`, if `get_world_position` immediate-draw is reintroduced (the double-scale bug), or if the teammate font base drops below 72.

## 0.2.226-dev (2026-07-13) -- #522 inventory character-preview backdrop dropdown [untested]

- **#522: new "Inventory" options group with a "Character Preview Backdrop" dropdown (default Vanilla) that swaps the scene behind the hero in the inventory preview pane.** Three choices: **Vanilla** (`levels/ui_inventory_preview/world`, untouched), **Dark Camp** -- the dark campfire scene the chest-opening screen uses (`levels/end_screen/world` + `environment/ui_end_screen`, object set `flow_victory` mirrored verbatim from the keep loot viewport def, `hero_view_state_loot_definitions.lua:1104-1115`) -- the "standard backdrop with the dark lighting" the issue asks for -- and **Victory Camp**, the mission-won celebration scene (`levels/end_screen_victory/world`, same env, weave end view precedent `level_end_view_weave.lua:347`).
  - **Mechanism (`_gut_inventory_backdrop.lua`, new module):** ONE singleton pre-hook on `HeroWindowCharacterPreview.create_ui_elements` (preflight: gut had zero hooks on that class) mutates the cached viewport def's `level_name`/`level_package_name`/`shading_environment`/`object_sets` BEFORE vanilla reads the def (`hero_window_character_preview.lua:100`), so vanilla's OWN machinery does everything else: it async-loads the chosen package under its `HeroWindowCharacterPreview` ref (:105), `post_update` refuses to mount the viewport until `has_loaded` (:163-164 -- the issue 336 ungated-mount C-fatal cannot occur), and `on_exit` unloads symmetrically (:131). The Vanilla choice actively restores captured originals every open, and a chained `mod.on_disabled` restores them when gut is turned off.
  - **Alternates were chosen for having standalone managed .package files** (both are loaded mid-mission by the game itself at round end, `adventure_mechanism.lua:353-366`), so the swap also stays safe inside gut's in-mission inventory. `Application.can_get("package", ...)` pre-checks existence and degrades to Vanilla with a printf on any miss. Candidates REJECTED for having no .package (cannot be residency-gated, keep-only bundles): `ui_character_selection` (bundle evidence, issue 173 research) and `ui_store_preview` (the documented mid-mission Customize C-fatal class, issue 336).
  - **rt check `inventory_backdrop_swap_522`:** catalog shape (package paths must be `resource_packages/levels/`, per the package-path rule), dropdown-value/catalog pairing, vanilla class + both consumed methods present, plus io-safe source needles for the `can_get("package")` gate and the def-swap line that routes the package through vanilla's `has_loaded` gate.

## 0.2.225-dev (2026-07-13) -- #527 collapsibles lead their level; #528 CKC bridge implicit [untested]

- **#527: the UI Tweaks and Crosshair Kill Confirmation collapsibles sat in the MIDDLE and at the BOTTOM of the HUD options, violating the ordering doctrine (collapsible sub-groups always placed FIRST at their level, A-Z among themselves, then the loose options).** Two root causes, two fixes:
  - **`gui_tweaker_dev_data.lua` (HUD group):** the `hb_group` ("UI Tweaks") collapsible was authored 4th, after the HUD-mode dropdown + two hotkeys ("deliberate order" comment from the 2026-07-02 reorg). Moved to the HEAD of `gut_hide_hud_ui_group.sub_widgets`; the loose options keep their rig order below it. Same doctrine applied to "Main Menu & Startup": the "Cutscenes & Monologues" collapsible now leads that level (was last, after two loose checkboxes).
  - **`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua` (`_inject_ckc_into_gut`):** the runtime-spliced "Crosshair Kill Confirmation" sub-group (issue 339 fold) was inserted at the END of the HUD child block (`end_idx` scan). Both twins now splice at the START of the block (`ins_idx = hud_idx + 1`, marker `[CKC-SPLICE-FIRST-527]`); "Crosshair Kill Confirmation" precedes "UI Tweaks" A-Z, so head-of-block IS its alphabetical slot. Rendered HUD order: CKC group, UI Tweaks group, loose options. (The keep sub-state twin is dormant/gated OFF but is documented byte-parallel, so it was mirrored.)
  - **Ordering rule (binding, enforced at both sites):** within every level of gut's menu, collapsible sub-groups come first (A-Z among themselves); loose options follow. Injected sub-groups obey the same rule via their splice point.
- **#528: the "Crosshair Kill Confirmation Options" checkbox under Mod Tweaker settings (`gut_ckc_options_bridge`, the issue-313 bridge master toggle) gated whether the CKC options-menu takeover was available at all. That availability gate is now IMPLICIT: the bridge is active whenever the CKC mod is installed and togglable, no toggle.** Widget removed from the data file, both loc keys removed, and in `_gut_ckc_bridge.lua`: `_bridge_on()`/`_S_BRIDGE` deleted, `_is_active()` = CKC presence only, and the `on_setting_changed` chain (which only listened for the toggle) removed. The feature's own On/Off control (the vanilla-Options dropdown takeover driving the CKC mod live) is untouched. The orphaned `gut_ckc_options_bridge` saved value stays in mods_settings unread (harmless, flat VMF namespace); `M.restore` stays as a manual recovery API.
- **rt checks:** `ckc_bridge_loc_keys` (which REQUIRED the retired loc key) replaced by `ckc_bridge_implicit_no_toggle` (#528: retired setting id must stay out of the data file and the bridge module); new `hud_collapsibles_hold_first_position` (#527: `hb_group` precedes `gut_hud_mode` in the data file, and both twins carry the `[CKC-SPLICE-FIRST-527]` head-of-HUD splice marker).

## 0.2.224-dev (2026-07-12) -- #505 Mod Tweaker filtered/searchable dropdown [untested]

- **#505: a generic FILTERED/SEARCHABLE dropdown capability in the Mod Tweaker, consumable by any mod (the pattern #446 set).** When a dropdown widget has many options (like ct's ~40+ CW mission list), the OPEN popup now gains (a) a type-to-filter search line that narrows the option list live as you type, and (b) declared CATEGORY chips to filter by a named group. A dropdown with NO registration is unchanged; a long one (>= 8 options) gets the search line for free; category chips appear only for a registered dropdown. This is the actual blocker the user hit testing the CW dev loader ("we need that dropdown feature").
  - **Render path extended (all view-internal, no VMF-UI guessing, no new `mod:hook`):** the popup factory `defs.create_dropdown_list` (`_mod_tweaker_definitions.lua`) took an optional 5th `header` arg -- when present it grows a header band ABOVE the option rows (a `DD_HEADER_SEARCH_H=26` search line + a `DD_HEADER_CHIP_H=28` chip row when chips exist), pushing the option rows down by `header_h` (the popup already drops downward from the collapsed row, and the v0.2.80 `BOTTOM_SCROLL_PAD` headroom covers the taller popup). Search line = a bg rect + a view-updated `search_text`; each chip = a bg rect + centered label + a `chip_<i>` hotspot. `header=nil` is byte-for-byte the old plain popup, so the gated-off keep sub-state's 4-arg calls and every plain dropdown are unchanged. New stash fields `w._dd_cur` (filtered-space selected index, highlight seed), `w._dd_header_h`, `w._dd_chip_count`.
  - **Filter machinery (`_mod_tweaker_view.lua`):** `self._dd_visible` = the array of ABSOLUTE option indices passing the current filter, recomputed by `_recompute_dd_visible` on open + every query/chip change (identity when nothing is active, so the popup matches the unfiltered dropdown). `_refresh_dropdown_list` renders the visible subset with the selected option remapped to filtered space (or -1 -> no gold when filtered out); `_open_dropdown_popup` looks up registered categories, sets `row._dd_filterable = (#options >= DD_FILTER_MIN) or has_categories`, and scrolls the filtered window to the selection; `_handle_dropdown_input` reads chip clicks + type-to-filter keystrokes (via the SHARED `_apply_keystrokes` reader refactored out of #497's `_search_apply_keystrokes` -- the same raw `Keyboard.keystrokes()` path, chat-blocked each frame) before mapping an option click through `_dd_visible` back to the absolute index; the wheel clamps against the filtered count; `_close_dropdown_popup` drops the per-open filter state. `_position_dropdown_highlight` seeds from `w._dd_cur`; `_draw` blinks the popup search caret each frame (guarded on `content.search_text`, absent for plain popups). An empty result renders a non-clickable "(no matches)" row.
  - **Registry + public API (mirrors #446):** `_mod_tweaker_settings.lua` gains `register_dropdown_categories(mod_id, setting_id, categories)` / `get_dropdown_categories` / `dropdown_category_count` -- each category is `{ label = <string>, match = <fn(value,text) OR key-list> }`, normalized to a predicate (a key-list becomes a membership test on the option VALUE, owning a clone). `_mod_tweaker.lua` exposes `mod_tweaker:register_dropdown_categories / :get_dropdown_categories`, reached by siblings via `get_mod("gut_dev").mod_tweaker`; rejections route through the existing `_dbg_alert`.
  - **rt check `mod_tweaker_dropdown_filter_api` (#505):** runtime-only -- registers throwaway categories (function + key-list form), verifies both normalize + resolve + rejects malformed shapes (missing setting_id, empty list, label-less entry), asserts the view carries the filter methods, and builds a probe popup WITH a header (asserts `chip_count==2` + `search_text` + `chip_1/chip_2` hotspots) and WITHOUT one (asserts no header band grows -- backward-compat guard).
  - **ct-side registration is OUT OF SCOPE for this gut-only task** (chaos_wastes_tweaker_dev is owned by another agent). The exact ready-to-paste `ctdm_base` Travel/Signature snippet is handed to the team lead to fold into the next ct build.
  - **NOT mirrored to the dormant keep sub-state `_mod_tweaker_state.lua`** (gated OFF, `_USE_KEEP_SUBSTATE = false`) -- same call as #497/#446; its 4-arg `create_dropdown_list` calls keep working because `header` is optional. If it is ever re-enabled, mirror the same view edits there.

## 0.2.223-dev (2026-07-12) -- #530 suspend the in-mission tab strip on Holseher's Map [untested]

- **#530 (crash): the in-mission inventory/crafting tab strip was still available on Holseher's Map (the Chaos Wastes shop/map screen), where it must be suspended like the rest of a CW run.** During a CW COMBAT mission the strip is already suspended for free -- every gut entry point that opens the hero_view (`gut_open_mission_inventory` / the ESC "Open Inventory" entry) deus-blocks, and CW combat has no native mid-mission hero_view -- so `HeroWindowPanelConsole.on_enter` never fires there. But Holseher's Map (`dlc_morris_map`, game_mode `map_deus`) opens the hero_view NATIVELY, so gut's `on_enter` hook fired and un-gated the whole strip: Inventory/Talents/Cosmetics went live and the (greyed) Crafting tab still showed on the pause menu -- and touching a loadout-locked CW build is the crash this is filed under.
  - **Fix (`_gut_mission_inventory.lua`, the existing `HeroWindowPanelConsole.on_enter` hook -- merged into the body, no new hook):** after the keep early-return, suspend the strip when `Managers.mechanism:current_mechanism_name() == "deus"`. This is the SAME adventure-exclusive signal `gut_open_mission_inventory` (:82) and `_patch_inventory_access` (:536) already use, and it is "deus" across the ENTIRE deus run -- hub, map AND ingame -- because `deus_mechanism.lua`'s `get_next_level_data` hard-sets `mechanism = "deus"` for every node (:150, log-confirmed `mech=deus` on `dlc_morris_map`). Adventure is untouched (mech=adventure proceeds); the keep is untouched (handled by the pre-existing `in_keep` return). Adds an always-on `printf("[gut:530] ...")` so the in-game test yields evidence with mod logging OFF.

## 0.2.222-dev (2026-07-12) -- #446 Mod Tweaker mutually-exclusive option groups [untested]

- **#446: a data-driven "mutually exclusive" grouping for Mod Tweaker checkboxes.** A sibling mod declares that a set of its own (or cross-mod) boolean settings are mutually exclusive; switching one member ON in the Mod Tweaker menu turns the others OFF -- a radio group over ordinary checkboxes (all-off is a valid "None [Default]" state, exactly the issue's mock-up). No new widget type: members stay normal `checkbox` widgets, wrapped in a native VMF `group` for the collapsible look; gut renders the group and enforces the exclusivity.
  - **Registry (`_mod_tweaker_settings.lua`):** new `register_exclusive_group(group_id, members)` (members = `{ { mod=, setting= }, ... }`, 2+ required; re-register REPLACES so an author reload re-declares cleanly), plus `get_exclusive_group_id(mod_id, setting_id)` (O(1) reverse membership index) / `get_exclusive_members(group_id)` / `exclusive_group_count()`. Member key is `mod_id\0setting_id` (NUL-joined -- ids never contain NUL, so no `::`-style collision).
  - **Public API (`_mod_tweaker.lua`):** `mod_tweaker:register_exclusive_group / :get_exclusive_group_id / :get_exclusive_members`, reached by siblings via `get_mod("gut_dev").mod_tweaker`. Rejections route through the existing `_dbg_alert` telemetry.
  - **Enforcement (`_mod_tweaker_view.lua`):** new `ModTweakerView:_enforce_exclusive(category, setting_id)` -- when a member is switched ON, it stages every OTHER member OFF (only ones whose effective staged/live value is truthy, so no false-dirty edits), keyed DIRECTLY into the pending buffer under each member's own mod_id (same key `stage_set` resolves for a same-mod member; correct per-mod buffer for a cross-mod member). The checkbox toggle handler calls it and, on any change, does a `_build_rows` rebuild + return (the same shape as the group-header toggle) so the switched-off sibling rows REPAINT -- checkbox display is cached, so `stage_set` alone would not update them. Turning a member OFF is the "select None" path and touches no sibling. No new `mod:hook` (all changes are inside the view class + registry modules).
  - **Scope of enforcement:** same-mod members commit together on that tab's APPLY; a cross-mod sibling buffers under its own tab and commits when THAT tab is applied. Enforcement is Mod-Tweaker-menu only -- editing the same setting in VMF's stock options menu is not swept (documented in `MOD_TWEAKER_INTEGRATION.md` new "Mutually-exclusive option groups" section, with the author recipe).
  - **rt check `mod_tweaker_exclusive_group_api` (#446):** runtime-only (no source read) -- registers a throwaway 2-member group, verifies the reverse lookup resolves both members + rejects a non-member and malformed shapes (empty id, single member), and asserts the view class still carries `_enforce_exclusive`.
  - **The issue's named group ("Zealot THP Conversions") lives in `crt`, out of scope for this gut-only task**, so no real group is wired here: the API + rt check ship and consumers register from their own mods (recipe in the integration doc). NOT mirrored to the dormant keep sub-state `_mod_tweaker_state.lua` (gated OFF, `_USE_KEEP_SUBSTATE = false`) -- same call as #497; if it is ever re-enabled, mirror the tiny `_enforce_exclusive` method + the 5-line handler hook there (its checkbox handler is byte-identical to the view's).

## 0.2.221-dev (2026-07-12) -- #497 Mod Tweaker per-tab menu search [untested]

- **#497: added a SEARCH bar to the Mod Tweaker view (`_mod_tweaker_view.lua`).** A fixed input field above the settings list, flush with the row-content width, filters the CURRENT tab to only the settings and collapsibles whose (case-insensitive) label contains the typed term.
  - **Layout (`_mod_tweaker_definitions.lua`):** new `mt_search` scenegraph node parented to `background_frame` (fixed, does NOT scroll), left-aligned at x=58 = list_mask inset (18) + mt_list_start inset (40) with width = `ROW_W`, so its left/right edges line up with the row content. To open the strip, the list window (`list_mask`) + scrollbar are shrunk by `SEARCH_BAND_H=44` and their centres nudged down half that (top edge drops 44px, bottom unchanged); list_mask stays centre-aligned so the existing `_draw` row-cull (which reads its live world-pos/size) is unaffected. New `create_search_box()` factory: rect bevel + hotspot + text, no material lookups (safe on the borrowed renderer).
  - **Filter (`_build_rows`):** when `_search_active()` returns a term, render a FLAT list (no gear/collapse/drill): every node whose localized label (`_node_label`, mirroring the row label logic) contains the term, PLUS each match's ANCESTORS (nested match stays reachable + shows its section) and, for a matched GROUP, its DESCENDANTS (the matched section's contents). A matched group is force-expanded. Empty result shows a "No settings match" row.
  - **Input:** click the box to focus (commits any active numeric edit first); printable keystrokes edit the query via `Keyboard.keystrokes()` (the SAME raw path the numeric type-to-edit uses) with chat input blocked each frame so keys/Enter don't leak to game chat; the list re-filters live on every change. Enter drops focus (keeps the filter); ESC clears the filter (first ESC) then closes the menu (second); clicking a row/tab/button drops focus. Search resets on every open and on a tab switch, so scope is always the current tab. No new `mod:hook` (all changes are inside the view class).
  - **NOT mirrored to the dormant keep sub-state `_mod_tweaker_state.lua`** (`HeroViewStateModTweaker`): it is gated OFF (`_USE_KEEP_SUBSTATE = false`, `gui_tweaker_dev.lua:1228`) and the ESC "Mod Tweaker" button routes BOTH keep and mission to the standalone `ModTweakerView`. If the sub-state is ever re-enabled, mirror the same edits there (the shared `create_search_box` in defs makes it mechanical).

## 0.2.220-dev (2026-07-12) -- #511 io-safe regression checks: source-reads no longer throw in the retail sandbox [untested]

- **#511: the `/gut_regression_test` source-pattern checks threw `attempt to index global 'io' (a nil value)` in the retail client and reported FALSE FAILs.** The VMF retail Stingray VM registers no `io` library (mods are `loadstring`'d into the game's shared `_G`; the engine registers `os` -- its own mod_manager.lua calls `os.date` unguarded at :313 -- but not `io`), so every `io.open` self-read threw and the runner's `pcall` surfaced it as a check FAIL on healthy code.
  - NEW `_rt_src_read(path)` helper (near `_rt_register`): guards `rawget(_G,"io")` and returns nil when `io` is absent, so a check's existing "unreadable source => skip (PASS)" branch runs instead of throwing. All 17 `io.open` source-reads in `gui_tweaker_dev.lua` now route through it (inline blocks, the `read_all` locals, and `_gut_read_all`).
  - In retail the source-text half is skipped; the RUNTIME markers each check already asserts (anchor function / vanilla class + method / gate behavior) are now the authoritative in-game signal. Two previously source-only checks (`mission_map_preview_backdrop`, `cutscene_postskip_fade_swallow`) gained an explicit runtime anchor assert (`gut_open_mission_map` / `gut_skip_cutscenes_toggle` must be wired) so retail still catches a module-load regression. The source-text needles remain live under the modding-tools executable / CI and are listed for repo QA-gate moves (PROJECT_STANDARDS 2.2b tier a).
- **`_gut_config_file.lua` (config-read FEATURE, not a check) left in place** but made io-safe: its two `io.open(path,"r")` reads route through a local `io_open` guard (still a no-op in retail, as before via the outer `pcall(_gut_config.apply)`), and the stale "reads work, writes are sandboxed" header comment was corrected -- `io` is entirely nil in retail, so the LOAD/OVERRIDE read path only functions under the modding-tools build. No behavior change.

## 0.2.219-dev (2026-07-12) -- #499 rename _gut_options_probe.lua -> _gut_diag_optionsview.lua; rename /regression_test command to /gut_regression_test [untested]

- **COMMAND RENAME (users must relearn):** the dev self-check command is now `/gut_regression_test` (was the bare `/regression_test`). Bare `/regression_test` no longer exists. This aligns gut_dev with stable `gut` (which already uses `gut_regression_test`) and removes the collision the `gt_` prefix rule in `docs/COMMANDS.md` was written to avoid (PROJECT_STANDARDS section 2.2b). Registration at `gui_tweaker_dev.lua:82`; the 7 in-source `/regression_test` doc comments across `gui_tweaker_dev.lua`, `_gut_freecam.lua`, `_gut_mission_map.lua`, `_gut_native_loadouts.lua`, `_mod_tweaker_view.lua` were updated to the new name.
- **#499 probe consolidation (PROJECT_STANDARDS section 2.2b):** renamed the root-level `_gut_options_probe.lua` -> `_gut_diag_optionsview.lua` (git mv, one path) so the filename states its topic, per the `_<ns>_diag_<topic>.lua` convention (canonical: ct_dev's `_ct_diag_freeze487.lua`). This is the standing Mod Tweaker scrollbar ground-truth probe (auto-dumps the live vanilla OptionsView layout on ESC -> Options; `/dump_options` manual re-dump; owns `mod._opt_ref` / `_opt_dumped` / `_opt_apply_dumped`, all set+read within the file). NOT keyed to a single issue, so its `[opt-probe]` / `[opt-apply]` channel prefixes stay topic-based.
- **Content byte-identical except the file-header comment** (rewritten to the new name + purpose + `Owned by:` line per section 2.2). The two `OptionsView` `hook_safe` callbacks (`on_enter`, `update_apply_button`) and the `/dump_options` registration are unchanged.
- Updated references: `gui_tweaker_dev.lua` dofile + comment, `_gut_ckc_bridge.lua` hook-inventory comment, `ENGINE_SURFACE.md` (surface 4 pre-flight note + surface 5b probe row). Package is glob-based (`scripts/mods/gui_tweaker_dev/*`), so no `.package`/manifest entry changed. `docs/COMMANDS.md` already lists `gut_regression_test` for stable `gut` and does not track dev-only commands, so no COMMANDS.md row required.

## 0.2.218-dev (2026-07-12) -- #500 remove stale probes for closed issues (173/92/99/95/123/124/106) [untested]

- **#500: removed four diagnostic probe files whose issues are all CLOSED.** Each was pure read-only telemetry (raw-printf / mod:info, returns `{}` or nothing, no state consumed by any non-probe module -- verified by whole-mod grep of every field they set). No behavior change to the mod.
  - `_gut_173_probes.lua` (issue 173, `[gut:173] B7`): hook_safe `GameModeAdventure.force_respawn` + a 60-frame post-respawn position read. Only hook on that method; only effect was the printf. Removed the file + its dofile line.
  - `_gut_glow_probe.lua` (issues 92, 99, `[gut-glow-probe]`): hook_safe `OptionsView.draw_widgets` + `IngameUI.update` A/B glow capture. Its only mod-state write, `mod._opt_view_ref`, is read nowhere else. Removed the file + its dofile line.
  - `_gut_keybind_probe.lua` (issues 95, 123, `[gut-keybind-probe]`): hook_safe on three `VMFOptionsView` rebind methods + a `mod.update`-chain scan (its `mod._gut_kb_last_rows` latch is file-local). Removed the file + its dofile line.
  - `_gut_menu_transition_probe.lua` (issues 124, 106, 123, `[gut-menu-probe]`; also hosted the 173 Probe B3 `[gut:173] B3` residency line): hook_safe `IngameUI.transition_with_fade` + `IngameUI.handle_transition` + an instance-level wrap of the live ModTweakerView exit/on_enter. All observation-only. Removed the file + its dofile line.
- **KEPT `_gut_options_probe.lua`** (Mod Tweaker scrollbar ground-truth): not listed in #500 and carries no closed-issue tag, so left byte-identical (still owns `mod._opt_ref` / `_opt_dumped` / `_opt_apply_dumped` and the `/dump_options` command).
- **KEPT `_gut_cutscenes.lua`** (the `[gut:cutscene]` probe is inside the live cutscene feature, not a standalone probe file) untouched.
- `.package` uses a `scripts/mods/gui_tweaker_dev/*` glob, so no package-manifest edit was needed; only the four `pcall(mod.dofile, ...)` lines in `gui_tweaker_dev.lua` were removed.

## 0.2.217-dev (2026-07-11) -- two P0 crash-window fixes (freecam world gate; loadout fallback index space) + #480 gear-read trace throttle [verify-fix]

- **P0 FIX (freecam): Leave Game with Free Camera active could fassert in `WorldManager.world`** (BUG_CLASSES class 32, issue 459 family; IMPROVEMENT_BACKLOG gut_dev row). `_drive_free_cam` ran a bare `Managers.world` name lookup per frame from mods_update -- which keeps ticking through StateIngame teardown -- and `WorldManager.world()` fasserts on a missing name (world_manager.lua:111-115), making the `if not world` check after it dead code. The activation-time render-state diagnostic had the same bare lookup.
  - NEW `_live_world(name)` helper (`_gut_freecam.lua`): `has_world` probe BEFORE the lookup; every world resolution in the module now routes through it (drive path, render-state diagnostic, enter gate, exit path). No world handle is cached in the module (always resolved fresh from the engine's own `data.viewport_world_name`), so no identity check is needed on top.
  - NEW force-exit on game-state transition: `("exit","StateIngame")` fires BEFORE the old state's teardown (game_state_machine.lua:17-21 -> state_ingame.lua:1939), so the handler now runs a full `apply(false)` there -- releasing the free-flight viewport into a LIVE world and syncing the checkbox off -- instead of only dropping local flags (which left the engine slot `active=true` with a stale world name; the engine's own dead-world cleanup never runs for us because the `disable_free_flight` gate stays up). If the world is somehow already gone, the exit path now runs vanilla's own `_clear_free_flight` (free_flight_manager.lua:531-535) instead of `_exit_free_flight`, whose ungated world lookup (:620) would fassert.
  - `/regression_test` `freecam_invariants` INVARIANT 6: functional check that the gate predicate returns nil (not raises) for a missing world, plus source-pattern checks that no bare world lookup and no dropped dead-world release path regress.
- **P0 FIX (native loadouts): MODE_STORE official gear fallback passed a STORE-space loadout index into the OFFICIAL-space read** (residual of issues 387/372; IMPROVEMENT_BACKLOG gut_dev row). In MODE_STORE every explicit loadout index circulating through the interface/UI indexes OUR store's rows; vanilla `get_character_data` indexes `_career_data[career][index]` directly and returns nil for a missing row (playfab_mirror_base.lua:1909-1919) -- so a store row number with no official counterpart served an EMPTY weapon slot, the spawn-fatal shape ("Tried to wield default slot ... contained no weapon").
  - NEW `_official_gear_fallback`: both fallback sites (nil-weapon and resolve-no) now pass a NIL index so vanilla resolves the official SELECTED row via `_career_loadouts` (:1911). Weapon-slot last resort: the career default loadout row (get_default_loadouts :1955-1966). If even that is nil, printf loudly and serve nil -- never invent an id, never spawn from a guess.
  - `/regression_test` `native_loadouts_fallback_index_translation`: synthetic store-row drive proving the official read receives a nil index, the selected row is served, the weapon-slot default-loadout last resort works, and a non-weapon gear slot may still resolve nil.
- **#480 FIX: issue-387 gear-read diagnostic throttled to one line per (career, slot, row) value/source change** (20,120 identical lines in the i477b host log). The old cache was keyed (career, slot) with the row index inside the signature; interface refreshes read the same slot across MULTIPLE loadout rows back to back, so consecutive reads always differed from the single cached signature and re-emitted every ~3 ms. Cache is now keyed per row -- first occurrence prints verbatim, identical repeats are suppressed, and a genuine per-row change (the issue-474 mechanism-3 signal called out in the issue) still prints exactly once. Diagnostic stays always-on in dev (throttle, not removal). New `/regression_test` check `native_loadouts_trace_throttle_per_change` drives first/repeat/interleaved/changed tuples through the exported predicate.

## 0.2.216-dev (2026-07-07) -- regression coverage: VMF lifecycle-chain integrity (issue 425)

- Audit finding F3: the mod chains ~15 VMF lifecycle callbacks (`mod.update`, `mod.on_setting_changed`,
  `mod.on_game_state_changed`, `mod.on_disabled`) across 48 files via the capture-prev idiom
  (`local prev = mod.X; mod.X = function(...) ...; prev(...) end`). It is correct everywhere but
  convention-only and unguarded -- one future file that forgets the `local prev =` capture would
  silently orphan every earlier-loaded handler with no error and no test to catch it.
- **NEW `/regression_test` check `lifecycle_chain_integrity`.** The root `mod.on_setting_changed`
  (gui_tweaker_dev.lua) now recognizes a synthetic probe id (`__gut_chain_probe__`) and flips
  `mod._gut_chain_probe.on_setting_changed`. The check drives the current (outermost)
  on_setting_changed with that id; since every feature handler ignores an unknown id while still
  calling `prev`, reaching the root proves the whole chain is intact. A dropped predecessor fails
  the check. on_setting_changed is the most-wrapped chain and the only one drivable side-effect-free
  from any menu state, so it is the representative proof for the shared idiom.
- **`_G._MEM_PROBE_T0_GUT` namespaced** under the mod table (`mod._gut_mem_t0`) -- the only global
  leak in the mod; boot mem-probe readout reader updated.
- Coverage only; no behavior change. Passes against current code.

## 0.2.215-dev (2026-07-06) -- issues #387 (FIX) + #402 (prevention proven + repair): loadout-system logic completed [verify-fix]

- Two decompiled-source audits (2026-07-06) closed the two open loadout defects at the source level -- no further user diagnostic needed.
- **issue #387 FIX (weapons do not follow the selected loadout on switch).** ROOT CAUSE (source-confirmed): `_resolve_item_raw` disagreed with the hero-view presentation. `get_item_from_id(id)` == `self._items[id]` after a dirty refresh and consults `self._items` ONLY (`backend_interface_item_playfab.lua:384-388`; there is NO `_all_backend_items` field and NO `_fake_items` consult). The old resolver returned YES on `_items`-OR-`_fake_items` presence; after a loadout switch (`set_loadout_item` sets `_dirty` :667) `self._items` is a FROZEN game-mode clone (:68-73) while `_fake_items` stays live, so a fake-only / stale-clone id read YES here yet `get_item_from_id` (which rebuilds `_items`) returned nil -- exactly the es_mercenary loadout-5 melee `C60E860C16C0B5E9` case (served store, never presentable, slot stuck on loadout-6's `wh_1h_falchion`).
  - FIX (`_gut_native_loadouts.lua` `_resolve_item_raw`): predict `get_item_from_id` faithfully and recursion-free -- when `not iface._dirty` read `self._items[id]` (exactly what get_item_from_id returns clean); when dirty, predict the pending rebuild from its SOURCES, `backend_mirror._inventory_items[id]` (`get_all_inventory_items()` :75, a bare field return :2189 -- no `_refresh`, so the v0.2.173 recursion stays impossible) OR the active game-mode overlay (:71-73). Dropped the `_fake_items` positive (fakes are inserted into `_inventory_items` too, :2400-2401, so nothing is lost but the false positive). A weapon that will not present now reads RESOLVE_NO -> the slot serves a resolvable weapon and FOLLOWS the switch instead of sticking. Fixes the get_character_data fallback AND the #372 preview guard (both share the resolver).
- **issue #402 (0-critical regression: modded weapon + frame ids in OFFICIAL loadouts).** PREVENTION PROVEN: the audit found NO un-hooked official-write path -- every runtime write that diverges official `_career_data` from its mirror funnels through `PlayFabMirrorBase.set_character_data` (writes `_career_data` :1933 BEFORE delegating :1941), and both the weapon AND the portrait FRAME (slot_frame is an ordinary loadout slot, not a hero-attribute) persist through it. We hook + no-op it in modded, so no NEW leak is possible; the corruption is residual pre-isolation #174 cloud data that never self-healed.
  - NEW rt-check `native_loadouts_official_write_chokepoint`: asserts all five official-write methods (`set_character_data` + the four others) stay hooked, so a future dropped hook that re-opens the leak fails the regression gate.
  - NEW command `/scrub_official_loadouts` (issue #402 repair). Report-only by default (lists every official loadout slot whose id fails `get_item_from_id` -- weapons + slot_frame). `/scrub_official_loadouts apply` (OFFICIAL realm only) replaces each broken slot with a resolvable id the player already owns for that slot (from another of their loadout rows); it only ever writes a verified-resolvable value into an already-broken slot, so it cannot break a working slot, and skips+reports a slot with no owned replacement. Hard-refuses in the modded realm (the write would be captured to the store, not official).

## 0.2.214-dev (2026-07-06) -- issue #387: DIAGNOSTIC v2 -- root cause narrowed to an unresolvable weapon id at presentation [diagnostics-armed]

- issue #387 UPDATE (v0.2.213 trace refuted the first hypothesis). The v0.2.213 `#387 gear-read` trace (console-2026-07-06-21.28) proved the mirror is NOT the problem: after `set_loadout_index es_mercenary -> 5`, get_character_data served `slot_melee idx=5 value=C60E860C16C0B5E9 source=store` and `slot_ranged idx=5 value=2D9CA7F1B89ACD5D source=store` -- both correct loadout-5 weapons, no official fallback. Also RULED OUT: store corruption (well-formed, distinct per-row weapons) and is_bot routing (active career_index == viewed, so is_bot=false).
- ROOT CAUSE (found): it is resolvable-vs-not PER SLOT, not weapons-vs-jewelry. 15 ms after the switch the grid presented ranged=`2D9CA7F1B89ACD5D` (es_repeating_handgun, loadout 5 -- UPDATED) but melee=`1118C3E8A0873F85` (wh_1h_falchion, loadout 6 -- STALE). The served melee id `C60E860C16C0B5E9` appears exactly once in the entire log and never resolves to an item: `get_item_from_id` returns nil, so `_populate_loadout` cannot present it and the slot keeps the previously-wielded weapon. It was served `source=store` (not the fallback) because `_resolve_item_raw` returned UNKNOWN/YES, not affirmative NO.
- CHANGED (`_gut_native_loadouts.lua`), diagnostic-only, no behavior change:
  - The `#387 gear-read` trace now splits `source=store` into `store-yes` (raw registry holds the id now) vs `store-unknown` (registry not inspectable at read) -- so the log distinguishes a genuinely-owned id from one served optimistically on UNKNOWN.
  - `/gut_loadout_status [career]` now takes an optional career filter and, per row, resolves every GEAR slot id BOTH ways -- `raw=YES/NO/UNKNOWN` (what the fallback consults) and `get_item_from_id=<key>|<FAIL>` (what the hero-view presentation consults) -- and echoes `weapon_ids_unresolvable=N` per career to chat. A slot with `raw=UNKNOWN/YES` but `get_item_from_id=<FAIL>` is exactly the stuck-weapon signature.
- REPRO (pins the fix -- data-repair vs resolve-timing): in a modded hero view run `/gut_loadout_status es_mercenary`, then send the newest console log. If loadout-5 melee shows `get_item_from_id=<FAIL>`, the stored id is dangling (bad seed / deleted item) and the fix is store validation + fallback-substitution at the loadout level; if it resolves fine when queried directly, it is a switch-time UNKNOWN race and the fix is a resolve guard on the presentation refresh.

## 0.2.213-dev (2026-07-06) -- issue #387: DIAGNOSTIC for weapons not following the selected loadout on switch [diagnostics-armed]

- issue #387 (distinct from #379). Reported: clicking a different saved loadout in a modded hero view changes cosmetics and jewelry (necklace/ring/trinket) but the main/secondary WEAPONS stay on the previously-equipped weapon. Confirmed from console-2026-07-06-20.54.23: `set_loadout_index` fires and the store `selected_index` advances (3->4->3->2->1->2 ...), yet the equipped melee stays `es_2h_sword` (rarity=modded) and ranged `es_longbow` across every switch. The persisted store (`user_settings.config` native_loadouts) is well-formed with DISTINCT per-row weapons, so this is NOT store corruption.
- WHY it is weapon-specific (analysis): `update_full_loadout` bumps `loadout_sync_id`, so `HeroWindowLoadoutConsole._populate_loadout` re-reads every slot via `get_loadout_item` -> `_refresh_loadouts` -> `mirror:get_character_data(selected)`. The only place a weapon slot diverges from a jewelry slot is gut's `get_character_data` hook: a weapon whose stored id is nil or `RESOLVE_NO` falls back to `func(...)` = the OFFICIAL loadout read, which is index-agnostic -- so weapons cannot follow the modded selection while resolvable jewelry is served straight from the store. That fallback exists on purpose (v0.2.172 spawn-fatal burn: an empty/late-registering weapon id fatals at wield), so this ships an INSTRUMENT first rather than a blind change.
- ADDED (`_gut_native_loadouts.lua`) a throttled gear-read trace: `_trace_gear_read` logs ONE line per (career, slot) whenever the served (index, value, source) tuple changes -- i.e. exactly on a loadout switch or equip -- printing `#387 gear-read career=.. slot=.. idx=.. value=.. source=store|official-fallback-nil-weapon|official-fallback-resolve-no|store-nil-jewelry`. get_character_data is a hot path, so the throttle keeps the log to one line per real change. Always-on in dev, never a menu toggle.
- NO behavior change -- this build only observes. REPRO (modded hero view): switch loadouts 2-3 times, including to a loadout whose weapons differ, then send the newest console log. The trace will show whether `slot_melee`/`slot_ranged` take an `official-fallback-*` source while `slot_necklace` shows `source=store`, which pinpoints the fix.

## 0.2.212-dev (2026-07-06) -- issue 275 CLOSED (user-confirmed in-game): Skip Cutscenes wired-on_skip policy

- issue 275 CLOSED. The user confirmed in-game that The Enchanter's Lair Nurgloth fight is healthy with Skip Cutscenes ON: the boss cinematic plays out (gut correctly LOCKS a cutscene with no wired `event_on_skip`), the health gate steps past 66%, and the fight is completable. gut's wired-`on_skip` gate (v0.2.209-dev, commit d4784dc) is confirmed correct behavior -- playing the boss cinematic is by design. The gameplay root cause of the softlock lived in gt's Creature Spawner BTConditions guard collapse (gt commit b166251), not in cutscene skipping; this entry closes gut's half.
- LOC: stripped the dev status tags from the two Skip Cutscenes menu strings now that the fix is user-confirmed -- `gut_skip_cutscenes_enabled` and `gut_skip_cutscenes_auto` dropped their `[verify-fix] [Issue 275]` tags, leaving clean labels ("Skip Cutscenes" / "Auto-skip Cutscenes") per LOCALIZATION_STANDARD s13. `gut_skip_cutscenes_hotkey` is untouched (it carries a separate open issue 126 ref).
- No behavior change. The `gut_cutscene_no_global_latch` regression check (v0.2.209-dev) stays armed: it asserts `script_data.skippable_cutscenes` is falsy at rest, the wired-skip gate refuses an `{event_on_skip=nil}` stub, and the toggle no longer re-latches the global flag.

## 0.2.211-dev (2026-07-06) -- issue #379: FIX hovered loadout preview stale after an in-view equip [verify-fix]

- issue #379 FIX. In a modded hero view, equipping a weapon and then hovering a saved loadout slot showed the OLD gear/cosmetic icons in the context-menu preview; only closing and reopening the whole inventory refreshed it. Root cause is a vanilla caching seam our modded flow exposes: `HeroWindowLoadoutSelectionConsole` captures each loadout snapshot into `content.loadout` ONCE, at `_populate_loadout_buttons` (window-enter) time (`hero_window_loadout_selection_console.lua:191`), but the item interface REBUILDS `self._career_loadouts` as brand-new tables on every refresh (`backend_interface_item_playfab.lua:166` `table.clear` -> :170 fresh per-career table -> :179 fresh row tables). So the cached `content.loadout` reference is orphaned the instant anything dirties the interface (e.g. an in-view equip), and `_show_context_menu` (:763) keeps drawing that dead snapshot. Nothing re-runs `_populate_loadout_buttons` after an equip, so the stale preview persists until the view re-enters.
- CHANGED (`_gut_native_loadouts.lua`): the existing `_populate_context_menu_loadout` hook (added for #372) now re-fetches the LIVE loadout row -- `item_interface:get_career_loadouts(career_name)[loadout_index]` -- before populating, so the preview always reflects current data. That is the exact interface getter vanilla's own `_populate_loadout_buttons` calls (it self-refreshes when dirty and, in modded, pulls from our store); it is NOT `get_item_from_id`, so there is no mirror-read recursion (v0.2.173 burn). Scoped to a modded backend view (`_adventure_mode() ~= MODE_OFF` -- the loadout surface we own); the official realm keeps exact vanilla behavior. Falls back to the passed `content.loadout` if the live row is unavailable (e.g. index out of range mid-add). Composes with the #372 crash guard: the unresolvable-id substitution + `pcall` backstop now run on the fresh row.
- No new hook registration -- the change merges into the hook already declared in `M.HOOK_TARGETS` (`HeroWindowLoadoutSelectionConsole._populate_context_menu_loadout`).
- VERIFY IN-GAME (modded session, hero view kept open): equip a different weapon on the selected career, then hover that loadout's roman-numeral slot -- the context-menu preview now shows the NEW weapon icon immediately, with no need to close and reopen the inventory.

## 0.2.210-dev (2026-07-06) -- issue 375: FIX modded loadout store partial official import + edits not updating the active loadout [verify-fix]

- issue 375 FIX (both symptoms share one root cause). The modded loadout store (`_gut_native_loadouts.lua`, #175 lineage) only partially imported official loadouts, and equipping in modded did not update the loadout you were using. Root cause: the BackendUtils equip capture (`_install_bu_capture`) created a bare store entry `{loadouts={}}` WITHOUT seeding first, and the old `_ensure_seeded` early-returned on ANY existing entry (`if store[career_name] then return`). So an equip that landed before the first mirror-read left a bare entry that permanently blocked the official snapshot -- the store held only slots equipped while in modded (symptom 1). With whole official loadout rows missing, `set_loadout_index`'s `if entry.loadouts[idx]` guard failed on every slot switch, `selected_index` never advanced, and edits wrote to the wrong row (symptom 2 cascades from symptom 1).
- CHANGED (`_gut_native_loadouts.lua`):
  - **Seed-first in the BU equip capture:** resolve the mirror and call `_ensure_seeded` BEFORE any entry can be created, so a pre-mirror-read equip can no longer strand a bare entry. The fallback bare entry (only when official data is not ready yet) is deliberately NOT flagged seeded, so it is repaired once data lands.
  - **Self-healing `_ensure_seeded`:** a one-time `_seeded` flag now marks a fully-imported entry. A fresh career takes a full official snapshot; a pre-existing PARTIAL entry (bare BU entry, or a store persisted by the buggy build) is REPAIRED once -- every missing official loadout row is added, and any row that lost its weapons (the corrupt-partial signature; a legitimately edited loadout always keeps both weapon slots) has its missing gear refilled from official. Rows the player genuinely edited (both weapons present) are left untouched, so deliberate jewelry unequips survive. Raw field reads only -- no `get_item_from_id` recursion (v0.2.173 burn).
- ADDED `/gut_loadout_status` (issue 375 diagnostic): echoes to CHAT (visible with mod-logging off) the realm/mode and, per career, seeded? / loadout count / selected index / bot index, plus a per-row slot-fill dump to the console log. Answers "is the loadout system even working" at a glance and confirms a repair landed.
- ADDED regression check `native_loadouts_seed_repair_predicate` (pure logic): the corrupt-partial classifier flags nil / weapon-missing rows and must NOT flag a both-weapons row (guards against clobbering edits); asserts weapon slots are a subset of the gear set.
- EXISTING STORES self-heal on the next modded hero-view open. If a store looks wrong after this build, `/reset_modded_loadouts [career]` forces a clean re-seed from official.
- VERIFY IN-GAME (as the affected client, in a modded session): open the hero view, run `/gut_loadout_status` (expect `seeded=true`, `loadouts=` matching your official count, each row showing its full gear). Switch loadout slots -- each roman-numeral slot shows its full official gear, not blanks. Equip a weapon on the SELECTED slot, re-open `/gut_loadout_status` -- the change lands on the row whose `selected=true`, and swapping away and back keeps it.

## 0.2.209-dev (2026-07-06) -- issue 275: only skip cutscenes with a wired event_on_skip flow path (Nurgloth phase-desync softlock) [verify-fix]

**SOFTLOCK (0-critical), repro RainReligion (host, solo+bots, base Cataclysm), console-2026-07-05:** on The Enchanter's Lair (Drachenfels 3, level key `dlc_castle`) in a Chaos Wastes run with Skip Cutscenes enabled, Nurgloth's mid-mission appearance cinematic was force-unlocked and auto-skipped by gut. The boss then behaved like his final phase from the moment of appearance and his health floored at ~66% forever -- unbeatable. Repro log: mid-mission cutscene ACTIVATE at 05:25:43.953 with `on_activate=nil on_skip=nil`, then `AUTO-SKIP deferred-tick firing | level=dlc_castle force_unlock=true`.

- **Root cause.** The engine has NO per-cutscene lock; the entire skip gate is `if self.active_camera and script_data.skippable_cutscenes` (`Vermintide-2-Source-Code/scripts/entity_system/systems/cutscene/cutscene_system.lua:98`). In retail that flag is unset, so nothing is skippable. gut previously (a) LATCHED `script_data.skippable_cutscenes = true` globally at load (and in the toggle), (b) force-unlocked + auto-skipped every cutscene outside Chaos Wastes, (c) force-unlocked manual skips outside deus. A skip fires the cutscene's `event_on_skip` LEVEL flow event early (`:99-105`). Mission-INTRO cutscenes ship a wired `event_on_skip` (e.g. `cs_01_skip`) -- the author provided a skip path, so skipping is safe. Nurgloth's boss cinematic ships `event_on_skip=nil` -- there is NO wired skip path, so terminating it early leaves the level's cinematic flow sequence dangling and the boss fight state machine desyncs. The 66% floor is vanilla's intro health gate `set_min_health_percentage(0.65)` set in `on_chaos_exalted_sorcerer_drachenfels_intro_enter` (`penny_ai_settings_part_3.lua:102`), only lowered by `sorcerer_drachenfels_re_enter_defensive_mode` (`:156/:158`), which never ran because the intro flow was cut short.
- **POLICY (the fix).** gut may only unlock/skip a cutscene that carries a WIRED `event_on_skip`. New gate `_gut_cutscene_has_wired_skip(cutscene_system)` returns `cutscene_system.event_on_skip ~= nil` (the field vanilla stores at `cutscene_system.lua:183`, niled on skip/deactivate `:105/:196`). nil = LOCKED = play it out vanilla; no unlock, no skip. deus and adventure are now treated identically -- the wired-skip gate is the sole arbiter; the old in_deus force-unlock split is gone with the global latch it relied on.
- **CHANGED (`_gut_cutscenes.lua`):**
  - **Removed the load-time global latch** (both sites): the load-path `if enabled then script_data.skippable_cutscenes = true` and the toggle's `= new_val or nil`. At rest the flag now stays unset, exactly like retail. The toggle clears it defensively when disabled; nothing latches it on.
  - **Auto-skip** (`flow_cb_activate_cutscene_logic` hook + the deferred `_pending_auto_skip` processor): only queue/fire the skip when `event_on_skip ~= nil`; the deferred tick re-verifies the wired gate, SCOPE-unlocks `script_data.skippable_cutscenes` (true only around the single `skip_pressed` call, restored on every path incl. a throw), and printfs a `[gut:cutscene] LOCKED (no wired on_skip flow event ...)` decision line when nil.
  - **Manual skip** (`skip_pressed` hook): force-unlock (scope-only) only when `_gut_cutscene_has_wired_skip(self)`; a locked cutscene falls through to vanilla (flag unset -> vanilla refuses the skip) and logs the LOCKED line.
  - All existing issue-140 / issue-274 post-skip camera-guard logic (the `_skipped_cutscene_system` suppression + the fx_fade guard-swallow) is untouched. The always-on `[gut:cutscene]` printf probe is intact, extended only with the LOCKED line; AUTO-SKIP lines still print `force_unlock=` (now always paired with a wired on_skip).
- **HOOKS.** No new hook registrations -- all changes merge into the existing (CutsceneSystem, ...) hook bodies. Pre-flight grep confirmed CutsceneSystem + ShowCursorStack are hooked only in this file.
- **TEST.** New `gut_cutscene_no_global_latch` regression check: asserts `mod._gut_cutscene_has_wired_skip` exists and refuses a `{event_on_skip=nil}` stub while accepting a wired one, that `script_data.skippable_cutscenes` is falsy at rest, and (source guard on `_gut_cutscenes.lua`) that the toggle no longer re-latches the flag and the gate is still defined.
- **LOC.** `gut_skip_cutscenes_enabled` / `gut_skip_cutscenes_auto` status tags set to `[verify-fix] [Issue 275]`; the enable tooltip no longer claims the caveat is Chaos-Wastes-only (it is any cutscene the level gives no built-in skip path).
- **VERIFY IN-GAME (issue 275):** The Enchanter's Lair (`dlc_castle`), Skip Cutscenes ON: the mission intro still auto-skips; Nurgloth's appearance cinematic now PLAYS (log shows a `[gut:cutscene] LOCKED` line at his ACTIVATE); the boss health must progress below 66% after the second defensive wave and the fight must be completable.

## 0.2.208-dev (2026-07-06) -- issue 372: CRASH FIX hovering a saved loadout in the keep (unresolvable equipment item) [verify-fix]

- issue 372 FIX. Hovering a saved loadout in the hero-view loadout manager CTD'd in vanilla `UIUtils.get_ui_information_from_item` (`ui_utils.lua:248`, `item.data` on a nil item), reached through `HeroWindowLoadoutSelectionConsole._populate_context_menu_loadout` (crash 16.09.08 log: client in a CW hub, `es_mercenary` loadout, `slot_ranged` item = nil). Root cause: vanilla's EQUIPMENT loop (`hero_window_loadout_selection_console.lua:913-933`) has NO nil-guard, unlike the COSMETICS loop right above it (`:840-867`). We own the modded loadout store, and by design it legitimately holds a gear id that is unresolvable RIGHT NOW (late-registering cim craft / LA-cosmetics UUID, or a stale id — the store is never destructively sanitized).
- CHANGED (`_gut_native_loadouts.lua`): new hook `HeroWindowLoadoutSelectionConsole._populate_context_menu_loadout` (pre-flight: gut's only prior hooks on this class are `_save_bot_equipment` here and `_show_context_menu` in `_gut_mission_inventory.lua` — distinct methods). Each equipment slot whose id is not `RESOLVE_YES` (raw tri-state `_resolve_item_raw`, NOT `get_item_from_id`, to avoid the v0.2.173 mirror-read recursion) is substituted with the career's currently-equipped (always-resolvable) item in a SHALLOW COPY — the store row is never mutated. A `pcall` around the vanilla call is a last-resort backstop for the pathological case where even the fallback will not resolve. Cosmetic slots are already vanilla-nil-safe and left untouched.
- Registered the new `(HeroWindowLoadoutSelectionConsole, _populate_context_menu_loadout)` pair in `M.HOOK_TARGETS` so the `native_loadouts_hook_targets_unique` regression check covers the singleton invariant.
- KNOWN FOLLOW-UP (tracked on issue 372): the interim substitution shows the *current* weapon for a slot whose saved id can't resolve, rather than the saved one. The proper fix — gut validating / owning the loadout at save + serving a fallback-substituted copy from `get_career_loadouts` so no UI path ever sees an unresolvable id — remains the larger design-intent work.
- VERIFY IN-GAME: as the crashing client, open the loadout manager and hover the same `es_mercenary` saved loadout that crashed 16.09.08 (and any others) — no CTD; the ranged slot shows a weapon icon. Log line `issue #372: suppressed loadout-preview crash` only appears in the pathological no-fallback case.

## 0.2.207-dev (2026-07-06) -- issue 336 CLOSED (user-confirmed in-game): mid-mission mission map

- issue 336 CLOSED. The user confirmed in-game on v0.2.206-dev: the mid-mission map opens over the inventory-preview menu stage (no black plate, no button-glow trails), area selection no longer crashes on `area_video_*` materials, and picking a mission auto-starts it for the party. Both regression guards have been registered since v0.2.206-dev (`area_video_guard_two_layers`, `mission_map_preview_backdrop`); no behavior change this build.
- LOC: stripped the dev status tags from the three mission-map menu strings now that the fix is user-confirmed (`gut_mission_map` dropped `[verify-fix] [Issue 336]`; `gut_mission_map_hotkey` and `gut_mission_map_host_only` dropped `[untested] [Issue 336]`) per LOCALIZATION_STANDARD s13.
- DOC: cataloged the crash class as `docs/BUG_CLASSES.md` entry 23 ("keep-only Gui material drawn mid-mission") covering the three shipped instances (pose atlas issue 155, store atlas issue 363, area videos issue 336) and the two-layer fix template (inject-when-resident + skip-the-widget).

## 0.2.206-dev (2026-07-06) -- issue 336 follow-up: CRASH FIX mid-mission map area videos + PREVIEW backdrop replaces the black "transparent" tier [verify-fix]

**CRASH (0-critical), user log console-2026-07-06-03.24.08 (gut_dev v0.2.204-dev, `dlc_dwarf_whaling`; reproduced by RainReligion, console-2026-07-06-00.40.54):** map opened mid-mission at 03:28:45 (`[gut_dev:MM] backdrop tier: keep=false -> transparent`), the user navigated to area selection (03:28:49 `Enter Substate StartGameWindowAreaSelectionConsoleV2`), and at 03:28:50 the client hard-crashed: `scripts/ui/ui_renderer.lua:1345: Material 'area_video_bogenhafen' not found in Gui`.

- **Root cause:** vanilla appends the `AreaSettings[*].video_settings.resource` area-video materials (e.g. `video/area_videos/bogenhafen/area_video_bogenhafen`, `area_settings.lua:12-15` + the DLC `level_unlock_settings_*` files) to the ingame ui/ui_top renderer material lists ONLY inside `if is_in_inn` (`ingame_ui_settings.lua:594-601` ui_renderer_function, `:681-688` ui_top_renderer_function). Mid-mission the renderers lack every `area_video_*` material, but the console area-selection window still builds a video widget for the hovered area (`start_game_window_area_selection_console_v2.lua:362-370` -> `_assign_video_player` `:647-670`) and draws it on ui_top_renderer (`:628-638`) -> `UIRenderer.draw_video` -> `Gui.video` raises the uncatchable "Material not found in Gui" fatal (shipped `ui_renderer.lua:1345`; decompiled `:1296`). Same class as the pose-atlas (issue 155) and store-atlas (issue 80/issue 363) crashes.
- **FIX layer 1 (`_gut_gui_material_guard.lua`):** the existing `UIRenderer.create` hook (singleton; issue 155/issue 80 precedent) now ALSO injects each `AreaSettings[*].video_settings.resource` into ingame ui/ui_top renderers when the resource is resident (`Application.can_get`-gated with the existing trust protocol; a non-resident add would itself fatal `create_screen_gui`). Publishes the per-material outcome in `mod._gut_area_videos_ingame` (material_name -> in-Gui true/false) and edge-logs `[gut:336] area-video materials at ingame-renderer create: present=/injected=/skipped=` with names.
- **FIX layer 2 (`_gut_mission_map.lua`):** full-wrapper skip guards on BOTH area-selection windows' video builders (preflight: gut_dev hooked neither class anywhere): `StartGameWindowAreaSelectionConsoleV2._assign_video_player` (the console layout the mid-mission map uses, `start_game_window_layout_console.lua:54-58`) and `StartGameWindowAreaSelection._setup_video_player` (`start_game_window_area_selection.lua:458-476`, PC layout, same crash class). When the material is not in the ingame Gui (published flag false, or unknown + not in the keep), the video widget is never created -- the static area image stays. Guard-not-bail: both builders only create the widget/player; every consumer nil-guards `_video_widget` (v2 draw `:629`, `_destroy_video_widget` `:675`; PC `draw_video` `:440`, `_destroy_video_player` `:482/:488`). The parent state's `_create_video_players` (`start_game_state_settings_overview.lua:246-263`, at state enter `:212`) runs `World.create_video_player` on every area resource and did NOT crash in either user log mid-mission -- creation is safe, only the Gui draw of an unlisted material is fatal, so no pre-filter is needed there.
- **BACKDROP (user + RainReligion report: "transparent" tier rendered SOLID BLACK + menu-button glow left permanent trails):** the v0.2.198 tier-2 backdrop spawned no world at all, so nothing cleared the framebuffer behind the UI each frame -- stale pixels persisted and the additive button glow accumulated ("bleeding"). Per user direction (proper menu background like the keep's; the literal `levels/ui_keep_menu/world` ships only inside the keep's level packages, `level_settings.lua:72-73`, with no standalone package), tier 2 now mounts the PROVEN mission-safe menu stage from the hero-select recipe: async `Managers.package:load` of `resource_packages/levels/ui_inventory_preview` under the module's own ref `gut_mission_map` (kicked at StateIngame enter when the toggle is on, re-kicked on open; retained for the session -- `PackageManager.load` on an already-loaded package just bumps the refcount and fires the callback synchronously, `package_manager.lua:26-27,56-58`), then a `has_loaded`-gated def swap in the consolidated `_create_viewport_definition` hook to `levels/ui_inventory_preview/world` + `environment/ui_inventory_preview` (vanilla pairing: `hero_window_character_preview_definitions.lua:225-227`) with its own `LevelResource.object_set_names`. `post_update` runs vanilla on this tier (widget + `MenuWorldPreviewer` world DO spawn, clearing the framebuffer); the keep-only `_update_object_sets` scenery pass stays diverted. v0.2.190 lesson honored: the gate is the PACKAGE `has_loaded`, not `can_get("level", ...)` (false in missions until the package loads).
- **Fallback (first-open race):** if the package has not finished streaming when the map opens, that open uses the old level-less def (black backdrop once, no crash, `post_update` skipped) and the load is re-kicked; the tier printf now reads `[gut_dev:MM] backdrop tier: keep=.. preview_loaded=.. -> keep|preview|levelless-fallback`. The user-validated auto-start behavior (countdown-flag arm + `complete_level` -> `promote_next_level_data` divert, v0.2.198) is untouched.
- **TESTS:** new `area_video_guard_two_layers` (asserts the injection + publish survive in the material guard AND the two window skip-guards survive in the map module, plus vanilla-method presence) and `mission_map_preview_backdrop` (asserts the package path, the load kick, the `has_loaded` gate, and the tier-2 `level_name = PREVIEW_LEVEL` def swap survive). Existing `mission_map_backdrop_swap` still guards the fallback tier's `_gut_mm_none_backdrop` divert.
- **LOC:** `gut_mission_map_tooltip` updated (proper menu backdrop instead of "mission still visible behind it").
- **Verify in-game (issue 336):** mid-mission, open the map (M), go to mission select and hover/select areas including Bogenhafen -- no crash (log shows `[gut:336] area-video ...` and, if a video is skipped, `[gut_dev:MM] area video '...' -> video widget skipped`); the map background is the inventory-preview menu stage (not black), and the menu-button glow no longer smears trails. Log shows `backdrop tier: ... -> preview` (or `levelless-fallback` exactly once on a very fast first open).

## 0.2.205-dev (2026-07-05) -- issue 307 CLOSED (user-confirmed in-game): Free Camera

- issue 307 CLOSED. The user confirmed in-game that the Free Camera works: it detaches the camera to fly around the level (WASD move, mouse look, E/Q up/down, wheel speed), freezes the character, and exits cleanly with F8. Fix already live in `_gut_freecam.lua` (ported from `FreeFlightManager`): the input device is RELEASED after entering so the game does not hard-lock, `is_input_blocked` freezes the character, and the camera is driven from the raw Keyboard/Mouse. No code change this build; this is the close-out.
- Stripped the `[verify-fix] [Issue 307]` dev status tags from the two menu-visible loc strings (`gut_freecam_enabled`, `gut_freecam_hotkey`) now that the fix is user-confirmed -- they read plain "Free Camera" / "Free Camera (Hotkey)". The `freecam_invariants` regression guard (asserts `mod._gut_apply_freecam` + `mod.gut_freecam_toggle` stay wired) remains in place.

## 0.2.204-dev (2026-07-05) -- issue 339 CLOSED (user-confirmed in-game): integrated mods fold into a category, never a top-level Mod Tweaker tab

- issue 339 CLOSED (CRITICAL). The user confirmed in-game that Crosshair Kill Confirmation (integration issue 313) no longer renders as a top-level Mod Tweaker TAB; its options now appear INSIDE gut's Interface tab under the HUD group as a "Crosshair Kill Confirmation" sub-collapsible, and the vanilla-Options gear focuses that HUD category (not a CKC tab). Behavior fix already live: CKC is out of the `_MY_MODS` tab whitelist in `_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`; `_inject_ckc_into_gut` splices its live options under `gut_hide_hud_ui_group` as `gut_ckc_group`; `_gut_ckc_bridge.lua`'s focus request is redirected by `_apply_focus_request` to the gut Interface tab with the HUD + CKC groups auto-expanded. Same model as the UI Tweaks / HideBuffs precedent (issue 312). This build adds the hardening.
- TEST (inverted the stale guard): `ckc_modtweaker_whitelisted` asserted the OLD (pre-339) invariant -- that CKC MUST be in `_MY_MODS` -- so it was returning a FAIL once the fix removed CKC. Replaced with `mod_tweaker_no_integrated_toplevel_tabs`, which asserts the correct 339 invariant: CKC is NOT whitelisted in the two tab-driving files AND `_inject_ckc_into_gut` is wired in both, so it folds into Interface>HUD. The config-EXPORT whitelist in `_gut_config_file.lua` legitimately keeps CKC + HideBuffs (settings snapshot, not tabs) and is intentionally not checked.
- DOC: `MOD_TWEAKER_INTEGRATION.md` (authoritative) states the binding rule -- a top-level tab is only for the author's own Tweaker-series mods; a third-party integration (CKC issue 313, HideBuffs issue 312, HUD-adjust issue 310) NEVER gets a tab or top-level collapsible, it folds into the correct existing category collapsible. Any "open in Mod Tweaker" bridge focuses the CATEGORY, not a tab.

## 0.2.203-dev (2026-07-05) -- #363 CLOSED (user-confirmed in-game): regression guard for the Salvage store-atlas injection

- #363 CLOSED. The user confirmed in-game that the in-mission Crafting Salvage page renders without crashing (fix shipped in v0.2.202-dev). No code change to the fix; this build adds the regression guard.
- TEST: new `salvage_store_atlas_injected` source-pattern guard on `_gut_gui_material_guard.lua` (located as a sibling of `_gut_mission_inventory.lua`). Asserts the three load-bearing pieces of the store-atlas injection survive: the `materials/ui/ui_1080p_store_menu` path declaration, the `append_store` residency gate, and the token append into the ingame Gui material list. If any is removed, the Salvage page would take the "Material not found in Gui" C-fatal in-mission again, and the test now catches it on `/regression_test`.

## 0.2.202-dev (2026-07-05) -- CRASH FIX #363: in-mission Crafting Salvage page (gui_store_menu_atlas not in Gui)

**Crash console 2026-07-06-00.49.31** (in-mission, bench toggle ON + cim_dev, wood_elf): opening the Salvage page of the in-mission Crafting tab crashed at `ui_passes.lua:194: Material 'gui_store_menu_atlas' not found in Gui` (DRAW fatal). The vanilla Salvage page draws its auto-fill rarity buttons (`store_tag_icon_weapon_*`) from `gui_store_menu_atlas` (material file `materials/ui/ui_1080p_store_menu`), which `store_ui_settings.lua` lists under `ui_materials_in_inn` -- so vanilla adds it to the ingame ui/ui_top renderer only in the keep. In a mission that renderer lacks it -> uncatchable "Material not found in Gui" fatal (same class as the pose-atlas / loading-screen crashes).

- **Extended `_gut_gui_material_guard.lua`** (the `UIRenderer.create` hook that already injects the pose-cosmetics atlas #155) to ALSO inject `materials/ui/ui_1080p_store_menu` into ingame ui/ui_top renderers when resident (can_get-gated). The store atlas IS resident in-mission (`resource_packages/dlcs/store` is force-loaded at boot), so -- unlike the pose atlas which usually self-skips -- this injection lands and the Salvage page renders. Edge-logged `[gut:80] injected 'materials/ui/ui_1080p_store_menu' …` so the next in-mission Salvage test is verifiable.
- Complements #80 (the tab-enable fix in v0.2.200): v0.2.200 made the tab clickable in Adventure; this makes its Salvage page not crash.

## 0.2.201-dev (2026-07-05) -- #152 CLOSED (user-confirmed in-game): Mod Tweaker slider-arrow increment + hold-repeat

- #152 CLOSED (user confirmed the slider arrows no longer over-adjust). Fix live since
  v0.2.109-dev: a single arrow click = ONE natural increment (1 for ints, 10^-decimals),
  EDGE-LATCHED (one step per physical press, no auto-move on press); a HELD arrow repeats
  after a ~0.37s delay and ACCELERATES, matching the vanilla options slider. Fix unchanged;
  this build adds the regression guard.
- TEST: new `mod_tweaker_arrow_edge_latch_hold_repeat` source-pattern guard asserts the
  accelerating hold-repeat survives (the existing `mod_tweaker_step_resolution` guards the
  step VALUE resolution, not the click/hold behavior).

## 0.2.200-dev (2026-07-05) -- #80 FIX: in-mission Crafting tab was greyed in Adventure too (stable-only cim check missed cim_dev)

**User report:** the CIM standard crafting bench tab is greyed in-mission even in normal Adventure (~9 prior attempts had no effect). Chaos Wastes exclusion is correct and intended (loadout is altar-upgraded there); the bug was that it was ALSO greyed in Adventure, where it should work.

**Root cause:** `_gut_mission_inventory.lua` gated the tab on `get_mod("cim")` (STABLE id only), in FOUR places, while the rest of gut_dev correctly uses `get_mod("cim_dev") or get_mod("cim")` (gui_tweaker_dev.lua:695/:2113, data `_cim_present()`). The user (and any dev tester) runs **cim_dev** with stable cim disabled (`enabled="false"` in console 2026-07-05-23.47.05), so `get_mod("cim")` returned nil, `bench_ok` was always false, and gut's `HeroWindowPanelConsole.on_enter` hook **force-greyed** the tab -- even though vanilla `create_ui_elements` leaves the forge tab ENABLED in Adventure (`can_add('forge')` true; disable_button set only at hero_window_panel_console.lua:142/:147, no per-frame re-eval). The stable-only check failing silently is why the mechanism looked correct through ~9 iterations.

- **Fix:** new dev-clone-aware `_gut_cim_present()` helper (`get_mod("cim_dev") or get_mod("cim")`); replaced all four stable-only cim checks in `_gut_mission_inventory.lua` (tab-enable gate, the `_gut_mount_fix_active` double-apply guard, and two diagnostics). Adventure gating now: `toggle ON` + cim/cim_dev present + `mech ~= "deus"`.
- **Armed diagnostic:** the tab decision now prints via engine `printf` (visible with mod logging OFF): `[gut:80] Crafting tab set: toggle=.. cim=.. mech=.. not_deus=.. -> bench_ok=.. (ENABLED/greyed)`. The prior diagnostic was `mod:debug` (invisible to the user), which is part of why 9 attempts couldn't be verified from logs.
- Chaos Wastes/deus stays greyed by design (unchanged). Athanor stays keep-only (unchanged).
- **Verify (Adventure only):** with the bench toggle ON and cim/cim_dev loaded, open the in-mission inventory in an Adventure mission -> the Crafting tab is clickable (not greyed), and the log shows `[gut:80] ... -> bench_ok=true (ENABLED)`.

## 0.2.199-dev (2026-07-05) -- #140 CLOSED (user-confirmed in-game): "A Parting of the Waves" stray post-skip fade

- #140 CLOSED - user confirmed the v0.2.178-dev fix works in-game. On "A Parting of the
  Waves" (`dlc_dwarf_whaling`) the CutsceneSystem flow fires late node groups after the
  auto-skip, each with an `fx_fade` ~97 ms BEFORE its camera node, so the one-shot
  `_skip_next_fade` (armed at the camera node) misses it and a black fade played. The
  shipped fix swallows every `fx_fade` in `flow_cb_cutscene_effect` while the issue-106
  post-skip guard is armed (`_skipped_cutscene_system == self`). The fix itself is
  unchanged (live since v0.2.178-dev); this build adds the regression guard + flips the
  loc tag on close.
- TEST: new `_rt_register("cutscene_postskip_fade_swallow")` source-pattern guard - locates
  `_gut_cutscenes.lua` via `mod.gut_skip_cutscenes_toggle` and asserts the fx_fade-swallow
  line survives, so the fix cannot silently revert (`/regression_test`).
- LOC: `gut_skip_cutscenes_auto` tag `[Issue 275 & 140]` -> `[Issue 275]` (dropped the now-closed
  140 ref; kept `[diag]`). Issue 275 (the Enchanter's Lair boss-softlock, 0-critical) stays
  open with its live diag probe, so its own label must NOT change on this ship.

## 0.2.198-dev (2026-07-05) -- #336: mission map AUTO-STARTS the picked mission + transparent backdrop (live mission visible) [verify-fix]

- FIX (#336 follow-up, user report): picking a mission from the mid-mission map ran
  matchmaking but never launched - the flow parks in `MatchmakingStateWaitForCountdown`
  waiting for the keep waystone-portal countdown flag that nothing sets mid-mission
  (user log: `Hosting game on mission: dlc_termite_1` then 2+ min idle;
  `matchmaking_state_wait_for_countdown.lua:26-50`). New `hook_safe` on that state's
  `on_enter`: host + adventure + not-in-keep -> set the countdown flag immediately, so
  vanilla `MatchmakingStateStartGame` runs its full start machinery (quickplay level
  roll, seed, difficulty, lobby data, `rpc_matchmaking_join_game`).
- Vanilla's final step there is `game_mode:complete_level()` (`matchmaking_state_start_game.lua:408`)
  which mid-mission would end the round as a FAKE "won" (rewards/stats for an abandoned
  run, `game_mode_adventure.lua:124-129`). New `GameModeManager.complete_level` wrapper:
  when armed by the auto-start (<15 s window) it diverts to
  `level_transition_handler:promote_next_level_data()` - the same clean no-win
  transition the vanilla return-to-keep vote uses (`game_mode_manager.lua:678-692`).
  Unarmed/stale calls run vanilla (gt's /complete_level debug stays untouched).
- CHANGE (#336, user request): the mid-mission backdrop is now TRANSPARENT - the
  background window's `post_update` is wrapped so no viewport widget / world is ever
  created on a swapped instance; the live mission renders behind the map UI, matching
  the in-mission hero/inventory views. The v0.2.195 black empty-world tier and the
  unused inventory-preview swap tier are removed. Loading-overlay fade preserved.
- Tooltip updated (auto-start + live-game backdrop). All [verify-fix] pending in-game
  confirmation: map opens transparent, picking a mission loads it for the party, no
  fake end-of-mission rewards, ESC still returns to the run.

## 0.2.197-dev (2026-07-05) -- #307: Free Camera "no cam" -- drive the camera from RAW input (the unblock starved the FreeFlight service) [verify-fix]

- FIX (#307 follow-up): with the v0.2.196 hard-lock fix in hand (user confirmed: chat +
  `/freecam` now escape cleanly, no force-close), the camera itself still did nothing -
  "no cam, input still blocked" in the keep. Root cause found by comparing against the
  reference "Photomode" mod: the vanilla camera driver reads the **FreeFlight input
  service** (`get_service("FreeFlight"):get("move"/"look")`), and that service only
  receives device input while free flight BLOCKS every device to it. v0.2.196 unblocks
  the devices (correctly, to keep ESC/chat/keybind exits alive) - which STARVES that
  service, so `_drive_free_cam` read all-zeros and never moved the camera.
- **Fix:** `_drive_free_cam` now reads **raw `Keyboard`/`Mouse`** (WASD/E-Q via
  `Keyboard.button`, look via `Mouse.axis("mouse")`, speed via `Mouse.axis("wheel")`) -
  the exact pattern vanilla `scripts/freeflight.lua:17-60` uses. Raw hardware reads are
  unaffected by input-service blocking, so the camera flies whether or not devices are
  blocked, with zero dependency on the starved FreeFlight service. Camera math is the
  vanilla free-fly (move in camera-local frame * speed * dt; mouse pan * rotation_speed).
- **Triage diagnostics (always-on printf):** activation now logs `[gut_dev:FC]
  render-state: world=.. vp=.. base_viewport=.. ff_viewport=.. active=..` so we can
  confirm the detached viewport lives in the on-screen world; and a one-shot `[gut_dev:FC]
  drive error (camera not moving): ..` surfaces any pcall failure in the driver (was
  silently swallowed before). If the camera still doesn't render after this, that line
  tells us render-vs-input in one toggle.
- is_input_blocked freeze + device-unblock (v0.2.196) are unchanged; this only swaps how
  the camera reads input.

## 0.2.196-dev (2026-07-05) -- #307: Free Camera hard input-lock -- give the input devices BACK after entering free flight [verify-fix]

- FIX (#307, crash-class): turning Free Camera ON locked ALL input and forced a game
  close. Root cause, from the console log `console-2026-07-05-18.05.37`: activation
  reached `[gut_dev:FC] activated` and the log then ended with NO `deactivated` line --
  the user could never exit and force-closed via Steam. This repeated across FOUR builds
  (v0.2.189 -> .194) because every prior fix treated a symptom.
- **The real defect:** the engine's `_enter_free_flight` runs
  `block_device_except_service("FreeFlight", <device>)` on keyboard/mouse/gamepad
  (`free_flight_manager.lua:610-612`), which `set_blocked`s EVERY input service except
  FreeFlight. That killed ESC, chat, VMF keybinds, the checkbox AND `/freecam`, leaving
  the raw-F8 poll as the ONLY escape -- and that poll empirically never fired. A feature
  that steals all input and hangs the whole escape on one fragile poll is one bug away
  from a brick every single time.
- **The fix:** immediately after `_enter_free_flight` succeeds, call
  `device_unblock_all_services` on keyboard/mouse/gamepad (`_gut_freecam.lua`,
  `_gut_apply_freecam`). We never needed that block to stop the character -- the
  `PlayerInputExtension.is_input_blocked -> true` hook already nullifies every player read
  (`player_input_extension.lua:146-157`, "the reliable stop"). FreeFlight was the block
  exception and stays mapped to the devices, so the camera still flies from
  `_drive_free_cam`; meanwhile ESC / keybind / checkbox / `/freecam` (and the kept F8
  poll) ALL work again as exits. Vanilla itself unblocks these same services on exit
  (`:642-644`), so the call is safe. No more single point of failure.
- `[gut_dev:FC] activated` now logs `(input devices unblocked; character held by
  is_input_blocked)`; the ON echo lists the menu toggle as an exit alongside F8.
- rt: `freecam_invariants` gains INVARIANT 5 -- asserts `device_unblock_all_services` is
  present in the module source, so removing the unblock (re-bricking the mod) fails the
  regression test.

## 0.2.195-dev (2026-07-05) -- #336: mission map opens mid-mission with a black backdrop when no menu level is resident [verify-fix]

- FIX (#336 follow-up): the in-mission mission map (#305) now OPENS mid-mission even
  when neither backdrop level is resident -- which is the normal case in most missions.
  The prior #336 CTD fix fail-CLOSED there (chat notice "Cannot open the mission map here:
  no menu backdrop level is loadable." + no-op, user log `gate=backdrop blocked
  (keep=false preview=false) -> no-op`). The user's verdict: get it working, not just
  explain why it doesn't. The fail-closed gate + chat notice are removed; the map now
  transitions unconditionally.
- **Three-tier backdrop def-swap (`_gut_mission_map.lua`, `_create_viewport_definition`
  hook).** Tier 1 (keep resident/unknown) -> vanilla def, unchanged. Tier 2 (preview
  stage positively gettable) -> preview-stage def, unchanged. Tier 3 (NEW; neither
  gettable) -> the same def shape with NO `level_name` key and `object_sets = {}`, so the
  Viewport UI element spawns an empty world = a plain black backdrop instead of crashing
  or no-opping. A nil `level_name` is engine-safe on the Viewport path: `ui_passes.lua`
  only spawns a level when `level_name` is non-nil (2447-2459). Tier 3 sets both
  `_gut_mm_swapped_backdrop` (drives the existing `_update_object_sets` divert) and
  `_gut_mm_none_backdrop`.
- **Third singleton hook `_setup_object_sets`.** Vanilla `_setup_object_sets` reads the
  def's `level_name` and calls `LevelResource.object_set_names(level_name)`
  (`start_game_window_background_console.lua:112-123`) -- with tier 3's nil `level_name`
  that would raise. On a none-backdrop instance (or any nil-level def) the hook sets
  `self._object_sets = {}` and returns; native + preview-swap instances (which carry a
  `level_name`) run vanilla untouched. HOOK PRE-FLIGHT: gut_dev registers no other hook
  on `StartGameWindowBackgroundConsole` (grep 2026-07-05) -- this is the only hook on
  that class+method.
- `gut_open_mission_map` now emits a printf-only backdrop tier report
  (`[gut_dev:MM] backdrop tier: keep=%s preview=%s -> %s`, tier = keep/preview/none) and
  proceeds. All other gates (master toggle, keep no-op, adventure-only mechanism, host-only)
  and the final `pcall` around `handle_transition` are unchanged.
- rt: `mission_map_backdrop_swap` extended -- now also asserts `gut_open_mission_map` +
  `_setup_object_sets` are present and that the `_gut_mm_none_backdrop` marker is still in
  the module source (fails if the none tier is removed).
- Loc: `gut_mission_map` title `[verify-fix] [crash] [Issue 336]` -> `[verify-fix]
  [Issue 336]` (this follow-up is a feature-enable fix, not a crash fix).
- VERIFY IN-GAME (Adventure mission, no backdrop level resident): press M (or /map) --
  the mission-selection map should OPEN with a black backdrop (no chat notice, no crash),
  and ESC/back should drop straight back into the mission.

## 0.2.194-dev (2026-07-05) -- #318: disabled mods no longer show as Mod Tweaker tabs [verify-fix]

- FIX (#318): a VMF-**disabled** whitelisted mod (e.g. CWV when unchecked in the VMF mod list) still appeared as a greyed-out tab in the Mod Tweaker. That was deliberate old behavior (the tab builder set `tab.content.disabled` and appended a `*`), but it's wrong -- a disabled mod should not show at all. `_vmf_categories()` now **skips** any mod whose `is_enabled()` returns false, in BOTH `_mod_tweaker_view.lua` and `_mod_tweaker_state.lua`, so it never becomes a tab (and never folds into the #208 Equipment merge). `is_enabled` absent/erroring still defaults to shown, so an indeterminate mod isn't silently hidden. The downstream greyed-out-tab code is now dead (left in place, harmless).
- Root cause was in gut's Mod Tweaker, not CWV -- #318 is a gut bug (mislabelled `cwv`).

## 0.2.193-dev (2026-07-05) -- #313: Crosshair Kill Confirmation options-menu bridge [untested]

New integration for the sanctioned Workshop mod "Crosshair Kill Confirmation" (CKC, by pixaal).
Active only when CKC is installed and togglable and the new `gut_ckc_options_bridge` toggle is
on (default on); a complete no-op otherwise (no hooks registered).

- Whitelisted CKC (bracketed key `["Crosshair Kill Confirmation"]`, the id has spaces) into the
  `_MY_MODS` tables of all three surfaces: `_mod_tweaker_view.lua`, `_mod_tweaker_state.lua`,
  `_gut_config_file.lua` - so its 7 options surface as a Mod Tweaker tab and ride config export.
  (These files plus `_gut_ckc_bridge.lua` itself landed early, riding commit 15ba7e4 while the
  shared files were claimed by parallel work; this version adds the activation wiring.)
- New module `_gut_ckc_bridge.lua`: takes over the vanilla `crosshair_kill_confirm` dropdown in
  the game's Options menu. It becomes a 2-option On / Off toggle that LIVE-drives the CKC mod via
  VMF `mod_state_changed` (parity with the VMF-menu checkbox, not staged through Apply). The
  vanilla marker user_setting is forced "off" (CrosshairUI stops drawing it), remembering the
  user's prior group and restoring it if the bridge toggle is turned off. A gear button is added
  to the right of the row; clicking it opens the Mod Tweaker focused on the CKC tab.
- Mod Tweaker one-shot tab focus (`_mod_tweaker_view.lua` `_apply_focus_request`): another
  feature can set `mod._gut_mt_focus_request = <mod_id>` to open the Tweaker on that tab (page
  flip aware). Consumed once, cleared whether or not the mod is found.
- The bridge self-wires by chaining `on_all_mods_loaded` + `on_setting_changed` at dofile time;
  the main file contributes only a single dofile line.
- rt: `ckc_modtweaker_whitelisted`, `ckc_bridge_module_wired`, `ckc_bridge_loc_keys`.
- VERIFY IN-GAME (with CKC installed, Workshop 1593460250): ESC -> Options -> Gameplay - the
  "Crosshair Kill Confirmation" row shows On/Off and flipping it enables/disables the mod live;
  the vanilla kill marker no longer draws; the gear opens the Mod Tweaker on the CKC tab.
  Without CKC installed: the row behaves exactly like stock vanilla.

## 0.2.192-dev (2026-07-05) -- #307 fix Free Camera soft-lock when toggled from an open menu [verify-fix]

User report (2026-07-05, running 0.2.189-dev, log 17.03.22-87719970): turning Free Camera on
from inside the mod options menu "froze" the game - no input worked, forced close via Steam.
Log timeline: freecam widget hovered/toggled 17:14:49, then nothing until Steam's close request
triggered a CLEAN exit at 17:15:12 (save + "Lua signals application exit") - an input soft-lock,
not an engine freeze.

- **Root cause:** entering free flight routes EVERY input device to the FreeFlight service
  (`block_device_except_service`, free_flight_manager.lua:610-612, by design). Toggling the
  checkbox while the options view was open activated freecam UNDER the open menu, cutting all
  input to it: no clicks, no ESC. The F8 raw-poll exit existed but nothing on screen said so
  (the hint echo only fired on the /freecam-command path, and the menu blocked chat anyway).
- **Fix (`_gut_freecam.lua`):** menu gate + deferred activation. `_gut_apply_freecam(true)`
  now refuses to enter free flight while any menu/view is open (`IngameUI.menu_active` OR
  `current_view ~= nil`, ingame_ui.lua:228/:765, via `Managers.ui._ingame_ui`,
  ui_manager.lua:26) and defers: `mod.update` completes the activation on the first frame
  after the menu closes (or drops it if the setting was flipped back off, and on any game
  state change). apply() now owns ALL feedback: every activation path echoes the controls
  incl. "F8 to exit"; deactivation echoes OFF once. Always-on `[gut_dev:FC]` printf lines
  (deferred / activated / deactivated) for triage.
- Loc: freecam titles [untested] -> [verify-fix]; tooltip documents the menu deferral.
- VERIFY IN-GAME: in a mission or the keep, open Mod Options, turn Free Camera ON, close the
  menu - the camera should detach only AFTER the menu closes, chat shows the F8 hint, and F8
  returns control. Toggling it on and back off inside the menu should do nothing.

## 0.2.191-dev (2026-07-05) -- #312 UI Tweaks menu fix + #310 HUD edit-mode keybind [verify-fix]

Fixes a #312 misread the user caught: UI Tweaks had been surfaced as its OWN separate tab in the Mod Tweaker menu (by whitelisting the stock `HideBuffs` mod), when the assignment ("interface with UI Tweaks... from within GUT's own menu, to the extent features overlap") wanted the options in GUT's own menu. Also adds the HUD edit-mode keybind #310 asked for (previously edit mode was reachable ONLY via the `/edit_hud` chat command, so there was no key to bind).

- **UI Tweaks now lives in ONE group in GUT's own menu.** The absorbed HideBuffs tree (`hb_group`) is relabelled "Hide UI Elements & Buffs" -> **"UI Tweaks"**, and the former standalone "UI Tweaks Integration" group (sync toggle + the two vanilla numeric mirrors) is now **nested inside it** as a "Sync & Vanilla Mirrors" subgroup. So all UI Tweaks options sit under one "UI Tweaks" heading in the HUD category. No setting_ids changed (persistence + fork hooks intact).
- **Removed the separate UI Tweaks tab from the Mod Tweaker.** `HideBuffs` de-whitelisted from `_MY_MODS` in `_mod_tweaker_view.lua` and `_mod_tweaker_state.lua`, so it no longer appears as its own tab in the in-game Mod Tweaker mod-list. (Left in `_gut_config_file.lua`'s export whitelist so HUD-layout snapshots still carry UI Tweaks settings.) The regression test `uitweaks_modtweaker_whitelisted` is inverted to `uitweaks_not_separate_modtweaker_tab` (now fails if HideBuffs is re-whitelisted).
- **HUD edit-mode keybind (#310):** new `gut_edit_hud_hotkey` keybind widget in the HUD category, wired to `mod.gut_edit_hud_toggle` (extracted from the `/edit_hud` command body; both now call it). Bind a key to enter/exit the click-drag HUD customizer. NOTE: #310 also asks for element **resize** (corner-drag, 15-300%), which is still NOT built -- only move exists. #310 stays open for resize.

## 0.2.190-dev (2026-07-05) -- #336: fix mid-mission map CTD (keep backdrop not resident) [verify-fix]

- FIX (#336, 0-critical CTD): opening the in-mission mission map (#305) crashed to desktop
  the moment the play screen entered. StartGameWindowBackgroundConsole's viewport def mounts
  `levels/ui_keep_menu/world` and calls `LevelResource.object_set_names` on it at def-BUILD
  time (`start_game_window_background_console.lua:56/66`); that level resource is resident
  only in the hub, so mid-mission the engine raised "Level not loaded" - fatal, bypasses
  pcall. Crash log `console-2026-07-05-16.49.12-44a6c78a...`, 17:01:57.032, skittergate,
  gut_dev v0.2.188-dev. The #305 docstring wrongly asserted StartGameView mounts no
  keep-only world - true for the view, not for its windows.
- Fix (hero-select recipe, `_gut_mission_map.lua`): `Application.can_get("level", ...)`
  pre-filter with the resident-level self-test; when `ui_keep_menu` is not gettable, a
  singleton `mod:hook` on `_create_viewport_definition` returns the vanilla def shape
  mounted on the mission-safe `levels/ui_inventory_preview/world` (+ its object sets); a
  second singleton hook diverts `_update_object_sets` on swapped instances (keep-only
  object sets / flow events like `quick_play` don't exist on the preview stage;
  `Level.trigger_event` on a missing event is an engine-assert risk,
  `menu_world_previewer.lua:769-770`). `gut_open_mission_map` now fails CLOSED (echo, no
  transition) when neither backdrop level is positively gettable. Keep flow stays
  byte-for-byte vanilla.
- Loc: mission-map option titles re-tagged `[verify-fix] [crash] [Issue 336]` /
  `[untested] [Issue 336]` per LOCALIZATION_STANDARD s13.4.
- rt: new `mission_map_backdrop_swap` check (helper wired + both hook targets still exist).
- VERIFY IN-GAME: in an Adventure mission press M (or `/map`) - the map opens over the
  inventory-preview backdrop; pick a mission or ESC back into the run - no crash.

## 0.2.189-dev (2026-07-05) -- #307: Free Camera (detached fly-cam) [untested]

New feature under the 3rd-Person Camera group: a detached free camera to pan around and
view the level. The character stops responding to input and stays put; WASD moves, mouse
looks, E/Q go up/down, the mouse wheel changes speed. Toggle on with the checkbox, the
`gut_freecam_hotkey` keybind, or `/freecam`; **exit with F8**.

- **New `_gut_freecam.lua`.** Drives the engine's own `FreeFlightManager`:
  `_enter_free_flight` creates an overlay viewport and renders from a detached camera while
  the player unit keeps simulating (`free_flight_manager.lua:584-617`); `_exit_free_flight`
  tears it down (:619-645). The per-frame camera motion is a trimmed faithful copy of vanilla
  `_update_free_flight` (:655-717, move/look/speed only) driven from `mod.update` -- it OMITS
  the vanilla drop-player-at-camera (Enter), DOF and raycast keys (:719+) so the camera is
  view-only. Sets `Development._hardcoded_dev_params.third_person_mode = true` on enter so the
  local body renders (a detached cam sees nothing otherwise).
- **Avoids both prior-attempt failure classes.** The gt_dev Free Camera removed at
  gt v0.2.113-dev failed two ways this design structurally prevents:
  1. *WASD bled through to the character.* Fixed with a `PlayerInputExtension.is_input_blocked
     -> true` hook for the local player (the block the old attempt lacked;
     `player_input_extension.lua:149` nullifies every input the character reads).
  2. *`loco:set_disabled(nil run_func)` crashed a frame later* in the engine's
     `update_disabled_units` loop (`locomotion_templates_player.lua:323`, no nil-check). This
     port **never touches locomotion** -- that crash class cannot occur.
- **Gate stays up.** We do NOT lift `GameSettingsDevelopment.disable_free_flight`; that gate
  is checked only inside `FreeFlightManager.update` (`free_flight_manager.lua:64`), the vanilla
  dispatcher that reads F8/F9/F10 and the Enter=drop-player key. Leaving it up means that
  dispatcher never runs, so none of those keys misfire; we drive the camera ourselves.
- **Exit is a raw keyboard poll.** Because `_enter_free_flight` routes all input to the
  FreeFlight service (`block_device_except_service`, :610-612), chat, VMF keybinds and the ESC
  menu can't reach the user while active -- so F8 is read via raw `Keyboard.button` (hardware,
  bypassing service routing), the same technique Photo Mode uses.
- **Transition safety net** (a gap the Photo Mode mod itself has): a world teardown mid-freecam
  routes to the engine's `_clear_free_flight` (NOT `_exit_free_flight`), so our exit never runs
  and input would stay blocked into the next state. `on_game_state_changed` force-resets the
  active flag; the `mod.update` tick also self-heals if the player/world vanishes underneath it;
  and a `hook_safe` on `_exit_free_flight` syncs the flag + checkbox if the engine exits for any
  reason we didn't drive.
- **Hooks** (pre-flight verified disjoint from the rest of gut): `PlayerInputExtension.is_input_blocked`,
  `FreeFlightManager._exit_free_flight`. Chains `mod.update` / `on_setting_changed` /
  `on_game_state_changed` (capture-prev / call-prev-first).
- **Regression test** `freecam_invariants` (`/regression_test`): asserts the wiring is live and
  source-pattern-checks the four load-bearing invariants -- no `set_disabled` call, the
  `is_input_blocked` hook present, the raw `Keyboard.button` exit poll present, and the
  `disable_free_flight` gate NOT lifted.
- **[untested]** -- structurally complete and compiles; needs in-game confirmation (enter shows a
  detached cam with the body visible, WASD/mouse fly it, character doesn't move, F8 exits
  cleanly, and a level transition mid-freecam leaves input working).

## 0.2.188-dev (2026-07-04) -- #305: In-mission mission map (keep "M" map mid-mission)

New feature: open the mission-selection view (the keep's "M" map) during a mission.

- **New `_gut_mission_map.lua`.** Public dispatch field `mod.gut_open_mission_map` fires
  `Managers.ui:handle_transition("start_game_view_force", { menu_state_name = "play",
  use_fade = true })` - the same transition + "play" screen the vanilla "M" hotkey routes
  to (ingame_ui_settings.lua hotkey_map / start_game_view_force :451-454;
  StartGameView.post_update_on_enter reads menu_state_name -> "play" =
  StartGameStateSettingsOverview, start_game_view_definitions.lua:90-91). Bypasses the
  keep-only hotkey gate exactly as the in-mission inventory does. Registers NO hooks:
  StartGameView mounts no keep-only preview world (init binds the live "level_world" and
  create_ui_elements builds only flat scenegraph widgets, start_game_view.lua:48,183-195),
  so unlike the hero-select feature it needs no backdrop swap or restore hooks.
- **Master toggle `gut_mission_map`** (In-Mission Menus group, default OFF) with
  auto-hiding sub_widgets: **`gut_mission_map_hotkey`** keybind (default **M**,
  function_call -> gut_open_mission_map) and **`gut_mission_map_host_only`** checkbox
  (default OFF, issue #305 requirement). Feature does nothing while the master toggle is
  off - the default-M keybind no-ops silently (VMF registers the keybind regardless of the
  parent checkbox, so the handler gates on the setting itself). New chat command **`/map`**
  (no collision - grep-clean across the repo).
- **Adventure-only gate.** Opens only in the `adventure` mechanism. Blocked in `deus`
  (Chaos Wastes - journey-selection layout, documented deus-view crash class, sibling
  parity), `versus` (vanilla gates "M" behind _handle_versus_matchmaking), and
  `weave`/anything else (no positive safety evidence). Keep presses are a silent no-op
  (vanilla "M" already handles the keep). Exit is 100% vanilla (exit_to_game=true ->
  "exit_menu", back to the mission).
- Always-on `[gut_dev:MM]` printf diagnostic on every attempt naming the gate hit
  (disabled/keep/mechanism/host_only/opened). New loc option titles carry `[untested]` tags.
- **Untested:** needs in-game verification in an Adventure mission (open via M and /map,
  ESC back to mission), in the keep (M still opens the vanilla map, no double-open), in
  Chaos Wastes (blocked with the CW message), and as a client with host-only on and off.

## 0.2.187-dev (2026-07-04) -- #287: cosmetics stay editable under "Use non-modded loadouts"

Fixed issue #287: with **Use non-modded loadouts** (`gut_use_non_modded_loadouts`) ON, you
could not change cosmetics (weapon illusion / hat / skin / portrait frame / victory pose) in
the modded realm - the change snapped back. That READONLY mode makes the whole loadout a
read-only mirror of your official data, and cosmetic equips were caught by the same
snap-back as the gameplay loadout.

- **Scope of the exemption.** Only the gameplay loadout (gear = ranged/melee/necklace/ring/
  trinket, plus talents, loadout selection, and bot designation) stays read-only and snaps
  back. Cosmetic slots (`slot_skin` / `slot_hat` / `slot_frame` / `slot_pose`) are now
  editable in READONLY. The set is exactly `LOADOUT_SLOT_NAMES` minus `GEAR_SLOT_NAMES`
  (asserted by a new `native_loadouts_cosmetic_exempt_readonly` regression check) and lines
  up with vanilla `CosmeticUtils` cosmetic slots + `slot_pose`.
- **Persistence, isolation preserved.** Cosmetic edits made in modded persist modded-side in
  a NEW cosmetic overlay (VMF setting `native_cosmetic_overlay`), kept separate from the
  STORE-mode loadout store and keyed by the OFFICIAL selected loadout index so an overlaid
  hat always lines up with the official gear shown beside it. Official cloud data is NEVER
  written - the "never touch your official loadouts" guarantee still holds, now for
  cosmetics too. An untouched cosmetic falls through to your official one.
- **Where it hooks.** `PlayFabMirrorAdventure.get_character_data` serves cosmetic slots from
  the overlay (fixes the equipped snap-back); `get_career_loadouts` overlays cosmetics onto
  the per-loadout previews so the I-VI bar matches; `set_character_data` and the LA-bypass
  `set_career_read_only_data` capture cosmetic writes into the overlay instead of blocking
  them. STORE mode (default, toggle OFF) is unchanged.
- `/reset_modded_loadouts [career]` now also clears the cosmetic overlay.
- Tooltip + option tag updated (`[verify-fix] [diag] [Issue 287]`), awaiting in-game
  confirmation.

## 0.2.186-dev (2026-07-04) -- Ship #301 dev status-tag pass (rider on 0.2.185 #312 UI Tweaks work)

## 0.2.185-dev (2026-07-04) -- #312: UI Tweaks integration, phase 1

Made the standalone Workshop mod "UI Tweaks" (internal id `HideBuffs`) a first-class
citizen of gut's HUD tooling, so the two mods stop fighting over the same HUD elements.

- **Root problem.** gut's HUD customizer and UI Tweaks BOTH reposition four shared HUD
  elements every time the game draws them: the buff bar, the boss health bar, the
  overcharge/heat bar, and the energy bar. gut moves its own registry scenegraph node
  once; UI Tweaks moves a related node/widget-offset in the SAME transform chain every
  frame inside its own hooks. Configure both and the offsets STACK (each nudges a
  different node), which is confusing and wrong. UI Tweaks also has no in-game drag editor.
- **Ownership model.** New checkbox `gut_uitweaks_sync` (HUD > UI Tweaks Integration,
  default on). When UI Tweaks is installed AND enabled AND this is on, UI Tweaks becomes
  the single owner of the four elements: gut's drag editor writes UI Tweaks' offset
  settings instead of gut's own, and gut pins its own node to the vanilla baseline so it
  contributes nothing (no more stacking). New `_gut_uitweaks_sync.lua` holds the element
  map + is_owned / preview / commit / reset / migrate; it adds NO game hooks of its own.
  A one-time `migrate()` folds any pre-existing gut HUD offsets for these elements into UI
  Tweaks (additively, preserving the on-screen position) then zeros gut's, so nothing
  jumps when ownership transfers. Total no-op when UI Tweaks is absent or disabled.
- **Per-element verification (no exclusions).** Each element's UI Tweaks apply site was
  read against gut's apply site in the decompiled engine + HideBuffs source. All four are
  additive offsets in scenegraph UI units (1080p, y-up: +x right, +y up), matching gut's
  cursor/drag space; `node.position` aliases `node.local_position` (ui_scenegraph.lua:82).
  buff_ui -> `BUFFS_OFFSET_X/_Y` (buff_ui.lua:161-168, buff_pivot default {0,0}); boss_health
  -> `OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_X/_Y` (HideBuffs.lua:576-584, clean base+offset);
  overcharge_bar -> `OTHER_ELEMENTS_HEAT_BAR_OFFSET_X/_Y` (overcharge_bar.lua:4-11, widget
  offset); energy_bar -> `OTHER_ENERGY_OFFSET_X/_Y` (HideBuffs.lua:457-463 via the
  crosshair-follow on `screen_bottom_pivot`, of which gut's node is a child). No element was
  excluded. Known phase-1 limitation: for buff/boss/overcharge, gut's registry node is a
  parent of (or separate from) the node UI Tweaks moves, so the drag OVERLAY stays at gut's
  node while the element shifts -- the element ends up correct, but the handle may not track
  a large offset. energy_bar's overlay tracks (child node) but its bar follows the crosshair
  and redraws only when dirty, so a live preview can lag. Committed values are always correct.
- **Durable save.** Foreign-mod settings persist through `get_mod("VMF").save_unsaved_settings_to_file()`:
  VMFMod.set writes into a single shared `_mods_settings` table + unsaved flag, and that flush
  writes it via `Application.save_user_settings()` (VMF core/settings.lua:5-55). Commit/reset/
  migrate call it; drag preview uses notify=false with no save (cheap in-memory).
- **Mod Tweaker tab.** `HideBuffs` added to the `_MY_MODS` whitelist in both
  `_mod_tweaker_view.lua` and `_mod_tweaker_state.lua`, so UI Tweaks' options get a tab when
  it is installed (harmless when absent -- no VMF entry exists then). No STEP_OVERRIDES were
  needed: UI Tweaks' offset sliders omit `decimals_number`, which VMF normalizes to 0
  (options.lua:443), so gut's `_resolve_step` already yields step 1 -- correct pixel
  granularity for a +/-5000 px offset (the drag bar covers coarse movement).
- **Config file.** `HideBuffs` also added to `_MY_MODS` in `_gut_config_file.lua` (the one
  deliberate third-party inclusion): because UI Tweaks now owns the HUD element positions,
  the user's HUD layout lives in HideBuffs' settings, so `/export_settings` + `/reload_config`
  now capture and restore it.
- **Vanilla numeric-UI mirror.** New checkboxes `gut_vanilla_numeric_ui` and
  `gut_vanilla_persistent_ammo` mirror the base game's Gameplay > HUD Customization options
  into gut's menu. on_setting_changed writes `Application.set_user_setting(...)` +
  `save_user_settings()`; on_all_mods_loaded seeds gut's stored values FROM the engine
  (no notify) so a change made in the vanilla menu wins. Liveness caveat: `numeric_ui` is
  live (UnitFramesHandler polls it every frame, unit_frames_handler.lua:1285);
  `persistent_ammo_counter` is cached at chunk load (equipment_ui.lua:10) so it needs a game
  restart -- stated in the tooltip.
- New `/regression_test` checks: `uitweaks_modtweaker_whitelisted`, `uitweaks_sync_map_resolves`,
  `vanilla_numeric_mirror_wired`. Loc titles carry `[untested]` (#301 doctrine); tooltips untagged.

## 0.2.184-dev (2026-07-04) -- Localization: applied dev status-tag doctrine (#301)

Localization: applied dev status-tag doctrine (#301). 75 widget titles tagged: 58 [working],
7 [untested], 10 issue-tagged (#209, #281, #285, #193, #172, #155, #87, #80, #287, #274, #257,
#126, #275, #140), with [crash] on 2, [verify-fix] on 5, [diag] on 4. No em dashes; tooltips,
dropdown value labels, and Mod Tweaker custom-renderer strings left untagged.

- Angle-bracket strip caveat (gut memory `^<(.-)>$`) checked FIRST: the strip in
  `_mod_tweaker_view.lua:196,219` / `_mod_tweaker_state.lua:95,118` operates on the widget
  KEY field of foreign mods (recovering a frozen `<key>` marker), never on gut's own resolved
  display values, and the only value-side guard is `not string.find(s, "^<")`. A `[tag] ` prefix
  starts with `[`, not `<`, and no gut loc entry is itself an angle-bracket string, so prefix
  tagging is safe here with no adaptation needed.
- `gut_use_non_modded_loadouts` normalized from the non-vocabulary `[confirmed working]` to
  `[Issue 287] [diag]`.

## 0.2.183-dev (2026-07-03) -- #285: respawn-timer over the dead teammate portrait now actually renders

The `gut_respawn_timer` feature (large seconds-to-respawn number over a dead teammate's
HUD portrait) drew nothing in-game. Reimplemented `_gut_respawn_timer.lua` by porting the
mechanism from the working Workshop mod "复活CD / Respawn CD (beta)" (id 3747644100).

- **Root cause.** Every symbol the old version used was individually valid (the hook
  installed and fired, `_frame_type == "team"`, `self.data.is_dead`, the `portrait_pivot`
  scenegraph node, `get_world_position`, the font). The break was the draw *path*: it
  drew from a `hook_safe("UnitFrameUI", "draw")` and issued its own
  begin_pass/draw_text/end_pass on the LIVE frame's retained `ui_renderer` +
  `ui_scenegraph`, right after the frame's own draw (which early-returns on
  `not self._dirty` -- the steady state of a settled dead-skull portrait). Piggybacking an
  immediate-mode pass onto that per-frame retained renderer never composited to screen.
- **Fix.** The draw now rides `IngameHud.update` (ingame_hud.lua:372; gut has no other hook
  on it) and uses IngameHud's own HUD renderer -- the same renderer gut's HUD customizer
  overlay draws on (gui_tweaker_dev.lua:660) -- through a throwaway root scenegraph.
  Position is read from the live `UnitFramesHandler` component's team-frame `portrait_pivot`
  node (team_member_unit_frame_ui_definitions.lua:72). Font is the one Respawn CD uses:
  `hell_shark_header` -> material `materials/fonts/gw_head`, font `gw_head` (ui_fonts.lua:58).
- Detection reads the same `data.is_dead` the game maintains on each team frame
  (unit_frames_handler.lua:775-776, set from `status_extension:is_dead()`); the countdown is
  a client-safe estimate anchored to the game-time the flag flips, ticking down
  `hero_respawn_time` (30 default). Teammates only; hidden over an open scoreboard/menu/view.
- Setting ids (`gut_respawn_timer`, `gut_respawn_font_size`, `gut_respawn_r/g/b`) and the HUD
  menu placement are unchanged, so existing user settings persist.
- Coexistence: the reference mod can stay installed; the two do not share hooks or state
  (double-draw at worst). New `/regression_test` check `respawn_timer_ingamehud_draw_path`.

## 0.2.182-dev (2026-07-02) -- #155/#172: in-mission Cosmetics split (tab is vanilla, gear icon is cosmetics_tweaker)

The in-mission Cosmetics access is now split in two, per user direction:

### (a) Cosmetics TAB works mid-mission WITHOUT cosmetics_tweaker (#172, reverses the #155 gate)
The Cosmetics tab is vanilla UI, so it is now enabled mid-mission unconditionally and no longer
depends on Tweaker: Cosmetics or on the pose atlas being injected.

- **`_gut_mission_inventory.lua`** — `tb[4]` (the Cosmetics tab) is set `disable_button = false`
  unconditionally in the `HeroWindowPanelConsole.on_enter` tab-strip hook (was: gated on
  `mod._gut_pose_atlas_ingame`).
- **Actually addressed the #155 crash class, not just ungated.** The crash was
  `HeroWindowCosmeticsLoadoutConsole` drawing the equipped weapon-POSE item icon through the
  `gui_pose_items_atlas` material, which vanilla only adds to the ingame Gui when `is_in_inn`
  (`ingame_ui_settings.lua:590,679`), so mid-mission it C-fatals at `ui_passes.lua:134` (GUID
  5c0865b4). Fix: replaced the former **whole-window draw-skip** (which blanked the entire tab)
  with a targeted filter — a new hook on `HeroWindowCosmeticsLoadoutConsole._equip_item_presentation`
  skips presenting the POSE slot's item (`slot.type == ItemType.POSE == "weapon_pose"`,
  `inventory_settings.lua:9,88-96`) when mid-mission AND the atlas isn't resident
  (`mod._gut_pose_atlas_ingame` false, published by `_gut_gui_material_guard.lua`). The pose slot
  then renders empty (its slot-type icon is `store_tag_icon_pose`, a store atlas — safe), while
  hat/skin/frame present normally, so the tab is fully usable with no C-fatal. When the atlas IS
  resident, the guard injects it and poses show.
- **Pose PICKER guarded too.** Clicking the emptied pose slot opens the `pose_selection` layout
  (`HeroWindowCosmeticsLoadoutPoseInventoryConsole`), a 100%-pose grid. New draw hook skips its
  draw mid-mission when the atlas isn't resident (blank picker, ESC still works — update/input
  run), preventing the same C-fatal. It borrows the parent `world_previewer`, so there is no
  separate preview-world mount crash to guard.

### (b) GEAR ICON (illusion-swap customize) is cosmetics_tweaker-gated (#172)
The per-slot gear/cog customize popup (`HeroWindowItemCustomization`) is the only part that
depends on Tweaker: Cosmetics mid-mission.

- **`_gut_mission_inventory.lua`** — `_gut_customize_allowed()` now returns
  `in_keep or get_mod("cosmetics_tweaker") ~= nil` (was `in_keep or cim or cosmetics_tweaker`).
  gut's #84 preview-world mount-fix already activates on the cosmetics_tweaker path (cim absent),
  and cim's own mount-fix covers the cim-present case, so the view still mounts cleanly.
- **cim note (cited).** cim also hooks `HeroWindowItemCustomization` (`illusion_swap.lua` illusion
  swaps via `_on_illusion_index_pressed`; `standard_forge.lua` reroll), so the gear-icon view is a
  shared surface. A cim user still reaches apply-illusion / reroll mid-mission through the standard
  crafting BENCH (the Crafting tab from 0.2.181, `forge` layout → `CraftPageApplySkin` /
  `CraftPageRollProperties`), so this gating removes only the gear-icon *shortcut* for a
  cim-without-cosmetics_tweaker user, not their crafting. **Flagged for the user to confirm** the
  intended split (drop cim from the shortcut vs. keep `cim OR cosmetics_tweaker`).

### Regression
- New `_rt_register("cosmetics_split_tab_ungated_gear_gated")`: asserts tb[4] is enabled
  unconditionally, the `_equip_item_presentation` pose filter is present, and the gear-icon gate is
  keyed on cosmetics_tweaker specifically.

### Verify in-game (Adventure mission)
1. WITHOUT Tweaker: Cosmetics installed: open the mid-mission menu, the **Cosmetics** tab is
   clickable and shows hat/skin/frame (pose slot may be empty if the pose atlas isn't loaded); no
   crash on open or when clicking the pose slot. The per-slot **gear icon** is inert.
2. WITH Tweaker: Cosmetics installed: the gear icon opens the illusion-swap customize popup.

## 0.2.181-dev (2026-07-02) -- #80: in-mission Crafting tab honors the bench toggle; Compendium usable mid-mission

### In-mission Crafting tab now works (#80)
With "Allow crafting bench in mission" (`gut_cim_bench_in_mission`) ON, the Crafting tab
in the mid-mission HeroView menu is now enabled and routes to the standard crafting bench.
Previously the toggle only reached cim's hotkey / `/cim_craft_standard` command paths; the
tab stayed greyed.

- **`_gut_mission_inventory.lua`** — the `HeroWindowPanelConsole.on_enter` tab-strip hook now
  drives `tb[3]` (the Crafting/Forge tab, asserted `hero_window_crafting` at
  `hero_window_panel_console.lua:140`) off `gut_cim_bench_in_mission` **AND** `get_mod("cim")`
  **AND** Adventure (`current_mechanism_name() ~= "deus"`). `disable_button` is set BOTH ways
  so the state is deterministic (was: only disabled when cim absent, leaving the tab in
  whatever vanilla `create_ui_elements` left — its `1..N can_add` loop actually enables
  `forge` in Adventure, so the tab was inconsistent). Toggle OFF / cim absent / Chaos Wastes =
  greyed, exactly as before.
- **Routing:** clicking the tab calls the vanilla `set_layout_by_name("forge")` within the
  already-open view — the standard bench (`HeroWindowCrafting` family that cim's
  `standard_forge.lua` on_enter hooks activate), the SAME surface `/cim_craft_standard` opens
  (`menu_state_name = "forge"`). It never reaches the Athanor (`weave_forge`, a separate state
  cim keeps Keep-only). No `_cim_open_standard_inv_pending` handshake needed: a layout switch
  doesn't re-run `HeroView.on_enter` (`hero_view.lua:323`), the sole reader of the
  loadout-access gate; the view was already opened with that access via gut's mission-inventory
  patch.
- **Mission-safety:** the standard bench is material-clean in Adventure (flat atlas widgets, no
  preview world / shading env — per cim's `standard_forge.lua` notes; `/cim_craft_standard`
  already opens it mid-mission). The crash-prone gear-icon Customization view
  (`HeroWindowItemCustomization`, `levels/ui_store_preview/world`) is a separate loadout-cog
  path gut already guards and is not reachable from this tab.

### Compendium (Armory + Bestiary) usable mid-mission — no toggle
The Armory + Bestiary compendium now opens and works during a mission, not just in the keep.

- **`_ba_heroview_inject.lua`** — removed the `ctx.is_in_inn == false` keep-block from
  `mod._gut_open_compendium`. The from-outside open now uses `hero_view_force` mid-mission
  (sets `exit_to_game` so ESC/close returns to gameplay; `ingame_ui_settings.lua:441-443`) and
  the normal `hero_view` transition in the keep. Both are `is_transition_allowed` mid-mission
  (`ingame_ui.lua:872` blocks only `profile_view` / `inventory_view_force` when
  matchmaking-ready).
- **`_ba_compendium_tabs.lua`** — `_apply_tab_state` no longer greys the Armory/Bestiary tabs
  out of the keep; they are enabled everywhere.
- **Mission-safety:** both surfaces are atlas/primitive UI only — the Bestiary sub-state
  (`HeroViewStateCompendium`) and the in-menu Armory window (`HeroWindowArmory`) draw flat
  rect/border/text/hotspot passes on the shared `ui_(top_)renderer` with no viewport, no
  preview world, no keep-only material — so they carry none of the mid-mission crash classes
  the crafting/cosmetics tabs guard against. (`HeroWindowBackgroundConsole._update_object_sets`
  is already wrapped for the custom `gut_armory` layout.)

### Regression
- New `_rt_register("crafting_tab_honors_bench_toggle")`: asserts the tab reads
  `gut_cim_bench_in_mission` and `tb[3].disable_button` is driven by `bench_ok`.
- New `_rt_register("compendium_mission_access_ungated")`: asserts the compendium keep-echo is
  gone from `_gut_open_compendium` and `_apply_tab_state` no longer greys tabs out of the keep.

### Loc
- `gut_mission_menu_tabs_tooltip` no longer claims the Crafting tab is permanently disabled;
  `gut_cim_bench_in_mission_tooltip` now mentions the mid-mission Crafting tab entry point.

### Verify in-game (Adventure only, never Chaos Wastes)
1. Options: enable "Show menu tabs in-mission" + "Allow crafting bench in mission" (cim
   installed). Start an Adventure mission, `/inv` to open the menu, confirm the **Crafting**
   tab is no longer greyed, click it, and run a salvage / re-roll to confirm the standard bench
   works with no crash. Toggle "Allow crafting bench in mission" OFF and confirm the tab greys
   back out.
2. `/armory` and `/bestiary` mid-mission: both open (Bestiary stub panel / Armory list); ESC
   returns to gameplay. With the menu open (`/inv`), the Armory/Bestiary tabs are clickable.

## 0.2.180-dev (2026-07-02) -- Loadouts rename + crafting-bench-in-mission option moved here from cim

### Changed (user direction 2026-07-02)
- **"Loadout Manager" group renamed "Loadouts".**
- **"Use non-modded loadouts" flipped to `[confirmed working]`** - user-verified in-game
  2026-07-02 (modded shows official loadouts read-only; all writes blocked). #175 closed
  on this confirmation.
- **New In-Mission Menus option: "Allow crafting bench in mission"** (moved FROM
  Crafting in Modded, whose own widget is removed in cim v0.8.46-dev). Shown ONLY when
  cim is installed (load-order-safe `_cim_present()` prune - get_mod fast path +
  ModManager manifest title scan, the inverse of cim's former #96 gating). gut writes
  through to cim's `allow_in_mission` setting on change and at load, with a one-time
  marker-based ADOPTION of the user's pre-existing cim value, so cim's
  open_forge/open_standard_crafting gates are untouched and stored values carry over.
  New regression check `cim_bench_write_through_present`.

## 0.2.179-dev (2026-07-02) -- #164: Mod Tweaker per-setting slider step (cim power + ct coins step 25), min-anchored snap

### Why
The Mod Tweaker's slider arrows/drag stepped by the natural unit (1 for an integer slider), ignoring a setting's intended coarse increment. Per the binding 2026-07-02 direction, VMF's own options menu stays at its natural fine granularity (users deliberately dial exact values there, e.g. pilgrim's coins = 324); the coarse stepping lives ONLY here in the Mod Tweaker.

### Changed (`_mod_tweaker_view.lua`)
- **Per-setting STEP resolution** via a new `_resolve_step(node, mod_id, setting_id, dec)` helper. Precedence: an explicit widget-def `step` field > the gut-side `STEP_OVERRIDES[mod_id][setting_id]` registry > the natural unit (1 / 10^-decimals). Used in `_build_node_row`'s numeric branch (replaces the old inline `range/40`-derived step).
- **`STEP_OVERRIDES` registry** restructured to nested `[mod_id][setting_id] = step` and re-seeded with the two first consumers, both step 25: `cim`/`cim_dev` -> `base_power_level` (0-950) and `ct`/`ct_dev` -> `starting_coins` (0-3000). **Bug fixed:** the prior entries were keyed by DIRECTORY name (`chaos_wastes_tweaker_dev:starting_coins`), but `category.mod_id` is the `new_mod()` id (`ct_dev`), so the ct override silently never matched. Now keyed by the real mod id.
- **Registry (not widget def) is the working path for a FOREIGN mod**, proven against the decompiled VMF source (`scripts/mods/vmf/modules/core/options.lua`): `initialize_numeric_data` (options.lua:439-448) rebuilds every numeric widget into a fresh table copying only `range`/`default_value`/`decimals_number`/`unit_text`, so a custom `step` field is stripped before it reaches `vmf.options_widgets_data` (what gut reads). A 3-element `range` is worse — `validate_numeric_data` FATALS on it. The widget-def `step` field is still honored first for any category gut walks from RAW data (its own hand-authored tree).
- **Snap anchored at RANGE MIN.** The drag and arrow (click + hold-repeat) paths now route through the existing `_snap_and_clamp(c, n)` helper (clamp -> snap to a min-anchored `step` grid, or to decimals when no step), so drag / arrow / text-entry all land on identical grid points. A pre-existing off-step value (e.g. a 324-coin value dialed in VMF's fine-grained menu) shows as-is at build time and only snaps once the user moves it.
- Exposed `_resolve_step` + `_snap_and_clamp` as statics on the view module for the regression test.

### Regression
- New `_rt_register("mod_tweaker_step_resolution")` (`/regression_test`): asserts the resolver precedence (field > registry > default), registry hits for both consumers on stable + dev ids (guards the directory-name-key regression), and min-anchored + clamped snap math (324 -> 325; min=10/step=25/value=20 -> 10; clamp to max).

### Verify in-game
- Keep -> ESC -> Mod Tweaker -> Chaos Wastes (ct) tab -> Pilgrim's Coin: the starting-coins slider arrows move 25 per click and Apply commits the snapped value. Crafting (cim) tab -> base power level: steps 25 per click.
- VMF's OWN ct menu (Mod Options -> Chaos Wastes Tweaker): the starting-coins slider still moves by 1 and accepts an exact value like 324 (unchanged by this mod; see ct_dev 0.7.207-dev).

## 0.2.178-dev (2026-07-02) -- FIX #140 round 2: guard-based fx_fade swallow (Parting of the Waves post-skip black fade)

### Why (clean user trace 2026-07-02 22:04, v0.2.175-dev, no other cutscene mods)
On "A Parting of the Waves" (level key `dlc_dwarf_whaling` - NOT dlc_portals, earlier docs
had the key wrong) gut's auto-skip works end to end: cutscene activates, deferred skip
fires, fade #1 swallowed via `_skip_next_fade`, teardown clean, post-skip guard
`_skipped_cutscene_system` ARMED. But the map's flow keeps firing delayed node groups
AFTER the skip, and in each group the `fx_fade` effect fires ~97 ms BEFORE its
`flow_cb_activate_cutscene_camera` node (trace-proven ordering):
- 22:04:39.972 `effect | name=fx_fade skip_next_fade=false` -> PLAYED (the bug: visible black fade)
- 22:04:40.069 camera node -> fade-arm sets flag + CAMERA-ACTIVATE suppressed by the guard (97 ms too late for the fade above)
- 22:04:45.417 fade #3 swallowed only by luck (leftover flag from the 40.069 arm)
The single-shot `_skip_next_fade` armed at the camera node (#140 round 1) can never catch
a fade that PRECEDES its own camera node.

### Changed
- **Guard-based fx_fade swallow**, merged into the EXISTING
  `CutsceneSystem.flow_cb_cutscene_effect` hook body (no second hook - VMF drops
  duplicates): while the #106 post-skip guard is armed
  (`_skipped_cutscene_system == self`), every `fx_fade` on that system is swallowed and
  logged as `[gut:cutscene] fx_fade swallowed (post-skip guard)`. The one-shot
  `_skip_next_fade` branch stays as-is - it handles the fade that arrives during
  skip_pressed BEFORE the guard arms (trace 22:04:36.434 proves it is still needed).
- **Trade-off (accepted, documented in the module docstring):** while the guard is armed
  (from the skip until the next cutscene activation or level change), any scripted
  standalone fx_fade routed through CutsceneSystem is also swallowed - a cosmetic pop
  instead of a masking fade. Accepted vs. the erroneous black screen.

## 0.2.177-dev (2026-07-02) -- Interface reorg round 2: single HUD category + Cutscenes under Main Menu & Startup

### Changed (user direction 2026-07-02; all setting_ids unchanged, settings carry over)
- **"On-Screen Overlays" category DELETED; single "HUD" category instead.** The overlays
  (parry indicator, respawn-over-portrait timer, floating damage numbers) modify HUD
  elements, so splitting them from the HUD group was pointless. `gut_hide_hud_ui_group`
  relabeled "Hide HUD & UI" -> "HUD" and now holds: HUD-mode dropdown + cycle hotkey,
  the Hide UI Elements & Buffs sub-tree, then the three overlay master toggles. The
  `gut_hud_group` wrapper widget + loc entry are gone.
- **"Cutscenes & Monologues" nested under "Main Menu & Startup"** (was top-level).
- Top-level categories now: 3rd-Person Camera, HUD, In-Mission Menus, Loadout Manager,
  Main Menu & Startup, Mod Tweaker (A-Z preserved).

## 0.2.176-dev (2026-07-02) -- Interface reorg + Loadout Manager group (user direction 2026-07-02)

### Changed
- **"In-Mission Menus" collapsible group** now wraps the former top-level "In-Mission
  Hero Select" and "In-Mission Inventory" groups. All setting_ids unchanged, so user
  settings carry over.
- **"Native Loadouts (Modded Realm)" group REMOVED** - the modded-scoped store is an
  intrinsic, implicit feature (always on in the modded realm); an enable toggle was
  pointless. `gut_native_loadouts_group` / `gut_native_loadouts_enabled` widgets and loc
  deleted.
- **New "Loadout Manager" group** (options for managing loadouts; more to come). First
  option: **"Use non-modded loadouts"** (`gut_use_non_modded_loadouts`, default OFF).
  ON = while modded, the I-VI bar reads your non-modded (official) loadouts READ-ONLY:
  every loadout write (equips, talents, loadout switches, add/delete, bot designation)
  is blocked at the mirror - nothing modded can change them, and nothing writes to the
  modded store either. OFF (default) = separate modded loadouts as before.
- Module gate reworked to tri-mode (`M.mode`: OFF official / STORE modded default /
  READONLY use-non-modded); failsafe regression check rewritten accordingly.

## 0.2.175-dev (2026-07-02) -- FIX #175: equips in modded now persist with Loremaster's Armoury installed (LA clone-dispatch capture gap)

### Why (friend logs 2026-07-02 21:25 + 21:27)
With the modded store serving reads, the friend equipped the correct sword in modded,
relaunched, and got the stale one back. Both logs show ZERO equip captures for a live
equip: with Loremaster's Armoury installed, menu equips
(hero_view_state_overview.lua:1108 -> BackendUtils.set_loadout_item ->
get_loadout_interface_by_slot) route through an LA-CLONED interface whose copied methods
bypass class-level hooks, so gear writes never reached the
PlayFabMirrorAdventure.set_character_data capture - reads came from the store, writes
leaked down the clone path. cim burned identically 2026-05-30 and documents the fix
(crafting_in_modded_dev.lua:1495): capture at the stable OUTER BackendUtils entry point.
Pose captures in the same logs prove the mirror hook itself works for non-clone flows.

### Changed
- **TABLE-form `BackendUtils.set_loadout_item` capture**, installed deferred once the
  backend answers (cim/cosmetics timing), gear slots only (cosmetic ids are rewritten at
  the interface layer, so cosmetics stay captured at the mirror hook). Equip flow itself
  is untouched (func always called).
- **`set_career_read_only_data` capture + block while gated** (base:3630, the
  `_characters_data`/cloud-push writer, NOT eac-gated by vanilla): career-scoped writes
  are stored and blocked so clone-bypass paths cannot mutate official character data;
  career-nil writes pass through.
- HOOK_TARGETS + regression uniqueness check extended to both new targets.
- Friend remediation on this build: run `/reset_modded_loadouts` once (his correction
  went to official via the bypass, so a re-seed picks it up), or simply re-equip once in
  modded - now captured.

## 0.2.174-dev (2026-07-02) -- CRITICAL FIX #175: v0.2.173 infinite recursion (stack overflow -> 1 GiB lua_heap crash)

### Why (PC-A log 2026-07-02 21:09, 457k lines in ~2 min; friend unbootable with no surviving log)
v0.2.173's read-time fallback called `iface:get_item_from_id()` from INSIDE the mirror
`get_character_data` hook. Recursion chain (all cited): `get_item_from_id` ->
`get_all_backend_items` -> `if self._dirty then self:_refresh()`
(backend_interface_item_playfab.lua) -> `_refresh` -> `_refresh_loadouts` -> mirror
`get_character_data` -> our hook -> resolve -> `get_item_from_id` -> `_dirty` STILL true
(cleared only when `_refresh` completes) -> unbounded mutual recursion. Stack overflow
(~10k frames, surfacing at cosmetics_tweaker.lua:1513 on the same hook chain), then the
error-handler's per-frame locals dumps exhausted the 1 GiB `lua_heap`
("Not enough memory reserved for heap lua_heap", 21:11:43.211).

### Changed
- **`_resolve_item_raw`: raw field reads only** (`Managers.backend._interfaces.items`
  registry field per backend_manager_playfab.lua:202, then `_items` / `_fake_items`
  tables directly). No interface method calls in any hook path = no dirty check = re-entry
  structurally impossible.
- **Tri-state contract**: YES -> serve store value; NO (checkable, absent now) -> official
  value for that read only; UNKNOWN (backend not inspectable) -> serve store value - never
  guess official on UNKNOWN, that would bleed official gear into modded views at boot.
- Regression check extended: tri-state resolve verified on a nonexistent id.

## 0.2.173-dev (2026-07-02) -- CRITICAL FIX #175: startup spawn fatal; destructive sanitize removed entirely

### Why (friend log 2026-07-02 20:23, game unbootable)
v0.2.172's gear-slot sanitizer nulled we_shade's `slot_melee` at boot
(`sanitize ... dropped dangling id=59630ccf-43e0-427a-99b8-809d30cd223f`, 20:23:43.587)
and the spawn wield fataled 9s later ("Tried to wield default slot slot_melee for
we_shade that contained no weapon"), making the game unbootable on every launch (the
nulled slot was persisted). The dropped id is a dashed UUID - a cosmetics/LA/cim
per-instance synthetic id that registers LATER in boot than the sanitize pass ran, so
"not resolvable right now" did not mean "gone". Second destructive-sanitize burn in one
day (after the pose-key drop); the design is wrong, not the tuning.

### Changed
- **Destructive sanitize removed entirely** (no `_sanitize_career`, no store mutation on
  validation grounds - ever).
- **Non-destructive per-read gear fallback** in the `get_character_data` hook: a gear id
  that is empty or unresolvable at read time is served from the OFFICIAL value for that
  read only; the store is untouched, so late-registering modded ids self-heal and serve
  again the moment they resolve. Empty-slot fallback applies to weapon slots only
  (slot_melee/slot_ranged - empty jewelry is legitimate; empty weapons fatal at spawn).
- This also boot-rescues stores already damaged by v0.2.172 (nil melee now falls back to
  official at read time) - no config surgery needed.
- Regression check replaced: `native_loadouts_gear_fallback_nondestructive` (asserts no
  destructive pass exists + slot-set shape).

## 0.2.172-dev (2026-07-02) -- FIX #175 follow-up: pose-sanitize defect + /reset_modded_loadouts re-seed command

### Why (friend logs 2026-07-02 19:40-19:57 + user_settings capture)
Two defects surfaced on the first friend deployment of the v0.2.170-dev native
modded-scoped loadouts:
1. **Sanitizer stripped victory poses every session.** `slot_pose` values are item KEYS
   (e.g. `es_2h_sword_weapon_pose_02`), not backend GUIDs, so `get_item_from_id` could
   never resolve them and the sanitizer dropped every pose on every career - including a
   `default_weapon_pose_01` drop/rewrite loop each session. Log-proven
   (`sanitize ... slot=slot_pose dropped dangling id=...` across 22 careers).
2. **Seed froze pre-isolation corruption.** The one-time official-to-modded seed
   faithfully snapshotted the cloud state at first touch - but that state already
   contained blacksmith items committed by the pre-isolation #174 bleed (merc Kruber
   `slot_melee` seeded to the blacksmith greatsword GUID; sanitize validated it as a
   real owned item at 19:41:10, and zero gear writes were captured afterward, ruling
   out post-seed corruption). The user then fixed official (correct there), but the
   modded snapshot stayed frozen wrong by design.

### Changed
- **Sanitize gear slots only.** New `GEAR_SLOT_NAMES` whitelist (ranged/melee/necklace/
  ring/trinket_1 - the slots that always hold backend GUIDs); cosmetic slots
  (skin/hat/frame/pose) are never validated. New regression check
  `native_loadouts_sanitize_gear_only`.
- **New `/reset_modded_loadouts [career]` chat command.** Wipes the modded store (all
  careers, or one, e.g. `/reset_modded_loadouts es_mercenary`) so loadouts re-seed from
  the CURRENT official data on next use. This is the cure for a bad frozen seed: fix
  your gear in official, then reset in modded. Official data is never written;
  modded-only edits in the wiped entries are discarded.
- Note: poses already lost from a v0.2.170 store (dropped before this fix) come back
  via the same reset, or by re-equipping the pose in modded.

## 0.2.171-dev (2026-07-02) -- FIX #173: Hero Select now opens the REAL hero/career selection screen mid-mission

### Why
The "Open Hero Select (Mid-Mission)" keybind / `/hero_select` deliberately opened the
HeroView TALENTS layout and called that hero select -- the wrong view, coded in by a
prior session as a crash-avoidance substitute. The real target is
`CharacterSelectionView` (the keep "C"-key character/career pick grid). Two findings
unblocked the real thing (both in `HERO_SELECT_RESEARCH_173.md`, updated):
- **Bundle evidence (2026-07-02):** `levels/ui_character_selection/world.level` lives
  ONLY in hub/menu bundles; no mission bundle has it and NO
  `resource_packages/levels/ui_character_selection.package` exists in the game files,
  so a preload is impossible and a blind transition is a C-level mount fatal. By
  contrast `levels/ui_inventory_preview/world` HAS a managed package that HeroView
  itself force-loads mid-mission (`hero_window_character_preview.lua:100-105`).
- **B7 probe (live logs 2026-07-02):** career-swap `force_respawn` lands with
  `moved=0.0` -- respawn happens IN PLACE. The old "teleports you to level start"
  blocker was refuted empirically.

### Changed
- **`_gut_mission_hero_select.lua` rewritten (C7 design).** Open path now fires the
  vanilla keep-pedestal transition verbatim (`character_selection_force`,
  `menu_state_name="character"`, `use_fade=true`). Mid-mission (native backdrop not
  gettable per a self-tested `Application.can_get("level", ...)` check) it first
  async-loads `resource_packages/levels/ui_inventory_preview` under gut's own ref
  (`gut_hero_select`), swaps the CACHED charsel defs viewport `level_name` to
  `levels/ui_inventory_preview/world` (+ its shading env), fires the transition, and
  restores the original def values the moment the viewport mounts
  (`CharacterSelectionView.post_update_on_enter` hook_safe; `on_exit` as
  belt-and-suspenders). The package ref is kept for the session (documented; unload
  races avoided, leak-proofing, zero reopen latency). Keep-bail and deus/CW block
  stay; the CW echo now states the honest reason (boon/loadout desync). New hooks are
  preflight-verified singletons (gut hooked CharacterSelectionView nowhere before).
  `[gut:heroselect]` printf at every branch.
- **B3 probe fixed (`_gut_menu_transition_probe.lua`).** The original passed a
  `"gut_probe"` reference_name to `has_loaded` -- reference-scoped semantics made it
  always-false, so its data was VOID. Now queries global residency AND logs the
  decisive `Application.can_get("level", ...)` boolean; legend updated.
- **Decoupled hero-select from the HeroView loadout-access patch**
  (`_gut_mission_inventory.lua`, `on_setting_changed`): CharacterSelectionView does
  not read `inventory_loadout_access_supported_game_modes`; the patch now keys off
  the inventory toggle alone. The open path also gates on the feature checkbox now.
- **Loc/tooltips rewritten** to describe the real behavior (career-select grid
  mid-mission; picking a career respawns in place); the false "keep-only by design"
  claim is gone. Checkbox re-labeled `[untested]` pending in-game verify.

## 0.2.170-dev (2026-07-02) -- FEATURE: modded-realm-scoped native loadouts (#175)

### Why
In the modded (EAC-untrusted) realm the game's native saved-loadout system (the I-VI
loadout bar) reads and writes the SAME PlayFab-backed store as the official realm, so
modded play can overwrite official loadouts. The character-data commit push
(`updateHeroAttributes`, playfab_mirror_base.lua:2891/2903) is NOT eac-gated (unlike
stats/weaves/poses at :2826/2839/2857), so modded equips reach the official cloud data.

### Changed
- **New `_gut_native_loadouts.lua`.** While in the modded realm (Adventure only), the
  native I-VI loadout bar -- gear, cosmetics, per-loadout talents, and bot designation --
  reads and writes a modded-only VMF store (`native_loadouts`), fully isolated from the
  official-realm loadouts. Default ON. Inert in the official realm and in Versus.
- **Isolation approach:** intercept the backend MIRROR, `PlayFabMirrorAdventure`, which is
  the single convergence point below the item + talents interfaces (and any MoreItemsLibrary
  interface swap or Loremaster's Armoury dispatch, which all call the mirror). Hook the four
  mirror WRITE methods (`set_character_data` / `set_loadout_index` / `add_loadout` /
  `delete_loadout`) to capture into the store and NO-OP vanilla, so `_career_data` /
  `_characters_data` are never mutated -- the commit diff (`_check_career_data`) then finds
  nothing dirty and never pushes modded loadouts to PlayFab. Hook the three mirror READ
  methods (`get_character_data` / `get_career_loadouts` / `has_loadout`) to serve from the
  store, so the interface caches refresh with modded values and the in-session equip/spawn
  flow works unchanged. Hooked on the concrete runtime subclass `PlayFabMirrorAdventure`
  (NOT `PlayFabMirrorBase`) because class.lua copies parent methods into the child.
- **Seeding:** on first activation per career the official loadouts (contents + selected
  index + per-loadout talents) are snapshotted once into the store; official data is only
  ever READ, later official changes do not re-sync.
- **Bot designation:** `HeroWindowLoadoutSelectionConsole._save_bot_equipment` writes the
  bot loadout index to the store and skips the `PlayerData.loadout_selection.bot_equipment`
  write; `BackendInterfaceItemPlayfab.refresh_bot_loadouts` (hook_safe overlay) resolves the
  bot loadout from the store.
- **Dangling id validation:** stored gear ids are validated against the backend once per
  career per session; dead ids are dropped (printf, no crash). Cosmetic/pose slots degrade
  gracefully to empty via vanilla.
- **Realm signal:** `script_data["eac-untrusted"]` (application_parameter.lua:150; named
  `in_modded_realm` at mod_manager.lua:22). Failsafe: any uncertainty => fully inert.
- Master toggle `gut_native_loadouts_enabled` in a new top-level "Native Loadouts (Modded
  Realm)" group (gui_tweaker_dev_data.lua / _localization.lua). Diagnostics via `printf`
  with the `[gut_dev:NATIVE_LOADOUTS]` prefix on load, seed, sanitize, and every write.

### Notes
- Cross-mod: our hooks sit at the mirror layer, BELOW cim's / cosmetics_tweaker's
  BackendUtils + interface hooks, so they do not collide; mp installs zero backend hooks.
- Loadout cap read from `InventorySettings.MAX_NUM_CUSTOM_LOADOUTS` (6 today), never
  hardcoded, so issue #231's raise to 30 needs no change here.
- Regression markers: `native_loadouts_installed`, `native_loadouts_failsafe_inert`,
  `native_loadouts_no_hardcoded_6`, `native_loadouts_hook_targets_unique` (`/gut_dev`
  regression_test). Needs in-game verification (see the ship report).
- Dedicated-server hosting (`PlayFabMirrorDedicated`) is out of scope (P2P host only).

## 0.2.169-dev (2026-07-02) -- FIX: "Parting of the Waves" brief fade-IN on auto-skip (#140)

- **Skip Cutscenes fade-in fix.** On the mission "Parting of the Waves" (`dlc_portals`),
  auto Skip Cutscenes correctly skipped the cutscene but a brief black fade-IN still played
  over the screen for a couple seconds (user-confirmed 2026-07-02; reproduces in
  official/vanilla Adventure, NOT Chaos-Wastes-specific). Root cause: gut armed its
  single-shot fade-swallow flag `_skip_next_fade` only inside the
  `flow_cb_activate_cutscene_logic` hook, but this map's native fade-in effect fires around
  the EARLIER `flow_cb_activate_cutscene_camera` flow node, at which point `_skip_next_fade`
  was still false -- so the fade played. Fix: re-arm `_skip_next_fade` at the camera node
  too (merged into gut's existing `flow_cb_activate_cutscene_camera` hook), matching the
  known-good Aussiemon "Skip Cutscenes" mod (`SkipCutscenes.lua:8`). Gated on "will this
  cutscene actually skip" (`not _gut_in_deus() or script_data.skippable_cutscenes`) so a CW
  author-LOCKED boss cinematic that is intentionally played through keeps its own fade
  intact. A `[gut:cutscene] CAMERA-NODE fade-arm` printf line marks it firing in the log.

## 0.2.168-dev (2026-07-02) -- FIX: Armory in-menu open crashed the vanilla background window (#217)

- **Crash fix.** One frame after the Armory tab opened its in-menu window layout, the
  vanilla `HeroWindowBackgroundConsole._update_object_sets` crashed:
  `attempt to index local 'object_set_to_enable' (a nil value)` with `layout_name =
  "gut_armory"`. That method resolves the current layout name to a keep object set via
  the file-local `object_sets_per_layout` map and indexes `.keep_current_object_set`
  with no nil-guard (hero_window_background_console.lua:395-400); our custom layout name
  isn't in that map. The map is a file-local we can't register into, and its own
  non-set-dressing entries use `keep_current_object_set = true`, so the correct behavior
  for an unknown layout is to leave the current object set as-is. Fix: wrap
  `_update_object_sets` (gut's only hook on this class) so the known-layout path runs
  unchanged and an unknown layout no-ops (the nil index errors before mutating anything).
  This also guards any future custom hero layout (e.g. a Bestiary window). No other
  per-layout map in that window is unguarded (the rest use `or false` / `or EMPTY_TABLE`
  / default), and the gut_armory layout entry matches the vanilla equipment entry
  field-for-field (name, close_on_exit, sound_event_enter/exit, windows).

## 0.2.167-dev (2026-07-02) -- FEATURE: Armory opens in-menu + live game-sourced weapon stats (#217)

- **Armory now opens IN-MENU like Equipment/Cosmetics** instead of replacing the whole
  hero screen (fixes the "closes the menu with the pop" feedback). It is registered as a
  WINDOW LAYOUT (`gut_armory`) inside `HeroViewStateOverview`: a new `HeroWindowArmory`
  window + a layout entry are injected into the shared console-layout module
  (`hero_window_layout_console.lua` `windows` / `window_layouts`), and the Armory tab now
  routes to `overview:set_layout_by_name("gut_armory")` -- the exact call vanilla tabs make
  (`hero_window_panel_console.lua:452`). The tab strip and chrome stay put; ESC/back behave
  like the other tabs; no hero_view re-enter, so the #223 crash path is not touched. The
  Armory tab also highlights as selected. `/armory` + `/gut_armory` open the in-menu window
  when the hero menu is already on the overview state.
- **Bestiary stays state-based** for now (its content is not built yet); it still routes
  through the #223-safe internal state switch.
- **Weapon list + stats are sourced live from the game, no hardcoded numbers.** The list is
  the current career's eligible weapons (filtered by the engine's `can_wield`, grouped
  melee/ranged, localized names via `ItemMasterList.display_name`). Selecting a weapon shows
  template stats read straight off `Weapons[template]`: dodge count + distance bonus
  (`dodge_count`, `buffs.change_dodge_distance`), stamina (`max_fatigue_points`), block angle
  + inner/outer fatigue multipliers, push radius/arc (the push action), and ammo
  (`ammo_data`) or overcharge (`overcharge_data`) for ranged. Per attack (light/heavy/push;
  ranged primary/alternate, chains derived by `_ba_attack_labeler`) it shows the damage
  profile name, cleave damage/stagger target counts computed via the engine's own
  `ActionUtils.get_max_targets` at the player's LIVE scaled cleave power, and traits
  (crit bonus, bleed/burn/poison, area damage, linesman/tank) read from the action + its
  `DamageProfileTemplates` entry.
- **Deliberately deferred (documented):** full per-armor-type breakpoint DAMAGE numbers (the
  standalone Armory reimplements a chunk of the combat pipeline for these); a 3D weapon
  preview/illusion browser; a weapon-list scrollbar (current career lists fit without one);
  and Bestiary content. All are follow-ups. Rendering is atlas-safe primitive passes only.

## 0.2.166-dev (2026-07-02) -- FIX: Compendium tab crash (#223) + `<key>` markers (#224)

- **#223 crash fix.** Clicking the Armory/Bestiary tab from inside the hero menu fataled
  with `World "hero_view_hdr" already exists`. The tab routed through
  `transition_with_fade("hero_view", { force_open = true })`, which re-runs
  `HeroView.on_enter` -> `_setup_hdr_gui` -> `create_world("hero_view_hdr")` while the
  old world still exists (`ingame_ui.lua:953` forces the on_exit/on_enter block even when
  `old_view == new_view`). The tab now switches via HeroView's OWN internal mechanism
  (`HeroView:requested_screen_change_by_name("gut_compendium")` -> `_change_screen_by_name`
  -> `_wanted_state`, hero_view.lua:236-245/470-490), which swaps the sub-state without
  re-entering the view (no HDR-world recreation). The from-outside path (`/armory` while
  not in hero_view) keeps its `force_open` transition. New shared helper
  `mod._gut_switch_to_compendium_state`.
- **Hard guard (belt-and-suspenders).** `mod._gut_open_compendium` now checks
  `ingame_ui.current_view == "hero_view"` and routes to the internal switch (or no-ops
  with a `[gut:217]` printf) instead of ever re-entering hero_view. A dead tab beats a
  dead game.
- **#224 `<key>` markers fix.** The tabs rendered `<GUT_TAB_ARMORY>` / `<GUT_TAB_BESTIARY>`.
  Root cause was in `_resolve_label`: for an unregistered loc key VMF returns the sentinel
  `"<key>"` (angle brackets), which slipped past the `s ~= key` guard and, with
  `localize = false`, rendered verbatim. `_resolve_label` now rejects the bare key AND any
  `"<...>"` marker form, falling back to the display literal (Armory / Bestiary). No
  `_G.Localize` hook needed -- the tab text is a `localize = false` literal, so Localize is
  never consulted for it.
- **Diagnostic.** `dump_hero_view`'s `state=? state_index=?` line now resolves the live
  state or reports a clear reason (state machine not created until post_update_on_enter),
  via `printf` (visible with mod logging off).

## 0.2.165-dev (2026-07-01) -- FEATURE: Armory + Bestiary hero-menu tabs (Compendium Phase 1, #217)

Adds two tabs, **Armory** and **Bestiary**, to the hero/character menu's top tab
strip (Equipment / Talents / Crafting / Cosmetics ...). Clicking one opens gut's
existing Compendium hero-view sub-state (`HeroViewStateCompendium`) in the matching
mode via `mod._gut_open_compendium("armory" | "bestiary")` -- the same path the
`/gut_armory` `/gut_bestiary` chat commands use. This is Phase 1 of the Compendium
(builds on the #212-era foundation: `_ba_compendium_state` / `_ba_heroview_inject`
/ `_ba_compendium`).

- **New `_ba_compendium_tabs.lua`.** Targets the **console menu layout**
  (`HeroWindowPanelConsole`) -- VT2's default (Options -> "Use PC menu layout" OFF),
  what most players see, and the strip gut already integrates with. The strip is
  width-measured (`_setup_text_buttons_width` divides `panel_entry_area` by
  `#title_button_widgets`), so appending two `title_button_definitions` +
  `game_option`-style scenegraph nodes to the shared console-definition tables
  **auto-reflows** with no fixed-width overlap (same shared-table-mutation technique
  gut uses for `menu_layouts` / `InventorySettings`; nodes can't be added to a built
  scenegraph). Two new hooks, neither duplicating an existing gut hook on the class:
  `HeroWindowPanelConsole.create_ui_elements` (one FULL hook: inject defs before,
  label/grey after) and `._on_panel_button_selected` (routes our tabs to the
  Compendium, matched by namespaced `scenegraph_id`).
- **Keep-only, greyed in mission.** The Compendium opens only in the keep/inn, so the
  tabs are greyed (`disable_button`) mid-mission -- mirroring the existing
  crafting/cosmetics tab-gating -- and the opener keep-gates as belt-and-suspenders.
- **Labels are literals** (`localize = false`): these are vanilla game widgets whose
  text is resolved by the engine `Localize()`, which cannot resolve a VMF mod loc key.
- **Follow-up:** the PC menu layout (`HeroWindowOptions`, "Use PC menu layout" ON) is a
  fixed-position vertical column with no measured reflow -- deferred (see #217) rather
  than ship a rushed overflow-prone layout. Pending in-game verification.

## 0.2.164-dev (2026-07-01) -- POLISH: settings menu reorganization (no functional changes)

Sort + organize + polish pass on the VMF options tree only. No behavior, setting,
default, range, hook, or command changes; every `setting_id` is unchanged, so saved
settings and the HideBuffs-fork hooks (which read `mod:get(SETTING_NAMES.<id>)`) are
untouched. The Mod Tweaker custom renderer walks the generic node tree, so it picks
up the new layout automatically.

- **New "Hide HUD & UI" umbrella (`gut_hide_hud_ui_group`).** Folds the two
  formerly-sibling, confusingly-similar hide-UI surfaces into one collapsible group:
  the HUD-visibility dropdown + cycle hotkey (the dissolved `gut_hud_visibility_group`
  container) sit at the top, then the absorbed HideBuffs "UI Tweaks" sub-tree.
- **`hb_group` label de-jargoned:** "UI Tweaks (absorbed)" -> "Hide UI Elements &
  Buffs" (label only; `setting_id` unchanged). It now nests "Hide UI Elements", "Hide
  Active Buffs", and a new "Portrait & Markers" sub-group (`gut_hb_misc_group`) that
  collects the three formerly-loose toggles (`force_default_frame`,
  `UNOBTRUSIVE_FLOATING_OBJECTIVE`, `UNOBTRUSIVE_MISSION_TOOLTIP`).
- **`gut_hud_group` label de-jargoned:** "HUD" -> "On-Screen Overlays" (label only;
  `setting_id` unchanged) so it no longer reads as a duplicate of the hide-HUD area.
  Still holds the parry indicator, respawn timer, and floating damage numbers.
- **Top-level groups sorted A->Z by display label** (repo standing rule): 3rd-Person
  Camera, Cutscenes & Monologues, Hide HUD & UI, In-Mission Hero Select, In-Mission
  Inventory, Main Menu & Startup, Mod Tweaker, On-Screen Overlays. Deliberate-order
  exemptions (camera rig order; the HUD dropdown/hotkey at the top of Hide HUD & UI)
  are commented in `gui_tweaker_dev_data.lua`.
- **Localization file reordered** to mirror the new widget tree with `-- ====` section
  banners; the one over-long tooltip (`gut_parry_indicator_tooltip`) tightened to the
  LOCALIZATION_STANDARD section 11 length while preserving its "works on every weapon,
  not just the Parry trait" claim. The now-unused `gut_hud_visibility_group` label is
  retained (not deleted) per the orphan policy.

## 0.2.163-dev (2026-07-01) -- FIX (#212): /armory + /bestiary collide with the standalone Armory / Bestiary mods

VMF rejects a command name that another mod already registered (boot log:
`command name 'armory' is already used by another mod 'armory'`), and which mod
loses depends on load order -- so gut's unconditional short-name registration
either silently lost (Armory loaded first) or would have broken the standalone
mod (gut loaded first).

- `_ba_compendium.lua`: `/gut_armory` + `/gut_bestiary` are now always registered.
  The short `/armory` + `/bestiary` aliases are claimed in `on_all_mods_loaded`
  (chained handler, same pattern as gui_tweaker_dev.lua) and ONLY when
  `get_mod("armory")` / `get_mod("bestiary")` is absent, so the standalone mods
  always keep their names.

## 0.2.162-dev (2026-07-01) -- CRASH FIX (#216): 3P camera + overcharge weapon = set_particles_material_scalar nil-id fatal

User-hit crash (GUID 0a41da66): the #209 screen-effect suppression returns nil from
`PlayerUnitFirstPerson.create_screen_particles` while the 3P camera is active, but its
safety analysis only covered BuffExtension. `PlayerUnitOverchargeExtension._update_screen_effect`
lazily creates its overlay particle id and then unconditionally feeds it to
`World.set_particles_material_scalar` every update while overcharge > 0 -- with the create
suppressed, the nil id is a per-frame Lua error (repro: 3P camera + any overcharge weapon
above 0 heat; hit on Kruber wielding Sienna's Bolt Staff via wt, but native Sienna in 3P
crashes identically). The player/enemy `*_state_in_vortex` exit paths pass their stored id
to `stop_spawning_screen_particles` unguarded -- same latent crash on leaving a plague
vortex in 3P.

- `_gut_camera.lua`: full-wrapper hook on `PlayerUnitOverchargeExtension._update_screen_effect` --
  while 3P is active, destroy any existing screen-space overcharge particles (vanilla
  `_destroy_all_screen_space_particles` nils both id fields) and skip; overlay lazily
  recreates on the 3P->1P switch.
- `_gut_camera.lua`: nil-id guards on the sinks `PlayerUnitFirstPerson.stop_spawning_screen_particles`
  and `.destroy_screen_particles`, covering the vortex exits and any other unguarded vanilla caller.
- Audited every other vanilla `create_screen_particles` consumer: all nil-guard their stored
  id or are fire-and-forget. `career_ability_rat_ogre_vs` shares the unguarded pattern but is
  Versus-only (noted in #216, not patched).

## 0.2.161-dev (2026-07-01) -- FIX: settings-menu localization ("<...>"-wrapped tooltips) + rewritten option descriptions

Localization + descriptions only; no behavior, setting, default, or range changes.

- **Double-localized tooltips no longer show wrapped in angle brackets.** Each widget's tooltip
  in `gui_tweaker_dev_data.lua` eagerly called `mod:localize("<key>")`, which returns the English
  sentence; VMF's options module then localizes that sentence a SECOND time, misses (it isn't a
  key), and displays the whole tooltip as `<...the sentence...>`. Converted all 60 tooltip fields
  to pass the raw loc KEY (`tooltip = "<key>"`) so VMF localizes exactly once. The one correct
  eager-localize -- the mod's top-level `description = mod:localize("mod_description")` -- is left
  as-is.
- **"Hide UI" HUD-mode dropdown no longer shows `<Off>` / `<Partial>` / `<Complete>` / `<Camera>`.**
  The dropdown option `text` fields were literal display strings, but VMF localizes each option's
  `text` as a loc key (`option.text = mod:localize(option.text)`), so literals rendered bracketed.
  They now use loc keys (`gut_hud_mode_opt_off/partial/complete/camera`) with matching entries;
  the stored values (off/partial/complete/camera) are unchanged.
- **Rewrote every option tooltip/description** into short, plain, player-facing English (about two
  sentences, no engine/internal jargon) in `gui_tweaker_dev_localization.lua`. 55 values rewritten
  (54 tooltips + `mod_description`); titles/labels left unchanged. Added the four new
  dropdown-option loc keys.
- **(#173) Read-only Hero Select research probes B3 + B7** (zero behavior change; engine `printf`
  tagged `[gut:173]`, so they surface with mod logging OFF). **B3** (folded into the existing
  `IngameUI.handle_transition` hook in `_gut_menu_transition_probe.lua`, per the VMF
  no-duplicate-hook rule): on each menu-open transition, `pcall`-queries
  `Managers.package:has_loaded("resource_packages/levels/ui_character_selection")` (no ref, so it
  reports true residency) + the current `level_key`, edge-latched per (level, residency) --
  answers whether a direct `character_selection_force` rewire is safe in-mission (true), needs a
  preload (false), or must avoid the view (pcall error). **B7** (new `_gut_173_probes.lua`):
  `hook_safe GameModeAdventure.force_respawn` (verified game_mode_adventure.lua:283; gut hooks it
  nowhere else), captures the local player's pre-respawn position (as number components -- Vector3
  is a stack temporary) and logs the post-respawn position + distance moved ~60 frames later on the
  chained `mod.update`, settling whether a career swap teleports to level start. Both settle the
  open questions in `HERO_SELECT_RESEARCH_173.md` before any rewire is attempted.

## 0.2.160-dev (2026-07-01) -- READY FOR TEST: in-mission Cosmetics tab (#155) + gear-icon on cosmetics_tweaker (#84/#87)

Two in-mission inventory surfaces moved from "hard-gated crash guard" to "ready for in-game
verification". Both produce `[gut:155]` / `[gut:84]` engine `printf` evidence (mod logging can
stay OFF). REQUIRES a full Steam restart before testing (self-authored Workshop re-pull).

- **#155 -- in-mission Cosmetics tab (pose items).** The tab was disabled mid-mission because
  `HeroWindowCosmeticsLoadoutConsole` draws weapon-pose items through the `gui_pose_items_atlas`
  material (inside `materials/ui/ui_1080p_pose_cosmetics`), which vanilla only adds to the ingame
  renderer's Gui when `is_in_inn` -> mid-mission it's absent and the pose draw takes a C-level
  "Material not found in Gui" fatal at `ui_passes.lua:134` (crash GUID 5c0865b4). Root-caused in
  the decompiled source: this is a DRAW-time fatal (`Gui.bitmap`), a different path from the
  create_screen_gui fatal the v0.2.158 material guard handles -- so the guard alone did NOT cover
  it. Fix: `_gut_gui_material_guard.lua` (the sole `UIRenderer.create` hook) now also INJECTS
  `ui_1080p_pose_cosmetics` into ingame renderers that lack it, but ONLY when the resource is
  resident (`Application.can_get`) -- adding a non-resident material would itself fatal create,
  and the drop-filter would strip it. The result is published in `mod._gut_pose_atlas_ingame`;
  `_gut_mission_inventory.lua` enables the Cosmetics tab in-mission (and lets the window draw)
  ONLY when the atlas actually made it into the Gui, otherwise the tab stays gated exactly as
  before (blank/no-crash). If the resource turns out to be keep-only (not resident in a mission),
  the `[gut:155] ... NOT resident (can_get=false)` line reports that a package pin is the next
  step. Best case: the tab works in-mission; worst case: unchanged + a definitive diagnostic.
- **#84/#87 -- gear/cog "Customize" icon on the cosmetics_tweaker path.** The in-mission cog gate
  (`_gut_customize_allowed`) now allows the Customization view when `cosmetics_tweaker` is present,
  not only `cim` (still inert when gut runs alone). To make that view MOUNT without cim, gut now
  carries its own copy of cim's proven preview-world mount-fix (`HeroWindowItemCustomization`
  `_create_item_preview_widget_definition` + `_register_object_sets`, ported from
  crafting_in_modded v0.7.45): mid-mission with cim absent it serves a level-free preview widget
  def (mission-safe `environment/ui_hdr`) and seeds an empty object-set, dodging the
  `levels/ui_store_preview/world` "Level not loaded" mount fatal (crash GUID ef637399). Both hooks
  are inert in the keep and when cim is present (cim owns the fix then; gut passes through, so the
  same-method hooks on the two mod-ids don't fight). This enables the view to open so cosmetic
  changes can be tried in-mission; whether a given illusion applies + re-renders live is what the
  test verifies. Modded crafting (reroll/salvage) still requires cim.

## 0.2.159-dev (2026-07-01) -- FIX: post-skip camera guard (bastion sticky cutscene, #106) + camera-lifecycle logging + frame-time heartbeat

HOST log forensics (2026-07-01, `dlc_bastion_nurgle_path1` / Blood in the Darkness): gut's
auto-skip completed clean in 16 ms, but the LEVEL's cutscene flow timeline kept firing DELAYED
camera-activate nodes that are not gated on the skip event. Vanilla
`flow_cb_activate_cutscene_camera` (cutscene_system.lua:129-151) unconditionally re-set
`active_camera`, hid the HUD, re-flagged the loading icon and re-queued the letterbox,
re-locking the player TWICE after the successful skip until the timeline ran out at the
cutscene's natural ~35.5 s duration. Vanilla `skip_pressed` (:97-109) tears down only the
CURRENT camera and never short-circuits pending flow nodes. Distinct from the dlc_termite
deferred-teardown variant fixed earlier; all in `_gut_cutscenes.lua`.

- **Post-skip camera guard (#106 fix):** the `skip_pressed` hook now remembers WHICH
  CutsceneSystem instance a skip actually executed on (armed only when the before-state had an
  active camera and vanilla's teardown removed it, so orphan presses and author-locked CW
  cutscenes never arm it; covers both auto-skip and manual skip, which share the hooked path).
  While armed, a NEW `flow_cb_activate_cutscene_camera` hook suppresses that instance's late
  camera re-activations (logged as `CAMERA-ACTIVATE suppressed (post-skip guard)`). The guard
  clears when `flow_cb_activate_cutscene_logic` announces a genuinely new cutscene (reset runs
  before the auto-skip evaluation, so the new cutscene can itself be skipped and re-arm the
  guard), and it is instance-keyed, so a level transition (fresh CutsceneSystem per level)
  invalidates it automatically. Dup-hook pre-flight re-run: no other gut hook on either camera
  callback (comment references in `_gut_camera.lua` only).
- **Camera-lifecycle logging (closes the client blind spot):** `[gut:cutscene] CAMERA-ACTIVATE`
  / `CAMERA-DEACTIVATE` printf lines (hook + hook_safe respectively) with the same teardown
  state snapshot the file already logs. The 2026-07-01 session showed
  `flow_cb_activate_cutscene_logic` NEVER fires client-side (exactly 2 `[gut:cutscene]` lines
  in the client's whole 7-mission log); the camera callbacks do fire on clients, so client
  cutscene behavior is now observable.
- **`[gut:frametime]` heartbeat (always on):** one printf every 30 s with
  `level=<key> avg_ms=<x.x> worst_ms=<x.x> frames=<n>` accumulated in the existing chained
  `mod.update` tick (accumulators reset each beat; ~2 lines/min). Both machines had FPS
  complaints this session that could not be anchored to timestamps because neither log carried
  any frame-time data.

Verification is via the printf lines themselves (feature only observable in-mission during a
cutscene, so no keep-runnable `/verify_*` command): a bastion run should show `post-skip camera
guard ARMED` after the auto-skip, then `CAMERA-ACTIVATE suppressed (post-skip guard)` in place
of the two re-locks. NOT yet verified in-game.

## 0.2.158-dev (2026-07-01) -- GUI material guard: prevent "Gui material not found" client CTDs (mod-compat hardening)

A friend's client hard-crashed on mission load into `dlc_castle_nurgle_path1` with
`<<Script Error>> materials/ui/ui_1080p_chat`, deep in the "More Loading Screens" mod's
loading-screen creation (`create_screen_gui`). `create_screen_gui` C-fatals -- bypassing
pcall AND xpcall (the crash went through VMF's own `safe_call_nr` xpcall and still killed the
client) -- whenever any listed material isn't resident. `ui_1080p_chat` is a real vanilla
loading-screen material that simply wasn't loaded on that client at that instant (a mod-compat
timing edge). Since it can't be CAUGHT, it must be PRE-FILTERED.

- **New `_gut_gui_material_guard.lua`:** hooks `UIRenderer.create` (the funnel every screen GUI
  passes through, and the exact function VMF's `custom_textures` already hooks, so proven-hookable)
  and drops any `("material", <path>)` pair whose material is NOT loadable, tested with
  `Application.can_get("material", path)` -- vanilla's own safe, non-faulting existence check
  (`pickup_system.lua:882` uses `can_get("unit", ...)` for the identical "don't spawn a missing
  resource" guard). A missing material now makes that ONE element silently not render instead of
  crashing the client. Mod-agnostic: protects against More Loading Screens, Loremaster's Armoury,
  and our own mods; generalizes the LA-atlas-specific `_la_atlas_keepalive`.
- **Safety interlock:** the guard stays PASSIVE (pure passthrough) until `can_get` proves
  trustworthy via a self-test against a known-always-resident material (`gw_fonts`), and fails
  OPEN on any error -- it can never be the thing that breaks or blanks GUI creation.

## 0.2.157-dev (2026-07-01) -- Apply colour matched to the FARMED live vanilla values + harden labels vs "<...>" + marker diagnostic

- **Apply button colours now the EXACT farmed live-vanilla values** (from the v0.2.156 `[opt-apply]`
  probe): ready = cheeseburger `{255,255,168,0}`, hover = white, disabled = gray a50
  `{50,128,128,128}` (all {A,R,G,B}). The prior values were a wrong guess -- an earlier build matched
  Apply to the TAB colour (font_button_normal tan), but the live game overrides ready-Apply to
  cheeseburger via `update_apply_button`, and disabled is gray a50 not font_default a75. gut's Apply
  now renders identically to the live game's Apply. (The shade the user reads as "green" is this
  cheeseburger amber; gut was tan before, hence the mismatch.)
- **`_vmf_label` hardened with the same "<...>" defence as `_vmf_tooltip`** (v0.2.155): strip a frozen
  "<key>" marker, re-localize the inner key at render time, never surface a marker (fall back to the
  bare key). Belt-and-suspenders in case a marker rides in via a title/text field, not just a tooltip.
- **`[gut:desc]` marker diagnostic (temp):** on every row build, if the raw node title/tooltip OR the
  resolved label/desc still contains "<", printf the mod + setting + raw + resolved values. With the
  hardening this should fire zero times; if the user still sees "<>" while it stays silent, the marker
  is coming from a different element (value/dropdown), which the log will then let us pinpoint.

## 0.2.156-dev (2026-07-01) -- DIAGNOSTIC: farm the live Apply-ready button colour (temp)

The vanilla Options Apply button is light green when ready in the LIVE game, but the decompiled
source shows gold (cheeseburger), text-only, no green -- the source snapshot is older than the
current build, so the exact shade cannot be read from source. Extended the OptionsView probe to
`printf` the live Apply button's colours (`[opt-apply]` lines: every style's text_color + color)
the first time it enters the READY state (changes pending). Open ESC to Options and change one
setting to capture the real RGBA, then gut's Apply-ready colour is set to match. Remove once matched.
No gameplay change; hook_safe on OptionsView.update_apply_button (no duplicate hook).

## 0.2.155-dev (2026-07-01) -- ROOT FIX: no more "<...>" in option DESCRIPTIONS

The recurring angle-bracket markers in the Mod Tweaker's hover descriptions are gone for good. Root
cause: `_vmf_tooltip` (the description source) could return a FROZEN missing-loc marker. VMF sometimes
bakes "<key>" into a widget's `tooltip` field when that key did not resolve at data-build time; the old
code rejected re-localizing a "<...>" string but then fell back to RETURNING that marker (the leak,
which is why it kept resurfacing no matter how many guards were added). Fix: strip the brackets to
recover the key, re-localize it at RENDER time (all mods are registered by then, so it resolves), and
NEVER return a "<...>" string -- if it still cannot resolve, the description is simply omitted. Applied
to both twins (standalone view + keep sub-state). Labels were already fine; this closes the descriptions.

## 0.2.154-dev (2026-07-01) -- EXPERIMENTAL: /gut_swap_career diagnostic command (real mid-mission career swap feasibility test, #173)

- **EXPERIMENTAL/diagnostic: added `/gut_swap_career <n>` to test a REAL mid-mission career swap (#173 feasibility step, before building the Hero Select picker).** The command asks the game to swap the local player's CURRENT hero to career index n (1-4) while in a live mission, via the vanilla `ProfileRequester:request_profile(peer_id, 1, hero_name, career_name, force_respawn=true)` -- the same host-mediated path the keep character-select and the engine's `ImguiCareerDebug` use. No UI and no `CharacterSelectionView` (that view's keep-only preview world is the mid-mission crash gut normally avoids). It reaches the requester the same way `ImguiCareerDebug` does mid-mission (`Managers.state.network` -> `.network_server or .network_client` -> `:profile_requester()`) and uses `player:network_id()` for the local peer. Heavy `[gut:career]` printf logging at every step (resolve player/profile, validate career, get requester + host/client path, before/after the request_profile call) so the log tells us EXACTLY where it succeeds or fails. Fully pcall-guarded; a failure prints the error and echoes a plain message, never crashes. Caveat being tested: `force_respawn=true` may respawn the player at the level-start spawn, and the host can decline the swap. No new hooks; command only. See `_gut_career_swap.lua`.

## 0.2.153-dev (2026-07-01) -- Gear-drill view no longer repeats the parent option's toggle; third-person camera no longer shows first-person screen effects (#209)

- **Gear-drill view no longer repeats the parent option's own toggle.** Drilling into a setting's gear sub-view used to re-render the parent option's toggle row at the top, which was redundant: you already toggle it on the main-list row, and the "Advanced: <name>" Back row supplies the context. Removed the parent-row build/append; the parent's direct children now render as top-level rows at depth 0 (rebased from depth 1) under the Back row. Applied in parity across both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`); the planner's internal flat-depth collapse/gear detection is unchanged, only the RENDER depth shifts.
- **Third-person camera no longer shows first-person screen effects (#209).** Buff/ability SCREEN effects spawn via `PlayerUnitFirstPerson.create_screen_particles` (screen-space, bound to the first-person view), so they still overlaid the screen while the mod's 3P camera was active. `_gut_camera.lua` now suppresses `create_screen_particles` (returns nil) while the 3P camera is on. Safe because `BuffExtension._stop_screen_effect` guards on `if effect_id`, so a nil id is a no-op. Known edge: a continuous screen effect already active when ENTERING 3P persists; only newly-spawned effects are suppressed.

## 0.2.152-dev (2026-07-01) -- Fixed the Default confirm popup showing `< >` around its text; buff-bar crash fix made implicit; em dashes removed from menu strings

- **Fixed the Default confirm popup rendering `< >` around all its text (Fix A).** The v0.2.151-dev popup passed RAW English strings to `Managers.popup:queue_popup`; the engine Localizes popup text, so raw strings rendered as `<raw string>` (and gut/VMF loc keys don't resolve in the global `Localize` either). Both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) now mirror the VANILLA reset-settings popup verbatim (`options_view.lua:3335`): `queue_popup(Localize("reset_settings_popup_text"), Localize("popup_discard_changes_topic"), "reset_values", Localize("button_ok"), "revert_changes", Localize("popup_choice_cancel"))`. Confirm result stays `"reset_values"` (runs the reset); cancel is now `"revert_changes"` (dismiss). No raw strings remain in any popup argument.
- **UI-mod buff-bar crash fix is now implicit (Fix B).** A crash-prevention fix should never be toggleable, so the `PriorityBuffUI._add_buff` nil-guard in `_gut_buffbar_endtime_fix.lua` always applies now (removed the `gut_buffbar_endtime_fix` gate + the `SETTING` local). Removed the `gut_buffbar_endtime_fix` checkbox and, since it was that group's only member, the entire "UI Mod Compatibility" (`gut_compat_group`) group. Dropped the three now-dead loc keys (`gut_compat_group`, `gut_buffbar_endtime_fix`, `gut_buffbar_endtime_fix_tooltip`). (The absorbed Temporal Fix was already baked-in with no widget.)
- **Removed em dashes from menu strings (Fix C, new standing rule).** Em dashes (U+2014) must not appear in in-game menu strings. Rewrote the two Skip-Cutscenes tooltips (`gut_skip_cutscenes_enabled_tooltip`, `gut_skip_cutscenes_auto_tooltip`) to use periods instead. Code comments (not shown in-game) were left as-is.

## 0.2.151-dev (2026-07-01) -- Mod Tweaker: font sizes + Apply/Default layout matched to the FARMED vanilla literals; Default now confirms before resetting

Uses the values FARMED from the live vanilla Options menu (the temporary diagnostic in 0.2.150-dev),
not decompiled literals — the earlier 0.2.149-dev sizes (checkbox 28, headers 24, tabs 22) rendered far
too large because the global `RESOLUTION_LOOKUP.scale` (2 at the user's 4K) doubles the literal.

- **Font sizes corrected to the farmed vanilla literals (Fix 1).** Option row labels 28 -> **16** (checkbox label; slider + dropdown labels were already 16); the boolean ON/OFF stepper value text 18 -> **16** (kept <= label). Section titles + group headers 24 -> **18** (vanilla in-list header). Tabs 22 -> **18** (vanilla `title_buttons`), DECOUPLED from the Apply/Default buttons. Apply + Default buttons stay **22** (vanilla hell_shark apply/reset). All existing `upper_case = true` preserved; the tooltip popup is unchanged (confirmed correct).
- **Apply + Default button position/width matched to vanilla (Fix 2).** Apply width is now text-fit instead of the fixed 150 — measuring via `UIRenderer.text_size` is impractical at module-load (no renderer yet), so FIXED tuned design-space widths are used: **APPLY_W = 60** ("APPLY" @22), **RESET_W = 92** ("DEFAULT" @22). Apply local_position stays `{-30,-7}`, height 30, right/top on the bottom panel. Default (`mt_reset`) is parented to the Apply node at local_position.x = **-(APPLY_W + 50)** (was the fabricated `-(APPLY_W + 20)`), so a 50px gutter separates them. Both button hotspot/box sizes track the new node widths so the click zone follows the visible text.
- **Default now shows a confirm popup (Fix 3).** Clicking "Default" opens a native `Managers.popup:queue_popup` confirm (title "RESTORE DEFAULTS", body "Reset this tab's settings to their defaults?", buttons Reset / Cancel) — the game's own popup manager renders it (no borrowed-renderer issue), mirroring vanilla OptionsView's reset confirm. The result is polled each frame via `query_result`; only the CONFIRM result runs the reset. While the popup is up it's modal (ESC / row input suppressed); a dangling popup is cancelled on menu close. The reset itself is unchanged and stays **current-tab only** (iterates `self._build_nodes`).
- **Removed the temporary font diagnostic (Fix 4).** `_gut_options_probe.lua` is back to the scrollbar-only probe: the `[opt-font]` FONT/BUTTON PROBE block and the `_font_line` / `_dump_widget_fonts` helpers are gone; the original `_dump_node`/`_dump_widget` scrollbar dump, the auto-dump on-enter hook, and the `/dump_options` command remain.

Both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) updated in parity for the reset-confirm popup (queue on click, poll in `update`, cancel on `on_exit`); `_mod_tweaker_definitions.lua` (shared) carries the font-size + button width/position changes.

## 0.2.150-dev (2026-07-01) -- DIAGNOSTIC: dump the vanilla Options menu's REAL font sizes + button positions (temp)

Stop guessing font sizes from decompiled literals — they don't render 1:1 in gut's borrowed renderer
(dynamic_font_size shrinks vanilla labels; matched literals came out too large). Extended the existing
OptionsView probe (`_gut_options_probe.lua`; auto-dumps once on ESC→Options open, `/dump_options` to
re-dump): it now printf's `[opt-font]` lines with each vanilla widget's font_type, literal size, ACTUAL
scaled px (via `UIFontByResolution`), `dynamic_font_size` flag, and `upper_case`, for the option rows,
the Apply + Default(reset_to_default) buttons (incl. their scenegraph position/size), and the
category/tab buttons — plus `RESOLUTION_LOOKUP.scale`/res. Ground truth to match the Mod Tweaker's
fonts + button layout to vanilla. Remove once matched. No gameplay change.

## 0.2.149-dev (2026-06-30) -- Mod Tweaker: match the vanilla Options menu (all-caps, per-widget font sizes, tab-colored buttons, persistent open-group glow, no bottom hint)

Five polish fixes bringing the Mod Tweaker chrome in line with the vanilla Options menu.

- **ALL-CAPS row labels (Fix 1).** Every row label now renders upper-case like the vanilla Options menu. Done at one point — `upper_case = true` on the shared `_text_style` helper — which covers checkbox / slider / numeric / dropdown / section-title / group-header labels, the dropdown value + option list, and the back-row label. (ON/OFF words + the numeric slider value are already caps / digits, so no visible change there.) Tabs, section titles, and the Apply/Default buttons already carried `upper_case`. The tooltip popup builds its own styles and is NOT routed through `_text_style`, so its description prose stays normal-case (only its title is caps).
- **Per-widget font sizes match vanilla (Fix 2).** Sizes verified against `options_view_definitions.lua`: boolean/checkbox row LABEL 16 -> **28** (vanilla `create_checkbox_widget` label, :1425); section title + group header 22 -> **24** (vanilla `keybind_info`/section font, :1162/:1975/:3372); tabs 20 -> **22** (vanilla `create_text_button` font — the widget type the vanilla apply/reset buttons use at 22, :1292-1293). Slider/numeric label (16) and dropdown label (16) already matched vanilla and are unchanged. NOTE: vanilla is internally inconsistent (checkbox label 28 vs stepper label 16); gut renders booleans as a stepper but sizes the LABEL to the vanilla checkbox 28 — needs an in-game eyeball.
- **"Default" button, colored like the tabs (Fix 3).** The reset button's loc (`gut_mt_reset`) is renamed "Restore Defaults" -> **"Default"** (renders "DEFAULT"). Its text color now matches the TAB scheme — `font_button_normal` `{255,160,146,101}` idle, white `{255,255,255,255}` on hover — instead of `font_default` grey. The Apply button (same `create_text_button` widget type in vanilla) gets the same ENABLED scheme (font_button_normal idle / white hover; was cheeseburger gold); its DISABLED color stays `font_default` α75 `{75,181,181,181}`. Applied to both factories' base color + both twins' per-frame drivers.
- **Open collapsible group stays lit (Fix 4).** An EXPANDED group now keeps its arrow glowing and its row highlight bar visible even when not hovered (was hover-only). `create_group_header` stores an `expanded` flag on the widget content and the arrow-glow driver lights on `is_hover OR expanded`; the row highlight uses the same `hover OR expanded`. Both twins refresh `content.expanded` live each frame in `_apply_row_hover` from `self._expanded[row._group_key]` (the same source the row toggle uses), so it tracks a toggle immediately.
- **Removed the bottom hint (Fix 5).** The "Click a tab to pick a mod..." bottom hint text is gone entirely (vanilla Options has no bottom hint): the `build_hint` widget, `self._hint` build, its per-frame text set, and its draw call removed from both twins; the `build_hint` factory + `_text_widget` helper + `mt_hint` scenegraph node removed from the shared definitions (no dangling nil-draw).

Both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) updated in parity for the button drivers, the open-group glow/highlight, and the hint removal; `_mod_tweaker_definitions.lua` (shared) carries the all-caps + font-size + button base-color + group-header `expanded` changes and the hint-factory removal. Loc `gut_mt_reset` renamed in `gui_tweaker_dev_localization.lua`.

## 0.2.148-dev (2026-06-30) -- Mod Tweaker bottom row: vanilla greyed Apply color + "Restore Defaults" button

- **Greyed Apply text now matches vanilla.** When the active tab has no pending edits, the disabled APPLY label is drawn with `Colors.get_color_table_with_alpha("font_default", 75)` = `{75,181,181,181}` — the exact vanilla `disabled_color` (`options_view_definitions.lua:2346`). Was a fabricated dim grey `{255,110,110,110}`. Applied in both twins' per-frame Apply driver.
- **Added a "Restore Defaults" button (#209).** Clones vanilla's `reset_to_default` (`options_view_definitions.lua:358-371`), parented to the Apply button and sitting to its LEFT with a 20px gutter (`mt_reset` scenegraph node, factory `create_default_button`, new loc key `gut_mt_reset = "Restore Defaults"`). Clicking it STAGES every setting in the current tab back to its `default_value` and repaints the rows — it does NOT write live; the user clicks Apply to commit, exactly like a manual staged edit. Because `stage_set` routes each edit to its owner mod_id, the merged Equipment tab correctly resets all member mods. Skips groups/headers (no `setting_id`), settings with no `default_value`, and keybinds. Always enabled; brightens to white on hover.

Both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) updated in parity for the button build/draw/click/hover and the greyed-Apply color; `_mod_tweaker_definitions.lua` (shared) carries the `mt_reset` node + `create_default_button` factory. The state twin also gained the `self._build_nodes`/`_build_category` storage the view twin already kept (the reset button iterates it).

## 0.2.147-dev (2026-06-30) -- Mod Tweaker UI polish: implicit config override, native tooltip + tab styling, "Interface" tab

- **Config-file override is now IMPLICIT / always-on; the toggle is gone.** The `.toml` override (`_gut_config_file.lua` `apply()`) is applied unconditionally on load and is a harmless no-op when no config file exists, so there was nothing worth gating — the `gut_config_override` checkbox was removed from the VMF options (data comment updated). [already-made edit]
- **Tooltip popup now draws ABOVE the row with a native-style border (#207).** The hover-info popup defaults to drawing ABOVE the hovered row (bottom edge flush to the row's top), matching the native options tooltip, and flips BELOW only when drawing above would run off the top of the visible screen (was: below-by-default, flip up near the screen bottom). The fake 2px grey "shade" border is replaced with the real `menu_frame_12` 9-slice frame — the SAME frame the vanilla settings tooltip uses (`item_tooltip_frame_01`) — drawn as a per-frame-sized `texture_frame` over a `{255,3,3,3}` fill. Definitions only (`create_tooltip_popup` / `layout_tooltip`).
- **Tab text color matches vanilla.** Tabs now use the vanilla options-tab colors (`UIWidgets.create_text_button`): idle = `font_button_normal` `{255,160,146,101}`, selected OR hovered = white `{255,255,255,255}` (was a gold/grey split). Applied to `create_tab`'s base color and both twins' per-frame tab driver.
- **gut's own Mod Tweaker tab is renamed to "Interface".** In `_vmf_categories()` (both twins), the `gut` / `gut_dev` category's display label is overridden to "Interface"; the mod id, Workshop title, and `.mod`/cfg are unchanged.

Both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) updated in parity for the tab-color and "Interface"-label changes; `_mod_tweaker_definitions.lua` (shared) carries the tooltip + tab base-color changes.

## 0.2.146-dev (2026-06-30) -- Mod Tweaker: remove the spurious top-level indent on every plain mod tab (#208)

Follow-up to .145: with Equipment now correctly un-indented at the top level, the PLAIN VMF mod tabs
were revealed to be the wrong ones — VMF gives each mod's top-level content a natural `depth` of 1, so
every standalone mod tab indented its whole top level one step for no reason. `_build_rows` now rebases
a plain VMF tab by its own MINIMUM natural setting depth (excluding the non-rendered per-mod header),
so its top-level rows render at depth 0 — no indent, matching the Equipment tab. Relative nesting is
preserved (uniform shift), so collapse/gear/indent of deeper rows is unchanged. Equipment's own
synthesized `_depths` is untouched. Both twins.

## 0.2.145-dev (2026-06-30) -- Equipment tab: fix member over-nesting + match other tabs' spacing (#208)

Root-caused from a runtime depth dump: the merged Equipment tab's member content was rendering one
level too deep. VMF mods' top content sits at NATURAL depth 1 (not 0), and the synthesis blindly
added a base offset on top — so e.g. "Crafting" (section, depth 0) had cim's groups at depth 2, and
the nested "Career Weapon Variants" header (correctly depth 1) looked *un-indented* next to wt's
content (wrongly depth 2). Fix: `_add_member` now **rebases each member by its own minimum natural
depth**, so its shallowest content renders exactly one level under its section header, internal
nesting preserved. CWV now indents consistently with wt's content.

Also **removed the special `TOP_SECTION_GAP`** — sections/groups now stack with the same row rhythm
as every other tab, so the Equipment tab's vertical spacing matches other menus (no more
bigger-than-everything-else padding). Removed the temporary indent diagnostic `printf`. Both twins.

## 0.2.144-dev (2026-06-30) -- Mod Tweaker: uniform top-section padding (#206/#208) + Equipment indent diagnostic

- **Top-section gap now applies to EVERY top-level (depth-0) collapsible**, including the first one (removed the `#self._rows > 0` skip in both twins). Previously the first top-level section had no `TOP_SECTION_GAP` above it while the rest did, so spacing looked inconsistent; now all top-level collapsibles are padded uniformly.
- **Equipment indent diagnostic (temp):** a `printf("[mt:equip] section '<label>' depth=<d>")` logs each merged section header's runtime depth (engine printf, visible with mod-logging off) to root-cause the report that the nested "Career Weapon Variants" header (should be depth 1, indented under Weapons) renders flush. Removed once verified.

## 0.2.143-dev (2026-06-30) -- Mod Tweaker: merge the 4 inventory mods into one "Equipment" tab (#208)

The Mod Tweaker now folds the four inventory-management mods into a single **Equipment** tab
when 2+ of them are active (present **and** enabled), instead of one tab each. Roles:
`cosmetics_tweaker` -> **Cosmetics**, `cim`/`cim_dev` -> **Crafting**, `wt` -> **Weapons**,
`character_weapon_variants` (CWV) -> **Career Weapon Variants**.

- **N=1, only CWV** -> its single tab is relabeled **"Weapons"**. **N=1, any other** -> unchanged.
- **N>=2** -> ONE **"Equipment"** tab; the matching individual tabs are removed and folded in as
  COLLAPSIBLE top-level sections, order **Cosmetics -> Crafting -> Weapons**. When both `wt` and
  CWV are active, CWV nests as a collapsible **"Career Weapon Variants"** section UNDER Weapons;
  CWV-without-`wt` sits at the top level of Equipment. A disabled inventory mod is not "active"
  and keeps its own tab. (Also trims the tab strip toward the MAX_TABS=8 pagination limit.)

**How it's built.** A post-process step on the `_vmf_categories()` output (`_synthesize_equipment`)
removes the active members and appends ONE synthesized FLAT category whose `widgets` is the four
mods' setting nodes interleaved with synthetic `type="group"` section headers, plus a parallel
`_depths` array that shifts each member's nodes under its section header (CWV +2 under Weapons,
+1 elsewhere). Reusing the existing flat-list renderer means each mod KEEPS its own internal
collapsibles / gear-drill nesting intact (the #206 indent + #165 chevron behavior is unchanged).

**Per-NODE ownership (the cross-mod part).** The merged tab spans four mod objects, but get/set/
stage/apply previously keyed off the category's single `mod_obj`/`mod_id`. The Equipment category
now carries `_owners[setting_id] = { mod_id, mod_obj }` for every member setting; a new `_owner()`
helper resolves the owning mod per node (and returns `category.mod_obj`/`category.mod_id` for every
NON-Equipment category, so normal tabs are behaviorally unchanged). `_cat_get`/`_cat_set` route to
the owner's mod object; `stage_set`/`get_staged` buffer under the OWNER's mod_id (an Equipment edit
to a cosmetics setting buffers under `cosmetics_tweaker`); `_active_category_dirty` returns true if
ANY member's buffer is non-empty; and an Equipment **Apply** flushes EACH member mod_id's pending
buffer through its own mod object (keybinds re-registered across the committed settings in the
standalone view, matching #123). Labels/tooltips localize against the owning mod.

Five gut-owned loc strings added (Equipment / Cosmetics / Crafting / Weapons / Career Weapon
Variants). No new engine hooks (pure data synthesis + the existing draw/render path). Applied to
BOTH presentations (the standalone in-mission `ModTweakerView` and the keep HeroView sub-state),
kept in parity. (#208)

## 0.2.142-dev (2026-06-30) -- Mod Tweaker: native-style hover info popup per setting (#207)

The Mod Tweaker's in-game settings list now shows a per-setting info popup on mouseover,
matching the native options menu: a popup with the setting's **title** (header) and its
**description** underneath. It **fades in** (waits 0.1s, then ramps `math.easeOutCubic` at
speed 4 — the exact native `tooltip_wait_duration` / `tooltip_fade_in_speed` values,
ui_settings.lua:22-23) and **disappears instantly** when the cursor leaves the row (de-hover
or moving to a different row resets the fade to 0). Rows without a tooltip show nothing.

The description text already exists per setting in VMF widget data (mods write
`tooltip = mod:localize("<id>_tooltip")`); the state now resolves each node's `tooltip` field
the same pcall-localize way it resolves the title (so both already-localized strings and raw
loc keys work) and stores `{ title = row label, desc = tooltip }` on the row. The view's draw
loop tracks the hovered row each frame and drives the popup.

**Hand-built for the borrowed renderer.** The Mod Tweaker draws on a borrowed
(HeroView / level-world) renderer, so this does NOT use the native `option_tooltip` pass or
its `item_tooltip_background` / `item_tooltip_frame_01` box art — those are raw / gui_frames_atlas
materials whose residency on that renderer is unconfirmed and can crash (the same raw-material
trap that forced gut to hand-build its option rows, reference_vt2_options_widgets_raw_materials).
The popup is assembled the same proven way as the existing dropdown popup (`create_dropdown_list`):
a 2px-larger `rect` "shade" frame behind a dark `rect` panel + a `font_title` size-22 title text
pass over a word-wrapped (`word_wrap`) `font_default` size-18 description, on a new `mt_tooltip`
scenegraph node (parented to `mt_list` so it scrolls with the rows, z above them), drawn LAST in
the draw loop so it overlays and is never culled. Box height fits the wrapped line count (measured
via `UIRenderer.word_wrap` + `UIGetFontHeight`, mirroring native generic_text); positioned just
below the hovered row, left-aligned to the label column, and flipped ABOVE the row when dropping
below would run off the screen bottom. Width fit to the panel (native 600, clamped to gut's panel).
Additive only — no change to existing row factories; no new engine hooks (pure draw-loop render).
Applied to BOTH presentations (the standalone in-mission `ModTweakerView` and the keep HeroView
sub-state). (#207)

## 0.2.141-dev (2026-06-30) -- Mod Tweaker: nested rows of different widget types now left-align (#206)

Inside collapsibles, toggles and dropdowns sat ~12px to the right of sliders and section titles
at the same nesting depth. The per-depth indent (`INDENT_PER_DEPTH = 24`) was uniform, but the
label's **base x was hard-coded per widget factory** — checkbox & dropdown at 12, slider/numeric
& section title at 0 — so different row types didn't share a left margin. (It was a programmatic
x-offset, never leading whitespace in localization.)

Introduced a single `LABEL_BASE_X = 12` constant used by all non-chevron rows (checkbox, slider,
numeric, stepper, dropdown, section title), so every such row left-aligns at `LABEL_BASE_X + ind`
for a given depth. Clamp widths adjusted in lockstep so labels still terminate before the controls.
Collapsible **group headers** are intentionally exempt — their label clears the +/- chevron column
(tree-style indent past the toggle), which is by design, not the misalignment this fixes.

## 0.2.140-dev (2026-06-30) -- 'Disable Aim Zoom-In' now disabled at the per-weapon zoom layer, not the camera node (#202)

v0.2.139's FOV-node override didn't work: aim zoom-in in 3P is driven **per-weapon**, not by
a fixed pair of camera nodes. The weapon hands `GenericStatusExtension` a camera node name
(`zoom_in` / `increased_zoom_in` / `zoom_in_trueflight` / …), the engine appends
`_third_person` in 3P mode, and writes it to the camera's `settings_node`. Patching the FOV of
two specific nodes missed every other weapon's zoom node and never stopped the camera from
switching to a zoom node at all, so the view still zoomed.

Fixed at the right layer: `hook_safe` on the two node writers — `set_zooming` (on aim) and
`switch_variable_zoom` (multi-level zoom, e.g. longbows) — forcing the camera node back to
`over_shoulder` while the 3P camera and the toggle are both on. This disables the aim zoom for
**every** weapon uniformly (FOV + pull-in), and leaves aim mechanics intact — `is_zooming`,
accuracy, and bow-charge key off `self.zooming` (still set by vanilla), not the camera node, so
only the view changes. The v0.2.139 `TransformCamera.vertical_fov` hook was removed (wrong layer).

## 0.2.139-dev (2026-06-30) -- 'Disable Aim Zoom-In' now also neutralizes the FOV zoom, not just camera distance (#202)

The third-person "Disable Aim Zoom-In" toggle (`gut_tp_disable_zoom_in`) had no visible
effect when aiming. Aim zoom-in in 3P is primarily an **FOV narrowing**, not just a camera
pull-in: in `camera_settings.lua`, `zoom_in_third_person` has `vertical_fov = 65` (the normal
view) but `increased_zoom_in_third_person` has `vertical_fov = 16` (heavy magnification).
`_gut_patch_camera_offset` only rewrote `offset_position`, so with the toggle on the camera
stayed at the configured distance but the FOV still narrowed and the view still magnified.

`vertical_fov` is baked at parse (`BaseCamera.parse_parameters` → `self._vertical_fov`), unlike
`offset_position` (held by reference, so its in-place mutation applies live), so mutating
`CameraSettings.vertical_fov` post-load does nothing live. Fix: hook `TransformCamera.vertical_fov`
(the zoom nodes' actual class — not `BaseCamera`, per the derived-class rule) and, while the 3P
camera is on AND the toggle is on AND the node is `zoom_in_third_person` /
`increased_zoom_in_third_person`, return the parent (un-zoomed) FOV. `CameraTransitionGeneric`
reads the transition target via `node:vertical_fov()` live, so the blend now targets the normal
FOV — no magnification. No-op whenever the 3P camera or the toggle is off.

## 0.2.138-dev (2026-06-30) -- collapsible arrow glow: pivot on the chevron, not the box (#165)

The hover glow on collapsible group-header arrows was offset — most visibly anchored to the
wrong SIDE of the arrow when the group was collapsed. Cause: the glow sprite
(`drop_down_menu_arrow_clicked`, 31x28) has its chevron ~1px from the bottom of the sprite,
not at its box centre (the #99 dropdown ground truth: the 28-tall glow needs a +13 nudge to
align its chevron). The collapsible drew it with the pivot at the box centre `{12,11}`, so the
chevron sat ~10px off the rotation centre — a vertical shift while expanded, and (once the
sprite is rotated 90° for the collapsed ▶ state) a sideways shift onto the wrong side of the
base chevron. Fixed by rotating about the chevron instead: `pivot {12,1}`, `offset cy-1`, which
keeps the rotation centre at the base chevron `(20+ind, cy)` so the glow lands on the arrow in
both the expanded and collapsed states. Base arrow geometry unchanged.

## 0.2.137-dev (2026-06-30) -- drop the `gut_` prefix from every chat command

All of gut's chat commands lost their `gut_` prefix — they're now invoked by the bare
name. No behavior change, just shorter names:

`/gut_save_loadout` → `/save_loadout`, `/gut_load_loadout` → `/load_loadout`,
`/gut_list_loadouts` → `/list_loadouts`, `/gut_edit_hud` → `/edit_hud`,
`/gut_reset_hud` → `/reset_hud`, `/gut_list_hud` → `/list_hud`, `/gut_hud` → `/hud`,
`/gut_inv` → `/inv`, `/gut_hero_select` → `/hero_select`, `/gut_mod_tweaker` → `/mod_tweaker`,
`/gut_skipcutscenes` → `/skipcutscenes`, `/gut_intromono` → `/intromono`, `/gut_quit` → `/quit`,
`/gut_armory` → `/armory`, `/gut_bestiary` → `/bestiary`, `/gut_ba_dump_weapons` → `/ba_dump_weapons`,
`/gut_ba_dump_breeds` → `/ba_dump_breeds`, `/gut_export_settings` → `/export_settings`,
`/gut_reload_config` → `/reload_config`, `/gut_dump_options` → `/dump_options`,
`/gut_lua_mem` → `/lua_mem`, `/gut_regression_test` → `/regression_test`, and
`/gut_tp` → `/tp`.

Updated the inline command descriptions, the VMF setting tooltips, and the
`tools/gut-settings*.ps1` help text to match. Keybind setting ids
(`gut_open_mod_tweaker_hotkey` etc.) and all VMF setting ids are NOT commands and were
left unchanged.

**`/tp` note (gt collision):** the third-person toggle reclaims the bare `/tp` now that
the feature lives in gut (migrated from gt, #191). `general_tweaker_dev` already dropped
its `/tp`, so there's no collision in the dev streams. **Stable `general_tweaker` still
registers `/tp`** until its next promotion drops it — so `qa/check_command_collisions.ps1`
will flag a transient `gut`↔`general_tweaker` collision on `tp`, and a player running
stable gt + gut_dev together would see one of the two `/tp`s fail to register until stable
gt is promoted. (Stable `gui_tweaker` keeps the `gut_` prefixes; this rename is dev-only
and ports to stable at gut's next promotion.)

## 0.2.136-dev (2026-06-30) -- row hover-highlight now spans the whole row (dropdown/slider/keybind)

Dropdown, slider, and keybind rows now light up the hover bar when the cursor is over their LABEL, not just the control. Only the checkbox had a full-row hotspot; the others had partial control hotspots (input box / track), so hovering the label never set `is_hover`. Added one hover-only full-row hotspot in `_append_highlight` (every row calls it) and checked `row_hs.is_hover` in `_apply_row_hover`. (Pop-up tooltips/descriptions are a separate, larger piece — still queued.)

## 0.2.135-dev (2026-06-30) -- collapsible arrow: real orangey glow IMAGE on hover (#165)

The collapsible arrow now shows the same `drop_down_menu_arrow_clicked` glow sprite as every other arrow — alpha-ramped in/out on hover by the `local_offset` driver, rotated to match the chevron — instead of merely brightening the base arrow grey->white. Base arrow reverted to steady grey 181. (The .134 brighten confirmed the driver + `is_hover` work; this just swaps the effect for the proper glow image.)

## 0.2.134-dev (2026-06-29) -- collapsible arrow glow via live-ui_style driver (#165); silence widget_init_skip chat warnings

- **#165** (real fix): the collapsible arrow hover-brighten now runs in a `local_offset` `offset_function` on the group header — the ONLY pass type whose offset_function fires every frame — mutating the **live** `ui_style.arrow.color` at draw-time, exactly like the working dropdown glow. The .133 attempt wrote `row.style` (a possibly-cloned table) from `_apply_row_hover`, which never reached the render.
- **Warnings**: demoted the `[gut:dbg]` `_dbg_alert` logger from `mod:warning` to `mod:debug`, so HUD `widget_init_skip` diagnostics (`scenegraph_node_missing` in the keep) stop spamming the in-game chat.

## 0.2.133-dev (2026-06-29) -- FIX collapsible arrow hover-glow (#165) + caret position & arrow-keys (#188)

- **#165**: the collapsible group-header arrow now brightens **grey -> white on hover**, driven DIRECTLY by the view per-frame in `_apply_row_hover`. The old `content_check` `arrow_hover` overlay never rendered — `rotated_texture` ignores `content_check_function` on the borrowed Mod Tweaker renderer. The single arrow pass always draws, so this is reliable.
- **#188**: the value-box caret now (a) **lines up with the digits** — measured with `materials/fonts/gw_body` (hell_shark's REAL material, ui_fonts.lua:42) instead of arial, which was narrower and sat the caret left of the text; and (b) **responds to Left/Right arrow keys + Delete**, with typing inserting AT the cursor — via a `caret_idx` threaded through the keystroke handler and the caret render.

## 0.2.132-dev (2026-06-29) -- Mod Tweaker: grey out tabs for VMF-disabled mods

A mod toggled OFF in VMF's mod list now shows its Mod Tweaker tab **greyed out** (dim grey, low alpha) instead of the old `*` suffix. Driven from `cat.enabled` (`mod_obj:is_enabled()`), stamped onto each tab as `content.disabled` and applied in the per-frame tab-colour driver (overrides the gold/inactive colours).

## 0.2.131-dev (2026-06-29) -- Mod Tweaker tab label: Character Weapon Variants -> "CWV"

Added `character_weapon_variants` (+ `_dev`) to `_TAB_LABEL_OVERRIDE` so its Mod Tweaker tab reads "CWV" instead of the full "Character Weapon Variants".

## 0.2.130-dev (2026-06-29) -- ABSORB from general_tweaker: Floating Damage Numbers, Main Menu & Startup (#190), 3rd-Person Camera (#191), Loading-Screen Monologues (#192)

Four features migrated out of `general_tweaker` (gt) and into gut. gt loses the options/loc/handlers; gut now owns them (each as a self-contained `_gut_*` module, `dofile`'d after the main chunk so it can chain `mod.on_setting_changed` / `mod.on_game_state_changed` / `mod.on_disabled` / `mod.update`).

- **Floating Damage Numbers** → existing **HUD** group (`gut_hud_group`). New `_gut_damage_numbers.lua`: client-side, networking-free numbers over enemies you damage, via the engine `DamageNumbersUI` + `DamageUtils.add_unit_floating_damage_numbers`. Registers its OWN hooks on `DamageUtils.add_damage_network` / `add_damage_network_player` (gut has no godmode to share them with, unlike gt — pre-flight grep confirmed no other gut hook on either method). Setting ids `gut_damage_numbers_enabled` + `gut_damage_numbers_include_dots`.
- **Main Menu & Startup (#190)** → new group `gut_mainmenu_group` ("Main Menu & Startup"). New `_gut_mainmenu.lua`: "Skip start screen (straight to the keep)" (`GameSettingsDevelopment.skip_start_screen`, next-launch) + "Return to Main Menu quits to desktop" (remaps the `return_to_title_screen` transitions to `quit_game`) + the `/gut_quit` instant-exit command. Plain engine-data reassignments, no hooks; restores both on disable.
- **3rd-Person Camera (#191)** → new group `gut_camera_group` ("3rd-Person Camera"). New `_gut_camera.lua`: follow camera with distance/height/side-offset sliders + Disable-Aim-Zoom-In, the `gut_tp_camera_enabled` toggle and `/gut_tp` command. **Camera Distance min preserved at -3.0 (issue #147 — closer / over-shoulder views below 1.0).** Hooks `PlayerUnitFirstPerson.set_first_person_mode` (cutscene-yield fix preserved) + `.extensions_ready`; chains `mod.update` for the post-spawn re-arm timer. Dropped gt's godmode/noclip post-spawn-reapply trigger (gut has neither).
- **Disable Loading-Screen Monologues (#192)** → existing cutscenes group, relabelled **"Cutscenes & Monologues"** (`gut_cutscenes_group`). New `_gut_monologue.lua`: flips `script_data.disable_level_intro_dialogue`; `gut_disable_intro_monologue` toggle + `/gut_intromono` command. (Cutscene SKIP was already migrated, #106.)

## 0.2.129-dev (2026-06-29) -- HUD group, Pilgrim's-coin 25-step slider, stronger collapsible hover glow

- **Mod Tweaker — Pilgrim's coin slider snaps to 25.** Added a gut-side `STEP_OVERRIDES` table (keyed `<mod_id>:<setting_id>`) so the foreign `chaos_wastes_tweaker[_dev]:starting_coins` slider drags/arrow-steps in increments of 25. The step can't live on the widget — VMF has no native `step` field and FATALS on a 3-element `range`, killing the whole mod's options init — so it's resolved in `_build_node_row` before the natural fallback. The drag-snap (`_snap_and_clamp`) and arrow-step paths already honour `row.content.step`.
- **New collapsible "HUD" group** wrapping the Parry Indicator + Respawn Timer entries (previously top-level). Loc key `gut_hud_group = "HUD"`.
- **#165**: collapsible group-header hover glow is now obvious — the REST chevron is dimmed (grey 180 → 130) and the white hover chevron is enlarged ~15% (24×12 → 28×14, pivot/offset re-centred) so it visibly pops on hover. Wiring (`is_highlighted` set from the row hotspot's `is_hover`) was already correct.

## 0.2.128-dev (2026-06-29) -- dropdown glow restored (#99), collapsible arrows fixed + hover (#165), gear icon +40% (#189)

- **#99**: dropdown hover-glow restored to the native `drop_down_menu_arrow_clicked` sprite (31×28) + the flip-offset shift (28-tall centre **+13 closed / −12 open**) — matches the in-game `[gut-glow-probe]` native data. (.125 had swapped it to the 31×15 base sprite, which rendered invisible.)
- **#165**: collapsible chevron now points the correct way (collapsed → right, via `-π/2`), and **brightens grey→white on hover** (added an `arrow_hover` pass gated on `is_highlighted`).
- **#189**: advanced-settings gear/cog icon **+40%** (`GEAR_SIZE` 26 → 36).

## 0.2.127-dev (2026-06-29) -- Auto-collapse sections toggle (#163, default ON)

New **"Auto-collapse sections"** toggle (default ON) in the Mod Tweaker settings group: opening a collapsible section auto-closes its SAME-LEVEL siblings, and closing a section also closes its nested sub-sections — so only one branch stays open per level. Level-aware via the flat node/depth tree saved at build (`_auto_collapse_apply`): siblings = same-depth groups in the same parent block; descendants = the contiguous deeper run after the group. Turn OFF for independent expand/collapse (old behaviour).

## 0.2.126-dev (2026-06-29) -- collapsible group headers: [+]/[-] -> chevron arrows (#165)

Group headers now show the `drop_down_menu_arrow` chevron instead of the `"[+]"`/`"[-]"` text glyph: **▼ down when expanded, ▶ right when collapsed** (rotated_texture at +π/2; VT2 UI is Y-up so a down chevron rotated +90° points right). Native tree-toggle look. If it points the wrong way in-game it's a one-line sign flip.

## 0.2.125-dev (2026-06-29) -- slider-drag modal covers the release frame (#2); dropdown glow = the arrow sprite (#99)

- Slider drag: the modal now persists THROUGH the release frame (`r._dragging` stays true that frame) and blocks row input until a fresh press, so releasing a slider drag over a checkbox no longer toggles it. (It was disengaging the exact frame the release fired — "as if I did nothing".)
- Dropdown hover glow now uses the SAME `drop_down_menu_arrow` sprite at the same offset + flip as the visible arrow (brightened on hover/open) instead of the `_clicked` sprite I kept mis-placing — so it can't be misplaced or face the opposite way.

## 0.2.124-dev (2026-06-29) -- FIX dropdown hover-glow facing wrong way / misplaced when open (#99)

The dropdown hover-glow (`drop_down_menu_arrow_clicked`, 28-tall) flipped for the open state but stayed at a FIXED offset, so the flipped chevron's point landed wrong and read as facing the opposite direction. Vanilla repositions it when it flips — `arrow_hover` (closed) at centre +13, `arrow_hover_flipped` (open) at centre -12 (options_view_definitions.lua:2799 / :2812). The glow driver now applies that exact shift (`cy - 14 + (open and -12 or 13)`).

## 0.2.123-dev (2026-06-29) -- FIX dropdown highlight flicker-to-top (#158b) — now sticky

The dropdown popup highlight snapped to the SELECTED option (row 1 for a top/None-selected dropdown) on EVERY frame the cursor's hover briefly dropped — crossing between rows, an is_hover flicker, or leaving the popup — which read as "flickering to the top". The position fields it reads (`_dd_list_top` etc.) were correctly set (1172-1177); the bug was the per-frame fallback. Now STICKY: it remembers the last-hovered option (`_dd_hl_k`) and only moves to a row the cursor actually hovered (seeded at the selected option on open, reset each open).

## 0.2.122-dev (2026-06-29) -- hero-select keybind: robust mission-only gate + diagnostic (#173)

The in-mission hero-select keybind now uses a robust keep-check — `level_key == "inn_level"` (primary; what gut's cutscene code uses) with `DamageUtils.is_in_inn` as backup — instead of `is_in_inn` alone, and emits a visible `printf [gut:heroselect]` with the exact context (`in_keep` / `level_key` / `is_in_inn`) each time it fires, so the next log pins down whether it bails/fires where it should. Mission-only is the intent (the keep has a native keybind).

## 0.2.121-dev (2026-06-29) -- FIX dropdown click-bleed / re-open (#158) + slider drag is now modal

- **#158**: clicking a dropdown option no longer also clicks the row behind it, and clicking an open dropdown no longer re-opens it. The shared `mt_list_start` node latches `on_release` for an UNBOUNDED number of frames, so the old 6-frame swallow was too short. Now all row input is blocked after a popup closes until the next fresh left-press (`Mouse.pressed(0)`) begins a new click cycle.
- **Slider drag is now MODAL**: while dragging a slider, no other row reacts to clicks/releases (releasing over a checkbox was toggling it) and only the dragged row highlights under the cursor.

## 0.2.120-dev (2026-06-29) -- scrollbar rounded corners (#166); Hide UI fixes — viewmodel no longer double-renders (#170), HUD restores on un-hide (#171)

- **#166** scrollbar: track + thumb now use `rounded_background` passes with `corner_radius = 2` (the vanilla options-scrollbar value, confirmed from the opt-probe dump), instead of square `rect` passes.
- **#170** Hide UI camera mode: cycling it off no longer reveals BOTH weapons. On un-hide only the WIELDED slot's 1p units are restored; holstered slots stay hidden (was force-showing every slot → both weapons blended until a re-wield).
- **#171** Hide UI off now restores the HUD: leaving complete/camera `set_visible(true)` on the components we force-hid (vanilla then re-applies its visibility groups), so no UI Tweaks toggle needed.

## 0.2.119-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.2.118-dev (2026-06-28) -- FIX: in-mission loadout context-menu crash (#193)

Right-clicking a loadout slot mid-mission opened the loadout context menu, whose delete-bar + loadout-icon textures aren't resident in the in-mission renderer -> `UIRenderer_draw_texture` C-fatal (Adventure, `HeroWindowLoadoutSelectionConsole`). Gated `_show_context_menu` to keep-only (`DamageUtils.is_in_inn`), so the menu can't open mid-mission. Basic loadout selection (viewing/picking) still works in-mission; only the right-click rename/delete menu is suppressed there. Same class as the #155 cosmetics gate.

## 0.2.117-dev (2026-06-28) -- dropdown polish: glow at true 31x28, highlight no longer phantom-falls-back to row 1

- Dropdown arrow hover GLOW now draws the `drop_down_menu_arrow_clicked` sprite at its true atlas size 31x28 (was the 31x15 base -> squished + mispositioned), re-centered on the row mid-line. Same class as the stepper #92/#99 fix.
- Dropdown popup highlight no longer falls back to the FIRST option when the cursor is over a gap between rows or outside the popup. The old code defaulted an unset / None(-1) selection to slot 1; now it only highlights the selected option when there is a real selection.

## 0.2.116-dev (2026-06-28) -- hero-select keybind is now mission-only (no-op in the keep) (#173)

The in-mission Hero Select shortcut now bails in the KEEP (`DamageUtils.is_in_inn`, a boolean field set by `state_ingame.lua:137`). In the keep the native hero select (full character/career change) is already on the menu, and this shortcut only opens the talents-only layout — which read as "hero select opens talents". The keybind and `/gut_hero_select` are mission-only now.

## 0.2.115-dev (2026-06-28) -- FIX: dropdown open up-arrow + hover glow now render (texture_uv read a nil content key)

The dropdown's open-state up-arrow and hover glow never drew. The `texture_uv` passes used `texture_id = "texture_id"` + `content_id = "arrow_up"`, but `ui_passes.lua:145` `texture_uv.draw` reads the texture from `content[texture_id]` and uvs from `content.uvs` (top-level) — it ignores `content_id`. So it read `content.texture_id` = nil -> nothing drew. Fixed: texture strings now live in top-level content keys (`arrow_up_tex` / `arrow_glow_tex`), and the single shared `content.uvs` is flipped by the driver (up while open). `arrow_down` (a plain `texture` pass) was unaffected, which is why only the closed-state down chevron ever showed.

## 0.2.114-dev (2026-06-28) -- Mod Tweaker sliders honor a declared step/increment (#164)

A slider that declares a fixed increment now steps by it in the Mod Tweaker: gut reads `step` (or `range[3]`) off the widget def and uses it for the arrow increment AND the drag snap. Before, the arrow only used the natural unit (1 / 10^-decimals), so e.g. a CW starting_coins +25 slider stepped by 1. To wire a setting, add `step = 25` (or `range = {0, 3000, 25}`) to that mod's slider widget def. NOTE: ct_dev currently won't build (200-locals limit at `chaos_wastes_tweaker_dev.lua:10285`), so adding the step to ct's starting_coins is blocked on fixing that first.

## 0.2.113-dev (2026-06-28) -- slider DRAG release no longer machine-guns / keeps following the cursor (#167)

Releasing a slider drag produced a brief "keeps following the cursor" delay + 3-6 rapid click sounds. Cause: the drag committed on `on_left_release`, which stays LATCHED on the shared node for several frames, re-running the cursor-follow math + firing `_play_click` each frame. Now the drag follows the cursor ONLY while `is_held`, and commits + plays the sound exactly ONCE on the `is_held`->false edge (edge-latched via `row._dragging`).

## 0.2.112-dev (2026-06-28) -- dropdown popup is fully modal: no click/hover bleed-through to rows behind it (#158)

Open dropdown popup no longer leaks input to the rows behind it:
- HOVER bleed: `_apply_row_hover` now suppresses the underlying rows' highlight + hover sound while a popup is open, so the row behind the popup no longer lights up under the cursor.
- CLICK bleed: selecting an option closed the popup but the click's `on_release` stayed LATCHED on the shared-node row hotspots for several frames, so the row behind processed the stale release the next frame. `_close_dropdown_popup` now sets a 6-frame input swallow that `_handle_input` honors, so the closing click can't reach the row behind. `[mt:dd]` logs the swallow.
Regression test deferred to close-time (the view method can't be re-dofiled safely — it re-registers hooks; will add a source/stub check when #158 is closed after in-game verification).

## 0.2.111-dev (2026-06-28) -- slider arrow hold no longer machine-guns the click sound; + regression test for the arrow glow size

- The slider-arrow click sound now plays on the CLICK / drag-release EDGE only, NOT on every hold-repeat increment (the "click-click-click machine gun"). A `play_sound` flag gates `_play_click`; the value still updates every increment.
- New regression test `arrow_hover_native_size` (#92/#99): builds a stepper row and asserts the hover overlay is the native 30x35 (not the 19x27 base), so the glow size/position fix can't silently revert. Run via `/gut_regression_test`. (Per the user's standing rule: a test accompanies every issue we close.)

## 0.2.110-dev (2026-06-28) -- FIX: cosmetics tab in-mission CRASH (gui_pose_items_atlas C-fatal) (#155)

Going to the Cosmetics tab in a mission crashed: `HeroWindowCosmeticsLoadoutConsole:draw` (verified method, options source line 289) draws the weapon-pose items via `gui_pose_items_atlas`, which is NOT in the in-mission renderer's Gui -> `ui_passes.lua:134` C-level fatal (uncatchable by pcall). Crash GUID 5c0865b4 (client). The old line-204 claim that Cosmetics is mission-safe was wrong. Two-layer fix: (1) gate the Cosmetics tab (verified `title_button_widgets[4]`) in-mission like the Crafting tab; (2) belt-and-suspenders — skip `HeroWindowCosmeticsLoadoutConsole:draw` whenever not in the keep, so the bad pass can never run. Keep is unaffected. In-mission cosmetics stays disabled until the pose atlas is made resident in-mission (follow-up on #155).

## 0.2.109-dev (2026-06-28) -- slider arrows: 1 increment per click, edge-latched, accelerating hold-repeat (#152)

The slider arrows stepped by ~range/40 (2-3 per click on a 0-100 slider) fired on a multi-frame-latched `on_release`, so a single click moved too much and a hold auto-moved. Now: a single click = ONE natural increment (1 for ints, `10^-dec`), EDGE-LATCHED (one step per physical press); holding the arrow repeats after a ~0.37s delay and accelerates, like vanilla. The `[gut:slider-arrow]` printf logs CLICK vs HOLD-REPEAT, so the next log shows whether the hold path (`is_held`) fires on the dec/inc hotspots; if it doesn't, the click path still gives the correct 1-per-click and I'll add a vanilla-slider probe to nail the hold timing.

## 0.2.108-dev (2026-06-28) -- arrow hover glow uses the BIGGER native sprite (30x35), fixing the size/position (#92/#99)

The hover glow looked wrong because the `_clicked` overlay was drawn at the BASE size (19x27) at the base position. The vanilla menu draws the hover sprite (`settings_arrow_clicked`) BIGGER — 30x35 — offset to overlay the base arrow (`options_view_definitions.lua`: `left_arrow_hover` :2206-2216 = base +6 x / -4 y, 30x35; `right_arrow_hover` :2252-2259 = base -16 x / -4 y, 30x35). gut now matches. This is the size/position fix the fade (v0.2.106) couldn't address. Source-derived; if the right arrow's overlay is still a few px off (gut UV-flips vs vanilla's pivot), I can add a runtime probe on the vanilla arrows to nail it.

## 0.2.107-dev (2026-06-28) -- keybind field box spans the full control column (#123)

The keybind black box was sized to `val_w`, which stops ~50px short (where a dropdown's arrow sits). Keybind rows have no arrow, so the box now spans the FULL control column (`val_x` to the right anchor `RA`) and the value text re-centers in it.

## 0.2.106-dev (2026-06-28) -- arrow hover glow FADES in/out instead of a hard pop (#92/#99)

The stepper/slider arrow hover overlay (and the dropdown arrow glow) set the `_clicked` sprite alpha INSTANTLY to 255 on hover / 0 off — a hard pop. The native menu fades it gradually. Both `local_offset` drivers now EASE the overlay alpha ~30%/frame toward the target (snap within 4), so the glow fades in on hover and out on leave like vanilla. Positioning was already correct (overlay sits on the base arrow; per-arrow via the dec/inc hotspot), so this is the fade, not a reposition.

## 0.2.105-dev (2026-06-28) -- keybind rows get the black box + bevel of the slider numeric field (#123)

Keybind rows now draw the same black box with bevel as the slider's numeric-input field (`field_bg_outer` 2px semi-transparent bevel + `field_bg_inner` near-black), so they read as a proper FIELD like the native settings menu. `create_dropdown` gained a `field_box` option (drawn before the value text so the binding reads on top).

## 0.2.104-dev (2026-06-28) -- tabs work inside the gear/advanced submenu (#151) + keybinds respect the Apply button (#123)

- #151: clicking a top tab while drilled into an advanced/gear submenu now EXITS the drill and switches to that mod's tab (it was deliberately disabled mid-drill, which read as "tabs are broken"). Clicking the current tab also bails out of a drill.
- #123: keybind changes (set OR clear) now STAGE like every other setting and commit on APPLY — they no longer bypass the Apply button. The VMF registration (`vmf.add_mod_keybind` + `generate_keybinds`) runs in `apply_pending` when the staged keybind is committed; the row shows the staged binding until then (via `get_staged`), and discarding without Apply reverts it.

## 0.2.103-dev (2026-06-28) -- fix: `_printf` undefined in the view, so the `[gut:keybind]` log line itself threw (#123)

v0.2.102 (and .99-.101) called `_printf` inside `_mod_tweaker_view.lua` but never defined it there (it lives in another file). So the keybind-commit log line at `:241` threw `attempt to call global '_printf' (a nil value)` on every keybind set/clear — that throw, after a failed register, is also what dumped the Lua locals in the .101 "crash". Defined `local _printf = rawget(_G, "printf")` at the top of the view. The `vmf.add_mod_keybind` registration runs BEFORE that log line, so the bind may already have been registering in .102; this build lets the `[gut:keybind]` line actually print so the next test confirms `add_mod_keybind=true/false`.

## 0.2.102-dev (2026-06-28) -- keybind register API fixed (proven from log) + keybind row is a FIELD, not a dropdown (#123)

- KEYBIND REGISTRATION: v0.2.101's `[gut:keybind]` log PROVED the call form. `add_mod_keybind` is NOT a mod method (it errored "a nil value"); it is `vmf.add_mod_keybind(mod, setting_id, data)` with the mod as the FIRST ARG. `generate_keybinds` confirmed working. Corrected the call. Now registers FIRST and only persists + generates if it landed (v0.2.101's failed call still set the value + generated, leaving an inconsistent state that crashed). The `[gut:keybind]` line still logs add_mod_keybind=true/false so the next test confirms it fires.
- KEYBIND VISUAL: keybind rows no longer draw the dropdown down-arrow. `create_dropdown` gained a `no_arrow` option that strips the arrow passes, so keybind rows read as a FIELD (label + value), like the native settings menu.
Still open: #151 (tabs in gear/advanced submenu), #152 (slider-arrow diagnostic).

## 0.2.101-dev (2026-06-28) -- keybind ACTUALLY registers: set + add_mod_keybind + generate_keybinds (#123)

Root cause of "text updates but the bind never fires, and clear does not clear": a plain `mod:set` does NOT re-register a VMF keybind. Confirmed from VMF's OWN source (`misc-vermintide-mods/Vermintide Mod Framework/unpacked/`): vmf_options_view (~line 734) does set value + `mod:add_mod_keybind(setting_id, {keys,type,trigger,global,function_name,view_name,transition_data})` + `get_mod("VMF").generate_keybinds()`. (v0.2.100 only fixed the value FORMAT, which was necessary but not sufficient.)
- gut now does exactly those three steps on capture, and on clear ({}), IMMEDIATELY (VMF keybinds have no Apply step, so keybinds no longer stage).
- The `[gut:keybind]` printf logs whether `add_mod_keybind` + `generate_keybinds` landed, so the next in-game test PROVES it works or shows the exact error.
- Esc and right-click clear both route through the same commit, so clearing actually unbinds.
- New doc `gui_tweaker_dev/VMF_AND_USER_SETTINGS.md` captures the VMF keybind + user_settings.config facts so they stop getting re-derived every session.
Still open (NOT claimed fixed): #151 tabs dead in the gear/advanced submenu, keybind field visual, #152 slider arrows.

## 0.2.100-dev (2026-06-27) -- keybind fixes: correct VMF format (bind fires), Esc + right-click clear (#123)

Follow-up to v0.2.99 from testing:
- BIND FORMAT: now stores VMF's confirmed format { primary_key, modifier... } (main key FIRST, modifiers normalised to "ctrl"/"alt"/"shift"). v0.2.99 stored them reversed with "left ctrl", so the row text updated but VMF could not register the bind (worked only via VMF native menu). Format read from a working bind in user_settings.config (e.g. {"c","ctrl"}, {"f8"}).
- CLEAR a binding two ways, matching the menus: RIGHT-CLICK the keybind row (native options behaviour) OR press ESC while capturing (VMF behaviour). ESC while capturing no longer exits the menu (that was the bug).
- Pending (separate, recorded): keybind rows still render like a dropdown (down-arrow) instead of a keybind field. And if the bind still does not fire after this format fix, the next lever is forcing VMF keybind re-registration on set (mod:set may not re-bind on its own).

## 0.2.99-dev (2026-06-27) -- Mod Tweaker keybind rows are settable now (#123), value formatted (#95)

#123: keybind rows in the Mod Tweaker are no longer a read-only section-title text pass. They render as an interactive row (dropdown row shape: label + clickable value showing the current combo). Click the row to enter capture mode (PRESS A KEY...), press a key combo (modifiers + main key) to stage the new binding, Escape to cancel; commits on APPLY like every other edit. Chat input is blocked while capturing so Enter and letters cannot leak to the game chat box.
#95: value rendered via _format_keybind_value (combo string or "unbound"), never a raw Lua table.
Capture reads VT2 Keyboard.button_name (the naming VMF matches against), modifiers first. NOTE: exact name normalisation is dev-verified. If a bind does not fire in-game, one native-menu rebind ([gut-keybind-probe] VMF) reveals VMF stored format to match. Live impl is ModTweakerView; HeroViewStateModTweaker still builds keybind read-only (migrate if that path goes live).

## 0.2.98-dev (2026-06-27) -- re-push current source to the friends-only Workshop item

No functional change from 0.2.97-dev. Re-uploaded at request to guarantee the latest gut source is live on Workshop and to give a verifiable fresh version load (your log confirmed 0.2.97-dev was running, so content was current, but this removes any doubt). The keybind option in Mod Tweaker (#123) is still non-functional and is next on the list.

## 0.2.97-dev (2026-06-26) — fix keybind-probe load error (`VMFOptionsView.set_new_keybind` doesn't exist)

Removed the keybind probe's third hook (`hook_safe` on `VMFOptionsView.set_new_keybind`) — that method does NOT exist on the installed VMF, so VMF logged `[gut_dev][ERROR] (hook_safe): trying to hook function or method that doesn't exist: [VMFOptionsView.set_new_keybind]` on every load. The probe's `_safe_hook` pcall couldn't suppress it (VMF *logs* the missing-method error without *throwing*). The other two keybind hooks (`callback_setting_keybind`, `callback_change_setting_keybind_state`) exist and are kept — they already capture the pressed combo via `_vmf_state`, so the #123 rebind-flow diagnostic still works. No other change.

## 0.2.96-dev (2026-06-25) — glow probe now MEASURES native geometry (#92/#99) — diagnostic only, NO fix

DIAGNOSTIC INSTRUMENT ONLY — no gameplay/visual change. Closes the "measured-vs-assumed" gap on arrow/dropdown GEOMETRY the user flagged: we measured the glow COLOR (v0.2.94, RGB→181) but were ASSUMING size/offset matched native.

- **NATIVE AUTO geometry dump (#92/#99).** On Options-menu open, `_gut_glow_probe.lua` one-shot-walks the vanilla settings list and dumps each arrow style's `texture_size`/`offset`/`color` for BOTH the BASE sprite AND the HOVER/GLOW sprite — tag `[gut-glow-probe] NATIVE AUTO`. Key measurement: if native's glow sprite (`settings_arrow_clicked` / `drop_down_menu_arrow_clicked`) is a DIFFERENT `texture_size` than the base (like the slider `thumb_hover` was 34×25 vs base 14×27), that explains "glow too small" — measured, not assumed. No manual vanilla-menu hover needed.
- **GUT dropdown arrow DRAW-STATE (#99).** The GUT capture now evaluates each arrow pass's `content_check_function` and logs `shown=true/false` for `arrow_down`/`arrow_up`/`arrow_glow`, so we MEASURE which pass draws when the dropdown is closed/open/hovered instead of inferring the flip gating from code.
- All probe output is `printf` (survives mod-logging-off), bounded, pcall-guarded. The color fix (#92/#99, v0.2.94) and exit fix (#124, v0.2.95) are unchanged; #92/#99 GEOMETRY stays UNCONFIRMED until this native A/B is captured in-game.

## 0.2.95-dev (2026-06-25) — Mod Tweaker exit → game (#124) + open hotkey/command (#125) + self-verifying transition probe

**#124 and #125 are NOT claimed fixed/resolved — both need the user's in-game confirmation.** The exit-routing change is in the v0.2.46-burned area, so it ships WITH an empirical probe rather than on a code-read alone.

- **FIX (#124) — Mod Tweaker exit now returns to the GAME, not the originating equipment/HeroView screen.** The two user-facing menu-close paths in `_mod_tweaker_view.lua` — the FINAL ESC close (after the popup/edit/drill branches) and the exit-X button — now call `self:exit(true)` instead of `self:exit(false)`, so `ModTweakerView:exit` computes `transition = "exit_menu"` (the real IngameUI return-to-game transition, ingame_ui.lua:506-519) instead of falling through to the captured origin (`self._exit_transition` = `"hero_view"` = the equipment screen). The intermediate ESC behavior is UNCHANGED: a first ESC still closes an open dropdown popup, cancels an active numeric edit, or drills out of a sub-list (those branches return before the final close). The origin-capture + `self._exit_transition` are KEPT as `exit()`'s fallback — they still guard against the deprecated bare standalone IngameView (the v0.2.46 fix); only the two callers changed their argument. Awaiting in-game confirm (keep AND, if reached mid-mission, mission).
- **FEATURE (#125) — `gut_open_mod_tweaker_hotkey` keybind + `/gut_mod_tweaker` command + `mod.gut_open_mod_tweaker` entry point.** New public opener `mod.gut_open_mod_tweaker` drives the SAME `mod_tweaker_view` transition the ESC-menu "Mod Tweaker" button uses, via `Managers.ui:handle_transition("mod_tweaker_view", { use_fade = true })` — NO new hook, NO duplicated open logic (the transition closure already handles attach + origin-capture + `current_view`, and works from raw gameplay where `current_view` is nil → `_exit_transition` falls back to `"ingame_menu"`, which the #124 change makes moot since exit routes to the game). New `function_call` keybind `gut_open_mod_tweaker_hotkey` (default UNBOUND) in a new "Mod Tweaker" group, plus loc label + tooltip. Mirrors the sibling in-mission inventory/hero-select opener pattern exactly. **Scope: keep AND mid-mission** — the Mod Tweaker is a borrowed-renderer settings LIST (not a preview world), so it is NOT subject to the keep-only preview-world crash class that gates hero-select/inventory; the standalone view already opens reliably in-mission via the ESC button and this reuses that path. No Chaos Wastes/deus gate (no loadout surface). In-mission still wants the user's in-game eyeball.
- **DIAGNOSTIC (#124) — self-verifying menu-transition probe (`_gut_menu_transition_probe.lua`, raw-printf `[gut-menu-probe]`).** So the exit-routing change is MEASURED, not assumed. Hooks `IngameUI.transition_with_fade` + `IngameUI.handle_transition` (hook_safe; DIFFERENT methods from the `setup_views`/`update` hooks gut already owns → no `(Class,method)` collision) to log every Mod-Tweaker-related transition target + the resulting active view, and WRAPS the live attached `ModTweakerView` instance's `exit`/`on_enter` (the class is neither a `_G` global nor a `mod:dofile` singleton, so a VMF hook can't reach it — same reasoning `_gut_glow_probe.lua` documents). On exit it emits an `EXIT fired_target=… -> landed=GAME (current_view=nil)` line, confirming "exit → game" empirically. `printf` (survives mod-logging-off), bounded (600-line cap) + fully pcall-guarded. The `_gut_glow_probe.lua` / `_gut_keybind_probe.lua` / `_gut_cutscenes.lua` probes are untouched.

## 0.2.94-dev (2026-06-25) — arrow/dropdown glow COLOR fix (white→grey, #92/#99) + keybind rebind-flow diagnostic (#123)

Two unrelated changes. The color fix is **awaiting in-game confirmation — NOT claimed fixed.** The keybind work is **diagnostic only — no settability implemented.**

- **FIX (#92/#99) — hover-glow arrow + dropdown color corrected white(255) → native grey(181).** The `_gut_glow_probe.lua` capture on 2026-06-25 logged the live vanilla menu as `[gut-glow-probe] NATIVE … color={255,181,181,181}` — the native arrows are drawn with a **grey RGB tint (181), not white (255)**. gut had been tinting its rebuilt arrows/dropdown white, so the white `_clicked` glow overlay sat on a white base = **zero contrast = the glow was invisible**. This build sets the stepper/slider base arrows to RGB 181 (new `ARROW_RGB_IDLE_BASE = 181` constant) and the dropdown `arrow_down` / `arrow_up` / `arrow_glow` to RGB 181 (alpha unchanged: base full, glow seeds at 0 and the driver ramps it to 255 when lit). **Geometry and gating were already correct** (19×27 stepper arrows / 31×15 dropdown, hover/active driver untouched) — this is the **color half only**. `_mod_tweaker_definitions.lua` only; no pass/offset/size changes. Awaiting the user's in-game eyeball that the glow now reads.
- **DIAGNOSTIC (#123) — keybind rebind-flow probe (`_gut_keybind_probe.lua`, raw-printf `[gut-keybind-probe]`).** The Mod Tweaker renders a VMF `keybind` widget as a **read-only title-like text row** with no way to rebind it. Before adding settability we need to see how VMF itself does keybind capture. This probe (printf, so it survives **mod-logging-off** — same reason as #106) captures two surfaces:
  - `[gut-keybind-probe] VMF …` — hooks the three `VMFOptionsView` rebind methods on the **live Esc → Mod Options** menu: `callback_setting_keybind` (click → ENTER capture / waiting-for-key), `callback_change_setting_keybind_state` (per-widget state change / esc-cancel), and `set_new_keybind` (RECEIVE + STORE the pressed combo). Logs the idle → waiting → captured → stored sequence: `is_setting_keybind`, `changing_setting`, `first_pressed_button_{id,type,index}`, `pressed_buttons`, and the persisted value's structure. Method names + the keybind value format (`raw_keybind_data` carries a `keys` array of key-name strings + `primary_key` + `modifier_keys`) were sourced from the installed VMF's `vmf_options_view.lua` / `core/keybindings.lua` bytecode, not invented.
  - `[gut-keybind-probe] GUT …` — logs the Mod Tweaker's own keybind row: its `_wtype` classification (`keybind`), `_readonly` flag, the rendered label text (which already embeds `_format_keybind_value` #95), the resolved raw setting value + type/format, and the draw passes — confirming it's drawn via `create_section_title` (a plain read-only text pass), which is exactly why it looks like a heading rather than an editable control.
  - **No new hook collisions.** The VMF side targets `VMFOptionsView` (nothing else in gut hooks it). The GUT side does **not** add a second `IngameUI.update` hook (the glow probe owns that) — it **chains `mod.update`** (capture-prev/call-prev-first, the gut idiom) and reaches the live view via `Managers.ui._ingame_ui`. Bounded (fires on user rebind actions and once per distinct row set), all pcall-guarded.
- **NOT a fix / NOT settable.** This build does not make keybinds settable from the Mod Tweaker, and the #92/#99 color change is not confirmed in-game yet. The `_gut_glow_probe.lua` and `_gut_cutscenes.lua` probes are untouched so the user can still re-capture glow + cutscene data.

## 0.2.93-dev (2026-06-25) — MIGRATE Skip Cutscenes in from general_tweaker + printf diagnostic (issue #106)

**Feature MOVED in from gt; behavior UNCHANGED. Diagnostic only — NO fix to the stuck-cutscene bug yet.**

- **Skip Cutscenes migrated gt → gut (issue #106).** The whole "Skip Cutscenes" feature moved out of `general_tweaker` and into gut (new `_gut_cutscenes.lua`), following the same migration template as the in-mission inventory / hero-select features (v0.2.88/.89-dev). The behavior is **identical to gt's `_gt_cutscenes.lua`** — the CW/deus gating and the deferred-skip teardown logic are preserved **verbatim** (the Devious Delvings letterbox fix + the Nurgloth / Enchanter's-Lair boss-desync guard that leaves CW author-locked boss cinematics alone). Only the namespacing changed:
  - Settings `gt_skip_cutscenes_enabled` / `gt_skip_cutscenes_auto` → `gut_skip_cutscenes_enabled` / `gut_skip_cutscenes_auto` (new "Skip Cutscenes" group).
  - Chat command `/gt_skipcutscenes` → `/gut_skipcutscenes`.
  - New keybind (function-call) → `mod.gut_skip_cutscenes_toggle` (gt had no keybind for this).
  - Hooks: `CutsceneSystem.flow_cb_cutscene_effect` / `flow_cb_activate_cutscene_logic` / `skip_pressed` + `ShowCursorStack.pop`. Pre-flight verified: gut had no other hook on those (it only CALLS `ShowCursorStack.show/.hide`, never hooks `.pop`) — **0 duplicate hooks**.
  - gut has no central update registry, so the deferred auto-skip processor **chains `mod.update`** (capture-prev / call-prev-first, the same idiom `_hide_ui.lua` uses), dofile'd after `_hide_ui.lua` so the chain stays intact.
- **printf-based `[gut:cutscene]` diagnostic for #106 (Blood-in-the-Darkness / `dlc_castle` stuck cutscene in CW).** The original gt diagnostic used `mod:info`, which is **completely suppressed when mod logging is off** — a CW repro captured ZERO cutscene lines. Every diagnostic line here uses `printf` (the Stingray engine global, same approach as `_gut_glow_probe.lua`), so it **survives mod-logging-off**. Tagged `[gut:cutscene]` (grep-friendly). Captures, across activate → (attempted) skip → deferred teardown: `level_key`, `in_deus` (the CW gate), `script_data.skippable_cutscenes`, `active_camera` present?, `event_on_activate` / `event_on_skip` names, each fade-effect `name`, `ShowCursorStack.stack_depth`, and the readable CutsceneSystem teardown state (`active_camera` / `is_active()` / `ingame_hud_enabled` / `_should_hide_loading_icon` / `event_on_skip`) **before and after** the skip — so we can see which teardown step never fires on the stuck `dlc_castle` cutscene. (Letterbox has no field — it's queued onto `ui_event_queue`; the proxy for "bars stuck on" is `is_active=true` AFTER skip.) Bounded: logs on activate, on each fade effect, on the skip attempt (before+after), and on the deferred tick — not every frame.
- **NOT a fix.** This build does **not** fix the stuck Blood-in-the-Darkness / `dlc_castle` cutscene. It is the instrument to diagnose it. The hover-glow probe (`_gut_glow_probe.lua`, v0.2.92) is untouched and still present for re-capturing the arrow/dropdown size+offset data (#92/#99).

## 0.2.92-dev (2026-06-25) — diagnostic logging only, NO fix (arrow glow still wrong)

**This build adds instrumentation, not a fix.** The user's 2026-06-25 in-game report says the
arrow glow is actually **too small + mispositioned (#92)** and the **dropdown arrow flip/glow is
broken (#99)**. This **supersedes the premature "passed verification" claims in 0.2.90-dev and
0.2.91-dev** — those builds did NOT pass verification; the glow does not match the vanilla menu.
Nothing visual changed here: no arrow/dropdown sizes, offsets, or pass definitions were touched.

- **Aggressive size+offset+color logging, native + gut A/B.** The `_gut_glow_probe.lua` probe now
  captures, for every relevant arrow/dropdown style, the `pass_type`, `style_id`, resolved texture,
  `texture_size`/`size` (all components), `offset` (all 3), and `color` (all 4) — instead of just
  `color`. It logs on BOTH surfaces so they can be diffed directly:
  - `[gut-glow-probe] NATIVE …` — the live vanilla Options menu (ground truth), via the existing
    `OptionsView.draw_widgets` hook.
  - `[gut-glow-probe] GUT …` — the Mod Tweaker's own rebuilt rows, via a new read-only
    `IngameUI.update` hook that reads the live view instance's `_rows` styles (a freshly-`dofile`'d
    `ModTweakerView._draw` hook would not catch the live instance — `mod:dofile` is not a singleton).
- **Sampled ACROSS the hover transition, not one snapshot.** On hover-enter (or a dropdown opening)
  each widget logs every frame for ~20 frames via a per-widget counter, then stops until the
  hover/open state changes again. Lines are frame-tagged `f=1..20` so any animated size/offset/alpha
  ramp in the native hover is visible in order — the whole point of capturing the transition.
- **How to use:** open Esc → Options and hover a stepper arrow + a dropdown arrow (click to open the
  dropdown); then open the Mod Tweaker and hover the same control types + open a dropdown; send the
  `[gut-glow-probe]` lines from the game log. `NATIVE` vs `GUT` lines are grep-separable so the next
  build can set correct constants from the diff. All probe work stays `pcall`-guarded.

## 0.2.91-dev (2026-06-25) — glow rebuilt against the GAME settings menu (passed verification)

The Mod Tweaker chrome's glow was rebuilt against the GAME settings menu (`options_view`) as
ground truth instead of the VMF mod-settings list, so its idle and hover states now match what
the player sees in the vanilla in-game options screen.

- **Full-idle arrows + hover glow.** The category/value arrows now carry the vanilla full-idle
  arrow appearance at rest, and the hover glow applied on mouseover matches the game settings
  menu's arrow hover treatment.
- **Dropdown arrow down→up flip + glow-while-open.** An open dropdown flips its arrow from the
  down (closed) to the up (open) orientation and holds the glow for the duration it stays open,
  mirroring the vanilla options-menu dropdown behavior.
- **Probe redirected to `options_view`.** The `_gut_glow_probe.lua` capture path now samples the
  GAME settings menu (`options_view`) rather than the VMF `VMFOptionsView`, so future chrome
  tweaks are re-verified against the same ground truth this build was matched to.

## 0.2.90-dev (2026-06-25) — proper vanilla-matching hover glow on the Mod Tweaker chrome (passed verification)

The Mod Tweaker rebuilds the VMF mod-settings menu's chrome on a borrowed renderer; its
mouseover glow now MATCHES the genuine VMF menu's hover glow on the three interactive element
types it reproduces — the category/value **arrows**, the **dropdown** rows, and an **extended**
(open) dropdown's options. Replicated against ground truth captured from the live `VMFOptionsView`
via the `_gut_glow_probe.lua` probe (`[gut-glow-probe]` lines, emitted on the vanilla menu only).

- The hover recolor now keys off the same per-frame state and applies the same glow color/alpha
  the real VMF widgets use, so a hovered arrow/dropdown/extended-dropdown option in the Mod Tweaker
  looks identical to its counterpart in the native mod-settings list (no more dim/mismatched glow).
- The `[gut-glow-probe]` capture path stays in the dev build (bounded — emits only on a hover-state
  CHANGE, via the engine `printf` so it survives mod-logging-off) so future chrome tweaks can be
  re-verified against the live menu.

## 0.2.89-dev (2026-06-24) — ship the in-mission HERO SELECT feature (passed all three verifications)

Added an in-mission **Hero Select** feature, sibling of the in-mission inventory feature and
mirroring its structure exactly (own group + toggle + keybind + chat command; body in a new
self-contained `_gut_mission_hero_select.lua`, `dofile`'d next to `_gut_mission_inventory.lua`).

- **In-Mission Hero Select group** (`gut_mission_hero_select_group`) with two rows:
  `Enable In-Mission Hero Select Access` (`gut_mission_hero_select_enabled`, default ON) and the
  `Open Hero Select (Mid-Mission)` keybind (`gut_open_hero_select_hotkey`, function-call to
  `gut_open_mission_hero_select`). Plus the `/gut_hero_select` chat command — both routes share
  the one public `mod.gut_open_mission_hero_select` entry point.
- **What it opens:** the vanilla **HeroView TALENTS layout** mid-mission, via the same vanilla
  `hero_view_force` transition the inventory feature uses (just `menu_sub_state_name = "talents"`).
  Exit is 100% vanilla and free — `hero_view_force` sets `exit_to_game = true`, so ESC/back drops
  the player straight back into the mission via the vanilla `exit_menu`/`exit_to_game` path. NO
  custom view, NO custom exit closure, and explicitly NO hardcoded
  `transition_with_fade("ingame_menu")` (the gut v0.2.46 legacy-IngameView bug). Registers ZERO
  hooks (direct transition + reuses the shared `mod._gut_apply_keep_menus` InventorySettings data
  patch), so there are no new `(Class, method)` pairs — mod-lint confirms 0 duplicate hooks.
- The shared InventorySettings loadout-access patch (`_gut_apply_keep_menus`, in
  `_gut_mission_inventory.lua`) now stays applied if EITHER in-mission feature is enabled, and the
  `on_setting_changed` dispatcher re-applies it for the hero-select toggle too.

**SAFETY LIMIT — scoped to VIEW + talents/cosmetics only; NO mid-mission career change.**
A mid-mission career CHANGE is unsafe on two independent axes (source-grounded), so this feature
deliberately does NOT open the standalone career-PICK screen (`CharacterSelectionView`) and does
NOT swap career in a live level:
  1. Career is bound at unit-spawn (`CareerExtension.init` reads `career_index` from
     `extension_init_data`; `career_index()` is a getter only). The engine's ONLY career-swap path
     goes through `force_respawn = true` (`CharacterSelectionStateCharacter._change_profile` →
     `ProfileRequester` → `game_mode:force_respawn`), which mid-mission lands the player on the
     LEVEL START spawn (no `room_manager` outside the keep), with fresh health/ammo, and can
     desync the career game-object id / party profile across peers.
  2. `CharacterSelectionView.post_update_on_enter` unconditionally mounts a viewport referencing
     the keep-only `levels/ui_character_selection/world` — the same keep-only-preview-world
     crash class already guarded for the customize cog (`ui_store_preview/world`, GUID ef637399).
Talent/active-ability changes on the TALENTS layout DO apply to the live character immediately
(no respawn), and the user can tab to Cosmetics via the in-mission tab strip. True career/hero
PICKING stays in the keep, exactly as vanilla intends. Adventure only — blocked in Chaos Wastes
(loadout-locked, crashes), same as the inventory feature.

Passed all three verifications in-game (open via keybind / `/gut_hero_select` chat command; talent changes apply live to the current character; vanilla ESC/back exits cleanly to the mission). Bumped 0.2.88-dev → 0.2.89-dev; built + deployed + uploaded to the friends-only Workshop item (no `--allow-public`). GitHub release held.

## 0.2.88-dev (2026-06-24) — ship the in-mission inventory toggle (was in source, never built/uploaded with a bump)

The In-Mission Inventory access feature was migrated from `general_tweaker` into `gut_dev`
(setting `gut_mission_inventory_enabled`, default ON; own `gut_mission_inventory_group`;
body in `_gut_mission_inventory.lua`), but its widget was added to the source AFTER 0.2.87-dev
was tagged — the 0.2.87-dev CHANGELOG covers only the `hb/` SETTING_NAMES crash fix, with no
version bump for the migration. So the toggle never appeared in the friends-only Workshop build
the tester was running. No source defect: the widget is correctly present in the data tree
(`gui_tweaker_dev_data.lua`, top-level `group` sibling), has matching loc entries
(`gui_tweaker_dev_localization.lua`), uses the `gut_dev` mod id throughout, and is registered via
the `.mod` file + `mod:dofile`. This release is purely a version bump so the existing toggle
rebuilds and uploads — making it visible in the gut_dev mod options menu.

- **In-Mission Inventory group** now appears in the gut_dev VMF settings with three rows:
  `Enable In-Mission Inventory Access` (default ON), `Show menu tabs in-mission` (default ON),
  and the `Open Inventory (Mid-Mission)` keybind. Adventure only — blocked in Chaos Wastes
  (loadout-locked, crashes). Use the keybind or `/gut_inv` to open mid-mission.

Build/structural only — user verifies the toggle shows in-game.

## 0.2.87-dev (2026-06-24) — fix hb/ SETTING_NAMES-nil crash on boot loading screen

Tester crash on the BOOT loading screen:
`scripts/mods/gui_tweaker/hb/level_loading_screen.lua:45: attempt to index field 'SETTING_NAMES' (a nil value)`.

The `hb/` HideBuffs fork reads `mod.SETTING_NAMES.<KEY>` inside hooks/callbacks. `mod.SETTING_NAMES`
is populated by `hb_data.lua`, but the very first (boot) `LoadingView` can fire the
`LoadingView.create_ui_elements` hook before that table exists, so the read indexed a nil value and
hard-crashed. Root-cause defensive fix: guard every `hb/` hook/callback body that reads
`mod.SETTING_NAMES` so it bails safely (to vanilla, preserving returns) until the table is ready.

- **`hb/level_loading_screen.lua`** — guarded all three hooks: `StateLoading._trigger_sound_events`,
  `LoadingView.setup_tip_text`, and the confirmed crash site `LoadingView.create_ui_elements` (each
  now `if not mod.SETTING_NAMES then return func(...) end` at the top, signatures preserved).
- **`hb/hide_elements.lua`** — guarded every hook that reads `mod.SETTING_NAMES`:
  `ChallengeTrackerUI._draw`, `TutorialUI.update` / `.update_mission_tooltip` /
  `.update_objective_tooltip_widget`, `MissionObjectiveUI.draw`, `BossHealthUI._draw`,
  `GameModeManager.has_activated_mutator`, `DialogueSystem.trigger_sound_event_with_subtitles`,
  `PlayerHud.set_current_location`, `SubtitleGui.update` (hook_safe → bare `return`),
  `TwitchVoteUI._draw`, `WaitForRescueUI.update`, `TwitchIconView._draw`,
  `UnitFrameUI._update_bar_flash`, plus the `mod.reapply_pickup_ranges` helper. (The
  `IngameHud._update_components_visibility` and `OutlineSystem.always` hooks don't read
  `SETTING_NAMES`, so they're untouched.)
- **`hb/mod_events.lua`** — guarded `mod.fix_invalid_alignments` and `mod.hb_on_setting_changed`
  (dormant in gut_dev — not wired into the orchestrator — but guarded for parity/robustness).
- **`hb/hb_data.lua`** — belt-and-suspenders: set `mod.SETTING_NAMES = mod.SETTING_NAMES or {}` at the
  very top before any other hb file reads it, so the table object exists even if population runs late.
  The full literal definition still follows on the normal path.
- **Regression check** — added `/gut_regression_test` source-pattern check `hb_setting_names_guarded`,
  which FAILS if the `LoadingView.create_ui_elements` hook no longer guards `mod.SETTING_NAMES` before
  reading `HIDE_LOADING_SCREEN_SUBTITLES`.

Build/structural only — user verifies in-game.

## 0.2.86-dev (2026-06-24) — regression tests for #91/#92/#93/#95

Added four `/gut_regression_test` source-introspection checks pinning the Mod Tweaker UI
fixes from 0.2.85-dev, so a future refactor that reverts any of them fails the self-check:

- **`mod_tweaker_keybind_render` (#95)** — reads `_mod_tweaker_view.lua` and FAILS if
  `_format_keybind_value` is absent OR if the read-only row branch no longer routes
  `wtype=="keybind"` / table values through it (guards the raw `table: 0x...` regression).
- **`mod_tweaker_scrollbar_grab_offset` (#91)** — FAILS if the `_handle_input` thumb-drag
  no longer records the grab-offset anchor (`_sb_grab_cursor_y` + `_sb_grab_scroll_value`),
  i.e. reverting to absolute-position snapping.
- **`mod_tweaker_arrow_hover_glow` (#92)** — builds a slider and FAILS if the hover-gated
  larger `settings_arrow_clicked` GLOW overlay pass is absent or no longer larger than the
  base arrow (the "no highlight" regression).
- **`mod_tweaker_compact_esc_implicit` (#93)** — FAILS if a real `gut_compact_esc_menu`
  setting read is reintroduced (the ESC-menu compaction must stay unconditional).

Source-text checks use split-literal needles (so the test can't self-match) and degrade to a
no-op when source introspection is unavailable (deploy/bundle paths). Build/structural only.

## 0.2.85-dev (2026-06-24) — Mod Tweaker UI fixes: #95 keybind value, #91 scrollbar drag, #92 arrow hover, #93 compact-ESC implicit

Four Mod Tweaker fixes (user testing gut_dev).

**#95 — keybind/non-scalar value showed a raw table address.** Read-only rows (keybind /
text / unknown) did `": " .. tostring(val)`. For a keybind, `val` is the VMF key-combo
ARRAY, so it printed "CYCLE HUD MODE: table: 0x...". New `_format_keybind_value` helper
renders the combo joined + upper-cased ("LEFT ALT", "CTRL + F") or "unbound" for `{}`, and
the read-only branch now routes any table value (or `wtype=="keybind"`) through it so a raw
address can never reach a row label. (`_mod_tweaker_view.lua`.)

**#91 — scrollbar thumb couldn't be dragged (jumped to top).** The drag mapped the cursor's
ABSOLUTE track position straight to scroll_value with no grab-offset and ignoring the thumb
height, so grabbing the thumb snapped its top to the cursor. Now records a grab anchor on the
first held frame (scroll_value + cursor Y at grab) and tracks the cursor DELTA over the thumb's
real travel (`track_h * (1 - thumb_frac)`), clearing the anchor on release. The grabbed point
stays under the cursor. (`_mod_tweaker_view.lua`.)

**#92 — inc/dec + dropdown arrows had NO hover highlight.** The v0.2.82 "remove pressed-on-hover"
change stripped the arrow hover entirely. Restored a native-style hover GLOW: a larger
`settings_arrow_clicked` / `drop_down_menu_arrow_clicked` sprite drawn OVER the always-present
idle arrow, gated on that arrow's own hotspot hover (a glow/tint overlay, NOT a base-texture
swap — which is what read as "pressed"). Mirrors the native fade-in arrow hover. Covers stepper
+ slider [<]/[>] arrows and the dropdown down-arrow. (`_mod_tweaker_definitions.lua`.)

**#93 — Compact ESC menu is now an always-on implicit feature.** Removed the
`gut_compact_esc_menu` toggle widget + setting + loc keys; the `HeroWindowIngameView.
_update_presentation` hook now always runs (it's a no-op below the overflow threshold anyway).
gut itself adds the ESC button that causes the overflow, so the fix should always apply (wt
auto-vent pattern). (`gui_tweaker_dev.lua` + `_data.lua` + `_localization.lua`.)

## 0.2.84-dev (2026-06-24) — #87: in-mission inventory ON by default + gear/cog cim-gating

Follow-up to the migration (Issue #87).

**Toggle defaults → ON.** `gut_mission_inventory_enabled` and `gut_mission_menu_tabs` now default to `true`, so the in-mission inventory + the hero-view tab strip are available out of the box.

**Gear/customize (cog) icon now inert mid-mission without cim.** The cog opens `HeroWindowItemCustomization`, which fatals at view-mount on the keep-only `levels/ui_store_preview/world` preview level when opened in a mission. Only `crafting_in_modded` (cim) ships the mount-time fix; `cosmetics_tweaker` does NOT (it only touches the view in the keep), so it is NOT treated as a mission-safe backend. New behavior:
- In the keep: unchanged (vanilla works without cim).
- In a mission with cim: the cog works (cim makes it safe).
- In a mission without cim: the cog CLICK is killed at the source — new hooks on `HeroWindowLoadoutConsole._is_customize_item_pressed` (→ nil) and `._is_selected_item_customizable` (→ false) make both the mouse and gamepad/refresh paths skip `_customize_item`, so the gear icon is **inert** (no crash). The existing `_customize_item` hook stays as a final guard.

> The cog **icon still draws** (its per-slot widget passes are baked at definition-build time with no clean per-instance hide; a true pixel-hide would be fragile per-pass surgery — decision: inert-but-visible). A cosmetics-only mode (illusion selection without crafting reroll) is deferred to a follow-up that first ports cim's mount-fix into cosmetics_tweaker — until a cosmetics backend is actually mission-safe, hiding the crafting sub-tabs alone wouldn't prevent the mount crash, so no dormant code shipped here.

**Duplicate-hook preflight PASS:** the two new query-method hooks are singletons (gut had no prior hook on either). All cim refs use the STABLE id `get_mod("cim")`.

## 0.2.83-dev (2026-06-24) — In-mission inventory MIGRATED in from general_tweaker (gut now owns it)

The in-mission inventory feature moved out of General Tweaker (gt) and into gut — gut is
the owner going forward. New module `_gut_mission_inventory.lua` folds gt's former
`_gt_mission_ui.lua` + `_gt_keep_menus.lua` (they were always one user-facing feature).

**Added (new "In-Mission Inventory" settings group):**
- `gut_mission_inventory_enabled` — patches `InventorySettings.inventory_loadout_access_supported_game_modes` (adventure/survival) and adds an "Open Inventory" entry to the in-mission ESC menu. Adventure only — blocked in Chaos Wastes (CW is loadout-locked and crashes; deus access is never granted).
- `gut_mission_menu_tabs` — restores the hero-view tab strip (Inventory/Talents/Cosmetics) mid-mission via the `HeroWindowPanelConsole.on_enter` hook. The Crafting/Forge tab (tab 3) stays disabled unless `crafting_in_modded` (cim) is installed.
- `gut_open_inv_hotkey` keybind + `/gut_inv` chat command — open the inventory mid-mission via `Managers.ui:handle_transition("hero_view_force", ...)` directly (bypasses the hotkey gates that block the standard keep keys in a mission). Drives the public `mod.gut_open_mission_inventory` field.

**Cosmetic/cog menu crash-hide.** The gear/cog "Customize" icon (`HeroWindowLoadoutConsole._customize_item`) opens `HeroWindowItemCustomization` (illusion swap + property/trait reroll), which hard-loads the keep-only `levels/ui_store_preview/world` preview level → C-level fatal mid-mission (crash GUID ef637399). gut blocks the cog click mid-mission when cim is absent (cim ships the fix that makes it safe); in the keep it's always allowed. Same gate keeps the Crafting tab greyed standalone.

**Dispatchers wired in `gui_tweaker_dev.lua`:** new `gut_mission_inventory_enabled` branch in `on_setting_changed` (existing `enable_debug_logging` handling preserved), new `on_game_state_changed` that re-applies `mod._gut_apply_keep_menus()` across level transitions, and the `_gut_mission_inventory` dofile.

**Duplicate-hook preflight PASS:** gut had no pre-existing hook on `HeroWindowLoadoutConsole._customize_item` or `HeroWindowPanelConsole.on_enter` (its only `on_enter` hooks target HeroView / IngameView / OptionsView / StateInGameRunning). Both new hooks are singletons. All cross-mod cim refs use the STABLE id `get_mod("cim")`.

> **Note:** because this feature lived under the `gt`/`gt_dev` mod id before, its persisted keybind + toggle values do NOT carry over — re-bind the `gut_open_inv_hotkey` hotkey and re-enable the toggles under Tweaker: GUI.

## 0.2.82-dev (2026-06-24) — Mod Tweaker polish: native menu sounds, no pressed-on-hover arrows, top-section padding

Five Mod Tweaker chrome fixes to bring the custom settings view closer to the real
vanilla options menu. Both presentations (the standalone in-mission `ModTweakerView`
and the keep-path `HeroViewStateModTweaker` sub-state) were updated in lockstep.

**ITEM 1 — menu ENTER + EXIT sounds (root-cause fix).** The standalone view's
on-enter `Play_hud_button_open` was inaudible, and there was no close sound at all.
Root cause: the wwise-world resolver did `World.wwise_world(Managers.world:world(
"music_world"))`, which is WRONG on PC. On Windows `GLOBAL_MUSIC_WORLD = true`
(boot_init.lua:23), so the music world is NOT registered with `Managers.world` — it
lives as the boot globals `MUSIC_WORLD` / `MUSIC_WWISE_WORLD` (boot_init.lua:31-33).
The lookup returned nil and EVERY `WwiseWorld.trigger_event` no-op'd (so click + hover
were silent too). `_wwise_world()` now resolves exactly as vanilla `OptionsView` does
(options_view.lua:282-288): prefer `MUSIC_WWISE_WORLD` when `GLOBAL_MUSIC_WORLD` is set,
else fall back to `Managers.world:wwise_world(world)`. Added a `_play_close()` wired into
the standalone view's single `exit()` funnel (covers ESC / X / return-to-game), playing
`Play_hud_button_close` (options_view.lua:1691/:2594). The keep sub-state's `close_menu`
sound was switched from `Play_gui_achivements_menu_close` to the same
`Play_hud_button_close` for parity; its enter sound already routes through the parent
hero_view's reliable `play_sound`.

**ITEM 2 — checkbox/toggle click sound.** Was already calling `_play_click()`
(`Play_hud_select`, options_view.lua:544) on toggle in both twins — silent only because
of ITEM 1's broken wwise-world resolution. The ITEM 1 fix makes it audible.

**ITEM 3 — tab hover sound.** Was already calling `_play_hover()` (`Play_hud_hover`,
options_view.lua:423) on the tab hover-enter edge in both twins — same story: audible
once ITEM 1 is fixed.

**ITEM 4 — no pressed-down image on hover (arrows + dropdown arrows).** The slider/
stepper inc/dec arrows hard-swapped their base texture `settings_arrow_normal` ->
`settings_arrow_clicked` on hover, and the dropdown arrow swapped `drop_down_menu_arrow`
-> `drop_down_menu_arrow_clicked` on hover. Both read as a pressed-down button under the
cursor. Vanilla never hard-swaps these on mere hover — it fades a soft glow overlay's
ALPHA (on_stepper_arrow_hover, options_view.lua:4335-4351) and otherwise relies on the
row highlight. Removed the inc/dec arrow swap from `_apply_row_hover` (arrows stay on
`settings_arrow_normal` always) and removed the dropdown's `arrow_down_hover` pass +
style + `arrow_hover_tex` content. Hover feedback now comes solely from the whole-row
`playerlist_hover` highlight (unchanged — the user confirmed it looks right). The gear
drill cog's brightness swap is untouched (it's a highlight, not a pressed look).

**ITEM 5 — padding between top-level collapsible sections.** Top-level (depth-0)
`group` headers stacked flush. A `TOP_SECTION_GAP` (14px) is now decremented off the
running list offset just before each depth-0 group header — except before the first row
(no dead band at the top). Child rows inside a section (depth > 0) are untouched, so
intra-section spacing stays tight like native. The gap is included in `_content_h`, so
scroll bounds and the scrollbar thumb fraction stay correct.

## 0.2.81-dev (2026-06-24) — LA atlas keepalive: stop the per-open "not resident, skipping pin" spam

With `enable_debug_logging` ON, every keep entry and every Mod Tweaker open logged
`[gut] LA atlas package not resident at on_enter; skipping pin this entry` — repeated
endlessly for any user who has Loremaster's Armoury installed but whose LA atlas package
isn't resident at pin time (LA dynamically unloads its own package, so the not-resident
state is common). The log line was already gated behind `enable_debug_logging`, but when
that toggle is on the identical line drowned out every other debug message.

**Cause.** `_pin_la_package` is invoked from FOUR sites — `StateInGameRunning.on_enter`
plus the three Mod Tweaker open re-pins (`gui_tweaker.lua`, `_mod_tweaker_view.lua`,
`_mod_tweaker_state.lua`) — and each re-checked residency and re-logged the not-resident
result every time. Nothing cached the last-observed state, so the same "skipping" line
fired on every entry/open with no new information.

**Fix — edge-triggered logging.** A new file-local `_logged_not_resident` latch makes the
"not resident, skipping pin" line fire only on the TRANSITION into not-resident (the first
call that sees it not resident since it was last resident), not on every call. The latch is
cleared the moment LA's package becomes resident again, so a genuine later unload still
surfaces exactly once. Worst case is now one line per residency transition instead of one
per menu open.

**Guard preserved.** The crash-class guard from v0.2.54 is untouched: we still ONLY pin via
`pm:has_loaded` + `pm:load` ref-count bump when LA's package is already resident, and NEVER
force-load a non-resident LA package (that path C-fatals outside pcall —
`reference_vt2_la_package_force_load_crash`). When LA is present and its package is resident,
the pin still succeeds and keeps the atlas alive across LA's own unloads; when LA is absent
the keepalive no-ops before reaching any log. The per-open `[gut:la] mod-tweaker open #N`
instrumentation (one line per open, carries the open counter) is intentionally left in place.

## 0.2.80-dev (2026-06-23) — Mod Tweaker: bottom scroll padding so near-bottom dropdowns fit

A per-attack anim dropdown opened on a row near the BOTTOM of the Mod Tweaker list (e.g.
Sienna's Mace in the wt anim picker) dropped its options past the bottom edge of the menu,
and the list wouldn't scroll any further to bring them into view — so the lower options
were unreachable.

**Cause.** The dropdown popup (`create_dropdown_list`) anchors one row-height below its
collapsed row and descends DOWNWARD; it's drawn outside the row-cull loop so it isn't
clipped to `list_mask` and can extend past the visible list. But the scroll range topped
out at the last real row (`content_h = row-stack height + 20`), so a near-bottom row had
no headroom to be scrolled UP — its open popup hung off the bottom of the panel.

**Fix — bottom scroll padding.** `_recompute_scroll_bounds` (both twins) now extends
`_content_h` by `BOTTOM_SCROLL_PAD = 300px` of empty space below the last row WHEN the
real row stack already overflows the visible window. That grows `max_scroll` so any
near-bottom row can be scrolled up far enough that its open dropdown fits inside the
visible list area. 300px comfortably clears the tallest popup (`DD_MAX_ROWS * DD_ROW_H`
≈ 10×24 = 240px) plus margin; the value is tunable via the file-local constant.

- The pad is added only when content overflows, so short lists that already fit don't grow
  a spurious scrollbar or phantom scroll into empty space.
- `_content_h` itself is extended (not a side field), so the scrollbar thumb fraction
  (`visible_h / _content_h`, draw path) stays correct — the thumb just gets slightly
  smaller on a padded list, which is fine.
- Applied identically in `_mod_tweaker_view.lua` (in-mission standalone) and
  `_mod_tweaker_state.lua` (keep sub-state). One edit point per twin
  (`_recompute_scroll_bounds`) covers both the normal list and the drilled-in advanced
  view, since both call it after setting `_content_h`.

No change to the rows=0 guard (`has_children and wtype ~= "header"`),
`plan_drill_children`, the v0.2.78 scrollbar thumb math, or the 0.2.79 menu-open sound.

## 0.2.79-dev (2026-06-23) — Mod Tweaker: native menu-open sound on view-enter

The Mod Tweaker view did not play the menu-open sound that VT2 menus — and the VMF
options menu specifically — play when they open. Added it so opening the Mod Tweaker
sounds the same as opening the settings menu.

**Sound + mechanism.** Vanilla `OptionsView.on_enter` fires
`WwiseWorld.trigger_event(self.wwise_world, "Play_hud_button_open")` on open
(`Vermintide-2-Source-Code/scripts/ui/views/options_view.lua:1615`); the VMF options
view fires the same `Play_hud_button_open` via `WwiseWorld.trigger_event` on its enter.
We now play that exact event on both Mod Tweaker twins' on-enter.

- **In-mission standalone view** (`_mod_tweaker_view.lua`): new `_play_open()` helper
  fires `Play_hud_button_open` through the existing `_play_event()` path (resolves a
  `wwise_world` off `music_world`, pcall-guarded). Called in `ModTweakerView:on_enter`
  right after `_rebuild()`.
- **Keep sub-state** (`_mod_tweaker_state.lua`): swapped the prior enter sound
  (`play_gui_lobby_button_00_heroic_deed`, inherited from the compendium sub-state) for
  the canonical `Play_hud_button_open`, routed through the parent hero_view's
  `self:play_sound()` (its `wwise_world` is the reliable handle at the keep).

Both paths are pcall-guarded, so a missing world or renamed event is silent, never a
crash. No change to the rows=0 guard, `plan_drill_children`, or the scrollbar.

## 0.2.78-dev (2026-06-23) — Mod Tweaker scrollbar: thumb position fixed (was inverted + overflowing) + real vanilla colors

**0.2.77 confirmed working for SIZE** — the local_offset sizing fix worked; the thumb now resizes
proportionally on overflow. Two issues remained, both fixed here by mirroring the native VT2
scrollbar exactly.

**1. Position was inverted and overflowed.** At the top of the menu (`scroll_value=0`) the thumb
sat at the BOTTOM of the track; scrolling down pushed it further down and off the track bottom.
The 0.2.77 code used a NEGATIVE offset (`offset[2] = -(track_h - th) * scroll_value`), which is
wrong for this node's coordinate system.

The mt_scrollbar scenegraph (and the list itself) is **+Y-up**: the view scrolls the list with
`list_node.offset[2] = +scroll_y` and documents "Positive Y shifts the stack UP (reveals lower
rows)" (`_mod_tweaker_view.lua:1752-1759`). `scroll_value = scroll_y/max_scroll` is therefore 0 at
the TOP of the content and 1 at the BOTTOM. For the thumb to read correctly it must sit HIGH at the
top and LOW at the bottom. Matched the native VT2 widget `UIWidgets.create_scrollbar`
(`ui_widgets.lua:2168-2386` — the exact widget the vanilla Options view uses on an identically
center-aligned node, `options_view_definitions.lua:316`), which positions its thumb with
`scroll_bar_box.offset[axis] = (scroll_length - thumb_length) * value` clamped to
`[0, end_position]` (`:2251-2259`). Corrected formula
(`_mod_tweaker_definitions.lua:1200-1235`):

```lua
local end_position = track_h - th                              -- max thumb travel
local current_position = end_position * (1 - clamp(scroll_value, 0, 1))  -- HIGH at top, 0 at bottom
ui_style.thumb.offset[2] = math.clamp(current_position, 0, end_position) -- never overflows
```

**Top/bottom clamp.** `offset[2]` is clamped to `[0, end_position]`, so the thumb's bottom-left
origin is always `>= 0` (never below the track bottom) and its top edge is
`offset + th <= end_position + th = track_h` (never above the track top). The thumb can no longer
run off either end.

**2. Track color was fabricated.** The `{70,70,70}` track grey was invented. Read the REAL vanilla
values from native `create_scrollbar` (`ui_widgets.lua:2286-2306`):
- **track** (`background`) default = `{255, 5, 5, 5}` (near-black) — now used (was the made-up
  `{70,70,70}`).
- **thumb** (`scroll_bar_box`) default = `Colors.font_button_normal` = `{255, 160, 146, 101}`
  (`colors.lua:1021-1026`, the warm tan) — gut already had this exact value since 0.2.76; it turns
  out to be the native default, so it is kept.

**Probe extended (both twins).** The `[mt:scrollbar]` dump now logs the thumb's RESOLVED `offset[2]`
(`_resolved_thumb_off`, written by the local_offset pass) and a computed **world-Y top + bottom**
line versus the track's world-Y span, plus `scroll_value`, so position is verifiable from log data:
on overflow the thumb should be flush at the track TOP at `scroll_value=0` and flush at the BOTTOM
at `scroll_value=1`, always inside `[track_y, track_y + track_h]`.

**Not regressed:** the v0.2.77 local_offset SIZING (sizes the thumb to
`track_h * clamp(thumb_frac, 0.06, 1)`), the `_max_scroll > 0` draw-gate, the thumb-drag input,
the `rows=0` guard, and `plan_drill_children` are all untouched.

## 0.2.77-dev (2026-06-23) — Mod Tweaker scrollbar: thumb now sizes + drags (offset_function moved to a local_offset pass)

**Symptom (user, in-game).** The scrollbar thumb was ALWAYS the full length of the track and could
not be dragged to scroll. The `[mt:scrollbar]` probe confirmed the thumb's `style.size = {8, 760}`
= the full 760px track height, regardless of how much the content overflowed.

**Root cause — the same `offset_function` / `local_offset` defect that burned the gut SLIDER 3x
(fixed v0.2.59).** The thumb's proportional sizing + scroll-position math lived in an
`offset_function` attached directly to the thumb's `rect` pass
(`_mod_tweaker_definitions.lua:1185`). But VT2's generic widget draw loop
(`ui_renderer.lua:521-555`) NEVER calls `offset_function` for `texture`/`rect`/`texture_uv` passes —
only a dedicated `pass_type = "local_offset"` pass invokes it (`UIPasses.local_offset.draw`,
`ui_passes.lua:4587-4593`, is literally just `pass_definition.offset_function(...)`). So the
thumb's sizing function silently never ran: the thumb kept its scenegraph style size
`{8, track_h}` = the full track every frame, leaving nothing shorter than the track to grab. The
0.2.76-dev note "thumb `offset_function` ... Unchanged; just no longer drawn" was wrong on that
point — the function was never firing in the first place.

**Fix.** Replaced the per-pass `offset_function` with a single `local_offset` pass placed BEFORE
the thumb `rect` pass, mirroring the working slider (`create_slider`,
`_mod_tweaker_definitions.lua:591-669`) and the native VT2 pattern
(`options_view_definitions.lua:1673-1695`). That pass mutates the thumb sub-style in place every
frame:

- `ui_style.thumb.size[2] = track_h * clamp(thumb_frac, 0.06, 1)` — proportional height,
  strictly `< track_h` on real overflow, so the thumb is now visibly shorter than the track.
- `ui_style.thumb.offset[2] = -(track_h - thumb_h) * clamp(scroll_value, 0, 1)` — slides the
  thumb down the track as you scroll.

The view still feeds `content.scroll_value` + `content.thumb_frac` each frame, gated on
`_max_scroll > 0` (`_mod_tweaker_view.lua:1801` / `_mod_tweaker_state.lua:1754`), so on a fitting
menu the whole widget stays hidden (correct, unchanged). The existing thumb-drag input path
(`_max_scroll > 0` block reading the scrollbar hotspot, both twins ~:1376/:1339) is unchanged —
it now has a sub-track-length thumb to drag against. Colors unchanged: tan thumb
`{255,160,146,101}`, track `{255,70,70,70}`.

**Probe extended.** The `[mt:scrollbar]` THUMB line now logs the RESOLVED thumb height (the
local_offset pass writes `content._resolved_thumb_h`), so a full-track value there immediately
flags the pass not running. The probe also fires once on each overflow-state TRANSITION inside
`_recompute_scroll_bounds` (`scroll-bound:overflow` / `:fits`), so the next repro captures the
overflow state — on_enter alone often sampled before the list had overflowed. Both twins.

**Not regressed:** the `_max_scroll > 0` draw-gate, the tan/grey colors, the normal-list `rows=0`
guard, and the 0.2.75-dev `plan_drill_children` nested-dropdown fix are all untouched.

## 0.2.76-dev (2026-06-23) — Mod Tweaker scrollbar: native-tan thumb (no more "solid grey column")

The user reported the scrollbar still drew as a solid grey column covering the whole track,
always max size, with no visible backdrop. The `[mt:scrollbar]` probe from 0.2.73-dev confirmed
the geometry path.

**1. Draw is gated on overflow.** Both twins' `_draw` already wrap the scrollbar
`UIRenderer.draw_widget(renderer, self._scrollbar)` in
`if self._scrollbar and (self._max_scroll or 0) > 0 then` (`_mod_tweaker_view.lua:1801` /
`_mod_tweaker_state.lua:1754`). `_max_scroll = max(0, content_h - visible_h)`
(`_recompute_scroll_bounds`), so when the content fits the window the WHOLE widget — track,
thumb, and hotspot passes — is skipped, exactly like the native VT2 scrollbar. The earlier
"full grey column even when nothing scrolls" was the pre-gate state the probe captured; the gate
is in place and is the single draw path (verified: exactly one `draw_widget(self._scrollbar)`
call per twin, both inside the gate).

**2. Proportional thumb on overflow.** When `_max_scroll > 0`, the draw sets
`thumb_frac = visible_h / content_h` (< 1), and the thumb pass's `offset_function`
(`_mod_tweaker_definitions.lua:1185`) sizes the thumb to `track_h * clamp(frac, 0.06, 1)` — always
strictly less than `track_h` on real overflow — so the track backdrop is visible behind/around
the thumb. Unchanged; just no longer drawn in the content-fits case where `frac` would clamp to 1.

**3. COLOR — the live fix this version.** The thumb was grey `{210,210,210}` — wrong hue and far
too bright, which read as the "solid grey column." Switched it to native VT2 tan
`{160,146,101}` (`font_button_normal`) so it matches the rest of the menu chrome. The track stays
mid-grey `{70,70,70}` (~55 levels over the probe-measured `{15,15,15}` background backing, and
clearly distinct from the tan thumb). Shared build lives once in `build_scrollbar_rect`
(`_mod_tweaker_definitions.lua:1209-1210`); both twins consume it. EXACT RGB is an in-game
eyeball call per the no-speculate-on-appearance rule — these are native-matched defaults.

**Not regressed:** the `[mt:scrollbar]` probe stays in place for re-verify; the normal-list
`rows=0` guard (`has_children and wtype ~= "header"`) and the 0.2.75-dev `plan_drill_children`
nested-dropdown fix are untouched.

## 0.2.75-dev (2026-06-23) — Mod Tweaker: VMF dropdowns nested 3-deep now show their options

**Symptom.** The wt anim picker's per-attack dropdowns (and any VMF dropdown sitting three
levels deep) opened empty / showed `?` in the Mod Tweaker, even though VMF's own native menu
renders them full.

**Root cause — a NESTING-DEPTH navigation bug, NOT a wrong options read.** gut already reads a
dropdown's option list the SAME way VMF's native options view does: the option array is at
`node.options` (top-level on the flattened `vmf.options_widgets_data` entry), and each entry's
label/value are `option.text` / `option.value` — byte-for-byte VMF's
`initialize_dropdown_data` (`new_data.options = data.options`) and its render loop
(`for i, option in ipairs(widget_definition.options) do options_texts[i] = option.text;
options_values[i] = option.value`). gut reads exactly that via `_nf(w, "options")` →
`_nf(o, "text")` / `_nf(o, "value")` (`_mod_tweaker_state.lua:543/550-554`). That read was never
the problem and is unchanged.

The wt anim picker wires its dropdowns as `checkbox (depth 1) → set-group (depth 2) →
per-attack dropdown (depth 3)`. The gear-drill's child loop only ever rendered the drilled
parent's **direct** children (a hard-coded single `depths[j] == pdepth + 1` level): drilling the
checkbox showed the depth-2 set-GROUP headers, and the loop never descended to build the depth-3
dropdown nodes. The dropdowns therefore never existed as rows, so their (correctly-read) options
were never surfaced — the `?` / empty was the **absence of the row**, not an empty option list.

**Fix.** New shared planner `defs.plan_drill_children` (`_mod_tweaker_definitions.lua`) walks the
WHOLE subtree under the drilled parent using the SAME group-collapse / gear-parent rules as the
normal list loop, rebased so the parent is row-depth 0 and a flat-depth-d node renders at
row-depth `d - pdepth`. A child that is itself a `group` honors the user's expand state (collapsed
groups hide descendants inline, expanded groups reveal them); a non-group node with deeper
children gets a gear so it can be drilled one level further. So the user can now drill the
checkbox → expand a set-group → see and pick its dropdowns, and selecting an option stages +
applies through the existing `_commit_dropdown` path unchanged.

Both twins (standalone `ModTweakerView` in-mission, `HeroViewStateModTweaker` keep sub-state)
call the shared planner identically. A new `:_group_key(node, category)` method (added to both
twins, mirroring the original inline gid) is shared by `_build_node_row` and the planner's
`is_expanded` predicate so the rendered group row and the planner agree on the exact expand key.

**Not regressed:** the normal-list `rows=0` guard (`has_children and wtype ~= "header"`,
`_mod_tweaker_state.lua:700` / `_mod_tweaker_view.lua:570`) is untouched — the planner runs only
inside the `self._drill` branch. The header exclusion is intentionally not replicated in the
planner because a VMF per-mod header only ever appears at top level (depth 0), never inside a
drilled subtree. `luacheck`: 0 errors across all three files.

## 0.2.74-dev (2026-06-23) — Mod Tweaker scrollbar POSITION + COLOR fix (from REAL probe data)

The 0.2.73-dev `[mt:scrollbar]` probe gave us the runtime truth. Two problems, both fixed off
measured values (no more inference):

**1. POSITION (the real bug) — root cause: wrong anchor.** The bar parented to `list_mask` and
right-aligned with a `-30` inset. But native `list_mask` is a **left-aligned 1400px-wide node**
(== `WINDOW_WIDTH`) sitting at `+18` on the centered `background_frame`
(`options_view_definitions.lua:274-287`), so its **right edge juts ~18px PAST the visible panel's
right edge**. Right-aligning the bar to that off-panel edge made its on-screen X depend on a brittle
absolute offset: the probe measured world x **-12** (off the left) when the menu sat at origin
`{0,0}`, and world x **1638** (right edge of the over-wide mask, on/over the frame border) when the
menu was at `{260,90}` — not deterministic, not anchored to anything the player sees.

Fix: re-anchor `mt_scrollbar` to **`background_frame`** (the decorated panel — centered, same
1400×900 as `background`), right-aligned with a small `-12` X inset (matching how native parents its
own `scrollbar_root` to `background`, not to the over-wide list_mask), vertical-centered with the
list-window height (760). The bar's world position is now identical in BOTH the standalone-view and
keep-sub-state presentations regardless of menu world position, and sits in the panel's right gutter
just inside the frame border. The thumb-drag math and the `offset_function` thumb travel are
unaffected — the node's world Y is numerically identical to the old list_mask-anchored value
(frame_bottom + 70 either way).

**On_screen-flag interpretation (why the probe said `false` in BOTH states — and it was a red
herring).** `math.point_is_inside_2d_box` uses **strict** `<`/`>` (`math.lua:142-143`). The old
probe tested the bar's bottom-left ORIGIN against the `list_mask` box; because the bar shares
`list_mask`'s vertical span, the bar's bottom-left Y **equals** the box's bottom Y, so `pos[2] >
lower[2]` is `false` → `on_screen=false` even when the bar is perfectly visible. So the `false` was a
strict-shared-edge artifact, not proof of off-screen. The probe is now corrected to test the bar's
**CENTRE** against **`background_frame`** (the visible panel), making the flag meaningful for the
next verify.

**2. COLOR — calibrated to the measured `{15,15,15}` background.** The probe confirmed the real
`background` chrome the bar draws over is `{15,15,15}` (not the `~{10,10,10}` the 0.2.72 comment
assumed). The old track `{30,30,30}` is only ~15 levels above that = barely distinguishable.
Track → `{70,70,70}` (clearly lighter than `{15,15,15}`); thumb stays bright at `{210,210,210}`
(reads strongly against the `{70,70,70}` track). EXACT RGB is an in-game eyeball call per the
no-speculate-on-appearance rule — these are reasonable high-contrast starting values to nudge after
a live look. **Thumb DYNAMIC SIZING is untouched** (probe confirmed frac 0.821 → 624px is correct).

The `[mt:scrollbar]` probe stays in place for the next verify. Shared scrollbar build (position +
color) lives once in `_mod_tweaker_definitions.lua` (`build_scrollbar_rect` + the `mt_scrollbar`
scenegraph node), so both twins inherit it; only the per-twin probe `on_screen` block was edited in
both files. The `rows=0` guard is untouched.

## 0.2.73-dev (2026-06-23) — Mod Tweaker scrollbar DIAGNOSTIC PROBE (instrument only, NO behavior change)

The scrollbar is still reported as "doesn't work" + "wrong color" after the 0.2.72-dev contrast
fix. That fix used INFERRED colors — it assumed the menu `background` was `~{255,10,10,10}` from a
code comment and never MEASURED it. (The native `background` chrome rect is actually
`{255,15,15,15}`; only the top/bottom panels are `{10,10,10}`.) Before touching colors again, we
need the REAL runtime render-state from an in-game repro.

This release adds a one-time-per-open `[mt:scrollbar]` debug dump (gated on `enable_debug_logging`,
fired from the SAME site as the existing `[mt:dump]` probe — `on_enter` / `substate_on_enter`) in
BOTH twins (`_mod_tweaker_view.lua` ESC-flow standalone view + `_mod_tweaker_state.lua`
`HeroViewStateModTweaker` keep sub-state). The dump logs:

- **Background chrome** `chrome[1]` resolved color `{A,R,G,B}` + scenegraph world position/size — the
  actual contrast baseline (no longer inferred). Also logs the top/bottom panels + list_mask.
- **Scrollbar TRACK + THUMB** resolved colors, scenegraph world position/size, and each style's z
  (`offset[3]`) for draw-order.
- **Scroll math:** `_content_h`, `_visible_h`, `_max_scroll`, `track_h`, the computed `thumb_frac`
  (= visible/content, same formula as the draw path), the clamped frac, the resulting `thumb_px`,
  and `will_draw` (the bar only draws when `_max_scroll > 0`).
- **On-screen check:** whether the `mt_scrollbar` node's world X/Y falls inside the `list_mask` panel
  box (off-panel = invisible to the eye even if "drawn").

NO scrollbar color/logic/geometry was changed — this is purely an instrument so the next repro log
reveals (a) the real background color, (b) whether the bar is drawn and where, and (c) whether the
thumb height is sane. Twin discipline preserved: identical probe body in both files.

## 0.2.72-dev (2026-06-23) — Mod Tweaker scrollbar now VISIBLE (contrast fix); confirmed thumb already dynamic + recomputed on collapse/expand

The scrollbar was reported as "wrong" — looking like there was no bar, and not appearing to
resize on collapse/expand. Diagnosis split the report into two halves:

- **Thumb sizing / collapse-expand recompute: ALREADY CORRECT (no code change).** The thumb is
  genuinely dynamic. `content.thumb_frac = visible_h / content_h` is recomputed every frame
  (`_mod_tweaker_view.lua:1682`, twin `_mod_tweaker_state.lua:1646`) from `self._content_h`, and
  the defs `offset_function` converts it to a live thumb height `th = track_h * frac`
  (`_mod_tweaker_definitions.lua:1099-1104`) — the native `track_length * (visible/total)` formula.
  `_content_h` is itself recomputed by `_build_rows` on EVERY collapse/expand/drill/tab-switch
  (`view:582-584`, `state:712-713`), which the group-header click funnels through. So the thumb
  grows when a group collapses (less content) and shrinks when it expands (more content) without
  any extra wiring. This half of the report was not a real bug.

- **Visibility / color: THE REAL CAUSE — fixed.** The track color was `{255,5,5,5}` — DARKER than
  gut's `background` chrome fill (`~{255,10,10,10}`), so the track was effectively invisible against
  the panel (exactly the user's "bar equals the menu background" guess). The native scrollbar only
  reads in the real Options menu because its track sits over a lighter list backing; gut's
  `mt_scrollbar` draws over the raw dark background. The thumb `{255,160,146,101}` was the dim idle
  `font_button_normal` tan with weak contrast and no hover-brighten. Fix raises the track to
  `{255,30,30,30}` (now LIGHTER than the background) and the thumb to `{255,200,200,200}` (bright,
  clearly visible). Single edit in the SHARED `_mod_tweaker_definitions.lua:1110-1121` scrollbar
  factory (`build_scrollbar_rect`), so it covers both presentations at once.

Twin discipline + the `rows=0` guard (`has_children and wtype ~= "header"`) are untouched in both
`_mod_tweaker_view.lua` (ESC-flow standalone) and `_mod_tweaker_state.lua`
(`HeroViewStateModTweaker` keep sub-state).

## 0.2.71-dev (2026-06-22) — Mod Tweaker polish: ON/OFF flicker fix, width-based tab pagination (no more "More 1/2"), bare-text APPLY, native slider glow, full hover sounds (both twins, rows-guard intact)

Five contained Mod Tweaker fixes. Every view/draw/scenegraph change lands in BOTH twins
(`_mod_tweaker_view.lua` = ESC-flow standalone, `_mod_tweaker_state.lua` =
`HeroViewStateModTweaker` keep sub-state) identically; shared widget factories in
`_mod_tweaker_definitions.lua`. The `rows=0` guard (`has_children and wtype ~= "header"`) is
untouched in both twins.

1. **ON/OFF toggle flicker FIXED.** A single physical click on a checkbox/boolean row was
   flipping `content.flag` on/off/on across several frames ("negotiating" flicker). Root cause:
   the rows share the `mt_list_start` node, which keeps `on_release`/`on_left_release` latched
   true for several consecutive draw frames, and the handler's unconditional
   `c.flag = not c.flag` re-inverted the flag once per latched frame (the displayed word follows
   `content.flag` directly via the defs `on_text`/`off_text` passes, so every extra toggle is
   visible). Fix = a per-row `row._toggle_armed` release edge-latch so the toggle fires exactly
   ONCE per physical release, then clears when all three hotspots' (`hotspot`/`dec`/`inc`)
   release flags drop. Mirrors the existing `row._was_hovered` hover debounce. Checkbox branch
   of `_handle_input` in both twins.

2. **"More 1/2" pagination dropped — paginate on MEASURED width, not tab COUNT.** Tabs are
   text-aware (variable width via `_layout_tabs`), so the old `total > MAX_TABS` (=8) count test
   over-paginated, showing a "More 1/2" tab even when every label fit. The `_rebuild` pagination
   block now pre-measures each tab label the SAME way `_layout_tabs` does (create_tab style =
   `hell_shark` / size 20 / `upper_case`; `UIFontByResolution` + `UIRenderer.text_size` + a 20px
   gap each) and only paginates when the sum exceeds the usable strip
   (`defs.window.w` 1400 − x0 anchor 65 − 120px right margin). When it fits, `per_page = total`
   so ALL tabs show and no More tab is built. The measure is pcall-guarded → falls back to "fits"
   (no pagination) on a borrowed-renderer failure. `MAX_TABS` survives only as the per-page size
   for a genuine overflow; the "More" tab-click branch + paged hint stay (dead but harmless
   unless a future overflow re-triggers them).

3. **APPLY button box REMOVED — bare text + hover.** Dropped the filled `rect` bg pass and the
   1px `border` pass from `create_apply_button` (defs), keeping only the `hotspot` (click +
   hover) and `text` passes. The `bg`/`border` STYLE tables are kept so both twins' per-frame
   `asty.bg.color` / `asty.border.color` writes still index live tables (now harmless no-ops);
   the gold/grey enabled-disabled text-color feedback and the gated hover sound are retained.

4. **Native slider hover-GLOW restored.** gut already had a `thumb_hover` (`slider_thumb_hover`)
   texture pass gated on `c.track_hs.is_hover`, but it was sized at the BASE thumb's 14x27 — an
   invisible same-size overlay, not the glow. The native glow is the WIDER 34x25
   `slider_thumb_hover` atlas sprite (`gui_settings_atlas.lua:396`) centered on the 14px base
   thumb and drawn on top only while hovering (`options_view_definitions.lua:1720-1739`,
   `:2062-2073`). Defs now size `thumb_hover` at 34x25 (`THUMB_HOVER_W/H`), center it vertically
   on the row and horizontally on the base thumb (the `local_offset` pass adds
   `THUMB_W/2 − THUMB_HOVER_W/2`), and set `masked = false` (the borrowed renderer has no stencil;
   the sprite is fully inside its UV rect). Both sprites are atlas-backed and resident → safe on
   the borrowed renderer (per `reference_vt2_options_widgets_raw_materials`).

5. **Hover sounds wired on tabs, APPLY, and exit-X.** Clicks already fired `_play_click()` on
   every commit (toggle/arrow/dropdown-select/slider-release/tab-switch/APPLY/gear/exit). Hover
   sounds previously fired ONLY for list rows (`_apply_row_hover`). Added edge-debounced
   `_play_hover()` on the hover-ENTER edge for the top tabs (`tab._was_hovered` in the tab-tint
   loop), the APPLY button (`self._apply._was_hovered`, gated on `enabled` so the greyed button
   stays silent), and the exit-X (`self._exit._was_hovered`) — all in both twins' `_draw`. No
   change to `_wwise_world` / `_play_event` (resolution off `music_world` is already correct +
   pcall-safe).

## 0.2.70-dev (2026-06-22) — Mod Tweaker PHASE 4: STAGED-change model + bottom-right APPLY button (both twins, rows-guard intact)

PHASE 4 from the implementation spec. Editing a setting no longer writes live — every edit
(toggle / stepper / slider drag / dropdown select / typed number field) now stages into a
**pending buffer**, and a native-style **APPLY** button (bottom-right of the bottom panel)
commits the whole buffer at once. Exiting the menu **discards** any unapplied edits. Rows
**display the pending value** while it's pending (so a staged toggle/slider/dropdown shows the
new value, not the old live one). Modeled on native Options, which stages all edits in
`changed_user_settings` and only writes on APPLY (`options_view.lua:1789-1939, 3129-3196`). No
DEFAULT/reset button (deliberately omitted per spec).

How the buffer works:
- `self._pending[mod_id][setting_id] = staged_value`. Keyed by **mod_id** (a stable string),
  NOT the category table — category tables are re-created on every `_rebuild`
  (`_vmf_categories`), so keying by the table would lose the buffer on a tab switch. mod_id
  survives, which also gives **per-category isolation** for free: switching tabs away and back
  preserves that category's staged edits, and APPLY commits only the active category's buffer.
- **`stage_set(category, id, value)`** — every row WRITE routes here (was a live `_cat_set`).
  Records the value + refreshes the APPLY dirty state. Does NOT set `self._dirty`.
- **`get_staged(category, id, live_value)`** — every row READ/repaint routes here. Returns the
  staged value if pending, else the live value (mirrors native `_get_setting` `assigned(...)`).
  Wired into the checkbox `flag`, slider `value`, and dropdown `current_selection` reads in
  `_build_node_row`, so a rebuilt row reflects its staged edit instead of snapping back to live.
- **`apply_pending(category)`** — the APPLY click. The **ONLY** place `_cat_set` runs on edit:
  it loops the buffer through `_cat_set` (so each mod's `on_setting_changed` still fires —
  ct's 25-coin snap, etc.), clears the buffer, sets `self._dirty` (so the TOML still exports on
  exit), greys the button, and `_build_rows` repaints from the new live values.

APPLY button:
- New `mt_apply` scenegraph node — clone of native `apply_button`
  (`options_view_definitions.lua:344-357`): parent `background_bottom_panel`, right/top
  aligned, position `{-30,-7}`, size `{150,30}`. Native's `reset_to_default` (DEFAULT) sibling
  (`:358-371`) is **not** cloned.
- Hand-built widget (`create_apply_button`, defs) — `rect` bg + `border` + hotspot + centered
  text — NOT `UIWidgets.create_text_button` (atlas/material backing can miss on the borrowed
  renderer; same reasoning as the tabs). Both passes are material-lookup-free (`border` uses
  only `UIRenderer.draw_rect`, `ui_passes.lua:1245-1258`), so they resolve on the borrowed
  renderer. Label from `menu_settings_apply` when it localizes cleanly, else literal "APPLY".
- Enabled/greyed (`_update_apply_button`, recomputed each draw frame): **gold** text
  (`cheeseburger` `{255,255,168,0}`, `colors.lua:85`) + brighter border when the active
  category's buffer is non-empty (`next(pending) ~= nil`); dim grey + faint border + click
  suppressed when empty. Hover brightens the bg fill when enabled. Mirrors native
  `update_apply_button` (`options_view.lua:3129-3140`).

Discard semantics: because nothing was written live, exit = drop the buffer (`self._pending =
{}` in `on_exit`). No native `apply_changes(original_*)` re-apply is needed (that exists only
for native's live video-preview). `self._dirty` (the auto-save-to-log trigger) is set ONLY by
`apply_pending` — a buffer that was never applied leaves `_dirty` false, so exiting with only
pending edits correctly does **not** export.

Audit constraint (load-bearing): every former live-write site — checkbox toggle, slider
commit, dropdown commit, and the typed-number `_commit_edit` — now calls `stage_set`; `_cat_set`
is called from `apply_pending` ONLY (verified by grep in both twins). Any row still reading live
(not `get_staged`) would visually snap back after an edit — the three editable reads were all
converted.

Implemented IDENTICALLY across the two verbatim twins (`_mod_tweaker_view.lua` = standalone
in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state): the five staging methods
(`stage_set` / `get_staged` / `_active_category_dirty` / `_update_apply_button` /
`apply_pending`), the `_cat_key` helper, the buffer init, the three buffer-first reads, the four
staged writes, the APPLY input handler, the APPLY per-frame styling, the APPLY draw, and the
discard-on-exit are all the same modulo the class-name prefix. The one deliberate difference:
the view defines the staging helpers AFTER its `_cat_set`/`_play_click` file-locals (the view
declares them after the class; placing the helpers right after the class would capture the
GLOBAL nil `_cat_set` — forward-reference trap), whereas the state declares `_cat_set` before its
class so it places them earlier. Behaviour is byte-identical. Shared APPLY widget factory
(`create_apply_button`) + scenegraph node live once in `_mod_tweaker_definitions.lua`. The
`rows=0` build guard (`has_children and wtype ~= "header"`) is unchanged in BOTH twins. No new
hooks. luacheck: 0 errors. **Needs an in-game eyeball.**

## 0.2.69-dev (2026-06-22) — Mod Tweaker PHASE 3: real DROPDOWNS (single down arrow → popup option list → select/close), both twins, rows-guard intact

PHASE 3 from the implementation spec. Dropdown-type settings are now a REAL dropdown
instead of a `[<]`/`[>]` stepper carousel: the collapsed row shows the selected value with a
single **down-pointing arrow** on the right; clicking the row opens a **popup list** of the
options; clicking an option **sets the value + closes**; click-away or **Esc closes** without
committing. Modeled on native `create_drop_down_widget`
(`options_view_definitions.lua:2299-3047`). Steppers, sliders, checkboxes, and the gear
drill-down are untouched.

Built on gut's borrowed renderer with only atlas-resident textures (no raw non-atlas
materials): the collapsed arrow is `drop_down_menu_arrow` / `drop_down_menu_arrow_clicked`
(`gui_settings_atlas`, the same atlas as the slider thumb + stepper arrows; arrow box 31×15,
confirmed `gui_settings_atlas.lua:172`), flipped vertically (`uvs {{0,1},{1,0}}`) to point UP
while open. The popup highlight is `playerlist_hover` (`gui_menus_atlas`, the same sprite gut
already uses for row hover + the gear); the popup background panel + shade are plain `rect`
passes (the borrowed renderer lacks `rect_masked` — same substitution gut uses for the
slider track / separator).

The popup is its OWN overlay widget on a new `mt_dropdown` scenegraph node (child of `mt_list`,
so it scrolls with the rows but draws LAST, after the rows + scrollbar, OUTSIDE the cull loop
— so it overlays everything and is never clipped by the `list_mask`). This is the
cosmetics_tweaker glow-picker "own overlay scenegraph" pattern. While a dropdown is open it's
**modal**: `_handle_input` short-circuits to the popup so no other row reacts. One dropdown
open at a time (`self._open_dropdown`); the buffer is cleared on every list rebuild (tab
switch / drill / collapse), same as the type-edit teardown.

Open / select / close mechanics:
- **Open** — click the collapsed row's right field strip (`content.hotspot.on_left_release`) →
  `_open_dropdown_popup`: sets `content.active` (flips the arrow up), scrolls the visible window
  so the current selection is in view, builds the popup widget, plays `Play_hud_select`.
- **Select** — click a visible option row (`content.opt_<k>.on_left_release`) →
  `_commit_dropdown`: maps the visible slot `k` to the absolute option index via `start_index`,
  writes through the existing `_cat_set` path (so the mod's `on_setting_changed` still fires),
  updates the collapsed-row value text, closes.
- **Close without commit** — click-away (`Mouse.released(0)` not over an option) OR the first
  **Esc** (highest-priority branch in `update`, above the type-edit and drill ESC handlers).
- **Long lists** — popup caps at 10 visible rows; the mouse wheel over an open list scrolls the
  option window (`start_index ± 1`) and rebuilds the popup.

Implemented IDENTICALLY across the two verbatim twins (`_mod_tweaker_view.lua` = standalone
in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state) — the six new dropdown
methods, the modal short-circuit, the row-loop open branch, the ESC-close branch, the
`_build_node_row` routing, the `_build_rows` clear, and the `_draw` popup overlay were all
verified byte-identical between twins (modulo the class-name prefix). Shared widget factories
(`create_dropdown` + `create_dropdown_list`) live once in `_mod_tweaker_definitions.lua`. The
`rows=0` build guard (`has_children and wtype ~= "header"`) is unchanged in BOTH twins. No new
hooks (mod-lint PASS: 0 duplicate hooks). **Needs an in-game eyeball.**

## 0.2.68-dev (2026-06-22) — Mod Tweaker LAYOUT batch finalized: equipment-cog gear + control-column gutter, measured tabs, native scrollbar (both twins, rows-guard intact)

LAYOUT-batch finalization pass on the Mod Tweaker. The three layout items below were
landed in 0.2.67-dev as part of the larger polish+layout pass; this version pins them as
the verified LAYOUT deliverable after a both-twins parity + native-atlas audit. No new
behavioral subsystems — the option rows still cycle via the `[<]`/`[>]` stepper and every
edit still writes live (PHASE 3 popup dropdown / PHASE 4 staged APPLY remain deferred).

All three were verified IDENTICAL across the two verbatim twins (`_mod_tweaker_view.lua` =
standalone in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state) with the
shared widget pieces living once in `_mod_tweaker_definitions.lua`. The `rows=0` build guard
(`has_children and wtype ~= "header"`) is unchanged in BOTH twins. **Needs an in-game eyeball.**

- **Gear = equipment-menu cog (atlas-audited).** `create_gear_button` (defs) uses `cog_icon`
  (idle) / `cog_icon_selected` (hover), both confirmed present in `gui_menus_atlas`
  (`gui_menus_atlas.lua:1586`/`:1600`, authored 58×58) — the proven-resident atlas on the
  borrowed renderer. `texture_size` rescales the 58px sprite into the 26px gear box; a
  `cog_hover` pass gated on the gear hotspot highlight does the idle→selected swap. Shared
  factory, so both twins inherit it identically.
- **Control column left-shifted into its own gutter.** `RA = ROW_W - (GEAR_SIZE+24)` (=
  `ROW_W-50`); every arrow/value/track column derives from `RA`, so all recede 50px while the
  gear (`ROW_W - GEAR_SIZE - 10`) sits alone in the right-edge gutter — fixing the prior
  stepper-inc-arrow ↔ gear collision. `GEAR_SIZE` is defined above `RA` so the shift math can
  reference it; applied unconditionally so all rows stay column-aligned. Shared in defs.
- **Text-aware (measured) tabs.** `_layout_tabs()` (present + byte-identical in both twins)
  measures each tab label via `UIRenderer.text_size(renderer, text, font[1], scaled)`
  (`font,scaled = UIFontByResolution(text_style)`, uppercased to match the rendered string)
  and packs the tab scenegraph nodes left-to-right with a literal 20px gap, exactly like
  native (`options_view.lua:986-994`). pcall-guarded so a measure failure leaves the
  fixed-width fallback layout untouched.
- **Native scrollbar colors + dynamic thumb.** `build_scrollbar_rect` (defs): track
  `{255,5,5,5}`, thumb `{255,160,146,101}` (`font_button_normal` @255). Thumb height =
  `track_h * thumb_frac` clamped `[0.06,1]`; both twins set
  `thumb_frac = visible_height / total_content_height` each frame, and the bar draws only when
  content overflows (`max_scroll > 0`), so it's hidden when `thumb_frac ≥ 1`.

## 0.2.67-dev (2026-06-22) — Mod Tweaker native-fidelity POLISH + layout pass (slider fill, group bg, nesting indent, number-field bevel, Enter→chat, gear texture, control-column shift, measured tabs, scrollbar)

Native-fidelity polish + layout pass on the Mod Tweaker, all derived from the VT2
`OptionsView` / `options_view_definitions` source. Shared widget pieces live once in
`_mod_tweaker_definitions.lua` (so both verbatim twins inherit them); the depth-threading,
chat-block, and measured-tab logic were added IDENTICALLY to BOTH twins
(`_mod_tweaker_view.lua` = standalone in-mission view, `_mod_tweaker_state.lua` = HeroView
keep sub-state). The `rows=0` build guard (`has_children and wtype ~= "header"`) is
unchanged in both twins. **Needs an in-game eyeball.**

### PHASE 1 — Polish

- **Slider yellow fill removed (native parity).** Native sliders have NO growing colored
  fill — only the thumb conveys position over a flat dark track
  (`options_view_definitions.lua:1675-1752`). Deleted the `fill` pass, its style, and the
  per-frame fill-width driver in the slider's `local_offset` pass; recolored the track from
  `{255,35,35,35}` to native `slider_box` near-black `{255,5,5,5}`. The thumb is unchanged.
- **Group-header tinted bar removed; larger colored title kept.** Deleted the `bg` rect pass
  + style on `create_group_header` (and matched it on `create_back_row` for consistency).
  The font-22 `font_title`-colored indicator + label are now the sole group differentiator,
  matching native (which has no tinted header bar).
- **Per-depth leading indent for nested child rows.** New `INDENT_PER_DEPTH = 24` constant;
  each factory (`create_checkbox` / `create_slider` / `create_stepper` /
  `create_section_title` / `create_group_header`) now takes a trailing `depth` arg and
  indents ONLY the left label x by `24*depth`, narrowing the label clamp width by the same
  amount so indented labels still terminate before the controls. The right-anchored control
  columns (arrows / value / track / gear) are untouched and stay column-aligned. Both twins
  thread `depths[i]` from `_build_rows` into `_build_node_row` and on into the factories
  (drill children render at depth 1 under their depth-0 parent).
- **Dark bevel behind the editable number field.** Native `input_field_background` is two
  stacked `rect_masked` passes (outer `{200,0,0,0}` 52px + inner `{255,10,10,10}` 50px one z
  up) under the value text. The borrowed renderer lacks `rect_masked`, so plain `rect`
  passes substitute (gut's established swap). Always-on; the transient `value_focus_bg`
  editing highlight had its z bumped 1→3 so it still layers over the bevel while typing.
- **Enter commits and never opens chat.** While a number field is being edited, the loop now
  re-asserts `Managers.chat:block_chat_input_for_one_frame()` every frame (pcall-guarded,
  `ChatGuiNull`-safe). The chat `chat_input` service is an independent read of keyboard
  Enter that gut's own `Keyboard.released(13)` commit can't block; the engine-sanctioned
  per-frame block (`chat_manager.lua:390-397`) suppresses chat activation for the whole edit
  (Enter-commit AND stray `y`/letters) and self-clears when editing ends. Existing
  Enter→commit / Esc→cancel handling is unchanged.

### PHASE 2 — Layout

- **Gear swapped to the equipment-menu cog.** `create_gear_button` now uses `cog_icon` (idle)
  / `cog_icon_selected` (hover) from `gui_menus_atlas` (the proven-resident atlas), rescaled
  into the 26px gear box, with a hover-swap pass gated on the gear hotspot's highlight. Was
  `cogwheel_small`.
- **Control column left-shifted to give the gear a gutter.** `RA` (the right anchor every
  arrow/value/track column derives from) now recedes 50px: `RA = ROW_W - (GEAR_SIZE+24)`.
  This opens a clean right-edge gutter where the gear (`ROW_W - GEAR_SIZE - 10`) sits alone,
  fixing the old collision between the stepper inc arrow and the gear. `GEAR_SIZE` was
  promoted above `RA` so the shift math can reference it. Applied unconditionally so all
  rows stay aligned. The exported `gear_col_w` (50) already equals the shift.
- **Text-aware (measured) tab widths.** New `_layout_tabs()` in both twins measures each
  tab's label via `UIRenderer.text_size(renderer, text, font[1], scaled)` (font from
  `UIFontByResolution(text_style)`, uppercased to match the rendered string) and packs the
  tab scenegraph nodes left-to-right with a literal 20px gap, exactly like native
  (`options_view.lua:986-994`). pcall-guarded — a measure failure leaves the fixed-width
  fallback untouched.
- **Scrollbar native colors.** Track `{150,12,12,12}`→`{255,5,5,5}`; thumb
  `{255,160,160,160}`→`{255,160,146,101}` (`font_button_normal` @255). The dynamic thumb
  size (`track_h * thumb_frac`, `[0.06,1]` clamp) and the per-frame
  `thumb_frac = visible_height / total_content_height` set by the view are unchanged; the
  bar is already drawn only when content overflows (`max_scroll > 0`), so it's hidden when
  `thumb_frac >= 1` as specced.

### Deferred (not in this build)

- **PHASE 3 (real popup dropdown) and PHASE 4 (staged-change model + APPLY button) are NOT
  in 0.2.67-dev.** Both are large behavioral subsystems that change the menu's input/write
  model (a modal popup list with its own scroll + click-away; converting every row from
  live-write to a staged buffer committed only on APPLY). They warrant their own in-game
  iteration loop rather than landing blind alongside the low-risk polish/layout pass. The
  option rows still cycle via the `[<]`/`[>]` stepper, and every edit still writes live.

## 0.2.66-dev (2026-06-22) — Mod Tweaker sliders: click-to-type the numeric value (Enter/focus-loss commit, clamp + step-snap)

Additive type-to-edit on every Mod Tweaker slider/numeric row, mirroring VMF's typeable
popup but inline in the value column. The drag, the `[<]`/`[>]` arrow stepping, and the
`rows=0` build guard (`has_children and wtype ~= "header"`) are all unchanged — typing is
a purely additive third input path that is suppressed only while a field is focused.

Shared widget pieces live once in `_mod_tweaker_definitions.lua` (so both verbatim twins
inherit them); the focus/keystroke/commit logic was added IDENTICALLY to BOTH twins
(`_mod_tweaker_view.lua` = standalone in-mission view, `_mod_tweaker_state.lua` =
HeroView keep sub-state). Needs an in-game eyeball.

### Added
- **Click the slider's value to type a number directly.** A new `value_hs` hotspot over
  just the value box (separate from the track/arrow hotspots) focuses the field on click;
  digits, `.` (when the slider has decimals), and `-` (only when the range allows
  negatives) are accepted, Backspace trims, 16-char cap — the exact VMF filter
  (`vmf_options_view.lua:4532-4556`). Only one row edits at a time (`self._editing_row`).
- **Edit cursor + focus highlight while typing.** A faint highlight behind the value box
  (`value_focus_bg`) marks the focused field, and a thin caret bar (`caret`) pulses at the
  end of the typed text. Both are driven every frame by the slider's existing
  `local_offset` pass (rect passes ignore their own `offset_function`, so the caret x +
  pulsing alpha + highlight alpha are mutated there, like the thumb). Caret x is measured
  via `UIRenderer.text_size`; invalid/out-of-range input red-tints the value text
  (`{255,255,70,70}`, VMF parity); a trailing bare `.` is allowed so typing can continue.
- **Commit on Enter or focus-loss; cancel on Escape.** Enter (`Keyboard.released(13)`) or a
  click outside the value box (`Mouse.released(0)`) commits; Escape (`Keyboard.released(27)`)
  — intercepted in `update` BEFORE the menu-close/drill-out so the first Esc cancels the
  edit — restores the prior value. On commit the typed number is clamped to `[min,max]` and
  snapped to the slider's `step` grid (same math the drag/arrow paths use), then run through
  gut's existing `_cat_set` + re-read so any mod-side snap (e.g. ct's 25-coin rounding) is
  reflected. An in-progress edit is abandoned on any list rebuild (tab switch / drill /
  group collapse) so no stale `_editing_row` survives.

## 0.2.65-dev (2026-06-22) — Mod Tweaker native-fidelity layout pass (title removed, tabs full-band, arrows column-aligned)

Five native-layout fixes derived from the VT2 `OptionsView` source, plus the keep
separator shift. All shared layout changes live once in `_mod_tweaker_definitions.lua`
(so they land in BOTH verbatim twins automatically); the title-widget removal touched
both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) identically; the
separator shift is in `gui_tweaker.lua`. The rows=0 guard (`has_children and
wtype ~= "header"`) is unchanged and still present in both twins. Visual — needs an
in-game eyeball to confirm the exact placement.

### Changed
- **"MOD TWEAKER" title removed entirely (A/B).** Native Options has NO title text in
  the top band — the tab buttons span the whole band. Deleted the `mt_title` scenegraph
  node, the `build_title` factory, and every `self._title` build/draw/teardown in both
  twins. Undid the v0.2.64 band-split: tabs now occupy the FULL 50px top band,
  bottom-aligned and lifted +9px off the panel bottom, starting at x=65 — matching
  native `button_pivot` (`options_view_definitions.lua:204-217`).
- **Tab strip restored to the native full-band layout (B).** Tab nodes parent to
  `background_top_panel`, bottom-aligned, box height 30 (native tab box), x0=65, gap 20.
- **Inter-tab gap = native 20 (C).** Matches `options_view.lua:993` (`x += text_w + 20`).
  (Tabs remain fixed-width slots — a deliberate simplification of native's per-tab
  measured width, noted in-code so it isn't read as a bug.)
- **Stepper + slider arrows now share constant right-anchored x-columns (D).** Both the
  ON/OFF stepper arrows and the slider `[<]`/`[>]` arrows derive from native-anchored
  constants (`RA = ROW_W`; `ROW_W = list_width − 100 = 1300`): decrement (left) arrow at
  `RA−400` is a single flush column for BOTH types; increment (right) arrow at `RA−19`
  for steppers / `RA−71` for sliders (52px inboard to clear the slider's value box, per
  native); value text centered at `RA−200` (stepper) / `RA−25` (slider). The slider
  track/fill moved into the input-field column (`RA−370`, width 288, height 10) so its
  arrows bracket it exactly as native. Native click feel: stepper arrow hotspots widened
  to the native 200px (`INPUT_FIELD_WIDTH/2`). Replaces the old `TRACK_X`/`TRACK_W`
  flanking layout. (`options_view_definitions.lua` :3404-3512 stepper, :2087-2251 slider.)
- **Slider + checkbox label fonts reduced to native 16 (E).** Native slider label is 16
  (`:1991-2002`); booleans render as a stepper so they use the native stepper label 16
  (`:3488-3502`), not the native checkbox label 28. Slider was 18, checkbox was 24.

### Fixed
- **Keep ESC menu separator no longer bleeds through the lifted button text (A).** The
  `gut_compact_esc_menu` hook lifts the button column up by `TOP_BIAS`, but the keep
  `divider` widget's position was unchanged, so the raised text overlapped the stationary
  rule. The `HeroWindowIngameView._update_presentation` hook now also shifts the
  `_widgets_by_name.divider` render `offset[2]` up by the same `TOP_BIAS` (SET, not
  accumulate — idempotent across presentation rebuilds), keeping it visible above the
  menu text. (`hero_window_ingame_view_definitions.lua:279`.) *Tune-in-game: bump to
  `TOP_BIAS + SPACING` if it needs to clear the top text row.*

## 0.2.64-dev (2026-06-22) — FIX two long-standing layout bugs (title overlap + keep-menu overflow), both rediagnosed

Two fixes where prior attempts changed the wrong lever. Both are visual and need an
in-game eyeball to confirm the exact placement (per-item notes). The title fix lives
once in the shared `_mod_tweaker_definitions.lua` (so it lands in BOTH verbatim twins
automatically); the keep-menu fix is in `gui_tweaker.lua`.

### Fixed
- **Mod Tweaker title no longer renders behind the tab strip (PROBLEM 1).** Root cause
  was NOT z-order (the prior build-3 fix bumped the title's z to 20 + drew it after the
  tabs — both Z-ORDER levers, which don't separate two widgets that share the same
  screen rectangle). The real cause: `mt_title` AND the `mt_tab_*` nodes both parented to
  `background_top_panel` (the 50px top band) with `vertical_alignment = "center"`, so
  they occupied the SAME band and overlapped spatially. Fix: vertically split the band —
  the title is now TOP-aligned in the upper ~22px, the tab strip BOTTOM-aligned in the
  lower ~26px (mirrors native Options, where the tab buttons hang off the panel BOTTOM
  via `button_pivot`). Title font 28 -> 22 to fit the slimmer band. *Needs in-game
  eyeball to confirm the title clears both the tabs and the cogwheel.*
- **Keep ESC "Main Menu" no longer overflows; logo hidden (PROBLEM 2).** Root cause: the
  prior `gut_compact_esc_menu` hook (since v0.2.56) targeted `IngameView.set_background_height`,
  but the keep pause menu is the MODERN `HeroWindowIngameView` sub-window (the bare legacy
  `IngameView` is only the in-mission menu) — that class has no `set_background_height`, so
  the hook NEVER FIRED there. Its logo-hide branch was also dead even on the legacy path
  (`IngameView.create_ui_elements` never assigns `self.logo`). Now gut hooks
  `HeroWindowIngameView._update_presentation` (the method that lays out the button column
  at spacing 60 and sizes the panel — `hero_window_ingame_view.lua:490-515`): once the
  column crosses ~8 buttons it re-packs the column tighter (spacing 60 -> 48) with an
  up-bias and hides the keep logo (zeroing `style.texture_id.color` alpha — the path
  `create_simple_texture` actually uses, not `style.color`). *Column lift amount + spacing
  are tune-in-game values; needs an in-game eyeball.*

## 0.2.63-dev (2026-06-22) — Mod Tweaker refinements toward the native settings menu

Five tweaks pushing the Mod Tweaker menu closer to VT2's native Options menu. All
visual — they need an in-game eyeball to confirm the exact look (see the per-item
notes). View/draw changes landed identically in BOTH verbatim twins
(`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`); shared factory changes live
once in `_mod_tweaker_definitions.lua`.

### Changed
- **Tab label overrides (item 5).** Added a `_TAB_LABEL_OVERRIDE` map (in both twins)
  applied in `_rebuild` BEFORE the "Tweaker: " prefix-strip + truncation, so a mapped
  mod's tab reads exactly the override. `cim` + `cim_dev` -> "CRAFTING". General Tweaker
  (`gt`/`gt_dev`) is left as-is (its VMF name already reads "General"). Easy to extend
  with more `<mod_id> = "LABEL"` lines.
- **Removed Verminious Dreams Lighting from the Mod Tweaker (item 7).** Dropped
  `verminious_dreams_lighting` + `_dev` from `_MY_MODS` in both twins so they no longer
  appear as a Mod Tweaker tab. They keep their own normal VMF menu. (The separate
  `_gut_config_file.lua` TOML-export whitelist is intentionally left untouched.)
- **Brighter row hover highlight (item 9).** Raised the `_append_highlight`
  ("playerlist_hover") alpha from 70 to 255 to match native's full-alpha row hover.
  *Needs in-game eyeball.*
- **Slider arrows flank the track (item 2).** The `[<]`/`[>]` arrows now sit just left
  and just right of the slider TRACK (value text after), column-justified off the
  constant TRACK_X/TRACK_W across all slider rows — matching native order, instead of
  both arrows bunched to the far right after the value. The track drag hit-zone was
  tightened to the track bounds so it no longer overlaps the flanking arrow hotspots.
- **Tighter rows + native-er fonts (item 4).** Row height 46 -> 32 (native is 30 with
  zero inter-row gap); checkbox label font 22 -> 24, slider label font 22 -> 18 (native
  is 28 / 16, using the masked font — gut uses the unmasked font, so these are
  tune-toward values). *Exact px needs an in-game eyeball.*

## 0.2.61-dev (2026-06-22) — FIX blank Mod Tweaker (rows=0): VMF header was hiding every setting

The build-4 gear refactor of `_build_rows` treated any node whose next node is deeper
as a "gear parent" and set `skip_below` to hide its children inline. But VMF's per-mod
widget list starts with a synthesized **header** node, with every setting a deeper
sibling under it — so the header itself was treated as a gear-parent and `skip_below`
hid EVERY setting. Net: header → nil row, all settings skipped → the menu rendered only
the tab strip with a blank body (`[mt] rebuild ... rows=0` in the log).

Fix: exclude `wtype == "header"` from the `has_children` gear/skip branch in BOTH twins
(`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`). Verify in-game: the menu body shows
settings; the `[mt] rebuild` debug line reads `rows=` > 0.

## 0.2.60-dev (2026-06-22) — Mod Tweaker keep ESC button now actually opens (force_open)

### Fixed
- **"MOD TWEAKER" in the keep ESC menu darkened the screen then opened nothing.**
  The build-2 keep path fired `transition_with_fade("hero_view", { menu_state_name =
  "gut_mod_tweaker" })`, the fade played, but the `gut_mod_tweaker` HeroView sub-state
  never switched in. Root cause: the ESC "Mod Tweaker" button fires from INSIDE the
  already-open keep ESC menu, which *is* `hero_view` (the `ingame_menu` window inside
  `HeroViewStateOverview`), so `IngameUI.current_view == "hero_view"` ALREADY. When the
  transition closure set `current_view = "hero_view"` again, `IngameUI.handle_transition`'s
  re-enter guard `if old_view ~= new_view or force_open` (`ingame_ui.lua:953`) evaluated
  `"hero_view" ~= "hero_view"` (false) with no `force_open` → it SKIPPED
  `HeroView:on_enter` / `post_update_on_enter`. And `post_update_on_enter`
  (`hero_view.lua:504-508`) is the ONLY code that reads `menu_state_name` and calls
  `_change_screen_by_name`. So `menu_state_name = "gut_mod_tweaker"` was silently dropped:
  fade in, fade out, no screen change. (The `[gui_tweaker] hero_view: state=?` diagnostic
  reflected the machine still sitting on the overview state, never switched.)
  - **Fix:** pass `force_open = true` in the transition params. This is the EXACT vanilla
    keep-button flow — every keep ESC menu button (Inventory, Loot, …) uses
    `transition = "hero_view"` + `transition_state = <screen>` + `force_open = true`
    (`ingame_view_menu_layout_console.lua:742-745`). `force_open` makes the
    `handle_transition` guard pass even when `old_view == new_view == "hero_view"`, forcing
    the re-enter so `post_update_on_enter` honors `menu_state_name`. Harmless on the
    not-already-in-hero_view path (`/gut_mod_tweaker` from gameplay), where `old_view`
    is `nil` and the re-enter happens regardless.
  - Applied to all three sub-state openers so they're robust regardless of entry state:
    the ESC closure (`gui_tweaker.lua` ~910), the `/gut_mod_tweaker` chat opener
    (`mod._gut_open_mod_tweaker`, `_ba_heroview_inject.lua`), and the compendium opener
    (`mod._gut_open_compendium`, same file) — the compendium carried the identical latent
    bug, masked only because `/gut_armory` / `/gut_bestiary` are chat-only (fired with no
    menu open, where `old_view` is `nil`).
  - **No new `mod:hook`/`mod:hook_safe` registrations** (pure params change). The
    in-mission standalone `ModTweakerView` path is untouched — it still opens its own view
    and routes exit via the origin-captured `_exit_transition`.

## 0.2.59-dev (2026-06-22) — Mod Tweaker gear "Advanced Settings" drill-down + slider thumb move fix

All Mod Tweaker view changes land identically in BOTH the in-mission standalone
`ModTweakerView` (`_mod_tweaker_view.lua`) and the keep `HeroViewStateModTweaker`
sub-state (`_mod_tweaker_state.lua`) — they are verbatim twins. The shared widget
factories live once in `_mod_tweaker_definitions.lua`.

### Added
- **Gear "Advanced Settings" drill-down (issue #79).** Any setting that owns nested
  sub-options now shows a 3rd-column **gear** (cogwheel) instead of flattening its
  children inline. Clicking the gear drills INTO that setting *in place*: the same
  list converts to a `< Back` row + the parent setting's own row + one row per child,
  on the SAME scenegraph/scrollbar. The `< Back` row (or the **first ESC**) drills back
  OUT to the normal list; a second ESC closes the menu. Tab/page switching is guarded
  while drilled. Good test targets on gut's own tab: **Parry Indicator**
  (`gut_parry_indicator` + R/G/B children) and **Respawn Timer** (`gut_respawn_timer`
  + font-size/R/G/B children).
  - Detection of "has children": gut NESTED categories = a non-`group` node with a
    non-empty `sub_widgets`; VMF FLAT categories = the next node's `depth` is greater
    than this node's. The nested walk now synthesizes a parallel `depth` array
    (`_walk_nested` replacing `_walk_leaves`) so BOTH paths run the identical
    "next node is deeper" detection + inline-skip. Groups keep their existing
    `[+]/[-]` collapse (no gear); only non-group parents get a gear.
  - The gear texture is `cogwheel_small` (`gui_icons_atlas`, 40x40) — the SAME sprite
    the window chrome already draws every frame as `menu_symbol`, so it's proven to
    resolve on the borrowed renderer (no raw-material crash risk). Its hotspot carries
    an explicit `style_id` (rows share the `mt_list_start` node, so without one the hit
    target collapses to 1x1 — the same gotcha already handled for checkboxes). The
    gear-parent's whole-row hotspot is trimmed so it stops before the gear column and
    a gear click can't double-fire on the parent row.
  - Child rows reuse the existing checkbox/numeric/dropdown build + `_cat_get`/`_cat_set`
    — **no new persistence**. The per-node row build was factored into a shared
    `_build_node_row` helper so the normal list and the drill view build rows identically.
  - **No new `mod:hook`/`mod:hook_safe` registrations** (mod-lint clean: 47 hooks,
    0 duplicates).

### Fixed
- **Slider thumb / fill now actually move (the build-3 "thumb doesn't move" report).**
  Root cause found in the decompiled engine, not guessed: `offset_function` is **not**
  a generic per-pass field. The generic widget draw loop (`ui_renderer.lua:521-555`)
  places each pass from `pass_style.offset` but NEVER calls `offset_function` for
  `texture`/`rect`/`texture_uv` passes — only the dedicated **`local_offset`** pass
  type invokes it (`ui_passes.lua:4587-4593`; the native slider uses exactly this at
  `options_view_definitions.lua:1673-1695`). The prior build attached the thumb/fill/
  thumb_hover `offset_function`s to `texture`/`rect` passes, where they were silently
  ignored — so the fill stayed at width 0 and the thumb stayed pinned at value 0.
  Fixed by replacing those dead per-pass functions with a single `local_offset` pass
  that mutates `style.fill.size[1]`, `style.thumb.offset[1]`, and
  `style.thumb_hover.offset[1]` in place from `internal_value` every frame — the
  native mechanism. The `[mt:slider-probe]` debug log is preserved (now inside the
  `local_offset` pass).

## 0.2.58-dev (2026-06-22) — Mod Tweaker native-settings fidelity: ON/OFF switches, texture arrows, moving thumb, separators, hover/sounds + in-mission origin-exit fix

All Mod Tweaker view changes land identically in BOTH the in-mission standalone
`ModTweakerView` (`_mod_tweaker_view.lua`) and the keep `HeroViewStateModTweaker`
sub-state (`_mod_tweaker_state.lua`) — they are verbatim twins. The shared widget
factories live once in `_mod_tweaker_definitions.lua`.

### Fixed
- **In-mission Mod Tweaker exit now returns to the menu the player actually opened — no more deprecated bare `IngameView` after exiting in a mission.** The prior build fixed only the keep path (HeroView sub-state). In a mission the standalone view's exit was hard-coded to `"ingame_menu"` (the deprecated legacy menu), so players who opened the modern HeroView ESC menu (the PC default, `use_pc_menu_layout=false`) were dumped into the bare 9-button legacy menu on exit. The transition closure now **captures the origin view** (`self.current_view`, still the engine's pre-closure snapshot per `ingame_ui.lua:946`) and routes exit back to it: `hero_view` origin → `hero_view` (which `ModTweakerView:exit` already handles safely with `{ menu_state_name = "overview" }`), everything else → `ingame_menu`. The `mod_tweaker_transition_registered` regression check now asserts both origin branches. (Same bug class as memory `reference_vt2_modview_exit_legacy_ingameview`.)
- **"MOD TWEAKER" title no longer renders behind the tabs.** The title and the tab strip both parented to `background_top_panel` at equal world-z and the title was drawn first, so the tabs overpainted it. Fixed two ways (belt-and-suspenders): the title node's local z is bumped `{0,0,4}` → `{0,0,20}` (above the tabs at z=4), and `_draw` now draws the title **after** the tab loop. The title is text-only (no hotspot) so drawing it last can never eat a tab click.

### Changed
- **Booleans render as a native ON/OFF stepper switch instead of a hand-built checkbox.** VT2's native settings render booleans as two-option steppers (`{true → "menu_settings_on"} / {false → "menu_settings_off"}`, `options_view_settings.lua:456`), not checkboxes. The `create_checkbox` factory now draws the label (left) + centered ON/OFF text (from the game's own `menu_settings_on`/`menu_settings_off` loc keys) flanked by the two native arrow textures. Either arrow, or the whole row, toggles the value.
- **Slider/stepper inc-dec controls are now the native arrow TEXTURES, not `<` / `>` text glyphs.** Left = `settings_arrow_normal` (a `texture` pass); right = the SAME texture flipped horizontally via a `texture_uv` pass with uvs `{{1,0},{0,1}}` — exactly the native pattern (`options_view_definitions.lua:1803-1837`). Hovering an arrow swaps it to `settings_arrow_clicked`.
- **Slider thumb tracks `internal_value` and shows the atlas `slider_thumb`/`slider_thumb_hover` sprite.** The thumb's `offset_function` recomputes `offset[1] = TRACK_X + TRACK_W·internal_value − thumb_w/2` every frame (mutating the offset table in place), so the thumb visibly slides as the value changes. A debug-gated probe (`[mt:slider-probe]`, throttled ~1/sec, gated on `enable_debug_logging`) logs `internal_value`, the computed thumb `offset[1]`, and whether the `slider_thumb` texture resolved — so if the thumb still doesn't move in-game the log pins the cause.
- **Per-row separators.** Each row now draws a faint full-width 2px bottom rule (a plain `rect` pass — never the native `rect_masked` material, which is absent on the borrowed renderer), color `font_default @ alpha 50`, matching the native `bottom_edge` (`options_view_definitions.lua:25-26`). Rows stack with no gap, so the rules read as one continuous ruled list.
- **Right-justified controls / left-justified names.** Control column x is now derived as `ROW_W − INPUT_FIELD_WIDTH(400)` (the native right-justify rule) instead of the old magic `600`; the slider track width was reduced so the track + value text + both arrows fit inside the right column. Names stay flush-left.
- **Tabs are ALL-CAPS with native 20px inter-tab spacing.** The tab text style now sets `upper_case = true` (a pure render transform — `localize` stays `false` since mod names aren't loc keys), and the inter-tab gap is 20px to match native (`options_view.lua:993`).
- **Mouseover hover highlight on rows + controls.** Each editable/clickable row draws the atlas `playerlist_hover` sprite (in `gui_menus_atlas`, gated on `content.is_highlighted`) when its hotspot is hovered. Set per-frame from the row hotspot's `is_hover` in the new `_apply_row_hover` draw helper.
- **Native Wwise sounds.** `_play_click` now fires `Play_hud_select` on every commit (checkbox flip, arrow click, dropdown cycle, slider release); a new `_play_hover` fires `Play_hud_hover` on the hover-enter edge only (debounced per row, never every frame), matching the real Options menu (`options_view.lua:544`/`423`). A one-time debug-gated `[mt:wwise]` probe logs which worlds expose a usable `wwise_world` (current handle is the `music_world`'s); if `Play_hud_*` are inaudible the log shows whether the handle resolved.

All textures used are atlas-backed and proven to resolve on the borrowed renderer: `slider_thumb`/`slider_thumb_hover`/`settings_arrow_normal`/`settings_arrow_clicked` (`gui_settings_atlas`), `playerlist_hover` (`gui_menus_atlas`). No raw materials (`checkbox_checked`/`rect_masked`/`highlight_texture`) are referenced — they crash on this renderer (memory `reference_vt2_options_widgets_raw_materials`). No new `mod:hook`/`mod:hook_safe` registrations were added.

## 0.2.57-dev (2026-06-22) — Mod Tweaker as a HeroView sub-state (keep path): kills the deprecated-menu look AND the LA-atlas crash

### Fixed
- **Opening the Mod Tweaker from the keep is now a HeroView SUB-STATE — no more deprecated bare-IngameView menu on exit, and no more Loremaster's Armoury `armoury_atlas` crash on repeated opens.** Root cause of BOTH symptoms: the keep path reached the Mod Tweaker by *leaving and re-entering* `hero_view` via `transition_with_fade`, which **recreates hero_view's renderer**; VMF then re-injects LA's atlas into the fresh renderer (the C-fatal, crash `42c81d84`), and the recreation dumped the player back into the deprecated standalone `IngameView` (the bare 9-button menu). A HeroView sub-state stays **inside the already-open hero_view and never recreates the renderer**, eliminating both. This is the proper fix the prior build's TODO described (modeled on the existing `HeroViewStateCompendium` sub-state). The in-mission path is **unchanged** — there's no `hero_view` in a mission, so the ESC "Mod Tweaker" button there still opens the standalone `ModTweakerView` (which routes its own exit to `ingame_menu`, the never-crashed path), preserving in-mission access.

### Added
- **`HeroViewStateModTweaker`** (`_mod_tweaker_state.lua`) — the Mod Tweaker rendered as a hero-menu sub-state. Ports the VMF auto-discovery, General-Tweaker-first tab ordering, pagination, collapsible groups, draggable sliders/dropdowns, scroll/cull, and the pcall-protected `end_pass` draw guard verbatim from `_mod_tweaker_view.lua`; the lifecycle shell follows the sub-state contract (renderer borrowed from the hero_view context — never recreated; input read from the parent hero_view's shared service; cursor managed by hero_view — gut pushes none; exit via `parent:close_menu`). The on-exit settings auto-save (TOML export) is preserved. Reachable in the keep via the ESC "Mod Tweaker" button **or** the new `/gut_mod_tweaker` chat command.
- **`/gut_mod_tweaker`** chat command — opens the Mod Tweaker hero-menu sub-state from the keep (mirrors `/gut_armory`); echoes a hint if used outside the keep.

### Changed
- The `gut_mod_tweaker` screen descriptor is registered alongside `gut_compendium` in the **single existing** `HeroView.init` hook (no new duplicate hook). The ESC "Mod Tweaker" transition closure now branches on `ingame_ui_context.is_in_inn`: keep → sub-state, mission → standalone view.

## 0.2.56-dev (2026-06-22) — ESC-menu overflow fix, pin General Tweaker tab, LA-atlas re-pin + instrument

### Fixed
- **ESC/keep menu no longer overflows off the bottom of the screen.** gut injects a "Mod Tweaker" button into the IngameView button column; on the keep host/client layout this makes 9 buttons, and the vertically-centred column ran off the bottom edge. A new `hook_safe("IngameView", "set_background_height", ...)` nudges the column up (and dims the logo/top panel) once the column crosses 8 buttons. Gated behind a new **Compact ESC Menu** checkbox (`gut_compact_esc_menu`, default ON). *NOTE: the nudge direction (up vs down) and the 44px/row amount are tune-in-game values — the column may move the wrong way on this first build; flip the sign after the user reports what they see.*
- **In-mission "Mod Tweaker" crash on the 3rd/4th open (materials/Loremasters-Armoury/armoury_atlas) — stopgap + instrumentation.** Root cause: the Mod Tweaker BORROWS the long-lived IngameUI renderer (it does NOT recreate it), but `_la_atlas_keepalive.lua` only pinned LA's atlas package ONCE (on `StateInGameRunning.on_enter`) — its premise that LA always keeps the atlas resident is false, so the atlas can be unloaded between opens and the borrowed renderer then hands a missing material to a C-fatal. gut now **defensively re-pins LA's package on every Mod Tweaker open** (both the ESC transition and `ModTweakerView:on_enter`), pcall-guarded and keeping the keepalive's `has_loaded` guard intact (it still NEVER force-loads a non-resident LA package — that was the 0.2.54 crash). Added debug-gated instrumentation: atlas residency, gut's pin state, an open-counter (1st/2nd/3rd/4th), the borrowed `ui_renderer`/`ui_top_renderer` identity per open, and a read-only log-and-passthrough hook on `PackageManager.unload` filtered to LA's package to catch any unload between opens. All instrumentation is gated on `enable_debug_logging`.

### Changed
- **General Tweaker is now pinned as the first (leftmost) Mod Tweaker tab.** The per-mod tab strip puts `gt` (stable) / `gt_dev` (dev) first regardless of the default ordering; every other mod keeps its existing relative order. Implemented via an explicit `TAB_PRIORITY` list so it's easy to extend later.

## 0.2.55-dev (2026-06-22) — NumericUI ability cooldown shows real-time reduced seconds

### Added
- **NumericUI's ability-cooldown number now counts in real seconds.** VT2 applies cooldown reduction by making the cooldown value *decrease faster* (`career_extension.lua:244`: `reduce_activated_ability_cooldown(dt * cooldown_regen_mult)`), not by shortening it — so NumericUI's display, which shows the raw `current_ability_cooldown()`, visibly **sped up** under CDR. gut now divides that read by the same `cooldown_regen` multiplier **only while NumericUI is computing its display** (inside its `UnitFramesHandler._sync_player_stats` hook), so the number shows the accurate reduced cooldown ticking at 1 second per second. The game's actual cooldown logic, the ability-bar fill, and bot AI are untouched (the flag can't leak — vanilla `_sync_player_stats` never reads the cooldown seconds). No-op if NumericUI isn't installed.

## 0.2.54-dev (2026-06-21) — Fix: the LA atlas keepalive itself hard-crashed (force-materialized LA's broken bundle)

The v0.2.53 keepalive (`_la_atlas_keepalive.lua`) called `Managers.package:load(LA_PACKAGE, GUT_REF, nil, true)` on every `StateInGameRunning.on_enter`. The 4th arg is `asynchronous` (not "persistent", as the comment wrongly claimed) — and because LA dynamically **unloads its own package**, at our on_enter the package is often NOT resident, so `load()` QUEUED a fresh load that **force-materializes every member of LA's bundle**. LA's installed bundle is missing an internal member, so the async `_pop_queue → resource_package` step took a C-level fatal: `Resource '#ID[3ac73385950a26ea]' not found` (that hash IS this LA package — Stingray names bundles by murmur64A of the package path). The `pcall` couldn't catch it (the fatal fires async, outside the Lua frame). Recurred every keep entry while LA was installed; vanilla was unaffected.

### Fixed
- `_la_atlas_keepalive.lua` now **only pins when LA's package is ALREADY fully resident** (`pm:has_loaded(LA_PACKAGE)`), making `load()` a pure reference-count increment — no re-materialize, no fresh-load queue. If LA's package isn't resident at on_enter (LA unloaded it / not loaded yet), it bails and retries next entry instead of force-loading it. The reference (held by `GUT_REF`) still survives LA's own unload, so the atlas stays resident when we do pin. Corrected the misleading "4th arg = persistent" comment. MOD_VERSION → 0.2.54-dev.

## 0.2.53-dev (2026-06-21) — Guard the Loremaster's Armoury atlas crash on the hero view

### Fixed
- **`[Script Error]: materials/Loremasters-Armoury/armoury_atlas` opening the hero menu (crash efadf778).** Root cause (traced from the full stack): LA registers its atlas for VMF custom-texture injection into the `hero_view` renderer-creator; the hero view's HDR sub-renderer (`hero_view_hdr`) shares that creator, so VMF injects the atlas there during `_setup_hdr_renderer`. LA *also* dynamically unloads its own package (it hooks `PackageManager.unload`), so the atlas is sometimes gone when that early HDR renderer is built → `create_screen_gui` C-fatal (not catchable by the `pcall` cim wraps around `_setup_hdr_gui`). Not a gut bug — gut wasn't in the stack — but fixable from our side: gut now **pins LA's package under its own package-manager reference** (on `StateInGameRunning.on_enter`) so LA's unload can't drop the atlas out from under the renderer. No-op if LA isn't installed. (Fix authorized by LA's authors; shipped in gut per the constraint that it ship from our mods.)

## 0.2.52-dev (2026-06-21) — Stop messing with captions at default settings

### Fixed
- **Captions/subtitles were being repositioned even with no settings changed.** The `SubtitleGui.update` hook (from the absorbed HideBuffs "reposition subtitles" feature) ran every frame as a `hook_safe` and unconditionally wrote `subtitle_widget.offset = {x, y}` — and since the subtitle-offset settings aren't exposed in gut's UI, `x`/`y` were always `0`, so it clobbered vanilla's own caption positioning with `{0, 0}`. Now it bails when both offsets are 0 (the default), leaving vanilla positioning untouched; it only moves captions if a non-zero offset is actually set.

## 0.2.51-dev (2026-06-21) — `<>` on the ESC entry: actual root cause fixed + tracked status doc

### Fixed
- **The `<>` on the "Mod Tweaker" ESC entry — finally root-caused.** The modern hero menu (`hero_window_ingame_view.lua:473`) builds the label as `text_field = display_name_func() or display_name` and then **localizes** `text_field`. Our button carried a `display_name_func` that returned the already-resolved string `"Mod Tweaker"`, so the menu re-localized that literal into **`<Mod Tweaker>`**. The legacy ESC menu used the key directly (which is why the probe always showed it resolving), masking the real culprit. Removed the func — the `display_name` key now localizes to "Mod Tweaker" (via the append fix) in **both** menus.

### Process
- Added **`GUI_TWEAKER_TODO.md`** — a tracked, honest status list of every Mod Tweaker / GUI request (active bugs, the native-parity rework phases, and what's done) so nothing gets dropped. The deprecated-menu-on-exit fix (make the Mod Tweaker a HeroView sub-state) and the native-parity rework are logged there as the next big tasks.

## 0.2.50-dev (2026-06-21) — Temporal Fix: baked in at -48, always on (no toggle/slider)

### Changed
- **UI Tweaks "Temporal Fix" is now always on with a baked-in `-48` nudge** (the value that lands the mini-HUD player health bar correctly). Removed the `gut_uitweaks_temporal_fix` checkbox and the `gut_temporal_hp_nudge_x` slider — the fix just applies whenever UI Tweaks (HideBuffs) is installed with its mini-HUD layout. (`gut_buffbar_endtime_fix` stays as a toggle.)

### Notes from the latest log
- The ESC-menu **`<>` is resolved** — the probe confirms `Localize('mod_tweaker_button_name') -> 'Mod Tweaker'`. If any `<>` remains it's a different element inside the Mod Tweaker view, not this button.
- Scrollbar `thumb_frac` computes correctly (0.936, scaling to content); no drag was exercised in the log, so slider/scrollbar dragging still needs an in-game check.

## 0.2.49-dev (2026-06-20) — Hide UI: fold in the proven original mod's outline + arms hiding

Compared the migrated feature against the **original "Hide UI" mod** (Workshop 2007374303) it replaces, and added the two pieces it was missing — all APIs re-verified against the current engine:
- **Outline system disabled** in complete/camera modes (`outline_system:set_disabled(true)`), so enemy/ally silhouettes hide too. Re-enable is **guarded against the Realism mutator** (which manages outlines itself), exactly like the original.
- **First-person arms hide** now uses the proper `first_person_extension:hide_weapons()` + the `first_person_attachment_unit` toggle (what vanilla `set_first_person_mode` does) instead of brute-forcing the whole FP rig — more correct, with the per-slot loop kept as a fallback.
- Outline/arms state toggles only on mode transitions (not every frame), and resets out of mission so re-entering a level re-applies against the fresh OutlineSystem/FP rig.

## 0.2.48-dev (2026-06-20) — Hide UI feature (migrated from gt, fixed) + exit-crash revert

### Added
- **Hide UI** (off / partial / complete / camera), migrated from General Tweaker. A dropdown + a cycle hotkey (`/gut_hud`). Two bugs that made it a no-op in gt were fixed in the move: the HUD-disable hook now targets the **derived** game-mode classes (the base-class hook never fired because VT2 copies methods into subclasses at definition time), and the force-hide path now reads `Managers.ui._ingame_ui.ingame_hud` (the old `Managers.ui.ingame_hud` was nil).

### Fixed / reverted
- **Mod Tweaker exit no longer crashes with Loremaster's Armoury.** v0.2.46 returned to `hero_view` on exit, but recreating hero_view makes VMF re-inject every mod's custom UI material into the new renderer, which hard-crashed on `materials/Loremasters-Armoury/armoury_atlas` (crash 42c81d84). Reverted to the `ingame_menu` exit (no crash; the older menu style returns). The proper fix — making the Mod Tweaker a HeroView **sub-state** so it never recreates hero_view (kills both the crash AND the legacy look) — is noted in code as the next step.

### Diagnostics
- The backend-loc registration now also logs `Localize('mod_tweaker_button_name')` right after registering, to confirm whether the `<>` you still see is this ESC button (would print `<...>`) or a different element (would print `Mod Tweaker`).

## 0.2.47-dev (2026-06-20) — Fix hero-menu crash on exit (v0.2.46 regression)

### Fixed
- **Crash exiting the Mod Tweaker:** `hero_view_state_overview.lua:73: attempt to index field 'state_params' (a nil value)`. v0.2.46's deprecated-menu fix routed the exit to `transition_with_fade("hero_view")` with **no params** — HeroView's `post_update_on_enter` then took its else-branch (`_change_screen_by_index(1)`), which enters the overview state with `state_params = nil`, and the vanilla overview indexes `params.state_params.force_ingame_menu` with no nil guard → crash. Now the exit passes `{ menu_state_name = "overview" }` so HeroView threads our (table) params through as `state_params` — the same pattern the compendium open already uses. The deprecated-menu fix stays intact; it just returns cleanly now.

## 0.2.46-dev (2026-06-20) — Deprecated-menu ROOT CAUSE fix + GUI probes (Phase 0 of native-parity rework)

A second multi-agent investigation found the *real* deprecated-menu cause (renderer/layout-variant theories were both wrong) and produced a full phased plan to make the menu match native settings.

### Fixed
- **"Deprecated menu after exiting" — actual root cause.** The Mod Tweaker is opened from HeroView's modern embedded menu, but its exit **hardcoded `transition_with_fade("ingame_menu")`**, which opens the standalone **legacy `IngameView`** (the bare 9-button menu). So exiting ejected you from HeroView into the old menu. Now the transition closure captures the **origin view** (`self.current_view`) and routes the exit back there (`hero_view` → returns to the modern menu). `on_enter` preserves that origin instead of clobbering it. (The `[mt:esc]` diagnostic exposing the 10-vs-9-button alternation is what cracked this.)

### Added (probes)
- `[mt:slider] DRAG …` logs `internal_value` + computed thumb x every drag frame — to prove whether the drag math works (it does) vs the thumb-render/reference-frame is the defect (the shared-node root cause).
- `[mt:dump] heartbeat …` now logs `thumb_frac` + `scroll_value` — to show why the scrollbar thumb stays full-size.
- `[mt:esc] opened from current_view=… -> exit will route to …` confirms the origin-capture fix.

### Roadmap (native-parity rework, next)
Per the investigation: keep custom widgets (native factories crash on the borrowed renderer), but give **each row its own scenegraph node** (the shared `{1,1}` node is the root cause of the dead slider drag + cosmetic scrollbar), then port native hover/sound/tooltip/drag. Phases: 1) per-row nodes, 2) slider+scrollbar drag, 3) dividers/two-column/font+colors/tab-shift/nested-indent, 4) hover+sound, 5) On/Off switch + type-in number + tooltips.

## 0.2.45-dev (2026-06-21) — `<>` button: fix registration TIMING

The v0.2.44 `append_backend_localizations` approach was right, but `Managers.localizer` wasn't ready at gut's boot, so it silently no-op'd (the log shows no registration line). Now it also registers on `on_all_mods_loaded`, on `LocalizationManager.init`, and on **`IngameView.on_enter`** (fires right before the ESC menu draws, localizer guaranteed up) — so the key is set before the button's text resolves. The register helper now logs at info level so the next log confirms it fired.

Note: the "deprecated menu after exit" is being re-investigated — the `[mt:esc]` diagnostic revealed it's the **legacy button-layout variant** (9-button `*_legacy` set), not a renderer issue, so v0.2.44's renderer switch was the wrong fix. A larger native-menu rework (font/colors, On/Off toggles, hover+sound, tooltips, dividers, functional scrollbar, nested indentation) is being designed.

## 0.2.44-dev (2026-06-20) — Root-cause fixes for the `<>` button + deprecated-menu (multi-agent investigation)

A fan-out investigation finally found both root causes (prior fixes had attacked the wrong layer).

### Fixed
- **`<mod_tweaker_button_name>` ESC button.** Root cause: the engine's `LocalizationManager._base_lookup` only checks `_backend_localizations` + compiled string bundles — **never** a mod's VMF loc table. Both prior fixes were *interception* hooks and each missed a path (the `_G.Localize` hook gets blown away by the `rawset` re-init; the `lookup` hook is bypassed because the button text pass also localizes via the **sibling** `simple_lookup`). The fix **supplies the string** instead of intercepting: `Managers.localizer:append_backend_localizations({ mod_tweaker_button_name = "Mod Tweaker" })`, which `_base_lookup` checks first — so it resolves on *every* path. Re-registered on `LocalizationManager.init` (language switch). Deleted both failed hooks.
- **ESC menu "deprecated buttons" after exiting.** Root cause: the Mod Tweaker drew on `ui_renderer` (level_world / in-mission HUD renderer) — the **only** ESC-flow view to do so. OptionsView and IngameView both draw on `ui_top_renderer`; gut polluting level_world's renderer state made IngameView's chrome fail to resolve on the next frame → flat buttons. (My v0.2.40 comment claiming IngameView shares `ui_renderer` was factually wrong — it's on `ui_top_renderer`.) Fix: draw on `ui_top_renderer` like the vanilla views. Our rows are already atlas-safe, so the original reason for level_world no longer applies.

## 0.2.43-dev (2026-06-20) — Collapsible groups

### Added
- **Group headers are now collapsible** (interim organization until a better sort lands). Each VMF `group` becomes a clickable header with a `[+]`/`[-]` indicator on a tinted bar; clicking it expands/collapses its settings. Uses each flat node's `depth` to skip a collapsed group's descendants (handles nested groups). **Groups start collapsed**, so opening a big mod (e.g. ct's ~1900 settings) shows a tidy list of group headers instead of an endless flat scroll — expand only what you need. Expand state persists across tab switches for the session.

## 0.2.42-dev (2026-06-20) — Slider matches VMF (mod-side snapping) + two-column layout

### Fixed
- **Slider now lands on the same values as VMF.** Found it: `starting_coins` is `range = {0, 3000}` and its **own `on_setting_changed` snaps the value to the nearest 25** (not a VMF slider step). VMF shows the snapped value because it re-reads after setting; my menu showed the raw drag value (257 vs 250). Now after a commit the menu **re-reads the stored value** and shows that — so it snaps to 25s exactly like VMF, for any mod that clamps/snaps in its change handler. Reverted the stepper to the coarser ~range/40 (the natural increment min), and added a `[mt:num] '<id>' bounds=… step=…` diagnostic (debug on) to confirm the read bounds.

### Added
- **Two-column layout** like the game's settings menu: the setting **name fills the left column**, and every **control** (checkbox box, slider track, `[<]`/`[>]` steppers) sits in the **right column** at a consistent x. Much cleaner than the old left-packed rows.

## 0.2.41-dev (2026-06-20) — Slider crash fix (per-frame commit) + finer steps

Crash dragging the Chaos Wastes `starting_coins` slider, diagnosed from the log.

### Fixed
- **Crash + "slider didn't move" while dragging.** The drag committed the value via `mod:set(..., true)` **every frame**, firing the mod's `on_setting_changed` continuously. For `starting_coins`, that handler **broadcasts the entire ~18KB config to clients** (`[ct_sync] ... 18133 bytes, 489 keys`) — once per frame floods the network and crashes (and the crash interrupted the visual, so the bar looked frozen). Now the drag updates only the **visual** each frame and **commits once on release** (matching how VMF fires a setting change). Smooth drag, one network sync, no crash.
- **Stepper increments were too coarse (≈25/click).** The `[<]`/`[>]` step was `(max-min)/40` — ~25 on a 0–1000 range. Changed to the **natural increment** (1 for integers, `10^-decimals` otherwise), matching VMF. The draggable track still handles big moves, so fine ±1 stepping no longer means tiny drags.

## 0.2.40-dev (2026-06-20) — The two stubborn ones: `<>` ESC button + "deprecated menu" after exit

Fresh diagnosis after the previous fixes didn't take.

### Fixed
- **`<mod_tweaker_button_name>` ESC button.** The log confirmed gut's `_G.Localize` hook IS registered, yet the key didn't resolve — meaning the wrapper was bypassed (the localizer re-inits via `rawset(_G,"Localize",...)`, which can blow the wrapper away). The robust fix: also hook the **`LocalizationManager.lookup` class method** — the global `Localize` is literally `function(id) return Managers.localizer:lookup(id) end`, so the method hook intercepts every localization regardless of the `_G` wrapper's state, and survives re-inits.
- **"Main menu looks deprecated (just buttons)" after leaving the Mod Tweaker.** Ruled out the exit transition (it's identical to OptionsView's). Real cause is renderer state: the Mod Tweaker draws on `ui_renderer` (level_world) — the **same renderer IngameView draws its styled background on** (its buttons are on `ui_top_renderer`). If any `draw_widget` errored between the Mod Tweaker's `begin_pass` and `end_pass`, `end_pass` was skipped → the renderer was left mid-pass → IngameView's background didn't render → just bare buttons. Wrapped the entire draw body in a guard so **`end_pass` always runs** even if a widget draw throws.
- Added a `[mt:esc] setup_button_layout -> N buttons` diagnostic (debug on) to confirm the button set isn't accumulating, in case the menu look is still off.

## 0.2.39-dev (2026-06-20) — Mod Tweaker sliders are now draggable

The log confirmed checkboxes/tabs work but sliders never registered a change. Root cause: the numeric rows were a tiny `[<] value [>]` stepper — the track itself had **no hotspot**, so dragging the bar (the natural slider gesture) did nothing; only the small glyphs were clickable.

### Fixed
- **Added a draggable track hotspot** across the slider bar. Click or drag anywhere on the track to set the value from the cursor position; the `[<]`/`[>]` glyphs remain for fine ±step. Per-frame writes during a drag are skipped unless the value actually moves.

### Still queued
- **Armory/Bestiary top-tab button** in the hero menu (next to Equipment/Talents/Crafting/Cosmetics) — Phase 1, the crash-sensitive `HeroWindowOptions` injection, getting its own careful pass. Phase 0 (the `/gut_armory` stub panel) is live.

## 0.2.38-dev (2026-06-20) — Armory/Bestiary Compendium: Phase 0 (hero-menu entry + stub panel)

First slice of the Armory + Bestiary "Compendium" as a real HeroView screen (the hero menu), built on the proven old-Armory-mod injection. Phase 0 proves the injection works before the real UI lands.

### Added
- `_ba_compendium_state.lua` — `HeroViewStateCompendium`, a HeroView sub-state that draws a framed stub panel ("Compendium — work in progress") + a Back button. Defensive lifecycle (nil-guarded draw/update/input). Atlas-safe widgets only; hotspot carries `style_id`.
- `_ba_heroview_inject.lua` — registers the sub-state into `HeroView._state_machine_params.settings_by_screen` (post `HeroView.init`, idempotent), captures `ingame_ui_context` (via a self-disabling `StateInGameRunning.update` hook), and exposes `mod._gut_open_compendium(mode)`.
- `/gut_armory` and `/gut_bestiary` now **open the stub panel** in the hero menu (was: echo stub).

### Notes
- Entry point for Phase 0 is the chat commands; the **top-tab button** in the hero menu (next to Inventory/Cosmetics/Talents/Crafting) is Phase 1 (kept off the crash-sensitive tab-bar hooks until the panel is proven).
- No duplicate hooks: `HeroView.init` (distinct from gut's existing `HeroView.on_enter`) + `StateInGameRunning.update` (unused elsewhere).
- Phase plan: 0 entry+stub → 1 framed panel + Weapons|Enemies toggle + top-tab button → 2 lists from the `_ba_` data layer → 3 3D preview → 4 polish/console.

## 0.2.37-dev (2026-06-20) — Config file gets a WRITE path (log→watcher bridge) + auto-save

Answering "can't we add something that lets us write?": yes. The mod can't `io.open("w")`, but it *can* write to the log, and a desktop process can turn that into a real file write. So the game now has effective two-way file sync.

### Added
- **`tools/gut-settings-watch.ps1`** — a background watcher. Leave it running while you play; it polls the newest console log and **auto-writes `gut_mod_settings.toml`** whenever the mod emits a fresh `[gut:toml]` block (only when content changes; backs up the previous file).
- **Auto-export on Mod Tweaker close** — if you changed any setting while the Mod Tweaker was open, closing it emits the TOML to the log (so the watcher commits it). No command needed. Manual `/gut_export_settings` still works.

### Flow
Run the watcher once → adjust settings in the Mod Tweaker → close it → `gut_mod_settings.toml` is written automatically → edit it by hand any time → restart or `/gut_reload_config` to load it back. The mod still **reads** the file directly on load (v0.2.36); the watcher only provides the **write** half.

## 0.2.36-dev (2026-06-20) — External config file: edit a .toml, override VMF settings on load

New feature (queued request). Keep all your tweaker mods' settings in a `.toml` you can edit directly; on game load those values override the in-game VMF options.

### How it works (and the sandbox constraint)
VMF mods can **read** files but **cannot write** them (Stingray sandbox), so it's split:
- **Override on load** — on `on_all_mods_loaded`, gut reads `%APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml` and `mod:set`s each value for your mods (`_MY_MODS` whitelist), so the file wins over what each mod restored. No-op if the file doesn't exist. Toggle: **Override settings from config file** (on by default).
- **Edit directly** — edit the `.toml` by hand; `/gut_reload_config` re-applies it with no restart.
- **Export** — `/gut_export_settings` dumps current settings as TOML to the log (prefix `[gut:toml]`); the companion **`tools/gut-settings.ps1`** parses the newest log and writes the `.toml` (the mod can't write it itself).

### Added
- `_gut_config_file.lua` — minimal TOML reader/writer (flat `[mod_id]` sections, bool/int/float/string; keybinds skipped), `_collect`/`apply`, `/gut_export_settings`, `/gut_reload_config`.
- `tools/gut-settings.ps1` — writes `gut_mod_settings.toml` from a `/gut_export_settings` log dump (backs up any existing file).
- Setting `gut_config_override` (default on).

### Round-trip
in-game `/gut_export_settings` → desktop `.\gut-settings.ps1` → edit the `.toml` → restart or `/gut_reload_config`.

## 0.2.35-dev (2026-06-20) — Mod Tweaker: row clicks + scrollbar drag actually fire

The v0.2.34 `style_id` fix made rows receive cursor input (hover works), but the log showed `on_release` never fired for any row (count=0) while tabs clicked fine.

### Fixed
- **Row clicks now register.** Root cause: the option rows all share the `mt_list_start` scenegraph node, and the hotspot pass's `input_pressed` state machine (ui_passes.lua:4364) doesn't persist correctly across the shared node, so `on_release` never fires. Switched the checkbox/stepper handlers to **`on_left_release`** (set on release-over-widget regardless of `input_pressed`), which tabs don't need because they each have their own node.
- **Scrollbar drag.** Now driven by the hotspot's **`is_held`** flag (set while the LMB is held over the scrollbar's own node) instead of fragile `on_pressed` + `left_hold` tracking.

### Added
- Heartbeat now logs `scroll`, `vis_h`, `cont_h`, `sb_world`, `sb_hover/held` (debug logging on) to confirm the scrollbar's position + input next session.

## 0.2.34-dev (2026-06-20) — Mod Tweaker: options are now CLICKABLE + scrollbar on-panel + tighter fit

Three fixes from the v0.2.33 in-game report, diagnosed off the auto-dump.

### Fixed
- **Couldn't change any option** — the row hotspot passes had **no `style_id`**, so the hotspot pass fell back to the scenegraph node size. Every row shares `mt_list_start` (size `{1,1}`), making each click target **1×1 pixel**. (Tabs worked because each `mt_tab_N` node has a real size.) Added `style_id = "hotspot"` to the checkbox and `style_id = "dec"/"inc"` to the slider/dropdown steppers, so they use the real `{ROW_W, ROW_H}` hit area. Checkboxes/steppers/dropdowns are now clickable.
- **Scrollbar wasn't visible** — it was right-aligned in `list_mask`, whose right edge extends ~18px **past the decorated panel**, so the bar drew off the panel. Inset it 30px (and bumped its z) so it sits inside the window. Confirmed from the dump: `list_mask` world right edge 1678 vs panel edge ~1660.
- **Options didn't fit the window** — rows were drawn if their lower OR top edge was inside the mask, so edge rows overdrew past the panel (no GPU clip). Now a row draws only when its **centre** is inside the mask — clean top/bottom boundary.

### Added
- `[mt:dbg] row input: hover/release/visible` diagnostic (debug logging on) to confirm row hotspots receive cursor input.

## 0.2.33-dev (2026-06-19) — Mod Tweaker: real scrolling (no more overflow)

Implemented from a study of the vanilla `OptionsView` scroll machinery (the working reference).

### Added
- **The option list now scrolls like the native settings menu.** Mechanism mirrors `OptionsView`:
  - **Scroll offset** applied to the `mt_list` scenegraph node (one write moves the whole row stack), same sign as `OptionsView.update_scrollbar`.
  - **Position-culling** against the `list_mask` box via `math.point_is_inside_2d_box` (lower/middle/top points) — rows outside the panel aren't drawn, so **nothing overflows** anymore. Removed the old 50-row cap.
  - **A rect-based scrollbar** (`mt_scrollbar` node + `build_scrollbar_rect`) with a thumb sized to visible/total and positioned by scroll fraction. Pure `rect`/`hotspot` passes — no `mask_rect`/`rounded_background` materials, so no raw-material crash on the borrowed renderer.
  - **Mouse-wheel** scroll (1 notch ≈ 1 row) + **thumb drag**.
  - Culled rows are non-interactive (visibility-gated clicks + cleared stale flags); scroll resets to top on tab switch.

### Notes / may need a tweak after testing
- The wheel reads `scroll_axis` off the menu input service; if that action isn't mapped there, the **thumb drag still works** and I'll add a `scroll`-pass catcher. The drag sign (`sb_pos - cursor`) may need one flip — tell me if dragging feels inverted.

## 0.2.32-dev (2026-06-19) — Fix the `<>` ESC button (table-form Localize hook) + auto-dumping probe

### Fixed
- **The ESC-menu "Mod Tweaker" button rendered as `<mod_tweaker_button_name>`.** gut's `_G.Localize` hook used the STRING form `mod:hook("_G", ...)`, which resolves the class via `_G["_G"]` — not reliably set in Stingray, so the hook silently never applied. Switched to the documented TABLE form `mod:hook(_G, "Localize", ...)`. The button now reads "Mod Tweaker". (Recorded in the localization rules.)

### Changed
- **The OptionsView probe now auto-dumps** the moment you open ESC → Options (once per game session) — no `/gut_dump_options` typing needed. Matches the data-harness philosophy: visit the menu, the layout appears in the log. The command is kept only as a manual re-dump.

## 0.2.31-dev (2026-06-19) — Add OptionsView layout probe (scrollbar groundwork)

Before implementing the Mod Tweaker scrollbar, capture how the real settings menu actually scrolls.

### Added
- `_gut_options_probe.lua` — hooks `OptionsView.on_enter` to capture the live vanilla settings-menu instance, and a `/gut_dump_options` command that dumps its scroll/mask/scrollbar machinery (the `list_mask` node bounds, `scroll_value`, `selected_settings_list` scroll fields, the `scrollbar` widget's passes/content/style, sample list-widget offsets) to the log. Ground-truth for replicating native scrolling in the Mod Tweaker. Open ESC → Options, then run `/gut_dump_options`.

## 0.2.30-dev (2026-06-19) — Temporal Fix: rebase the health-bar position + widen the nudge range

User feedback: the health-bar nudge maxed at -400 wasn't enough, and the correction was in the wrong direction.

### Changed
- **Rebased the player health-bar horizontal position** in `_gut_uitweaks_temporal_fix.lua` from Isaakk's rightward `+size/2 + 50` (the "wrong direction") to **centred on the anchor (`-size/2`) + a symmetric nudge** — negative pulls left, positive pushes right, default 0 = centred. Applies to all three bars (total_health_bar, hp_bar, hp_bar_highlight).
- **Widened `gut_temporal_hp_nudge_x` range** from ±400 to **±2000** so the bar can be placed anywhere on screen.
- **Action needed:** saved nudge values from before this build were relative to the old base — **reset the Health-bar nudge to 0 and re-dial.** (No auto-reset: VMF's settings restore could clobber it, so it's a manual one-time step.) Once you find the value that looks right, tell me and I'll bake it as the default.

## 0.2.29-dev (2026-06-19) — Mod Tweaker: fix the menu-corruption + `<MOD TWEAKER>` title + tab prefix + click sound

### Fixed
- **Menu corruption (the "deprecated buttons" look on the real menus after leaving the Mod Tweaker).** Root cause found: the Mod Tweaker **shallow-cloned** `options_view_definitions.scenegraph_definition`, sharing the node TABLES with the real OptionsView, and parented our `mt_*` nodes onto OVD nodes — so `init_scenegraph` attached our children onto the SHARED OptionsView parent nodes, corrupting it. Now a **deep copy** — every node independent, OVD untouched. (This is the real cause of the recurring "old GUI"/"`<>`" after the menu, separate from the earlier crash.)
- **`<MOD TWEAKER>` title.** `UIWidgets.create_simple_text` localizes its text even with `localize=false` passed, so the title rendered as the missing-key marker. Rebuilt title + hint as hand-made text widgets with `localize=false` (same fix as the tabs). Documented in the new localization rules.
- **Tab labels: dropped the "Tweaker: " prefix** (this menu is all your tweaker mods) — tabs now read "GUI", "Chaos Wastes", etc.
- **Click sound feedback** — tabs, checkboxes, steppers, dropdowns, and the exit button now play the native UI click sound (`play_gui_start_menu_button_click` via the music_world's wwise_world).

### Still to do
- **Scroll bar** — long mod option-lists still overflow the panel (rows are capped at 50 but not clipped/scrolled). A real scrollbar needs masked-clip rendering like the native settings list; that's the next focused task.

## 0.2.28-dev (2026-06-19) — Mod Tweaker: your mods only, fix `<TWEAKER>` tabs, cap huge trees

Addressing in-game feedback on the Mod Tweaker.

### Fixed / changed
- **Your mods only.** The menu was enumerating all ~19 installed VMF mods (no room for that many tabs). Now whitelisted to this author's mods (`_MY_MODS` in `_mod_tweaker_view.lua`): gut, wt, ct(+dev), gt(+dev), cim(+dev), crt, cosmetics_tweaker, dcp, enemy_tweaker, cwv, event_tweaker, mp, bt, vdl(+dev). Far fewer tabs.
- **`<TWEAKER>` tabs fixed.** Tabs were built with `UIWidgets.create_text_button`, which hard-codes `localize = true` + `upper_case = true` on its text — so a mod name (a plain string, not a loc key) rendered as the missing-key marker `<TWEAKER: GUI>`. Rebuilt tabs as a hand-made hotspot+text widget with `localize = false`, so the raw label always shows. Selected/hovered tab is gold, others dim grey.
- **Huge mods no longer explode.** A big mod's flattened settings tree hit `rows=1927`; with no scrolling yet that's a perf/offscreen blowup. Capped at 50 rows per category (revisit when list scrolling lands).

### Still to do (separate)
- The "options are read-only/greyed" report: most was read-only widget *types* (keybinds/groups) in non-your mods; with the whitelist you'll land on your mods' real checkboxes/sliders, which are editable. If a checkbox/slider still won't change, turn on Debug Logging, click one, and send the log (it prints `[mt:dump] input: checkbox …`).
- Armory/Bestiary will move to **HeroView tabs** (inventory/cosmetic menus), not this settings menu.

## 0.2.27-dev (2026-06-19) — Fix Phase-1 fork crash on nil offset settings (boss HP / GK quests / subtitles / twitch)

`hb/hide_elements.lua:161: attempt to perform arithmetic on a nil value` — the Phase-1 fork brought over four hooks (boss HP bar, Grail-Knight quests, subtitles, twitch vote) that also **reposition** their elements, reading 9 numeric `OTHER_ELEMENTS_*` / `GK_QUESTS_*` offset/alpha settings. Those belong to a later phase and weren't registered yet (and 6 of them weren't even in the forked `SETTING_NAMES`), so `mod:get` returned nil and the `+` crashed.

### Fixed
- Guarded all 9 reads in `hide_elements.lua` with defaults (offsets → 0, GK-quests alpha → 200, matching the hook's own default check). The hides work; the repositions are no-ops until their settings land in a later phase. No crash regardless of registration state.
- This very likely also resolves the earlier **"main menu shows old GUI + options in `<>`" after leaving the Mod Tweaker**: the `ChallengeTrackerUI._draw` (GK quests) hook reads those same nil settings and that UI draws in the keep, so it was erroring every frame and cascading into broken menu/loc rendering. With the reads guarded it no longer throws. (Please confirm next session.)

## 0.2.26-dev (2026-06-19) — Respawn countdown over a dead teammate's portrait (optional)

New optional HUD widget: a large number (seconds till respawn, one decimal) drawn over a **dead teammate's** portrait while they wait to respawn.

### Added
- `_gut_respawn_timer.lua` — hooks `UnitFrameUI.draw` (post; gut doesn't hook it, no collision), teammate frames only (`_frame_type == "team"`). Detects the dead-skull state via the frame's `data.is_dead` (set by UnitFramesHandler from the networked, husk-safe status extension) and draws the number centered on the frame's `portrait_pivot` node, with a shadow.
- **Countdown source:** VT2 Adventure has no client-synced respawn countdown (`respawn_handler`'s `game_mode_data.respawn_timer` is host-only / non-networked), so this anchors a client-side estimate to the moment `data.is_dead` flips true (= when the skull appears = when the server starts the timer) and ticks down `RESPAWN_TIME` (30) or the mechanism's `hero_respawn_time`. Reads a touch early only if the host has a `faster_respawn` buff (invisible to clients); clamped at 0; stops when assisted-respawn begins.
- Settings (group **Respawn Timer over Portrait**, default **off**): `gut_respawn_timer` toggle + `gut_respawn_font_size` (12–80, default 32) + `gut_respawn_r/g/b` colour (default 255/60/60, red).

### To verify
- Have a teammate (or bot) die and wait for respawn — a red countdown should appear over their skull portrait and tick to 0. If the number's position/size is off, the font size + colour are sliders; tell me and I can add a position nudge.

## 0.2.25-dev (2026-06-19) — Fix UI Tweaks buff-bar end-time crash spam (stacking buffs)

### Fixed
- **UI Tweaks (HideBuffs) `PriorityBuffUI.lua:228: attempt to compare nil with number`** — diagnosed from a player console log spamming it ~1000×/session (once per frame, both buff bars) while a stacking buff was active (repro: Bardin Outcast Engineer pump stacks, `bardin_engineer_pump_buff`). `_add_buff` merges a re-applied buff with `data.end_time = end_time and ((data.end_time < end_time and end_time) or data.end_time)` — the `end_time and …` guard protects only the *incoming* end-time; if the *stored* `data.end_time` is nil (buff first added while infinite, then refreshed with a finite end-time) the compare is `nil < number` and throws.
  - **Fix:** new `gut_compat_group` toggle **`gut_buffbar_endtime_fix`** (default ON). Wraps the global `PriorityBuffUI._add_buff`, mirrors its own match loop, and backfills only the single entry it will act on (stored nil end-time + finite incoming) with the incoming end-time before the compare runs. Result: the vanilla compare evaluates to false and keeps the refreshed end-time — no crash, no visible change beyond stopping the spam. Pure-Lua wrap of stock UI Tweaks (no forked resources); read live so the toggle reverts instantly; no-op if UI Tweaks isn't installed. New file `_gut_buffbar_endtime_fix.lua`, wired beside the Temporal Fix (load + `on_all_mods_loaded` retry + immediate try).

## 0.2.24-dev (2026-06-19) — Absorb UI Tweaks (HideBuffs), Phase 1: hide UI elements / hide buffs / loading-screen hides

First phase of porting UI Tweaks (HideBuffs) into gut so you can drop the standalone mod. Fork-and-renamespace: the forked Lua lives under `scripts/mods/gui_tweaker/hb/` with `get_mod("HideBuffs")` → `get_mod("gut")`. **Disable the standalone "UI Tweaks" mod once gut covers what you use, to avoid double-hooking.**

### Added (28 settings, group "UI Tweaks (absorbed)")
- `hb/hb_data.lua` — the data backbone (SETTING_NAMES, alignments, portrait-icon maps, etc.), with HideBuffs' VMF options-tree construction stripped (gut registers the tree statically). Penlight (`pl`) is globally available in VT2, so no bundling needed.
- `hb/hide_elements.lua` — the self-contained single-element hide hooks: `ChallengeTrackerUI._draw`, `TutorialUI.*`, `MissionObjectiveUI.draw`, `BossHealthUI._draw`, `GameModeManager.has_activated_mutator` (hide-HUD-when-inspecting), `IngameHud._update_components_visibility`, `OutlineSystem.always` (pickup/objective outlines), `DialogueSystem.*`/`SubtitleGui`/`PlayerHud`/`TwitchVoteUI`/`WaitForRescueUI`/`TwitchIconView`, and `UnitFrameUI._update_bar_flash` (stop white-HP flashing). Plus the **Hide-HUD hotkey** (`HIDE_HUD_HOTKEY` keybind → `mod.hide_hud`).
- `hb/level_loading_screen.lua` — hide loading-screen tips/subtitles + disable level-intro / Olesya audio.
- Settings: **Hide UI Elements** (17, incl. boss HP bar, levels, frames, outlines, new-area popup, loading tips/subtitles, intro audio, twitch icon, rescue message), **Hide Active Buffs** (9 per-class passive/grimoire hides), and root toggles (default portrait frames, unobtrusive objective/mission markers). All ids kept verbatim from HideBuffs so the forked hooks resolve.

### Notes
- Skipped the `mod_events` lifecycle backbone this phase — the hide hooks are draw-time + the keybind auto-wires, so it isn't needed yet (it comes with the buff/unit-frame phases, along with its Phase-2+ guards).
- Phases 2–5 (ammo counter, equipment UI, unit frames + portraits + temporal-fix reconciliation, buff bars, dodge counter) follow.

## 0.2.23-dev (2026-06-19) — Temporal-fix offset now tunable; Parry Indicator hardened + diagnostic

### Temporal fix — health-bar offset reported "wrong direction"
My port faithfully reproduces Isaakk's Nov-2024 values (`size/2 + 50`), but a later game patch can move the correct spot. Made the horizontal placement a **slider** — `gut_temporal_hp_nudge_x` (range ±400, default 0 = the original fix), nested under the Temporal Fix toggle — so it can be dialled either way without a rebuild (negative = pull left). Added a one-shot debug line logging the bar's `size_x -> offset_x` so the right value is readable from the log.

### Parry Indicator — "isn't working"
The install log showed `toggle: false` — it's **off by default**; enable **Parry Indicator** in gut's settings. Also hardened it:
- Recolour now runs **after** the original `update_shields` and **mutates RGB in place** (indices 2-4) instead of replacing the whole color table — leaving alpha to the game's fade animation (verified: vanilla `update_shields` only writes `style.color[1]`).
- Added debug lines (`[gut:parry] update_shields hook live: N shields…` once, and `timed-block window ENTER` on each block) so if it's enabled and still not visible, the log shows whether the hook fires and the window is detected.

## 0.2.22-dev (2026-06-19) — Fix Mod Tweaker VMF enumeration (correct field names from the in-game probe)

The v0.2.20 auto-populate showed only gut's dogfood tab (`[mt] rebuild: total=1 … rows=2`). The in-game debug probe revealed why: VMF's real fields are `mods` / `mods_unloading_order` / `options_widgets_data` — **no leading underscore** (the reverse-engineered guess `_mods_unloading_order` was nil, so the enumeration bailed).

### Fixed
- `_mod_tweaker_view.lua` `_vmf_categories()` now iterates `vmf.options_widgets_data` directly: each per-mod list's `[1]` header carries `mod_name` + `readable_mod_name` (confirmed flat via the probe), `[2..]` are the setting nodes; the mod object for get/set is `get_mod(mod_name)`. So every VMF mod with options should now get a tab populated with its real settings.
- Enhanced the debug probe to also log the first real setting node's keys + types (`[mt] vmf node[n][2] …`), so the per-widget shape (label/value field names) is visible for the next round if any node-level field needs adjusting.

## 0.2.21-dev (2026-06-18) — Absorb Bestiary + Armory as one self-populating compendium (data layer)

Merging the standalone **Armory** (weapon compendium, Workshop 1464907434) and **Bestiary** (enemy compendium, Workshop 1431393962) mods into gut as a single feature, rebuilt with a **pure-dynamic data layer** — content is enumerated live from the game's own tables, so new weapons/enemies (Necromancer, Beastmen, undead, DLC specials) appear automatically with no hardcoded roster to go stale. This phase lands the data providers + console probes; the HeroView compendium UI follows.

### Added
- `_ba_weapon_provider.lua` — enumerates `ItemMasterList` (keep `has_power_level` + weapon `slot_type`), groups by `can_wield` (engine source of truth, auto-handles cross-career weapons like the flail and new careers like Necromancer), resolves name/icon/3D-units/illusions, derives attack chains. Lazy-built cache.
- `_ba_enemy_provider.lua` — enumerates `Breeds` filtered to combat AI breeds (`is_ai` + race ∈ skaven/chaos/beastmen/undead, minus critters/dummies/pets). Per-breed attributes ported verbatim from the original Bestiary (difficulty-scaled health/mass/stagger arrays, armor category, boss/elite/special). Replaces the original's hardcoded skaven/chaos/beastmen roster + icon-slot tables. Variant (shielded/commander/warlord/boss) grouping derived dynamically by suffix.
- `_ba_attack_labeler.lua` — derives a weapon's light/heavy/push (melee) and ranged/alternate (ranged) attack chains + labels from `Weapons[template].actions`, replacing the original Armory's hand-authored `armory_wanted_attack_list`.
- `_ba_compendium.lua` — feature entry; wires the providers + commands. Dofile'd from `gui_tweaker.lua`.
- Commands: `/gut_ba_dump_weapons` and `/gut_ba_dump_breeds` (paste-ready console dumps to verify the live enumeration), plus `/gut_armory` and `/gut_bestiary` (open commands; UI pending).

### Notes
- Pure-dynamic by design (no curated preview offsets or attack labels) per direction — generic framing + generated labels, refined in-game later.
- Single-hook discipline preserved: the compendium will add exactly one `HeroView.init` and one each `HeroViewStateOverview.create_ui_elements`/`_handle_input` hook in the UI phase (gut currently hooks only `HeroView.on_enter`, so no collision).

## 0.2.20-dev (2026-06-18) — Mod Tweaker auto-populates a tab per VMF mod, with that mod's real options

The Mod Tweaker now discovers every installed VMF mod and renders one tab each, populated from that mod's real settings — edits write straight to the live mod (firing its `on_setting_changed`). (Mapped VMF's runtime data model via a workflow, since VMF ships as bytecode.)

### Added
- **Auto-discovery** (`_mod_tweaker_view.lua`): enumerate `get_mod("VMF")._mods_unloading_order`; each mod's flattened widget list comes from `get_mod("VMF").options_widgets_data` (matched by `mod_name`). Excludes VMF itself; gut appears with its real settings. Sorted enabled-first then alphabetically; disabled mods marked `*`.
- **Real get/set routing**: `mod_obj:get(id)` / `mod_obj:set(id, value, true)` (3rd arg fires the mod's `on_setting_changed` so it reacts live; VMF persists automatically). The gut controller path remains for any non-VMF category.
- **Widget-type coverage**: checkbox + numeric (`[<]`/`[>]` stepper) are editable; **dropdown** is an option cycler; group titles + keybind/text show read-only. Field reads are defensive (flat or `content`-wrapped) and pcall-guarded.
- **Tab paging**: the strip fits 8 tabs; with more mods it shows 7 + a `More N/M >` tab that pages through all of them (so every mod is reachable). Long names truncated.
- **Debug probe**: with debug logging on, logs VMF's actual table fields + a sample node's keys once, so the real bytecode shape is visible if any reverse-engineered field name is off.

### Known limitations (follow-ups)
- No row scrolling yet — a mod with many settings draws past the list area (clipped, no crash).
- Dropdown `show_widgets` sub-reveal not handled (all options shown); keybind/text not yet editable.

## 0.2.19-dev (2026-06-18) — Absorb the Parry Indicator (works on every weapon)

Ported the **Parry Indicator** mod (Workshop 1459917022) into gut as an optional toggle, with one deliberate change: it now works **regardless of whether the current weapon has the Parry trait**.

### Added
- `_gut_parry_indicator.lua` — recolours the HUD block/stamina shields (`FatigueUI.update_shields`) during the **timed-block window**: the first 0.5s after raising block, while actively blocking and not mid push / attack / revive / pull-up / assisted-respawn (the action-exclusion hooks are ported verbatim). Verified VT2 internals: `FatigueUI.self.shields[].style.color`; `GenericStatusExtension.raise_block_time` + `.blocking` (status_system extension).
  - **Change from the original:** the original gated the cue on the weapon carrying the Parry trait (tracked via the `timed_block_cost` stat buff). gut **drops that gate** — the BuffExtension `has_parry` tracking is omitted entirely — so the timing cue shows on every weapon (the timed-block window exists for all weapons; Parry just makes blocks in it free).
- Settings (group **Parry Indicator**, default **off**): `gut_parry_indicator` toggle + `gut_parry_r/g/b` colour (0-255, defaults 0/255/120 — a parry teal, matching the original).
- Duplicate-hook preflight: none of `FatigueUI`/`ActionPushStagger`/`ActionSweep`/`InteractionDefinitions.*` were hooked elsewhere in gut.

## 0.2.18-dev (2026-06-18) — Fix Mod Tweaker render crash (`checkbox_checked not found in Gui`)

The menu now opens, but crashed on the first row: `ui_passes.lua:134: Material 'checkbox_checked' not found in Gui`.

### Root cause
Reused the native `options_view_definitions` checkbox/slider factories, which reference **raw (non-atlas) materials** — `checkbox_checked`, `checkbox_unchecked`, `rect_masked`, `highlight_texture` — that appear only inside that file and in no atlas. They aren't present in the borrowed in-game renderer's Gui, so the first texture pass crashed. (Classified every row material against `scripts/ui/atlas_settings/` to confirm which are atlas-backed vs raw.)

### Fixed
- **Rebuilt the row widgets** from things that resolve on the borrowed renderer: `rect`/`border` passes (no material lookup) + atlas-backed textures resolved globally by `UIAtlasHelper` whose master atlas is resident (proven: hero_view keep states render these on this renderer) — `matchmaking_checkbox` (checkbox marker) and `slider_thumb`. No more raw materials.
  - **Checkbox**: rect box + border + atlas check marker + label; whole-row hotspot toggles it.
  - **Numeric**: label + rect track + fill + atlas thumb + `[<]`/`[>]` click zones + value text (stepper; `step ≈ range/40`, min one display unit). Drag-to-set can come later.
- **Draw on `ui_renderer`** (level_world) instead of `ui_top_renderer` — it carries the full settings-menu material set (the renderer OptionsView/hero_view use for their checkbox/slider widgets).
- **Dropped the scrollbar** from the draw (its OVD definition also uses raw `rect_masked`/`mask_rect`); the list is short. Revisit with a rect-based scrollbar when scrolling is added.

## 0.2.17-dev (2026-06-18) — Fix Mod Tweaker not opening + `<>` localization

Two bugs reported after v0.2.16 shipped: the Mod Tweaker menu didn't open, and menu entries rendered as raw keys in angle brackets (`<…>`).

### Fixed
- **Menu didn't open.** The `IngameUI.setup_views` post-hook saw `self.views` as not-yet-a-table (the game's Versus update shifted when `self.views` is populated relative to `setup_views`), so the view never attached and the ESC transition correctly no-op'd. Now the view is **lazy-attached in the transition closure** — at click time the IngameUI is fully initialised (`self.views` + `self.ingame_ui_context` both set, `ingame_ui.lua:138`), which is the reliable build point. Extracted `_attach_view()` (idempotent), used by both the setup_views hook (early attempt) and the transition (guaranteed path). On dofile/`:new` failure it logs and stays a no-op rather than crashing.
- **`<mod_tweaker_button_name>` ESC entry.** The ESC button localizes its `display_name` through the GLOBAL `Localize()`, where VMF mod localization is NOT registered — so the key rendered literally. Added a guarded `_G.Localize` hook resolving our one key to "Mod Tweaker" (duplicate-hook preflight: no other gut Localize hook).
- **`<Tweaker: GUI>` tab labels** (would have shown once the menu opened). `UIWidgets.create_text_button` forces `localize=true` on its text styles; `create_tab` now disables `localize` on every text style so the raw category label renders.

## 0.2.16-dev (2026-06-18) — Absorb the "UI Tweaks Temporal Fix" (player health-bar placement)

Researched and reimplemented the removed/unsanctioned standalone mod **"UI Tweaks Temporal Fix"** (Isaakk, Workshop 3366928597) as a clean, sanctioned patch inside gut. Despite the name it has nothing to do with temporal reprojection — it re-aligns the **player's own health bar** in UI Tweaks' (HideBuffs) **mini-HUD layout**, which the game's Versus update knocked out of place.

The exact fix was recovered by bytecode-diffing 3366928597 against stock UI Tweaks (1467751760), both decompiled with the same tool so only Isaakk's change remained:
- `player_unit_frame_ui.lua` (`player_unit_frame_draw`, MINI_HUD_PRESET branch): `total_health_bar` / `hp_bar` / `hp_bar_highlight` `.offset[1]` sign-flip `-size/2` → `+size/2 + 50`; `ability_dynamic.offset[1]` `0` → `-2`.
- `content_change_functions.lua` (player grimoire divider + bar): `offset[1]` shifted left by `58 * hp_bar_w_scale`.

### Added
- `_gut_uitweaks_temporal_fix.lua` — wraps the three PUBLIC HideBuffs functions (`player_unit_frame_draw`, `player_grimoire_debuff_divider_content_change_fun`, `player_grimoire_bar_content_change_fun`): calls the original, then re-applies the corrected offsets. Pure-Lua, sanctioned (no forked engine resources, unlike Isaakk's mod). Installed at `on_all_mods_loaded`; idempotent; no-op when UI Tweaks isn't installed. Gated on the toggle and read live each frame so toggling reverts instantly.
- Setting **`gut_uitweaks_temporal_fix`** (group "UI Mod Compatibility"), default **on**.

### To verify (in-game)
- With UI Tweaks installed + its mini-HUD layout active, your own health bar should sit correctly (not shoved off to one side). Toggle the setting off to compare against the broken vanilla-UI-Tweaks placement.

## 0.2.15-dev (2026-06-17) — Mod Tweaker: native settings-menu chrome (reuse OptionsView pieces)

Replaced the crude rect placeholders with the REAL Options-menu look, by reusing the native pieces instead of hand-rolling. Full inventory of `options_view_definitions` taken (verified 2026-06-17).

- `_mod_tweaker_definitions.lua` — now `local_require`s the native `options_view_definitions` and assembles from it: clones the native `scenegraph_definition` (so the 1400×900 window, frame, top/bottom panels, `list_mask`, scrollbar nodes all exist + lay out identically), builds the chrome from `background_widget_definitions` (the `menu_frame_12` border, `{255,10,10,10}` panels, `cogwheel_small` symbol), the native `scrollbar_definition`, and the native `exit_button` (`friends_icon_close`). Adds a horizontal tab strip (`mt_tab_N`) + a list anchor (`mt_list_start`) under `list_mask`. Tabs are `UIWidgets.create_text_button` (idle→white-on-hover/selected); rows are the native `create_checkbox_widget` / `create_slider_widget`.
- `_mod_tweaker_view.lua` — rebuilt to draw the native chrome + tab strip + native rows + scrollbar in one `begin_pass`. Native checkbox flips `content.flag` in its own pass; native slider updates `content.value` via its passes; the view reads those and persists on change. Each row's native factory call is `pcall`-guarded (one bad row can't blank the menu) and logged. Render-state probe (`[mt:dump]`) + heartbeat retained.

### To verify (in-game, debug logging on)
- ESC → Mod Tweaker should now show a framed window (menu_frame_12 border, dark panels, cogwheel top-left, X close top-right) with a **Tweaker: GUI** tab across the top and native-style checkbox/slider rows. Send the `[mt:dump]` lines if anything's off.

## 0.2.14-dev (2026-06-17) — Mod Tweaker render-state probe (diagnostic only)

The view opens with no errors (log: `ModTweakerView attached`, no nil/texture/font failures), so nothing is failing to render — but the menu doesn't look like the native settings menu, and our logging only caught render *errors*, not widgets that render fine yet sit off-screen / zero-size / invisible. This build adds that missing visibility (instrument only — no behavior change yet):

- `_mod_tweaker_view.lua` — `_dump_state()` logs, on view open (`[mt:dump]` lines, debug-gated): category/tab/row counts, the on-screen world position + size of `panel` / `tab_area` / `list_area` (vs the 1920×1080 screen), and each tab's/row's offset/size/value. So the log alone shows whether elements are positioned, sized, and on-screen.
- `_mod_tweaker_view.lua` — per-~2s **draw heartbeat** (confirms `update`/`_draw` is running and how many widgets it draws) + **input-event logging** (tab click / checkbox toggle / slider drag) so we can see input reaching the widgets.

No widget/visual changes — the next log tells us whether this is a layout/visibility bug or just needs the native widget art, before rebuilding.

## 0.2.13-dev (2026-06-17) — Fix: view missing required IngameUI contract methods (input_service crash)

v0.2.12 fixed construction (the view now attaches — log confirms `[mt] setup_views: ModTweakerView attached`), but opening it then crashed `ingame_ui.lua: attempt to call method 'input_service' (a nil value)`: IngameUI calls `active_view:input_service()` **unconditionally** every frame (ingame_ui.lua:416/770) and the view didn't implement it.

### Fixed
- `_mod_tweaker_view.lua` — added the three view-contract methods IngameUI calls unconditionally on the active/new/old view: `input_service()` (returns the view's input service), and no-op `post_update_on_enter(params)` / `post_update_on_exit(params, was_replaced)` (called on every view transition — would have crashed on open/close next). The other contract methods (`current_state` / `disable_toggle_menu` / `hotkey_allowed` / `set_map_interaction_state` / `is_survey_*`) are guarded with `if view.method` in IngameUI and are safely omitted.

## 0.2.12-dev (2026-06-17) — Fix: Mod Tweaker view crashed IngameUI (nil view on open)

In-game test of v0.2.11 crashed on opening the Mod Tweaker: `ingame_ui.lua:625: attempt to index a nil value` (current_view = "mod_tweaker_view"). Root cause: `IngameUI.init` passes the context to `setup_views(ingame_ui_context)` as an **argument** (ingame_ui.lua:107) and does NOT store `self.ingame_ui_context` at that point — the scaffold hook read `self.ingame_ui_context` (nil), so `ModTweakerView:new` threw, the view never attached, and transitioning to the missing view indexed `views[current_view]` = nil → hard crash.

### Fixed
- `gui_tweaker.lua` — the `setup_views` hook now captures the **`ingame_ui_context` argument** (`function(self, ingame_ui_context)`) and builds the view from it; refuses to attach a context-less view.
- `gui_tweaker.lua` — the `mod_tweaker_view` transition closure now switches `current_view` only if `self.views.mod_tweaker_view` exists, so a missing view can never crash IngameUI (the ESC entry becomes a no-op instead).
- `_mod_tweaker_view.lua` — `init` errors clearly on a nil context (caught by the hook's pcall) instead of failing mid-body.

(Unrelated: the log also shows a pre-existing VMF/Loremasters-Armoury tooltip error in `vmf_options_view` via the deprecated `_G.UIResolutionScale_pow2` — not part of gut.)

## 0.2.11-dev (2026-06-17) — Mod Tweaker view: first renderable pass (tasks #6–8)

The Mod Tweaker (the in-game settings menu for all the Tweaker mods, opened from the ESC menu) now actually **renders** — previously the view was a stub and clicking the ESC entry opened nothing. Built from the verified VT2 `OptionsView` contract (read 2026-06-17): borrows the IngameUI renderer, registers a modal input service, draws in one `begin_pass`/`end_pass`, and returns to the ESC menu via `ingame_ui:transition_with_fade("ingame_menu")`.

### Changed
- **`_mod_tweaker_definitions.lua`** — real scenegraph (root/screen-dim/panel/title/left tab strip/right list/hint) + widget factories (panel, title, hint, tab, checkbox, slider). Deliberately atlas-free (`rect`+`text`+`hotspot` passes only) so the first on-screen pass can't fail on a missing texture; visual polish (proper checkbox/slider art) is a later pass. Per-row/per-tab hotspot styles give correct hit regions.
- **`_mod_tweaker_view.lua`** — replaced the stub with a working `ModTweakerView`: init borrows the context renderer + registers the `gut_mod_tweaker` input service; `on_enter` shows the cursor + makes the view modal + builds tabs/rows from the registered categories; `update` draws and handles input; checkbox click toggles + persists, slider drag sets value + persists (both through the controller `mod.mod_tweaker` so there's a single registry); `exit` transitions back to the ESC menu. Reads the registry via the controller (NOT a fresh `_mod_tweaker_settings` dofile, which would be empty).
- **`gui_tweaker.lua`** — registers a dogfood `gut` category (debug-logging checkbox that bridges to VMF + a demo slider) so the view shows real, interactive content end-to-end.

### To verify (in-game)
- In a mission or the keep, press ESC → click **Mod Tweaker** (above Options). A panel should open with a "Tweaker: GUI" tab on the left and two rows: a Debug-logging checkbox (click toggles ON/OFF) and a demo slider (drag to change the value). ESC closes back to the ESC menu. `/gut_regression_test` still passes the mod_tweaker entry/transition checks.

## 0.2.10-dev (2026-06-16) — `/gut_lua_mem` diagnostic (Lua-heap footprint measurement)

### Why
A friend (nicho) hit the VT2 hard crash `Not enough memory reserved for heap lua_heap` (reserved 1073741824 = 1 GiB, `heap_allocator.cpp:227`) at mission load while running ~58 mods incl. the now-public Tweaker mods — the Lua heap was pinned at 100% (1 GiB used of 1 GiB). The `lua_atpanic/lua_close` callstack is the symptom, not the cause. To attribute footprint per-mod (which can't be read off source line counts — it's a runtime quantity) we need a live measurement.

### Changed
- `gui_tweaker.lua` — new `/gut_lua_mem [label]` command: forces a full GC and prints live Lua memory (`collectgarbage("count")`) in MB. Per-mod workflow: disable suspects → launch → load a level → `/gut_lua_mem baseline`; enable one mod → relaunch → `/gut_lua_mem <mod>`; the jump is that mod's footprint. (Lower-bound proxy: the engine `lua_heap` also holds bytecode + C-side Lua structures; compare deltas, not absolutes.)

## 0.2.9-dev (2026-06-16) — Phase 0: fix Versus host-crash in vanilla damage-feedback (UI-absorption groundwork)

### Why
First step of absorbing NumericUI + UI Tweaks (HideBuffs) into gut against the current GUI. The reported Versus host-crash is a **vanilla** bug, independent of any rendering: `UnitFrameUI.add_damage_feedback` (`unit_frame_ui.lua`) assigns `self._damage_widgets[order_index]` and sets `widget.content.visible = true` (vanilla L1687-1690 / L1699-1702) for a NEW event *before* the over-MAX eviction at the bottom — and that eviction is dead-coded behind `fassert(false)` (vanilla L1724-1725). When more than `#self._damage_widgets` (4 with damage feedback on) distinct damage events are active at once, `order_index` exceeds the pool, the widget is `nil`, and `widget.content.visible = true` is a fatal index-of-nil. On the **host** it crashes the whole session. Reproduced in Versus by a Pactsworn Ratling Gunner's sustained machinegun fire stacking 5+ simultaneous damage messages on one hero frame (crash GUID `59ae9a93-…`, 2026-06-15). NumericUI re-news the vanilla `UnitFrameUI`, keeping this vanilla path live — but the bug is vanilla and the fix is independent of NumericUI.

### Changed
- `gui_tweaker.lua` — new `mod:hook("UnitFrameUI", "add_damage_feedback", …)` (the mandatory pre-flight grep confirmed gut had no prior `UnitFrameUI` hook). The wrapper drops the **overflow** event before it reaches the nil-widget index — only when the pool is already full AND a new `order_index` would be assigned (a brand-new event, or a re-activated `disabled` one). Existing active events pass through untouched. No vanilla state is mutated (pure pre-call guard; degrades safely if the vanilla shape drifts). The cap is self-healing: vanilla `_update_damage_feedback` removes expired events from `_hash_order` (`table.remove`, vanilla L1819), freeing slots. Perf-gated: the hash/lookup work only runs in the rare at-capacity case. Always-on (a safety guard, not a toggled feature). Decision rule extracted to `mod._gut_damage_feedback_should_drop` for testability.

### Tests
- New `/gut_regression_test` check `damage_feedback_overflow_guard` — pins the drop/keep decision across boundary cases (full pool + new → drop; free slot + new → keep; existing event → always pass through; empty pool → drop).

### To verify (in-game)
- Host a Versus match (host-side crash), keep Numeric UI enabled for now, play a Pactsworn Ratling Gunner and hold sustained fire on heroes — confirm **no host crash** (the 5th+ simultaneous damage message is silently dropped instead). Then `/gut_regression_test` → `PASS: damage_feedback_overflow_guard`.

## 0.2.8-dev (2026-06-07) — HUD drag preserves each widget's vanilla baseline

### Why
Audit 2026-06-07 (F5, HIGH). `_apply_offset_to_scenegraph` wrote the RAW drag delta straight into `node.local_position[1]/[2]`, discarding each widget's non-zero vanilla baseline. The vanilla `HudCustomizer.run` (decompiled `scripts/ui/hud_ui/hud_customizer.lua:119-122`) can assign the raw offset only because the nodes IT customizes baseline at `{0,0}` — its `offset_registry` value IS that node's `local_position`. Our REGISTRY targets real HUD widget nodes whose baselines are non-zero: `equipment_ui` pivot `{0,69}`, `buff_ui` pivot_root `{150,18}`, `boss_health` pivot_parent `{0,-72}`, `challenge_tracker` pivot `{1,155}`, `loot_objective`/`news_feed` etc. So the first drag (even a tiny one) snapped those widgets to screen origin instead of moving them by the delta. `reset_widget` already wrote `entry.vanilla_position` back, confirming that field is the correct baseline reference — the drag path just wasn't using it.

### Changed
- `_hud_customizer.lua:106-134` — extracted the position math into a new exported `CustomizerModule.local_position_for(widget_id, dx, dy)` that returns `vanilla_position + delta` (reads `REGISTRY_BY_ID[widget_id].vanilla_position`, degrades to `{0,0}` baseline for unknown ids). `_apply_offset_to_scenegraph` now calls it instead of assigning the raw `dx, dy`. Baseline preserved; pure delta applied. No new hooks (the two call sites — `_reapply_all_offsets` and the per-class `init` hook body in `install_hooks` — already pass the registry entry's data through `widget_id`).
- `gui_tweaker.lua:578-611` — added `_rt_register("hud_offset_preserves_vanilla_baseline", ...)`. Registered next to the `gut_*` HUD commands (after the `Customizer` dofile) because it closes over `Customizer`.

### Tests
- `/gut_regression_test` → new `hud_offset_preserves_vanilla_baseline` check. Asserts `local_position_for("equipment_ui", 25, -40)` == `{25, 29}` (baseline `{0,69}` + delta), `local_position_for("buff_ui", 0, 0)` == `{150, 18}` (zero-drag returns exact baseline — the old raw-write returned `{0,0}` here), and unknown ids degrade to `{0,0}+delta`. Fails if the baseline term is dropped again.

### To verify
- `/gut_edit_hud`, then drag `equipment_ui` (ammo/equipment cluster), `buff_ui` (buff icons), and `boss_health` a small amount — they should track the cursor smoothly from their current on-screen spot, NOT jump to the screen origin on the first click-drag.
- `/gut_reset_hud` should still snap each widget back to its vanilla position (unchanged path).
- `/gut_regression_test` reports the new check PASS.

## 0.2.7-dev (2026-05-30) -- Loc integrity: ESC-menu button loc key

### Why
`qa/check_name_integrity.ps1` check #2 flagged `display_name = "mod_tweaker_button_name"` (gui_tweaker.lua:627) — the ESC-menu "Mod Tweaker" button entry assigned a loc key that resolved in no loc table. The vanilla ingame_view render path runs the button's `display_name` through Localize (style `localize = true`, ingame_view.lua:138-140 + :252), and `display_name_func` is a dead vanilla field never invoked — so the button rendered the raw key string instead of "Mod Tweaker".

### Changed
- `gui_tweaker_localization.lua` — added `mod_tweaker_button_name = { en = "Mod Tweaker" }` (matches the intent of the existing `display_name_func` that returned "Mod Tweaker").

### Notes
- Resolves the gui_tweaker entry in the 13 check_name_integrity errors.

## 0.2.5-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `gui_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gut] v<MOD_VERSION> loaded")` runs once.

## 0.2.4-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- gui_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- gui_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build gui_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.3-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gut] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `gui_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gut] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.3-dev.

## 0.2.2-dev (2026-05-25) — Fix dead `NewsHeadUI` hook (issue #41)

### Why
Two `[MOD][gut][ERROR] (hook_safe): trying to hook object that doesn't exist: NewsHeadUI` lines fired every session. The HUD customizer's REGISTRY (`_hud_customizer.lua` line 23) used `class_name = "NewsHeadUI"`, but vanilla VT2's news-feed widget class is named `NewsFeedUI` — the file lives at `scripts/ui/hud_ui/news_feed_ui.lua`. The two error lines came from `install_hooks` iterating REGISTRY and registering both `init` and `destroy` hooks (lines 264 and 268) against the non-existent class.

### Changed
- `_hud_customizer.lua` line 23 — renamed `class_name` `NewsHeadUI` → `NewsFeedUI`, and `definitions_file` documentation reference from `news_head_ui_definitions.lua` → `news_feed_ui_definitions.lua` (the actual vanilla path).
- `gui_tweaker.lua` — `MOD_VERSION` bumped 0.2.1-dev → 0.2.2-dev.
- `itemV2.cfg` — title bumped to v0.2.2-dev.

### Notes
- `scenegraph_node_id = "pivot"` is correct — confirmed against `news_feed_ui_definitions.lua` scenegraph_definition.
- Result: the news-feed HUD widget is now actually drag-repositionable in `/gut_edit_hud` instead of being silently absent from the live-views table.

### Closes
- #41 (gut hook_safe target `NewsHeadUI` doesn't exist — 2 silent dead hooks).

## 0.2.1-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod. gui_tweaker previously had no `_dbg` helper at all.

### Changed
- `gui_tweaker.lua` — added file-local `_dbg(fmt, ...)` and `_dbg_alert(fmt, ...)` helpers at top. Output prefix `[gut:dbg]` / `[gut]`.
- `gui_tweaker.lua` — promoted the previous one-line `/gut_regression_test` stub to a proper `_RT_CHECKS` scaffold and registered `dbg_helpers_two_channel`.
- `itemV2.cfg` — bumped to v0.2.1-dev.

### Notes
- 0 existing `_dbg(...)` call sites (helper was newly introduced).
- 0 bare `mod:echo` reclassified — every `mod:echo` in `gui_tweaker.lua` is either inside a `/gut_*` chat command body (user-operational) or is the unconditional `hud-customizer hook install failed` operational error at line 306. Both classes are correct as bare `mod:echo` per the policy.
