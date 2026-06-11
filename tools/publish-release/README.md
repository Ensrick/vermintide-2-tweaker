# publish-release

Builds every published VMB mod in this repo, zips each bundle, writes a `manifest.json`, and
publishes the whole set as a GitHub release on
[`Ensrick/vermintide-2-tweaker`](https://github.com/Ensrick/vermintide-2-tweaker/releases).

The release is consumed by the [vt2-mod-updater](https://github.com/Ensrick/vt2-mod-updater)
desktop app, which friends use to keep their Steam Workshop folders synced to the latest
builds without waiting on Workshop propagation.

## Usage

```powershell
.\publish-release.ps1                       # build all mods + create release with date-stamped tag
.\publish-release.ps1 -Tag mods-2026-05-21  # explicit tag
.\publish-release.ps1 -SkipBuild            # reuse existing bundleV2/ output (faster repeat runs)
.\publish-release.ps1 -DryRun               # build + stage but don't push to GitHub
```

Requires:

- `gh` CLI authenticated for `github.com` as `Ensrick`.
- `VMBLauncher.exe` present (built via `tools/vmb-launcher/publish.ps1 -SkipOpen` first).
- PowerShell 7+ (so `Compress-Archive` and `ConvertTo-Json` behave).

## When to run

**After every Workshop upload.** Per the user's standing rule: "from here on out, claude will
also build the latest as well and make sure the pre-built mod files are on github, in addition
to deploying and building, and uploading to the workshop whenever a mod is updated."

The canonical sequence for a single mod update is now:

```powershell
& $vmblauncher all <mod>                      # build + deploy + Workshop upload
.\tools\publish-release\publish-release.ps1   # then publish the GitHub release
```

Or for a batch of mods updated in one session, run `publish-release.ps1` once at the end —
it always packages every mod's current bundle, so a single release covers all changes.

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

The mod list is hard-coded near the top of the .ps1. When you add a new published mod to the
repo, append it to the `$mods` array.

Mods with no `published_id` (unpublished, e.g. `modded_progression`) are auto-skipped.
