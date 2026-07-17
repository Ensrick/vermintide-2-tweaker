# docs/generated/ — machine-generated, do NOT hand-edit

Everything in this directory is **regenerated from ground truth**. Editing these
files by hand is pointless: the next regeneration overwrites your changes, and
worse, a hand-edit defeats the entire purpose (these files exist *because*
hand-maintained catalogs drift and then get trusted while stale).

## Files

| File | What it is |
|------|------------|
| `NAME_MAP.generated.json` | Machine-authoritative key → display-name map. One entry per internal key (vanilla weapon/skin/career/breed keys + mod-created cwv variants, cosmetics custom illusions, wt unlock entries). Schema below. |
| `NAME_MAP.generated.md` | Human/Claude-readable view of the same data, grouped by source then kind. **Grep THIS instead of the legacy hand-maintained catalogs.** |
| `OPEN_ISSUE_AUDIT.generated.json` | Live open-issue doctrine audit plus ranked closed-issue ancestry. Every relationship carries its exact score inputs and prior closure evidence; similarity is review-only and never auto-reopens an issue. |
| `OPEN_ISSUE_CONTINGENCIES.generated.md` | Human-readable form of the open/closed audit. Every open issue retains three evidence-triggered fallback approaches and its top closed-history candidates. |
| `BRANCH_RECONCILIATION.generated.json` | Machine-readable, report-only census of local and remote `agent/*` and `codex/*` refs. Identical tips are deduplicated; ancestry, `git cherry`, issue, path-overlap, version, and manifest evidence remain explicit. |
| `BRANCH_RECONCILIATION.generated.md` | Concise human view of the same branch census. Only exact ancestors and complete pure patch-equivalent tips are automatic; all semantic cases require review. |

## Regenerate

```powershell
# date is a required param — the build env has no reliable clock, so the
# generation date is stamped from what you pass.
pwsh -NoProfile -File tools/gen-name-map/gen-name-map.ps1 -GenDate 2026-05-30

# Requires authenticated gh access. Reads issues only; never edits GitHub.
pwsh -NoProfile -File tools/github/audit-open-issues.ps1 `
  -OutputPath docs/generated/OPEN_ISSUE_AUDIT.generated.json `
  -MarkdownPath docs/generated/OPEN_ISSUE_CONTINGENCIES.generated.md

# Report-only: reads existing refs and never checks out, merges, deletes, or pushes.
# Fetch/prune is deliberately separate and explicit.
git fetch origin --prune
pwsh -NoProfile -File tools/github/branch-reconciliation-census.ps1 `
  -BaseRef origin/master `
  -OutputPath docs/generated/BRANCH_RECONCILIATION.generated.json `
  -MarkdownPath docs/generated/BRANCH_RECONCILIATION.generated.md
```

Deterministic + sorted output → regeneration produces a clean, reviewable diff.
Run it after any change to: a mod's definition tables (cwv `_variant_definitions`,
cosmetics `_cos_illusions.lua` `_custom_illusions`, wt `weapon_unlock_map`), a mod's
`_localization.lua`, or when the decompiled VT2 source is updated.

## What supersedes what

The generated `NAME_MAP.generated.md` is now the authoritative key→name source.
These legacy hand-maintained catalogs are **superseded for key→display-name
lookups** (the maintainer can retire them deliberately — this build does NOT
delete them):

- `ITEM_LIST.md` (repo root) — weapon key catalog
- `WEAPON_CATALOG.md` (repo root) — weapon catalog w/ model paths
- `dynamic_cosmetic_portraits/CHARACTER_COSMETIC_CATALOG.md` — hat/skin key→name
- `cosmetics_tweaker/_cos_probe.txt` — cosmetic key dump

Those catalogs still carry data the map does NOT (model paths, atlas membership,
cross-character port status, portrait-pipeline notes), so they aren't pure
duplicates — but for "what is the in-game name of key X" the generated map is the
source of truth.

## Related grounded surfaces (not the same thing)

This directory answers "what is the in-game NAME of key X." It is distinct from:

- `docs/MECHANICS.md` — the provenance-enforced index of "how does mechanic X
  WORK, and how do we know." Every bullet carries a `[src:]`/`[dump:]`/
  `[memory:]`/`[bugclass:]`/`[user:]`/`[unverified]` tag and is linted by
  `qa/check_mechanics_citations.ps1`. Like this directory, it accretes only from
  ground truth — but it's hand-curated-from-grounded-sources, not regenerated.
- The **memory store** (`~/.claude/.../memory/`) — "how WE work" + cross-cutting
  observations. MECHANICS points at the mechanics-relevant memory notes
  (`[memory: <note>]`) rather than copying them; this generated map is downstream
  of the same ground truth but machine-produced.

## Vanilla names auto-refresh (zero manual action)

The vanilla half of the map (weapons / skins / hats / careers / breeds) has its
English strings in undumped `.package` bundles, so the decompiled source can't
resolve them. The fix is a self-refreshing loop with **no command to remember**:

1. **gt_dev dumps automatically.** `general_tweaker_dev`'s `gt_auto_name_dump`
   setting (checkbox, **default ON**) walks the in-memory `ItemMasterList`,
   `SPProfiles` (careers/heroes), and `Breeds` on **keep/inn entry** and writes
   every `loc_key<TAB>English` pair to the console log, prefixed `[gt:name_dump]`
   — the same tab-separated shape as `dumps/boon_loc_dump.txt`. (VMF mods are
   sandboxed and **cannot write arbitrary files** — `io.open(...,"w")` /
   `mod:get_temp_data_directory` / `Application.save_user_settings_to_file` are
   all unavailable — so the console log is the only writable surface, per the
   established gt dump doctrine.)
2. **Build-version gated.** gt stores the last-dumped `Application.build_identifier()`
   and only (re)dumps when it differs. A player who never patches dumps exactly
   **once, ever**; a game patch (the only time vanilla names *could* change)
   re-fires the dump automatically. That's the "happens when needed naturally"
   refresh.
3. **The generator auto-ingests.** On every regenerate, `gen-name-map.ps1` looks
   for the freshest dump with **no flags**, in priority order:
   - `dumps/name_loc_dump.txt` (a plain file a sync step landed), then
   - `%APPDATA%\Fatshark\Vermintide 2\dumps\name_loc_dump.txt` (future file path), then
   - the newest `%APPDATA%\Fatshark\Vermintide 2\console_logs\*.log` containing
     `[gt:name_dump]` lines.
   For each still-`unresolved` vanilla entry whose `loc_key` the dump knows, it
   fills `display_name` and sets `display_name_source = "game_dump"`. Mod-resolved
   entries are never overwritten. If no dump exists anywhere, vanilla stays
   `unresolved` exactly as before — **never fabricated**. The generated header
   (`_name_dump` in JSON, the "Name dump" line in MD) records the dump path,
   game build id, and how many vanilla entries were resolved vs still unresolved.

**To force a fresh dump:** run `/gt_dump_names` in-game (bypasses the build gate).
**To regenerate:** `gen-name-map.ps1 -GenDate <date>`. No manual step links the two.

A clearly-marked sample dump lives at `dumps/name_loc_dump.SAMPLE.txt` (the
`.SAMPLE` suffix keeps it out of the generator's auto-discovery; rename to
`name_loc_dump.txt` to feed it). It demonstrates both accepted line shapes
(console-log `[gt:name_dump] <key>\t<English>` and plain `<key>\t<English>`).

## Schema (`NAME_MAP.generated.json` entries[])

| field | meaning |
|-------|---------|
| `key` | internal key (e.g. `cwv_es_crossbow`, `wh_crossbow`, `dr_ironbreaker`). For wt unlocks: `<career>::<weapon>`. |
| `kind` | `weapon` / `skin` / `hat` / `frame` / `weapon_skin` / `career` / `breed` / `cwv_variant` / `cwv_skin_only` / `custom_illusion` / `wt_unlock` / ... |
| `display_name` | resolved English string, or `null` if unresolved. **Never fabricated.** |
| `display_name_source` | `literal` (mod hard-coded English) / `mod_loc` (mod `_localization.lua`) / `runtime_dump` (`dumps/boon_loc_dump.txt`) / `game_dump` (in-game `[gt:name_dump]` capture, see "Vanilla names auto-refresh") / `null` if unresolved. |
| `loc_key` | the localization key the engine resolves at render time. |
| `item_type` | item_type field (matters: `Localize(item_data.item_type)` is a real render path). |
| `slot_type` | slot_type field. |
| `careers` | `can_wield` / `careers` list. |
| `source` | `vanilla` or the owning mod id (`character_weapon_variants`, `cosmetics_tweaker`, `weapon_tweaker`, ...). |
| `required_dlc` | DLC gate id, if any. |
| `unresolved` | `true` when no trustworthy English source exists. |
| `reason` | why it's unresolved. |

## Provenance honesty (the point of this tool)

- **Mod-created items are fully grounded** — cwv variants, cosmetics custom
  illusions, and wt unlock entries all resolve to real English via the mods'
  own definition tables / loc tables. This is the maintainer's worst-pain area
  and it is 100% resolved here.
- **Most vanilla English strings are NOT in the decompiled source** — they live
  in undumped `.package` bundles. So vanilla weapons/skins/hats/careers/breeds
  appear with their real `loc_key` but `display_name: null, unresolved: true`.
  The boon dump (`dumps/boon_loc_dump.txt`) was the first vanilla English
  source. The **rest of the vanilla half now self-refreshes**: gt_dev's
  `gt_auto_name_dump` writes a `[gt:name_dump]` capture of `Localize(loc_key)`
  to the console log on keep entry (once per game build), and this generator
  auto-ingests the newest dump on every regenerate (`display_name_source =
  game_dump`). See "Vanilla names auto-refresh" above. With no dump present,
  vanilla entries fall back to `unresolved` — never fabricated.
- The generator **never guesses a name**. An unresolved entry is recorded
  honestly rather than filled with a plausible-but-wrong string — fabrication is
  the exact disease this tool fights.
