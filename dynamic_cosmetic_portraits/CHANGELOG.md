# Changelog — Dynamic Cosmetic Portraits

## Unreleased — #925 bounded live portrait invalidation

- DCP now consumes the shared local presentation generation emitted by
  successful hat/outfit equips. It drains at most eight records per tick and
  performs one portrait-settings synchronization for the batch.
- The writer's exact cosmetic key bridges at most sixteen resolver passes while the
  synchronized player row catches up, then DCP returns to its existing
  `CosmeticUtils`/backend resolver. The bridge is bounded and does not become a
  second persistent loadout store.
- Added bounded `[dcp:925]` evidence and runtime/offline coverage. This entry is
  a source candidate only; no version bump, Workshop upload, or verification
  claim has been made.

## Unreleased -- #526 vanilla-equivalent cutout atlas candidate [not built]

- Empirical correction: all 12 committed HUD PNG alpha channels are exactly
  equal to `tools/vanilla_hud_alpha_mask_86x108.png`, yet the attached
  post-remask score-screen screenshot still shows the custom portrait's
  rectangle. Vanilla source proves the portrait widget has no clipping pass:
  `UIRenderer.script_draw_bitmap` sends atlas sprites to `Gui.bitmap_uv` and
  standalone identifiers to `Gui.bitmap`. DCP used the latter while vanilla
  portraits use the former.
- Migrated all 12 HUD and 12 small cutout portraits to one deterministic
  512x512 private atlas registered through VMF's existing `custom_atlas` API.
  Medium portraits remain on the proven standalone path. The readiness gate now
  requires valid HUD/small atlas rows plus resident atlas and medium materials;
  an incomplete registration fails open to the vanilla portrait.
- Added `tools/rebuild_portrait_atlas.ps1`; `add_portrait.ps1` invokes it and no
  longer generates new HUD/small standalone metadata. The atlas uses
  `A8R8G8B8` with alpha cutting disabled and two-pixel transparent padding.
- Added runtime check `portrait_cutouts_use_atlas_path_526` and expanded offline
  coverage for identifier collision, atlas completeness/dimensions/UV bounds,
  PNG dimensions, alpha-preserving metadata, package/data registration, and
  readiness gating. Updated the renderer and authoring documentation to remove
  the stale claim that atlas registration was ineffective.
- Related-issue cross-check: #435's score-record/player-scope resolver and
  #609's safe network-teardown lookup are unchanged. Closed score-screen
  cosmetic-model reports such as #513 and the broader 3D appearance umbrellas
  operate on hero/weapon units rather than this 2D portrait renderer seam, so
  they are not duplicates of #526.
- #749's borrowed-renderer residency rules remain intact: DCP owns a private,
  packaged atlas and never borrows or unloads another mod's resource. Readiness
  now proves every one of the 24 atlas rows and all 12 medium materials before
  assigning a custom portrait. DCP still owns only `es_mercenary`; unknown or
  custom careers, including Pusfume, remain on their existing portrait path.

This is source-complete at the pre-build boundary only. No VMB build, deploy,
Workshop upload, lifecycle-label change, or live-test card has occurred.

If the first built atlas still fails visually, use this evidence ladder rather
than another guessed asset edit:

1. Extract the compiled atlas from the exact root bundle and compare its alpha
   channel against the checked-in PNG, separating compiler loss from UI draw.
2. If compiled alpha is intact but ordinary atlas output is rectangular, set
   the portrait pass to `masked=true` only for DCP atlas rows and exercise the
   already-declared atlas masked material (the prior failure was a standalone
   masked material, not this UV path).
3. If both atlas shaders ignore alpha, instrument `Gui.bitmap_uv` material/UV
   selection beside one vanilla portrait, then clone the exact resident vanilla
   HUD-atlas material contract or add a narrowly scoped score-widget mask. Do
   not alter career lookup, player scope, or the working medium path.

## 0.1.27-dev (2026-07-18) -- #435 score rows use recorded cosmetics [verify-fix-coop]

- The attached client log had Dynamic Cosmetic Portraits disabled and no
  `[dcp:LOAD]` rows; its only Mercenary was a host-owned bot. The previous score
  hook forced bot rows to vanilla because a bot shares its owner's peer id.
- Score portraits now resolve skin first, then hat, from each score record's
  own `hero_skin` and `hat`. Vanilla creates those fields per human or bot and
  clients retain them while applying the host's score values.
- Added a material-residency gate, bounded bot/remote score evidence, a pure
  record resolver, and engine-free coverage for skin priority, bot identity,
  missing cosmetics, and malformed records. The #609 safe teardown path remains
  unchanged.

**Verify (co-op):** Both peers enable v0.1.27-dev. Host a non-Kruber career
with a tracked Mercenary hat saved and a Kruber bot; both score screens must
match the bot's HUD portrait. Then have the host play Mercenary with that hat;
the client score screen must show the host's custom portrait. Both logs must
contain `[dcp:LOAD] v0.1.27-dev` and bounded `[dcp:435] surface=score` rows.
Run `/dcp_regression_test`; both `portrait_override_player_scoped` and
`local_player_safe_network_lifecycle_609` must pass.

## 0.1.26-dev (2026-07-18) -- #609 release/source reconciliation [verify-fix]

- Published the already-merged safe network-teardown lifecycle from
  `0.1.25-dev` under a new unambiguous version because that earlier Workshop
  artifact predates the final source integration.
- Corrected the Workshop description's stale embedded `0.1.13` version.

**Verify:** Enter the keep, then return to the title screen normally. The newest
console log must contain no DCP `Network backend has not been set` callstack.
Run `/dcp_regression_test`; `local_player_safe_network_lifecycle_609` must pass.

## 0.1.25-dev (2026-07-14) -- #609 safe network-teardown lifecycle [verify-fix]

- Routed both local hat/skin portrait lookups through vanilla's `PlayerManager.local_player_safe()`. DCP's title-screen state callback now keeps its last known/backend fallback behavior without calling `Network.peer_id()` after teardown.
- Added runtime check `local_player_safe_network_lifecycle_609` for absent-network and live-game transitions, plus offline coverage rejecting bare local-player calls.

**Verify:** Enter the keep, then return to the title screen normally. The newest console log must contain no DCP `Network backend has not been set` callstack. Run `/dcp_regression_test`; `local_player_safe_network_lifecycle_609` must pass.

## 0.1.24-dev (2026-07-14) -- #526 restore visible custom portraits [diagnostics-armed]

- Reverted the incompatible `gui_gradient:DIFFUSE_MAP:MASKED` experiment on all 24 HUD/small materials. The newest host log proves DCP found the material and swapped Kruber to `portrait_kruber_mercenary_hat_0004`, yet the portrait rendered blank after that shader-only deployment.
- Kept the corrected vanilla-conformant PNG alpha masks. All 36 portrait materials and the generator now use the previously visible `gui:DIFFUSE_MAP` path; offline/runtime regression coverage rejects reintroducing the blank-material shader.
- The original score-screen corner clipping in #526 remains open for a different solution. Portrait visibility takes precedence over that cosmetic overflow.

## 0.1.23-dev (2026-07-14) -- #435 bounded player-scoped portrait evidence [verify-fix-coop]

- Added automatic `[dcp:435]` INFO evidence at the primary per-player HUD, Tab-list, and score-screen seams. Records identify subject class, custom/vanilla resolution, and portrait without peer/account identifiers.
- Evidence is exact-result deduplicated and hard-capped at 24 records per session. It does not poll, send RPCs, or write to chat.
- Added offline coverage for deduplication, cap enforcement, all three seams, and log-only output. Shipped portrait behavior is unchanged.

**Verify:** Exercise HUD, Tab, and score views with a remote Mercenary or bot. Each surface should log its independent resolution once; remote custom portraits must reflect their synced cosmetic, while unresolved/bot score rows report vanilla.

## 0.1.22-dev (2026-07-13) -- #526 preserve portrait alpha in the Gui material [verify-fix]

- The v0.1.20 PNG remask was necessary but insufficient: the mission-completion screenshot still shows the custom 86x108 texture's rectangular corners outside `UIWidgets.create_portrait_frame`, while adjacent vanilla portraits clip correctly. The source PNGs have transparent corners; the remaining difference is the standalone material shader.
- All 12 HUD and 12 small portrait materials now use `gui_gradient:DIFFUSE_MAP:MASKED`, the repository's established explicit alpha-mask Gui shader. Medium portraits retain `gui:DIFFUSE_MAP` because their frame has an opaque surround and they are intentionally full-bleed.
- `add_portrait.ps1` now selects the shader by generated size. Added offline coverage for all 24 cutout materials and the generator policy, plus `/dcp_regression_test` check `portrait_cutout_materials_use_masked_shader_526`.

- **Verify (solo):** restart the game after installing v0.1.22-dev, equip a tracked Kruber Mercenary cosmetic, finish any mission, and inspect Kruber's score tile. No rectangular image corner may appear beyond the octagonal frame. Also confirm the HUD and Tab portraits remain visible and clipped. One tester is sufficient; co-op is optional for comparing the custom tile beside vanilla peers.

## 0.1.21-dev (2026-07-13) -- #427 _dbg_alert log-only via engine printf [untested]

- `_dbg_alert` rerouted mod:info + mod:echo -> pcall-guarded engine printf (the echo half posted to chat, the info half is invisible with mod logging OFF; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template). `dynamic_cosmetic_portraits.lua` only; `_dbg` (mod:info) untouched.

## 0.1.20-dev (2026-07-13) -- #526 hud portraits no longer bleed outside the octagonal frame on the mission-completion score screen [untested]

### Why
The end-of-round score screen builds one portrait tile per player via `UIWidgets.create_portrait_frame` (`end_view_state_score.lua:514`), which draws the career's `portrait_image` texture at 86x108 under the frame ring (`ui_widgets_honduras.lua:13837-13869`, portrait layer 1 / frame layer 10). The frame ring is a thin octagonal outline with a transparent EXTERIOR, so any opaque portrait pixel outside the ring's silhouette is visible bleed. The octagonal cutout is baked into each portrait texture's ALPHA channel -- and dcp's hud-size (86x108) alpha mask was content-derived rather than taken from the vanilla silhouette: measured against the vanilla mask (consensus of 19 extracted 84x108 vanilla hud portraits), it had 446 opaque pixels outside the window, including content touching the canvas top edge and a 2-5px excess along the bottom taper. Every portrait shared the same wrong mask (the pipeline borrows alpha from `portrait_kruber_mercenary_hat_0001.png`, whose mask WAS the wrong one), so every custom portrait overflowed the octagonal frame -- most visibly on the score screen where four tiles sit center-screen. The same texture is drawn on the HUD unit frames and Tab list (same 86x108 rect), so the bleed existed there too, just less noticeably. The small (60x70) masks already matched the vanilla small silhouette exactly and the mediums are full-bleed like vanilla mediums -- only the hud size was wrong.

### Changed
- `gui/1080p/single_textures/custom_portraits/portrait_kruber_*.png` (all 12 hud-size textures) -- alpha channel replaced with the vanilla hud silhouette (RGB untouched). Verified per file: 0 opaque pixels outside the vanilla mask, all four corners fully transparent, identical opaque footprint across the set.
- NEW `tools/vanilla_hud_alpha_mask_86x108.png` -- the canonical vanilla hud silhouette (median alpha of 19 vanilla 84x108 hud portraits extracted from the game bundles, scaled to the 86x108 draw rect). Provenance for every future re-mask.
- `tools/add_portrait.ps1` -- new hard gate: after generating a HUD variant, the script throws if any opaque pixel falls outside the canonical mask ("silhouette conformance"). The alpha-borrow workflow is unchanged (the reference portrait now carries the corrected mask).
- NEW rt check `hud_alpha_mask_conformance_pipeline` -- texture alpha is not readable from Lua, so the runtime lock is on the pipeline: io-safe source check (skips in retail per issue 511) that `add_portrait.ps1` still references the canonical mask and still runs the conformance gate, and that the mask file exists.
- `qa/rt_textual_invariants.psd1` -- two new `#526` needles locking the canonical-mask reference + conformance gate in `add_portrait.ps1`. The four pre-existing dcp needles (issue 509 / issue 511) are untouched.
- `MOD_VERSION` `0.1.19-dev` -> `0.1.20-dev`.

### Tests
Built via VMBLauncher (compile-only); lint clean. Not deployed/uploaded per task scope.

### To verify
- Solo, any mission, playing Kruber Mercenary with a tracked cosmetic equipped (e.g. Estalian Conquistador): finish the mission and look at your tile on the score screen. The portrait must sit entirely inside the octagonal frame -- no square corners, no content poking past the top of the frame, no fringe along the lower taper (pre-fix: visible overflow). One tester is enough.
- Same session, sanity-check the HUD portrait (bottom-left) and the Tab player list row: silhouette should now match vanilla portraits exactly.
- Run `/dcp_regression_test`: expect `hud_alpha_mask_conformance_pipeline` PASS (skips its source half in retail) and the 6 pre-existing checks PASS.

## 0.1.19-dev (2026-07-13) -- #435 portrait override is now player-scoped: the local swap no longer leaks onto other players' frames [untested]

### Why
The portrait override mutates `SPProfiles[5].careers[1].portrait_image` -- one GLOBAL table entry shared by every player on Kruber Mercenary. Every UI surface resolves portraits by `(profile_index, career_index)` with no player key (HUD unit frames `unit_frames_handler.lua:167-173`/`:747`, Tab player list `ingame_player_list_ui_v2.lua:887`, end-of-round score `end_view_state_score.lua:504-514`), so with the swap active, every es_mercenary in the lobby (other humans, bots, a spectated player) showed the LOCAL player's cosmetic-derived portrait. Worse, the hat/skin detection scanned `pm:players()` and took the FIRST es_mercenary found, so the local override itself could be keyed off a REMOTE player's (or bot's) cosmetics.

### Changed
- `dynamic_cosmetic_portraits.lua` -- `_get_kruber_merc_hat_key` / `_get_kruber_merc_skin_key` now read `pm:local_player()` only (shared `_player_career_name` helper); the global swap is derived exclusively from the local player's cosmetics. The `BackendUtils.get_loadout_item` fallback stays (local backend = local loadout by definition; it also serves the hero-select picking preview when the local player is not currently on merc).
- NEW `_resolve_portrait_set_for_player(player)` -- resolves a portrait set from ONE player's own synced cosmetics via `CosmeticUtils.get_cosmetic_slot` (`cosmetic_utils.lua:254`; network-synced, works for remote humans and bots -- the same API vanilla's scoreboard uses for other players' skins, `scoreboard_helper.lua:369-373`). Skin-over-hat priority preserved; gated on material readiness; returns nil for untracked/unsynced -> callers fall back to the vanilla original, never the local override.
- NEW seam hooks (three), each resolving per-player at draw time:
  - `UnitFramesHandler._sync_player_stats` (wrapper): for a non-local es_mercenary frame, the global field is temporarily pointed at that player's own resolution around the wrapped call (single-frame-per-call site `unit_frames_handler.lua:1224`; vanilla's dirty-check then caches the per-player value, no widget churn).
  - `IngamePlayerListUI._update_player_information` (hook_safe): post-corrects each non-local merc row's portrait widget content (key `portrait`).
  - `EndViewStateScore._setup_player_scores` (hook_safe): post-corrects non-local merc rows; the Player object is resolved back from the score record's `peer_id`. Bots and departed players fall back to vanilla there (bots share the host's peer_id, so a score record cannot be mapped back to a specific bot).
- Bot behavior: in-mission HUD/Tab-list bot frames resolve from the bot's own synced cosmetics (bots wear the host's saved merc loadout, so a tracked hat on a bot legitimately shows its portrait); on the end-of-round score screen bots always show vanilla.
- Surfaces NOT yet covered (transient/secondary, same global read; listed in the seam-hook banner): deus overworld map + shop, matchmaking status, kill-feed popups, social wheel, twitch vote, versus tab.
- NEW rt check `portrait_override_player_scoped` -- runtime: per-player resolver exists; source (io-safe, CI): the three seam hooks are registered and local detection keys off `pm:local_player()`. The four locked needles from issue 509 / issue 511 (`_skin_portrait_map[skin_key]`, `_hat_portrait_map[hat_key]`, save-before-swap, restore-original) are untouched.
- `MOD_VERSION` `0.1.18-dev` -> `0.1.19-dev`.

### Tests
Built via VMBLauncher (compile-only); lint clean. Not deployed/uploaded per task scope.

### To verify
Note: vanilla adventure allows one player per HERO, so two humans can never both be Kruber Mercenary there -- the true two-merc leak pair only forms in Versus or duplicate-hero modded lobbies. The adventure-reachable defects are the wrong-source override (root cause 2) and the bot leak, and those are what the protocols below exercise.
- Solo (1 human + bots, host, deterministic): play a NON-merc career with a tracked hat (e.g. Estalian Conquistador) saved on your Kruber Mercenary loadout, with a Kruber bot in the party. In-mission the bot's HUD frame showing the custom portrait is CORRECT post-fix (the bot genuinely wears your saved hat; it resolves from the bot's own synced cosmetics). The discriminator is the END-OF-ROUND score screen: the bot's tile must show the VANILLA merc portrait (pre-fix: the custom one).
- 2 humans (both on this build): B plays Kruber Mercenary, A plays another hero but has a tracked hat saved on A's own merc loadout. On A's screen, B's HUD team frame + Tab-list row + end-of-round tile must reflect B's OWN hat: custom portrait if B wears a tracked hat, vanilla if untracked -- never A's loadout-derived portrait (pre-fix, A's global swap could key off A's saved loadout via the backend fallback, or off B's hat via the players() scan, and paint B's frames with it).
- Both testers: run `/dcp_regression_test` -- expect `portrait_override_player_scoped` PASS (and the 5 pre-existing checks PASS).

## 0.1.18-dev (2026-07-12) -- #511 io-safe regression checks: source-reads no longer throw in the retail sandbox [untested]

### Why
`/dcp_regression_test`'s source-pattern checks (`skin_map_overrides_hat_map`, and the save/restore portrait check) read dcp's own source via `io.open`. The VMF retail Stingray VM registers no `io` library (mods are `loadstring`'d into the game's shared `_G`; the engine registers `os` but not `io`), so `io.open` threw `attempt to index global 'io' (a nil value)` and the runner's pcall reported them as FALSE FAILs on healthy code.

### What
- NEW `_rt_src_read(path)` helper (next to `_rt_register`): guards `rawget(_G,"io")` and returns nil when `io` is absent, so each check's existing "unreadable source => skip (PASS)" branch runs instead of throwing. Both `io.open` reads route through it.
- The save/restore check already asserts its invariant at runtime (`_restore_portrait_settings` + `mod.on_unload` must be wired) so retail keeps that protection; the source-text needles (skin-before-hat lookup order, save/restore literals) are skipped in retail, still run under the modding-tools build / CI, and are listed as repo QA-gate candidates (PROJECT_STANDARDS 2.2b tier a). No behavior change.

## 0.1.17-dev (2026-07-12) -- issue 509 regression-harness backfill + issue 510 mem-probe file-local [untested]

### Why
Issue 509: dcp's `/dcp_regression_test` suite carried only the two generic checks (`dbg_helpers_two_channel`, `localization_format_safe`) and locked none of dcp's own bug-class invariants. Issue 510: `_MEM_PROBE_T0_DCP` leaked a bare `_G` global.

### Changed
- `dynamic_cosmetic_portraits.lua` - added three `_rt_register` checks, registered AFTER the portrait maps + sync/restore functions (not up with the generic checks) because Lua locals are not hoisted and this mod's predecessor crashed on that exact forward-reference:
  - `portrait_maps_have_registered_materials` - every hud/medium/small texture in `_hat_portrait_map` + `_skin_portrait_map` must have a matching `materials/ui/<name>` entry in `_PORTRAIT_MATERIALS`. Locks the "map key without asset -> Material-not-found-in-Gui crash" class (CHANGELOG v0.1.0/.1/.2). Pure runtime, so it asserts on a deployed install.
  - `skin_map_overrides_hat_map` - source-pattern: `_sync_portrait_settings` consults `_skin_portrait_map` before falling back to `_hat_portrait_map` (skins override hats).
  - `career_settings_swap_saves_and_restores` - `_restore_portrait_settings` + `mod.on_unload` exist; source confirms originals are captured before the swap and restored back. Locks the career_settings swap scope (issue 509 row-of-concern).
- `dynamic_cosmetic_portraits.lua:2` - `_MEM_PROBE_T0_DCP` is now `local` (issue 510), matching `modded_progression.lua:27`. Grep confirmed the only readers are the assignment and the boot-footprint log line, both in this same chunk.
- `MOD_VERSION` `0.1.16-dev` -> `0.1.17-dev`.

### Tests
Built via VMBLauncher (compile-only); lint clean. Not deployed/uploaded per task scope.

### To verify
- In-game (keep): run `/dcp_regression_test`. Expect every line `PASS` and a `N passed, 0 failed` tail. `portrait_maps_have_registered_materials` is the load-bearing runtime check (source-pattern checks soft-skip on a deployed install where the .lua source is not on disk).

## 0.1.16-dev (2026-07-01) -- Localization audit (no bugs found; mod has no settings page)

### Why
Repo-wide sweep for the VMF double-localize bug class: VMF's options module localizes each widget's `title`/`tooltip`/dropdown-option `text`/`unit_text` itself at menu build time, so a widget value written as `tooltip = mod:localize("key")` gets localized twice and renders wrapped in angle brackets. This mod was audited for that pattern and for stale/missing loc keys.

Nothing needed fixing. This mod removed its VMF settings page in v0.1.15-dev, so there are no widgets, no tooltips, no dropdowns, and no `setting_id` fields to double-localize. The only remaining loc key is `mod_description`, referenced once as `description = mod:localize("mod_description")` in `_data.lua` — this is the top-level mod-list description, the one place VMF does NOT auto-localize, so the explicit `mod:localize` is correct and stays. The description value already reads as plain human English (2 sentences, ASCII only, no em dashes, no percent signs, no angle brackets), so it was reviewed and left unchanged.

### Changed
- `dynamic_cosmetic_portraits.lua:4` — `MOD_VERSION` `0.1.15-dev` -> `0.1.16-dev`.
- No source/localization behavior changes: the audit found no widget-level double-localize, no missing loc keys, and no description rewrites were warranted.

### Tests
Not built/deployed per task scope. `/dcp_regression_test` scaffold unaffected (`localization_format_safe` still guards literal `%` in loc strings; the sole loc value has none).

### To verify
- In-game: this mod still shows no VMF settings page (unchanged from v0.1.15-dev); its mod-list entry description reads correctly with no stray angle brackets.

## 0.1.15-dev (2026-06-22) -- Remove the VMF settings page entirely (no options, no toggles)

### Why
User directive: "this mod doesn't really need any options or toggles. It simply does what it does." The mod's two settings — `dynamic_portraits` (portrait-swap on/off) and `enable_debug_logging` — were the only user-facing surface, and neither earns its keep: portrait swapping is the entire point of the mod, and the debug toggle gated a tiny amount of diagnostic output. Both are now hard-on, and VMF shows no settings page for this mod.

Portrait-swapping functionality is COMPLETELY UNCHANGED — only the options/menu surface was removed. The load-bearing `custom_gui_textures` registration in `_data.lua` (texture/material injection into the UI renderers) is untouched; it is not an "option," it's how the portraits reach the screen.

### Changed
- `dynamic_cosmetic_portraits.lua:4` — `MOD_VERSION` `0.1.14-dev` -> `0.1.15-dev`.
- `dynamic_cosmetic_portraits_data.lua` — removed the entire `options.widgets` tree (the `dynamic_portraits` checkbox + the `enable_debug_logging` checkbox) and set `is_togglable = false`, so VMF renders no settings page and no enable/disable toggle. Kept `name`, `description`, and the load-bearing `custom_gui_textures` block.
- `dynamic_cosmetic_portraits.lua` — `_dbg` / `_dbg_alert` no longer gate on `mod:get("enable_debug_logging")`; debug logging is always on (the mod has few debug features, so the volume is negligible).
- `dynamic_cosmetic_portraits.lua` — `_sync_portrait_settings()` no longer gates on `mod:get("dynamic_portraits")`; portrait swapping is always on.
- `dynamic_cosmetic_portraits.lua` — removed the now-dead `mod.on_setting_changed` handler (it only reacted to `dynamic_portraits`).
- `dynamic_cosmetic_portraits.lua` — `/portrait_diag` now reports `dynamic_portraits=always-on`; the `dbg_helpers_two_channel` regression check no longer flips the removed setting, it just verifies the helpers don't raise.
- `dynamic_cosmetic_portraits_localization.lua` — removed the orphaned `dynamic_portraits` / `dynamic_portraits_tooltip` / `enable_debug_logging` / `enable_debug_logging_tooltip` strings; kept `mod_description` (still referenced by `_data.lua`).

### Tests
Not built/deployed per task scope. `/dcp_regression_test` scaffold preserved (`dbg_helpers_two_channel` updated, `localization_format_safe` unaffected).

### To verify
- In-game: this mod no longer appears with a settings page in the VMF mod options menu (and has no enable/disable toggle there).
- Portraits still swap to match equipped Kruber Mercenary hats/outfits exactly as before.
- `/portrait_diag` reports `dynamic_portraits=always-on` and the same material-readiness/career state as before.

## 0.1.14-dev (2026-06-07) -- Back-fill: Workshop preview swap (item_preview.png -> preview.jpg) + version bump

### Why
Back-filled during the 2026-06-07 audit (`check_versions` flagged that MOD_VERSION `0.1.14-dev` had no matching CHANGELOG entry). The version was bumped to `0.1.14-dev` on 2026-05-26 but the CHANGELOG was never updated.

Best-effort attribution from source/asset timestamps and git working-tree state (no git commit isolates this version, and there is no in-source feature/behavior marker for it):
- The main lua was last touched 2026-05-26 13:23:44 -- AFTER v0.1.13 was finalized (2026-05-25 18:59). The only version-bearing delta in it is the `MOD_VERSION` constant `0.1.13` -> `0.1.14-dev`; no new hooks, commands, or behavioral markers were introduced.
- `itemV2.cfg` was touched 2026-05-26 13:24:26 (title suffix rewritten to ` v0.1.14-dev` by the launcher) and its `preview` field points at `preview.jpg`.
- The Workshop preview image was swapped: `item_preview.png` was deleted and replaced by a new `preview.jpg` (created 2026-05-26 13:23). This is the substantive change behind the bump -- a Workshop presentation refresh, not a code change.

**Uncertainty:** attribution is reconstructed from file timestamps + working-tree diff, not from a per-version commit. If v0.1.14-dev carried any additional unreviewed code change it is not visible in the source as a dated marker. The `itemV2.cfg` description body still reads "v0.1.13" (prose was not revised for this bump), consistent with a preview-asset/version-only change.

### Changed
- `dynamic_cosmetic_portraits.lua:3` -- `MOD_VERSION` bumped `0.1.13` -> `0.1.14-dev`.
- `itemV2.cfg:1,3` -- title suffix `v0.1.14-dev`; `preview = "preview.jpg"`.
- `item_preview.png` (removed) / `preview.jpg` (added) -- Workshop preview image swapped to JPG.

### Tests
None -- documentation-only back-fill. No code change, so no new regression check. Existing `/dcp_regression_test` scaffold (`dbg_helpers_two_channel`, `localization_format_safe`) is unaffected.

### To verify
- Workshop item page shows the new `preview.jpg` thumbnail (not the old `item_preview.png`).
- In-game load banner / `/dcp_regression_test` header reports `v0.1.14-dev`.

## 0.1.13 (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Dynamic Cosmetic Portraits v" .. MOD_VERSION)` startup line from every mod. dcp is still 0.x (no track suffix, but version starts with `0.`) so it counts as in-flight: the user can't tell at a glance which patch is running. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable (>=1.0.0) versions stay silent.

### Changed
- `dynamic_cosmetic_portraits.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. The `^0%.` branch is what fires for dcp (no suffix). When any branch fires, `mod:echo("[dcp] v<MOD_VERSION> loaded")` runs once.

## 0.1.12 (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[dcp] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- dynamic_cosmetic_portraits.lua -- removed the load-time `mod:echo("dynamic_cosmetic_portraits v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[dcp] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("dynamic_cosmetic_portraits v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build dynamic_cosmetic_portraits -- verification only. NOT deployed, NOT uploaded.

This mod was split out of `cosmetics_tweaker` on 2026-05-06. The full
pre-split development history of the portrait system (v0.7.37–v0.7.102 and
the v0.8.0–v0.8.4-dev cosmetics_tweaker line) lives in
[../cosmetics_tweaker/CHANGELOG.md](../cosmetics_tweaker/CHANGELOG.md) — keep it as the
authoritative archive of how the system was researched and stabilised.

## 0.1.11 (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- dynamic_cosmetic_portraits_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- dynamic_cosmetic_portraits.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build dynamic_cosmetic_portraits -- verification only. NOT deployed, NOT uploaded.

## [2026-05-25 v0.1.10] — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[dcp] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `dynamic_cosmetic_portraits.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[dcp] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.1.10.

## [2026-05-25 v0.1.9] — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `dynamic_cosmetic_portraits.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added new `_RT_CHECKS` regression scaffold (`/dcp_regression_test`) with `dbg_helpers_two_channel` check (dcp had no regression command before).
- `itemV2.cfg` — bumped to v0.1.9.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified.

## [2026-05-25 v0.1.8] — Standardize Debug Logging toggle (universal convention)
### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). dcp previously had no debug toggle — added.

### Changed
- `dynamic_cosmetic_portraits_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, top-level (NOT inside any group).
- `dynamic_cosmetic_portraits_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `dynamic_cosmetic_portraits.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[dcp:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.1.8.

### Notes
- No existing debug key to rename (dcp had none).

## [2026-05-20 v0.1.7] — Add Sellsword's Twinplume portrait
### Added
- Kruber Mercenary hat `mercenary_hat_0005` (Sellsword's Twinplume). Generated via `tools/add_portrait.ps1` from the 110x130 source PNG; alpha mask borrowed from the canonical `mercenary_hat_0001` reference.

## [2026-05-08 v0.1.6] — Fix Spoils of War crash + cover all known portrait-bearing views
### Fixed
- **Crash on Spoils of War loot menu** with same error shape as v0.1.5 (`Material 'portrait_kruber_mercenary_hat_1002' not found in Gui` at `ui_passes.lua:134`). Root cause clarification: Lua 5.1's **tail-call elimination** strips the inner-factory frames (`view_settings.ui_renderer_function` → `IngameUI:create_ui_renderer`) from the call stack. So when `hero_view_state_loot.lua:271` calls `self.ingame_ui:create_ui_renderer(world)`, VMF's frame-4 traceback parser lands on `hero_view_state_loot.lua`, NOT on `ingame_ui_settings.lua`. The v0.1.5 fix happened to mask the pause-menu case for a different reason (HeroView's caller chain may not have been fully tail-called), but did not generalize.
- Added every portrait-bearing entry-point file we could identify from the VT2 source's `create_ui_renderer` call sites: `hero_view`, `hero_view_state_loot` (Spoils of War), `hero_view_state_store` (Emporium), `hero_view_state_weave_forge` (Athanor), `start_game_state_settings_overview`, `store_item_purchase_popup`, `store_welcome_popup`, `game_mode_map_deus` (Chaos Wastes map), and `ui_manager`. Plus the existing `ingame_ui`, `ingame_ui_settings`, `level_end_view_base`, `level_end_view_versus`.

## [2026-05-08 v0.1.5] — Fix pause-menu crash (inject into ingame_ui_settings + level_end)
### Fixed
- **Crash on clicking any pause-menu button** with `Material 'portrait_kruber_mercenary_hat_0009' not found in Gui` at `ui_passes.lua:134`. Root cause: VMF's `inject_materials` keys off the basename of the lua file that called `UIRenderer.create`, and we only registered `"ingame_ui"`. The pause menu's HeroView / OptionsView / CharacterSelection / StartMenu / StartGame all get their renderer from `scripts/ui/views/ingame_ui_settings.lua` (lines 648, 650, 726, 728), so those views' Gui handles never received our portrait materials and crashed the moment they tried to draw a unit frame referencing one. Same shape would have hit at end-of-mission via `level_end_view_base` / `level_end_view_versus`.
- Refactored `dynamic_cosmetic_portraits_data.lua` to derive `ui_renderer_injections` from a single `_texture_names` list and a `_renderer_creators` list, instead of two parallel hand-maintained 33-line literals. Now adding a portrait only requires touching one list (after running `tools/add_portrait.ps1`).

### Renderer creators now covered
- `ingame_ui`
- `ingame_ui_settings` ← **the missing one that caused the crash**
- `level_end_view_base`
- `level_end_view_versus`

## [2026-05-07 v0.1.4] — Codify the workflow against future mistakes
### Added
- **`tools/add_portrait.ps1`** — single-command portrait asset generator.
  Encodes the only correct workflow: medium = source verbatim 110×130, HUD
  and small = bicubic-resize RGB + alpha channel borrowed from the
  `mercenary_hat_0001` reference variants. Generates `.png` / `.texture` /
  `.material` files, verifies output alpha at corners, prints next manual
  steps. Re-running it on Plumed Horseshoe produces functionally identical
  output to v0.1.3 (verified).
- **`CLAUDE.md` at the mod root** — workflow guardrails for AI agents,
  recurring failure modes table, in-game diagnostic command list.
- **DEVELOPMENT.md prominent banner** at the top — points at the script,
  enumerates the failure modes from v0.1.0 / v0.1.1 / v0.1.2 / v0.1.3.
- **Tripwire comments in `dynamic_cosmetic_portraits.lua`** above
  `_PORTRAIT_MATERIALS`, `_hat_portrait_map`, and `_skin_portrait_map`,
  warning that adding entries without running the script first crashes
  in-game with "Material not found in Gui".
- **Tripwire comment in `dynamic_cosmetic_portraits_data.lua`** above
  `custom_gui_textures`.
- **Repo-root `CLAUDE.md`** Key Reference Files updated with the new
  script and child CLAUDE.md.

### Why
Three shipped versions broke the same way (different specific guesses,
same root cause: free-handing the asset pipeline instead of borrowing
the alpha mask from a working portrait). Encoding the workflow in a
script + tripwires + a child CLAUDE.md should make accidental regression
much harder.

## [2026-05-07 v0.1.3] — Plumed Horseshoe alpha-mask fix + correct workflow doc
### Fixed
- **`mercenary_hat_0003` (Plumed Horseshoe) HUD/small overflow.** Both
  v0.1.1 (bicubic resize, no alpha) and v0.1.2 (110×130 verbatim under all
  three names, also no alpha) shipped HUD and small variants without the
  hex/shield-shaped alpha mask that defines the visible silhouette inside
  the in-game frame widget's hex cutout. Without the mask, RGB content at
  the canvas corners pokes past the frame's cutout edge — observed as
  "overflow" in-game. Fix: HUD (86×108) and small (60×70) now use the RGB
  content bicubic-downscaled from the 110×130 source PLUS the alpha channel
  copied verbatim from the corresponding `mercenary_hat_0001` (Estalia)
  reference variant. The medium (110×130) stays as a verbatim copy of the
  source — no mask needed at hero-select size.

### Documentation
- **DEVELOPMENT.md workflow rewritten** with the correct three-step asset
  generation (medium = source verbatim; HUD = resize 86×108 + alpha from
  reference; small = resize 60×70 + alpha from reference). Includes the
  PowerShell snippet that produces all three variants from a single source.
- Earlier doc revisions in v0.1.1 and v0.1.2 had the workflow wrong in
  different ways — neither acknowledged that HUD/small need shaped alpha
  borrowed from a reference portrait.

## [2026-05-06 v0.1.2] — Plumed Horseshoe (still broken — superseded by v0.1.3)
### Added/changed
- Replaced v0.1.1's bicubic-resized HUD/small with verbatim 110×130 copies.
  Still wrong: HUD/small at 110×130 still lack the hex-shaped alpha mask,
  and the engine's scale-down to widget size doesn't add a mask. Overflow
  persisted; fixed in v0.1.3.

## [2026-05-06 v0.1.1] — Plumed Horseshoe portrait (broken — superseded by v0.1.2)
### Added
- `mercenary_hat_0003` ("Plumed Horseshoe") with bicubic-downscaled HUD
  and small variants but no alpha mask. Caused visible content to extend
  past the in-game frame's hex cutout.

## [2026-05-06 v0.1.0] — Initial split from cosmetics_tweaker
### Added
- New standalone mod (Workshop ID `3721036701`, private). Wraps the dynamic
  portrait system that previously shipped inside `cosmetics_tweaker`.
- Includes 10 portrait sets (8 Kruber Mercenary hats + 2 outfits — Felix
  and VT1 Champion of Ubersreik).
- `dynamic_portraits` toggle (default ON).
- `portrait_diag`, `portrait_dump`, `test_portrait` console commands.
- `CHARACTER_COSMETIC_CATALOG.md` moved here (it's exclusively a
  portrait-authoring reference).

### Architecture
Identical to the pre-split design (see ../cosmetics_tweaker/CHANGELOG.md
v0.7.62 entry):
- Single source-of-truth swap of `SPProfiles[5].careers[1].portrait_image`
  and `.picking_image` — every UI surface that builds portrait textures from
  career_settings updates automatically (HUD, hero selection, ESC menu, tab
  overlay, end-of-round, matchmaking).
- `_check_portrait_materials_ready()` probes `Gui.material()` directly,
  since VMF bypasses the `UIRenderer.create` hook used pre-v0.7.52.
- Skin/outfit portraits override hat portraits because outfits replace
  Kruber's head model regardless of equipped hat.

### Carried-over from pre-split
- `_gui_has_material()` and `_flush_log()` are duplicated as locals here
  rather than imported, so this mod has no runtime dependency on
  cosmetics_tweaker.
- `NewsFeedUI:draw` hot-reload safety hook stayed in cosmetics_tweaker —
  it protects illusion/LA atlases, not portrait materials.
- `_get_hat_item_key_for_unit` was deleted (was an orphan).

### Known limitations (post-split)
- Only Kruber Mercenary is covered. Other characters/careers need new
  Photoshop portraits + new entries in `_hat_portrait_map` / `_skin_portrait_map`.
- Hot-reload (Ctrl+Shift+R) is unsafe — engine-level resource locks on
  loaded materials/textures. Always restart VT2 after redeploying.
