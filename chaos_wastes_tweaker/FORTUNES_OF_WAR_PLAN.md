# Fortunes of War — Plan

A wave-based coin economy mode layered onto Chaos Wastes journey finales (`arena_ruin`, `arena_cave`, `arena_ice`, `arena_citadel`). Host-side, opt-in via a ct config toggle.

## Concept

- Each finale wave drops coins (vanilla `deus_soft_currency`, already in CW).
- A ring of chests around the central statue. One chest auto-opens per wave with a reward.
- A second pen-area cluster acts as a store: chests with fixed costs and themed reward tables that you can voluntarily spend coins on between waves.

---

## Vanilla building blocks (confirmed in source)

| Concept | Vanilla artifact | Notes |
|---|---|---|
| Coin pickup | `Pickups.deus_soft_currency` → `units/props/deus_pickups/deus_loot_pyramide_01`, template `pickup_unit` | Already increments `DeusRunController._soft_currency`. ct already hooks `on_soft_currency_picked_up` for `coin_multiplier`. |
| Spawnable chest | `Pickups.deus_weapon_chest` → `units/props/inn/deus/deus_chest_01`, template `deus_weapon_chest` | Interaction goes through `InteractionDefinitions.deus_weapon_chest` → `pickup_extension:open_chest()`, gated by `can_be_unlocked()`. |
| "Lightning" chest visual | `units/props/inn/deus/deus_cursed_chest`, template `deus_cursed_chest` | Has the unsealing-flash VFX baked into its flow SM. Heavier to repurpose (carries the cursed-chest extension/state machine). |
| Wave terror events | `Managers.state.conflict:start_terror_event(name, seed, source_unit)` plus level flow events (`on_arena_end_triggered` etc.) | Hook point for wave start / wave end. |
| Coin spawn (server) | `pickup_system:spawn_pickup("deus_soft_currency", position, rot, true, "dropped")` | Same call pattern used by `GreedPinataSettings`. |
| Reward menu reference | `GreedPinataSettings.possible_drops` | Pre-balanced drop table we can crib from. |
| Center anchor | `DeusArenaIdolExtension` unit (`deus_arena_idol`) | Statue in finale arenas. Probe via `Level.units(level)` + extension check. |
| In-mission UI | None vanilla — `DeusShopView` is map-screen only | Custom shop UI is a separate, large effort. Tier-3 only. |

---

## Design — three tiers, each independently shippable

### Tier 1 — Chest ring (MVP)

On finale level enter (host):
1. Locate center: walk `Level.units(current_level)` and find a unit with `deus_arena_idol_system` extension. Fall back to centroid of `arena_*_event` spawner positions.
2. Spawn `N` `deus_chest_01` units in a ring at radius `R` (`N` = wave count, default 4; `R` ≈ 6m).
3. Suppress vanilla `open_chest` reward path on these chests — flag them via `Unit.set_data(unit, "fow_ring_chest", true)` so we recognize them.
4. Hook the finale's wave-end signal (terror-event completion or named level flow event). On each wave end, server picks the next ring chest, fires `Unit.flow_event(chest, "lua_open")`, drops a configurable reward cluster (coins + a small pickup) at the chest position.

**Reward table (per-wave, configurable):**
- wave 1 → 30 coins + healing_draught
- wave 2 → 50 coins + grenade
- wave 3 → 80 coins + potion
- wave 4 → 120 coins + boon-roll (call `DeusPowerUpUtils.generate_random_power_up` and apply via `DeusBackendCommon`)

### Tier 2 — Spendable chests (player interacts to open)

- Hook `pickup_extension:can_be_unlocked()` (or wrap `InteractionDefinitions.deus_weapon_chest.client.stop`) to enforce a coin cost on opening.
- Cost scales with chest tier (cheap = small reward, expensive = boon).
- Deduct coins via `DeusRunController:on_soft_currency_picked_up(-cost, ...)` (same path ct already touches; verify sign convention — `setup_run` grants positive, so we'd need a "subtract coins" helper or `_soft_currency` field touch directly).
- Reward roll is driven server-side from a config table per chest "slot".

### Tier 3 — Pen-area store

Two flavors, pick one:

**3a. Cheap (recommended):** spawn a second cluster of `deus_chest_01` chests in the pen area, each with a *fixed labeled reward* (chest is the "item card"). Cost shown via overridden `interaction_data.hud_description` + a localization string. No new UI, no new RPCs.

**3b. Full shop UI:** new interactable type + custom view modeled on `DeusShopView` but reachable in-mission. Needs:
- new `InteractionDefinitions.fow_store` mirroring `deus_arena_interactable`
- new view class with its own RPCs for purchases (sync state across clients)
- camera transition or overlay rendering — `DeusShopView` swaps camera, which inside a live mission is bad UX. Likely needs overlay-only.

Tier 3b is a project. Tier 3a probably hits the same vibe in 1/10 the code.

---

## Open questions (need decisions before code)

1. **Chest visual.** `deus_chest_01` (cheap, fits altars but no lightning) or repurpose `deus_cursed_chest` (lightning visual, much more work to strip the carry/defense behavior). Default: `deus_chest_01`.
2. **Levels.** All 4 finales day-1, or pilot on `arena_ruin` and roll out after testing?
3. **Pen-area store.** Tier 3a (preset chest cluster) or Tier 3b (real UI)?
4. **Coin economy balance.** Are coins persistent into the post-finale journey, or zeroed when leaving the arena? Vanilla preserves them — leaving them preserved means a generous Tier 1 leaks into next-run economy. Likely want a per-mode flag.
5. **Reward fallback.** What does the wave-end chest drop if all configured rewards are exhausted? (Drop nothing? Drop coins-only? Drop another full boon?)

---

## Implementation outline (Tier 1)

New file: `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_fortunes_of_war.lua`

```
local FOW = {}
local FINALE_LEVELS = { arena_ruin = true, arena_cave = true, arena_ice = true, arena_citadel = true }
local CHEST_UNIT = "units/props/inn/deus/deus_chest_01"
local CHEST_TEMPLATE = "deus_weapon_chest"
local RING_RADIUS = 6
local WAVE_COUNT = 4

-- state per active arena
local state = nil  -- { center, chests, wave_index, rewards }

-- public entry from chaos_wastes_tweaker.lua on level enter:
function FOW.maybe_start(level_key)
    if not mod:get("fow_enabled") then return end
    if not FINALE_LEVELS[level_key] then return end
    if not Managers.player.is_server then return end
    local center = _find_arena_center()
    if not center then return end
    state = { center = center, chests = _spawn_chest_ring(center), wave_index = 0,
              rewards = mod:get("fow_reward_table") or DEFAULT_REWARDS }
    _hook_wave_signal()
end

function FOW.on_level_exit()
    if state then _despawn_ring(state.chests); state = nil end
end

local function _on_wave_completed()
    state.wave_index = state.wave_index + 1
    local chest = state.chests[state.wave_index]
    if not chest or not ALIVE[chest] then return end
    Unit.flow_event(chest, "lua_open")
    _drop_reward(POSITION_LOOKUP[chest], state.rewards[state.wave_index])
end
```

Wire-up in `chaos_wastes_tweaker.lua`:
- on `GameModeDeus.local_player_game_starts` (already hooked) → call `FOW.maybe_start(level_key)`
- on level exit (hook `GameModeDeus.on_level_exit` or similar) → call `FOW.on_level_exit()`
- find the wave-end hook by reading `level_scripts/honduras_dlcs/morris/arena_*` or by hooking `start_terror_event` and counting starts matching `arena_*_event` names

### Config additions (ct mod settings)

- `fow_enabled` — toggle
- `fow_wave_count` — default 4
- `fow_ring_radius` — default 6
- `fow_reward_table` — per-wave reward picker (UI-friendly enum or JSON)
- `fow_coin_multiplier_on_arena` — separate from base `coin_multiplier`, default 2x

---

## Risk register

- **Center detection** — if `deus_arena_idol_system` isn't on the central unit in every finale, spawner-centroid fallback may land chests in a non-traversable spot. Need test sweep across all 4 arenas.
- **Pickup networking** — `spawn_network_unit` from a non-server peer is undefined; gate every spawn on `Managers.player.is_server`.
- **Wave hook fragility** — relying on terror-event names couples us to vanilla naming. Prefer level flow events if they exist and are stable.
- **Cleanup on disconnect / failure / restart** — `state` must be cleared when the arena ends abnormally, or ghost chests persist if the level reloads.
- **Combined hash** — no `LevelSettings` mutation here, so host can run with vanilla clients. Confirm before claiming host-only compat.
- **Interaction with existing ct chest-distribution hooks** — Tier 2 chests open via the same `pickup_extension:open_chest()` path that ct's `get_deus_weapon_chest_type` distribution covers. Will produce a chest_type roll unless we shortcut. Need to gate on the `fow_ring_chest` flag in our hook.

---

## Out of scope (deliberate)

- Boss waves / special encounters per wave.
- Tier-3b shop UI (defer indefinitely unless Tier 3a is insufficient).
- Cross-run persistence of coins beyond what vanilla already does.
- Non-finale levels.
