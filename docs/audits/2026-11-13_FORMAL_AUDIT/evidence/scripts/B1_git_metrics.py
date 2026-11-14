#!/usr/bin/env python3
"""B1: commit volume per month and path-class share. Read-only (git log)."""
import subprocess, collections, re, sys
REPO = r"<repos>/vermintide-2-tweaker"
SINCE = sys.argv[1] if len(sys.argv) > 1 else "2026-04-01"
out = subprocess.run(["git", "-C", REPO, "log", "master", "--first-parent", f"--since={SINCE}", "--name-only", "--no-renames",
                      "--pretty=format:@@%H|%ad|%an|%s", "--date=short", "-m"], capture_output=True).stdout.decode("utf-8", "replace")
commits = []
cur = None
for line in out.splitlines():
    if line.startswith("@@"):
        h, d, a, s = line[2:].split("|", 3)
        cur = {"h": h, "d": d, "a": a, "s": s, "files": []}
        commits.append(cur)
    elif line.strip() and cur is not None:
        cur["files"].append(line.strip())

def fclass(f):
    if "/scripts/mods/" in f and f.endswith(".lua"): return "modsrc"
    if "/bundleV2/" in f or f.endswith(".build-receipt.json"): return "artifact"
    if f.endswith("itemV2.cfg") or f.endswith(".mod"): return "modmeta"
    if re.match(r"^[a-z_]+/CHANGELOG\.md$", f): return "changelog"
    if f.startswith("tools/verify/live_test_contract_exceptions") or f.startswith("tools/verify/deployed_source_incident"): return "pins"
    if f.startswith("tools/") or f.startswith(".github/"): return "tooling"
    if f.startswith("qa/lua/"): return "luatests"
    if f.startswith("qa/"): return "qa"
    if f.startswith("docs/") or f.endswith(".md"): return "docs"
    return "other"

def cclass(c):
    k = set(fclass(f) for f in c["files"])
    if not k: return "empty"
    if "modsrc" in k: return "product(mod-lua touched)"
    if k <= {"pins"} : return "pins-only"
    if k <= {"artifact", "modmeta", "changelog", "pins"}: return "release-paperwork-only"
    if k <= {"tooling", "qa", "docs", "pins", "luatests", "other", "artifact", "changelog", "modmeta"} and ("tooling" in k or "qa" in k):
        return "tooling/qa(no mod-lua)"
    if k <= {"docs", "changelog", "other", "pins"}: return "docs-only"
    if k <= {"luatests", "docs", "other"}: return "lua-tests-only"
    return "other-mix"

bymonth = collections.defaultdict(collections.Counter)
for c in commits:
    bymonth[c["d"][:7]][cclass(c)] += 1
classes = sorted({k for m in bymonth.values() for k in m})
print(f"first-parent commits on master since {SINCE}: {len(commits)}")
print(f"{'month':8s} {'total':>6s} " + " ".join(f"{k[:24]:>24s}" for k in classes))
tot = collections.Counter()
for m in sorted(bymonth):
    row = bymonth[m]; t = sum(row.values()); tot.update(row)
    print(f"{m:8s} {t:6d} " + " ".join(f"{row[k]:24d}" for k in classes))
T = sum(tot.values())
print(f"{'ALL':8s} {T:6d} " + " ".join(f"{tot[k]:24d}" for k in classes))
print("share: " + ", ".join(f"{k}={100*tot[k]/T:.1f}%" for k in classes))
# file-change volume by class
fc = collections.Counter()
for c in commits:
    for f in c["files"]: fc[fclass(f)] += 1
print("file-touch counts by class:", dict(fc.most_common()))
auth = collections.Counter(c["a"] for c in commits)
print("authors:", dict(auth.most_common(8)))
if "--last90" in sys.argv:
    import datetime as dt
    cut = (dt.date(2026, 11, 13) - dt.timedelta(days=90)).isoformat()
    r = collections.Counter(cclass(c) for c in commits if c["d"] >= cut)
    n = sum(r.values())
    print(f"\nlast 90 days (since {cut}): {n} commits")
    for k, v in r.most_common(): print(f"  {k:30s} {v:5d} {100*v/n:5.1f}%")
