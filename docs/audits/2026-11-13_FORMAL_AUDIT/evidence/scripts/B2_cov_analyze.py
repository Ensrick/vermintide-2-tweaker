"""B2 audit: merge sharded line-hook dumps of the offline Lua suite and report, per mod,
how much production Lua is EXECUTED by any offline test. Reads only; prints a table.

Attribution of an executed chunk to a production file:
  A. chunk name is a real path inside the repository                      (loadfile / dofile)
  B. chunk name is the VMF-style '@scripts/mods/<mod>/<file>'             (loadstring with engine name)
  C. chunk name is '@<basename>' matching exactly one production basename (loadstring, whole file assumed)
  D. unnamed chunk (name == source text): its first characters are located inside a production
     file and line numbers are shifted by that offset                    (extracted span or whole file)
Anything else (vanilla fixture sources, custom labels) stays unattributed and is reported."""
import os, re, glob, collections

REPO = r"<repos>/vermintide-2-tweaker"
OUT = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/B2_out"
AUDIT = ["weapon_tweaker", "chaos_wastes_tweaker_dev", "general_tweaker_dev", "gui_tweaker_dev", "crafting_in_modded_dev",
         "verminious_dreams_lighting_dev", "cosmetics_tweaker", "dynamic_cosmetic_portraits", "career_tweaker", "enemy_tweaker",
         "character_weapon_variants", "character_dialogue", "weapons_of_chaos", "event_tweaker", "modded_progression"]
OTHER = ["weapon_tweaker_dev", "chaos_wastes_tweaker", "general_tweaker", "gui_tweaker", "crafting_in_modded", "verminious_dreams_lighting"]
WS = re.compile(r"[\r\n\t]")

prod = {}      # rel -> text
by_base = collections.defaultdict(list)
for mod in AUDIT + OTHER + ["tools/shared_lib"]:
    base = os.path.join(REPO, mod, "scripts") if not mod.startswith("tools") else os.path.join(REPO, mod)
    for dp, dn, fn in os.walk(base):
        for f in fn:
            if f.endswith(".lua"):
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, REPO).replace("\\", "/")
                prod[rel] = open(p, encoding="utf-8", errors="replace").read()
                by_base[f[:-4]].append(rel)
norm_cache = {}
def norm_text(rel):
    if rel not in norm_cache:
        norm_cache[rel] = WS.sub(" ", prod[rel].replace("\r\n", "\n"))
    return norm_cache[rel]

hits = collections.defaultdict(set)
how = collections.Counter()
meta = []
unattributed = collections.Counter()
for path in sorted(glob.glob(os.path.join(OUT, "cov2_shard*.tsv"))):
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if parts[0].startswith("#shard"):
                meta.append(" ".join(parts)); continue
            if len(parts) < 3: continue
            src, lines = parts[0], [int(x) for x in parts[2].split(",") if x]
            norm = src.replace("\\", "/")
            rel, offset, kind = None, 0, None
            m = re.match(r"^@(?:[A-Za-z]:)?/?.*?/vermintide-2-tweaker/(.+)$", norm)
            if m:
                rel, kind = os.path.normpath(m.group(1)).replace("\\", "/"), "A path"
            elif norm.startswith("@"):
                name = norm[1:]
                if name.startswith("./"): name = name[2:]
                if name.endswith(".lua"): name = name[:-4]
                m2 = re.match(r"^scripts/mods/([a-z_]+)/(.+)$", name)
                if m2 and (m2.group(1) + "/scripts/mods/" + m2.group(1) + "/" + m2.group(2) + ".lua") in prod:
                    rel, kind = m2.group(1) + "/scripts/mods/" + m2.group(1) + "/" + m2.group(2) + ".lua", "B vmf-name"
                elif (name + ".lua") in prod:
                    rel, kind = name + ".lua", "A path"
                elif "/" not in name and len(by_base.get(name, [])) >= 1:
                    cands = by_base[name]
                    pref = [c for c in cands if c.split("/")[0] in AUDIT] or cands
                    rel, kind = pref[0], "C basename"
            elif not norm.startswith("="):
                head = norm.split("...<inline-chunk")[0][:100]
                if len(head) >= 40:
                    for cand in prod:
                        t = norm_text(cand)
                        at = t.find(head)
                        if at >= 0:
                            rel, kind = cand, "D inline-span"
                            offset = prod[cand].replace("\r\n", "\n")[:at].count("\n")
                            if cand.split("/")[0] in AUDIT: break
            if rel is None or rel not in prod:
                unattributed[norm[:60]] += len(lines)
                continue
            how[kind] += 1
            for x in lines: hits[rel].add(x + offset)

def code_lines(text):
    out = set(); in_block = False
    for i, l in enumerate(text.split("\n"), 1):
        s = l.strip()
        if in_block:
            if "]]" in s or "]=]" in s: in_block = False
            continue
        if not s: continue
        if s.startswith("--[[") or s.startswith("--[=["):
            if "]]" not in s and "]=]" not in s: in_block = True
            continue
        if s.startswith("--"): continue
        out.add(i)
    return out

def is_data(rel):
    b = os.path.basename(rel)
    return bool(re.search(r"(_localization|_data|_catalog|_catalogue|_lines|_generated)\.lua$", b)) or "localization" in b

print("\n".join(meta))
print("chunk attribution:", dict(how), " unattributed chunks:", len(unattributed), "lines hit there:", sum(unattributed.values()))
print("largest unattributed:", [(k, v) for k, v in unattributed.most_common(8)])
print()
hdr = "%-31s %5s %7s | %9s %7s %6s | %7s %7s %6s | %s"
print(hdr % ("mod (audited tree)", "files", "code_ln", "files_exe", "ln_exe", "exe%", "logic_ln", "lg_exe", "lg%", "largest files with ZERO executed lines (code lines)"))
tot = collections.Counter(); rows_never = []
def report(mod, base=None):
    files = [r for r in prod if r.startswith(mod + "/")]
    n_code = n_exe = f_exe = lg_code = lg_exe = 0; never = []
    for rel in files:
        cl = code_lines(prod[rel]); h = hits.get(rel, set()); e = len(cl & h)
        n_code += len(cl); n_exe += e
        if not is_data(rel): lg_code += len(cl); lg_exe += e
        if h: f_exe += 1
        else: never.append((len(cl), os.path.basename(rel)))
    never.sort(reverse=True)
    print("%-31s %5d %7d | %4d/%-4d %7d %5.1f%% | %7d %7d %5.1f%% | %s" % (mod, len(files), n_code, f_exe, len(files), n_exe,
          100.0 * n_exe / max(n_code, 1), lg_code, lg_exe, 100.0 * lg_exe / max(lg_code, 1),
          ", ".join("%s(%d)" % (b, a) for a, b in never[:3])))
    return len(files), n_code, f_exe, n_exe, lg_code, lg_exe, never
for mod in AUDIT:
    a, b, c, d, e, f, never = report(mod)
    tot["files"] += a; tot["code"] += b; tot["fexe"] += c; tot["exe"] += d; tot["lg"] += e; tot["lgexe"] += f
    rows_never += [(n, mod, fn) for n, fn in never]
print("%-31s %5d %7d | %4d/%-4d %7d %5.1f%% | %7d %7d %5.1f%%" % ("AUDITED TREES TOTAL", tot["files"], tot["code"], tot["fexe"], tot["files"],
      tot["exe"], 100.0 * tot["exe"] / max(tot["code"], 1), tot["lg"], tot["lgexe"], 100.0 * tot["lgexe"] / max(tot["lg"], 1)))
print()
print("drift trees (public/stable or mirror; not the audited primary):")
for mod in OTHER: report(mod)
report("tools/shared_lib")
rows_never.sort(reverse=True)
print()
print("30 largest production files with ZERO lines executed by any offline test:")
for n, mod, fn in rows_never[:30]: print("  %6d  %s/%s" % (n, mod, fn))
# entry files
print()
print("entry files (<mod>.lua): executed code lines / code lines")
for mod in AUDIT:
    rel = "%s/scripts/mods/%s/%s.lua" % (mod, mod, mod)
    if rel in prod:
        cl = code_lines(prod[rel]); h = hits.get(rel, set())
        print("  %-34s %5d / %5d  (%.0f%%)" % (mod, len(cl & h), len(cl), 100.0 * len(cl & h) / max(len(cl), 1)))
