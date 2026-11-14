"""A2: extract a compact variant table from _cwv_variant_catalog.lua (regex, read-only)."""
import re, sys
p = sys.argv[1]
src = open(p, encoding='utf-8', errors='replace').read().split('\n')
rows = []; cur = None; depth = 0
keyre = re.compile(r'^\s*([a-zA-Z_0-9]+)\s*=\s*(.+?),?\s*(--.*)?$')
for i, l in enumerate(src, 1):
    s = l.strip()
    if s.startswith('--'): continue
    m = keyre.match(l)
    if m and m.group(1) == 'item_key':
        cur = {'line': i, 'item_key': m.group(2).strip('", ')}
        rows.append(cur); continue
    if cur is not None and m:
        k = m.group(1); v = m.group(2).strip().rstrip(',')
        if k in ('base_weapon','template','rarity','character','item_type','slot_type','cross_slot','cwv_retired','skin_only','power_level','right_hand_unit','left_hand_unit','custom_mesh','style_target_item','careers','mod_unit','husk_units','display_name','skin_rarity','hidden','husk_right_hand_unit','husk_left_hand_unit','weapon_template'):
            cur.setdefault(k, v.strip('"'))
print('n item_key rows:', len(rows))
allkeys = set()
for r in rows: allkeys |= set(r)
print('fields seen:', sorted(allkeys))
for r in rows:
    print('\t'.join([str(r['line']), r['item_key'], r.get('base_weapon','-'), r.get('template','-'), r.get('rarity','-'), r.get('character','-'), r.get('item_type','-'), ('RETIRED' if r.get('cwv_retired') else ''), ('SKINONLY' if r.get('skin_only') else ''), ('XSLOT' if r.get('cross_slot') else ''), r.get('right_hand_unit','-').split('/')[-1], r.get('left_hand_unit','-').split('/')[-1]]))
