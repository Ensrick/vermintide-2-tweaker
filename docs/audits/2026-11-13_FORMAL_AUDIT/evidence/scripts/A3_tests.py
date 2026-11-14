# A3 helper: classify host-Lua unit tests that touch a mod (behavioural vs source-text assertions)
import re, os, sys, glob
REPO = r"<repos>/vermintide-2-tweaker"
needles = sys.argv[1:]
rows = []
for p in sorted(glob.glob(os.path.join(REPO, 'qa', 'lua', 'tests', 'test_*.lua'))):
    s = open(p, encoding='utf-8', errors='replace').read()
    if not any(n in s for n in needles): continue
    tests = len(re.findall(r'Harness\.test\(|\bT\.test\(|\btest\(\s*"', s))
    cases = len(re.findall(r'Harness\.(equal|truthy|falsy|fail|deep_equal|raises|near)\(', s))
    srcfind = len(re.findall(r'(source|src|text|txt|body|content|code)\w*:(find|match|gmatch)\(', s))
    dofile_mods = len(set(re.findall(r'dofile\([^)]*?/scripts/mods/[^)]*?/(_?[\w]+)\.lua', s)))
    loads = len(re.findall(r'loadstring|loadfile|dofile\(', s))
    rows.append((os.path.basename(p), s.count('\n'), tests, cases, srcfind, loads))
print('files=%d lines=%d tests=%d asserts=%d source_text_matches=%d' % (len(rows), sum(r[1] for r in rows), sum(r[2] for r in rows), sum(r[3] for r in rows), sum(r[4] for r in rows)))
heavy_src = [r for r in rows if r[4] > r[3] * 0.5 and r[4] >= 5]
print('files where source-text matches >= 50%% of assertion count: %d' % len(heavy_src))
for r in sorted(rows, key=lambda r: -r[1])[:int(os.environ.get('TOPN', '25'))]:
    print('%-62s lines=%5d tests=%3d asserts=%4d srcfind=%3d loads=%2d' % r)
