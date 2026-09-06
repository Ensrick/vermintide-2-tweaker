# Public-release closure attestation policy (#1527)

This is an **offline policy component**, not a live close-event audit. No issue
is closed/reopened/commented on, and no workflow or retrospective enforcement
is installed by this change. The existing open lifecycle guard and PR closure
authorization remain unchanged. The future event adapter is still required.

## Trust boundary and API

Dot-source `public_release_closure_policy.ps1`, then call
`Get-VtPublicReleaseClosureDecision` with these explicit arguments:

- `Repository`: the trusted workflow's exact `owner/repository` coordinate.
- `Issue`: complete authenticated GitHub state, normalized to `Complete = true`,
  `repository`, positive `number`, `state`, `labels` (objects with `name`),
  `closedAt`, and `closureEventId`. The latter is the immutable ClosedEvent ID,
  not an issue number, delivery ID, mutable update time, or guessed counter.
- `CommentSnapshot`: `Complete = true`, `PinsComplete = true`, `ObservedAt`
  (UTC), and `Comments`, including the attestation, evidence, and every exact
  test card. Each comment has its API `databaseId`, raw `body`, `createdAt`,
  `updatedAt`; every exact card also needs boolean `isPinned`. The attestation
  needs authenticated `author.login` and `authorAssociation` metadata.
- `AttestationId`: the exact comment carrying the trusted structured decision.
  The caller chooses it explicitly; the policy never infers success from prose.
- `AuthoritySnapshot`: a trusted persisted **closure-time** record with
  `Source = 'deployed-source-contract/v1'`, `Complete = true`, `Repository`,
  `ClosedEventId`, `ClosedAt`, `PolicySourceCommit`, and `Authority`. The latter
  is the complete output of the existing deployed-source contract resolver,
  including its canonical inventory `Public` facts and source-derived routes.
  Generation, repository and time must match the issue. The policy does not
  download current releases or manufacture that historical authority.
- `EnforceFromUtc`: an explicitly configured rollout boundary. There is no
  hardcoded retrospective start date. `TrustedVerifier` defaults to Ensrick and
  RainReligion, additionally requiring OWNER, MEMBER or COLLABORATOR association.

**Authentication belongs to the caller.** Do not deserialize issue bodies into
these trusted API/authority metadata objects, accept `Complete` or `Public`
flags from commenters, execute PR-head policy in a privileged workflow, or
substitute a caller-supplied `PASS` result for the source-authority resolver.
The pure function validates bindings and completeness, not network signatures.
All input data must be read-only snapshots (not getters with external effects).
Completeness, pin, and Public flags require actual Boolean values, not strings,
numbers, or other truthy objects. Canonical artifact identities must be well
formed and unique by ModId, directory, and Workshop ID across the snapshot.
ModId case is preserved, including canonical `WOC`; case-colliding ModIds are
rejected and an attested lowercase alias cannot select an uppercase target.
Folder slugs remain lowercase. A source-resolver-authenticated unrelated legacy
row may carry an explicit `SourceCommit = null` with full `RootTree` and
`ModTree` provenance (the resolver validates its exact legacy pin). Omitted,
empty or malformed source identities are not legacy evidence. Such a row never
needs invented root-bundle metadata: when it predates that metadata, both
`RootBundle` and `RootBundleSha256` must be present and literally null together.
One null field, an omitted field, or malformed non-null data is unavailable;
modern commit-qualified rows retain both required exact root-bundle fields.
An unrelated legacy row never
qualifies as the actually verified target: the attestation still requires the
exact full source commit, and a tree hash cannot substitute for it. This is not
authority to synthesize legacy rows or bypass the deployed-source resolver.

The attestation is necessarily prepared for an observed closure generation;
its comment cannot predate that ClosedEvent. A later event adapter must handle
this protocol deliberately, rather than immediately reopening an issue while
its trusted attestation is still being recorded. That orchestration, retry,
state reread, and idempotent mutation policy are not implemented here.

## Exact attestation body

The whole comment is the heading `## PUBLIC RELEASE CLOSURE ATTESTATION`,
followed by one fenced `json` object. Its flat schema contains exactly:

| Fields | Meaning |
|---|---|
| `Schema` (integer 1), `Repository`, `IssueNumber` (positive integer) | Exact schema and issue scope |
| `ClosedEventId`, `ClosedAt`, `VerifiedAt` | Exact closure generation and actual observed verification time |
| `VerifierLogin`, `VerifierAssociation` | Must match the trusted attestation comment's authenticated author metadata |
| `CardId`, `CardSha256`, `EvidenceId`, `EvidenceSha256` | Distinct exact comments and SHA-256 of their raw UTF-8 bodies, with no newline/whitespace normalization |
| `Outcome` | Exactly `public-artifact-verified`; arbitrary PASS prose and older receipt formats are not authorization |
| `ModId`, `Dir`, `Stream`, `WorkshopId`, `Version` | The specific actually-verified target, not merely a public sibling elsewhere on the card |
| `SourceCommit`, `RootBundle`, `RootBundleSha256`, `AssetFilename`, `AssetSha256` | Exact canonical deployed source and artifact identity |

Every value except the two integer fields is a nonempty JSON string. IDs are
positive decimal strings, digests are lowercase hexadecimal, and times are
explicit UTC ISO-8601 ending in `Z`. Unknown, duplicate or escaped property
names, nested/array values, and attestations larger than 16 KiB of strict UTF-8
bytes are rejected. Invalid Unicode in any snapshot body is Unavailable; it is
never silently replaced before byte counting or evidence hashing.

The verifier attests their interpretation of the bound human evidence; the
evidence author need not be a maintainer (ordinary public users can verify).
The policy does not classify the evidence's prose. It requires the newest exact
test card to be the one and only pinned exact card, using the existing strict
`Get-VtLiveTestCardSelection` and deployed authority. The open-ready lifecycle
decision is deliberately not called: a Rain result consumes an open invitation
but is legitimate input to closure verification.

Chronology is based on **both creation and revision times**: the card's latest
revision cannot follow evidence creation; the evidence's latest revision cannot
follow `VerifiedAt`; verification cannot follow closure; the attestation cannot
precede closure. A later card/evidence edit cannot borrow an old creation time,
even when its body was changed back to the same text/digest.

## Results and persistence

`Status` is one of `Accepted`, `Rejected`, `Unavailable`, `NotApplicable`, or
`LegacyReviewRequired`. `Valid` is true only for Accepted. Every result has
`MayMutate = false`: this component never authorizes live mutations by itself.
Unavailable (partial comments/pins, missing authority or metadata, exceptions)
is an infrastructure condition, **not proof of a bad fix or permission to
reopen**. A complete non-public or already-open issue is NotApplicable.

Accepted returns the bound proof and a deterministic `ClosureKey` containing
repository, issue and ClosedEvent ID. Duplicate delivery of identical inputs
returns the same key/proof identity; a new closure generation needs a new
attestation. The future trusted adapter must persist authority provenance and
deduplicate on this generation, then reread issue state before any mutation.

Retain the authenticated closure-time authority snapshot after acceptance.
Do not replace it with the next release's authority: later publication does not
invalidate a previously verified artifact. Revalidation must still use complete
current comment metadata to detect edits/deletions, while retaining the original
closure-time artifact authority. Accepted proof is not an unsigned shortcut
which untrusted callers can submit instead of those inputs.

Future adapter integration must also retain the accepted closure-time card/pin
evidence: later harmless unpinning of a closed issue is not itself a regression
or permission to reopen. The current offline component strictly validates the
supplied card/pin snapshot; the adapter must deliberately reconcile preserved
acceptance evidence with current body-revision metadata before enforcement.
This consideration does not grant automatic reopening authority.

Historical closures before rollout return LegacyReviewRequired, not Rejected.
#1509 is legitimately verified/closed through an upstream VT2 correction; its
pre-schema evidence needs deliberate legacy migration, not automated reversal.
There is no requirement that the mod version increase after a report: the exact
public artifact must be verified. Conversely #1465's reviewed Dev code/build
alone cannot close a public-release issue. Public promotion authorization remains
an independent gate and is never granted by this policy.

Bounds: 2,048 comments; 1 MiB per comment; 16 MiB total comment bodies; 256
authority records. Caller truncation or exceeding these bounds is Unavailable.

## Offline verification

### Read-only GitHub collection

`tools/github/public-release-closure-collector.ps1` now supplies
`Get-VtGitHubPublicReleaseClosureAudit`. It is a library, not a workflow or an
autonomous issue-action adapter. Dot-sourcing it performs no collection. Call
it with the exact `Repository`, `IssueNumber`, `AttestationId`, configured
`EnforceFromUtc`, and the same trusted retained `AuthoritySnapshot` described
above. Optional `TrustedVerifier` retains the policy defaults. Missing or
mismatched closure-time authority remains Unavailable; the collector never
downloads today's release to manufacture a historical snapshot.

Its mandatory trusted `Request` scriptblock accepts `(Query, Variables)` and
returns the complete authenticated GitHub GraphQL envelope, including `data`
and any `errors`. The query is fixed and read-only. The transport must bind
authentication and HTTPS to GitHub, retain raw string timestamps/body text,
bound each request's duration and response bytes, and surface failures rather
than truncate or invent metadata. Do not source this callback, rollout date,
verifier list or authority from issue content. No shell/network transport is
installed by this slice; a later trusted caller owns that boundary.

One issue is collected twice, each time including all comments, author
association, raw bodies/revision times and Boolean pin states. Every page also
reads the issue identity/state/revision, complete labels, comment total and
the latest Closed/Reopened timeline event. A closed issue requires the last
event to be ClosedEvent with its immutable ID and matching closure time.
Partial responses, duplicate IDs, non-progressing cursors, metadata movement
during pagination, and any difference between complete passes are Unavailable.
Only identical passes become `Complete=true` inputs to the unchanged strict
policy. This detects observed races; GraphQL does not provide a cross-request
atomic snapshot and a mutation after collection remains possible. The future
action adapter still requires fresh state checks and generation-bound handling.

Bounds: 100 labels (reject if truncated), 100 comments per requested page,
2,048 comments, 1 MiB per body and 16 MiB aggregate per pass, 512-character
cursors, and 44 requests across both passes. The default 30-second request
budget may be reduced or raised up to 60 seconds with
`DeadlineMilliseconds`. It refuses further requests after a transport overrun;
it cannot forcibly interrupt a caller's scriptblock. Transport-level timeout
and response-size enforcement therefore remain mandatory for a live caller.

The returned object includes `Issue`, `CommentSnapshot`, `Decision` and a
read-only `Collection` record (source, request count and elapsed time). Both
the wrapper and policy decision always carry literal `MayMutate=false`.
Authenticated API availability is not inferred from any user-supplied Boolean.
No attestation is selected from PASS prose, no authority snapshot is archived,
and no issue/comment/pin/label/release mutation occurs. In particular, a later
harmless unpin can currently produce a read-only rejection; it is not authority
to reopen an accepted closure. Preserving closure-time pin evidence and
reconciling it with current revisions remain explicit future adapter work.

`qa/check_public_release_closure_collector.ps1` exercises the actual pagination
and double-read orchestration through a stubbed authenticated request seam,
then the real strict card/closure policy. It covers multi-page acceptance,
incomplete/truncated data, Boolean coercion, bounded loops, metadata/body/pin
races, trusted author metadata, absent historical authority, and historical
non-enforcement. Its request stub permits only the exact issue coordinates and
read-only query. No fixtures contact GitHub.

### Policy fixtures

`qa/check_public_release_closure_policy.ps1` runs in Quick/full QA and can be run
directly with `-Quiet`. It invokes the actual shared strict selector and covers
public/Dev/mixed targets, raw body edits, creation-versus-edit chronology,
association forgery, scope/artifact mismatch, incomplete snapshots, ambiguous
pins, duplicate JSON fields, duplicate/new closure generations, historical #1509,
UTF-8 byte boundaries, comment/authority limits, invalid Unicode/hash containment,
and retaining closure-time authority across later publication.
Canonical WOC, case aliases and unrelated source-pinned legacy rows are covered,
including refusal to borrow a legacy public sibling for a Dev-only pass. Run it under
PowerShell 7 and Windows PowerShell 5.1. No fixtures call GitHub or mutate issues.
