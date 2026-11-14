"""A2: classify offline Lua tests that touch cwv / woc: executable (loadfile/dofile of mod module) vs textual (read source, :find)."""
import os, re, sys
tdir = sys.argv[1]
rows = []
for f in sorted(os.listdir(tdir)):
    if not f.endswith('.lua'): continue
    p = os.path.join(tdir, f)
    s = open(p, encoding='utf-8', errors='replace').read()
    cw = 'character_weapon_variants' in s; wo = 'weapons_of_chaos' in s
    if not (cw or wo): continue
    n_load = len(re.findall(r'\b(loadfile|dofile|loadstring|load_module|H\.load\w*|H\.dofile\w*|require)\s*\(', s))
    n_read = len(re.findall(r'(read_file|io\.open|H\.read\w*|read_source|slurp|read_text)\s*\(', s))
    n_find = len(re.findall(r':(find|match|gmatch)\s*\(', s))
    n_cases = len(re.findall(r'\bH\.(test|case|it)\s*\(|\btest\s*\(\s*"', s))
    n_assert = len(re.findall(r'\b(H\.(eq|ok|assert\w*|is_\w+|truthy|falsy|ne|check\w*)|assert)\s*\(', s))
    lines = s.count('\n') + 1
    rows.append((f, 'cwv' if cw else '', 'woc' if wo else '', lines, n_load, n_read, n_find, n_cases, n_assert))
print('file\tcwv\twoc\tlines\tloads\treads\tfinds\tcases\tasserts')
tl = 0; textual = 0; execd = 0; mixed = 0
for r in rows:
    tl += r[3]
    kind = 'EXEC' if r[4] > 0 and r[6] <= r[4] * 3 else ('TEXT' if r[4] == 0 and r[6] > 0 else 'MIXED')
    if kind == 'EXEC': execd += 1
    elif kind == 'TEXT': textual += 1
    else: mixed += 1
    print('\t'.join(map(str, r)) + '\t' + kind)
print(f'files={len(rows)} lines={tl} EXEC={execd} TEXT={textual} MIXED={mixed}')
