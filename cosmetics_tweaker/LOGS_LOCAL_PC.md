# Local-PC VT2 Log Extraction — CT/LA Desync Investigation

Extracted from the two most-recently-modified VT2 console logs on this PC (danjo / 11000010ef3befb).

## 1. Log file selection

| # | Path | Size | LastWriteTime | Lines |
|---|------|------|---------------|-------|
| A | `C:\Users\danjo\AppData\Roaming\Fatshark\Vermintide 2\console_logs\console-2026-05-19-19.41.36-4bf12bfc-d305-482c-af90-0496f6e23c90.log` | 435,698 B | 2026-05-19 14:49:59 | 4,472 |
| B | `C:\Users\danjo\AppData\Roaming\Fatshark\Vermintide 2\console_logs\console-2026-05-19-19.18.05-dc114fde-05c0-4ef0-bfe5-c3f7630ea05d.log` | 471,099 B | 2026-05-19 14:36:51 | 4,843 |

Both sessions are this user (Ensrick, `11000010ef3befb`) running as **host** (`host_type = 1`), with the friend `1100001428b80b3` connecting as **client**. Both sessions ended cleanly (`Lua signals application exit`, `force silent exit code`) — **no crash, no fatal**.

CT version observed: `Cosmetics Tweaker v0.8.67-dev`. LA mod present: `Loremaster's Armoury` (workshop_id 2789506353), loaded BEFORE CT in mod ordering (line 1115 vs 1267 in log A).

---

## 2. Errors and stack traces (full context)

### Log A — Only Lua error is from an unrelated mod, fired AFTER game exit started

There are **no** `[Engine Error]`, `[Script Error]`, `attempt to index/call`, `assertion failed`, `fatal`, or `Stack traceback` lines in log A. The only `error:` markers are the boring boot-time ones:

- `19:41:36.793 warning: [D3D12_RENDER_DEVICE] SL Error: …nvngx_update.exe …` (×4) — NVIDIA Streamline DLSS auto-update can't reach the network; harmless.
- `19:41:51.017 error: [ResourcePackage] Synchronous package load of '#ID[e4a1e23d]'` — vanilla startup warning.
- `19:42:02.860 error: [Lua] Missing xbox achievement "divine_generator_challenge"` (and friends) — vanilla DLC achievement registration noise.
- Long block of `warning: [ResourceManager] Don't know how to load #ID[3fcdd69156a46417] #ID[...]` — VMF probing for mod resources, normal.

### Log B — One Lua error, fired DURING shutdown of an unrelated mod

```
19:36:45.439 [Lua] Error: ...sshair Kill Confirmation/Crosshair Kill Confirmation.lua:235:
    attempt to index field 'world' (a nil value)
  Callstack:
    [1] @scripts\mods\vmf\modules\core\safe_calls.lua:16: in function __index
    ...
    [12] @scripts\boot.lua:711
  Locals:
    error_message = "...:235: attempt to index field 'world' (a nil value)"
    exit_game = true
    mod = ...796C020 ; error_prefix_data = "(event) on_unload"
19:36:45.439 [Lua] [MOD][Crosshair Kill Confirmation][ERROR] (event) on_unload: ...:235: attempt to index field 'world' (a nil value)
19:36:45.441 [Lua] VMF:ON_UNLOAD()
```

This is third-party mod **Crosshair Kill Confirmation** crashing in its `on_unload` handler during quit-to-desktop. Unrelated to CT/LA. Not a cause of the desync.

### CT/LA actual error pattern (NOT classified as Lua error — caught and logged by CT)

In both logs, when the user changes Kruber's hat from a CT-managed LA hat illusion back to a vanilla questing-knight hat, CT logs a single line:

```
[MOD][cosmetics_tweaker][INFO] [net-safe] sync_loadout_slot slot_hat
    LA(questing_knight_hat_0001_LA_Kruber_Pureheart_helm_white) -> vanilla(questing_knight_hat_0001)
[MOD][cosmetics_tweaker][INFO] [cos_la_apply hat] create_attachment Kruber_Pureheart_helm_white failed:
    scripts/helpers/attachment_utils.lua:4: Slot is not empty, remove attachment before creating a new one.
```

**This is the CT/LA bug surface.** It is swallowed (CT logs as INFO, not ERROR; engine never sees an unhandled Lua error) but it means the attachment slot **does not transition cleanly** between LA and vanilla hats — the previous attachment was not torn down before CT tried to graft the new LA cosmetic on.

---

## 3. CT/LA timeline (chronological)

### Log A — session 19:41:36 → 19:49:59 (8 min)

| Time | Phase | Event |
|------|-------|-------|
| 19:42:07.823 | Boot | LA hooks installed (send_rpc_server, _get_no_wield_required_property_and_trait_buffs, link_unit, AttachmentUtils.link, HeroPreviewer._spawn_item_unit, PackageManager load/unload, …) |
| 19:42:08.394 | Boot | CT hooks installed including `wield`/`destroy`/`destroy_slot` on **both** SimpleInventoryExtension AND SimpleHuskInventoryExtension; `apply_material_settings` on GearUtils and CosmeticUtils |
| 19:42:08.394 | Boot | `[GLOW] _G.apply_material_settings nil at hook time` — CT's glow hook attempts global lookup before it's populated |
| 19:42:08.395 | Boot | `[net-safe] hook registration: CosmeticUtils=true LoadoutUtils=true AttachmentUtils=true PUAE=true` |
| 19:42:09.616 | Boot | CT `[LA bridge] pre_register_la_inventory_packages: 31 variant(s)` registered |
| 19:42:09.618 | Boot | CT registers 5 LA offhand shield pools (es_1h_sword_shield_breton: 11, es_deus_01: 8, es_1h_sword_shield: 8, es_1h_mace_shield: 8, we_1h_spears_shield: 12). `[LA bridge] apply gate installed (raw replacement)`. 35 LA items registered, 0 skipped. |
| 19:42:29.522 | Solo (keep) | host num_players 1, peer_hot_join_synced for self |
| 19:42:31.232 | Solo | ProfileSynchronizer hot_join_sync for self |
| 19:42:35.189 | Solo / inventory open | `[LA paint] skip: no _offhand_selection for backend_id=502C1B4B2D86C217` + `=29D8DF12F964B3C6` + 2× `has_skin=false` — paint hook firing on two ranged backends that don't have an offhand selection |
| **19:42:44.825** | **Friend joins** | `[LobbyMembers] Member joined 1100001428b80b3` — num_players 1→2 |
| 19:42:50.043 | Hot-join | `[ProfileSynchronizer] Running hot_join_sync for peer 1100001428b80b3` |
| 19:42:56.369 | Hot-join | `peer_hot_join_synced:1100001428b80b3:0:0:0:0 = true` (took ~6.3s) |
| 19:43:35.113 | Friend present | LA paint skip series repeats (4 lines) |
| 19:43:38.695-695 | Hat change #1 | `[LA paint] skip: has_skin=false` ×2 |
| 19:43:38.827 | Hat change #1 | `sync_loadout_slot slot_hat LA(questing_knight_hat_0001_LA_Kruber_Pureheart_helm_white) -> vanilla(questing_knight_hat_0001)` |
| 19:43:38.828 | **BUG** | `[cos_la_apply hat] create_attachment Kruber_Pureheart_helm_white failed: Slot is not empty` |
| **19:44:05.786** | **Friend leaves** | num_players 2→1 |
| **19:45:34.882** | **Friend rejoins** | num_players 1→2 |
| 19:45:39.246 | Hot-join | hot_join_sync for peer 1100001428b80b3 |
| 19:45:55.527 | Hot-join | peer_hot_join_synced=true (took ~16.3s — much slower than first join) |
| 19:46:13.816 | Friend present | LA paint skip series repeats (4 lines, both backends) |
| 19:46:16.782 | Hat change #2 | `[LA paint] skip: has_skin=false` ×2 |
| 19:46:18.438 | Hat change #2 | `[LA paint] skip: has_skin=false` ×2 |
| 19:46:18.526 | Hat change #2 | `sync_loadout_slot slot_hat LA(questing_knight_hat_0003_LA_Kruber_Hippogryph_helm_white) -> vanilla(questing_knight_hat_0003)` |
| 19:46:18.526 | **BUG** | `[cos_la_apply hat] create_attachment Kruber_Hippogryph_helm_white failed: Slot is not empty` |
| 19:49:55.289 | Friend leaves | num_players 2→1 |
| 19:49:57.856 | Quit | clean shutdown |

### Log B — session 19:18:05 → 19:36:51 (18 min, earlier)

Same shape:

| Time | Event |
|------|-------|
| 19:18:40 | LA + CT hooks installed (same set, mod ordering identical) |
| 19:18:42.110 | CT LA bridge: 31 variants pre-registered, 35 items registered, same 5 offhand pools |
| 19:18:59.840 | Self hot-join-synced |
| 19:19:05.768 | `[LA paint] skip: no _offhand_selection` 502C1B4B & 29D8DF12 + 2× has_skin=false |
| 19:19:09.008 | Same LA paint skip series |
| 19:19:11.285 | `[LA paint] skip: has_skin=false` ×2 |
| 19:19:11.297 | `sync_loadout_slot slot_hat LA(questing_knight_hat_0003_LA_Kruber_Hippogryph_helm_white) -> vanilla(questing_knight_hat_0003)` |
| 19:19:11.297 | **BUG** `[cos_la_apply hat] create_attachment Kruber_Hippogryph_helm_white failed: Slot is not empty` |
| **19:19:24.313** | **Friend joins** (first time) |
| 19:19:29.655 | hot_join_sync for 1100001428b80b3 |
| 19:19:40.809 | peer_hot_join_synced=true (~11.2s) |
| 19:20:46.072 | Friend leaves (num_players 2→1) |
| 19:29:58.224 / 19:29:59.495 | LA paint skip series repeats while solo |
| **19:35:43.125** | **Friend rejoins** |
| 19:35:46.387 | hot_join_sync |
| 19:35:57.672 | peer_hot_join_synced=true (~14.5s) |
| 19:36:28.525 | LA paint skip series (4 lines, both backends) |
| 19:36:30.806 | `[LA paint] skip: has_skin=false` ×2 |
| 19:36:30.938 | `sync_loadout_slot slot_hat LA(questing_knight_hat_0001_LA_Kruber_Pureheart_helm_red) -> vanilla(questing_knight_hat_0001)` |
| 19:36:30.938 | **BUG** `[cos_la_apply hat] create_attachment Kruber_Pureheart_helm_red failed: Slot is not empty` |
| 19:36:45.439 | Unrelated Crosshair Kill Confirmation on_unload error (game shutting down) |

**Crucial observation:** the "Slot is not empty" `cos_la_apply hat` failure also occurs when the user is **solo** (log B, 19:19:11.297 — friend hasn't joined yet). So the slot-cleanup bug is **not** a host/client desync per se — it's a CT-local code path that runs whenever a player switches between LA-mapped and vanilla hat illusions on the same character. The friend's presence is incidental to *this particular log line*, though it may compound subsequent desync.

---

## 4. RPC anomalies

No `STRING_MAX`, `chunk too`, `chunked_rpc`, `payload too`, `too large`, or `truncated` markers in either log. No oversized-RPC failure detected.

No explicit `rpc_add_equipment` / `rpc_wield_equipment` / `rpc_create_attachment` lines were logged — these RPCs fire silently in vanilla. Nothing in CT/LA emits a `[net-safe]` send-failure or `network_send returned false`.

Hot-join timings:

| Log | First hot_join_sync | Subsequent rejoin |
|-----|---------------------|--------------------|
| A | 6.3 s | 16.3 s |
| B | 11.2 s | 14.5 s |

Rejoin took noticeably longer than first join in both sessions (15s vs 8s avg). This is *probably* because vanilla profile-resync has more state to walk after the keep has aged (more inventory items mutated, more attachments to enumerate), but it's worth noting if the user reports the friend's first 10–15 s after rejoin show wrong cosmetics.

CT's `[net-safe]` log channel emits only:
- `hook registration` (once at boot, all 4 hooks reported true)
- `sync_loadout_slot slot_hat LA(...) -> vanilla(...)` (only on actual hat-slot changes)

No `[net-safe]` errors, warnings, or send-side failures recorded.

---

## 5. Pattern summary — top 5 patterns

1. **`cos_la_apply hat] create_attachment ... failed: Slot is not empty`** — fired exactly once per hat-slot change between any two LA-mapped hat illusions. Confirmed in both logs (3 occurrences across 2 sessions, on 3 different LA hats: Pureheart_helm_white, Hippogryph_helm_white, Pureheart_helm_red, Hippogryph_helm_red). **Likely cause:** CT's `cos_la_apply` path for slot_hat calls `AttachmentUtils.create_attachment` without first calling `AttachmentUtils.destroy_attachment` for the existing slot. The matching destroy hooks are registered for `SimpleInventoryExtension.destroy_slot` / `SimpleHuskInventoryExtension.destroy_slot`, but those fire on weapon-slot teardown, not cosmetic-hat slot transitions.

2. **`[LA paint] skip: no _offhand_selection for backend_id=502C1B4B2D86C217` / `=29D8DF12F964B3C6`** — fires every time the LA paint hook walks the wielded backend pair. These two backend IDs persistently lack `_offhand_selection` in CT's table. Could mean (a) two specific ranged weapons CT never marked with an offhand, OR (b) the paint hook is being called on ranged weapons where offhand selection is conceptually N/A. Volume: 4 lines per paint walk × ~7 walks per session = ~28 noisy logs per session.

3. **`[LA paint] skip: has_skin=false`** — fires in pairs alongside the slot_hat sync, suggesting the paint hook is invoked once per slot and skips because the equipped hat doesn't carry a `_skin` field. Cosmetic, but loud.

4. **`[GLOW] _G.apply_material_settings nil at hook time`** — fired once at boot. CT's glow hook discovers the global isn't set when CT loads. CT still hooks `GearUtils.apply_material_settings` and `CosmeticUtils.apply_material_settings` directly. If glow customization is missing from logs / not working in-game, this nil-at-hook-time is the smoking gun — the global wrapper was never installed.

5. **`[LA bridge] apply gate installed (raw replacement)`** + **`pre_register_la_inventory_packages: 31 variant(s) registered (sorted, all kind=unit)`** — CT is pre-registering LA inventory packages in **sorted** order. This is consistent with `feedback_vt2_gated_registration_diverges.md` (must be sorted, unconditional). Good. 35 items registered, 0 skipped, in both sessions.

### Notable absence

- **No husk-side log channel.** CT's hat-attachment failure log only fires on the local (host) player. Whether the friend's husk sees the broken hat cannot be confirmed from these logs — they're host-only console output.
- **No `BackendUtils.get_item_units` error or warning.** The hook is installed (line 1304 log A) but logs nothing.
- **No SimpleHuskInventoryExtension events logged**, despite three hooks being installed on it. Either the friend never wielded an LA-mapped weapon during the visit, OR CT's husk-side handlers are silent (no INFO trace) by design.
