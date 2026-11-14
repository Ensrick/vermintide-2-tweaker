# A3 helper: per-file code/comment/blank split for Lua files (read-only)
import sys, os, re
root = sys.argv[1]
rows = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith('.lua'): continue
        p = os.path.join(dp, f)
        code = com = blank = 0
        inblock = False
        maxlen = 0
        with open(p, encoding='utf-8', errors='replace') as fh:
            for line in fh:
                s = line.strip()
                maxlen = max(maxlen, len(line.rstrip('\n')))
                if inblock:
                    com += 1
                    if ']]' in s: inblock = False
                    continue
                if not s: blank += 1
                elif s.startswith('--[[') or s.startswith('--[=['):
                    com += 1
                    if ']]' not in s: inblock = True
                elif s.startswith('--'): com += 1
                else: code += 1
        rows.append((code+com+blank, code, com, blank, maxlen, os.path.relpath(p, root)))
rows.sort(reverse=True)
tot = [sum(r[i] for r in rows) for i in range(4)]
print("total=%d code=%d comment=%d blank=%d files=%d" % (tot[0], tot[1], tot[2], tot[3], len(rows)))
n = int(sys.argv[2]) if len(sys.argv) > 2 else 25
for r in rows[:n]:
    print("%6d code=%6d com=%5d (%2d%%) maxline=%5d %s" % (r[0], r[1], r[2], 100*r[2]//max(1,r[0]), r[4], r[5]))
