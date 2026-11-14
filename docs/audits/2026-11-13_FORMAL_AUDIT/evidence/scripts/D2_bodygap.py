import re, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
digest = open(os.path.join(base, "issues", "digest", "D2_wt_cosmetics_open_digest.md"), encoding="utf-8", errors="replace").read()
nums = re.findall(r"(?m)^=== #(\d+) \[open\]", digest)
pat = re.compile(r"(not ready for tester|remaining readiness|readiness gap|regression gap|current gap|not ready for an in-game|is not ready|before returning (this issue )?to .verify-fix|never integrated|not deployed|keep blocked and not-started|remains .not-started|not-started. remains)", re.I)
for n in nums:
    t = open(os.path.join(base, "issues", "open", n + ".md"), encoding="utf-8", errors="replace").read()
    labels = re.search(r"(?m)^labels: (.*)$", t).group(1)
    body = t.split("## BODY", 1)[1].split("## COMMENT by", 1)[0]
    hits = sorted(set(m.group(1).lower() for m in pat.finditer(body)))
    life = [l for l in ["verify-fix", "diagnostics-armed", "not-started"] if l in labels]
    if hits: print("#%s [%s] body: %s" % (n, "/".join(life), "; ".join(hits)))
