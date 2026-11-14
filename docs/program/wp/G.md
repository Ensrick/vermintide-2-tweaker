# Track G: governance, rules, tracker process and documentation

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/E1.md` (auditor E1, 2026-11-13, repo `592253d1`). Placeholders: `<repos>` = the folder that holds `vermintide-2-tweaker`, `Vermintide-2-Source-Code` and `Vermintide-Mod-Framework`; `<audit>` = the audit workspace that holds `plan/` and `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/`; `<memory>` = the Claude memory store (its path is printed in `~/.claude/CLAUDE.md`, section "Persistent context"); `<helpers>` = `~/.claude/vt2-ship-helpers/`.

## Track brief

1. The rules were written for a human tester who has stopped playing. 282 of 329 open issues wait in a "ready to test" state; 858 pinned test cards have no reader.
2. Owner decisions of 2026-11-13, already taken: (a) the rig may launch the game unattended, only through `tools/harness/run.ps1`; (b) issues of evidence class U, S, R close on machine evidence, class V and C go to a human list and never block; (c) manual live-test cards stop.
3. Today those decisions contradict the rule texts in five to seven files and one gate (`qa/check_pr_autoclose.ps1`). WP-G-01 fixes that first, so no agent is asked to break a written rule.
4. Mandatory reading today is about 89k tokens to ship one line. WP-G-02 installs a one-page `AGENTS.md` (draft: `<audit>/plan/drafts/AGENTS.md`) and the execution protocol (`<audit>/plan/drafts/EXECUTION_PROTOCOL.md`).
5. The pull-request gate reads tracker state (`.github/workflows/qa.yml:125-141`), so one issue's label can fail every pull request. WP-G-03 removes that.
6. Cards are replaced by one JSON spec per issue in the repo (WP-G-04, WP-G-05), a two-label lifecycle with one write tool (WP-G-06) and a generated human list (WP-G-07).
7. Knowledge that exists only in the Claude memory store moves into the repo (WP-G-08). The ship helper scripts in `<helpers>` are moved by track P (`<audit>/plan/wp/P.md`); G does not duplicate that card.
8. Inventories are generated (WP-G-09), verified contradictions are fixed (WP-G-10), documentation leaves the build receipt (WP-G-11), then the root, `PROJECT_STANDARDS.md` and `docs/` are swept behind a link check (WP-G-12 to WP-G-14).
9. Order: 01, 02, 03 first (any order between 02 and 03). 04, 05, 06, 07 in sequence. 08 to 11 any time. 12 before 13 and 14. After every card the repo has one consistent rule set.
10. None of these cards touches a mod folder, so none needs a claim, a build or a ship. Exception: WP-G-11 runs two local `-BuildOnly` builds as a proof and commits no bundle.
11. Evidence class for every card in this track: S (the acceptance commands). No card needs the rig.
12. New files must be ASCII, pass `qa/run_all.ps1 -Quick -SkipLua`, and never add a rule that a script already enforces.
13. Open owner decisions with defaults are at the end. A card that depends on one names its id.

---

### WP-G-01 Record owner decisions; change launch, evidence and card rules

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | strong (rewords non-negotiable rules in nine files and one gate; a wrong sentence misdirects every later agent) |
| Depends on | none |
| Issues | advances #546 |
| Source | E1-F02, E1-F01 |
| Streams | none (no mod folder) |

**Goal.** The rule texts and the pull-request closure gate say: the rig is the only permitted game launch, class U/S/R issues close on machine evidence, manual live-test cards are stopped.

**Context.** Launching is forbidden in `~/.claude/CLAUDE.md` (rule 2), `<repos>/CLAUDE.md:69`, `CLAUDE.md:10`, `PROJECT_STANDARDS.md:1506`, `docs/BUG_TRIAGE_RUNBOOK.md:554` and `CONTRIBUTING.md:166`, while `<repos>/AGENTS.md:24` (the Codex layer) demands a launch before handoff. Only a human may verify: `CLAUDE.md:18`, `PROJECT_STANDARDS.md:2396`, `docs/BUG_TRIAGE_RUNBOOK.md:444`, and `qa/check_pr_autoclose.ps1:62` accepts only `Verification: user-confirmed`. Cards are mandatory in `CLAUDE.md:21`, `PROJECT_STANDARDS.md:2315` and `docs/BUG_TRIAGE_RUNBOOK.md:343-429,441`. The old tracker guard keeps running until WP-G-03 and WP-G-06; it accepts a `not-started` issue with no pinned card and an existing ready issue with its existing pinned card. So this card changes rule text only: no label, no card, no comment on GitHub.

**Steps.**
1. Create `docs/adr/0001-rig-launch-machine-evidence-no-cards.md` (at most 2 KB): date 2026-11-13; the three decisions; the class table (U unit test under `qa/lua/tests`, S static check, R rig run, V human eyes or ears, C two clients, X blocked or owner decision; U/S/R close on machine evidence, V/C/X do not); the report phrase `auto-verified (<class>) on <mod> <version> <commit>, run <id>`; the receipt of step 2; one line: "A rig PASS is never reported as 'works'."
2. `qa/check_pr_autoclose.ps1`, function `Test-TrustedClosureReceipt` (lines 53-67): keep the existing test. Add `$hasMachine`, true when the comment body matches all of `(?im)^Verification:\s*machine-evidence\s*$`, `(?im)^Evidence class:\s*[USR]\s*$`, `(?im)^Result:\s*PASS\s*$`, `(?im)^Spec:\s*qa/specs/issue_\d+\.json\s*$`, `(?im)^Run:\s*\S.*$`. Return `$true` when `$trustedLogin -and $trustedAssociation -and $hasHeading -and $boundToPr -and ($hasVerification -or $hasMachine)`. In `Invoke-SelfTest` (lines 101-161) add four fixtures: a complete class R receipt is accepted; `Evidence class: V` is rejected; a receipt without `Run:` is rejected; `Result: FAIL` is rejected. Keep the existing rejection of `Verification: build-passed` (lines 128-129).
3. `CLAUDE.md`, table rows (each row is one physical line; keep it one line):
   - row 2 (line 10) becomes: `| 2 | The only permitted game launch is the unattended rig, tools/harness/run.ps1 (owner decision 2026-11-13, docs/adr/0001-rig-launch-machine-evidence-no-cards.md). Never start VT2, Steam, a launcher window or any interactive app another way, and never restart Steam. |` (put the two paths in backticks).
   - row 10 (line 18) becomes: `| 10 | Never claim a runtime issue fixed from a build, a review or a green gate. Evidence classes U (unit test), S (static check) and R (rig run) close an issue on machine evidence, reported as "auto-verified (<class>) on <mod> <version> <commit>, run <id>". Classes V (human eyes or ears) and C (two clients) go to the human list and never block other work. See the ADR named in rule 2. |`
   - row 13 (line 21): keep the first sentence and the type, priority, mod-tag and issue-format sentences. Replace everything from "The latter two mean runnable live in-game testing NOW" up to and including "Tooling/docs never enter the live-test queue; verify them autonomously and close." with: "Manual `## CURRENT LIVE TEST` cards are stopped (2026-11-13): do not post, pin, unpin or edit a card and do not change a lifecycle label by hand. Record evidence as an issue comment; a machine PASS of class U, S or R closes the issue (rule 10)."
   - row 15 (line 23) becomes: `| 15 | Loaded-version authority: the newest console log's [<id>:LOAD] line names the version that ran, and the rig records it with every result. Human testers on the class V/C list refresh through the dev collection (unsubscribe, resubscribe). |`
4. `PROJECT_STANDARDS.md`:
   - line 1506: replace the sentence "Do not launch the game or restart Steam unsolicited." with "The only permitted game launch is the unattended rig, `tools/harness/run.ps1` (`docs/adr/0001-rig-launch-machine-evidence-no-cards.md`); never restart Steam."
   - lines 2396-2400, the bullet "**Verified closure:**": replace its first sentence with "Machine evidence of class U, S or R closes an issue (`docs/adr/0001-rig-launch-machine-evidence-no-cards.md`); so does confirmation by the user or designated playtester RainReligion. Class V and C work goes to the human list and never blocks." Replace its last sentence ("If the evidence does not verify the fix ...") with "A failed check is recorded as an issue comment; do not change the label by hand."
   - directly above the bullet "**Live-test card prerequisite:**" (line 2315) insert a new bullet: "- **Cards stopped (2026-11-13).** Do not post, pin, unpin or edit a `## CURRENT LIVE TEST` card and do not move an issue into `diagnostics-armed` or `verify-fix` by hand. The prerequisite below describes only the cards that already exist."
   - lines 2844-2845 (quick reference card): replace the two card lines with "  - No live-test card (stopped 2026-11-13); record machine evidence on the issue".
5. `docs/BUG_TRIAGE_RUNBOOK.md`:
   - replace the whole checklist item that starts "**Add the status label to the Issue NOW" (line 343) up to the line before "**Refresh by tester role.**" (line 430) with: "- [ ] **Record the ship on the issue** in one comment: version, what shipped, and the test, check or rig case that will verify it. Do not post a card and do not change the lifecycle label by hand (cards stopped 2026-11-13, `docs/adr/0001-rig-launch-machine-evidence-no-cards.md`)."
   - line 441 item ("**Provide ONE current live-test card ...") becomes: "- [ ] **Verify by machine first.** Class U or S: run the named test or check. Class R: queue the rig case (`tools/harness/run.ps1`). Report `auto-verified (<class>) on <mod> <version> <commit>, run <id>`."
   - line 444 item: replace "until the user confirms in-game" with "from a build or review alone" and append "A machine PASS of class U, S or R closes it; class V or C remainders go to the human list."
   - line 549: replace "Only the user's in-game confirmation closes an item" with "Only machine evidence (class U, S, R) or a human confirmation closes an item".
   - line 554: replace the bullet with "- **Launching VT2 outside the rig.** The only permitted launch is `tools/harness/run.ps1`."
6. `CONTRIBUTING.md`: replace the paragraph starting "The two ready states require the newest exact" (line 61) with "Manual `## CURRENT LIVE TEST` cards are stopped. Do not change lifecycle labels by hand. Issues of evidence class U, S or R close on machine evidence; class V and C go to the human list."; line 126 becomes "- Never claim a game fix is complete from a build or review alone; see `docs/adr/0001-rig-launch-machine-evidence-no-cards.md`."; after the sentence at line 166 add "The project's unattended rig (`tools/harness/run.ps1`) is the one exception on the maintainer's machines." `.github/pull_request_template.md`: line 35 becomes "- [ ] The game was launched only through `tools/harness/run.ps1`, if at all; nothing was uploaded outside `tools/ship/ship.ps1`."; in the "Issue lifecycle" section (line 41) replace the sentences about the card and `coop-required` with "Manual live-test cards are stopped; do not change lifecycle labels by hand. Class U, S, R issues close on machine evidence." Delete `.github/CURRENT_LIVE_TEST_TEMPLATE.md` with `git rm` (no tool or document links to it).
7. Outside git (three instruction files of the owner; decision OD-G-06). Add exactly these sentences and nothing else:
   - `~/.claude/CLAUDE.md`, table row 2, append: " Exception (owner decision 2026-11-13): in `vermintide-2-tweaker` the unattended rig `tools/harness/run.ps1` may launch Vermintide 2." Row 6, append: " Exception: VT2 monorepo issues of evidence class U, S or R close on machine evidence (that repo's `docs/adr/0001-rig-launch-machine-evidence-no-cards.md`)."
   - `<repos>/CLAUDE.md` line 69: replace the bullet with "- **VT2 launches only through the rig:** `vermintide-2-tweaker/tools/harness/run.ps1` (owner decision 2026-11-13). Never start the game, Steam or a launcher window any other way."
   - `<repos>/AGENTS.md`, section "VT2 monorepo routing" (line 39), append: "In this repo the launch-verification rule above is met only by the rig entry `tools/harness/run.ps1`."

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_pr_autoclose.ps1 -SelfTest` exits 0.
- OFFLINE: `git grep -n "confirms in-game\|ask the user before launching\|launch the game or restart Steam unsolicited" -- CLAUDE.md PROJECT_STANDARDS.md docs/BUG_TRIAGE_RUNBOOK.md CONTRIBUTING.md` prints nothing.
- OFFLINE: `git grep -l "tools/harness/run.ps1" -- CLAUDE.md PROJECT_STANDARDS.md docs/BUG_TRIAGE_RUNBOOK.md CONTRIBUTING.md .github/pull_request_template.md docs/adr` lists six files.
- OFFLINE: `pwsh -NoProfile -File qa/check_publication_doctrine.ps1` exits 0, and `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` ends with `[worktree-purity] OK`.
- RIG: not applicable.
- Evidence class S. Closes no issue; advances #546.

**Guardrails.** Do not post, pin, unpin or edit any card or label on GitHub. Do not delete the card grammar in `PROJECT_STANDARDS.md` section 11 (WP-G-13 does). Keep the ten tokens that `qa/check_publication_doctrine.ps1:865-880` requires in `PROJECT_STANDARDS.md`, and the section 6.6 links in `AGENTS.md` and `CLAUDE.md`. `tools/harness/run.ps1` may not exist yet; the rule is still correct (then nothing may be launched).

**Stop and escalate if.** A quoted anchor sentence is not at or near the cited line (the file changed): skip that item and list it. Your session's own rules forbid editing instruction files outside the repo: leave step 7 undone and paste its sentences into the pull request for the owner (OD-G-06). The self-test of step 2 fails and you cannot see why.

---

### WP-G-02 Install the one-page agent entry and the execution protocol

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | WP-G-01 |
| Issues | advances #1025 |
| Source | E1-F03, E1-F08 |
| Streams | none |

**Goal.** `AGENTS.md` is the single vendor-neutral entry (at most 6,144 bytes), `docs/EXECUTION_PROTOCOL.md` exists, and `CLAUDE.md` sends every agent to `AGENTS.md` first.

**Context.** `AGENTS.md` is 528 bytes and orders agents to read `CLAUDE.md` (65,832 bytes) and `PROJECT_STANDARDS.md` (183,118 bytes) in full: about 62k tokens before any task. The rules are addressed "to Claude" although Codex agents work here too. `qa/check_publication_doctrine.ps1:116-141` requires `AGENTS.md` to exist once and to contain the links `](CLAUDE.md)` and `](PROJECT_STANDARDS.md#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01)`; lines 226-288 reject some line shapes in `AGENTS.md` and `CLAUDE.md`. The drafts in `<audit>/plan/drafts/` already satisfy this (checked with `<audit>/scripts/E1_check_agents_draft.py`).

**Steps.**
1. Copy `<audit>/plan/drafts/AGENTS.md` over `AGENTS.md`, byte for byte.
2. Copy `<audit>/plan/drafts/EXECUTION_PROTOCOL.md` to `docs/EXECUTION_PROTOCOL.md`.
3. `CLAUDE.md`: replace line 3 ("This file provides guidance to Claude Code ...") with "Start with [AGENTS.md](AGENTS.md): it is the mandatory entry for every agent. This file is the long technical reference; read it by section." Replace the block quote that starts "> **READ FIRST**: `PROJECT_STANDARDS.md`" (lines 26-30) with "> `PROJECT_STANDARDS.md` is the operational rulebook. Look up the section you need (6.6 for shipping, 11 for the tracker); it is not required reading in full." Change nothing else in `CLAUDE.md`.
4. Add `qa/check_agent_entry.ps1` (ASCII; parameters `-RepoRoot`, `-Quiet`, `-SelfTest`; exit 0 or 2). It fails when: `AGENTS.md` is larger than 6,144 bytes; it contains a non-ASCII byte; a `Dir` value of `tools/mod-inventory.psd1` does not occur in it; a backticked repo path in it does not exist (skip tokens that contain `<` or `*`, and allow `tools/harness/run.ps1` until that file exists).
5. Wire it into `qa/run_all.ps1` directly after the `check_publication_doctrine` line (line 321): `Run-Check "check_agent_entry" { & (Join-Path $here "check_agent_entry.ps1") -Quiet:$Quiet }`.
6. Outside git, optional (OD-G-06): in `<repos>/AGENTS.md` section "VT2 monorepo routing" replace "first read [its CLAUDE.md]" with "first read its `AGENTS.md`".

**Acceptance (machine, no human).**
- OFFLINE: `git diff --no-index --stat <audit>/plan/drafts/AGENTS.md AGENTS.md` prints nothing.
- OFFLINE: `pwsh -NoProfile -File qa/check_agent_entry.ps1` exits 0; `-SelfTest` exits 0 (fixtures: oversize file, missing mod folder name, dead path are each rejected).
- OFFLINE: `pwsh -NoProfile -File qa/check_publication_doctrine.ps1` exits 0 and `pwsh -NoProfile -File qa/check_publication_doctrine.ps1 -SelfTest` exits 0.
- OFFLINE: `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S. Advances #1025.

**Guardrails.** Do not add rules to the draft (the size limit is the point). Do not delete the rule table in `CLAUDE.md` yet (WP-G-13). Do not edit `qa/check_publication_doctrine.ps1`.

**Stop and escalate if.** `qa/check_publication_doctrine.ps1` reports a violation in `AGENTS.md`: report the line; do not weaken the checker. `docs/adr/0001-rig-launch-machine-evidence-no-cards.md` is missing (WP-G-01 not merged).

---

### WP-G-03 Take the tracker guard out of the pull-request gate

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances #546 |
| Source | E1-F05, E1-F01 |
| Streams | none |

**Goal.** The required check `qa-gate` depends only on the tree under test: no step reads GitHub issue state, and an aged generated file cannot fail it.

**Context.** `.github/workflows/qa.yml:125-141` runs `tools/github/check-lifecycle-cardinality.ps1` inside `qa-gate`, which branch protection requires (`tools/github/protect-master.ps1:8`). The guard reads every open issue's labels, pinned comments and tester comments, so the state of one issue fails every pull request and every master run; a ship needs the master run green (`tools/ship/publication-authorization.ps1:56`). The same guard also runs on tracker events and daily in `.github/workflows/issue-lifecycle.yml`, which is not a required check and stays as it is. Second coupling: `qa/run_all.ps1:377` runs `check_branch_reconciliation_census` with Standard policy, and that check fails once the committed census is older than 14 days (`qa/check_branch_reconciliation_census.ps1:14`; last refresh 2026-11-11).

**Steps.**
1. `.github/workflows/qa.yml`: delete the whole step that starts at line 125 (`- name: check-lifecycle-cardinality.ps1 (tracker lifecycle guard, issue 750)`) through line 141. In the comment at lines 13-15 delete the words "lifecycle cardinality and". Keep `issues: read`.
2. `qa/run_all.ps1` line 377: append ` -Policy 'Advisory'` to the `check_branch_reconciliation_census` call and add one comment line above it: "Advisory: a stale generated census must not fail unrelated pull requests."
3. `PROJECT_STANDARDS.md` lines 2538-2539: change "runs as a blocking step in `.github/workflows/qa.yml` and `.github/workflows/issue-lifecycle.yml`" to "runs in `.github/workflows/issue-lifecycle.yml` (tracker events, manual, daily); it is not part of the pull-request gate".
4. If present, delete the sub-item that starts "**The lifecycle grammar is CI-enforced and fails wide" in `docs/BUG_TRIAGE_RUNBOOK.md` (line 384; WP-G-01 may already have removed it) and the first table row of section 6 in `docs/EXECUTION_PROTOCOL.md`.

**Acceptance (machine, no human).**
- OFFLINE: `git grep -n "check-lifecycle-cardinality" -- .github/workflows/qa.yml` prints nothing.
- OFFLINE: `pwsh -NoProfile -File qa/check_ci_hardening.ps1` exits 0 and `pwsh -NoProfile -File qa/check_ci_hardening.ps1 -SelfTest` exits 0.
- OFFLINE: `pwsh -NoProfile -File tools/github/check-lifecycle-cardinality.ps1 -SelfTest` exits 0 (the guard itself is untouched).
- OFFLINE: `git grep -n "check_branch_reconciliation_census" -- qa/run_all.ps1` shows `-Policy 'Advisory'`; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- After the pull request's own CI run: `gh run view <run-id> --json jobs --jq ".jobs[].steps[].name"` lists no step named `check-lifecycle-cardinality.ps1`.
- RIG: not applicable. Evidence class S. Advances #546.

**Guardrails.** Do not edit `.github/workflows/issue-lifecycle.yml`: `qa/check_ci_hardening.ps1:239-571` pins its exact structure. Do not delete or change the guard script, `tools/github/protect-master.ps1`, or any label.

**Stop and escalate if.** `qa/check_ci_hardening.ps1` fails with a message about `qa.yml` after step 1 (only the first 75 lines of its `Test-CiContract` were read in the audit): report the exact message and do not change the checker.

---

### WP-G-04 Add the verification spec format, schema and checker

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | E1-F01 (target design 9.4) |
| Streams | none |

**Goal.** One JSON file per issue under `qa/specs/` states how that issue is decided, and a check in `qa/run_all.ps1` validates every spec file.

**Context.** Test steps live in pinned GitHub comments (858 `## CURRENT LIVE TEST` cards on open issues). CI cannot validate them without reading the tracker, and each ship makes them stale. The program's verification packs (VP cards, `<audit>/plan/CONVENTIONS.md` section 5) and rig scripts (`qa/runtime/<mod>/issue_<N>_<slug>.lua`) need one machine-readable index per issue that lives in the repo. `qa/specs/` does not exist yet. `Test-Json` is absent from Windows PowerShell 5.1, so the checker validates by hand.

**Steps.**
1. Create `qa/specs/README.md` (at most 3 KB) with this field table (right column: the VP card field it comes from):

   | Field | Type and rule | VP field |
   |---|---|---|
   | `schema` | integer `1` | |
   | `issue` | integer; the file is `qa/specs/issue_<issue>.json` | Issues |
   | `class` | one of `U` `S` `R` `V` `C` `X` | the letter after the issue number |
   | `status` | `draft` (converted, not runnable) or `ready` | |
   | `vp` | string `VP-<BUCKET>-<NN>` or null | VP id |
   | `arena` | `none`, `boot`, `keep`, `deus`, `coop`, `mission:<level_key>`; `unknown` only while `draft`; `none` only for class U, S, X | Arena |
   | `mods` | array of `{ "dir", "min_version", "settings" }`; `dir` is a `Dir` of `tools/mod-inventory.psd1` (the folder names the stream); required for R, V, C | Mods and stream |
   | `boots` | integer, 0 or more | Boots |
   | `depends_on` | array of WP ids | Depends on |
   | `setup` | string | Setup |
   | `cases` | array of `{ "script", "steps": [], "assertions": [], "pass_closes": bool }`; required for R and C | Cases |
   | `offline` | array of `{ "class": "U" or "S", "command", "expect" }`; required for U and S | table "issues that need NO rig" |
   | `rt_checks` | array of `{ "mod", "check", "behavioural": bool }` | Reused in-mod checks |
   | `left_for_humans` | array of strings; required for V and C | Left for humans |
   | `on_fail` | string | If it FAILS |
   | `source` | `{ "card_comment_id", "card_date", "ledger" }` | provenance of a converted card |

2. Create `qa/specs/spec.schema.json` (JSON Schema draft-07) with the same fields, for editors.
3. Create `qa/check_verify_specs.ps1` (ASCII; parameters `-RepoRoot`, `-Quiet`, `-SelfTest`; exit 0 or 2; no network). Rules: R1 the file name matches `issue`; R2 required fields present, enum values valid, no unknown top-level key; R3 the class-conditional requirements of the table; R4 every `mods[].dir` is in the inventory; R5 when `status` is `ready`: every `cases[].script` is a file under `qa/runtime/`, every `offline[].command` is non-empty and its first token that ends in `.ps1` or `.lua` exists, `arena` is not `unknown`; R6 when `status` is `draft`, empty `script` and `command` strings are allowed.
4. Fixtures for `-SelfTest` under `qa/_test_fixtures/verify_specs/`: one valid `ready` spec, one valid `draft` spec, and four invalid ones (wrong file name, class R without `cases`, unknown mod folder, `ready` with a missing script).
5. Wire into `qa/run_all.ps1` after line 321: `Run-Check "check_verify_specs" { & (Join-Path $here "check_verify_specs.ps1") -Quiet:$Quiet }`. With no spec files the check prints `0 specs` and exits 0.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_verify_specs.ps1 -SelfTest` exits 0 (two fixtures accepted, four rejected).
- OFFLINE: `pwsh -NoProfile -File qa/check_verify_specs.ps1` exits 0; `git grep -c "check_verify_specs" -- qa/run_all.ps1` prints 1; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S.

**Guardrails.** No spec file under a mod folder. The checker never calls GitHub. Do not use `Test-Json`. Field names are fixed by this card: other tracks read them.

**Stop and escalate if.** The repo already holds a different per-issue index introduced by track H (look for a schema or README under `qa/runtime/`): reconcile field names with that file instead of adding a second format.

---

### WP-G-05 Convert live-test cards and audit ledgers into draft specs

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-G-04 |
| Issues | none (prepares every open issue) |
| Source | E1-F01 |
| Streams | none |

**Goal.** Every open issue has a `qa/specs/issue_<N>.json` with `status: draft`, built from its newest card and its audit ledger row.

**Context.** 298 of 329 open issues carry at least one comment headed `## CURRENT LIVE TEST`. The fields are regular: `**Build/banner:**`, `**Topology:**` (Solo or Co-op), numbered steps, `**Expected:**` (format in `tools/verify/README.md`). The audit ledgers `<audit>/findings/D1_ledger.tsv` to `D5_ledger.tsv` (tab-separated, 329 rows in total, header row first) give per issue `number`, `verification_class`, `cluster`, `auto_check`, `disposition`. Together they hold what a spec needs; the rig scripts are written later by the VP cards.

**Steps.**
1. Create `tools/tracker/convert-cards.ps1` (ASCII; parameters `-Repository` default `Ensrick/vermintide-2-tweaker`, `-LedgerDir`, `-OutDir` default `qa/specs`, `-IssuesJsonPath` for offline input, `-SelfTest`). It reads open issues and their comments with `gh api --paginate` (read-only).
2. Per open issue build the spec: `class` = the first of U, S, R, V, C, X that appears in the ledger cell `verification_class`; no ledger row means `class: "X"` and `on_fail: "unclassified: triage first"`. `status: "draft"`. `arena`: `none` for U, S, X, otherwise `unknown`. `mods`: one entry per mod label of the issue, mapped with the label table in `PROJECT_STANDARDS.md` section 11 ("Mod (1+)"); for the five dev/stable pairs use the `_dev` folder, and add the stable folder too when the issue has the label `public-release`; `min_version` = the version written next to that mod in the card's `Build/banner` line, or an empty string. `cases`: one case with `script: ""`, `steps` = the card's numbered lines copied verbatim, `assertions` = the card's `Expected` text and the ledger `auto_check` text, `pass_closes` = true for class U, S, R. `offline` (class U, S): one entry with `command: ""` and `expect` = the `auto_check` text. `left_for_humans` (class V, C): the `Expected` text; for class C add "needs two clients". `source`: the comment id, its date, the ledger file name.
3. Never overwrite an existing spec whose `status` is `ready`.
4. `-SelfTest` uses a fixture issue list (one issue with a card, one without) and a fixture ledger under `qa/_test_fixtures/verify_specs/convert/`.
5. Run the tool and commit the generated specs in the same pull request.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/tracker/convert-cards.ps1 -SelfTest` exits 0.
- OFFLINE: the run prints `open issues: N, specs written: N, without card: K, without ledger row: M`; `(Get-ChildItem qa/specs/issue_*.json).Count` equals N.
- OFFLINE: `pwsh -NoProfile -File qa/check_verify_specs.ps1` exits 0.
- RIG: not applicable. Evidence class S.

**Guardrails.** Read-only on GitHub: no comment, label, pin or edit. Copy card text verbatim; invent no step and no expected result. The repo is public and so are the cards, so no scrub is needed, but write no local path into a spec.

**Stop and escalate if.** The ledger files are not found. More than 10 open issues have no ledger row (the tracker moved since the audit: report the list). A card cannot be parsed: write that issue as class X draft and list it in the pull request.

---

### WP-G-06 Simplify lifecycle labels; one tracker write tool; new guard

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (three pull requests: A tool and guard, B workflow switch, C label migration and document text) |
| Agent | strong (changes the CI contract checker and performs about 80 tracker writes) |
| Depends on | WP-G-03, WP-G-05 |
| Issues | advances #546 |
| Source | E1-F01, E1-F14, E1-F21 |
| Streams | none |

**Goal.** Every open issue carries exactly one of `not-started` or `verify-fix`; `needs-human` marks class V and C work; every tracker write goes through one script; the scheduled guard checks only these rules.

**Context.** On 2026-11-13: 228 open issues are `verify-fix`, 54 `diagnostics-armed`, 47 `not-started`; 22 have `coop-required` (all with `verify-fix`), 35 `blocked` (all with `not-started`). The old guard (`tools/github/check-lifecycle-cardinality.ps1`, rules in `tools/verify/lifecycle_method_policy.ps1:1396-1456`) requires a valid pinned card on every ready issue; cards are stopped, so that rule cannot be met for new work. `.github/workflows/issue-lifecycle.yml:58-60` calls the old guard, and `qa/check_ci_hardening.ps1` pins those two command lines (lines 695-697 and its fixtures at 947-1070). `tools/ship/ship.ps1` steps 6 and 6b still load the old card code but never fail a ship (`tools/ship/ship.ps1:2774-2775,2943`); removing them is track P's work.

New scheme:

| Label | Meaning | Comes from |
|---|---|---|
| `not-started` | no candidate fix for this issue is merged | `not-started` (47) and `diagnostics-armed` (54): a probe is now a rig case in the spec |
| `verify-fix` | a candidate fix is merged; evidence is owed | `verify-fix` (228), unchanged |
| `needs-human` (new) | spec class V or C: listed in `docs/generated/HUMAN_LIST.md`; never blocks; only with `verify-fix` | new |
| `coop-required` | two clients needed; only with `verify-fix` (as today) | `coop-required` (22), unchanged |
| `blocked` | class X: waits on a dependency or an owner decision; only with `not-started` | `blocked` (35), unchanged |
| type, priority, mod, `public-release`, `regression`, `audit`, `refactor`, `architecture`, `vanilla-bug`, `deferred`, `question`, `documentation`, `duplicate`, `wontfix`, `human-input-needed`, `stable-promotion-approved` | unchanged | unchanged |
| `diagnostics-armed`, `Fixed`, `verify-fix-coop` | not allowed on an open issue; `diagnostics-armed` and `Fixed` stay in the label set because closed issues use them (11 and 212) | retired for open issues |
| `good first issue`, `help wanted`, `invalid` | deleted (no use on any open or closed issue) | deleted |

**Steps.**
1. (A) Create `tools/tracker/check-tracker.ps1` (ASCII; parameters `-Repository`, `-IssuesJsonPath`, `-SelfTest`; read-only; exit 0 or 2). Rules: T1 exactly one of `not-started`, `verify-fix`; T2 none of `diagnostics-armed`, `Fixed`, `verify-fix-coop`; T3 `blocked` only with `not-started`; T4 `needs-human` only with `verify-fix`; T5 `coop-required` only with `verify-fix`; T6 exactly one of `bug`, `enhancement`, `feature` and exactly one of `0-critical`, `1-major`, `2-moderate`, `3-low`. It prints, without failing, the open issues that have no `qa/specs/issue_<N>.json`.
2. (A) Create `tools/tracker/set-state.ps1` (ASCII; parameters `-Issue`, `-State not-started|verify-fix|closed`, `-EvidencePath`, `-Apply`, `-SelfTest`). Without `-Apply` it prints the plan and writes nothing. With `-Apply`, in this order: (i) create or edit in place the one comment whose first line is `## VERIFICATION STATUS`, with the lines `auto-verified (<class>) on <mod> <version> <commit>, run <id>` (or `FAIL (<class>) on ...`), `Spec: qa/specs/issue_<N>.json`, `Result: PASS|FAIL`, `Left for humans: <text or none>`; (ii) one `gh issue edit` that adds the target lifecycle label and removes the other lifecycle labels in the same call, and adds `needs-human` when the spec class is V or C and the state is `verify-fix`; (iii) for `-State closed`: refuse unless the spec class is U, S or R and the evidence result is PASS; for an issue labelled `public-release` also refuse unless the evidence names a folder whose inventory row has `Public = $true`; then `gh issue close <N> --reason completed`.
3. (B) Replace the two command lines in `.github/workflows/issue-lifecycle.yml` (lines 58 and 60) with `./tools/tracker/check-tracker.ps1 -SelfTest` and `./tools/tracker/check-tracker.ps1 -Repository '${{ github.repository }}'`. In `qa/check_ci_hardening.ps1` replace every occurrence of `./tools/github/check-lifecycle-cardinality.ps1` with `./tools/tracker/check-tracker.ps1` (lines 695, 697, 947, 949, 1021, 1022, 1055, 1057, 1070). Change nothing else in either file.
4. (C) After B is merged, migrate on GitHub: `gh label create needs-human --color D4C5F9 --description "Class V or C: needs a human check; never blocks"`; for each open issue with `diagnostics-armed` run `set-state.ps1 -Issue <N> -State not-started -Apply`; for each open `verify-fix` issue whose spec class is V or C add `needs-human` through `set-state.ps1`; `gh label delete` the three unused labels.
5. (C) Text: in `PROJECT_STANDARDS.md` section 11 replace the list under "**Status (exactly 1 of these on every OPEN issue)**" with the table above, keeping the heading; update `CLAUDE.md` rule 13, `CONTRIBUTING.md` (the three-label list), the header text of the three forms in `.github/ISSUE_TEMPLATE/`, and `.github/pull_request_template.md` to name the two labels and `tools/tracker/set-state.ps1`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/tracker/check-tracker.ps1 -SelfTest` and `pwsh -NoProfile -File tools/tracker/set-state.ps1 -SelfTest` exit 0 (fixtures cover each rule T1 to T6 and each refusal of step 2).
- OFFLINE: `pwsh -NoProfile -File qa/check_ci_hardening.ps1` and `-SelfTest` exit 0 after step 3.
- After step 4: `pwsh -NoProfile -File tools/tracker/check-tracker.ps1` prints `violations: 0` and exits 0; `gh issue list --state open --label diagnostics-armed --json number --jq length` prints 0; `gh label list --limit 200` shows `needs-human` and none of the three deleted labels.
- RIG: not applicable. Evidence class S. Advances #546.

**Guardrails.** Never run a bare `gh issue edit --remove-label` on a lifecycle label; every write goes through `set-state.ps1`. Do not rename `not-started` or `verify-fix` (ship tooling and the audit ledgers use these names). Do not edit `tools/verify/lifecycle_method_policy.ps1`, `tools/ship/ship.ps1` or `tools/ship/refresh-cards.ps1`. Do not unpin, edit or delete existing cards. Do not delete a label that any closed issue uses. Do not touch `stable-promotion-approved`.

**Stop and escalate if.** `qa/check_ci_hardening.ps1` rejects the workflow for a reason other than the command strings. An open issue carries both lifecycle labels or none. Decision OD-G-09 was answered "no".

---

### WP-G-07 Generate the human list; retire the playtest documents

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | WP-G-05, WP-G-06 |
| Issues | none |
| Source | E1-F01, E1-F19, E1-F23 |
| Streams | none |

**Goal.** `docs/generated/HUMAN_LIST.md` lists every open class V and C check and every pending owner decision, generated from the specs; the old playtest documents are gone.

**Context.** `docs/PLAYTEST_SCRIPT.md` (73 KB) and `docs/PLAYTEST_COOP.md` were generated on 2026-09-01 from pinned cards by `tools/verify/generate_playtest.ps1`: 258 checks, section estimates adding up to about 427 minutes. Nobody ran them. Decision (b) says class V and C work goes to a human list and never blocks. No QA script reads the two documents or calls the generator (grep over `qa/`, `tools/`, `.github/`).

**Steps.**
1. Create `tools/tracker/human-list.ps1` (ASCII; parameters `-SpecDir` default `qa/specs`, `-OutPath` default `docs/generated/HUMAN_LIST.md`, `-GenDate` required, `-RigSummaryDir` optional, `-SelfTest`; no network). Output sections: "1. Checks for one person (class V)", "2. Checks for two clients (class C)", "3. Owner decisions (class X)". One row per spec: issue number, mod folders, the `left_for_humans` text (class X: the `on_fail` text), and the path of the newest rig summary for that issue when `-RigSummaryDir` has one. Sort by issue number. Header line: "GENERATED on <GenDate> by tools/tracker/human-list.ps1. Do not edit."
2. Run it and commit `docs/generated/HUMAN_LIST.md`. Add a row for it to `docs/generated/README.md`.
3. `git rm docs/PLAYTEST_SCRIPT.md docs/PLAYTEST_COOP.md`. In `PROJECT_STANDARDS.md` lines 2848-2849 replace the `generate_playtest.ps1` line with "  - tools/tracker/human-list.ps1 (the list of checks that need a person)". At the top of `tools/verify/README.md` add: "Retired 2026-11: the human list is generated by `tools/tracker/human-list.ps1`." Leave `tools/verify/generate_playtest.ps1` in place.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/tracker/human-list.ps1 -SelfTest` exits 0.
- OFFLINE: `pwsh -NoProfile -File tools/tracker/human-list.ps1 -GenDate 2026-11-20` prints `class V: a, class C: b, class X: c`, and the row count of the file equals a+b+c.
- OFFLINE: `git ls-files docs/PLAYTEST_SCRIPT.md docs/PLAYTEST_COOP.md` prints nothing; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S.

**Guardrails.** No GitHub call. Copy spec text; write no time estimate and no description of how anything looks. The list is never a gate.

**Stop and escalate if.** `qa/run_all.ps1` fails because something expects the playtest documents: restore them with `git checkout` and report the failing check.

---

### WP-G-08 Import VT2 knowledge from the Claude memory store

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (three pull requests: ship and pipeline notes; engine and VMF notes; per-mod and project notes) |
| Agent | strong (the repo is public; the scrub of personal data needs judgment) |
| Depends on | none |
| Issues | advances #1025, #546 |
| Source | E1-F04, E1-F09, E1-F13 |
| Streams | none (writes only under `docs/kb/`, `qa/`, `tools/docs/` and rule documents) |

**Goal.** Every VT2 fact that exists only in the Claude memory store is a scrubbed file under `docs/kb/`, and no document outside a mod folder cites a memory note that is not in the repo.

**Context.** The memory store `<memory>` is loaded only into Claude sessions started in `<repos>`. Codex agents, CI and a fresh clone never see it. 154 of its files are linked from its VT2 indexes (about 523 KB): ship recovery traps, engine crash classes, VMF facts, per-mod decisions. The repo depends on it: `PROJECT_STANDARDS.md:2744` defines `[memory: note]` as a provenance tier and `docs/MECHANICS.md` uses it 15 times. 116 memory names cited in repo documents and Lua comments no longer exist in the store. The repo is public: 67 of 68 `reference_vt2_*` notes carry a session id in their front matter, and some notes hold personal paths or quote the owner.

**Steps.**
1. Build `docs/kb/_import_list.txt`: every `.md` file linked from `<memory>/index_vt2_engine_and_vmf.md` and `<memory>/index_vt2_mods.md`, plus every file linked under the headings "## VT2 ship pipeline" and "## VT2 engine, VMF, mods (sub-indexes)" of `<memory>/MEMORY.md`, plus `reference_ps_select_first_kills_ship_pipeline.md`. Drop `index_*` files and names that contain `doomrocket`, `warlock_bombardier`, `ranalds`, `community_shaders` or `crusader`. Expected: 155 names.
2. Create `tools/docs/import-memory.ps1` (ASCII; parameters `-MemoryDir`, `-ListPath`, `-OutDir` default `docs/kb`). For each listed file write `docs/kb/<same name>` with these scrub rules: S1 keep only the front-matter keys `name`, `description`, `type`, and add `status: raw`; S2 replace `<drive>:\Users\<name>\source\repos` with `<repos>` and any other `<drive>:\Users\<name>` or `/c/Users/<name>` with `~`; S3 replace e-mail addresses with `<email>`; S4 delete lines that contain `claude.ai/code/session` or `originSessionId`. It also writes `docs/kb/README.md`: one table row per file (name, type, description, status) and the sentence "Reference notes imported from an agent memory store. Raw: verify against the code before relying on one. Never required reading."
3. Manual pass over the output (this is why the card needs a strong agent): delete sentences that quote the owner or describe the owner's mood; keep the technical content unchanged; turn `[[other-note]]` links into `` `docs/kb/<other-note>.md` `` when that note was imported, otherwise into plain text.
4. Create `qa/check_memory_citations.ps1` (ASCII; `-RepoRoot`, `-Quiet`, `-SelfTest`). It finds three citation shapes: a backticked token `feedback_*.md`, `reference_*.md` or `project_*.md`; a path `memory/<name>.md`; a tag `[memory: <name>]`. Each must resolve to `docs/kb/<name>.md`. Scope with exit 2: root `*.md`, `docs/` (not `docs/kb/`), `qa/`, `tools/`. Mod folders are only counted and printed (`dead citations in mod folders: N`), never failed. Wire it into `qa/run_all.ps1`.
5. Fix every dead citation the check reports outside mod folders: point it at the repo document that holds the content (for example `docs/VMF_RECIPES.md` section 1 for the hook notes), or delete the citation phrase.
6. `PROJECT_STANDARDS.md:2744` and the tag legend at the top of `docs/MECHANICS.md`: change the definition of `[memory: note]` to "a note imported to `docs/kb/<note>.md`". Do not rename the tag: `qa/check_mechanics_citations.ps1` parses it.
7. Outside git, in `<memory>` (OD-G-03): delete nothing. In `MEMORY.md` prefix the index entry "author stale build = STEAM restart" with "SUPERSEDED, do not follow (repo PROJECT_STANDARDS 6.6): ", and put the same sentence as the first body line of `reference_vt2_stale_version_restart_trap.md`. Do not copy the scripts in `<helpers>`: track P moves them (`<audit>/plan/wp/P.md`).

**Acceptance (machine, no human).**
- OFFLINE: `git grep -nE "originSessionId|claude\.ai/code/session|@gmail\.|[A-Za-z]:\\\\Users\\\\" -- docs/kb` prints nothing.
- OFFLINE: `(Get-ChildItem docs/kb/*.md).Count` is at least the line count of `docs/kb/_import_list.txt` plus 1.
- OFFLINE: `pwsh -NoProfile -File qa/check_memory_citations.ps1` exits 0 and prints `dead citations outside mod folders: 0`; `pwsh -NoProfile -File qa/check_mechanics_citations.ps1` exits 0; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S. Advances #1025 and #546.

**Guardrails.** Public repo: no owner quotes, no names, no session ids, no local paths. Import only the listed VT2 notes. Do not edit any file under a mod folder (their documents and Lua comments are build inputs). Do not correct technical content during the import; mark it `raw`. Do not link `docs/kb/` from `AGENTS.md`.

**Stop and escalate if.** A note contains a credential, a token or personal data about a third person: skip the file and list it. `<memory>` cannot be found, or more than 20% of the listed files are missing. Decision OD-G-07 was answered "no".

---

### WP-G-09 Generate the command, hook and QA-check inventories

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | WP-G-02 |
| Issues | none |
| Source | E1-F12, E1-F19, E1-F22 |
| Streams | none (reads mod folders, writes none) |

**Goal.** The command list, the hook list and the QA-check list are produced by one script, and a check fails when a tracked copy is stale.

**Context.** `docs/COMMANDS.md` is a hand-kept snapshot dated 2026-08-13: 161 of 410 literal `mod:command("...")` names in the active mods do not appear in it. `qa/README.md:31` says the folder ships 18 checks; there are 107 `qa/check_*.ps1`, `qa/run_all.ps1` names 74 of them, and `qa/CHECKS.md` omits 23. No document says which checks block. Hooks are described by hand in 15 `ENGINE_SURFACE.md` files inside mod folders.

**Steps.**
1. Create `tools/docs/gen-inventories.ps1` (PowerShell 7, runs on Linux CI; parameters `-RepoRoot`, `-OutDir`; no network; output sorted, LF line endings, no dates). It loads `tools/mod-inventory.psd1` with `Import-PowerShellDataFile` and writes:
   - `docs/COMMANDS.md` (replaces the hand file): per mod folder, every name matched by `mod:command\(\s*"([A-Za-z0-9_]+)"` in `<Dir>/scripts/mods/**/*.lua`, with the description string (second argument, when it is a literal) and the file that registers it.
   - `docs/generated/HOOKS.generated.md`: per mod folder, rows `Class | method | kind | file:line` matched by `mod:(hook|hook_safe|hook_origin)\(\s*("?[A-Za-z_][\w.]*"?)\s*,\s*"([A-Za-z_]\w*)"`, then a list "same (mod, Class, method) registered more than once".
   - `docs/generated/QA_CHECKS.generated.md`: one row per `qa/check_*.ps1`: name, named in `qa/run_all.ps1` (yes or no), policy taken from its `Run-Check` line (`Standard` when no `-Policy`), first comment line of the script.
   Each file starts with "GENERATED by tools/docs/gen-inventories.ps1. Do not edit."
2. Create `qa/check_generated_docs.ps1` (ASCII; `-RepoRoot`, `-Quiet`, `-SelfTest`): runs the generator into a folder under `[IO.Path]::GetTempPath()`, compares the three files byte for byte with the tracked copies, and also requires every inventory `Dir` to occur in `AGENTS.md` and `README.md`. Exit 2 on a difference with the message "run pwsh tools/docs/gen-inventories.ps1". `-SelfTest` uses a small fixture tree under `qa/_test_fixtures/gen_inventories/` and proves that an added `mod:command` line makes the comparison fail.
3. Wire `check_generated_docs` into `qa/run_all.ps1` (Standard).
4. `qa/README.md` lines 28-34: replace the note with "The complete list of checks with their policy is `docs/generated/QA_CHECKS.generated.md`."

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/docs/gen-inventories.ps1` prints `commands: N` with N at least 410; a second run leaves `git status --short` unchanged.
- OFFLINE: `pwsh -NoProfile -File qa/check_generated_docs.ps1` exits 0 and `-SelfTest` exits 0.
- OFFLINE: `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes and ends with `[worktree-purity] OK`.
- RIG: not applicable. Evidence class S.

**Guardrails.** Do not overwrite `qa/CHECKS.md` (hand-written map of bug classes to checks). Write nothing under a mod folder. No timestamps in generated files. The check must leave no file in the worktree (the purity check in `qa/run_all.ps1` fails otherwise).

**Stop and escalate if.** A script under `qa/` or `tools/` parses the old `docs/COMMANDS.md` format (none on 2026-11-13: check with `git grep -n "COMMANDS.md" -- qa tools`).

---

### WP-G-10 Fix the verified contradictions in rule documents

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | WP-G-01, WP-G-02 (same files) |
| Issues | advances #1025 |
| Source | E1-F07, E1-F12 (contradictions C1 to C31 in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/E1.md`) |
| Streams | none |

**Goal.** Each fact below is stated once, correctly, in the rule documents outside mod folders.

**Context.** The audit verified 31 contradictions against code. The ones fixed here: the duplicate-hook rule is described three ways and two contradict the VMF source (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/hooks.lua:197-236`: a mod's second registration on the same object and method keeps the first handler and logs a warning); three logging doctrines; four statements about which document is the mod inventory's authority; stale counts and file sizes; code citations that point at the wrong file; a retired subsystem in the triage runbook.

**Steps.**
1. Hooks. Use this wording everywhere: "VMF keeps one hook per mod per hooked function. A second `mod:hook`, `mod:hook_safe` or `mod:hook_origin` from the same mod on the same `(object, method)` is neither chained nor a replacement: VMF keeps the first handler and logs `Attempting to rehook active hook [<method>]` through `mod:warning` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/hooks.lua:209-234`). The second handler never runs. The hook is keyed by the hooked object, so a hook on a class table and a hook on an instance are separate hooks (`hooks.lua:197-205`)." Apply it to `docs/VMF_RECIPES.md` lines 12-29 (replace the Rule and Why paragraphs of section 1) and `CLAUDE.md` line 336 (replace the paragraph). In `CLAUDE.md` line 16 and lines 39-41 replace "VMF silently drops the 2nd" / "VMF silently drops the SECOND hook" with "VMF keeps the first hook and ignores the second with a log warning".
2. Logging. `PROJECT_STANDARDS.md` section 3.2 (line 290): insert as first line "Diagnostics use engine `printf` (section 3.6). The levels below are for user-facing messages only." Section 3.4 (lines 308-309): replace "An `info`-level entry log" with "A `printf` entry log" and "A `warning`-level log" with "A `printf` log". Line 2823: replace with "  - Diagnostics: engine printf with a [mod:feature] prefix (sec. 3.6)".
3. Precedence. `PROJECT_STANDARDS.md` line 1843: replace the sentence "Precedence is CLAUDE.md > PROJECT_STANDARDS > topic docs (the global prefs restate this)." with "Precedence: what a script enforces, then `AGENTS.md`, then section 6.6 for shipping, then other documents."
4. Inventory authority. `tools/mod-inventory.psd1` lines 15-16 (comment only): "Values come from each mod's itemV2.cfg. The tables in README.md, AGENTS.md and CLAUDE.md are copies of this file." `README.md` line 16: "This table mirrors `tools/mod-inventory.psd1`, which is the authority." `CLAUDE.md` line 149: start the paragraph with "`tools/mod-inventory.psd1` is the authority for repository membership, stream and Workshop ID." `CONTRIBUTING.md` line 93: "The authoritative inventory is `tools/mod-inventory.psd1`; [README.md](./README.md#mod-directory) mirrors it." `README.md` line 25 (`character_dialogue` row): change `Single/private` to `Single/friends-only`.
5. Stale state. `PROJECT_STANDARDS.md` lines 33-44 (first bullet under "What's still weak"): replace with "- **File sizes.** The frozen list of files over the 2,500-line limit is `qa/baselines/file_sizes.json`; `qa/check_file_sizes.ps1` blocks growth. Tracked in issue #2." Line 2178: remove `` `lobby_tweaker`, ``. Line 2188: heading becomes "### 10.3 Stable (clean version, no suffix)". Line 2198: delete the "Candidates" line. Line 2828: "  - Launcher resolved per docs/PORTABLE_SETUP.md". Line 2837: "  - lint-mod.ps1 and luacheck pass (forward references)".
6. Code citations in `CLAUDE.md` (name the symbol, no line number): line 431 -> `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` (`_skin_requires_unowned_dlc`); line 434 -> `career_tweaker/scripts/mods/career_tweaker/_crt_talent_swap.lua` (`_career_requires_unowned_dlc`); line 437 -> `character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua` (`_build_entry`, the line `entry.required_dlc = nil`).
7. `CLAUDE.md` line 461: delete the bullet "Never clean `.build/` unless file lock errors" (only the frozen `tweaker/` has `.build/`). Line 282: replace the list of what the hook runs with "It runs the eight steps listed at the top of `tools/hooks/pre-commit.ps1`."
8. `docs/BUG_TRIAGE_RUNBOOK.md`: delete the table row at line 195 (`[BR:fp] MISMATCH`) and the row at line 518 ("Crash on join ... shared BR registration"). Big Rebalance is retired (`docs/RETIRED_BIG_REBALANCE.md`) and no active Lua emits `[BR:fp]`.
9. `qa/README.md`: line 31 remove the count "18 `check_*.ps1` scripts" (say "see `qa/run_all.ps1`" unless WP-G-09 already replaced the note); lines 94-99: replace the baseline paragraph with "Luacheck findings are advisory (`PROJECT_STANDARDS.md` section 11b)."; lines 147-148: replace with "- In-game checks run through the rig (`tools/harness/run.ps1`) and the per-mod `/<mod>_regression_test` commands."
10. Outside git, optional (OD-G-06): in `<repos>/CLAUDE.md` remove `bt/` from the "15+ active VMF mods" list and delete the bullet "Big Rebalance integration" under "Active project state" (the mod is retired).

**Acceptance (machine, no human).**
- OFFLINE, each prints nothing: `git grep -n "silently overwrite\|treats the second registration as\|silently drops the 2nd\|silently drops the SECOND" -- CLAUDE.md docs/VMF_RECIPES.md`; `git grep -n "BR:fp" -- docs/BUG_TRIAGE_RUNBOOK.md`; `git grep -n "no current mods at this tier\|future: luacheck\|9 Lua files remain\|Precedence is CLAUDE.md" -- PROJECT_STANDARDS.md`; `git grep -n "cosmetics_tweaker.lua:43\|career_tweaker.lua:77\|~7895\|Never clean" -- CLAUDE.md`; `git grep -n "18 .check_" -- qa/README.md`.
- OFFLINE: `git grep -c "hooks.lua:209-234" -- docs/VMF_RECIPES.md CLAUDE.md` prints a count of at least 1 for each file; `git grep -n "Single/private" -- README.md` shows only the `modded_progression` row.
- OFFLINE: `pwsh -NoProfile -File qa/check_publication_doctrine.ps1`, `pwsh -NoProfile -File qa/check_mod_inventory.ps1` and `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` pass.
- RIG: not applicable. Evidence class S. Advances #1025.

**Guardrails.** Edit only root files, `docs/`, `qa/README.md` and the comment in `tools/mod-inventory.psd1`. No file under a mod folder. Change only the quoted sentences; do not rewrite sections. Table rows stay on one line.

**Stop and escalate if.** An anchor sentence is not found: skip that item and list it. A gate fails after the `tools/mod-inventory.psd1` comment edit: revert only that edit and report the gate.

---

### WP-G-11 Take documentation out of the build receipt

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (pull request 1: the proof of step 1; pull request 2: steps 2 to 5) |
| Agent | strong (changes release tooling that every ship depends on) |
| Depends on | none; coordinate with track P |
| Issues | advances #1025 and #558 |
| Source | E1-F06 |
| Streams | tooling only; every mod folder's receipt must stay valid |

**Goal.** Editing a markdown file other than `CHANGELOG.md` inside a mod folder no longer invalidates that mod's `.build-receipt.json`.

**Context.** `Test-VtBuildReceiptRelevantPath` (`tools/ship/build-receipt.ps1:122-135`) treats every file in a mod folder as a build input except `.build-receipt.json` and `bundleV2/`. `chaos_wastes_tweaker_dev/.build-receipt.json` lists 26 markdown files among its 126 `source_files`. So a typo fix in `<mod>/ENGINE_SURFACE.md` fails `qa/check_build_receipts.ps1` until someone runs a claimed build; issue #1025 published CWV 0.1.560-dev only to carry documentation corrections. 212 markdown files live in mod folders and 20 of 21 mods have a tracked receipt. The atomicity gate already treats `.md` as non-runtime (`qa/check_release_bundle_atomicity.ps1:333-335`).

**Steps.**
1. Proof, no repo change. In your worktree run `pwsh tools/ship/ship.ps1 -Mod event_tweaker -BuildOnly -NoClaim` on unchanged source and note `output_fingerprint_sha256` in `event_tweaker/.build-receipt.json` (`-NoClaim` is accepted only with `-BuildOnly`, `tools/ship/CLAIMS.md` section "-NoClaim"; this command was not run during the audit). Move every `event_tweaker/*.md` except `CHANGELOG.md` to a folder outside the worktree, run the command again, note the fingerprint, then restore with `git checkout -- event_tweaker`. Equal fingerprints prove the compiler ignores the markdown. Put both values in the pull request.
2. In `Test-VtBuildReceiptRelevantPath`, after the `bundleV2/` test, return `$false` when the path ends in `.md` (case-insensitive) and its file name is not `CHANGELOG.md`.
3. Keep existing receipts valid without regenerating them: where a receipt's recorded `source_files` are compared with the recomputed map (`Compare-VtBuildSourceMaps`, `tools/ship/build-receipt.ps1:540`, and its callers in `qa/check_build_receipts.ps1`), filter the recorded entries through the same predicate before comparing. Leave any integrity check of `source_fingerprint_sha256` on the unfiltered recorded list.
4. Extend `qa/check_build_receipts.ps1 -SelfTest`: (a) editing `example_mod/DEVELOPMENT.md` after the receipt was written keeps it valid; (b) editing `example_mod/CHANGELOG.md` still invalidates it (the existing fixture near line 470 expects that); (c) a receipt that lists a markdown source file still validates.
5. Text: in `PROJECT_STANDARDS.md` section 6.6, after the sentence "Only the exact bookkeeping file `.build-receipt.json` is excluded from its own map." add "Markdown files other than `CHANGELOG.md` are also excluded." In `AGENTS.md` change "(documentation included)" to "(`CHANGELOG.md` included, other documentation excepted)", and adjust section 3 of `docs/EXECUTION_PROTOCOL.md` the same way.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_build_receipts.ps1 -SelfTest` exits 0; `pwsh -NoProfile -File qa/check_build_receipts.ps1` exits 0 on the unchanged tree (all 20 receipts still valid).
- OFFLINE: append one blank line to `event_tweaker/DEVELOPMENT.md` without committing; `pwsh -NoProfile -File qa/check_build_receipts.ps1` exits 0; restore with `git checkout -- event_tweaker/DEVELOPMENT.md`.
- OFFLINE: `pwsh -NoProfile -File tools/ship/ship.ps1 -SelfTest` exits 0 and `pwsh -NoProfile -File qa/check_ps51_compatibility.ps1` exits 0.
- RIG: not applicable. Evidence class S. Advances #1025 and #558.

**Guardrails.** Do not regenerate or hand-edit any `.build-receipt.json`. Exclude no other extension: only markdown is proven. `tools/ship/*.ps1` are ASCII and must parse under Windows PowerShell 5.1. If `<audit>/plan/wp/P.md` has a card that changes receipt policy or stops tracking bundles (#558), make this change inside that card.

**Stop and escalate if.** The two fingerprints of step 1 differ (markdown is then a real input; the alternative, moving documents out of mod folders, needs a new card). `-BuildOnly` cannot run on this machine. Step 3 would require changing how `source_fingerprint_sha256` is verified.

---

### WP-G-12 Add a documentation link check; sweep the repository root

| Field | Value |
|---|---|
| Priority | P3 |
| Size | M |
| Agent | any |
| Depends on | WP-G-02 |
| Issues | none |
| Source | E1-F13, E1-F20 |
| Streams | none |

**Goal.** Rule documents outside mod folders contain no dead repo link, and the root holds no redirect stub, no self-declared historical file and no empty ownership table.

**Context.** Eleven root files are redirect or "retired" stubs from 2026-07 (`COMMANDS.md`, `CROSS_MOD_ARCHITECTURE.md`, `LOCALIZATION_STANDARD.md`, `VMF_RECIPES.md`, `WEAPONS.md`, `WEAPON_CATALOG.md`, `TODO.md`, `WORK_ITEMS.md`, `TESTING_STATUS.md`, `.meta_boons_audit_2026-05-24.md`, `.test_coverage_audit_2026-05-24.md`); none has an inbound markdown link, and three of them disagree about `STATUS.md`. The root stub `REGRESSION_CHECKLIST.md` is linked from 17 files inside mod folders, so it stays. `STATUS.md` (35 KB) and `ANIMATION_RESEARCH.md` call themselves historical; two hidden dated notes sit at the root. `MOD_OWNERSHIP.md` says "Ensrick" in all 22 rows. No script under `qa/` or `tools/` reads any of these files. `CLAUDE.md`, `PROJECT_STANDARDS.md` and `DEVELOPMENT.md` contain 8, 14 and 19 path references that do not resolve.

**Steps.**
1. Create `qa/check_doc_links.ps1` (ASCII; `-RepoRoot`, `-Quiet`, `-SelfTest`; exit 0 or 2). Scope: root `*.md`, `docs/**/*.md` except `docs/generated/` and `docs/kb/`, `qa/*.md`, `tools/**/*.md`, `.github/*.md`. It checks (a) markdown links `](path)` or `](path#anchor)` that are not `http` links, and (b) backticked tokens that contain `/` and end in `.md`, `.ps1`, `.psd1`, `.json` or `.yml`. The target must exist relative to the repo root or to the document's folder. Skip tokens that contain `<`, `*` or `...`, tokens that start with `scripts/`, `foundation/` or `Vermintide-2-Source-Code/` (game source), and entries of `qa/baselines/doc_links_allow.txt` (one path per line, then a tab and a reason).
2. Run it. For each dead reference fix the path or delete the sentence. A reference to a file that is deliberately gone goes into the allow file with the reason `historical`. The allow file may hold at most 30 lines.
3. `git rm` the eleven stubs named above.
4. `git mv` into `_archive/docs/2026-11_root_sweep/`: `STATUS.md`, `ANIMATION_RESEARCH.md`, `.ammo_system_design_2026-05-24.md`, `.chest_of_trials_crash_2026-05-23.md`.
5. `git rm MOD_OWNERSHIP.md` and fix its references: delete the bullet at `CLAUDE.md:288`; in `CLAUDE.md:291` delete "check its durable role in `MOD_OWNERSHIP.md`,"; `CONTRIBUTING.md:49` becomes "2. Check `git status` and open pull requests before editing a mod."; delete the bullet at `.in_progress/README.md:56-57`; in `PROJECT_STANDARDS.md:1802` delete "+ `MOD_OWNERSHIP.md`".
6. Delete the entries for `STATUS.md` and `ANIMATION_RESEARCH.md` in the "Documentation Map" and "Key Reference Files" lists of `CLAUDE.md` and their rows in the table of `PROJECT_STANDARDS.md` section 7.1.
7. Wire `check_doc_links` into `qa/run_all.ps1` (Standard).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_doc_links.ps1 -SelfTest` exits 0 and `pwsh -NoProfile -File qa/check_doc_links.ps1` exits 0.
- OFFLINE: `git ls-files COMMANDS.md TODO.md WORK_ITEMS.md TESTING_STATUS.md STATUS.md MOD_OWNERSHIP.md` prints nothing; `git ls-files REGRESSION_CHECKLIST.md ITEM_LIST.md DEVELOPMENT.md` prints three files.
- OFFLINE: `(Get-Content qa/baselines/doc_links_allow.txt).Count -le 30` is true; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S.

**Guardrails.** Keep `REGRESSION_CHECKLIST.md` (root), `ITEM_LIST.md`, `DEVELOPMENT.md`, `MOD_DEPENDENCIES.md`, `CONTRIBUTING.md` (linked from `.github/ISSUE_TEMPLATE/config.yml`) and `CHANGELOG.md`. Use `git mv` and `git rm` only. No edit under a mod folder; a dead link inside a mod folder is out of scope.

**Stop and escalate if.** `qa/check_stale_docs.ps1` or another check fails because a stub is gone: restore that stub and report the check.

---

### WP-G-13 Split PROJECT_STANDARDS into a tracker runbook, standards and pointers

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (pull request 1: section 11; pull request 2: code and testing sections; pull request 3: stale sections and the `CLAUDE.md` rule table) |
| Agent | strong (decides which rule text survives; must not lose a rule that has no gate) |
| Depends on | WP-G-01, WP-G-06, WP-G-12 |
| Issues | advances #1025 and #546 |
| Source | E1-F03, E1-F10, E1-F11 |
| Streams | none |

**Goal.** `PROJECT_STANDARDS.md` holds section 6 plus one pointer line per other section (under 70 KB); tracker rules are `docs/runbooks/tracker.md` (at most 6 KB); code and test rules are `docs/standards/code.md` and `docs/standards/testing.md` (at most 12 KB together); `CLAUDE.md` no longer carries a rule table.

**Context.** `PROJECT_STANDARDS.md` is 183,118 bytes: 58% is process text. Section 11 (27.8 KB) is mostly the grammar of the stopped cards. Sections 1, 10 and 14 are stale. `AGENTS.md` now carries the rules that no script enforces. Other documents cite sections by number ("PROJECT_STANDARDS section 11", "section 3.6"), so every numbered heading must stay. `qa/check_publication_doctrine.ps1:116-141,865-880` requires the 6.6 heading, ten tokens inside this file and the links to it from `AGENTS.md`, `CLAUDE.md` and `docs/PORTABLE_SETUP.md`. Section 6.5 and 6.6 content belongs to track P.

**Steps.**
1. Create `docs/runbooks/tracker.md`: issue format (title, the four bold labels), the label table of WP-G-06, "state changes only through `tools/tracker/set-state.ps1`", evidence classes (pointer to `docs/adr/0001-rig-launch-machine-evidence-no-cards.md`), umbrella rule (three lines), external intake (three lines), `Refs #N` rule. No card grammar.
2. Create `docs/standards/code.md` from sections 2, 3, 4, 9, 9a, 9b and `docs/standards/testing.md` from 2.2b, 5, 11b, 14a, 15: rules only, one logging doctrine (WP-G-10 wording), the hook wording of WP-G-10, no incident history.
3. For incident history worth keeping write at most ten decision records `docs/adr/NNNN-<slug>.md` (2 KB each). The rest stays in git history.
4. In `PROJECT_STANDARDS.md` replace the body of every moved section with one line under its unchanged heading, for example "Moved to `docs/runbooks/tracker.md`." Replace the bodies of sections 1, 10, 12, 13 and 14 with "Removed 2026-11; see `AGENTS.md`." Keep section 6 byte for byte. Keep section 7.1's table but delete rows for files that no longer exist.
5. `CLAUDE.md`: delete the NON-NEGOTIABLES table and the STOP block (lines 5 to 52) after checking each row has a home: rows 1 to 4, 6 to 10, 12, 13 are in `AGENTS.md`; row 5 is in the `AGENTS.md` gate list; row 11 is `docs/LOCALIZATION_STANDARD.md` section 13; row 14 is in the `AGENTS.md` task table; row 15 is the decision record 0001; row 16 is `docs/EXECUTION_PROTOCOL.md`. Keep one link to section 6.6 in `CLAUDE.md`.

**Acceptance (machine, no human).**
- OFFLINE: `(Get-Item PROJECT_STANDARDS.md).Length -lt 70000`; `(Get-Item docs/runbooks/tracker.md).Length -le 6144`; `((Get-Item docs/standards/code.md).Length + (Get-Item docs/standards/testing.md).Length) -le 12288`: all true.
- OFFLINE: `foreach ($n in '1','2','3','4','5','6','7','8','9','9a','9b','10','11','11a','11b','12','12a','13','14','14a','15') { if (-not (Select-String -Path PROJECT_STANDARDS.md -Pattern "^## $n\. " -Quiet)) { "missing $n" } }` prints nothing.
- OFFLINE: `git grep -n "CURRENT LIVE TEST" -- docs/runbooks docs/standards` prints nothing; `pwsh -NoProfile -File qa/check_publication_doctrine.ps1` and `-SelfTest` exit 0; `pwsh -NoProfile -File qa/check_doc_links.ps1` exits 0; `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` passes.
- RIG: not applicable. Evidence class S. Advances #1025 and #546.

**Guardrails.** Do not change section 6.5 or 6.6 (track P). Do not change the text of any numbered heading. Add no new rule: move or delete only. The size budgets are hard limits. No edit under a mod folder.

**Stop and escalate if.** A rule in the old text has no gate, is not in `AGENTS.md`, and you cannot tell whether it still matters: drop it from the new files and list it in the pull request under "Rules dropped, owner to confirm" (OD-G-04). Track P has moved section 6.6: then follow its card for the checker tokens.

---

### WP-G-14 Sweep docs/: archive finished plans, delete stale generated files

| Field | Value |
|---|---|
| Priority | P3 |
| Size | M |
| Agent | any |
| Depends on | WP-G-07, WP-G-12 |
| Issues | none |
| Source | E1-F19, E1-F20 |
| Streams | none |

**Goal.** `docs/` holds only current reference, runbooks, standards, decision records and generated files that a gate keeps fresh.

**Context.** `docs/generated/OPEN_ISSUE_CONTINGENCIES.generated.md` (2.9 MB) and `docs/generated/OPEN_ISSUE_AUDIT.generated.json` were generated on 2026-07-18 for 317 issues; no script reads them. `docs/OOP_REFACTOR_PLAN.md` says "Status: COMPLETE". `docs/audits/` holds six dated snapshots from July 2026. `docs/OVERNIGHT_RETROSPECTIVE_2026-07-15.md` is a dated retrospective. `docs/engine/IMPROVEMENT_BACKLOG.md` is a backlog inside a document. Generated files that gates read and that must stay tracked: `docs/generated/NAME_MAP.generated.json` (`qa/check_name_integrity.ps1:246`), `docs/generated/APPEARANCE_CENSUS_GAPS.generated.md` (`qa/check_appearance_census_gaps.ps1`), `docs/generated/BRANCH_RECONCILIATION.generated.*` (`qa/check_branch_reconciliation_census.ps1`).

**Steps.**
1. `git rm docs/generated/OPEN_ISSUE_CONTINGENCIES.generated.md docs/generated/OPEN_ISSUE_AUDIT.generated.json`. In `docs/generated/README.md` delete their two table rows and their regenerate command.
2. `git mv` into `_archive/docs/2026-11_docs_sweep/`: `docs/OOP_REFACTOR_PLAN.md`, `docs/OVERNIGHT_RETROSPECTIVE_2026-07-15.md`, `docs/engine/IMPROVEMENT_BACKLOG.md`, and the folder `docs/audits/`.
3. Run `pwsh -NoProfile -File qa/check_doc_links.ps1` and fix what it reports (known referrers: `CLAUDE.md`, `PROJECT_STANDARDS.md`, `docs/engine/README.md`, `docs/engine/01_foundation_and_oop.md`, `qa/CHECKS.md`): delete the sentence or point it at the archive path.
4. In `PROJECT_STANDARDS.md` section 11 delete the subsection "Three empirical fallback paths" if WP-G-13 has not already done so (its generated register is gone; OD-G-04).

**Acceptance (machine, no human).**
- OFFLINE: `git ls-files docs/generated/OPEN_ISSUE_CONTINGENCIES.generated.md docs/generated/OPEN_ISSUE_AUDIT.generated.json docs/audits docs/OOP_REFACTOR_PLAN.md docs/engine/IMPROVEMENT_BACKLOG.md` prints nothing.
- OFFLINE: `git ls-files docs/generated/NAME_MAP.generated.json docs/generated/APPEARANCE_CENSUS_GAPS.generated.md docs/generated/BRANCH_RECONCILIATION.generated.json` prints three files.
- OFFLINE: `pwsh -NoProfile -File qa/check_doc_links.ps1`, `pwsh -NoProfile -File qa/check_source_provenance.ps1` and `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua` pass.
- RIG: not applicable. Evidence class S.

**Guardrails.** Do not move or delete `docs/engine/01` to `11`, `docs/engine/README.md`, `docs/engine/SOURCE_PROVENANCE.json`, `docs/BUG_CLASSES.md`, `docs/MECHANICS.md`, `docs/VMF_RECIPES.md`, `docs/CROSS_MOD_ARCHITECTURE.md`, `docs/PORTABLE_SETUP.md`, `docs/PROMOTION_PROCESS.md`, `docs/BUNDLE_AUTHORITY.md`, `docs/LOCALIZATION_STANDARD.md` (QA scripts read or name them). Leave `docs/APPEARANCE_UNIFICATION_PLAN.md`, `docs/LA_SYNC_CORE_AUDIT.md`, `docs/TRANSLATION_READINESS_444.md`, `docs/WEAPON_APPEARANCE_STANDARD.md`, `docs/WEAPON_APPEARANCE_EXTRACTION_420.md`, `docs/CUSTOM_WEAPON_MODEL_PIPELINE.md` and `docs/RETIRED_BIG_REBALANCE.md` in place: the mod-family tracks may cite them. Use `git mv` and `git rm` only.

**Stop and escalate if.** A check fails after a move: move the file back and report the check.

---

## Owner decisions

| Id | Question | Conservative default used by the cards |
|---|---|---|
| OD-G-01 | While nobody tests by hand, should every change to a mod still get its own version and Workshop upload, public single-stream items included? | Keep today's rule: one ship per merged mod change (the version claim expires after 24 hours). Never ship a build whose only content is a diagnostic probe; probes run on the rig. Revisit once the rig can load a local `-BuildOnly` output. |
| OD-G-02 | Is the friends-only `weapon_tweaker_dev` mirror still needed? | Keep the mirror and its parity gate unchanged. |
| OD-G-03 | May VT2 rules and knowledge live only in the repo, with the Claude memory store reduced to personal preferences? | Import into the repo (WP-G-08) and delete nothing from the store. Only the one entry that contradicts the repo is marked superseded. |
| OD-G-04 | Which preference rules still matter when agents are the main readers: 8-word titles, 150-word bodies, no em dashes, three fallback paths? | Keep the title, body and em-dash rules as guidance without a gate. Stop requiring the three-fallback comment (24 of 329 issues have one; the spec field `on_fail` replaces it). Any other rule dropped by WP-G-13 is listed in its pull request for confirmation. |
| OD-G-05 | Who grants stable promotions, clean-version releases and outside feature requests? | Agents never add `stable-promotion-approved`, never ship a clean-version release and never implement an outside request. These wait in section 3 of `docs/generated/HUMAN_LIST.md`. Consequence: the 20 open `public-release` issues cannot close until promotions are approved. |
| OD-G-06 | May agents edit the owner's instruction files outside git (`~/.claude/CLAUDE.md`, `<repos>/CLAUDE.md`, `<repos>/AGENTS.md`)? | Only the exact sentences written in WP-G-01 step 7, WP-G-02 step 6 and WP-G-10 step 10. If the session forbids it, the agent pastes the sentences into the pull request and the owner applies them. |
| OD-G-07 | The repo is public. May scrubbed memory notes be published in it? | Yes, after the scrub of WP-G-08 (no session ids, personal paths, e-mail addresses or owner quotes). A doubtful note is skipped and listed. |
| OD-G-08 | The repo's `.git/config` sets `user.name = VT2 QA`, which overrides the owner's identity in every worktree. Repair it? | Leave the config alone. Agents commit with the global identity (`docs/EXECUTION_PROTOCOL.md` section 0). |
| OD-G-09 | Retire `diagnostics-armed` for open issues and add `needs-human` (labels are visible to outside reporters)? | Yes, as in WP-G-06. No label used by a closed issue is deleted. |
