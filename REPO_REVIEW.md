# Repo-Level Review (2026-05-01)

Scope: root-level docs, deploy/upload PowerShell scripts, and shared infrastructure. Per-mod code is being reviewed by other agents in parallel.

## Summary

Overall health is **good** for the active build/deploy infrastructure (DEVELOPMENT.md, deploy_all.ps1, upload_*.ps1) which has been refreshed for the 2026-05-01 VMB migration. Two large doc files (`ANTIGRAVITY.md` and the build-instruction sections of `CLAUDE.md`) still describe the **pre-migration SDK pipeline** as if it were current. Several files have an inconsistent claim about `character_weapon_variants` — `itemV2.cfg`, `deploy_all.ps1`, and the `reference_build_deploy.md` memory all agree it's **published as 3716869446**, but `CLAUDE.md` and `DEVELOPMENT.md` still list it as `(unpublished)`. PowerShell scripts are sane and the visibility-public abort guard on `upload_wt.ps1` does what it should. `.gitignore` is mostly correct but has a few latent questions. WORK_ITEMS.md is dated 2026-04-27 and hasn't absorbed the latest CHANGELOG entries.

## Stale references found

- `CLAUDE.md:13-20` — Mod Directory table says `character_weapon_variants` Workshop ID is `(unpublished)`; on-disk `character_weapon_variants/itemV2.cfg` has `published_id = 3716869446L` and `deploy_all.ps1` maps it to `"3716869446"`. Should be **3716869446 / private**.
- `CLAUDE.md:24-46` — "SDK mods (legacy `tweaker` only)" build block is technically labeled legacy but reads as primary. After 2026-05-01 every active mod is VMB; this block applies to a single deprecated source tree. Recommend collapsing to a one-line pointer.
- `CLAUDE.md:99-126` — "Mod File Structure" splits into "SDK mods" vs "VMB mods" but every active mod uses the VMB layout now. The `wt.mod / settings.ini / .build/OUT / upload/content/` shape only survives in `/tweaker`.
- `CLAUDE.md:187` — "No `goto` in SDK mods (available in VMB-built mods, including chaos_wastes_tweaker now that it's VMB)" — only the legacy tweaker still lacks `goto`; the qualifier is correct but reads as if multiple SDK mods still exist.
- `CLAUDE.md:197` — "**`deploy_all.ps1` does NOT handle cosmetics_tweaker or character_weapon_variants** — both must be deployed manually." This is **wrong**: `deploy_all.ps1` has both in `$workshopIds` and the auto-detection (`Test-Path bundleV2`) covers them. Just pass `-Mods @("cosmetics_tweaker")`. DEVELOPMENT.md confirms the new behavior.
- `DEVELOPMENT.md:15` — character_weapon_variants row says `(unpublished)` and visibility `n/a`. Should be `3716869446` / `private`.
- `ANTIGRAVITY.md` (entire file) — describes the pre-VMB pipeline (`wt.mod` at repo root, `settings.ini` per mod, `.build/OUT/`, `upload/content/`, `_run_build.bat`, `build.bat`, `install_local.bat`, `deploy.ps1`, `upload.ps1`, `upload_all.ps1`). Status table also lists Career Tweaker as "Not started" and is missing cosmetics_tweaker, general_tweaker, enemy_tweaker, character_weapon_variants. **Most importantly**, line ~83 documents `visibility = "public"` as the upload example for weapon_tweaker — this is dangerous given that flipping that mod public previously got it removed-from-community. File should be banner-marked as STALE, deleted, or fully rewritten.
- `ANIMATION_RESEARCH.md:80-87` — "Commands for Discovery" lists `t probe_3p`, `t dump_templates`, `t dump_crossbow`, `t dump_chest_view`. Those use the legacy `t` prefix; current commands are `wt` / `gt` / `ct`-prefixed.
- `TODO.md:18-22` — `t unstuck` / `t god` / `t win` / `t dump_boons` use the legacy `t` prefix. Should be `ct` (chaos_wastes_tweaker) or whichever mod hosts each command now.
- `TODO.md:1` — File title says "Chaos Wastes Tweaker — Feature To-Do" but content covers all six active tweaker mods. Misleading title.
- `WEAPONS.md` — references the `t` legacy mod implicitly via cross-mention to ANIMATION_RESEARCH; otherwise consistent.
- `readme.txt` — SDK-shipped generic README. References `streamable_resources/.build/OUT`, `compile_streamable_resources.bat`, and SDK `sample_item` upload — none apply to active mods.
- `dumps/README.txt` is dated 2026-04-25 but not stale per se.

## Workshop ID / mod ID inconsistencies

| File | character_weapon_variants entry | Status |
|------|-------------------------------|--------|
| `character_weapon_variants/itemV2.cfg` | `published_id = 3716869446L` | source of truth |
| `deploy_all.ps1` | `"3716869446"` | matches |
| `memory/reference_build_deploy.md` | `3716869446` | matches |
| `TODO.md` | `Workshop 3716869446` | matches |
| `CLAUDE.md` | `(unpublished)` | **inconsistent** |
| `DEVELOPMENT.md` | `(unpublished)` | **inconsistent** |
| Task description (this review) | `(unpublished)` | also inconsistent |

Recommend a single-source-of-truth comment in CLAUDE.md and DEVELOPMENT.md tables noting that `deploy_all.ps1`'s `$workshopIds` is the authoritative map.

All six other Workshop IDs (`weapon_tweaker=3712896117`, `chaos_wastes_tweaker=3712929235`, `general_tweaker=3713619122`, `cosmetics_tweaker=3715714222`, `career_tweaker=3716286199`, `enemy_tweaker=3716780252`, `tweaker=3704660429`) are consistent across all checked files.

## Visibility documentation gaps

- ANTIGRAVITY.md line ~83 has `visibility = "public"` as a literal example for **weapon_tweaker**. This is the exact case that previously got the mod flagged. This is the highest-priority cleanup item.
- DEVELOPMENT.md correctly captures the rule (lines 115, 569 in current version) but the "irreversible Steam removal-from-community" warning is buried — could be more prominent.
- CLAUDE.md does not mention visibility at all in the build/deploy commands. Should at least cross-reference DEVELOPMENT.md's "do NOT change visibility without explicit user direction" rule.
- No upload script exists for general_tweaker, career_tweaker, cosmetics_tweaker, enemy_tweaker, or character_weapon_variants. If/when they're added, each should follow `upload_wt.ps1`'s visibility="public" abort pattern.

## Hook pattern guidance — coverage check

- `CLAUDE.md:140-147` — covers string-form vs table-form hooks, `_G` for globals, `hook_safe`, and the BackendUtils.can_wield_item warning. **Mostly complete.**
- Missing from CLAUDE.md but present in DEVELOPMENT.md and CROSS_MOD_ARCHITECTURE.md:
  - `BackendUtils.set_loadout_item` ≠ `items_iface:set_loadout_item` distinction (loadout dispatch via `get_loadout_interface_by_slot`).
  - `rawget(ItemMasterList, key)` requirement (the `__index` crashify metamethod).
  - `rawget(NetworkLookup.weapon_skins, key)` and similar guarded tables.
  - Guidance that `BackendUtils` must be hooked **by table reference, not string** (DEVELOPMENT.md line 635).
- DEVELOPMENT.md "Known Errors & Fixes" has the rawget error and the BackendUtils.can_wield_item error documented — those are good.

Recommendation: extract a short "Hook gotchas" section into CLAUDE.md or cross-link explicitly to DEVELOPMENT.md from the Hooking section.

## Three rendering paths coverage

- `CLAUDE.md:149-160` — has the table with all three (GearUtils.create_equipment, HeroPreviewer._spawn_item, LootItemUnitPreviewer.spawn_units) and notes MenuWorldPreviewer is NOT usable. **Good.**
- `DEVELOPMENT.md:582-595` — same table, more detail on LootItemUnitPreviewer index ordering. **Good.**
- `CROSS_MOD_ARCHITECTURE.md` covers MenuWorldPreviewer in the LA bridge section but not in the cosmetic-architecture section — moot since the LA bridge correctly notes `MenuWorldPreviewer extends HeroPreviewer`.
- Per-mod docs (`cosmetics_tweaker/...`) not in this scope but should be checked by other reviewers.

No gaps found.

## Animation system coverage

- `DEVELOPMENT.md:174-285` — covers all three layers (anim_redirect, career_anim_redirect, _3p_weapon_remap), Two-Units architecture, anim_event vs anim_event_3p, the "non-weapon `to_` events trap", and the "do not clear remap on non-weapon events" rule. **Comprehensive and current.**
- `WORK_ITEMS.md:111-126` — confirms the rules with concrete bullet points.
- `WEAPON_CATALOG.md` — per-weapon remap reference, consistent with DEVELOPMENT.md.
- `ANIMATION_RESEARCH.md` — historical research record; status superseded by WORK_ITEMS.md.

The 3-layer system, the `is_local` direction (player_unit IS the 3P body), and the non-weapon `to_` event whitelist are all captured in multiple places. **No coverage gaps.**

## PowerShell script audit

### deploy_all.ps1

- Hardcoded paths: `$workshopBase = "C:\Program Files (x86)\Steam\steamapps\workshop\content\552500"` — fine for solo dev, but if repo is shared, should fall through env var.
- Workshop IDs: all seven match itemV2.cfg published_ids. **Verified consistent.**
- VMB layout auto-detect: `Test-Path $vmbOut` then `$sdkOut` fallback. **Works.** Will pick VMB when both exist (correct since post-migration `bundleV2/` is the new source of truth).
- `Clean-StaleBundles`: present, runs before each copy, removes `*.mod` and `*.mod_bundle` from target dir. Does NOT remove extensionless legacy hex-named bundles, but those should no longer accumulate.
- Default `-Mods` list: `("chaos_wastes_tweaker", "weapon_tweaker", "general_tweaker")` only. cosmetics_tweaker, career_tweaker, enemy_tweaker, character_weapon_variants are **deployable but not deployed by default** — a bare `& .\deploy_all.ps1` won't touch them. Document or expand default.
- The legacy SDK branch (still present) writes to `<mod>/upload/content/` — only relevant for the legacy `/tweaker` build. Could be removed once `/tweaker` is retired entirely; harmless until then.

### deploy_ct.ps1 / deploy_wt.ps1

- Tiny one-liners that delegate to deploy_all.ps1. Workshop IDs not duplicated here (good — single source of truth in deploy_all.ps1's `$workshopIds`). **No issues.**

### upload_ct.ps1

- chaos_wastes_tweaker is intentionally `visibility = "public"` (the only public mod), so no abort-on-public guard. **Consistent with the visibility rule.**
- Sanity check on `bundleV2` existence and `*.mod_bundle` files: present. Good.
- Suggestion: add a positive guard that aborts if visibility is anything OTHER than `"public"` (catches accidental drift to private/friends). Optional.

### upload_wt.ps1

- Has the visibility=public abort guard at line 19-21 — pattern match against `'visibility\s*=\s*"public"'`. **Working as intended.**
- Sanity check on `bundleV2` and `*.mod_bundle` files: present. Good.
- Header comment correctly notes the irreversible removed-from-community history. Good.

### send_keys.ps1

- Targets a window with title exactly "Vermintide 2" via `FindWindow($null, "Vermintide 2")`. If another window has that exact title, it would receive keys instead — low real-world risk.
- Uses `SetForegroundWindow` then `[System.Windows.Forms.SendKeys]::SendWait`. SendKeys is unreliable when focus stealing is blocked (Win 10+ default), but the 200ms `Start-Sleep` mitigates.
- Adds a `keybd_event` P/Invoke wrapper but **never calls it** (only `[System.Windows.Forms.SendKeys]::SendWait` is used). Dead code; safe to drop the `InputSender` Add-Type block.
- Exits cleanly if window not found. Good.
- `$Keys` parameter is mandatory and passed straight through to SendKeys — caller-trusted (dev tool only).

**Verdict: SAFE.** No risk of unintended keystroke replay.

## .gitignore review

Current entries:
- `**/.build/` — covers SDK output. Good.
- `**/upload/content/` — covers SDK upload staging. Good.
- 16-hex glob — covers extensionless legacy bundle files. Also matches `bundleV2/<hex>.mod_bundle` files inadvertently? No — `.mod_bundle` extension means the glob (which matches base name only) won't match.
- `*.zip` — good (catches manual install zips).
- `*.lua.processed` — good (preprocessor output, no longer used by VMB but harmless).
- `CLAUDE.md` and `ANTIGRAVITY.md` ignored — interesting; these contain local machine paths. Note that this means CLAUDE.md edits don't get committed; flag if user wanted them tracked.
- `upload/steam_appid.txt` — old SDK artifact; harmless.
- `.temp/` — VMB tempdir; good.

**Not ignored but maybe should be considered:**
- `bundleV2/` — currently tracked; confirm intentional. Tracking generated bundles in git is a deliberate choice (so commits include the artifact that was deployed).
- `dumps/*.txt` — large dumps tracked. Confirm intentional.
- `launcher_screenshot.png` — 1MB tracked at root. Should it move to a docs folder?
- `bundleHistory.dat` — binary, tracked, mtime old (Apr 28). Likely harmless but worth confirming with maintainer.
- `.vmbrc` — contains absolute paths; tracked. Could add a `.vmbrc.example` pattern instead.

No sensitive paths missing — there are no .env / credentials.json files in repo.

## TODO.md / WORK_ITEMS.md staleness

### TODO.md
- File title is "Chaos Wastes Tweaker — Feature To-Do" but covers six mods. Misleading.
- Legacy `t` prefix on commands listed under "Implemented" (`t unstuck`, `t god`, `t win`, `t dump_boons`).
- "Investigate CW ghost scythe 3P spawn crash" entry references CROSS_CAREER_PACKAGE_FIX.md as "partially obsolete — original cross-career theory was wrong" — that doc should be banner-marked.
- Several items appear up-to-date with current state (e.g. v0.10.14 mitigation reference, "AnyWeapon" entry checked).
- `[x] AnyWeapon — allow any weapon regardless of career restrictions (implemented in weapon_tweaker)` — confirmed implemented, so OK.

### WORK_ITEMS.md
- Last updated: 2026-04-27 — predates the 2026-05-01 VMB migration. Has not absorbed:
  - cosmetics_tweaker v0.6.19, v0.6.38, v0.7.0 entries from CHANGELOG.md
  - weapon_tweaker v0.10.6 (current root CHANGELOG.md says v0.10.6-dev; this file says v0.9.57-dev)
  - cosmetics_tweaker is entirely missing from the "Confirmed Working" section
  - enemy_tweaker, character_weapon_variants are missing entirely
- "Animation rules (confirmed)" section has 16 bullet points, all of which appear consistent with current weapon_tweaker code.

## WEAPON_CATALOG.md / WEAPONS.md / ITEM_LIST.md

Spot-checked against DEVELOPMENT.md cross-career status table and per-mod weapon_tweaker code references in WORK_ITEMS.md — all three files are consistent with each other and with the DEVELOPMENT.md narrative. No build/upload references in these files (purely data references).

- WEAPON_CATALOG.md: comprehensive per-weapon catalog with version markers (v0.10.10, v0.10.16+, v0.10.21). Marked itself authoritative; DEVELOPMENT.md confirms.
- WEAPONS.md: high-level summary, consistent with WEAPON_CATALOG.md.
- ITEM_LIST.md: static dump, undated. Generation provenance not noted in file — recommend adding a header.

## CROSS_MOD_ARCHITECTURE.md / CROSS_CAREER_PACKAGE_FIX.md

### CROSS_MOD_ARCHITECTURE.md

Detection pattern (`get_mod("wt")`, `get_mod("character_weapon_variants")`) is correct post-migration. The detailed LA Bridge section is consistent with `feedback_cwv_backend_id_lookup.md` and `feedback_cwv_clone_name_clobber.md` in memory. **Accurate post-VMB.**

### CROSS_CAREER_PACKAGE_FIX.md

Per TODO.md, the original cross-career theory was disproven (the actual ghost scythe crash reproduces without cross-career unlocks, and the root cause is suspected nil career_name on bot inventory recreation, not package timing). The doc still presents Option A/B/C without a banner indicating the analysis is partially obsolete. Recommend prepending: "STATUS: Original analysis disproven 2026-04-29. See TODO.md 'Investigate CW ghost scythe 3P spawn crash' for current diagnostic state."

## readme.txt status

Generic SDK-shipped README. References `streamable_resources/.build/OUT`, `compile_streamable_resources.bat`, SDK `sample_item` staging — none apply to active mods. **Not a bug, but presence at repo root is potentially confusing.** Inline review marker added; recommend either renaming to `readme_sdk_reference.txt` or moving to `old-backup/`.

## old-backup/README.md completeness

Was missing the `upload/` subfolder (legacy `tweaker` upload staging with `item.cfg`, `preview.jpg`, `steam_appid.txt`, `content/`). I added a section documenting it. Otherwise content matches the directory listing.

## settings.ini at repo root

Used by an external bundle-decompiler tool (writes alongside `bundleHistory.dat`), NOT by VMB or the Stingray compiler. Format is plain `KEY=VALUE` — adding `#`-prefixed comments could break the parser, so I did NOT add a review marker inline. The file's purpose should be documented in DEVELOPMENT.md or `old-backup/README.md` so a reader doesn't think it's a leftover SDK settings.ini.

## bundleHistory.dat

Binary file at repo root, mtime 2026-04-28, 203 bytes. Companion to settings.ini for the bundle decompiler tool. Not parsed; presence noted.

## dumps/

Inventoried (per task instructions, not reviewed file by file): 14 files including `boon_*.txt`, `cosmetics_raw.txt`, `mutator_templates.txt`, `reference_*.txt`, `weapon_*.txt`, `weapon_unlock_map_full.lua`, plus a `README.txt` dated 2026-04-25 with index. No build/deploy implications.

## Recommended next actions (top 5 highest-leverage)

1. **Fix `character_weapon_variants` Workshop ID in CLAUDE.md and DEVELOPMENT.md** — change `(unpublished)` to `3716869446` and add visibility `private` in both files. Single-line edit each. (Source of truth: `character_weapon_variants/itemV2.cfg` and `deploy_all.ps1`.)

2. **Banner-mark or delete ANTIGRAVITY.md** — it's the largest stale doc and contains a literal `visibility = "public"` example for weapon_tweaker, which is exactly the action that previously got a mod removed-from-community. Either prepend a "STALE — DO NOT FOLLOW" banner or fold any unique content into DEVELOPMENT.md and delete.

3. **Fix CLAUDE.md "deploy_all.ps1 does NOT handle cosmetics_tweaker..." line** — it does. Change to "deploy_all.ps1 default `-Mods` list does not include cosmetics_tweaker, character_weapon_variants, enemy_tweaker, or career_tweaker — pass `-Mods @("...")` explicitly to deploy them."

4. **Update legacy `t` prefix references** in TODO.md and ANIMATION_RESEARCH.md to current per-mod prefixes (`ct`, `wt`, `gt`) or note that those commands lived in the legacy monolithic mod.

5. **Refresh WORK_ITEMS.md** — bump "Last updated" to 2026-05-01, sync version stickers with root CHANGELOG.md, and add cosmetics_tweaker / enemy_tweaker / character_weapon_variants sections (or note that they have their own per-mod CHANGELOG.md and TODO.md).
