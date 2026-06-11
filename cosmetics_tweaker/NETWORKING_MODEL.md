# Cosmetics Tweaker — Host / client networking model

How vanilla VT2 syncs cosmetic state across peers, where our LA bridge sits in that model, and what we need to add for the per-instance-glow feature (issue #48). Written 2026-05-28 against vanilla source + 2026-05-26 host-log evidence + the existing `cos_la_apply` implementation.

---

## 1. Vanilla's model in one sentence

**Vanilla syncs the *inventory item identity*; every peer independently materializes the visuals from their own local data tables.**

That's it. Glows aren't broadcast. Hats aren't broadcast. Only "Player X has weapon skin `es_2h_sword_skin_03_magic_01` equipped in `slot_melee`" is broadcast, and every peer looks up the same `WeaponSkins.skins[skin_key]` table to discover that the skin's `material_settings_name` is `weaves` and applies the corresponding `MaterialSettingsTemplates.weaves` block to the unit they spawned.

This is why **vanilla glows always look right** without any explicit network plumbing: every peer's `WeaponSkins.skins` is identical (it's a shipped data table), every peer's `MaterialSettingsTemplates` is identical, so the same skin_key arrives at the same visual on every machine.

It's also why **LA cosmetics need extra plumbing** — LA armoury items aren't in `WeaponSkins.skins`, so the vanilla sync arrives at no-match → no glow → no swap. We have to bridge.

---

## 2. The transport layers

Three things move cosmetic-relevant data:

### 2a. `ProfileSynchronizer` (host → all peers)

`ProfileSynchronizer:_resync_loadout(peer_id)` runs whenever a peer's loadout changes (equip / unequip / career switch / fresh join). It serializes the peer's full inventory into a single network-state map and broadcasts it via `SharedState`.

Evidence (host log 2026-05-26 lines 6330-6331):
```
[ProfileSynchronizer] Resyncing loadout of peer(11000013cb862af:1)
[SharedState] network_state_11000013cb862af: <set 11000013cb862af> inventory_list:0:1:0:0:0 = {
    "third_person":{
        "resource_packages/careers/we_maidenguard":false,
        "units/beings/player/way_watcher_maiden_guard/headpiece/ww_mg_hat_12":false,
        ... // full unit-path map
    },
    "inventory_hash":"bc129f1fd1282237",
    "inventory_id":2,
    "first_person":{ ... }
}
```

What's in there: every resource_package + unit path the peer's loadout currently references. What's NOT in there: any glow / material-settings data. The glow is a function of the skin (downstream lookup).

### 2b. VMF `network_send` / `network_broadcast` (mod-defined RPCs)

For data vanilla doesn't sync, mods register RPCs and ship the payload manually. We use this for `cos_la_apply`:

- **Trigger:** local player applies an LA cosmetic (hat / body skin / shield mesh swap / weapon illusion).
- **Send:** `mod:network_send("cos_la_apply", peers, wearer_peer_id, slot_name, kind, armoury_key, vanilla_key, hand_field?)` where `peers` is either `"others"` (broadcast) or `"server"` (forward via host).
- **Recv:** every peer (host included on its own emit) writes to `_la_equips_by_peer[wearer_peer_id][slot_name]` and calls `_apply_la_on_unit` on every unit currently owned by `wearer_peer_id`.

### 2c. Local apply: `apply_material_settings(unit, mat_name)`

`Material.apply_material_settings(unit, name)` is a per-peer LOCAL call. The engine reads `MaterialSettingsTemplates[name]` and pushes the vector3 fields onto the unit's material slots. No network traffic.

We hook this at `cosmetics_tweaker.lua:3620` to log every apply + to inject our `_cosmetics_tweaker_glow` override (the existing `glow_override_enable` toggle). The hook is local-only by design — each peer needs to call it on their own copy of the unit, just like vanilla glows.

---

## 3. The state caches

Where each piece of cosmetic state lives at runtime:

| State | Where it lives | Lifetime | Key | Source of truth |
|---|---|---|---|---|
| Vanilla loadout | `ProfileSynchronizer` + `SharedState.network_state_<peer>` | Per session | `(peer_id, profile_id, career_id)` | Host (re-syncs from PlayFab) |
| LA equips (in-memory) | `_la_equips_by_peer[peer][slot]` | Per session | `(peer_id, slot_name)` | Owning peer's emit |
| LA equips (persisted) | VMF setting `la_persisted_equips.careers[career_name]` | Across restarts | `(career_name, slot_name)` | Owning peer's local writes |
| LA illusions (persisted) | VMF setting `la_persisted_equips.illusions[backend_id]` | Across restarts | `backend_id` | Owning peer's local writes |
| Glow override (per-toggle) | VMF setting `glow_override_*` | Across restarts | (global) | Owning peer |
| **Custom glow blob (per-weapon, planned)** | **CIM `_forged_weapons[bid].custom_glow`** | **Across restarts** | **`backend_id`** | **Owning peer's local writes** |
| Material settings on unit (live) | Engine-internal | Per-spawn | Unit ID | Whichever peer last called `apply_material_settings` on that unit |

Cache invalidation:
- ProfileSynchronizer reruns on every loadout change → SharedState mutates → every peer's `MenuWorldPreviewer` / `GearUtils` re-spawns the unit with the new identity → re-applies glow locally.
- `_la_equips_by_peer` is keyed per-peer-only and **does not invalidate on career switch** (was the v0.9.27 bug → v0.9.28 self-heal patches the stale entry on cross-skeleton detection).
- Disconnect: `mod:hook_safe("PlayerManager", "_remove_player")` purges `_la_equips_by_peer[peer]`.

---

## 4. Why this gives the right answer for vanilla cosmetics

Walk through a vanilla illusion swap on a connected peer:

1. Client A equips skin `es_2h_sword_skin_04_runed_01` (blue_glow rarity=unique) via the customizer.
2. PlayFab inventory write completes; client A's `BackendInterfaceItem.set_loadout_item_id` fires.
3. `ProfileSynchronizer._resync_loadout(A.peer_id)` re-serializes A's inventory into `network_state_A`.
4. SharedState broadcasts; clients B, C, D receive `network_state_A`.
5. On each peer, the next inventory-spawn pass (in keep: `MenuWorldPreviewer._spawn_item_unit` for A's character; in mission: `GearUtils.spawn_inventory_unit`) reads A's new `skin_key`, looks up `WeaponSkins.skins.es_2h_sword_skin_04_runed_01` → `material_settings_name = "blue_glow"`, calls `Material.apply_material_settings(spawned_unit, "blue_glow")` which pulls from local `MaterialSettingsTemplates.blue_glow`.
6. Every peer's view of A's weapon glows blue.

**No glow data crossed the wire.** Just the skin key.

---

## 5. Why LA needs `cos_la_apply` — and where the per-instance glow needs the same pattern

LA cosmetics break step 5: there is no `WeaponSkins.skins[la_armoury_key]` entry on remote peers, so vanilla's lookup arrives at `nil` and nothing applies. We bridge by:

1. Local apply: client A picks LA hat `Kerillian_elf_hat_Windrunner_Avelorn`.
2. `_send_la_apply` emits `cos_la_apply` RPC to every peer carrying `(A.peer_id, "slot_hat", "hat", "Kerillian_elf_hat_Windrunner_Avelorn", vanilla_fallback_key)`.
3. On every peer, the recv handler writes to `_la_equips_by_peer[A][slot_hat]` and calls `_apply_la_on_unit(A.player_unit, "slot_hat", ...)` to attach the LA mesh.
4. On every subsequent unit spawn for A (career swap, mission start, hot-join), the spawn-monitor walks `_la_equips_by_peer[A]` and re-applies.

**Per-instance glow (issue #48) needs the SAME pattern with a different payload:**

| | LA cosmetics (`cos_la_apply`) | Per-instance glow (planned `cos_glow_apply`) |
|---|---|---|
| Trigger | Local apply of LA hat/body/illusion | Local apply of custom glow blob in popup |
| Payload | `(peer, slot_name, kind, armoury_key, vanilla_key)` | `(peer, backend_id, glow_blob)` |
| Recv cache | `_la_equips_by_peer[peer][slot]` | `_custom_glow_by_peer[peer][backend_id]` |
| Local apply | `_apply_la_on_unit` → attach mesh | `_apply_custom_glow_on_unit` → register synthetic `_cosmetics_tweaker_glow_<bid>` template + `apply_material_settings` |
| Persistence | VMF setting per-career + per-backend_id | CIM `_forged_weapons[bid].custom_glow` (substrate ready) |
| Hot-join replay | On peer-join, host re-sends every cached LA emit | On peer-join, host re-sends every cached glow blob |

The glow blob shape is constrained by `MaterialSettingsTemplates.weaves` (5 vector3 fields = 5 × 3 floats = 15 floats per blob). Fits comfortably under the 500-char RPC string cap if we ship as a compact `"%.4g,%.4g,%.4g;%.4g,...;%.4g,%.4g,%.4g"` packed string. Or use VMF binary RPCs and skip serialization.

### Synthetic template registration

`Material.apply_material_settings` reads from the GLOBAL `MaterialSettingsTemplates` table. For per-instance glows, we need a stable name string to pass to it. Two paths:

- **Path A — one template per backend_id.** Register `MaterialSettingsTemplates["_ct_glow_" .. backend_id]` on every peer's recv. Pollutes the global table but is simple. Cleanup needs disconnect-purge hooks.
- **Path B — single shared mutable template.** Maintain one `MaterialSettingsTemplates._ct_glow_active` and overwrite it just before each `apply_material_settings` call. Cleaner table state but races if two units want different glows in the same frame.

Path A is the recommended starting point — race-free, predictable cleanup, easy to scale. Add to `_la_equips_by_peer`-style purge on peer disconnect.

---

## 6. Bots — special case

The host owns every bot unit; remote clients see the bots but don't drive them. The bot's `player.peer_id` equals the host's peer_id (with a non-1 `local_player_id`). For our LA persistence:

- **Host runs the persistence write.** Every cos_la_apply for a host-owned career writes to `_la_equips_by_peer[host_peer][slot]` (no `local_player_id` dimension).
- **Spawn-monitor fires on every unit ready** including bots. It looks up `_la_equips_by_peer[wearer_peer]` and re-applies. The v0.9.11 character-mismatch guard catches the case where the host's career-A entry doesn't fit the bot's career-B body (e.g. host plays Kerillian, bot is Saltzpyre WHC).

This is why **bot hats showing up wrong** was a real bug: the cache is per-peer, the host's career-A LA hat would attempt to attach onto bot-B's body, and the v0.9.11 guard caught + bailed the apply. v0.9.28 added self-heal: after the guard bails, also clear the cache entry so the warning stops firing.

For per-instance glow, bots inherit the same model. The host's local custom_glow blob applies to host-owned weapons including those held by bots. Remote peers receive the broadcast and apply on their puppet copies.

---

## 7. Where the gaps are right now

What works:
- LA hat / body / illusion sync across peers (cos_la_apply).
- Vanilla glow propagation (free — skin keys are the only thing needed).
- Per-career LA persistence across restarts (`_la_persistence.lua`).
- Per-backend_id LA illusion persistence (`la_persisted_equips.illusions`).
- Global glow-override toggle (`glow_override_enable` + per-channel sliders) — **NOT per-instance**, applies to whatever weapon the user wields.
- Bot LA hat self-heal on cross-skeleton mismatch.

What's planned for issue #48:
- Per-instance glow blob storage (CIM `custom_glow` field — substrate exists per `crafting_in_modded.lua`).
- `cos_glow_apply` RPC for cross-peer sync of the blob.
- Synthetic per-backend_id MaterialSettingsTemplates registration on recv.
- Hot-join replay (host re-sends every active glow on peer-join).
- UI popup on the customizer (data probe v0.9.30+ captures the surface).
- Hide weavebound by default in the picker (v0.9.29 ✓).

What we still need to learn from in-game runtime:
- The full `HeroWindowItemCustomization` state machine — `_state_*` methods, transitions, click-callback wiring. v0.9.30 dump captures snapshot.
- The current-skin selection state (`_selected_illusion_index`) behavior across re-opens.
- What CIM passes through on weapon spawn vs what gets dropped (CIM's `_forge_load` is the apply point).

---

## 8. Diagnostic commands

| Command | What it does |
|---|---|
| `/cos_regression_test` | Runs every `_rt_register` test. Covers cache self-heal, illusion filter, LA char-compatibility guard, etc. |
| `/dump_glows` | Buckets every weapon skin by `material_settings_name`. Confirms the 9 weapon-mat families. |
| Enable `enable_debug_logging` toggle | Activates per-window UI dumps (`[ui-dump:HeroWindow*]`) including the MaterialSettingsTemplates global dump on first customizer open (v0.9.30+). |

---

## 9. References

- Vanilla `ProfileSynchronizer`: `scripts/managers/profile_synchronizer/profile_synchronizer.lua` (look at `_resync_loadout`)
- Vanilla `apply_material_settings` hook target: `scripts/helpers/cosmetic_utils.lua` (`CosmeticUtils.apply_material_settings` global wrapper)
- `MaterialSettingsTemplates.weaves`: `scripts/settings/equipment/weapon_material_settings_templates.lua:52`
- LA bridge implementation: `cosmetics_tweaker.lua` lines 4703-5800 (search `cos_la_apply` / `_la_equips_by_peer` / `_apply_la_on_unit`)
- Per-instance glow CIM substrate: `crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua` (`_forge_save` / `_forge_load` / `_cim_set_custom_glow`)
- v0.9.28 cache self-heal: `cosmetics_tweaker.lua:_purge_stale_peer_slot` + `_la_spawn_monitor` mismatch handler
