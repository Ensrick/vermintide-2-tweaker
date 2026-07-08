# Mod Dependencies — cross-mod relationships + the standalone invariant

> **Invariant (set 2026-06-22):** every mod in this monorepo **loads and functions
> fully standalone** — no mod hard-requires another. Cross-mod features are optional
> *enhancements* that degrade gracefully (no-op, never crash) when the other mod is
> absent.
>
> **Audited 2026-06-22:** zero ungated cross-mod dependencies, zero hard `.mod`
> dependencies, across ~30 cross-mod edges. Enforced going forward by
> `qa/check_cross_mod_deps.ps1` (wired into `qa/run_all.ps1`).

## The gating convention (the rule)

A feature that uses another mod MUST:

1. **Nil-guard before any deref.** Resolve via `local other = get_mod("X")` and
   nil-check, or wrap the feature in `if get_mod("X") then … end`. Inline chained
   derefs — `get_mod("X").field` / `get_mod("X"):method()` — are **forbidden** unless
   wrapped: `(get_mod("X") or {}):method()`. *(The check flags the unwrapped form.)*
2. **Treat absence as the safe/default path** — the feature goes inert; the mod keeps
   working.
3. **Never declare a hard dependency** in the `.mod` file for an optional feature
   (the only allowed `.mod` assertion is the standard `fassert(rawget(_G,'new_mod'), …)`
   VMF load-order guard).
4. **Reference the stable mod_id** (`get_mod("cim")`, not `"cim_dev"`). Dev clones are
   isolated; nothing external consumes a `*_dev` id.

Self-references (a file dereferencing `get_mod` of its *own* id) are exempt — the mod
is always present in its own files. Suppress a verified-safe inline deref with a
trailing `-- cross-mod-ok` comment.

## Dependency matrix (consumer → requires)

| Consumer | Requires | Feature | Degrades to (when absent) |
|---|---|---|---|
| wt · wt_dev · ct · ct_dev · crt · enemy_tweaker | **bt** *(retired)* | Big Rebalance master gate (`is_br_active`) + `net_replay` diagnostics | BR sub-features inert — `if not (bt and bt.is_br_active) then return false`. bt is retired, so permanently inert by design (not stripped). |
| **character_weapon_variants** | **MoreItemsLibrary** | Register CWV variant items into the local backend (CWV's core) | ⚠️ Warns + registers **zero** variants (no crash). **Non-functional standalone** unless MIL is provided by cosmetics_tweaker's embed or standalone MIL. See *Known gap*, [#82]. |
| wt · wt_dev | character_weapon_variants | Presence flag (#368): wt + CWV are **independent** (overlap allowed). wt flips overlapping cross-char availability defaults **ON** when CWV is present and covers CWV's `cwv_variant` items with its own toggles. The old `cwv_managed` dedup/cede is being removed. | wt applies its standalone cross-char defaults (ports OFF) |
| gt · gt_dev | cim | Enable the mid-mission Customize/Forge tab (cim neutralizes the preview crash) | Forge tab stays disabled mid-mission (the safe path) |
| cosmetics_tweaker | cim | Defer modded-realm vanilla-illusion-swap ownership to cim | cosmetics_tweaker keeps owning the swap (its own fallback) |
| cosmetics_tweaker | Loremasters-Armoury + MIL | LA cosmetic bridge (mirror LA hats/illusions, husk swap) | Bridge dormant + echoes a notice |
| cosmetics_tweaker | Material-Hijack / material_hijack_patched / la_prefix_patch | **Conflict guard** (embed goes dormant if the standalone is *enabled*) | Embed stays active (inverse of a dependency) |

Per-edge file:line citations live in the 2026-06-22 audit + `docs/CROSS_MOD_ARCHITECTURE.md`.

## Exposed APIs (provider → consumers)

| Provider | API surface | Consumed by |
|---|---|---|
| **gut** | `get_mod("gut").mod_tweaker:{register_category, get, set, list_categories, …}` | self only so far — designed for other mods to register settings categories |
| **mp** | `get_mod("mp").{is_unlocked, spend, credit, grant_item, has_currency, …}` | none wired yet (CWV/cosmetics are the designed consumers) |
| **bt** *(retired)* | `get_mod("bt"):is_br_active()` / `:net_replay()` | wt · wt_dev · ct · ct_dev · et · crt (guarded → inert) |
| **cim** | presence flag (`get_mod("cim") ~= nil`) — owns modded-realm vanilla-illusion swap | cosmetics_tweaker · gt · gt_dev |
| **cwv** | presence flag — owns its cross-character variant items (`cwv_variant`); wt reads it to flip overlapping availability defaults ON + expose toggles for CWV's items (#368) | wt · wt_dev |

Most cross-mod contracts are **presence-flag** checks, not method APIs.

## Known gap (enhancement, not a bug) — [#82]

`character_weapon_variants` ships **no embedded MoreItemsLibrary**, so standalone CWV
(without cosmetics_tweaker or the standalone MIL mod) loads but registers zero variants.
It degrades gracefully (warn + no-op, no crash) — so it does **not** violate the
no-hard-require invariant — but CWV is non-functional alone. Fix: drop the
copy-pasteable `_moreitemslibrary_embedded.lua` + `_la_prefix_embedded.lua` sentinel
pair (from cosmetics_tweaker, written to be portable) into CWV. Tracked in [#82].

## Adding a new cross-mod feature — checklist

1. Guard it (`get_mod` nil-check or `if get_mod("X") then`).
2. Make absence the safe default.
3. Add a row to the matrix above.
4. If it's a new exposed API, add a row to the APIs table.
5. `qa/check_cross_mod_deps.ps1` must pass (run `qa/run_all.ps1 -Quick`).
