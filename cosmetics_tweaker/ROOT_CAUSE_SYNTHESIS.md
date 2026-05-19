# Root-Cause Synthesis — CT/LA Host/Client Desync

**Date:** 2026-05-19
**Status:** COMPLETE — six research agents reported, log evidence included
**Source documents:**
- `HOST_CLIENT_AUDIT.md` — current CT code map
- `LA_SYNC_MODEL.md` — LA's own networking (or lack thereof)
- `VT2_NETWORKING_REFERENCE.md` — Stingray/VT2 sync primitives
- `PRIOR_ATTEMPTS_TIMELINE.md` — 4 days of failed fix attempts
- `LOGS_LOCAL_PC.md` — PC-A (host) console logs, 2026-05-19 19:18-19:50
- `LOGS_PC_B.md` — PC-B (client) console logs, 2026-05-19 19:34-19:50

---

## ✅ ROOT CAUSE — single missing dependency on PC-B

PC-B (client) is not subscribed to **MoreItemsLibrary** (Workshop ID `1422758813`).

CT's LA bridge init lives in `mod.update` and is gated on four conditions (`cosmetics_tweaker.lua:3881-3886`):
```lua
if mod:get("la_bridge_enable")
   and ItemMasterList
   and get_mod("Loremasters-Armoury")
   and get_mod("MoreItemsLibrary") then
    LA_BRIDGE.register_all()
    ...
```

**Evidence:**
- PC-A log (console-2026-05-19-19.41.36): `'MoreItemsLibrary' Mod loading...` at line 1084, `Init VMF mod 'MoreItemsLibrary' [workshop_id: 1422758813]` at line 1088 → bridge gate opens → `[LA bridge] registered 35 items, skipped 0` → all RPCs work.
- PC-B log (both sessions): zero mentions of MoreItemsLibrary. Bridge gate never opens → `[LA paint] skip: bridge not registered` ×50+ → CT's entire LA receiver pipeline dormant.
- PC-B Workshop subscriptions include 18 items — LA (2789506353), all the tweakers, helpers — but NOT 1422758813.
- PC-A and PC-B have byte-identical CT installs (SHA256 match on all 5 files). The bug is not in our code; it's a missing peer dependency on the client.

**Why this single missing mod produces ALL 4 user-visible symptoms:**
- Axis 1 (LA items wrong host↔client): client receiver returns `skip: bridge not registered` for every paint/attach broadcast from the host
- Axis 2 (custom-mesh crashes): when the bridge is dormant, peer-load guards never engage; spawn races can hit unloaded resources
- Axis 3 (hat colors don't show for all): same as Axis 1 — host paints locally, client never receives the message that translates the equip
- Axis 4 (per-peer glow): this is mostly downstream — even after MIL fix, glow needs the new RPC channel (still greenfield)

**This is a deployment problem, not a code problem.** Subscribe PC-B to MoreItemsLibrary, restart VT2 on PC-B, retest. After that the remaining bugs are the ones the audit identified independently (host-side hat slot teardown, GLOW hook timing, quadruple-emit, per-peer glow greenfield, etc.).

---

## Headline: why this has burned 4 days

The user is fighting **two systems' design limits at once**:

1. **Loremaster's Armoury has zero peer-sync.** It is a local visual-mutation mod. Each LA-loaded peer destructively rewrites globals (`WeaponSkins.skins[k].right_hand_unit`, `ItemMasterList[k].unit`, `NetworkLookup.inventory_packages`) based on **its own** dropdown selection. Vanilla equip RPC carries only the skin name; receivers locally rebind. Different LA dropdowns on host vs client → different meshes for the same remote player. Non-LA peers see vanilla. This is not a CT bug — it's the LA architectural premise.
2. **VT2's sync channels carry skin_id only.** No material override, no glow template, no per-player tint travels over the wire. (`rpc_add_equipment(go_id, slot_id, item_id, weapon_skin_id)` is everything.) Anything CT wants peers to see has to ride a new channel CT itself builds.

CT v0.8.58→v0.8.67-dev is CT trying to build that channel on top of LA's destructive mutation model. It's mid-redesign (Family C: server-authoritative `cos_la_apply_req` → host validates → broadcast `cos_la_apply`) with known regressions unaddressed.

---

## Failure axes and ranked root causes

### Axis 1 — LA item picks don't show correctly host ↔ client

| # | Cause | Evidence | Confidence |
|---|---|---|---|
| A1 | **Hot-join replay uses local `_local_la_equips`, not authoritative `_la_equips_by_peer`** | PRIOR_ATTEMPTS_TIMELINE.md outstanding regression | HIGH — design bug in current attempt |
| A2 | **Quadruple-emit per hat equip** (CosmeticUtils + 2× PUAE + AttachmentUtils.hot_join_sync) → receivers respawn attachment 3× per equip → flicker, unstable end state | HOST_CLIENT_AUDIT.md §3 | HIGH |
| A3 | **Vanilla-mesh row-2 offhand picks never broadcast** — emit gated on `opt.la_armoury_key`. "GK Shield Blue" on Bret is invisible to peers. | HOST_CLIENT_AUDIT.md, cosmetics_tweaker.lua:2032 | HIGH |
| A4 | **`_la_equips_by_peer` never cleans on peer disconnect** → stale state through host migration | HOST_CLIENT_AUDIT.md | MEDIUM |
| A5 | **`_local_la_equips` stale on LA→vanilla swap** (line 3284 only writes inside LA branch) | HOST_CLIENT_AUDIT.md | MEDIUM |
| A6 | **Wearer "waits one RTT" path unverified** — in v0.8.67 the wearer themselves may briefly see vanilla before host echoes back | PRIOR_ATTEMPTS_TIMELINE.md | MEDIUM — needs log evidence |
| A7 | **`Managers.player:players_at_peer` returns nil during loading** → broadcast might fire too early | HOST_CLIENT_AUDIT.md | LOW |

### Axis 2 — Custom-mesh LA items crash

| # | Cause | Evidence | Confidence |
|---|---|---|---|
| B1 | **Remote husk crashes `World.spawn_unit` when viewer lacks LA** — LA's master `.package` glob is conditional on LA being loaded; no guard in CT's receiver path | LA_SYNC_MODEL.md §3 | HIGH (if any non-LA peer in lobby) |
| B2 | **kind="unit" custom-mesh LA shields explicitly deferred for husks** — code path says "vanilla mesh stays" — was a conscious skip but is part of "doesn't show up properly" | HOST_CLIENT_AUDIT.md | HIGH |
| B3 | **Late-spawn race with 5-sec pending TTL too tight** — slow-loading peers drop messages | PRIOR_ATTEMPTS_TIMELINE.md | MEDIUM — needs log evidence |
| B4 | LA's `GameSession.create_game_object` fallback hook ("temp fix for clients errors") indicates the hijack is fragile under network sync | LA_SYNC_MODEL.md, LA `utils/funcs.lua:1688-1694` | LOW (background risk) |

### Axis 3 — Custom-colored hats don't show for all players

| # | Cause | Evidence | Confidence |
|---|---|---|---|
| C1 | **LA `apply_new_skin_from_texture` mutates global `WeaponSkins[skin].inventory_icon` / `ItemMasterList[skin].inventory_icon`** — bridge avoids this locally with mark/restore but the husk RECEIVER path calls it directly | HOST_CLIENT_AUDIT.md, LA `_la_bridge.lua:766-772` | HIGH for icon pollution; MEDIUM for visual hat color |
| C2 | **Per-frame re-apply loop in `mod.update(dt)` in LA may fight CT's overrides** | LA_SYNC_MODEL.md §4 | MEDIUM — needs verify |
| C3 | Quadruple-emit (A2) interacts here too: hat attachment respawned 3× → final color depends on last winner | HOST_CLIENT_AUDIT.md | HIGH (composite with A2) |

### Axis 4 — Per-peer glow (each client's glow on their own weapon visible to others)

| # | Cause | Evidence | Confidence |
|---|---|---|---|
| D1 | **Glow is COMPLETELY UNSYNCED.** `apply_material_settings` hook (cosmetics_tweaker.lua:2393-2557) reads `mod:get("glow_*")` on every machine including remote husk paint, so each viewer paints THEIR OWN glow onto every weapon they see | HOST_CLIENT_AUDIT.md | HIGH — confirmed greenfield |
| D2 | No per-peer glow state store exists; no RPC carries glow choices | HOST_CLIENT_AUDIT.md | HIGH |
| D3 | `MaterialSettingsTemplates[name]` is GLOBAL — CT's working pattern is to temporarily mutate the template, delegate to vanilla, then restore. This is unsafe for per-peer broadcast unless serialized. | VT2_NETWORKING_REFERENCE.md | MEDIUM (design constraint) |

---

## Log evidence — host (PC-A)

- **Host-side hat-equip emits failing locally**: `[cos_la_apply hat] create_attachment ... failed: Slot is not empty, remove attachment before creating a new one` repeats across Pureheart_helm_white ×2, Hippogryph_helm_white, Pureheart_helm_red. **Reproducible solo** (log B 19:19:11, before friend joined). This is the **quadruple-emit symptom (A2)**: the 2nd+ emit lands on a non-empty slot, errors, and is swallowed as INFO.
- **Glow hook never installed**: `[GLOW] _G.apply_material_settings nil at hook time` at boot. CT fell back to hooking GearUtils + CosmeticUtils directly. **This is D1 refined** — the per-peer glow path can't even start because its anchor hook missed.
- **Bridge coverage gap**: `[LA paint] skip: no _offhand_selection for backend_id=502C1B4B2D86C217 / =29D8DF12F964B3C6` every paint walk. Two specific ranged backend IDs never registered an offhand for. Log noise + visual gap.
- **Pre-registration confirmed correct**: `pre_register_la_inventory_packages: 31 variant(s) registered (sorted, all kind=unit)` — Family D doctrine working.
- **No crashes, no oversized RPCs, no STRING_MAX** — chunking isn't the bottleneck.

## Log evidence — client (PC-B)

- **Bridge dormant**: `[LA paint] skip: bridge not registered` ×50+. **No CT receiver code ran at all.** This is the new top-priority bug.
- **Both mods loaded successfully** — VMF hooks register; the gate is elsewhere.
- **No crashes, no engine errors related to CT/LA.** Only orthogonal noise (`MeshObject Failed looking up material #ID[5a0213f3]` from LA-shipped unit references to renamed vanilla materials; un-escaped `%` in `general_tweaker_data.lua:165` from a sibling mod).
- **Three client lifecycles captured**: 19:35:42-19:36:42 (`rpc_connection_failed host_left_game`), 19:42:43-, 19:45:34-19:49:53 (`lost_connection_to_host`). Disconnects look network-related, not crash-related.

---

## Proposed fix order

### Phase 0 — UNBLOCK THE CLIENT (must come first)

0. **Find why PC-B's CT bridge sentinel isn't registered.** Options:
   - Diff `_la_bridge.lua` and `cosmetics_tweaker.lua` between PC-A and PC-B (size + hash) to confirm deploy parity
   - Check PC-B's CT version string in the boot log vs PC-A's v0.8.67-dev
   - Read `_la_bridge.lua`'s sentinel-set code path to identify the gate condition, then grep PC-B log for evidence of which branch was taken
   - If versions match but sentinel still misses: instrument the gate with verbose logging in next build

Until Phase 0 passes (PC-B logs `[LA paint] apply: ...` instead of `skip: bridge not registered`), every other fix is invisible.

### Phase 1 — Stabilize current Family C attempt (low risk, mostly cleanup)

1. **A1: hot-join replay** → use `_la_equips_by_peer` not `_local_la_equips`
2. **A2/C3: de-duplicate emit** → pick ONE authoritative emit site (likely CosmeticUtils); remove from the other 3. **CONFIRMED BY LOGS** — slot-not-empty errors are the duplicate emits failing.
3. **A4: peer-disconnect cleanup** for `_la_equips_by_peer`
4. **A5: LA→vanilla swap** must clear `_local_la_equips` (cosmetics_tweaker.lua:3284)
5. **A7: nil-guard** `Managers.player:players_at_peer` and defer broadcast if loading
6. **Local hat teardown fix** — wherever `cos_la_apply hat` calls `AttachmentUtils.create_attachment`, first call destroy/remove. Even with de-duplication in #2, sequential hat changes will hit this same error.
7. **GLOW hook installation** — investigate why `_G.apply_material_settings` is nil at hook time. Likely a `Managers.localizer` / VMF-pre-init timing issue or the symbol moved between VT2 patches. Fix is to either delay the hook (`mod.on_all_mods_loaded` / `mod.on_game_state_changed`) or hook the actual underlying function instead of the local helper.
8. **Coverage**: register `_offhand_selection` for backend_ids `502C1B4B2D86C217` and `29D8DF12F964B3C6`

### Phase 2 — Close coverage gaps

6. **A3: vanilla-mesh row-2 picks** — remove `opt.la_armoury_key` emit gate; add `mesh_kind` flag in payload so receivers know to use vanilla unit
7. **C1: receiver-side mark/restore** around `LA.apply_new_skin_from_texture` to prevent global icon mutation leak
8. **B1: package-load guard** — receiver checks whether the LA custom-mesh unit is loadable before `World.spawn_unit`; if not, fall back to vanilla mesh with log warning
9. **B2: lift kind="unit" husk deferral** — apply custom mesh on husks (with B1's guard)

### Phase 3 — Greenfield per-peer glow

10. New RPC `cos_glow_apply { peer_id, slot, glow_template_name, color_rgb, alpha }`
11. `_glow_by_peer` cache on every machine
12. Rework `apply_material_settings` hook: identify owner peer of unit (via `Managers.player:owner(unit)` or for husks `ScriptUnit.has_extension(unit, "inventory_system")._owner_player_id` pattern), look up `_glow_by_peer[owner]`, mutate template, delegate, restore. Falls back to local `mod:get` for owner's own units.
13. Late-join: include glow in `cos_la_handshake` keyset (which doesn't exist yet — see Phase 4)

### Phase 4 — Untried angle: lobby-join handshake

14. **`cos_la_handshake` on lobby join** — exchange SKIN_LIST keyset so host can pre-classify per-peer renderability and degrade gracefully instead of silently dropping unknown `armoury_keys` at receive time (suggested in PRIOR_ATTEMPTS_TIMELINE.md as untried)

### Phase 5 — Verify

15. Build & deploy via vmblauncher (`vmblauncher all cosmetics_tweaker`)
16. Host + client in-game with both Steam accounts
17. Walk each of the 4 user complaints; for each combination of {LA mesh / vanilla mesh} × {host wearer / client wearer} verify the OTHER side sees the correct visual
18. Host migration test (mid-mission host swap) for offhand paint regression flagged in v0.8.66

---

## Open questions pending log evidence

- Does the host or client log show the v0.8.67 `cos_la_apply_req`/`cos_la_apply` round-trip completing successfully, or are messages dropping?
- Any `attempt to index nil` from a missed code path?
- Any `Resource '#ID[...]' not found` indicating package-load crashes (B1)?
- Is one of the test PCs the host and the other client, and what does each side log say about the same equip event?
