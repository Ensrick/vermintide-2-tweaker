#!/usr/bin/env python3
"""B1: delivery metrics from cached gh JSON (read-only)."""
import json, sys, re, statistics, collections, datetime as dt
D = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts"
def ts(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
def pct(xs, p):
    xs = sorted(xs)
    if not xs: return float("nan")
    k = (len(xs) - 1) * p
    f = int(k); c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)

runs = json.load(open(D + r"\B1_runs.json", encoding="utf-8"))
print(f"== workflow runs: {len(runs)}  window {min(r['createdAt'] for r in runs)} .. {max(r['createdAt'] for r in runs)}")
by = collections.defaultdict(list)
for r in runs: by[(r.get("workflowName") or r["name"], r["event"])].append(r)
print(f"{'workflow':40s} {'event':22s} {'n':>4s} {'ok':>4s} {'fail':>4s} {'canc':>4s} {'skip':>4s} {'other':>5s} {'fail%':>6s} {'p50min':>7s} {'p90min':>7s}")
for k in sorted(by, key=lambda k: -len(by[k])):
    rs = by[k]
    c = collections.Counter(r["conclusion"] or r["status"] for r in rs)
    durs = [(ts(r["updatedAt"]) - ts(r["createdAt"])).total_seconds() / 60 for r in rs if r["conclusion"] in ("success", "failure")]
    done = c["success"] + c["failure"]
    other = len(rs) - c["success"] - c["failure"] - c["cancelled"] - c["skipped"]
    print(f"{k[0][:40]:40s} {k[1][:22]:22s} {len(rs):4d} {c['success']:4d} {c['failure']:4d} {c['cancelled']:4d} {c['skipped']:4d} {other:5d} {100*c['failure']/done if done else 0:6.1f} {pct(durs,.5):7.1f} {pct(durs,.9):7.1f}")

prs = json.load(open(D + r"\B1_prs_merged.json", encoding="utf-8"))
print(f"\n== merged PRs fetched: {len(prs)}  merged window {min(p['mergedAt'] for p in prs)} .. {max(p['mergedAt'] for p in prs)}")
now = dt.datetime(2026, 11, 14, tzinfo=dt.timezone.utc)
cut = now - dt.timedelta(days=90)
recent = [p for p in prs if ts(p["mergedAt"]) >= cut]
print(f"merged in last 90 days (since {cut.date()}): {len(recent)}")
lead = [(ts(p["mergedAt"]) - ts(p["createdAt"])).total_seconds() / 3600 for p in recent]
if lead:
    print(f"PR lead time hours (created->merged): p50={pct(lead,.5):.2f} p75={pct(lead,.75):.2f} p90={pct(lead,.9):.2f} max={max(lead):.1f} mean={statistics.mean(lead):.2f}")
permonth = collections.Counter(p["mergedAt"][:7] for p in prs)
print("merged per month:", dict(sorted(permonth.items())))

PIPE = re.compile(r"(?i)\b(ship|pipeline|publication|publish|release|receipt|claim|lease|pin|pins|ci\b|qa[- ]gate|gate|workflow|hook|pre-commit|authority|bundle authority|atomicity|provenance|launcher|vmb|promotion|promote|card|cards|live[- ]test|lifecycle|label|tracker|closure|census|worktree|manifest|snapshot|reconcil|metadata|docs?\b|standards|runbook|policy|contract|selftest|self-test|ps5\.?1|eol|crlf|normaliz)")
PROD = re.compile(r"(?i)^\s*(\[?(wt|ct|cim|gt|gut|cwv|woc|bt|et|mp|dcp|cosmetics?|career|vdl|enemy|event)(_dev|-dev)?\b|weapon|chaos|crafting|general|gui|cosmetic|portrait|career|modded|lighting|character)")
def classify(t):
    tl = t.lower()
    # title-based heuristic; 'both' when a product prefix AND pipeline words
    pipe = bool(PIPE.search(t)); prod = bool(PROD.search(t)) or bool(re.search(r"\bv?\d+\.\d+\.\d+(-\w+)?\b", t))
    if prod and not pipe: return "product"
    if pipe and not prod: return "process"
    if prod and pipe: return "mixed"
    return "unclassified"
cls = collections.Counter(classify(p["title"]) for p in recent)
print("title-heuristic classification (last 90d):", dict(cls))
if "--titles" in sys.argv:
    for p in sorted(recent, key=lambda p: p["mergedAt"]):
        print(f"  #{p['number']:5d} {p['mergedAt'][:10]} {classify(p['title']):12s} {p['headRefName'][:38]:38s} {p['title'][:110]}")
