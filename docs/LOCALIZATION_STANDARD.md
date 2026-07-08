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

`gt` 0.2.35's CHANGELOG was the first place this rule was documented in the repo, after the same class of bug appeared in a percentage string. That note was per-mod and got missed when `wt` and the lobby failed-join strings (originally in the now-retired `lobby_tweaker`, since absorbed into `general_tweaker`) later authored the same shape of string — hence this central doc.

### Recurring offender — environment variable references (`%APPDATA%`, `%USERNAME%`, etc.)

The most common second-time-burn is referencing a Windows env var by name inside a tooltip. **Every `%FOO%` token must be written as `%%FOO%%`** because Lua's `string.format` reads the first `%` as a format directive opener — `%A` (in `%APPDATA%`) is the directive `A` which is undefined and raises `invalid option '%A' to 'format'`. The user sees a red error tooltip on hover.

```lua
-- WRONG -- VMF tooltip render path raises "invalid option '%A' to 'format'"
enable_debug_logging_tooltip = { en = "Logs to %APPDATA%\\Fatshark\\Vermintide 2\\console_logs\\." },

-- RIGHT
enable_debug_logging_tooltip = { en = "Logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\." },
```

**Burned again 2026-05-25** across all 16 mods (every `enable_debug_logging_tooltip` shipped with literal `%APPDATA%`). Triggered the multi-layer defense below.

### Defense layers

The repo enforces this rule at four points:

1. **Static lint** — `qa/check_localization.ps1` walks every `*_localization.lua` file and reports unescaped `%` in loc values. Exit code 2 = errors. Runs automatically as part of the pre-commit hook (via `qa/run_all.ps1`).
2. **Build-time doctrine** — `tools/vmb-launcher/CLAUDE.md` § "Run `qa/check_localization.ps1` before declaring any localization edit complete" — agents are required to run the static check explicitly any time they touch a loc file, even if not committing.
3. **Runtime regression test** — each mod's `_rt_register("localization_format_safe", ...)` check (in `<mod>.lua`) dofiles the loc table and `pcall(string.format, value)` on each entry. Run via `/<mod>_regression_test` chat command. Catches drift even when the static check is skipped.
4. **Bug class catalog** — `docs/BUG_CLASSES.md` lists this as a known repeat-offender pattern. New bug reports matching the symptom (red error tooltip on a VMF settings hover) should pattern-match here first.

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

This is exactly the bug the lobby failed-join reveal shipped pre-Fix 1 (originally in `lobby_tweaker`, now in `general_tweaker`'s `_gt_lobby_failed_join_reveal.lua`): `"You are missing %d mods required by the host:"` was being passed through both VMF and an outer `string.format`. Fixed by escaping to `%%d` in the localization so VMF renders the literal `%d`, then the caller's `string.format` interpolates it.

### Two valid patterns

**Pattern A — pre-format directive, escape in localization, format at call site (RECOMMENDED for short interpolations)**

```lua
-- localization
gt_lobby_failnotify_required_header = { en = "You are missing %%d mods required by the host:" },

-- call site
local n = #missing
local header = string.format(mod:localize("gt_lobby_failnotify_required_header"), n)
```

This is what `general_tweaker`'s lobby failed-join reveal uses post-Fix 1 (`general_tweaker_localization.lua:398`, consumed at `_gt_lobby_failed_join_reveal.lua:188-189`). It was absorbed from the now-retired `lobby_tweaker`.

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

### Tooltips — pass a RAW loc key in `tooltip`; `_tooltip` suffix (naming convention)

**CORRECTED 2026-07-01 (verified against the live VMF bundle's `core/options.lua` bytecode + upstream source).** VMF localizes the widget's `tooltip` field **itself** at options-menu build time (`options.localize` defaults to `true`, and `localize_generic_widget_data` runs `mod:localize()` on `title`/`tooltip`/dropdown option `text`/numeric `unit_text`). Two consequences:

1. **The `tooltip` field must be a RAW key string** (`tooltip = "tp_camera_enabled_tooltip"`). **NEVER write `tooltip = mod:localize("...")` in a `_data.lua` widget** — the pre-localized English comes back, VMF then re-localizes that whole sentence as a key, misses, and the menu renders the sentence wrapped in `<...>`. This double-localize was the repo-wide source of the `<>` markers around option descriptions (fixed in the 2026-07-01 sweep). Same rule for widget `title`, dropdown option `text`, and `unit_text`. The ONE legitimate eager localize in a data file is the top-level mod `description = mod:localize("mod_description")` — VMF does not re-localize that field.
2. **The auto-resolved fallback suffix is `_description`, not `_tooltip`.** When a widget has NO `tooltip` field, VMF tries `quick_localize(setting_id .. "_description")` and silently shows nothing if missing (no marker). The earlier version of this doc had this backwards.

Naming convention for explicitly-passed keys stays `_tooltip`:

```lua
-- _data.lua
{ setting_id = "tp_camera_enabled", type = "checkbox", tooltip = "tp_camera_enabled_tooltip", ... }

-- _localization.lua
tp_camera_enabled         = { en = "Enable Third-Person Camera" },
tp_camera_enabled_tooltip = { en = "Toggle third-person camera view. Can also be toggled in-game with the 'gt tp' chat command." },
```

Existing `_description` keys (weapon_tweaker, crafting_in_modded have hundreds) are fine where the widget omits `tooltip` — they ride the auto-resolve. Don't mass-rename in either direction.

### Group labels

Same as the widget's `setting_id`. Convention: groups suffix `_group`:

```lua
tp_camera_group = { en = "Third-Person Camera" },
gameplay_group  = { en = "Gameplay" },
```

### Required keys for every mod

- `mod_description` — top-level mod blurb shown by VMF in the mod-options panel header. Every mod MUST define this.
- `mod_name` — optional but recommended; some mods use it for the panel header. (`career_tweaker`, `chaos_wastes_tweaker` define it; `general_tweaker`, `modded_progression`, `verminious_dreams_lighting`, `enemy_tweaker` rely on the mod-id alone. The retired `buff_tweaker` / `lobby_tweaker` — now under `_archive/` — were previously cited here.)

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
- `general_tweaker`, `weapon_tweaker`, `enemy_tweaker` use the `{ en = "..." }` longhand.

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

(`general_tweaker/scripts/mods/general_tweaker/_gt_lobby_failed_join_reveal.lua:44` — the only confirmed in-repo use; this lobby failed-join reveal was absorbed from the now-retired `lobby_tweaker`, whose `_failed_join_reveal.lua` originally held it.)

It is **OPTIONAL**. The bare `mod:localize("key")` form is fine and is what most mods use. The fallback variant is useful when missing localization would render bracket-noise (e.g. `<failnotify_title>`) inside a popup label.

### IMPORTANT: `_lz()` HIDES references from grep

The orphan-key audit (Section C P2) grep-walks every `.lua` file for `mod:localize("key")` literals. Keys that flow through `_lz(...)` look like orphans in that report — false positives. **Section C explicitly notes this caveat** (lines 66-72).

If a mod uses `_lz()`, its orphan-key list is unreliable. Either:

- Drop the `_lz()` wrapper and call `mod:localize` directly, OR
- Document the wrapper at the top of the file and treat orphan reports for that mod as advisory only.

For most mods the call-site terseness gain is marginal; the audit-clarity loss is real. **Recommendation: avoid `_lz()` unless you have a concrete need for the fallback-on-missing behavior.**

---

## 6. Missing-key behavior

When `_data.lua` references a key that doesn't exist in `_localization.lua` (**corrected 2026-07-01** — verified against live VMF bytecode):

- Widget titles (the `setting_id` / explicit `title` key) and explicit `tooltip` keys: VMF runs them through `mod:localize()` at menu build, so a missing key renders **`<key>` with angle brackets** frozen into the widget.
- The auto-resolved `<setting_id>_description` fallback (widget with no `tooltip` field) uses `quick_localize`, which returns nil on a miss — the row simply has **no tooltip**, no marker.
- Any explicit `mod:localize("key")` call elsewhere returns the string `<key>` (with angle brackets).

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

> **[SUPERSEDED 2026-07-07]** `buff_tweaker` and `lobby_tweaker` are RETIRED (now under `_archive/buff_tweaker_v0.1.12-alpha/` and `_archive/lobby_tweaker_v0.1.7-dev/`). `lobby_tweaker`'s failed-join reveal (the only `_lz()` user) was absorbed into `general_tweaker`, so the `_lz()` = yes marker moved to that row. Rows kept below for history and annotated inline.

| Mod | mod_description present | `%` escaping clean | `_tooltip` convention | Uses `_lz()` wrapper |
|-----|:-:|:-:|:-:|:-:|
| `buff_tweaker` (RETIRED — archived) | YES | YES | YES | no |
| `general_tweaker` | YES | YES | YES | yes (in `_gt_lobby_failed_join_reveal.lua`) |
| `weapon_tweaker` (post 0.12.63-dev) | YES | YES (Fix 1) | mixed `_tooltip`/`_description` | no |
| `lobby_tweaker` (RETIRED — absorbed into `general_tweaker`) | YES | YES (Fix 1) | YES | yes (was `_failed_join_reveal.lua`; now gt's `_gt_lobby_failed_join_reveal.lua`) |
| `verminious_dreams_lighting` | YES | YES | YES | no |
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
3. **Phase 3 — `_lz()` wrapper retirement** (optional, low value). Convert `general_tweaker`'s `_gt_lobby_failed_join_reveal.lua` (the `_lz()` user, absorbed from the retired `lobby_tweaker`) to direct `mod:localize` calls so the orphan-key audit becomes reliable for that mod.
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
[ ] If a label is COMPUTED from another loc entry (dynamic menu), it reads the raw loc DATA, not `mod:localize`, and not a parallel hardcoded name map (see § 12)?
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

## 11. Style — match vanilla VT2 terseness

The rules above keep localization files *correct* (no `<<crashify-exception>>` spam, no missing keys, no double-`string.format`). This section keeps them *readable*. Vanilla VT2's tooltips, talent text, and boon text are uniformly **short, present-tense, and free of meta-language**. Mod menus that drift away from that style read as bloated and chaotic next to the base game.

### 11.1 — Setting titles (the toggle / slider / dropdown label)

- **≤ 6 words.** Longer than that is a tooltip, not a label.
- **Sentence case.** Not Title Case. Not ALL CAPS.
- **No trailing period.** Labels are not sentences.
- **Active verb if the setting performs an action** — "Boost Throwing Axes", "Disable Quest Markers".
- **Noun phrase if the setting is a property** — "Altar Distribution", "Coin Multiplier", "Starting State".

| Bad | Why | Good |
|-----|-----|------|
| `"Toggle whether or not you want to enable the third-person camera feature"` | Meta-language; sentence-as-label | `"Enable third-person camera"` |
| `"Repeater Handgun maximum ammo boost setting"` | Trailing noise ("setting") | `"Boost Repeater Handgun max ammo"` |
| `"This option controls the multiplier for shilling drops."` | Meta-language; full sentence | `"Shilling multiplier"` |

### 11.2 — Setting tooltips (the `_tooltip` body shown on hover)

- **≤ 2 sentences. ≤ 30 words total.** If you need more, you're explaining a system; cite the relevant doc in the CHANGELOG instead.
- **Present-tense or imperative.** "Heals slightly when killing an enemy with melee." NOT "When you kill an enemy with a melee weapon, you will heal a small amount."
- **No meta-language.** Never start with "This option / toggle / setting / feature does..." — say what it does directly. The fact that it's a setting is implied by where it appears.
- **Magnitudes go inline.** `x1.5 damage`, `12 → 18 ammo`, `+15%% vs armoured` — not "a significant increase" or "a larger amount".
- **Host-only / restart-required caveats** go in a second sentence, NOT a parenthetical clause inside the main one. Keep them terse: "Host-only.", "Requires game restart."

| Bad | Why | Good |
|-----|-----|------|
| `"When this option is enabled, players will be able to access an additional category of crafting recipes that allow them to upgrade their weapons further."` | Meta-language preamble; vague magnitude | `"Adds upgrade recipes to the forge. +1 power tier per upgrade."` |
| `"Toggle whether or not you want to enable the feature that boosts the maximum amount of ammo for the Repeater Handgun (default 12, with this on it's 18)."` | "Toggle whether..." preamble; parenthetical magnitude | `"Boosts Repeater Handgun max ammo: 12 → 18."` |
| `"This is a slider that controls the multiplier for the amount of coins dropped from chest pickups in the Chaos Wastes."` | "This is a slider..." preamble | `"Coin multiplier for chest pickups."` |

### 11.3 — Boon / Talent descriptions (overriding vanilla mechanics)

When a mod replaces or extends a vanilla boon / talent / trait, the description MUST match vanilla style — players compare them side-by-side with stock entries.

- **≤ 2 sentences.** Factual mechanical detail, magnitudes inline.
- **No flavor text** unless the vanilla entry for the same category has flavor text. Stock boon descriptions are dry mechanical lines; stock career-class blurbs have flavor. Match the neighbor.
- **Imperative or present tense.** "Replace your ult with X." / "Heal slightly when..." / "Gain X stacks for Y seconds on Z."
- **Magnitudes inline** — `+15%%`, `5 seconds`, `x2`. No "slightly" / "significantly" / "a lot".

Vanilla examples (canonical phrasings — match this voice exactly):

- Sister of the Thorn ult "Briarwall": *"Replace your ult with Briarwall — places a thicket of vines that blocks enemy movement and slowly damages enemies within."*
- Heal-on-melee-kill boon family: *"Heal slightly when killing an enemy with a melee attack."*
- Resourceful Combatant trait: *"Critical hits reduce the cooldown of your career skill by 1 second. 1 second cooldown."*

### 11.4 — Group / section headings

- **1-4 words.** Anything longer is a description, not a heading.
- **Title Case if 2+ words** — "Big Rebalance", "Chaos Wastes Economy", "Altar Distribution".
- **No punctuation.** No trailing `:` or `.`.

### 11.5 — Dropdown / checkbox option labels

- **≤ 3 words usually.** Sentence case.
- **Single-word options preferred** when they parse: "Off / Low / Medium / High / Extreme".
- **No magnitude inside the option label** — the magnitude goes in the tooltip, not the dropdown row. Exception: numeric-only dropdowns where the magnitude IS the label (`"1.5x"`, `"2.0x"`).

### 11.6 — Anti-patterns (do not ship)

These three patterns must never appear in a new or rewritten entry. Find-and-replace if any survive:

1. **Meta-language preamble.** Any string that opens with `"This option..."` / `"This toggle..."` / `"This setting..."` / `"Toggle whether..."` / `"When this is enabled..."` / `"With this on..."`. Say what it does, not that it's a thing that does things.
2. **Vague magnitudes.** "Slightly", "significantly", "a lot", "much more", "a small amount of". Replace with the actual number.
3. **Trailing noise nouns.** Labels ending in `... feature`, `... setting`, `... option`, `... mode`, `... functionality`. The widget chrome already conveys "this is a setting".

### 11.7 — Preserved when tightening

When rewriting an existing entry to match this section:

- **Preserve magnitude numbers** (every `%%`, `x1.5`, `+15`, `12 → 18`). Tightening must not strip mechanical accuracy.
- **Preserve mechanical claims.** "Host-authoritative." stays. "Requires game restart." stays. "Mutually exclusive with `(B) ...`" stays (see § 10 for the mutex-cluster header).
- **Preserve key references.** If a tooltip names a specific in-game term (an item key, a talent name, a chat command), keep it verbatim — those are searchable handles.

### 11.8 — Quick checklist for tightening passes

Run this every time you rewrite or audit an existing entry:

```
[ ] ≤ 6 words for setting title, ≤ 30 words for tooltip, ≤ 4 words for group heading?
[ ] No "This option/toggle/setting/feature..." preamble?
[ ] Imperative or present tense (no "will" / "you can" / "when you do X, Y happens")?
[ ] Vague magnitudes ("slightly", "much more") replaced with the real number?
[ ] Mechanical claims preserved (host-only, restart-required, magnitudes, mutex tooltips)?
[ ] Trailing period dropped from labels (kept in 2-sentence tooltips)?
```

---

## 12. Dynamically-resolved menu labels — read raw loc DATA, never `mod:localize` during registration

Most labels are static `{ en = "..." }` entries. But some menus compute a label at
build time from another loc entry — e.g. the `weapon_tweaker` dev anim picker derives
each weapon group's label ("Sienna: Coruscation Staff rendered on Kruber body") from the
**documented** `unlock_<career>_<weapon>` name, so the picker and the Weapon Availability
menu can never disagree (the single-source-of-truth rule — see memory
`feedback_use_documented_localized_names`). Two hard rules apply, both learned the hard way.

### 12.1 — Resolve from the loc, NEVER from a parallel hardcoded map

A menu that shows item/weapon/career names must derive them from the localization
(the single source of truth), not a second hand-maintained `{ key = "Name" }` table.
The parallel map silently goes stale: when seven Sienna staves were added but not
added to the picker's hardcoded `_WEAPON_NAME`, the picker fell back to raw keys
(`Sienna bw_deus_01`) and a tester couldn't tell what the weapon was (wt #159). Keep a
hardcoded map ONLY as a last-resort fallback, and make the fallback a source-qualified
key — **never surface a bare internal key**.

### 12.2 — Do NOT call `mod:localize` from any path that runs DURING loc registration

This is the load-order trap that burned wt **#197** (a 27× error flood + the names
silently not resolving):

- VMF registers a mod's localization only when its `_localization.lua` `return`s its
  table. Any code that runs **before** that — i.e. *during* the loc file's own
  execution — cannot use `mod:localize` for that mod's own keys.
- The classic trigger: the loc file `mod:dofile`s a dev/feature module and calls its
  `loc_keys()` from inside its own body (to merge dynamic keys). That `loc_keys()` (and
  any catalog/label build it does) runs **pre-registration**. A `mod:localize` call
  there logs **`[MOD][<id>][ERROR] (localize): localization file was not loaded for this
  mod`** once per call AND returns nothing usable — so the computed labels silently fall
  back to raw keys, and the labels VMF actually registers are the wrong ones.
- **The fix: read the raw loc DATA table directly.** Publish it on the mod object before
  dofiling the consumer, and have the consumer read the entry:

  ```lua
  -- in <mod>_localization.lua, BEFORE it dofiles the consumer + calls loc_keys():
  mod._wt_loc_raw = loc

  -- in the consumer's label resolver (NO mod:localize):
  local entry = mod._wt_loc_raw and mod._wt_loc_raw["unlock_" .. career .. "_" .. weapon_key]
  if type(entry) == "table" and entry.en then
      return (entry.en:gsub("^%s*%b[]%s*", ""))   -- strip any computed "[...]" status tag
  end
  ```

  The raw read has no load-order dependency. Note the published table is the SAME
  reference the loc file may later mutate in place (e.g. a status-tag post-process loop),
  so reads after that see tags — strip them.

### 12.3 — Tests that guard this (wt `/wt_regression_test`)

A test that *rebuilds* a label and checks it is NOT enough: it runs in-game (loc
registered), so `mod:localize` works there and the registration-time bug stays hidden.
Test the **registered value** VMF actually renders:

- `dev_picker_group_labels_registered` — for each menu group, asserts `mod:localize(group_sid)`
  resolves to a real label (not the raw weapon key, not an unregistered `<key>`/bare sid).
  This is the one that would have caught #197.
- `wt_loc_raw_published` — asserts the loc file still publishes `mod._wt_loc_raw` with the
  expected entries (guards the load-bearing dependency).
- `dev_picker_names_localized` — the freshly-rebuilt-label check (catches the resolver
  itself regressing).

Memory: `reference_vmf_localize_before_registration`, `feedback_use_documented_localized_names`.

---

## 13. Dev status tags (issue #301)

Origin: GitHub issue #301 ("New Doctrine on Issues/Localization!"). **Dev builds** carry
a short status tag as a PREFIX of each option's `en` title string so the user can see,
right in the in-game VMF options panel, which features still need testing, which have open
issues, and which are presumed working. Tags are a live-status surface, not decoration —
they get rewritten in the same pass whenever an issue is opened/closed, diagnostics are
armed/removed, or a feature is added/overhauled.

**Tags exist ONLY in dev builds.** A dev build is one whose `MOD_VERSION` carries a
pre-release suffix (`-dev` / `-alpha` / `-beta` / `-rc<N>`). Clean-versioned public/stable
releases (no suffix) carry NO tags — see § 13.5.

### 13.1 — Tag vocabulary (the seven sanctioned tags)

Exact spelling and casing as listed — lowercase tags, capital `I` in `[Issue N]` — so
grep/QA tooling can find them. Never invent a new tag.

| Tag | Meaning | Removed / replaced when |
|---|---|---|
| `[untested]` | Brand new (or significantly overhauled) feature not yet confirmed working in-game. | The user confirms it works (→ `[working]`), or an issue emerges (→ `[Issue N]`). |
| `[Issue N]` | An open issue relates to the feature (bug or not). E.g. `[Issue 491]`. | The issue closes (tags updated in the SAME session). |
| `[working]` | No open issues; presumed working. | The feature changes significantly (→ `[untested]`) or an issue touching it opens (→ `[Issue N]`). |
| `[diag]` | Diagnostic logging is in place for the feature (almost always paired with an open issue). | The diagnostics are removed. |
| `[crash]` | Feature has open issue(s) investigating a crash it may have caused. | No such open crash issue remains. |
| `[verify-fix]` | A potential fix is in place and must be verified in-game. Co-occurs with the `[Issue N]` of the issue being verified. | The fix is confirmed (→ `[working]`) or fails (stays `[Issue N]`). |
| `[needs animations]` | **`weapon_tweaker` weapon-availability entries only** — the item lacks 3rd-person animations. Should pair with either an open issue to add it to the dev animation picker, or its presence in the picker. | The item gets 3P animations wired. |
| `[needs animations → <target>]` | **wt-only extension** (§ 13.8). The `[needs animations]` variant that also names the mapped target receiver whose 3P anims the port borrows, e.g. `[needs animations → Greathammer]`. Emitted at load, not hand-authored. | Same as `[needs animations]`. |
| `[needs offsets]` | **wt-only extension** (§ 13.8). The 3P port renders but its grip offsets are still missing. Emitted at load, not hand-authored. | The grip offset is baked. |

The last two rows are `weapon_tweaker`-only extensions; see § 13.8 for the runtime emitter
that owns them. `qa/check_loc_tags.ps1` accepts all nine forms.

**Mutually exclusive:** `[crash]`, `[working]`, `[untested]` are mutually exclusive — a
feature is exactly one of "presumed working", "brand-new/untested", or "under crash
investigation" at a time. Never combine two of these three.

### 13.2 — Multiple tags and multiple issue numbers

- **Multiple tags** on one option are allowed, space-separated, e.g.
  `[untested] [Issue 497]` or `[verify-fix] [Issue 491]` (the `[verify-fix]` case should
  always name its issue).
- **Multiple issue numbers inside ONE `[Issue ...]` tag** use these exact formats:
  - Two: `[Issue 501 & 427]`
  - Three or more: `[Issue 501, 427 & 418]` (comma-separated, final pair joined by `&`).

### 13.3 — Placement and formatting

- **Prefix of the `en` title string.** Each tag in its own square brackets, a single space
  between consecutive tags, and a single space between the last tag and the display name:

  ```lua
  noclip_enabled = { en = "[working] Noclip" },
  gt_ai_afk_takeover = { en = "[Issue 247] AFK Bot Takeover" },
  gt_bot_behavior_improvements = { en = "[Issue 297, 300, 139 & 142] Bot Behavior Improvements" },
  ```

  This matches the existing convention in `general_tweaker_dev`.
- **Tag ONLY option TITLE strings** — entries whose loc key matches a widget `setting_id`
  in the mod's `_data.lua`, INCLUDING group / master-toggle widget titles. Never tag:
  tooltip / description bodies (`*_tooltip`, `*_description`), dropdown value labels, chat /
  log / popup message strings, or pure text entries with no backing widget.
- **Tags live only in the localization DATA file**, as raw authored strings — never
  pre-localized (§ 12.2), no em dashes, `%` escaped as `%%` (§ 1). All existing repo loc
  rules still apply.
- **Every feature / menu option in a dev build should carry a tag.** New or overhauled
  feature ⇒ `[untested]`; otherwise `[working]` (or the relevant issue/diag/crash tag).
  Two exemptions (§ 13.8): pure navigation container groups, and known issue clusters with
  no menu widget to hang a tag on. Inert blocks take their tracking `[Issue N]` (§ 13.8).

### 13.4 — Tags are updated in the same pass as the change

Tags are a live status surface, so they move whenever the underlying state moves — and that
update happens in the SAME session/commit as the triggering change, never batched for later:

- **Opening an issue** that touches a feature ⇒ add `[Issue N]` (and drop `[working]`).
- **Closing an issue** ⇒ remove its number from the feature's `[Issue ...]` tag and re-tag
  appropriately (`[working]`, or `[untested]` if still unverified). This repo already has a
  "test every closed issue" rule — updating the tag is part of closing.
- **Arming / removing diagnostics** ⇒ add / drop `[diag]`.
- **Landing a candidate fix** ⇒ add `[verify-fix]` (keep `[Issue N]`); on in-game
  confirmation, drop both for `[working]`.
- **Adding or significantly overhauling a feature** ⇒ `[untested]`.

`[Issue N]` must reference an OPEN issue in `Ensrick/vermintide-2-tweaker`. A tag naming a
closed issue is stale and must be corrected.

**Mechanized (issue #326):** `qa/check_issue_tag_sync.ps1` (advisory, in `run_all`) enforces
this section against GitHub — it warns on stale `[Issue N]` tags (closed / non-existent
issues), on `[verify-fix]`/`[diag]` tags whose paired issue lacks the matching
`verify-fix`/`diagnostics-armed` label, and on the reverse (a labeled open issue with no
matching loc tag — legitimate when the fix has no menu surface, § 13.3/13.8). The ship-time
half lives in `tools/ship/ship.ps1` step 6, which auto-adds the status label from the shipped
CHANGELOG entry.

### 13.5 — Stable strips ALL tags (promotion is the strip point)

Tags are dev-only. **Promotion to a clean (no-suffix) stable version strips every tag** as
part of the promote-to-stable checklist (`PROJECT_STANDARDS.md` § 6.5). A stable/public
build must never render a `[untested]` / `[Issue N]` / etc. prefix to a subscriber.

**Cautionary example (known violation):** stable `crafting_in_modded` currently ships seven
`[untested]` tags — a promotion leak that escaped the strip step. It is tracked for cleanup
at the next `cim` promotion. `qa/check_loc_tags.ps1` (see § 13.7) exists specifically to
catch this class going forward: it warns on any tag found in a stable mod directory.

### 13.6 — Sorting ignores tags

Alphabetical sorting of options (`feedback_sort_categories_alphabetically`) uses the display
name AFTER stripping the leading tag run as the sort key. `[working] Noclip` sorts under "N",
not "[". Strip the leading `%b[]` run (and any following spaces) before comparing.

### 13.7 — QA: `qa/check_loc_tags.ps1`

A warning-only, non-blocking scan (`qa/CHECKS.md` row 19e) that walks every
`*_localization.lua` and reports:

- **Stable leak** — any sanctioned tag present in a stable mod directory
  (`chaos_wastes_tweaker`, `crafting_in_modded`, `general_tweaker`, `gui_tweaker`,
  `verminious_dreams_lighting` — the unsuffixed siblings of the `_dev` dirs).
- **Unknown vocabulary** — a tag-like leading bracket group (lowercase- or `Issue`-leading)
  that is not one of the seven sanctioned tags. Uppercase-leading brackets (`[CW]`,
  `[Big Rebalance]`, `[WARNING]`) are treated as legitimate display-name prefixes and left
  alone; `gut`'s `<...>` angle markers are not brackets and are ignored.
- **Mutex violation** — `[crash]`, `[working]`, `[untested]` combined on one option.

It never fails the gate (see § 13.5 for the leak it is designed to surface). Run it after any
loc tag edit. It accepts the § 13.1 vocabulary plus the § 13.8 `weapon_tweaker` extensions.

### 13.8 — Extensions & exemptions (from the 2026-07-04 live audit)

**`weapon_tweaker` runtime tag emitter.** wt's ~939 `unlock_*` Weapon-Availability rows are
tagged AT LOAD by the loop in `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua`
(~lines 1285-1333): for every `unlock_*` entry it strips any leading `[...]` run
(`_strip_leading_tag`, `gsub("^%s*%b[]%s*", "")`) and re-prepends the tag computed by
`wt_port_status.lua`'s `tag(career, weapon_key)` (fed by the state tables that module derives
from `weapon_tweaker/ANIMATION_COVERAGE.md`). So **any hand-typed tag on an `unlock_*` row is
discarded by design** — do not maintain those tags by hand; edit the coverage state instead.
The tag casing was normalized to the #301 lowercase doctrine forms in wt v0.12.204-dev
(`weapon_tweaker_localization.lua:1323`). The emitter emits the #301 lowercase vocabulary plus
two **wt-only extensions**:

- `[needs offsets]` — the port renders but its 3P grip offsets are still missing.
- `[needs animations → <target>]` — the wt variant of `[needs animations]`, carrying the
  mapped target receiver weapon after the arrow (e.g. `[needs animations → Greathammer]`).

Because these live only in the emitter's runtime output — not in the static
`_localization.lua` — `qa/check_loc_tags.ps1` normally never encounters them; it accepts both
as sanctioned vocabulary regardless, so a normalized or stray static occurrence is never
mis-flagged.

**Inert-feature convention.** When an ENTIRE block of options is inert because a dependency
was retired/removed — current case: the Big Rebalance `br_*` toggles gated on the retired
`buff_tweaker` — tag those rows with the governing tracking ISSUE (`[Issue 321]` here), NOT
`[working]`/`[untested]`. Inert features can't be tested, and a blanket `[untested]` would
drown the real testing radar. Re-tag or remove per § 13.4 when the dependency returns or the
block is deleted.

**Exemptions from the every-option-tagged rule (§ 13.3).** Two kinds of option legitimately
carry no tag:

- **Pure navigation container groups** — a `group` widget that only nests other options and
  has no behavior of its own.
- **Known issue clusters with no menu widget** to hang a tag on (e.g. the cosmetics LA
  rendering/crash cluster). Those are tracked in GitHub only; there is no loc string to tag.

---

## Cross-references

- [`AUDIT_section_c.md`](./AUDIT_section_c.md) — full localization sweep with the P0/P1/P2/P3 findings this standard is built around.
- [`AUDIT_2026_05_21.md`](./AUDIT_2026_05_21.md) — master audit; "Documentation gaps surfaced" section lists the gaps this doc closes.
- Memory: `feedback_ps5_getcontent_utf8.md` — UTF-8 / PowerShell 5.1 reading.
- Memory: `reference_vmf_localize_before_registration.md` — the §12.2 load-order trap (mod:localize fails during loc registration).
- Memory: `feedback_use_documented_localized_names.md` — the §12.1 single-source-of-truth rule (no parallel hardcoded name maps).
- `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua` — canonical reference for trait-description `%%` escaping (post Fix 1).
- `general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua` (see `gt_lobby_failnotify_required_header`, line ~398) + `_gt_lobby_failed_join_reveal.lua` (call site ~188-189) — canonical reference for Pattern A pre-format directives (`%%d` in localization, `string.format` at call site). Absorbed from the now-retired `lobby_tweaker`.
- `general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua` — canonical reference for clean conventional formatting (`_tooltip` suffix, group/setting layout, mod_description).
- `general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua` — clean, conventional reference for new mods. (The former `buff_tweaker` minimal example is retired/archived to `_archive/buff_tweaker_v0.1.12-alpha/`.)
- `qa/check_loc_tags.ps1` — the § 13 dev-status-tag QA scan (stable leaks, unknown vocab, mutex combos). Documented in `qa/CHECKS.md` row 19e. GitHub issue #301.
- `general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev_localization.lua` — canonical reference for the § 13 dev status-tag convention (`[working]` / `[untested]` / `[Issue N]` prefixes).
