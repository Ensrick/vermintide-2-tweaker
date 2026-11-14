# E1: classify qa/check_*.ps1 by concern (name-keyword heuristic, hand-reviewed list) and sum lines.
import os, glob, collections, re
QA = r"qa"
cls = [
 ("publication/receipt/claim/release plumbing", r"build_output|build_receipts|bundle_authority|bundle_output_set|current_source_pin|deployed_source_proof|github_release|local_deployment_receipt|machine_transaction|permanent_claim|pipeline_state|publication_|release_bundle|release_manifest|release_recovery|release_reproducibility|workshop_|vmb_launcher_path|published_ids|content_manifest|promotion|dev_only_edits|versions|cfg\b|cfg\.|mod_descriptor_line|wt_stream_parity|source_provenance|ci_hardening|ps51|worktree_budget|in_progress|diff_whitespace|mod_inventory"),
 ("tracker/cards/issue lifecycle", r"issue_status|live_card|live_test|pr_autoclose|public_release_closure|branch_reconciliation"),
 ("wt history reproducibility", r"wt_history"),
 ("docs/meta", r"stale_docs|mechanics_citations|decisions_wired|translation_readiness|loc_description_titles|diagnostic_ownership|decomposition|file_sizes|hook_test_coverage|rt_textual"),
 ("asset/bundle content contracts", r"custom_unit|cwv_old_musket|dcp_portrait|encarmine|woc_|native_resource|dofile_package|appearance"),
 ("Lua code correctness (static)", r"command_collisions|cross_mod_deps|event_register|level_lookup|loc_tags|localization|logging|lua_parse|lua_unit_tests|mp_login|name_integrity|network_lookup|pusfume|retired_big|shared_lib|unpack_safety|vmf_widget"),
]
tot = collections.defaultdict(lambda: [0, 0, []])
for p in sorted(glob.glob(os.path.join(QA, "check_*.ps1"))):
    n = os.path.basename(p)
    lines = sum(1 for _ in open(p, "rb"))
    for name, rx in cls:
        if re.search(rx, n):
            tot[name][0] += 1; tot[name][1] += lines; tot[name][2].append(n); break
    else:
        tot["UNCLASSIFIED"][0] += 1; tot["UNCLASSIFIED"][1] += lines; tot["UNCLASSIFIED"][2].append(n)
g = sum(v[0] for v in tot.values()); gl = sum(v[1] for v in tot.values())
for k, v in sorted(tot.items(), key=lambda kv: -kv[1][1]):
    print(f"{k}: {v[0]} scripts ({100*v[0]/g:.0f}%), {v[1]} lines ({100*v[1]/gl:.0f}%)")
    if k == "UNCLASSIFIED": print("   ", v[2])
print("total", g, gl)
