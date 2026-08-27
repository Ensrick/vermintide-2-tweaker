# Immutable review content manifests

`content-manifest.ps1` is the only supported way to freeze a bounded source
candidate for implementation/review handoff. It is noninteractive, works under
Windows PowerShell 5.1 and PowerShell 7, and never changes the reviewed
repository, its index, settings, installed mods, or Workshop state.

## Canonical use

Run from PowerShell. Supply the exact repository root, the full base commit ID,
and an explicit bounded set of repository-relative files:

```powershell
$root = 'C:\path\to\repository'
$base = git -C $root rev-parse HEAD

& C:\path\to\vermintide-2-tweaker\tools\review\content-manifest.ps1 `
    -RepositoryRoot $root `
    -BaseCommit $base `
    -ChangedSinceBase `
    -ManifestOut (Join-Path $env:TEMP 'candidate.vt2-manifest')
```

`-ManifestOut` must be a new path outside the reviewed repository; the tool
will not overwrite an existing evidence file. Omit it to write the canonical
manifest bytes to standard output, or use `-DigestOnly` when only the
digest/entry census is needed. `-PathFile` accepts a strict bounded UTF-8
one-path-per-line input when an explicitly curated array is inconvenient.
`-ChangedSinceBase` uses a repository-owned NUL-delimited byte collector, rather
than PowerShell's locale/encoding-sensitive native-output pipeline, to include
every tracked change from the exact base plus every untracked non-ignored file.
Defaults are 4,096 paths, 4,096 UTF-8 bytes per path, a 1 MiB aggregate path
set, and a 1 MiB path-list file.

Use this exact command shape in implementation, CI, and independent-review
lanes. Do not replace it with `Sort-Object`, a locale-dependent shell recipe, or
a hand-written hashing loop.

## Grammar

The canonical file is UTF-8 without BOM, LF-only, and always ends in LF:

```text
VT2-CONTENT-MANIFEST|1
BASE|<commit-id-byte-count>|<lowercase-full-commit-id>
COUNT|<entry-count>
P|<path-utf8-byte-count>|<percent-encoded-path>|<file-byte-count>|<lowercase-sha256>
D|<path-utf8-byte-count>|<percent-encoded-path>
```

Paths are normalized to forward slashes and sorted with
`StringComparer.Ordinal`. Percent encoding operates on UTF-8 bytes; only ASCII
letters, digits, `/`, `.`, `_`, and `-` remain literal. A missing working-tree
path is a deletion only when the exact base commit contains a blob at that path.
Unknown missing paths fail closed.

Colon-bearing paths are refused so an NTFS alternate data stream cannot be
presented as a Git working-tree file. External manifest output also refuses any
existing reparse component; a junction cannot alias an apparently external
destination back into the reviewed repository.

The aggregate SHA-256 covers every canonical byte, including the base commit
and final LF. The tool also emits `reviewer_compatibility_sha256` for safe paths;
that is the earlier `path|byte_length|lowercase_sha256`/LF recipe used by the
frozen #1429/#1430 reviews. It is evidence migration only, not the new authority.
Paths containing `|`, CR, or LF deliberately have no compatibility digest.

## Safety and regression coverage

The complete lexical path set, bounds, duplicate/case-collision checks,
out-of-root checks, and reparse checks finish before any candidate file is
opened or hashed. Present files are hashed through read-only handles. The tool
rejects directories and a repository root reached through a reparse point.

`qa/check_content_manifest.ps1` runs in normal QA and exercises en-US, tr-TR,
and invariant cultures; ordinal/culture-order divergence; Unicode, spaces,
CRLF content, empty files, untracked files, and deletions; every digest axis;
input bounds and hostile paths; plus frozen reviewer records for VMBLauncher
#1429 and updater #1430. Optional `-VmbSnapshotRoot` and
`-UpdaterSnapshotRoot` arguments re-hash the surviving external worktrees.
