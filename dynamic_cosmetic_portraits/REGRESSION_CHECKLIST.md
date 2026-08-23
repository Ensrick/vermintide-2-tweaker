# Regression Checklist — dynamic_cosmetic_portraits

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to dynamic_cosmetic_portraits.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-18.

## Network teardown player lookup (#609)

- [ ] Hat and skin resolution call the shared `local_player_safe` gate, never bare `local_player()`.
- [ ] Title/teardown state returns nil without querying `Network.peer_id()`; last-known/backend portrait fallback remains available.
- [ ] A live in-game state still resolves the local Mercenary and applies the selected portrait.
- [ ] `/dcp_regression_test` passes `local_player_safe_network_lifecycle_609`; offline `test_dcp_player_scope.lua` passes.

## Player-scoped portrait resolution (#435)

- [ ] Remote Mercenary HUD and Tab portraits resolve from that player's synced cosmetic, never the local loadout.
- [ ] Score rows resolve skin first, then hat, from their own recorded cosmetics; bot rows no longer inherit the human owner's identity or force vanilla.
- [ ] A missing/untracked score-record cosmetic falls back to the saved vanilla portrait, and a not-ready Gui material prevents custom assignment.
- [ ] `/dcp_regression_test` passes `portrait_override_player_scoped`; offline `test_dcp_score_record` and `test_dcp_player_scope` pass.

---
## Multiplayer / Network Sync

### vmf-network-send-recipients — `"server"` recipient is silently dropped

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client emit log fires, host receive log never fires. No error, no warning. |
| Root cause | VMF's `convert_names_to_numbers` accepts only `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` / `"host"` / `"clients"` fall into else branch and are treated as a literal peer_id; `_vmf_users[peer_id]` lookup fails; `send_rpc_vmf_data` returns silently. |
| Mod(s) | cosmetics_tweaker, chaos_wastes_tweaker, any mod with client→host RPCs |
| Fix version(s) | cosmetics_tweaker v0.9.0.15-hotfix |
| Category | INTEGRATION |
| Repro | 1. Friend hosts a lobby. 2. You join as CLIENT. 3. Perform an action that should send an RPC to the host (e.g. cosmetics_tweaker LA cosmetic apply). |
| Expected post-fix | Host receives the RPC; you see the action reflected on the host's screen (and on other clients via host re-broadcast). |
| Detection | Add `mod:info("[emit] CLIENT->req")` before the send and `mod:info("[recv]")` at the receiver. Recv must fire when the test runs with you as client. |


---

## Localization / UI

### dcp-portrait-material-alpha -- cutout alpha survives Gui compilation

| Field | Value |
|-------|-------|
| Symptom | Mission-completion portraits exposed rectangular corners; the first masked-gradient follow-up then made the custom portrait fully transparent. |
| Root cause | The PNG alpha was corrected and byte-identical to the canonical mask, but DCP still registered HUD/small portraits as standalone textures. Vanilla `UIRenderer` sends atlas sprites through `Gui.bitmap_uv` and standalone identifiers through `Gui.bitmap`; the score widget has no clipping pass. The incompatible masked-gradient shader did not repair that renderer-contract mismatch. |
| Mod(s) | dynamic_cosmetic_portraits |
| Fix version(s) | Unreleased candidate |
| Category | INTEGRATION / ASSET |
| Repro | Equip a tracked Kruber Mercenary cosmetic, finish a mission, and inspect the Kruber portrait tile. |
| Expected post-fix | HUD and small portrait identifiers resolve to the private DCP atlas at exact 86x108 / 60x70 sizes; medium portraits remain standalone. Custom portraits stay visible and clipped on HUD, Tab, and score surfaces. Missing atlas/material residency fails open to vanilla. |
| Detection | Offline `test_dcp_portrait_materials.lua` checks atlas completeness, UV bounds, format, package/data registration, generator policy, and readiness source contract. `/dcp_regression_test` passes `portrait_materials_use_visible_shader_526`, `portrait_cutouts_use_atlas_path_526`, and the alpha-pipeline check. Final evidence is one solo HUD/Tab/score visual check after a full restart. |
| Tracking | GitHub issue #526. |

### vmf-dropdown-options-mutated — Multi-angle-bracket cascades from shared options table

| Field | Value |
|-------|-------|
| Symptom | VMF dropdown shows `<<key>>` or `<<<key>>>` cascades on second/third dropdown sharing an options table. |
| Root cause | VMF's `localize_dropdown_data` mutates `option.text` in place. Two dropdowns referencing the same options table get the first localized; the second tries to localize the already-localized string. |
| Mod(s) | enemy_tweaker, career_tweaker, any mod with multiple dropdowns of the same option set |
| Fix version(s) | enemy_tweaker v0.4.2-dev, crt v0.2.18-dev (talent-swap dropdown cascade) |
| Category | STATIC |
| Repro | 1. Define `local _SHARED = { { text = "off", value = "off" }, ... }`. 2. Use `options = _SHARED` on two different dropdown widgets. 3. Open settings. |
| Expected post-fix | Each dropdown gets its own options table (inline literal or factory function `_build_options()`). No bracket cascade. |
| Detection | Open mod's VMF settings UI; look for `<<...>>` text in any dropdown. Should be absent. |


---

### vmf-renderer-creator-keys — Material 'X' not found in Gui crashes on pause-menu / loot view

| Field | Value |
|-------|-------|
| Symptom | Crash `Material 'X' not found in Gui at ui_passes.lua:134` when opening certain UI surfaces. |
| Root cause | VMF reads `ui_renderer_creator` from `debug.traceback()` at frame 4. Lua 5.1 tail-call elimination means frame 4 is usually the OUTER caller, not the inner factory. Every entry-point .lua file must be listed in `ui_renderer_injections`. |
| Mod(s) | dynamic_cosmetic_portraits, cosmetics_tweaker |
| Fix version(s) | dynamic_cosmetic_portraits v0.1.4-0.1.6 |
| Category | INTEGRATION |
| Repro | 1. Mod registers custom material with creator `"ingame_ui_settings"` only. 2. Open Spoils of War / Lohner's Emporium / hero diorama / etc. 3. Observe crash. |
| Expected post-fix | `_renderer_creators` enumerates `ingame_ui`, `ingame_ui_settings`, `hero_view`, `hero_view_state_loot`, `hero_view_state_store`, `hero_view_state_weave_forge`, `start_game_state_settings_overview`, `store_item_purchase_popup`, `store_welcome_popup`, `level_end_view_base`, `level_end_view_versus`, `game_mode_map_deus`, `ui_manager`. |
| Detection | Walk every UI surface (pause menu, all keep sub-views, Spoils, Emporium, end-of-mission, CW map). No crash. |


---

### vmf-custom-gui-textures — ui_renderer_injections needs nested tables

| Field | Value |
|-------|-------|
| Symptom | Material registration silently does nothing; `Gui.material(gui, name)` returns nil; custom portraits/icons don't appear. |
| Root cause | VMF expects `ui_renderer_injections = { { "creator", "material1", ... }, ... }` (nested tables). A flat list of strings is silently skipped — no error, no log. |
| Mod(s) | dynamic_cosmetic_portraits, cosmetics_tweaker |
| Fix version(s) | dynamic_cosmetic_portraits investigation v0.7.37-v0.7.50 |
| Category | STATIC |
| Repro | 1. Set `ui_renderer_injections = { "ingame_ui", "material1" }` (flat). 2. Open game. 3. Probe `Gui.material(gui, "material1")` returns nil. |
| Expected post-fix | Nested-table format. |
| Detection | Audit `_data.lua` files: each `ui_renderer_injections` entry is a nested table starting with creator string. |


---

### vt2-portrait-system — Dynamic portrait swap via career_settings only

| Field | Value |
|-------|-------|
| Symptom | Custom portraits show in HUD but not in hero selection / pause menu / Spoils / end-of-mission. |
| Root cause | Per-widget `content.portrait` swaps only cover the HUD path. The only universal swap is `SPProfiles[profile].careers[career].portrait_image` at runtime. |
| Mod(s) | dynamic_cosmetic_portraits |
| Fix version(s) | v0.7.62 |
| Category | INTEGRATION |
| Repro | 1. Equip a portrait-bound hat. 2. Open hero selection / ESC menu / Spoils. 3. Check if custom portrait appears. |
| Expected post-fix | Custom portrait visible in every UI surface that shows the character's portrait. |
| Detection | Walk every portrait-display surface. |


---

### vmf-widget-id-unique — Duplicate setting_id breaks settings page

| Field | Value |
|-------|-------|
| Symptom | Mod's ENTIRE settings page disappears in VMF UI. Boot log: `Widgets N and M have the same setting_id`. |
| Root cause | VMF requires every widget's `setting_id` to be globally unique across the settings tree. Can't have one setting appear in two different category groups. |
| Mod(s) | chaos_wastes_tweaker, others |
| Fix version(s) | ct v0.7.26-test |
| Category | STATIC |
| Repro | 1. Duplicate any widget under two different groups (same setting_id). 2. Open settings. |
| Expected post-fix | Unique setting_ids only; use display-name prefixes for cross-cutting categorization. |
| Detection | Boot log grep for `same setting_id`. Should be absent. |


---

### vt2-chat-command-syntax — Commands are `/<name>` directly, not `/<modid> <name>`

| Field | Value |
|-------|-------|
| Symptom | Documentation / Workshop description shows commands as `/wt dump` / `/cos probe_hat` — wrong; misinforms players. |
| Root cause | `mod:command("name", ...)` registers `/name` directly. Mod-id is internal identifier, not chat prefix. |
| Mod(s) | all |
| Fix version(s) | doc rule (audit 2026-05-19) |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Every doc / cfg description / CHANGELOG references commands as `/<name>` directly. |
| Detection | Lint: grep `CHANGELOG.md` / `itemV2.cfg` / `*.md` for `/wt `, `/ct `, `/cos ` etc. before each command. Should be absent. |


---

### vt2-mod-command-inventory — Audit command name collisions

| Field | Value |
|-------|-------|
| Symptom | Two mods register the same `/name`; one shadows the other. |
| Root cause | Chat-command namespace is global. |
| Mod(s) | all |
| Fix version(s) | inventory snapshot 2026-05-19 |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Cross-check every new `mod:command("name", ...)` against the monorepo inventory. Rename if collision. |
| Detection | Lint pass over all mod sources comparing `mod:command(` first args. |


---

## Build / Deploy / Workshop

### lua-forward-reference — Functions called before definition crash at runtime

| Field | Value |
|-------|-------|
| Symptom | Game crashes on first frame with `attempt to call global 'NAME' (a nil value)` from a function defined later in the file. |
| Root cause | Lua 5.1 does NOT hoist `local function` definitions. Shipped 6+ times in cosmetics_tweaker (v0.7.1, v0.7.37, v0.7.39, v0.7.51, v0.7.53, v0.8.39). |
| Mod(s) | cosmetics_tweaker, others |
| Fix version(s) | cosmetics_tweaker v0.8.40 (defensive `M.fn = function()` pattern) |
| Category | STATIC |
| Repro | (Static rule — any forward reference will crash on first use.) |
| Expected post-fix | All `local function NAME` definitions appear ABOVE every call site. For helpers that logically belong in a different section, hoist as `M.NAME = function()` on a module table. |
| Detection | `tools/lint/regression-lint.ps1` walks each mod's Lua and reports forward refs. |


---

### feedback-pre-deploy-checklist — Forgetting checklist costs ~2 min/restart per skipped check

| Field | Value |
|-------|-------|
| Symptom | (Same as lua-forward-reference.) Burned 5+ times in v0.7.x portrait work. |
| Root cause | No mandatory pre-deploy gate. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | (Process.) |
| Expected post-fix | Before EVERY build+deploy: (1) forward-reference audit, (2) MOD_VERSION bump, (3) changelog update, (4) bundle verification, (5) hash verification. |
| Detection | VMBLauncher build gate integrates lint suite. |


---

### ugc-tool-forward-slashes — `tags = [];` causes 0x2 first-upload failure

| Field | Value |
|-------|-------|
| Symptom | First upload of a new mod fails with `generic failure (probably empty content directory) (0x2)` even though staging is otherwise correct. |
| Root cause | `tags = [];` line in `itemV2.cfg`. ugc_tool adds that line itself after a successful first upload — pre-writing it causes the 0x2. |
| Mod(s) | every newly-created mod's first upload |
| Fix version(s) | vmb-launcher v0.2.8 |
| Category | STATIC |
| Repro | 1. Hand-write `itemV2.cfg` with `tags = [ ];`. 2. Run the canonical reviewed ship sequence from `PROJECT_STANDARDS.md` section 6.6. 3. Confirm the cfg gate rejects it before publication. |
| Expected post-fix | Don't include `tags = [];` in the staged cfg for first upload. (Also: disable Zapret if present.) |
| Detection | Audit cfg before first upload; ensure no `tags` line. |


---

### ps5-getcontent-utf8 — PS 5.1 Get-Content -Raw mangles UTF-8

| Field | Value |
|-------|-------|
| Symptom | Workshop description shows `â€¢` instead of `•` (and similar garbled multi-byte chars). |
| Root cause | PowerShell 5.1's `Get-Content -Raw` uses system code page (Windows-1252), not UTF-8. Multi-byte UTF-8 silently mangled. |
| Mod(s) | any mod whose cfg contains bullets / em-dashes / accented chars |
| Fix version(s) | _upload_helper.ps1 fix 2026-05-14 |
| Category | STATIC |
| Repro | 1. Put `•` in description in source cfg. 2. Run an upload via a tool using `Get-Content -Raw`. 3. Workshop page shows `â€¢`. |
| Expected post-fix | Use `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)` and `WriteAllText(... , [System.Text.UTF8Encoding]::new($false))` (no BOM). |
| Detection | After upload, verify Workshop page shows correct chars; or compute `xxd -p source.cfg | grep -o 'e280a2' | wc -l` and match against staged. |


---

### feedback-workshop-upload-verify — `Upload finished` lies; check workshop_log.txt + file size

| Field | Value |
|-------|-------|
| Symptom | User reports the mod hasn't changed despite multiple "successful" uploads. |
| Root cause | ugc_tool prints `Upload finished` on no-op. Steam logs `No content change detected` in `workshop_log.txt`. Workshop page `time_updated` doesn't bump on no-op. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Upload a mod whose bundle is byte-identical to Workshop. 2. Read "Upload finished" message. 3. Notice page didn't change. |
| Expected post-fix | After every upload, grep `C:\Program Files (x86)\Steam\logs\workshop_log.txt` for `Uploaded new content` (not `No content change detected`). For friends_only items, eyeball Workshop page file size. |
| Detection | Manual log check OR Workshop page file-size check after every upload. |


---

### feedback-workshop-upload-without-deploy — Author's local install stays stale

| Field | Value |
|-------|-------|
| Symptom | After uploading a new version, you restart VT2 and console still echoes the OLD version. |
| Root cause | Steam doesn't reliably re-download Workshop items the same Steam account authored. |
| Mod(s) | all |
| Fix version(s) | n/a - canonical reviewed ship; see `PROJECT_STANDARDS.md` section 6.6 |
| Category | MANUAL |
| Repro | Historical direct-publication path: upload without the reviewed tracked bundle/deploy transaction, then observe the author still loading the old version. The current receipt gate blocks this path. |
| Expected post-fix | Use the canonical merge-first reviewed ship sequence in `PROJECT_STANDARDS.md` section 6.6; direct launcher publication is prohibited. |
| Detection | PC-A uses the hash-verified local deploy without restarting Steam; volunteer testers unsubscribe/resubscribe through the dev collection. Confirm the newest console log's `[<id>:LOAD]` version. |


---

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | n/a - canonical reviewed ship; see `PROJECT_STANDARDS.md` section 6.6 |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use the canonical merge-first reviewed ship sequence in `PROJECT_STANDARDS.md` section 6.6 for subscriber-facing changes. |
| Detection | After every iterative fix, verify both the local file AND the Workshop page changed. |


---

### ugc-tool-pushes-all-cfg-fields — Every upload overwrites title/desc/preview/visibility

| Field | Value |
|-------|-------|
| Symptom | Workshop page title/description/preview reverts to whatever the local cfg says. |
| Root cause | ugc_tool reads `itemV2.cfg` and pushes EVERY field on every upload. Direct edits to the live Workshop page are reverted. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Edit live Workshop page directly. 2. Upload from local cfg. 3. Live page reverts. |
| Expected post-fix | Cross-check cfg vs live Workshop page BEFORE every upload. Ensure cfg's title/desc/preview/visibility reflect the desired live state. |
| Detection | Manual pre-upload audit. |


---

### vmblauncher-handscaffold-first-upload — Missing `item_preview.png` creates orphan Workshop items

| Field | Value |
|-------|-------|
| Symptom | First upload of a hand-scaffolded mod fails with `0x9` invalid preview file, but ugc_tool still created a Workshop item. |
| Root cause | vmblauncher does NOT synthesize a placeholder preview. ugc_tool creates the Workshop item BEFORE validating preview/content. On failure, item exists but isn't written back to cfg. |
| Mod(s) | every newly-scaffolded mod |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | 1. Hand-scaffold a new mod (skip `vmb create`) without `item_preview.png`. 2. Run the canonical reviewed ship sequence from `PROJECT_STANDARDS.md` section 6.6. 3. Confirm preflight rejects the missing preview before publication. |
| Expected post-fix | Copy `vmb/.template-vmf/item_preview.png` into mod root BEFORE first upload. If failure occurs, capture orphan publisher_id from stdout, convert signed→unsigned, write `published_id = <N>L;` to cfg manually, then retry. |
| Detection | Verify `item_preview.png` exists in mod root before any first upload. |


---

### feedback-mod-version-format — Release-track suffix only (alpha/beta/dev)

| Field | Value |
|-------|-------|
| Symptom | Workshop title shows weird suffixes like `v0.9.9.1-revert` / `v0.9.8.7-revert` / `v0.7.81-hotfix`. |
| Root cause | Suffix should be track-only (`alpha`/`beta`/`dev`/`rc`). Change-descriptors belong in changelog, not version. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | STATIC |
| Repro | 1. Set `MOD_VERSION = "0.9.9.1-revert"`. 2. Run the canonical nonpublishing `ship.ps1 -BuildOnly` phase. 3. Confirm version QA rejects the descriptor before publication. |
| Expected post-fix | `MOD_VERSION = "X.Y.Z[.W][-alpha|beta|dev|rc]"`. No change descriptors. |
| Detection | Lint: grep each mod's `MOD_VERSION` for suffix tokens outside the allowed set. |


---

### feedback-redundant-safeguards-ok — Belt-and-suspenders dual-table writes are OK

| Field | Value |
|-------|-------|
| Symptom | (Not a bug — process note.) |
| Root cause | When redundancy is cheap and missed-path failure is silent, write to multiple tables / install multiple gates. Examples: dual buff registration (DeusPowerUpBuffTemplates + _G.BuffTemplates), late-arrival re-apply paths, idempotent registration. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Don't strip "redundant" safeguards without confirming the missed-path failure has actually been eliminated. |
| Detection | Code review process. |


---

### feedback-search-changelog-for-known-crashes — Grep CHANGELOG before theorizing

| Field | Value |
|-------|-------|
| Symptom | (Process rule.) |
| Root cause | Most surprising VT2 crashes have a documented prior fix. Searching memory + CHANGELOG.md before theorizing saves 1-2 wasted versions per crash. |
| Mod(s) | all |
| Fix version(s) | n/a |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Before theorizing about a crash, grep all `CHANGELOG.md` + `memory/` for the literal crash signature. |
| Detection | Process. |


---

### vt2-hash-reverse-lookup — Decipher `Resource '#ID[hash]' not found!` via murmur hash

**[GAME-PATCH-WATCH]**

| Field | Value |
|-------|-------|
| Symptom | `[Engine Error]: Resource '#ID[xxx]' was not found!` with no path. |
| Root cause | Hash is murmur64 of a Stingray resource path. Need to brute-hash candidate paths and match. |
| Mod(s) | all |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Use `C:/Tools/vt2_bundle_unpacker/target/release/unpacker.exe murmur hash <path>` to find the missing resource. Don't speculate. |
| Detection | When crash occurs, run hash candidates before authoring a fix. |


---

## Slugs

- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- lua-forward-reference
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-custom-gui-textures
- vmf-dropdown-options-mutated
- vmf-network-send-recipients
- vmf-renderer-creator-keys
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-hash-reverse-lookup
- vt2-mod-command-inventory
- vt2-portrait-system
