import os, re, sys, collections, json
repo = r"<repos>/vermintide-2-tweaker"
tests = os.path.join(repo, "qa", "lua", "tests")
out_tsv = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\lua_tests_classified.tsv"
MOD_DIRS = ["weapon_tweaker_dev","weapon_tweaker","chaos_wastes_tweaker_dev","chaos_wastes_tweaker","general_tweaker_dev","general_tweaker",
 "gui_tweaker_dev","gui_tweaker","cosmetics_tweaker","dynamic_cosmetic_portraits","career_tweaker","enemy_tweaker","character_weapon_variants",
 "character_dialogue","weapons_of_chaos","crafting_in_modded_dev","crafting_in_modded","event_tweaker","modded_progression",
 "verminious_dreams_lighting_dev","verminious_dreams_lighting","tweaker"]
NONMOD = ["tools","qa",".github","docs","_archive","dumps"]
path_lit = re.compile(r'"(/?(?:%s)/[^"]*)"' % "|".join(re.escape(d) for d in MOD_DIRS+NONMOD))
exec_re = re.compile(r'\b(loadfile|loadstring|setfenv|dofile|load)\s*\(')
find_re = re.compile(r'(:find\(|string\.find\(|:match\(|string\.match\(|:gmatch\(|:gsub\()')
assert_re = re.compile(r'(H\.(equal|deep_equal|truthy)\s*\(|\bassert\s*\(|\berror\s*\()')
case_re = re.compile(r'H\.test(_if)?\s*\(')
helper_def = re.compile(r'local function ([A-Za-z_][A-Za-z0-9_]*)\s*\(')
rows = []
for fn in sorted(os.listdir(tests)):
    p = os.path.join(tests, fn)
    if not os.path.isfile(p) or not fn.endswith(".lua"): continue
    src = open(p, "r", encoding="utf-8", errors="replace").read()
    lines = src.split("\n")
    # helper functions whose (short) body does a find -> text helper
    text_helpers = set()
    for i, l in enumerate(lines):
        m = helper_def.search(l)
        if m:
            body = "\n".join(lines[i:i+12])
            # stop at first 'end' at same indent roughly
            if find_re.search(body) and ("source" in body or "text" in body or "needle" in body or "haystack" in body or "body" in body or "pattern" in body):
                text_helpers.add(m.group(1))
    helper_call = re.compile(r'\b(%s)\s*\(' % "|".join(map(re.escape, text_helpers))) if text_helpers else None
    def is_text_line(l):
        return bool(find_re.search(l)) or bool(helper_call and helper_call.search(l) and not helper_def.search(l))
    paths = path_lit.findall(src)
    mod_paths = [x for x in paths if x.lstrip("/").split("/")[0] in MOD_DIRS]
    non_paths = [x for x in paths if x.lstrip("/").split("/")[0] in NONMOD]
    mods = sorted(set(x.lstrip("/").split("/")[0] for x in mod_paths))
    has_exec = bool(exec_re.search(src))
    n_loadfile = len(re.findall(r'\bloadfile\s*\(', src)); n_loadstring = len(re.findall(r'\bloadstring\s*\(', src))
    n_setfenv = len(re.findall(r'\bsetfenv\s*\(', src)); n_dofile = len(re.findall(r'\bdofile\s*\(', src))
    n_ioopen = len(re.findall(r'io\.open\s*\(', src))
    # split into cases
    idx = [i for i, l in enumerate(lines) if case_re.search(l)]
    n_cases = len(idx); text_cases = 0; beh_cases = 0; mixed_cases = 0
    for k, start in enumerate(idx):
        end = idx[k+1] if k+1 < len(idx) else len(lines)
        body = lines[start:end]
        a_text = 0; a_other = 0
        for l in body:
            if assert_re.search(l) or (helper_call and helper_call.search(l)):
                if is_text_line(l): a_text += 1
                else: a_other += 1
        if a_text and not a_other: text_cases += 1
        elif a_text and a_other: mixed_cases += 1
        else: beh_cases += 1
    n_find_lines = sum(1 for l in lines if is_text_line(l))
    n_assert_lines = sum(1 for l in lines if assert_re.search(l))
    fake_mod = bool(re.search(r'function\s+[A-Za-z_\.]*mod[:\.](hook|hook_safe|get|dofile|command|echo)\b', src)) or bool(re.search(r'\b(hook|hook_safe|dofile|get)\s*=\s*function', src))
    get_mod = "get_mod" in src
    if not mod_paths and non_paths: fclass = "TOOLING"
    elif not mod_paths and not non_paths:
        fclass = "NO_PATH_LITERAL"
    elif not has_exec: fclass = "TEXT_ONLY"
    else: fclass = "LOADS_PROD"
    pref = fn[5:].split("_")[0] if fn.startswith("test_") else "(helper)"
    rows.append(dict(file=fn, prefix=pref, lines=len(lines), cls=fclass, cases=n_cases, text_cases=text_cases, mixed_cases=mixed_cases, beh_cases=beh_cases,
        find_lines=n_find_lines, assert_lines=n_assert_lines, loadfile=n_loadfile, loadstring=n_loadstring, setfenv=n_setfenv, dofile=n_dofile, ioopen=n_ioopen,
        fake_mod=int(fake_mod), get_mod=int(get_mod), mods=",".join(mods), nonmod=",".join(sorted(set(x.lstrip("/").split("/")[0] for x in non_paths)))))
cols = list(rows[0].keys())
with open(out_tsv, "w", encoding="utf-8") as f:
    f.write("\t".join(cols) + "\n")
    for r in rows: f.write("\t".join(str(r[c]) for c in cols) + "\n")
print("files", len(rows), "lines", sum(r["lines"] for r in rows))
c = collections.Counter(r["cls"] for r in rows); print("file class:", dict(c))
for k in ("cases","text_cases","mixed_cases","beh_cases","find_lines","assert_lines"): print(k, sum(r[k] for r in rows))
print("fake_mod files", sum(r["fake_mod"] for r in rows), "get_mod files", sum(r["get_mod"] for r in rows))
# heavy-text files: LOADS_PROD but text_cases >= 80% cases
ht = [r for r in rows if r["cls"]=="LOADS_PROD" and r["cases"] and r["text_cases"]/r["cases"]>=0.8]
print("LOADS_PROD files with >=80% text-only cases:", len(ht))
mt = [r for r in rows if r["cls"]=="LOADS_PROD" and r["cases"] and r["text_cases"]/r["cases"]<=0.2]
print("LOADS_PROD files with <=20% text-only cases:", len(mt))
