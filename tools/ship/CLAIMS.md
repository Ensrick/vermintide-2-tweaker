# Ship / version claim broker

## Permanent reservations: prospective migration (#724)

The permanent-burn requirement is implemented in `claim-allocation.ps1`, but
**no live mod is activated by this source change**. The source-owned
`claim-allocation-policy.psd1` starts with an empty `EnabledMods` array. The
legacy behavior described below remains in effect for an unactivated mod with
no allocation state. It does NOT preserve abandoned numbers. Do not allocate
protected queued versions through that legacy lane while migration is pending.
The September 6 private reproduction established reuse after ordinary release
and stale takeover; older claims already deleted cannot be reconstructed from
the current directory. Source-plus-one is not historical reconciliation.

An activated mod has one `<mod>.allocation` file beside its unchanged four-field
`<mod>.claim`. Its numeric floor survives release, stale takeover and failure;
the next patch is above both that floor and the current source numeric version,
using the source's release suffix. Its current reservation binds the exact
claim bytes/SHA-256, owner, version and original timestamp. Same-owner LIVE
reclaim is idempotent. Stale adoption never renews a timestamp; replacing stale
work requires a new higher version and regenerated artifacts/receipts.

### Explicit reviewed migration (separate authorization)

This operation is available for a reviewed migration, not run by builds or
implicitly by Acquire/Verify. Source merge alone does not complete #724.

1. Quiesce older broker writers for the exact mod. Review the current source,
   retained claims, pending artifacts and known historical reservations. Choose
   a conservative numeric floor at least as high as all known allocations,
   documenting any irrecoverable historical uncertainty. Never sweep the shared
   directory: other projects, including Doomrocket/Pusfume, own their records.
2. Record the exact current claim's SHA-256 (raw UTF-8 bytes), or the literal
   `absent` only when review established that absence. A review reference is an
   audit link, not itself an authorization credential. The operator must have
   explicit migration approval; do not infer it from a stale claim.
3. Run the canonical broker initialization for ONLY that mod:

   ```powershell
   .\tools\ship\claim.ps1 -Mod <mod> -InitializeAllocation `
       -ReviewedFloor <major.minor.patch> `
       -ExpectedClaimSha256 <exact-sha256-or-absent> `
       -ReviewReference <reviewed-issue-or-PR-URL>
   ```

   It refuses an existing ledger, a changed/malformed claim, or a floor below
   source/claim. It adopts existing bytes without rewriting them, renewing them,
   releasing ownership, or asserting their artifact validity. A newly appearing
   old-writer claim causes failure with the floor retained. Initialization
   never recovers unknown past history by guessing.
4. Activate ONLY that mod in `claim-allocation-policy.psd1` through a reviewed
   protected source PR. Between initialization and activation, the new broker
   refuses ordinary operations for that mod. Once activated, missing/corrupt
   history refuses operations rather than falling back. If initialization or
   activation is interrupted, preserve all files and reconcile explicitly;
   never delete a ledger or lower its floor to unblock work.
5. Verify the adopted claim. A stale result remains stale under both the broker
   and approved launcher's existing 24-hour check. Acquire a NEW higher version
   for stale/abandoned work; bump, rebuild, review, merge and publish normally.
   Pending artifacts bound to approved launcher 0.6.1 are not reinterpreted by
   0.6.2 or by this migration. There is no same-allocation renewal command.

### Serialization, interruption and old clients

Strict operations take a path-qualified `Global` per-mod mutex, then the legacy
`Local` mutex. These are bounded leaf locks: they acquire no machine/release
lease and return before callers proceed. An existing ship may nest this leaf
below its machine/release ownership; never hold it while starting a ship. The
global lock serializes new brokers across Windows sessions. It does NOT make
an older cross-session broker participate.

Existing claim proof/deletion therefore uses the existing native exact-delete
handle owner: read+DELETE access, share READ only, single-link regular-file
proof, same-handle hash/read, and delete-on-close. The handle stays held while
the ledger is durably retired. An old writer cannot replace/delete/write the
claim between proof and deletion even if it ignores the new mutex. Absence is
not a lock: if an old writer wins `CREATE_NEW` after the new floor was persisted,
the new operation fails and retains the burned floor and foreign claim.

State writes flush a unique same-directory pending file to disk, atomically
move/replace it under the Global owner, then read back. The byte comparison is
drift detection, not a claim of lock-free CAS. Reserve is persisted BEFORE claim
creation; retire is persisted BEFORE exact deletion. A hard process death may
burn an extra number; it may not permit reuse. A partial/corrupt claim or state
stops for explicit reconciliation. Orphan `.pending` files are not authority.
These fixtures establish process-interruption behavior, not storage-device or
power-loss guarantees beyond Windows filesystem semantics.

Approved launcher 0.6.1/0.6.2 still read the original four-field wire; they are
not allocators and do not understand the sidecar. Canonical activated Verify
rejects unbound old-broker claims or replayed retired claims before publication
authorization. Very old checkouts can still run their old allocator; they are
not a supported way to bypass migration. Canonical publication's clean current
default-head and hosted-receipt gates remain unchanged. No live claim,
allocation state, version, artifact or launcher is changed by this source PR.

`qa/check_permanent_claim_allocation.ps1 -SelfTest` exercises real private
broker dispatch, explicit initialization, stale adoption, release/reclaim,
native cross-mutex-domain exclusion, two processes, hard owner death, corruption
and interrupted writes. It is auto-discovered by `qa/run_selftests.ps1`.

`tools/ship/claim.ps1` is an atomic mutual-exclusion lock over a mod's next
build. It stops parallel Claude sessions on this machine from allocating the
**same** next `MOD_VERSION` and uploading competing bundles.

## Why it exists

Multiple sessions running on one machine repeatedly picked the same next patch
version and shipped colliding Workshop bundles, each forcing a manual
"reconciliation build". Documented incidents:

- cosmetics `0.9.143` **and** `0.9.145` allocated in parallel
- weapon_tweaker `0.12.273-beta`
- weapon_tweaker_dev `0.12.274-dev`

The `.in_progress/` sentinels (see `CLAUDE.md` "Multi-agent coordination") are
**advisory awareness** only. This broker is the enforced version-allocation lock
that `ship.ps1` refuses to ship without.

## The lock

Acquiring a claim is an **atomic exclusive file create** of
`%APPDATA%\VMBLauncher\ship_claims\<mod>.claim`. This is the machine-global
directory used by VMBLauncher, so separate git worktrees, the outer ship
wrapper, and nested launcher processes all consult the same authority. The
create uses the OS `CREATE_NEW` disposition: exactly one racer's create can
succeed; every other racer gets `IOException` and reports contention.

The repo-local `.ship_claims/` directory is a tracked legacy documentation
pointer only. It is not the default claim authority. `-ClaimsDir` exists for
isolated tests and diagnostics, not normal shipping.

### Claim file format

```
# VT2 ship/version claim -- see tools/ship/CLAIMS.md
mod = weapon_tweaker
version = 0.12.274-beta
session = <explicit/Claude/Codex owner id, or deterministic worktree id>
created = 2026-07-18T04:12:33Z
```

In the legacy/unactivated lane, `version` is the allocated **next** patch version: the mod's current
`MOD_VERSION` with `PATCH + 1`, preserving the `-dev` / `-beta` / `-alpha` /
`-rc` suffix. 4-segment versions are rejected (normalize per the `CLAUDE.md`
"Format: 3-segment semver only" rule before claiming).

`session` is an enforced owner credential. Resolution order is
`VT2_SHIP_SESSION_ID`, `CLAUDE_SESSION_ID`, `CODEX_THREAD_ID`, then a stable
fingerprint of the invoking worktree for a normal manual shell. Verification
and release both require the exact same owner; a foreign task cannot consume or
erase a same-version live claim.

## Usage (claim -> bump -> ship -> release)

```powershell
# 1. Claim the mod. This reads its CURRENT MOD_VERSION and allocates the next
#    patch, printing it. Claim BEFORE you bump the source.
.\tools\ship\claim.ps1 -Mod weapon_tweaker
#    -> Allocated version: 0.12.274-beta

# 2. Set  local MOD_VERSION = "0.12.274-beta"  in the mod's lua, make your
#    changes, write the CHANGELOG entry.

# 3. Build the tracked release artifact without deploying or publishing.
.\tools\ship\ship.ps1 -Mod weapon_tweaker -BuildOnly

# 4. Commit source + bundle + the generated .build-receipt.json together, push,
#    open the PR, pass hosted qa-gate, and merge. Any relevant source edit after
#    BuildOnly invalidates the receipt and requires another BuildOnly run. Raw
#    working bytes must also be reproducible from the Git-clean staged blobs.

# 5. From a clean worktree at the exact live default-branch commit, ship.
#    ship.ps1 verifies the same live claim, merged PR, hosted qa-gate, and
#    freshly rebuilt bundle bytes. It records release provenance, then gives
#    VMBLauncher the exact five-minute receipt hosted on that GitHub release.
#    The launcher independently downloads those bytes, rechecks root, commit,
#    owner, mod/version, cfg/source hashes, and the exact SDK-staged content
#    immediately before ugc_tool.
.\tools\ship\ship.ps1 -Mod weapon_tweaker

# Free your own claim manually (abandoned work, or ship never ran):
.\tools\ship\claim.ps1 -Mod weapon_tweaker -Release
```

First-upload bootstrap is the exception to automatic release. When the reviewed
cfg carries `published_id = 0L`, the successful bootstrap writes only Steam's
assigned ID, stops before lifecycle labeling/test-readiness output, and keeps
the claim held. Rerun canonical BuildOnly so the refreshed receipt binds the
assigned-ID cfg, then commit the ID-only cfg and receipt, pass protected PR QA,
merge, and run the ordinary canonical ship from the new live default HEAD. The
root may remain byte-identical; the narrow atomicity exception accepts only
`0L` to one positive ID with every other cfg byte and `MOD_VERSION` unchanged.
Releasing the claim earlier permits another clean worktree to create a second
Workshop item.

Claim **before** bumping the source: the broker allocates from the current (not
yet bumped) version. Re-running `claim.ps1 -Mod <name>` in the same session is
idempotent -- it returns the version you already hold, it does not allocate again.

## ship.ps1 enforcement

Near the top of a ship (after param parsing, before the QA gates and before any
build/deploy/upload) `ship.ps1` calls
`claim.ps1 -Mod <name> -Verify -ExpectedVersion <source MOD_VERSION>` and aborts
when the claim is:

- **absent** -- no one claimed this mod; run `claim.ps1 -Mod <name>` first.
- **mismatched** -- the claim's version is not the source `MOD_VERSION` being
  shipped (another session likely allocated a different number).
- **stale** -- the claim is older than the stale window and no longer valid.
- **foreign-owned** -- the version matches, but another Claude/Codex/manual
  worktree owner created the claim.

On a fully successful ship, `ship.ps1` releases its own claim automatically.
Foreign releases fail closed and leave the original claim intact.

### `-NoClaim`

`-NoClaim` is accepted only with `-BuildOnly`, which cannot deploy or upload.
Workshop publication cannot bypass the machine-global claim.
The inverse is equally important: a matching claim is version coordination,
not publication authorization. Direct launcher `upload`/`all`, GUI
publication, and caller-authored JSON cannot publish on a claim alone.

## Stale policy

A claim older than **24 hours** (`-StaleHours`) is stale. Activated allocation
retains its floor and allocates a fresh higher version; it never renews the old
timestamp. The remaining paragraph describes legacy ownership behavior. This covers a normal
feature-branch review and hosted-QA cycle without releasing the reserved
version. A new claimant will
break a stale claim (deleting it and taking its own), and says so in the output.
This keeps a crashed or abandoned session from wedging a mod's version stream
forever. A stale claim never authorizes a ship -- `ship.ps1` treats it as absent.

## Cross-worktree ownership

Codex/Claude task identities survive child processes and worktree changes. A
manual multi-worktree release must set one explicit identity before both claim
and ship, for example `$env:VT2_SHIP_SESSION_ID = 'wt-0.12.274-beta'`. A
different owner cannot spend or erase the claim even when the version matches.

Claims are about version allocation; `.in_progress/` sentinels are advisory
editing awareness. They remain complementary.

## Self-test

`claim.ps1 -SelfTest` runs offline fixtures: allocate-increment (with 4-segment
rejection), timestamp round-trip + staleness, idempotent re-claim vs contention,
stale-break, release (own + idempotent), the ship.ps1 verify contract, and a
foreign-owner verify/release refusal, nested-authority visibility, plus a real
two-worktree/two-process race asserting exactly one process acquires. It is wired into
`qa/run_selftests.ps1` (and therefore `qa/run_all.ps1` full pass + CI). Exit
codes: 0 pass, 2 regression.
