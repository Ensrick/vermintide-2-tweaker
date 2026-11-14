import os, re, json, glob, collections
REPO = r"<repos>/vermintide-2-tweaker"
DATA = r"<audit-workspace>/data"
tests = {}
for p in glob.glob(os.path.join(REPO, "qa", "lua", "tests", "*.lua")):
    tests[os.path.basename(p)] = open(p, encoding="utf-8", errors="replace").read()
rt = json.load(open(r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\rt_checks_classified.json", encoding="utf-8"))
issues = {}
for b in glob.glob(os.path.join(DATA, "bucket_*.tsv")):
    for i, line in enumerate(open(b, encoding="utf-8", errors="replace")):
        if i == 0: continue
        f = line.rstrip("\n").split("\t")
        issues[int(f[0])] = f[5]
def has(n, text):
    return re.search(r"(?:#|[Ii]ssue[ _]?|[a-z]{2,4})%d(?![0-9])" % n, text) is not None
res = collections.Counter(); cards_with_rt = 0
for n, labels in sorted(issues.items()):
    life = "verify-fix" if "verify-fix" in labels else "diagnostics-armed" if "diagnostics-armed" in labels else "not-started" if "not-started" in labels else "other"
    t = [k for k, v in tests.items() if re.search(r"(?:#|[Ii]ssue[ _]?)%d(?![0-9])" % n, v)]
    r = [o["name"] for o in rt if re.search(r"(?<![0-9])%d(?![0-9])" % n, o["name"])]
    res[(life, "offline_test" if t else "-", "rt_check" if r else "-")] += 1
    p = os.path.join(r"<audit-workspace>/issues\open", "%d.md" % n)
    if life == "verify-fix" and os.path.exists(p):
        s = open(p, encoding="utf-8", errors="replace").read()
        blocks = [b for b in s.split("## COMMENT by ") if "## CURRENT LIVE TEST" in b]
        if blocks and re.search(r"_regression_test|PASS: ", blocks[-1]): cards_with_rt += 1
tot = collections.Counter()
for (life, a, b), v in sorted(res.items()):
    print(f"{life:18s} {a:13s} {b:9s} {v}")
    tot[life] += v
print(dict(tot)); print("verify-fix cards whose newest card already names a regression command/PASS line:", cards_with_rt)
