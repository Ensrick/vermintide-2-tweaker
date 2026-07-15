# Regression Checklist — crafting_in_modded

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to crafting_in_modded.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-14.

### athanor-literal-property-values - issue #244

| Field | Value |
|---|---|
| Symptom | Forging three of five Attack Speed bubbles displays/applies 4.2% on the resulting item instead of the picker value of 3%. |
| Root cause | The Weave picker bubble fraction was stored directly as the Adventure property's normalized interpolation parameter. |
| Fix version(s) | cim_dev 0.8.74-dev |
| Category | SOLO |
| Repro | Set Attack Speed to three bubbles, inspect the item, then reopen the Athanor. Repeat at four/five bubbles and with one signed reduction property. |
| Expected post-fix | Three/four/five bubbles round-trip as 3%/4%/5%; normalized zero preserves the low-end property; special/discrete properties are unchanged. |
| Detection | Offline `test_cim_property_value_policy.lua` passes and `/cim_regression_test` passes `issue244_athanor_literal_property_values`. |

---

### cw-trait-exact-slot-family - issue #414

| Field | Value |
|---|---|
| Symptom | `Allow Chaos Wastes traits` lets ranged-only traits roll on melee weapons and melee-only traits appear on ranged weapons. |
| Root cause | CIM flattened every `deus_*` combination category instead of preserving the category family vanilla uses as slot identity. |
| Fix version(s) | cim_dev 0.8.73-dev |
| Category | SOLO |
| Repro | Enable the toggle; reroll and inspect both a melee and ranged weapon on the standard bench and in the Athanor. |
| Expected post-fix | Only exact-slot CW traits appear; shared boons remain on both; the accessory view receives no CW weapon traits. |
| Detection | Offline `test_cim_trait_slot_policy.lua` passes and `/cim_regression_test` passes `issue414_cw_traits_preserve_slot_family`. |

---

### cwv-acquisition-selector-bound - issue #524

| Field | Value |
|---|---|
| Symptom | Each crafted CWV weapon appears to add another 300-power base/blacksmith choice, or every CWV Blacksmith selector is absent when the Craft Item page is opened directly. |
| Root cause | CWV clones inherit the base weapon `.key`/`.name`, requiring exact selector identity. After acquisition moved wholly to CIM, the selector cache was also activated by a post-`on_enter` hook even though vanilla builds the initial recipe page inside `on_enter`; all synthetic rows therefore missed that first query. |
| Fix version(s) | cim_dev 0.8.72-dev (bounded identity), 0.8.76-dev (pre-enter catalog availability) |
| Category | SOLO |
| Repro | Open the standard Craft Item page directly and inspect Dual Axes, Infantry Spear, Crowbill, and Greataxe; craft Imperial Longsword twice, then leave and reopen the grid. |
| Expected post-fix | Every career-owned CWV family has exactly one authored-icon Blacksmith selector; the two separate Modded-rarity crafts appear only in ordinary inventory. |
| Detection | Offline `test_cim_cwv_template_selector.lua` and `test_cim_cwv_template_catalog.lua` pass; `/cim_regression_test` passes `issue524_cwv_selector_bounded` and `issue524_all_cwv_blacksmith_selectors`. |

---

### athanor-tooltip-slot-anchor - issue #521

| Field | Value |
|---|---|
| Symptom | The secondary weapon's one remaining tooltip appears over the primary weapon panel. |
| Root cause | CIM used one tooltip parented to the center panel without composing the hovered weapon viewport's authored x offset. |
| Fix version(s) | cim_dev 0.8.71-dev |
| Category | SOLO |
| Repro | Hover primary, then secondary, in the Athanor overview. |
| Expected post-fix | One tooltip follows the hovered panel: melee x=-535, ranged x=555; mouse-out clears it. |
| Detection | `/cim_regression_test` passes `forge_tooltip_no_equipped_compare` and `issue521_tooltip_follows_hovered_weapon`. |

---

## Hold-Tab Loadout Preview

### issue246-tab-preview-exact-skin - Remote weapon icon follows the equipped illusion

| Field | Value |
|-------|-------|
| Scope | Hold-Tab player list melee/ranged icons and their existing hover tooltips. |
| Source boundary | Vanilla loadout RPC omits skin; live `inventory_system:equipment().slots[slot].skin` is exact because `rpc_add_equipment` carries `weapon_skin_id`. |
| Repro | Two players equip distinct non-default melee and ranged illusions, then inspect each other while holding Tab. Swap one illusion and return another to default. |
| Expected post-fix | Icons and hover tooltips match the live equipped skins in both host-to-client directions, update after swaps, and clear to the base icon for default skin. |
| Detection | Run the offline Lua suite and `/cim_regression_test`; require `issue246_tab_preview_exact_skin_icon` PASS. Unknown registered identity emits one bounded `[cim:246]` line. |

---

## Custom Rarity UI

### issue263-modded-upgrade-copy - Customization Upgrade text is never blank

| Field | Value |
|-------|-------|
| Scope | Gear-icon item customization Upgrade option and detailed Upgrade state. |
| Repro | Open the customization viewer first for an upgradeable vanilla-rarity weapon, then for a Modded-rarity weapon. |
| Expected post-fix | Vanilla upgrade copy and behavior remain unchanged. The Modded option and detailed state show one sentence explaining Modded rarity; no recipe, cost, lock, or transition changes. |
| Detection | Run `/cim_regression_test`; require `issue263_modded_upgrade_copy` PASS. |

---

## Bulk Cleanup

### issue277-exact-cim-weapon-cleanup - Destructive cleanup fails closed

| Field | Value |
|-------|-------|
| Scope | Only backend IDs present in CIM's exact `_forged_weapons` store whose live ItemMasterList row is `melee` or `ranged`. Accessories, unresolved definitions, rarity-only rows, prefix-only rows, and ordinary backend items are retained. |
| Safety | `/forge_delete_all` previews and snapshots the exact set. `/forge_delete_all CONFIRM` proceeds only if the set is unchanged and no candidate appears in a current or saved loadout; uncertainty refuses the entire transaction. |
| Persistence | The runtime mirror row, legacy MoreItemsLibrary row, CIM forged record, dormant modded-loadout references, and exact-ID illusion override are removed; forge persistence and UI refresh run once per batch. |
| Repro | Craft two weapons and one accessory. Leave every craft unequipped. Run `/forge_delete_all`, review the counts, then run `/forge_delete_all CONFIRM`. Restart and verify the weapons do not return while the accessory and every vanilla item remain. |
| Negative cases | Equip one CIM weapon in any current or saved loadout and confirm the command deletes nothing. Preview, craft another weapon, then confirm and verify the changed-set guard refuses. Disable a source mod and verify its unresolved record is retained. |
| Detection | Run the offline Lua suite and `/cim_regression_test`; require `issue277_bulk_cleanup_exact_owner_transaction` PASS. |

---

## Illusion Persistence

### issue563-vanilla-illusion-exact-id - Vanilla skin override survives mirror rebuild

| Field | Value |
|-------|-------|
| Symptom | A primary weapon illusion applies locally, then reverts when PlayFab rebuilds the inventory mirror or after restart. |
| Root cause | The first fix saved server-owned overrides only inside CIM's local craft helper. When Cosmetics Tweaker owned the customization craft bypass, explicit Apply changed the mirror but never replaced CIM's older saved override. |
| Mod(s) | crafting_in_modded_dev |
| Fix version(s) | 0.8.65-dev; reopened precedence fix 0.8.66-dev |
| Category | INTEGRATION |
| Repro | Start with saved override A on a server-owned item. In Keep and then in an Adventure mission, use the gear-icon customization view to explicitly Apply different illusion B with Cosmetics Tweaker enabled. Wait for a backend mirror-ready refresh. Repeat on a second copy of the same weapon template. |
| Expected post-fix | Apply completion emits `[cim:563] explicit_saved ... skin=B`; every later rehydrate uses B, never A. The same-template sibling remains independent. CIM-owned crafts use their forge record and leave no stale vanilla override. Missing/salvaged backend IDs are pruned. |
| Detection | Run `/cim_regression_test`; require `issue563_vanilla_skin_override_exact_backend_id` PASS. Confirm old A -> explicit B -> `[cim:563] ready_rehydrate` remains B in both Keep and mission. |

---

## Craft Output

### issue562-crafted-weapon-auto-equip - Exact bid and slot stay synchronized

| Field | Value |
|-------|-------|
| Symptom | A newly crafted weapon only appears in inventory, or its loadout icon changes while the live avatar still holds the previous weapon. |
| Root cause | Craft output and live equipment are separate engine surfaces. A bare loadout write does not recreate the spawned weapon unit (historical issue #12). |
| Mod(s) | crafting_in_modded_dev |
| Fix version(s) | 0.8.64-dev |
| Category | INTEGRATION |
| Repro | 1. Keep `Automatically equip newly crafted weapons` ON. 2. Open the Athanor. 3. Craft once from Primary, then once from Secondary. 4. Repeat with the setting OFF. |
| Expected post-fix | ON: the exact newly created Athanor item is equipped in the chosen slot, and the visible weapon matches its loadout icon. OFF: the new item stays inventory-only and the equipped slot is unchanged. Standard-forge, jewelry, and accessory crafts remain unchanged. |
| Detection | Run `/cim_regression_test` and require `issue562_auto_equip_contract` PASS. In game, verify both weapon slots plus the OFF and accessory cases. |

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
| Repro | 1. Hand-write `itemV2.cfg` with `tags = [ ];`. 2. Run `vmblauncher upload <mod>` for first time. 3. Watch failure. |
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
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher upload <mod>`. 2. Restart VT2. 3. Watch console show old version. |
| Expected post-fix | Use `vmblauncher all <mod>` (build + deploy + upload) during iterative dev. |
| Detection | After every upload, restart VT2; console version matches bumped MOD_VERSION. |


---

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use `vmblauncher all <mod>` for changes intended to reach subscribers. |
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
| Repro | 1. Hand-scaffold a new mod (skip `vmb create`). 2. Run `vmblauncher upload <mod>` without copying `item_preview.png`. 3. Watch failure. |
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
| Repro | 1. Set `MOD_VERSION = "0.9.9.1-revert"`. 2. Run `vmblauncher all <mod>`. 3. See Workshop title carry the descriptor. |
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
