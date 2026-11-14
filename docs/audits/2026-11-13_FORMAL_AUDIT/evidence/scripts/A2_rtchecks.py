"""A2: rough classification of in-game _rt_register checks (read-only heuristic)."""
import os, re, sys, collections
root = sys.argv[1]
start = re.compile(r'^\s*_?rt_register\(\s*"([a-z0-9_]+)"\s*,\s*(function\s*\(\)|[A-Za-z_.]+)')
res = []
for f in sorted(os.listdir(root)):
    if not f.endswith('.lua'): continue
    L = open(os.path.join(root, f), encoding='utf-8', errors='replace').read().split('\n')
    i = 0
    while i < len(L):
        m = start.match(L[i])
        if m:
            name = m.group(1); j = i + 1
            if m.group(2).startswith('function'):
                while j < len(L) and not re.match(r'^end\)|^end,\s*\{|^\tend\)|^    end\)', L[j]): j += 1
            body = '\n'.join(L[i:j + 1]); n = j - i + 1
            code = '\n'.join(l for l in L[i:j + 1] if not l.strip().startswith('--'))
            calls = len(re.findall(r'(_om|mod|policy|lifecycle|M)[\.:][A-Za-z_][\w\.]*\(', code))
            flags = len(re.findall(r'_installed\b|_fix_markers|_hook_installed|_ran\b', code))
            typechecks = len(re.findall(r'type\([^)]*\)\s*[~=]=\s*"function"', code))
            engine = len(re.findall(r'\b(Unit|World|Managers|ScriptUnit|Application|ItemMasterList|NetworkLookup|Weapons|WeaponSkins|DamageProfileTemplates)\b', code))
            kind = 'delegated' if not m.group(2).startswith('function') else ('flag/marker' if (flags > 0 and calls <= 1 and n < 40) else ('shape-only' if calls == 0 and engine > 0 else ('drives-code' if calls >= 2 else 'other')))
            res.append((f, name, n, calls, flags, typechecks, engine, kind)); i = j
        i += 1
c = collections.Counter(r[7] for r in res)
print('checks parsed:', len(res), dict(c))
print('median body lines:', sorted(r[2] for r in res)[len(res)//2], 'total lines in check bodies:', sum(r[2] for r in res))
for k in ('flag/marker', 'shape-only', 'other', 'delegated'):
    print(k + ':', ', '.join(r[1] for r in res if r[7] == k)[:900])
