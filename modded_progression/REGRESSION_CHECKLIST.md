# Regression Checklist — modded_progression

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to modded_progression.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

- [ ] #607: one ordinary official-realm chest/vault opening emits exactly one bounded `[mp:607] CAPTURE applied ... backend=observed-only` summary without changing the native opening.
- [ ] #607: modded-realm navigation/open attempts add no capture; `/mp_loot_diag` contains at most 12 sanitized records and `/mp_loot_diag reset` clears only diagnostic evidence.
- [ ] #607: `/mp_regression_test` passes `mp607_official_loot_capture_is_bounded_and_realm_gated`; engine-free `test_mp_loot_diag.lua` passes.

- [ ] #577: one modded SM purchase debits local shillings once, grants/owns the exact item immediately and after restart, and never enqueues `PurchaseItem` or `storePurchaseMade`.
- [ ] #577: repeat/double activation, stale price, owned item, insufficient funds, unavailable/DLC/platform/bundle offer, and failed persistence cannot double-spend or partially grant; official purchase remains vanilla.
- [ ] #578: modded Emporium wallet, tooltip, SM purchase action, daily reward row, and claim popup use the exact vanilla Silver Shilling presentation, with no `Local` qualifier.
- [ ] #578: claim, credit, debit, `/mp_reset`, and realm transition invalidate wallet/preview affordability; `/mp_regression_test` passes `mp578_local_shilling_ui_lifecycle`.
- [ ] #578: each observed revision/realm edge emits one `[mp:578] wallet_refresh` and `affordability_refresh` line; unchanged frames emit none.
- [ ] #581: startup/keep challenge-board polling never reads an `mp_daily_v2_*` key from `StatisticsDatabase`; `/mp_regression_test` passes `mp581_owned_daily_bypasses_statistics_db`.
- [ ] #589: the modded login-reward button remains disabled and no caller reaches `claimStoreRewards`; `/mp_regression_test` passes both `mp589_store_login_claim_*` checks. Official-realm claim remains vanilla.
- [ ] #573: modded `get_quests` exposes only MP-owned daily rows with empty weekly/event slices, and modded refresh never calls backend `update_quests`; official read/refresh delegates unchanged.

Last updated: 2026-07-13.

---
## Backend isolation

### mp-emporium-purchase-local — SM purchase must be one durable backend-free transaction

| Field | Value |
|-------|-------|
| Symptom | The Emporium buy UI is enabled in modded play, but purchase either calls PlayFab or cannot debit the isolated ledger and grant the selected item. |
| Root cause | Vanilla `exchange_chips` enqueues `PurchaseItem`, then performs mirror mutation, chip debit, and `storePurchaseMade` in separate authenticated callbacks. |
| Fix version(s) | mp v0.2.24-dev |
| Category | INTEGRATION / CRITICAL |
| Repro | With enough local SM, buy an unowned Silver Shilling cosmetic in modded play; repeat activation, reopen the store, and restart. |
| Expected post-fix | Debit, exact grant, unlock, and transaction markers persist together once; native inventory/store sees the mirror overlay; no PlayFab request occurs. Official play remains native. |
| Detection | `/mp_regression_test` passes `mp577_backend_free_emporium_purchase`; offline `test_mp_emporium_purchase.lua` covers validation, duplicates, and persistence failure. Log has one bounded `[mp:577] purchase_committed ... backend=none` line and no `PurchaseItem`/`storePurchaseMade` request. |

### mp-quest-surface-owned - official rows and refresh requests cannot enter modded play

| Field | Value |
|-------|-------|
| Symptom | An official weekly/event quest appears in the modded challenge board, but claiming it is rejected as non-MP; refreshing the surface may still enqueue backend `getQuests`. |
| Root cause | The first #573 hook replaced only `quests.daily` and retained vanilla weekly/event slices. Vanilla `update_quests` independently polls all three official timer families before issuing CloudScript refresh. |
| Fix version(s) | mp v0.2.22-dev |
| Category | INTEGRATION / CRITICAL |
| Repro | Open Okri's Challenges in modded play with an active official weekly/event quest, then refresh or reopen the surface and attempt its claim. |
| Expected post-fix | The modded surface contains only three MP-owned dailies; weekly/event are empty; refresh rotates locally without `getQuests`; local claims cannot reach `generateQuestRewards`. Official play remains native. |
| Detection | `/mp_regression_test` passes `mp573_quest_surface_is_owned_and_backend_free`; offline `test_mp_quest_boundary.lua` proves slice filtering, zero vanilla calls, local refresh, and exact official pass-through. Log contains no official quest id, `getQuests`, `generateQuestRewards`, backend 511, or `-1` from this path. |

### mp-store-login-reward-fail-closed - login reward must not enqueue PlayFab

| Field | Value |
|-------|-------|
| Symptom | Claiming the Emporium daily login reward requests EAC, receives backend 511 / `-1`, and forces the game to exit. |
| Root cause | MP un-gated `StoreLoginRewardsPopup._create_ui_elements` but did not intercept `_claim_rewards` or `BackendInterfacePeddlerPlayFab.claim_login_rewards`, which enqueues authenticated `claimStoreRewards`. |
| Fix version(s) | mp v0.2.21-dev |
| Category | INTEGRATION / CRITICAL |
| Repro | In the modded realm, open the Emporium login-reward popup and attempt mouse/gamepad activation. |
| Expected post-fix | Button stays disabled; direct and backend calls fail closed; no PlayFab request, EAC challenge, 511, `-1`, or exit. Official realm remains native. |
| Detection | `/mp_regression_test` passes `mp589_store_login_claim_request_boundary` and `mp589_store_login_claim_ui_disabled`; inspect the log for absence of `claimStoreRewards`. |

### mp-local-daily-lifecycle — roster/progress/claims/SM must share an isolated durable state

| Field | Value |
|---|---|
| Symptom | Dailies depend on the official roster, lose progress on restart, reset twice after clock changes, or merge local rewards into official Silver Shillings. |
| Root cause | The #568 simulation copied server-selected templates and kept claim markers in the generic currency wallet; progress still lived in vanilla quest statistics. |
| Fix version(s) | mp v0.2.19-dev |
| Repro | In modded play, progress and claim a daily; restart; cross/reset the wall clock; compare SM in official and modded realms. |
| Expected post-fix | UTC roster selection is deterministic; persisted progress survives; clock rollback never rotates; claim + ledger credit is exact-once; official balance is untouched. |
| Detection | `/mp_regression_test` passes the ownership/rotation/ledger checks; log contains bounded `[mp:daily]` generation/progress/reset/claim records and no backend reward request. |

### mp-simulated-daily-claim-local — daily claim must not enqueue PlayFab

| Field | Value |
|-------|-------|
| Symptom | Claiming a completed daily enqueues `generateQuestRewards`, requests EAC, raises backend error 511, and forces exit. |
| Root cause | MP exposed backend daily ids and only un-gated claim UI; individual `_claim_quest_reward` still called `QuestManager.claim_reward`. |
| Fix version(s) | mp v0.2.18-dev |
| Category | INTEGRATION / CRITICAL |
| Repro | In modded realm, complete one `mp_daily_*` entry and claim it; repeat with claim-all. |
| Expected post-fix | Local shillings and claim marker persist atomically; entry refreshes immediately; no `generateQuestRewards`, EAC request, 511, or exit. Unknown/official ids receive no local grant. |
| Detection | Run `/mp_regression_test`, then inspect the session log around each claim. Restart and prove the same id cannot grant twice. |

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
- vmf-dropdown-options-mutated
- vmf-network-send-recipients
- vmf-widget-id-unique
- vt2-chat-command-syntax
- vt2-hash-reverse-lookup
- vt2-mod-command-inventory
