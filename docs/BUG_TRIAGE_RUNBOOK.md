# BUG_TRIAGE_RUNBOOK.md

**Audience:** any Claude session that has just received a user bug report.
**Goal:** orient in 60 seconds, identify the bug class, and reach a confirmed
fix without re-learning the workflow from scratch.

**Read order on a fresh bug report:** this file -> phase 1 commands ->
`docs/BUG_CLASSES.md` (if present) -> mod source.

> **Binding docs cross-referenced from this runbook** (cite by section number
> when applying a rule):
> - `PROJECT_STANDARDS.md` (operational rulebook)
> - `CLAUDE.md` (technical reference + Build Commands)
> - `VMF_RECIPES.md` (Vermintide Mod Framework gotchas)
> - `DEVELOPMENT.md` (engine quirks, known errors)
> - per-mod `CHANGELOG.md` + `REGRESSION_CHECKLIST.md` + `POSTMORTEMS.md`

---

## Phase 1 — Receive (within 60 seconds)

What the user typically provides:
- Log file path (usually `%APPDATA%\Fatshark\Vermintide 2\console_logs\console_log-<GUID>.log`).
- One-line symptom description.
- Optional: screenshot, crash dump GUID, mod version they think shipped.

**First three reads, in this order:**

- [ ] **1. The log file.** Find every `[<mod_id>] enabled v<version> settings_fp=<hash>` line — one per loaded mod (per `PROJECT_STANDARDS.md` § 3.6 "Applied marker line"). Capture which mod versions + settings hashes were running. Mismatched fingerprints between host and client are themselves a bug class (see Phase 3).
- [ ] **2. Recent shipped work.** Run `git log --oneline -10` from the repo root. If the bug appeared today, today's commits are the suspect list. Also run `git status` to know if there are uncommitted edits sitting in the tree.
- [ ] **3. Known issues.** Run `gh issue list --repo Ensrick/vermintide-2-tweaker --state open` to check whether the bug is already filed. If yes, append the new evidence to that Issue instead of opening a duplicate.

Do not start coding before all three reads complete. The total budget for
phase 1 is one minute.

---

## Phase 2 — Identify the bug class

- [ ] Open `docs/BUG_CLASSES.md` (if it exists yet — this catalog is built
  incrementally; if missing, skip to Phase 3 and create the entry in
  Phase 5).
- [ ] Match the symptom one-liner against the catalog's pattern column.
- [ ] If a match: jump to the catalog's "known fix template" and apply.
  Skip ahead to Phase 4 — the fix shape is already established.
- [ ] If no match: this is a novel bug. Proceed to Phase 3.

The catalog is the highest-ROI first read because most user-reported bugs
recur in patterns we have already named. Always check before deep-diving.

---

## Phase 3 — Deep dive (only for novel bugs)

Grep the log for the affected mod's prefix. The repo's logging convention
(`PROJECT_STANDARDS.md` § 3.1, § 3.6) puts every meaningful line behind a
`[<mod_id>:<feature>]` or `[<mod_id>:dbg]` tag.

- [ ] `[<mod_id>:dbg]` lines -> confirmation events from the mod's
  `_dbg` helper (file-only). Pair them with `[<mod_id>:dbg]` in chat (via
  `_dbg_alert`) if chat is part of the report.
- [ ] `[<mod_id>]` lines -> permanent operational logs (not gated on
  `enable_debug_logging`). Includes the applied marker, hook-install
  confirmations, RPC sends.
- [ ] `_dbg_alert` lines (`PROJECT_STANDARDS.md` § 3.6 two-channel
  discipline) -> the mod itself flagged an unexpected condition. Investigate
  these first; they are pre-filtered to be interesting.

### Specific log patterns -> diagnosis

| Log signature | Likely cause | Next move |
|---|---|---|
| `[wt:safe_hook] <Class>.<method> raised: ...` | wt's pcall-isolated hook caught a consumer raise. The mod itself did not crash, but a hook body failed. | Follow the captured callstack. See `VMF_RECIPES.md` § 2b "Pcall-isolated hooks". |
| `[<mod_id>:trace] event=enter ... n_args=N` / `event=exit ... n_returned=M` where `M` differs from expected | Multi-return collapse, nil-hole truncation, or hook chain divergence. | Apply `VMF_RECIPES.md` § 2 / § 2a recipe (`select("#", ...)` + explicit `j`). |
| `[BR:fp] MISMATCH host=<hash> client=<hash>` | Big Rebalance settings divergence between host and client (et / bt / wt / ct cross-peer). | Reconcile sub-toggles; bt master gate + sub-toggle must match per peer. See bt's CHANGELOG + `CLAUDE.md` Mod Directory entry for bt. |
| `<<crashify-exception>>` block in `.log` | Hard runtime error reaching the engine crash reporter. | Read the surrounding callstack + locals. Locals are gold — they show the state the function held at fault time. Cross-ref the crash GUID against memory + CHANGELOGs (`PROJECT_STANDARDS.md` § 9.7 "Skipping the bug-search-first protocol"). |
| `<<crashify-property>>Mod:<id>:<name> = true<</crashify-property>>` | Just the loaded-mod inventory at crash time — context, not the cause. | Use to confirm which mods were active, then move on. |
| Mismatched `settings_fp` between two peers' logs | Host and client are running different config or different MOD_VERSION. | First confirm the version skew. If versions match but fp differs, walk the widget list to find the divergent setting. |
| `[<mod_id>] enabled v<X> ...` missing entirely | The mod did not load at all on that peer. | Confirm the mod is subscribed + enabled in VMF (`mods/<mod>.mod`, VMF Mod Options). Check `vt2-mod-updater` sync for friends. |
| Nothing relevant in log, but the game crashed | Hard engine crash that bypassed Lua logging. | Read the matching crash dump at `%APPDATA%\Fatshark\Vermintide 2\crash_dumps\` — file name matches the GUID in the log file. |

When nothing in the log explains the symptom, fall back to:

- [ ] Read the source of the suspected hook / feature (do not trust stale
  audit line numbers — `PROJECT_STANDARDS.md` § 8.1 "Empirical-first").
- [ ] Read the vanilla VT2 source (`C:\Users\danjo\source\repos\Vermintide-2-Source-Code\`) for the function being hooked. Half of novel bugs are guards that disagree with vanilla's actual contract (`PROJECT_STANDARDS.md` § 4.2 "guard != bail").
- [ ] Grep `CHANGELOG.md` + memory for the literal crash signature before writing any fix (`PROJECT_STANDARDS.md` § 9.7).
- [ ] If reading more than three files to answer one question, dispatch a subagent (`PROJECT_STANDARDS.md` § 8.2 "Subagent-first for context-heavy tasks").

---

## Phase 4 — Fix (with the right pattern)

- [ ] **One Issue per discovered bug.** `gh issue create --repo Ensrick/vermintide-2-tweaker ...` with a label from the §11 set (`crash`, `regression`, `audit`, `bug`, `blocked`, `deferred`). Search before opening to avoid dupes.
- [ ] **Read vanilla first.** If the fix is a hook, grep `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\` for the actual function body and any sibling tables vanilla reads at call time. Wrong-table gates are a known repeat offender (`PROJECT_STANDARDS.md` § 5.1a "Verify the right table").
- [ ] **Fix in the affected mod's source.** One focused change per session (`PROJECT_STANDARDS.md` § 8.3). Don't batch unrelated fixes into the same patch.
- [ ] **Apply-site log line.** Every mutation / hook install must emit a concrete-evidence log line: `[<feature>] applied: <numbers / names>` (`PROJECT_STANDARDS.md` § 5.1a step 1).
- [ ] **`_rt_register` regression check.** Add a runtime assertion that would FAIL if the bug returned, registered into the mod's `_RT_CHECKS` scaffold (`PROJECT_STANDARDS.md` § 15 "Every bug requires a test"). Belt-and-suspenders: even a lint-covered fix needs the runtime check.
- [ ] **`/verify_<feature>` chat command.** Per-item rows showing `name | toggle_state | live_state | PASS/FAIL`. Should work from the keep where possible (`PROJECT_STANDARDS.md` § 5.1a step 2).
- [ ] **Bump MOD_VERSION patch** (`PROJECT_STANDARDS.md` § 6.2). Update `itemV2.cfg` title suffix is handled automatically by `VMBLauncher.exe upload`.
- [ ] **CHANGELOG entry** for the new version using the § 6.4 format. Body MUST include the `/verify_<feature>` command name (`PROJECT_STANDARDS.md` § 5.1a step 5).
- [ ] **`VMBLauncher.exe build <mod>`** to verify the bundle compiles (`CLAUDE.md` Build Commands).
- [ ] **`VMBLauncher.exe all <mod>`** for build + local deploy + PC-B deploy + Workshop upload (`CLAUDE.md` Build Commands).
- [ ] **`.\tools\publish-release\publish-release.ps1`** to refresh the GitHub release the `vt2-mod-updater` consumers pull from (`CLAUDE.md` § "Required: GitHub release after every Workshop upload"). Non-optional, especially for friends-only mods.
- [ ] **Verify Workshop file size** in Steam after upload — `ugc_tool` prints "Upload finished" even when transfer fails (`CLAUDE.md` "Important Constraints").
- [ ] **Close the Issue** with a version-stamped comment linking the commit + CHANGELOG entry.

If any step is genuinely impractical for this specific bug (e.g. nothing
observable from the keep so `/verify_<feature>` can't work), say so
explicitly in the CHANGELOG entry. The default is full coverage.

---

## Phase 5 — Hardening (after the fix is verified)

- [ ] **Novel bug class -> catalog it.** If `docs/BUG_CLASSES.md` had no matching entry in Phase 2, append a new one (symptom pattern, root cause, fix template, mods affected, postmortem reference).
- [ ] **Static check possible? File an Issue.** If a `qa/check_*.ps1` pattern could have caught this at lint time (like `qa/check_unpack_safety.ps1`), open an Issue and implement when bandwidth allows. Cross-reference the check name in `qa/CHECKS.md`.
- [ ] **Documentation gap?** If the bug surfaced because a recipe / standard / per-mod CLAUDE.md was missing or stale, update the doc in the same session — `PROJECT_STANDARDS.md` § 7.7 "Doc maintenance trigger" (update in place at the moment of change).
- [ ] **POSTMORTEMS.md entry.** Per `PROJECT_STANDARDS.md` § 7.3 Bucket B, write a single immutable entry in the affected mod's `POSTMORTEMS.md` summarizing symptom, root cause, fix, "why it took so long" if applicable, and future-prevention hooks (lint, test, memory).
- [ ] **Memory entry if cross-session.** If the bug exposed a recurring class likely to bite again, drop a `feedback_*.md` or `reference_*.md` in `C:\Users\danjo\.claude\projects\C--Users-danjo-source-repos\memory\` and add an index line to `MEMORY.md` (`PROJECT_STANDARDS.md` § 12).

---

## Appendix A — Quick reference: where to look first

| Symptom (one-liner) | Likely mod | First command to run | Doc section |
|---|---|---|---|
| Crash on join (CW lobby / Workshop friend) | bt / wt / ct (BR registration) | Grep log for `[BR:fp]`, compare host vs client `settings_fp` | `CLAUDE.md` bt entry; `PROJECT_STANDARDS.md` § 9.3 conditional-registration |
| Missing 3P attack anim, body holds previous weapon's idle | wt (cross-character port) or cwv (variant) | Grep log for `[wt:dbg]` / `[cwv:dbg]` around weapon wield | `weapon_tweaker/DEVELOPMENT.md` § "1P animations are universal"; `PROJECT_STANDARDS.md` § 9.5; `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` |
| Missing helmet / hat on husk (other player's view) | cosmetics_tweaker (LA bridge) | Grep log for `[cosmetics:husk-hat-create]` | `cosmetics_tweaker/LA_SYNC_MODEL.md` § 6 |
| `<<crashify-exception>>` with `ItemMasterList[key]` in stack | cosmetics_tweaker / wt / cwv (unknown key) | Read crash dump locals at the indexed line | `DEVELOPMENT.md` § "ItemMasterList crashify on unknown keys"; use `rawget` |
| Inventory preview shows wrong / missing weapon | cosmetics_tweaker / wt (preview hook on wrong class) | Grep source for `HeroPreviewer` hooks; must be `MenuWorldPreviewer` | `CLAUDE.md` § "HOOK THE DERIVED CLASS, NEVER THE BASE" |
| Hook installed but never fires | any mod | Grep source for `local <name> = <Class>.<method>` upvalue captures + duplicate `mod:hook_safe` on same pair | `VMF_RECIPES.md` § 1 (hook_safe no-chain); `CLAUDE.md` § "Hooks that silently no-op" |
| Multi-return values silently drop to nil | any mod with hook wrappers | Search hook body for `return wrapper(func(...))` or bare `unpack(t)` | `VMF_RECIPES.md` § 2 / § 2a |
| Mutator / event preset toggle doesn't take effect | event_tweaker | Run `/verify_<feature>` if implemented; check `DLC_BY_MUTATOR` gate | `event_tweaker/DEVELOPMENT.md`; `CLAUDE.md` § "DLC Ownership Gate" |
| Buff / damage profile / explosion crash on second peer joining | bt / ct / wt / et (gated registration) | Confirm bt master toggle, check sorted-order registration | `PROJECT_STANDARDS.md` § 9.3; `DEVELOPMENT.md` § "Gated registration diverges across peers" |
| Crafting screen shows item player doesn't own DLC for | cim / cosmetics_tweaker / career_tweaker / event_tweaker | Grep for `_*_requires_unowned_dlc` helper; confirm filter fires before enumeration | `CLAUDE.md` § "DLC Ownership Gate" |
| Settings differ between sessions for "the same setup" | any mod | Compare `settings_fp=<hash>` in `[<mod_id>] enabled` lines across logs | `PROJECT_STANDARDS.md` § 3.6 "Applied marker line" |
| Game crashed with no `<<crashify-exception>>` in log | engine-level (Stingray) | Read crash dump at `%APPDATA%\Fatshark\Vermintide 2\crash_dumps\<GUID>.dmp` | `PROJECT_STANDARDS.md` § 9.7 grep-first |

---

## Appendix B — Anti-patterns the runbook explicitly prevents

The behaviors below have wasted prior sessions; the phases above are
structured to short-circuit them.

- **Speculative defense stacking** (`PROJECT_STANDARDS.md` § 9.1). Don't add a guard without answering the § 8.6 four-question gate. Revert speculative patches; find the real root cause.
- **Guard != bail** (`PROJECT_STANDARDS.md` § 4.2). An early `return` removes vanilla's mutation. Confirm vanilla's contract before bailing.
- **Skipping the grep-first protocol** (`PROJECT_STANDARDS.md` § 9.7). Most surprising crashes are documented; grep CHANGELOGs + memory for the literal signature first.
- **Inventing internals** (global CLAUDE.md "Don't invent internals"). Don't write field names, line numbers, or mechanic claims that haven't been grepped in source.
- **Hot-reload assumption** (`PROJECT_STANDARDS.md` § 9.4). Ctrl+Shift+R is broken for wt / cosmetics_tweaker and unsafe in general — full game restart after redeploy.
- **Auto-launching VT2** (global CLAUDE.md "Never auto-launch games"). Build, deploy, and then ask the user before launching.

---

## Appendix C — When this runbook is wrong

This runbook is a living checklist of what already works in practice. If a
phase or step is counterproductive on a real bug, propose the update in the
same PR as the fix. Don't silently ignore the rule, and don't add steps that
haven't actually paid off in a real session.

Cross-ref: `PROJECT_STANDARDS.md` § 13 "When this doc is wrong" — same policy.
