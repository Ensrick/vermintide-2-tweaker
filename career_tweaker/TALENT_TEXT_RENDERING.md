# VT2 talent name + description rendering (for mods)

How the talent inventory tooltip turns a `Talents[hero][id]` table into the
title + body text the player sees — and why mod-defined strings need special
handling. Written after the Leading Shots talent rendered its raw loc keys
(2026-06-18); this is the canonical reference for any crt rework that renames a
talent or rewrites its description.

## TL;DR — the trap that bit Leading Shots

The talent UI calls the **global** `Localize(key)`. **VMF does NOT register a
mod's `<mod>_localization.lua` keys into the global `Localize`** (VMF_RECIPES
mod-localization-scope caveat). So setting `talent.display_name` /
`talent.description` to a mod-only loc key makes the UI call
`Localize("crt_engineer_leading_shots_name")`, which the engine can't resolve →
the tooltip renders garbled/raw. **Fix: serve the text through crt's shared
`_G.Localize` hook via the `CRT_DESC_OVERRIDES` table** (`career_tweaker_balance.lua`),
exactly like every other rework. Changing `{1}`→`%s` (the first attempt) was
necessary-but-not-sufficient — the keys never resolved in the first place.

## Title field precedence

The title resolves as `Localize(talent.display_name or talent.name)`
(`scripts/ui/views/hero_view/windows/hero_window_talents.lua:328`).
- `display_name` wins if present; otherwise `name` is used.
- To rename a talent, set `talent.display_name` and leave `talent.name` alone, so
  `custom_restore` can restore cleanly. (Leading Shots sets `display_name`.)

## Description placeholder style (printf, NOT `{1}`)

The body is rendered by `UIUtils.get_talent_description` →
`UIUtils.format_localized_description` (`scripts/helpers/ui_utils.lua:34-78`). The
load-bearing line is `ui_utils.lua:69`:

    str = string.format(Localize(talent.description), unpack(VALUE_LIST, 1, num_defs))

So the description is a **C/printf format string consumed by Lua `string.format`**:
use `%s` / `%d` / `%.1f`. **`{1}`-style indexing does NOT work** — it renders
literally. **Gotcha:** a literal percent sign MUST be written `%%`, or the tooltip
crashes to `[Invalid String Format]` (confirmed in production at
`chaos_wastes_tweaker.lua:2862-2865` / `5126-5129`).

Note the early-out at `ui_utils.lua:36-38`: if `description_values` is empty/nil,
`format_localized_description` returns `Localize(description)` **without** calling
`string.format`. So a description with **no** placeholders and **no**
`description_values` skips `string.format` entirely (no `%%` worries).

## `description_values` shape

The value list unpacked into `string.format`. Two valid forms:
1. **Ordered list of `{value_type=..., value=...}` sub-tables** (canonical):
   - `value_type = "percent"` → multiplies a 0..1 `value` by 100 (`ui_utils.lua:56-57`).
   - `value_type = "baked_percent"` → `100 * (value - 1)` (`ui_utils.lua:58-59`).
   - No `value_type` → the raw `value` is passed straight through. e.g.
     `{ { value = 4 } }` against `"Every %s shots..."` → "Every 4 shots...".
2. **Flat list of string keys**, e.g. `{ "multiplier" }` (`buff_templates.lua:4869`).

The Nth entry fills the Nth `%`-placeholder; placeholder count must equal `num_defs`.

Vanilla canonical example: talent `markus_huntsman_heal_share` ("Conqueror"),
`scripts/managers/talents/talent_settings_markus.lua:1722-1737` — a single
percent-typed value against a `%d%%` placeholder.

## The fix pattern (crt): serve mod talent text through `_G.Localize`

crt has **exactly one** `_G.Localize` hook (VMF silently drops a second hook on
the same `(_G, "Localize")` pair — consolidate, never add a second). It reads a
single table `CRT_DESC_OVERRIDES` (`career_tweaker_balance.lua:2685+`) keyed by the
exact string passed to `Localize`, gated by the rework's setting id so it only
applies while the rework is active:

    ["crt_engineer_leading_shots_name"] = {
        setting = "rework_dr_engineer_leading_shots",
        text    = "Leading Shots",
    },
    ["crt_engineer_leading_shots_desc"] = {
        setting = "rework_dr_engineer_leading_shots",
        text    = "Every 4 ranged attacks (including the Crank Gun), your next ranged attack is a guaranteed critical hit.",
    },

Both the **title key** (`display_name`) and the **description key** go through this
same hook. Note the established convention: **hardcode the numbers in the text**
(and double any literal `%` → `%%`) rather than relying on `%s` +
`description_values` — every existing entry does this, and it sidesteps the
`string.format` path entirely.

### Minimal working recipe
    -- In custom_apply, repoint the talent:
    talent.display_name = "crt_<x>_name"   -- resolved by the _G.Localize hook
    talent.description  = "crt_<x>_desc"   -- resolved by the _G.Localize hook
    -- In CRT_DESC_OVERRIDES (career_tweaker_balance.lua), gated by the setting:
    ["crt_<x>_name"] = { setting = "<rework_setting>", text = "Display Name" },
    ["crt_<x>_desc"] = { setting = "<rework_setting>", text = "Body text, %% for literal percent." },

(The `<mod>_localization.lua` keys are then optional/redundant for the tooltip —
the hook is authoritative — but harmless to keep as documentation.)

## Key file references
- `hero_window_talents.lua:328` — title = `Localize(display_name or name)`.
- `ui_utils.lua:34-78` — `format_localized_description` / `get_talent_description`; line 69 is the `string.format` call; lines 36-38 the empty-values early-out.
- `talent_settings_markus.lua:1722-1737` — vanilla "Conqueror" canonical example.
- `chaos_wastes_tweaker.lua:2862-2865` / `5126-5129` — `%%`-escape requirement (in-production).
- `career_tweaker_balance.lua:2685+` — the shared `_G.Localize` hook + `CRT_DESC_OVERRIDES` table.
