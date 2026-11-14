#!/usr/bin/env python3
"""B1: refined pipeline-vs-product LOC (explicit gate list). Read-only."""
import subprocess, os, re, collections
REPO = r"<repos>/vermintide-2-tweaker"
files = [f for f in subprocess.run(["git", "-C", REPO, "ls-files", "-z"], capture_output=True).stdout.decode("utf-8", "replace").split("\0") if f]
REL_QA = re.compile(r"^qa/(check|run)_(publication_|release_|build_|bundle_|deployed_source_proof|local_deployment_receipt|machine_transaction|permanent_claim_allocation|promotion|public_release_closure_|published_ids|source_provenance|live_card_receipts|pipeline_state|workshop_|current_source_pin_recovery|github_release_fallback|ci_hardening|pr_autoclose|content_manifest|vmb_launcher_path|worktree_budget|branch_reconciliation_census|live_test_contract|issue_status_labels|in_progress|dev_only_edits|versions|ps51_|wt_stream_parity|mod_inventory)")
REL_QA_OTHER = {"qa/promotion_version_reader.ps1", "qa/worktree_state.ps1", "qa/PUBLISHED_IDS.md"}
def lines(p):
    with open(p, "rb") as fh: d = fh.read()
    return d.count(b"\n")
def nonblank_code(p):
    n = 0
    with open(p, "rb") as fh:
        for l in fh:
            s = l.strip()
            if s and not s.startswith(b"#") and not s.startswith(b"--"): n += 1
    return n
B = collections.defaultdict(lambda: [0, 0, 0])
for f in files:
    p = os.path.join(REPO, f)
    if not os.path.isfile(p): continue
    ext = os.path.splitext(f)[1].lower()
    if ext not in (".ps1", ".psm1", ".psd1", ".cs", ".yml", ".lua", ".py", ".md"): continue
    if f.startswith(("tools/ship/", "tools/publish-release/", "tools/promote/", "tools/worktrees/", "tools/hooks/")) or f in ("tools/install-hooks.ps1", "tools/vmb-launcher-path.ps1"): b = "A release pipeline: ship/publish/promote/worktrees/hooks"
    elif f.startswith(("tools/verify/", "tools/github/", "tools/review/")): b = "B tracker/card authority: tools/verify, tools/github, tools/review"
    elif f.startswith(".github/"): b = "C .github workflows/templates"
    elif REL_QA.match(f) or f in REL_QA_OTHER: b = "D release-paperwork QA gates (qa/check_*, run_*)"
    elif f.startswith("qa/lua/"): b = "T qa/lua unit tests"
    elif f.startswith("qa/") and ext in (".ps1", ".psd1", ".py"): b = "Q other QA gates (code/content checks, wt-history repro)"
    elif f.startswith("tools/") : b = "O other tools (lint, weapon-history, diagnostics...)"
    elif "/scripts/mods/" in f and ext == ".lua": b = "P product mod Lua"
    else: continue
    if ext == ".md" and not b.startswith(("A", "B", "C")): continue
    s = B[b]; s[0] += 1; s[1] += lines(p); s[2] += nonblank_code(p) if ext != ".md" else 0
print(f"{'bucket':66s} {'files':>5s} {'lines':>8s} {'code lines*':>11s}")
for b in sorted(B): print(f"{b:66s} {B[b][0]:5d} {B[b][1]:8d} {B[b][2]:11d}")
pipe = sum(B[b][1] for b in B if b[0] in "ABCD"); pipec = sum(B[b][2] for b in B if b[0] in "ABCD")
prod = B["P product mod Lua"]
print(f"\nPIPELINE (A+B+C+D): {pipe} lines, {pipec} code lines*   | product mod Lua: {prod[1]} lines, {prod[2]} code lines* in {prod[0]} files")
print("* non-blank lines not starting with a comment marker")
