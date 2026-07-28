# publish-release

Builds published VMB mods in this repo, zips each bundle, writes a `manifest.json`, and
publishes the set as a GitHub release on
[`Ensrick/vermintide-2-tweaker`](https://github.com/Ensrick/vermintide-2-tweaker/releases).

The release is consumed by the [vt2-mod-updater](https://github.com/Ensrick/vt2-mod-updater)
desktop app, which friends use to keep their Steam Workshop folders synced to the latest
builds without waiting on Workshop propagation.

## Usage

This is an authorization-bound internal publication component. Routine releases
must enter through `tools\ship\ship.ps1 -Mod <name>`; do not invoke this publisher
directly or hand-author its authorization/dependency parameters.
The operator sequence is owned by `PROJECT_STANDARDS.md` section 6.6. This
component opens no GUI and is never a substitute for the owner's merge-first
claim, `-BuildOnly`, protected-merge, and clean-default-HEAD phases.

Caller JSON is correlation evidence, never authority. Immediately before any
release mutation, this component re-queries the live default branch, exact
merged PR SHA, and successful hosted `qa-gate` for the exact source commit.
New zip and receipt inputs are reconstructed from that commit's Git blobs, not
hashed from mutable working-tree paths. Missing, forged, stale, emergency, or
contradictory evidence fails closed.

`ship.ps1` also supplies `-LauncherPath`, `-LauncherSource`, and
`-LauncherApprovalAnchor` internally. That snapshot is the exact approved
VMBLauncher dependency used for the Workshop phase; the release phase
revalidates its path/provenance without rereading mutable global settings
before recording the builder version. Do not hand-author those parameters for
routine publishing.

Publication requires VMBLauncher 0.5.7 or newer with
`hosted-publication-receipt-v3`, `git-commit-blob-snapshot-v1`, and
`locked-upload-snapshot-v1`, plus
`constrained-first-upload-bootstrap-v1`. The launcher release must land and be
installed before this monorepo guard lands. Both `ship.ps1` and this publisher
probe those capabilities before any GitHub release mutation. Release zip,
receipt, and manifest inputs are captured once as immutable bytes; new releases
remain drafts until those bytes are uploaded, with the manifest last. Before
mutation, every entry inside each immutable ZIP snapshot is independently
hashed against the commit-derived manifest bundle records; a staged-file swap
during compression cannot be hidden by restoring the path afterward.
The complete lookup/carry-forward/manifest/release-ID mutation is also guarded
by one machine-global mutex. Per-mod claims do not serialize two different mods,
so this prevents concurrent ships from reading the same daily manifest and
silently erasing one another's new entry.

First Workshop item creation stays inside canonical ship with a distinct
`workshop_bootstrap` receipt over the exact reviewed commit carrying
`published_id = 0L`. VMBLauncher keeps content files/directories, preview, and
tool bytes pinned, opens only the staged cfg/parent replacement boundary
immediately before ugc_tool, validates the complete output, and compare-and-swaps only Steam's
nonzero ID into a source cfg that still matches the authorized Git blob. The
outer ship then stops before test-ready labeling and retains the claim until the
ID-only commit passes protected review, merges, and receives an ordinary ship.

Requires:

- `gh` CLI authenticated for `github.com` as `Ensrick`.
- `VMBLauncher.exe` present in an approved location: this invoking checkout,
  VMBLauncher's configured `ProjectRoot`, the primary git worktree, or the
  explicit `VT2_SHIP_VMB_LAUNCHER` operator override. A set but invalid override
  fails instead of silently falling back.
- PowerShell 7+ (so `Compress-Archive` and `ConvertTo-Json` behave).

Clean linked worktrees do not need the ignored launcher binary copied into
their own tree. Standalone publishing uses the same resolver as `ship.ps1` and
fails closed if no approved executable exists. The offline contract runs under
both Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\qa\check_vmb_launcher_path.ps1 -SelfTest
```

## Two modes (issues #436 / #493)

**FULL (no `-Mods`)** — lint the whole repo, build every inventory mod as a
reproducibility gate, stage exact source-commit bundle blobs, and write a fresh
manifest. It publishes the selected commit bytes, not whatever a mutable path
contains at check time; any mod's broken build still fails the entire run.

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

**Before every Workshop upload, inside the canonical ship transaction.** The
authorized release record must exist before the launcher is allowed to mutate
Workshop.

The canonical path is `tools\ship\ship.ps1 -Mod <name>`. It invokes this script
with exact authorization evidence after clean tracked-bundle parity succeeds and
before the final launcher upload. There is no supported manual equivalent.

FULL mode (no `-Mods`) is reserved for authorization-bearing internal automation
performing a deliberate whole-set refresh of a release-clean tree, such as after
retiring or adding a mod. It is not a separate operator entry point.

Source pull requests must link tracker work with `Refs #N` before publication.
Do not use GitHub auto-closing keywords: a successful release or merge is not
the user-verification receipt required to close an in-game issue.
Repository-only issues are closed after their named deterministic check passes.

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
      "publication_authorization": {
        "mode": "hosted_qa",
        "source_commit": "0123456789abcdef0123456789abcdef01234567",
        "checked_at_utc": "2026-05-21T17:59:00Z",
        "default_branch": "master",
        "default_branch_commit": "0123456789abcdef0123456789abcdef01234567",
        "merged_pr_number": 724,
        "qa_check": "qa-gate",
        "qa_check_url": "https://github.com/Ensrick/vermintide-2-tweaker/actions/runs/1",
        "qa_completed_at_utc": "2026-05-21T17:58:00Z"
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
`source_state` must be `clean`; dirty provenance is rejected. The publisher
also checks whole-worktree cleanliness independently before mutation.

`builder.name` is fixed to `VMBLauncher`, preserving it as the only sanctioned
builder. `builder.version` comes from the launcher's Windows ProductVersion or
FileVersion metadata. `bundle_files` records every raw top-level VMB output
(`.mod_bundle` and `.mod`) by leaf filename and lowercase SHA-256. Its hashes
describe the raw files inside the zip, while the existing entry-level `sha256`
continues to describe the downloadable zip itself.

`publication_authorization` must be canonical `hosted_qa` evidence. Its source
and default-branch commits must equal the entry commit; the merged PR and exact
successful check are independently queried rather than trusted from this JSON.
The mutation-boundary correlation canonicalizes the QA completion timestamp to
UTC because PowerShell 7 deserializes ISO JSON dates as `DateTime` while Windows
PowerShell 5.1 retains strings; a genuinely different instant still fails.

Before any GitHub mutation, `publish-release.ps1` validates every newly staged
entry against the copied bytes in `.release-stage`. A filtered publish carries
older sibling entries and their SHA-256-verified assets verbatim. Historical
carried entries may predate provenance entirely, predate
`publication_authorization`, or record the historical dirty `source_state`;
those immutable transition fields warn instead of blocking a later unrelated
mod. Any provenance or authorization metadata that is present must still be
well-formed. Newly staged entries always require clean source and complete
hosted-QA authorization and fail hard otherwise.

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

The canonical transaction requires a clean, reviewed default-branch source
commit before build, proves the build reproduces tracked artifacts, records
authorized release provenance, and only then uploads to Workshop. The publisher
independently rejects dirty source as defense in depth. For a read-only audit:

```powershell
.\qa\check_release_reproducibility.ps1 -Mod <folder-or-mod-id> -AuditOnly
```

Exit 0 means the selected mod's source paths match `HEAD`; `bundleV2/` changes
are excluded because they are generated outputs. Exit 2 lists the source
changes that prevent `HEAD` from being an immutable build input. This audit does
not publish or mutate external state.

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

The canonical transaction is already ordered around immutable reviewed source:
run `ship.ps1 -BuildOnly`, commit source and the exact generated bundle together,
push, pass review and hosted `qa-gate`, merge, then run the final ship from a
clean checkout at the exact live default-branch HEAD. The publisher re-queries
that live state after lint, staging, and carry-forward downloads and immediately
before GitHub mutation. A failure leaves Workshop untouched; there is no
post-upload source commit or push.

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
