# Modded Progression — Changelog

## v0.2.0-dev (2026-05-15)

Build-order step 2 — UI gate overrides + achievement-progress un-gate.

Wraps 10 vanilla functions with a flip-flag wrapper (`script_data["eac-untrusted"] = nil` for the call, restored on exit), so the gated bodies run as if in official realm. Flag stays globally true outside our wrapped calls, preserving commit suppression at `playfab_mirror_base.lua:2826/2839/2857` and the DLC update gate at `unlock_manager.lua:719`.

**Functions hooked:**
- `LevelEndViewBase.init` — runs `_get_level_up_rewards` / `_get_deed_rewards` / `_get_deus_rewards` / `_get_keep_decoration_rewards` / `_get_event_rewards` / `_get_win_track_rewards` / `_get_versus_level_up_rewards` setup branch
- `HeroViewStateAchievements._create_entries` — restores `completed` flag on each Okri's Challenges entry
- `HeroViewStateAchievements._handle_claim_all_challenges` — un-greys claim-all button
- `StoreWindowItemPreview._set_unlock_button_states` — un-greys Lohner's buy button
- `StoreItemPurchasePopup._create_ui_elements` — un-greys purchase popup button
- `StoreLoginRewardsPopup._create_ui_elements` — un-greys daily-rewards claim button
- `HeroWindowItemCustomization._enable_craft_button` / `_update_state_craft_button` — un-greys keep crafting bench
- `IngameUI.not_in_modded` — overridden to always return `true`
- `AchievementManager.trigger_event` — **critical** un-gate: lets every achievement-progress event run, so kill counts / completion timers / etc. actually advance challenge counters

**Intentionally left gated:**
- `AchievementManager.update` (line 294) — Steam-platform achievement push loop. Local progression doesn't need Steam to register them.
- All commit paths in `playfab_mirror_base.lua` — the whole point of writing local.

**Verification:**
- VMB build clean (1.93s incremental, 4 bundles).
- In-game verification deferred to user — should expect: level-end reward popups appear and queue, Okri's Challenges grey claim button no longer greyed, Lohner's buy buttons live, keep crafting bench buttons clickable, kill statistics tick up during a mission.

## v0.1.0-dev (2026-05-14)

Initial scaffold. Internal id `mp`. Workshop unpublished (private visibility).

**Shipped:**
- VMF mod registration, build via VMB, output to `bundleV2/`.
- VMF settings UI with the starting-state dropdown (fresh / level 35 default / level 35 everything unlocked).
- Local persistence stores via VMF settings (`currency`, `unlocks`, `inventory`, `seeded`, `schema_version`).
- Sibling API stubs (`mp.is_unlocked`, `mp.mark_unlocked`, `mp.has_currency`, `mp.spend`, `mp.credit`, `mp.get_currency`, `mp.grant_item`) — all returning sane defaults pre-seed so co-installed CWV / cosmetics_tweaker don't crash.
- Diagnostic commands: `mp_dump` (current state), `mp_reset` (wipe local store).
- Schema versioning hook for future migrations.

**Not yet wired (per `PLAN.md` build order):**
- Step 1.b: mirror-overlay layer (VMF → backend_mirror at boot) and serialization layer (mirror mutation → VMF) — function stubs in place, no hooks.
- Step 2: UI gate overrides (~10 sites) + `AchievementManager.trigger_event` hook.
- Steps 3–7: end-of-mission rewards, loot-chest opening, Okri's Challenges, Lohner's Emporium, crafting bench interceptions.
- Step 8: starting-state seeder.
- Step 9: sibling consumer hooks in CWV / cosmetics_tweaker.

**Blockers for step 7 (crafting bench):**
- Runtime dump of `scripts/settings/crafting/crafting_recipes` table.
- Runtime dump of `CraftingData` table.
- PlayFab title-data inspection at sign-in.
