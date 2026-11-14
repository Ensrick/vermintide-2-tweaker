p='findings/A2.md'; s=open(p,encoding='utf-8').read()
def rep(a,b):
    global s
    assert a in s, 'missing: '+a[:80]
    s=s.replace(a,b,1)
rep("`mod.update` is wrapped three times in a chain (`_lib_peer_parity.lua:654`, `_cwv_rewield_coalescer.lua:256`, `_cwv_item_identity_transport_owner.lua:556`).",
    "`mod.update` is re-wrapped in a chain from three places (`_lib_peer_parity.lua:654`, once per parity instance; `_cwv_rewield_coalescer.lua:256`; `_cwv_item_identity_transport_owner.lua:556`).")
rep("`variant_catalog:487-579,1016-1069`, `cross_access:115-135` | #704 | rt: none specific; ut: none specific |",
    "`variant_catalog:487-579,1016-1069`, `cross_access:115-135` | none open | rt: none specific; ut: none specific |")
rep("R: bot or scripted throw in the keep, assert a pickup unit of `cwv_tuskgor_javelin` exists afterwards and ammo dropped by 1.",
    "R: scripted throw in the keep, assert a pickup with the mod's registered javelin `pickup_names` key exists afterwards and ammo dropped by 1.")
rep("R: after wield, assert each cwv 3P unit is enrolled in the fade system's unit list",
    "R: after wield, assert each cwv 3P unit was handed to `FadeSystem.new_linked_units` for its owner (record the call in a tap)")
open(p,'w',encoding='utf-8',newline='\n').write(s); print('ok')
