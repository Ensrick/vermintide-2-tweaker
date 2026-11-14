"""B2 audit: do the literal string-form VMF hook targets in the audited mod trees resolve to a
method defined in the decompiled vanilla source (6.13.0)? Static only. Handles `class(X, Parent)`
inheritance by walking the parent chain. Prints counts and the unresolved list."""
import os, re, collections

REPO = r"<repos>/vermintide-2-tweaker"
SRC = r"<repos>/Vermintide-2-Source-Code"
AUDIT = ["weapon_tweaker", "chaos_wastes_tweaker_dev", "general_tweaker_dev", "gui_tweaker_dev", "crafting_in_modded_dev",
         "verminious_dreams_lighting_dev", "cosmetics_tweaker", "dynamic_cosmetic_portraits", "career_tweaker", "enemy_tweaker",
         "character_weapon_variants", "character_dialogue", "weapons_of_chaos", "event_tweaker", "modded_progression"]

# 1. index vanilla: methods per class/table, and class parents
methods = collections.defaultdict(set)
parents = {}
def_re = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)[\.:]([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*function\b|\()", re.M)
fn_re = re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)[\.:]([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
asg_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b", re.M)
alias_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*$", re.M)
class_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*class\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:,\s*([A-Za-z_][A-Za-z0-9_]*))?", re.M)
nfiles = 0
for base in ("scripts", "foundation", "core"):
    for dp, dn, fn in os.walk(os.path.join(SRC, base)):
        for f in fn:
            if not f.endswith(".lua"): continue
            nfiles += 1
            s = open(os.path.join(dp, f), encoding="utf-8-sig", errors="replace").read()
            for m in fn_re.finditer(s): methods[m.group(1)].add(m.group(2))
            for m in asg_re.finditer(s): methods[m.group(1)].add(m.group(2))
            for m in alias_re.finditer(s): methods[m.group(1)].add(m.group(2))
            for m in class_re.finditer(s):
                if m.group(3): parents[m.group(1)] = m.group(3)

def resolves(cls, meth):
    seen = set()
    while cls and cls not in seen:
        seen.add(cls)
        if meth in methods.get(cls, ()): return True
        cls = parents.get(cls)
    return False

# 2. collect literal string-form hooks
hook_re = re.compile(r"[A-Za-z_][A-Za-z0-9_\.]*[:\.](hook|hook_safe|hook_origin)\(\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\s*,\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
tab_re = re.compile(r"[A-Za-z_][A-Za-z0-9_\.]*[:\.](hook|hook_safe|hook_origin)\(\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*,\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
total = collections.Counter(); unresolved = []; classes_missing = collections.Counter(); table_form = collections.Counter()
for mod in AUDIT:
    for dp, dn, fn in os.walk(os.path.join(REPO, mod, "scripts")):
        for f in fn:
            if not f.endswith(".lua"): continue
            p = os.path.join(dp, f)
            for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                if line.lstrip().startswith("--"): continue
                m = hook_re.search(line)
                if m:
                    total[mod] += 1
                    cls, meth = m.group(2), m.group(3)
                    if not resolves(cls, meth):
                        known_class = cls in methods or cls in parents
                        unresolved.append((mod, os.path.relpath(p, REPO).replace("\\", "/"), i, cls, meth, known_class))
                        if not known_class: classes_missing[cls] += 1
                    continue
                m = tab_re.search(line)
                if m and m.group(2) not in ("_G",):
                    table_form[mod] += 1
print("vanilla files indexed: %d, classes/tables with methods: %d" % (nfiles, len(methods)))
print("literal string-form hooks: %d ; table-form/variable hooks (not checked): %d" % (sum(total.values()), sum(table_form.values())))
print("UNRESOLVED string-form hook targets: %d" % len(unresolved))
print("  of which class/table name unknown to the decompile: %d (%s)" % (sum(1 for u in unresolved if not u[5]), dict(classes_missing.most_common(12))))
bymod = collections.Counter(u[0] for u in unresolved)
for mod in AUDIT:
    print("  %-32s string hooks=%4d unresolved=%3d" % (mod, total[mod], bymod[mod]))
print()
for u in unresolved[:80]:
    print("  %s:%d  %s.%s%s" % (u[1], u[2], u[3], u[4], "" if u[5] else "   [class not in decompile]"))
