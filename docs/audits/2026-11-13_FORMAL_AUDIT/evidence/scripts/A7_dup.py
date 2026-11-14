# A7: duplication between file pairs (normalized non-trivial lines shared), read-only.
import sys, re, os
d = r"gui_tweaker_dev\scripts\mods\gui_tweaker_dev"
def lines(f):
    out = []
    for l in open(os.path.join(d, f), encoding="utf-8", errors="replace"):
        s = l.strip()
        if not s or s.startswith("--") or s in ("end", "end)", "else", "})", "}", "},", "return", "end,"): continue
        if len(s) < 12: continue
        out.append(re.sub(r"\s+", " ", s))
    return out
def funcs(f):
    t = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
    return set(re.findall(r"function\s+[\w\.]+[:\.](\w+)\s*\(", t)) | set(re.findall(r"local function (\w+)\s*\(", t))
pairs = [("_mod_tweaker_view.lua", "_mod_tweaker_state.lua"),
         ("_mod_tweaker_view_interaction.lua", "_mod_tweaker_state_interaction.lua"),
         ("_gut_boss_damage_sync.lua", "_gut_custom_stat_sync.lua"),
         ("_gut_boss_damage_sync_policy.lua", "_gut_custom_stat_sync_policy.lua")]
for a, b in pairs:
    la, lb = lines(a), lines(b)
    sa, sb = set(la), set(lb)
    common = sa & sb
    da = sum(1 for x in la if x in common); db = sum(1 for x in lb if x in common)
    fa, fb = funcs(a), funcs(b)
    print(f"{a} ({len(la)} sig lines) vs {b} ({len(lb)}): shared-line share {da/len(la):.0%} / {db/len(lb):.0%}; fn names {len(fa)} / {len(fb)}, common {len(fa & fb)}")
