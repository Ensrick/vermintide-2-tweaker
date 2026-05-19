# PC-B Console Log Analysis

Investigation of host/client desync between cosmetics_tweaker (`ct`/`cos`) and Loremaster's Armoury (LA) on PC-B (Tailscale tunnel, user `ensrick`).

## 1. Log File Selection

Source: `C:\Users\Ensrick\AppData\Roaming\Fatshark\Vermintide 2\console_logs\` on PC-B (Tailnet 100.117.23.21). Game's launcher log (`vermintide2_launcher.log` in same dir) was not useful — the per-session console logs are the canonical record.

| Local copy | Original path | Size | mtime (PC-B local) |
|---|---|---|---|
| `_pc_b_logs/pc_b_console_2026-05-19_19.44.33.log` | `console-2026-05-19-19.44.33-f9d1c501-…log` | 407 012 B | 2026-05-19 14:49:57 |
| `_pc_b_logs/pc_b_console_2026-05-19_19.34.51.log` | `console-2026-05-19-19.34.51-6be55b9e-…log` | 547 248 B | 2026-05-19 14:44:07 |

Both pulled via `scp` over the Tailscale `pc-b` host alias; sizes match remote.

## 2. PC-B Network Role

PC-B's own Steam peer id (both sessions): **`1100001428b80b3`**.

### Session A — `console-…19.34.51.log` (mtime 14:44 local, 19:35–19:43 UTC in log)
- **19:35:28** — Solo `LobbyHost` (single-player inn). `NetworkServer Players: 1`.
- **19:35:42** — `LobbyClient Created` → connects to server peer `11000010ef3befb` (PC-A). PC-B is now CLIENT.
- **19:35:45** — `network_context_created server_peer_id=11000010ef3befb, own_peer_id=1100001428b80b3` (confirmed client). State machine walks `connecting → connected → loading → loaded → waiting_enter_game → is_ingame → game_started`.
- **19:36:42** — `[NetworkClient] rpc_connection_failed due to host_left_game` → state `denied_enter_game`. PC-A ended the test.
- **19:36:44** — PC-B resumes as solo host.
- **19:42:43** — Re-joins same PC-A host as CLIENT for a second test session.

### Session B — `console-…19.44.33.log` (mtime 14:49 local, 19:44–19:50 UTC in log)
- **19:45:11** — Solo `LobbyHost`. Lobby unique_server_name = "CakeCat", network_hash = `0252d7010c18b370`, num_levels=582 (ct adventure-injected count present; combined_hash matches a peer that also has ct).
- **19:45:34** — Becomes CLIENT again to host peer `11000010ef3befb` (PC-A). Joins lobby `186000014a0b507`.
- **19:49:53** — `[NetworkClient] New State lost_connection_to_host` → `LobbyClient close server channel 1 to 11000010ef3befb`. Disconnect, no further sessions.

**Conclusion: in both relevant multiplayer windows PC-B was the CLIENT and PC-A (peer `11000010ef3befb`) was the HOST.**

## 3. Mod Inventory (both sessions identical)

VMF init order on PC-B:
- `Loremaster's Armoury` (workshop_id 2789506353) — init at 19:35:11 / 19:44:53. Hooks `NetworkTransmit.send_rpc_server`, `SimpleInventoryExtension._get_no_wield_required_property_and_trait_buffs`, `World.link_unit`, `AttachmentUtils.link`, `HeroPreviewer._spawn_item_unit`, `HeroPreviewer.post_update`, plus PackageManager/Localization/Achievement hooks. Notably it hooks `HeroPreviewer._spawn_item_unit` — **not `MenuWorldPreviewer`** — so its preview unit hooks fire on `team_previewer.lua` only, not on the keep inventory (consistent with `feedback_inventory_preview_hook_menuworldpreviewer.md`).
- `cosmetics_tweaker v0.8.67-dev` — init at 19:35:12 / 19:44:53. Standard hook set: SimpleInventoryExtension, SimpleHuskInventoryExtension (both `wield`, `destroy`, `destroy_slot`), CosmeticUtils, GearUtils, LoadoutUtils, PlayerUnitAttachmentExtension, AttachmentUtils, World.link_unit, MenuWorldPreviewer + HeroPreviewer (`equip_item`, `_spawn_item`, `_spawn_item_unit`), LootItemUnitPreviewer.
- Also loaded: `gt`, `ct`, `crt`, `wt`, `verminious_dreams_lighting`. ct logs `pre-registered 9 buff templates + 9 power-up names for client compat` and `pre-registered 4 trait boons for client compat` and `Lobby hash shim installed (vanilla level_keys count = 582)`.

## 4. Errors and Warnings

### 4.1 Pre-existing string.format crash (NOT the desync bug)
`general_tweaker_data.lua:165` triggers `string.format` "Invalid string format" at mod init (line 792 in both logs). Stack:
```
[4] @scripts/mods/vmf/modules/core/localization.lua:24: safe_string_format
[5] @scripts/mods/vmf/modules/core/localization.lua:49: localize
[6] @scripts/mods/general_tweaker/general_tweaker_data.lua:165: in main chunk
```
Caused by an un-escaped `%` (literal "5%") in the description string. This is a `crashify-exception` that's caught and logged but doesn't fatal — gt still loads. Cosmetic only; deserves a `%%` fix in `gt` but unrelated to the LA/CT desync.

### 4.2 Resource warnings (recurring, vanilla noise)
`#ID[3fcdd69156a46417]` is the unknown resource type LA tries to load — ~12 distinct unit IDs all fail with the same `Don't know how to load 'X' '#ID[…]'` and `Ignoring resource lookup for unknown resource type` warning pair (lines 658-1104 of `19.44.33`, 659-1105 of `19.34.51`). Each lookup also triggers a `Synchronous package load` warning shortly after. Pattern is consistent across both logs and identical timing relative to startup — this is LA's package preload list firing once per launch, not a runtime desync trigger.

`#ID[5a0213f3]`, `#ID[6e98026a]` — `[MeshObject] Failed looking up material … in unit #ID[1fb853701ecc3ad8]` / `#ID[79faad3b728de276]` / `#ID[9fb763101a3d9819]`. These fire at every keep entry and again at every level reload (lines 2166-3410 of `19.44.33`, 2167-4798 of `19.34.51`) — same units, same missing materials, both sessions. Likely an LA cosmetic unit referencing a vanilla material slot that no longer exists. Not host-only and not client-only.

### 4.3 NO fatal Lua errors, NO `[Engine Error]`, NO `attempt to index nil`, NO assertion failures
Grep across both logs for `[Script Error]`, `Lua error`, `attempt to`, `nil value`, `assertion failed`, `Resource not found`, `fatal` returns only the gt string.format exception above. The session ended via `host_left_game` (session A) and `lost_connection_to_host` (session B), not via a crash.

## 5. CT/LA Bridge Timeline

The single most prominent CT/LA log line, in both sessions and at every keep entry / mission load:

```
[MOD][cosmetics_tweaker][INFO] [LA paint] skip: bridge not registered
```

Occurrences:
- 19.34.51 log: lines 2474–2477, 2518–2519, 3278–3281, 4048–4051, 4800–4803, 4939–4944 (≈ 28 hits across the run)
- 19.44.33 log: lines 2432–2435, 2476–2477, 2564–2565, 2598–2599, 2604–2605, 2709–2712, 3412–3415 (≈ 24 hits)

This is `cosmetics_tweaker` trying to apply LA paint to a previewer-spawned unit and finding `cosmetics_tweaker._la_bridge` (or whichever bridge sentinel CT checks) is nil. Each "skip" pair fires per previewer item spawn — confirmed by interleaving with `[LA preview] _spawn_item name=… direct=true` lines (e.g. 19.44.33 lines 2474-2477: `_spawn_item we_longbow` immediately followed by two `LA paint] skip: bridge not registered`).

CT's `[LA preview] equip_item` instrumentation IS firing correctly and resolving backend skin IDs (`backend-resolved skin for we_longbow: we_longbow_skin_04`, `backend-resolved skin for dr_handgun: dw_handgun_skin_02`, etc.), so the previewer flow reaches the bridge call site — but the bridge handle is never published by LA on this PC-B build.

**There is no `cos_la_apply`, `cos_la_attach`, `cos_la_apply_req`, `_la_equips_by_peer`, `_local_la_equips` log line in either file** — these CT bridge entrypoints are never reached because the bridge itself is unregistered. The RPC integration code path is dead on PC-B.

## 6. Husk and RPC Layer

- Both CT and `wt` hook `SimpleHuskInventoryExtension.wield`/`destroy`/`destroy_slot` (lines 1108-1113 of 19.44.33). Hooks register without errors.
- Husk packages load normally on each client-side level entry: `chr_third_person_husk_base` for `way_watcher` (PC-B's career) loads and force-loads cleanly at 19:35:45, 19:42:49, 19:45:38.
- **NO `rpc_create_attachment` mismatch, NO `rpc_add_equipment` failure, NO `STRING_MAX` / chunking warnings, NO `network_send` failures** in either log. The vanilla equipment RPC path is healthy.
- Profile sync on first client entry (19:45:16 in session B) shows PC-B sending its full `inventory_list` `SharedState` — vanilla unit paths only (`wpn_we_bow_02_t2`, `way_watcher_upgraded_skin_01`, etc.). No CT-injected paths, no LA-injected paths in the broadcast.

## 7. Pattern Summary

1. **PC-B is the CLIENT in both relevant test sessions.** Host is PC-A peer `11000010ef3befb`.
2. **The CT→LA bridge is not registered on PC-B.** `[LA paint] skip: bridge not registered` fires consistently at every previewer spawn in both sessions. CT's hooks AND LA's hooks both load, both initialize VMF, but the explicit handshake handle CT looks for is absent. Either (a) LA's bridge registration code path requires a specific call site that isn't being hit on PC-B's career/items, (b) the LA version installed on PC-B (last updated 12/9/2024 — over a year old) predates the bridge API CT expects, or (c) CT's bridge probe runs too early and never re-checks.
3. **The desync would not surface as a Lua crash here** — because the bridge is never registered, CT bails out gracefully on every "LA paint" attempt rather than executing the mis-synced material code. Whatever desync the user is seeing client-side is the result of LA's vanilla code path running unaugmented on PC-B's husks while PC-A (host) potentially has the bridge functional.
4. **LA workshop id 2789506353 last_updated="12/9/2024"** is suspicious — verify both PCs have the same LA version. The PC-A log (sister agent) should be cross-checked for "Init VMF mod 'Loremasters-Armoury'" timing and for whether `bridge: registered` (or whatever CT logs on the success path) ever fires there.
5. **Material lookup failures (`#ID[5a0213f3]`, `#ID[6e98026a]`) on units `#ID[1fb853701ecc3ad8]` / `#ID[79faad3b728de276]` / `#ID[9fb763101a3d9819]`** are persistent across both sessions but happen during keep-painting/lobby setup, not during gameplay. Almost certainly an LA-shipped unit referencing a material that vanilla VT2 has since renamed. Tracked but probably orthogonal to the husk-render desync.
6. **No `Engine Error: Resource not found`** — the previously hot path for CT/LA crashes (per `reference_vt2_hash_reverse_lookup.md`) is not triggered in either session.

## 8. Recommended Next Steps (for caller)

- Confirm PC-A's `Loremaster's Armoury` mod last_updated date matches PC-B's `12/9/2024`. If PC-A has a newer LA, mismatch alone could explain why the bridge handle exists host-side but not client-side.
- In CT source, locate the `[LA paint] skip: bridge not registered` log site and the corresponding registration write — that registration must run on every peer that has LA installed; if it's gated on `is_server` or runs only when a mission entity LA-tagged spawns, that's the gap.
- Re-run the test with `script_data.network_debug = true` and capture the rpc_loading_synced → game_started window — that's where any chunked CT/LA payload would first fire.
