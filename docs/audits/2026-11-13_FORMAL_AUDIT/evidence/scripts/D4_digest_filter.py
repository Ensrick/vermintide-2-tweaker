import sys,re
sys.stdout.reconfigure(encoding="utf-8",errors="replace")
src=r'<audit-workspace>/issues\digest\D4_cim_mp_career_gui_open_digest.md'
lines=open(src,encoding='utf-8',errors='replace').read().split('\n')
out=[]
skip=False
boiler=('**Setup:** Enable public Tweaker','**Report:** State which steps','Use the latest applicable GUI Tweaker stream','- **Tweaker: GUI `v0.2.280`**','- **Tweaker: GUI Dev `v0.2.306-dev`**','Use Dev when the procedure requires developer-only','The newest issue-specific verification procedure above remains authoritative','## Current deployed-floor correction','Use official **Crafting in Modded**','**Configuration receipt:**')
for i,l in enumerate(lines,1):
    if any(l.startswith(b) for b in boiler): continue
    if not l.strip(): continue
    out.append(f"{i}: {l[:int(sys.argv[3]) if len(sys.argv)>3 else 1100]}")
a,b=int(sys.argv[1]),int(sys.argv[2])
for o in out:
    n=int(o.split(':',1)[0])
    if a<=n<=b: print(o)
