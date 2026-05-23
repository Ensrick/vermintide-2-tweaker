# Localization Standard — VT2 Tweaker Monorepo

Canonical convention for every `*_localization.lua` file across the tweaker monorepo. Establishes the rules that prevent the `<<crashify-exception>>` bug class, documents the patterns that work, and lists which mods currently conform.

**Snapshot:** 2026-05-21. See [`AUDIT_section_c.md`](./AUDIT_section_c.md) for the full localization sweep (13 P0 unescaped `%`, 8 P1 missing keys, 1247 P2 orphans) and [`AUDIT_2026_05_21.md`](./AUDIT_2026_05_21.md) for the master audit and the documentation gaps this doc closes.

---

## 1. Core rule — `mod:localize` runs `safe_string_format`

VMF's `mod:localize(key)` does NOT return the raw `en = "..."` value. It runs the value through `safe_string_format` (essentially `string.format`). Every literal `%` in the string is treated as the start of a format directive.

**Consequence:** any lone `%` that is NOT part of an escaped `%%` pair emits a `<<crashify-exception>>` event when VMF builds the widget (typically at mod-options panel open / tooltip hover). Most of these don't crash the game, but they spam the log and the widget renders garbage.

**Rule:** every literal `%` in a localization string MUST be doubled to `%%`.

### Positive example — `weapon_tweaker` post-Fix 1 (v0.12.63-dev)

```lua
trait_melee_attack_speed_on_crit_description = {
    en = "Critical hits grant +20%% attack speed for 5 seconds."
},
trait_melee_counter_push_power_description = {
    en = "Pushes against attacks gain 50%% bonus push power."
},
trait_ranged_replenish_ammo_on_crit_description = {
    en = "Critical hits restore 5%% of max ammo."
},
```

(See `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua:548-590`.)

### Historical context — `general_tweaker` 0.2.35

`gt` 0.2.35's CHANGELOG was the first place this rule was documented in the repo, after the same class of bug appeared in a percentage string. That note was per-mod and got missed when `wt` and `lobby_tweaker` later authored the same shape of string — hence this central doc.

---

## 2. The double-format anti-pattern

**Anti-pattern:**

```lua
-- BAD: VMF's localize already consumed the %d. The outer string.format
-- operates on the post-formatted string and either no-ops or errors.
local msg = string.format(mod:localize("missing_mods_count"), n)
-- where the en string is "You are missing %d mods..."
```

If the localization string contains a format directive like `%d` or `%s`, VMF consumes it during `mod:localize` — by the time the value returns, the directive is GONE. Wrapping in an outer `string.format` then does the wrong thing.

This is exactly the bug `lobby_tweaker` shipped pre-Fix 1: `"You are missing %d mods required by the host:"` was being passed through both VMF and an outer `string.format`. Fixed by escaping to `%%d` in the localization so VMF renders the literal `%d`, then the caller's `string.format` interpolates it.

### Two valid patterns

**Pattern A — pre-format directive, escape in localization, format at call site (RECOMMENDED for short interpolations)**

```lua
-- localization
failnotify_required_header = { en = "You are missing %%d mods required by the host:" },

-- call site
local n = #missing
local header = string.format(mod:localize("failnotify_required_header"), n)
```

This is what `lobby_tweaker` uses post-Fix 1 (`lobby_tweaker_localization.lua:36-38`).

VMF reads `%%d`, renders it as `%d`, returns `"You are missing %d mods required by the host:"`. The caller's `string.format` then interpolates `n`.

**Pattern B — no directives, concatenate at call site (RECOMMENDED for longer strings or locales where word order varies)**

```lua
-- localization (no directives)
found_mods_prefix = { en = "Found" },
found_mods_suffix = { en = "mods" },

-- call site
local msg = mod:localize("found_mods_prefix") .. " " .. tostring(n) .. " " .. mod:localize("found_mods_suffix")
```

Less idiomatic for English, but the only safe pattern if any future translation might need different word order. Use this when the dynamic value sits in the middle of a long phrase.

### When in doubt

Default to Pattern A. It matches `string.format` semantics that every Lua dev already knows. Pattern B is a footnote for the longer-string case.

---

## 3. Key naming conventions

### Setting widgets

Use `kebab_case` matching the widget's `setting_id`. Both VMF resolution and human grep-ability depend on this 1:1 match.

```lua
-- _data.lua
{ setting_id = "tp_camera_enabled", ... }

-- _localization.lua
tp_camera_enabled = { en = "Enable Third-Person Camera" },
```

### Tooltips — `_tooltip` suffix (canonical)

VMF auto-resolves `<setting_id>_tooltip` as the tooltip key. Use `_tooltip`, NOT `_description`.

```lua
tp_camera_enabled         = { en = "Enable Third-Person Camera" },
tp_camera_enabled_tooltip = { en = "Toggle third-person camera view. Can also be toggled in-game with the 'gt tp' chat command." },
```

`_description` is a legacy variant some older entries use. It is NOT auto-resolved by VMF — those keys only work if the data file passes them explicitly. Do not author new `_description` keys. (Some mods such as `weapon_tweaker` and `crafting_in_modded` have hundreds of `_description` keys for historical reasons; migrating them is a follow-up — do not touch in this pass.)

### Group labels

Same as the widget's `setting_id`. Convention: groups suffix `_group`:

```lua
tp_camera_group = { en = "Third-Person Camera" },
gameplay_group  = { en = "Gameplay" },
```

### Required keys for every mod

- `mod_description` — top-level mod blurb shown by VMF in the mod-options panel header. Every mod MUST define this.
- `mod_name` — optional but recommended; some mods use it for the panel header. (`buff_tweaker`, `career_tweaker`, `chaos_wastes_tweaker`, `la_prefix_patch` define it; `general_tweaker`, `modded_progression`, `verminious_dreams_lighting`, `enemy_tweaker`, `lobby_tweaker` rely on the mod-id alone.)

---

## 4. File structure

Every localization file should follow this template:

```lua
-- Optional: short helper to keep entries terse
local function en(s) return { en = s } end

return {
    mod_description = en("One-line elevator pitch for the mod-options panel header."),

    -- ============================================================
    -- Group 1 — short heading comment
    -- ============================================================
    group_one_group        = en("Group One"),
    setting_a              = en("Setting A"),
    setting_a_tooltip      = en("Tooltip for Setting A. Be specific about what ON/OFF do and any host-only caveats."),
    setting_b              = en("Setting B"),
    setting_b_tooltip      = en("..."),

    -- ============================================================
    -- Group 2
    -- ============================================================
    group_two_group        = en("Group Two"),
    -- ...
}
```

### Spacing & visual grouping

- One blank line between groups.
- Settings inside a group sit consecutively, no blank lines between paired `setting` / `setting_tooltip` rows.
- Section banner comments (`-- =====` style) help when the file grows past ~50 entries.

### `en("...")` helper vs `{ en = "..." }` longhand

Both are fine. Pick one per file and stick with it:

- `modded_progression`, `verminious_dreams_lighting` use the `local function en(s)` helper.
- `general_tweaker`, `buff_tweaker`, `weapon_tweaker`, `enemy_tweaker` use the `{ en = "..." }` longhand.

The helper saves keystrokes for tooltip-heavy mods. The longhand is fine for short files.

### Multi-line strings

For long tooltips, the engine accepts either Lua-string newline escapes (`\n`) or string concatenation. Most mods inline `\n`:

```lua
inject_adventure_maps_tooltip = { en = "EXPERIMENTAL. Adds adventure missions to the random TRAVEL/SIGNATURE pool of every Chaos Wastes journey...\n\nUse Available Missions to toggle Chaos Wastes scenarios...\n\nHost-only. Requires game restart to take effect." },
```

---

## 5. The `_lz()` wrapper pattern (optional)

Some mods define a helper for terseness inside complex widget trees:

```lua
local function _lz(key, fallback)
    local s = mod and mod.localize and mod:localize(key)
    if not s or s == "" or s:sub(1, 1) == "<" then return fallback end
    return s
end
```

(`lobby_tweaker/scripts/mods/lobby_tweaker/_failed_join_reveal.lua:29-35` — the only confirmed in-repo use.)

It is **OPTIONAL**. The bare `mod:localize("key")` form is fine and is what most mods use. The fallback variant is useful when missing localization would render bracket-noise (e.g. `<failnotify_title>`) inside a popup label.

### IMPORTANT: `_lz()` HIDES references from grep

The orphan-key audit (Section C P2) grep-walks every `.lua` file for `mod:localize("key")` literals. Keys that flow through `_lz(...)` look like orphans in that report — false positives. **Section C explicitly notes this caveat** (lines 66-72).

If a mod uses `_lz()`, its orphan-key list is unreliable. Either:

- Drop the `_lz()` wrapper and call `mod:localize` directly, OR
- Document the wrapper at the top of the file and treat orphan reports for that mod as advisory only.

For most mods the call-site terseness gain is marginal; the audit-clarity loss is real. **Recommendation: avoid `_lz()` unless you have a concrete need for the fallback-on-missing behavior.**

---

## 6. Missing-key behavior

When `_data.lua` references a key that doesn't exist in `_localization.lua`:

- For setting widget IDs / tooltip IDs / group IDs: VMF renders the **raw setting_id string** in the UI. No crash. Just looks ugly (e.g. `mod_description` appears literally as `mod_description` in the panel header).
- For explicit `mod:localize("key")` calls: VMF returns the string `<key>` (with angle brackets).

**Implication:** missing keys are silent. Always spot-check the rendered VMF panel for any mod whose `_data.lua` has been edited. If you see a raw `setting_id` rendered, that's the symptom.

Section C P1 caught 8 of these (one resolved in Fix 4, 7 remain — see audit for the list). The fix is mechanical: add the missing entry to `_localization.lua`.

---

## 7. Encoding — UTF-8 without BOM

All localization files MUST be saved as **UTF-8 without BOM**.

- Stingray's Lua loader handles BOM-less UTF-8 fine.
- Every localization file in the monorepo is currently BOM-less (verified Section C, lines 134-152).
- The BOM is NOT required, but mixing files (some BOM, some not) makes diff/grep noisy.

### PowerShell 5.1 gotcha — `Get-Content -Raw` defaults to Windows-1252

PS 5.1's `Get-Content -Raw` does NOT default to UTF-8 — it uses Windows-1252 and silently mangles em-dashes, bullets, accented characters, smart quotes. Full recipe in `tools/vmb-launcher/CLAUDE.md § PowerShell 5.1 Get-Content -Raw is NOT UTF-8`. If a tool script needs to read a localization file from PS 5.1, use the explicit decode pattern:

```powershell
$text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
```

PS 7+ defaults to UTF-8 and is fine. The repo's `_tools/` scripts should use the explicit decode pattern regardless, since contributors may invoke them under either shell.

---

## 8. Migration plan — current conformance & next steps

### Mods currently conforming (post-Fix 1, 2026-05-21)

| Mod | mod_description present | `%` escaping clean | `_tooltip` convention | Uses `_lz()` wrapper |
|-----|:-:|:-:|:-:|:-:|
| `buff_tweaker` | YES | YES | YES | no |
| `general_tweaker` | YES | YES | YES | no |
| `weapon_tweaker` (post 0.12.63-dev) | YES | YES (Fix 1) | mixed `_tooltip`/`_description` | no |
| `lobby_tweaker` (post 0.1.1-dev) | YES | YES (Fix 1) | YES | yes (in `_failed_join_reveal.lua`) |
| `verminious_dreams_lighting` | YES | YES | YES | no |
| `la_prefix_patch` | YES | YES | YES | no |
| `enemy_tweaker` | YES | YES | YES | no |
| `chaos_wastes_tweaker` | YES | YES | YES | no |
| `career_tweaker` | YES | YES | YES | no |
| `modded_progression` (post Fix 4) | YES | YES | YES | no |

### Mods needing migration

Per Section C P1, these have missing `mod_description` or other missing keys:

- `event_tweaker` — missing `mod_description`
- `material_hijack_patched` — missing `mod_description`
- `modded_progression` — missing several keys (RESOLVED in Fix 4 for `starting_state_description`; verify others)
- `verminious_dreams_lighting` — missing `mod_description` (Section C reported; verify post-Fix 4 since AUDIT_2026_05_21.md says claim may be stale)

### Mods with high orphan-key counts (Section C P2)

- `career_tweaker` (363 orphans)
- `chaos_wastes_tweaker` (788 orphans)
- `weapon_tweaker` (59 orphans)
- `cosmetics_tweaker` (12 orphans)
- `enemy_tweaker` (13 orphans)

Most of these are likely false positives from `_data.lua` implicit-resolution paths the audit doesn't fully walk. Do NOT bulk-delete. Cleanup is a per-mod investigation, post-migration.

### Phased migration (recommended order)

1. **Phase 1 — P1 missing keys** (cheap, no risk). Add `mod_description` and any other audited missing keys to the offending mods.
2. **Phase 2 — `_description` → `_tooltip` rename** (mechanical, larger scope). Rename every `<setting_id>_description` to `<setting_id>_tooltip` in `weapon_tweaker`, `crafting_in_modded`, etc. so VMF's auto-resolution works without the data file having to pass `description = "..."` explicitly. Coordinate with the corresponding `_data.lua` edits.
3. **Phase 3 — `_lz()` wrapper retirement** (optional, low value). Convert `lobby_tweaker/_failed_join_reveal.lua` to direct `mod:localize` calls so the orphan-key audit becomes reliable for that mod.
4. **Phase 4 — orphan-key sweep** (post-Phase 2 only). Once `_description`→`_tooltip` is settled, re-run the audit. Delete confirmed orphans per-mod. Expect 50-80% of current "orphans" to evaporate after Phase 2.

**Do NOT migrate as part of this doc's commit.** This file establishes the standard. Migration is follow-up work to be tracked in `AUDIT_2026_05_21.md`'s P1 list.

---

## 9. Quick checklist for new localization strings

Run this every time you add or edit an entry in any `_localization.lua` file:

```
[ ] Every literal `%` in the string is doubled to `%%`?
[ ] Any format directives (`%d`, `%s`) match one of the two documented call-site patterns (Pattern A: pre-format + outer string.format; Pattern B: concat, no directives in localization)?
[ ] Setting key matches the widget's setting_id in _data.lua, and tooltip key is exactly `<setting_id>_tooltip`?
[ ] File is saved as UTF-8 without BOM?
[ ] If this is a new mod, `mod_description` is defined?
```

If any line is unchecked, fix before committing. The cost of a missed `%` in a tooltip is a `<<crashify-exception>>` spam burst the next time the panel renders, plus a half-day audit hunting it down.

---

## 10. Mutex cluster pattern — single-select from N alternatives

VMF has no native radio / multiple-choice widget. `dropdown` truncates the visible label inside the closed widget, has no per-option tooltip, and supports only short `text` strings. When you need "pick one of N alternatives" with full localized labels and full multi-line tooltips per choice — the canonical case is **`rework_*` (Tweaker's version) vs `cbr_*` (Big Rebalance's version) of the same talent** — use a **mutex checkbox cluster** instead.

### The pattern

Each alternative is a normal `checkbox` (full label + multi-line `_tooltip`). A small enforcer in `on_setting_changed` programmatically un-ticks the siblings when one is ticked on. All defaults are `false` so the all-off state means vanilla / no rework active.

Helper module at `career_tweaker/scripts/mods/career_tweaker/career_tweaker_mutex.lua` — see the doc-block at the top of that file. The pattern is currently ct-only; copy verbatim into a sibling mod when needed (it's ~80 lines and dependency-free).

### Declaring a cluster (call site in the main mod file)

```lua
local mutex = mod:dofile("scripts/mods/<mod>/<mod>_mutex")

mutex.declare("bh_passive_choice", {
    "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
    "cbr_bh_passive_perks_rework",
})
```

Call from module load. `group_id` is a short logical name (used only for diagnostics + logs). `members` is the array of `setting_id` strings; ≥ 2 required.

### Wiring the enforcer

```lua
mod.on_setting_changed = function(setting_id)
    mutex.enforce(setting_id)  -- runs BEFORE the apply dispatch
    -- ... your existing dispatch (apply / restore / refresh UI / etc.)
end
```

The enforcer:
- No-ops if `setting_id` is not in any declared cluster.
- No-ops if the new value is `false` (= back to vanilla; nothing to deselect).
- Otherwise iterates the cluster and `mod:set(other, false)` for each sibling currently on. A re-entry guard inside `enforce` keeps the recursive `on_setting_changed` cascade bounded to one level.

### Label convention — `(A)` / `(B)` / `(C)` prefix with 4-space leading indent

VMF doesn't render checkboxes any differently when they're in a mutex cluster vs being independent toggles. To make the multiple-choice relationship visually obvious to the player, **every cluster member's display label MUST use this exact prefix format**:

```
    (A) <short choice name>
    (B) <short choice name>
    (C) <short choice name>
```

Rules:
- **Leading indent**: exactly 4 spaces. Makes the cluster members visually sit "under" the surrounding group header — like nested options in a multiple-choice quiz.
- **Parenthesized letter**: `(A)`, `(B)`, `(C)`, etc. Single uppercase letter, no period after the close-paren.
- **Single space** between the close-paren and the choice name.
- **Choice name**: 1-7 words. Should read fine standalone; the prefix carries the cluster context.

Live example (ct 0.7.85-alpha `isha_choice`):

```lua
tweak_miracle_of_isha_aegis  = { en = "    (A) Aegis: -25%% damage taken for the rest of the run" },
tweak_miracle_of_isha_wounds = { en = "    (B) Unlimited Wounds: recruit-style, every knockdown revivable" },
```

Live example (crt 0.3.5-dev `bh_passive_choice`):

```lua
rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr = { en = "    (A) BH passive: Job Well Done innate +5%%/stack DR" },
cbr_bh_passive_perks_rework                                      = { en = "    (B) BH passive: perks rework (Big Rebalance)" },
```

### Widget tooltips — surface the relationship

The cluster members can live anywhere in the widget tree (the enforcer doesn't care about visual nesting). But the UI gives no visual cue that the checkboxes are mutually exclusive — so every cluster member's `_tooltip` MUST open with a one-line "alternative to X" hint that names the cluster size + this member's letter. Convention:

```
<cluster name> — choice (A) of (B). Alternative to '(B) <other-letter-and-label>' — these are
mutually exclusive (toggling either one off-checks the other; both off = vanilla).
<Rest of the per-alternative description.>
```

Live example (ct 0.7.85-alpha `isha_choice`):

```lua
tweak_miracle_of_isha_aegis_tooltip = {
    en = "Miracle of Isha — choice (A) of (B). Alternative to '(B) Unlimited Wounds' — these are mutually exclusive (toggling either one off-checks the other; both off = vanilla revive-once behavior).\n\nEvery hero takes -25%% damage for the rest of the run after Blessing of Isha is picked up at the shrine.\n\nHost-authoritative. Vanilla revive mutator is fully disabled when this is on."
},
```

### Member naming order

Lock the letter assignment to **chronological order of when the alternatives were added**, not alphabetical or any other ordering. The first-shipped alternative is (A), the next is (B), and so on. This avoids label churn (and migrating settings) when a future mod adds a third alternative — the new option just becomes `(C)`, no relabeling needed.

### When to use a mutex cluster vs a dropdown

- **Use cluster** when alternative descriptions are long enough that dropdown `text` would truncate, or when you want each alternative to surface its own tooltip on hover.
- **Use dropdown** when the alternatives are 1-4 short words ("Off / Low / Medium / High") and a single shared widget-level tooltip is enough.

### When NOT to use a cluster

- For purely additive toggles (both can sensibly be on). Use independent checkboxes.
- For numeric tunings (e.g. crit chance %). Use `numeric`.

### Diagnostic API

The helper exposes two introspection calls for `/<mod>_status`-style commands:

- `mutex.active(group_id)` — returns the active member's setting_id, or nil if all members are off (= vanilla).
- `mutex.snapshot()` — returns the full `{ group_id = active_member_or_nil }` map.

---

## Cross-references

- [`AUDIT_section_c.md`](./AUDIT_section_c.md) — full localization sweep with the P0/P1/P2/P3 findings this standard is built around.
- [`AUDIT_2026_05_21.md`](./AUDIT_2026_05_21.md) — master audit; "Documentation gaps surfaced" section lists the gaps this doc closes.
- Memory: `feedback_ps5_getcontent_utf8.md` — UTF-8 / PowerShell 5.1 reading.
- `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua` — canonical reference for trait-description `%%` escaping (post Fix 1).
- `lobby_tweaker/scripts/mods/lobby_tweaker/lobby_tweaker_localization.lua` — canonical reference for Pattern A pre-format directives (`%%d` in localization, `string.format` at call site).
- `general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua` — canonical reference for clean conventional formatting (`_tooltip` suffix, group/setting layout, mod_description).
- `buff_tweaker/scripts/mods/buff_tweaker/buff_tweaker_localization.lua` — minimal example for new mods.
