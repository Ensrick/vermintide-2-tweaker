# A3 helper: cross-check every literal (Class, method) hook target against the decompiled source.
import re, os, sys, subprocess, collections
REPO = r"<repos>/vermintide-2-tweaker"
SRC = r"<repos>/Vermintide-2-Source-Code"
mods = sys.argv[1:]
hook_re = re.compile(r'(\w+):(hook|hook_safe|hook_origin)\(\s*("?)([\w\.]+)\3\s*,\s*"(\w+)"')
targets = collections.OrderedDict()
for m in mods:
    for dp, dn, fn in os.walk(os.path.join(REPO, m)):
        for f in fn:
            if not f.endswith('.lua'): continue
            p = os.path.join(dp, f)
            for i, line in enumerate(open(p, encoding='utf-8', errors='replace'), 1):
                s = line.strip()
                if s.startswith('--'): continue
                mm = hook_re.search(line)
                if mm:
                    targets.setdefault((mm.group(4), mm.group(5)), []).append((os.path.relpath(p, REPO).replace(os.sep,'/'), i, mm.group(2), mm.group(3) == '"'))
# index decompile definitions
defs = collections.defaultdict(list)
def_re = re.compile(r'^([A-Za-z_][\w]*)\.([A-Za-z_]\w*)\s*=\s*function\s*\(([^)]*)\)')
for dp, dn, fn in os.walk(SRC):
    if '.git' in dp: continue
    for f in fn:
        if not f.endswith('.lua'): continue
        p = os.path.join(dp, f)
        try:
            for i, line in enumerate(open(p, encoding='utf-8', errors='replace'), 1):
                mm = def_re.match(line)
                if mm:
                    defs[(mm.group(1), mm.group(2))].append((os.path.relpath(p, SRC).replace(os.sep,'/'), i, mm.group(3)))
        except Exception as e:
            pass
ok = miss = dup = 0
seen_pairs = collections.Counter()
for (cls, meth), sites in targets.items():
    d = defs.get((cls, meth))
    seen_pairs[(cls, meth)] = len(sites)
    tag = 'CONFIRMED' if d else 'NOT-FOUND'
    if d: ok += 1
    else: miss += 1
    site = '; '.join('%s:%d(%s)' % (s[0].split('/')[-1], s[1], s[2]) for s in sites)
    where = ('%s:%d (%s)' % (d[0][0], d[0][1], d[0][2])) if d else '-'
    flag = '  **DUP-HOOK x%d**' % len(sites) if len(sites) > 1 else ''
    print('%-10s %s.%s  <- %s%s\n           def: %s' % (tag, cls, meth, site, flag, where))
print('\nTOTAL distinct targets=%d confirmed=%d not-found(or alias/table-form)=%d' % (len(targets), ok, miss))
