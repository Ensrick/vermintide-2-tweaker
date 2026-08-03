# Regression Checklist — crafting_in_modded

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to crafting_in_modded.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-22.

### accessory-property-layer-isolation - issue #959

| Field | Value |
|---|---|
| Symptom | Filling Health on Necklace makes Health unavailable on Charm and Trinket; right-click or Clear can target the wrong accessory after the same property is used in multiple categories. |
| Root cause | CIM widens each property key into every accessory category, but its backend mutation helper and vanilla presentation/removal consumers used the aggregate property-key array without retaining the active category's ten-slot layer. The native UI then played its success sound after CIM silently rejected the sibling-layer write. |
| Fix version(s) | Unreleased source candidate |
| Category | SOLO |
| Repro | In the Athanor accessory editor, set Necklace Health to five bubbles. Click Health on Charm and Trinket and confirm each click visibly applies rather than only playing a sound. Right-click Health in each category, then use Clear in one category. |
| Expected post-fix | Each accessory independently admits, shows, and edits its own Health bubbles. Per-key and ten-distinct-property capacity are enforced inside the active layer. Right-click removes from the open accessory; Clear leaves the other two accessories unchanged. Weapon property editing retains its global cap. |
| Detection | Offline `test_cim_accessory_property_policy.lua` performs the production-equivalent sibling-layer store, the layered mastery-costs over-index read, and the re-seed merge/clamp, and passes. `/cim_regression_test` passes `issue959_accessory_property_layers_are_independent`; bounded `[cim:959] property store` rows report `result=stored` with advancing slot indices for each accessory layer, `[cim:959] seed key=... layers=a,b,c` proves both sibling accessories survive an Athanor reopen, and no `[cim:404] _sync_backend_loadout threw` row follows a store. |

---

### canonical-synthetic-item-salvage - issue #628

| Field | Value |
|---|---|
| Symptom | CIM-crafted provider weapons can craft/equip/persist but disappear from Salvage, or unsafe rows are admitted independently of equip, favorite, and saved-loadout state. |
| Root cause | Craft, mirror restore, inventory filtering, and salvage constructed or classified partial item records independently; after those identities were unified, the salvage adapter still iterated vanilla's backend-id keyed input map with `ipairs`, silently visiting zero real items. |
| Fix version(s) | cim_dev 0.8.80-dev |
| Category | SOLO |
| Repro | Craft the three Dawi Maces and one older CWV weapon; inspect inventory/preview/restart/salvage, then repeat while equipped, favorited, or present in any saved loadout. Equip Blightreaper and confirm it never appears on a CIM acquisition or edit surface. |
| Expected post-fix | Every CIM surface consumes one exact CIM-owned identity; only an unequipped, unfavorited, no-loadout Modded instance appears. WOC trophy relics remain provider-owned singletons and are never crafted, edited, mirrored, or salvaged by CIM. |
| Detection | Offline `test_cim_synthetic_item_contract.lua` locks `pairs(items)` at the raw backend-map boundary and `/cim_regression_test` passes `issue628_provider_contract`, `issue628_saved_instance_contract`, and `issue628_salvage_state_diagnostic`. Bounded `[cim:628] salvage_state` rows name the exact instance, rejecting guard, active careers, saved loadouts, favorite, and backend dirty state. |

---

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
| Symptom | Each crafted CWV weapon appears to add another base/blacksmith choice, every CWV selector is absent on initial entry, or native preview/Versus aliases appear beside the same weapon family. |
| Root cause | CWV clones require exact authored identity, but ordinary ItemMasterList helper rows require family identity. The 0.8.76 exact-key catalog restored CWV rows but also admitted ordinary `_preview`/Versus aliases as separate selectors. The final selector later ignored crafted Modded rows for family ownership but still returned them if an upstream mirror/hook leaked them past vanilla `can_craft_with`. |
| Fix version(s) | cim_dev 0.8.72-dev (bounded identity), 0.8.76-dev (pre-enter availability), 0.8.79-dev (craft-family alias dedupe), 0.8.93-dev (shared picker-role contract + final instance exclusion) |
| Category | SOLO |
| Repro | Open the standard Craft Item page directly and inspect Dual Axes, Crowbill, Greataxe, and native Tuskgor Spear; craft Imperial Longsword twice, then leave and reopen the grid. |
| Expected post-fix | Every ordinary weapon family has one deterministic selector; every authored CWV key remains distinct, including veteran/stat variants; Modded-rarity crafts appear only in ordinary inventory. |
| Detection | Offline `test_cim_cwv_template_selector.lua`, `test_cim_cwv_template_catalog.lua`, and `test_cim_synthetic_item_contract.lua` pass; `/cim_regression_test` passes every `issue524_*` check. `[cim:524]` reports the bounded final rendered list and any remaining hard/soft duplicate identities. |

---

### keep-forge-interaction - issue #624

| Field | Value |
|---|---|
| Symptom | The physical forge in the Keep has no interaction prompt in the modded realm even with CIM installed. |
| Root cause | Vanilla `forge_access.can_interact` returns false when `script_data["eac-untrusted"]` is true, before its existing transition callback can open the standard forge. |
| Fix version(s) | cim_dev 0.8.79-dev |
| Category | SOLO |
| Repro | Enter the modded Keep, approach the physical forge, interact, close the view, and repeat with keyboard/mouse or controller. |
| Expected post-fix | The native prompt opens CIM's backend-safe standard forge every time. Official realm and non-Keep behavior remain vanilla. |
| Detection | Offline `test_cim_keep_forge_interaction.lua` passes and `/cim_regression_test` passes `issue624_keep_forge_interaction`; first successful availability emits one `[cim:624]` line. |

### athanor-selector-icon-resource-closure - issue #617

| Field | Value |
|---|---|
| Repro | Open CIM's Athanor weapon selector and scroll until a CWV Dual Axes row using `icon_wpn_axe_hatchet_t1_dual_cwv` becomes visible. |
| Expected post-fix | The list remains open. Every icon passed to `_populate_list` has a masked+saturated material proven in the exact `ui_top_renderer` Gui. Unsafe custom icons use their paired vanilla/base icon; a row with no proven fallback is omitted rather than drawn. |
| CWV paired-icon refinement (#787) | With CWV active, both Kruber and Saltzpyre Dual Axes selectors retain `icon_wpn_axe_hatchet_t1_dual_cwv` through the shared `ingame_ui` top renderer; a failed exact-Gui material proof still takes the single-axe fallback. These synthetic rows do not enter Cosmetics #650's exact-instance compositor. Run `/cim_regression_test` and require `issue787_cim_dual_axes_authored_icon`. |
| Boundedness | One catalog pass per list build; at most one summary plus twelve changed-row diagnostic lines. No per-frame probe, package load, renderer rebuild, RPC, or ItemMasterList mutation. |
| Detection | Offline `test_cim_athanor_icon_policy.lua` proves all nine current CWV paired icons close to vanilla and rejects missing material variants. `/cim_regression_test` passes `issue617_athanor_icon_resource_closure`; `[cim:617] Athanor icon closure` reports `omitted=0` in a healthy live catalog. |

---

### athanor-dynamic-widget-resource-closure - issue #83

| Field | Value |
|---|---|
| Symptom | Opening CIM in a mission and selecting a shield weapon crashes in `HeroWindowWeaveForgeWeapons._draw` because `icon_block_arch_masked` is absent from the mission Gui. |
| Root cause | `_setup_weapon_stats` appends freshly created widgets to `_scrollbars.stats.list_widgets` after `create_ui_elements`; the older safety layer inspected only static `_bottom_widgets`/`_top_widgets` arrays. |
| Fix version(s) | cim_dev 0.8.92-dev |
| Category | SOLO |
| Repro | Enter a mission, open CIM's Athanor, select a melee weapon with a block angle, and leave the stats list visible. |
| Expected post-fix | The view remains open. Only texture passes not resident in the exact top renderer are hidden; safe icons, text and controls remain. Keep rendering is unchanged. |
| Detection | Offline `test_cim_mission_forge_widget_safety.lua` passes and `/cim_regression_test` passes `issue83_dynamic_forge_widget_material_closure`. The log may contain one bounded `[cim:83] suppressed non-resident dynamic forge material` line, never the Gui fatal. |

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

### issue598/921-hold-tab-rarity-convergence - Modded frames follow the current slot item

| Field | Value |
|-------|-------|
| Scope | Hold-Tab rarity backgrounds for the owner and every CIM observer; resource/icon identity remains separately renderer-gated. |
| Source boundary | The vanilla server queues `rpc_sync_loadout_slot` locally as well as sending it to clients, but CIM's `network_send(..., "others", ...)` excludes the sender [src: `network_transmit.lua:508-524`; `loadout_utils.lua:13-42`]. The side-channel cache must therefore be primed locally and retain explicit `false` as distinct from not-yet-received metadata. |
| Solo repro first | Equip a Career Weapon Variants weapon, hold Tab, then equip the Blightreaper and hold Tab. Replace either with a vanilla weapon and hold Tab again. |
| Expected post-fix | A Modded item uses the Modded frame for its owner and observer. A common replacement immediately uses its ordinary frame on both peers; no prior slot occupant leaks through a transition. A peer without CIM still receives only the vanilla-safe `unique` rarity. |
| Co-op follow-up | Only after solo passes: host and client inspect their own and each other's rows, enter the Chaos Wastes so the slot becomes a common-rarity weapon, and repeat in the opposite direction with the Imperial Crowbill. Then repeat with one peer lacking CIM. |
| Detection | Run the offline Lua suite and `/cim_regression_test`; require `issue921_tab_rarity_state_is_tristate` PASS. The bounded `[cim:921]` lines must show `current=false` on the common replacement and no custom resource name on the side-channel path. |

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

### issue277-exact-cim-craft-cleanup - Destructive cleanup fails closed

| Field | Value |
|-------|-------|
| Scope | Only backend IDs present in CIM's exact `_forged_weapons` store whose normalized owner/schema and live ItemMasterList row prove a contract-owned craftable slot: `melee`, `ranged`, `necklace`, `ring` (Charm), or `trinket`. Out-of-scope rows, unresolved definitions, rarity/prefix lookalikes, and ordinary backend items are retained. |
| Safety | `/forge_delete_all` previews and fingerprints the exact cleanup identity: backend ID, owner/schema, canonical item, live slot/provider, and mirror-vs-MIL route. `/forge_delete_all CONFIRM` proceeds only if that identity is unchanged and no candidate appears in a current or saved loadout; uncertainty refuses the entire transaction. Execution revalidates the same contract before mutation. |
| Persistence | The runtime mirror row, legacy MoreItemsLibrary row, CIM forged record, dormant modded-loadout references, and exact-ID illusion override are removed; forge persistence and UI refresh run once per batch. |
| Repro | Craft one weapon plus a necklace, Charm, and trinket. Leave every craft unequipped. Run `/forge_delete_all`, verify the preview counts all four, then run `/forge_delete_all CONFIRM`. Restart and verify none return while ordinary equivalents remain. |
| Negative cases | Equip one CIM craft in any current or saved loadout and confirm the command deletes nothing. Preview, craft another item, then confirm and verify the changed-set guard refuses. Disable a source mod and verify its unresolved record is retained. |
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

### issue618-modded-salvage-autofill — Fifth rarity button preserves nine-slot bound

| Field | Value |
|-------|-------|
| Symptom | The standard Salvage page has no autofill control for CIM's Modded rarity. |
| Root cause | Vanilla defines buttons only for plentiful, common, rare, and exotic, then Clear. |
| Mod(s) | cim_dev |
| Fix version(s) | 0.8.77-dev |
| Category | UI / CRAFTING |
| Repro | Open standard Salvage with at least ten Modded-rarity items and press the pale-gold fifth rarity button. |
| Expected post-fix | Exactly nine matching items fill the queue; Clear remains available as the sixth button. |
| Detection | Engine-free `test_cim_salvage_autofill.lua` checks layout, bounded vanilla dispatch, dedicated crossed-swords texture ID, and full resource packaging; runtime `/cim_regression_test` check `issue618_modded_salvage_autofill`; `[cim:618]` apply/press traces. |

## Slugs

- issue618-modded-salvage-autofill

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
