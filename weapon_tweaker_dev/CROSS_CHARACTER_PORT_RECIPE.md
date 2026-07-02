# Cross-Character Weapon Port — Recipe

A reusable playbook for shipping "**weapon X playable by character Y, rendered
on Y's body as Y's own 3P model and animations**." This is the
`_patch_brace_template_for_kruber()` / `_patch_longbow_empire_template_for_saltzpyre()`
pattern, distilled.

This recipe is the `weapon_tweaker` sibling of
`character_weapon_variants/RECIPES.md` and reuses CWV's "closed vocabulary"
animation discipline. Where CWV ships **new inventory items** that graft
cross-character meshes, weapon_tweaker keeps the same `ItemMasterList` entry
and only overrides the **3P render side** (mesh + animations) per career.

Worked examples in code:
- Kruber wields Saltzpyre's Brace of Pistols, sees a Repeating Handgun in 3P.
  Patcher: `weapon_tweaker.lua:1664`.
- Saltzpyre wields Kruber's Empire Longbow, sees a Crossbow in 3P.
  Patcher: `weapon_tweaker.lua:1721`.
- Saltzpyre / Kruber wield Kerillian's Elven Spear, see Billhook / Polearm
  stance in 3P. Patcher: `weapon_tweaker.lua:1793` (wield-stance only — no
  per-action remap, no 3P unit swap; included as the simplest case).

---

## 1. Scope

A cross-character port is a **3P-only override**. The first-person view
(`first_person_base` unit) is the same skeleton on every character, so 1P
state machines, 1P wield events, and 1P clips all play correctly on any
character by default. **Never override `anim_event`, `wield_anim`,
`state_machine`, or any other 1P field per character** — only `anim_event_3p`,
`wield_anim_3p`, `wield_anim_career_3p`, and the 3P display unit. See
`feedback_1p_animations_universal.md`.

That gives this scope:

| Subsystem | Touched? | Notes |
|---|---|---|
| `can_wield` | yes — one VMF checkbox + `weapon_unlock_map` entry per (career, weapon) | `weapon_tweaker.lua:29` `weapon_unlock_map`; `apply_weapon_unlocks` strips/adds at `:80` |
| Weapon template `actions[*].anim_event` (1P) | **no** | universal |
| Weapon template `actions[*].anim_event_3p` (3P) | yes — only for events the target SM doesn't author | closed vocabulary |
| Template `wield_anim` (1P) | **no** | universal |
| Template `wield_anim_career_3p[career]` | yes — points at target's `to_<stance>` event | added by template patcher |
| 3P display unit (weapon mesh on the body) | yes — for full visual port | force-load + spawn-hook swap + preview-hook swap |
| 1P display unit (first-person hands view) | **no** | stays vanilla equip-side weapon |
| Damage / ammo / fire rate / stats | **no** | this recipe is cosmetic + animation only |

If you also want stat changes, layer them on top via the normal
`_BASE_OVERRIDES` patches (or `authentic_brace_of_pistols`-style toggles); this
recipe doesn't cover them.

---

## 2. The 7-step procedure

Adding a new port is seven discrete edits across three files plus optional
force-load + unit-swap plumbing for the full visual port.

### (a) Add a `weapon_unlock_map` entry

`weapon_tweaker.lua:29-55`. Append the equip-side weapon key to the target
career's array.

```lua
wh_captain = { ..., "es_longbow" },
wh_bountyhunter = { ..., "es_longbow" },
wh_zealot = { ..., "es_longbow" },
-- wh_priest deliberately omitted — no cross-character bow/crossbow/longbow
-- ports for Warrior Priest (user rule, see feedback_vt2_no_bows_on_warrior_priest).
```

`apply_weapon_unlocks` (`:80`) reads this map plus VMF settings and
strips/adds the career on `ItemMasterList[weapon_key].can_wield`. Never hook
`BackendUtils.can_wield_item` — it's not hookable from Workshop mods

Priest's row in `weapon_unlock_map` should contain **melee weapons only**.
The mod's audit closed this invariant in v0.12.48-dev (
`weapon_tweaker.lua` v0.12.46–v0.12.48-dev) — any future port that adds
a bow / crossbow / longbow / volley-crossbow entry to
`weapon_unlock_map.wh_priest` is a rule violation. See the step (d)
callout below.
(`CLAUDE.md` "Don't hook BackendUtils.can_wield_item").

### (b) Add an `unlock_<career>_<weaponkey>` widget

`weapon_tweaker_data.lua` — find the matching `ranged_<career>` /
`melee_<career>` group and append a checkbox:

```lua
{ setting_id = "unlock_wh_captain_es_longbow", type = "checkbox", default_value = false },
```

Defaults are conservative: `false` for most cross-character ports, `true`
only for "this is the canonical port we ship enabled" cases (e.g.
`unlock_es_huntsman_es_longbow = true` at `weapon_tweaker_data.lua:557` —
Huntsman's vanilla weapon).

### (c) Add a localization entry

`weapon_tweaker_localization.lua` — match the widget's `setting_id` with
a "**Source Character: Weapon Name**"-format display string. Pattern in
the file: the name is what *appears in the checkbox*, framed from the
viewpoint of the equipping career.

```lua
unlock_wh_captain_es_longbow = { en = "Kruber: Longbow" },
unlock_es_mercenary_wh_brace_of_pistols = { en = "Saltzpyre: Brace of Pistols" },
```

Every career row has an entry. Examples at `_localization.lua:78`, `:381`.

### (d) Define `_<PORT>_WIELD_3P` (the wield-stance map)

In `weapon_tweaker.lua`, near the existing two patchers (`:1653`, `:1708`).
Maps target career → that career's native `to_<stance>` event (the
3P wield transition Step (e) will install).

```lua
local _SP_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
    -- wh_priest deliberately omitted (see step (a)).
}
```

Rule: only list careers actually unlocked in step (a). Entries for careers
that never wield this weapon are dead code (`weapon_tweaker.lua:1782-1791`
calls this out).

> **NEVER add `wh_priest` to a bow / crossbow / longbow / volley-crossbow
> port table.** Warrior Priest's 3P body skeleton authors no ranged
> wield events — only the six universal wields plus `to_2h_hammer`
> (verify against `reference_3p_skeleton_events.md`). Including him
> produces a silent missing-event no-op at best (the body holds his
> prior-weapon idle stance, per `feedback_vt2_no_tpose_default_stance.md`
> — not a T-pose) and an engine-fatal wield at worst. If the port
> targets a ranged 3P mesh, omit `wh_priest` from EVERY surface:
> `weapon_unlock_map` (step (a)), `_data.lua` checkboxes (step (b)),
> `_localization.lua` labels (step (c)), `_<PORT>_WIELD_3P`
> (step (d)), and the template patcher's career loop (step (f)).
> Rule established 2026-05-19; see `feedback_vt2_no_bows_on_warrior_priest.md`.
> Cross-character MELEE ports MAY still include him, gated on his
> actual melee vocabulary (`to_1h_hammer`, `to_2h_hammer`,
> `to_1h_hammer_shield`).

### (e) Define `_<PORT>_ANIM_REMAP_3P` (the per-action remap)

`source_event → target_3P_event`. Source events come from the equip-side
template's `actions[*][*].anim_event` (only 3P-relevant ones; firing,
draws, special attacks). Target events MUST exist in the target character's
3P SM vocabulary — see `feedback_anim_closed_vocabulary.md`. The CLOSED
VOCABULARY rule means: never invent. If the target SM doesn't author the
event, find a different name that IS authored and shaped right, or fall
through unchanged.

```lua
local _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",
}
```

The justification comments (`weapon_tweaker.lua:1700-1718`) document each
remap. Always add a justification comment per entry — "shoot_fast → shoot
because crossbow has no rapid-fire variant" is the kind of context the next
agent will need.

**Deriving the remap mechanically.** Do this BEFORE writing the patcher
— don't guess from weapon-name semantics:

1. **Resolve source weapon** — `ItemMasterList[<source_key>].template` →
   the `Weapons.<template>` global. The template name is ground truth,
   not the IML key. Names lie (cf. CWV RECIPES "Universal preflight").
2. **Enumerate source `anim_event` vocabulary.** Walk
   `Weapons.<source_template>.actions[X][Y]` and collect every
   `anim_event`, `anim_event_last_ammo`, `anim_end_event`, and the
   top-level `wield_anim`. In-game shortcut: `/dump_actions <pattern>`
   (registered in `weapon_tweaker.lua:297`) lists `anim_event` (1P) and
   `anim_event_3p` (3P override) per sub-action, sorted alphabetically.
3. **Enumerate target template's authored `anim_event_3p` set** the
   same way — these are the 3P events the target wield-stance SM is
   known to author. Augment with target-character 3P body skeleton
   events from the precomputed `reference_3p_skeleton_events.md` probe
   or an in-game `/sm_probe`. **A skeleton entry being TRUE is
   necessary but not sufficient** — visible playback still depends on
   the SM template authoring the event; always verify in-game.
4. **For each source event NOT in the target's `anim_event_3p` set**,
   pick the closest semantic match. Common substitutions:
   `*_fast` → non-fast variant (rapid-fire → single shot),
   `draw_<weapon>` → `to_zoom` / `to_aim`, suffix-charged variants →
   unsuffixed.
5. **Confirm the wield event** (Step (d)'s `to_<stance>`) is in the
   target character's 3P body vocabulary, not just the target template's.
   Cross-character ports fire the wield event on the target character's
   skeleton; if that skeleton doesn't author `to_crossbow`, the body
   silently no-ops the event and keeps whatever idle stance was active
   before the wield, regardless of what the template says
   (`feedback_vt2_no_tpose_default_stance.md`).
6. **Annotate each entry with WHY.** See the comment block at
   `weapon_tweaker.lua:1700-1718` for the canonical justification shape.

### (f) Write `_patch_<weapon>_template_for_<character>()`

The patcher mutates the equip-side weapon's template in two passes:

1. Set `wield_anim_career_3p[career]` for each entry in the wield map.
2. Walk every `actions[*][*].anim_event` and, if it's a key in the remap,
   set the sibling `anim_event_3p` field.

Canonical body (`weapon_tweaker.lua:1664-1690`):

```lua
local function _patch_brace_template_for_kruber()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then return end
    local tpl = Weapons.brace_of_pistols_template_1

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_BRACE_REPEATER_BASE_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
    end

    if tpl.actions then
        for _, action_group in pairs(tpl.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table"
                            and sub_action.anim_event
                            and _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event] then
                        sub_action.anim_event_3p = _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event]
                    end
                end
            end
        end
    end
end

_patch_brace_template_for_kruber()
```

Call the patcher unconditionally at module load. It's idempotent (lookups
are key-based; second-run rewrites are no-ops). If the player toggles the
VMF setting at runtime, the patch already applied — no on-setting-changed
re-patch is needed because the template field exists for all careers but
only fires when the equip-side weapon is actually wielded by that career.

### (g) (Full visual port only) 3P-unit swap

Steps (a)-(f) get you a working port where the equip-side mesh stays on
the body (e.g. Saltzpyre holds the longbow mesh in 3P but plays crossbow
fire animations). To replace the 3P mesh entirely with the target character's
weapon, add three pieces:

1. **Force-load the target 3P unit** at module load.
   Pattern: `_force_load_brace_repeater_3p_unit` (`weapon_tweaker.lua:1476`),
   `_force_load_sp_crossbow_3p_units` (`:1509`). Vanilla packages for the
   equip-side weapon don't include the target's unit, so without this the
   in-mission swap throws the C++ "Unit not found" assertion (crash GUID
   d9e1d3d3). Loads asynchronously at mod init — by the time any equip
   path runs, the unit is ready. Pattern documented in
   `feedback_cwv_cross_character_unit_packages.md`.

2. **Hook `GearUtils.spawn_inventory_unit`** to swap the 3P unit at
   mission-spawn. Canonical for right-hand: brace→repeater swap
   (`weapon_tweaker.lua:2161-2330`). Canonical for left-hand (with ammo):
   longbow→crossbow swap (`:2333-2510`). Five things to get right:
   - **Career detection via `_unit_career_name(owner_unit_3p)`**
     (`weapon_tweaker.lua:858`). At mission-spawn timing,
     `Managers.player:owner(unit)` returns nil — use the inventory_system /
     career_system extensions first. See
     `feedback_vt2_mission_spawn_career_lookup.md`.
   - **Spawn the new unit FIRST, then `mark_for_deletion` the vanilla**
     (`:2283-2291`). Reverse order leaves a one-frame gap with no unit.
   - **Use the TARGET template's `attachment_node_linking`, not the
     source template's** (`:2471-2480`). The longbow's `bow_root` node
     doesn't exist on the crossbow mesh; linking against the source
     template raises a non-pcall-safe engine fatal
     (`feedback_vt2_unit_node_not_pcall_safe.md`, crashify `f210b3b7`).
   - **Mirror vanilla `_wield_slot` visibility**: hide the new 3P unit
     when `owner_unit_1p` is non-nil (local player has 1P view), keep it
     visible for husks (`:2311-2313`). Unconditional `set_unit_visibility
     (new_unit, false)` was a v0.12.37 bug that made the swapped unit
     invisible on other players' views of the local Kruber.
   - **`pcall` the whole body and fall through to vanilla on failure**
     (`:2260, :2321`). Package not loaded, missing template field, any
     error — return the original tuple and let the equip-side mesh render.

3. **Hook `MenuWorldPreviewer.equip_item`** to swap the 3P unit in the
   keep inventory preview. The keep inventory does NOT go through
   `GearUtils.spawn_inventory_unit` — it calls `World.spawn_unit` directly
   from precomputed `spawn_data` built in `equip_item`. Pattern at
   `weapon_tweaker.lua:2597-2695` (consolidated brace + longbow + scale
   hooks; see "hook_safe doesn't chain" caveat below).
   - Hook **MenuWorldPreviewer**, never HeroPreviewer
     (`feedback_inventory_preview_hook_menuworldpreviewer.md`,
     `feedback_vt2_class_hook_derived.md`). VT2's `class()` helper copies
     parent methods into the child at class-definition time, so hooks on
     the base never fire on the derived instance.
   - Mutate `self._item_info_by_slot[slot_type].spawn_data` entries
     in-place: rewrite `entry.unit_name` to the target 3P unit; for
     dual-mesh swaps (e.g. brace's left pistol clipping a repeater body)
     **drop** the unwanted entry (`:2617-2628`).
   - For node-attachment-sensitive swaps (longbow → crossbow), ALSO
     overwrite `entry.unit_attachment_node_linking` with the target
     template's table (`:2673-2687`). Same `a_unwielded_bow` engine-fatal
     risk as in-mission.
   - **One `hook_safe` per (Class, method)**. Two `mod:hook_safe(Class,
     method, ...)` calls silently shadow each other; only the last fires.
     Consolidate into a single callback that dispatches to helpers
     (`feedback_vmf_hook_safe_no_chain.md`, `weapon_tweaker.lua:2592-2596`).
   - **Forward-declare any local helpers** the consolidated callback
     calls; without it the closure resolves them as nil globals
     (`feedback_lua_forward_reference.md`, see `:2562-2563`).

If you only need wield-stance per-career (e.g. spear-on-non-elves at
`:1793`), step (g) is unnecessary — only (a)-(d) and (f). Skip (e) when
every source action's `anim_event` already exists in the target SM
vocabulary unchanged.

### Reusing an existing helper for sibling ports

**When two ports target the same 3P weapon mesh** (different equip-side
source → same display unit), step (g) collapses to a one-line dispatcher
edit. The in-mission and preview swap helpers can be written
source-template-agnostic: they reference the target template directly and
never read fields off the equip-side template. Adding a second source
weapon to an existing port becomes:

1. Widen the in-mission hook's `item_data.name` predicate
   (the dispatcher line that decides which helper to call) to match the
   new source key.
2. Widen the preview hook's `item_name` predicate the same way.
3. **No new force-load** — both ports share the same target unit, already
   loaded.
4. **No new helper function** — same body handles both.
5. Steps (a)-(f) for the new source are unchanged; only step (g) compresses.

Canonical example: Port C (`we_longbow` → Crossbow 3P, v0.12.44-dev)
shipped by widening the longbow dispatcher predicate at `:2172` to
`item_data.name == "es_longbow" or item_data.name == "we_longbow"` and
reusing `_wt_longbow_3p_swap_apply` (`:2359-2510`) +
`_wt_longbow_preview_swap_apply` (`:2652-2695`) unchanged. The
`a_unwielded_bow` substitution + bolt-attachment re-link were already in
place from Port B's implementation.

**Sibling-port checklist** (when contemplating reuse):

- [ ] **Same target 3P unit?** (Same `units/.../*_3p` mesh path?)
- [ ] **Same target template?** (Same `Weapons.<target>` source for
  attachment-node tables?)
- [ ] **Same hand?** (Both right, or both left? If one is left and one
  is right, a single helper isn't enough — different hand-attachment
  tables, different `mark_for_deletion` targets in the vanilla tuple.)
- [ ] **Same ancillary mesh swaps?** (Both have an ammo unit to swap, or
  neither?)
- [ ] **Same special-case caveats?** (E.g. both source meshes hit the
  same `a_unwielded_bow` node fatal, so the existing substitution
  already covers the new source.)
- [ ] **Source's `*_hand_attachment_node_linking` is mesh-agnostic?**
  Look up the source template's `[hand]_hand_attachment_node_linking
  .third_person.wielded` table and check whether the node names it
  references are **trivial** (e.g. brace-of-pistols' `j_rightweaponattach
  → 0`) or **mesh-specific** (e.g. repeater pistol's `lock_hammer`,
  `rotator`, `trigger_t1` — nodes that only exist on the source weapon's
  mesh). If mesh-specific, the existing helper's `GearUtils.link`
  against the new target mesh will raise `Unit.node` (non-pcall-safe —
  see `feedback_vt2_unit_node_not_pcall_safe.md`). The brace hook got
  away with reusing source linking because the brace table is trivial;
  Port B (repeater pistol) could NOT, which forced fork into
  `_wt_repeating_pistol_3p_swap_apply` (`weapon_tweaker.lua:2629`).

If any cell is "no," fork a new helper that substitutes the **target
template's** linking table. If all six are "yes," widen the dispatcher
predicate and you're done with step (g).

---

## 3. Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| **New weapon wielded but body stays in previous weapon's idle stance** (missing-event no-op, not a T-pose — `feedback_vt2_no_tpose_default_stance.md`) | Target career's body has no `to_<stance>` event for the source weapon's `wield_anim`. The 3P SM silently no-ops the missing event; the body holds whatever stance was active before the wield. | Step (d): add `_<PORT>_WIELD_3P[career] = "to_<other_stance>"` pointing at a stance the target body authors. |
| **`wh_priest` "wielding" a bow holds his prior-weapon idle stance silently** | Priest's 3P body authors no `to_longbow` / `to_crossbow` / `to_repeating_crossbow` events — missing-event no-op per `feedback_vt2_no_tpose_default_stance.md`. Common when a port author copies the Saltzpyre career list (4 careers) without auditing Priest's skeleton. | Strip `wh_priest` from ALL FOUR port surfaces (`weapon_unlock_map`, `_data.lua`, `_localization.lua`, `_<PORT>_WIELD_3P`). See the step (d) callout AND `feedback_vt2_no_bows_on_warrior_priest.md`. Burned three times during the v0.12.46–v0.12.48-dev audit chain: `_WE_LONGBOW_CROSSBOW_WIELD_3P` (v0.12.46-dev, new Port A), legacy `_SP_LONGBOW_CROSSBOW_WIELD_3P` (v0.12.47-dev retroactive), and `we_crossbow_repeater` Volley Crossbow (v0.12.48-dev, closed the audit). Rule is now hard-enforced in `weapon_unlock_map.wh_priest` (zero ranged entries). |
| **"`buff_template` (a nil value)" / engine fatal at wield, no Lua trace** | The template patcher's `wield_anim_career_3p` write fired before `Weapons.<template>` existed (mod load order race). | The patchers are nil-guarded (`if not Weapons or not Weapons.<tpl> then return end`); the call happens at module load, after `Weapons` is populated. If you see this, the `Weapons` global isn't ready — confirm patcher is called at top-level, not lazily. |
| **Preview model is wrong while in-mission fires correctly** | `MenuWorldPreviewer.equip_item` hook didn't fire (you hooked HeroPreviewer) OR the hook fires but the `spawn_data` mutation didn't run (multiple `hook_safe` registrations on the same method shadowing each other). | Hook MenuWorldPreviewer; consolidate to one hook_safe; forward-declare helpers. See `feedback_inventory_preview_hook_menuworldpreviewer.md`, `feedback_vmf_hook_safe_no_chain.md`, `feedback_lua_forward_reference.md`. |
| **In-mission model is wrong while preview shows the swapped unit** | `GearUtils.spawn_inventory_unit` hook bailed silently. Most common cause: career detection returned nil (used `Managers.player:owner` instead of `_unit_career_name`); second-most common: package not yet loaded. | Verify the diagnostic `[wt ...-3p-swap] enter` log line fires per equip and that `career=<expected>` is non-nil. See `feedback_vt2_mission_spawn_career_lookup.md`. |
| **Host sees correct swap; other players see vanilla equip-side mesh** | Husk-side `set_unit_visibility(new_unit, false)` ran unconditionally (the `owner_unit_1p == nil` branch was missing). | Gate visibility hide on `if owner_unit_1p then ...` — husks have no 1P unit and need 3P to stay visible. `weapon_tweaker.lua:2311-2313`. |
| **Brace's left pistol clipping a repeater body / arrow attached at wrong node** | Dual-unit weapon: only the primary 3P unit was swapped, the secondary stayed vanilla AND its attachment links into nodes that don't exist on the new mesh. | (1) Hide / drop the secondary unit (left pistol case, `:2528-2556`). (2) Re-link via the TARGET template's `ammo_unit_attachment_node_linking` (bolt-on-crossbow case, `:2446-2456`). |
| **Wield/un-wield re-shows a hidden secondary 3P unit** | `show_third_person_inventory` resets visibility on every wield. | Post-hook `SimpleInventoryExtension.show_third_person_inventory` AND `SimpleHuskInventoryExtension.show_third_person_inventory` to re-hide. **Hook both classes** — `feedback_vt2_husk_extension_class_pair.md`. Burned in v0.12.39 (`weapon_tweaker.lua:2555-2556`). |
| **Engine fatal on unwielding (holstered weapon mounts a missing node)** | Source template's `unit_attachment_node_linking.third_person.unwielded` references a node only present on the source body. `Unit.node` raises non-pcall-safe. | Substitute the target template's `unwielded` linking table in BOTH the in-mission spawn hook AND the preview hook. See `weapon_tweaker.lua:2462-2480` and `:2662-2680`, crashify `f210b3b7`. |
| **Engine fatal during wield (`GearUtils.link` raises `Unit.node` non-pcall-safe)** | Reusing an existing sibling-port helper whose body links via the SOURCE template's `*_hand_attachment_node_linking.third_person.wielded`. Source's wielded table references mesh-specific nodes (e.g. repeater pistol's `lock_hammer`, `rotator`, `trigger_t1`) that don't exist on the target mesh. Brace got away with reuse because its wielded table is trivial (`j_rightweaponattach → 0`); meshes with non-trivial nodes won't. | Fork a new helper that substitutes `Weapons.<target_template>.<hand>_hand_attachment_node_linking.third_person.wielded`. Pattern: `_wt_repeating_pistol_3p_swap_apply` `weapon_tweaker.lua:2670-2685`. The 6th item of the "Reusing an existing helper" checklist in Section 2 gates this — vet source's wielded node names BEFORE reusing. `feedback_vt2_unit_node_not_pcall_safe.md`. |
| **Local-player and remote-husk animations diverge per equip** | Anim remap state was stored on a single global, not weak-keyed per 3P body. Husks animate as if they held the local viewer's weapon. | `feedback_anim_remap_per_unit_state.md`. Per-unit state was a v0.12.35 fix; the patcher-only approach in this recipe doesn't hit it because per-action `anim_event_3p` is read from the template at fire time, not stored on the unit. Hit it if you add unit_state-based redirects on top. |
| **`Managers.package:load` succeeds but a later spawn fatals "Resource not found"** | The target 3P unit path isn't listed in `scripts/network_lookup/inventory_package_list.lua`. `:load` returns OK synchronously but the async fatal bypasses pcall. Common with display-only units. | `feedback_vt2_force_load_only_listed_paths.md`. Confirm the target path exists in `inventory_package_list.lua` BEFORE wiring the force-load. If it isn't there, the port needs a different mesh (one that IS listed) or the CWV custom-mesh recipe (`reference_la_custom_mesh_pattern.md`) — `weapon_tweaker` can't ship the unlisted unit safely. Burned in CWV v0.1.224 + v0.1.289. |

---

## 4. Canonical references (line citations)

All cites are in
`vermintide-2-tweaker/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua`
unless stated otherwise.

| Concept | File:line | Notes |
|---|---|---|
| Unlock map | `:29-55` | Strip/add at `:80-123` (`apply_weapon_unlocks`) |
| Career detection from a unit | `:858-895` (`_unit_career_name`) | Career-system → inventory → Managers.player fallbacks |
| Animation-event hook (the redirect funnel) | `:901+` (`Unit.animation_event`) | Layered redirect dispatch; 1P-skip at `:919` |
| Wield-stance patch (simplest case, no remap, no unit swap) | `:1793-1802` (`_patch_elf_spear_template_for_non_elves`) | Step (d) + (f) only |
| Wield-stance patch + per-action remap (no unit swap) | `:1664-1690` (`_patch_brace_template_for_kruber`) | Steps (d), (e), (f) |
| Force-load target 3P unit | `:1476-1488` (brace), `:1509-1526` (crossbow) | Step (g.1) |
| In-mission 3P unit swap (right-hand) | `:2161-2330` | The `mod:hook("GearUtils", "spawn_inventory_unit", ...)` block |
| In-mission 3P unit swap (left-hand + ammo) | `:2333-2510` (`_wt_longbow_3p_swap_apply`) | Helper called from the consolidated brace hook |
| Hide-secondary-unit hook for dual-mesh weapons | `:2528-2556` | `_hide_brace_left_pistol`; registered on both classes |
| Consolidated `MenuWorldPreviewer.equip_item` hook | `:2597-2634` | Brace inline body; dispatches to longbow + key-capture helpers |
| Preview 3P unit swap helper | `:2652-2695` (`_wt_longbow_preview_swap_apply`) | Step (g.3) |

---

## 5. Verification matrix

After implementing a port, walk all eight cells before declaring done.
The same matrix `character_weapon_variants/DEFINITION_OF_DONE.md` calls out
under `G-CROSS-CHAR` / `G-3P-ANIM`.

| Scenario | Check | Expected |
|---|---|---|
| **Solo, local player, in keep** | Equip the weapon in keep inventory; rotate the character preview. | Equip-side weapon visible in IML/equip slot. 3P body shows TARGET mesh in TARGET wield stance — not stuck in the previous weapon's idle (which is what a missing `to_<stance>` event would look like; see `feedback_vt2_no_tpose_default_stance.md`). |
| **Solo, local player, in mission** | Drop into a private mission; switch to the weapon. | 3P body (visible via the third-person camera enabled with `/tp`, or to other observers) shows target mesh + target firing/attack anims. 1P is the source weapon's normal 1P. |
| **Solo, bot teammate equip** | Hand-edit a bot loadout or use any other available bot-loadout tool; observe the bot. | Bot's 3P body shows target mesh + target anims. Same as the host-player path because bots go through `_unit_career_name` like any 3P unit. |
| **Multiplayer, host, viewing remote player husk** | Friend equips the weapon, joins host's lobby. | Host sees friend's 3P body with target mesh. The unconditional-`set_visibility(false)` regression that hits here was v0.12.37; verify the `if owner_unit_1p then` branch is in place. |
| **Multiplayer, client, viewing host** | Inverse of above. | Same as above; both halves use the same hook on both ends. |
| **Wield / un-wield cycle in mission** | Press Q to swap to melee, then back. | 3P mesh re-applies on each wield; dual-mesh secondaries (e.g. brace left pistol) stay hidden on each wield (`show_third_person_inventory` post-hook). |
| **Unwield to holster (mission end / inspect)** | Sheath the weapon (mission complete screen). | No engine fatal from `unwielded` node linking — verify target template's `unwielded` linking is in use in both swap paths. |
| **Toggle the VMF setting off** | Disable `unlock_<career>_<weaponkey>`, re-enter keep. | Career stripped from `can_wield`. Equip slot becomes empty. No leftover patches on the template fire because the career never equips. |

Two `mod:info` log lines you should see exactly once per equip on the swap
path: `[wt <port>] enter hand=<L|R> husk=<bool> career=<career> ...` and
`[wt <port>] swapped 3P <source> → <target> on career=<career>`. If
"enter" appears but "swapped" doesn't, read the bail line in between — a
SKIP line names the exact short-circuit (hand check / career check / v_w3p
nil / package not loaded / pcall ERROR). The diagnostic block at
`weapon_tweaker.lua:2218-2237` (brace) and `:2362-2381` (longbow) is the
template for this.

---

## 6. Cross-references

Background reading from the auto-memory store. Read these before
attempting a port for the first time:

- `feedback_1p_animations_universal.md` — **load-bearing.** 1P never gets
  per-character overrides; this recipe is 3P-only.
- `feedback_animation_remap_rules.md` — three-layer remap architecture
  (`_anim_redirect`, `_career_anim_redirect`, `_suffix_career_map`). Most
  ports don't need to touch the global maps; per-template `anim_event_3p`
  is the right surface for action-specific remaps.
- `feedback_anim_closed_vocabulary.md` — the closed-vocabulary rule.
  Remap targets must exist in the target wield-SM template's `anim_event`
  set. Skeleton-probe results don't guarantee playback; never invent.
- `feedback_anim_remap_per_unit_state.md` — when adding any unit-keyed
  state (e.g. a runtime stance toggle), weak-key per 3P body. Recipe-level
  template patching doesn't hit this; if you add stateful redirects on
  top, this rule applies.
- `reference_3p_anim_fix_process.md` — animlog → identify missing event →
  choose remap target → test workflow. Use when step (e) needs to be
  re-derived for a new weapon pairing.
- `feedback_vt2_husk_extension_class_pair.md` — register dual-extension
  hooks (`SimpleInventoryExtension` + `SimpleHuskInventoryExtension`,
  etc.). Hit twice in this codebase.
- `feedback_vt2_class_hook_derived.md` /
  `feedback_inventory_preview_hook_menuworldpreviewer.md` — hook
  MenuWorldPreviewer, not HeroPreviewer.
- `feedback_vt2_mission_spawn_career_lookup.md` — read career from
  inventory_system / career_system extension; `Managers.player:owner` is
  nil at spawn timing.
- `feedback_vmf_hook_safe_no_chain.md` — one hook_safe per (Class, method).
- `feedback_lua_forward_reference.md` — forward-declare locals used by
  hook closures.
- `feedback_vt2_no_bows_on_warrior_priest.md` — `wh_priest` is excluded
  from every bow/crossbow/longbow/volley-crossbow cross-character port.
  See the step (d) callout. Backstop for the failure-mode row above.
- `feedback_vt2_no_tpose_default_stance.md` — missing `anim_event_3p`
  doesn't T-pose; the body silently holds the previous weapon's idle
  stance. Frames the language used throughout Sections 3 and 5.
- `reference_3p_skeleton_events.md` — per-character matrix of authored
  3P wield events. The ground truth Step (d)'s sub-step 5 verifies the
  target wield event against. Use it to derive eligible careers for
  any new port and to confirm exclusions like `wh_priest` from bows.
- `feedback_cwv_cross_character_unit_packages.md` — force-load the target
  3P unit at mod init, async + prioritize.
- `feedback_vt2_force_load_only_listed_paths.md` — `Managers.package:load`
  returns OK even for unit paths not in `inventory_package_list.lua`, but
  any later spawn fatals with a non-pcall-safe "Resource not found". Vet
  the target unit path against `inventory_package_list.lua` BEFORE
  authoring the force-load.
- `feedback_vt2_unit_node_not_pcall_safe.md` — `Unit.node` engine fatals
  bypass pcall; substitute the target template's linking tables.
- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` — sibling CWV
  doc; the 9-step closed-vocabulary procedure also applies here.

---

## 7. Worked examples

### Example A — Brace of Pistols on Kruber → Repeating Handgun 3P

| Field | Value |
|---|---|
| Equip-side weapon (IML key) | `wh_brace_of_pistols` |
| Equip-side template | `Weapons.brace_of_pistols_template_1` |
| Source SM `wield_anim` (1P + 3P fallback) | `to_brace_of_pistols` |
| Target career(s) | `es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight` |
| Target 3P weapon (display) | Repeating Handgun |
| Target 3P unit path | `units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1_3p` |
| Target wield-3p event | `to_repeating_handgun` |
| `_<PORT>_WIELD_3P` | `{ es_mercenary = "to_repeating_handgun", es_huntsman = ..., es_knight = ..., es_questingknight = ... }` (`:1653`) |
| `_<PORT>_ANIM_REMAP_3P` | `{ special_action = "attack_shoot_fast" }` (`:1660`) |
| Patcher | `_patch_brace_template_for_kruber()` `:1664` |
| In-mission swap | right-hand branch in `GearUtils.spawn_inventory_unit` hook, `:2161-2330` |
| Preview swap | inline body in consolidated `MenuWorldPreviewer.equip_item` hook, `:2606-2634` |
| Secondary-unit handling | left brace pistol hidden via `_hide_brace_left_pistol` + dropped from preview spawn_data |

### Example B — Empire Longbow on Saltzpyre → Crossbow 3P *(originally shipped; `wh_priest` retroactively stripped v0.12.47-dev, 2026-05-19)*

| Field | Value |
|---|---|
| Equip-side weapon (IML key) | `es_longbow` |
| Equip-side template | `Weapons.longbow_empire_template` |
| Source SM `wield_anim` | `to_es_longbow` |
| Target career(s) | `wh_captain`, `wh_bountyhunter`, `wh_zealot` (`wh_priest` excluded — see Section 2 step (d) Warrior Priest rule. Stripped from `_SP_LONGBOW_CROSSBOW_WIELD_3P` in v0.12.47-dev.) |
| Target 3P weapon (display) | Empire Crossbow |
| Target 3P unit path | `units/weapons/player/wpn_empire_crossbow_t1/wpn_empire_crossbow_tier1_3p` |
| Target 3P ammo unit | `units/weapons/player/wpn_crossbow_quiver/wpn_crossbow_bolt_3p` |
| Target template (for node linking) | `Weapons.crossbow_template_1` |
| Target wield-3p event | `to_crossbow` |
| `_<PORT>_WIELD_3P` | `{ wh_captain = "to_crossbow", wh_bountyhunter = ..., wh_zealot = ... }` (`:1708`) |
| `_<PORT>_ANIM_REMAP_3P` | `{ attack_shoot_fast = "attack_shoot", attack_shoot_fast_last = "attack_shoot_last", draw_bow = "to_zoom" }` (`:1715`) — bow has rapid-fire; crossbow doesn't, so remap `*_fast` to non-fast; `draw_bow` aim-hold becomes crossbow `to_zoom`. |
| Patcher | `_patch_longbow_empire_template_for_saltzpyre()` `:1721` |
| In-mission swap | `_wt_longbow_3p_swap_apply` helper at `:2359-2510`; swaps BOTH weapon (bow→crossbow) AND ammo (arrow→bolt); uses target template's `ammo_unit_attachment_node_linking` |
| Preview swap | `_wt_longbow_preview_swap_apply` helper at `:2652-2695`; mutates `entry.unit_name` AND `entry.unit_attachment_node_linking` |
| Special-case caveat | source template's `unit_attachment_node_linking.third_person.unwielded` references `a_unwielded_bow` (only on elf/empire bodies, not Saltzpyre's) → engine fatal bypasses pcall; substitute target template's table in both swap paths |

### Example C — Elf Longbow (`we_longbow`) on Saltzpyre → Empire Crossbow 3P *(shipped v0.12.44-dev, 2026-05-19)*

Sibling of Example B (`es_longbow`→crossbow). The Wood Elf longbow points
at a different `Weapons.<template>` and uses elf-specific 1P meshes, but the
3P target is identical to Example B — same `_SP_CROSSBOW_3P_UNIT` /
`_SP_CROSSBOW_BOLT_3P_UNIT` constants, same force-load, same target template.
This made the implementation a step-(a)-through-(f) port that contributed
**zero new step-(g) infrastructure** — see the "Reusing an existing helper
for sibling ports" sub-section under Section 2 below for the general pattern.

| Field | Value |
|---|---|
| Equip-side weapon (IML key) | `we_longbow` |
| Equip-side template | `Weapons.longbow_template_1` (source: `weapon_templates/longbows.lua`) |
| Equip-side `wield_anim` (1P) | `to_longbow` (bare; no per-character override on the source side) |
| Equip-side `wield_anim_no_ammo` (1P) | `to_longbow_noammo` |
| Equip-side action vocab (1P) | `attack_shoot_fast` / `attack_shoot_fast_last` (action_one.default), `attack_shoot` / `attack_shoot_last` (action_one.shoot_charged + shoot_special_charged), `draw_bow` / `draw_cancel` (action_two.default) |
| Equip-side `left_hand_unit` | `units/weapons/player/wpn_we_bow_01_t1/wpn_we_bow_01_t1` |
| Equip-side `ammo_unit` | `units/weapons/player/wpn_we_quiver_t1/wpn_we_arrow_t1` |
| Equip hand | left |
| Target career(s) | `wh_captain`, `wh_bountyhunter`, `wh_zealot` (`wh_priest` excluded — see Section 2 step (d) Warrior Priest rule. Stripped from `_WE_LONGBOW_CROSSBOW_WIELD_3P` in v0.12.46-dev.) |
| Target 3P weapon unit | `_SP_CROSSBOW_3P_UNIT` (`weapon_tweaker.lua:1506`) |
| Target 3P ammo unit | `_SP_CROSSBOW_BOLT_3P_UNIT` (`:1507`) |
| Target template | `Weapons.crossbow_template_1` |
| Target wield-3p event | `to_crossbow` |
| Target SM closed vocab | `attack_shoot`, `attack_shoot_last`, `attack_shoot_no_reload`, `to_zoom`, `to_unzoom` |
| Force-load | reused `_force_load_sp_crossbow_3p_units` (`:1509-1526`). No new load required — both ports target the same 3P weapon + bolt unit. |
| `_WE_LONGBOW_CROSSBOW_WIELD_3P` | `{ wh_captain = "to_crossbow", wh_bountyhunter = "to_crossbow", wh_zealot = "to_crossbow" }` (`weapon_tweaker.lua:1758`) |
| `_WE_LONGBOW_CROSSBOW_ANIM_REMAP_3P` | `{ attack_shoot_fast = "attack_shoot", attack_shoot_fast_last = "attack_shoot_last", draw_bow = "to_zoom" }` (`:1765`) — identical to Example B's remap (elf longbow + Empire longbow share the same `actions[*][*].anim_event` vocabulary, so the rapid-fire-vs-no-rapid-fire mismatch with crossbow is identical). `shoot_charged` / `shoot_special_charged` use `attack_shoot` natively → fall through. |
| Patcher | `_patch_longbow_template_1_for_saltzpyre()` `weapon_tweaker.lua:1771` |
| In-mission swap | reused `_wt_longbow_3p_swap_apply` (`:2359-2510`); dispatcher predicate at `:2172` widened to `item_data.name == "es_longbow" or item_data.name == "we_longbow"`. Same body otherwise. |
| Preview swap | reused `_wt_longbow_preview_swap_apply` (`:2652-2695`); `item_name` predicate widened the same way. |
| Special-case caveat 1 — `a_unwielded_bow` fatal | Same engine-fatal as Example B (`feedback_vt2_unit_node_not_pcall_safe.md`). The elf longbow's `unit_attachment_node_linking.third_person.unwielded` also references `a_unwielded_bow`, a node absent on Saltzpyre's 3P body. Already covered by the existing helpers' substitution of `Weapons.crossbow_template_1.left_hand_attachment_node_linking.third_person` in BOTH swap paths. Crashify precedents: `92f9907f` (in-mission), `f210b3b7` (preview). |
| Special-case caveat 2 — bolt attachment | Already covered by the existing helpers — they use `Weapons.crossbow_template_1.ammo_data.ammo_unit_attachment_node_linking.third_person.wielded` for the bolt's 3P attachment. The elf arrow's linking targets the bow nock, which doesn't exist on the crossbow mesh. |

### Example D — Saltzpyre's Repeating Pistol (`wh_repeating_pistols`) on Kruber → Repeating Handgun 3P *(shipped v0.12.45-dev, 2026-05-19)*

User-confirmed Port B variant: the source is the revolving **Repeating
Pistol**, NOT the Repeating Crossbow. Sibling of Example A
(`wh_brace_of_pistols` → Repeating Handgun on Kruber) — same hand, same
target 3P unit + force-load, same target template. The "Reusing an
existing helper for sibling ports" checklist in Section 2 gates **only
4/5** against the brace hook: identical on target unit / target template
/ hand / no ancillary swaps, but the **6th attachment-node-linking
gate** (see Section 2 checklist) FAILS. The repeater pistol's `wielded`
linking table references mesh-specific nodes (`lock_hammer`, `rotator`,
`trigger_t1`) that don't exist on the handgun mesh; reusing the brace
hook's body would `Unit.node` fatal (non-pcall-safe).

So Port B shipped with **forked helpers** rather than dispatcher-widened:
`_wt_repeating_pistol_3p_swap_apply` (in-mission, `weapon_tweaker.lua:2629`)
and `_wt_repeating_pistol_preview_swap_apply` (preview, `:2940`). Both
explicitly substitute `Weapons.repeating_handgun_template_1.right_hand_attachment_node_linking.third_person.wielded`
for the source's table. See the substitution body + non-pcall-safe-node
justification comment at `weapon_tweaker.lua:2670-2685`.

Step (e)'s remap table is empty — target SM is a strict superset of
source vocab. The patcher writes `wield_anim_career_3p` only; no
`anim_event_3p` walk runs.

| Field | Value |
|---|---|
| Equip-side weapon (IML key) | `wh_repeating_pistols` |
| Equip-side template | `Weapons.repeating_pistol_template_1` (source: `weapon_templates/repeating_pistols.lua`) |
| Equip-side `wield_anim` (1P) | `to_repeater_pistol` |
| Equip-side action vocab (1P) | `attack_shoot` (action_one.default, action_one.bullet_spray), `lock_target` / `attack_finished` (action_two.default) |
| Equip-side `right_hand_unit` | `units/weapons/player/wpn_empire_pistol_repeater_02/wpn_empire_pistol_repeater_02_t1` |
| Equip-side `ammo_unit` | none |
| Equip hand | right |
| Target career(s) | `es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight` |
| Target 3P weapon unit | `_BRACE_REPEATER_3P_UNIT` (`weapon_tweaker.lua:1459`) |
| Target template | `Weapons.repeating_handgun_template_1` (source: `weapon_templates/repeating_handguns.lua`) |
| Target wield-3p event | `to_repeating_handgun` |
| Target SM closed vocab | `attack_shoot`, `attack_shoot_last`, `attack_shoot_fast`, `attack_shoot_fast_last`, `lock_target`, `lock_target_loop`, `reload`, `attack_finished` |
| Force-load | reuses existing `_force_load_brace_repeater_3p_unit` (`:1476-1488`). |
| `_WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P` | `{ es_mercenary = "to_repeating_handgun", es_huntsman = ..., es_knight = ..., es_questingknight = ... }` at `weapon_tweaker.lua:1812` |
| `_<PORT>_ANIM_REMAP_3P` | `{}` (intentionally absent — see the load-bearing comment at `:1828-1829`). Target SM is a superset of source vocab; every source `anim_event` falls through unchanged. |
| Patcher | `_patch_repeating_pistol_template_1_for_kruber()` `weapon_tweaker.lua:1819`. Writes `wield_anim_career_3p` only; no `actions` walk. |
| In-mission swap | **forked**: `_wt_repeating_pistol_3p_swap_apply` `:2629-2738`. Dispatched from the brace hook at `:2262-2263` via `item_data.name == "wh_repeating_pistols"`. |
| Preview swap | **forked**: `_wt_repeating_pistol_preview_swap_apply` `:2940+`. Dispatched from the consolidated `MenuWorldPreviewer.equip_item` hook at `:2835`. |
| Husk extension class pair | extend `_hide_brace_left_pistol` (`:2528-2553`) item_name match — though for `wh_repeating_pistols` the source has NO left-hand pistol, so the left-pistol-hide is a no-op for this port. Don't break it for the brace case. |
| Special-case caveat — attachment-node-linking fatal | **The reason helpers were forked instead of dispatcher-widened.** The source pistol's `right_hand_attachment_node_linking.third_person.wielded` references nodes (`lock_hammer`, `rotator`, `trigger_t1`) only present on the pistol mesh; linking them against the handgun mesh raises `Unit.node` (non-pcall-safe — `feedback_vt2_unit_node_not_pcall_safe.md`). Substituted via `Weapons.repeating_handgun_template_1.right_hand_attachment_node_linking.third_person.wielded` at `weapon_tweaker.lua:2670-2685`. The comment block in the helper body documents the failure mode. |

> **Historical note.** Before user confirmation, Port B was ambiguous
> between `wh_repeating_pistols` (this Example) and `wh_crossbow_repeater`
> (Saltzpyre's repeater crossbow — left-hand source). The latter would
> have needed a NEW left-hand swap helper plus a hand-cross-over caveat
> (left-hand source → right-hand target attachment). It was ruled out
> by the user; this note is preserved in case a future port wants the
> repeater crossbow as a source (e.g. on Kerillian, who can also wield
> it). The shape would mirror Example D2 in earlier doc revisions: see
> git history at `vermintide-2-tweaker/weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`.

---

## 8. Pre-deploy checklist

Before tagging a version that ships a new port:

- [ ] All 7 procedure steps done; patcher invoked at module load.
- [ ] VMF widget appears in the expected ranged/melee group, with the
      expected localized name; toggle on/off cycles `can_wield` correctly
      (re-enter keep to verify).
- [ ] Forward-reference audit on the file (`feedback_lua_forward_reference.md`).
- [ ] Verification matrix walked end-to-end (8 cells); diagnostic
      `[wt <port>] swapped ...` lines visible once per equip on both
      host and client.
- [ ] `MOD_VERSION` bumped (`weapon_tweaker.lua:25`); `CHANGELOG.md`
      entry describes the new port, including the remap table and any
      target-template substitutions.
- [ ] If a sibling mod (e.g. `character_weapon_variants`) ships an
      overlapping (career, weapon) variant, add the entry to `_cwv_managed`
      at `weapon_tweaker.lua:62` and strip the widget so the two mods
      don't compete for the `can_wield` slot.
