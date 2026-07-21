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
            CeilingLines = 10229
            RequiredModules = @('_cos_render.lua', '_cos_wire.lua', '_cos_runtime_checks.lua', '_cos_attachment_link_policy.lua')
        }
        @{
            Name = 'weapon_tweaker'
            State = 'partial'
            Entry = 'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'
            CeilingLines = 4183
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_regression.lua')
        }
        @{
            Name = 'weapon_tweaker_dev'
            State = 'partial'
            Entry = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua'
            CeilingLines = 4335
            RequiredModules = @('_wt_anim_remap.lua', '_wt_availability.lua', '_wt_regression.lua')
        }
        @{
            Name = 'career_tweaker_balance'
            State = 'partial'
            Entry = 'career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'
            CeilingLines = 3889
            RequiredModules = @('_career_tweaker_balance_hooks.lua', '_crt_foot_knight.lua')
        }
        @{
            Name = 'crafting_in_modded_dev'
            State = 'partial'
            Entry = 'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'
            CeilingLines = 5723
            RequiredModules = @('_cim_forge_preview.lua', '_cim_inventory_filter.lua', '_cim_regression_checks.lua')
        }
        @{
            Name = 'chaos_wastes_tweaker_dev'
            State = 'partial'
            Entry = 'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'
            CeilingLines = 11333
            RequiredModules = @('_ct_combat_hooks.lua', '_ct_boon_registry.lua', '_ct_regression.lua')
        }
        @{
            Name = 'character_weapon_variants'
            State = 'partial'
            Entry = 'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            CeilingLines = 10844
            RequiredModules = @('_cwv_variant_catalog.lua', '_cwv_husk_path.lua', '_cwv_regression_identity.lua')
        }
    )
}
