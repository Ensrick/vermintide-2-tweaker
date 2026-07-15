# Workshop `published_id` integrity

**Every mod's `itemV2.cfg` `published_id` must be UNIQUE and match its canonical
Steam Workshop ID.** A wrong number silently hijacks another mod's Workshop item
on upload. This is enforced by **`qa/check_published_ids.ps1`** (the test).

## The incident this prevents (2026-06-19)

`gui_tweaker/itemV2.cfg` carried `published_id = 3733367409` — which is
**`general_tweaker_dev`'s** ID, not gut's (`3732144878`). The VMBLauncher uploads
to whatever `published_id` the cfg names, so **every `upload gui_tweaker` pushed
"Tweaker: GUI" onto gt_dev's Workshop item**, overwriting "Tweaker: General
(dev)". Symptom the user saw: *"Tweaker: General dev is missing and we have two
Tweaker: GUI titles."* One wrong number in one cfg = a published mod clobbered on
every upload, with no error.

Fix applied: corrected gut's cfg to `3732144878`, re-uploaded gt_dev (restoring
"Tweaker: General" to `3733367409`) and gut (to its correct item), re-synced the
GitHub release.

## Canonical map (source of truth)

This table lives in code at the top of `qa/check_published_ids.ps1` — that file is
authoritative; this table is the human-readable mirror. Cross-checked against the
"Mod Directory" table in `vermintide-2-tweaker/CLAUDE.md`.

| Mod directory | published_id | Workshop title |
|---|---|---|
| `weapon_tweaker` | 3712896117 | Tweaker: Weapons |
| `chaos_wastes_tweaker` | 3712929235 | Tweaker: Chaos Wastes (stable) |
| `general_tweaker` | 3713619122 | Tweaker: General (stable) |
| `cosmetics_tweaker` | 3715714222 | Tweaker: Cosmetics |
| `career_tweaker` | 3716286199 | Tweaker: Careers |
| `enemy_tweaker` | 3716780252 | Tweaker: Enemies |
| `character_weapon_variants` | 3716869446 | Character Weapon Variants |
| `character_dialogue` | 3765055148 | Character Dialogue |
| `dynamic_cosmetic_portraits` | 3721036701 | Dynamic Cosmetic Portraits |
| `crafting_in_modded` | 3721038774 | Crafting in Modded (stable) |
| `event_tweaker` | 3721290755 | Tweaker: Events |
| `verminious_dreams_lighting` | 3727221800 | Verminious Dreams Lighting (stable) |
| `modded_progression` | 3730422873 | Modded Progression |
| `gui_tweaker` | **3732144878** | Tweaker: GUI |
| `verminious_dreams_lighting_dev` | 3733366748 | Verminious Dreams Lighting (dev) |
| `crafting_in_modded_dev` | 3733366851 | Crafting in Modded (dev) |
| `chaos_wastes_tweaker_dev` | 3733366926 | Tweaker: Chaos Wastes (dev) |
| `general_tweaker_dev` | **3733367409** | Tweaker: General (dev) |
| `weapon_tweaker_dev` | 3748824853 | Tweaker: Weapons (dev) |
| `gui_tweaker_dev` | 3751024698 | Tweaker: GUI (dev) |

## The test

```powershell
pwsh -File qa/check_published_ids.ps1      # exit 0 = clean, 1 = collision/mismatch
```

It **FAILS** (exit 1) on:
- **Duplicate** `published_id` across two mods (the hijack condition).
- A `published_id` that **doesn't match** the canonical for that mod dir.

It **WARNS** (no failure) on a cfg whose dir isn't in the canonical map — that's
your cue to add the new item to the map in the same commit.

**Where it runs automatically:**
- `qa/run_all.ps1` (including `-Quick`) → so the **pre-commit hook** runs it on
  every commit that stages a `.cfg`.
- Should also be run before any Workshop upload (see launcher doctrine).

## The rules that avoid recurrence

1. **NEVER copy an `itemV2.cfg` from another mod without changing `published_id`
   AND `title`.** That copy-paste is exactly how this happened.
2. **Publishing a NEW Workshop item?** Add its dir + id to the canonical map in
   `qa/check_published_ids.ps1` **in the same commit** that adds the cfg.
3. **A failing `check_published_ids` is a hard stop — do not upload.** A wrong id
   doesn't error on upload; it silently overwrites a live, published mod.
