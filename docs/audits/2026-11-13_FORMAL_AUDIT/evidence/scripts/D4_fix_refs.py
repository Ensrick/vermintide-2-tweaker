# D4: one-off citation corrections + section renumbering for findings/D4.md and the ledger row files.
import re, io
def sub(path, pairs):
    s = open(path, encoding="utf-8").read(); n = 0
    for a, b in pairs:
        c = s.count(a); n += c; s = s.replace(a, b)
    open(path, "w", encoding="utf-8", newline="\n").write(s); print(path, "replacements:", n)
pairs = [
    ("_gut_official_loadout_boot_guard.lua:101-158", "_gut_official_loadout_boot_guard.lua:98-158"),
    ("_gut_official_loadout_boot_guard.lua:28-32,101-158", "_gut_official_loadout_boot_guard.lua:28-32,98-158"),
    ("Five boot hooks at `_gut_official_loadout_boot_guard.lua:101-158`", "Five boot hooks at `_gut_official_loadout_boot_guard.lua:98-158`"),
    ("_cim_keep_forge_interaction.lua:38-55", "_cim_keep_forge_interaction.lua:37-56"),
    ("_cim_trait_slot_policy.lua:33-36", "_cim_trait_slot_policy.lua:32-35"),
    ("_cim_trait_slot_policy.lua:43-56", "_cim_trait_slot_policy.lua:42"),
    ("_crt_dance_of_blades.lua:33-56", "_crt_dance_of_blades.lua:33-60"),
    ("`crafting_in_modded/CHANGELOG.md:29-30`", "`crafting_in_modded/CHANGELOG.md:31-32`"),
    ("_cim_regression_checks.lua:304-357", "_cim_regression_checks.lua:304-356"),
    ("the snapshot of `forged_weapons` is shallow, `:318-319`", "the snapshot of `forged_weapons` is shallow, `:317-318`"),
    ("(`_cim_regression_checks.lua:309-314`)", "(`crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_regression_checks.lua:310-316`)"),
    ("_cim_illusion_apply_presentation.lua:86-89", "_cim_illusion_apply_presentation.lua:87-88"),
    ("_cim_regression_checks.lua:452-464", "_cim_regression_checks.lua:445-469"),
]
for p in ("findings/D4.md", "scripts/D4_rows_a.py", "scripts/D4_rows_b.py", "scripts/D4_rows_c.py"):
    sub(p, pairs)
# section renumbering in D4.md (brief order: 1 stats, 2 clusters, 3 spot check, 4 mislabelled, 5 closed, 6 share, 7 top ten)
s = open("findings/D4.md", encoding="utf-8").read()
parts = re.split(r"(?m)^(?=## \d+\. )", s)
head, secs = parts[0], parts[1:]
by = {int(re.match(r"## (\d+)\.", x).group(1)): x for x in secs}
order = [(0, 0), (1, 1), (3, 2), (4, 3), (5, 4), (6, 5), (7, 6), (8, 7), (2, 8), (9, 9)]
out = [head]
for old, new in order:
    x = by[old]
    x = re.sub(r"^## %d\." % old, "## %d." % new, x)
    x = re.sub(r"(?m)^### %d\.(\d+)" % old, lambda m: "### %d.%s" % (new, m.group(1)), x)
    out.append(x)
s = "".join(out)
fix = [
    ("(section 4.4)", "(section 4.5)"),
    ("Cause: section 3.2.", "Cause: section 2.2."),
    ("#1671 and #1684 are in 3.2)", "#1671 and #1684 are in 2.2)"),
    ("plus #1688 from 3.2;", "plus #1688 from 2.2;"),
    ("Source spot check: 24 issues (section 3)", "Source spot check: 24 issues (section 3)"),
    ("## 8. Findings that cut across the bucket (severity per the common brief)", "## 8. Cross-cutting findings (severity per the common brief)"),
]
for a, b in fix:
    assert a in s, a
    s = s.replace(a, b)
s = s.replace("Helper scripts:", "Cross-cutting findings F1 to F10 (the part most useful for the execution plan) are in section 8.\nHelper scripts:", 1)
open("findings/D4.md", "w", encoding="utf-8", newline="\n").write(s)
print([l for l in s.split("\n") if l.startswith("## ") or l.startswith("### ")])
