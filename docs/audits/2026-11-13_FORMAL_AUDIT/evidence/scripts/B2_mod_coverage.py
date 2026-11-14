import os, re, collections
repo = r"<repos>/vermintide-2-tweaker"
tests = os.path.join(repo, "qa", "lua", "tests")
fixt = os.path.join(repo, "qa", "lua", "fixtures")
# audit trees (dev for promotion pairs, weapon_tweaker for wt)
AUDIT = ["weapon_tweaker","chaos_wastes_tweaker_dev","general_tweaker_dev","gui_tweaker_dev","crafting_in_modded_dev","verminious_dreams_lighting_dev",
 "cosmetics_tweaker","dynamic_cosmetic_portraits","career_tweaker","enemy_tweaker","character_weapon_variants","character_dialogue","weapons_of_chaos",
 "event_tweaker","modded_progression"]
OTHER = ["weapon_tweaker_dev","chaos_wastes_tweaker","general_tweaker","gui_tweaker","crafting_in_modded","verminious_dreams_lighting"]
# load all test + fixture text
blob = {}
for d in (tests, os.path.join(tests,"fixtures"), fixt, os.path.join(repo,"qa","lua")):
    for fn in os.listdir(d):
        p = os.path.join(d, fn)
        if os.path.isfile(p) and fn.endswith(".lua"):
            blob[p] = open(p, "r", encoding="utf-8", errors="replace").read()
alltext = "\n".join(blob.values())
cls = {}
with open(r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\lua_tests_classified2.tsv", encoding="utf-8") as f:
    hdr = f.readline().rstrip("\n").split("\t")
    for line in f:
        r = dict(zip(hdr, line.rstrip("\n").split("\t"))); cls[r["file"]] = r
def lua_files(mod):
    out = []
    for root, dirs, files in os.walk(os.path.join(repo, mod)):
        if "bundleV2" in root or ".build" in root: continue
        for fn in files:
            if fn.endswith(".lua"): out.append(os.path.join(root, fn))
    return out
def nlines(p):
    with open(p, "rb") as fh: return fh.read().count(b"\n")
print(f"{'mod':32s} {'files':>5s} {'lines':>7s} {'loc/data':>8s} {'logic':>7s} | {'tests':>5s} {'behav':>5s} {'textdom':>7s} {'cases':>5s} {'t/kLOC':>6s} | {'files_ref':>9s} {'lines_ref%':>10s} {'rt_reg':>6s}")
tot = collections.Counter()
for mod in AUDIT + OTHER:
    fs = lua_files(mod)
    L = {p: nlines(p) for p in fs}
    total = sum(L.values())
    locdata = sum(v for p, v in L.items() if re.search(r'(_localization|_data)\.lua$', p) or "localization" in os.path.basename(p))
    logic = total - locdata
    # tests referencing this mod dir by path literal "/<mod>/" (exact dir boundary)
    pat = re.compile(r'[/"]%s/' % re.escape(mod))
    tfiles = [os.path.basename(p) for p, t in blob.items() if os.path.dirname(p) == tests and pat.search(t)]
    # add *_source users by owner prefix
    extra = [fn for fn, r in cls.items() if r["mods"].split(",") == [mod.replace("_dev","")] or mod in r["mods"].split(",")]
    tset = sorted(set(tfiles) | set(e for e in extra if mod in cls[e]["mods"].split(",")))
    beh = sum(1 for t in tset if t in cls and cls[t]["cls"].startswith("BEHAV"))
    txt = sum(1 for t in tset if t in cls and (cls[t]["cls"].startswith("TEXT") or cls[t]["cls"].startswith("EXEC+TEXT")))
    cases = sum(int(cls[t]["cases"]) for t in tset if t in cls)
    # production files referenced by basename in any test/fixture text
    ref = [p for p in fs if re.search(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(os.path.basename(p)[:-4]), alltext)]
    ref_lines = sum(L[p] for p in ref)
    # rt_register calls
    rt = 0
    for p in fs:
        s = open(p, "r", encoding="utf-8", errors="replace").read()
        rt += len(re.findall(r'(?<![A-Za-z0-9_])_?rt_register\s*\(\s*["\']', s))
    print(f"{mod:32s} {len(fs):5d} {total:7d} {locdata:8d} {logic:7d} | {len(tset):5d} {beh:5d} {txt:7d} {cases:5d} {len(tset)/max(logic,1)*1000:6.2f} | {len(ref):4d}/{len(fs):<4d} {100*ref_lines/max(total,1):9.1f}% {rt:6d}")
    if mod in AUDIT:
        tot["files"] += len(fs); tot["lines"] += total; tot["logic"] += logic; tot["rt"] += rt
print("AUDIT-TREE TOTAL files", tot["files"], "lines", tot["lines"], "logic", tot["logic"], "rt_register", tot["rt"])
