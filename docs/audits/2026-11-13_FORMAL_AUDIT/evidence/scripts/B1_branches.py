#!/usr/bin/env python3
"""B1: branch census (read-only: for-each-ref, branch --merged)."""
import subprocess, collections, datetime as dt, re
REPO = r"<repos>/vermintide-2-tweaker"
def git(*a): return subprocess.run(["git", "-C", REPO, *a], capture_output=True).stdout.decode("utf-8", "replace")
now = dt.datetime(2026, 11, 13, tzinfo=dt.timezone.utc)
for scope, ref in (("local", "refs/heads"), ("remote", "refs/remotes/origin")):
    rows = [l.split("|") for l in git("for-each-ref", "--format=%(refname:short)|%(committerdate:iso-strict)|%(objectname)", ref).splitlines() if l]
    merged = set(l.strip().lstrip("* ").strip() for l in git("branch", "--merged", "master", *( ["-r"] if scope == "remote" else [])).splitlines())
    n = len(rows); m = sum(1 for r in rows if r[0] in merged)
    ages = [(now - dt.datetime.fromisoformat(r[1])).days for r in rows]
    buckets = collections.Counter("<=7d" if a <= 7 else "8-30d" if a <= 30 else "31-90d" if a <= 90 else ">90d" for a in ages)
    pref = collections.Counter(re.split(r"[/-]", r[0].replace("origin/", ""), 1)[0] for r in rows)
    unmerged_old = sum(1 for r, a in zip(rows, ages) if r[0] not in merged and a > 30)
    print(f"{scope}: {n} branches; fully merged into master: {m}; NOT merged: {n-m}; not merged and >30d old: {unmerged_old}")
    print("   age buckets:", dict(buckets))
    print("   top prefixes:", pref.most_common(12))
# other ref namespaces
allrefs = git("for-each-ref", "--format=%(refname)").splitlines()
ns = collections.Counter("/".join(r.split("/")[:2]) for r in allrefs)
print("ref namespaces:", dict(ns.most_common(12)))
print("stash entries:", len(git("stash", "list").splitlines()))
tags = git("tag").splitlines()
tp = collections.Counter(re.split(r"[-_/v0-9]", t, 1)[0] or t[:6] for t in tags)
print("tags:", len(tags), tp.most_common(8))
