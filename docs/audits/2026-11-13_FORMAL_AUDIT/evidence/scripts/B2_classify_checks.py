import os, sys, re, collections
repo = r"<repos>/vermintide-2-tweaker"
qa = os.path.join(repo, "qa")
# category map by exact name (auditor judgement from reading each header; see findings B2)
P_SRC = """check_command_collisions check_cross_mod_deps check_decisions_wired check_dofile_package_coverage
check_event_register_signature check_level_lookup_budget check_loc_description_titles check_loc_tags
check_localization check_logging check_lua_parse check_lua_unit_tests check_mp_login_source_contract
check_name_integrity check_native_resource_contracts check_native_resource_safety
check_network_lookup_append_budget check_pusfume_compatibility check_retired_big_rebalance
check_rt_textual_invariants check_shared_lib_drift check_translation_readiness check_unpack_safety
check_vmf_widget_types check_wt_stream_parity check_appearance_contracts check_hook_test_coverage
check_mod_descriptor_line_endings check_cfg""".split()
P_ASSET = """check_custom_unit_bundle_reachability check_cwv_old_musket_asset_contract
check_cwv_old_musket_compiled_contract check_dcp_portrait_atlas check_encarmine_bundle_contract
check_woc_blightreaper_bundle_contract check_woc_skarrik_asset_sources check_woc_skarrik_halberd_sources""".split()
STRUCT = """check_file_sizes check_decomposition_contracts check_diagnostic_ownership check_mod_inventory
check_dev_only_edits check_appearance_census_gaps""".split()
REL = """check_build_output_normalization check_build_receipts check_bundle_authority check_bundle_output_set
check_content_manifest check_current_source_pin_recovery check_deployed_source_proof
check_github_release_fallback check_local_deployment_receipt check_machine_transaction_lease
check_permanent_claim_allocation check_promotion check_promotion_authorization
check_public_release_closure_collector check_public_release_closure_evidence
check_public_release_closure_policy check_public_release_closure_transport check_publication_doctrine
check_publication_pin_finalization check_publication_pin_handoff check_publication_receipt
check_publication_snapshot check_published_ids check_release_bundle_atomicity check_release_manifest
check_release_recovery_record check_release_reproducibility check_versions check_vmb_launcher_path
check_workshop_nochange_result check_workshop_published_file_snapshot check_workshop_upload_evidence
check_workshop_upload_result check_workshop_upload_result_release check_custom_unit_gate_reporting""".split()
TRACK = """check_branch_reconciliation_census check_ci_hardening check_diff_whitespace check_in_progress
check_issue_status_labels check_live_card_receipts check_live_test_contract check_mechanics_citations
check_pipeline_state check_pr_autoclose check_ps51_compatibility check_source_provenance check_stale_docs
check_worktree_budget""".split()
cats = collections.OrderedDict([
 ("A product: mod source / loc / data static", P_SRC),
 ("B product: asset / compiled-bundle content", P_ASSET),
 ("C structure / maintainability census", STRUCT),
 ("D release / publication / receipt / claim pipeline", REL),
 ("E tracker / docs / CI / repo-process", TRACK),
])
files = sorted(f for f in os.listdir(qa) if f.startswith("check_") and f.endswith(".ps1"))
def lines(f):
    with open(os.path.join(qa, f), "rb") as fh: return fh.read().count(b"\n")
assigned = {}
for c, names in cats.items():
    for n in names: assigned[n + ".ps1"] = c
tot = collections.Counter(); cnt = collections.Counter(); un = []
for f in files:
    c = assigned.get(f)
    if c is None:
        if f.startswith("check_wt_history"): c = "F generated-data provenance / reproducibility (wt history)"
        else: un.append(f); c = "?? unassigned"
    tot[c] += lines(f); cnt[c] += 1
for c in sorted(cnt): print(f"{c:60s} files={cnt[c]:3d} lines={tot[c]:6d}")
print("TOTAL", sum(cnt.values()), sum(tot.values())); print("unassigned", un)
missing = [n for n in assigned if n not in files]; print("mapped-but-missing", missing)
