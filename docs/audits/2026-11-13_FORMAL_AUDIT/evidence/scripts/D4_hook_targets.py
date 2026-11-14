# D4 patch-day canary 1: static resolution of literal VMF hook targets against the decompiled game source.
# For each mod:hook / hook_safe / hook_origin ("Class", "method") literal in a mod, check that
# `Class.method = function` (or `function Class.method` / `Class:method`) exists somewhere in
# Vermintide-2-Source-Code. Inherited methods are resolved through `A = class(A, B...)`
# (class() copies the parent's functions into the child, foundation/scripts/util/class.lua:51-57).
# Read-only. Usage: py -3 D4_hook_targets.py <mod_dir> [<mod_dir> ...]
# Paths: environment variables VT2_REPO_ROOT and VT2_DECOMPILE_ROOT override the defaults below.
# Exit code: 0 when every literal target resolves or is in ALLOW; 1 otherwise.
# Blind spot: hooks whose first argument is a variable (for example mod:hook(player_bot, "spawn", ...))
# are counted and reported as "non-literal" but not resolved.
import os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = os.environ.get("VT2_REPO_ROOT", os.path.join(os.path.expanduser("~"), "source", "repos", "vermintide-2-tweaker"))
SRC = os.environ.get("VT2_DECOMPILE_ROOT", os.path.join(os.path.expanduser("~"), "source", "repos", "Vermintide-2-Source-Code"))
# Guarded dead branches that are known and harmless: (Class, method)
ALLOW = {
    ("HeroWindowCraftingInventory", "_update_crafting_material_panel"),  # rawget-guarded, _cim_standard_forge_presentation.lua:260-262
}
defs = {}      # class -> set(methods)
supers = {}    # class -> [supers]
def_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function")
def2_re = re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)[.:]([A-Za-z_][A-Za-z0-9_]*)\s*\(")
class_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*class\(\s*([A-Za-z_][A-Za-z0-9_]*)?\s*(?:,\s*([A-Za-z_][A-Za-z0-9_,\s]*))?\)")
for root, _, files in os.walk(SRC):
    if ".git" in root:
        continue
    for f in files:
        if not f.endswith(".lua"):
            continue
        try:
            for line in open(os.path.join(root, f), encoding="utf-8", errors="replace"):
                m = def_re.match(line) or def2_re.match(line)
                if m:
                    defs.setdefault(m.group(1), set()).add(m.group(2))
                    continue
                c = class_re.match(line)
                if c and c.group(3):
                    supers.setdefault(c.group(1), []).extend([s.strip() for s in c.group(3).split(",") if s.strip()])
        except OSError:
            pass
if not defs:
    print("ERROR: no definitions found under", SRC)
    sys.exit(2)


def resolves(cls, meth, depth=0):
    if meth in defs.get(cls, ()):
        return True
    if depth > 6:
        return False
    return any(resolves(s, meth, depth + 1) for s in supers.get(cls, ()))


hook_re = re.compile(r"mod:(hook|hook_safe|hook_origin)\(\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\s*,\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
any_hook_re = re.compile(r"mod:(hook|hook_safe|hook_origin)\(")
bad_total = 0
for mod in sys.argv[1:]:
    total = 0
    all_sites = 0
    missing = []
    allowed = []
    seen = set()
    base = os.path.join(REPO, mod, "scripts")
    for root, _, files in os.walk(base):
        for f in files:
            if not f.endswith(".lua"):
                continue
            p = os.path.join(root, f)
            for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                if line.lstrip().startswith("--"):
                    continue
                all_sites += len(any_hook_re.findall(line))
                for m in hook_re.finditer(line):
                    key = (m.group(2), m.group(3))
                    total += 1
                    if key in seen:
                        continue
                    seen.add(key)
                    if not resolves(*key):
                        where = "%s.%s  (%s:%d)%s" % (key[0], key[1], os.path.relpath(p, REPO).replace("\\", "/"), i,
                                                    "" if key[0] in defs else "  [class not found in source]")
                        (allowed if key in ALLOW else missing).append(where)
    print("== %s: %d literal hook sites, %d distinct targets, %d unresolved, %d allow-listed, %d non-literal sites not checked"
          % (mod, total, len(seen), len(missing), len(allowed), all_sites - total))
    for x in missing:
        print("   UNRESOLVED " + x)
    for x in allowed:
        print("   allow-listed " + x)
    bad_total += len(missing)
sys.exit(1 if bad_total else 0)
