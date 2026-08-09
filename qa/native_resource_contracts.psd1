@{
    SchemaVersion = 1
    Issue = 749
    Policies = @(
        'shared-v2-strict'
        'shared-v2-global-preserve-unknown'
        'exact-gui-existing'
        'owned-world-existing'
        'diagnostic-only'
        'deferred-legacy'
    )
    Rows = @(
        # The census is deliberately exact. A new, removed, or moved native
        # renderer boundary must update this file and its named QA evidence.
        @{ File='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_curse_lighting_owner.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua'; Kind='material_bind'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cwv_texture_residency.lua' }
        @{ File='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cwv_texture_residency.lua' }
        @{ File='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua'; Kind='residency_proof'; Count=3; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cwv_texture_residency.lua' }
        @{ File='character_weapon_variants/scripts/mods/character_weapon_variants/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_hats.lua'; Kind='texture'; Count=3; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_custom_hats.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_hats.lua'; Kind='residency_proof'; Count=2; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_diagnostics.lua'; Kind='gui_lookup'; Count=1; Policy='diagnostic-only'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua'; Kind='texture'; Count=2; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_grail_knight_set.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua'; Kind='residency_proof'; Count=2; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'; Kind='material_bind'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'; Kind='residency_proof'; Count=2; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim.lua'; Kind='residency_proof'; Count=2; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'; Kind='material_bind'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'; Kind='residency_proof'; Count=3; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; Kind='gui_lookup'; Count=1; Policy='exact-gui-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; Kind='shading'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='crafting_in_modded/scripts/mods/crafting_in_modded/_cim_athanor_icon_policy.lua'; Kind='gui_lookup'; Count=1; Policy='exact-gui-existing'; Evidence='qa/lua/tests/test_cim_athanor_icon_policy.lua' }
        @{ File='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_athanor_icon_policy.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cim_athanor_icon_policy.lua' }
        @{ File='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_cim_mission_forge_widget_safety.lua' }
        @{ File='dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua'; Kind='gui_lookup'; Count=2; Policy='exact-gui-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='event_tweaker/scripts/mods/event_tweaker/_evt_cursed_adventure.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; Kind='gui_create'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; Kind='gui_create'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'; Kind='residency_proof'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_solo_qol.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua'; Kind='gui_create'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='general_tweaker/scripts/mods/general_tweaker/_gt_solo_qol.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_gui_material_guard.lua'; Kind='renderer_hook'; Count=1; Policy='shared-v2-global-preserve-unknown'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_gui_material_guard.lua'; Kind='residency_proof'; Count=4; Policy='shared-v2-global-preserve-unknown'; Evidence='qa/lua/tests/test_cos_resource_residency.lua' }
        @{ File='gui_tweaker/scripts/mods/gui_tweaker/_gut_gui_material_guard.lua'; Kind='renderer_hook'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev.lua'; Kind='shading'; Count=4; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='verminious_dreams_lighting/scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua'; Kind='shading'; Count=2; Policy='owned-world-existing'; Evidence='qa/lua/tests/test_resource_residency_census.lua' }
        @{ File='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='weapon_tweaker/scripts/mods/weapon_tweaker/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_weapon_appearance.lua'; Kind='texture'; Count=1; Policy='deferred-legacy'; Evidence='issue:#749' }
        @{ File='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'; Kind='material_bind'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_woc_blightreaper_pulse.lua' }
        @{ File='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'; Kind='texture'; Count=1; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_woc_blightreaper_pulse.lua' }
        @{ File='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'; Kind='residency_proof'; Count=3; Policy='shared-v2-strict'; Evidence='qa/lua/tests/test_woc_blightreaper_pulse.lua' }
    )
}
