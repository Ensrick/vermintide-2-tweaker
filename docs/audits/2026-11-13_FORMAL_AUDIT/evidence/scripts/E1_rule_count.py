# E1: count rule-signal tokens per rule surface.
import re, os, sys, subprocess, collections
REPO = r"<repos>/vermintide-2-tweaker"
EXTRA = [r"%USERPROFILE%\.claude\CLAUDE.md", r"<repos>/CLAUDE.md"]
pats = collections.OrderedDict([
 ("binding", re.compile(r"\bbinding\b", re.I)),
 ("MUST", re.compile(r"\bMUST\b")),
 ("must", re.compile(r"\bmust\b")),
 ("NEVER", re.compile(r"\bNEVER\b")),
 ("never", re.compile(r"\b[Nn]ever\b")),
 ("non-neg", re.compile(r"non-negotiable", re.I)),
 ("DO NOT", re.compile(r"\bD[Oo] NOT\b|\bDon't\b|\bdo not\b")),
 ("mandatory", re.compile(r"\bmandatory\b|\bMANDATORY\b|\brequired\b|\bREQUIRED\b")),
 ("forbidden", re.compile(r"\bforbidden\b|\bprohibited\b|\bbanned\b", re.I)),
 ("fail closed", re.compile(r"fail(s|ed)?[ -]closed", re.I)),
 ("issue#", re.compile(r"#\d{2,4}\b")),
 ("burned", re.compile(r"\b[Bb]urned\b")),
])
files = sys.argv[1:]
print("file\tbytes\t" + "\t".join(pats))
tot = collections.Counter(); tb = 0
for f in files:
    p = f if os.path.isabs(f) else os.path.join(REPO, f)
    try: s = open(p, "rb").read().decode("utf-8", "replace")
    except OSError as e: print(f, "ERR", e); continue
    row = [len(pt.findall(s)) for pt in pats.values()]
    for k, v in zip(pats, row): tot[k] += v
    tb += len(s.encode("utf-8"))
    print(f"{f}\t{len(s.encode('utf-8'))}\t" + "\t".join(map(str, row)))
print("TOTAL\t%d\t" % tb + "\t".join(str(tot[k]) for k in pats))
