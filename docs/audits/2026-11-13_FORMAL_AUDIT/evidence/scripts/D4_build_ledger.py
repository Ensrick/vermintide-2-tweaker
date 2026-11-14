# D4 ledger builder: rows are authored in D4_rows_*.py, written to findings/D4_ledger.tsv,
# and validated against the bucket TSVs. Read-only on the repo. Usage: py -3 D4_build_ledger.py
import os, sys
from collections import Counter
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BASE = r"<audit-workspace>"
HDR = ["number", "mod", "author_class", "type", "lifecycle", "priority", "summary", "cluster", "fix_state",
       "verification_class", "auto_check", "disposition", "related", "confidence", "note"]
R = []


def row(*a):
    assert len(a) == len(HDR), (a[0], len(a))
    R.append([str(x).replace("\t", " ").replace("\n", " ") for x in a])


FSU = "fix-shipped-unverified"
here = os.path.dirname(os.path.abspath(__file__))
for part in ("D4_rows_a.py", "D4_rows_b.py", "D4_rows_c.py"):
    exec(compile(open(os.path.join(here, part), encoding="utf-8").read(), part, "exec"))

out = os.path.join(BASE, "findings", "D4_ledger.tsv")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("\t".join(HDR) + "\n")
    for r in R:
        f.write("\t".join(r) + "\n")

want = {}
for b in ("bucket_D_cim_mp_career.tsv", "bucket_E_gui.tsv"):
    for i, line in enumerate(open(os.path.join(BASE, "data", b), encoding="utf-8", errors="replace")):
        if i == 0:
            continue
        p = line.rstrip("\n").split("\t")
        if p and p[0].isdigit():
            want[int(p[0])] = p
have = [int(r[0]) for r in R]
print("rows:", len(R), "distinct:", len(set(have)), "bucket issues:", len(want))
print("missing:", sorted(set(want) - set(have)), "extra:", sorted(set(have) - set(want)))
for col in ("author_class", "type", "lifecycle", "priority", "verification_class", "confidence", "mod"):
    i = HDR.index(col)
    print(col, dict(Counter(r[i] for r in R).most_common()))
i = HDR.index("disposition")
print("disposition", dict(Counter(r[i].split(":")[0] for r in R).most_common()))
i = HDR.index("cluster")
print("cluster", dict(Counter(r[i] for r in R).most_common()))
i = HDR.index("fix_state")
print("fix_state", dict(Counter(r[i].split(" (")[0].split(":")[0] for r in R).most_common()))
# cross tab: verification class x disposition
vc = HDR.index("verification_class")
dp = HDR.index("disposition")
print("class x disposition", dict(Counter((r[vc], r[dp].split(":")[0]) for r in R).most_common()))
lc_i = HDR.index("lifecycle")
print("class x lifecycle", dict(Counter((r[vc], r[lc_i]) for r in R).most_common()))
for r in R:
    if len(r[6].split()) > 20:
        print("summary>20 words:", r[0], len(r[6].split()))
    if len(r[10].split()) > 30:
        print("auto_check>30 words:", r[0], len(r[10].split()))
for n, p in sorted(want.items()):
    labels = p[5]
    r = next(x for x in R if int(x[0]) == n)
    lc = ("verify-fix" if "verify-fix" in labels else "diagnostics-armed" if "diagnostics-armed" in labels
          else "not-started" if "not-started" in labels else "?")
    if "blocked" in labels and lc == "not-started":
        lc = "not-started+blocked"
    if lc != r[4]:
        print("lifecycle mismatch", n, "labels:", lc, "ledger:", r[4])
    pr = [x for x in labels.split(",") if x[:2] in ("0-", "1-", "2-", "3-")]
    if pr and pr[0] != r[5]:
        print("priority mismatch", n, pr[0], r[5])
    ac = "owner" if p[1] == "Ensrick" else "rain" if p[1] == "RainReligion" else "external"
    if ac != r[2]:
        print("author mismatch", n, p[1], r[2])
