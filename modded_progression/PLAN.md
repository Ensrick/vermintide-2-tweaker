# Modded Progression — Plan

Internal id: `mp`. Single VMF mod that re-enables 100% of vanilla Vermintide 2's progression systems in the modded realm, with all state persisted locally and the player's real PlayFab account untouched.

## Goal

Make modded realm a fully distinct, self-contained progression universe. Earn XP, level careers, accumulate currency, open chests, claim Okri's Challenges, buy from Lohner's, craft and salvage at the keep bench — all the systems vanilla offers, all working, all writing to local VMF settings instead of PlayFab.

No new systems invented. Vanilla only.

## Scope

**In**
- End-of-mission rewards: XP, shillings, loot chests, deed rewards, win-track XP, weekly-event drops, level-up rewards.
- Loot-chest opening: items + skins + cosmetics + weapon poses.
- Okri's Challenges: progress tracking and reward claiming.
- Lohner's Emporium: purchase with shillings / versus currency / event currencies.
- Daily login rewards.
- Vanilla keep crafting bench: forge new item, salvage, re-roll properties, re-roll trait, upgrade rarity.
- Per-career XP / level / level-up unlocks.
- Three starting-state options (fresh / level 35 default / level 35 everything unlocked).
- Sibling integration API: `mp.is_unlocked(...)` for `character_weapon_variants` and `cosmetics_tweaker` to gate items behind earned unlocks.

**Out**
- Chaos Wastes economy bridge — CW already routes through the vanilla pipeline; once `mp` un-gates that pipeline, CW completions credit campaign progress for free.
- Multiplayer state sync — single-player local only.
- Versus-mode XP / win-track in v0.1.x.
- Any non-vanilla currency, system, NPC, or UI surface.

## Core architectural insight

`script_data["eac-untrusted"]` is not the master gate. Two distinct things happen in modded:

1. **PlayFab commit suppression** — `playfab_mirror_base.lua:2826,2839,2857` — already prevents writes from leaving the client. **Keep gated.** This is what makes `mp`'s mirror writes non-destructive to the real account.
2. **UI button greying + popup skipping** — ~10 `eac-untrusted` checks in UI files disable click handlers and skip reward popups. **Override per-site.**

The actual loot / XP / currency pipeline is **not** Lua-gated. It runs in modded; the PlayFab CloudScript calls go out and are server-side rejected. The strategy: **intercept each `BackendInterface*Playfab` method before it queues to PlayFab, generate the data locally, call the same `backend_mirror:*` mutator the success callback would have called.**

The backend mirror is the in-memory truth for every UI screen, every `can_wield` check, every level read, every currency display. If our local-rolled data flows through the same mirror mutators, the rest of the game cannot tell the difference.

## Vanilla data flow (verified)

```
Mission ends
  → Rewards:award_end_of_level_rewards()                      (rewards.lua:31)
  → Rewards:_award_end_of_level_rewards()                     (rewards.lua:59)
        builds mission_results (XP per kill/grim/tome/multiplier)
  → Rewards:_generate_end_of_level_loot()                     (rewards.lua:452)
  → BackendInterfaceLootPlayfab:generate_end_of_level_loot()  (loot_playfab.lua:153)
        enqueues PlayFab CloudScript "generateEndOfLevelLoot"
        ─── INTERCEPT HERE ───
  → end_of_level_loot_request_cb()                            (loot_playfab.lua:192)
        backend_mirror:add_item(...)                  items
        backend_mirror:add_keep_decoration(...)       paintings
        backend_mirror:add_unlocked_weapon_skin(...)  skin unlocks
        backend_mirror:set_essence(...)               essence
        peddler_interface:set_chips("SM", new_total)  shillings
        backend_mirror:set_read_only_data(hero.."_experience", v, true)
```

## Interception map

| Action | PlayFab call to intercept | Mirror callback to replicate locally |
|---|---|---|
| End-of-mission rewards | `generateEndOfLevelLoot` | `end_of_level_loot_request_cb` (loot_playfab.lua:192) |
| Open loot chest | `generateLootChestRewards` | `loot_chest_rewards_request_cb` (loot_playfab.lua:49) |
| Claim Okri's achievement (single) | `generateAchievementRewards` | `achievement_rewards_request_cb` (loot_playfab.lua:478) |
| Claim achievements (batch) | (same) | `claim_multiple_achievement_rewards_request_cb` (loot_playfab.lua:678) |
| Claim quest/daily (single) | `generateQuestRewards` | `BackendInterfaceQuestsPlayfab.claim_quest_rewards` (`backend_interface_quests_playfab.lua:285`) |
| Claim quests/dailies (batch) | `generateQuestRewards` | `BackendInterfaceQuestsPlayfab.claim_multiple_quest_rewards` (`backend_interface_quests_playfab.lua:500`) |
| Lohner's purchase | `PurchaseItem` + `storePurchaseMade` | `_exchange_chips_success_cb` (peddler_playfab.lua:676), `_store_purchase_made_cb` (peddler_playfab.lua:723). **Implemented for SM offers in #577:** exact local offer validation + one durable debit/grant transaction + native mirror overlay; official/non-SM delegate unchanged. |
| Daily login rewards | `claimStoreRewards` | `_claim_store_rewards_cb` (peddler_playfab.lua:830). **Current #589 safety boundary:** popup remains disabled and both UI/backend claim methods fail closed in the modded realm; do not re-enable until this mixed item/currency callback has a durable local transaction. |
| Forge / salvage / re-roll / upgrade | `BackendInterfaceCraftingPlayfab.*` | (open research — item #1) |

## UI gates to override

Each is a one-line VMF hook returning the opposite of `script_data["eac-untrusted"]` at the read site:

| Site | What it un-gates |
|---|---|
| `level_end_view_base.lua:59-71` | Reward-popup setup (level-up, deed, deus, keep-decoration, event, win-track, versus-level-up rewards) |
| `hero_view_state_achievements.lua:646,2992` | Okri's challenge claim button |
| `store_window_item_preview.lua:1873`, `store_item_purchase_popup.lua:1149`, `store_login_rewards_popup.lua:57` | Buy / claim buttons in Lohner's |
| `hero_window_item_customization.lua:1878,1928` | Crafting bench "craft" button |
| `hero_window_weave_properties.lua:1895`, `hero_window_weave_forge_overview.lua:985` | Athanor essence-craft buttons (cim already routes around these) |
| `ingame_ui.lua:382` | Generic UI surface enable |
| `achievement_manager.lua:125` (`trigger_event`) | **Achievement progress tracking** — entry point for every progress event; halted in modded. Un-gating this is what makes Okri's Challenges actually advance. Confirmed in research item #3 |
| `achievement_manager.lua:294` (`update`) | Platform achievement push loop (Steam etc.). Not strictly needed for `mp` (local achievement tracking is enough) — leave gated unless we want Steam to register the achievements |

## Local persistence model

PlayFab sign-in still happens in modded; the mirror initializes from the **real account**. `mp` overlays the modded shadow on top of that fresh-loaded mirror at game-start, then re-serializes to VMF settings on every mutation.

**Mirror fields serialized to VMF settings:**
- `_read_only_data[hero_name .. "_experience"]` × 20 careers, plus `_experience_pool`
- `_inventory_items` (items map keyed by backend_id) — modded-earned additions
- `_unlocked_weapon_skins`, `_unlocked_cosmetics`, `_unlocked_weapon_poses`
- `_keep_decorations`
- `_claimed_achievements`
- `_essence`
- Peddler chips (`SM`, `VS`)
- `chest_inventory` read-only-data key
- `_career_data` / `_characters_data` (loadout + talent picks)

**Boot sequence (modded):**
1. VT2 boots, PlayFab sign-in completes, mirror initializes from real account.
2. `mp` detects modded realm, reads VMF settings.
3. **First-time entry:** apply selected starting-state seed; save snapshot to VMF settings; mark as seeded.
4. **Returning entry:** overwrite the mirror's modded-tracked fields with the VMF-saved shadow.
5. From this point, every `BackendInterface*Playfab.*` method that would write to PlayFab is intercepted; the local replacement mutates the mirror and re-serializes to VMF settings.

## Starting-state options (VMF dropdown)

| Option | Seed |
|---|---|
| Fresh / level 1 | All careers `experience = 0`; default starter weapons per `WeaponSkins.skin_combinations`; no skin/cosmetic unlocks beyond DLC defaults; 0 currencies |
| Level 35, vanilla starter inventory | All careers `experience = ExperienceSettings.max_level_xp`; default starter weapons only; 0 currencies; no cosmetic unlocks beyond DLC defaults |
| Level 35, everything unlocked | Same XP; plus every `_unlocked_weapon_skins` / `_unlocked_cosmetics` / `_unlocked_weapon_poses` entry pre-seeded; one of every craftable item; a sane shillings/scrap/essence balance |

Seed flag is one-shot per save slot. Switching tiers post-seed warns about losing progress.

## Sibling integration

| Sibling | What changes |
|---|---|
| `character_weapon_variants` | Today's unconditional `ItemMasterList[variant_key].can_wield` patch becomes `mp.is_unlocked(variant_key) and base_can_wield(...)`. Variants ship locked; unlocked via loot chests, challenge rewards, Lohner's, mission completion. Without `mp`, current free-unlock behavior remains. |
| `cosmetics_tweaker` | Custom illusions, custom shield options, custom portraits gate on `mp.is_unlocked(key)`. Without `mp`, current free-unlock behavior remains. |
| `crafting_in_modded` | Untouched. Athanor sandbox stays free. Players who want vanilla-cost crafting use the keep bench (re-enabled by `mp`). |
| `chaos_wastes_tweaker` | No code interaction. CW end-of-run already calls into the vanilla XP/loot path; once `mp` un-gates, CW completions credit campaign progress. |
| `event_tweaker` | No interaction. Mutators are live during mission; mission-end rewards are downstream. |
| `weapon_tweaker` | No interaction. Cross-career unlocks already operate at `can_wield` level — orthogonal. |

**Sibling API:**
- `mp.is_unlocked(item_key) → bool`
- `mp.grant_item(item_data) → backend_id` (writes through mirror)
- `mp.spend(kind, amount) → bool` (kind = `"SM"`, `"scrap"`, `"green_dust"`, etc.)
- `mp.credit(kind, amount)`
- `mp.has_currency(kind, amount) → bool`

## Research findings (2026-05-14)

### #1 — `BackendInterfaceCraftingPlayfab` — RESOLVED

`scripts/managers/backend_playfab/backend_interface_crafting_playfab.lua`. Inherits from `BackendInterfaceCraftingBase`. **All five craft pages funnel through one method**: `craft(career_name, item_backend_ids, recipe_override)`. Dispatch is by `recipe.result_function_playfab` (the cloud-script function name); the recipe table is loaded via `dofile("scripts/settings/crafting/crafting_recipes")`.

Callback `craft_request_cb` writes through mirror:
- `items` (new): `backend_mirror:add_item(backend_id, item)` per entry
- `consumed_items`: `backend_mirror:update_item_field(bid, "RemainingUses", v)` or `remove_item`
- `modified_items`: `backend_mirror:update_item(bid, item)`
- `unlocked_weapon_skins`: `backend_mirror:add_unlocked_weapon_skin(skin)`

Recipe names referenced in the four craft pages (`scripts/ui/views/hero_view/craft_pages/*.lua`):
- `craft_weapon`, `craft_jewellery` — forge a new item
- `reroll_weapon_properties`, `reroll_jewellery_properties` — re-roll properties
- `reroll_weapon_traits`, `reroll_jewellery_traits` — re-roll trait
- `salvage_*` — salvage (uses `salvage_validation_func`)
- Skin-extract variants — extract weapon skin from an item

`BackendInterfaceCraftingBase` provides `salvage_validation_func`, `craft_validation_func`, `weapon_skin_application_validation_func`. The ingredients table per recipe specifies categories and amounts.

**For `mp`:** hook the single `craft` method. Branch on `recipe_override` / recipe name to do the local roll; write through the same mirror mutators above. Per-recipe ingredient-consumption is already validated upstream by `_get_valid_recipe`.

**Still missing from source dump:** `scripts/settings/crafting/crafting_recipes.lua` and `crafting_data.lua` — these are referenced via `dofile` but not present in the extracted Lua tree. Must be dumped from the running game (per `feedback_dump_from_game.md`): `local rec = dofile("scripts/settings/crafting/crafting_recipes"); table.dump(rec, "RECIPES", 5)` plus a `CraftingData` dump. Same trick for property/trait roll weights.

### #2 — `unlock_manager.lua:719` — RESOLVED

Inside `UnlockManager:update()`, the `query_unlocked` state branch short-circuits when `eac-untrusted` is true (lines 719-721). Effect: DLC-ownership refresh loop doesn't run in modded; the initial PlayFab sign-in result is what we have. Does **not** gate per-career level-up unlocks (those live in `_career_data` and flow through `set_read_only_data`). Safe to leave as-is for v0.1.x.

### #3 — `achievement_manager.lua:125,294` — RESOLVED (critical)

- **Line 125** (`trigger_event`): the entry point for **every** achievement progress event (kill counts, mission completion, etc.). When `eac-untrusted` is true, returns immediately. **All challenge progress is fully halted in modded.**
- **Line 294** (`update`): the platform-push loop. Halted too. Affects Steam achievement broadcast.

**Implication for `mp`:** un-gating the claim button alone gets nothing — challenge progress doesn't track at all. The fix is one more hook: replace `trigger_event` with a wrapper that **always** runs the body, regardless of `eac-untrusted`. This goes into UI-gate-override step 2 (it's a one-line `mod:hook(AchievementManager, "trigger_event", ...)`).

### #4 — Loot-table data location — RESOLVED

`scripts/settings/equipment/loot_chest_data_1.lua` (only loot_chest_data file present). Contents:

- **Scoring** (`LootChestData.scores.default`): `game_won = 10`, `tome = 10`, `grimoire = 15`, `loot_dice = 5`, `quickplay = 10`, `max_random_score = 30`.
- **Tier thresholds** (`LootChestData.score_thresholds`): `{0, 20, 40, 60, 80, 100}` — six tiers per category.
- **Categories** (`chests_by_category`): `easy`, `normal`, `hard`, `harder`, `hardest`, `cataclysm` — keyed off mission difficulty. Each category points to one `chests_d{N}` package and six backend keys (`loot_chest_0{N}_0{tier}`).
- **Power-level easing** (`calculate_power_level`): client-side curve mapping career level + chest tier to item power-level range.

**Tier selection is Lua-side.** Map difficulty + completion score → category + tier (1-6) → `loot_chest_0{N}_0{tier}` backend key. The chest item itself is just an inventory entry; opening it is what rolls contents (cloud-script).

### #5 — `chest_inventory` shape — VERIFIED

Per `loot_playfab.lua:880-893`:
```
chest_inventory = cjson.decode(read_only_data("chest_inventory"))
chest_levels = chest_inventory[chest_name]
-- iterate chest_levels: for lvl_key, num in pairs(chest_levels) do
--     level_num = tonumber(string.split(lvl_key, "_")[2])
-- end
```

Shape: `{ [chest_backend_key] = { ["chest_level_1"] = N, ["chest_level_2"] = N, ... } }`. Stored as JSON string under read-only-data key `"chest_inventory"`.

### #6 — Loot rolling probabilities — PARTIAL

Confirmed server-side. Not in Lua source. Two paths forward:

- **Empirical seeding:** ship `mp` v0.1.0 with hand-tuned approximation tables (rarity weight per chest tier; property/trait counts per rarity; weapon-type weight per slot). Expose VMF sliders.
- **Runtime dump (preferred long-term):** dump the live PlayFab title-data and read-only-data for the player at sign-in; some of the loot-table parameters may be embedded as PlayFab title-data values readable via `backend_mirror:get_title_data()`. Worth inspecting before authoring approximations.

For v0.1.0: ship approximations. Refine after live testing.

## Items still gated on a runtime dump

1. `crafting_recipes` table (ingredients per recipe, dispatch names) — dump via `dofile + table.dump` from in-game console.
2. `CraftingData` table (slot-type categories, weapon-skin slot types).
3. PlayFab title-data inspection at sign-in — check whether server-side loot/property/trait tables are partially mirrored here.

These three can be done at any time; they unblock the crafting-bench section and the loot-rolling tuning.

## Verified data flow for `craft`

```
craft_page_*:on_craft_button → parent:craft(items, recipe_name)
  → HeroWindowCraft:craft(items, recipe_name)
  → BackendInterfaceCraftingPlayfab:craft(career, ids, recipe_name)   (crafting_playfab.lua:32)
        recipe = crafting_recipes_by_name[recipe_name]
        validated via recipe.validation_function
        enqueues PlayFab CloudScript recipe.result_function_playfab
        ─── INTERCEPT HERE ───
  → craft_request_cb(id, result)                                       (crafting_playfab.lua:56)
        backend_mirror:add_item(bid, item)        for items (new)
        backend_mirror:update_item_field(...)     for consumed_items
        backend_mirror:update_item(bid, item)     for modified_items
        backend_mirror:add_unlocked_weapon_skin   for unlocked_weapon_skins
```

Single intercept point covers all five craft pages.

## Risks

- **Loot rolling probabilities are server-side** (item #6). Mitigation: sane local approximations, VMF tuning sliders, accept divergence from official.
- **Mirror surface is large.** ~30 distinct mutator methods. Each triggered from a local replacement needs commit-side verified blocked (already gated, but confirm during dev).
- **Achievement progress tracking** — if `achievement_manager.lua:125,294` fully halts progress, un-gating the claim popup gets nothing until tracking is re-enabled (item #3).
- **DLC ownership** — `dlc_ownership_request_cb` (playfab_mirror_base.lua:458) takes a different branch in modded. `_handle_owned_dlcs_data` populates `_owned_dlcs` from PlayFab result; DLC-locked items inherit. Should work as today, but verify.
- **Schema migration.** Once a starting-state seed lands in VMF settings, a future schema change needs explicit handling. Add a `settings_version` field from v0.1.0.
- **Hot-reload.** `mp` hooks `BackendInterface*` methods (pure Lua, no C++ unit resources). Hot-reload should survive. Verify during dev; if it doesn't, document alongside `feedback_hot_reload_unfixable.md`.

## Build order

1. **Scaffolding** — VMB mod folder, VMF settings UI for starting-state, mirror-overlay layer (read VMF → mirror), serialization layer (mirror → VMF).
2. **UI gate overrides + achievement tracking** — ~10 hooks returning `false` for `eac-untrusted` at the click-handler / popup-setup sites, **plus** a `mod:hook(AchievementManager, "trigger_event", ...)` that lets the body run regardless of `eac-untrusted` (without this, Okri's Challenges show zero progress). Visual verification: every gated screen displays normally, buttons clickable, kill-count statistics tick up.
3. **End-of-mission rewards** — intercept `generate_end_of_level_loot`, build local loot table, call mirror mutators. Verify XP credit, shillings credit, chest enters inventory.
4. **Loot chest opening** — intercept `open_loot_chest`. Verify items grant and chest decrements.
5. **Okri's Challenges** — un-gate tracking; intercept `claim_achievement_rewards` / `claim_multiple_achievement_rewards`. Verify claim popup grants items.
6. **Lohner's Emporium** — SM `exchange_chips` purchase path implemented in #577. Versus/event currency purchases remain future work; `claim_login_rewards` remains fail-closed under #589 until its mixed reward transaction exists.
7. **Crafting bench** — intercept the single `BackendInterfaceCraftingPlayfab:craft` method. Branch on recipe name; local roll; mutate item via mirror. Requires the runtime-dumped `crafting_recipes` + `CraftingData` tables first.
8. **Starting-state seeder** — first-run seed for the three options, one-shot flag.
9. **Sibling API** — expose `mp.is_unlocked` / `mp.grant_item` / `mp.spend` / `mp.credit`. CWV + cosmetics_tweaker gating hooks land in those mods.

Step 2 unblocks visual verification of every subsequent step. Steps 3–7 are independent and can be parallelized.

## Out of scope (explicit)

- No new screens, NPCs, or items.
- No multiplayer state sync.
- No CW economy bridge — CW already routes through the un-gated pipeline.
- No Versus-mode XP/win-track work in v0.1.x.
- No achievement *grant* beyond what vanilla flows produce — no custom challenge definitions.
