import os, re, sys, collections, json
repo = r"<repos>/vermintide-2-tweaker"
AUDIT = ["weapon_tweaker","chaos_wastes_tweaker_dev","general_tweaker_dev","gui_tweaker_dev","crafting_in_modded_dev","verminious_dreams_lighting_dev",
 "cosmetics_tweaker","dynamic_cosmetic_portraits","career_tweaker","enemy_tweaker","character_weapon_variants","character_dialogue","weapons_of_chaos",
 "event_tweaker","modded_progression"]
reg_re = re.compile(r'(?<![A-Za-z0-9_])((?:[A-Za-z_][A-Za-z0-9_]*[\.:])?_?rt_register|register_check|_register_check)\s*\(\s*(["\'])([^"\']+)\2\s*,(.*)$')
out = []
for mod in AUDIT:
    for root, dirs, files in os.walk(os.path.join(repo, mod, "scripts")):
        for fn in files:
            if not fn.endswith(".lua"): continue
            p = os.path.join(root, fn)
            lines = open(p, "r", encoding="utf-8", errors="replace").read().split("\n")
            for i, l in enumerate(lines):
                if l.lstrip().startswith("--"): continue
                m = reg_re.search(l)
                if not m: continue
                name = m.group(3); rest = m.group(4)
                indent = len(l) - len(l.lstrip())
                body = [l]
                inline_fn = "function" in rest
                j = i + 1
                if inline_fn and not re.search(r'\bend\s*(,[^)]*)?\)\s*$', l):
                    while j < len(lines) and j - i < 400:
                        body.append(lines[j])
                        lj = lines[j]
                        if (len(lj) - len(lj.lstrip())) <= indent and re.match(r'\s*end\s*(,.*)?\)?', lj) and lj.strip().startswith("end"):
                            break
                        j += 1
                out.append(dict(mod=mod, file=os.path.relpath(p, repo).replace("\\","/"), line=i+1, name=name, inline=inline_fn, body="\n".join(body)))
json.dump(out, open(r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\rt_checks.json", "w", encoding="utf-8"), indent=0)
c = collections.Counter(o["mod"] for o in out)
for k, v in c.most_common(): print(f"{v:4d} {k}")
print("total", len(out), "inline-fn", sum(1 for o in out if o["inline"]))
lens = sorted(len(o["body"].split("\n")) for o in out)
print("body lines median", lens[len(lens)//2], "p90", lens[int(len(lens)*0.9)], "max", lens[-1])
