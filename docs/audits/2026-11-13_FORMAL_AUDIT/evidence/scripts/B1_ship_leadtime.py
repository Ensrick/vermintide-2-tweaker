#!/usr/bin/env python3
"""B1: per-ship lead times from release asset names (source commit) and git history. Read-only."""
import subprocess, re, datetime as dt, statistics, json, collections
REPO = r"<repos>/vermintide-2-tweaker"
D = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts"
def git(*a): return subprocess.run(["git", "-C", REPO, *a], capture_output=True).stdout.decode("utf-8", "replace").strip()
def ts(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
rows = [l.rstrip("\n").split("\t") for l in open(D + r"\B1_release_assets.tsv", encoding="utf-8") if "\t" in l]
prs = {p["number"]: p for p in json.load(open(D + r"\B1_prs_merged.json", encoding="utf-8"))}
ships = []
for t, n, s, c, u in rows:
    m = re.match(r"workshop-upload-result-(.+?)-([0-9a-f]{40})-", n)
    if not m: continue
    mod, sha = m.group(1), m.group(2)
    ct = git("show", "-s", "--format=%cI", sha)
    subj = git("show", "-s", "--format=%s", sha)
    if not ct: continue
    prn = re.search(r"Merge pull request #(\d+)", subj)
    pr = prs.get(int(prn.group(1))) if prn else None
    # last commit touching this mod's lua before/at source commit (the change that needed shipping)
    lastsrc = git("log", "-1", "--format=%cI", sha, "--", f"{mod}/scripts")
    ships.append(dict(mod=mod, sha=sha, asset=ts(c), merged=dt.datetime.fromisoformat(ct), pr=pr, subj=subj, lastsrc=dt.datetime.fromisoformat(lastsrc) if lastsrc else None))
def q(xs, p): xs = sorted(xs); return xs[min(len(xs) - 1, int(len(xs) * p))]
m2s = [(s["asset"] - s["merged"]).total_seconds() / 60 for s in ships]
print(f"verified ships analysed: {len(ships)}")
print("source-commit(master HEAD) -> verified Workshop upload result, minutes: p50=%.0f p75=%.0f p90=%.0f min=%.0f max=%.0f" % (q(m2s, .5), q(m2s, .75), q(m2s, .9), min(m2s), max(m2s)))
src = [(s["asset"] - s["lastsrc"]).total_seconds() / 3600 for s in ships if s["lastsrc"]]
print("last mod-source change on master -> verified upload, hours: p50=%.1f p75=%.1f p90=%.1f max=%.1f" % (q(src, .5), q(src, .75), q(src, .9), max(src)))
# is the shipped source commit itself the PR that changed the mod? (else HEAD moved by unrelated merges)
same = 0
for s in ships:
    files = git("diff", "--name-only", s["sha"] + "^1", s["sha"], "--", s["mod"])
    if files: same += 1
print(f"ships whose source commit (master HEAD at ship) itself changed the shipped mod: {same}/{len(ships)}")
byday = collections.Counter(s["asset"].date().isoformat() for s in ships)
print("ships per day: max=%d median=%d days=%d" % (max(byday.values()), statistics.median(byday.values()), len(byday)))
gaps = sorted(set(byday))
print("ship days:", ", ".join(f"{d[5:]}x{byday[d]}" for d in gaps))
