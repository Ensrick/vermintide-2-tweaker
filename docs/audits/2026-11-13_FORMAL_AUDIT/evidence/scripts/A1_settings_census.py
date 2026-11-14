# A1 read-only: compare literal mod:get("id") readers vs widgets declared in the data tree.
import re, glob, os, sys
root = r"weapon_tweaker\scripts\mods\weapon_tweaker"
def strip_comments(s):
    s = re.sub(r'--\[(=*)\[.*?\]\1\]', '', s, flags=re.S)
    s = re.sub(r'--[^\n]*', '', s)
    return s
widgets, readers = {}, {}
for p in glob.glob(os.path.join(root, "*.lua")):
    name = os.path.basename(p)
    if re.match(r'_wt_history_.*catalog', name): continue
    src = strip_comments(open(p, encoding="utf-8", errors="replace").read())
    for m in re.finditer(r'setting_id\s*=\s*"([A-Za-z0-9_]+)"', src):
        widgets.setdefault(m.group(1), set()).add(name)
    for m in re.finditer(r'(?:mod|self\.mod|c\.mod|_mod)\s*:\s*get\(\s*"([A-Za-z0-9_]+)"', src):
        readers.setdefault(m.group(1), set()).add(name)
    for m in re.finditer(r'feature_enabled\(\s*(?:mod\s*,\s*)?"([A-Za-z0-9_]+)"', src):
        readers.setdefault(m.group(1), set()).add(name)
    for m in re.finditer(r'[A-Z_]+_SETTING(?:_ID)?\s*=\s*"([A-Za-z0-9_]+)"', src):
        readers.setdefault(m.group(1), set()).add(name + " (const)")
nw = [w for w in widgets if not w.startswith("unlock_")]
print("active non-unlock widgets:", len(nw))
print("literal readers:", len(readers))
print("\nREADERS WITH NO WIDGET (setting read but never declared):")
for r in sorted(readers):
    if r not in widgets: print("  ", r, sorted(readers[r]))
print("\nWIDGETS (non-unlock, non-group-looking) WITH NO LITERAL READER:")
for w in sorted(nw):
    if w not in readers: print("  ", w, sorted(widgets[w]))
