import sys, io, os, re, collections
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from D2_ledger_rows_a import ROWS_A
from D2_ledger_rows_b import ROWS_B
rows = ROWS_A + ROWS_B
TAB = chr(9); NL = chr(10)
hdr = ["number","mod","author_class","type","lifecycle","priority","summary","cluster","fix_state","verification_class","auto_check","disposition","related","confidence","note"]
base = os.path.dirname(here)
digest = open(os.path.join(base, "issues", "digest", "D2_wt_cosmetics_open_digest.md"), encoding="utf-8", errors="replace").read()
want = [int(x) for x in re.findall(r"(?m)^=== #(\d+) \[open\]", digest)]
got = [r[0] for r in rows]
problems = []
if sorted(want) != sorted(got): problems.append("number mismatch: missing %s extra %s" % (sorted(set(want)-set(got)), sorted(set(got)-set(want))))
if len(got) != len(set(got)): problems.append("duplicate numbers")
for r in rows:
    if len(r) != 15: problems.append("#%s has %d fields" % (r[0], len(r)))
    for f in r:
        if TAB in str(f) or NL in str(f): problems.append("#%s tab/newline in field" % r[0])
    if len(r[6].split()) > 20: problems.append("#%s summary %d words" % (r[0], len(r[6].split())))
    if len(r[10].split()) > 30: problems.append("#%s auto_check %d words" % (r[0], len(r[10].split())))
rows.sort(key=lambda r: r[0])
out = os.path.join(base, "findings", "D2_ledger.tsv")
with open(out, "w", encoding="utf-8", newline="") as f:
    f.write(TAB.join(hdr) + NL)
    for r in rows:
        f.write(TAB.join(str(x) for x in r) + NL)
print("rows:", len(rows), "problems:", problems if problems else "none")
def cnt(i):
    c = collections.Counter(r[i] for r in rows)
    return ", ".join("%s=%d" % kv for kv in sorted(c.items(), key=lambda kv: (-kv[1], kv[0])))
for name, i in [("author", 2), ("type", 3), ("lifecycle", 4), ("priority", 5), ("fix_state", 8), ("vclass", 9), ("confidence", 13)]:
    print(name + ":", cnt(i))
print("disposition:", ", ".join("%s=%d" % kv for kv in sorted(collections.Counter(r[11].split(":")[0] for r in rows).items(), key=lambda kv: -kv[1])))
cl = collections.defaultdict(list)
for r in rows: cl[r[7]].append(r[0])
for k in sorted(cl, key=lambda k: -len(cl[k])): print("cluster", k, len(cl[k]), cl[k])
byv = collections.defaultdict(list)
for r in rows: byv[r[9]].append(r[0])
for k in byv: print("class", k, byv[k])
