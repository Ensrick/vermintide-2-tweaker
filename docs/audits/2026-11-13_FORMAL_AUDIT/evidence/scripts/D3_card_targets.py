# D3: which build does each issue's newest CURRENT LIVE TEST card target? Read-only.
import re, os, collections
base = r"<audit-workspace>"
d = open(os.path.join(base, "issues", "digest", "D3_cw_events_enemies_open_digest.md"), encoding="utf-8").read()
blocks = re.split(r"\n(?==== #\d+ \[open\])", d)
out = collections.defaultdict(list)
for b in blocks:
    m = re.match(r"=== #(\d+) \[open\]", b.strip())
    if not m: continue
    n = int(m.group(1))
    labels = re.search(r"\nlabels: (.*)", b).group(1)
    life = "verify-fix" if "verify-fix" in labels else ("diagnostics-armed" if "diagnostics-armed" in labels else "not-started")
    cm = re.search(r"--- newest CURRENT LIVE TEST card \((\d{4}-\d\d-\d\d), (\d+) cards total\)\n(.*?)(?=\n--- (?:non-owner )?comment by|\Z)", b, re.S)
    if not cm:
        out[(life, "no card")].append(n); continue
    date, ncards, text = cm.group(1), int(cm.group(2)), cm.group(3)
    vers = sorted(set(re.findall(r"v?(\d+\.\d+\.\d+(?:-(?:dev|beta|alpha))?)", text[:900])))
    tgt = "ct-official-beta" if "0.7.354-beta" in text else ("ct-dev" if "0.7.354-dev" in text else ("et" if "et:LOAD" in text else ("evt" if "event_tweaker:LOAD" in text else "other")))
    topo = re.search(r"\*\*Topology:\*\*\s*([^\n]*)", text)
    out[(life, tgt)].append((n, date, ncards, (topo.group(1)[:28] if topo else "?")))
for k in sorted(out):
    print(k, len(out[k]))
    for v in out[k]: print("    ", v)
