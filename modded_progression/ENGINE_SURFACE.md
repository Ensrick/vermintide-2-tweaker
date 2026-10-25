# modded_progression - engine contact surface

What vanilla VT2/Stingray does at every seam `modded_progression` (`mp`) touches,
and why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's `PLAN.md` (the roadmap and explicitly historical research) - it
names each engine seam, cites the vanilla behavior, and links out. Decompile
paths are relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`;
`mp` line numbers are `modded_progression.lua` unless noted. `§N` =
a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue. Grep-verified
2026-08-13 against the decompile. Current realm/Emporium corrections below use
6.13.0 source `93dea911`; historical line references are not current gate authority.

`mp` re-enables selected vanilla progression surfaces while the complete local
mission-loot system remains unbuilt. Its target architecture covers XP, loot,
currency, Okri's Challenges, Lohner's, and keep crafting in the modded realm,
storing all owned state in VMF settings and never writing to the real PlayFab
account. [PLAN.md](PLAN.md) preserves the original design and historical research;
this document names current installed seams. Game 6.12+ publishes native
`MODDED_REALM` and sets `GameSettingsDevelopment.read_only_backend`
(`application_parameter.lua:150-152`, `game_settings_development.lua:49-50`).
The latter also protects real PlayFab commits
(`playfab_mirror_base.lua:2826,2839,2857`) and must never be cleared.

Legacy EAC brackets are old-game compatibility only, not modern UI adapters.
Local daily claim/backend interception and plain-SM Emporium transactions exist,
but modern daily-row presentation remains legacy-pending until its separate
adapter lands. The Emporium owner below does not complete daily rows, #607's
mission containers, #589's mixed login rewards or #840's remaining Fresh slices.
The Fresh items/loadouts slice is an MP-owned interface route, not a blanket
canonical-mirror overlay.

## Hook table

Current shared authority (#1693, 0.2.44-dev): MODDED_REALM at
`foundation/scripts/util/application_parameter.lua:150-152` (source 93dea911)
decides before legacy depth, script flags or sibling fallback. Exactly true
permits; present false/malformed denies, and only absence uses the old-game
query. The named check exercises isolated contexts, not a live protection toggle.
This does not implement #1684's local UI adapters or #607's container award/open.

Daily reroll safety (#1684, 0.2.45-dev): `_mp_daily_reroll_runtime.lua` owns
the backend `can_refresh_daily_quest` / `refresh_daily_quest` methods and the
achievement row's `_on_achievement_pressed` action. Native daily replacement
directly enqueues `refreshQuest` without an EAC challenge
(`backend_interface_quests_playfab.lua:193-212`), independently of automatic
`update_quests`. Modded availability is false and direct rerolls are denied;
stale close clicks stop before native input blocking with a nil poll id
(`hero_view_state_achievements.lua:1219-1228`). Only explicitly readable official
authority delegates. No account-protection flag or quest state is changed.
The named isolated check exercises installed callbacks, not a live backend.

Registration sites use `mod:hook` (full wrapper); the current total is reported
by `tools/mod-lint/lint-mod.ps1`, not frozen here. `[hook]` =
full wrapper (can rewrite args/returns). Legacy compatibility calls use
`_with_eac_off` or its Fresh-aware sibling; their counts are not frozen here.
The Fresh items/loadouts route lives in `_mp_fresh_profile_runtime.lua`, and the
Emporium's five seams live in `_mp_emporium_ui_runtime.lua`. The remainder own
local progression/read/claim boundaries. There are no `hook_safe` sites and one
table-form site (the #1637 instance join in the runtime).
The 50 sites whose class and method are both string literals are listed in
`_mp_hook_targets.lua`; `/mp_regression_test` `mp1671_hook_targets_resolve`
fails when a loaded class lacks one of those methods or a class is not loaded
(#1671), and the offline `test_mp_hook_targets_resolve.lua` keeps the list to the source.

### The EAC-window bracket - shared wrapper (row-of-concern: issue 434) (owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `_with_eac_off` (shared wrapper, not a hook) | Pre-6.12 compatibility clears/restores the legacy script flag; it does not bypass modern native gates | Preserve the existing bounded bracket, nested depth and complete return/exception contract (#434) | Native `MODDED_REALM` and `read_only_backend` are never written. Real commit protection in 6.13.0 is `read_only_backend` at `playfab_mirror_base.lua:2826,2839,2857`, not the bracketed legacy key |

### Reward popups + progression UI un-gate (owner doc: `docs/engine/09`, feeds `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `LevelEndViewBase.init` [hook] | Current reward-popup setup is gated by `read_only_backend` [src 6.13.0: `scripts/ui/views/level_end/level_end_view_base.lua:59,231`] | Retains the old-game Fresh-aware compatibility wrapper | LEGACY-PENDING on current native gates; this wrapper does not implement local mission rewards or make them available |
| `HeroViewStateAchievements._create_entries` / `_handle_claim_all_challenges` [hooks] | Native row completion and claim-all visibility read `read_only_backend` [src 6.13.0: `scripts/ui/views/hero_view/states/hero_view_state_achievements.lua:646,2992`] | Retains the existing Fresh-aware legacy presentation wrappers | LEGACY-PENDING: backend-free daily claim routing is not a modern row adapter. The separate daily-row release must own filtering/completion/claim-all without altering native protections |
| `StoreWindowItemPreview._set_unlock_button_states` [hook; `_mp_emporium_ui_runtime.lua`] | Native preview writes buy-button disabled state [src 6.13.0: `scripts/ui/views/hero_view/windows/store/store_window_item_preview.lua:1872-1880`] | After native presentation, enable only an exact current plain-SM offer satisfying native acquisition flags and the local owner contract | Replaces the retired legacy bracket; no global flag changes and no authorization while pending/busy |
| `StoreItemPurchasePopup._create_ui_elements` [hook; `_mp_emporium_ui_runtime.lua`] | Native constructor disables purchase in read-only play [src 6.13.0: `scripts/ui/views/store_item_purchase_popup.lua:1149`] | Update only this owned hotspot after native construction and current offer validation | Replaces the retired legacy bracket. Disabled/enabled presentation is never action authority |
| `HeroViewStateStore.product_purchase_request` [hook; `_mp_emporium_ui_runtime.lua`] | Product routing can reach Steam/DLC before popup creation [src 6.13.0: `scripts/ui/views/hero_view/states/hero_view_state_store.lua:1527-1595`] | Deny unsafe/stale modded products before that routing | Only current validated plain-SM local products proceed; official calls preserve native tuples/errors |
| `StoreItemPurchasePopup._poll_result_on_enter` [hook; `_mp_emporium_ui_runtime.lua`] | Native chooses a currency with `pairs` and calls `exchange_chips`; controller confirm ignores disabled hotspots [src 6.13.0: `scripts/ui/views/store_item_purchase_popup.lua:1524-1547,1557-1584`] | Revalidate the exact live offer and queue the existing local SM transaction instead of native purchase | No DLC/platform/bundle/mixed/non-SM/foreign/stale offer may use this local action |
| `StoreItemPurchasePopup.update` [hook; `_mp_emporium_ui_runtime.lua`] | Native transition invokes on-enter before storing state [src 6.13.0: `scripts/ui/views/store_item_purchase_popup.lua:1065-1084,1224-1254`] | Settle the pending local action after native update so synchronous completion is not overwritten | One current pending owner; revalidate before debit, release abandoned/destroyed popups, contain errors without native purchase fallback |
| `StoreLoginRewardsPopup._create_ui_elements` / `_claim_rewards` + `BackendInterfacePeddlerPlayFab.claim_login_rewards` [hooks] | Popup construction disables the button in modded play; `_claim_rewards` otherwise enters claiming state and calls the peddler method; that method enqueues authenticated `claimStoreRewards` [src: `store_login_rewards_popup.lua:41-59,181-216`; `backend_interface_peddler_playfab.lua:811-828`] | #589 fail-closed boundary: retain/reinforce the disabled UI, intercept direct activation, and reject every modded backend caller before enqueue; official realm is unchanged | Local mixed item/currency transaction is not armed; two runtime checks cover UI + request policy, and textual QA locks both hooks |
| `HeroWindowItemCustomization._enable_craft_button` / `_update_state_craft_button` [hooks] | Native craft visibility and hotspot state read `read_only_backend` [src 6.13.0: `scripts/ui/views/hero_view/windows/hero_window_item_customization.lua:1877-1905,1928`] | Retains the existing Fresh-aware legacy wrapper | Not a current native-menu crafting implementation; keep account protection unchanged and treat a local crafting transaction/presentation adapter as separate work |

### Bounded mission-loot layer diagnostics (issue 607)

`_mp_loot_diag_runtime.lua` owns this complete adapter set; the entry point has
one ordered installer call and no duplicate registration sites.

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceLootPlayfab.generate_end_of_level_loot` [hook] | Builds the mission result request and enqueues `generateEndOfLevelLoot` with an EAC challenge [src: `backend_interface_loot_playfab.lua:153-191`] | Emit the mission-end entry and a post-enqueue census of MP's local inventory | Observation only; forwards every named argument plus trailing args and preserves the full return tuple |
| `BackendInterfaceLootPlayfab.open_loot_chest` [hook] | Resolves the selected chest backend instance, builds `generateLootChestRewards`, and enqueues it [src: `backend_interface_loot_playfab.lua:27-47`] | Emit the Spoils of War entry and local container/use census | Never stores or prints the backend id; does not open or consume anything itself |
| `PlayFabRequestQueue.enqueue` [hook] | Adds metadata, clones the request, and appends it to the local queue before EAC/network dispatch [src: `playfab_request_queue.lua:25-55`] | Attribute only `generateEndOfLevelLoot` and `generateLootChestRewards` at the last pre-network local seam | Calls vanilla exactly once, emits after obtaining the local numeric queue id, preserves the return tuple, and ignores every other request family |
| `BackendManagerPlayFab.playfab_eac_error` / `.playfab_api_error` [hooks] | Convert EAC rejection or API failure into the backend error-dialog path [src: `backend_manager_playfab.lua:553-586`] | Attribute a rejection to the active target request and census the local ledger before vanilla error handling continues | Reads only the active request's function name and EAC state; raw backend error payloads and player ids are never retained |
| `BackendInterfaceLootPlayfab.loot_chest_rewards_request_cb` [hook] | On success, grants returned items/unlocks, consumes the chest, updates `chest_inventory`, and exposes the completed poll [src: `backend_interface_loot_playfab.lua:49-150`] | Preserve the earlier bounded successful-result census as optional R&D evidence | Success is not required for diagnostic readiness; the callback delegates unchanged and remains bounded/sanitized |

The derived result is deliberately capability-honest: after mission entry and
native enqueue, `first_missing=local_container_award`, with
`award_capable=false` and `open_capable=false`. Those values describe the
current implementation boundary, not a fix. The runtime check
`issue607_local_loot_layer_diagnostic_contract` and engine-free
`test_mp_loot_diag.lua` lock request scope, rejection attribution, bounds,
sanitization, local container census, one hook per seam, native delegation,
trailing-argument forwarding, and nil-hole return preservation. All observer
realm/context/store/persistence/logging work is pcall-contained outside the
native call. Planted failures cover all six wrappers and first/middle/trailing
nil returns; `pre_request` requires vanilla to return a finite positive numeric
enqueue id. Observer-failure rows retain only their controlled stage and the
fixed `observer_failed` reason, never raw exception text or identifiers.

The emit gate asks one boolean realm query, `LootDiag.realm_is_modded`, wired
in `modded_progression.lua`: game 6.12.0+ publishes the realm only as the
global `MODDED_REALM` [src: `application_parameter.lua:150-152` at 6.13.0],
which decides whenever it is a boolean; mp's legacy realm query (raw flag,
launch parameter, bracket depth) answers only when it is absent. The gate no
longer reads `script_data["eac-untrusted"]`, which 6.12.0 stopped writing, so
a 0.2.41-dev-style raw-flag gate never opened (issue 1692). Runtime check
`issue1692_loot_diag_gate_open_in_modded_realm` and engine-free
`test_mp_loot_diag_realm_gate.lua` lock both game layouts.

### Vanilla Silver Shilling presentation and local refresh (issue 578; owner docs: `docs/engine/09`, `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `StoreWindowPanel._sync_player_wallet` [hook] | Called by panel update; compares each `get_chips` result with `_currencies`, then rebuilds all wallet widgets only on a changed cached amount [src: `store_window_panel.lua:169-176,601-652`] | Invalidate cached SM on ledger revision/realm edges | Uses the native update call, not a new poll; never rewrites wallet text; official transition forces a clean native rebuild even if both balances are numerically equal |
| `StoreWindowItemPreview._sync_products_version` [hook] | Product-version changes force `_sync_presentation_item`, which recalculates affordability [src: `store_window_item_preview.lua:401-443,872-993`] | Merge the local ledger revision into native product invalidation | Purchase title, tooltip, fake-currency metadata, daily rows, and popups remain entirely vanilla; the actual SM transaction is owned by the #577 boundary below |

Both refresh hooks emit one `[mp:578]` INFO record only when the same scalar
realm/revision policy requests invalidation. These automatic diagnostics are
transaction/transition-bounded and never run as a separate update loop. There
is deliberately no `_G.Localize`, `BackendUtils.get_fake_currency_item`, or
`StoreWindowItemPreview._set_price` presentation hook: modded and official
Silver Shillings use the same native wording and layout.

### Backend-free Emporium purchase (issue 577; owner docs: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfacePeddlerPlayFab.exchange_chips` [hook] | Enqueues `PurchaseItem`; its success callback adds returned items to the mirror, debits chips, then enqueues `storePurchaseMade` [src: `backend_interface_peddler_playfab.lua:661-707`] | For a modded-realm SM offer, validate the live stock row and atomically persist the local debit, exact item, unlock, and duplicate markers before calling the native callback contract | No PlayFab call is made; deterministic transaction/item ids make duplicate callbacks idempotent; official and non-SM calls delegate unchanged |
| `BackendInterfacePeddlerPlayFab.get_peddler_stock` / `.get_filtered_items` [hooks] | Native stock rows derive `owned` from the official mirror [src: `backend_interface_peddler_playfab.lua:152-191`] | Clone plain SM rows and project ownership from the durable MP unlock/inventory state | Native stock is never mutated; platform, bundle, and non-SM rows retain official ownership |
| `HeroViewStateStore._populate_item_widget` / `._populate_pose_item`, `StoreWindowFeatured._get_default_featured_grid_content`, `StoreWindowItemPreview._sync_presentation_item`, `StoreWindowItemList._update_item_list`, `StoreItemPurchasePopup._populate_item_widget` [hooks] | These synchronous presentation paths re-query `BackendInterfaceItemPlayfab.has_item` / `.has_weapon_illusion` after reading stock [src: `hero_view_state_store.lua:1844-1974,2123-2143`; `store_window_featured.lua:608-659`; `store_window_item_preview.lua:883-964`; `store_window_item_list.lua:280-317`; `store_item_purchase_popup.lua:1612-1688`] | Bracket only these calls with a local-ownership facade for eligible SM keys | The bracket restores after success or error; inventory, crafting, loadouts, and official play never consume the facade |
| `mod.update` (revision-gated overlay, not a hook) | Vanilla callbacks classify returned item data through the mirror's normal item/cosmetic/weapon-skin/weapon-pose mutators [src: `playfab_mirror_base.lua:2494-2544`] | Reapply persisted MP grants when the mirror becomes ready or its local revision changes, so existing store/inventory consumers see native-shaped records | Unchanged frames compare one scalar and allocate no tables; a failed overlay retries, and official transition removes only tracked MP instance ids. #840: while the Fresh items route is active the overlay is skipped (`fresh_routed`) and any applied rows are cleaned up; the Fresh view carries the durable Emporium grants itself |

### Isolated Fresh profile: items/loadouts route (issue 840; owner doc: `docs/engine/11`)

`_mp_fresh_profile_runtime.lua` owns all 22 class hooks plus the one
table-form instance join site; the entry point has one `install` call and
never hooks a routed method itself (offline `test_mp_fresh_profile_routing.lua`
locks both).

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceItemPlayfab.get_item_from_id` [hook, Fresh-first lookup] | `get_all_backend_items()[backend_id]` [src: `backend_interface_item_playfab.lua:384-389`]; the reader every spawn, inventory, hero-view, crafting-preview and loadout-sync path uses to turn a loadout id into a record [src: `backend_utils.lua:30-46`; `simple_inventory_extension.lua:375-391,883`; `gear_utils.lua:601`] | Answer from the Fresh view directly (issue 1637) instead of depending on the hook topology of `get_all_backend_items`; a miss continues down the chain so sibling synthetic ids still resolve, and the chain's vanilla tail reads the routed root | The derived readers `get_item_rarity` / `get_item_power_level` / `get_traits` / `get_skin` / `get_key` / `get_item_masterlist_data` / `get_item_amount` call this through `self:` [src: `backend_interface_item_playfab.lua:320-382`] and are NOT hooked. A handler throw latches `official:fault` and delegates |
| live items interface instance, every routed method a sibling shadowed (table-form `mod:hook(instance, method, wrapper)` from `R.tick`) | A sibling that hooks the INSTANCE gets a separate VMF chain whose tail is the vanilla method: the origin is remapped through `_registry.uids` and `create_internal_hook` installs a raw field on the instance [src: vmf `hooks.lua:106-120,176-193,305-308`]; `get_loadout_interface_by_slot` and `get_interface("items")` both return that instance [src: `backend_manager_playfab.lua:201-208,329-341`] | Join the instance chain with the same wrapper closure the class hook uses (issue 1637: Tweaker: Weapons Dev and Tweaker: Cosmetics shadow `get_loadout` / `get_loadout_item_id`, Weapons Dev also the loadout writes), so a call through the instance reaches the same per-call decision | Once per (instance, method), weak-keyed by instance; one bounded `[mp:fresh] instance_join methods=...` receipt per batch; never installed while the route is unresolved; `mp840_fresh_route_instance_shadows_joined` proves every live shadow is joined |
| `BackendInterfaceItemPlayfab.get_all_backend_items` / `.get_all_fake_backend_items` / `.get_loadout` / `.get_bot_loadout` / `.get_career_loadouts` / `.get_selected_career_loadout` / `.get_default_loadouts` / `.get_default_override` / `.get_loadout_item_id` / `.get_backend_id_from_cosmetic_item` / `.get_unlocked_weapon_poses` / `.get_equipped_weapon_pose_skins` / `.get_equipped_weapon_pose_skin` / `.sum_best_power_levels` / `.equipped_by_loadout` / `.is_equipped_by_any_loadout` [hooks] | The root reads of the items interface refresh from and return the canonical mirror's inventory, fake cosmetic rows, and per-career character data [src: `backend_interface_item_playfab.lua:37-160,384-544,760-800,894-902`]; every consumer reaches this one object through `get_interface("items")` or the loadout override registry [src: `backend_manager_playfab.lua:201-209,329-341`] | Serve the MP-owned Fresh view (seeded once per profile generation) only when modded realm + `starting_state == "fresh"` + boot-time resolution + no fault all hold; otherwise delegate to the original method | Per-call decision, no native mutation, so every exit path (setting, realm, disable, fault, re-enable) is a restore. `get_loadout_item_id` never answers an equipment id the same view cannot resolve: it falls back to the seeded career default, else nil, with one bounded `slot_fallback` receipt per (career, slot, id) (issue 1637). Derived methods (`get_filtered_items`, `has_item`, `equipped_by`, `get_cosmetic_loadout`, `get_loadout_by_career_name`, ...) follow through `self:` and are NOT hooked (the two existing `has_item` / `has_weapon_illusion` hooks from #577 stay the only entry-point hooks on this class). A handler throw latches `official:fault` and delegates; mechanism default loadouts (versus) return nil under Fresh |
| `BackendInterfaceItemPlayfab.set_loadout_item` / `.set_loadout_index` / `.add_loadout` / `.delete_loadout` / `.set_weapon_pose_skin` [hooks] | Validate against the item map, then write the mirror's character data / loadout index / pose skin [src: `backend_interface_item_playfab.lua:257-276,587-602,635-670`; `playfab_mirror_base.lua:1928-1942,1968-2068,2253-2255`] | Commit copy-on-write to the persisted profile with vanilla's validation (unknown item, `magic` rarity, cosmetic slots store the item key) and never touch the native mirror | A failed persist discards the copy and returns the vanilla failure value (`false` / nil) without delegating, so official state stays byte-identical and the route stays active; `mp840_fresh_route_write_never_touches_native` checks this in-game |
| `_with_eac_off_unless_fresh` + inline `_create_entries` / `_handle_claim_all_challenges` variants (wrapper, not a hook) | Current level-end, achievement row/claim-all and crafting sites read `read_only_backend` [src 6.13.0: `level_end_view_base.lua:59`; `hero_view_state_achievements.lua:646,2992`; `hero_window_item_customization.lua:1878,1928`] | Retains old-game Fresh isolation behavior: do not clear even the legacy flag for un-routed Fresh slices | The old bracket on daily rows is not a current row adapter. Keep those rows legacy-pending and native protection intact until their separate owned implementation |

### Achievement progress tracking (row-of-concern) (owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `AchievementManager.trigger_event` [hook] | Current native tracking returns when `read_only_backend` is true; platform update also checks it [src 6.13.0: `scripts/managers/achievements/achievement_manager.lua:128-130,298`] | Retains the pre-6.12 legacy compatibility wrapper and its #434 throw/tuple contract | Does not bypass current tracking gates. Never clear the native protection or enable platform writes to make local challenges progress |

### Simulated daily ownership and claim (issue 568; owner doc: `docs/engine/11`)

Backend ownership/claim boundaries below are not a claim that the modern rows
are integrated. `_create_entries` / `_handle_claim_all_challenges` remain
legacy-pending until the separate daily-row adapter release; Emporium does not
change them or the daily-reroll safety owner.

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceQuestsPlayfab.get_quests` / `get_quest_key` / `get_quest_by_key` [hooks] | Supplies quest records and maps display ids to backend keys [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:153-161,740-798`] | Replace the modded-realm daily slice with persisted, namespaced `mp_daily_*` copies while leaving official-realm reads untouched | An MP id resolves only through the local ownership store; a vanilla id is never locally granted |
| `HeroViewStateAchievements._claim_quest_reward` / `_claim_multiple_quest_rewards` [hooks] | Calls `QuestManager.can_claim*` then `claim_reward` / `claim_multiple_quest_rewards` [src: `scripts/ui/views/hero_view/states/hero_view_state_achievements.lua:1324-1351`] | Stop single and claim-all at the UI boundary, atomically persist local reward + idempotency marker, and return a synthetic poll id | Exact issue-568 escape seam. Unknown/official ids are rejected in modded play; official realm delegates vanilla |
| `BackendInterfaceQuestsPlayfab.get_quest_rewards` [hook] | Returns completed backend poll loot for native reward presentation [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:810-812`] | Resolve one-shot synthetic local poll rewards so the native UI presents and refreshes immediately | Synthetic entries are removed on read to keep the transient map bounded |
| `BackendInterfaceQuestsPlayfab.claim_quest_rewards` / `claim_multiple_quest_rewards` [hooks] | Enqueues `generateQuestRewards` through the PlayFab request queue [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:285-302,500-522`] | Defense-in-depth suppression for any missed modded-realm caller | No quest identity may reach these methods from MP's modded surface; official realm delegates vanilla |

## Subsystem notes (how the vanilla flow runs end-to-end, for mp's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and `PLAN.md` carry the full architecture.

### Legacy bracket compatibility, not current protection (owner: `docs/engine/11`)

The pre-6.12 EAC bracket remains balanced, nested and throw-safe (#434); that
historical contract is worth preserving. It is not a 6.13.0 UI or backend bypass.
Shared realm V2 queries native `MODDED_REALM` before legacy inputs, and modern
commit suppression reads `GameSettingsDevelopment.read_only_backend` at
`playfab_mirror_base.lua:2826,2839,2857`. Neither native field may be changed.
New local features require exact owned presentation/action and transaction
boundaries, not another flag-clearing wrapper. The Emporium owner below is one
bounded example, not authorization for unrelated progression routes.

### Backend mirror and owned local projections (owner doc: `docs/engine/11`)

The canonical mirror contains official account state. #577 commits the local
SM purchase transaction to VMF settings before projecting that exact item's
owned inventory/unlock data; it does not isolate an entire profile. #840's
implemented Fresh items/loadouts route uses `_mp_fresh_profile_runtime.lua`
and `_mp_fresh_profile_state.lua` without mutating the native mirror.
The entry's `apply_mirror_overlay` and generic serialization helpers remain
disabled/stubbed; do not wire a blanket overwrite or mark Fresh seeded.
XP/talents, currencies/store and crafting/loot/decorations isolation remain
separate slices in [PLAN.md](PLAN.md#fresh-profile-isolation-boundary-840).

### Sibling API surface (owner: `docs/engine/11`; detail: `docs/CROSS_MOD_ARCHITECTURE.md` Mod 4)

`mp` exposes `is_unlocked` / `mark_unlocked` / `has_currency` / `spend` /
`credit` / `get_currency` / `grant_item` on the `mod` table (`:311`-`:349`) for
`character_weapon_variants` and `cosmetics_tweaker` to consult via `get_mod("mp")`
[src: `docs/CROSS_MOD_ARCHITECTURE.md:311-331`]. Pre-seed, `is_unlocked` returns
true (don't gate anything before the realm is seeded), so siblings never break
during scaffolding. Cross-mod refs resolve against the stable `mp` id (there is no
`mp_dev` clone). The consuming gates (CWV `can_wield`, cosmetics illusion/portrait
unlocks) live in those mods, not here.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `PLAN.md` (research findings, risks) and the code comments - do not
re-discover these.

- **No global protection bypass.** In 6.13.0, `read_only_backend` protects
  statistics/weave/weapon-pose commits at `playfab_mirror_base.lua:2826,2839,2857`.
  Clearing the legacy key does not bypass it, and clearing the native flag is
  forbidden. Preserve the legacy bracket's restore-on-throw contract only for
  compatibility; it is not a new-feature implementation strategy.
- **A claim button alone is not local progression.** Current native tracking and
  row/claim-all gates are separate read-only sites
  (`achievement_manager.lua:128-130,298`;
  `hero_view_state_achievements.lua:646,2992`). Daily claim backend isolation
  does not prove modern row completion/filtering or full achievement tracking.
- **Loot-rolling probabilities are server-side and not in the Lua tree.** The
  chest-open / property-roll / trait-roll weight tables live in PlayFab
  CloudScript, not `scripts/`. Issue #607 explicitly rejects hand-tuned
  approximations: its behavioral implementation remains unbuilt until the
  rarity, eligibility, property/trait, power, DLC, and duplicate contracts are
  source-backed. v0.2.35-dev diagnoses the first missing local layer without
  depending on a successful callback (PLAN.md research #6).
- **`crafting_recipes` / `CraftingData` are `dofile`-referenced but absent from
  the extracted source.** They must be dumped from the running game
  (`dofile + table.dump`) before the crafting-bench interception can be authored -
  they are not in the decompile (PLAN.md research #1, "Items still gated on a
  runtime dump").
- **The Spoils of War hotkey gate is not worth un-gating (#1671).** mp hooked
  `IngameUI.not_in_modded` from 0.2.0-dev to keep the loot hotkey open; game
  6.12.0 removed it and `hotkey_loot` now names `can_open_loot`
  (`not GameSettingsDevelopment.read_only_backend`, which `MODDED_REALM` forces
  true) [src 6.13.0: `scripts/ui/views/ingame_ui_settings.lua:818`,
  `ingame_ui.lua:381-382,459,469`, `scripts/settings/game_settings_development.lua:49-50`].
  Retargeting would open a screen with nothing to open: 6.13.0 greys both chest
  Open buttons on the same flag and the press path needs them enabled
  [src: `scripts/ui/views/hero_view/states/hero_view_state_loot.lua:1193-1199,1577`],
  and mp neither awards nor opens containers locally
  (`_mp_loot_diag.lua:20-21`). 0.2.41-dev deletes the dead hook; the hotkey and
  the keep's `loot_access` interaction
  (`scripts/unit_extensions/generic/interactions.lua:2301-2302`) stay
  vanilla until #607 has a local chest open.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if an mp hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc owns current installed seams; `PLAN.md` preserves the
roadmap/interception map and explicitly labeled historical research. Historical
proposals are not current authorization to clear flags or overwrite the mirror. The realm, Emporium, daily-row, crafting and achievement gate citations above
were checked against game 6.13.0 source `93dea911`. Other inherited citations
retain their historical scope; resolve by function name against the current
source before changing a seam, rather than treating a historical flag as current.
Section shape (hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".

## Local Silver Shilling action boundary (#1684/#577)

`_mp_emporium_ui_runtime.lua` replaces only the preview unlock and popup-create
legacy brackets. A current plain-SM stock row and all native acquisition flags
are required before a preview authorization is minted; stock/data/price changes,
missing DLC, local ownership, insufficient funds and pending work fail closed.
DLC/platform, bundles, mixed currency, non-SM and foreign products are not enabled.

`HeroViewStateStore.product_purchase_request` is guarded before its Steam/DLC
branches (`hero_view_state_store.lua:1527-1595`). Controller confirmation ignores
the popup disabled hotspot (`store_item_purchase_popup.lua:1524-1547`), so
`_poll_result_on_enter` independently revalidates instead of delegating to native
currency selection / `exchange_chips` (`:1557-1584`). The existing SM transaction
is shared by a local function; no new backend writer is introduced.

Native `_change_state` invokes on-enter before storing its new state (`:1065-1084`).
Because the local exchange callback is synchronous, the adapter settles after
native `update` returns (`:1224-1254`), preventing approved/exit from being
clobbered back to poll_result. One current authorization and one pending popup
are retained; no RPC, backend flag spoofing or broad UI replacement is used.
The named runtime smoke uses detached test state and never purchases a live item.

The shared local transaction also preserves both `pcall` results when checking
an owned required DLC. Combining `unlock and pcall(...)` collapsed its ownership
result to nil; the actual-ledger required-DLC test locks the corrected tuple.
