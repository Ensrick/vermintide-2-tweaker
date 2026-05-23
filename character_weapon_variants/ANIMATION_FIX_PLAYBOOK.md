# 3P Animation Fix Playbook

A standardized procedure for fixing third-person animations on cross-character weapons in the Character Weapon Variants mod and adjacent code paths in `weapon_tweaker`. Read once before touching any animation code; re-read before adding a new remap entry.

This is the linear how-to. The reference docs (`character_weapon_variants/DEVELOPMENT.md` "Animation: System B" and "Animation: cross-access weapons", top-level `DEVELOPMENT.md` "Animation System Architecture", `WEAPON_CATALOG.md`) cover the why and the API surface. This file covers the do.

---

## Scope: 3P ONLY

This entire playbook is about **third-person body animations**. First-person animations are universal across all six characters and out of scope — they work correctly on every character with every weapon by default and **must never be touched**. Every rule, table, hook, and verification step below applies to the 3P body only.

If a remap, template clone, or hook in this codebase appears to touch `anim_event` (1P), `wield_anim` (1P), `state_machine`, `anim_event_1p`, or any per-character 1P field, that's a bug — back it out.

## Three non-negotiable rules

1. **1P animations are universal — never touch.** First-person hands share `first_person_base` across every character; any weapon's 1P state machine plays correctly on every character's first-person view by default. Only `anim_event_3p`, `wield_anim_3p`, `wield_anim_career_3p` are in scope. Touching `anim_event` / `wield_anim` / `state_machine` per character is harmful, not just unnecessary. The `Unit.animation_event` hook in CWV's cross-access remap is gated to fire only on the local 3P body via five early-exits — 1P calls never enter the remap path.

2. **Closed-vocabulary rule (3P).** Every 3P remap target MUST be a string already present in the `anim_event` column of the target body's wield-SM-matching template. The skeleton-events probe (`/sm_probe`) and `Unit.has_animation_event` only report whether the master state machine knows the name; the destination state in the current sub-graph may be a stub that animates nothing. The only safe candidate universe is the target template's authored event set. There is no parallel "1P closed list" — 1P doesn't need one.

3. **Chain-context rule.** Closed-vocab is necessary but still not sufficient. The body's clip selection depends on **chain state**, not just event name. An in-vocab event can produce zero animation if the body's current chain state has no clip mapped for that event. Pick a target event that the target's NATIVE template fires from a chain position equivalent to the source action's chain position (source H1 from idle → target's idle-H1 event; source H2 after H1 → target's H2 event). Read the source template Lua at `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/<target>.lua` — the action sub-tables show which event each chain position fires.

If you remember nothing else, remember those three.

---

## Step 1 — Triage the symptom

Classify before reaching for tools.

| Symptom | Likely scope |
|---|---|
| **A. Wield pose wrong** (idle stance, weapon held weird) | `wield_anim_3p` / `wield_anim_career_3p` on the variant template, or a base-template patch for the inventory previewer |
| **B. Attack missing (event silently no-ops — body holds previous idle, NOT a T-pose; see `PROJECT_STANDARDS.md` § 9.8) / wrong direction** | `anim_event_3p` on sub-actions (System B) or runtime event-name rewrite (cross-access remap, or `weapon_tweaker` System A) |
| **C. In-game OK, menu preview wrong** | Base template's `wield_anim_career_3p` — `HeroPreviewer` reads the base, not the clone |
| **D. Local OK, husk wrong** | The cross-access runtime remap doesn't cover husks. Either accept the gap or port `weapon_tweaker`'s `_unit_career_name` per-unit resolver |
| **E. Native wielder regression** | A shared template's `anim_event_3p` was mutated for a foreign career and broke the native one. Back the change out and re-do via the runtime hook |

Do not skip this step. The symptom dictates which tool you reach for; the wrong tool wastes a build cycle.

## Step 2 — Decide which pattern applies

| Situation | Pattern |
|---|---|
| New CWV variant item with custom template clone | **System B** — edit `anim_event_3p` on cloned sub-actions |
| `can_wield` expansion on a shared vanilla template, action plays wrong on foreign career | **Cross-access runtime remap** — `mod:hook("Unit", "animation_event", ...)` with (item, career) dispatch |
| `can_wield` expansion, only the wield pose reads wrong | **`wield_anim_career_3p`** patch on the base template |
| Vanilla weapon unlocked via `weapon_tweaker.weapon_unlock_map` | **System A** in `weapon_tweaker` (out of scope for this mod) |
| In-game right but inventory preview wrong | **Base template `wield_anim_career_3p`** patch (Step 6 in System B's recipe) |

If you don't own the item, use the runtime hook. If you own it (CWV variant with custom template), prefer System B — direct sub-action edits compose better with the rest of the data.

## Step 3 — Lock the closed vocabulary

This is the step that gets skipped.

1. Identify the **target body's wield SM** for the foreign career. For a cross-access weapon, this is the `wield_anim_career_3p` value set in `_cross_access_template_wield_3p`. Example: axe+falchion on Kruber routes to `to_dual_hammer_sword_es`, so the target template is `dual_wield_hammer_sword_template`.
2. Pull every `anim_event` value from that template (in `dumps/weapon_actions.txt`, or live via `/dump_actions <template>`).
3. **Write the closed list down**, including which sub-action each event belongs to. That is your allowed set of remap targets. Nothing else is a candidate.
4. If the wield SM has companion templates authored in the same sub-graph (rare — verify by sharing the same `wield_anim` prefix), union those events in too.

Example for `dual_wield_hammer_sword_template` (Kruber's mace+sword, used as target SM for axe+falchion and dual axes on Kruber):

| Closed list | Type | Source action |
|---|---|---|
| `attack_swing_charge_right` | charge | `default_right` |
| `attack_swing_charge_left` | charge | `default_left`, `default_right_heavy`, `default` |
| `attack_swing_heavy_left_diagonal` | strike | `heavy_attack` |
| `attack_swing_heavy_right_diagonal` | strike | `heavy_attack_2` |
| `attack_swing_left_diagonal` | strike | `light_attack_left_diagonal` |
| `attack_swing_down` | strike | `light_attack_bopp` |
| `attack_swing_left` | strike | `light_attack_left` |
| `attack_swing_right` | strike | `light_attack_right` |
| `attack_swing_right_diagonal` | strike | `light_attack_right_diagonal` |
| `attack_push` | push | `push` |
| `parry_pose` | block | `action_two.default` |
| `inspect_start` | inspect | `action_inspect.action_inspect_hold` |

That is the entire universe of valid remap targets for this SM. Picking anything outside it is invention.

## Step 4 — Cross-reference the source template

Walk the source template's `anim_event` strings (also from `dumps/weapon_actions.txt`). For each one, ask two questions:

1. **Is the event in the target's closed list?**
2. **Does the target's clip for that event match the source's visual intent?**

The decision matrix:

| In target vocab? | Target's clip matches intent? | Action |
|---|---|---|
| ❌ No | (n/a) | **Remap.** Pick a substitute from the closed list whose visual direction matches the source's intent. |
| ✅ Yes | ✅ Yes | **Leave alone.** The native clip plays correctly. |
| ✅ Yes | ❌ No | **Remap to a different in-vocab event.** The closed-vocab rule still constrains the substitute, but you're picking a different in-vocab event whose clip matches the intent. |

Common bugs from skipping the second question:
- Source push-attack `attack_swing_down` IS in mace+sword's vocab, but target's clip is a downward mace chop (right-hand). If the variant's design wants a left-hand falchion swing for the push-attack, remap to `attack_swing_left` (still in vocab, different clip).
- Source heavy `attack_swing_heavy_down` exists on some target SMs as a stub or a non-strike pose. "In vocab" doesn't mean the clip plays a usable strike.

Common bug from over-remapping:
- Rewriting `attack_push` when both source and target already use it AND target's clip reads as a normal push. The engine plays the correct clip on both sides — substituting it replaces a working clip with a different one.

The "in vocab" check is necessary but not sufficient. The visual-intent check (Step 6 verifies it) is what closes the loop.

Example — axe+falchion source (`dual_wield_axe_falchion_template`) cross-referenced against Kruber's mace+sword target:

| Source event | In target? | Target clip matches intent? | Action |
|---|---|---|---|
| `attack_swing_heavy_down` (H1 release) | ❌ | n/a | remap (overhead → right-diag heavy) |
| `attack_swing_charge_down` (H1 charge) | ❌ | n/a | remap (paired with H1 release) |
| `attack_swing_heavy_left` (H2 release) | ❌ | n/a | remap (left-side heavy) |
| `attack_swing_down_left` (light) | ❌ | n/a | remap (left diagonal) |
| `attack_swing_down` (push-attack) | ✅ | ❌ — target plays right-hand mace chop, design wants left-hand falchion | **remap to `attack_swing_left`** (in vocab, different clip) |
| `attack_push` (push) | ✅ | ✅ | leave alone |
| `attack_swing_charge_left` (H2/L charge) | ✅ | ✅ | leave alone |
| `attack_swing_left_diagonal` (light) | ✅ | ✅ | leave alone |
| `attack_swing_right` (light) | ✅ | ✅ | leave alone |
| `attack_swing_right_diagonal` (light) | ✅ | ✅ | leave alone |

Five entries needed, five left alone. Adding any remap to a "leave alone" event is a regression — it overrides a working clip with a different one. Skipping a remap on a "matches intent: ❌" event leaves the visual wrong even though no engine-level error occurs.

## Step 5 — Direction-coherence pass

For every heavy charge/release pair you are remapping, the **wind-up direction must match the strike direction**. Source templates pair specific charges with specific releases via the chain graph; remapping each independently can break the visual pairing (charge cocks left, release strikes right).

For each pair:
1. Open the source template's `actions[*][*]` block. Find which charge sub-action chains into the release sub-action you are remapping (look at `allowed_chain_actions` if available, otherwise infer from the `default_*` / `heavy_attack*` naming convention).
2. Decide on a target direction (left or right). Both work — pick whichever has a closer-matching strike clip in the closed list.
3. Set both the charge and the release remap targets to that direction.

Example — H1 of axe+falchion on Kruber:
- Source: `default_down` (charge `attack_swing_charge_down`) → `heavy_attack` (release `attack_swing_heavy_down`). Both are "downward / overhead" intent.
- Closed list has no overhead clips. Pick right-side: `attack_swing_charge_right` + `attack_swing_heavy_right_diagonal`. Both right-side, direction-coherent.

H2 of the same case:
- Source: `default_left` (charge `attack_swing_charge_left`) → `heavy_attack_2` (release `attack_swing_heavy_left`). Both left-side.
- `attack_swing_charge_left` is already in the closed list, so no charge remap. Release remaps to `attack_swing_heavy_left_diagonal` (closest left-side strike). Direction-coherent.

Caveat — chain context: in the target template, a charge event like `attack_swing_charge_left` may be authored across multiple sub-actions (e.g., as both a light charge and a heavy continuation charge). The clip the body actually plays depends on the SM's chain context, not the event name. If a remapped heavy plays a light's wind-up clip first and then a heavy strike, you can't fix it with the closed-vocab rule alone — that's an SM chain-context issue and requires a different approach (System B template clone, or accept the visual quirk).

Direction mismatches are surfaced most clearly on Kruber's empire-soldier 3P body during a cold-start heavy from idle. Other bodies (especially Kerillian's wood-elf) blend through them; assume they will not.

## Step 6 — Verify each candidate visually

The closed-vocabulary rule is necessary but not sufficient. Some events in the closed list still produce stub playback in the current sub-graph state. The only proof a remap will work is "I watched the body and it animated correctly."

For each chosen substitute:
1. Equip the cross-character weapon on the target career. Stand idle in the keep.
2. Run `/force3p <substitute>` in chat.
3. Watch the 3P body (use a mirror, or have a teammate spectate). Only "the body visibly moved through a complete strike" counts. `/force3p` printing `exists=true` is meaningless on its own — that comes from `Unit.has_animation_event`, which lies about visible playback.
4. Note the strike's actual direction; if it's not what you expected, pick a different candidate.

Skip this step at your peril. Past sessions wasted hours guessing remap targets that "existed" on the skeleton table but produced no visible animation.

## Step 7 — Implement (per the chosen pattern)

### System B — template clone

See `_create_imperial_dual_swords_template` for the canonical example. Shape:
1. Guard against missing source / re-clone.
2. Deep-clone via `table.clone(source, true)`. Shallow clones leak mutations into vanilla.
3. Walk `template.actions[*][*]` and write `_remap_table[anim_event] → anim_event_3p` per sub-action. Never touch `sub_action.anim_event` (1P).
4. Set `template.wield_anim_3p` (default) and `template.wield_anim_career_3p` (per-career).
5. Register the clone: `Weapons.<clone_name> = template`.
6. **Patch the BASE template's `wield_anim_career_3p`** for the inventory previewer. Merge per-key — never wholesale-assign.
7. Call the function at file load.

### Cross-access runtime remap

See `_kruber_axe_falchion_remap` and `_cross_access_action_remap` for the canonical example. Shape:
1. Define a `local _<wielder>_<weapon>_remap = { src_event = "target_event", ... }` table. Every value MUST be in the target SM's closed list (Step 3).
2. Register it in `_cross_access_action_remap[<base_item_key>][<career_name>]`. List exact career names — no prefix matching in this pattern.
3. The wield-tracker hook (`SimpleInventoryExtension.wield`) and the `Unit.animation_event` hook are already in place; new entries just plug into the existing dispatch.

### Wield-only base patch

```lua
local base = Weapons.<base_template>
if base then
    base.wield_anim_career_3p = base.wield_anim_career_3p or {}
    base.wield_anim_career_3p.<career_name> = "to_<target_sm>"
end
```

Merge keys; do not clobber. Other careers may have already added entries.

## Step 8 — Build, deploy, test

1. **Bump `MOD_VERSION`** in `character_weapon_variants.lua` (every build, no exceptions — required for visual hot-reload confirmation).
2. **Forward-reference audit** — confirm every function/local referenced is defined above its use. Five crashes from this bug class alone in this codebase.
3. Build: `node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd`. Verify `bundleV2/` output has fresh files.
4. Deploy to Workshop folder. CWV's Workshop ID is `3716869446`.
5. **Full game restart.** Hot-reload is unsafe for CWV (engine-level C++ resource locks).
6. In-game: re-equip the weapon (the wield-tracker hook must fire to pick up the new template / career).
7. `/animlog` — confirm `[MISSING]` is gone for the events you remapped, and `REMAP` markers fire on the right events.
8. Visual check on the target career: full L-chain, full H-chain, push, push-attack. Watch the body.
9. Inventory preview check: open the menu, confirm wield pose matches in-game.
10. Husk check (if relevant): bot or friend wields the same weapon, watch their body. The cross-access remap pattern doesn't cover husks by default — note any gap.
11. **Native-wielder regression check**: equip on the original native career, verify nothing changed.

## Step 9 — Document the change

- `CHANGELOG.md` (this mod) — version + one-line summary of what changed and why.
- `WEAPON_CATALOG.md` (top-level) — update the per-weapon row if status changed.
- New gotcha discovered (event that exists-but-doesn't-play, SM-corrupting remap, base-template indirection)? Write a memory file. Existing memory rule: every recurring failure mode gets recorded so future sessions don't repeat it.

---

## Quick checklist (use before every commit)

- [ ] `MOD_VERSION` bumped
- [ ] Every remap target appears in the target template's `anim_event` column (`dumps/weapon_actions.txt`)
- [ ] Source events that already exist in the target list are NOT remapped
- [ ] For every remapped heavy release, the paired charge is also direction-matched (or already in target vocab natively)
- [ ] Each substitute was verified with `/force3p` and a visible strike was confirmed
- [ ] No `anim_event` (1P), `wield_anim` (1P), or `state_machine` is touched per character
- [ ] `CHANGELOG.md` updated
- [ ] In-game test passed on at least one foreign career
- [ ] Native-wielder regression check passed

---

## Worked example — Kruber wielding Saltzpyre's axe+falchion

Source template: `dual_wield_axe_falchion_template` (wield `to_dual_axe_sword_wh`).
Foreign wielder: any `es_*` career.
Target wield SM: `to_dual_hammer_sword_es` (set in `_cross_access_template_wield_3p`).
Target template: `dual_wield_hammer_sword_template`. Closed list per Step 3 above.

Remap (`_kruber_axe_falchion_remap`):

```lua
{
    -- H1: source overhead (charge_down → heavy_down). No overhead in closed
    -- list; route to right-side. Direction-coherent.
    attack_swing_charge_down = "attack_swing_charge_right",
    attack_swing_heavy_down  = "attack_swing_heavy_right_diagonal",
    -- H2: source heavy_left → left-diagonal (closest left-side strike).
    -- H2's charge `attack_swing_charge_left` is in the closed list natively.
    attack_swing_heavy_left  = "attack_swing_heavy_left_diagonal",
    -- Light: source down_left → left-diagonal.
    attack_swing_down_left   = "attack_swing_left_diagonal",
    -- Push-attack: source attack_swing_down IS in target vocab, but target's
    -- clip is a right-hand mace chop. Design wants a left-hand falchion swing,
    -- so remap to attack_swing_left (target's light_attack_left).
    attack_swing_down        = "attack_swing_left",
}
```

Source events explicitly NOT remapped because they're in the target's closed list AND the target's clip matches intent:

- `attack_push` (universal push, target plays normal push)
- `attack_swing_charge_left`, `attack_swing_left_diagonal`, `attack_swing_right`, `attack_swing_right_diagonal` (light/strike events shared between source and target with matching intent)

Version history of this remap:
- pre-v0.1.158: had `attack_push → attack_swing_left_diagonal`. Violated the closed-vocab rule (`attack_push` is in vocab and plays natively). Removed in v0.1.158.
- v0.1.158: down to four entries. `attack_swing_down` (push-attack) was left alone because it was "in vocab." User reported the resulting clip was a right-hand mace chop, not the left-hand falchion swing the variant's design called for.
- v0.1.161: added `attack_swing_down → attack_swing_left`. Demonstrates the "in vocab is necessary but not sufficient" caveat: the target's clip for an in-vocab event still has to match the visual intent, or you remap to a different in-vocab event whose clip does.
