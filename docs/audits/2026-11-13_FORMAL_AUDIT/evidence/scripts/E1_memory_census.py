# E1: census of the Claude memory store: how much concerns VT2, how much is referenced from the repo,
# which repo-cited memory files do not exist, which VT2 engineering memories are not cited anywhere in the repo.
import os, re, subprocess, collections, sys
MEM = r"<memory-store>"
REPO = r"<repos>/vermintide-2-tweaker"
OUT = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/E1_memory_census.tsv"
name_rx = re.compile(r"(vt2|vmf|vmb|vermintide|_wt_|^reference_wt|_cim_|_cwv_|_gut_|_ct_|_cw_|workshop|ship|steambrew|doomrocket|woc_|stingray|husk|bundle|ranalds|ui_tweaks|uitweaks|la_|loremaster|deus|chaos_wastes|athanor|portrait|illusion|weave|pusfume)", re.I)
body_rx = re.compile(r"(vermintide|\bVT2\b|\bVMF\b|VMBLauncher|vmb-launcher|ship\.ps1|weapon_tweaker|cosmetics_tweaker|chaos_wastes|crafting_in_modded|character_weapon_variants|gui_tweaker|general_tweaker|ItemMasterList|mod:hook|Stingray)", re.I)
other_rx = re.compile(r"(shcde|byzantine|skyrim|kohan|k2_|war2r|nwn|minecraft|budget|isu_|homebuyer|glazewm|blender|nexus|dark_messiah|apishared|firefly|mameluke|landscape|naval|paws|dwm|ctfmon|fancyzones|codex|sol_)", re.I)
files = sorted(f for f in os.listdir(MEM) if f.endswith(".md"))
# repo text corpus of tracked md + lua comments? only md/ps1/psd1/lua names search via git grep per batch is slow; build one big blob of tracked text docs
ls = subprocess.run(["git", "-C", REPO, "ls-files"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.splitlines()
doc_files = [f for f in ls if f.lower().endswith((".md", ".ps1", ".psd1", ".lua", ".yml", ".json", ".txt")) and not f.startswith("_archive/") and "/bundleV2/" not in f]
names_in_repo = collections.Counter(); where = collections.defaultdict(set)
mem_ref_rx = re.compile(r"\b((?:feedback|reference|project|user|index)_[A-Za-z0-9_\-]+)(?:\.md)?\b")
for f in doc_files:
    p = os.path.join(REPO, f.replace("/", os.sep))
    try:
        if os.path.getsize(p) > 6_000_000: continue
        s = open(p, "rb").read().decode("utf-8", "replace")
    except OSError: continue
    if "feedback_" not in s and "reference_" not in s and "project_" not in s: continue
    for m in mem_ref_rx.finditer(s):
        names_in_repo[m.group(1)] += 1; where[m.group(1)].add(f)
idx = ""
for i in ("MEMORY.md", "index_vt2_engine_and_vmf.md", "index_vt2_mods.md", "index_other_projects.md", "index_skyrim.md", "index_skyrim_tech.md"):
    try: idx += open(os.path.join(MEM, i), "rb").read().decode("utf-8", "replace")
    except OSError: pass
rows = []; tot = collections.Counter(); totb = collections.Counter()
for f in files:
    if f == "MEMORY.md" or f.startswith("index_"): continue
    p = os.path.join(MEM, f)
    s = open(p, "rb").read().decode("utf-8", "replace")
    b = len(s.encode("utf-8"))
    stem = f[:-3]
    hits_body = len(body_rx.findall(s))
    is_vt2 = bool(name_rx.search(f)) and not other_rx.search(f)
    if not is_vt2 and hits_body >= 3 and not other_rx.search(f): is_vt2 = True
    indexed = (f in idx)
    in_repo = names_in_repo.get(stem, 0)
    kind = f.split("_")[0]
    mt = re.search(r"type:\s*(\w+)", s)
    rows.append((f, b, kind, "vt2" if is_vt2 else "other", "indexed" if indexed else "ORPHAN", in_repo, ";".join(sorted(where.get(stem, []))[:4])))
    tot[("vt2" if is_vt2 else "other")] += 1; totb[("vt2" if is_vt2 else "other")] += b
    tot[("vt2" if is_vt2 else "other", kind)] += 1
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("file\tbytes\tkind\tscope\tindexed\trepo_refs\trepo_files\n")
    for r in rows: fh.write("\t".join(str(x) for x in r) + "\n")
print("memory files (excluding MEMORY.md and index_*):", len(rows))
for k in ("vt2", "other"):
    print(k, tot[k], "files", totb[k], "bytes", "~%d tok" % (totb[k] // 4), {kk[1]: v for kk, v in tot.items() if isinstance(kk, tuple) and kk[0] == k})
vt2 = [r for r in rows if r[3] == "vt2"]
print("vt2 memories cited by name somewhere in repo (non-archive):", sum(1 for r in vt2 if r[5] > 0), "of", len(vt2))
print("vt2 memories NOT cited anywhere in repo:", sum(1 for r in vt2 if r[5] == 0), "bytes", sum(r[1] for r in vt2 if r[5] == 0))
print("vt2 memories not in any index (orphans):", sum(1 for r in vt2 if r[4] == "ORPHAN"))
print("all orphans:", sum(1 for r in rows if r[4] == "ORPHAN"))
existing = set(f[:-3] for f in files)
missing = sorted((n, c) for n, c in names_in_repo.items() if n not in existing and re.match(r"(feedback|reference)_", n))
print("distinct memory-style names cited in repo:", len([n for n in names_in_repo if re.match(r'(feedback|reference|project)_', n)]))
print("cited feedback_/reference_ names that do NOT exist in the memory store:", len(missing))
for n, c in missing[:80]: print("   ", n, c, sorted(where[n])[:2])
