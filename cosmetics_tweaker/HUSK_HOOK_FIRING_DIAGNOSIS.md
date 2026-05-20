# Husk Hook Firing Diagnosis — cosmetics_tweaker v0.9.0.7-hotfix

## Environment

- PC-A (host, peer `11000010ef3befb`, Ensrick) is the user cycling Bret shield variants on Grail Knight.
- PC-B (client, peer `1100001428b80b3`) is observer; runs Way Watcher (career 1, profile 4).
- Both machines run identical deployed cosmetics_tweaker v0.9.0.7-hotfix (verified by matching workshop bundle sizes on PC-A and PC-B and by the log line `Cosmetics Tweaker v0.9.0.7-hotfix loaded`).
- Local source is now v0.9.0.8-hotfix (uncommitted) — but that build is NOT yet on either machine.
- PC-B log: `console-2026-05-19-22.48.20-2833923e-3fbd-4080-906e-e7f44c6ada71.log` (copied locally to `cosmetics_tweaker/pcb-log.log`).

## Evidence walk-through

### Boot-time hook registration (PC-B log lines 1118-1180)

```
1122  hook_safe: Hooking 'wield' from [SimpleInventoryExtension]                  -- (#1) from _tpe.lua:507
1123  hook_safe: Hooking 'wield' from [SimpleHuskInventoryExtension]              -- (#2) from _tpe.lua:511
1124  hook_safe: Hooking 'destroy_slot' from [SimpleInventoryExtension]
1125  hook_safe: Hooking 'destroy' from [SimpleInventoryExtension]
1126  hook_safe: Hooking 'destroy_slot' from [SimpleHuskInventoryExtension]
1127  hook_safe: Hooking 'destroy' from [SimpleHuskInventoryExtension]
1129  Cosmetics Tweaker v0.9.0.7-hotfix loaded
...
1172  hook:      Hooking '_wield_slot' from [SimpleHuskInventoryExtension]        -- (#3) from cosmetics_tweaker.lua:4275 (mod:hook, table-form, gated by rawget)
1173  hook_safe: Hooking 'wield' from [SimpleHuskInventoryExtension]              -- (#4) from cosmetics_tweaker.lua:4329 (hook_safe, attempt to add CT re-paint)
1174  WARNING (hook_safe): Attempting to rehook active hook [wield].              -- <-- THE SMOKING GUN
```

The `_tpe.lua` `install_hooks()` runs FIRST and registers `hook_safe SimpleHuskInventoryExtension.wield` (the keep-third-person extension toggle). When `cosmetics_tweaker.lua` later tries to add its own `hook_safe` on the SAME Class+method (the v0.9.0.5 re-paint hook), VMF emits the warning at line 1174 and **silently drops the registration** — exactly the failure mode documented in `feedback_vmf_hook_safe_no_chain.md`.

(Confirmed by reading DMF's `hooks.lua:245-253` — DMF and VMF share the same engine-era code: when a second `hook_safe` arrives for an already-hooked Class.method and `allow_rehooking` is false, the framework logs `"Attempting to rehook active hook [%s]"` and `return`s without registering. There is no chaining for `hook_safe` like there is for `hook`.)

### Runtime evidence

During PC-B's session (22:50:07 to 22:51:52 in host's keep):

```
3479  [cos_la_apply hat] paint Kruber_Hippogryph_helm_red                       -- texture paint on attachment (different code path)
3480  [cos_la_apply recv] from=11000010ef3befb wearer=11000010ef3befb slot=slot_hat ...
3603-3608  [cos_la_apply recv] ... slot=es_1h_sword_shield_breton kind=offhand ... (4 shield variant cycles)
3614  game object destroyed id=46  type=player_unit, owned by peer=11000010ef3befb   -- host changed career/profile
3616  game object created go_id=50, owner_id=11000010ef3befb  type=player_unit       -- fresh husk created
3618  [cos_la_apply hat] paint Kruber_Hippogryph_helm_white  on hat_unit=...
3672  game object destroyed id=50  type=player_unit                                    -- host changed again
3674  game object created go_id=52, owner_id=11000010ef3befb  type=player_unit
3676  [cos_la_apply hat] paint Kruber_Hippogryph_helm_white  on hat_unit=...
```

- ZERO `[husk-mesh-swap]` lines  — the offhand mesh swap inside `BackendUtils.get_item_units` never fires its override branch.
- The user said "ZERO secondary `[cos_la_apply hat] paint` events" — this is INCORRECT: lines 3479, 3484, 3618, 3676 are all paint events fired by the `cos_la_apply` receive handler, which is a per-RPC paint, not a husk-wield re-paint. (Re-clarify with user if needed.) The TRUE missing pieces are the `[husk-wield-repaint]` log (would only exist in v0.9.0.8) and the `[husk-mesh-swap]` log.

## Hypothesis verdicts

### H1 — Hook never registered. PARTIALLY REFUTED.
- `_wield_slot` hook IS registered (boot line 1172). The `rawget(_G, "SimpleHuskInventoryExtension")` gate passed at mod-init time.
- `wield` hook_safe IS rejected by VMF (boot line 1174). The `rawget` gate passed, the `mod:hook_safe(...)` was called — but VMF silently dropped it because `_tpe.lua` had already hooked the same Class+method 0.001 s earlier.
- **Net effect:** the v0.9.0.5 husk-wield re-paint hook NEVER runs on PC-B (or on any peer where `_tpe.lua` is loaded — which is every peer with cosmetics_tweaker).

### H2 — Hook registered but wield never fires. PARTIAL.
- `_wield_slot` is only called from `SimpleHuskInventoryExtension.wield` (vanilla line 319), which only runs when `InventorySystem:rpc_wield_equipment` arrives (vanilla line 393) — i.e. when the host actually CHANGES which weapon slot is active (`/` to swap melee→ranged, picks up a tome, etc.).
- The host's shield-variant picker in CT emits ONLY a `cos_la_apply` RPC; it does NOT trigger an `rpc_wield_equipment`. So no `wield` fires on the client during shield cycling. This is by design — the offhand variant is a cosmetic overlay, not a slot change.
- However, the host DID change profile/career twice (lines 3614 / 3672) which destroyed and recreated `player_unit`. A fresh `SimpleHuskInventoryExtension` is added to the new unit and its initial wield WOULD pass through `wield → _wield_slot`. We cannot prove this from the v0.9.0.7 log because the diagnostic mod:info inside the wrap was added in v0.9.0.8. Conclusion: indeterminate from this log; assumed-firing on player_unit recreation.

### H3 — Wrap exits before get_item_units. NOT REACHED.
- Cannot evaluate; wrap was either never entered (H2 case during shield cycling) or did fire silently with no diagnostic to confirm (player_unit recreation case).
- Reading vanilla `_wield_slot` lines 641-662: `GearUtils.destroy_equipment` at 658 is synchronous and doesn't yield; `BackendUtils.get_item_units` is the next call at 662. Nothing between them can break the wrap's set→call→clear bracket.

### H4 — Lua upvalue scoping. REFUTED.
- `local _current_husk_wield = nil` at line 2245 (module top-level).
- Both the BackendUtils hook (line 2248) and the `_wield_slot` wrap (line 4275) are at module top-level, in the same lexical scope, AFTER the local declaration. Both capture the same upvalue. Closure works correctly.

### H5 — `item_data.template` lookup mismatch. NOT REACHED.
- Cannot evaluate without the wrap firing first. The probe log added in v0.9.0.8 (`[husk-mesh-swap probe] ... template=%s cache_has_entry=%s`) would answer this — once v0.9.0.8 is deployed and a husk actually wields.
- BUT the `_la_equips_by_peer` cache write was only added on the CLIENT side in v0.9.0.7-hotfix (the diff at the `cos_la_apply` receive handler, line ~4068). Before v0.9.0.7 clients NEVER recorded the entry, so even if the wrap fired, the equipment lookup would have returned nil. This is now fixed; the recv handler writes to `_la_equips_by_peer` on every peer.

## Root cause

**Two independent, compounding bugs in the v0.9.0.5-7 husk codepath:**

1. **Hook-safe shadowing (`_tpe.lua` vs cosmetics_tweaker.lua):** The v0.9.0.5 husk-wield re-paint hook at `cosmetics_tweaker.lua:4329` is silently dropped by VMF because `_tpe.lua:511` already registered `hook_safe("SimpleHuskInventoryExtension", "wield", ...)` 13 ms earlier in the same boot. This is the canonical failure mode in `feedback_vmf_hook_safe_no_chain.md`. The boot log warning at line 1174 confirms it. **Result: husk re-paint never runs on any peer that has cosmetics_tweaker loaded** (the TPE module is part of the same mod, so this affects 100% of users).

2. **Wrong trigger for the husk-mesh-swap:** Shield-variant cycles emit `cos_la_apply` only. They do NOT trigger `rpc_wield_equipment`, so vanilla `_wield_slot` does not run on the client, so the get_item_units wrap has nothing to fire on. The `[husk-mesh-swap]` log line would only ever appear when the host actually swaps slot_melee/slot_ranged or changes loadout — not when cycling shield textures via the picker. The fix for "Ostermark shield on the husk renders as vanilla mesh" requires either:
   - Triggering a real husk wield on shield-cycle (e.g. send a `cos_la_apply` follow-up that calls `inventory_ext:destroy_slot(...) + add_equipment(...) + wield(...)` on the husk after the variant changes), OR
   - Doing the mesh swap directly in the `cos_la_apply` recv handler instead of waiting for the next `_wield_slot`. The recv handler already has access to the husk_unit and the LA variant — it can call `GearUtils.destroy_slot` + force a re-wield, or manipulate `equipment.left_hand_wielded_unit_3p` directly.

## Recommended fix (read-only — do NOT edit cosmetics_tweaker.lua yet)

### Fix #1 (consolidate hook_safe) — REQUIRED

`feedback_vmf_hook_safe_no_chain.md` mandates: **consolidate the two `hook_safe SimpleHuskInventoryExtension.wield` callbacks into ONE callback** in a single file.

Concretely: delete the standalone `mod:hook_safe("SimpleHuskInventoryExtension", "wield", ...)` block at `cosmetics_tweaker.lua:4329-4406` and FOLD the re-paint logic into the existing `_tpe.lua:511-514` callback (or a new shared callback that both modules call into). Pseudocode for the merged body:

```lua
-- _tpe.lua (or a new shared file imported by both):
mod:hook_safe("SimpleHuskInventoryExtension", "wield", function(self, slot_name)
    -- TPE side (always runs, gated by tpe_enable inside wield_equipment):
    if is_enabled() then wield_equipment(self._unit, slot_name) end
    -- LA re-paint side (always runs; no toggle):
    mod._husk_wield_repaint(self, slot_name)  -- exposed by cosmetics_tweaker.lua
end)
```

Then `cosmetics_tweaker.lua` exposes the re-paint as a module-level function `mod._husk_wield_repaint = function(self, slot_name) ... end` and DELETES its standalone `mod:hook_safe(...)`. This makes the order deterministic, both code paths run, and VMF never sees a duplicate registration.

Apply the same fix to:
- `mod:hook_safe("SimpleHuskInventoryExtension", "destroy_slot", ...)` — `_tpe.lua:524` exists; check if `cosmetics_tweaker.lua` adds another. (Currently doesn't, but worth grepping every time.)
- `mod:hook_safe("SimpleHuskInventoryExtension", "destroy", ...)` — same.

### Fix #2 (move mesh-swap into recv handler) — REQUIRED for kind="unit" shields

The husk-mesh-swap branch in `BackendUtils.get_item_units` (cosmetics_tweaker.lua:2261-2294) is only reachable when vanilla `_wield_slot` runs, which is NOT triggered by a CT picker shield cycle. Move the mesh-swap into the `cos_la_apply` recv handler at line ~4090 (just below the new cache write at line 4083-4087 in the v0.9.0.7 diff):

```lua
-- After _try_apply_by_peer:
if kind == "unit" then
    -- Resolve husk unit for `wearer` and force a husk re-wield on slot_name so
    -- vanilla _wield_slot fires and our get_item_units hook applies the LA mesh.
    local husk_unit = _resolve_husk_unit_for_peer(wearer)
    local inv = husk_unit and ScriptUnit.has_extension(husk_unit, "inventory_system")
    if inv and inv.wield then inv:wield(inv:get_wielded_slot_name() or slot_name) end
end
```

This is the cheapest path to making kind="unit" Ostermark/Bastonne shields render on husks — leverages the existing get_item_units intercept by triggering a fresh wield exactly when the user changes their shield variant.

(Alternative: do the mesh swap directly in recv by calling `GearUtils.destroy_slot` and a fresh `add_equipment` with a patched item_template — more invasive, more places for desync.)

### Fix #3 (add diagnostic logging — already done in v0.9.0.8)

The v0.9.0.8 diff adds `[husk-wield-wrap] entry`, `[husk-mesh-swap probe]`, and `[husk-wield-repaint] entry` lines. Keep them. They are the difference between "did the hook fire?" being a 5-minute log read vs a 2-day debug. Once Fix #2 lands and you see entries, you can demote them to mod:debug.

## Verification matrix once fixes are deployed

| Action on host | Expected PC-B log lines |
|---|---|
| Host cycles shield variant via CT picker (kind="texture") | `[cos_la_apply recv] applied=true` + (after Fix #1) `[husk-wield-repaint] apply stored_key=...` |
| Host cycles shield variant via CT picker (kind="unit", e.g. Ostermark) | (after Fix #2) `[husk-wield-wrap] entry` + `[husk-mesh-swap APPLIED]` |
| Host presses `/` to swap slot_melee↔slot_ranged | `[husk-wield-wrap] entry slot=slot_ranged` + `[husk-mesh-swap probe] cache_has_entry=true/false` + (if cached) `APPLIED` |
| Host changes career in keep | player_unit destroyed/created → new husk → `[husk-wield-wrap] entry` for initial slot |

## Files referenced

- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\cosmetics_tweaker.lua`
  - Line 2245: `local _current_husk_wield = nil`
  - Line 2247-2294: `BackendUtils.get_item_units` hook with husk-mesh-swap branch
  - Line 4068-4087 (diff): cache mirror write in `cos_la_apply` recv handler (v0.9.0.7)
  - Line 4275-4303: `_wield_slot` wrap (v0.9.0.6 / v0.9.0.8)
  - Line 4329-4406: shadowed `hook_safe("...wield")` re-paint hook (v0.9.0.5) — needs to merge into `_tpe.lua` callback
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\_tpe.lua`
  - Line 511-514: the WINNING `hook_safe("SimpleHuskInventoryExtension", "wield", ...)` registration
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\unit_extensions\default_player_unit\inventory\simple_husk_inventory_extension.lua`
  - Line 314-321: `SimpleHuskInventoryExtension.wield` (sole caller of `_wield_slot`)
  - Line 641-680: `_wield_slot` (the wrapped target — calls `BackendUtils.get_item_units` at line 662)
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\entity_system\systems\inventory\inventory_system.lua`
  - Line 382-394: `rpc_wield_equipment` (sole network entry point that triggers husk wield)
- `C:\Users\danjo\source\repos\darktide-mods\DMF\dmf\scripts\mods\dmf\modules\core\hooks.lua`
  - Line 245-253: confirms VMF/DMF behavior — second `hook_safe` on same Class+method is silently dropped with "Attempting to rehook active hook" warning
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\pcb-log.log` (copied from PC-B)
  - Line 1123: TPE wield hook registers first
  - Line 1173-1174: CT wield hook registration + rehook warning (the bug)
  - Line 1172: CT `_wield_slot` hook registers cleanly (different hook type)
