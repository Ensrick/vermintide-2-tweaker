import re
p='findings/A2.md'; s=open(p,encoding='utf-8').read()
def rep(a,b):
    global s
    assert a in s, 'missing: '+a[:70]
    s=s.replace(a,b,1)
rep("is an ordered script of about 75 `mod:dofile` calls (132 across the mod)","is an ordered script of 97 `mod:dofile` calls (132 across the mod)")
rep("1. `:5-113` policy modules loaded into one table `_om` (pure-ish modules, no hooks).","1. `:5-113` mostly policy modules loaded into one table `_om`; three already install side effects (smoke-bomb probe `:9`, re-wield coalescer `:112`, exact-pair channel `:113`).")
rep("| `mod:network_register` channels | 6 | 3 |","| `mod:network_register` | 6 call sites, 8 channels at runtime (the shared parity lib is instantiated 3 times) | 3 |")
rep("| offline tests mentioning the mod (`qa/lua/tests`) | 108 files | 20 files |","| offline tests (`qa/lua/tests`) | 108 files named `*cwv*` | 20 files named `*woc*`; 140 files in total reference either mod's source path |")
rep("12. `:1537-1574` four in-game regression modules.","12. `:1537-1574` in-game regression modules (four installed here plus one owner module they load).")
open(p,'w',encoding='utf-8',newline='\n').write(s)
# table sanity: consecutive rows starting with '|' must have the same number of unescaped pipes
lines=s.split('\n'); bad=[]; prev=None
for i,l in enumerate(lines,1):
    if l.startswith('|'):
        n=len(re.findall(r'(?<!\)\|',l))
        if prev is not None and n!=prev: bad.append((i,n,prev))
        prev=n
    else: prev=None
print('table column mismatches:',bad[:20])
print('em dashes:',s.count('—'),'en dashes:',s.count('–'),'lines:',len(lines),'words:',len(s.split()))
