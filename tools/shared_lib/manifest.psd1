@{
    Libraries = @(
        @{
            Source = "_lib_peer_parity.lua"
            Consumers = @(
                "career_tweaker/scripts/mods/career_tweaker/_lib_peer_parity.lua"
                "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_lib_peer_parity.lua"
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_peer_parity.lua"
                "event_tweaker/scripts/mods/event_tweaker/_lib_peer_parity.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_peer_parity.lua"
            )
        }
        @{
            Source = "_lib_debug.lua"
            Consumers = @(
                "general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_debug.lua"
            )
        }
        @{
            Source = "_lib_weapon_appearance.lua"
            Consumers = @(
                "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_weapon_appearance.lua"
                "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_weapon_appearance.lua"
                "weapon_tweaker/scripts/mods/weapon_tweaker/_lib_weapon_appearance.lua"
                "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_weapon_appearance.lua"
            )
        }
    )
}
