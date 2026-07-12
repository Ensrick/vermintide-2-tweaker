> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-05-21 (51 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-05-21/`.
# Attachment Storage Audit — post-v0.9.8.6

Comprehensive verification of cosmetics_tweaker's interaction with the
VT2 attachment system, prompted by the v0.9.8.x crash chain
(Lyndsey 02:26:04 GUID `a31bc963`).

Four parallel subagent audits informed this doc. Verdicts at the bottom.

## 1. The bug we just fixed

### v0.9.8.4 introduced a wrong-storage-key bug

```lua
-- WRONG (v0.9.8.4):
local has_slot = self._attachments and self._attachments[slot_name]
```

The expression `self._attachments[slot_name]` is **always nil**, because
vanilla stores per-slot data at `self._attachments.slots[slot_name]`,
not directly on `_attachments`. The outer `_attachments` table holds
*metadata*; the `.slots` sub-table holds the *per-slot data records*.

### Consequence

The v0.9.8.4 guard always bailed without delegating to vanilla
`remove_attachment`. Two failure modes followed:

1. **"No helmet at all"**: when the user changed hats, vanilla sent
   `rpc_remove_attachment` → our hook bailed → slot kept stale data.
   Later RPCs left the visual state inconsistent.

2. **"Slot is not empty" crash** (Lyndsey GUID `a31bc963`):
   vanilla `create_attachment` (line 55 of `player_husk_attachment_extension.lua`)
   calls `self:remove_attachment(slot_name)` BEFORE creating a new
   attachment. Our broken guard bailed instead of delegating → slot
   stayed populated → vanilla then called
   `AttachmentUtils.create_attachment` (line 65) → assertion at
   `attachment_utils.lua:6`
   (`attachments.slots[slot_name] == nil`) → crash.

### v0.9.8.6 fix

```lua
-- CORRECT (v0.9.8.6):
local slots = self._attachments and self._attachments.slots
if not slots or not slots[slot_name] then
    return  -- truly empty slot; silent no-op
end
return func(self, slot_name)
```

Two-character semantic change (`[name]` → `.slots[name]`) plus a
defensive three-level nil chain.

## 2. Vanilla storage shape contract

### `PlayerHuskAttachmentExtension`

File: `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/attachment/player_husk_attachment_extension.lua`

Init (lines 14-16):
```lua
self._attachments = {
    slots = {},
}
```

All slot reads/writes:

| Line | Operation | Code |
| --- | --- | --- |
| 52 | read | `old_slot_data = attachments.slots[slot_name]` |
| 75 | write | `attachments.slots[slot_name] = slot_data` |
| 95 | read | `slot_data = self._attachments.slots[slot_name]` |
| 103 | clear | `self._attachments.slots[slot_name] = nil` |
| 30 | iter | `slots = self._attachments.slots` |
| 119 | iter | `slots = self._attachments.slots` |
| 112 | iter | `slots = attachments.slots` (in `get_slot_data`) |

**Every single access goes through `.slots`.** There are zero direct
indexes on `_attachments[name]` for slot data anywhere in vanilla.

### `PlayerUnitAttachmentExtension` (local player)

File: `player_unit_attachment_extension.lua`

Identical shape:
```lua
self._attachments = {
    slots = {},
}
```

8 read/write sites — all use `.slots`. Sibling class to husk; not a
parent/child relationship (so the CLAUDE.md "hook the derived class"
caveat doesn't apply between these two).

### `AttachmentUtils` shared library

File: `Vermintide-2-Source-Code/scripts/helpers/attachment_utils.lua`

Line 5-6 (the assertion the v0.9.8.4 bug tripped):
```lua
AttachmentUtils.create_attachment = function (world, owner_unit, attachments, slot_name, item_data, show)
    assert(attachments.slots[slot_name] == nil, "Slot is not empty, remove attachment before creating a new one.")
```

The `attachments` parameter must be the OUTER table. The function
checks `.slots[slot_name]`. Callers always pass `self._attachments`.

### `attachment_system.lua`

RPC dispatch — receives `rpc_create_attachment` / `rpc_remove_attachment`
/ `rpc_add_attachment_buffs`, resolves `slot_name` via lookup, calls the
extension's matching method. No direct slot-storage access; pure
forwarding layer.

## 3. Audit of every `_attachments` access in cosmetics_tweaker

Five total sites, all verified correct:

| File:Line | Pattern | Status |
| --- | --- | --- |
| cosmetics_tweaker.lua:495 | `if ext and ext._attachments then` + dump iteration | SAFE — diagnostic, no slot indexing |
| cosmetics_tweaker.lua:4536 | `ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]` | CORRECT |
| cosmetics_tweaker.lua:4562 | `ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]` | CORRECT |
| cosmetics_tweaker.lua:5271 | `self._attachments and self._attachments.slots and self._attachments.slots[slot_name]` | CORRECT (inside create hook, post-vanilla read) |
| cosmetics_tweaker.lua:5308 | `local slots = self._attachments and self._attachments.slots; if not slots or not slots[slot_name] then` | CORRECT (v0.9.8.6 fix) |
| cosmetics_tweaker.lua:5318 | `local slots = self._attachments and self._attachments.slots` (iterate) | CORRECT |
| `_la_bridge.lua:1383` | `if ext and ext._attachments then` + pairs iteration | SAFE — recursion probe, iterates metadata |

**No instances of the wrong-key pattern `_attachments[slot_name]` exist
anywhere in the active codebase.** Cross-mod scan of all 16 tweaker
mods came back clean too.

## 4. Hook contract audit

43 hooks reviewed across cosmetics_tweaker.lua + embedded sub-files.
**Zero contractual mismatches.** Highlights:

### Storage-shape correctness (the v0.9.8.4 bug class)

Every hook that reads `self._attachments`, `self._equipment`,
`self.wielded_slot`, or any similar extension field has been verified
against vanilla source for the correct sub-table key. No other
mismatches found.

### Function signatures

All wrappers pass the right argument count and order to `func(...)`.
Return values flow through untouched where vanilla callers expect
them.

### Class hierarchy traps (CLAUDE.md rule)

Per the doctrine "HOOK THE DERIVED CLASS, NEVER THE BASE":
* `HeroPreviewer` (base) + `MenuWorldPreviewer` (derived): **both
  hooked separately**, as Stingray `class()` copies methods at
  load-time. ✓
* `PlayerUnitAttachmentExtension` vs `PlayerHuskAttachmentExtension`:
  siblings (not parent/child). Both hooked separately. ✓
* `SimpleInventoryExtension` vs `SimpleHuskInventoryExtension`:
  siblings. Both hooked separately. ✓

### Cache ordering

Persistent caches (`_la_equips_by_peer`, `_local_la_equips`,
`_offhand_selection`, `_per_item_glow_runtime`, `_unit_to_backend_id`)
populate before they're read in every code path examined.

### pcall coverage

`pm:local_player()` calls in mod.update / on_game_state_changed paths
are pcall-wrapped (v0.9.5.1). User-invoked paths (chat commands, slider
drags) are not wrapped because network is up by definition when those
fire.

## 5. The v0.9.8.x crash chain — chronological

| Version | Change | Result |
| --- | --- | --- |
| v0.9.8.2 | (earlier baseline) | Sienna bot received Kerillian LA hat → `Unit.node(j_spine1)` fails on incompatible skeleton → crash. Audit ID: **d82119d4**. |
| v0.9.8.3 | Added skeleton-not-ready precheck (`Unit.has_node(husk, "j_spine1")` → bail) | Papered over the symptom. The actual problem was cross-character mesh, not a timing race. |
| v0.9.8.4 | Added companion `remove_attachment` guard. **Bug**: checked `_attachments[slot_name]` (wrong key). | Guard always bailed → vanilla remove never ran → next create assert-crashed. Also caused "no hat at all" visual state. Audit ID: **a31bc963**. |
| v0.9.8.5 | Added character-mismatch gate on create hook (compare path-encoded character keys before patching) | The real fix for the cross-character crash. |
| v0.9.8.6 | Fixed v0.9.8.4's wrong storage key (`.slots[name]`) | Resolved the secondary crash + missing-hat symptom. |

## 6. Triple defense in place

Three independent layers now sit between user state and vanilla:

1. **v0.9.8.5 character gate** — refuses to patch when the cached LA
   hat's character doesn't match the current spawn target. Prevents
   the cross-character mesh crash at the source.

2. **v0.9.8.3 skeleton precheck** — last-resort `Unit.has_node(husk,
   "j_spine1")` check. Catches any race condition where the husk's
   skeleton truly isn't ready (e.g. mid-revive hot-join). Returns
   silently; vanilla retries on next RPC.

3. **v0.9.8.6 remove guard** — silent no-op when slot is genuinely
   empty (e.g. after a v0.9.8.3 silent bail). Calls vanilla
   `remove_attachment` normally when slot has data. Symmetric to the
   create-side defense.

Each layer is correct on its own; all three together cover the matrix
of (cross-character × skeleton-race × remove-after-bail) cases.

## 7. Latent risks identified by the audit

Four lower-severity findings the fourth subagent flagged. None are
crash-class today but worth knowing about:

### LOW: offhand override with CWV cross-character variants

`BackendUtils.get_item_units` hook (cosmetics_tweaker.lua:2711) reads
`_offhand_selection[backend_id]` and patches `result.left_hand_unit`.
The v0.9.8.1 mirror-write filter already gates writes to same-item_type
slots — a strong defense. But a CWV cross-character variant
(e.g. Bret sword+shield given to Kerillian via character_weapon_variants)
shares an item_type with the original. Mirror could propagate the
selection across characters in that narrow case.

The crash mechanism would mirror the v0.9.5 bow case: vanilla's
attachment_node_linking expects bones on the substituted left_hand_unit
that match the parent weapon template. If the unit comes from a
different career's mesh, attachment can crash.

**Risk**: only triggers with a specific CWV variant + cross-character
combination + offhand picker selection. No reproduction yet observed.

**If it surfaces**: add a parallel character-mismatch gate in the
offhand override path, extracting the career prefix from
`units/weapons/player/wpn_<prefix>_*` for both the cached and the
incoming hand units.

### LOW: stale `_glow_by_peer` cleanup on peer leave

When a peer disconnects, line 4710's hook purges
`_la_equips_by_peer[peer_id]` but not `_glow_by_peer[peer_id]`. If a
new peer is assigned the same peer_id (Steam recycling), they'd read
the previous peer's glow settings. **Cosmetic only, no crash.**

### LOW: template mutation window in `apply_material_settings`

cosmetics_tweaker.lua:3218-3279 mutates a shared template in place,
restores after the vanilla call. Lua's single-threaded execution
mitigates concurrent mutation, but Stingray's flow-graph integration
is multi-threaded. **No reproduction; architectural note only.**

### LOW: `_unit_to_backend_id` weak table population gaps

Populated by `GearUtils.create_equipment` + `MenuWorldPreviewer.equip_item`
hooks. If another mod spawns weapon units via `World.spawn_unit`
directly, those units never enter the table — per-item glow override
no-ops silently. **Annoying, never crashes.**

## 8. Verdicts

* **v0.9.8.6 fix is correct.** Verified line-by-line against vanilla
  source. The three-level guard handles all edge cases (extension
  teardown, empty slots table, missing slot, populated slot).

* **No other site has the wrong-key bug.** Full repo grep across 16
  mods, every `_attachments` reference accounted for, every other
  site uses the correct `.slots[name]` shape.

* **43 hooks reviewed for contractual correctness.** Zero violations
  of vanilla method signatures, return shapes, or class-hierarchy
  rules.

* **Four latent risks documented**, all low-severity, none requiring
  immediate code changes. Tracked here for future iterations.

* **Triple defense in place** (character gate + skeleton precheck +
  remove guard) covers the matrix of failure modes that produced the
  d82119d4 and a31bc963 crashes.

## 9. Lessons captured

* **Read vanilla storage shape before writing a guard.** v0.9.8.4
  burned because I checked `_attachments[name]` from memory instead
  of reading the vanilla source. Two minutes of source-reading would
  have prevented the regression.

* **A guard that always bails IS a bug, not a defense.** v0.9.8.4
  appeared "defensive" but actually broke every code path it touched.
  Always log or assert in tests that the guard's positive case fires.

* **Cross-character cosmetic patching is a recurring failure mode.**
  v0.9.5 (offhand bow/shield), v0.9.8.5 (hat) both share this class:
  cached state mutated against a context the cache wasn't authored
  for. Same gate pattern (extract character key from path, compare)
  works for both.

* **Symmetric guards matter.** Hooks on create_attachment need
  matching guards on remove_attachment when the create can silently
  fail (v0.9.8.3 + v0.9.8.4 pair).

---

*Audit performed 2026-05-22 via four parallel subagents.*
*Author: cosmetics_tweaker maintainer. Update on any future change to attachment hooks.*
