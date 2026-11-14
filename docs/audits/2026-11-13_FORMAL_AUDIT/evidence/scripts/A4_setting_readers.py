"""A4 helper: for each widget setting id, find a reader (literal or dynamic-prefix) outside *_data/*_localization."""
import re, os, sys, collections
root = r"<repos>/vermintide-2-tweaker"
jobs = [("chaos_wastes_tweaker_dev", "A4_settings_ct_dev.tsv"), ("chaos_wastes_tweaker", "A4_settings_ct.tsv"),
        ("event_tweaker", "A4_settings_evt.tsv"), ("enemy_tweaker", "A4_settings_et.tsv")]
here = os.path.dirname(os.path.abspath(__file__))
for mod, tsv in jobs:
    ids = []
    for line in open(os.path.join(here, tsv), encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2 and p[1] != "group": ids.append(p[0])
    code = {}
    for dp, dn, fn in os.walk(os.path.join(root, mod, "scripts")):
        for f in fn:
            if f.endswith(".lua") and not f.endswith("_data.lua") and not f.endswith("_localization.lua"):
                txt = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
                # strip full-line comments
                txt = "\n".join(l for l in txt.splitlines() if not l.strip().startswith("--"))
                code[f] = txt
    alltxt = "\n".join(code.values())
    # dynamic prefixes: "prefix_" ..   or  ("prefix_" .. x)  or string.format("prefix_%s"
    prefixes = set(re.findall(r'"([a-z0-9_]+_)"\s*\.\.', alltxt)) | set(re.findall(r'"([a-z0-9_]+_)%[sd]', alltxt)) | set(m.rstrip('^') for m in re.findall(r'\^([a-z0-9_]+_)', alltxt))
    suffixes = set(re.findall(r'\.\.\s*"(_[a-z0-9_]+)"', alltxt))
    lit, dyn, none = [], [], []
    for sid in ids:
        if ('"%s"' % sid) in alltxt or ("'%s'" % sid) in alltxt:
            lit.append(sid)
        elif any(sid.startswith(p) for p in prefixes) or any(sid.endswith(s) for s in suffixes):
            dyn.append(sid)
        else:
            none.append(sid)
    print("== %s: settings=%d literal_reader=%d dynamic_prefix_reader=%d NO_READER=%d" % (mod, len(ids), len(lit), len(dyn), len(none)))
    for s in none[:80]: print("   no-reader:", s)
