# `_archive/` — cold storage

Created 2026-05-21 as part of the Section A audit pass.

Nothing in here is on the active build path. Safe to delete wholesale once
the maintainer is confident the contents are no longer needed for reference.

## Subfolders

| Folder | Contents | Why archived |
|--------|----------|--------------|
| `old-backup/` | Pre-VMB SDK artifacts (build.bat, install_local.bat, upload.ps1, etc.) + 4 loose hex-named bundle files + `tweaker_manual_install.zip` + `lighting_tweaker_20260516/` pre-rename snapshot of `verminious_dreams_lighting` + the dir's own `README.md` and `ANTIGRAVITY.md` | Self-flagged for deletion in its own README. Fully superseded by `VMBLauncher.exe`. |
| `root-misc/` | `bundleHistory.dat` (old VMB state, 203 B), `launcher_screenshot.png` (1 MB GUI reference), `readme.txt` (generic SDK readme — self-flagged for archival in its first line) | Stale by ~3 weeks, no active references. |
| `backups/` | `chaos_wastes_tweaker_localization.lua.v0726.bak` (manual restore-point from ct v0.7.26), `verminious_dreams_lighting_item_preview.png.bak` (pre-resize 1.3 MB original) | `.bak` extension; not glob-matched by any `.package` file. |
| `legacy_deploy_scripts/` | `deploy_all.ps1` + 3 thin shims (`deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1`) | Wholly superseded by `VMBLauncher.exe deploy <mod>`. The 3 shims depended on `deploy_all.ps1` so all 4 archive together as one unit. The 5 `upload_*.ps1` wrappers stay at root — they add visibility-regression guards beyond the launcher. |

## Not touched (yet)

- `tweaker/` legacy mod tree — flagged for archival in audit Section A but
  awaits explicit maintainer sign-off.
- `cosmetics_tweaker/`'s 13 ephemeral diagnosis `.md` files — active host/client
  visual-sync investigation; archive once concluded.
- `_tools/extract_all_bundles.ps1` — active reusable script; could fold into
  `tools/` for naming consistency but no urgent need.
