#!/usr/bin/env python3
"""B1: dev/stable directory duplication cost. Read-only."""
import os, re, difflib, subprocess
REPO = r"<repos>/vermintide-2-tweaker"
PAIRS = ["chaos_wastes_tweaker", "crafting_in_modded", "general_tweaker", "gui_tweaker", "verminious_dreams_lighting", "weapon_tweaker"]
def lua_files(mod):
    base = os.path.join(REPO, mod, "scripts", "mods")
    out = {}
    for dp, dn, fn in os.walk(base):
        for f in fn:
            if f.endswith(".lua"):
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, base).replace("\\", "/")
                out[rel] = p
    return out
def read(p):
    with open(p, "rb") as fh: return fh.read().decode("utf-8", "replace")
def ver(mod):
    p = os.path.join(REPO, mod, "scripts", "mods", mod, mod + ".lua")
    m = re.search(r'MOD_VERSION\s*=\s*"([^"]+)"', read(p)) if os.path.exists(p) else None
    return m.group(1) if m else "?"
def lastdate(mod):
    return subprocess.run(["git", "-C", REPO, "log", "-1", "--format=%ad", "--date=short", "master", "--", mod + "/scripts"], capture_output=True).stdout.decode().strip()
print(f"{'pair':28s} {'stable ver':15s} {'dev ver':15s} {'st files':>8s} {'dev files':>9s} {'st lines':>8s} {'dev lines':>9s} {'only-st':>7s} {'only-dev':>8s} {'identical*':>10s} {'differ':>6s} {'chg lines':>9s} {'st last':>10s} {'dev last':>10s}")
T = [0, 0]
for m in PAIRS:
    s, d = lua_files(m), lua_files(m + "_dev")
    norm = lambda rel, mod: rel.replace(mod + "_dev", mod)
    dn = {norm(k, m): v for k, v in d.items()}
    sl = sum(read(p).count("\n") for p in s.values()); dl = sum(read(p).count("\n") for p in d.values())
    only_s = [k for k in s if k not in dn]; only_d = [k for k in dn if k not in s]
    ident = differ = chg = 0
    for k in s:
        if k in dn:
            a = read(s[k]); b = read(dn[k]).replace(m + "_dev", m)
            # also normalise short ids like ct_dev -> ct is not attempted: report raw
            if a == b: ident += 1
            else:
                differ += 1
                al, bl = a.splitlines(), b.splitlines()
                sm = difflib.SequenceMatcher(None, al, bl, autojunk=False) if max(len(al), len(bl)) < 4000 else None
                if sm:
                    chg += sum(max(i2 - i1, j2 - j1) for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal")
                else:
                    chg += abs(len(al) - len(bl)) + len(set(al) ^ set(bl)) // 2
    T[0] += sl; T[1] += dl
    print(f"{m:28s} {ver(m):15s} {ver(m+'_dev'):15s} {len(s):8d} {len(d):9d} {sl:8d} {dl:9d} {len(only_s):7d} {len(only_d):8d} {ident:10d} {differ:6d} {chg:9d} {lastdate(m):>10s} {lastdate(m+'_dev'):>10s}")
print(f"TOTAL stable-side lines {T[0]}, dev-side lines {T[1]}  (* identical after replacing '<mod>_dev' with '<mod>' in content)")
