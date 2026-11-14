#!/usr/bin/env python3
"""B1: history weight by extension over all reachable objects. Read-only (rev-list + cat-file --batch-check)."""
import subprocess, collections, os
REPO = r"<repos>/vermintide-2-tweaker"
p1 = subprocess.run(["git", "-C", REPO, "rev-list", "--objects", "--all"], capture_output=True)
lines = p1.stdout.decode("utf-8", "replace").splitlines()
names = {}
for l in lines:
    parts = l.split(" ", 1)
    if len(parts) == 2: names.setdefault(parts[0], parts[1])
inp = "\n".join(l.split(" ", 1)[0] for l in lines) + "\n"
p2 = subprocess.run(["git", "-C", REPO, "cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize) %(objectsize:disk)"],
                    input=inp.encode(), capture_output=True)
byext = collections.defaultdict(lambda: [0, 0, 0])
bundle_paths = collections.Counter()
tot = [0, 0, 0]
big = []
for l in p2.stdout.decode().splitlines():
    h, t, sz, dsz = l.split()
    if t != "blob": continue
    n = names.get(h, "")
    e = os.path.splitext(n)[1].lower() or "(none)"
    s = byext[e]; s[0] += 1; s[1] += int(sz); s[2] += int(dsz)
    tot[0] += 1; tot[1] += int(sz); tot[2] += int(dsz)
    if e == ".mod_bundle": bundle_paths[n.split("/")[0]] += 1
    big.append((int(dsz), int(sz), n))
print(f"reachable blobs: {tot[0]}  logical {tot[1]/2**30:.2f} GiB  on-disk {tot[2]/2**30:.2f} GiB")
print(f"{'ext':14s} {'blobs':>7s} {'logical MiB':>12s} {'disk MiB':>10s}")
for e, s in sorted(byext.items(), key=lambda kv: -kv[1][2])[:14]:
    print(f"{e:14s} {s[0]:7d} {s[1]/2**20:12.1f} {s[2]/2**20:10.1f}")
print("\n.mod_bundle blob versions in history by mod dir:")
for k, v in bundle_paths.most_common(): print(f"  {v:5d}  {k}")
