# E1: inventory every tracked markdown file: bytes, lines, last-commit date, first-commit date, commit count.
import subprocess, os, sys, collections
REPO = r"<repos>/vermintide-2-tweaker"
OUT = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/E1_md_inventory.tsv"
def git(*a):
    return subprocess.run(["git", "-C", REPO, "-c", "core.quotepath=false"] + list(a), capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
files = [f for f in git("ls-files").splitlines() if f.lower().endswith(".md")]
last = {}; first = {}; count = collections.Counter()
log = git("log", "--format=@@%cs", "--name-only", "--no-renames", "--", "*.md")
cur = None
for line in log.splitlines():
    if line.startswith("@@"):
        cur = line[2:]
    elif line.strip():
        f = line.strip()
        count[f] += 1
        if f not in last: last[f] = cur
        first[f] = cur
rows = []
for f in files:
    p = os.path.join(REPO, f.replace("/", os.sep))
    try:
        b = os.path.getsize(p)
        with open(p, "rb") as fh: n = fh.read().count(b"\n")
    except OSError:
        b = -1; n = -1
    rows.append((f, b, n, last.get(f, "?"), first.get(f, "?"), count.get(f, 0)))
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("path\tbytes\tlines\tlast_commit\tfirst_commit\tcommits\n")
    for r in rows: fh.write("\t".join(str(x) for x in r) + "\n")
tot = sum(r[1] for r in rows)
print("tracked md files:", len(rows), "bytes:", tot, "approx tokens:", tot // 4)
# by top-level dir
by = collections.defaultdict(lambda: [0, 0])
for r in rows:
    top = r[0].split("/")[0] if "/" in r[0] else "(root)"
    by[top][0] += 1; by[top][1] += r[1]
for k, v in sorted(by.items(), key=lambda kv: -kv[1][1]):
    print(f"{k}\t{v[0]}\t{v[1]}")
