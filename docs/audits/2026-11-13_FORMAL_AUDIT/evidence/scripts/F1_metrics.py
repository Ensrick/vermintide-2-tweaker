import os,sys,re,hashlib,collections,subprocess,json
R=r'<repos>/vermintide-2-tweaker'
MODS=['weapon_tweaker','weapon_tweaker_dev','character_weapon_variants','weapons_of_chaos','cosmetics_tweaker','dynamic_cosmetic_portraits','character_dialogue','chaos_wastes_tweaker','chaos_wastes_tweaker_dev','event_tweaker','enemy_tweaker','crafting_in_modded','crafting_in_modded_dev','modded_progression','career_tweaker','general_tweaker','general_tweaker_dev','gui_tweaker','gui_tweaker_dev','verminious_dreams_lighting','verminious_dreams_lighting_dev','tweaker']
files=subprocess.run(['git','-C',R,'ls-files'],capture_output=True,text=True).stdout.splitlines()
lua=[f for f in files if f.endswith('.lua')]
def read(f):
    try: return open(os.path.join(R,f),encoding='utf-8',errors='replace').read()
    except Exception as e: return ''
pat={'hook':re.compile(r'\bmod:hook\s*\('),'hook_safe':re.compile(r'\bmod:hook_safe\s*\('),'hook_origin':re.compile(r'\bmod:hook_origin\s*\('),
     'pcall':re.compile(r'\b(?:pcall|xpcall)\s*\('),'rawset_G':re.compile(r'rawset\s*\(\s*_G'),'G_write':re.compile(r'^\s*_G\.[A-Za-z_][\w]*\s*=',re.M),
     'get_mod':re.compile(r'\bget_mod\s*\(\s*["\']([\w]+)["\']'),'command':re.compile(r'\bmod:command\s*\('),'rpc_reg':re.compile(r'\bmod:network_register\s*\('),
     'net_send':re.compile(r'\bmod:network_send\s*\('),'rt_reg':re.compile(r'\b_?rt_register\s*\('),'printf':re.compile(r'\bprintf\s*\('),
     'NetworkLookup':re.compile(r'\bNetworkLookup\b'),'ItemMasterList':re.compile(r'\bItemMasterList\b'),'mod_get':re.compile(r'\bmod:get\s*\('),'mod_set':re.compile(r'\bmod:set\s*\('),
     'update_fn':re.compile(r'\bmod\.update\s*=|function\s+mod\.update\b|function\s+mod:update\b'),'TODO':re.compile(r'\b(?:TODO|FIXME|HACK|XXX)\b'),'issue_ref':re.compile(r'#\d{2,4}\b')}
stats={m:collections.Counter() for m in MODS}; deps=collections.defaultdict(collections.Counter); sizes={}
hashes=collections.defaultdict(list); bigfiles=[]
for f in lua:
    top=f.split('/')[0]
    if top not in stats: continue
    t=read(f); n=t.count('\n')+1; s=stats[top]; s['files']+=1; s['loc']+=n
    code=sum(1 for l in t.splitlines() if l.strip() and not l.strip().startswith('--')); s['code']+=code
    s['comment']+=sum(1 for l in t.splitlines() if l.strip().startswith('--'))
    for k,p in pat.items():
        if k=='get_mod':
            for m in p.findall(t): deps[top][m]+=1
        else: s[k]+=len(p.findall(t))
    if n>1500: s['over1500']+=1
    if n>2500: s['over2500']+=1
    bigfiles.append((n,f))
    base=os.path.basename(f)
    hashes[hashlib.sha1(t.replace('\r','').encode('utf-8','replace')).hexdigest()].append(f)
cols=['files','loc','code','comment','hook','hook_safe','hook_origin','pcall','rawset_G','G_write','command','rpc_reg','net_send','rt_reg','printf','NetworkLookup','ItemMasterList','mod_get','mod_set','TODO','issue_ref','over1500','over2500']
print('\t'.join(['mod']+cols))
tot=collections.Counter()
for m in MODS:
    print('\t'.join([m]+[str(stats[m][c]) for c in cols])); tot.update(stats[m])
print('\t'.join(['TOTAL']+[str(tot[c]) for c in cols]))
print('\n== get_mod dependency edges (mod dir -> referenced mod id: count)')
for m in MODS:
    if deps[m]: print(' ',m,'->',dict(deps[m].most_common()))
print('\n== largest Lua files')
for n,f in sorted(bigfiles,reverse=True)[:30]: print(' ',n,f)
print('\n== byte-identical Lua files shared across different top-level dirs')
groups=[v for v in hashes.values() if len({x.split('/')[0] for x in v})>1]
bytop=collections.Counter()
for g in groups:
    tops=tuple(sorted({x.split('/')[0] for x in g})); bytop[tops]+=1
for k,v in bytop.most_common(40): print(' ',v,k)
print('identical groups',len(groups),'files involved',sum(len(g) for g in groups))
json.dump({m:dict(stats[m]) for m in MODS},open(os.path.join(sys.argv[1],'data','F1_metrics.json'),'w'),indent=1)
