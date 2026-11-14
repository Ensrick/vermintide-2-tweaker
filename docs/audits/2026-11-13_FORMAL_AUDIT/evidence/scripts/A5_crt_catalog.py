# A5 helper: summarize career_tweaker balance catalog entries (read-only, regex-based, approximate).
import re, os, collections
d = r"career_tweaker\scripts\mods\career_tweaker"
files = ["_crt_balance_catalog_early.lua", "_crt_balance_catalog_engineer.lua", "_crt_balance_catalog_focused_spirit.lua", "_crt_balance_catalog_late.lua"]
entries = []
for f in files:
    src = open(os.path.join(d, f), encoding="utf-8", errors="replace").read().splitlines()
    cur = None
    for i, line in enumerate(src, 1):
        m = re.match(r"^    ([a-z][a-z0-9_]+) = (\{|_build_[a-z_]+\()", line)
        if m:
            cur = {"id": m.group(1), "file": f, "line": i, "career": None, "character": None, "custom": False, "patches": 0, "builder": m.group(2) != "{"}
            entries.append(cur)
        elif cur:
            m2 = re.search(r'\bcareer\s*=\s*"([a-z_]+)"', line)
            if m2 and not cur["career"]: cur["career"] = m2.group(1)
            m3 = re.search(r'\bcharacter\s*=\s*"([a-z_]+)"', line)
            if m3 and not cur["character"]: cur["character"] = m3.group(1)
            if "custom_apply" in line: cur["custom"] = True
            if re.search(r"\{\s*buff\s*=", line): cur["patches"] += 1
print("balance entries:", len(entries))
bycar = collections.Counter((e["career"] or ("char:" + str(e["character"]))) for e in entries)
for k, v in sorted(bycar.items()): print("  %-28s %d" % (k, v))
print("with custom_apply closures:", sum(e["custom"] for e in entries), " builder-made:", sum(e["builder"] for e in entries), " pure data patches only:", sum((not e["custom"]) and (not e["builder"]) and e["patches"] > 0 for e in entries), " empty owner rows (hook-owned):", sum((not e["custom"]) and (not e["builder"]) and e["patches"] == 0 for e in entries))
