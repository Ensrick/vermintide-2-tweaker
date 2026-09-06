-- Machine-readable completeness contract for the exposed history catalog.
--
-- This ledger distinguishes bounded adjacent patch deltas from the Patch 5.2
-- direct historical baselines. _wt_history_catalog.lua validates it before the
-- runtime exposes any selector, so a missing, extra, or misclassified row makes
-- the whole history surface unavailable instead of silently overclaiming it.
return {
    catalogs = {
        {
            catalog_id = "wt_history_patch_2_0_6_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 2.0.6 Handgun hipfire/aimed penetration leaves projected onto both current gameplay clones",
            exclusions = {
                { id = "adjacent_key_order_churn", reason = "all other handguns.lua movement is table-key ordering" },
                { id = "unrelated_dot_network_sync", reason = "the adjacent weapons.lua DoT network-sync fix is outside this Handgun boundary" },
                { id = "current_versus_clones", reason = "current Versus Handgun clones do not exist at the adjacent boundary" },
            },
            family_states = {
                { family_id = "handgun_shared", operations = 6, profiles = 0, state_id = "2_0_5" },
            },
            later_same_leaf_policy = "only the three adjacent leaves are projected onto each exact current gameplay clone over source-derived guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_2_0_9_1_halberd_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 2.0.9.1 Halberd push-follow-up chain leaves only",
            exclusions = {
                { id = "outside_halberd_push_follow_up", reason = "all other adjacent source changes are outside the official missing-overhead fix" },
            },
            family_states = {
                { family_id = "kruber_halberd", operations = 20, profiles = 0, state_id = "2_0_9" },
            },
            later_same_leaf_policy = "only the exact adjacent push-follow-up chain is projected over current source-derived guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_2_0_10_sword_and_dagger_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 2.0.10 Sword-and-Dagger heavy-profile melee-boost values and their four exact current routes",
            exclusions = {
                { id = "outside_sword_and_dagger_family", reason = "all other adjacent Patch 2.0.10 files and leaves are outside the official Sword-and-Dagger heavy-attack fix" },
                { id = "shared_profile_consumers", reason = "native shared profiles remain current; only private profiles on exact Sword-and-Dagger routes are selected" },
            },
            family_states = {
                { family_id = "sword_and_dagger", operations = 4, profiles = 2, state_id = "2_0_9_1" },
            },
            later_same_leaf_policy = "only the two adjacent scalar values are projected into private current-schema profiles over exact current route guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_3_1_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 3.1 Blunderbuss maximum-ammunition and Tuskgor Spear block-cost leaves only",
            exclusions = {
                { id = "current_only_versus_template", reason = "blunderbuss_template_1_vs is absent from both adjacent revisions and remains current" },
            },
            family_states = {
                { family_id = "kruber_blunderbuss", operations = 1, profiles = 0, state_id = "pre_3_1_delta" },
                { family_id = "tuskgor_spear", operations = 1, profiles = 0, state_id = "pre_3_1_delta" },
            },
            later_same_leaf_policy = "only the adjacent 12-to-16 ammo and 0.25-to-0.5 block-cost deltas are projected over exact current guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_3_2_v1",
            cumulative_backfill = false,
            declared_scope = "Kerillian One-Handed Axe Patch 3.2 push-follow-up critical-chance leaf only",
            exclusions = {},
            family_states = {
                { family_id = "elf_one_handed_axe", operations = 1, profiles = 0, state_id = "3_1_0" },
            },
            later_same_leaf_policy = "only the adjacent Patch 3.2 leaf is projected; later absent-current state is guarded explicitly",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_5_2_v1",
            cumulative_backfill = true,
            declared_scope = "all official Patch 5.2.0 and 5.2.3 named weapon groups in the recorded source surfaces",
            exclusions = {
                { id = "flaming_sword_unowned_delta", reason = "source-semantic fatigue-cost delta is absent from the official named weapon groups" },
                { id = "presentation_roots", reason = "units, animation state machines, sounds, tooltips, and other presentation roots remain current" },
            },
            family_states = {
                { family_id = "coruscation_staff", operations = 9, profiles = 3, state_id = "5_1_1" },
                { family_id = "dual_daggers", operations = 6, profiles = 0, state_id = "5_1_1" },
                { family_id = "dual_daggers", operations = 6, profiles = 1, state_id = "5_2_0" },
                { family_id = "one_handed_sword_shared", operations = 9, profiles = 2, state_id = "5_1_1" },
                { family_id = "one_handed_sword_shared", operations = 7, profiles = 1, state_id = "5_2_0" },
                { family_id = "two_handed_sword_shared", operations = 3, profiles = 1, state_id = "5_1_1" },
                { family_id = "one_handed_axe_shared", operations = 24, profiles = 1, state_id = "5_1_1" },
                { family_id = "one_handed_axe_shared", operations = 22, profiles = 0, state_id = "5_2_0" },
                { family_id = "one_handed_hammer_shared", operations = 9, profiles = 0, state_id = "5_1_1" },
                { family_id = "one_handed_hammer_shared", operations = 6, profiles = 0, state_id = "5_2_0" },
                { family_id = "javelin", operations = 0, profiles = 4, state_id = "5_1_1" },
                { family_id = "elf_one_handed_axe", operations = 33, profiles = 1, state_id = "5_1_1" },
                { family_id = "elf_one_handed_axe", operations = 15, profiles = 0, state_id = "5_2_0" },
                { family_id = "kruber_sword_and_shield", operations = 6, profiles = 0, state_id = "5_1_1" },
                { family_id = "kruber_sword_and_shield", operations = 5, profiles = 0, state_id = "5_2_0" },
                { family_id = "falchion", operations = 4, profiles = 0, state_id = "5_2_0" },
                { family_id = "falchion", operations = 3, profiles = 0, state_id = "5_2_3" },
                { family_id = "crowbill", operations = 7, profiles = 0, state_id = "5_2_0" },
                { family_id = "crowbill", operations = 6, profiles = 0, state_id = "5_2_3" },
                { family_id = "one_handed_flail", operations = 1, profiles = 0, state_id = "5_2_0" },
                { family_id = "sword_and_dagger", operations = 1, profiles = 0, state_id = "5_2_0" },
                { family_id = "masterwork_pistol", operations = 0, profiles = 1, state_id = "5_2_0" },
            },
            later_same_leaf_policy = "each selected historical state is projected directly over the current anchor",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "complete_direct_historical_baseline",
        },
        {
            catalog_id = "wt_history_patch_6_0_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 6.0 sword-and-shield scalar leaves and Fireball charged profile route",
            exclusions = {
                { id = "outside_declared_patch_slice", reason = "other Patch 6.0 changes are outside this independently proven shield-and-Fireball slice" },
            },
            family_states = {
                { family_id = "kruber_sword_and_shield", operations = 5, profiles = 0, state_id = "5_6_1" },
                { family_id = "kruber_bretonnian_sword_and_shield", operations = 6, profiles = 0, state_id = "5_6_1" },
                { family_id = "sienna_fireball_staff", operations = 0, profiles = 1, state_id = "5_6_1" },
            },
            later_same_leaf_policy = "only the adjacent Patch 6.0 leaves are projected against exact current guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_6_6_v1",
            cumulative_backfill = false,
            declared_scope = "Patch 6.6 Deepwood Staff chaos-bulwark lift across two weapon templates and the vortex table",
            exclusions = {
                { id = "later_breed_rows", reason = "later rows such as chaos_tether_sorcerer remain current" },
            },
            family_states = {
                { family_id = "deepwood_staff", operations = 3, profiles = 0, state_id = "6_5_4" },
            },
            later_same_leaf_policy = "only the three adjacent chaos-bulwark leaves are removed transactionally",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_6_8_v1",
            cumulative_backfill = false,
            declared_scope = "Kerillian Greatsword Patch 6.8 first-heavy range leaf only",
            exclusions = {
                { id = "outside_declared_patch_slice", reason = "other Patch 6.8 content is outside this one-leaf source-proven slice" },
            },
            family_states = {
                { family_id = "elf_greatsword", operations = 1, profiles = 0, state_id = "6_7_2" },
            },
            later_same_leaf_policy = "only the adjacent first-heavy range leaf is projected over its current guard",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_6_11_0_v3",
            cumulative_backfill = false,
            declared_scope = "Patch 6.11.0 Kruber Longbow automatic-zoom delay, shared one-handed Hammer/Mace block-angle and dodge-count leaves, and Kerillian Swiftbow maximum-ammunition leaf",
            exclusions = {
                { id = "outside_declared_patch_6_11_0_families", reason = "all other Patch 6.11.0 changes are outside these independently proven scalar families" },
                { id = "swiftbow_profile_changes", reason = "the Swiftbow cleave and headshot changes live in shared damage/power profiles outside the ammo-capacity template leaf" },
            },
            family_states = {
                { family_id = "kruber_longbow", operations = 2, profiles = 0, state_id = "6_10_0" },
                { family_id = "one_handed_hammer_shared", operations = 6, profiles = 0, state_id = "6_10_0" },
                { family_id = "kerillian_swiftbow", operations = 1, profiles = 0, state_id = "6_10_0_swiftbow_ammunition" },
            },
            later_same_leaf_policy = "only the adjacent Longbow timing, shared Hammer/Mace block/dodge, and Swiftbow maximum-ammunition leaves are projected over exact current guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_6_11_2_reversions_v2",
            cumulative_backfill = false,
            declared_scope = "Hotfix 6.11.2 Sienna Dagger Heavy Attack 2 and Axe-and-Falchion Heavy Attack 1/2 damage-profile route reversions",
            exclusions = {
                { id = "outside_declared_native_route_reversions", reason = "all other Hotfix 6.11.2 changes are outside this independently proven three-route slice" },
            },
            family_states = {
                { family_id = "sienna_dagger", operations = 1, profiles = 0, state_id = "6_11_1" },
                { family_id = "axe_and_falchion", operations = 2, profiles = 0, state_id = "6_11_1" },
            },
            later_same_leaf_policy = "only the three adjacent reverted damage-profile routes are projected over their exact current guards",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_4_1_1_v1",
            cumulative_backfill = false,
            declared_scope = "Masterwork Pistol Patch 4.1.1 ammo-pickup reload flag only",
            exclusions = {},
            family_states = {
                { family_id = "masterwork_pistol", operations = 1, profiles = 0, state_id = "4_0_1" },
            },
            later_same_leaf_policy = "only the adjacent present-false flag is projected; absence and false remain distinct",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
        {
            catalog_id = "wt_history_patch_4_6_hagbane_v1",
            cumulative_backfill = false,
            declared_scope = "Hagbane Patch 4.6 finesse-DoT flags and their two current profile routes",
            exclusions = {
                { id = "ricochet_behavior", reason = "aoe_on_bounce belongs to Ricochet-talent behavior" },
                { id = "weapon_diagram", reason = "weapon_diagram is presentation-only" },
                { id = "moonfire_boundary", reason = "Moonfire crosses a global buff profile, timing, and live explosion references outside this atomic slice" },
            },
            family_states = {
                { family_id = "hagbane_shortbow", operations = 0, profiles = 2, state_id = "4_5_1" },
            },
            later_same_leaf_policy = "only the two adjacent finesse flags are removed from current-schema private profiles",
            official_coverage = "complete_for_declared_scope",
            projection_kind = "adjacent_delta",
        },
    },
    current_revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    schema = 1,
    stream_identity = "public_dev_byte_identical",
    totals = {
        catalogs = 13,
        families = 27,
        family_states = 40,
        operations = 243,
        states = 16,
    },
}
