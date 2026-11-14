# D3: closed issues referenced by bucket's open issues, with reopen-signal score. Read-only.
import re, csv, os, sys
base = r"<audit-workspace>"
bucket = [r["number"] for r in csv.DictReader(open(os.path.join(base, "data", "bucket_C_cw_events_enemies.tsv"), encoding="utf-8"), delimiter="\t")]
sig = {r["number"]: r for r in csv.DictReader(open(os.path.join(base, "data", "closed_reopen_signals.tsv"), encoding="utf-8"), delimiter="\t")}
closed = {r["number"]: r for r in csv.DictReader(open(os.path.join(base, "data", "closed_index.tsv"), encoding="utf-8"), delimiter="\t")}
digest = open(os.path.join(base, "issues", "digest", "D3_cw_events_enemies_open_digest.md"), encoding="utf-8").read()
refs = {}
cur = None
for line in digest.split("\n"):
    m = re.match(r"=== #(\d+) \[open\]", line)
    if m: cur = m.group(1)
    if line.startswith("refs:") and cur:
        for n, st in re.findall(r"#(\d+)\((o|c)\)", line):
            if st == "c":
                refs.setdefault(n, []).append(cur)
rows = []
for n, by in refs.items():
    c = closed.get(n, {})
    s = sig.get(n, {})
    rows.append((int(s.get("score", 0) or 0), n, c.get("closed", "?"), c.get("state_reason", "?"), c.get("labels", "?"), c.get("title", "?"), ",".join(by), s.get("has_confirmation_text", "?"), s.get("nonowner_comments", "?")))
rows.sort(reverse=True)
print("closed refs:", len(rows))
for r in rows:
    print("\t".join(str(x) for x in r))
