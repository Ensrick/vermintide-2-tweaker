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
  remote PC-B deploy. Don't bypass it. It now lives in its own repository
  (relocated ~2026-07-30); this repo resolves the binary through
  `tools/vmb-launcher-path.ps1` / `VT2_SHIP_VMB_LAUNCHER`.
- **Per-mod data + localization separation** is canonical VMF and well followed.
- **QA tooling in place** — policy-driven PowerShell gates, offline Lua 5.1
  tests, and GitHub Actions catch recurring bug classes that previously slipped
  through. See `qa/CHECKS.md` for the live inventory (§11a lists only a
  representative subset); do not freeze a check count in prose.

### What's still weak
- **File sizes exceed Claude's effective working memory.** 9 Lua files remain
  over the 2500-line hard limit (`chaos_wastes_tweaker.lua` at ~12800,
  `chaos_wastes_tweaker_dev.lua` at ~11300, `character_weapon_variants.lua` at
  ~10900, `cosmetics_tweaker.lua` at ~10200, plus five others; exact frozen
  counts live in `qa/baselines/file_sizes.json` — do not restate them here,
  they drift). Reading the
  worst offenders consumes well over ~80K tokens. The set is now frozen in
  `qa/baselines/file_sizes.json` (issue #429) so the gate blocks only on growth
  past a baselined count or a new file crossing the limit. Tracked under GitHub
  Issue #2.
- **Logging conventions partially adopted.** The §3.1 prefix convention is not
  universal across mods, but enforcement now exists: `qa/check_logging.ps1`
  (advisory, wired into `qa/run_all.ps1`) scans for chat-echo in NEVER contexts,
  per-frame `mod:info`/`mod:warning`, and level misuse, with an inline
  `-- allow-echo: <reason>` suppression path. Under §11b every warning it emits
  carries a one-week clock. Remaining work is the per-mod prefix sweep, not the
  missing checker.
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
  `.\qa\check_file_sizes.ps1` for the live list. The canonical metric is
  PowerShell `Get-Content | Measure-Object -Line` (non-empty logical lines;
  whitespace-only lines count). Files above the hard
  limit are frozen in `qa/baselines/file_sizes.json`; every current file
  between the target and hard limit has an independent exact ceiling in
  `qa/baselines/file_sizes_target.json`. A frozen file may shrink but may not
  grow, and a new file crossing either threshold blocks QA. Baseline refreshes
  are explicit reviewed operations; they are never an ordinary way to bless
  growth. Splits happen one coherent owner boundary at a time.

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

### 2.2a Full module-split conventions (the event_tweaker template, 2026-07-11)

When a mod is decomposed into single-responsibility modules (OOP_REFACTOR_PLAN
WS5), follow the template proven on event_tweaker v0.4.26-dev:

1. **Entry file = manifest only.** `<mod>.lua` keeps MOD_VERSION (the launcher
   parses it from THIS file), the load banner/echo lines, a `mod._<ns>` shared
   namespace table, and an ordered `mod:dofile` manifest with a comment stating
   why the order is load-bearing. All logic lives in modules.
2. **One dofile per module, from the manifest only.** `mod:dofile` is NOT a
   singleton — every call re-executes the file — so modules never dofile each
   other. Pick a unique module prefix (check other mods' prefixes first:
   `_et_` = enemy_tweaker, `_evt_` = event_tweaker, `_gt_`, `_ct_`, ...).
3. **Cross-module surface goes through `mod._<ns>`.** The owning module exports
   (`ET.x = x`); consumers localize at their top (`local x = ET.x`), which only
   works if the owner is EARLIER in the manifest. Established `mod._<field>`
   names (regression checks / docs cite them) survive as-is.
4. **Data shared with `_data.lua`/`_localization.lua` goes in require'd modules**
   (pure data, no `mod` access) — script-set fields are nil when those files
   evaluate (VMF loads localization → data → script).
5. **Issue guards get their own `_<ns>_guardNNN_<name>.lua`**, manifest-ordered
   before the module that applies them; each registers its own regression check;
   the guard call sites stay at the single injection/dispatch chokepoint.
6. **Regression checks register in the module that owns the guarded code**; the
   harness module exports `rt_register`. Check names and their registration
   order (= manifest order) are frozen surface — reordering the manifest
   reorders the in-game output.
7. **Per-frame hooks read file-locals only** — no namespace lookups, no require,
   zero new per-frame allocations.
8. **Split = pure structural.** Log/printf strings byte-identical, hook set
   identical (one hook per (Class, method) mod-wide), command names identical.
   Before shipping, run independent adversarial review over the diff hunting
   orphaned upvalues, load-order breaks, dropped duplicate hooks, bundle
   omissions, and guard drift; verify every new file landed in the bundle
   (murmur64-hash the resource paths against the bundle listing — a raw byte
   scan cannot see hashed entries).
   Custom weapon resources additionally follow
   [`docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](docs/CUSTOM_WEAPON_MODEL_PIPELINE.md):
   compile success is not residency, preview discovery, or ProfileSynchronizer
   wire safety, and all three require independent evidence.
9. **Docs in the same commit:** the mod's DEVELOPMENT.md gets a "Module
   contracts" section (per file: responsibility, public surface, manifest
   position) + a "Where new code goes" placement recipe, so the monolith does
   not regrow; REGRESSION_CHECKLIST.md detection pointers get the new file names.

### 2.2b Test and diagnostic tiers (issues #499 / #501, 2026-07-12)

Three distinct layers answer "does this still work". Each has ONE home; do not
mix them, and do not invent a fourth.

**Tier (a) - Repo QA gates (`qa/*`).** Static PowerShell checks, `luacheck`,
and engine-free Lua 5.1 unit tests, run by the pre-commit hook
(`qa/run_all.ps1 -Quick -SkipLua`) and CI
(`.github/workflows/qa.yml`). They read SOURCE, never the running game, so they
are the only tier that runs without VT2. Errors (exit >=2) block the commit;
warnings (exit 1) report but never block (`qa/CHECKS.md` "Gate semantics"). New
STATIC bug-class detection lands here: scaffold `qa/check_<name>.ps1`, wire it
into `run_all.ps1`, add a row to `qa/CHECKS.md`. Deterministic transformations
on ordinary Lua values may instead use `qa/lua/`; do not mock a general VMF or
Stingray runtime to force engine behavior into this tier.

Default tier-(a) orchestration is read-only. Quick and full `run_all.ps1`
invocations must leave the exact initial Git-visible state unchanged, including
tracked/index state and non-ignored untracked file contents when the developer
started dirty. A checker that intentionally writes must expose a named opt-in
mode; the current canonical example is `run_all.ps1 -FixStale`, which visibly
skips the purity guard because that flag authorizes documentation edits.

**Tier (b) - In-game regression harnesses.** A per-mod runtime self-check suite,
invoked from chat as `/<mod>_regression_test`. Each check is a closure
registered via `_rt_register("<name>", function() ... end)` that returns a
failure STRING if the invariant broke and nil if it held (a boolean first
return is a malformed check - §5.1d rule 3). Checks assert on
live engine state: hook installed, table shape intact, `NetworkLookup` entry
present, or the singleton-hook invariant via a source-pattern marker (a check
greps its own mod source for a required banner such as
`_<mod>_consolidated_<method>_hook`). This tier is the belt-and-suspenders
runtime counterpart to a tier-(a) gate: even a lint-covered fix earns a check
here (`docs/BUG_TRIAGE_RUNBOOK.md` STEP 9).

- TARGET home: a dedicated `_<ns>_regression.lua` module per mod that owns the
  `_rt_register` definition and the `/<mod>_regression_test` command, exporting
  `rt_register`; individual check registrations live in the module that owns the
  guarded code (per §2.2a rule 6) and call the exported `rt_register`.
- TARGET check name: `issueNNN_<slug>` when the check locks a specific fixed
  issue, so `/<mod>_regression_test` output maps 1:1 onto the tracker.
  Descriptive names (`dbg_helpers_two_channel`) are correct for structural
  invariants with no single issue.

**Tier (c) - Per-issue diagnostics / probes.** Instrumentation that captures
runtime data the decompiled source cannot give us (resolved anim vocab, live
table contents, attribution of a mis-behaving write). It is NOT tier (b): a
probe OBSERVES to diagnose an issue that is still OPEN; a regression check
ASSERTS that a CLOSED one stays fixed.

- Home: a per-mod diagnostics module - `_<ns>_diagnostics.lua` for the mod's
  standing dump/probe commands, or a per-cluster `_<ns>_diag_<topic>.lua` for one
  focused investigation (canonical: ct_dev's `_ct_diag_freeze487.lua`, keyed to
  issue #487).
- Engine `printf` only. The user plays with VMF mod-logging OFF, so
  `mod:info`/`mod:debug`/`mod:warning` can be invisible; `printf` always lands
  in `console_logs\` (CLAUDE.md NON-NEG #9; §3.6 "critical always-on telemetry").
- Armed while the issue is OPEN, RETIRED when it closes. Issue #500's probe
  sweep is the enforcement precedent: a probe that outlives its issue is dead
  log-noise, so closing the issue (`BUG_TRIAGE_RUNBOOK.md` STEP 9) includes
  removing or disarming its probe.
- The issue number appears in the probe's `printf` prefix as `[<ns>:<issue>]`
  (`[174:loadout]`, `[198:dummy_hits]`), so a captured log greps straight back
  to the tracker.

**Rules (binding):**

1. **No standalone one-issue probe file at a mod's script root going forward.**
   A single-issue probe folds into the mod's `_<ns>_diagnostics.lua`, or, if it
   is a self-contained cluster, lives as `_<ns>_diag_<topic>.lua`. Surviving
   root-level `_*_probe.lua` / `_diag_probe.lua` files are the #499 migration
   backlog, not the pattern to copy.
2. **Probes are automatic in dev streams unless their finite budget or topology
   requires an explicit command; they are inert-or-absent in clean stable.** A
   dev build normally captures the open issue without a menu toggle or setup
   command (§3.7 probe-first doctrine). A reviewed command-armed diagnostic is
   required when boot arming would consume its one-shot budget before the tester
   reaches the reproduction (canonical: #347's closed-chest pickup trace) or
   would capture the wrong host/client role. The registry records that arming
   mode. A clean-versioned stable/public build carries no issue-specific
   diagnostic: it retires before promotion or is stripped at promotion (§6.5).
   Existing public exceptions are explicit shrinking #499 debt, not precedent.
   Never gate a probe on a menu toggle.
3. **The probe's issue number is in its `printf` prefix** (`[<ns>:<issue>]`). No
   prefix, no traceability.

**Enforcement (2026-08-23).** `qa/diagnostic_ownership.psd1` is the authoritative
production census for every `*probe*.lua` and `_diag_*` root. Each row is exactly
one of `standing`, `active_issue`, `permanent_policy`, or
`temporary_exception`. Active rows bind the open issue, stream, exact receipt
prefix (including a documented alias such as #1309's legacy `[et:1149t]`), load
owner, arming mode, and finite-bound anchors. `qa/check_diagnostic_ownership.ps1`
blocks an unregistered root, missing metadata, a new standalone probe, or an
unreviewed public issue diagnostic in both Quick/full QA. Its fixtures are
offline. The hosted issue-lifecycle guard reuses its already-fetched issue set
and fails when an `active_issue` row no longer names an open issue. Closing an
issue therefore cannot silently leave armed instrumentation behind.

The only filenames containing `probe` permitted as permanent standing owners
are the exact stable/dev General Tweaker `_gt_debug_probes.lua` paths. All other
probe-named rows carry a shrinking `RemovalIssue = 499` exception. Do not widen
that list; rename or retire one owning mod transaction at a time.

**Current reality (2026-08-23; TARGET convention above, honest exceptions here):**

- Every active mod ships a `/<mod>_regression_test` command backed by an
  `_rt_register` suite - full tier-(b) coverage.
- Only 4 mods use a dedicated `_<ns>_regression.lua` module (wt, crt, et,
  event_tweaker). The other 10 register checks inline in `<mod>.lua`. Extracting
  the suite to a module is opportunistic, folded into the §2.2a decomposition,
  not a standalone chore. (wt already splits the harness into
  `_wt_regression.lua` while its 30 checks still register in `weapon_tweaker.lua`.)
- `issueNNN_` check naming is currently used only by cim / cim_dev
  (`issue88_*`, `issue96_*`); every other mod names checks descriptively. Adopt
  `issueNNN_` for NEW issue-locking checks.
- `gut_dev` registers the bare command `regression_test`; stable `gut` correctly
  uses `gut_regression_test`. Align dev to `gut_regression_test` on the next
  gut_dev touch (bare `regression_test` is the collision the gt prefix rule in
  `docs/COMMANDS.md` was written to avoid).
- `qa/diagnostic_ownership.psd1` is the authoritative production-owner census.
  Do not duplicate its changing counts or paths in prose; every migration must
  update the manifest and its self-tests in the same change.

Cross-ref: §3.5 (diagnostic dump commands), §3.6 (printf vs VMF logging), §3.7
(probe-first data harness), §5.1a (verify before shipping), §5.3 (pre-ship
review), `qa/CHECKS.md` (tier-a catalog + row 24a hook-test coverage),
`docs/BUG_TRIAGE_RUNBOOK.md` STEP 6/STEP 9 (where a fix's probe + regression
marker land).

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

### 3.6 Debug logging — VMF-native, no per-mod toggle (current policy 2026-06-29)

> **CURRENT POLICY (established 2026-06-29, supersedes the 2026-05-25 per-mod
> toggle below).** We do **NOT** ship our own `enable_debug_logging` checkbox
> anymore — it is redundant with VMF's own logging controls. Diagnostics route
> through VMF's logging methods and are gated by VMF's logging output level,
> which the user sets ONCE in VMF's options. There is **no per-mod toggle to
> enable/disable on our mods** — that is superfluous.
>
> - **Routine diagnostics** use the two file-local helpers, which now call VMF's
>   severity-scoped log methods directly (no `mod:get` gate of our own):
>   - `_dbg(fmt, ...)` → `mod:debug(...)` — emits only when VMF's **debug** log
>     level is on. File only.
>   - `_dbg_alert(fmt, ...)` → `mod:warning(...)` — emits only when VMF's
>     **warning** log level is on. File AND in-game chat.
>   So "as long as VMF logging is on, it happens" — specifically, `_dbg` rides
>   VMF's debug channel and `_dbg_alert` rides VMF's warning channel. The user
>   never touches a toggle on OUR side.
>   **CAUTION (Issue #240, 2026-07-02):** because VMF defaults `warning` to
>   mode 3 (`send_to_chat = mode >= 2`, upstream `logging.lua`
>   `load_logging_settings()`), a `mod:warning`-routed alert helper posts to
>   CHAT, not just the log. That is acceptable ONLY for genuine anomalies.
>   Routine diagnostics (plateau notices, expected boot-timing states,
>   consequences of the user's own slider values) must NOT route through it —
>   et's roaming-plateau line spammed chat on every mission load. et
>   (v0.7.25-dev) now routes `_dbg_alert`/`_spawn_dbg_alert` through
>   pcall-guarded log-only raw `printf` instead; see
>   `docs/BUG_CLASSES.md § 17 Variant B` for the fix template. `ct_dev`
>   still carries the chat-visible routing (fold into #169's sweep).
> - **Critical always-on telemetry** (instrumentation that MUST be captured even
>   when the user runs with VMF logging off — e.g. ct's `[ct-spawn-tally]` /
>   `[populate_pickups]` Horn-of-Magnus census) uses **raw `printf`**, which
>   bypasses ALL toggles (VMF's included) and always lands in `console_logs\`.
>   Reserve this for load-bearing diagnostics, not routine noise.
> - **Reference implementation:** `chaos_wastes_tweaker_dev` (#169, v0.7.186-dev).
>   `_dbg`/`_dbg_alert` route through `mod:debug`/`mod:warning`; zero live reads
>   of any `enable_debug_logging` key; no menu widget.
>
> **Migration status (2026-08-02).** Fully VMF-native (no `enable_debug_logging`
> key anywhere): `ct_dev`, `chaos_wastes_tweaker` (stable),
> `character_weapon_variants`, `weapons_of_chaos`, `career_tweaker`,
> `enemy_tweaker`, `event_tweaker`, `modded_progression`. Still on the legacy
> per-mod gate, keyed in code only (no menu widget): `cosmetics_tweaker`,
> `crafting_in_modded`, `crafting_in_modded_dev`, `dynamic_cosmetic_portraits`,
> `general_tweaker`, `general_tweaker_dev`. Still exposing the menu checkbox in
> `*_data.lua`: `gui_tweaker`, `gui_tweaker_dev`, `weapon_tweaker`,
> `weapon_tweaker_dev`. Rolling the VMF-native pattern out is a per-mod task — do
> it when touching each mod, or as a deliberate sweep. **Re-derive this list
> before trusting it** (`grep -rl enable_debug_logging --include=*.lua`, then the
> same over `--include=*_data.lua` for the widget split); the 2026-07-07 snapshot
> this replaces had drifted wrong in both directions.

---

#### Legacy: per-mod Debug Logging toggle (2026-05-25 — being phased out)

> Retained for the not-yet-migrated mods above. Do NOT add this to new mods or
> to `ct_dev`. New work follows the VMF-native policy above.

Established 2026-05-25. User feedback: "VMF menu options for debug are
inconsistent. Just a toggle for Debug Logging at the BOTTOM and have one
available for every single mod I have."

Each legacy (unmigrated) mod exposes a single VMF widget with **exactly** these
properties:

| Field | Value |
|---|---|
| `setting_id` | `enable_debug_logging` (verbatim — no per-mod prefix) |
| Widget type | `checkbox` |
| `default_value` | `false` |
| Localization (en) | `"Debug Logging"` |
| Tooltip (en) | `"Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable."` (note `%%APPDATA%%` — every literal `%` MUST be doubled because VMF runs the value through `string.format`; see `docs/LOCALIZATION_STANDARD.md` § 1) |
| Position | At the **BOTTOM of the widget tree**, as a **direct child of the top-level `mod.options_widgets`**. NOT nested inside any `group` / `Advanced` / `Misc` / `Developer` heading. |

**Anti-patterns:**
- Don't use a per-mod prefix on the setting_id (NOT `wt_enable_debug_logging`,
  NOT `cwv_debug_mode`). Same key everywhere.
- Don't nest it inside a group widget. Top-level only.
- Don't add it under "Advanced" / "Misc" / "Developer" group headings.

**Wiring (every `<mod>.lua` exposes a file-local `_dbg` helper near the top):**

```lua
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[%s:dbg] " .. fmt, "<mod_id>", ...)
    end
end
```

If the mod already has a `_dbg` / `_log` / `mod:debug` helper under a different
gate name (`debug_mode`, `wt_debug_mode`, `cwv_debug_mode`, `debug_dumps`,
`debug`), the helper body must be renormalized to read
`mod:get("enable_debug_logging")`. Don't break existing call sites — the gate
key changes, the helper signature and call sites stay the same.

### 3.7 Debug mode is a DATA HARNESS (established 2026-06-11)

User directive: *"when the debug mode is active, every mod with it on should be
gathering any data that is not in the game's source code and is not available
via other mods I have available. I don't want to have to do a lot of digging or
scraping for data."*

**Why:** Claude cannot see the running game, and the decompiled source lacks
runtime-resolved data (skeleton anim-event vocabularies, resolved material
slots, live table contents after DLC/mod merging, unit↔backend-id maps). Every
time that data is missing, the user pays a full in-game session to fetch it by
hand. Debug Logging ON = the user is granting a data-collection window — use it.

**Rules:**

1. **Probe-first development.** When designing any feature that depends on
   runtime data, ship the probe/dump in the build BEFORE (or with) the feature
   scaffold, have the user run one session, then build on captured data — never
   on guesses. (Sibling of §14a and the diagnose-before-mitigating rule.)
2. **Dumps are parseable, not prose.** Probe output is either (a) paste-ready
   Lua in the EXACT table syntax of the destination source file (the
   `/wt_dump_anim_picks` pattern — `local _PORT_WIELD_3P = {...}` blocks), or
   (b) one-line `key=value` records greppable by a stable prefix tag
   (`[illusion-probe]`, `[wt:dev_anim]`). Never multi-line free text.
3. **Opportunistic capture is encouraged** when it's data-not-in-source and
   cheap: low-volume always-on probes (≤1 line per user action — the
   cosmetics `[illusion-probe]` precedent) may even stay UNGATED; anything
   chattier rides the `enable_debug_logging` gate.
4. **Tune→export→bake loop.** Any in-game tuning surface (anim picker, hold
   pose, glow sliders, scale/grip) MUST pair with an export command that
   serializes the user's current tuned values as paste-ready Lua. Tuning UIs
   without an export path strand the data in the session.
5. **Index your probes.** Each mod's CHANGELOG/DEVELOPMENT notes which probe
   tags exist and what they capture, so a later session greps the log instead
   of re-deriving.

**Migration:** when renaming an old key, leave a brief CHANGELOG note that the
old key (`wt_debug_mode`, etc.) was renamed and users may need to re-toggle the
new `Debug Logging` checkbox after first load. Don't try to silently auto-
migrate the saved value — the friction is one re-tick.

Cross-ref: `docs/VMF_RECIPES.md` § 9. For Layer 3 `mod:traced_hook` (shipped in `weapon_tweaker` v0.12.84-dev), which emits structured `[<mod>:trace] event=enter|exit class=<C> method=<m> n_args=N` / `n_returned=M` log lines gated on this same `enable_debug_logging` toggle, see `docs/VMF_RECIPES.md` § 2b "Layer 3: traced_hook" — including the per-frame rate-limit caveat.

#### Two-channel discipline (`_dbg` vs `_dbg_alert`)

Established 2026-05-25. User feedback: "When debug logging is on, I want
messages to be consistent for each mod, and show up in the in-game chat log
via echo whenever something is unexpected or wrong. If things go as expected
or just to confirm things are working or firing, I want log messages in the
actual log, not the ingame chat log. Likewise info dumps and such go into
the game log, not the in-game log."

Every mod ships **two** debug helpers (not one), both gated on the same
`enable_debug_logging` key:

**Decision matrix:**

| Case | Helper | Lands in |
|---|---|---|
| Confirmation / dump / expected behavior | `_dbg` | log file only |
| Unexpected / wrong / mismatch / error condition | `_dbg_alert` | log file AND in-game chat |
| User-operational (chat command reply, `/verify_*` output) | bare `mod:echo` | chat (not gated) |
| Permanent operational log (`[wt] enabled vX.Y.Z`) | bare `mod:info` | log file (not gated) |
| Stricter VMF levels | `mod:warning` / `mod:error` | VMF default semantics |

**Canonical helper pair** (insert near top of every `<mod>/scripts/mods/<mod>/<mod>.lua`):

```lua
-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[<mod_id>:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[<mod_id>:dbg] " .. fmt, ...)
        mod:echo("[<mod_id>] " .. fmt, ...)
    end
end
```

Replace `<mod_id>` with the mod's short ID (`wt`, `ct`, `gt`, `cwv`, `cosmetics`,
`cim`, `bt`, etc.) — match the existing log prefix convention. The mod's
`_RT_CHECKS` regression scaffold must include the smoke test:

```lua
_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local saved = mod:get("enable_debug_logging")
    if saved ~= false then mod:set("enable_debug_logging", false) end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
    if saved == true then mod:set("enable_debug_logging", true) end
end)
```

**Classifying call sites:**

When picking between `_dbg` and `_dbg_alert` for a new call site, look at the
format string + context:

- Words/phrases suggesting an **ALERT** (`_dbg_alert`):
  "failed", "error", "unexpected", "missing", "nil", "mismatch", "raised",
  "skipped", "dropped", "fallback", "corrupt", "stale", "couldn't",
  "no longer", "broken", "invalid"
- Words/phrases suggesting **CONFIRMATION** (`_dbg`):
  "fired", "applied", "installed", "registered", "loaded", "completed",
  "ok", "ready", "received", "sent", "match", "found"
- Ambiguous → leave as `_dbg`. **Conservative default.**

**Edge cases:**

- **Expected guard / SKIP branches** — even if the format string says "nil"
  or "no X", if the branch is the normal-flow exit when a guard condition
  is unmet (e.g. `if not local_player then _dbg("no local player"); return end`),
  keep as `_dbg`. Promoting it would spam chat during normal play.
- **Hot-path observation hooks** — state machine transitions, frame-by-frame
  hook entry logs, scale/grip dumps, wield events. These are confirmation,
  not alerts. `_dbg`.
- **Post-warning follow-up logs** — when a `mod:warning` has already fired
  and a follow-up `_dbg` line documents the resulting bail path,
  promote to `_dbg_alert` so the user sees the chain.

**Anti-patterns:**

- Don't use bare `mod:echo` for non-user-facing dumps — that bypasses the
  toggle and pollutes chat. Use `_dbg` (log file) or `_dbg_alert` (chat
  when toggle is on).
- Don't use `_dbg_alert` for routine confirmations — that defeats the
  whole point of the two-channel split.
- Don't introduce a third helper. Two channels (log-only, log+chat) cover
  every case in the policy matrix above.

**Cross-ref:** `docs/VMF_RECIPES.md` § 9 (universal debug toggle).

#### Applied marker line (universal)

Established 2026-05-25 (rolled out across all 16 active mods in the same pass that added `/perf_dump` to bt). Every mod prints ONE banner-style `mod:info` line at load surfacing the current MOD_VERSION and a short hash of the live settings values, so scrolling back any `console_log-*.log` you can see exactly which build + config was running at any point.

| Field | Value |
|---|---|
| Line format | `[<mod_id>] enabled v<MOD_VERSION> settings_fp=<8-hex>` |
| Log level | `mod:info` — ALWAYS fires. Not gated on `enable_debug_logging` — this is operational telemetry, not debug noise. |
| When | Once, at load. Right after the `_dbg_alert` helper (or inside `mod.on_enabled` if the mod is togglable and the on-load surface is awkward). |
| Where to place | File-local `_settings_fingerprint()` helper near MOD_VERSION setup; the marker line directly below it. |
| Per-mod addenda | OK as trailing space-separated `key=value` tokens (e.g. et appends `host_required=true`). Keep them short. |

**Fingerprint helper** (drop-in; replace `<MOD_LONG_ID>` with the mod's directory name):

```lua
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/<MOD_LONG_ID>/<MOD_LONG_ID>_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    -- FNV-1a 32-bit, plain-arithmetic XOR (no bit32 in Lua 5.1 sandbox).
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[<mod_id>] enabled v%s settings_fp=%s", MOD_VERSION, _settings_fingerprint())
```

**Why this shape:**

- **Walks the data widget tree via `pcall(require, "...")`** rather than a hardcoded key list per mod, so the helper stays maintenance-free as `_data.lua` grows / shrinks. Cached in `package.loaded`; safe to call from main lua (already-required by VMF before main runs). Idempotent — re-evaluating the data file just rebuilds the same widget table.
- **`pcall` wrap** so a malformed / missing data file produces `nodata` instead of a hard crash on every mod load.
- **FNV-1a-32 inline** instead of a shared module — keeps the helper file-local, no resource_package additions, no cross-mod coupling. Plain-arithmetic XOR (not `bit32`/`bxor`) because VT2's Lua 5.1 sandbox doesn't ship `bit32`. Reuse the canonical implementation from `enemy_tweaker.lua:_fnv1a32` if a mod already has it (et does — its helper became the prototype for this convention).
- **Sorted keys** so the hash is deterministic across peers when settings match. Different config → different fp → mismatch visible at a glance.
- **`mod:get(k)`** at fingerprint time — captures the LIVE setting value on this peer (post any `_strip_*_widgets` mutation in `_data.lua`, like wt's CIM-conditional strip), not just the canonical definition.

**Anti-patterns:**

- Don't gate the marker on `enable_debug_logging` — it MUST always fire so logs are self-documenting.
- Don't walk `widget_definitions` or VMF internals — the simple recursive walk of the returned data table works for every shape used in this repo.
- Don't hardcode `_BR_SETTING_NAMES`-style key lists per mod for the universal marker. That pattern is fine for feature-specific RPC compares (et's `_br_settings_fingerprint` still uses it because the BR cross-peer RPC needs a stable subset), but the universal marker hashes everything.
- Don't include the master toggle in a per-mod addendum if it's already in the hashed key set — the fingerprint already changes when the master flips. Addenda are for fields that AREN'T in the widget tree (et's `host_required=true` is a static design-intent token).
- Don't print this line more than once per mod load.

**Cross-ref:** `docs/VMF_RECIPES.md` § 11 (Per-hook perf timing via bt.perf_record — sibling experimental hardening that landed in the same pass). **[SUPERSEDED 2026-07-07 — bt retired 2026-06: the `bt.perf_record` framework is gone with `bt`; this cross-ref is historical.]**

#### Chat-echo policy (when is `mod:echo` allowed?)

Established 2026-05-25. User feedback: *"on enabling debug logging, I'm getting needless echos to the chat that it's enabled, this is inconsistent... on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV, and I don't see the need."*

`mod:echo` writes to the in-game chat log and is **always visible to the player**. Use it sparingly. The decision matrix below is binding.

| Call site | Policy | Why |
|---|---|---|
| Module load (top of `<mod>.lua`) -- stable (>=1.0.0) versions | **NEVER** | The applied marker `[<mod>] enabled v<X> settings_fp=<hash>` line already lands in the console log; chat banner is pure spam. |
| Module load (top of `<mod>.lua`) -- dev / alpha / beta / rc / 0.x versions | **REQUIRED** -- one line, `[<mod_id>] v<MOD_VERSION> loaded` (see snippet below) | Established 2026-05-25 EOD: in-flight builds change patch-by-patch and the user needs the active version visible at a glance. Silent dev banners feel like errors are being hidden. Cross-ref § 14a persistence-after-fix protocol. The applied marker is log-only and not enough for live iteration. |
| `mod.on_setting_changed` for routine settings | **NEVER** | Spams chat on every checkbox flip — including the universal `enable_debug_logging` toggle, which is what triggered this policy. Use `_dbg` if you need a trace. |
| `mod.on_setting_changed` for explicit high-impact toggles | **OK** | Operational feedback the user expects in response to a deliberate action. Canonical examples: `bt`'s `bt_master_enable_br_registrations` ("can't apply yet — restart" / "master toggled OFF") at `buff_tweaker.lua:~275`; `gt`'s AI takeover toggle ("AI ON / OFF requested") at `general_tweaker.lua:~826-828`. |
| `mod.on_enabled` echoing version / banner | **NEVER** | Same reasoning as module load — the applied marker line covers it. |
| `mod.on_enabled` / `mod.on_disabled` for non-trivial state changes | **OK** | When the user toggles the whole mod off/on via the VMF menu, immediate chat confirmation of what unwound (or didn't) is high-impact operational feedback. Canonical examples: `enemy`'s "Enemy Tweaker enabled / disabled — compositions restored" at `enemy_tweaker.lua:~929/949`; `gt`'s `on_disabled` "Disable does not fully unwind active mutations" warning at `general_tweaker.lua:~849` (this is the canonical Issue #15 documented-limitation pattern from `docs/BUG_CLASSES.md § 7`). |
| Inside `mod:command(...)` bodies (`/verify_*`, `/<mod>_regression_test`, `/dump`, status commands, etc.) | **OK** | User invoked the command via chat; reply belongs in chat. Don't gate these on `enable_debug_logging`. |
| Routine confirmations / diagnostic traces | **NEVER bare `mod:echo`** — and NEVER `mod:warning` either | Use `_dbg` (debug channel, log-only) or a log-only printf helper. `mod:warning` posts to CHAT under VMF default settings (Issue #240; `BUG_CLASSES.md § 17 Variant B`). |
| Unexpected guard / fallback recovery | `_dbg_alert` (or `mod:warning`) | Per two-channel discipline. NB: `mod:warning` lands in chat whenever VMF's warning channel is chat-enabled — which is the DEFAULT (mode 3), not only when debug logging is on. Acceptable for genuine anomalies; et routes its alert helpers through log-only printf instead (#240). |

**Canonical dev-banner snippet** (drop right after the `mod:info("[<mod_id>] enabled v%s settings_fp=%s", ...)` applied marker line in every mod's main lua):

```lua
-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[<mod_id>] v%s loaded", MOD_VERSION))
end
```

Replace `<mod_id>` with the canonical short id (bt / crt / ct / cwv / cosmetics / cim / dcp / et / ewt / gt / gut / mp / wt). The `^0%.` branch catches versions like `0.1.12` (no track suffix) so dcp and other 0.x stable-looking versions still print. Bump to 1.0.0+ to flip a mod to silent-on-load — no other change needed; the detector matches no branches and the `if` falls through.

**Anti-patterns:**
- Don't add a debug-gated `if mod:get("enable_debug_logging") then mod:echo(version) end` — the dev-banner above already runs unconditionally for dev/alpha/beta/0.x and is silent for stable. Gating on debug-logging is the wrong axis.
- Don't add new `mod:echo` in any hook body without confirming the call site appears in the OK column above. New chat echoes are a code-review red flag.
- Don't downgrade an OK echo to `_dbg` just because the policy mentions `_dbg`. The matrix is exhaustive — if the call site is in an OK row, keep the bare `mod:echo`.
- Don't echo more than one banner per module load — one line is enough. The applied-marker `mod:info` line above stays unchanged and remains log-only.

**Verification:** before shipping any mod, `Grep mod:echo <mod>/scripts/mods/<mod>/<mod>.lua` and audit each hit against the matrix. Per `docs/BUG_CLASSES.md § 17 "Chat-echo spam"` for the failure-mode catalogue.

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
4. **No `tags = [ ]`** in cfg (enforced by `qa/check_cfg.ps1`; rationale in the launcher repository's `CLAUDE.md` § "Drop `tags = [ ];` from cfg on first upload").
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

### 5.1b Appearance architecture census (binding, issue #660)

Any change that introduces or migrates a weapon/cosmetic appearance concern
(unit identity, transform, material, glow, pose, effective template, icon, or
name) must register that concern in `qa/appearance_contracts.psd1` in the same
commit. The entry must declare every canonical render surface and lifecycle
replay edge, including honest `deferred` or `not-applicable` cells with reasons,
and map every `covered` cell to an existing named offline test.

The checker owns immutable minimum surface, replay-edge, and concern
vocabularies. The manifest may add cells but may not shrink those minima; a
manifest and its contracts deleting the same required cell must fail CI.

`qa/check_appearance_contracts.ps1` is a blocking Quick/full gate. Passing it
means only that the architectural census and referenced structural tests are
complete. It never means a renderer, transition, retained engine state, or
peer observer passed in-game; those remain subject to G-APPEARANCE's live and
co-op verification matrix.

### 5.1c Retained-state verification (binding, issue #660)

Any fix that touches rendering, transform, material, glow, or pose state MUST
log the RETAINED engine state read BACK from the engine after the edge it
mutates, never the success of the setter call. A `set_local_scale` /
`set_local_position` / material-override call can return cleanly while the
retained state the renderer actually reads stays unchanged, so setter-success
("applied=y") is worthless as verification evidence: it proves a call happened,
not that anything changed.

This is the #660 false-positive class. `weapons_of_chaos` logged an apply target
of `{0,0,-0.3}` while the retained transform stayed identity, and that setter-
success line read as a pass while the render was in fact untouched. The
reference implementation is the `[cwv:huskpath]` postcondition pattern in
`character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua`
(`_om._husk_postcondition_log`): after the apply resolves a def it reads
`retained_scale` / `retained_pos` / `retained_rot` back off the engine and logs
those, throttled once per (slot, hand, def, retained-fingerprint). Copy that
shape at any new appearance apply site: read back, log the readback, never the
setter return.

A `verify-fix` label on an appearance issue additionally
requires the census row context per `docs/APPEARANCE_UNIFICATION_PLAN.md` § 4:
the family's census row must be green across cells, and the test-method comment
(§11 test-method prerequisite) must name the cells exercised. A setter-success
log or a single-surface check does NOT earn the label.

Cross-ref: §5.1a (apply-site log line), §5.1b (appearance contracts census),
§11 Labels (verify-* prerequisites), `docs/WEAPON_APPEARANCE_STANDARD.md` (the
canonical render-path contract).

### 5.1d Postcondition-first verification (binding, issue #1156)

A check that renders a verdict is an INSTRUMENT. When the instrument lies,
every downstream session aims its fix at the wrong target, and a green suite
actively hides the defect. The five rules below bind every `_rt_register`
check, every `/verify_<feature>` command, and every offline QA gate that
decides whether a fix landed. #1156 is the program issue; the symptom /
diagnosis catalog is `docs/BUG_CLASSES.md` § 85 "Lying instrument (harness
misreport)".

1. **Assert RETAINED, player-visible state against INDEPENDENT ground truth.**
   The expectation comes from authored data the defect cannot move (an
   `ItemMasterList` entry, a catalog table, an authored settings default),
   never from setter success, and never from a value the code path or state
   under test just produced. Evidence: the cwv offline checks
   `issue579_dual_axes_preview_and_husk_skin_continuity` and
   `issue719_imperial_crowbill_remote_identity` both PASSED while both defects
   reproduced in the live co-op session; the 579 check compared against an
   expectation derived from the already-collapsed state the defect itself
   produces, so it could only ever agree with the bug. This generalizes §5.1c
   from appearance state to every check.

2. **Disconnecting, relocating, or shadowing a live hook, marker, or needle
   MUST fail a contract check loudly.** A check that can silently read `nil`
   and still return a verdict (pass OR fail) is malformed: it is reporting on
   nothing. Assert that the read resolved before asserting on its value.
   Evidence: #1148, where the marker constants are file-scope locals in
   `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:26-38`
   while the relocated checks in `_cwv_regression_identity.lua` read them as
   bare globals, producing false "was the fix reverted?" FAILs on
   verifiably present code. Same class in the other direction: the cosmetics
   `0.9.65-dev` transition self-heal shipped inert and stayed inert 3+
   versions because no gate noticed a live hook had been disconnected (#233).

3. **Runner return-shape contract.** A check returns `nil` on success and a
   reason STRING on failure. A runner passes ONLY on `nil`, and treats boolean
   `true` as a LOUD malformed-check failure: not a pass, and not an ordinary
   FAIL to be triaged as a code bug. Evidence: #1153, where a gt check returns
   `true` on success while the runner passes only on `nil`, so healthy wiring
   reports FAIL permanently and the real signal is buried. Current reality: the
   gt_dev runner gives a boolean return its own loud BAD-SHAPE verdict as of
   `0.2.264-dev`, and the cwv runner renders XFAIL/XPASS as of `0.1.490-dev`
   (both #1156 Phase 1); the cwv runner does not yet flag a boolean return
   specially.

4. **Known-open defects are annotated as EXPECTED failures, never
   assertion-weakened.** A check locking a defect that is still open carries an
   XFAIL annotation naming the issue, so the suite is honest about what is
   broken. An XFAIL that PASSES (XPASS) is itself a loud failure: it demands
   either removing the annotation or verifying the fix, because the suite's
   model of reality has drifted. Never make a suite green by loosening an
   assertion, widening a tolerance, or deleting a case; that converts a known
   defect into an unknown one.

5. **Any needle a test card relies on must be ALWAYS-ON and TEXT-STABLE.**
   Bounded engine `printf`, never `mod:debug` / `mod:info` and never behind a
   `_dbg` flag or menu toggle - a needle that cannot appear with mod logging
   off false-PASSes its card, which is how the user always plays. The emitted
   TEXT is part of the same contract: the issue-154 husk preflight instruments
   were already always-on, but the strings the card greps
   (`NOT in resource manager`, `cache_has_wearer=`) had been reworded out of
   the emissions in cosmetics `0.9.42-dev`, so a tester greps the needle,
   finds nothing, and scores the absence as a pass. Rewording an emitted
   needle requires updating every card that greps it in the same change
   (needles restored in `0.9.187-dev`). Same rule as §3.6 "critical always-on
   telemetry" and §2.2b tier-(c), applied to the card's evidence line
   specifically.

Cross-ref: §5.1a (apply-site log line), §5.1c (retained-state readback),
§2.2b (test and diagnostic tiers), §3.6 (printf vs VMF logging),
`docs/BUG_CLASSES.md` § 85, `docs/BUG_TRIAGE_RUNBOOK.md` STEP 8.

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

### 5.3a Immutable review manifests (binding, issue #1435)

Any handoff or independent review that claims a frozen multi-file byte set uses
`tools/review/content-manifest.ps1`. Supply the exact repository root, full base
commit ID, and bounded repository-relative file set. The canonical manifest and
its aggregate digest are the evidence identity; ad hoc `Sort-Object` hashing
recipes are forbidden because PowerShell sorting follows the current culture.

The tool is read-only against the reviewed repository and uses an explicit
ordinal path order, strict UTF-8-without-BOM/LF grammar, normalized forward-slash
paths, present/deleted records, raw file lengths/hashes, and a base-commit-bound
aggregate. Implementation and reviewer lanes invoke the same tool. A candidate
changes identity when any byte, length, path, deletion state, or base commit
changes. Full grammar and command examples live in `tools/review/README.md`;
`qa/check_content_manifest.ps1` is the blocking cross-culture contract.

### 5.4 Automated host testing

The repository now has all three host-side layers: `luacheck`, PowerShell
policy/static checks, and dependency-free Lua 5.1 unit tests. `qa/run_all.ps1`
is the single policy engine locally and in GitHub Actions.

Pure Lua tests are for deterministic transformations that accept and return
ordinary Lua values. Load the production module; do not copy its implementation
into a fixture. One narrow boundary function (for example `Localize`) may be
supplied test-locally, but hooks, RPCs, engine objects, and multiplayer state
remain in the in-game regression tier. See `qa/lua/README.md`.

Next investment should follow demonstrated bug classes: extract pure logic when
a touched feature already has a clean seam, then add the regression before or
with the behavior change. CHANGELOG-format validation remains optional/low ROI.

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

### 6.5 Dev vs stable promotion streams

Established 2026-05-26. Five mod families — `chaos_wastes_tweaker`
(`ct`), `crafting_in_modded` (`cim`), `general_tweaker` (`gt`),
`gui_tweaker` (`gut`), `verminious_dreams_lighting` — are split into two parallel directories each:
`<mod>/` (stable promotion target) and `<mod>-dev/` (friends-only development
item). Stable-item visibility is read from its current `itemV2.cfg`; it is not
implied by this stream shape. Weapon Tweaker's public-beta/friends-only parity
mirror is a separate contract, and all other mods are single-stream.
See `CLAUDE.md` § "Dev/stable split workflow" for the full rationale and the
Workshop ID / mod_id mapping. **[Corrected 2026-07-07: `gui_tweaker`/`gut` was added to the split after this section's 2026-05-26 authoring and had been undercounted here as four.]**

**The binding rules:**

- **All new work goes in `<mod>-dev/`.** Iteration, in-flight fixes, half-done
  experiments. Never edit the stable directory directly for in-flight work —
  if a stable-bound user bug needs a hotfix, write the fix in `<mod>-dev/`
  first, verify it in the dev stream, then promote.
- **Dev MOD_VERSION carries `-dev`/`-alpha`/`-beta`/`-rc<N>`** per § 6.1. Dev
  uploads always target the friends-only item with `visibility = "friends_only"`
  in the dev clone's `itemV2.cfg`. They never use `--allow-public`.
- **Stable receives release merges only.** When a chunk of dev work is ready
  for the stable stream, it gets promoted via the checklist below — never by
  editing the stable directory in parallel with dev.

**Promote-to-stable checklist** (binding when merging dev work down to stable):

1. **Cherry-pick or merge** the work into `<mod>/` from `<mod>-dev/`. Do this
   as a deliberate copy / patch — don't symlink, don't share files, don't
   build from the dev tree with a `--out=<stable>` trick. The stable tree
   must be an independent, audit-able copy of the released code.
2. **Set MOD_VERSION to the version the user names for the release** in
   `<mod>/scripts/mods/<mod>/<mod>.lua`. It MAY keep a pre-release suffix —
   a beta/alpha on the stable item is a legitimate, user-chosen state
   (e.g. ct promoted 2026-07-03 as `0.7.130-beta`; gut stable runs as a
   public alpha). Strip the suffix only when the user names a clean version
   (then per § 6.1: `0.7.66-dev` in dev becomes `0.7.66`, or bump to
   `0.7.67` if a previous stable build already used it). The suffix carried
   here decides future ship approval per § 6.6.
3. **Update the stable mod's CHANGELOG.md** with a single rolled-up entry
   covering the merged work. Reference the dev versions that contributed
   if it helps the reader (`merge of dev 0.7.62-dev..0.7.66-dev`).
4. **Claim, then build the authority-selected artifact** with
   `tools\ship\claim.ps1 -Mod <stable-mod>` and
   `tools\ship\ship.ps1 -Mod <stable-mod> -BuildOnly`.
5. **Commit source plus its exact authority proof together.** Tracked authority
   commits the generated bundle; receipt authority commits schema 3 and no
   `bundleV2` output. Push a feature branch, open a PR to protected `master`,
   require `qa-gate`, and merge.
6. **Apply the suffix approval rule in § 6.6.** A clean MOD_VERSION needs a
   fresh per-build ship signal naming the version. A user-chosen pre-release
   suffix ships the full pipeline without another prompt, including on a public
   item. Workshop visibility does not change this approval rule.
7. **From a clean worktree at the exact live default-branch commit, run
   `ship.ps1 -Mod <stable> -AllowPublic`.** The wrapper requires the merged PR,
   successful hosted `qa-gate`, exact newest CHANGELOG/MOD_VERSION identity,
   and machine-global version claim before any mutation. It clean-builds and
   proves the complete output equals the merge commit's tracked blobs or
   committed schema-3 receipt. Tracked authority may then deploy and upload;
   receipt authority is publication-only. It records the authorization in the
   GitHub release manifest.
8. **Smoke-test the hash-verified deployed stable bundle.** A disabled remote is
   intentionally out of scope and must not be reported as updated. The dev
   bundle may be live in the same install (different mod_id); test that the
   stable build behaves correctly alone.

**Dev uploads are pre-authorized: NO per-build approval.** Per the ship
doctrine in § 6.6, a `-dev`/`-alpha`/`-beta`-versioned build ships the full
pipeline on every update. Dev uploads target the friends-only item, skip
`--allow-public`, and ride the reviewed `ship.ps1` pipeline. GitHub release and
the source commit/PR/hosted-QA/merge are mandatory predecessors to Workshop
mutation, not post-upload follow-ups.

**Cross-mod refs** always resolve against the stable mod_id (`get_mod("cim")`,
`get_mod("gt")`, `(get_mod('bt') or {}):is_br_active()`). Dev clones are
isolated test surfaces; no consumer mod resolves against `cim_dev`/`gt_dev`/
etc. If you need to point a consumer at a dev clone for testing, edit the
consumer's `get_mod(...)` call locally — never ship that change to a stable
directory.

**RPC isolation caveat:** anything keyed by mod_id (lobby RPC channels, the
`GT_LOBBY_RPC_SCHEMA` constant, mod-defined `network_register` channels) is
automatically isolated between stable and dev because the mod_ids differ.
Sessions that need the lobby/MOTD surface should pin every peer to the same
stream.

### 6.6 Ship doctrine: keyed off the MOD_VERSION suffix (canonical, 2026-07-01)

Whether a build ships to the Workshop without asking is decided by the
**MOD_VERSION suffix**, not by the directory, the Workshop visibility, or how
long ago the user said "ship it". This is the single source of truth for ship
approval; where earlier text conflicts, this section wins.

**Pre-release-versioned mods (`-dev` / `-alpha` / `-beta` / `-rc<N>`) cover
EVERY active mod in the repo, including single-stream items whose current cfg is
public:** every update ships the FULL pipeline with NO per-build approval. The
full pipeline is:

1. Acquire the machine-global mod/version claim. Update source, exact first
   CHANGELOG release, and `MOD_VERSION`; run
   `tools\ship\ship.ps1 -Mod <name> -BuildOnly` to generate and validate the
   authority-selected output without deploying or uploading. **If the change
   touches TWO mods, `-BuildOnly` BOTH before committing** — the atomicity gate below
   requires each mod's source change and its own tracked root `.mod_bundle` or
   committed schema-3 receipt in the same commit, so a half-built pair fails
   the PR.

**The claim broker owns the version number.** `tools\ship\claim.ps1` writes a
machine-global claim at `%APPDATA%\VMBLauncher\ship_claims\<mod>.claim`, shared
across every worktree and every concurrent session on the machine. The number it
returns can be HIGHER than the newest version on `master` + 1: prior claims that
never shipped burn their numbers permanently. Always renumber `MOD_VERSION`, the
newest CHANGELOG heading, and any version reference to the broker's answer —
never to master+1 by inspection, and never re-use a burned number. Claim BEFORE
bumping, not after; a bump chosen first usually has to be redone.
2. `git add` / `git commit` source and its authority proof together (tracked
   bundle or receipt-mode schema 3), push a feature branch, and merge it through
   protected `master` only after `qa-gate` passes.
3. From a clean worktree at the exact live default-branch commit, run
   `tools\ship\ship.ps1 -Mod <name>`. It re-runs hosted authorization, clean
   build, authority parity, authorization-backed GitHub release, Workshop
   upload, and transfer verification in that order. Tracked authority deploys
   first when a target is enabled; receipt authority never deploys. Recording
   authorization before Workshop mutation is mandatory. Add `-AllowPublic`
   when `itemV2.cfg` is public.
   Use `-NoRemote` only to skip an otherwise-enabled remote for that invocation,
   and identify the skipped target in the report.

There is no pre-merge or hosted-QA publication override. `-SkipGitHub` and
`-EmergencyPublicationReason` are prohibited because Workshop mutation cannot
bypass exact clean default HEAD, its merged PR, successful hosted `qa-gate`,
release provenance, the machine-global claim, or authority-selected output
parity.

The hosted-check lookup is fully paginated (issue #1109). Issue and tracker
workflows can attach more than GitHub's default 30 check runs to one commit, so
publication authorization must request the maximum page size and flatten every
page before locating the exact successful `qa-gate`. Never treat the first REST
page as a complete authorization census.

**Agent/headless publication is noninteractive.** The operator entry point is
only `tools\ship\ship.ps1`; direct launcher publication and GUI publication are
not alternatives. Agent, CI, and default launcher verification must not start
WPF, Explorer, or any other interactive window, and must not run real
build/deploy/publication integration actions as an incidental smoke test.
Launcher GUI and mutating integration suites require explicit human opt-in and
are never part of a ship. A visible launcher window during agent work is a
tooling defect: stop the transaction before publication and fix the launcher
guard rather than hiding or dismissing the window. The launcher repository's
`CLAUDE.md` owns its implementation and test split.

**One machine-global transaction owns every mutation (issue #1180).** Both
`ship.ps1 -BuildOnly` and the final ship acquire
`Global\Ensrick.VMBLauncher.Transaction.v1` before the first settings, VMB, or
filesystem mutation and retain it continuously through build, authority parity,
deploy, GitHub-release mutation, SDK staging/upload, Workshop verification,
card refresh, and claim finalization. The lock order is machine transaction,
then the publisher's GitHub-release mutex, then the launcher's legacy upload
semaphore. VMBLauncher 0.6.0 plus `machine-transaction-lease-v1` and
`crash-safe-upload-acl-journal-v1` is the minimum accepted publication
boundary; 0.5.9 fails before release mutation.

Canonical ship reads global launcher settings once for approved dependency
discovery, then writes one durable, PID/start-identified private `--config`
bound to the exact worktree. It never temporarily rewrites shared
`%APPDATA%\VMBLauncher\settings.json`. A named kill-on-close Windows Job contains
all mutating descendants. On hard owner death, a contender must observe the
persisted job drained through bounded `ActiveProcesses` accounting (not Job
signalling) before recovery or mutation; on ordinary release,
authenticated residual descendants are terminated before unlocking. Do not run a parallel retry, manually reset SDK ACLs, delete owner/journal records, or
weaken an ambiguous recovery failure. Only the exact journaled descriptor or
exact legacy 0.5.9 launcher DENY recovery lane may repair staging ACLs.
In short: canonical ship never rewrites shared launcher settings.

**First-upload bootstrap is identity allocation, not a test release.** A
reviewed `published_id = 0L` commit may use the constrained hosted bootstrap
receipt so Steam can allocate one ID. After the launcher compare-and-swaps only
that ID into the still-authorized cfg, `ship.ps1` must stop before lifecycle
labeling and test-readiness output and must retain the machine-global claim.
Rerun canonical BuildOnly so the receipt binds the assigned-ID cfg, then commit
the ID-only cfg and refreshed receipt, pass protected PR QA, merge, and run an
ordinary canonical ship before releasing the claim. The root may remain
byte-identical because `itemV2.cfg` is not compiled. The atomicity exception is
limited to exactly `published_id = 0L` becoming one canonical positive ID with
unchanged `MOD_VERSION`, title, and every other cfg byte; receipt validation is
still mandatory. The provisional GitHub manifest's zero Workshop ID is not
updater/test-ready evidence.

**Daily GitHub release mutation is globally serialized.** Per-mod claims permit
two different mods to ship concurrently, but their filtered publishers share
one release manifest. The publisher therefore holds one machine-global mutex
from release lookup through carry-forward, immutable snapshot capture, and
release-ID mutation; removing or narrowing that transaction revives lost
manifest updates.

**Pinned-card refresh is stream-specific, not load-tag-specific.** A runtime
tag such as `[wt:LOAD]` may be intentionally shared by public and development
streams. The post-ship refresher must bind a version rewrite to the exact mod
directory, Workshop item, and display/stream identity. A shared tag alone is
ambiguous and fails closed. When a card names the shipped item only as a mirror
receipt but its runtime anchor explicitly belongs to a sibling stream, only the
shipped item's manifest may advance; the sibling version remains byte-exact.
This is the #1102 boundary that prevents one stream's ship from rewriting the
other stream's test queue.

**Backlog card reconciliation is one atomic all-stream candidate.** A stale
cross-mod card cannot be repaired safely by a sequence of single-stream edits:
every intermediate body still names at least one superseded sibling and must
fail deployed-source authority. Use `refresh-cards.ps1 -ReconcileAllStreams`
for the corrective lane. It inventories every deployed stream from the hosted
latest-release manifest, resolves shared LOAD tags only through an exact item,
stream identity, or unique already-current version, rewrites all attributable
anchors in memory, normalizes only complete duplicate or known incomplete
optional Workshop coordinates, and validates the whole candidate once before
mutation. Ambiguous tags, unknown coordinate shapes, unsupported diagnostics,
or any final authority error remain untouched and must leave the issue outside
the ready queue until repaired. Run `-DryRun` first; the operation is
idempotent and preserves no-op card bytes exactly (issue #1343).

**Atomic source/output-authority gate (issues #724/#1412).** A PR that changes
an active mod's runtime source, `itemV2.cfg`, or newest CHANGELOG release
identity must also change that mod's exact authority proof. `tracked` authority
requires the exact root `.mod_bundle` identified by the canonical `RootBundle`
field in `tools/mod-inventory.psd1`; a common VMF bundle or custom asset sidecar
cannot stand in for the root. `receipt` authority instead requires the exact
schema-3 receipt and zero tracked `bundleV2` output, with the complete typed
transition validated by `bundle-authority.ps1`.
`qa/check_release_bundle_atomicity.ps1` enforces this in pre-commit, Quick/full
QA, and hosted PR QA. Docs/tests-only and authority-proof-only reconciliation
changes remain valid. A tracked-output deletion is legal only inside the exact
typed `tracked` to `receipt` transition; every other deletion keeps the
retirement-trailer rules, and an active tracked canonical root cannot be
deleted. The trusted stable-promotion authorization from the base-owned
`pull_request_target` status and `qa/check_promotion_authorization.ps1` permits
only the exact approved stable directories and only after binding the
maintainer grant to the current PR head and MOD_VERSION; it never executes PR
code at the trust boundary and never exempts a runtime source delta.
This closes the PR #759/#765/#766/#767/#769 class where
source/version/config merged first and its compiled artifact followed later.

**Exact dirty-source and complete-output BuildOnly receipt (issues #1278/#1400).**
Every newly generated canonical root also carries `<mod>/.build-receipt.json`.
Immediately before and after the clean BuildOnly compile, `ship.ps1` fingerprints
the complete runtime-relevant input map as both the raw SHA-256 bytes Stingray
consumes and the Git-clean blobs that a later `git add` will commit. The raw
bytes must match the checkout bytes Git can materialize from those blobs; an
EOL/filter-only difference therefore fails instead of producing an unrepeatable
receipt. Clean-filter probes write any temporary addressable blobs only to an
isolated object store with no repository alternate; read-only receipt checks
must not add or freshen objects in the real Git database. Any in-build source
change aborts. Dot-prefixed and ignored
compiler-visible inputs belong to the map because VMB passes the whole mod
directory as Stingray's source directory. Only the exact bookkeeping file
`.build-receipt.json` is excluded from its own map.

Schema 3 binds that dual source map to one canonical ordinal inventory of the
complete normalized `bundleV2` output: every exact filename, byte length,
SHA-256, canonical root, source-qualified descriptor, aggregate fingerprint,
VMBLauncher version, and normalization-policy fingerprint. It has no timestamp
or dirty commit id. Every inventory row explicitly remains
`BundleAuthority = 'tracked'`; schema 3 shadows and strengthens existing tracked
parity rather than replacing it, while untouched schema-2 receipts remain
admissible during migration. Issue #1412 prepares the second exact mode,
`receipt`, without switching any active row. Issue #1426 adds only its
receipt-gated publication consumer; deploy, updater/recovery consumption, and
bootstrap remain disabled. Issue #1430 adds an additive durable recovery
record to new release entries only when the immutable publication snapshot has
an exact committed schema-3 receipt. That record is producer metadata, not a
historical resolver or restore authority; tracked schema-2/missing receipts
remain explicit legacy and receipt authority fails closed without the record.
Its contract and typed transitions are documented in
`docs/BUNDLE_AUTHORITY.md`. Pre-commit validates the exact staged index,
hosted QA validates the committed PR tree, and final ship compares the same
freshly normalized complete output set before the authority-specific parity
gate.
An extra, missing, renamed, changed, nested, reparse, case-colliding,
wrong-descriptor, wrong-root, builder-drifted, or policy-drifted output fails
closed. A source edit after BuildOnly therefore requires another BuildOnly run.
Root `.gitattributes` changes revalidate every receipt-bearing active mod
because they can change checkout materialization globally. `bundleV2` contents
are not source-map inputs because schema 3 binds them as the separate complete
output map. Exact inventoried SDK sidecars are removed through a handle-locked
name+SHA policy before enumeration; changed bytes remain for inspection.
Release-manifest and reproducibility checks consume the same output contract
rather than defining weaker competing file sets.

Two exact `itemV2.cfg` non-promotion metadata exceptions exist because VMB
BuildOnly proves that Workshop config is not compiled into `bundleV2`. For a
title synchronization, the title line must be the entire cfg diff,
`MOD_VERSION` must be unchanged from the merge base, and the new title must be
exactly `<unchanged base name> v<MOD_VERSION>`. For the mandatory first-upload
reconciliation, the sole cfg delta must be `published_id = 0L` becoming one
canonical positive ID; `MOD_VERSION`, title, and every other cfg byte must stay
unchanged, and a refreshed #1278 receipt must bind the assigned-ID cfg even when
the rebuilt root remains byte-identical. Any description, visibility, content,
other `published_id` transition, runtime, or newest-release identity change
still requires the canonical root bundle. The title boundary was planted after
WT 0.12.292-beta failed closed before Workshop upload on 2026-08-06: both WT
BuildOnly roots reproduced byte-identically, while the reviewed cfg title was
one version behind.

Tracked bundle deletion is a separate fail-closed boundary (issue #1100).
Deleting any `bundleV2/<16-hex>.mod_bundle` requires a newly added exact trailer
in that mod's newest CHANGELOG release:

```text
VT2-Bundle-Retirement: 0123456789abcdef.mod_bundle
```

Historical or previously committed trailers do not authorize a later deletion.
The `RootBundle` of an active `tools/mod-inventory.psd1` entry cannot be retired;
change the owning inventory/lifecycle explicitly instead. This prevents a clean
rebuild or merge resolution from silently staging deletion of a sibling bundle.

Do NOT downgrade a `-dev` update to deploy-only "to be safe". For a mod the
user is subscribed to, Steam re-syncs the Workshop bundle over any local
deploy, so the upload is the ONLY path that reaches the user's game; and
uncommitted shipped work piles up silently (three sessions' worth was found
uncommitted on 2026-07-01), so the commit + push is mandatory.

**Clean-versioned stable promotions (no pre-release suffix, regardless of the
stable item's current visibility):**
require a FRESH, explicit, per-build ship signal from the user that names the
version. "Ship it" said earlier does NOT carry forward. Default for these is
build + deploy only; treat the upload like `git push --force`. Full promote
checklist in § 6.5.

**Visibility is orthogonal to the suffix rule (user ruling 2026-07-04, closed
#328).** Workshop visibility (public / friends-only / private) is user-dictated
per item and carries NO ship-approval meaning: the MOD_VERSION suffix alone
decides whether a build ships without asking. A public item whose current
version carries a pre-release suffix (e.g. stable ct at `0.7.130-beta`, a
deliberate public beta) ships the full pipeline with no ask. Never infer,
"correct", or guard a visibility from the version, directory, or stream —
`-AllowPublic` is a purely mechanical flag, required whenever `itemV2.cfg`
says `public`. There is no suffix-vs-visibility contradiction to tie-break.

**Post-ship checks (both streams):**
- Confirm one fresh item-specific result in `workshop_log.txt`. Normally this is
  `Uploaded new content`. A receipt-gated `No content change` is also valid when
  canonical `ship.ps1` proved the exact reviewed staged bytes; the launcher's
  generic "Upload finished" text is never evidence by itself.
- **Publication-only mode (#1376/#1426):** canonical `ship.ps1` enters this mode
  when an existing item's real Steam-managed content directory is absent, or
  whenever its bundle authority is `receipt`. It must not create or write a
  missing Workshop directory, attempt local/remote deploy, or claim a deploy
  hash. Clean exact-default-head authorization, authority parity, the
  GitHub-hosted publication receipt, VMB staging validation, and the fresh
  Workshop result remain mandatory. To test afterward, the author must
  subscribe/refresh the item first; volunteers use the normal dev-collection
  unsubscribe/resubscribe refresh.
- Deploy verification is byte-exact for compiled `.mod_bundle` files and all
  non-descriptor artifacts. For textual `.mod` descriptors only, LF and CRLF
  line endings compare as equivalent because Steam may normalize them after a
  deploy; every other descriptor byte remains significant (issue #646).
- **`.mod` working-copy CRLF drift is NOT covered by that carve-out.**
  `.gitattributes` declares `*.mod text eol=lf`. The deploy-verify tolerance
  above applies only to the post-deploy Steam comparison. The publication
  receipt always binds exact source Git blobs. Tracked outputs additionally use
  `git-commit-blob-snapshot-v1`; receipt outputs bind the committed schema-3 map
  and locked materialized bytes. A CRLF working copy therefore disagrees with
  the selected output and fails closed. Before a ship, confirm the mod's `.mod`
  descriptors
  (both the root and the `bundleV2/` copy) are LF. Remaining drifted mods are
  tracked in issue #1085.
- A real deploy-verify mismatch after a CONFIRMED upload is a Steam reconcile
  race, not a ship failure: do one local re-deploy, then continue.
- Test refresh (user ruling 2026-07-13): after a subscribed ship, the author on
  PC-A uses the hash-verified local deploy without restarting Steam. After a
  publication-only ship, the author first subscribes/refreshes because no local
  deploy was claimed. Volunteer testers unsubscribe/resubscribe through the dev
  collection. Confirm every tester's loaded version from the newest console
  log.

---

## 7. Documentation standards

Documentation in this repo falls into three categories — **canonical** (long-
lived, tracked, every reader needs them), **reference** (long-lived, tracked,
specific topics), and **ephemeral** (snapshot or in-flight work, not tracked).
The rules below codify what goes where and how each type is maintained.

### 7.1 Canonical document map

The complete list of canonical docs and where each lives.

**Repo-wide canonical (every doc below is binding on Claude when working anywhere in the repo; topic references live under `docs/` since 2026-07-08, issue #432 - old root paths are pointer stubs):**

| Doc | Tracked? | Purpose | Update trigger |
|---|---|---|---|
| `CLAUDE.md` | Yes | Technical entry point — how the code works | Architecture changes; new mods; new cross-mod patterns |
| `PROJECT_STANDARDS.md` (this file) | Yes | Operational rules — how WE work | New recurring pain → new rule; old rule disproven → revise |
| `docs/LOCALIZATION_STANDARD.md` | Yes | VMF localization convention | Convention change; new pattern proven across ≥2 mods |
| `docs/CROSS_MOD_ARCHITECTURE.md` | Yes | How mods interact at runtime (LA bridge, co-install detection) | New cross-mod surface; new bridge pattern |
| `CHANGELOG.md` (repo root) | Yes | Repo-aggregate release notes | Per-mod CHANGELOG entries that affect multiple mods or the toolchain |
| `docs/REGRESSION_CHECKLIST.md` (repo-wide) | Yes | Master list of repo-wide regression signatures | New crash class survives more than one fix attempt |
| `STATUS.md` | Yes | Dated session history; never a current deployment, version, or verification instruction | Preserve historical evidence only; GitHub Issues §11 is the sole current status authority |
| `docs/BUG_TRIAGE_RUNBOOK.md` | Yes | THE entry point on any bug report (STEP 0-9 loop) | A step proves counterproductive on a real bug, or the ship/label contract changes |
| `docs/BUG_CLASSES.md` | Yes | Known bug patterns (symptom -> diagnosis -> fix template) | A novel bug is solved and has no matching class |
| `docs/MECHANICS.md` | Yes | Provenance-tagged index of VT2/Stingray mechanics | Any new mechanic claim; `qa/check_mechanics_citations.ps1` blocks untagged ones |
| `docs/engine/README.md` (+ `01..11_*.md`) | Yes | Per-subsystem engine reference with decompile `file:line` citations | New engine subsystem contact; per-mod `ENGINE_SURFACE.md` additions |
| `docs/PORTABLE_SETUP.md` | Yes | Launcher + `.vmbrc` resolution for ships from any checkout or linked worktree | Launcher relocation; new resolution override or worktree gate |
| `docs/WEAPON_CATALOG.md` / `ITEM_LIST.md` / `ANIMATION_RESEARCH.md` | Yes | Reference catalogs | When the underlying data changes (new weapon, new skeleton probe) |
| `docs/VMF_RECIPES.md` / `docs/COMMANDS.md` | Yes | Cross-mod reference (VMF gotchas, command inventory) | New VMF burn class; new chat command in any mod |
| `DEVELOPMENT.md` (repo root) | Yes | Historical architecture reference | Pre-dates CLAUDE.md; still authoritative for topics it covers |

**Per-mod canonical:**

| Doc | Required? | Purpose |
|---|---|---|
| `CHANGELOG.md` | **Mandatory, every mod** | Per-mod version history (§6.4 format) |
| `REGRESSION_CHECKLIST.md` | **Mandatory, every mod** | Per-mod subset of repo-wide checklist + mod-specific regressions |
| `CODE_REVIEW.md` | **Mandatory for every mod whose current `itemV2.cfg` says `visibility = "public"`**; optional otherwise | Snapshot architectural review |
| `CLAUDE.md` (per-mod) | Optional | Workflow guardrails specific to that mod (only when the mod has non-obvious gates — see `dynamic_cosmetic_portraits/CLAUDE.md`) |
| `DEVELOPMENT.md` (per-mod) | Optional | Mod-specific architecture (use when the mod has system-level docs that don't fit in the main lua's header docstring) |
| `RECIPES.md`, `<TOPIC>_PLAYBOOK.md`, `DEFINITION_OF_DONE.md`, `ENGINE_SURFACE.md` | Optional | Reference docs for recurring authoring tasks within the mod (`ENGINE_SURFACE.md` = the mod's per-hook map onto vanilla engine behavior, companion to `docs/engine/`; template lives in `character_weapon_variants/`. All 7 high-contact mods carry one as of 2026-07-12 - the series index is the "Per-mod surface docs" table at the bottom of `docs/engine/README.md`) |
| `TODO.md` | **Discouraged** | Use GitHub Issues per §11 instead |
| `POSTMORTEMS.md` | Created on first incident | Rolled-up post-incident records — see §7.3 |

The `visibility` field in each active mod's `itemV2.cfg` is the only authority
for public/friends-only/private state. Do not maintain a copied mod list here;
it drifts as soon as the user changes Workshop visibility. If a cfg changes to
`public`, create or refresh `CODE_REVIEW.md` in the same change. If it moves away
from public, retain the review as dated history rather than deleting evidence.

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

**POSTMORTEMS.md is NOT snapshot-class (ruling 2026-08-02).** Per-mod
`POSTMORTEMS.md` files are append-only incident logs — CHANGELOG-class, every
entry carries its own date. A quiet month means no new incidents, not
staleness, so they are exempt from the `qa/check_stale_docs.ps1` staleness
ratchet and must never receive a SUPERSEDED banner or be moved to `_archive/`
while their mod is active. The checker excludes `POSTMORTEM*.md` by pattern.

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
- **At architecture change:** CLAUDE.md, docs/CROSS_MOD_ARCHITECTURE.md as relevant.
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

### 7.10 Deprecation lifecycle (docs, toggles, APIs)

Retirement is a three-stage pipeline, never a silent delete (added 2026-07-08,
issue #432 - previously ad hoc: bt, lobby_tweaker, la_prefix_patch each retired
differently).

**Stage 1 - Superseded.** The replacement exists and is named. Add the §7.5
SUPERSEDED banner (the word SUPERSEDED must appear in the first 10 lines -
`qa/check_stale_docs.ps1` keys on it) pointing at the new owner. Content stays
readable in place. For a settings toggle, the analogue is a CHANGELOG/GitHub
entry naming what replaces it; for a cross-mod API, the provider keeps
the old entry point returning inert values so consumers that guard (the
`(get_mod('bt') or {}):is_br_active()` pattern) degrade without crashing.

**Stage 2 - Stubbed.** Once nothing SHOULD read the old surface, reduce the doc
to a ~5-line pointer stub (banner + new home + where the full text lives).
Before stubbing, copy the full text to `_archive/<area>/<date>_<topic>/`
(gitignored - snapshots are not source of truth) AND to the durable external
archive `C:\Users\danjo\source\repos\_vt2-tweaker-archive\<date>\`; git history
keeps the tracked record. A stubbed toggle is removed from `_data.lua` but its
`setting_id` is never reused; a stubbed API keeps the guarded no-op shim.

**Stage 3 - Archived / removed.** When grep shows no inbound references left
(or the referencing docs are themselves archived), delete the stub in a commit
whose message names the new home (§7.5 rule). Mods retire the same way: mark
RETIRED in the Mod Directory + `MOD_OWNERSHIP.md`, archive the tree to
`_archive/` + the external archive, and verify every consumer guards before the
Workshop item is pulled.

Never skip a stage to "clean up faster" - stage 2 exists because commit
messages, memory files, and Workshop descriptions keep linking the old path
long after the content moved.

### 7.11 Doc process: keeping docs non-contradictory (issue #432)

The #432 audit found 6 live contradictions, 8 stale claims, and the same fact
restated (uncited) across up to 5 docs. Those all trace to one root cause: a
fact written in two places drifts, and a claim with no date cannot be told from
a current one. The rules below are the standing process that stops it recurring;
they bind the same as the rest of section 7.

1. **One owner doc per topic.** Every fact has a single home, listed in the
   section 7.1 canonical map (repo-wide) or the mod's own doc set (per-mod). A
   new doc names in its first lines the ONE topic it owns; if that topic already
   has an owner, extend the owner instead of opening a second surface.
2. **Facts live in the owner; everyone else cites.** Do not restate an owner
   doc's content in another doc - link to it (`docs/X.md` section N). A copy is
   a future contradiction: when the owner changes, the copy silently lies. If
   you catch yourself pasting a rule, replace the paste with a pointer.
3. **Dated and quantitative state claims carry their date.** Any claim true only
   at a moment - counts ("13 files over the limit"), "all N cfgs pass", "as of
   promotion", a per-mod status - is written with the date it was true
   (`... (2026-07-08)`) so a later reader sees its age. An undated count reads as
   eternal and is the staleness the audit kept finding. A current-state
   reference doc SHOULD carry a `Status as of YYYY-MM-DD` masthead and bump it
   whenever its body is touched.
4. **Current status lives only in GitHub Issues.** `STATUS.md` is dated session
   history, not a second live board. No other doc restates issue status or a
   task queue; it cites the issue number. Existing `TODO.md`, `WORK_ITEMS.md`,
   and `TESTING_STATUS.md` content is historical/reference material only and
   must carry that banner. This is the worked example of what status
   fragmentation rots into - do not recreate that shape anywhere.
5. **Retire by the section 7.10 lifecycle, never by silent delete or silent
   edit.** Superseded -> stubbed -> archived. A moved doc leaves a pointer stub
   whose link stays resolvable (`qa/check_stale_docs.ps1` scan 3 flags a stub
   linking a missing owner).
6. **On a contradiction, the owner wins.** Precedence is CLAUDE.md >
   PROJECT_STANDARDS > topic docs (the global prefs restate this). When two docs
   assert the same fact and differ, fix the non-owner to a citation of the owner
   in the same pass - do not leave both readings live for a later reader to
   arbitrate.

Automated backstops (advisory - they surface rot but never block a commit):
`qa/check_stale_docs.ps1` (time-based staleness on audit/review docs, snapshot-
banner placement per issue #502, and pointer-stub link integrity per issue #432),
`qa/check_mechanics_citations.ps1` (provenance on every MECHANICS fact,
section 12a), and the section 7.1 owner map itself. The scanners catch mechanical
drift; rules 1-6 are the human discipline they cannot enforce.

---

## 8. Workflow standards for Claude

### 8.0 Bug-report intake

When the user opens a session with a bug report (log path + symptom), the
first read is `docs/BUG_TRIAGE_RUNBOOK.md`, not the mod source. The runbook
is the 60-second orientation: Phase 1 (log + git log + open Issues), Phase 2
(match against `docs/BUG_CLASSES.md`), Phase 3 (deep-dive log signatures),
Phase 4 (fix with apply-site log + `_rt_register` + `/verify_<feature>` +
Workshop upload + GitHub release), Phase 5 (catalog the bug class +
POSTMORTEMS entry + lint follow-up). Cross-refs every rule in this doc that
applies (§ 3.6, § 4.2, § 5.1a, § 6.4, § 7.7, § 8.1, § 8.2, § 8.3, § 8.6,
§ 9.x anti-patterns, § 11 Issues, § 15 tests).

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

### 8.5a Pre-commit hook + `--no-verify` escape hatch

Established 2026-05-25 alongside `tools/install-hooks.ps1` (Issue #29). After cloning the repo, run `./tools/install-hooks.ps1` to install the local pre-commit hook. It first runs `qa/check_diff_whitespace.ps1 -Staged` against every non-empty staged patch, including docs/assets, then runs `qa/run_all.ps1 -Quick -SkipLua` and `tools/mod-lint/lint-mod.ps1` for staged `*.lua` / `*.cfg` / `*.ps1` / `*.mod` files. This keeps trailing whitespace, cfg drift, MOD_VERSION / title-suffix typos, duplicate hook registrations, and the other recurring bug classes catalogued in § 11a out of committed history. The installer is idempotent; only the heavier code gates self-disable for commits that touch no checked extensions. Hosted pull-request QA independently runs `check_diff_whitespace.ps1` on the explicit merge-base/base-to-head range, so committing a defect cannot hide it from a clean worktree.

**Gates block on ERRORS only.** A gate that finds an error fails the commit; WARNINGS print but do not block (this is the behavior a parallel `qa/run_all` change is landing). So the source commit + push that is part of every ship (§ 6.6) proceeds cleanly whenever the checks surface only advisory warnings; it does not get stuck behind a warning.

`git commit --no-verify` bypasses the hook for one commit. **Use it ONLY when a gate is itself wrong or out-of-scope for the change, and cite the reason in the commit message** so future-me can audit the override (`workshop-stage cfg rewrite already validated by VMBLauncher`, `lint false positive on <file>`, etc.). Prefer FIXING the gate over bypassing it. Never `--no-verify` to "fix on push" to dodge a real error; the GHA workflow runs the same checks and will block the merge anyway.

### 8.6 The "I'm about to add a defensive guard" gate
Before writing `if not X then return end` in a hook, answer in a comment:
1. What failure mode does this prevent?
2. What's the citation (CHANGELOG entry, crash GUID, vanilla source line)?
3. What does vanilla NORMALLY do here that this guard now skips?
4. Is skipping that mutation safe, or am I creating a new bug?

If you can't answer 1-4, DON'T add the guard.

### 8.7 Session hygiene: close out before ending (binding, 2026-07-18)

A session ends CLEAN or it does not end. Three closeouts are mandatory before
handing off; each traces to a state left dirty overnight that cost the next
session's start.

1. **Git operations resolved.** Never leave a conflicted cherry-pick, rebase, or
   merge in the tree overnight. A 15-file conflicted cherry-pick left mid-flight
   blocked the entire 2026-07-17 session start: no real work could begin until it
   was unwound. If a merge or cherry-pick cannot be completed cleanly, abort it
   (`git cherry-pick --abort`, `git rebase --abort`, `git merge --abort`) and
   re-open the remaining work as a GitHub issue per §11, rather than parking the
   index in a conflicted state a later session inherits blind.
2. **VMBLauncher `ProjectRoot` restored to the monorepo.** After any manual GUI
   worktree
   retarget, point `ProjectRoot` back at the monorepo root. Never leave it pinned
   to a worktree whose branch has already merged: the `vt2-cim-promo` pin was
   left live after its branch merged, and only `ship.ps1`'s provenance gate
   caught it before a stale-tree ship went out. The provenance gate is the
   backstop, not the plan; restore the root yourself as part of closing the
   worktree. Canonical ship does not retarget this shared setting: it uses one
   private exact-root `--config` and deletes it in `finally`.
3. **Absorbed remote branches deleted.** Once a branch's PR merges, delete the
   remote branch in the same pass. 57 merged-but-undeleted branches accumulated;
   the dead branches bury the handful a session actually needs to reason about
   and make the branch inventory untrustworthy.
4. **Linked worktree closed.** Read-only tasks do not create worktrees. Isolated
   write worktrees are created and closed only with
   `tools/worktrees/worktree.ps1`, and a finished agent's tree is closed in the
   same session after its source is committed. Invoke Close from the primary
   checkout, never from inside its target on Windows. The wrapper refuses dirty
   source and ambiguous ignored files. On 2026-07-30, 707 registered worktrees consumed
   hundreds of GiB; the recovery pass reclaimed at least 323.81 GiB. The binding
   budget is 8 secondary trees / 12 GiB, enforced by
   `qa/check_worktree_budget.ps1` in Quick QA, pre-commit, full QA, and ship
   preflight.
5. **QA is invariant to valid nested worktree placement.** Repository scanners
   MUST discover active mods from `tools/mod-inventory.psd1` (or another named
   canonical root list), not by recursively treating arbitrary top-level
   directories as mods. A registered checkout under `.claude/worktrees/` is
   another workspace, not a pseudo-mod, and must not create duplicate findings
   or require deletion before exact-master QA. `check_command_collisions.ps1
   -SelfTest` plants this regression shape under both supported PowerShell hosts.

Cross-ref: §6.5 / §6.6 (ship pipeline + protected-`master` landing), `CLAUDE.md`
NON-NEGOTIABLES (worktree / VMBLauncher discipline).

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

### 9.9a RPC payload without a schema gate

**Symptom**: host and client (or two peers) disagree on the positional shape
of a mod-defined `mod:network_send` payload, the receiver parses by position,
writes the wrong fields into local state, mod misbehaves with no log trace
pointing at the real cause. Likelihood scales with multi-build-per-day dev
iteration (host running latest dev, friend running stale Workshop bundle).

**Root cause**: implicit schema. The wire format is whatever the sender
happens to emit positionally; a receiver compiled against a different sender
shape has no way to know.

**Fix**: every mod that ships its own RPCs declares a `<MOD>_RPC_SCHEMA = N`
constant near `MOD_VERSION`. The constant is prepended as the FIRST positional
arg of every `mod:network_send`, validated as the first arg of every
`mod:network_register` callback, and on mismatch the receiver drops the
message with `_dbg_alert("[rpc:schema] <channel> mismatch ...")`. Graceful
degradation in both cross-version directions. Bump only when the payload
shape changes; one constant per mod across all the mod's RPCs.

Pilot: chaos_wastes_tweaker v0.7.114-dev (3 RPCs gated). Pattern + when-to-
bump + adding-new-RPCs + anti-patterns in `docs/VMF_RECIPES.md § 10`. Follow-up
Issues propagate to cosmetics_tweaker, lobby_tweaker, enemy_tweaker,
crafting_in_modded, general_tweaker — track via GitHub Issues, not eager
churn.

### 9.9 Multi-return collapse via implicit `#t`

**Symptom**: a hook wrapper captures a wrapped call's tuple via
`local results = { f(...) }` and re-emits via `unpack(results)` or
`unpack(results, i)` without an explicit `j`. When the wrapped function
returns nils anywhere in its tuple (e.g. `GearUtils.spawn_inventory_unit`
returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` with `ammo_*` nil for
melee weapons), Lua 5.1's `#results` is **undefined** — it's a binary
boundary search over the array part, so the truncation point is
non-deterministic. Downstream consumers see randomly-nil unit handles.

**Root cause**: assuming `#table` is well-defined. It isn't, for arrays with
nil holes — see `CLAUDE.md` § "High-frequency engine quirks". The bug
silently propagates: the wrapper looks correct, the immediate caller sees
"sometimes" the right values, and a chained `mod:hook` consumer downstream
re-emits the corrupted tuple further.

**Fix**: When intercepting a function that may return nils anywhere in its
tuple, you MUST capture the count via `select("#", ...)` from the source
variadic, and pass `j` explicitly to `unpack`:

```lua
local function _capture(...) return select("#", ...), { ... } end
local n, results = _capture(xpcall(handler, _err_handler, func, ...))
return unpack(results, 2, n)   -- explicit j preserves nil holes
```

Pattern + extended example in `docs/VMF_RECIPES.md § 2a`. Burned twice on the
same fix in 2 hours (weapon_tweaker v0.12.77 → .78 → .79 cycle on
2026-05-25). The new `mod:safe_hook` helper introduced in v0.12.77 was
itself an instance of the bug class warned about in the repo's own
`docs/VMF_RECIPES.md § 2` — the helper failed to apply its own repo's recipe.

Cross-refs:
- `CLAUDE.md` § "High-frequency engine quirks" — short-form bullet on the
  underlying `#table` quirk.
- `docs/VMF_RECIPES.md § 2a` — full recipe, burn history, canonical 4-return
  example.
- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — the helper
  whose v0.12.79 fix carries the canonical pattern in code.

---

## 9a. Cross-mod public API compatibility (binding; added 2026-07-08, issue #432)

Applies to every surface another mod may consume: gut's
`mod_tweaker:{register_category, get, set, ...}` registration API, the
(retired) bt shared-registration pattern, mp's sibling API, presence flags,
and the copied `_lib_*.lua` shared libraries. The registry of live surfaces
is the "Exposed APIs" table in `MOD_DEPENDENCIES.md` - every public surface
MUST have a row there before a consumer wires against it.

**Never break consumers.** Once a function is on a public surface, its name,
signature, and return shape are frozen. Evolve additively: new capability =
new function, or optional trailing parameters with safe defaults. A consumer
built against version N must keep working against N+1 unchanged.

**Consumers gate; providers degrade.** Consumers follow the
`MOD_DEPENDENCIES.md` gating convention: nil-guard every `get_mod(...)`
deref, treat absence as the safe default, resolve only the STABLE mod_id
(never `*_dev`). Providers retiring a surface follow §7.10: Stage 1 keeps
the old entry point returning inert values so guarded consumers degrade
without crashing (the `(get_mod('bt') or {}):is_br_active()` pattern is the
worked example - bt retired with zero consumer crashes); Stage 2 keeps a
guarded no-op shim; API names, like setting_ids, are never reused.

**Versioning.** Networked cross-mod channels carry an explicit schema
version with drop-on-mismatch (`docs/VMF_RECIPES.md` §10 is the canonical
recipe). Non-networked surfaces need no version constant while evolution
stays additive; if a breaking change is ever unavoidable, ship it as a NEW
surface name and retire the old one per §7.10 - do not repurpose in place.

**`_lib_*.lua` copied libraries** (the standalone invariant forbids runtime
`get_mod` deps between our mods): the master lives in `tools/shared_lib/`;
per-mod copies are verbatim and are NEVER edited locally - edit the master,
then re-copy to every consumer in the same pass. A mod needing divergent
behavior gets a differently-named fork, not a silently drifted copy. Each
lib's header names its master path so drift is detectable by diff.

**Copied-lib install transactions** (binding; #371/#1158). A shared lib whose
`install()` has more than one side effect - registering a network receiver AND
taking ownership of `mod.update` is the worked example
(`tools/shared_lib/_lib_peer_parity.lua`) - performs them inside ONE `pcall`,
commits its installed flag only after all of them return, keeps any externally
reachable callback inert until that commit, restores the exact previous value of
anything it overwrote if the transaction throws, makes a failed attempt TERMINAL
for the instance (a retry could double-register a receiver the transport already
retained), and RETURNS the commit boolean. Consumers must consume that boolean:
a factory that returned a table is not evidence the transport took the channel.
Safety queries on the instance hard-gate on the same commit flag, so an
uninstalled instance is fail-closed by construction rather than by caller
discipline.

---

## 9b. Pusfume non-interference (binding; user directive 2026-07-21)

Pusfume is an externally owned compatibility target. Tweaker-family mods must
not disable, rewrite, shadow, or assume ownership of Pusfume's career, profile,
loadout, assets, packages, synchronized identities, or project configuration.
The user-designated Pusfume project-manager Sol instance owns Pusfume changes;
Tweaker work stays in this repository unless that manager explicitly requests a
cross-repository change.

Generic Tweaker hooks must preserve unknown/additional careers and call-chain
behavior. If an optional Tweaker feature conflicts with Pusfume, the Tweaker
feature yields or degrades to its vanilla behavior; it must not make Pusfume
unselectable, unspawnable, invisible, or unsafe for peers. Direct Lua references
to `pusfume` require an adjacent `pusfume-compat-reviewed` annotation and review
against `docs/CROSS_MOD_ARCHITECTURE.md`; `qa/check_pusfume_compatibility.ps1`
enforces that review boundary and the presence of this doctrine.

Any change touching career enumeration, profile/career indices, loadout or
backend adapters, package ownership, player-unit spawning, or synchronized
registration must run the Pusfume compatibility matrix in
`docs/REGRESSION_CHECKLIST.md` before release. No compatibility claim is valid
from static inspection alone.

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
- Candidates: `verminious_dreams_lighting` (per audit findings).
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
3. When work ships, keep the issue open under its validated verify lifecycle.
   Close only after the named human/autonomous verification passes and the
   post-fix hardening pass is complete (or explicitly documented not applicable).
4. Run `gh issue list` at the start of a session if you want a picture of
   what's open before diving in.

### Issue format (binding, user directive 2026-07-06)

Issues had drifted verbose (e.g. #373: 551-word body, 30-word title). The user
reads issues as a test queue across multiple agents; padding wastes his tokens.

- **Title: 8 words max** after the `[mod]`/`mod:` prefix. Detail goes in the
  body, never the title.
- **Body: empirical data only, ~150 words target.** Sections, each 1-3 lines,
  skip any that are empty:
  - `**Symptom:**` what happens, where (mission/menu/weapon).
  - `**Evidence:**` log lines, `file:line` citations, repro steps. Data, not prose.
  - `**Fix:**` one line of direction. ONE leading hypothesis; name an alternative
    only if the fix differs.
  - `**Refs:**` bare `#N` list, no relationship essays.
- **Markdown transport is binding:** submit multiline bodies with
  `gh issue create/edit --body-file <file>` or `--body-file -` and real line
  breaks. Never pass a quoted string containing escaped `\n`; GitHub renders
  those characters literally and can turn the whole body into one malformed
  heading. Use the bold inline labels above, not `##` section headings.
- **Cut entirely:** restating the title, "Grounding"/background narrative,
  hedging (`[unverified]` on a hypothesis line is enough), meta-commentary,
  multi-paragraph hypothesis walkthroughs.
- **Routine ship comments follow the same rule:** version stamp + what shipped +
  how to test. The evidence/fallback comment below is the explicit exception.

### Three empirical fallback paths (binding, user directive 2026-07-16)

Every open issue must document three next attempts that remain available if the
current fix or diagnostic fails. Keep them in one compact issue comment rather
than inflating the issue body. A fallback is a testable path forward, not a claim
that its root cause is true: every entry names the evidence that would trigger
it, the bounded change/probe, and the observation that would falsify it.

```markdown
**Fallback 1**
- **Evidence/trigger:** `<observed log/repro/source condition>`
- **Change:** `<bounded corrective change or diagnostic probe>`
- **Falsifier:** `<result that rules this path out>`

**Fallback 2**
- **Evidence/trigger:** `<observed log/repro/source condition>`
- **Change:** `<bounded corrective change or diagnostic probe>`
- **Falsifier:** `<result that rules this path out>`

**Fallback 3**
- **Evidence/trigger:** `<observed log/repro/source condition>`
- **Change:** `<bounded corrective change or diagnostic probe>`
- **Falsifier:** `<result that rules this path out>`
```

Do not invent a third root cause to fill the template. If current evidence
cannot justify another corrective change, write `insufficient evidence` in the
trigger and make the **Change** a bounded probe that distinguishes candidate
paths. Promote that entry to a proposed fix only after the probe supplies the
named evidence.

### Labels (canonical taxonomy — do NOT invent new status labels)

Every issue carries three dimensions: **status + type + mod**. Nothing else is a
status. This was ad-hoc "wild west" through 2026-07-03 (four overlapping status
labels, features untagged, `et`/`enemy` duplicated); the scheme below is the fix.

**Status (exactly 1 of these on every OPEN issue) — the lifecycle signal:**
- `not-started` — the issue is not ready for live in-game testing. This is the
  default for every newly filed, partially implemented, blocked, repository-only,
  and otherwise unready issue.
- `diagnostics-armed` — a bounded diagnostic is deployed and can be run in VT2
  now using the current live-test card.
- `verify-fix` — a complete candidate fix is deployed and can be verified in
  VT2 now using the current live-test card.
- `Fixed` and `verify-fix-coop` are invalid on OPEN issues. Verified work is
  hardened and closed; co-op readiness is expressed with `coop-required`.
- **Live-test card prerequisite:** before applying `diagnostics-armed` or
  `verify-fix`, post a high-visibility comment whose heading is exactly
  `## CURRENT LIVE TEST`, pin that comment, and unpin every older exact card.
  The newest exact card must be the one and only pinned exact card; a ready issue
  with an unpinned newest card or multiple pinned exact cards fails policy. It must
  include `Build/banner:` where every named build has an explicitly bound semantic
  version and either `[mod:LOAD]` or a clearly labeled exact versioned banner (for
  example, `exact banner: [WOC] v0.1.42-dev loaded`). Each build/version/tag pair
  must match exactly one row in the latest deployed release manifest and its
  recorded exact source commit; dirty, ambiguous, duplicate, and version-drifted
  release identities fail closed. Unbound sibling versions/tags are invalid.
  Workshop item/ManifestID coordinates are optional; if either is supplied, the
  complete pair must be unique and its item must belong to the selected build.
  A line explicitly headed `Current receipt`, `Current <stream> receipt`,
  `Exact live artifact`, `Live artifact`, or `Exact source` is also a deployed
  claim: every source commit, root bundle/SHA-256, and release ZIP/SHA-256 named
  there must match that selected build's latest release-manifest row. Partial,
  ambiguous, or unexplained artifact hashes fail closed. A line headed exactly
  `Feature provenance` is immutable historical evidence, not a claim about the
  current deployment; untyped evidence headings are likewise never inferred or
  rewritten as current artifact authority.
  The card also needs `Topology:`
  (`Solo` or `Co-op`), numbered player-facing steps, and `Expected:`. Numbered
  steps use localized names players see in-game, never internal snake-case keys.
  Exact player-entered slash commands are allowed when wrapped in backticks and
  registered by the deployed source. When a `diagnostics-armed` card asks for log
  evidence, its numbered steps or Expected line must name one exact stable
  receipt prefix or field route emitted through raw engine `printf`, directly or
  through a conservatively proven one-hop binding, by that source. A marker alone
  is accepted as a stable prefix only when every exact deployed route in that
  marker family is individually finite; one unbounded sibling invalidates the
  family-wide claim. A later bare reference to "the `[marker]` line" resolves to
  one exact route only when that same card quotes exactly one route for the
  marker. A discriminating authored literal prefix may select a route subgroup
  only when every selected exact route is finite. Each route is finite only
  because it is a direct, loop-free emitter in an explicit command callback or
  because an immutable deployed-tree override pins its literal emitter and guard
  tokens. A command-owned receipt is valid only when the card runs that exact
  owning command; another registered command cannot lend it reachability.
  `goto` invalidates the simple loop-free proof, literal-false branches do not
  register routes, and raw `printf` trust applies to the complete deployed
  record: any source file that mutates the global or ambient-environment logger
  invalidates it. Nearby prose, strings/comments, fake-printf names, and
  marker-wide sibling emitters prove nothing. A native-chat disclaimer may
  exclude a marker only when it does not also require that marker to appear.
  An incomplete newer card invalidates an older valid card; issue-body text and
  legacy method headings are not fallbacks.
  The authoritative, machine-checked definition of this format is
  `tools/verify/lifecycle_method_policy.ps1` together with
  `tools/verify/live_test_contract.ps1`; `tools/ship/ship.ps1`,
  `tools/verify/generate_playtest.ps1`, and
  `tools/github/check-lifecycle-cardinality.ps1` all consume it. When prose here
  and those scripts disagree, the scripts win — fix the prose. The GitHub guard
  resolves the latest release manifest and tokenizes Lua from its exact immutable
  source commits with blob-filtered full history. The two visible legacy
  carry-forward rows lacking `source_commit` are bound to reviewed root/mod tree
  object IDs; the working tree is never substituted. During the staged rollout,
  the repository-wide guard reports deployed-source/card findings without adding
  them to blocking lifecycle errors, so existing ready cards do not create a
  release cliff. Canonical ship enforces that authority strictly before any new
  ready-label transition, and `refresh-cards.ps1` enforces it before rewriting a
  pinned card. Once the reported backlog is repaired, the global enforcement
  switch may be enabled deliberately.
- **Solo first:** `coop-required` is valid only beside `diagnostics-armed` or
  `verify-fix`, with a `Topology: Co-op` current card whose `Solo status:` says
  the useful solo stage passed/completed or was exhausted. Do not add it while
  any useful solo test remains. A solo card must not carry `coop-required`.
- **Blocked exclusion:** `blocked` requires `not-started` and forbids
  `diagnostics-armed`, `verify-fix`, and `coop-required`.
- **Tooling exclusion:** documentation, QA, and repository-only work never use
  live-test labels. Keep them `not-started` while open, verify autonomously, and
  close directly with evidence.
- **Complete-feature prerequisite (user rule 2026-07-12, set on issue #505):**
  `verify-fix` NEVER goes on a partially-delivered feature. If any spec item is
  unbuilt (deferred sub-feature, blocked dependency, "part 2 in flight"), the
  issue stays `not-started` until the spec is complete or the user
  explicitly re-scopes it - a tester filtering verify-fix must find only things
  that can pass in full. Partial progress lives in comments, not the label.
- **Verified closure:** human confirmation by the user or designated playtester
  RainReligion is first-class verification input. After verification, harden the
  path, update the owning prevention docs, add regression coverage, and close.
  If the evidence does not verify the fix, return it to `not-started` or post a
  replacement current card for the next genuinely ready diagnostic/test.
- **Retired 2026-07-03:** `verify-in-game` → merged into `verify-fix`; `probe-live` →
  merged into `diagnostics-armed`. Do not recreate them.
- **Retired for OPEN issues 2026-07-21:** `Fixed` and `verify-fix-coop`. `Fixed`
  still exists in the repo's label set and closed history may retain it as
  evidence; `verify-fix-coop` has since been DELETED outright (verified absent
  from `gh label list` 2026-08-02), so any doc or comment naming it is a legacy
  parse target only — a `--add-label verify-fix-coop` call now hard-errors. Use
  `verify-fix` plus `coop-required`.
- `qa/check_issue_status_labels.ps1` pass 3 sweeps all open issues and warns on
  zero/multiple canonical lifecycles or any retired lifecycle mixed with a
  canonical one (advisory, issue #498). The blocking CI cardinality guard rejects
  the same states.

**Type (exactly 1):**
- `bug` — something is broken.
- `enhancement` — improve an existing feature, OR a chore / refactor / audit task.
- `feature` — a new capability or system that does not exist yet.
- `crash` is a **severity flag layered on `bug`** (a crash issue carries BOTH `bug`
  and `crash`), not a separate type.

**Mod (1+) — DISPLAY-named, not internal ids.** The live labels are:

| Label | Mod |
|---|---|
| `Tweaker: Chaos Wastes` | `chaos_wastes_tweaker` (`ct`) |
| `Tweaker: General` | `general_tweaker` (`gt`) |
| `Tweaker: GUI` | `gui_tweaker` (`gut`) |
| `Tweaker: Weapons` | `weapon_tweaker` (`wt`) |
| `Tweaker: Cosmetics` | `cosmetics_tweaker` |
| `Tweaker: Enemies` | `enemy_tweaker` |
| `Tweaker: Events` | `event_tweaker` |
| `Tweaker: Career` | `career_tweaker` (`crt`) |
| `CWV` | `character_weapon_variants` |
| `WOC` | `weapons_of_chaos` |
| `dcp` | `dynamic_cosmetic_portraits` |
| `Character Dialogue` | `character_dialogue` |
| `Progression` | `modded_progression` (`mp`) |
| `cim` | `crafting_in_modded` |
| `cross-mod` | spans multiple mods |
| `tooling` | qa / build / repo tooling |

The eight `Tweaker: *` labels carry their internal id in the GitHub label
description (e.g. `Tweaker: GUI` → "[gut] ..."), so a `--label gut` call fails.
Pass the display name verbatim, quoted. Confirm with `gh label list --limit 60`
before a batch edit rather than trusting this table; it is a snapshot.
(`et` retired 2026-07-04 → split into `Tweaker: Enemies` + `Tweaker: Events`: the
single `et` label was ambiguous between the two `*_tweaker` mods — its GitHub
description said event_tweaker while a 2026-07-03 merge had repurposed it onto
enemy_tweaker issues. Do NOT recreate `et`. The short lowercase ids `ct` / `gt` /
`gut` / `wt` / `cosmetics` / `enemy` / `event` / `crt` / `mp` are likewise gone —
do not recreate them either.)

**Priority (exactly 1 on every open issue):** `0-critical` (crashes /
game-breaking; do next), `1-major` (really needed or wanted badly), `2-moderate`
(standard fix; the default — most issues land here), `3-low` (later / minor /
small, often vanilla, bugs). A `crash`-flagged bug is `0-critical`.

**Optional modifiers (informational, never a substitute for a type, priority, or
lifecycle):** `regression` (a fix that broke a working feature), `audit`,
`refactor`, `blocked`, `deferred`, `coop-required`, `architecture`,
`vanilla-bug`, `stable-promotion-approved`. `coop-required` is a live-test
routing qualifier, never a lifecycle or a substitute for the solo-first proof in
the current card. `vanilla-bug` marks a defect that exists in the official game —
we work around it rather than owning it, so it caps expectations on a fix and
usually pairs with `3-low`. `stable-promotion-approved` is NOT informational
housekeeping: it is the maintainer-granted, version- and head-SHA-bound
authorization consumed by `qa/check_promotion_authorization.ps1` (§6.6 atomic
source/root-bundle gate). Never add or re-add it by hand to keep a promotion PR
green — removing and re-granting it is the documented revocation path, and a
grant edited after the fact fails closed.

When you ship a fix or diagnostic, add the matching status label and remove every
competing/retired lifecycle in the **same pass** as the CHANGELOG entry. Filing a
new issue: give it type + mod + `not-started`; enter the live-test queue only
after the current card and deployment are ready.

**Mechanized (issue #326).** `tools/ship/ship.ps1` step 6 parses the `#N` refs
from the shipped CHANGELOG entry, but it mutates no issue unless the header names
exactly one explicit lifecycle marker: `[not-started]`, `[verify-fix]`, or
`[diagnostics-armed]`/`[diag]`. Before any issue mutation it validates the newest
exact current card through the shared policy. Co-op routing comes from that card;
stale `coop-required` is removed on a solo or non-ready target. `[docs]` and
`[tooling]` entries never auto-label issues. A
verify-to-diagnostics downgrade is blocked unless the selected replacement method
cites failed-verification evidence. A validated transition receives an evidence
comment, adds its target, and removes competing/retired lifecycles in the same
edit. Loc sweeps, missing/ambiguous intent, invalid methods, closed issues, and
non-issues are skipped without mutation. The advisory local scan and blocking CI
cardinality guard backstop the transaction.

### Tracker lifecycle discipline (binding, issue #750)

A 2026-07 out-of-repo reconciliation sweep ran targeted `gh issue edit
--remove-label` calls: each lifecycle label was removed alone (no paired add, no
comment), leaving 10 open issues bare and downgrading verified fixes blindly.
These rules prevent a repeat; the CI guard below makes the bare state
un-mergeable.

| Rule | Detail |
|---|---|
| One edit, add-then-remove | Every lifecycle change goes through `tools/ship/ship.ps1` `Get-ShipIssueTransitionDecision` / `Get-LifecycleEditPlan` or an equivalent single `gh issue edit` that adds the target label AND removes every competing lifecycle label together. A bare `--remove-label` on a lifecycle label with no paired add is forbidden. |
| Never leave an issue bare | Cardinality stays exactly 1 on every open issue at every instant. If no live test is ready, use `not-started`. |
| Never downgrade without failed-verify evidence | `verify-fix` may move to diagnostics only when the replacement current card cites failed verification. Otherwise move unready work to `not-started`. |
| Comment every change | Each lifecycle edit gets an issue comment naming the evidence that drove it (shipped version, failed-verify log, user confirmation). An uncommented label change is presumed wrong and gets reverted to the last evidenced state. |

**CI enforcement:** `tools/github/check-lifecycle-cardinality.ps1` runs as a
blocking step in `.github/workflows/qa.yml` and `.github/workflows/issue-lifecycle.yml`
(contents:read + issues:read only). It pages open issues and fetches complete
comment history only for ready issues through GraphQL so `IssueComment.isPinned`
is authoritative. Ready-issue comment connections are read in batches of at
most 20 aliases per request; any connection beyond 100 comments remains
cursor-paginated to completion. This preserves full pin evidence without the
one-network-round-trip-per-issue timeout that recurred on 2026-08-13. The
GraphQL transport retries only recognized TLS, connection,
timeout, rate-limit, and HTTP 5xx failures on a bounded 2/5/10-second schedule;
authentication, schema, and exhausted transport failures still fail closed. The
offline self-test pins both classifications and the retry bound. The dedicated
lifecycle checkout retains blob-filtered full history for exact deployed-source
authority, uses non-cone sparse patterns for `qa`, `tools`, and each current
`*/scripts/mods/` tree, and therefore hydrates the commonly shared Lua blobs in
the checkout pack instead of one lazy network fetch per historical
`git show`/`git grep`. Bundle trees remain excluded, and the checker still reads
the exact manifest-recorded commits rather than trusting current source. Blobs
that still miss because source drifted after the recorded deploy are hydrated by
the contract's batched promisor prefetch (one fetch per 200 missing objects,
fail-open to the lazy path), and the guard prints per-phase timings
(open-issues / release-manifest / deployed-contract / card-policy) so a
cancelled run attributes its five-minute budget; the 2026-08-15 measured scan
was ~70s against 296 open issues in a CI-shaped partial clone, versus the
841-blob lazy-fetch storm that cancelled the 2026-08-13/15 scheduled runs. The
lightweight lifecycle workflow runs on issue open/reopen/
close and label/comment changes, manually, and daily. GitHub exposes comment
pin state through GraphQL but no comment-pin workflow activity, so pin-only drift
is caught by the next manual/daily run. Both workflows fail on cardinality,
invalid open labels, blocked queue leakage, stale/mismatched co-op routing,
tooling queue leakage, malformed newest cards, or invalid pin state. The advisory
`qa/check_issue_status_labels.ps1` sweep remains the local nudge; the CI step is
the backstop that the #750 sweep proved necessary.

**Pull-request closure integrity:** PR bodies use `Refs #N`, never GitHub's
auto-closing keyword forms. A merge proves source integration, not user
verification or completion of the post-fix pass. `qa/check_pr_autoclose.ps1`
blocks every supported GitHub closing keyword/reference form unless the target
issue already carries a comment by a trusted verifier with the exact lines
`## CLOSURE AUTHORIZATION` and `Verification: user-confirmed`, plus
`Authorized PR: #N` naming that exact PR. The exception is explicit,
issue-local, and single-PR-bound; a PR author cannot self-authorize in the PR
body or reuse a stale receipt after an issue is reopened.

The base-owned `pr-autoclose-authorization.yml` workflow fails closed when its
PR body or required receipt metadata is unavailable, executes only trusted
default-branch policy, and is a required protected-branch status. A local run
without PR context reports a skip and must be paired with an explicit `-Body`
or `-BodyPath` check before opening the PR. The base-owned
`pr-autoclose-audit.yml` workflow is the post-merge fallback: it reopens an
issue GitHub closed without the receipt and leaves a tracker comment. This is
the PR #969 / issue #592 regression path; it is separate from lifecycle-label
cardinality and must remain covered independently.

**Player-facing localization is not an issue tracker.** Stable, beta, and dev streams
all omit issue/lifecycle prefixes such as `[Issue N]`, `[working]`, `[untested]`,
`[verify-fix]`, `[diag]`, and `(Experimental)`. Keep that state in GitHub labels,
issues, changelogs, and logs. Functional qualifiers describing ownership or behavior
remain valid. The blocking guard is `qa/check_loc_tags.ps1`; full rules are in
`docs/LOCALIZATION_STANDARD.md` § 13.

### Umbrella issues and label-cleanup integrity (binding, 2026-07-18)

**Umbrella doctrine.** The THIRD issue that traces to a shared root cause
REQUIRES an umbrella issue carrying a sub-issue list; the two prior singletons
become sub-items on it. From that point, a new symptom report of that known root
is filed as a comment or sub-item ON THE UMBRELLA, not as a fresh standalone
issue. Umbrella issues carry the `architecture` label (an informational modifier
alongside the `regression` / `audit` / `blocked` set above) so the root-cause
clusters are filterable.

Why it is not optional: 138 of 321 open issues traced to the single #660 root,
and #487 silently blocked ten downstream issues until it was promoted to an
umbrella and the dependents were linked to it. Without the umbrella, a root cause
hides as N unrelated-looking tickets and the same fix gets re-investigated from N
different symptoms.

**Lifecycle-label integrity.** Exactly ONE lifecycle label per open issue (the
Labels status set above: `not-started` / `verify-fix` /
`diagnostics-armed`). The ship.ps1 status-label mechanization (issue
#326) already enforces one-lifecycle on ship; manual edits must not reintroduce a
second. Any batch label-cleanup session MUST log what it removed and why, in an
issue comment on each affected issue. Silent stripping is banned: correct
`verify-fix` labels were silently removed twice, on 2026-07-17 and 2026-07-18,
dropping fixes off the user's test queue with no trace of who did it or why. A
cleanup that cannot explain a removal in a comment must not make the removal.

### What used to live here
A status roadmap (`✅ DONE / ⚠ PARTIAL / ❌ TODO` tables across "High ROI",
"Medium ROI", "Lower ROI", "Architectural", "Per-mod" subsections) was
maintained inline through 2026-05-23. It was removed because it duplicated
the GitHub issue list and silently drifted — exactly the failure mode §11
above is meant to prevent. The git history has the snapshots if you want to
see what was open on a given date.

## 11a. QA tooling — representative gates (full inventory: `qa/CHECKS.md`)

This table is a READING AID, not the inventory. `qa/` currently holds ~60
`check_*.ps1` gates; the rows below are the ones a session hits most often.
Notably absent but load-bearing: `check_logging.ps1` (§3.6 logging hygiene),
`check_wt_stream_parity.ps1` (wt beta/dev mirror + the one-patch-ahead version
bind), `check_publication_receipt.ps1` (#724 receipt schema),
`check_vmb_launcher_path.ps1` (launcher resolution), `check_dev_only_edits.ps1`
(NON-NEGOTIABLE #3 dev/stable split), `check_worktree_budget.ps1` and
`check_pipeline_state.ps1` (both named in the §14 card). Always resolve
"is there a gate for X?" against `qa/CHECKS.md` or a directory listing, never
against this table.

| Tool | Location | Catches | Run via |
|---|---|---|---|
| `luacheck` | `.luacheckrc` + GHA | forward refs, unused vars, undefined globals, Lua 5.1 syntax | `luacheck . --no-config-default` |
| `check_cfg.ps1` | `qa/` | `tags=[]`, missing preview, wrong visibility, missing bug-report block, missing BMC | `.\qa\check_cfg.ps1` |
| `check_versions.ps1` | `qa/` | missing MOD_VERSION, cfg title-version drift, missing CHANGELOG entry | `.\qa\check_versions.ps1` |
| `check_localization.ps1` | `qa/` | unescaped `%`, referenced-but-undefined keys, missing `mod_description` | `.\qa\check_localization.ps1` |
| `check_file_sizes.ps1` | `qa/` | files over 1500-line target / 2500-line hard limit | `.\qa\check_file_sizes.ps1` |
| `check_stale_docs.ps1` | `qa/` | audit/review markdowns >14 days without SUPERSEDED banner | `.\qa\check_stale_docs.ps1 [-Fix]` |
| `run_selftests.ps1` | `qa/` | regression in any QA check's own parsing/decision logic + ship.ps1 step-6 labeling logic (runs every script's `-SelfTest`; blocking) | `.\qa\run_selftests.ps1` |
| `check_lua_unit_tests.ps1` | `qa/` + `qa/lua/` | deterministic pure-Lua transformations under a pinned offline Lua 5.1.5 runtime; harness self-test includes a planted failure | `.\qa\check_lua_unit_tests.ps1 [-SelfTest]` |
| `check_release_bundle_atomicity.ps1` | `qa/` + `qa/fixtures/release_bundle_atomicity/` | runtime/version/config/newest-release diff without the owning exact root bundle (#724) | `.\qa\check_release_bundle_atomicity.ps1 [-Staged] [-Range <range>] [-SelfTest]` |
| `check_ps51_compatibility.ps1` | `qa/` | non-ASCII bytes in the explicit Windows PowerShell 5.1 target set; PS5/pwsh divergence in sentinel parsing; advisory policy hiding a parser/host/tool failure (#85) | `.\qa\check_ps51_compatibility.ps1 [-SelfTest]` |
| `run_all.ps1` | `qa/` | all of the above; reserved execution-failure exits 90-99 always block before per-check policy is applied; normal Quick/full runs compare exact pre/post Git-visible worktree fingerprints and block on mutation (`-FixStale` is the explicit write-mode exemption) | `.\qa\run_all.ps1 [-Quick] [-SkipLua] [-SelfTest]` |
| GitHub Actions | `.github/workflows/qa.yml`, `.github/workflows/issue-lifecycle.yml` | full code QA on push/PR plus a lightweight blocking tracker guard on issue/label/comment events, manual dispatch, and daily schedule; the tracker guard enforces true GraphQL pin state | automatic |

Full check-to-bug-class map: [`qa/CHECKS.md`](qa/CHECKS.md).

---

## 11b. Zero-warning policy (binding, 2026-07-18)

A QA warning is a bug with a deadline, not a permanent fixture. Within ONE WEEK
of first appearing, every warning surfaced by the §11a tooling must reach one of
three terminal states:

- **(a) Fixed** - the flagged source is corrected and the warning clears.
- **(b) Baselined** - the warning is entered into the check's baseline with a
  tracking issue number recorded IN the baseline entry (the `qa/baselines/`
  pattern, e.g. `file_sizes.json` per issue #429). A baseline with no issue
  number is not a baseline, it is a swept warning.
- **(c) Checker-defect** - the warning is traced to a bug in the checker itself,
  and the CHECKER is fixed so the false warning stops emitting.

**Standing warnings are forbidden.** A warning block that never clears trains
every session to scroll past it, so the day a real warning appears inside it,
nobody reads it. Tonight's evidence is decisive: all seven standing warnings
turned out to be checker defects, not real problems - the localization parser
(three separate false positives), the decisions-wired-career over-derivation
check, and luacheck missing `printf` from its globals list. Every one had been
scrolled past for weeks while masking exactly nothing that needed a human.

The §8.5a gate-semantics rule still holds (warnings report, errors block, so a
warning never wedges a ship); this policy governs what happens to a warning
AFTER it reports. Warnings do not block the commit, but they DO carry a one-week
clock, and "still there next week" is itself the failure.

**Corollary: every pre-crash probe needs a consumer.** A runtime probe that
detects a pre-crash condition must feed a consumer - issue auto-annotation, or a
named session-start check - not just a log line nobody reads. The `[gut:272]`
probe flagged the #737 score-CTD divergence four minutes before the crash, and
nothing was consuming its output, so the whole warning window bought us nothing.
An unconsumed probe is the runtime twin of a standing warning: signal with no
reader. (Sibling of §2.2b tier (c): a probe that outlives its issue is dead
log-noise; a probe whose output nothing reads is dead on arrival.)

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

## 12a. Mechanics knowledge substrate — capture doctrine

`docs/MECHANICS.md` is the repo's **provenance-enforced** index of how VT2 /
Stingray mechanics work. It exists to kill one specific failure: a session
drifts on how a mechanic works, **hallucinates to fill the gap**, and the wrong
claim propagates into code comments, docs, and crash triage. The substrate only
accretes GROUNDED inputs. `qa/check_mechanics_citations.ps1` fails on any
untagged factual bullet (wired into `run_all.ps1`, Standard policy — its exit 2
blocks the gate).

Every factual bullet carries one provenance tag: `[src: file:line]` (decompiled
source, opened and verified — the gold standard), `[dump: file]` (in-game
runtime dump), `[memory: note]` (a memory note that itself cites ground truth),
`[bugclass: §N]` (carried from `docs/BUG_CLASSES.md`), `[user: YYYY-MM-DD]`
(maintainer stated it — lowest tier, flag for source-confirmation), or
`[unverified]` (an explicit, COUNTED honest gap). Full schema at the top of
`docs/MECHANICS.md`.

### The four capture rules (this is the loop that keeps it growing from real inputs)

1. **Before stating ANY mechanic** — in a code comment, a doc, or a reply to the
   user — grep the decompiled source FIRST and cite `file:line`, OR write
   `[unverified]` / say "I don't know." NEVER confabulate. (This generalizes the
   `feedback_vmf_ui_no_guessing` "read the source before proposing" rule from VMF
   UI to ALL mechanics. The §13 "Don't invent internals" rule in the global
   prefs is the same principle.)
2. **When the decompiled source confirms a fact during work** → append a
   MECHANICS entry with `[src: file:line]`, in the SAME response as the code
   edit. Capture-as-you-verify; don't batch it for later (it rots).
3. **When the maintainer states a mechanic** → capture it to MECHANICS with
   `[user: <date>]`, and where possible add a source cross-check. Promote the tag
   `[user]` → `[src]` once the decompiled source confirms it. This is the
   "information the maintainer gives is added there" loop — it is explicit and
   cheap on purpose.
4. **When an in-game dump is collected** (the gt name-dump, ANIMATION_RESEARCH
   probes, a `/dump_*` capture) → reference it `[dump: <file>]`.
5. **When the Lua decompile cannot answer** (engine-native behavior: network
   type_info bounds, resource/package residency semantics, unit/material/scene
   graph internals, animation state machines) → consult the OFFICIAL Stingray /
   Bitsquid documentation online (Autodesk Stingray help + Lua API reference)
   and cite it `[engine-doc: <URL>]` (user directive 2026-08-03). An engine-doc
   citation outranks `[unverified]` but never outranks `[src:]` — where the
   decompile and the docs disagree, the decompile describes THIS game.
6. **Before designing any fix, cross-reference the issue against its siblings —
   open AND closed** (`gh search issues state:all`, `docs/BUG_CLASSES.md`, the
   per-mod census/coverage docs). If a sibling solved the same mechanism class,
   reuse that solution or record in the issue why it does not transfer. If the
   fix lands on one surface, enumerate the OTHER surfaces of the same class in
   the same pass and either fix them or file the parity gap — "works in one
   area, broken in another" is the failure mode this rule exists to kill
   (user directive 2026-08-03).

### Invariants

- The substrate is APPEND-mostly. Entries get PROMOTED up the provenance tiers as
  they're confirmed; they are never silently invented or downgraded.
- `[unverified]` is the CORRECT state where no grounded source exists. It is an
  honest, surfaced gap — NOT a license to fill it from model knowledge. The lint
  counts these as the known-gaps backlog so they stay visible.
- MECHANICS POINTS at memory / source / BUG_CLASSES; it does not restate them.
  Don't create a fourth knowledge surface that duplicates prose.

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
AT SESSION START:
  - check_pipeline_state.ps1 (pipeline + worktree state clean before touching anything)
  - check_worktree_budget.ps1 (max 8 secondary worktrees / 12 GiB)

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
  - VT2_SHIP_VMB_LAUNCHER set (launcher is out-of-repo; see docs/PORTABLE_SETUP.md)
  - claim.ps1 FIRST (before the version bump - the broker allocates the number)
  - MOD_VERSION renumbered to the BROKER's answer (may exceed master+1)
  - CHANGELOG entry written against that exact version
  - .mod descriptors are LF, root + bundleV2 (CRLF breaks the publication receipt)
  - Every changed mod BuildOnly'd before the commit (#724 atomicity)
  - Each changed mod's schema-3 .build-receipt.json matches staged source + the complete normalized output set (#1278/#1400)
  - Source and bundle committed together, pushed, reviewed, hosted QA passed, and merged
  - Final ship runs from a clean checkout at the exact live default-branch HEAD
  - No forward-ref bugs (visually verify; future: luacheck)
  - No new "guard ≠ bail" violations
  - Subagent pre-ship review for hot mods
  - Approval axis checked: -dev/-alpha/-beta = ship with NO ask; clean version = fresh per-build signal (sec. 6.6)

AFTER shipping:
  - workshop_log.txt shows "Uploaded new content" for the item
  - CURRENT LIVE TEST card posted AND pinned; every older exact card unpinned
    (CI cardinality guard fails the whole repo's qa-gate otherwise)
  - Do not add a post-upload source commit or push; the uploaded bytes must remain bound to the already reviewed and merged source commit

BEFORE a verify session:
  - generate_playtest.ps1 (generate the in-game playtest checklist)

WHEN BLOCKED:
  - Memory + CHANGELOG grep for the literal symptom
  - Dispatch Explore subagent if it needs >3 files
  - Don't add speculative defenses
```

---

## 14a. Persistence-after-fix protocol (assume I misfixed first)

Established 2026-05-25 EOD after I shipped gt v0.2.61 → .62 → .63 → .64 → .65 in ~45 minutes, each time claiming the bug was fixed, each time the user restarted and hit a NEW bug or the SAME bug pattern from a missed call site. User-facing impact: indistinguishable from gaslighting — "I fixed it, restart" → still broken → "oh that's a new bug, restart again" → etc.

### The binding rule

When a user reports that a bug PERSISTS after I claimed "shipped / fixed":

1. **First hypothesis: I didn't actually fix it.** Not "you have stale code." Not "your session predates the deploy." Not "Steam hasn't propagated."
2. **Verify the three layers before considering environmental causes:**
   - **Source:** read the source file. Does the fix actually exist in the code right now? (E.g. did the Edit fail silently? Was the file modified after my edit by another agent?)
   - **Bundle:** `Get-ChildItem <mod>/bundleV2/` — is the .mod_bundle newer than the source file? If source is newer than bundle, the bundle is stale.
   - **Loaded mod:** in the user's latest log, find the `<<crashify-property>>Mod:<id>:<name> v<version>` line. Does the loaded MOD_VERSION match the version I claimed shipped?
3. **Only after all three verify clean** may I suggest restart / Steam propagation / friend re-pull as the next hypothesis.

### Also: search for the SAME bug pattern across the whole file / module before declaring done

When fixing one instance of a class (e.g. `event:register(mod, "ev", FN_VALUE)` — Stingray expects string), grep the whole repo for the pattern BEFORE marking the task done. The user shouldn't have to restart 3 times to find 3 instances of the same bug. One grep finds all of them.

### Why this rule exists

The lt-merge session above shipped 5 bumps in 45 minutes:
- v0.2.61 — claimed fix for widget#103; was correct but I missed event_register bug entirely
- v0.2.62 — added /gt_lobby_motd_set chat command (a new feature, not a fix)
- v0.2.63 — claimed fix for event_register; fixed 2 of 3 sites (I missed session_ignore)
- v0.2.64 — fixed the 3rd site; introduced no new fix beyond that
- v0.2.65 — claimed fix for `set_lobby_data` nil spam; needed defensive type-check guard

Each "fix" surfaced another latent bug because I patched whack-a-mole without auditing the broader migrated code holistically. User had to restart 5 times to reach a clean state. From their seat, each restart cycle was "fixed → not fixed → fixed → not fixed."

### Detection mechanism

When the user says "still broken" / "errors persist" / "you didn't fix it":
- Apply this protocol BEFORE responding.
- Verify the three layers programmatically (don't trust the agent report; read the actual file).
- If all three verify clean and bug genuinely persists → THEN suggest restart.
- If any of the three doesn't verify → that's the real root cause, fix it.

Burn history: 2026-05-25 EOD (this very session).

## 15. Every bug requires a test

Established 2026-05-23 after the DORMANT_BOON_RARITY scope-bug shipped twice (crash GUIDs 4c5d2157 + prior chest-of-trials crash).

### The rule

When fixing any user-reported bug or any internal-discovered defect, the fix is incomplete until:

1. A regression test exists that would FAIL if the bug returned.
2. The test runs as part of the mod's `/<prefix>_regression_test` chat command.
3. The test is documented in the mod's CHANGELOG.md entry for that fix version, with the exact identifier so it's findable later.

No exceptions for "tiny" bugs. The bigger the bug seems, the more obvious the test should be — and yet, today's scope bug shipped without one even though the recon agent identified the cause.

### Test categories per mod

- **Source-pattern check**: embed a sentinel literal in the source body (e.g. `STARTING_COINS_MODE_MARKER = "setter-override-via-setup_run-arg"`); the regression check at boot asserts the literal is present in the compiled bundle. Catches accidental code deletion / refactor regression.
- **Runtime-state check**: in-keep assertion that touches the actual runtime structure (e.g. `_rt_register("dormant_boon_rarity_is_table", function() if type(_G.DORMANT_BOON_RARITY) ~= "table" then return "..." end end)`).
- **Disable-mode check**: when a feature is disabled, verify the disable is real — not just "the toggle says off" but "the feature's table is empty, the feature's setting key is not consumed, the feature's chat command is absent."

### When the test feels redundant

If the test feels redundant with the lint, write it anyway. Lints catch new code; tests catch live runtime behavior. They cover different surfaces. Memory `reference_redundant_safeguards_ok` already endorses this. **Belt-and-suspenders is the rule, not the exception: a lint-covered fix is PARTIAL until it ALSO has a runtime `_rt_register` check — both the static-pattern lint and the live-state assertion are required for PASS.** (Codified 2026-05-24 after the §15 test-coverage audit promoted five lint-only fixes to lint+runtime.)

### Defensive wrapper patterns

Per the chest-of-trials root-cause analysis (`DORMANT_BOON_RARITY` indexed by closures that resolved the name to `_G.DORMANT_BOON_RARITY` (nil)):

1. **Top-level data tables consumed by mid-file closures**: declare at the TOP of the file (above all closures), not late. If declared late, promote to `_G.<NAME>` at top so all closures resolve consistently.

2. **Global table indexes** that could be nil during early boot: wrap in `(rawget(_G, "<NAME>") or {})` sentinel before subscript.

3. **NetworkLookup / BuffTemplates / DeusPowerUpTemplates**: always `rawget(table, key)` — these install strict `__index` metatables that crashify on missing key. Memory `reference_vt2_strict_lookup_rawget`.

4. **Every disabled feature**: ship with a regression check that ASSERTS THE DISABLE (e.g. `<feature>_NOT_registered`, `<feature>_NOT_in_pool`). Re-enabling the feature would fail those checks until they're rewritten — guards against half-revert.

---

*Last updated: 2026-07-30 - added the binding 8-worktree / 12-GiB lifecycle budget, blocking QA guard, and fail-closed create/close wrapper after the 707-worktree cleanup reclaimed at least 323.81 GiB. Prior update 2026-07-21 - made the newest exact CURRENT LIVE TEST comment the one and only truly pinned exact card, enforced GraphQL pin state, and added tracker-event/daily enforcement. Prior update: restored `not-started` as the non-ready OPEN lifecycle, retired open `Fixed` / `verify-fix-coop`, made live-test labels require the newest strict CURRENT LIVE TEST card, and enforced solo-first co-op routing. Prior update 2026-07-19 - introduced the universal lifecycle guard. Prior update 2026-07-18 - added §11b zero-warning policy (fix/baseline/checker-defect within one week + pre-crash-probe-needs-a-consumer corollary), §11 umbrella doctrine + lifecycle-label-cleanup integrity, §8.7 session hygiene (git/worktree/branch closeout), §5.1c retained-state verification (read-back not setter-success), and three §14 card rows (claim.ps1 / check_pipeline_state.ps1 / generate_playtest.ps1). Prior update 2026-07-16 - reconciled cfg-owned visibility, suffix-owned ship approval, enabled-remote deployment, GitHub-only current status, and empirical issue fallback comments. Prior update 2026-07-12 - sec. 7.11 doc-process subsection added (issue #432 process durability: one owner per topic, cite don't restate, date state claims, retire per sec. 7.10). Prior update 2026-07-01 - sec. 6.5/6.6 ship doctrine rewritten (dev builds
pre-authorized for the full pipeline + git commit/push; stable promotions need a
fresh per-build signal), sec. 8.5a gate semantics (errors block, warnings
report), sec. 14 card gained the approval axis + AFTER-shipping steps.
Prior update 2026-05-23 — §7 documentation standards expanded: canonical doc
map (repo-root + per-mod tables with update triggers), three-bucket model for
non-canonical docs (Reference / POSTMORTEMS.md / `_investigating/`), audit
snapshot policy (gitignored, distill on action), supersession banner preserved,
doc creation gate, filename conventions. §1 baseline refreshed (QA tooling now
in place); §11 roadmap moved to GitHub Issues per §11's own discipline.
Initial draft: 2026-05-22.*
