import io, os
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = os.path.join(base, "plan", "vp", "D2.md")
t = io.open(p, encoding="utf-8").read()
lines = t.split(chr(10))
for i, l in enumerate(lines):
    if l.startswith("| #635 | S |"):
        lines[i] = ("| #635 | S | `git grep -n -i -e \"tuner\" -e \"anim picker\" -e \"animation picker\" -e \"hold.pose\" -e \"untested\" -e \"needs animations\" -- "
                    "weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua` returns nothing "
                    "(checked 2026-11-13); `ls weapon_tweaker/scripts/mods/weapon_tweaker` has no `wt_dev_*.lua`; `pwsh qa/check_wt_stream_parity.ps1` passes; "
                    "in-mod check at `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua:1368-1373` | close |")
io.open(p, "w", encoding="utf-8", newline="").write(chr(10).join(lines))
print([l[:60] for l in lines if l.startswith("| #635")])
