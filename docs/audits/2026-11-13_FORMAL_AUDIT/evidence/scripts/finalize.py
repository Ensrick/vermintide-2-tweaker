import os,sys,re
A=sys.argv[1]; D=os.path.join(A,'deliver')
rd=lambda p: open(p,encoding='utf-8').read()
def wr(p,s): open(p,'w',encoding='utf-8',newline='\n').write(s)
rig=rd(os.path.join(D,'_rig_result.txt')).strip(); hstat=rd(os.path.join(D,'_h_status.txt')).strip()
runid=(rd(os.path.join(D,'_rig_runid.txt')).strip() if os.path.exists(os.path.join(D,'_rig_runid.txt')) else 'queued (see status below)')
# AUDIT
a=rd(os.path.join(D,'AUDIT.src.md')) if os.path.exists(os.path.join(D,'AUDIT.src.md')) else rd(os.path.join(D,'AUDIT.md'))
if not os.path.exists(os.path.join(D,'AUDIT.src.md')): wr(os.path.join(D,'AUDIT.src.md'),a)
s8=rd(os.path.join(D,'_section8.md')).strip().replace('{{RIG_DRIVER_RESULT}}',rig)
rows=[('A1',0,4,12,3),('A2',1,7,13,3),('A3',0,5,13,3),('A4',3,7,8,4),('A5',3,5,11,5),('A6',0,7,11,5),('A7',0,5,11,5),('B1',2,7,8,4),('B2',1,7,5,2),('C1',1,3,5,1),('D1',2,4,2,0),('D2',1,3,3,0),('D3',1,3,1,0),('D4',2,3,4,1),('D5',0,4,6,2),('D6',1,5,6,3),('E1',2,7,11,3)]
t=[sum(r[i] for r in rows) for i in range(1,5)]
tab='\n'.join(f'| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {sum(r[1:])} |' for r in rows)+f'\n| **Total** | **{t[0]}** | **{t[1]}** | **{t[2]}** | **{t[3]}** | **{sum(t)}** |'
a=a.replace('{{SECTION_8}}',s8).replace('{{FINDINGS_TABLE}}',tab)
a=a.replace('19 findings are rated S0',f'{t[0]} findings are rated S0').replace('19 S0 and about 90 S1 findings are static',f'{t[0]} S0 and {t[1]} S1 findings are almost all static')
a=a.replace('About 830 in the active builds.','792 in the active builds.').replace('makes the 830 existing in-game checks run','makes the 792 existing in-game checks run')
a=a.replace('Desk research and tonight\'s experiments (section 8) show it is feasible','Desk research and experiments on the day of the audit (section 8) show it is feasible')
assert '{{' not in a, re.findall(r'\{\{.*?\}\}',a)
wr(os.path.join(D,'AUDIT.md'),a)
# PLAN
p=rd(os.path.join(D,'PLAN.src.md')) if os.path.exists(os.path.join(D,'PLAN.src.md')) else rd(os.path.join(D,'PLAN.md'))
if not os.path.exists(os.path.join(D,'PLAN.src.md')): wr(os.path.join(D,'PLAN.src.md'),p)
idx=rd(os.path.join(D,'INDEX.md')); m=re.search(r'Totals: (.*)',idx)
p=p.replace('{{INDEX}}',f'The full list of cards is generated into `INDEX.md` ({m.group(1) if m else ""}) It starts with the P0 cards, which come first whatever the wave.').replace('all (about 830)','all (792)')
assert '{{' not in p
wr(os.path.join(D,'PLAN.md'),p)
# H
hp=os.path.join(A,'plan','wp','H.md'); hs=os.path.join(A,'plan','wp','H.src.md')
h=rd(hs) if os.path.exists(hs) else rd(hp)
if not os.path.exists(hs): wr(hs,h)
h=h.replace('{{H_RUN_DRIVER}}',runid).replace('{{H_STATUS}}',hstat)
assert '{{' not in h
wr(hp,h)
print('finalized: AUDIT',len(a.splitlines()),'lines; PLAN',len(p.splitlines()),'; H',len(h.splitlines()),'; findings total',sum(t),t)
