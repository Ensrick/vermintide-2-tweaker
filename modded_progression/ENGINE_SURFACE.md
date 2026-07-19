# modded_progression - engine contact surface

What vanilla VT2/Stingray does at every seam `modded_progression` (`mp`) touches,
and why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's `PLAN.md` (the full re-enable design, interception map, build order) - it
names each engine seam, cites the vanilla behavior, and links out. Decompile
paths are relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`;
`mp` line numbers are `modded_progression.lua` unless noted. `§N` =
a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue. Grep-verified
2026-07-13 against the decompile.

`mp` re-enables vanilla progression (XP, loot, currency, Okri's Challenges,
Lohner's, keep crafting) in the modded realm, storing all state in VMF settings
and never writing to the real PlayFab account. Its core architectural insight
(`PLAN.md` "Core architectural insight") is that `script_data["eac-untrusted"]`
is NOT one master gate: the PlayFab commit-suppression sites keep the real
account safe and must stay live, while a separate set of UI sites merely grey out
buttons and skip reward popups. `mp` therefore flips the flag to nil only inside
a bracketed window around each vanilla UI/progression call, restores it on every
exit path, and leaves the commit-suppression gate untouched. As of v0.2.24-dev,
simulated daily claims and Silver Shilling Emporium purchases have fully local
backend interceptions; the remaining routes in `PLAN.md` are not yet wired.

## Hook table

29 registration sites, all `mod:hook` (full wrapper). `[hook]` =
full wrapper (can rewrite args/returns). Eight route through the shared
`_with_eac_off` wrapper, one (`IngameUI.not_in_modded`) is a flat return-true
override, and the remainder own local progression/read/claim boundaries. There are no
`hook_safe` sites and no table-form hooks. The
`_with_eac_off` wrapper is a single load-bearing row-of-concern (issue 434) called
out below and shared by all eight of its callers.

### The EAC-window bracket - shared wrapper (row-of-concern: issue 434) (owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `_with_eac_off` (shared wrapper, not a hook) `:390` | - | Clears `script_data["eac-untrusted"]` to nil, runs the wrapped vanilla body under `pcall`, then restores the flag AND decrements `mod._mp_eac_depth` on EVERY exit path, re-raising any error transparently | ROW-OF-CONCERN. A throw inside the body must not leak `eac-untrusted = nil` globally: the commit-suppression sites `playfab_mirror_base.lua:2826`/`:2839`/`:2857` gate real-account statistics/weave/item writes on that exact flag [src verified], so a leaked nil re-enables the writes `mp` exists to prevent (issue 434; regression `eac_flag_restored_after_throw` `:412`). Multi-return preserved via `select("#")` + explicit `unpack` bounds - nil-hole collapse class that burned weapon_tweaker v0.12.77/.78 |

### Reward popups + progression UI un-gate (owner doc: `docs/engine/09`, feeds `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `LevelEndViewBase.init` [hook] `:430` | Builds the end-of-mission reward reel (level-up, deed, deus, keep-decoration, event, win-track, versus-level-up); each popup is skipped in init when `is_untrusted` is true [src: `scripts/ui/views/level_end/level_end_view_base.lua:59-71` per PLAN.md] | Run the body with the flag cleared so the reward popups the modded realm earned actually display (`:430`) | Wrapped in `_with_eac_off`; hot-ish (once per mission end) but not per-frame |
| `HeroViewStateAchievements._create_entries` [hook] `:435` / `_handle_claim_all_challenges` [hook] `:436` | Okri's Challenges list: `_create_entries` sets the `completed`/claimable flag per entry (`:646`); `_handle_claim_all_challenges` gates the claim-all button (`:2992`) [src: `scripts/ui/views/hero_view/states/hero_view_state_achievements.lua`, lines per PLAN.md] | Un-gate the challenge list + claim-all so earned challenges are claimable (`:435`) | Two distinct methods on one class, no hook collision; both `_with_eac_off` |
| `StoreWindowItemPreview._set_unlock_button_states` [hook] `:442` | Lohner's Emporium: enables/disables the buy button (`:1873`) [src: `scripts/ui/views/store/windows/store_window_item_preview.lua` per PLAN.md] | Enable the buy button for currency the modded realm holds (`:442`) | `_with_eac_off` |
| `StoreItemPurchasePopup._create_ui_elements` [hook] `:443` | Emporium purchase-confirm popup buy-button disable flag (`:1149`) [src: `scripts/ui/views/store/store_item_purchase_popup.lua` per PLAN.md] | Enable the confirm-buy button (`:443`) | `_with_eac_off` |
| `StoreLoginRewardsPopup._create_ui_elements` / `_claim_rewards` + `BackendInterfacePeddlerPlayFab.claim_login_rewards` [hooks] | Popup construction disables the button in modded play; `_claim_rewards` otherwise enters claiming state and calls the peddler method; that method enqueues authenticated `claimStoreRewards` [src: `store_login_rewards_popup.lua:41-59,181-216`; `backend_interface_peddler_playfab.lua:811-828`] | #589 fail-closed boundary: retain/reinforce the disabled UI, intercept direct activation, and reject every modded backend caller before enqueue; official realm is unchanged | Local mixed item/currency transaction is not armed; two runtime checks cover UI + request policy, and textual QA locks both hooks |
| `HeroWindowItemCustomization._enable_craft_button` [hook] `:449` / `_update_state_craft_button` [hook] `:450` | Vanilla keep crafting bench: `_enable_craft_button` flips the `enable` arg false in modded (`:1878`); `_update_state_craft_button` sets the button-hotspot disable flag (`:1928`) [src: `scripts/ui/views/hero_view/windows/hero_window_item_customization.lua` per PLAN.md] | Re-enable the keep bench craft button so vanilla-cost crafting works (`:449`) | `_with_eac_off`; cim owns the Athanor sandbox, mp owns the keep bench (`docs/CROSS_MOD_ARCHITECTURE.md` Mod 4) |
| `IngameUI.not_in_modded` [hook] `:454` | Returns `not script_data["eac-untrusted"]` - a generic "is this a trusted UI surface" query [src: `scripts/ui/views/ingame_ui.lua:381-382` verified] | Force-return true so generic UI surfaces treat the session as trusted (`:454`) | The ONLY hook that is a flat override, not an `_with_eac_off` bracket - it does not touch the global flag, so no commit-suppression exposure |

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
| `mod.update` (revision-gated overlay, not a hook) | Vanilla callbacks classify returned item data through the mirror's normal item/cosmetic/weapon-skin/weapon-pose mutators [src: `playfab_mirror_base.lua:2494-2544`] | Reapply persisted MP grants when the mirror becomes ready or its local revision changes, so existing store/inventory consumers see native-shaped records | Unchanged frames compare one scalar and allocate no tables; a failed overlay retries, and official transition removes only tracked MP instance ids |

### Achievement progress tracking (row-of-concern) (owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `AchievementManager.trigger_event` [hook] `:460` | The entry point for EVERY achievement progress event (kill counts, mission completion, tome/grim, etc.); returns immediately when `DEDICATED_SERVER or script_data["eac-untrusted"]` is true [src: `scripts/managers/achievements/achievement_manager.lua:124-125` verified] | Run the body with the flag cleared so challenge progress counters actually tick - without this, un-gating the claim button gets nothing (PLAN.md research #3) (`:460`) | ROW-OF-CONCERN: highest throw-exposure `_with_eac_off` caller (hot per-mission path) - this is the fn issue 434's restore-on-throw exists to protect. The `DEDICATED_SERVER` half of the gate still holds (only the `eac-untrusted` half is flipped). `AchievementManager.update` (`:294`, the Steam platform-push loop) is deliberately LEFT gated - local tracking needs no Steam push [src: `achievement_manager.lua:294` verified] |

### Simulated daily ownership and claim (issue 568; owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why mp hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceQuestsPlayfab.get_quests` / `get_quest_key` / `get_quest_by_key` [hooks] | Supplies quest records and maps display ids to backend keys [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:153-161,740-798`] | Replace the modded-realm daily slice with persisted, namespaced `mp_daily_*` copies while leaving official-realm reads untouched | An MP id resolves only through the local ownership store; a vanilla id is never locally granted |
| `HeroViewStateAchievements._claim_quest_reward` / `_claim_multiple_quest_rewards` [hooks] | Calls `QuestManager.can_claim*` then `claim_reward` / `claim_multiple_quest_rewards` [src: `scripts/ui/views/hero_view/states/hero_view_state_achievements.lua:1324-1351`] | Stop single and claim-all at the UI boundary, atomically persist local reward + idempotency marker, and return a synthetic poll id | Exact issue-568 escape seam. Unknown/official ids are rejected in modded play; official realm delegates vanilla |
| `BackendInterfaceQuestsPlayfab.get_quest_rewards` [hook] | Returns completed backend poll loot for native reward presentation [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:810-812`] | Resolve one-shot synthetic local poll rewards so the native UI presents and refreshes immediately | Synthetic entries are removed on read to keep the transient map bounded |
| `BackendInterfaceQuestsPlayfab.claim_quest_rewards` / `claim_multiple_quest_rewards` [hooks] | Enqueues `generateQuestRewards` through the PlayFab request queue [src: `scripts/managers/backend_playfab/backend_interface_quests_playfab.lua:285-302,500-522`] | Defense-in-depth suppression for any missed modded-realm caller | No quest identity may reach these methods from MP's modded surface; official realm delegates vanilla |

## Subsystem notes (how the vanilla flow runs end-to-end, for mp's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and `PLAN.md` carry the full architecture.

### Why the flag is bracketed, not globally cleared (owner: `docs/engine/11`)

`script_data["eac-untrusted"]` gates two unrelated things (PLAN.md "Core
architectural insight"): (1) UI button-greying / popup-skipping - the ~10 sites
`mp` un-gates, harmless to flip; (2) PlayFab commit suppression at
`playfab_mirror_base.lua:2826` (statistics), `:2839` (weaves), `:2857` (items)
[src verified], the sites that keep the real account safe. `mp` must NEVER leave
that flag nil outside a wrapped call, or a real-account write leaks out - the
exact thing the mod exists to prevent. Hence `_with_eac_off` (`:390`) clears the
flag, runs one vanilla body, and restores it, with a `pcall`+re-raise so a throw
cannot skip the restore (issue 434). The `mod._mp_eac_depth` counter mirrors the
bracket so `mod.is_eac_window()` (`:379`) can tell a sibling (cosmetics' #174
chokepoint) whether the realm is currently un-gated. `IngameUI.not_in_modded` is
the one exception: it reads the flag but `mp` overrides the RETURN, never the
global, so it carries no suppression exposure.

### Backend mirror as the single source of truth (owner: `docs/engine/11`)

The in-memory `backend_mirror` is what inventory, ownership, and equipment
consumers read. Issue #577 wires the first durable inventory slice: the local
transaction is committed to VMF settings first, then its exact item record is
classified through the same mirror mutator family as vanilla. The overlay is
re-applied over a fresh mirror after boot and removed on official transition.
Other progression slices remain backed directly by the currency/unlock/inventory
stores (`:195`-`:349`) until their planned interceptions land.

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

- **`eac-untrusted` is not a single switch you can leave off.** Clearing it
  globally re-enables real-account PlayFab commits at
  `playfab_mirror_base.lua:2826`/`:2839`/`:2857`. The flag must be flipped only
  inside a bracket that restores it on every path including a throw (issue 434) -
  a leaked nil silently defeats the mod's whole non-destructive premise.
- **Un-gating the claim button alone does nothing.** Okri's Challenge progress is
  separately halted at `AchievementManager.trigger_event` (`:124-125`), so the
  claim popup shows zero progress until the tracking hook also runs the body. Both
  the UI gate AND the tracking gate must be un-gated (PLAN.md research #3).
- **Loot-rolling probabilities are server-side and not in the Lua tree.** The
  chest-open / property-roll / trait-roll weight tables live in PlayFab
  CloudScript, not `scripts/`. `mp` can only ship a hand-tuned local
  approximation (VMF sliders) or dump PlayFab title-data at sign-in; it cannot
  reproduce the official rolls exactly (PLAN.md research #6, "Risks").
- **`crafting_recipes` / `CraftingData` are `dofile`-referenced but absent from
  the extracted source.** They must be dumped from the running game
  (`dofile + table.dump`) before the crafting-bench interception can be authored -
  they are not in the decompile (PLAN.md research #1, "Items still gated on a
  runtime dump").

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if an mp hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc complements, and must not duplicate, `PLAN.md` (the full
re-enable design + interception map) - when the interception layer lands, `PLAN.md`
is the primary and this doc gains the `BackendInterface*Playfab` rows. Per-view UI
gate interior lines (`level_end_view_base.lua:59-71`, `hero_view_state_achievements`
`:646`/`:2992`, the store/customization lines) are cited from `PLAN.md`'s decompile
research; the load-bearing flag/commit sites (`not_in_modded`, `trigger_event`,
`playfab_mirror_base.lua:2826/2839/2857`) were re-verified this pass. Line numbers
are against the 2026-07-12 decompile - match crash logs by function name, not line.
Section shape (hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
