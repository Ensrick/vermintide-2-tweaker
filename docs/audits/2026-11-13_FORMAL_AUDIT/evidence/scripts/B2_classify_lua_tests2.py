import os, re, sys, collections
repo = r"<repos>/vermintide-2-tweaker"
tests = os.path.join(repo, "qa", "lua", "tests")
out_tsv = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out\lua_tests_classified2.tsv"
MOD_DIRS = ["weapon_tweaker_dev","weapon_tweaker","chaos_wastes_tweaker_dev","chaos_wastes_tweaker","general_tweaker_dev","general_tweaker",
 "gui_tweaker_dev","gui_tweaker","cosmetics_tweaker","dynamic_cosmetic_portraits","career_tweaker","enemy_tweaker","character_weapon_variants",
 "character_dialogue","weapons_of_chaos","crafting_in_modded_dev","crafting_in_modded","event_tweaker","modded_progression",
 "verminious_dreams_lighting_dev","verminious_dreams_lighting","tweaker"]
NONMOD = ["tools","qa",".github","docs","_archive","dumps"]
PREFIX_MOD = {"cim":"crafting_in_modded","cos":"cosmetics_tweaker","crt":"career_tweaker","ct":"chaos_wastes_tweaker","cwv":"character_weapon_variants",
 "et":"enemy_tweaker","gt":"general_tweaker","gut":"gui_tweaker","mod":"gui_tweaker","mp":"modded_progression","modded":"modded_progression","woc":"weapons_of_chaos","wt":"weapon_tweaker",
 "event":"event_tweaker","dcp":"dynamic_cosmetic_portraits","dialogue":"character_dialogue","character":"character_dialogue"}
path_lit = re.compile(r'"(/?(?:%s)/[^"]*)"' % "|".join(re.escape(d) for d in MOD_DIRS+NONMOD))
find_re = re.compile(r'(:find\(|string\.find\(|:match\(|string\.match\(|:gmatch\(|string\.gmatch\()')
case_re = re.compile(r'\bH\.test(_if)?\s*\(')
fn_def = re.compile(r'(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_\.:]*)\s*\(')
call_re = re.compile(r'([A-Za-z_][A-Za-z0-9_]*(?:[\.:][A-Za-z_][A-Za-z0-9_]*)*)\s*\(')
str_re = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
BUILTIN = set("""assert error ipairs pairs tostring tonumber type select unpack next rawget rawset setmetatable getmetatable pcall xpcall print
string.format string.rep string.sub string.len string.lower string.upper string.byte string.char string.gsub string.find string.match string.gmatch
table.concat table.insert table.sort table.remove math.floor math.max math.min math.abs io.open if and or not function while for return""".split())
STRMETH = set("find match gmatch gsub sub len lower upper format rep byte read close lines".split())
def strip_strings(s): return str_re.sub('""', s)
rows = []
for fn in sorted(os.listdir(tests)):
    p = os.path.join(tests, fn)
    if not os.path.isfile(p) or not fn.endswith(".lua"): continue
    src = open(p, "r", encoding="utf-8", errors="replace").read()
    lines = src.split("\n")
    # local helper functions: text helpers (find in body) and readers (io.open in body)
    helpers = set()
    i = 0
    defs = [(i, fn_def.search(l).group(1)) for i, l in enumerate(lines) if fn_def.search(l) and not case_re.search(l)]
    for (i, name) in defs:
        # function body: until a line that is exactly indentation+'end' at same indent
        indent = len(lines[i]) - len(lines[i].lstrip())
        j = i + 1
        while j < len(lines) and not (lines[j].strip() in ("end", "end,", "end)") and (len(lines[j]) - len(lines[j].lstrip())) <= indent): j += 1
        body = "\n".join(lines[i+1:j])
        sb = strip_strings(body)
        calls = set(m.group(1) for m in call_re.finditer(sb))
        calls = set(c for c in calls if c not in BUILTIN and c.split(":")[-1].split(".")[-1] not in STRMETH and not c.startswith("H."))
        if (find_re.search(body) or "io.open" in body) and j - i <= 40:
            helpers.add(name.split(".")[-1].split(":")[-1]); helpers.add(name)
    uses_source_helper = bool(re.search(r'(ct_source|crt_source|cwv_source)', src))
    paths = path_lit.findall(src)
    mod_paths = [x for x in paths if x.lstrip("/").split("/")[0] in MOD_DIRS]
    non_paths = [x for x in paths if x.lstrip("/").split("/")[0] in NONMOD and "_source.lua" not in x]
    tool_paths = [x for x in non_paths if not x.lstrip("/").startswith("qa/lua/")]
    mods = sorted(set(x.lstrip("/").split("/")[0] for x in mod_paths))
    exec_lines = [l for l in lines if re.search(r'\b(loadfile|loadstring|dofile|setfenv)\s*\(', l) and "_source.lua" not in l]
    has_exec = len(exec_lines) > 0
    idx = [i for i, l in enumerate(lines) if case_re.search(l)]
    n_cases = len(idx); text_cases = 0; beh_cases = 0; data_cases = 0
    for k, start in enumerate(idx):
        end = idx[k+1] if k+1 < len(idx) else len(lines)
        body = "\n".join(lines[start:end])
        sb = strip_strings(body)
        calls = set(m.group(1) for m in call_re.finditer(sb))
        other = set()
        for c in calls:
            last = c.split(":")[-1].split(".")[-1]
            if c in BUILTIN or c.startswith("H.") or last in STRMETH or c in helpers or last in helpers: continue
            if last in ("expanded","combined","entry") : continue
            other.add(c)
        has_find = bool(find_re.search(body)) or any(re.search(r'\b%s\s*\(' % re.escape(h), sb) for h in helpers)
        if not other and has_find: text_cases += 1
        elif not other: data_cases += 1
        else: beh_cases += 1
    pref = fn[5:].split("_")[0] if fn.startswith("test_") else "(helper)"
    owner = PREFIX_MOD.get(pref, "")
    if not mods and owner and (uses_source_helper): mods = [owner]
    if not mod_paths and not uses_source_helper and tool_paths: fclass = "TOOLING"
    elif not mod_paths and not uses_source_helper: fclass = "OTHER(no mod path literal)"
    elif not has_exec: fclass = "TEXT_ONLY(no prod code executed)"
    elif n_cases and text_cases / n_cases >= 0.5: fclass = "EXEC+TEXT_DOMINANT(>=50% text cases)"
    else: fclass = "BEHAVIOURAL(executes prod code)"
    rows.append(dict(file=fn, prefix=pref, owner=owner, lines=len(lines), cls=fclass, cases=n_cases, text_cases=text_cases, data_cases=data_cases, beh_cases=beh_cases,
        exec_lines=len(exec_lines), mods=",".join(mods), tool_paths=len(tool_paths)))
cols = list(rows[0].keys())
with open(out_tsv, "w", encoding="utf-8") as f:
    f.write("\t".join(cols) + "\n")
    for r in rows: f.write("\t".join(str(r[c]) for c in cols) + "\n")
print("files", len(rows))
c = collections.Counter(r["cls"] for r in rows)
for k, v in c.most_common(): print(f"  {v:4d}  {k}")
for k in ("cases","text_cases","data_cases","beh_cases"): print(k, sum(r[k] for r in rows))
# per-prefix
pp = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    pp[r["prefix"]]["files"] += 1; pp[r["prefix"]][r["cls"][:4]] += 1
    for k in ("cases","text_cases","data_cases","beh_cases","lines"): pp[r["prefix"]][k] += r[k]
print("prefix files BEHA EXEC TEXT TOOL OTHE cases text data beh lines")
for p, c in sorted(pp.items(), key=lambda kv: -kv[1]["files"]):
    print(f"{p:12s} {c['files']:4d} {c['BEHA']:4d} {c['EXEC']:4d} {c['TEXT']:4d} {c['TOOL']:4d} {c['OTHE']:4d} {c['cases']:5d} {c['text_cases']:5d} {c['data_cases']:5d} {c['beh_cases']:5d} {c['lines']:6d}")
