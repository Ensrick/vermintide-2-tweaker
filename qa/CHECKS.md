# QA Checks Map

For every documented bug class in this repo's history, the check that catches it
going forward. **Status as of 2026-07-08.**

This doc is the contract between [PROJECT_STANDARDS.md](../PROJECT_STANDARDS.md)
and the runnable QA tooling in this directory. Every memory file or audit
finding that names a recurring bug class should appear here with its detection
method.

Run all checks with: `qa\run_all.ps1`. CI (`.github/workflows/qa.yml`) runs the
same `run_all.ps1` full gate (the policy engine below decides what blocks) plus a
blocking all-mods `lint-mod.ps1` step on every push + PR (issue #429).

## Gate semantics (run_all exit codes)

Individual checks follow a **0 / 1 / 2 convention**: `0` = clean, `1` = advisory
WARNINGS, `2` (or higher) = ERRORS. `run_all.ps1` aggregates these so that:

- **Warnings (exit 1) are REPORTED but never fail the gate.** They are collected
  and printed loudly under a `WARNINGS (non-blocking)` summary block, and
  `run_all` still exits `0`. This is deliberate: pre-existing advisory warnings
  (bare-unpack in stable files, cfg title drift, stale `.in_progress` sentinels,
  data<->loc diffs) must not block unrelated commits, because a gate that blocks
  on noise trains sessions to bypass the pre-commit hook with `--no-verify`.
- **Errors (exit >=2) fail the gate.** `run_all` exits with the highest error
  code seen. The pre-commit hook (`qa/run_all.ps1 -Quick -SkipLua`) therefore
  blocks only on genuine breakage.

Seven checks are pinned in `run_all.ps1` to a non-default policy via the
`Run-Check -Policy` parameter:

| Check | Policy | Reason |
|---|---|---|
| `check_published_ids` | `Blocking` | Signals a real published_id collision (Workshop-item hijack) via **exit 1**. Any non-zero from it is a hard error, so it must fail the gate despite using exit 1. |
| `check_in_progress` | `Advisory` | Multi-agent coordination surface only ("Never blocks - just surfaces awareness", per CLAUDE.md). No exit code it returns (including exit 2 on a malformed sentinel) ever fails the gate; a non-zero is reported as an advisory notice. |
| `check_loc_tags` | `Advisory` | Dev status-tag doctrine surface (issue #301, `docs/LOCALIZATION_STANDARD.md` § 13). It uses the standard 0/1/2 convention (1 = findings, 2 = self-error) but is pinned Advisory so it NEVER blocks — it exists to flag a known pre-existing leak (7 `[untested]` tags in stable `crafting_in_modded`) plus vocab drift, none of which should stop a commit. |
| `check_issue_status_labels` | `Advisory` | GitHub issue status-label doctrine surface (PROJECT_STANDARDS §11). Uses the standard 0/1/2 convention (1 = findings, 2 = self/read error) but is pinned Advisory so it NEVER blocks — it queries GitHub (must not fail a commit offline) and its findings are nudges the maintainer reviews, not hard errors. |
| `check_issue_tag_sync` | `Advisory` | Loc-tag ↔ GitHub-label cross-surface sync (issue #326 part 2). Same reasoning as `check_issue_status_labels`: queries GitHub (self-exits 0 offline), findings are review nudges — stale `[Issue N]` tags, tag/label mismatches in either direction — never hard errors. |
| `check_stale_docs` | `Advisory` | Doc-hygiene surface (issue #429). Staleness is TIME-based (`check_stale_docs.ps1` flags a doc at its `$StaleDays = 14` default with no edit), so exit 2 must NOT hard-block a commit/CI on calendar drift. Pinned Advisory (formalizing the old CI `continue-on-error`). Remediation: `run_all.ps1 -FixStale`. |
| `luacheck` | `Advisory` | Lua static-analysis surface (issue #429). The ~415-warning baseline is driven down over sessions, not per-commit (CWV bare-globals cleanup, PROJECT_STANDARDS §11). Pinned Advisory — the policy-engine version of the old CI `\|\| true`. Flip to Standard once the baseline is clean. |
| `check_logging` | `Advisory` | Logging-hygiene surface (issue #429, rows 58a/b/c). Encodes § 3.6 + BUG_CLASSES § 17; the ~56-finding backlog (mostly the Issue-#240 `_dbg_alert → mod:warning` migration + § 3.6 hook-body echoes) is worked down over sessions, not per-commit. Pinned Advisory — NEVER blocks. Flip to Standard once the backlog is annotated/cleared. |
| `check_hook_test_coverage` | `Advisory` | Hook/NetworkLookup regression-coverage surface (issue #429, row 24a). Diff-scoped; warn-only in `run_all` AND pre-commit while we gather signal. Self-exits 0 on an indeterminate diff. Consider Standard once the `-- hook-test:` / `_rt_register` convention is established. |

Everything else uses the default `Standard` policy (exit 1 = warning, exit >=2 =
error). Checks that already hard-fail on exit 2 and never emit exit 1
(`check_vmf_widget_types`, `check_event_register_signature`,
`check_cross_mod_deps`, `check_command_collisions`, `check_mechanics_citations`,
`check_dev_only_edits`) keep blocking on their errors under this default.

### Ratchet baselines (issue #429)

Two Standard-policy checks would otherwise be permanently red on pre-existing,
not-per-session-fixable violations, so they are **ratcheted**: the current
violation set is frozen in `qa/baselines/*.json` and the check fails only on a
NEW offender (or growth past a frozen count). This lets the full gate BLOCK on
regressions without being permanently red.

| Check | Baseline file | Frozen | Fails on |
|---|---|---|---|
| `check_file_sizes` | `qa/baselines/file_sizes.json` | 13 files over the 2500-line hard limit | a NEW file crossing the hard limit, or a baselined file GROWING beyond its frozen line count. Target-tier (1500–2500) overages stay plain warnings. |
| `check_name_integrity` | `qa/baselines/name_integrity.json` | 14 errors (the no-VtSrc SUPERSET) | a NEW error only. The baseline is generated WITHOUT the decompiled `Vermintide-2-Source-Code` so it matches CI (which lacks the sibling repo); locally, with VtSrc present, fewer errors fire — all a subset. |

Regenerating a baseline is an **explicit** action (`<check>.ps1 -UpdateBaseline`),
never automatic, and requires maintainer sign-off (it can only hide a real new
violation). `check_name_integrity -UpdateBaseline` forces the no-VtSrc view so
the committed baseline always matches CI regardless of the local checkout.

## Legend

- **AUTO**: detected by a script in this directory; runs in CI
- **MANUAL**: human / Claude must verify before ship; checklist item only
- **PRE-SHIP**: covered by the pre-ship subagent review pattern (PROJECT_STANDARDS §5.3)
- **DEFERRED**: known gap, not catchable today; tracked here so it's not forgotten

## Documented bug classes → detection

### Lua-level static issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 1 | Forward-reference crashes (5+ instances) | `feedback_lua_forward_reference.md` | `luacheck` `--no-self` flag catches use-before-decl | AUTO (CI) |
| 2 | Unescaped `%` in localization strings (13 found in one audit) | `feedback_keep_docs_current.md` + AUDIT_section_c.md | `check_localization.ps1` regex scan for single `%[a-z]` in localization values | AUTO (script) |
| 3 | Bare `_foo = function` globals (namespace pollution, CWV has 9) | AUDIT_section_d.md | `luacheck` `unused`/`global` warning | AUTO (CI) |
| 4 | Lua 5.1 incompatibility (`table.unpack`, `goto` in SDK mods) | CLAUDE.md "Lua Environment" | `luacheck` Lua 5.1 dialect mode | AUTO (CI) |
| 5 | Unused locals / dead code | AUDIT_section_d.md | `luacheck` `unused` warning | AUTO (CI) |
| 6 | Wrong storage key (`_attachments[X]` vs `.slots[X]`) — v0.9.8.4 lesson | `feedback_vt2_dormant_buff_template_dual_register.md` + ATTACHMENT_STORAGE_AUDIT.md | Hard to detect statically; mitigated by PRE-SHIP "verify against vanilla source" rule | PRE-SHIP |
| 7 | `goto`/`continue` in SDK mods (Lua 5.1 limitation) | CLAUDE.md | `luacheck` syntax mode | AUTO (CI) |
| 7a | `--[[ ... ]]` long-comment with embedded `]]` (closes block prematurely) | wt v0.12.69 burn | `luacheck` syntax mode (line "expected '=' ',' or 'in'") | AUTO (CI) |
| 7b | Cross-mod chat-command name collision (7 mods registered `regression_test`) | GitHub Issue #11 + `reference_vt2_chat_command_syntax.md` | `check_command_collisions.ps1` grep + cross-mod aggregation | AUTO (script) |
| 7c | `unpack(t, i)` without explicit `j` → nil-hole truncation (Lua 5.1 `#table` undefined for sparse arrays). Burned weapon_tweaker v0.12.77 → .78 → .79 on 2026-05-25 in a single 2-hour fix cycle. | `docs/VMF_RECIPES.md § 2a` + `CLAUDE.md` engine-quirks + `PROJECT_STANDARDS.md § 9.9` | `check_unpack_safety.ps1` regex scan with `select("#", ...)` / inline-pragma suppression. GitHub Issue #36. | AUTO (script) |
| 7d | Invalid VMF widget `type` (e.g. `text_input`, `slider`, `string`) — breaks entire mod options init at load time, options page vanishes in-game. Burned gt v0.2.60-dev on 2026-05-25 (widget #103 `type="text_input"`). | `docs/VMF_RECIPES.md § 6a` (VMF widget type whitelist) + `docs/BUG_CLASSES.md` "Invalid VMF widget type breaks options init" | `check_vmf_widget_types.ps1` regex scan against canonical 6-type whitelist (`group`/`header`/`checkbox`/`dropdown`/`numeric`/`keybind`). Hard-fail (exit 2) on any non-canonical type — no warning tier, no suppression pragma. | AUTO (script) |
| 7d2 | Malformed numeric `range` — a `range` field with ≠ 2 elements (typically a 3-element `{ min, max, step }`) fails the SAME options-init validation (`'range' field must contain an array-like table with 2 elements`) and kills the ENTIRE mod's options (no `[<mod>:LOAD]`, every tweak gone). A "step" CANNOT live in range[3]; snap in `on_setting_changed`. Burned ct_dev v0.7.188-dev (`starting_coins` range `{ 0, 3000, 25 }`, #164 — mod fully dead until v0.7.189-dev reverted it). | this file + ct_dev CHANGELOG 0.7.189-dev + `docs/BUG_CLASSES.md` | `check_vmf_widget_types.ps1` (same script as 7d) — single-line `range = { ... }` element count; hard-fail (exit 2) on count ≠ 2. Self-test fixture `widget_range_bad.lua`. | AUTO (script) |
| 7e | Stingray `event:register(obj, "ev", FN_VALUE)` — 3rd arg must be a STRING method name on `obj`, not a function value. Engine logs `No function found with name '[function]'` and the handler silently dies. Burned gt v0.2.61 → .62 → .63 → .64 on 2026-05-25 (four separate fixes across lobby MOTD / session-ignore / slot-reservations). | `docs/VMF_RECIPES.md § 12` ("Stingray `event:register` signature") + `docs/BUG_CLASSES.md` "Stingray event:register function-value 3rd arg" | `check_event_register_signature.ps1` regex scan for `:register(<obj>, "<event>", <arg3>)` where `<arg3>` doesn't start with `"`. Hard-fail (exit 2). No suppression pragma. This static check IS the live gate; the former `bt:safe_event_register` runtime safety net (buff_tweaker v0.1.10-alpha+) is RETIRED (bt archived 2026-06). | AUTO (script) |
| 7f | Network-bound engine field WIDENING — a direct `<ident>._max_(overcharge\|energy\|ammo\|charge\|health\|stamina\|push_power) = <rhs>` that RAISES the cap crashes peers via fassert (engine `.network_config` hardcaps these). Burned ct v0.7.100-dev (`energy_ext._max_energy = ...`). | CLAUDE.md memory `feedback_vt2_max_resource_consumption_side` + chaos_wastes_tweaker v0.7.100-dev CHANGELOG | `lint-mod.ps1` Pattern A (Find-NetworkBoundMutation). Heuristic REFINED 2026-05-29 for precision: (a) the former "Pattern B" `stat_buff = "max_*"` data-table string match was REMOVED — those are buff-template literals resolved by the engine's network-safe buff system, not field writes (false-positived on crt's two `stat_buff = "max_health"` entries); (b) DOWNWARD CLAMPS are SAFE — `math.min(...)` RHS or a guarded `if X > CONST then X = CONST end` (canonical: chaos_wastes_tweaker.lua:7831 `_max_ammo` clamp, the load-bearing FIX for a CW-boon cap-widening crash); (c) bare WIDENING assignments STILL fire. WARN (exit 1); ERROR under `-Strict`. `-- LINT_OK_NETBOUND` escape hatch. | AUTO (script) |

### itemV2.cfg / Workshop-level issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 8 | `tags = [ ]` causes ugc_tool 0x2 error | `feedback_ugc_tool_forward_slashes.md` | `check_cfg.ps1` regex scan | AUTO (script) |
| 9 | Missing preview file referenced by cfg | various | `check_cfg.ps1` file-exists check | AUTO (script) |
| 10 | MOD_VERSION constant missing in main lua | `feedback_version_in_workshop_title.md` + CLAUDE.md §"Version bumping" | `check_versions.ps1` regex scan | AUTO (script) |
| 10a | 4-segment MOD_VERSION (e.g. `0.9.9.4-dev`) — the retired within-patch-hotfix anti-pattern; semver is 3-segment `MAJOR.MINOR.PATCH[-track]`. Burned cosmetics_tweaker 2026-05-23. | CLAUDE.md §"Version bumping" | `check_versions.ps1` — flags a 4th numeric segment as a WARNING (exit 1) instead of silently stripping it (issue #429). Normalize on the next bump. | AUTO (script) |
| 11 | cfg title doesn't carry current version suffix | `feedback_version_in_workshop_title.md` | `check_versions.ps1` cross-check | AUTO (script) |
| 12 | Visibility accidentally flipped to public | `feedback_workshop_metadata_user_dictates.md` | `check_cfg.ps1` whitelist visibility per mod | AUTO (script) |
| 13 | Description doesn't include bug-reporting block | (PROJECT_STANDARDS §7) | `check_cfg.ps1` regex for "issues" link + log path | AUTO (script) |
| 14 | BMC link missing or modified | `reference_bmc_button.md` | `check_cfg.ps1` regex for BMC SVG URL | AUTO (script) |
| 15 | Workshop upload "Upload finished" doesn't mean transferred | `feedback_workshop_upload_verify.md` | Post-upload Workshop page check | MANUAL |
| 16 | Steam doesn't auto-subscribe to own uploads (first-time blocker) | `reference_vmblauncher_handscaffold_first_upload.md` | (info doc; not a check) | MANUAL |

### Localization issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 17 | Referenced but undefined localization key (widget setting_id without entry) | AUDIT_section_c.md | `check_localization.ps1` data↔loc diff | AUTO (script) |
| 18 | Defined but unreferenced key (dead localization) | AUDIT_section_c.md | `check_localization.ps1` data↔loc diff | AUTO (script) |
| 19 | Missing `mod_description` (mh, vdl reported in audit) | AUDIT_section_c.md | `check_localization.ps1` required-key list | AUTO (script) |
| 19a | setting_id with NO loc entry (the red-tooltip class) — stricter ERROR variant of #17 | `docs/generated/README.md` | `check_name_integrity.ps1` check 1 (ERROR, skips concat-fragment ids) | AUTO (script, standalone) |
| 19b | A mod-assigned `display_name`/`item_type`/`description` literal-string key that resolves in NO loc table (mod / any-mod / vanilla) and isn't literal English — typo'd/orphan render key. `Localize(item_type)` is a real render path. | `docs/generated/README.md` | `check_name_integrity.ps1` check 2 (ERROR). Runtime-registered names (cwv `_display_names`, cosmetics `_custom_loc`) resolved via the `NAME_MAP.generated.json` oracle. | AUTO (script, standalone) |
| 19c | Orphan loc key — defined in a mod's `_localization.lua`, referenced nowhere in its Lua/data (some are dynamic) | `docs/generated/README.md` | `check_name_integrity.ps1` check 3 (WARN; concat-prefix aware) | AUTO (script, standalone) |
| 19d | Documented port decision not wired into all 3 surfaces (unlock_map + checkbox + loc) — "decisions must bake immediately" | `feedback_decisions_must_bake_immediately` | `check_decisions_wired.ps1` — parses `weapon_tweaker/CROSS_CHARACTER_PORT_DECISIONS.md`, 3-way: REGRESSION (shipped but missing = ERROR) / LEAK (skip-marked but present = ERROR) / PENDING (To-ADD not yet wired = backlog). Also flags ORPHAN (in unlock_map, no decision row) + UNCLASSIFIABLE (ambiguous doc row). Self-test fires REGRESSION + LEAK. | AUTO (script, in run_all) |
| 19e | Dev status-tag drift (issue #301) — a sanctioned tag leaked into a STABLE build (`[untested]` etc. must be stripped at promotion), an unknown/invented tag (`[confirmed working]` vs `[working]`, casing typos), or a mutex combo (`[crash]`/`[working]`/`[untested]` together) on a dev option TITLE. | `docs/LOCALIZATION_STANDARD.md § 13` "Dev status tags" | `check_loc_tags.ps1` — parses single- + multi-line `en = "..."` forms, reads the leading `[...]` run, classifies each group KNOWN/tag-like-UNKNOWN/NOT-TAG (uppercase-leading prefixes like `[CW]`/`[Big Rebalance]` and gut `<...>` markers are left alone). Known set = the 7 tags + the two wt-only extensions `[needs offsets]` / `[needs animations → <target>]` (§ 13.8). WARNING-only, non-blocking (Advisory). Self-test: `-SelfTest` (fixtures `loc_tags_dev_ok.lua` / `loc_tags_unknown.lua`). Current findings: 7 stable-cim leaks + 11 `[confirmed working]` unknown-vocab (gt_dev, gut_dev). | AUTO (script, in run_all) |
| 19f | GitHub issue STATUS-LABEL drift — a fix/probe shipped in a mod's latest CHANGELOG entry but the referenced OPEN issue carries no status label (`verify-fix` / `verify-fix-coop` / `diagnostics-armed` / `Fixed`; lifecycle per PROJECT_STANDARDS §11, user rules 2026-07-11), i.e. the label was forgotten in the ship pass. The recurring "shipped fixes aren't consistently labeled" miss (PROJECT_STANDARDS §11). | `PROJECT_STANDARDS.md § 11` "Labels" | `check_issue_status_labels.ps1` — reads each active mod's TOP `## <version>` entry, harvests `#N` refs, and via `gh issue view N` warns on any OPEN issue with no status label. SKIPS localization-sweep top entries (tags-only #301 passes reference issues as tag CONTEXT, not shipped work) so they don't drown the signal; context-mentions in a real fix entry ("...NOT fixed here, tracked as #N") still surface for maintainer review. Self-exits 0 when `gh` is offline/unauthenticated. WARNING-only, non-blocking (Advisory). Self-test: `-SelfTest` (pure parser fixtures — top-entry extraction, loc-sweep detection, ref harvest). PREVENTION at the source: `tools/ship/ship.ps1` step 6 (issue #326 part 1) auto-adds the status label at dev-ship time by parsing the shipped CHANGELOG entry (diag/probe/instrument header markers → `diagnostics-armed`, else `verify-fix`; never downgrades an existing `verify-fix-coop`/`Fixed`), printing every decision for correction. Coop-verify issues get the manual `verify-fix` → `verify-fix-coop` swap after ship. | AUTO (script, in run_all) |
| 19g | Loc-tag ↔ GitHub-label CROSS-SURFACE drift (issue #326 part 2) — (a) a `[Issue N]` tag naming a CLOSED/non-existent issue (stale, § 13.4), (b) `[verify-fix]`/`[diag]` with no `[Issue N]` in the run (unpairable, § 13.2), (c) `[verify-fix]`/`[diag]` whose paired open issue lacks a satisfying GitHub label (`verify-fix-coop`/`Fixed` satisfy `[verify-fix]`), (d) vice versa — an open `verify-fix`/`diagnostics-armed` issue with no matching loc tag anywhere (often legitimate: no menu surface, § 13.3/13.8; `tooling`-labeled issues exempt; reported compactly). | `docs/LOCALIZATION_STANDARD.md § 13.4` + `PROJECT_STANDARDS.md § 11` | `check_issue_tag_sync.ps1` — same loc-entry parsing as `check_loc_tags.ps1` (single- + multi-line literal forms; leading tag run; stable dirs skipped — tags there are 19e leaks), ONE `gh issue list --state all` fetch plus per-number `gh issue view` fallback for absent refs. WARNING-only, non-blocking (Advisory); self-exits 0 offline. Complements 19f (whole surface vs top CHANGELOG entry only). Self-test: `-SelfTest` (pure parser + sync decision matrix on synthetic issue metadata). | AUTO (script, in run_all) |
| 20 | Inconsistent CHANGELOG header format (3+ styles in use) | `_archive/audits/2026-05-08/AUDIT_section_b.md` | `check_changelog_format.ps1` (future) | DEFERRED |

### Hook / vanilla-API issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 21 | Hook on BASE class when DERIVED is the runtime type | CLAUDE.md §"HOOK THE DERIVED CLASS" + `feedback_vt2_class_hook_derived.md` | Hard to detect statically; mitigated by PRE-SHIP review | PRE-SHIP |
| 22 | Hook drops vanilla arg through too-narrow signature (`function(func,self,a,b,c)` when vanilla takes 5) | weapon_tweaker_backend.lua audit | PRE-SHIP review pattern | PRE-SHIP |
| 23 | Guard returns without calling vanilla `func` — silently changes state | PROJECT_STANDARDS §4.2 + ATTACHMENT_STORAGE_AUDIT lesson | PRE-SHIP review pattern | PRE-SHIP |
| 24 | "Attempting to rehook active hook" (same Class+method hooked twice in one mod handle) | v0.9.8.2 lesson | PRE-SHIP review (grep `mod:hook` for duplicate Class+method pairs per file) | PRE-SHIP |
| 24a | A diff ADDS a `mod:hook`/`mod:hook_safe` or a `NetworkLookup` write in a mod's lua but ships NO regression marker, so the singleton-hook invariant (#24, CLAUDE.md NON-NEG #8) and the gated-registration invariant (#29) go unchecked as the mod evolves. | CLAUDE.md NON-NEG #8 + `feedback_vmf_no_duplicate_hooks` + `feedback_vt2_gated_registration_diverges.md` | `check_hook_test_coverage.ps1` — parses `git diff -U0` (`-Range` default `HEAD~1..HEAD`, `-Staged`, or `origin/<base>...HEAD` in CI). A file that adds a hook/NL-write is covered iff the diff also adds a `_rt_register(`, carries a `-- hook-test: <check>` comment, OR the mod already ships an `_rt_register` suite. WARNING-only (exit 1), pinned **Advisory** in `run_all` + a warn-only step in pre-commit — gathers signal, never blocks; self-exits 0 on an indeterminate diff. Coverage-EXISTENCE, not per-hook proof (a marker can't be statically matched to one hook). The `_rt_register` suite it credits is the tier-(b) in-game regression harness defined in `PROJECT_STANDARDS.md` §2.2b (this gate is tier (a)). Self-test: `-SelfTest` (synthetic diff through the pure parser + decision fn). | AUTO (script, in run_all + pre-commit) |
| 25 | 1P animation override per character (breaks universal anim chain) | `feedback_1p_animations_universal.md` | PRE-SHIP review (grep for `anim_event = ` or `wield_anim = ` in cross-character contexts) | PRE-SHIP |
| 26 | Speculative defense stacking (v0.9.8.3-7 chain) | PROJECT_STANDARDS §9.1 | PRE-SHIP review pattern | PRE-SHIP |

### Network / multiplayer issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 27 | VMF RPC string > 500 chars (Stingray hardcap) | `reference_vmf_rpc_string_cap.md` | Manual — VMF doesn't expose payload size; mitigated by chunking pattern | MANUAL |
| 28 | `network_send(..., "server", ...)` silently dropped | `reference_vmf_network_send_recipients.md` | `check_network_send.ps1` regex scan for `"server"` as recipient (future) | DEFERRED |
| 29 | Conditional registration → peer NetworkLookup drift → crash on join | `feedback_vt2_gated_registration_diverges.md` | PRE-SHIP review (every `BuffTemplates[X] = ` or `NetworkLookup.X[#X+1] = ` must be unconditional + sorted) | PRE-SHIP |
| 30 | Mutator template `server_start_function` field is dead (must hook `server.start_function`) | `feedback_vt2_mutator_template_server_wrap.md` | PRE-SHIP review pattern | PRE-SHIP |
| 31 | Husk RPC race (rpc_create_attachment arrives after cos_la_apply) | `reference_vt2_husk_rpc_race.md` | Architectural; mitigated by hook ordering | PRE-SHIP |
| 32 | Husk extension class pair (Simple* vs SimpleHusk*) — must hook both | `feedback_vt2_husk_extension_class_pair.md` | PRE-SHIP review (any hook on `Simple*Extension` must check sibling `SimpleHusk*Extension`) | PRE-SHIP |
| 33 | Lobby `combined_hash` includes `num_levels` — injecting level_keys breaks vanilla join | `reference_vt2_lobby_combined_hash.md` | Architectural; mitigated in ct via shim | PRE-SHIP |

### Vanilla-API drift issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 34 | `DeusPowerUp` rarities limited to event/rare/exotic/unique only | `reference_vt2_deus_power_up_rarities.md` | PRE-SHIP review pattern | PRE-SHIP |
| 35 | Skittergate loot_amount_settings nil for hybrid breed names | (just fixed v0.7.82 via `__index` metatable) | Caught at runtime via mod:warning; metatable is the fix | (FIXED) |
| 36 | Vanilla `NetworkedFlowStateManager` leak (fatals at 512 states) | `reference_vt2_networked_flow_state_leak.md` | Architectural; ct patches via `mod:hook` | (PATCHED) |
| 37 | Adventure-injected levels crash on no_roamers mutator | `reference_vt2_adventure_pack_spawning_compat.md` | Architectural; ct strips incompatible mutators | (PATCHED) |
| 38 | Custom ExplosionTemplates need `.name` + global registration | `reference_vt2_custom_explosion_template.md` | PRE-SHIP review | PRE-SHIP |
| 39 | VMF custom_gui_textures must list ui_renderer_injections | `reference_vmf_renderer_creator_keys.md` | PRE-SHIP review | PRE-SHIP |

### Cosmetics-specific issues (handed off to other agent group)

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 40 | Cross-character LA hat applied to wrong skeleton (j_spine1 / j_spine2 crash) | ATTACHMENT_STORAGE_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 41 | Same-character LA hat with incompatible attachment_node_linking (j_spine2 v2 — e6fc17e2 crash) | (new this session) | Cosmetics agent group | HANDED OFF |
| 42 | Vanilla offhand picks don't sync across peers | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 43 | Per-peer glow RPC unimplemented | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 44 | LA armor apply leaks icons into vanilla inventory | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 45 | `_apply_la_on_unit` offhand respawn pending-queue fragile | HOST_CLIENT_AUDIT.md | Cosmetics agent group | HANDED OFF |
| 46 | CWV ammo weapons need full skin field mirroring | `feedback_cwv_ammo_unit_required.md` | PRE-SHIP review (covered by CWV DoD gate) | PRE-SHIP |
| 47 | CWV cross-character variants — base item gets cross-mod registration | `feedback_cwv_clone_name_clobber.md` | PRE-SHIP review | PRE-SHIP |
| 48 | CWV custom-mesh — multiple pitfalls | `reference_cwv_custom_mesh_material.md` | PRE-SHIP review (CWV RECIPES.md) | PRE-SHIP |

### Docs / repo hygiene issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 49 | Stale audit/review markdown > 14 days unbanner'd; also a snapshot-banner'd doc left OUTSIDE `_archive/` (issue #502) | PROJECT_STANDARDS §7.2 | `check_stale_docs.ps1` two scans: (1) date scan (`$StaleDays = 14` default, exit 2); (2) banner-placement scan (issue #502, exit 1) - a doc whose head carries the snapshot banner ("...this snapshot is from...") but sits outside `_archive/` should be `git mv`'d there. Scan 2 is head-only (no false positive on format docs), skips `CODE_REVIEW.md` (mandatory per-mod canonical doc, §7.1) and gitignored files (untracked, not `git mv`-able). Both pinned **Advisory** in `run_all` (issue #429) - staleness is TIME-based and must not hard-block a commit/CI. Fix staleness with `run_all.ps1 -FixStale`; fix placement by archiving. | AUTO (script, advisory) |
| 50 | Memory cited claim no longer matches current code | PROJECT_STANDARDS §12.3 | PRE-SHIP review (verify before recommending) | PRE-SHIP |
| 51 | CHANGELOG entry missing for current MOD_VERSION | PROJECT_STANDARDS §6.4 | `check_versions.ps1` cross-check | AUTO (script) |
| 52 | File exceeds 2500-line hard limit | PROJECT_STANDARDS §2.1 | `check_file_sizes.ps1` line-count, **ratcheted** against `qa/baselines/file_sizes.json` (issue #429): the 13 known-oversized files are frozen; fails only on a NEW file over the limit or a baselined file growing past its frozen count. Target-tier (1500–2500) overages are plain warnings. | AUTO (script) |
| 52b | Accidental edit to a split-mod STABLE dir (dev/stable split; stable is write-by-promotion-only) — nothing previously flagged it (`promotion-status.ps1` detects the reverse). | CLAUDE.md NON-NEG #3 + `PROMOTION_PROCESS.md` | `check_dev_only_edits.ps1` — flags any staged/diffed change under `chaos_wastes_tweaker/`, `crafting_in_modded/`, `general_tweaker/`, `gui_tweaker/`, `verminious_dreams_lighting/` (NOT their `_dev` twins). ERROR (exit 2); Standard in `run_all`, `-Staged` in pre-commit. Bypass a real promotion with env `VT2_PROMOTION=1`. Self-test: `-SelfTest`. Issue #429. | AUTO (script, in run_all + pre-commit) |
| 52a | Uncited mechanic claim in the MECHANICS substrate — a factual bullet in `docs/MECHANICS.md` with no provenance tag (the hallucination-propagation class). Cure for "session drifts on a mechanic, hallucinates, wrong claim spreads." | `feedback_vmf_ui_no_guessing` (generalized to ALL mechanics) + PROJECT_STANDARDS §13 | `check_mechanics_citations.ps1` — scans ONLY `docs/MECHANICS.md`; every factual bullet under a `## Domain:` heading must carry `[src:]`/`[dump:]`/`[memory:]`/`[bugclass:]`/`[user:]` or `[unverified]`. `[unverified]` is ALLOWED + counted as the known-gaps backlog metric. ERROR (exit 2) on any untagged bullet. Self-test plants uncited + unverified + cited bullets. Wired into `run_all.ps1` (Standard policy — exit 2 blocks). | AUTO (script, in run_all) |

### Process issues

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 53 | Hot-reload assumption (Ctrl+Shift+R breaks unit-creation hooks + non-Lua resources) | `feedback_hot_reload_unfixable.md` | (info; user/Claude must full-restart for hot mods) | MANUAL |
| 54 | PS 5.1 `Get-Content -Raw` defaults to Windows-1252, not UTF-8 | `feedback_ps5_getcontent_utf8.md` | (info; affects tooling authors only) | MANUAL |
| 55 | Workshop upload metadata user-dictated (only version suffix auto-managed) | `feedback_workshop_metadata_user_dictates.md` + `feedback_version_in_workshop_title.md` | PRE-SHIP review (any cfg description change must be user-requested) | PRE-SHIP |
| 56 | Deploy to PC-B every time (launcher v0.4.0+ auto-pushes) | `feedback_deploy_both_machines.md` | Handled by VMBLauncher | (HANDLED) |
| 57 | Always Workshop-upload + publish GitHub release together | `feedback_post_workshop_upload_github_release.md` | (workflow pattern) | MANUAL |

### Logging hygiene (chat-echo / per-frame / warn-chat)

`check_logging.ps1` encodes PROJECT_STANDARDS § 3.6 (Debug logging + "Chat-echo
policy" matrix) and `docs/BUG_CLASSES.md § 17` (chat-echo spam + Variant B). Three
advisory sub-checks in one full-repo scan (mirrors `check_unpack_safety.ps1`'s
comment/string-blanking + block-depth model). Pinned **Advisory** in `run_all`;
nonzero by design (it gathers signal). Each has a false-positive-safe escape.

| # | Bug class | Memory reference | Detection | Status |
|---|---|---|---|---|
| 58a | `mod:echo` in a § 3.6 "NEVER" context — a module-load banner (not the MOD_VERSION dev banner), an `on_setting_changed`/`on_enabled`/`on_disabled` lifecycle body, or a hook-callback body — i.e. the sites BUG_CLASSES § 17 says to audit against the chat-echo matrix. Echoes in ordinary functions and `mod:command`/keybind handler bodies are NOT flagged (a static tool can't trace a reply routed through a private helper without a call graph — favor precision). | PROJECT_STANDARDS § 3.6 "Chat-echo policy" + `docs/BUG_CLASSES.md § 17` | `check_logging.ps1` category **echo**. Escape a legit § 3.6-OK-row site (high-impact toggle, `on_disabled` limitation notice, ct's "Granted N boons" hook reply) with an inline `-- allow-echo: <reason>`. | AUTO (script, advisory) |
| 58b | `mod:info`/`mod:warning` inside a per-frame callback (`function update`, `mod.update`, `X.update`/`X:update`, inline `mod:hook*(..., "update", …)`) — logs every frame, floods the console + costs a `string.format` per tick. | PROJECT_STANDARDS § 3.6 + `docs/VMF_RECIPES.md § 2b` (traced_hook per-frame caveat) | `check_logging.ps1` category **per-frame**. Escape an intentional throttled/one-shot site with `-- allow-perframe: <reason>`. | AUTO (script, advisory) |
| 58c | `mod:warning` inside a dbg/alert HELPER (`_dbg_alert`, `_spawn_dbg_alert`, a `dbg`/`alert`-named helper — not a `chat`-named one). The **Issue #240** class: `mod:warning` is believed log-only but VMF `logging.lua` defaults `warning` to mode 3 (`send_to_chat = mode >= 2`), so a "log-only alert" helper spams chat. Sanctioned form is pcall-guarded raw `printf` (et v0.7.25-dev). Genuine failure-path `mod:warning` (ordinary guards, `_safe`) is NOT flagged. | `reference_vmf_warning_channel_posts_to_chat.md` + `docs/BUG_CLASSES.md § 17 Variant B` (#240) | `check_logging.ps1` category **warn-chat**. Escape an intentional in-helper chat warning with `-- allow-warn-chat: <reason>`. | AUTO (script, advisory) |

## Coverage summary

| Category | AUTO | PRE-SHIP | MANUAL | DEFERRED | HANDED OFF | FIXED |
|---|---|---|---|---|---|---|
| Lua static | 13 | 1 | — | — | — | — |
| cfg/Workshop | 8 | — | 2 | — | — | — |
| Localization | 10 | — | — | 1 | — | — |
| Hooks / vanilla-API | — | 6 | — | — | — | — |
| Network / multiplayer | — | 5 | 1 | 1 | — | — |
| Vanilla-API drift | — | 3 | — | — | — | 3 |
| Cosmetics-specific | — | 3 | — | — | 6 | — |
| Docs hygiene | 5 | 1 | — | — | — | — |
| Process | — | 1 | 3 | — | — | 1 |
| **TOTAL** | **36** | **20** | **6** | **2** | **6** | **4** |

**49% of documented bug classes are now automatable (36/74).** Another 27%
covered by pre-ship review pattern. Remaining are architectural,
intentionally manual, or handed off.

## Current luacheck baseline

As of 2026-05-23, after initial config tuning:

- **Total warnings**: 415 (down from 1951 baseline before config tuning)
- **CWV bare globals (audit finding)**: 141 warnings — real cleanup work
  tracked in PROJECT_STANDARDS §11 #9
- **Net non-CWV warnings**: 274 — distributed across unused locals (W211),
  shadowing (W431/W621/W421/W422), nil-init (W231), unreachable code (W511),
  and a few remaining undefined globals (SDK reference materials in
  `enemy_tweaker/.spawn_tweaks_ref/` aren't part of active mods)

**Goal**: drive non-CWV warnings below 100 over the next several sessions.
As of issue #429, luacheck runs through `run_all.ps1` pinned **Advisory** in
both CI and local (the policy-engine replacement for the old CI `|| true`) —
flip it to Standard once CWV bare globals are refactored and the baseline is
clean.

## Current state of each check

| Check | Last run (2026-05-23) | Notes |
|---|---|---|
| `check_cfg.ps1` | ✅ OK | all 20 cfgs pass |
| `check_versions.ps1` | ⚠ warnings only | cfg title drift (waiting on launcher auto-rewrite) + missing-CHANGELOG warnings. Now also flags 4-segment MOD_VERSIONs as a warning (row 10a, issue #429). |
| `check_unpack_safety.ps1` | ✅ OK | all sites in ct/mp/wt either explicit-j or annotated (post-Issue #36 audit) |
| `check_vmf_widget_types.ps1` | ✅ OK | all 23 active `*_data.lua` clean post-gt v0.2.60-dev `text_input` fix (2026-05-25) |
| `check_event_register_signature.ps1` | ✅ OK | clean post-gt v0.2.61 → .64 fix cycle (2026-05-25). This static check is the live gate; the former `bt:safe_event_register` runtime safety net (buff_tweaker v0.1.10-alpha+) is RETIRED (bt archived 2026-06). |
| `check_localization.ps1` | ⚠ 28 warnings | ct BOON_TREE category_ids; et_diff_ + mut_ false-positive prefixes |
| `check_loc_tags.ps1` | ⚠ 18 warnings (2026-07-04) | 7 stable-cim `[untested]` leaks (known promotion leak, tracked for next cim promotion) + 11 `[confirmed working]` unknown-vocab in gt_dev/gut_dev (should be `[working]`). Self-test passes. Advisory (never blocks). |
| `check_issue_status_labels.ps1` | ⚠ 1 warning (2026-07-04) | Post label-audit: only #322 (a `tracked-not-fixed` context-mention in ct's #294 crash-fix entry — correctly unlabeled; the check surfaces it for review). All other latest-entry refs are labeled or in skipped loc-sweep entries. Self-test passes. Advisory (never blocks; self-exits 0 offline). |
| `check_issue_tag_sync.ps1` | ⚠ 78 warnings (2026-07-04, first run) | 0 stale tags, 2 unpaired `[diag]` (career_tweaker rework groups — standing diagnostics, likely fine), 4 label-missing (`[diag]` on #291/#259/#126/#287 without `diagnostics-armed` — reconciled same day: labels added), 72 tag-missing (vice-versa backlog: labeled fixes with no menu-surface tag — mostly legitimate § 13.3 exemptions, reported compactly). Self-test passes. Advisory (never blocks; self-exits 0 offline). |
| `run_selftests.ps1` | ✅ OK (2026-07-05) | Unit-test entry point: auto-discovers every `qa/check_*.ps1` with a `[switch]$SelfTest` param (9 as of 2026-07-05) plus `tools/ship/ship.ps1` (step-6 labeling logic), runs each `-SelfTest`, replays output on failure. All fixture-based/offline, ~1s total. Exit 2 on any regression — Standard policy in `run_all` (full pass, not `-Quick`) so a broken check BLOCKS; also a blocking CI step in `qa.yml`. Failure path verified with a planted failing check. |
| `check_name_integrity.ps1` | ⚠ baselined (issue #429) | 4 errors fire locally (VtSrc present); 14 in CI / no-VtSrc — all frozen in `qa/baselines/name_integrity.json` (the no-VtSrc superset), so the check is NON-BLOCKING on the pre-existing set and blocks only on a NEW error. Wired into `run_all` full (Standard). Self-test passes. |
| `check_decisions_wired.ps1` | ⚠ exit 1 (2026-05-30, in run_all full pass) | 95 decisions parsed: 77 WIRED, 0 REGRESSION, 0 LEAK, 2 PENDING (`Kruber/dr_dual_wield_hammers` stale doc row, `Kruber/we_javelin` deferred-experimental), 78 ORPHAN (Saltzpyre/Kerillian decision sections stubbed — code ahead of doc), 1 UNCLASSIFIABLE. Self-test passes. |
| `check_mechanics_citations.ps1` | ✅ OK (2026-05-30) | 45 cited factual bullets across 8 domains (`[src:]` decompiled-verified, `[memory:]`, `[bugclass:]`, `[dump:]`), 4 honest `[unverified]` gaps, 0 uncited. Self-test passes. Run the script for the live per-domain breakdown. |
| `check_file_sizes.ps1` | ⚠ baselined (issue #429) | 13 files over the 2500-line hard limit, all frozen in `qa/baselines/file_sizes.json`; non-blocking until a NEW file crosses the limit or a baselined one grows. Target-tier overages remain plain warnings. |
| `check_dev_only_edits.ps1` | ✅ OK (2026-07-08) | Dev/stable split guard (row 52b, issue #429). Standard in `run_all`, `-Staged` in pre-commit. Clean working tree = exit 0. Self-test passes. |
| `check_logging.ps1` | ⚠ 56 findings (2026-07-08, first run) | Rows 58a/b/c (issue #429). echo=36 (§ 3.6 NEVER-context echoes — hook bodies, on_enabled/on_disabled, cim/gt/wt anim-log traces), per-frame=4 (cosmetics `mod.update` LA-sync `mod:info`), warn-chat=16 (every mod's `_dbg_alert` → `mod:warning`, the Issue #240 class — the migration-to-printf backlog). Advisory (never blocks). Self-test 5/5. |
| `check_hook_test_coverage.ps1` | ✅ OK (2026-07-08, first run) | Row 24a (issue #429). Diff-scoped (default `HEAD~1..HEAD`, `-Staged`, or CI `origin/<base>...HEAD`). Over `HEAD~10..HEAD` all added hooks/NL-writes resolved covered (mods ship suites). Advisory in `run_all` + warn-only pre-commit step 4. Self-exits 0 on indeterminate diff. Self-test 7/7. |
| `check_stale_docs.ps1` | ⚠ 19 stale (advisory) | Pinned Advisory in `run_all` (issue #429) — TIME-based, non-blocking. 19 docs currently >14 days (script `$StaleDays` default) without a SUPERSEDED banner; fix with `-FixStale`. |
| `luacheck` | ⚠ ~415 warnings (advisory) | Pinned Advisory in `run_all` AND CI (issue #429; was CI `\|\| true`). Baseline; 141 = CWV finding, 274 net real signal. Drive down, then flip to Standard. |

## Generated name-map (key → display-name) + integrity validator

The authoritative INTERNAL-key → in-game DISPLAY-name map is **generated**, not
hand-maintained — see `docs/generated/README.md`. Two related pieces:

```powershell
# 1. Regenerate the authoritative map (date is a required param — env has no clock):
pwsh -NoProfile -File tools/gen-name-map/gen-name-map.ps1 -GenDate 2026-05-30
#    -> docs/generated/NAME_MAP.generated.json  (machine-authoritative)
#    -> docs/generated/NAME_MAP.generated.md    (grep this, not the legacy catalogs)

# 2. Validate localization integrity (3 checks: missing setting_id loc = ERROR,
#    unresolvable assigned name = ERROR, orphan loc key = WARN):
pwsh -NoProfile -File qa/check_name_integrity.ps1            # all mods
pwsh -NoProfile -File qa/check_name_integrity.ps1 -SelfTest  # planted-fault proof
```

`check_name_integrity.ps1` reads `NAME_MAP.generated.json` as a runtime-name
oracle (so cwv/cosmetics runtime-registered names don't false-positive) — run the
generator first for best results. It **is wired into `run_all.ps1`** (Standard)
and, as of issue #429, **ratcheted**: the pre-existing errors are frozen in
`qa/baselines/name_integrity.json` (the no-VtSrc superset, so the same file
covers CI and local), and the check blocks only on a NEW error. The oracle is
committed, so it resolves identically in CI and locally; only the decompiled
`Vermintide-2-Source-Code` differs, which is exactly why the baseline is
generated in the no-VtSrc view. (Not yet in the launcher's blocking upload
preflight; that would mirror the `QaScriptGate.RunAsync(mod, ...)` pattern in
`tools/vmb-launcher/Services/ModRunner.cs`, exit 2 = block.)

## What's NOT covered yet (gaps)

1. **Network send recipient validation** (#28): would need a `check_network_send.ps1`
   that grep's for `mod:network_send` and verifies the 2nd arg is `"all"`,
   `"others"`, `"local"`, or a peer_id literal — not `"server"`.

2. **CHANGELOG format consistency** (#20): three styles in use across mods.
   Could be normalized by `check_changelog_format.ps1` — low ROI, skip until
   it bites.

3. **Wrong-key storage access at runtime** (#6): caught only by reading vanilla
   source carefully. PRE-SHIP review is the safety net.

4. **Same-character LA hat with template-vs-mesh node mismatch** (#41, this
   session's e6fc17e2 crash): handed off to cosmetics agent group.

5. **In-game smoke tests**: no headless Stingray runtime. Would require
   instrumented in-game commands that auto-verify state after every load.
   Tracked in PROJECT_STANDARDS §11 as future work.

## How to add a check

When a new bug class is discovered:
1. **Document the bug** in a memory file (`feedback_*.md` or `reference_*.md`).
2. **Add a row** to the appropriate table above with:
   - Bug class name
   - Memory file reference
   - Detection method
   - Status
3. **If AUTO**: scaffold the script in `qa/check_<name>.ps1`, wire into `qa/run_all.ps1`.
4. **If PRE-SHIP**: update PROJECT_STANDARDS §5.3 review template.
5. **If MANUAL**: ensure CLAUDE.md or PROJECT_STANDARDS surface the rule.

## When this doc is wrong

If a check name doesn't match the script, fix one or the other. If a bug class
is missing from the tables, add it. This is a living index, not a snapshot.
