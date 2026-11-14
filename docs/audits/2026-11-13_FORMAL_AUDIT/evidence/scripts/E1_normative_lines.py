# E1: count normative (rule-carrying) lines per rule surface and classify PROJECT_STANDARDS by concern.
import re, os, sys, collections
REPO = r"<repos>/vermintide-2-tweaker"
NORM = re.compile(r"\b(MUST|NEVER|must not|must|never|do not|don't|Do NOT|DO NOT|required|mandatory|forbidden|prohibited|banned|binding|non-negotiable|only|fail[s]? closed|is invalid|are invalid|not allowed|may not|shall)\b", re.I)
STRONG = re.compile(r"\b(MUST|NEVER|must not|must|never|Do NOT|DO NOT|do not|forbidden|prohibited|banned|mandatory|non-negotiable|fail[s]? closed|may not)\b")
surfaces = [
 r"%USERPROFILE%\.claude\CLAUDE.md", r"<repos>/CLAUDE.md", r"<repos>/AGENTS.md",
 "AGENTS.md", "CLAUDE.md", "PROJECT_STANDARDS.md", "CONTRIBUTING.md", "DEVELOPMENT.md", "MOD_OWNERSHIP.md", "MOD_DEPENDENCIES.md",
 "docs/BUG_TRIAGE_RUNBOOK.md", "docs/BUG_CLASSES.md", "docs/VMF_RECIPES.md", "docs/LOCALIZATION_STANDARD.md", "docs/WEAPON_APPEARANCE_STANDARD.md",
 "docs/PROMOTION_PROCESS.md", "docs/PORTABLE_SETUP.md", "docs/BUNDLE_AUTHORITY.md", "docs/CI_PROTECTION.md", "docs/MECHANICS.md",
 "tools/ship/CLAIMS.md", "tools/verify/README.md", "tools/verify/PUBLIC_RELEASE_CLOSURE.md", "qa/CHECKS.md", "qa/README.md",
 ".in_progress/README.md", ".github/pull_request_template.md", ".github/CURRENT_LIVE_TEST_TEMPLATE.md",
 "dynamic_cosmetic_portraits/CLAUDE.md", "event_tweaker/CLAUDE.md", "character_weapon_variants/DEFINITION_OF_DONE.md",
]
def sentences(text):
    # crude sentence split on prose (skip fenced code)
    out = []; fence = False
    for line in text.split("\n"):
        if line.strip().startswith("```"): fence = not fence; continue
        if fence: continue
        out.append(line)
    joined = " ".join(out)
    return re.split(r"(?<=[.!?:])\s+(?=[A-Z`*\[(])", joined)
tot_b = tot_s = tot_n = tot_strong = 0
print("surface\tbytes\tsentences\tnormative\tstrong_normative")
for s in surfaces:
    p = s if os.path.isabs(s) else os.path.join(REPO, s)
    try: t = open(p, "rb").read().decode("utf-8", "replace")
    except OSError: print(s, "MISSING"); continue
    ss = sentences(t)
    n = sum(1 for x in ss if NORM.search(x)); st = sum(1 for x in ss if STRONG.search(x))
    tot_b += len(t.encode("utf-8")); tot_s += len(ss); tot_n += n; tot_strong += st
    print(f"{s}\t{len(t.encode('utf-8'))}\t{len(ss)}\t{n}\t{st}")
print(f"TOTAL\t{tot_b}\t{tot_s}\t{tot_n}\t{tot_strong}")
# headings flagged binding / non-negotiable anywhere in tracked md
import subprocess
ls = subprocess.run(["git", "-C", REPO, "ls-files", "*.md"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.splitlines()
hb = []
for f in ls:
    if f.startswith("_archive/") or f.endswith("CHANGELOG.md") or "/generated/" in f: continue
    try: t = open(os.path.join(REPO, f), "rb").read().decode("utf-8", "replace")
    except OSError: continue
    for i, line in enumerate(t.split("\n"), 1):
        if re.match(r"^#{1,6} ", line) and re.search(r"binding|non-negotiable|mandatory|NON-NEGOTIABLE|MANDATORY", line):
            hb.append((f, i, line.strip()[:110]))
print("\nheadings self-labelled binding/mandatory/non-negotiable (tracked md, excl. archive/changelogs/generated):", len(hb))
c = collections.Counter(f for f, _, _ in hb)
for f, n in c.most_common(12): print("  ", n, f)
# PROJECT_STANDARDS by concern
ps = open(os.path.join(REPO, "PROJECT_STANDARDS.md"), "rb").read().decode("utf-8", "replace").split("\n")
heads = [(i, l) for i, l in enumerate(ps) if re.match(r"^## ", l)]
heads.append((len(ps), "## EOF"))
concern = {
 "1.": "meta", "2.": "code-design", "3.": "code-design(logging/diagnostics)", "4.": "code-design", "5.": "testing/verification",
 "6.": "release/ship/claims/receipts", "7.": "documentation process", "8.": "agent workflow", "9.": "code-design", "9a": "code-design", "9b": "code-design",
 "10": "release/ship/claims/receipts", "11.": "tracker/cards/labels", "11a": "testing/verification", "11b": "testing/verification", "12.": "documentation process",
 "12a": "documentation process", "13": "meta", "14.": "meta", "14a": "testing/verification", "15": "testing/verification",
}
agg = collections.Counter();
for (a, h), (b, _) in zip(heads, heads[1:]):
    key = h[3:].split(" ")[0]
    k = None
    for pref in sorted(concern, key=len, reverse=True):
        if key.startswith(pref.rstrip(".")) and (key.rstrip(".") == pref.rstrip(".")): k = concern[pref]; break
    by = sum(len(x.encode("utf-8")) + 1 for x in ps[a:b])
    agg[k or "meta"] += by
T = sum(agg.values())
print("\nPROJECT_STANDARDS bytes by concern (whole top-level sections):")
for k, v in agg.most_common(): print(f"   {k}: {v} B ({100*v/T:.0f}%)")
