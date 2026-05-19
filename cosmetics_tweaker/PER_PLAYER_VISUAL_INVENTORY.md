# Per-Player Visual Inventory — cosmetics_tweaker

Audit date: 2026-05-19, v0.8.67-dev. Source files:
- `scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data.lua` (widget tree)
- `scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` (main, 4288 lines)
- `scripts/mods/cosmetics_tweaker/_la_bridge.lua` (1473 lines; no `mod:get` reads)
- `scripts/mods/cosmetics_tweaker/_tpe.lua` (566 lines)

Question for each setting: when another player looks at this user's character, do they see the user's choice or do they see something else?

---

## 1. Master table

Columns: SettingID | Widget | Default | Visual effect | Where applied | Currently syncs to peers? | Apply path is owner-aware?

### A. Top-level (always-shown)

| Setting ID | Widget | Default | Visual effect | Where applied | Syncs to peers? | Owner-aware? |
|---|---|---|---|---|---|---|
| `unlock_all_illusions` | checkbox | false | Marks every WeaponSkins entry unlocked in local backend mirror so they're SELECTABLE in the local user's illusion grid. Equipping still goes through vanilla illusion equip; once equipped the skin syncs over the vanilla wire and other peers DO see it (it's a vanilla key). | `cosmetics_tweaker.lua:1048` — `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` writes `mirror._unlocked_weapon_skins[skin_key] = true` | NO emit. NO sync. But irrelevant — the eventual equip uses vanilla skin keys which sync natively. | N/A (read at backend-mirror build time, applies to local mirror only) |
| `unlock_all_frames` | checkbox | false | Same shape for portrait frames — adds every `item_type == "frame"` entry to local fake_inventory. Frames are HUD-side only, never appear on the player body. | `cosmetics_tweaker.lua:1133, 1149` — `PlayFabMirrorAdventure._create_fake_inventory_items` + `get_unlocked_cosmetics` | NO emit but irrelevant — frames aren't on-character visuals. | N/A |
| `la_bridge_enable` | checkbox | false | Gate flag for the entire LA bridge (`mod.update` at `cosmetics_tweaker.lua:3882`). When OFF, all LA cloned items, cos_la_apply RPCs, custom-mesh shield/hat overlays are inert. | `cosmetics_tweaker.lua:3882` | N/A — gate flag for many other settings | N/A (gate flag) |

### B. `appearance_group → weapon_model_group`

| Setting ID | Widget | Default | Visual effect | Where applied | Syncs to peers? | Owner-aware? |
|---|---|---|---|---|---|---|
| `es_bastard_sword_thiccc` | checkbox | false | Shrinks the Bretonian Longsword model X-axis to 65% (slim instead of slab). Matches against unit-path substring `wpn_emp_gk_sword_`, right hand only. | `cosmetics_tweaker.lua:746-768` (factor + scale entry); applied via `_apply_unit_path_scale_hand` called from `_scale_units` (in-game), `_spawn_item_post` (inventory preview), `LootItemUnitPreviewer.spawn_units` (illusion browser) — lines 2725, 2919, 3071 | NO. No emit. Reads `mod:get` LOCALLY on every machine that spawns the unit, including remote husk equip. **Each peer sees their own toggle's choice applied to EVERYONE's Bret longsword.** | **NO.** Reads local `mod:get` in `_breton_sword_thiccc(get)` (line 747), `get` is `function(id) return mod:get(id) end` (line 2290). |

### C. `appearance_group → glow_override_group`

| Setting ID | Widget | Default | Visual effect | Where applied | Syncs to peers? | Owner-aware? |
|---|---|---|---|---|---|---|
| `glow_override_enable` | checkbox | false | Master toggle for glow override. When OFF, all other glow_* settings inert and `apply_material_settings` passes through. | `cosmetics_tweaker.lua:2404, 2417, 2429, 2473, 2499, 2597`. Read inside `_hook_apply_with_template_mutation` callback that wraps `GearUtils.apply_material_settings`, `_G.apply_material_settings` (flow), and `CosmeticUtils.apply_material_settings` (lines 2548-2557). Also gates `GearUtils.spawn_inventory_unit` template injection (2595). Also gates the post-equip `_apply_glow_override` call at `create_equipment` (2744). | NO. No emit. Each peer reads their OWN `mod:get`. | **NO.** Mutates global `MaterialSettingsTemplates[name]` based on local viewer's settings, then delegates to vanilla apply, restores. The mutation happens whether the unit being spawned belongs to the local player or a remote husk. |
| `glow_override_preset` | dropdown ("default"/white_glow/purple_glow/golden_glow/deep_crimson/life_green/lileath) | `"default"` | Resolves to one RGB triple (`_COLOR_PRESETS` table at line 2343-2353) applied to every paintable glow variable on the weapon when override enabled. | Same hooks as `glow_override_enable`. Read via `_glow_main_rgb()` (2418) → `_resolve_preset_rgb(mod:get("glow_override_preset"))`. | NO. | NO. |
| `glow_mult_master` | numeric (0.0-5.0) | 1.0 | Master brightness multiplier applied to all channels' final brightness. | `_glow_master_mult()` (2394). Read on every apply. | NO. | NO. |
| `glow_per_channel_color_enable` | checkbox | false | Switches `glow_color_*_gradient`/`glow_color_dots` per-channel RGB lookups on for magic-family weapons (`_magic_01` / `_magic_02`). When OFF, magic family uses the main color. Rune-family (`_runed_*`) ignores this toggle either way. | `_glow_rgb_for_var(var_name)` (2432). | NO. | NO. |
| `glow_color_lower_gradient` | dropdown (7 presets + default) | `"default"` | When per-channel enabled, drives `color_glow_high` + `color_glow_low` (lower visible gradient on `_magic_*`). | `_glow_rgb_for_var` via `_GLOW_GROUP_COLOR_SETTING.lower`. | NO. | NO. |
| `glow_color_upper_gradient` | dropdown | `"default"` | When per-channel enabled, drives `color_smoke_high` + `color_smoke_low`. | Same path, `_GLOW_GROUP_COLOR_SETTING.upper`. | NO. | NO. |
| `glow_color_dots` | dropdown | `"default"` | When per-channel enabled AND `glow_mult_dots > 0`, drives `color_dots`. | Same path, `_GLOW_GROUP_COLOR_SETTING.dots`. | NO. | NO. |
| `glow_mult_rune` | numeric (0.0-5.0) | 1.0 | Per-channel brightness mult for `rune_emissive_color` (themed Veteran `_runed_02..06` + Stylish loot-chest `_runed_01`). 0 = skip channel. | `_glow_var_mult("glow_mult_rune")` (2398). | NO. | NO. |
| `glow_mult_glow_high` | numeric (0.0-5.0) | 1.0 | Per-channel brightness mult for `color_glow_high`. | Same. | NO. | NO. |
| `glow_mult_glow_low` | numeric (0.0-5.0) | 1.0 | Per-channel brightness mult for `color_glow_low`. | Same. | NO. | NO. |
| `glow_mult_smoke_high` | numeric (0.0-5.0) | 1.0 | Per-channel brightness mult for `color_smoke_high`. | Same. | NO. | NO. |
| `glow_mult_smoke_low` | numeric (0.0-5.0) | 1.0 | Per-channel brightness mult for `color_smoke_low`. | Same. | NO. | NO. |
| `glow_mult_dots` | numeric (0.0-5.0) | **0.0** | Per-channel brightness mult for `color_dots`. Default 0 (skip — preserves vanilla's value). | Same. | NO. | NO. |

### D. `tpe_group` (Third-Person Equipment, experimental)

| Setting ID | Widget | Default | Visual effect | Where applied | Syncs to peers? | Owner-aware? |
|---|---|---|---|---|---|---|
| `tpe_enable` | checkbox | false | Spawns extra holstered-weapon 3P meshes attached to every player's body (own + bots + remote players) for each non-wielded loadout slot. | `_tpe.lua:216, 542` — `M.update(dt)` calls `create_items_if_needed` which walks `Managers.player:human_and_bot_players()` and spawns meshes for everyone's player_unit on the local machine. | NO emit. Each peer reads their OWN toggle. **If host has TPE on but client has TPE off, the host sees TPE meshes on everyone (including the client); the client sees no TPE meshes.** This is consistent: each viewer chooses whether THEY see the extra meshes — it's a viewer preference, not a per-wearer broadcast. | **N/A — purely visual local overlay; doesn't change the underlying player_unit, just spawns extra meshes parented to it.** It IS owner-aware in the sense that it walks every player and applies the same overlay regardless of who they are. There's no per-wearer customization to broadcast. |
| `tpe_show_self_in_3p` | checkbox | true | Documented as "Hide Own Equipment in First Person" — when ON, the user's own holstered TPE meshes hide while in first-person camera. **GAP: this widget appears unwired beyond the `on_setting_changed` flush (`_tpe.lua:558`). No runtime read of this key exists in `_tpe.lua` — `is_enabled()` only checks `tpe_enable`.** | `_tpe.lua:558` (flush trigger only). Effective behavior: the FP-hide is hardcoded in `set_equipment_visibility` (lines 414-419) which always hides for the local player in firstperson mode regardless of the toggle. | N/A. Local visibility only. | N/A. |
| `tpe_downscale_big_weapons` | numeric (25-100) | 100 | Scale percentage applied to every spawned TPE mesh. Affects every player's TPE meshes the local viewer sees. | `_tpe.lua:311` — `Unit.set_local_scale` after spawn. | NO emit. Local viewer reads local toggle. | NO — viewer's local toggle scales ALL players' TPE meshes uniformly. |

### E. `cosmetic_availability_group` — 1896 auto-generated `cos_unlock_<career>_<item_key>` toggles

| Setting ID pattern | Widget | Default | Visual effect | Where applied | Syncs to peers? | Owner-aware? |
|---|---|---|---|---|---|---|
| `cos_unlock_<career>_<item_key>` × 1896 | checkbox | varies (native equips = true, foreign = false) | Adds/removes career from the item's `can_wield` array in `ItemMasterList`. Determines whether the cosmetic shows up in the keep's inventory grid for that career. Once a cosmetic is equipped via inventory, vanilla syncs the equip key to peers, so peers see the cosmetic IF they ALSO have it unlocked locally (otherwise vanilla's `rpc_create_attachment` would fail their lookup — but: same item key, so it's just a `can_wield` filter on the local UI). | `cosmetics_tweaker.lua:582` — `apply_cosmetic_unlocks` mutates `ItemMasterList[item_key].can_wield` at boot + game-state-changed. | N/A. Each peer's local `can_wield` toggle gates THEIR keep UI; the equipped vanilla key over the wire works regardless. **NOT a per-player visual setting.** | N/A — pre-game inventory permissions, not on-screen visual. |

### F. Implicit / un-widgeted per-player visual state (no `mod:get`, but still persistent local choices)

These don't have VMF widgets but ARE per-player local choices that produce on-character visuals. They MUST be in the inventory because the user's complaint covers them.

| State | Storage | Authored where | Default | Visual effect | Currently syncs? | Owner-aware? |
|---|---|---|---|---|---|---|
| Offhand pick (vanilla mesh) | `_offhand_selection[backend_id] = { unit, name, rarity, ... }` (`cosmetics_tweaker.lua:1705`, module-local, RAM only) | User clicks row-2 offhand button in HeroWindowItemCustomization → `_ct_on_offhand_pressed` (2006) stores into `_offhand_selection`. | nil (no override) | Replaces `result.left_hand_unit` in `BackendUtils.get_item_units` — swaps the shield/offhand model for ANY equipped vanilla mesh option. Also applies in `LootItemUnitPreviewer.spawn_units` and the inventory previewer via `_apply_la_offhand_to_units`. | **NO. Explicitly documented as unsynced** (line 2024-2031): "vanilla-mesh offhands ... still go unsynced". Emit at line 2032 is gated `if opt and opt.la_armoury_key`. | **NO.** Apply hooks read `_offhand_selection[bid]` keyed on the spawned unit's `backend_id`, but the table only contains the LOCAL user's picks. Remote husk equips read effective_backend_id, find nothing in the local table, no override applied. |
| Offhand pick (LA armoury_key, vanilla key) | Same `_offhand_selection` table with `la_armoury_key` + `vanilla_skin` + `intended_unit` set | Same picker | nil | Replaces `result.left_hand_unit` with `intended_unit` (LA mesh path) in `get_item_units`, then `_apply_la_offhand_to_units` paints LA heraldic textures onto the shield via `LA_BRIDGE.apply_offhand_to_unit`. | **PARTIAL.** When `opt.la_armoury_key` is set, `_send_la_apply(player_unit, weapon_key, "offhand", la_armoury_key, vanilla_skin)` fires (2041). Receiver path is `_apply_la_on_unit` → `LA_BRIDGE.apply_offhand_to_unit(... "network_husk")`. **Custom-mesh (`kind="unit"`) LA shield variants are explicitly deferred on husks** per `_la_bridge.lua:1176-1182` (vanilla mesh stays). | **PARTIAL.** RPC carries `wearer_peer_id`; receiver resolves wearer via `_wearer_unit_for_peer`, applies to that peer's wielded left unit. The receiver does NOT update `_offhand_selection[bid]` though, so on husk re-spawn (career switch on husk) the local hooks don't know to re-apply — relies on `_la_pending_apply` (5s TTL) or the next equip event. |
| LA hat equip | `_local_la_equips[player_unit][slot_hat] = la_backend_id` + host's `_la_equips_by_peer[wearer_peer][slot]` | User equips a clone-IML cloned hat → `CosmeticUtils.update_cosmetic_slot` hook (3225) writes the LA bid in `_local_la_equips` AND emits `cos_la_apply` `kind="hat"`. Also emitted by `PUAE.game_object_initialized` (3709), `PUAE.spawn_resynced_loadout` (3746), and `AttachmentUtils.hot_join_sync` (3772). | nil (vanilla hat) | Replaces the vanilla hat unit attachment with the LA mesh on the wearer's body. | **YES (but quadruple-emit).** Routed via `cos_la_apply_req` → host validates against `LA_BRIDGE.armoury_to_backend` → broadcasts `cos_la_apply` to all. | **YES.** Receiver resolves wearer via `wearer_peer_id` → `Managers.player:players_at_peer` and `_apply_la_on_unit(unit, slot, "hat", armoury_key, vanilla_key)` constructs a clone of IML[vanilla] with `item_data.unit = la_unit_path` and creates the attachment on the wearer's unit. |
| LA armor (slot_skin) equip | Same `_local_la_equips` table | Same `CosmeticUtils.update_cosmetic_slot` hook (3225-3287) | nil | Paints LA heraldic textures onto the wearer's body via `la.apply_new_skin_from_texture(armoury_key, level_world, vanilla_key, owner_unit)`. | **YES (but only via CosmeticUtils + hot_join_sync — NOT PUAE because slot_skin is "cosmetic" not "attachment" category).** | **YES.** Same `wearer_peer_id` routing. |
| LA weapon illusion equip (slot_melee/slot_ranged) | Same `_local_la_equips` table | `CosmeticUtils.update_cosmetic_slot` (3297) when `la_skin_subbed` is set (skin_name was substituted) | nil | Paints LA textures onto BOTH `right_hand_wielded_unit_3p` and `left_hand_wielded_unit_3p` of the wearer. | **YES but partial:** only paints the CURRENTLY-WIELDED weapon's 3P unit (line 3613 returns false if not wielded → re-queue with 5s TTL). Sheathe/unwield cycling past 5s leaves peer-side vanilla. | **YES.** Same `wearer_peer_id` routing. |

---

## 2. Sync coverage matrix

| Setting / State | Authored locally | Emitted to peers | Received by peers | Applied per-wearer-peer |
|---|---|---|---|---|
| `unlock_all_illusions` | YES | N/A (out of scope — local mirror, doesn't change wire format) | N/A | N/A |
| `unlock_all_frames` | YES | N/A | N/A | N/A |
| `la_bridge_enable` | YES | N/A (gate flag) | N/A | N/A |
| `es_bastard_sword_thiccc` | YES | **NO** | NO | **NO — every viewer reads own `mod:get`** |
| `glow_override_enable` | YES | **NO** | NO | **NO** |
| `glow_override_preset` | YES | **NO** | NO | **NO** |
| `glow_mult_master` | YES | NO | NO | NO |
| `glow_per_channel_color_enable` | YES | NO | NO | NO |
| `glow_color_lower_gradient` | YES | NO | NO | NO |
| `glow_color_upper_gradient` | YES | NO | NO | NO |
| `glow_color_dots` | YES | NO | NO | NO |
| `glow_mult_rune` | YES | NO | NO | NO |
| `glow_mult_glow_high` | YES | NO | NO | NO |
| `glow_mult_glow_low` | YES | NO | NO | NO |
| `glow_mult_smoke_high` | YES | NO | NO | NO |
| `glow_mult_smoke_low` | YES | NO | NO | NO |
| `glow_mult_dots` | YES | NO | NO | NO |
| `tpe_enable` | YES | N/A — local viewer overlay (no per-wearer customization to broadcast) | N/A | N/A |
| `tpe_show_self_in_3p` | YES | N/A (local-viewer only; widget appears half-wired) | N/A | N/A |
| `tpe_downscale_big_weapons` | YES | N/A (local viewer overlay) | N/A | N/A |
| `cos_unlock_*` (×1896) | YES | N/A (local availability filter — equipped item syncs natively via vanilla) | N/A | N/A |
| Offhand pick — vanilla mesh | YES | **NO** | NO | **NO — read from local `_offhand_selection` only** |
| Offhand pick — LA texture-paint variant | YES | YES (`cos_la_apply` kind="offhand") | YES (server-authoritative broadcast) | YES (`wearer_peer_id` routes apply to wearer's wielded left unit) — but receiver doesn't seed `_offhand_selection`, relies on pending-queue for re-spawn |
| Offhand pick — LA `kind="unit"` custom-mesh shield | YES | YES (broadcast same as above) | YES | **NO — receiver explicitly defers** `kind="unit"` husks (vanilla mesh stays per `_la_bridge.lua:1176-1182`) |
| LA hat equip | YES | YES (quadruple-emit from CosmeticUtils + PUAE×2 + hot_join_sync) | YES | YES |
| LA armor (slot_skin) equip | YES | YES (CosmeticUtils + hot_join_sync) | YES | YES |
| LA weapon illusion equip | YES | YES (CosmeticUtils + hot_join_sync) | PARTIAL (only paints wielded weapon; sheathed weapons paint stale on peers past 5s TTL) | YES |
| Vanilla hat / vanilla armor / vanilla illusion equips | YES | YES (vanilla `rpc_create_attachment` / `SyncData` / `rpc_sync_loadout_slot`) | YES | YES (vanilla path) |

---

## 3. Gaps

### Easy (just add to existing emit)
*None.* Every gap below requires NEW state plumbing.

### Medium (need new RPC + cache)

1. **Vanilla-mesh offhand picks** (e.g. "GK Shield Blue" on Bret weapon, dual-wield secondary swap). Currently the local user picks an option whose `opt.unit` (vanilla unit path) is set but `opt.la_armoury_key` is nil → `_send_la_apply` not called. Need a new RPC carrying `{ wearer_peer_id, slot_name, vanilla_unit_path }` and host-authoritative broadcast. Receiver writes into `_offhand_selection[bid]` for the wearer's backend_id so the existing `BackendUtils.get_item_units` swap-hook reads it on the next get_item_units call for that wearer.

   Sharp edges:
   - `_offhand_selection` is keyed by `backend_id` which is stable per-peer per-instance. The wearer's backend_id is what local code uses; receivers may not have the wearer's BID locally — need to verify whether `backend_id` is the same across peers for an attached item. If not, key receiver-side override by `wearer_peer_id + slot_name` instead.
   - `BackendUtils.get_item_units` runs on every spawn including remote husk spawn — already runs on receivers when the husk equips a weapon with backend stamped on `item_data.backend_id`. So receiver-side existing hook would pick up the override if we wrote to `_offhand_selection[remote_bid]`. That requires the host having the remote bid mapping — easier to key by wearer_peer.
   - Package preload race: `BackendUtils.get_item_units` gates on `_override_package_ready(override_unit)`. Receiver needs to preload the unit's package before applying (the local user already preloads via `_preload_offhand_for_option`). Add a synchronous preload at receive time.

2. **`es_bastard_sword_thiccc` (and any future weapon-model toggles in `_unit_path_scale_overrides`)**. Currently every viewer reads their own toggle, so a client-on-host can disable thiccc locally and the host will still see Bret swords thinned on the client's husk. Need an RPC carrying `{ wearer_peer_id, scale_toggle_state }` (or a more generic per-peer "weapon-scale prefs" payload) and an owner-aware lookup in `_apply_unit_path_scale_hand`. **Or** declare this a viewer-preference setting and never broadcast (clarify intent first — see recommendations).

### Hard (need owner-aware apply rework)

3. **All 12 `glow_*` settings**. This is the largest single gap and is greenfield.

   Currently `_hook_apply_with_template_mutation` mutates the SHARED `MaterialSettingsTemplates[name]` global based on local viewer's `mod:get`, calls vanilla apply, restores. The mutation is the local viewer's color regardless of which peer owns the unit being spawned.

   Required rework:
   - Per-peer state cache `_glow_by_peer[wearer_peer_id] = { enable, preset_rgb, per_channel_rgb_table, mults_table, master_mult }`.
   - New RPC `cos_glow_apply { wearer_peer_id, payload }` (host-authoritative, mirrors `cos_la_apply`). Wearer emits to host on equip and on settings-change; host validates and broadcasts.
   - Owner-aware lookup inside the apply hook: identify wearer from the unit via `Managers.player:owner(unit)` for local-spawned units OR via the SimpleHuskInventoryExtension parallel for husks. If owner is local player, read local `mod:get`; else read `_glow_by_peer[owner_peer]`. Fall back to local `mod:get` if not received yet.
   - Reception of own glow back from host (the wearer's own setting): the wearer's local viewer normally reads `mod:get` directly, but if the unified design routes ALL glow through `_glow_by_peer` (server-authoritative even for self), need the wearer to receive `cos_glow_apply` for their own peer_id. Easier: keep self-read direct via `mod:get`, only consult `_glow_by_peer` for REMOTE husks.
   - Per-channel cache update flow: 12 settings means a settings-change broadcast can pack the whole glow state per peer in one RPC (~12 numbers + 5 dropdown enum ints + 2 booleans = small, ~50 chars JSON, well under STRING_MAX=500). Use `mod.on_setting_changed` for setting_id startswith "glow_" to fire the RPC.

   Note on `MaterialSettingsTemplates` global mutation race: the apply window is synchronous within a single Lua thread, but mutation now must vary by which unit is being spawned within a single frame (host equips two weapons in same tick — host's own and a remote husk's). The mutate-apply-restore is local to one `func(unit, material_settings_name)` call, so no race. But: the read of "whose glow is this?" must happen INSIDE the mutate-apply-restore window. Lookup wearer from unit at the start of the hook, mutate to that wearer's RGB, call vanilla, restore. Adds one `Managers.player:owner(unit)` call per `apply_material_settings`.

4. **LA weapon-illusion peer paint persistence across wield cycles**. Currently `_apply_la_on_unit kind="illusion"` only paints the wielded weapon's 3P units. If wearer carries melee for 5+ seconds then wields ranged, the pending-queue has expired and the peers see vanilla on the now-wielded weapon. Need a `SimpleHuskInventoryExtension.wield` hook on receivers to re-apply LA paint from `_la_equips_by_peer[wearer_peer]` when a husk wields a slot whose entry has `kind="illusion"`.

5. **Hot-join replay uses local `_local_la_equips` not authoritative `_la_equips_by_peer`** (already flagged in HOST_CLIENT_AUDIT §A1). On joiner-arrival the existing player's `AttachmentUtils.hot_join_sync` hook replays from `_local_la_equips[unit]` (line 3818-3833) which is only populated for the LOCAL peer's equips. Other peers' equips don't replay. The fix is to drive hot-join replay from `_la_equips_by_peer` on the host (which has ALL peers' equips) — host receives the new joiner's connect and replays every peer's recorded entries.

6. **`_offhand_selection` receiver-side seed on `cos_la_apply` kind="offhand"**. Receiver applies the paint immediately but doesn't write to `_offhand_selection[bid]` for the wearer. On any later equip spawn (career switch on husk, weapon re-spawn from late package load), the local hooks (`get_item_units`, `_apply_la_offhand_to_units`) check `_offhand_selection` for that backend_id and find nothing → no override → vanilla mesh re-shows. Currently only the 5s pending-queue keeps this from being a permanent desync after re-spawn.

---

## 4. Unified design recommendations

### Payload shape for unified `cos_visual_state`

A per-wearer broadcast at equip-change and settings-change time. Carry only what NEEDS per-wearer override. Out-of-scope state (vanilla equips, frames, cos_unlock filters) stays on vanilla / local-only paths.

```lua
{
    wearer_peer_id = "...",         -- identity key (deterministic, host-authoritative)
    timestamp      = ...,           -- for late-arrival ordering
    -- Per-slot LA equips (replaces current cos_la_apply payload):
    la_equips = {
        slot_hat   = { kind="hat",      armoury_key="...", vanilla_key="..." },
        slot_skin  = { kind="armor",    armoury_key="...", vanilla_key="..." },
        slot_melee = { kind="illusion", armoury_key="...", vanilla_key="..." },
        -- + offhand entry keyed by slot of wielded weapon
        -- + kind="offhand" entries with armoury_key | "vanilla_mesh"+unit_path
    },
    -- Glow state (all 12 settings):
    glow = {
        enable          = bool,
        preset          = "white_glow"|"purple_glow"|...|"default",
        per_channel     = bool,
        color_lower     = "...",
        color_upper     = "...",
        color_dots      = "...",
        mult_master     = 1.0,
        mult_rune       = 1.0,
        mult_glow_high  = 1.0,
        mult_glow_low   = 1.0,
        mult_smoke_high = 1.0,
        mult_smoke_low  = 1.0,
        mult_dots       = 0.0,
    },
    -- Weapon-model toggles (currently 1 entry; extension point for future model tweaks):
    model_tweaks = {
        es_bastard_sword_thiccc = bool,
    },
    -- Vanilla-mesh offhand picks: per-slot, identified by slot_name (since
    -- backend_id is not necessarily portable across peers).
    offhand_vanilla = {
        [slot_name] = { unit_path = "units/.../..." },
    },
}
```

Size estimate: ~600-800 chars JSON for a fully-populated wearer state. **Over STRING_MAX=500** — must chunk per `reference_vmf_rpc_string_cap.md`. Mirror `chaos_wastes_tweaker.lua:252-389` shared_state.lua-style chunking (400-char per chunk, session id, seq/total).

Alternative: split into TWO RPCs — `cos_la_apply` (current shape, already <500) for LA equips, `cos_glow_apply` for the glow block (also <500 alone). Both can carry `wearer_peer_id` and version separately. Simpler than chunking.

### Per-peer cache shape (every machine maintains)

```lua
_cos_state_by_peer = {
    [wearer_peer_id] = {
        la_equips      = { [slot_name] = { kind, armoury_key, vanilla_key } },
        glow           = { enable, preset, per_channel, colors, mults, ... },
        model_tweaks   = { ... },
        offhand_vanilla = { [slot_name] = { unit_path } },
    },
}
```

Host additionally maintains `_la_equips_by_peer` as the authoritative source-of-truth for re-broadcast on hot-join and host-migration.

### Apply hooks needing owner-aware rework

1. **`_hook_apply_with_template_mutation`** (cosmetics_tweaker.lua:2496) — three install sites (GearUtils/_G/CosmeticUtils, lines 2548-2557). Replace `_glow_rgb_for_var(var)` with `_glow_rgb_for_var(var, owner_peer_id)`. Resolve owner from `unit` via `Managers.player:owner(unit)` or fall back to scanning all players for a unit match (for husks where `:owner()` might not resolve). For own units, read `mod:get` directly.

2. **`GearUtils.spawn_inventory_unit` template injection** (line 2595) — same owner resolution.

3. **`_apply_glow_override(units)` at `create_equipment`** (line 2472, 2744) — pass owner peer; loop units with owner-aware RGB lookup.

4. **`_apply_unit_path_scale_hand`** (line 2304) and **`_breton_sword_thiccc(get)`** (line 746) — `get` should be the wearer's settings, not the local viewer's. Pass `owner_peer_id` through `_scale_units`/`_apply_unit_path_scale_hand`/`_resolve_factor` and adapt `_breton_sword_thiccc` to take peer instead of `get`.

5. **`BackendUtils.get_item_units` hook** (line 2153) — currently reads `_offhand_selection[bid]` keyed by local table. For remote husks, need to consult `_cos_state_by_peer[owner_peer].offhand_vanilla[slot_name]` instead (or in addition).

6. **`_apply_la_offhand_to_units`** (line 2696) — same. Currently reads `_offhand_selection[bid]`; for husks read per-peer cache.

7. **`SimpleHuskInventoryExtension.wield` hook (NEW)** — fires when a remote husk wields a slot. Look up `_cos_state_by_peer[owner_peer].la_equips[slot]`; if `kind="illusion"`, re-call `_apply_la_on_unit` on the newly-wielded weapon. Closes the >5s sheathe/unwield gap.

8. **Hot-join replay (host-side)** — on new peer connect, host iterates `_la_equips_by_peer` and broadcasts a `cos_visual_state` for every existing peer to the new joiner. Replaces the current per-peer `_local_la_equips`-driven replay.

9. **`_la_equips_by_peer` and `_cos_state_by_peer` peer-disconnect cleanup** — hook the player-disconnect event to drop entries.

### Phasing recommendation

1. **Phase A — extend existing `cos_la_apply`** to cover vanilla-mesh offhand picks (medium gap #1). Adds one new payload variant. Minimal new infrastructure.
2. **Phase B — new `cos_glow_apply` RPC + `_glow_by_peer` cache + owner-aware apply hooks** (hard gap #3). Largest single change; user's #1 complaint.
3. **Phase C — owner-aware model_tweaks broadcast** (medium gap #2). Decide first whether `es_bastard_sword_thiccc` is per-wearer or viewer-preference (current behavior is "everyone sees my Bret sword the way I prefer" — arguably already correct as a viewer preference, since it's a model-shape opinion, not a wearer-identity choice. Confirm with user.)
4. **Phase D — fix LA wield-cycle persistence** (hard gap #4) and **hot-join replay from authoritative state** (#5) and **receiver-side `_offhand_selection` seed** (#6). Cleanup on existing LA pipeline.

### Out of scope (clarify intent before broadcasting)

- **TPE settings** (`tpe_enable`, `tpe_show_self_in_3p`, `tpe_downscale_big_weapons`) are per-viewer overlay preferences. There is no per-wearer customization to broadcast — every viewer chooses whether THEY see TPE meshes. Recommend keeping local.
- **`cos_unlock_*`** are inventory-availability filters, not on-character visuals. Equipped cosmetic syncs natively via vanilla key.
- **`unlock_all_illusions` / `unlock_all_frames`** are local backend-mirror unlocks. Equipped cosmetic syncs natively.
- **`la_bridge_enable`** is a gate flag. The bridge requires both peers to have it ON to see LA visuals — there's no per-wearer state to broadcast for this toggle itself.
