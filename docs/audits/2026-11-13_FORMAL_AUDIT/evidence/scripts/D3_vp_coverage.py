# D3: coverage proof for plan/vp/D3.md. Every bucket issue must appear exactly once across
# the No-rig table, a VP Issues field, or the Owner only section. Read-only on inputs.
import re, csv, os, collections
base = r"<audit-workspace>"
text = open(os.path.join(base, "plan", "vp", "D3.md"), encoding="utf-8").read()
bucket = sorted(int(r["number"]) for r in csv.DictReader(open(os.path.join(base, "data", "bucket_C_cw_events_enemies.tsv"), encoding="utf-8"), delimiter="\t"))
def section(title):
    m = re.search(r"^## " + re.escape(title) + r"\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    return m.group(1) if m else ""
where = collections.defaultdict(list)
for line in section("No rig needed").split("\n"):
    m = re.match(r"\| #(\d+) \|", line)
    if m: where[int(m.group(1))].append("no-rig")
owner = section("Owner only")
for n in re.findall(r"^\| #(\d+) \|", owner, re.M):
    where[int(n)].append("owner-only")
vps = re.findall(r"^### (VP-D3-\d+)[^\n]*\n(.*?)(?=^### |^## |\Z)", text, re.S | re.M)
per_vp = {}
for vid, body in vps:
    m = re.search(r"^\| Issues \| (.*?) \|\s*$", body, re.M)
    nums = [int(x) for x in re.findall(r"#(\d+)", m.group(1))] if m else []
    per_vp[vid] = nums
    for n in nums: where[n].append(vid)
missing = [n for n in bucket if n not in where]
dupes = {n: w for n, w in where.items() if len(w) > 1}
extra = sorted(n for n in where if n not in bucket)
print("bucket", len(bucket), "covered", len([n for n in bucket if n in where]))
print("missing", missing)
print("duplicates", dupes)
print("not in bucket", extra)
print("no-rig", sorted(n for n, w in where.items() if w == ["no-rig"]))
print("owner-only", sorted(n for n, w in where.items() if w == ["owner-only"]))
for vid in sorted(per_vp): print(vid, len(per_vp[vid]), per_vp[vid])
print("VP total", sum(len(v) for v in per_vp.values()), "VP count", len(per_vp))
cls = collections.Counter()
for vid, body in vps:
    m = re.search(r"^\| Issues \| (.*?) \|\s*$", body, re.M)
    for n, c in re.findall(r"#(\d+) \((\w)", m.group(1)): cls[c] += 1
print("classes in VP Issues fields", dict(cls))
