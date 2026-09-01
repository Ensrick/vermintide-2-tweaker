# Husk-side `kind="unit"` LA shield swap

Research for lifting the defer at `_la_bridge.lua:1176-1182` so LA custom-mesh shields render on REMOTE husks (peer machines viewing another player), not just on the local wearer's previewer.

Status: research-only. No code changes proposed in this document; recommendation + implementation sketch below.

## Recommended approach

**Approach 1 (intercept in `BackendUtils.get_item_units` with a husk-wield thread-local).**

Synthesis: keep Approach 1 as the primary mechanism, add a minimal portion of Approach 2 ONLY as a fallback path for the rare case where the wearer's `_la_equips_by_peer` entry arrives AFTER vanilla has already wielded (race window on profile sync). Approach 3 (mutating global `WeaponSkins.skins`) is rejected — every husk wielding the same vanilla skin would inherit the mutation regardless of wearer, and the bleed cannot be cleanly bounded because the spawn is async w.r.t. the apply.

### Why Approach 1 wins

| Criterion | Approach 1 (`get_item_units` hook) | Approach 2 (destroy + respawn) | Approach 3 (`WeaponSkins.skins` mutation) |
|---|---|---|---|
| Renders correctly on husk | Yes — engine spawns LA mesh from the start. Uses vanilla path including 3P `_3p` suffix appending in `gear_utils.lua:189`. | Yes — but second spawn doubles `World.spawn_unit` cost per wield. | Yes — but BLEEDS to every other husk wielding the same vanilla skin. |
| Per-peer isolation | Yes — lookup keyed on `wearer_peer`. | Yes. | NO — global mutation. Two husks both wearing `es_1h_sword_shield_breton` get the same LA mesh even if they picked different ones. |
| Engine state cleanliness | Vanilla spawn path runs once with correct unit. No orphans. | Network-coupled unit destroyed mid-frame; `rpc_create_attachment` refs, fade_system entries, scene-graph links all get torn down and re-built. Bug-prone. | None of vanilla's writes are aware of the mutation; subsequent unequip can leak. |
| Hook complexity | One wrap on `_wield_slot` (sets/clears flag), reuses existing `BackendUtils.get_item_units` hook. | New hook AFTER spawn + manual destroy + re-spawn + re-link via `GearUtils.link`. | Mutation + reverse mutation timing — spawn is async, no clean restore point. |
| Compatible with row-2 picker re-paint hook (v0.9.0.5) | Yes — Approach 1 runs first (wield), `kind="texture"` re-paint still runs after. No conflict. | Maybe — re-paint runs on the original spawned unit, then we destroy and re-spawn. Re-paint becomes dead work. | Yes but pointless. |
| Burn cost if wrong | Low — hook scope tightly bracketed by the husk-wield flag. | Medium — risk of half-destroyed units. | High — visible cross-bleed to bystanders, hard to debug after the fact. |
| Aligns with existing patterns | Yes — mirrors the wearer-side override in the same `BackendUtils.get_item_units` hook (line 2241), which already does the equivalent for the local player's row-2 picks (`_offhand_selection[backend_id].unit`). | New pattern. | New pattern, and one we already ruled out for the local-wearer case (CT v0.8.27 burn). |

### Why Approach 2 stays as fallback only

If the wearer joins / hot-swaps and their husk wields BEFORE `cos_la_apply` has reached us, Approach 1 fires too early — `_la_equips_by_peer[peer]` is empty, hook returns vanilla path, engine spawns vanilla mesh. When `cos_la_apply` lands later, the wielded unit is the wrong mesh. We CANNOT silently mutate it (the vanilla shield mesh has no LA texture slots). The fallback is: on late `cos_la_apply` arrival with `kind="unit"`, if the husk is currently wielding the corresponding slot, force a re-wield (vanilla's own `wield(slot_name)` call). The hook fires this time with the equip cached, spawns the LA mesh.

### Why Approach 3 is rejected

Mutating `WeaponSkins.skins[<vanilla_skin>].left_hand_unit` to the LA path is what LA itself does on the local wearer (`_la_bridge.lua:118-152` documents this). On the wearer's machine, the wearer's row-2 selection is the only one that matters, so the global mutation is harmless. On a husk-viewing peer, however, every player using the same vanilla shield illusion (`es_sword_shield_breton_skin_01` for example) becomes affected. There is no per-peer scoping primitive at the `WeaponSkins` level. The async spawn timing also means there is no safe point to restore the original value — by the time `spawn_inventory_unit` runs, the wield path has already read the field, but if we restore before that, the override is lost.

## Code sketch

Three edits, all in `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua`. Memory file references in parens.

### Edit 1: Husk-wield thread-local + hook wrap

Add near the existing v0.9.0.5 wield hook (line 4210):

```lua
-- Thread-local: set by the wrap below before vanilla _wield_slot runs,
-- cleared in the same wrap immediately after. Read by the
-- BackendUtils.get_item_units hook (line 2241) to detect "this call is
-- coming from a husk wield and we should consult _la_equips_by_peer".
-- Lua is single-threaded so a module-local global is safe here.
local _current_husk_wield = nil

if rawget(_G, "SimpleHuskInventoryExtension") then
    -- Full hook (not hook_safe): we need to bracket the inner BackendUtils
    -- call. hook_safe fires AFTER vanilla returns, too late.
    mod:hook(SimpleHuskInventoryExtension, "_wield_slot",
        function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
            -- Resolve wearer peer from the husk unit (same lookup the
            -- v0.9.0.5 re-paint hook uses). Returns nil for AI husks; the
            -- nil guard below makes that a no-op.
            local wearer_peer = nil
            local pm = Managers and Managers.player
            if pm and pm._players then
                for _, p in pairs(pm._players) do
                    if p.player_unit == self._unit then
                        wearer_peer = p.peer_id
                        break
                    end
                end
            end

            -- Stash slot_name too — the BackendUtils hook needs both to
            -- look up _la_equips_by_peer[peer][weapon_template].
            _current_husk_wield = {
                wearer_peer = wearer_peer,
                slot_name   = slot_name,
                self        = self,  -- for slot.item_data.template lookup
            }

            -- Run vanilla wield. The inner BackendUtils.get_item_units
            -- call (simple_husk_inventory_extension.lua:662) will hit our
            -- hook with the flag set.
            local ok, err = pcall(func, self, world, equipment, slot_name, unit_1p, unit_3p)

            _current_husk_wield = nil
            if not ok then error(err) end
        end)
end
```

### Edit 2: BackendUtils.get_item_units husk override

Extend the existing hook (line 2241). Insert before `return result`:

```lua
-- Husk-side kind="unit" LA shield swap. Detect husk-wield context via
-- the thread-local set by the _wield_slot wrap above. Look up the wearer's
-- LA selection in _la_equips_by_peer (populated by the cos_la_apply receiver
-- at line 4042+); if it's a kind="unit" variant, override result.left_hand_unit
-- to the LA mesh path so GearUtils.spawn_inventory_unit (gear_utils.lua:189)
-- spawns the LA mesh + its _3p sibling instead of the vanilla shield.
if _current_husk_wield and _current_husk_wield.wearer_peer then
    local peer = _current_husk_wield.wearer_peer
    local slot_self = _current_husk_wield.self
    local equips = _la_equips_by_peer and _la_equips_by_peer[peer]
    -- The wielded weapon template is the LA-equip key (matches
    -- _send_la_apply's `weapon_key` arg at cosmetics_tweaker.lua:2129).
    local slot = slot_self and slot_self._equipment
        and slot_self._equipment.slots and slot_self._equipment.slots[_current_husk_wield.slot_name]
    local weapon_template = slot and slot.item_data and slot.item_data.template
    local entry = equips and weapon_template and equips[weapon_template]

    if entry and entry.kind == "offhand" and entry.armoury_key then
        local LA = get_mod("Loremasters-Armoury")
        local variant = LA and LA.SKIN_LIST and LA.SKIN_LIST[entry.armoury_key]
        if variant and variant.kind == "unit"
                and type(variant.new_units) == "table"
                and variant.new_units[1] then
            local la_mesh = variant.new_units[1]
            -- Belt-and-suspenders: confirm both 1p and _3p are engine-
            -- resident (reference_ct_offhand_force_preload preloaded
            -- everything at mod init, but verify).
            if _override_package_ready(la_mesh) then
                result.left_hand_unit = la_mesh
                if LA_BRIDGE and LA_BRIDGE.trace then
                    mod:info("[husk swap] %s -> %s for peer %s slot %s",
                        tostring(result.left_hand_unit), la_mesh,
                        tostring(peer), tostring(_current_husk_wield.slot_name))
                end
            else
                mod:info("[husk swap] SKIP %s for peer %s (package not ready)",
                    tostring(la_mesh), tostring(peer))
            end
        end
    end
end
```

### Edit 3: Late-arrival re-wield path

Inside `_apply_la_on_unit` for `kind == "offhand"` (line 3880-3903), when the variant is `kind="unit"` and we're applying to a HUSK (not the local wearer), force a re-wield instead of (or in addition to) the local paint call:

```lua
if kind == "offhand" then
    local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
    if not inv then return false end
    local equipment = inv._equipment

    -- v0.9.x-dev: kind="unit" husk path. The local paint call won't help
    -- because the wielded mesh is the vanilla shield. Force a re-wield so
    -- our _wield_slot wrap (Edit 1) and BackendUtils hook (Edit 2) run with
    -- the now-cached _la_equips_by_peer entry and the LA mesh spawns.
    local LA = get_mod("Loremasters-Armoury")
    local variant = LA and LA.SKIN_LIST and LA.SKIN_LIST[armoury_key]
    local is_husk = inv.__class_name == "SimpleHuskInventoryExtension"
        or rawget(_G, "SimpleHuskInventoryExtension") and getmetatable(inv) == nil
        -- Lua class detection is fuzzy; safer: check the absence of the
        -- local-inventory-only methods. Approximation OK.
    if variant and variant.kind == "unit" and is_husk and inv.wield then
        local wielded = inv.wielded_slot
        if wielded then
            -- Re-wield triggers our hooks; idempotent for kind="texture".
            inv:wield(wielded)
            return true
        end
    end

    -- Existing kind="texture" paint path (unchanged):
    local left_unit = equipment and equipment.left_hand_wielded_unit_3p
    if not left_unit or not Unit.alive(left_unit) then return false end
    local world = _level_world()
    if not world then return false end
    LA_BRIDGE._bridge_active = true
    local ok, err = pcall(LA_BRIDGE.apply_offhand_to_unit, world, left_unit, armoury_key, vanilla_key, "network_husk")
    LA_BRIDGE._bridge_active = false
    if not ok then
        mod:info("[cos_la_apply offhand] %s on %s failed: %s",
            tostring(armoury_key), tostring(left_unit), tostring(err))
    end
    return true
end
```

### Edit 4 (also in `_la_bridge.lua:1176`): lift the defer guard

Change the guard so it bails out only for **non-husk** contexts that aren't `loot_previewer`:

```lua
if variant.kind == "unit" then
    -- "network_husk" no longer falls through — the husk wield path (Edit 1+2
    -- in cosmetics_tweaker.lua) now redirects the spawn to the LA mesh,
    -- so by the time apply_offhand_to_unit fires on a husk, the unit is
    -- already the LA mesh and the texture-paint code below is correct.
    -- BUT: ingame and hero_previewer are still vanilla-mesh paths (the
    -- wearer's own previewer already binds the LA mesh natively), so they
    -- early-return as before.
    if context == "ingame" or context == "hero_previewer" then
        if M.trace then
            mod:info("[LA bridge] kind=unit %s context=%s — skipping (vanilla path renders correctly)",
                tostring(armoury_key), tostring(context))
        end
        return false
    end
    -- For loot_previewer AND network_husk: do the swap + paint
    -- (existing path, unchanged).
    ...
end
```

### Hook order verification

1. `cos_la_apply` arrives on a peer machine (line 4042).
2. Receiver writes to `_la_equips_by_peer[wearer_peer][weapon_template]`. (Wait — the host's `cos_la_apply_req` handler at line 3958 writes to `_la_equips_by_peer`; the broadcast receiver at line 4042 does NOT. The receiver only calls `_try_apply_by_peer`. **Verify and likely fix: the broadcast receiver also needs to write to `_la_equips_by_peer` on every peer, not just the host.** The v0.9.0.5 re-paint hook relies on this cache being present on every peer.)
3. `_apply_la_on_unit` for `kind="offhand"`: if `kind="unit"` and husk, force re-wield (Edit 3). If `kind="texture"` and husk, local paint (existing path).
4. Re-wield calls `SimpleHuskInventoryExtension:wield(slot_name)`. Vanilla `wield` calls `_wield_slot` (Edit 1 wrap sets flag).
5. Inside vanilla `_wield_slot`: `BackendUtils.get_item_units` fires our hook (Edit 2), reads flag, looks up `_la_equips_by_peer`, overrides `result.left_hand_unit`.
6. `GearUtils.spawn_inventory_unit` (gear_utils.lua:189) spawns `la_mesh` and `la_mesh .. "_3p"`. Done.
7. After spawn: existing v0.9.0.5 wield-end hook (line 4211) re-runs LA paint for kind="texture" entries. kind="unit" entries no longer skip — `apply_offhand_to_unit` runs through `_paint_offhand_textures_locally`, hits the (now-modified) kind="unit" branch, runs the swap + paint with `context="network_husk"`.

## Edge cases

### Host migration

After host migration, the new host's `_la_equips_by_peer` is whatever the host had cached locally before promotion. If the migration completes a wield BEFORE the migrating peer broadcasts catch-up `cos_la_apply` messages for all wearers, husks may transiently show vanilla meshes. Mitigations:

- The existing `_la_equips_by_peer` cache persists on every peer (it's populated on broadcast), so promotion doesn't immediately lose state. **Verify: does the broadcast receiver write to `_la_equips_by_peer`?** (See "Hook order verification" item 2 — answer is currently NO; needs to be added.)
- On migration, the new host should re-broadcast `cos_la_apply` for every entry in `_la_equips_by_peer` so any peer who joined mid-flight catches up. Approximate path: hook the host-promotion event, walk `_la_equips_by_peer`, re-send each entry.
- Edit 3's re-wield path handles late arrivals organically.

### Local peer doesn't have the LA `kind="unit"` variant

Pre-condition: every peer with cosmetics_tweaker + LA installed has the same `SKIN_LIST` (LA is the source). The mismatch case is "wearer has LA installed, viewer does not". `_apply_la_on_unit` already bails out at `variant = LA.SKIN_LIST[armoury_key]` returning nil. Edit 2's hook also bails: `LA.SKIN_LIST[entry.armoury_key]` is nil → no override → vanilla mesh spawns. Correct fallback.

If the wearer has a NEWER cosmetics_tweaker that knows about an LA variant the viewer's CT doesn't, the issue isn't the LA mesh (they share LA) — it's that the viewer's `_la_equips_by_peer` may not get populated if the `cos_la_apply_req` validation at host rejects the unknown `armoury_key`. Already handled at line 3953: host rejects unknown `armoury_key` cleanly. Cross-version mixing is robust.

### `_la_equips_by_peer` cache stale across wearer's character swap

When the wearer switches careers / characters in the keep, their LA shield selections from the previous character stay in `_la_equips_by_peer[wearer_peer]` keyed by the OLD weapon templates. New character wields a different weapon template, lookup misses, no override, vanilla mesh — correct behavior. The stale entry doesn't bleed because the v0.9.0.6 fix already requires `stored_key == wielded_template` matching.

If the wearer re-equips the SAME weapon template with a DIFFERENT LA shield, the host's `cos_la_apply_req` handler at line 3959 does an idempotent overwrite (same slot key → entry replaced). Fine.

Stale entries accumulate (one per weapon_template the wearer ever picked an LA shield for). Memory cost is trivial (~64 bytes per entry, max ~50 per peer). Optional cleanup: when CT's settings menu emits `cos_la_apply` for a vanilla-skin re-equip (no LA), broadcast a `cos_la_apply` with `armoury_key = nil` or a sentinel, and have the receiver delete the entry. Not blocking.

### Peer disconnect cleanup

Already handled at line 3979-3981: `_la_equips_by_peer[peer_id] = nil` on disconnect.

### Wearer running CWV `kind="unit"` shield variant

Out of scope for THIS change (CWV manages its own per-character variant unit paths via `entry.cwv_variant` flag at the GearUtils/LootItem hooks). CWV variants do NOT flow through `_la_equips_by_peer` — they're standard inventory items. If a player picks a CWV shield variant on top of which they ALSO pick an LA `kind="unit"` row-2 option, the LA pick wins (Edit 2 overrides `result.left_hand_unit` after CWV's hook already set it). Verify CWV's hook ordering doesn't undo this; if so, gate Edit 2's override to skip when `item_data.cwv_variant == true`.

### Force-load coverage

`_force_load_all_offhand_packages` (cosmetics_tweaker.lua:1862) walks `LA_BRIDGE.la_offhand_options_by_weapon_type`. Verified at line 1878-1888: for every entry, calls `_preload_offhand_package(opt.unit)` AND `_preload_offhand_package(opt.intended_unit)`. For `kind="unit"` LA variants, `intended_unit = variant.new_units[1]` (set in `_resolve_intended_unit` at `_la_bridge.lua:143-148`). So both 1p and _3p halves are engine-resident on every peer at mod init. `_override_package_ready` gate in Edit 2 will pass.

### NetworkLookup.inventory_packages registration

Owned by `_la_registration_owner.lua`. Every `kind="unit"` LA variant's
`new_units[1]` and `new_units[2]` are discovered unconditionally and sorted
off-table. The canonical strict lookup helper validates a complete shadow of
`NetworkLookup.inventory_packages`; only the all-or-nothing registration commit
publishes it. The husk's `ProfileSynchronizer` therefore resolves an LA mesh
path to the same deterministic index on peers with the same manifested catalog,
without exposing the former partially appended lookup on a failed boot attempt.

### `slot.skin` reading on the husk

Vanilla husk's `slot.skin` is set by `add_equipment(slot_name, item_name, skin_name)` at line 215-221. The host sends the vanilla `skin_name` over the wire (NOT our LA armoury_key — armoury_keys aren't in `NetworkLookup.item_names`). So `BackendUtils.get_item_units(item_data, nil, slot.skin, career_name)` runs with the VANILLA skin, returns vanilla mesh paths. Our hook then overrides `result.left_hand_unit` to the LA mesh. Vanilla `skin` field stays vanilla — the `material_settings_name` from the vanilla skin still applies (correct for the LA mesh, which inherits the handgun material). No interference with `is_ammo_weapon`, `pickup_template_name`, etc. — LA `kind="unit"` shields don't touch those fields.

## Verification checklist

Pre-deploy:

- [ ] Grep `_la_equips_by_peer` writers; confirm broadcast receiver (line 4042+) writes to it on every peer, not just the host. (Likely needs adding — see "Hook order verification" step 2.)
- [ ] Confirm `_force_load_all_offhand_packages` runs before any client could equip a kind="unit" LA shield (search `_la_bridge_init_done` ordering).
- [ ] Confirm `_override_package_ready` returns true for `Kruber_Empire_shield01_mesh_Ostermark01` on a cold-start peer that never opened the customization screen. (Should pass — LA's resource_package is global.)
- [ ] Forward-reference audit: `_current_husk_wield`, `_la_equips_by_peer`, `_apply_la_on_unit` all referenced from Edits — verify each is declared above its first reader (`feedback_lua_forward_reference.md` is the load-bearing rule).
- [ ] Confirm Edit 2's `is_husk` detection works without `__class_name` (Lua class system per CLAUDE.md doesn't auto-set this). Safer: query `Managers.player:owner(self._unit)` and check `.remote` flag, or just check `ScriptUnit.has_extension(unit, "inventory_system") == SimpleHuskInventoryExtension`'s instance via metatable.

Post-deploy live verification (host + 1 peer minimum):

- [ ] PC-A wears a vanilla shield → PC-B sees vanilla shield. (Baseline.)
- [ ] PC-A picks LA kind="texture" shield (e.g. Lothar01) → PC-B sees the texture-painted vanilla mesh. (Existing v0.9.0.5 behavior; should not regress.)
- [ ] PC-A picks LA kind="unit" shield (e.g. Reiland = `Kruber_empire_shield_basic1_Ostermark01`) → PC-B sees the LA custom mesh, not the vanilla shield.
- [ ] PC-A wield-cycles slot_melee ↔ slot_ranged repeatedly with the kind="unit" LA equip → PC-B sees the LA mesh persist on every melee wield.
- [ ] PC-A swaps to a different LA kind="unit" variant via the row-2 picker → PC-B updates to the new mesh on the next wield (or immediately via Edit 3's re-wield).
- [ ] PC-B JOINS after PC-A has already equipped → PC-B sees the LA mesh on first wield (`AttachmentUtils.hot_join_sync` path triggers `_send_la_apply` which flows through `_la_equips_by_peer` → `_apply_la_on_unit` → re-wield).
- [ ] PC-A disconnects → PC-B's `_la_equips_by_peer[pc_a_peer]` is cleared (existing line 3979-3981).
- [ ] PC-A swaps from sword+shield_breton to sword+shield (empire) → PC-B sees correct empire shield on the new template, no cross-leak from the breton entry. (Slot-match filter via `weapon_template` lookup.)
- [ ] Grep `[husk swap]` log entries on PC-B during PC-A's equip flow — should fire once per wield with the correct LA path.
- [ ] No crashes from `World.spawn_unit` "Unit not found" on PC-B. (Force-load coverage + `_override_package_ready` gate.)
- [ ] PC-A as Kerillian with `Kerillian_elf_shield_heroClean_Saphery01` → PC-B sees the elf custom mesh. (Cross-character verification — every character's kind="unit" shields go through the same path.)

## References

- Memory: `feedback_cwv_cross_character_unit_packages.md` (force-load doctrine).
- Memory: `reference_la_custom_mesh_pattern.md` (LA's own pipeline; what we're replicating without LA's global mutations).
- Memory: `reference_la_kind_unit_pipeline.md` (per-context recipe; this doc extends it to network_husk).
- Memory: `reference_ct_offhand_force_preload.md` (mass-preload that this change relies on).
- Memory: `feedback_vt2_force_load_only_listed_paths.md` (engine-residency gate via `Application.can_get`).
- Memory: `reference_la_hat_kind_texture.md` (sibling cos_la_apply receiver lesson).
- VT2 source: `simple_husk_inventory_extension.lua:641-700` (`_wield_slot`).
- VT2 source: `gear_utils.lua:155-275` (`spawn_inventory_unit`).
- VT2 source: `backend_utils.lua:144-215` (`get_item_units`).
- Existing CT code: `cosmetics_tweaker.lua:2241-2321` (BackendUtils hook to extend).
- Existing CT code: `cosmetics_tweaker.lua:3774-3935` (`_apply_la_on_unit`, kind="offhand" branch to extend).
- Existing CT code: `cosmetics_tweaker.lua:4210-4276` (v0.9.0.5/0.9.0.6 wield-end re-paint hook, unchanged after this fix).
- Existing CT code: `_la_bridge.lua:1142-1213` (`_paint_offhand_textures_locally`, defer guard at 1176 to lift).
