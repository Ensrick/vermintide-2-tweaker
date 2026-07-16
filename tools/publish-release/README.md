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
  clobbered through the resolved numeric release/asset IDs; sibling assets are untouched.
- If the tag's release does not exist yet (first ship of a new day), the sibling zips are
  **carried forward** from the latest release (downloaded, sha256-verified against their carried
  manifest entries, re-uploaded), because vt2-mod-updater resolves every `asset_filename`
  against ONE release — each release must stay self-contained. A sibling entry whose asset is
  missing from the base release is dropped with a warning; a full publish restores it.
- A `-Mods` name not present in `tools/mod-inventory.psd1` fails loudly (typo guard).

Known residual: two concurrent filtered publishes race on `manifest.json` (last clobber wins,
computed from the manifest each fetched at its own start). The pre-filter behavior had the same
race across *all* assets; serialize ships if it ever matters.

### Degraded release-by-tag endpoint (issue #651)

Filtered publishing resolves the canonical `GET /releases/tags/{tag}` route first. A 404, network
error, 408, 429, or 5xx response triggers at most five 100-release list pages and requires a
case-sensitive exact `tag_name` match. This confirms a true 404 before creation and prevents a
route-specific false 404 from creating a duplicate. Multiple matches, a failed list request, or
five full pages without a match are **unavailable**, not absent; the tool refuses to create or
mutate anything while release identity is uncertain.

Once resolved, `manifest.json` and carry-forward zips download through their asset IDs. Existing
filtered assets are deleted by exact name/asset ID and uploaded through the numeric release ID,
with `manifest.json` last. The broken tag route is never reused, sibling assets remain untouched,
and staged provenance/hash validation still runs before mutation. Offline coverage:

```powershell
.\qa\check_github_release_fallback.ps1 -SelfTest
```

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
  "manifest_schema": 2,
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
      "visibility": "public",
      "source_commit": "0123456789abcdef0123456789abcdef01234567",
      "source_state": "clean",
      "builder": {
        "name": "VMBLauncher",
        "version": "1.2.3"
      },
      "bundle_files": [
        {
          "filename": "209fb8c3c0a8c3a4.mod_bundle",
          "sha256": "f3c1e6f691e14604711a446c8fe7090d79d7bce0b8c8035bd28a56738d937cb2"
        },
        {
          "filename": "ct.mod",
          "sha256": "616ddd4ccb968d2f858ee8d5a6311998e9f07194076c30940e365d1ee295e67f"
        }
      ]
    }
  ]
}
```

The updater fields through `visibility` retain their original meaning. The
schema-2 provenance fields are additive; consumers that ignore unknown JSON
fields continue to work. If a consumer starts depending on these fields, mirror
them in `vt2-mod-updater`'s `Models/ReleaseManifest.cs` and retain compatibility
with older releases.

`source_commit` is the repository `HEAD` used as the build baseline.
`source_state` is `clean` only when the mod's source paths match that commit;
generated `bundleV2/` changes are excluded. A `dirty` entry is intentionally
truthful transitional metadata, not proof that the commit alone reproduces the
bundle. Commit-before-build (or another immutable source snapshot identifier)
is still required before the project can promise exact commit-to-bundle
reproduction.

`builder.name` is fixed to `VMBLauncher`, preserving it as the only sanctioned
builder. `builder.version` comes from the launcher's Windows ProductVersion or
FileVersion metadata. `bundle_files` records every raw top-level VMB output
(`.mod_bundle` and `.mod`) by leaf filename and lowercase SHA-256. Its hashes
describe the raw files inside the zip, while the existing entry-level `sha256`
continues to describe the downloadable zip itself.

Before any GitHub mutation, `publish-release.ps1` validates every newly staged
entry against the copied bytes in `.release-stage`. A filtered publish carries
older sibling entries verbatim; pre-schema provenance is allowed with a warning
until that sibling is rebuilt, but a newly staged entry without complete
provenance is a hard failure. This makes the migration incremental without
rewriting releases or rebuilding unrelated mods.

Offline validator self-test and manual validation:

```powershell
.\qa\check_release_manifest.ps1 -SelfTest
.\qa\check_release_manifest.ps1 -ManifestPath .release-stage\manifest.json -StageRoot .release-stage
.\qa\check_release_reproducibility.ps1 -SelfTest
```

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

## Before bundle tracking can stop

This phase does not delete or ignore any tracked bundle. Stop tracking generated
outputs only after all of these are complete:

1. Publish at least one clean, schema-2 manifest entry for every active release
   mod, with no carried pre-transition warnings.
2. Make the release source immutable before the build so every entry records
   `source_state: clean`, then verify a fresh checkout of `source_commit` builds
   byte-identical raw bundle files with the recorded VMBLauncher version.
3. Teach `vt2-mod-updater` and bisect/recovery documentation how to select a
   release by source commit and verify each raw file, while retaining legacy
   manifest compatibility.
4. Add the generated output ignore rules in a coordinated transition commit and
   confirm VMBLauncher can bootstrap a checkout with no tracked `bundleV2`
   files. Keep genuine source assets in Git or Git LFS.
5. Preserve existing Git history initially. Consider history rewriting only as
   a separate, coordinated decision after measuring the reproducibility and
   clone-size results.

### Transition audit and fresh-checkout proof

The clean-source requirement cannot safely become a late
`publish-release.ps1` failure. The canonical `ship.ps1` sequence currently
builds, deploys, and uploads before the source commit is created. A dirty-source
failure in the GitHub-release step would therefore discover the problem only
after Workshop had already changed.

Until a maintainer explicitly approves a commit-before-build ship transaction,
run the read-only preflight report before building:

```powershell
.\qa\check_release_reproducibility.ps1 -Mod <folder-or-mod-id> -AuditOnly
```

Exit 0 means the selected mod's source paths match `HEAD`; `bundleV2/` changes
are excluded because they are generated outputs. Exit 2 lists the source
changes that prevent `HEAD` from being an immutable build input. This audit is
deliberately not wired into `ship.ps1` yet: doing so would make the documented
edit-then-ship workflow unshippable without also deciding commit/push failure,
upload failure, retry, and rollback policy.

After a clean schema-2 entry has been published, prove it from a separate fresh
checkout. Use the exact recorded commit and launcher version; configure only
ignored machine-local files, and do not deploy or upload:

```powershell
git clone --no-local https://github.com/Ensrick/vermintide-2-tweaker.git C:\temp\vt2-repro
git -C C:\temp\vt2-repro checkout --detach <manifest-source_commit>
Copy-Item C:\temp\vt2-repro\.vmbrc.example C:\temp\vt2-repro\.vmbrc

.\qa\check_release_reproducibility.ps1 `
  -Mod <folder-or-mod-id> `
  -CheckoutRoot C:\temp\vt2-repro `
  -ManifestPath <downloaded-manifest.json> `
  -LauncherPath <recorded-VMBLauncher.exe>
```

The verifier first requires clean mod source at the manifest's exact
`source_commit`, requires `builder.name: VMBLauncher` and an exact launcher
version match, then invokes only `VMBLauncher build --clean` through an isolated
temporary settings file whose `ProjectRoot` is the fresh checkout. Every raw
`.mod_bundle` and `.mod` filename and SHA-256 must match `bundle_files`; missing,
extra, or changed output fails the proof. It never deploys, uploads, edits
Workshop state, or treats a zip hash alone as reproducibility evidence.

**Maintainer decision still required:** reorder the canonical transaction so
the exact release source is committed (and decide whether it must also be
pushed) before VMBLauncher builds. Define what happens if build, Workshop
upload, GitHub publication, or the eventual source push fails after that point.
Only then should the audit become a blocking `ship.ps1` preflight and newly
staged manifests reject `source_state: dirty`.

## Mod inventory

The mod list lives in `tools/mod-inventory.psd1` (single source of truth, shared with
`tools/mod-lint/lint-mod.ps1` + `qa/check_cfg.ps1`). When you add a new published mod to the
repo, append it there.

Inventory entries are required to have a live folder and matching `itemV2.cfg`; every active
root mod with an `itemV2.cfg` must be present. `qa/check_mod_inventory.ps1` blocks missing,
retired, duplicate, or cfg/README-drifted records before release selection. The frozen
`tweaker` monolith is the only explicit non-pipeline exception. The friends-only
`weapon_tweaker_dev` mirror is active and parity-gated.

Script-internal gotcha: the inventory variable in the .ps1 is named `$releaseSet`, NOT `$mods` —
PowerShell variable names are case-insensitive, so `$mods` silently overwrites the `$Mods`
parameter (live ship failure 2026-07-13; `ship.ps1 -SelfTest` guards the invariant).
