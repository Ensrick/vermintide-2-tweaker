# A6: extract setting ids from a VMF *_data.lua with line, widget type and nesting indent; then count readers of each id across the mod's Lua.
import re, sys, os, glob
data = sys.argv[1]; moddir = os.path.dirname(data)
lines = open(data, encoding='utf-8', errors='replace').read().split('\n')
ids = []
for i, l in enumerate(lines):
    m = re.search(r'setting_id\s*=\s*"([^"]+)"', l)
    if m and not l.strip().startswith('--'):
        typ = None
        for j in range(i, min(i+12, len(lines))):
            t = re.search(r'\btype\s*=\s*"([^"]+)"', lines[j])
            if t: typ = t.group(1); break
        if typ is None:
            for j in range(i-1, max(i-6, 0), -1):
                t = re.search(r'\btype\s*=\s*"([^"]+)"', lines[j])
                if t: typ = t.group(1); break
        ids.append((i+1, m.group(1), typ, len(l) - len(l.lstrip())))
src = {}
for f in glob.glob(os.path.join(moddir, '*.lua')):
    b = os.path.basename(f)
    if b.endswith('_data.lua') or b.endswith('_localization.lua'): continue
    src[b] = open(f, encoding='utf-8', errors='replace').read()
for ln, sid, typ, ind in ids:
    readers = [b for b, s in src.items() if ('"%s"' % sid) in s]
    print("%5d\t%-44s\t%-10s\t%2d\t%s" % (ln, sid, typ, ind // 4, ",".join(sorted(readers)) or "NO_READER"))
