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

## What replaces these for VMB mods
| Old | New |
|---|---|
| `build.bat <mod>` | `node C:/Users/danjo/source/repos/vmb/vmb.js build <mod> --no-workshop --cwd` |
| `deploy.ps1` / `deploy_*.ps1` (SDK) | `deploy_all.ps1` (auto-detects VMB layout) or `deploy_ct.ps1`/`deploy_wt.ps1` |
| `upload.ps1` / `upload_*.ps1` (SDK staging) | `upload_ct.ps1` / `upload_wt.ps1` (call `ugc_tool` with `itemV2.cfg` directly) |
| `<mod>\.build\OUT\` | `<mod>\bundleV2\` |
| `<mod>\upload\item.cfg` | `<mod>\itemV2.cfg` |

The legacy `tweaker` mod source (at `<repo>/tweaker/`) is preserved unmigrated as a reference of the original all-in-one design — these build scripts are still the only way to build it if needed.
