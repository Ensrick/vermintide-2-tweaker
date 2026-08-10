@{
    Version = 1
    Contracts = @(
        @{
            Name = 'event_tweaker'
            State = 'complete'
            Entry = 'event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua'
            CeilingLines = 62
            RequiredModules = @('_evt_apply.lua', '_evt_regression.lua')
        }
        @{
            Name = 'enemy_tweaker'
            State = 'complete'
            Entry = 'enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua'
            CeilingLines = 97
            RequiredModules = @('_et_lifecycle.lua', '_et_regression.lua')
        }
        @{
            Name = 'cosmetics_tweaker'
            State = 'partial'
            Entry = 'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            CeilingLines = 3892
            RequiredModules = @('_cos_render.lua', '_cos_wire.lua', '_cos_runtime_checks.lua', '_cos_attachment_link_policy.lua', '_cos_ui_presentation_refresh.lua', '_cos_offhand_session_state.lua', '_cos_modded_illusion_swap.lua', '_cos_magic_skin_gateway.lua', '_cos_command_owner.lua', '_cos_glow_editor_button.lua', '_cos_item_grid_presentation.lua', '_cos_mod_lifecycle.lua', '_cos_la_replay_runtime.lua', '_cos_glow_transport.lua', '_cos_offhand_catalog.lua', '_cos_offhand_picker.lua', '_cos_preview_runtime.lua', '_cos_news_feed_safety.lua', '_cos_customization_view_lifecycle.lua', '_cos_attachment_spawn_sync.lua', '_cos_equipment_assembly.lua', '_cos_la_apply_runtime.lua', '_cos_la_sync_transport.lua')
        }
        @{
            Name = 'weapon_tweaker'
            State = 'partial'
            Entry = 'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'
            CeilingLines = 3071
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_cross_char_template_patches.lua', '_wt_moonfire_aoe.lua', '_wt_regression.lua', '_wt_weapon_balance_patches.lua')
        }
        @{
            Name = 'weapon_tweaker_dev'
            State = 'partial'
            Entry = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'
            CeilingLines = 3230
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_cross_char_template_patches.lua', '_wt_moonfire_aoe.lua', '_wt_regression.lua', '_wt_weapon_balance_patches.lua')
        }
        @{
            Name = 'career_tweaker_balance'
            State = 'complete'
            Entry = 'career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'
            CeilingLines = 910
            RequiredModules = @('_career_tweaker_balance_hooks.lua', '_crt_foot_knight.lua', '_crt_balance_catalog.lua')
        }
        @{
            # First entry brought under the 2500-line HARD limit (issue #1159).
            # State stays 'partial': 'complete' additionally requires the entry
            # to be at or under the 1500-line TARGET (see the State check in
            # check_decomposition_contracts.ps1), which this entry is not.
            # Its qa/baselines/file_sizes.json row was removed at the same time,
            # matching how career_tweaker_balance left the frozen-debt set.
            Name = 'crafting_in_modded_dev'
            State = 'partial'
            Entry = 'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'
            CeilingLines = 2353
            RequiredModules = @('_cim_forge_preview.lua', '_cim_forge_preview_owner.lua', '_cim_forge_picker_owner.lua', '_cim_forge_ui_owner.lua', '_cim_inventory_filter.lua', '_cim_command_owner.lua', '_cim_weave_economy.lua', '_cim_modded_loadout_owner.lua', '_cim_weave_loadout_owner.lua', '_cim_regression_checks.lua')
        }
        @{
            Name = 'chaos_wastes_tweaker_dev'
            State = 'partial'
            Entry = 'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'
            CeilingLines = 4717
            RequiredModules = @('_ct_altar_reuse_owner.lua', '_ct_boon_offer_view_owner.lua', '_ct_campaign_graph_owner.lua', '_ct_chest_revive_owner.lua', '_ct_combat_hooks.lua', '_ct_boon_grant_owner.lua', '_ct_boon_registry.lua', '_ct_boon_preview_helpers.lua', '_ct_boss_grudge_marks.lua', '_ct_bot_weapon_chest_owner.lua', '_ct_command_owner.lua', '_ct_curse_lighting_owner.lua', '_ct_journey_difficulty_guard.lua', '_ct_level_load_owner.lua', '_ct_node_entry_owner.lua', '_ct_pickup_population_owner.lua', '_ct_pickup_spawn_owner.lua', '_ct_spawn_eligibility_owner.lua', '_ct_tab_panel_owner.lua', '_ct_weapon_trait_generation.lua', '_ct_regression.lua')
        }
        @{
            Name = 'character_weapon_variants'
            State = 'partial'
            Entry = 'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            CeilingLines = 3849
            RequiredModules = @('_cwv_variant_catalog.lua', '_cwv_core_templates.lua', '_cwv_skin_registry.lua', '_cwv_illusion_families.lua', '_cwv_husk_path.lua', '_cwv_musket_runtime.lua', '_cwv_husk_residency_owner.lua', '_cwv_item_registration_owner.lua', '_cwv_menu_preview_owner.lua', '_cwv_weapon_transform_owner.lua', '_cwv_custom_mesh_runtime.lua', '_cwv_musket_equip_surface.lua', '_cwv_regression_identity.lua', '_cwv_illusion_provenance.lua')
        }
        @{
            # Inventoried at 2455 nonblank lines, 45 under the 2500 hard limit.
            # Below the limit it has no baseline row in file_sizes.json, so
            # before this contract nothing would have stopped it crossing.
            Name = 'weapons_of_chaos'
            State = 'partial'
            Entry = 'weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            CeilingLines = 2455
            RequiredModules = @('_woc_wire_policy.lua', '_woc_blightreaper_moveset.lua', '_woc_blightreaper_power.lua', '_woc_blightreaper_audio.lua', '_woc_blightreaper_pulse.lua', '_woc_blightreaper_spirits.lua', '_woc_cursed_rarity.lua', '_woc_attack_order.lua', '_woc_appearance_policy.lua', '_woc_mod_unit_preview.lua', '_woc_inventory_icons.lua', '_woc_relic_policy.lua')
        }
    )
}
