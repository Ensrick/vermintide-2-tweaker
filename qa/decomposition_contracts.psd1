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
            # Structural phase completed at 0.9.207-dev (#1159): the entry is
            # at or below the 1500-line target and every extracted owner is
            # retained by this machine-readable contract.
            Name = 'cosmetics_tweaker'
            State = 'complete'
            Entry = 'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            CeilingLines = 1494
            RequiredModules = @('_cos_render.lua', '_cos_wire.lua', '_cos_runtime_checks.lua', '_cos_attachment_link_policy.lua', '_cos_ui_presentation_refresh.lua', '_cos_offhand_session_state.lua', '_cos_modded_illusion_swap.lua', '_cos_magic_skin_gateway.lua', '_cos_command_owner.lua', '_cos_glow_editor_button.lua', '_cos_item_grid_presentation.lua', '_cos_mod_lifecycle.lua', '_cos_la_replay_runtime.lua', '_cos_glow_transport.lua', '_cos_offhand_catalog.lua', '_cos_offhand_picker.lua', '_cos_preview_runtime.lua', '_cos_news_feed_safety.lua', '_cos_customization_view_lifecycle.lua', '_cos_attachment_spawn_sync.lua', '_cos_equipment_assembly.lua', '_cos_la_apply_runtime.lua', '_cos_la_sync_transport.lua', '_cos_la_loadout_safety.lua', '_cos_glow_picker_host.lua', '_cos_local_wield_runtime.lua', '_cos_update_scheduler.lua', '_cos_item_presentation_runtime.lua', '_cos_spawn_boundary.lua', '_cos_moonfire_puff_runtime.lua', '_cos_la_husk_identity_runtime.lua', '_cos_husk_wield_runtime.lua', '_cos_offhand_state_runtime.lua', '_cos_offhand_apply_runtime.lua', '_cos_offhand_diagnostics.lua', '_cos_glow_diagnostics_runtime.lua', '_cos_deus_yield_policy.lua')
        }
        @{
            # Structural completion at 0.12.303-beta (#1159). Transform and
            # cross-character fatal-safety ownership moved behind explicit
            # installers; the 3P visibility repair joined its existing swap
            # owner. Stable/dev remain a parity-locked pair.
            Name = 'weapon_tweaker'
            State = 'complete'
            Entry = 'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'
            CeilingLines = 1328
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_cross_character_safety.lua', '_wt_cross_char_template_patches.lua', '_wt_ingame_3p_swap_owner.lua', '_wt_longbow_variable_zoom.lua', '_wt_menu_preview_owner.lua', '_wt_moonfire_aoe.lua', '_wt_regression.lua', '_wt_transform_runtime.lua', '_wt_weapon_balance_patches.lua')
        }
        @{
            # Mirror of the row above; the 159-line difference is the explicit
            # WT_DEV_OVERLAY surface admitted by the parity gate.
            Name = 'weapon_tweaker_dev'
            State = 'complete'
            Entry = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'
            CeilingLines = 1487
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_cross_character_safety.lua', '_wt_cross_char_template_patches.lua', '_wt_ingame_3p_swap_owner.lua', '_wt_longbow_variable_zoom.lua', '_wt_menu_preview_owner.lua', '_wt_moonfire_aoe.lua', '_wt_regression.lua', '_wt_transform_runtime.lua', '_wt_weapon_balance_patches.lua')
        }
        @{
            Name = 'career_tweaker_balance'
            State = 'complete'
            Entry = 'career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'
            CeilingLines = 910
            RequiredModules = @('_career_tweaker_balance_hooks.lua', '_crt_foot_knight.lua', '_crt_balance_catalog.lua')
        }
        @{
            # Structural phase completed at 0.8.121-dev (#1159): the entry is
            # at or below the 1500-line target and the contract retains every
            # extracted bootstrap, state, wire, forge, loadout, and regression
            # owner.
            Name = 'crafting_in_modded_dev'
            State = 'complete'
            Entry = 'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'
            CeilingLines = 1433
            RequiredModules = @('_cim_bootstrap_runtime.lua', '_cim_forge_state_owner.lua', '_cim_loadout_wire_owner.lua', '_cim_forge_preview.lua', '_cim_forge_preview_owner.lua', '_cim_forge_picker_owner.lua', '_cim_forge_ui_owner.lua', '_cim_inventory_filter.lua', '_cim_command_owner.lua', '_cim_weave_economy.lua', '_cim_modded_loadout_owner.lua', '_cim_weave_loadout_owner.lua', '_cim_regression_checks.lua')
        }
        @{
            # Completed by extracting host-state transport, run/backend
            # orchestration, adventure presentation, boon/grudge runtime, and
            # settings lifecycle into explicit owners. Entry is 1498 nonblank
            # lines, below the 1500-line target.
            Name = 'chaos_wastes_tweaker_dev'
            State = 'complete'
            Entry = 'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'
            CeilingLines = 1498
            RequiredModules = @('_ct_adventure_runtime_owner.lua', '_ct_altar_reuse_owner.lua', '_ct_boon_balance.lua', '_ct_boon_offer_view_owner.lua', '_ct_boon_runtime_owner.lua', '_ct_campaign_graph_owner.lua', '_ct_chest_revive_owner.lua', '_ct_combat_hooks.lua', '_ct_boon_grant_owner.lua', '_ct_boon_registry.lua', '_ct_boon_preview_helpers.lua', '_ct_boss_grudge_marks.lua', '_ct_bot_weapon_chest_owner.lua', '_ct_command_owner.lua', '_ct_curse_lighting_owner.lua', '_ct_diag_gargoyle1124.lua', '_ct_host_state_transport_owner.lua', '_ct_journey_difficulty_guard.lua', '_ct_level_load_owner.lua', '_ct_meta_boon_owner.lua', '_ct_meta_trait_boons.lua', '_ct_node_entry_owner.lua', '_ct_peer_manifest_owner.lua', '_ct_pickup_population_owner.lua', '_ct_pickup_spawn_owner.lua', '_ct_run_creation_owner.lua', '_ct_run_runtime_owner.lua', '_ct_settings_lifecycle_owner.lua', '_ct_spawn_eligibility_owner.lua', '_ct_stack_rebroadcast_owner.lua', '_ct_tab_panel_owner.lua', '_ct_weapon_trait_generation.lua', '_ct_regression.lua')
        }
        @{
            # Completed by extracting the Tuskgor Javelin and Rapier runtimes,
            # ordered localization/skin/item bootstrap, exact item-identity
            # transport, and world-equipment presentation into explicit owners.
            # Entry is 1490 nonblank lines, below the 1500-line target.
            Name = 'character_weapon_variants'
            State = 'complete'
            Entry = 'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            CeilingLines = 1490
            RequiredModules = @('_cwv_variant_catalog.lua', '_cwv_core_templates.lua', '_cwv_skin_registry.lua', '_cwv_illusion_families.lua', '_cwv_husk_path.lua', '_cwv_musket_runtime.lua', '_cwv_musket_ammo_hud.lua', '_cwv_husk_residency_owner.lua', '_cwv_item_registration_owner.lua', '_cwv_menu_preview_owner.lua', '_cwv_weapon_transform_owner.lua', '_cwv_custom_mesh_runtime.lua', '_cwv_musket_equip_surface.lua', '_cwv_javelin_runtime_owner.lua', '_cwv_rapier_runtime_owner.lua', '_cwv_variant_bootstrap_owner.lua', '_cwv_item_identity_transport_owner.lua', '_cwv_world_equipment_owner.lua', '_cwv_regression_identity.lua', '_cwv_regression_husk_ammo.lua', '_cwv_illusion_provenance.lua')
        }
        @{
            # Completed by extracting registration/Deus lifecycle and native
            # Shyish spirit runtime into explicit owners. Entry is 1390
            # nonblank lines, below the 1500-line completion target.
            Name = 'weapons_of_chaos'
            State = 'complete'
            Entry = 'weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            CeilingLines = 1390
            RequiredModules = @('_woc_wire_policy.lua', '_woc_blightreaper_moveset.lua', '_woc_blightreaper_power.lua', '_woc_blightreaper_audio.lua', '_woc_blightreaper_pulse.lua', '_woc_blightreaper_spirits.lua', '_woc_cursed_rarity.lua', '_woc_attack_order.lua', '_woc_appearance_policy.lua', '_woc_mod_unit_preview.lua', '_woc_inventory_icons.lua', '_woc_relic_policy.lua', '_woc_relic_registration_owner.lua', '_woc_spirit_runtime_owner.lua')
        }
    )
}
