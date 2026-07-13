# publish-release

Builds published VMB mods in this repo, zips each bundle, writes a `manifest.json`, and
publishes the set as a GitHub release on
[`Ensrick/vermintide-2-tweaker`](https://github.com/Ensrick/vermintide-2-tweaker/releases).

The release is consumed by the [vt2-mod-updater](https://github.com/Ensrick/vt2-mod-updater)
desktop app, which friends use to keep their Steam Workshop folders synced to the latest
builds without waiting on Workshop propagation.

## Usage

```powershell
.\publish-release.ps1                       # FULL mode: build all mods + create release with date-stamped tag
.\publish-release.ps1 -Tag mods-2026-05-21  # explicit tag
.\publish-release.ps1 -SkipBuild            # reuse existing bundleV2/ output (faster repeat runs)
.\publish-release.ps1 -DryRun               # build + stage but don't push to GitHub
.\publish-release.ps1 -Mods weapon_tweaker  # FILTERED mode (issues #436/#493): touch ONLY the named
                                            # mods (folder name or ModId, comma-separate for several)
```

Requires:

- `gh` CLI authenticated for `github.com` as `Ensrick`.
- `VMBLauncher.exe` present (built via `tools/vmb-launcher/publish.ps1 -SkipOpen` first).
- PowerShell 7+ (so `Compress-Archive` and `ConvertTo-Json` behave).

## Two modes (issues #436 / #493)

**FULL (no `-Mods`)** — the legacy behavior, unchanged: lint the whole repo, build + stage every
inventory mod, write a fresh manifest from live source, `gh release create`. Run it only when the
whole working tree is release-clean: it publishes whatever every mod's source builds to *right
now*, so a sibling mid-edit gets published with a version label that was never shipped to
Workshop (the issue #436 mislabel), and any mod's broken WIP fails the entire run (issue #493).

**FILTERED (`-Mods <names>`)** — what `ship.ps1` passes. Only the named mods are linted, built,
staged, and uploaded; sibling mods are never rebuilt, restaged, or re-uploaded:

- The lint gate is scoped to the named mods, so a sibling's WIP lint error cannot block the run.
- Sibling `manifest.json` entries are carried **verbatim** from the release's existing manifest
  (the version + sha256 of what was *actually published*), never re-read from live source.
  Base-manifest preference: the target tag's own manifest, else the latest release's. No base
  manifest reachable = hard fail (run a full publish once first). Filtered mode therefore needs
  network even with `-DryRun`.
- If the tag's release already exists, the staged zip(s) + merged manifest are
  `gh release upload --clobber`-ed; sibling assets are untouched.
- If the tag's release does not exist yet (first ship of a new day), the sibling zips are
  **carried forward** from the latest release (downloaded, sha256-verified against their carried
  manifest entries, re-uploaded), because vt2-mod-updater resolves every `asset_filename`
  against ONE release — each release must stay self-contained. A sibling entry whose asset is
  missing from the base release is dropped with a warning; a full publish restores it.
- A `-Mods` name not present in `tools/mod-inventory.psd1` fails loudly (typo guard).

Known residual: two concurrent filtered publishes race on `manifest.json` (last clobber wins,
computed from the manifest each fetched at its own start). The pre-filter behavior had the same
race across *all* assets; serialize ships if it ever matters.

## When to run

**After every Workshop upload.** Per the user's standing rule: "from here on out, claude will
also build the latest as well and make sure the pre-built mod files are on github, in addition
to deploying and building, and uploading to the workshop whenever a mod is updated."

The canonical path is `tools\ship\ship.ps1 -Mod <name>`, which invokes this script as
`publish-release.ps1 -Tag mods-<today> -Mods <name> -SkipBuild` (the ship's step 2 built the
bundle seconds earlier, so the release asset is byte-identical to the bundle that just went to
the Workshop). Manual equivalent for one mod:

```powershell
& $vmblauncher all <mod>                                    # build + deploy + Workshop upload
.\tools\publish-release\publish-release.ps1 -Mods <mod>     # then update ONLY this mod's release asset
```

Use FULL mode (no `-Mods`) only for a deliberate whole-set refresh of a release-clean tree —
e.g. after retiring/adding a mod, or to restore a dropped carry-forward entry.

## Manifest schema

```json
{
  "release_tag": "mods-2026-05-21",
  "published_at": "2026-05-21T18:00:00Z",
  "mods": [
    {
      "mod_id": "ct",
      "friendly_name": "Chaos Wastes Tweaker",
      "workshop_id": "3712929235",
      "version": "0.7.80-alpha",
      "asset_filename": "ct.zip",
      "sha256": "228ed038b0a243256121c52df7ed67dcb85479b3039c261099a4f3e191d38e08",
      "visibility": "public"
    }
  ]
}
```

If you add/remove a field here, mirror the change in `vt2-mod-updater`'s
`Models/ReleaseManifest.cs` — the schemas are coupled.

## Bundle integrity

Each `mods[]` entry carries an `sha256` field — the SHA-256 digest of the corresponding
`<mod_id>.zip` asset, encoded as lowercase hex (64 characters, `[0-9a-f]`). The hash is
computed over the raw zip bytes (the asset uploaded to the release), produced by
`Get-FileHash -Algorithm SHA256` immediately after `Compress-Archive`.

`vt2-mod-updater` hashes each downloaded zip and compares against this field before
extracting. Mismatch refuses the bundle, retries once, then surfaces a user-visible
warning if both attempts fail. This is the second-line gate against the known
`ugc_tool` "Upload finished" false-success bug (consumers don't go near ugc_tool, but
they pull the same release assets through GitHub's CDN, which has its own corruption
windows).

Backwards compatibility: older consumers that don't know about `sha256` ignore the
field. Older manifests without the field cause newer consumers to skip integrity
verification with a debug log entry — not a hard error.

## Mod inventory

The mod list lives in `tools/mod-inventory.psd1` (single source of truth, shared with
`tools/mod-lint/lint-mod.ps1` + `qa/check_cfg.ps1`). When you add a new published mod to the
repo, append it there.

Mods with no `published_id` in their `itemV2.cfg` are auto-skipped, as are inventory entries
whose folder is missing (e.g. the archived `buff_tweaker`).

Script-internal gotcha: the inventory variable in the .ps1 is named `$releaseSet`, NOT `$mods` —
PowerShell variable names are case-insensitive, so `$mods` silently overwrites the `$Mods`
parameter (live ship failure 2026-07-13; `ship.ps1 -SelfTest` guards the invariant).
