#!/usr/bin/env python3
"""B1: line churn by path class on master first-parent since a date. Read-only."""
import subprocess, collections, re, sys
REPO = r"<repos>/vermintide-2-tweaker"
SINCE = sys.argv[1] if len(sys.argv) > 1 else "2026-08-15"
out = subprocess.run(["git", "-C", REPO, "log", "master", "--first-parent", "-m", f"--since={SINCE}", "--numstat", "--no-renames",
                      "--pretty=format:@@%H|%ad", "--date=short"], capture_output=True).stdout.decode("utf-8", "replace")
def fclass(f):
    if "/scripts/mods/" in f and f.endswith(".lua"):
        if re.search(r"(regression|_rt_|_diag|diagnostic|_test)", f): return "mod-lua:regression/diag modules"
        return "mod-lua:feature code"
    if "/bundleV2/" in f or f.endswith(".build-receipt.json"): return "artifact/receipt"
    if f.startswith("tools/verify/live_test_contract_exceptions"): return "pins psd1"
    if f.startswith("tools/weapon-history/") or f.startswith("qa/check_wt_history") or f.startswith("qa/run_wt_history"): return "wt-history tooling"
    if f.startswith(("tools/ship/", "tools/publish-release/", "tools/promote/", "tools/verify/", "tools/github/", "tools/review/", "tools/worktrees/", "tools/hooks/", ".github/")): return "release/tracker tooling"
    if f.startswith("tools/"): return "other tools"
    if f.startswith("qa/lua/"): return "qa lua unit tests"
    if f.startswith("qa/"): return "qa gates (ps1)"
    if f.startswith("docs/generated/"): return "generated docs"
    if f.endswith(".md"): return "docs/changelogs"
    return "other"
add = collections.Counter(); dele = collections.Counter(); n = 0
for line in out.splitlines():
    if line.startswith("@@"): n += 1; continue
    p = line.split("\t")
    if len(p) != 3 or p[0] == "-": continue
    c = fclass(p[2]); add[c] += int(p[0]); dele[c] += int(p[1])
print(f"since {SINCE}: {n} first-parent commits")
T = sum(add.values())
print(f"{'class':36s} {'added':>9s} {'deleted':>9s} {'share of added':>15s}")
for c, v in add.most_common():
    print(f"{c:36s} {v:9d} {dele[c]:9d} {100*v/T:14.1f}%")
