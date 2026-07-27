# BUG_TRIAGE_RUNBOOK.md

**Audience:** any Claude session that has just received a user bug report.
**Goal:** run a fully autonomous bug-fix loop. The user plays Vermintide 2,
reports an issue in chat (possibly just "X broke"), and you diagnose from the
logs and data, fix, ship, and hand back ONE concrete in-game check. You do not
stop to ask permission for the reversible steps in between.

**This file is THE entry point.** On any bug report, work STEP 0 -> STEP 9 in
order. Do not skip ahead to reading mod source before STEP 2 has confirmed what
was actually running. Most reports never reach STEP 5, because STEP 3 finds a
known class or STEP 2 finds a stale build.

**Read order on a fresh report:** this file -> the newest console log ->
`docs/BUG_CLASSES.md` -> mod source (only if steps 0-4 did not resolve it).

> **Binding docs cross-referenced from this runbook** (cite by section number
> when applying a rule):
> - `PROJECT_STANDARDS.md` (operational rulebook)
> - `CLAUDE.md` (technical reference + Build Commands + Mod Directory)
> - `docs/BUG_CLASSES.md` (known bug patterns; pattern-match here first)
> - `VMF_RECIPES.md` (Vermintide Mod Framework gotchas)
> - `DEVELOPMENT.md` (engine quirks, known errors)
> - per-mod `CHANGELOG.md` + `REGRESSION_CHECKLIST.md` + `POSTMORTEMS.md`

---

## STEP 0 - INTAKE

- [ ] **Mirror the report back as a numbered list if it holds more than one
  distinct problem.** Track each item separately through the whole pipeline.
  Never merge distinct issues into one "fix" - one session collapsed three
  staff bugs into one and shipped a wrong diagnosis for all three.
- [ ] **Ask for a screenshot or the exact on-screen text ONLY if the report is
  ambiguous** (you cannot tell which mod, which screen, or which symptom). A
  clear one-line report like "the scythe holds wrong in third person" is enough
  to start; do not stall the loop asking for detail you can get from the log.
- [ ] **Restate each item in your own words before acting** so the user can
  correct a misread early.

Every later step operates per-item. If item 1 is a known class and item 2 is
novel, run STEP 3 on item 1 and STEP 5 on item 2 in parallel.

---

## STEP 1 - GET THE LOG

VT2 console logs live at:

```
%APPDATA%\Fatshark\Vermintide 2\console_logs\
```

- [ ] **Read the newest `console-*.log`** that covers the session in question.
  Filenames are `console-YYYY-MM-DD-HH.MM.SS-<GUID>.log`; newest timestamp =
  most recent session. Confirm the timestamp matches when the user was playing;
  a capture the user pasted can predate the crash they are describing.
- [ ] **If the game hard-crashed with no Lua error in the log,** the matching
  crash dump is at `%APPDATA%\Fatshark\Vermintide 2\crash_dumps\` - the file
  name carries the same GUID as the log. Read its callstack and locals.
- [ ] Note the crash GUID; you will cite it in the Issue and any memory entry.

---

## STEP 2 - VERIFY WHAT WAS RUNNING (before ANY code reading)

This step is non-negotiable and comes before opening a single mod file. A large
fraction of "still broken" reports are the user running a build that predates
the fix.

- [ ] **Confirm the loaded version of each suspect mod** via its version echo
  line. Pattern: `[<id>:LOAD] vX.Y.Z` or `<name> v%s loaded`. Diagnostics use
  engine `printf`, so this line is present even when mod-logging is off. If the
  echoed version is older than the current source `MOD_VERSION`, the user ran a
  stale build - go straight to STEP 7, ship the current build, and ask them to
  re-test BEFORE diagnosing anything. Do not diagnose against source the user
  was not running.
- [ ] **Determine which mods were ACTIVE**, not merely subscribed:
  - `Init VMF mod '<name>'` lines = mods that actually initialized this session.
  - `[ModManager] mods[N] = (id=..., name="...", enabled="true", ...)` = the
    subscribed list with the enabled flag.
  - **Rule:** a mod is active only if it has an `Init VMF mod` line AND
    `enabled="true"`. Do NOT infer active mods from the subscribed `name=`
    field alone - that list includes disabled subscriptions. (Burned once by
    calling a stable-but-disabled sub "double-loaded".)
- [ ] **Multiplayer reports: check every peer's build.** A host/client symptom
  is often one peer on a stale bundle. If you only have one peer's log, ask for
  the other's before assuming a code bug. Every peer needs the patched build
  (see the WHAT-THE-USER-SAYS table).

---

## STEP 3 - PATTERN-MATCH

- [ ] **Open `docs/BUG_CLASSES.md` and match the symptom against the pattern
  column BEFORE any deep dive.** Most reports are repeats of a class already
  shipped, debugged, and fixed elsewhere in the monorepo.
- [ ] **On a match:** jump to that class's known-fix template and go to STEP 6.
  The fix shape is already established; you are not re-deriving it.
- [ ] **On no match:** this is a novel bug. Proceed to STEP 4.

The catalog is the highest-ROI read because named classes carry their own fix
template and postmortem citation. Always check before deep-diving. If the class
is missing after you solve it, you add it in STEP 9.

---

## STEP 4 - SCOPE

- [ ] **If the symptom could come from more than one installed mod, request a
  disable-bisection from the user FIRST** (disable half the suspects, retest,
  narrow), OR reason from the log's `Init VMF mod` list to rule mods out. Do
  NOT tunnel on one suspect and build fixes on a hypothesis - a session burned
  three cim builds chasing a bot-loadout bug that turned out to be a one-line
  drop in cosmetics_tweaker, which a bisection found in one step.
- [ ] **When several of your own mods could touch the affected vanilla
  feature,** the bisection is mandatory, not optional. Your prior on "my mod
  broke it" is not evidence of which one.
- [ ] Once scoped to a single mod, everything below operates on that mod's DEV
  directory (for split mods) or its single-stream directory.

---

## STEP 5 - DIAGNOSE (novel bugs only)

- [ ] **Diagnostics use engine `printf`, never `mod:info` / `mod:echo`.** The
  user runs with mod-logging OFF, so `mod:info` output is invisible in their
  sessions. A `printf` line reaches the console log regardless.
- [ ] **Grep the decompiled source for any engine mechanic and cite it.** The
  vanilla source is at `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`.
  Before writing any field name, line number, or mechanic claim: grep for the
  exact term and cite `file:line`. If you cannot find it, write `[unverified]`
  and describe the behavior in plain English - never confabulate an internal.
- [ ] **Distinguish Lua errors from C-level fatals.** Lua errors are
  pcall-able and land as `<<crashify-exception>>` blocks with a Lua callstack.
  C-level fatals BYPASS pcall entirely and must be PRE-FILTERED, not caught.
  Known C-fatal triggers:
  - `Unit.node(unit, name)` on a missing/unready node -> use `Unit.has_node`
    first (skeleton-readiness fatal on husk hot-join / revive).
  - `create_screen_gui` handed an unloaded material ("Gui material not found")
    -> pre-filter the material list, do not xpcall it.
  - `Managers.package:load` on a unit PATH or a non-resident 3rd-party package
    -> `Resource '#ID[hash]' not found`, fires ASYNC. Needs a real `.package`
    name; only `load()` when `has_loaded()`.
- [ ] **Read the source of the suspected hook / feature** (do not trust stale
  audit line numbers - empirical-first, `PROJECT_STANDARDS.md` sec. 8.1).
- [ ] **Read the vanilla function being hooked.** Half of novel bugs are guards
  that disagree with vanilla's actual contract (`PROJECT_STANDARDS.md` sec. 4.2
  "guard != bail"). An early `return` removes vanilla's own mutation.
- [ ] **If answering one question needs more than three files, dispatch a
  subagent** (`PROJECT_STANDARDS.md` sec. 8.2) rather than burning context inline.

### Log signature -> diagnosis

| Log signature | Likely cause | Next move |
|---|---|---|
| `[wt:safe_hook] <Class>.<method> raised: ...` | wt's pcall-isolated hook caught a consumer raise. The mod did not crash; a hook body failed. | Follow the captured callstack. `VMF_RECIPES.md` sec. 2b. |
| `[<mod_id>:trace] ... n_returned=M` where M differs from expected | Multi-return collapse or nil-hole truncation. | Apply `VMF_RECIPES.md` sec. 2 / sec. 2a (`select("#", ...)` + explicit `j`). |
| `[BR:fp] MISMATCH host=<hash> client=<hash>` | Big Rebalance settings divergence between host and client. | Reconcile sub-toggles; the shared registration master gate must match per peer. See bt's CHANGELOG. |
| `<<crashify-exception>>` block | Lua error reached the engine crash reporter. | Read the callstack + locals (locals show the fault-time state). Grep CHANGELOGs + memory for the literal signature first. |
| `<<crashify-property>>Mod:<id>:<name> = true` | Loaded-mod inventory at crash time - context, not cause. | Confirm which mods were active, then move on. |
| `Attempting to rehook active hook` | Duplicate `mod:hook` / `mod:hook_safe` on the same `(Class, method)`; the second silently dropped. | Consolidate into one hook body. See STEP 6 pre-flight + `VMF_RECIPES.md` sec. 1. |
| `[<mod_id>] enabled ...` missing entirely | The mod did not load on that peer. | Confirm subscribed + enabled in VMF; check vt2-mod-updater sync for friends. |
| Game crashed, nothing relevant in log | Engine crash bypassing Lua logging. | Read the crash dump at `crash_dumps\<GUID>.dmp`. |
| A bot abandons a downed teammate; `[gt_bot:139] ... follow downed=false` at the moment it happens | Follow-scoped bot diagnostic reads `follow_unit` AFTER the follow-set already dropped the disabled player - structurally blind to the down. `BUG_CLASSES.md` class 25. | Don't trust the follow-scoped `[gt_bot:139]`/`[139:bot_tp]` lines. Enable the Bot Teleport Lab (`gt_btlab_enabled`) and read the side-scoped probes: `[gt:btlab:d1]` (teleport detail), `[gt:btlab:d2]` (split follow assignment), `[gt:btlab:d3]` (per-human distances), `[gt:btlab:breach]` (radius breach). |

---

## STEP 6 - FIX

- [ ] **Smallest change that fixes the root cause,** in the mod's DEV directory
  (split mods: `ct_dev` / `cim_dev` / `gt_dev` / `gui_tweaker_dev` /
  `verminious_dreams_lighting_dev`) or its single-stream directory. Never edit
  the stable directory for in-flight work. One focused change per item; do not
  batch unrelated fixes into one patch.
- [ ] **Hook pre-flight (MANDATORY before writing any `mod:hook` /
  `mod:hook_safe`).** Grep the target file for `("ClassName"` AND
  `<ClassNameSymbol>,` to find every existing hook on that class. If ANY hook
  already exists on `(ClassName, method)`, do NOT add a second - VMF silently
  drops it. Merge your logic into the existing hook body and add a
  `_<mod>_consolidated_<method>_hook` marker comment. This has burned the repo
  at least five times.
- [ ] **Capture every vanilla return value** before transforming. `return
  wrapper(func(self, ...))` collapses multi-returns to one and silently drops
  the rest. Assign all returns to locals, transform the one you need, return
  them all.
- [ ] **Name every vanilla parameter, including trailing `skip_sync` /
  `is_server`.** Dropping the sync-control param from a hooked networked
  function causes the RPC receiver to re-broadcast and creates a host<->client
  feedback loop. Capture `...` and splat it back if you do not need to name each.
- [ ] **Guard, do not bail.** A blanket early `return` removes vanilla's own
  side effects. Confirm vanilla's contract before short-circuiting it.
- [ ] **Add an apply-site log line** for every mutation / hook install:
  `printf("[<feature>] applied: <numbers / names>")`. Concrete evidence, not
  "done".
- [ ] **Put the probe and the regression check in their tier homes**
  (`PROJECT_STANDARDS.md` §2.2b). A per-issue diagnostic probe goes in the mod's
  `_<ns>_diagnostics.lua` or a per-cluster `_<ns>_diag_<topic>.lua` (engine
  `printf`, prefix `[<ns>:<issue>]`, armed while the issue is open, retired on
  close per #500) - NOT a standalone probe file at the mod's script root. The
  STEP 9 `_rt_register` regression check registers into the mod's
  `/<mod>_regression_test` suite (tier b). New STATIC detection goes in a
  `qa/*.ps1` gate (tier a), never as a probe.

---

## STEP 7 - SHIP

Shipping is how the user tests. Steam re-syncs a subscribed Workshop item over
any local deploy, so a `-dev` build only reaches the user's game after an
UPLOAD - a local deploy alone is silently clobbered.
This checklist applies the owner doctrine in `PROJECT_STANDARDS.md` section
6.6; if this secondary checklist ever differs, stop and correct it before
shipping. Agent publication is headless and opens no interactive window.

- [ ] **Bump `MOD_VERSION` (patch segment)** in
  `<mod>/scripts/mods/<mod>/<mod>.lua`. Three-segment semver plus track suffix
  (`0.12.68-dev`); never a 4th segment. The echoed version confirms the build
  in the next log.
- [ ] **Add a CHANGELOG entry** for the new version (symptom, root cause, fix,
  and the in-game verify check from STEP 8).
- [ ] **Generate the reviewed artifact without publishing:**

  ```powershell
  .\tools\ship\claim.ps1 -Mod <mod>
  .\tools\ship\ship.ps1 -Mod <mod> -BuildOnly
  ```

- [ ] **Commit source and generated bundle together, then review before
  publication.** Stage the exact mod source, `itemV2.cfg`, CHANGELOG, and root
  bundle; commit; push; open the PR; pass hosted `qa-gate`; and merge.
- [ ] **Publish only from a clean checkout at exact live default-branch HEAD:**

  ```powershell
  .\tools\ship\ship.ps1 -Mod <mod>
  ```

  The publisher independently re-queries default HEAD, the exact merged PR,
  and successful hosted `qa-gate`. VMBLauncher receives a capability valid for
  at most five minutes and independently rechecks the clean root, claim owner,
  mod/version, cfg hash, and every bundle hash immediately before `ugc_tool`.
  Direct launcher `upload`/`all`, GUI publication, caller-authored publisher
  JSON, `-SkipGitHub`, and claim-only publication are not supported.
  Add `-AllowPublic` whenever `itemV2.cfg` visibility is public. Add
  `-NoRemote` only to skip an otherwise-enabled remote target and identify it.
- [ ] **APPROVAL RULE:**
  - **`-dev` / `-alpha` / `-beta`-versioned mods: ship with NO asking, every
    update.** This is how the user tests. Includes single-stream public mods
    like wt / cosmetics_tweaker / crt whose `MOD_VERSION` carries `-dev`.
  - **Clean-versioned STABLE releases (no pre-release suffix, regardless of the
    stable item's current visibility): DO NOT upload without a fresh, per-build ship
    signal from the user naming the version.** "Ship it" earlier does not carry
    forward. Default for these is `build` + `deploy`, never `upload`. Treat a
    stable public upload like `git push --force`.
- [ ] **Verify the upload landed.** Confirm `Uploaded new content` for this item
  in `C:\Program Files (x86)\Steam\logs\workshop_log.txt`. `ugc_tool` prints
  "Upload finished" even when nothing transferred.
- [ ] **Deploy-verify hash mismatch after a confirmed upload:** re-run
  `VMBLauncher deploy <mod> --no-remote` once, then continue. Do not loop on it.
- [ ] **Add the status label to the Issue NOW (same pass, do NOT wait for STEP
  9).** Shipping a fix or diagnostic is what flips an issue into "ready to test",
  and that signal is a GitHub label, not just a comment. `PROJECT_STANDARDS.md`
  §11 requires it "in the same pass as the CHANGELOG entry":
  - **PREREQ:** post the newest exact `## CURRENT LIVE TEST` card FIRST. It
    names the semantic version and either `[mod:LOAD]` or a clearly labeled
    exact versioned banner such as `[WOC] v0.1.42-dev loaded`, `Topology: Solo` or
    `Co-op`, numbered localized/player-facing steps, and `Expected:` result.
    Issue-body text and older method headings do not qualify.
  - `gh issue edit <N> --remove-label not-started --add-label verify-fix` only
    when a **complete deployed fix** is runnable in-game now.
  - `gh issue edit <N> --remove-label not-started --add-label diagnostics-armed`
    only when a bounded deployed in-game diagnostic is runnable now.
  - Test useful solo paths first. Add `coop-required` only after the current
    co-op card records `Solo status: Passed/Completed/Exhausted`. Both fix and
    diagnostic co-op cards retain their ordinary lifecycle plus this qualifier.
  - Blocked, partial, tooling, docs, and otherwise unready work uses
    `not-started`, without `coop-required`. Verify tooling/docs autonomously and
    close directly; never put them in the live in-game queue.
  - Remove every competing lifecycle in the same `gh issue edit`; `Fixed` and
    `verify-fix-coop` are invalid while open.
  - Never more than one status label at a time, never invent a new one. Every open
    issue carries exactly one lifecycle label -
    a shipped-but-unlabeled fix is invisible to the user's backlog view. Label every
    issue the ship addressed (here: the primary Issue AND any it corroborates/fixes
    together).
  - If the fix touched player-facing localization, run the localization leak gate
    and keep lifecycle metadata exclusively on the GitHub issue. Localization
    values never carry GitHub lifecycle labels (`LOCALIZATION_STANDARD.md` §13).
- [ ] **Refresh by tester role.** The author on PC-A tests the hash-verified
  local deploy without restarting Steam. Volunteer testers unsubscribe and
  resubscribe through the designated dev collection, then confirm the loaded
  version in the newest console log. Suggest a Steam restart only after source,
  bundle, and loaded-version evidence are all current and the problem persists
  (`PROJECT_STANDARDS.md` §14a); never use restart as the first explanation.

---

## STEP 8 - VERIFY

- [ ] **Provide ONE current live-test card.** Name the build/banner, topology,
  player-visible steps, and expected in-game result.
- [ ] **NEVER claim a runtime issue "fixed" until the user confirms in-game.**
  Compile success and structural review are not runtime verification. Say
  "shipped v0.12.152-dev, please check X" - not "fixed". Repository-only work
  closes after its documented autonomous verification passes without entering
  the live-test queue.
- [ ] **If it is still broken, believe them.** Return to STEP 2 with the NEW
  log (they must be on the version you just shipped - re-verify the echoed
  version first). Do not re-defend the previous diagnosis.
- [ ] **When verification passes:** record the human or autonomous evidence,
  keep the existing verify lifecycle while completing the **post-fix pass**:
  harden the code path (guard the CLASS, not just the instance), write/extend the
  BUG_CLASSES.md entry and the owning mod doc, and add a regression test
  (`_rt_register` / QA check) locking the invariant. Then close when that pass is
  done or explicitly judged not applicable (say so in a comment); do not move an
  open issue to the retired `Fixed` label. Taxonomy: `PROJECT_STANDARDS.md` §11.

---

## STEP 9 - CLOSE (after human or autonomous verification)

- [ ] **`_rt_register` regression marker** where the repo pattern applies. Add a
  runtime assertion that would FAIL if the bug returned, registered into the
  mod's `_RT_CHECKS` scaffold, surfaced via the mod's `/verify_<feature>` or
  `/<mod>_regression_test` command. Belt-and-suspenders: even a lint-covered fix
  gets the runtime check.
- [ ] **GitHub Issue.** Close the matching Issue with a version-stamped comment
  linking the commit + CHANGELOG entry, or file one (labeled `crash` /
  `regression` / `bug` / `blocked` / `deferred`) if the fix was deferred or
  exposed follow-up work. Search before opening to avoid dupes.
- [ ] **Novel bug class -> catalog it.** If `docs/BUG_CLASSES.md` had no match in
  STEP 3, append a new entry (symptom pattern, root cause, fix template, mods
  affected, postmortem reference).
- [ ] **Docs + memory in the SAME response as the fix,** not batched later. If a
  recipe / standard / per-mod doc was missing or stale, update it now. If the
  bug exposed a recurring cross-session class, drop a `feedback_*.md` /
  `reference_*.md` in the memory store and add a one-line index entry to
  `MEMORY.md`.
- [ ] **POSTMORTEMS.md entry** in the affected mod (symptom, root cause, fix,
  why it took as long as it did, future-prevention hook) if the bug was
  non-trivial or recurring.

---

## WHAT THE USER SAYS -> WHAT YOU DO

| Report shape | First move |
|---|---|
| **Crash to desktop with an error dialog** | Get the GUID from the dialog, read that `console-*.log` + matching `crash_dumps\<GUID>.dmp`. Read the callstack + locals. Classify Lua error vs C-fatal (STEP 5). Grep CHANGELOGs + memory for the literal signature before writing a fix. |
| **Silent wrong behavior** (no crash, "it does X instead of Y") | Confirm the running build (STEP 2). Add a `printf` apply-site trace to see whether the feature's hook even fires and with what values. Compare against vanilla's contract in the decompiled source. |
| **Menu text / UI issue** (wrong label, missing widget, blank panel) | No em dashes in menu strings (repo rule). Check loc-key registration timing and widget `setting_id` uniqueness. Blank custom view often = a missing/raw material or an options-widget reused outside its atlas. Verify in-game, never off a build alone. |
| **Multiplayer-only issue** (fine solo, breaks with 2+ players) | Every peer needs the patched build - confirm each peer's echoed version. Suspect a dropped `skip_sync` param, an RPC feedback loop, or gated-registration divergence (host vs client `settings_fp`). |
| **"It worked before <version>"** | Diff the mod's CHANGELOG from the named version to now; the regression is almost always in one of those entries. Read those diffs before touching anything else. |
| **Two or more problems in one message** | STEP 0: mirror them back as a numbered list and track each separately through the pipeline. Never merge. |

---

## Appendix A - Quick reference: where to look first

| Symptom (one-liner) | Likely mod | First move | Doc section |
|---|---|---|---|
| Crash on join (CW lobby / Workshop friend) | shared BR registration (wt / ct / et) | Grep log for `[BR:fp]`, compare host vs client `settings_fp` | `PROJECT_STANDARDS.md` sec. 9.3 conditional-registration |
| Missing 3P attack anim, body holds previous weapon's idle | wt (cross-char port) or cwv (variant) | Grep log around weapon wield; check `anim_event_3p` remap | `weapon_tweaker/DEVELOPMENT.md`; `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` |
| Missing helmet / hat on husk (other player's view) | cosmetics_tweaker (LA bridge) | Grep log for `[cosmetics:husk-hat-create]`; check `Unit.has_node` guard | `cosmetics_tweaker/LA_SYNC_MODEL.md` sec. 6 |
| `<<crashify-exception>>` with `ItemMasterList[key]` in stack | cosmetics_tweaker / wt / cwv (unknown key) | Read crash-dump locals at the indexed line; use `rawget` | `DEVELOPMENT.md` "ItemMasterList crashify on unknown keys" |
| Inventory preview shows wrong / missing weapon | cosmetics_tweaker / wt (preview hook on wrong class) | Confirm hook targets `MenuWorldPreviewer`, not `HeroPreviewer` | `CLAUDE.md` "HOOK THE DERIVED CLASS, NEVER THE BASE" |
| Hook installed but never fires | any mod | Grep for `local <name> = <Class>.<method>` upvalue captures + duplicate `mod:hook` on same pair | `VMF_RECIPES.md` sec. 1; `CLAUDE.md` "Hooks that silently no-op" |
| Multi-return values silently drop to nil | any mod with hook wrappers | Search hook body for `return wrapper(func(...))` or bare `unpack(t)` | `VMF_RECIPES.md` sec. 2 / sec. 2a |
| Mutator / event preset toggle doesn't take effect | event_tweaker | Run `/verify_<feature>`; check the `DLC_BY_MUTATOR` gate | `event_tweaker/DEVELOPMENT.md`; `CLAUDE.md` "DLC Ownership Gate" |
| Buff / damage / explosion crash on second peer joining | ct / wt / et (gated registration) | Confirm shared registration master toggle; check sorted-order registration | `PROJECT_STANDARDS.md` sec. 9.3; `DEVELOPMENT.md` "Gated registration diverges across peers" |
| Crafting screen shows item player doesn't own DLC for | cim / cosmetics_tweaker / crt / event_tweaker | Grep for `_*_requires_unowned_dlc`; confirm the filter fires before enumeration | `CLAUDE.md` "DLC Ownership Gate" |
| Settings differ between "the same setup" | any mod | Compare `settings_fp=<hash>` across peer logs | `PROJECT_STANDARDS.md` sec. 3.6 "Applied marker line" |
| CWV weapon reverts after leaving Chaos Wastes | gut loadout persistence | Compare `[gut:persist]` ids before/after `old_loadout: deus new_loadout: nil`; temporary Deus ids must report as skipped foreign slot reads | `docs/engine/11`; `BUG_CLASSES.md` class 73 |
| Game crashed with no `<<crashify-exception>>` | engine-level (Stingray) | Read `crash_dumps\<GUID>.dmp` | `PROJECT_STANDARDS.md` sec. 9.7 grep-first |

---

## Appendix B - Anti-patterns the runbook prevents

The behaviors below have wasted prior sessions; the steps above are structured
to short-circuit them.

- **Diagnosing against a build the user was not running.** STEP 2 exists to
  catch this. Ship current + re-test before reading code.
- **Speculative defense stacking** (`PROJECT_STANDARDS.md` sec. 9.1). Do not add a
  guard without the sec. 8.6 four-question gate. Find the real root cause.
- **Guard != bail** (`PROJECT_STANDARDS.md` sec. 4.2). An early `return` removes
  vanilla's mutation. Confirm vanilla's contract first.
- **Skipping the grep-first protocol** (`PROJECT_STANDARDS.md` sec. 9.7). Most
  surprising crashes are already documented; grep for the literal signature.
- **Inventing internals** (global CLAUDE.md). No field names, line numbers, or
  mechanic claims that were not grepped in source. Write `[unverified]` instead.
- **Claiming "fixed" off a build.** Only the user's in-game confirmation closes
  an item (STEP 8).
- **Tunneling one suspect without a bisection** (STEP 4).
- **Hot-reload assumption.** Ctrl+Shift+R is unsafe for wt / cosmetics_tweaker
  and risky in general - full game restart after redeploy.
- **Auto-launching VT2** (global CLAUDE.md). Build, deploy, ship, THEN ask the
  user before launching.

---

## Appendix C - When this runbook is wrong

This runbook is a living checklist of what already works in practice. If a step
is counterproductive on a real bug, propose the update in the same commit as the
fix. Do not silently ignore a step, and do not add steps that have not actually
paid off in a real session. Cross-ref: `PROJECT_STANDARDS.md` sec. 13 "When this
doc is wrong".
