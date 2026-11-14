# E1: byte size per heading section of a markdown file (level <= N).
import sys, re
p = sys.argv[1]; lvl = int(sys.argv[2]) if len(sys.argv) > 2 else 2
data = open(p, "rb").read().decode("utf-8", "replace").split("\n")
heads = []
infence = False
for i, l in enumerate(data):
    if l.startswith("```"): infence = not infence
    if infence: continue
    m = re.match(r"^(#{1,6}) (.*)", l)
    if m and len(m.group(1)) <= lvl: heads.append((i, len(m.group(1)), m.group(2)))
heads.append((len(data), 0, "EOF"))
for (a, lv, t), (b, _, _) in zip(heads, heads[1:]):
    by = sum(len(x.encode("utf-8")) + 1 for x in data[a:b])
    print(f"{a+1:5d}-{b:5d}  {b-a:5d} lines  {by:7d} B  ~{by//4:6d} tok  {'#'*lv} {t[:90]}")
