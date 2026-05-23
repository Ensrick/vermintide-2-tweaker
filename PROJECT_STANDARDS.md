# PROJECT_STANDARDS.md

Operational rules for working on the Vermintide 2 Tweaker monorepo with Claude.
Authored 2026-05-22 after the v0.9.8.x cosmetics regression chain + the audit
sweep that found ~30 pending items across stale audit markdowns.

**This document is binding on Claude.** When working in this repo, follow these
rules unless the user explicitly overrides one for a specific task. When in
doubt, cite the section number you're applying.

Cross-reference: `CLAUDE.md` (technical) describes HOW things work. This doc
(`PROJECT_STANDARDS.md`) describes HOW WE WORK on them.

---

## 1. Current state assessment (baseline)

### What's working
- **CHANGELOG-per-mod discipline** is load-bearing for future-me catching up.
- **Memory file system** (`~/.claude/projects/...`) actively prevents re-burning
  recurring bug classes (forward refs, peer-sync drift, etc).
- **VMBLauncher** is engineered properly — hash verification, exit codes,
  remote PC-B deploy. Don't bypass it.
- **Per-mod data + localization separation** is canonical VMF and well followed.
- **QA tooling in place** — `luacheck` + GHA workflow + 6 PowerShell checks
  catch the recurring bug classes that previously slipped through (forward
  refs, unescaped `%`, `tags=[]`, MOD_VERSION drift, oversized files, stale
  audit docs). See §11a for the full table.

### What's still weak
- **File sizes exceed Claude's effective working memory.** 8 lua files remain
  over the 2500-line hard limit (`character_weapon_variants.lua` at ~8800,
  `chaos_wastes_tweaker.lua` at ~6100, `cosmetics_tweaker.lua` at ~6000, plus
  five others). Reading the worst offenders consumes ~80K tokens. Tracked
  under GitHub Issue #2.
- **Logging conventions inconsistent.** The prefix convention in §3.1 is only
  partially adopted across mods. No central enforcement yet.
- **Error handling has tended toward reactive layering.** The v0.9.8.x chain
  (4 patches in 24h, each fixing the prior patch's side effect) is the
  canonical example. §4.4 codifies the corrective rule; the pattern still
  recurs on hot mods if nobody catches it during review.

---

## 2. File structure standards

### 2.1 Maximum file size
- **Target**: 1500 lines per file.
- **Hard limit**: 2500 lines. When approaching, split before adding more.
- **Exemption**: pure data files (`_cosmetic_unlocks.lua`, etc.) can be larger.
- **Current violations**: tracked under GitHub Issue #2. Run
  `.\qa\check_file_sizes.ps1` for the live list. Splits happen opportunistically
  when a natural feature boundary surfaces — not Claude's job per-session unless
  asked.

### 2.2 Module layout per mod
Every mod should have:
- `<mod>.lua` — entry point + top-level hooks. Keep ≤1500 lines.
- `<mod>_data.lua` — VMF widget tree.
- `<mod>_localization.lua` — localized strings.
- Per-feature files: `_<feature>.lua` for non-trivial subsystems.

Per-feature files **must** start with a docstring header:
```lua
-- _<feature>.lua — <one-line purpose>
--
-- <2-5 sentences on what this file owns, what it depends on, and any
-- non-obvious invariants. Reference CHANGELOG entries for major design
-- decisions.>
--
-- Owned by: <mod>.lua entry point. Consumed via: <require path / mod:dofile>
```

### 2.3 When to split
Trigger a split when ANY of:
- File hits 2500 lines.
- Adding a feature would push it past that.
- A natural feature boundary lets you carve out 500+ contiguous lines.
- A subagent says "I had to re-read the whole file three times to answer this"
  — that's a context-cost smell.

---

## 3. Logging standards

### 3.1 Prefix convention
Every log line **must** start with `[<mod_id>:<feature>]`. Examples:
- `[ct:populate_pickups] level=morris_mission_03 ...`
- `[cosmetics:husk-hat-create] wearer=X armoury_key=Y ...`
- `[wt:anim-remap] career=es_questingknight key=es_axe ...`

`mod_id` is the short id (`ct`, `wt`, `cosmetics`, etc.). `feature` is a
load-bearing identifier — match what's grep'able after a crash.

### 3.2 Level discipline
- **`mod:info`** — normal flow events. Equipment changes, hooks firing,
  RPC sends. Should be safe to leave on during normal play.
- **`mod:warning`** — a guard fired and we recovered. pcall caught something.
  Vanilla returned an unexpected shape. Defensive bail with a fallback.
- **`mod:error`** — unrecovered. Crash imminent or already happened. Someone
  needs to look at this. Should be rare.
- **`mod:echo`** — user-visible chat. Only for things the player needs to see
  (mod-loaded banner, command output, error popups). Never use for debug.

### 3.3 What NOT to log
- Per-frame events (60+ Hz). Use a sample gate or move to `mod:info` only on
  state change.
- Anything that requires a verbose toggle to be useful — make it useful or
  delete it.

### 3.4 Required logging for new hooks
When you add a new `mod:hook(...)`, you must also add either:
- An `info`-level entry log on the happy path (with prefix), OR
- A `warning`-level log on every guard / bail path.

Reason: silent hooks become invisible regressions. If a feature stops working,
the log should say so.

### 3.5 Diagnostic commands
Every mod with non-trivial state should expose a `/<mod_id>_diag` chat command
that dumps current state in a copy-pasteable form. Examples:
- `/ct_diag` — current pool overrides, active mutators, altar config.
- `/cosmetics_diag` — la_equips_by_peer, offhand_selection, glow runtime.

---

## 4. Error handling standards

### 4.1 pcall discipline
Every hook on a vanilla method that could crash the game **must** pcall-wrap
the inner call if the wrap is non-trivial:
```lua
mod:hook("SomeClass", "some_method", function(func, self, ...)
    -- Setup / pre-mutation
    local ok, result = pcall(func, self, ...)
    -- Restore / post-mutation
    if not ok then
        mod:warning("[mod:feature] inner errored: %s — bailing", tostring(result))
        return
    end
    return result
end)
```

Trivial passthroughs (`return func(self, ...)`) don't need pcall.

### 4.2 The "guard ≠ bail" rule
**A hook that returns without calling `func` is NOT a no-op — it removes
vanilla's mutation.** Before adding a guard with an early return, ask:
- What state mutation does vanilla normally do here?
- Will skipping that mutation leave the system inconsistent?

If yes, the guard is wrong. Either let vanilla run, or do vanilla's mutation
yourself, or document the consequence loudly.

Reference: v0.9.8.3 cosmetics_tweaker skeleton precheck bailed without calling
vanilla → husk never got hat attachment → user reported "no helmet at all."
Captured in memory.

### 4.3 Document failure modes
When adding a defensive guard, the comment must include:
- **What failure mode** this prevents (crash type, log signature, repro steps).
- **Citation**: CHANGELOG version, crash GUID, or memory file reference.
- **Why this is the right shape** (vs alternatives).

Bad:
```lua
-- defensive guard
if not unit then return end
```

Good:
```lua
-- v0.7.84 sanity guard: vanilla rpc_create_attachment can arrive before
-- unit is fully initialized. Crash GUID a31bc963 (2026-05-22): nil
-- _attachments table indexed at attachment_utils.lua:52. Bailing here
-- lets vanilla retry on the next RPC.
if not unit then return end
```

### 4.4 Don't stack speculative defenses
If a fix introduces a NEW bug (e.g. v0.9.8.3 → v0.9.8.4 → v0.9.8.6 → v0.9.8.7),
**revert all of them and find the actual root cause** before adding any guards.
Speculative-defense stacking is the dominant regression pattern in this repo.

---

## 5. Testing & verification standards

### 5.1 Mandatory pre-ship checks
Before declaring any mod "shipped" (uploaded to Workshop), Claude must verify:
1. **`MOD_VERSION` bumped** since last upload.
2. **CHANGELOG entry** for the new version exists.
3. **Forward-reference audit**: every `local function foo` is defined before
   any caller. (Future: automate via luacheck.)
4. **No `tags = [ ]`** in cfg (per `tools/vmb-launcher/CLAUDE.md` § "Drop `tags = [ ];` from cfg on first upload").
5. **Preview file exists** at the path the cfg references.
6. **Visibility matches expectation** — never auto-flip to public.
7. **Verify-before-shipping coverage (§5.1a)** — every fix lands with an apply-site log line AND a `/verify_<feature>` chat command.

### 5.1a Verify before shipping (non-negotiable)

**Every fix to a VT2 mod ships with (a) an apply-site log line proving the path ran and (b) a `/verify_<feature>` chat command the user can run from the keep. No more "should work" fixes.** Established 2026-05-23 after repeated burns where fixes compiled, looked right, and silently did nothing in practice:

- ct v0.7.66 mutator hook on `template.server_start_function` — dead field, no behavior change shipped.
- ct v0.7.76 grudge marks hook on `add_enhancements_for_difficulty` — bypassed by upvalue captures.
- ct v0.7.88 dormant boon gate on `DeusPowerUpRarityPool` — vanilla rolls from `DeusPowerUpsArrayByRarity` instead, so the gate did nothing.

Each surfaced only in live play, often hours into a session, and required a host+client log diff to root-cause.

When writing any fix that mutates a runtime table or installs a hook:

1. **Add an apply-site log line** at the exact mutation / hook-installation. Format: `[<feature>] applied: <specific evidence>`. The log MUST contain concrete numbers / names that prove which path executed. "Applied." with no detail does NOT count. Examples:
   - `[grudge] %d marks banned: %s` after the `BossGrudgeMarks` mutation.
   - `[dormant] added %s to %s rarity pool (now %d entries)` after the pool insert.
   - `[hook-install] %s hooked at %s` after every `mod:hook` returns.

2. **Add a `/verify_<feature>` chat command** that reports the LIVE state of whatever the fix touches, compared against the toggle / setting that's supposed to gate it. Format: per-item rows showing `name | toggle_state | live_state | PASS/FAIL`. Should work from the keep where possible — read globals directly, don't depend on `Managers.state.entity`.

3. **Verify the right table.** Before gating any boon-related write, grep vanilla code (`deus_power_up_utils.lua`, `deus_run_controller.lua`, etc.) for which table is actually READ at roll/grant time. Don't gate the table that LOOKS authoritative — gate the table that vanilla's call site reads.

4. **For hook installations**, grep for `local <name> = <Class>.<method>` and `<field> = <Class>.<method>` patterns first (see `DEVELOPMENT.md` § "Upvalue capture at file load bypasses later mod:hook"). If any match exists, the hook is dead and you need to mutate data instead.

5. **CHANGELOG entries on fix-class commits** must include the verification command name in the body. Reviewer should be able to run `/verify_<feature>` and confirm before next session.

If any of these is impractical (e.g. nothing observable from the keep), say so explicitly in the changelog — but the default is full coverage.

### 5.2 Manual smoke test expectation
For changes affecting load-bearing systems (cosmetics, weapon hooks, attachment
system, network RPCs), the user is expected to do at least one in-game test
before next session. Claude should remind them and ask for the log if
something looks off.

### 5.3 Subagent pre-ship review (recommended)
For changes touching multiple files or load-bearing code, dispatch a subagent
BEFORE shipping:
- Read the diff
- Cross-reference against CHANGELOG
- Check pcall coverage
- Check no info-level logs in tight loops
- Verify MOD_VERSION bumped
- Look for regression patterns

Subagent prompt template:
> Review the recent changes to `<mod>` for ship-readiness. Read CHANGELOG entry
> for v<X.Y.Z>. Walk every modified hook, verify pcall coverage and log levels.
> Identify any new "guard ≠ bail" violations. Report: ship-ready / fix these
> first / open questions.

### 5.4 Future: automated testing
**Track item**: set up `luacheck` + GitHub Actions. Catches forward refs,
unescaped `%`, undefined variables, dead vars. ~1 hour to scaffold.

Recommended order of automation investment:
1. **`luacheck` locally** + pre-commit hook (catches forward refs, % bugs).
2. **GitHub Action** running luacheck on push (catches what slips locally).
3. **Cfg validator script** (catches tags=[], missing preview, BOM).
4. **MOD_VERSION presence check** (catches missing constants pre-publish).
5. **CHANGELOG format validator** (optional, low ROI).

---

## 6. Version & changelog standards

### 6.1 MOD_VERSION
Every mod **must** define `local MOD_VERSION = "X.Y.Z[-stage]"` near the top
of its main lua. Format:
- `X.Y.Z` — semver-ish for the mod
- `-stage` — optional: `-alpha`, `-beta`, `-dev`, `-rc<N>`. Descriptive
  suffixes (`-hotfix`, `-la-icons`) are tolerated for in-flight work but
  should be cleaned to `-alpha`/`-dev` for release-quality versions.

### 6.2 Bumping
Bump BEFORE building:
- **PATCH** (`0.7.83 → 0.7.84`): bug fixes, small features.
- **MINOR** (`0.7.84 → 0.8.0`): new user-facing features, breaking VMF setting
  renames.
- **MAJOR** (`0.8.x → 1.0.0`): explicit "stable release" milestone.

### 6.3 Workshop title sync
Per `feedback_version_in_workshop_title.md` memory: the cfg title carries
` v<MOD_VERSION>` suffix. Future: launcher auto-rewrites on upload. For now,
update by hand or accept that the title will lag.

### 6.4 CHANGELOG entry format
Per-mod `CHANGELOG.md`. Top entry first (descending chronology). Format:
```markdown
## 0.X.Y-stage (YYYY-MM-DD) — short title

### Why
<1-2 sentences on the trigger: bug report, audit finding, new feature ask>

### Changed
- file:line — summary
- file:line — summary

### Notes
- Optional: gotchas, deferred items, follow-up tasks.
```

Don't bury fixes in version "highlights" — list every meaningful change so
future-me can find it via grep.

---

## 7. Documentation standards

Documentation in this repo falls into three categories — **canonical** (long-
lived, tracked, every reader needs them), **reference** (long-lived, tracked,
specific topics), and **ephemeral** (snapshot or in-flight work, not tracked).
The rules below codify what goes where and how each type is maintained.

### 7.1 Canonical document map

The complete list of canonical docs and where each lives.

**Repo-root canonical (every doc below is binding on Claude when working anywhere in the repo):**

| Doc | Tracked? | Purpose | Update trigger |
|---|---|---|---|
| `CLAUDE.md` | Yes | Technical entry point — how the code works | Architecture changes; new mods; new cross-mod patterns |
| `PROJECT_STANDARDS.md` (this file) | Yes | Operational rules — how WE work | New recurring pain → new rule; old rule disproven → revise |
| `LOCALIZATION_STANDARD.md` | Yes | VMF localization convention | Convention change; new pattern proven across ≥2 mods |
| `CROSS_MOD_ARCHITECTURE.md` | Yes | How mods interact at runtime (LA bridge, co-install detection) | New cross-mod surface; new bridge pattern |
| `CHANGELOG.md` (repo root) | Yes | Repo-aggregate release notes | Per-mod CHANGELOG entries that affect multiple mods or the toolchain |
| `REGRESSION_CHECKLIST.md` (repo root) | Yes | Master list of repo-wide regression signatures | New crash class survives more than one fix attempt |
| `WORK_ITEMS.md` | Yes | Current status snapshot across mods | Treat as ephemeral pointer; GitHub Issues §11 is source of truth |
| `WEAPON_CATALOG.md` / `ITEM_LIST.md` / `ANIMATION_RESEARCH.md` | Yes | Reference catalogs | When the underlying data changes (new weapon, new skeleton probe) |
| `VMF_RECIPES.md` / `COMMANDS.md` | Yes | Cross-mod reference (VMF gotchas, command inventory) | New VMF burn class; new chat command in any mod |
| `DEVELOPMENT.md` (repo root) | Yes | Historical architecture reference | Pre-dates CLAUDE.md; still authoritative for topics it covers |

**Per-mod canonical:**

| Doc | Required? | Purpose |
|---|---|---|
| `CHANGELOG.md` | **Mandatory, every mod** | Per-mod version history (§6.4 format) |
| `REGRESSION_CHECKLIST.md` | **Mandatory, every mod** | Per-mod subset of repo-wide checklist + mod-specific regressions |
| `CODE_REVIEW.md` | **Mandatory for public-Workshop mods** (`ct`, `gt`, `cosmetics_tweaker`, `verminious_dreams_lighting`); optional for friends-only | Snapshot architectural review |
| `CLAUDE.md` (per-mod) | Optional | Workflow guardrails specific to that mod (only when the mod has non-obvious gates — see `dynamic_cosmetic_portraits/CLAUDE.md`) |
| `DEVELOPMENT.md` (per-mod) | Optional | Mod-specific architecture (use when the mod has system-level docs that don't fit in the main lua's header docstring) |
| `RECIPES.md`, `<TOPIC>_PLAYBOOK.md`, `DEFINITION_OF_DONE.md` | Optional | Reference docs for recurring authoring tasks within the mod |
| `TODO.md` | **Discouraged** | Use GitHub Issues per §11 instead |
| `POSTMORTEMS.md` | Created on first incident | Rolled-up post-incident records — see §7.3 |

The "public" / "friends-only" distinction is the `visibility` field in
`itemV2.cfg`. Friends-only mods (`wt`, `crt`, `cwv`, `cim`, etc.) ship without a
public CODE_REVIEW because they aren't user-facing in the same way. The list
above pins the currently-public mods explicitly — if you change a mod's
visibility, also create/remove CODE_REVIEW.md.

### 7.2 Per-mod required structure

Every per-mod folder must have at minimum:

```
<mod>/
├── CHANGELOG.md            # §6.4 format
├── REGRESSION_CHECKLIST.md # per-mod subset of repo-wide checklist + mod-specific entries
└── (CODE_REVIEW.md if public)
```

Anything else is optional. Don't create an empty stub of an optional doc just
to satisfy "the standard" — the standard says it's optional for a reason.

### 7.3 The three-bucket model for non-canonical docs

In addition to the canonical docs above, mods accumulate three other kinds of
documentation. Each has a fixed home.

**Bucket A — Reference docs** (long-lived knowledge, tracked, mod-root):

Enduring "how-to" or "why-this-works" knowledge that a future contributor needs
to consult. Examples: `character_weapon_variants/RECIPES.md`,
`cosmetics_tweaker/LA_SYNC_MODEL.md`, `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`,
`cosmetics_tweaker/VT2_NETWORKING_REFERENCE.md`.

Rules:
- Lives at the mod root, named `<TOPIC>.md` (UPPER_SNAKE_CASE).
- Tracked in git.
- Read top-to-bottom by a new reader; not append-only.
- Updated in place when the underlying knowledge changes.
- If a reference doc gets contradicted by a postmortem entry, update the
  reference; the postmortem entry is the trigger, the reference is the
  durable record.

**Bucket B — Postmortems** (`<mod>/POSTMORTEMS.md`, append-only, tracked):

When an investigation resolves (the bug is fixed, the mystery understood, the
patch shipped), the lessons get one entry in `POSTMORTEMS.md`. One file per
mod. Append-only — new entries go at the top.

Entry format:

```markdown
## YYYY-MM-DD — <symptom one-liner> (resolved v<X.Y.Z>)

**Symptom**: <what the user saw / what crashed / what log line surfaced>

**Root cause**: <the actual underlying cause, in 2-4 sentences>

**Fix**: <what shipped, with file:line citation>

**Why it took so long** (optional): <if the resolution path was non-obvious,
what the wrong hypotheses were and what evidence finally redirected>

**Future-prevention**: <what would catch this earlier next time —
a new check in qa/, a new memory entry, a new pre-ship gate>

**References**: CHANGELOG v<X.Y.Z>, memory `<name>`, GitHub #<N>
```

Rules:
- One `POSTMORTEMS.md` per mod, created on first incident.
- Tracked in git.
- Entries are immutable after they land (don't go back and rewrite — write a
  new entry pointing at the old one if understanding changes).
- A postmortem entry is the END of an investigation. Open investigations live
  in Bucket C.

**Bucket C — Active investigations** (`<mod>/_investigating/`, gitignored):

Working notes for a bug or feature currently being worked on. Multiple files
OK — name them `<short-topic>.md`. The convention is: anything in
`_investigating/` is in-flight and may be wrong.

Lifecycle:
1. Investigation starts → drop notes into `<mod>/_investigating/<topic>.md`.
2. Investigation finishes → distill key findings into one
   `POSTMORTEMS.md` entry, delete the `_investigating/` file(s).
3. If the investigation is abandoned (turned out to be unrelated, etc.), just
   delete the file — no postmortem needed.

Rules:
- The whole `_investigating/` subdir is in `.gitignore`. These notes are
  ephemeral; clones don't get them.
- Don't track these into git "just in case" — the distillation step is the
  whole point. Permanent archaeology lives in `POSTMORTEMS.md`.
- If you find yourself wanting to keep an `_investigating/` doc as a permanent
  artifact, ask: is this enduring knowledge (→ promote to Bucket A reference)
  or is it about a specific past incident (→ promote to Bucket B postmortem
  entry)? Either way, the in-flight file gets deleted.

**Migration note (2026-05-23):** The existing one-off investigation docs in
`cosmetics_tweaker/` (HOST_CLIENT_AUDIT, GLOW_HOOK_INVESTIGATION,
HUSK_HOOK_FIRING_DIAGNOSIS, LYNDSEY_v15_LOG_ANALYSIS, PCA_v15_LOG_ANALYSIS,
ROOT_CAUSE_SYNTHESIS, etc.) pre-date this standard. They are not required to
be migrated immediately. Treat them as a slow backlog: when one is referenced
during work, either distill it into a `POSTMORTEMS.md` entry then delete it,
or promote it to a permanent reference doc if it's enduring knowledge. Do not
sweep all 27 in one pass — touch them as work surfaces them.

### 7.4 Audit snapshots

Audit reports (`AUDIT_*.md` at repo root or per-mod) are a special case of
ephemeral document: they're snapshots of repo state at a point in time, not
living documents.

Rules:
- Audit reports are **gitignored** at the root (`AUDIT_*.md` pattern in
  `.gitignore`) — they're snapshots, not source of truth.
- Findings from an audit either:
  - Get filed as GitHub Issues (per §11), with the audit report as context, OR
  - Get distilled into a `POSTMORTEMS.md` entry (when the audit found a
    specific past incident's root cause), OR
  - Get rolled into a Bucket A reference doc (when the audit revealed a
    pattern worth documenting).
- The audit report itself is then deleted — its findings are now tracked
  somewhere durable.
- If you want to preserve an audit report for archaeological reasons, move it
  to `_archive/audits/YYYY-MM-DD/` and add a `> ⚠ ARCHIVED — superseded by
  <where>` banner per §7.5.

### 7.5 Supersession banner (preserved from previous version)

When a tracked doc becomes obsolete but you keep it for historical context,
mark it at the top with:

```markdown
> ⚠ SUPERSEDED — this snapshot is from <date>. Current state lives in
> <newer doc> as of <date>. Kept for historical context.
```

Do NOT silently delete obsolete tracked docs — they may be referenced from
commit messages, memory files, or external links. Banner + keep, or migrate
the content to its new home and then delete with a commit message that says
where it moved.

### 7.6 Doc creation gate (when do I make a new file?)

Before creating any new `.md` file, answer:

1. **Is this enduring knowledge or a one-time snapshot?** If snapshot, it's
   either a postmortem entry (Bucket B) or an audit (gitignored) — don't
   create a new doc, append to the existing one.
2. **Does this belong in an existing doc?** Reference docs (Bucket A) tend to
   sprawl. Check if a new section in an existing file fits before creating a
   new file. Three sections in one file beats three small files.
3. **Is this actually a GitHub Issue?** Planning docs, roadmaps,
   "we should do X" — those are Issues per §11.
4. **Is this a workflow guardrail for one mod, or general?** General → repo
   root. Mod-specific → per-mod (and only if the mod has non-obvious gates
   that won't fit in the main lua's docstring header).

If after answering 1-4 you still need a new file, create it. The bias is
against creating new files.

### 7.7 Doc maintenance trigger

Each canonical doc lists its update trigger in §7.1. In practice:

- **At ship time:** CHANGELOG entry, POSTMORTEMS.md entry if a bug got fixed.
- **At architecture change:** CLAUDE.md, CROSS_MOD_ARCHITECTURE.md as relevant.
- **At new-pattern recognition:** PROJECT_STANDARDS.md (this doc) — propose
  the rule update in the same PR as the work that revealed the new pattern.
- **At reference-knowledge drift:** Bucket A reference docs. If a recipe in
  RECIPES.md is wrong, fix it the same session you notice.

Don't run periodic "doc cleanup" passes. Update in place at the moment of
change, where the context is fresh. Periodic cleanup correlates with stale
docs because it disconnects the update from the cause.

### 7.8 Inline comments (preserved from previous version)

Comments explain **why**, not what. Bad:
```lua
-- increment i
i = i + 1
```

Good:
```lua
-- Skip the first slot (left hand) because vanilla's hand_unit_1p only
-- spawns into right-hand on careers without a shield.
i = i + 1
```

When fixing a bug, leave a citation in the comment:
```lua
-- v0.7.84: name-based identity check (was positional [1] before). Fragile
-- against FatShark array reorders; see CHANGELOG and POSTMORTEMS entry
-- 2026-05-22 for the original concern.
```

Citation targets: CHANGELOG version, POSTMORTEMS.md date, memory file name,
GitHub issue number. NOT audit-report line numbers (audits are ephemeral
per §7.4) and NOT raw line counts in long docs that will drift.

### 7.9 Filename conventions

- **All canonical/reference doc filenames are UPPER_SNAKE_CASE** with `.md`
  extension. Confirmed consistent across all 17 mods as of 2026-05-23 — no
  case drift in the repo. Maintain.
- **Investigation notes** (Bucket C) can use lowercase if you prefer; that
  subdir is gitignored and conventions there don't matter.
- **No spaces, no dashes in canonical filenames.** `CODE_REVIEW.md`, not
  `code-review.md` or `Code Review.md`.

---

## 8. Workflow standards for Claude

### 8.1 Empirical-first
Before adding code:
1. Read the actual crash/symptom evidence (log, dump, repro).
2. Read the actual current code (don't trust stale audit line numbers).
3. Read vanilla source if a hook is involved.
4. Form a hypothesis grounded in observed evidence.
5. THEN code.

If you can't articulate "the failure mode is X, citation Y, fix Z", you're not
ready to ship.

### 8.2 Subagent-first for context-heavy tasks
Dispatch a subagent when ANY:
- Reading >3 files for one question.
- Need to scan a CHANGELOG with >100 entries.
- Cross-referencing audit doc + current code + git log.
- "Where is X used across the repo?" type questions.

Subagent benefits:
- Preserves main context for synthesis + decisions.
- Forces explicit prompt = explicit task scope.
- Parallel agents fan out quickly.

### 8.3 One focused change per session
Multi-fix sessions correlate with regressions in this repo's history. Default
to one feature/fix per session unless the user explicitly asks for a batch.
When batching, ship + verify each one before starting the next.

### 8.4 Pre-ship subagent review (mandatory for hot mods)
For changes to `cosmetics_tweaker`, `chaos_wastes_tweaker`, `weapon_tweaker`,
`character_weapon_variants`: dispatch a pre-ship review subagent (see §5.3).
For other mods: optional but encouraged.

### 8.5 Defensive subagent for "is this still true?"
When a memory or audit references "current code does X at line Y": verify
before acting. Memory cited claims can be 20+ days old. The verification is
30 seconds via a single grep.

### 8.6 The "I'm about to add a defensive guard" gate
Before writing `if not X then return end` in a hook, answer in a comment:
1. What failure mode does this prevent?
2. What's the citation (CHANGELOG entry, crash GUID, vanilla source line)?
3. What does vanilla NORMALLY do here that this guard now skips?
4. Is skipping that mutation safe, or am I creating a new bug?

If you can't answer 1-4, DON'T add the guard.

---

## 9. Anti-patterns (observed in this repo's history — do not repeat)

### 9.1 Speculative defense stacking
**Symptom**: v0.9.8.3 → v0.9.8.4 → v0.9.8.5 → v0.9.8.6 → v0.9.8.7 in 24 hours,
each "fixing" a side effect of the prior. **Root cause**: not understanding
what vanilla does, just adding guards. **Fix**: revert all, understand,
ship one correct fix.

### 9.2 Wrong-key storage access
**Symptom**: `self._attachments[slot_name]` (always nil) instead of
`self._attachments.slots[slot_name]`. **Root cause**: writing guards from
memory instead of reading vanilla source. **Fix**: read vanilla source for
EVERY guard that touches non-obvious state.

### 9.3 Conditional registration with peer-sync
**Symptom**: a mod-load registration into `BuffTemplates`/`NetworkLookup`/
`DeusPowerUpsArray` gated by a per-user toggle → peers see different sequential
indices → `rpc_add_buff(integer_index)` crashes on join. **Fix**: pre-register
unconditionally in deterministic sorted order; gate only the offering pool.
See `DEVELOPMENT.md § Gated registration diverges across peers`.

### 9.4 Hot-reload assumption
Ctrl+Shift+R is **broken** for mods that hook unit creation
(`GearUtils.create_equipment`, `BackendUtils.get_item_units`) or use non-Lua
resources. Always full-restart VT2 after redeploying. See
`feedback_hot_reload_unfixable.md` memory.

### 9.5 1P animation overrides
**Symptom**: missing 3P attack on cross-character weapons (body holds previous weapon's idle stance — **NOT** a T-pose; see §9.8 terminology). **Wrong fix**: override `anim_event` or `wield_anim` (1P) per character. **Right fix**: only override 3P fields (`anim_event_3p`, `wield_anim_3p`). 1P is universal across characters; `first_person_base` is shared across all six characters and any weapon's 1P state machine plays correctly on every character's first-person view by default. See `weapon_tweaker/DEVELOPMENT.md` § "1P animations are universal — never touch" and `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` § "Three non-negotiable rules".

### 9.6 Adding fields to vanilla cfg fields you don't need
Especially `tags = [ ]` — causes ugc_tool first-upload to fail with 0x2.
Per `feedback_ugc_tool_forward_slashes.md`.

### 9.7 Skipping the bug-search-first protocol
Before "fixing" a crash, grep CHANGELOGs + memory for the literal crash
signature. Most surprising crashes are documented. Cost ~2 wasted ct versions
in 0.6.5-0.6.6 by skipping. See `feedback_search_changelog_for_known_crashes.md`.

### 9.8 Writing "T-pose" when the actual symptom is "missing event no-op"

VT2 characters do **NOT** T-pose when a `anim_event_3p` doesn't exist on the target weapon's 3P state machine. The actual behavior: the 3P body keeps the **last equipped weapon's idle stance** and silently no-ops the missing event. The attack animation simply doesn't play — no T-pose, no stuck frame, no engine fatal.

**Rule:** do NOT write "T-pose" in failure-mode descriptions, QA matrices, recipe docs, CHANGELOG entries, or commit messages. Use **"default stance of previous weapon"** or **"missing event no-op"** instead. T-pose specifically means the skeleton has no animation playing at all — rare; usually engine-fatal-adjacent — which is a different category of bug (typically a wholly broken state machine, or `Unit.animation_event` returning an error before any anim plays).

A missing `wield_anim_3p` is ALSO not a T-pose — it's the character not entering the new weapon's stance and instead staying in whatever the previous weapon's idle was.

**When auditing existing docs/code:** correct "T-pose" on contact. Most existing entries that say "T-pose" are technically wrong descriptions of "no-anim-played" symptoms. Established 2026-05-19 per user correction.

---

## 10. Mod maturity tiers (different bars for different mods)

### 10.1 Alpha (`-alpha`, `-dev`)
- Feature in flux. Breaking VMF changes tolerated.
- CHANGELOG required but can be terse.
- pcall on most hooks; some experimental hooks may be unprotected.
- Logging permissive.
- **Examples**: `modded_progression`, `lobby_tweaker`, `enemy_tweaker`.

### 10.2 Beta / Pre-stable
- Settings stabilizing. Breaking changes need migration code.
- CHANGELOG entries required for every release.
- pcall everywhere.
- Logging conservative.
- **Examples**: `chaos_wastes_tweaker`, `cosmetics_tweaker`,
  `character_weapon_variants`, `weapon_tweaker`.

### 10.3 Stable (no current mods at this tier yet)
- Breaking changes require deprecation + migration period.
- Every change requires CHANGELOG + verification (manual or automated).
- pcall everywhere + structured logging required.
- Test coverage expected (when we have it).
- Subagent pre-ship review required.

### 10.4 Frozen
- Mature mods we don't actively iterate on. Add `> FROZEN` banner at the top
  of the main lua.
- Candidates: `verminious_dreams_lighting`,
  `la_prefix_patch` (per audit findings).
- Frozen mods still receive crash fixes but no new features.

---

## 11. Pending work tracking

**GitHub Issues are the source of truth for open work.** Per memory
`feedback_github_issues_for_pending_work.md` (binding rule 2026-05-23): items
that need doing belong in the issue tracker, not in markdown roadmaps that
silently rot. Issue list lives at
https://github.com/Ensrick/vermintide-2-tweaker/issues.

**Live status:**
```
gh issue list --repo Ensrick/vermintide-2-tweaker            # open
gh issue list --repo Ensrick/vermintide-2-tweaker --state all # incl. closed
```

### Process
1. When you find a pending item (audit, code review, deferred work),
   `gh issue create` it with appropriate labels.
2. Reference the issue number from the code (`-- See #N`) and any docs that
   describe the work.
3. When the fix ships, close the issue on GitHub with a comment linking to
   the commit / CHANGELOG entry.
4. Run `gh issue list` at the start of a session if you want a picture of
   what's open before diving in.

### Labels
`audit`, `crash`, `regression`, `refactor`, `blocked`, `deferred`, plus the
defaults (`bug`, `enhancement`, `documentation`, `wontfix`).

### What used to live here
A status roadmap (`✅ DONE / ⚠ PARTIAL / ❌ TODO` tables across "High ROI",
"Medium ROI", "Lower ROI", "Architectural", "Per-mod" subsections) was
maintained inline through 2026-05-23. It was removed because it duplicated
the GitHub issue list and silently drifted — exactly the failure mode §11
above is meant to prevent. The git history has the snapshots if you want to
see what was open on a given date.

## 11a. QA tooling — what's in place

| Tool | Location | Catches | Run via |
|---|---|---|---|
| `luacheck` | `.luacheckrc` + GHA | forward refs, unused vars, undefined globals, Lua 5.1 syntax | `luacheck . --no-config-default` |
| `check_cfg.ps1` | `qa/` | `tags=[]`, missing preview, wrong visibility, missing bug-report block, missing BMC | `.\qa\check_cfg.ps1` |
| `check_versions.ps1` | `qa/` | missing MOD_VERSION, cfg title-version drift, missing CHANGELOG entry | `.\qa\check_versions.ps1` |
| `check_localization.ps1` | `qa/` | unescaped `%`, referenced-but-undefined keys, missing `mod_description` | `.\qa\check_localization.ps1` |
| `check_file_sizes.ps1` | `qa/` | files over 1500-line target / 2500-line hard limit | `.\qa\check_file_sizes.ps1` |
| `check_stale_docs.ps1` | `qa/` | audit/review markdowns >14 days without SUPERSEDED banner | `.\qa\check_stale_docs.ps1 [-Fix]` |
| `run_all.ps1` | `qa/` | all of the above | `.\qa\run_all.ps1 [-Quick] [-SkipLua]` |
| GitHub Action | `.github/workflows/qa.yml` | runs all checks on push + PR | automatic |

Full check-to-bug-class map: [`qa/CHECKS.md`](qa/CHECKS.md).

---

## 12. Memory hygiene rules

### 12.1 What goes in memory (per the user's auto-memory system)
- **User preferences** that span sessions (workflow conventions, terminology).
- **Project-level invariants** (load-bearing rules, deprecation gotchas).
- **Recurring bug class signatures** (so future-me doesn't re-burn them).
- **External system pointers** (where bugs are tracked, what dashboards to
  check).

### 12.2 What does NOT go in memory
- Code patterns (read the code instead).
- Git history (use `git log`).
- Ephemeral task state (use tasks).
- Anything already in CLAUDE.md.

### 12.3 Periodic memory hygiene
- When MEMORY.md exceeds the soft limit (~24KB), prune. Move detailed memories
  into topic files; keep one-line index entries.
- When a memory's claim is wrong (stale code citation, code moved, fixed),
  update or delete. Don't leave wrong memories — they're worse than no memory.

---

## 13. When this doc is wrong

This doc is itself versioned. When you encounter a rule that conflicts with
reality, or a workflow that's been proven counter-productive, propose an
update to this doc in the same PR as the work. Don't silently ignore the rule.

The rules are recommendations from observed pain. New pain may justify new
rules; old pain that's been solved may justify deleting rules. Both are fine.

---

## 14. Quick reference card

```
BEFORE coding a fix:
  - Read crash log / repro evidence
  - Read current source (not stale audit line numbers)
  - Read vanilla source if hooks involved
  - State: failure mode, citation, why this fix is the right shape

WHEN coding:
  - File ≤1500 lines target, ≤2500 hard
  - Logs prefixed [mod:feature]
  - mod:info / mod:warning / mod:error / mod:echo (correct level)
  - pcall wrap hooks that mutate non-trivial state
  - Comment: why, not what; cite when fixing a bug

BEFORE shipping:
  - MOD_VERSION bumped
  - CHANGELOG entry written
  - No forward-ref bugs (visually verify; future: luacheck)
  - No new "guard ≠ bail" violations
  - Subagent pre-ship review for hot mods

WHEN BLOCKED:
  - Memory + CHANGELOG grep for the literal symptom
  - Dispatch Explore subagent if it needs >3 files
  - Don't add speculative defenses
```

---

*Last updated: 2026-05-23 — §7 documentation standards expanded: canonical doc
map (repo-root + per-mod tables with update triggers), three-bucket model for
non-canonical docs (Reference / POSTMORTEMS.md / `_investigating/`), audit
snapshot policy (gitignored, distill on action), supersession banner preserved,
doc creation gate, filename conventions. §1 baseline refreshed (QA tooling now
in place); §11 roadmap moved to GitHub Issues per §11's own discipline.
Initial draft: 2026-05-22.*
