#!/usr/bin/env python3
"""B1: LOC of release pipeline vs product. Read-only: uses `git ls-files` and reads tracked files."""
import subprocess, os, re, sys, collections
REPO = r"<repos>/vermintide-2-tweaker"
files = subprocess.run(["git", "-C", REPO, "ls-files", "-z"], capture_output=True).stdout.decode("utf-8", "replace").split("\0")
files = [f for f in files if f]
TEXT_EXT = {".lua", ".ps1", ".psm1", ".psd1", ".py", ".md", ".yml", ".yaml", ".cs", ".json", ".cfg", ".mod", ".txt", ".sh", ".js", ".toml", ".ini"}

RELEASE_QA = re.compile(r"^qa/(check|run)_(publication_|release_|build_|bundle_|deployed_source_proof|local_deployment_receipt|machine_transaction|permanent_claim_allocation|promotion|public_release_closure_|published_ids|source_provenance|live_card_receipts|pipeline_state|workshop_|current_source_pin_recovery|github_release_fallback|ci_hardening|pr_autoclose|content_manifest|vmb_launcher_path|worktree_budget|branch_reconciliation_census|wt_history_|wt_stream_parity|versions|dev_only_edits|in_progress|issue_status_labels|ps51_|unpack_safety|mod_inventory|stale_docs|diff_whitespace|mod_descriptor_line_endings)")

def bucket(f):
    top = f.split("/")[0]
    ext = os.path.splitext(f)[1].lower()
    if f.startswith("tools/ship/"): return "pipeline:tools/ship"
    if f.startswith("tools/publish-release/"): return "pipeline:tools/publish-release"
    if f.startswith("tools/promote/"): return "pipeline:tools/promote"
    if f.startswith("tools/verify/"): return "pipeline:tools/verify"
    if f.startswith("tools/github/"): return "pipeline:tools/github"
    if f.startswith("tools/review/"): return "pipeline:tools/review"
    if f.startswith("tools/worktrees/"): return "pipeline:tools/worktrees"
    if f.startswith("tools/hooks/") or f == "tools/install-hooks.ps1": return "pipeline:tools/hooks"
    if f.startswith("tools/weapon-history/"): return "pipeline:tools/weapon-history"
    if f.startswith("tools/"): return "tools:other"
    if f.startswith(".github/"): return "pipeline:.github"
    if RELEASE_QA.match(f): return "pipeline:qa-release-gates"
    if f.startswith("qa/_test_fixtures/") or f.startswith("qa/fixtures/") or f.startswith("qa/baselines/") or f.startswith("qa/oracles/"): return "qa:fixtures-baselines"
    if f.startswith("qa/lua/"): return "qa:lua-tests"
    if f.startswith("qa/"): return "qa:other-gates"
    if f.startswith("docs/"): return "docs"
    if "/" not in f: return "root-files"
    # mod dirs
    if ext == ".lua" and "/scripts/mods/" in f: return "product:mod-lua"
    if ext == ".lua": return "product:other-lua"
    return "mod-dir:other(" + (ext or "noext") + ")"

stats = collections.defaultdict(lambda: [0, 0, 0])  # files, lines, bytes
perfile = []
for f in files:
    p = os.path.join(REPO, f)
    if not os.path.isfile(p):
        continue
    b = bucket(f)
    size = os.path.getsize(p)
    ext = os.path.splitext(f)[1].lower()
    lines = 0
    if ext in TEXT_EXT:
        with open(p, "rb") as fh:
            data = fh.read()
        lines = data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)
    s = stats[b]
    s[0] += 1; s[1] += lines; s[2] += size
    perfile.append((b, f, lines, size))

print(f"{'bucket':44s} {'files':>6s} {'lines':>9s} {'KiB':>9s}")
tot = [0, 0, 0]
for b in sorted(stats):
    s = stats[b]
    print(f"{b:44s} {s[0]:6d} {s[1]:9d} {s[2]/1024:9.0f}")
    for i in range(3): tot[i] += s[i]
print(f"{'TOTAL':44s} {tot[0]:6d} {tot[1]:9d} {tot[2]/1024:9.0f}")
pipe = sum(s[1] for b, s in stats.items() if b.startswith("pipeline:"))
prod = stats["product:mod-lua"][1]
print(f"\npipeline lines total: {pipe}")
print(f"product mod-lua lines: {prod}")
if "--top" in sys.argv:
    for b in sorted(stats):
        if not b.startswith("pipeline:"): continue
        print("\n==", b)
        for bb, f, l, sz in sorted([x for x in perfile if x[0] == b], key=lambda x: -x[2])[:60]:
            print(f"  {l:7d}  {f}")
