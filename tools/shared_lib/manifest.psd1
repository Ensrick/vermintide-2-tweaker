@{
    Libraries = @(
        @{
            Source = "_lib_appearance_descriptor.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_appearance_descriptor.lua"
            )
        }
        @{
            Source = "_lib_peer_parity.lua"
            Consumers = @(
                "career_tweaker/scripts/mods/career_tweaker/_lib_peer_parity.lua"
                "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_lib_peer_parity.lua"
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_peer_parity.lua"
                "event_tweaker/scripts/mods/event_tweaker/_lib_peer_parity.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_peer_parity.lua"
                "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_peer_parity.lua"
            )
        }
        @{
            Source = "_lib_wire_catalog.lua"
            Consumers = @(
                "career_tweaker/scripts/mods/career_tweaker/_lib_wire_catalog.lua"
            )
        }
        @{
            Source = "_lib_debug.lua"
            Consumers = @(
                "crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_lib_debug.lua"
                "general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_debug.lua"
                "verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/_lib_debug.lua"
            )
        }
        @{
            Source = "_lib_weapon_appearance.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_weapon_appearance.lua"
                "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_weapon_appearance.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_weapon_appearance.lua"
                "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_weapon_appearance.lua"
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_weapon_appearance.lua"
            )
        }
        @{
            Source = "_lib_resource_residency.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_resource_residency.lua"
                "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_resource_residency.lua"
                "crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_lib_resource_residency.lua"
                "general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_resource_residency.lua"
                "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_lib_resource_residency.lua"
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_resource_residency.lua"
            )
        }
        @{
            Source = "_lib_appearance_fade.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_appearance_fade.lua"
                "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_appearance_fade.lua"
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_appearance_fade.lua"
            )
        }
        @{
            Source = "_lib_career_weapon_actions.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_career_weapon_actions.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_career_weapon_actions.lua"
                "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_career_weapon_actions.lua"
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_career_weapon_actions.lua"
            )
        }
        @{
            Source = "_lib_effective_weapon_templates.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_effective_weapon_templates.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_effective_weapon_templates.lua"
                "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_effective_weapon_templates.lua"
            )
        }
        @{
            Source = "_lib_network_lookup.lua"
            Consumers = @(
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_network_lookup.lua"
            )
        }
        @{
            Source = "_lib_ui_presentation_refresh.lua"
            Consumers = @(
                "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_ui_presentation_refresh.lua"
                "dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/_lib_ui_presentation_refresh.lua"
                "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_lib_ui_presentation_refresh.lua"
            )
        }
    )
}
