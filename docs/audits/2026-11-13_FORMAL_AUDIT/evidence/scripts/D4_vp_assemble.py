# D4: assemble plan/vp/D4.md from scripts/D4_vp_parts/part*.md and prove coverage.
# Coverage rule (from the round-2 brief): every one of the 81 bucket issues appears exactly once across
#   (a) the first column of the "No rig needed" table (section 1),
#   (b) the `| Issues |` field of a verification pack (section 2),
#   (c) the "Owner only" section (section 5).
# The script fails (exit 1) when an issue is missing, duplicated, or foreign to the bucket.
# Usage: py -3 D4_vp_assemble.py            (writes plan/vp/D4.md)
#        py -3 D4_vp_assemble.py --check    (only re-checks the existing plan/vp/D4.md)
import os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(BASE, "scripts", "D4_vp_parts")
OUT = os.path.join(BASE, "plan", "vp", "D4.md")


def bucket():
    want = set()
    for b in ("bucket_D_cim_mp_career.tsv", "bucket_E_gui.tsv"):
        for i, line in enumerate(open(os.path.join(BASE, "data", b), encoding="utf-8", errors="replace")):
            p = line.split("\t")
            if i and p[0].isdigit():
                want.add(int(p[0]))
    return want


def coverage(text):
    sections = re.split(r"(?m)^(?=## \d+\. )", text)
    by = {}
    for s in sections:
        m = re.match(r"## (\d+)\. ", s)
        if m:
            by[int(m.group(1))] = s
    homes = {}

    def add(n, where):
        homes.setdefault(n, []).append(where)

    for line in by[1].split("\n"):                       # (a) No-rig table, first column only
        m = re.match(r"^\| #(\d+) \|", line)
        if m:
            add(int(m.group(1)), "no-rig")
    vp = None
    per_vp = {}
    for line in by[2].split("\n"):                       # (b) VP Issues fields
        h = re.match(r"^### (VP-D4-\d+) ", line)
        if h:
            vp = h.group(1)
            continue
        if line.startswith("| Issues |"):
            for n in re.findall(r"#(\d+)", line):
                add(int(n), vp)
                per_vp.setdefault(vp, []).append(int(n))
    owner = by.get(5, "")
    for n in re.findall(r"#(\d+)", owner):               # (c) Owner only
        add(int(n), "owner-only")
    return homes, per_vp


def report(text):
    want = bucket()
    homes, per_vp = coverage(text)
    missing = sorted(want - set(homes))
    extra = sorted(set(homes) - want)
    dup = sorted(n for n, w in homes.items() if len(w) > 1)
    norig = sorted(n for n, w in homes.items() if w == ["no-rig"])
    owner = sorted(n for n, w in homes.items() if w == ["owner-only"])
    in_vp = sorted(n for n, w in homes.items() if len(w) == 1 and w[0].startswith("VP-"))
    lines = []
    lines.append("| Home | Issues | Count |")
    lines.append("|---|---|---|")
    lines.append("| Section 1, No rig needed | %s | %d |" % (", ".join(str(n) for n in norig), len(norig)))
    for vp in sorted(per_vp):
        lines.append("| %s | %s | %d |" % (vp, ", ".join(str(n) for n in sorted(per_vp[vp])), len(per_vp[vp])))
    lines.append("| Section 5, Owner only | %s | %d |" % (", ".join(str(n) for n in owner) or "none", len(owner)))
    lines.append("| Total | | %d |" % (len(norig) + len(in_vp) + len(owner)))
    ok = not missing and not extra and not dup and len(homes) == len(want) == 81
    summary = ("Bucket issues: %d. Homed exactly once: %d. Missing: %s. Listed twice: %s. Not in the bucket: %s. Result: %s."
               % (len(want), len(norig) + len(in_vp) + len(owner), missing or "none", dup or "none", extra or "none",
                  "PASS" if ok else "FAIL"))
    return ok, summary, lines, len(per_vp)


if "--check" in sys.argv:
    text = open(OUT, encoding="utf-8").read()
    ok, summary, lines, n_vp = report(text)
    print(summary)
    sys.exit(0 if ok else 1)

body = ""
for name in ("part0.md", "part1.md", "part2.md", "part3.md", "part4.md", "part5.md"):
    body += open(os.path.join(PARTS, name), encoding="utf-8").read().rstrip("\n") + "\n\n"
ok, summary, lines, n_vp = report(body)
tail = ["## 6. Coverage proof", "",
        "Checked by `scripts/D4_vp_assemble.py` in the audit workspace (re-run with `--check`). It reads the issue numbers of the bucket from `data/bucket_D_cim_mp_career.tsv` and `data/bucket_E_gui.tsv`, then counts an issue once for each of: a first-column entry in the section 1 table, a mention in a pack's `Issues` field, a hash-numbered mention in section 5. Issue numbers in section 6 are written without the hash sign.",
        "", summary, ""] + lines + ["",
        "Packs: %d (VP-D4-01 to VP-D4-%02d). Issue numbers inside case tables, section 3 and section 4 are cross-references and are not counted." % (n_vp, n_vp), ""]
open(OUT, "w", encoding="utf-8", newline="\n").write(body + "\n".join(tail))
print(summary)
for l in lines:
    print(l)
print("wrote", OUT, "packs:", n_vp)
sys.exit(0 if ok else 1)
