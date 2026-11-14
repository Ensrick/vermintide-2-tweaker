# D4 patch-day canary 3: static check for #1122/#414. Lists the category keys of
# morris_weapon_traits.combinations in the decompiled weapon_traits_morris.lua and compares them with the
# MELEE/RANGED category tables of CIM's _cim_trait_slot_policy.lua (both streams). Read-only.
# Paths: environment variables VT2_REPO_ROOT and VT2_DECOMPILE_ROOT override the defaults.
# Exit code: 0 when no category is unmapped in either stream; 1 otherwise.
import os, re, sys
HOME = os.path.expanduser("~")
REPO = os.environ.get("VT2_REPO_ROOT", os.path.join(HOME, "source", "repos", "vermintide-2-tweaker"))
SRC = os.path.join(os.environ.get("VT2_DECOMPILE_ROOT", os.path.join(HOME, "source", "repos", "Vermintide-2-Source-Code")),
                   "scripts", "settings", "equipment", "weapon_traits_morris.lua")
lines = open(SRC, encoding="utf-8", errors="replace").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("morris_weapon_traits.combinations = {"))
cats = []
for l in lines[start + 1:]:
    if l.startswith("}"):
        break
    m = re.match(r"^\t([A-Za-z_0-9]+) = \{", l)
    if m:
        cats.append(m.group(1))
print("decompile categories (%d): %s" % (len(cats), ", ".join(cats)))
bad = 0
for stream in ("crafting_in_modded", "crafting_in_modded_dev"):
    p = os.path.join(REPO, stream, "scripts", "mods", stream, "_cim_trait_slot_policy.lua")
    s = open(p, encoding="utf-8").read()

    def block(name):
        b = re.search(r"local %s = \{(.*?)\n\}" % name, s, re.S).group(1)
        return set(re.findall(r"([A-Za-z_0-9]+) = true", b))

    known = block("MELEE_CATEGORIES") | block("RANGED_CATEGORIES")
    unmapped = sorted(set(cats) - known)
    bad += len(unmapped)
    print(stream, "policy categories:", len(known), "| in decompile but unmapped:", unmapped,
          "| mapped but absent from morris table:", sorted(known - set(cats)))
sys.exit(1 if bad else 0)
