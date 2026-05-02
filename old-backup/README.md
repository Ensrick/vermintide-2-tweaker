<!--
REVIEW (2026-05-01): Content is accurate and matches the directory listing (verified files:
build.bat, _run_build.bat, install_local.bat, repair_workshop.bat, deploy.ps1, upload.ps1,
upload_all.ps1, wt.mod, tweaker_manual_install.zip, four hex-named bundle files, plus an
upload/ subfolder). Coverage of "what replaces these for VMB mods" table is helpful. No issues.
Minor suggestion: add a one-line note that these files can be deleted entirely after a few
months of confidence in the VMB pipeline (currently kept for reference).
-->
# old-backup/

Files preserved during the VMB migration on 2026-05-01. Active mod source/build now lives at `<repo>/<mod_name>/` with VMB layout (`bundleV2/`, `itemV2.cfg`, `<mod_name>.mod`); these files target the old SDK pipeline (`<mod>/.build/OUT/`, `<mod>/upload/content/`, etc.) and are no longer used.

## Stray build artifacts (extensionless bundle files)
- `209fb8c3c0a8c3a4`, `4e6a9317aab221e1`, `e6ec798962435802`, `e7852992f40eb619` — static SDK bundle files that lived at the repo root. The current per-mod `bundleV2/` builds include their own copies.

## Legacy `tweaker` distribution
- `tweaker_manual_install.zip` — manual install bundle for the legacy all-in-one `tweaker` mod (now split into chaos_wastes/weapon/general/career).

## SDK-pipeline scripts
All of these reference paths that no longer exist (`<mod>\.build\OUT`, `<mod>\upload\content`):
- `build.bat`, `_run_build.bat` — Stingray compiler invokers (default mod name was `tweaker`)
- `install_local.bat` — local sideload via fake Workshop ID `9000000001`
- `repair_workshop.bat` — copies `tweaker\.build\OUT` over the Workshop content folder
- `deploy.ps1` — legacy single-mod deploy
- `upload.ps1` — legacy single-mod upload via SDK `sample_item` staging
- `upload_all.ps1` — same staging method, looped across mods

## Stray .mod
- `wt.mod` — leftover at repo root from old SDK builds. The active weapon_tweaker entry point is `weapon_tweaker/weapon_tweaker.mod`.

<!-- REVIEW: README does not mention the `upload/` subfolder (item.cfg, preview.jpg, steam_appid.txt, content/). That's the legacy `tweaker` mod's upload staging that lived at repo root. Add a section noting it. -->
## Legacy `tweaker` upload staging
- `upload/` — original tweaker (legacy `t`) mod's SDK upload staging directory. Contains the old `item.cfg`, `preview.jpg`, `steam_appid.txt`, and `content/` (extensionless bundle files). Replaced by per-mod `<mod>/itemV2.cfg` + `<mod>/bundleV2/` for active mods.

## Stale documentation
- `ANTIGRAVITY.md` — pre-VMB development log. Documents the entire retired SDK build/upload pipeline (`.build/OUT/`, SDK `sample_item` staging, `wt.mod` at repo root) and contains a now-misleading `visibility = "public"` example for weapon_tweaker (3 occurrences). Per the per-mod visibility intent recorded in memory, weapon_tweaker is intentionally **private** and any future automated change to public is the failure mode that previously got two mods removed-from-community. Moved here so AI agents reading the active doc set don't pick up the stale guidance.

## What replaces these for VMB mods
| Old | New |
|---|---|
| `build.bat <mod>` | `node C:/Users/danjo/source/repos/vmb/vmb.js build <mod> --no-workshop --cwd` |
| `deploy.ps1` / `deploy_*.ps1` (SDK) | `deploy_all.ps1` (auto-detects VMB layout) or `deploy_ct.ps1`/`deploy_wt.ps1` |
| `upload.ps1` / `upload_*.ps1` (SDK staging) | `upload_ct.ps1` / `upload_wt.ps1` (call `ugc_tool` with `itemV2.cfg` directly) |
| `<mod>\.build\OUT\` | `<mod>\bundleV2\` |
| `<mod>\upload\item.cfg` | `<mod>\itemV2.cfg` |

The legacy `tweaker` mod source (at `<repo>/tweaker/`) is preserved unmigrated as a reference of the original all-in-one design — these build scripts are still the only way to build it if needed.
