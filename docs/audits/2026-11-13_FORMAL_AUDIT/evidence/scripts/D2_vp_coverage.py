import re, io, os, sys, collections
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
vp = io.open(os.path.join(base, "plan", "vp", "D2.md"), encoding="utf-8").read()
digest = io.open(os.path.join(base, "issues", "digest", "D2_wt_cosmetics_open_digest.md"), encoding="utf-8", errors="replace").read()
bucket = sorted(int(x) for x in re.findall(r"(?m)^=== #(\d+) \[open\]", digest))
sec1 = vp.split("## 1. No rig needed", 1)[1].split("## 2. Verification packs", 1)[0]
norig = [int(x) for x in re.findall(r"(?m)^\| #(\d+) \|", sec1)]
sec2 = vp.split("## 2. Verification packs", 1)[1].split("## 3. Needs a fix first", 1)[0]
packs = collections.OrderedDict()
cur = None
for line in sec2.split(chr(10)):
    m = re.match(r"### (VP-D2-\d+) ", line)
    if m: cur = m.group(1); continue
    if line.startswith("| Issues |") and cur:
        packs[cur] = [int(x) for x in re.findall(r"#(\d+)", line)]
sec4 = vp.split("## 4. Owner only", 1)[1].split("## 5. Coverage proof", 1)[0]
owner = [int(x) for x in re.findall(r"(?m)^Owner only issue: #(\d+)", sec4)]
count = collections.Counter(norig)
for k, v in packs.items(): count.update(v)
count.update(owner)
missing = [n for n in bucket if count[n] == 0]
dup = [n for n in bucket if count[n] > 1]
extra = sorted(n for n in count if n not in bucket)
inpacks = sum(len(v) for v in packs.values())
print("bucket issues: %d" % len(bucket))
print("no-rig table: %d %s" % (len(norig), sorted(norig)))
print("packs: %d, issues in packs: %d" % (len(packs), inpacks))
for k, v in packs.items(): print("  %s: %s" % (k, v))
print("owner only: %d" % len(owner))
print("total placed: %d; missing: %s; duplicated: %s; not in bucket: %s" % (len(norig) + inpacks + len(owner), missing, dup, extra))
print("RESULT: %s" % ("PASS" if not missing and not dup and not extra and len(norig) + inpacks + len(owner) == len(bucket) else "FAIL"))
cases = re.findall(r"`(qa/runtime/[a-z_]+/issue_[0-9a-z_]+\.lua)`", sec2)
print("script files named: %d (unique %d)" % (len(cases), len(set(cases))))
