"""B2 audit: iteratively discover the boot-order prerequisites needed to load a vanilla
target under the engine-free probe. Read-only; writes only its own log."""
import os, re, subprocess, sys

LUA = r"qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe"
ROOT = r"<repos>/Vermintide-2-Source-Code"
HERE = os.path.dirname(os.path.abspath(__file__))
STUBS = os.path.join(HERE, sys.argv[1]).replace("\\", "/")
targets = sys.argv[2:]
pre = ["scripts/utils/colors", "scripts/utils/global_utils", "scripts/utils/loaded_dice",
       "scripts/unit_extensions/human/ai_player_unit/ai_utils",
       "scripts/settings/dlcs/morris/deus_shop_settings", "scripts/settings/dlcs/morris/deus_blessing_settings",
       "scripts/settings/paintings_01"]
pre += [a[1:] for a in sys.argv[2:] if a.startswith("+")]
targets = [a for a in targets if not a.startswith("+")]
_index = {}


def definer(name):
    """vanilla file that first assigns global NAME at column 0."""
    if name in _index:
        return _index[name]
    pat = re.compile(r"^%s\s*=\s*" % re.escape(name), re.M)
    hits = []
    for base in ("scripts", "foundation"):
        for dp, dn, fn in os.walk(os.path.join(ROOT, base)):
            for f in fn:
                if not f.endswith(".lua"):
                    continue
                p = os.path.join(dp, f)
                try:
                    s = open(p, encoding="utf-8-sig", errors="replace").read()
                except OSError:
                    continue
                if pat.search(s):
                    hits.append(os.path.relpath(p, ROOT).replace("\\", "/")[:-4])
    hits.sort(key=lambda h: (("/dlcs/" in h) or ("_dlc" in h), len(h)))
    _index[name] = hits[0] if hits else None
    return _index[name]


log = []
tried = set()
for rnd in range(60):
    cmd = [LUA, os.path.join(HERE, "probe.lua"), ROOT.replace("\\", "/"), STUBS] + pre + targets
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=HERE, timeout=300).stdout
    ff = re.search(r"^first failure: (.*)$", out, re.M)
    files = re.search(r"vanilla files executed: (\d+)", out)
    if not ff:
        log.append("round %d: ALL TARGETS LOADED, vanilla files executed=%s" % (rnd, files.group(1) if files else "?"))
        open(os.path.join(HERE, "last_success.txt"), "w", encoding="utf-8").write(out)
        break
    msg = ff.group(1)
    m = re.search(r"attempt to index global '(\w+)'|attempt to call global '(\w+)'|global '(\w+)' \(a nil value\)", msg)
    name = m and (m.group(1) or m.group(2) or m.group(3))
    d = definer(name) if name else None
    if not name:
        # create_lookup(nil): read the calling statement in network_lookup.lua and resolve its inputs
        tr = re.search(r"network_lookup\.lua:(\d+): in main chunk", out)
        if tr:
            n = int(tr.group(1))
            src = open(os.path.join(ROOT, "scripts", "network_lookup", "network_lookup.lua"), encoding="utf-8-sig").read().splitlines()
            stmt = " ".join(src[n - 1:n + 3])
            added = []
            for ident in re.findall(r"(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9_]+)", stmt):
                if ident in ("NetworkLookup",) or ident in tried: continue
                tried.add(ident)
                dd = definer(ident)
                if dd and dd not in pre:
                    pre.append(dd); added.append("%s<-%s" % (ident, dd))
            log.append("round %d: files=%s FAIL create_lookup(nil) at network_lookup.lua:%d: %s" % (rnd, files.group(1) if files else "?", n, stmt.strip()[:120]))
            if added:
                log.append("  -> add prerequisites " + ", ".join(added))
                continue
            log.append("  -> STOP: could not resolve inputs of that statement")
            open(os.path.join(HERE, "last_failure.txt"), "w", encoding="utf-8").write(out)
            break
    log.append("round %d: files=%s FAIL %s" % (rnd, files.group(1) if files else "?", msg[:230]))
    if not d or d in pre:
        log.append("  -> STOP: no automatic resolution for %r (definer=%r)" % (name, d))
        open(os.path.join(HERE, "last_failure.txt"), "w", encoding="utf-8").write(out)
        break
    log.append("  -> add prerequisite %s (defines global %s)" % (d, name))
    pre.insert(4, d)  # newest dependency first: it must load before whatever needed it
print("\n".join(log))
print("PREREQS(%d): %s" % (len(pre), " ".join(pre)))
