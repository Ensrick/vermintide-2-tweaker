# D6 round 2: curated dev-only fix identifier table (markdown). Read-only git grep on origin/master.
import os, re, json, subprocess
REPO = r'<repos>/vermintide-2-tweaker'
OUT = r'docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D6_out'
def git(*a): return subprocess.run(['git', '-C', REPO] + list(a), capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
rows = {r['number']: r for r in json.load(open(os.path.join(OUT, 'ledger_rows.json'), encoding='utf-8'))}
CW = [(63,'issue63_cot_cost_transaction'),(68,'ct:mapnode68'),(114,'boon_offer_scrollbar_wired'),(115,'boon_offer_scrollbar_wired'),(121,'pre_rarity'),(133,'description_deus_crit_chain_lightning'),
      (136,'apply_host_graph_snapshot_to_live_run'),(157,'ct:crash157'),(294,'_ct_pickup_unit_spawn_safe'),(331,'issue331_bot_coin_pickup_installed'),(350,'issue350_cot_early_reward_policy'),
      (351,'_ct351_rewrite_network_spawn'),(556,'issue556_starting_talent_identity'),(590,'map_duplicate_level_aliases'),(1004,'issue1004_boon_hover_tooltip_wired'),(291,'ct:journeyguard'),(406,'ct:406')]
GT = [(139,'gt_bot139_teleport_veto_singleton_and_gated'),(255,'_ult_screen_fx'),(293,'_gt_btlab_gui_deferred'),(295,'_gt_btlab_gui_deferred'),(304,'_gt_restore_keep_dummy_collision'),(308,'gt_melee_warning'),
      (320,'bot_drink_potion_advanced_conditions_registered'),(337,'_drain_pending_recall'),(492,'_gt492_should_suppress_pick'),(523,'issue523_bot_heal_allies_policy'),(600,'issue600_wait_aim_and_duration'),
      (693,'gt693_cs_client_request_wired'),(731,'channel_closed_during_send'),(939,'issue939_godmode_ledge_boundary')]
def table(lst, dev, stable):
    sf = set(os.path.basename(p) for p in git('ls-tree', '-r', '--name-only', 'origin/master', '--', stable + '/scripts').split('\n') if p)
    out = []
    for n, t in lst:
        w = [] if ':' in t else ['-w']
        hits = [h for h in git('grep', '-n', '-I', '-F', *w, '-e', t, 'origin/master', '--', dev + '/scripts').split('\n') if h]
        best = next((h for h in hits if re.search(r'(function\s+[\w.:]*%s|%s\s*=\s*function|_rt_register\(\s*["\']%s|rt_register\(\s*["\']%s|setting_id\s*=\s*"%s")' % ((re.escape(t),) * 5), h)), hits[0] if hits else None)
        cnt = git('grep', '-c', '-I', '-F', *w, '-e', t, 'origin/master', '--', stable)
        ns = sum(int(l.rsplit(':', 1)[1]) for l in cnt.split('\n') if l)
        r = rows[n]
        if best:
            p = best.split(':', 3); loc = '`%s:%s`' % (p[1], p[2]); same = 'yes' if os.path.basename(p[1]) in sf else 'no'
        else: loc = 'NOT FOUND'; same = '?'
        crash = 'yes' if r['typ'] == 'crash' else ('no (%s)' % (r['prio'] or 'no priority'))
        out.append('| #%d %s | `%s` | %s | `git grep -c %s-F "%s" origin/master -- %s/` = %d | %s | %s |' % (n, r['title'][:48].replace('|', '/').strip(), t, loc, '-w ' if w else '', t, stable, ns, crash, same))
    return out
txt = []
txt += ['CW'] + table(CW, 'chaos_wastes_tweaker_dev', 'chaos_wastes_tweaker')
txt += ['GT'] + table(GT, 'general_tweaker_dev', 'general_tweaker')
open(os.path.join(OUT, 'stable_gaps_table.md'), 'w', encoding='utf-8').write('\n'.join(txt))
print('\n'.join(txt))
