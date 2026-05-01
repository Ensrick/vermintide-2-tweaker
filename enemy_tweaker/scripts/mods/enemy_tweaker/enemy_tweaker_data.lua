local mod = get_mod("enemy_tweaker")

local breed_options = {
    { text = "off",                                    value = "off" },
    { text = "skaven_slave",                           value = "skaven_slave" },
    { text = "skaven_clan_rat",                        value = "skaven_clan_rat" },
    { text = "skaven_clan_rat_with_shield",            value = "skaven_clan_rat_with_shield" },
    { text = "skaven_storm_vermin",                    value = "skaven_storm_vermin" },
    { text = "skaven_storm_vermin_with_shield",        value = "skaven_storm_vermin_with_shield" },
    { text = "skaven_storm_vermin_commander",           value = "skaven_storm_vermin_commander" },
    { text = "skaven_plague_monk",                     value = "skaven_plague_monk" },
    { text = "skaven_gutter_runner",                   value = "skaven_gutter_runner" },
    { text = "skaven_pack_master",                     value = "skaven_pack_master" },
    { text = "skaven_poison_wind_globadier",           value = "skaven_poison_wind_globadier" },
    { text = "skaven_ratling_gunner",                  value = "skaven_ratling_gunner" },
    { text = "skaven_warpfire_thrower",                value = "skaven_warpfire_thrower" },
    { text = "skaven_rat_ogre",                        value = "skaven_rat_ogre" },
    { text = "skaven_stormfiend",                      value = "skaven_stormfiend" },
    { text = "chaos_fanatic",                          value = "chaos_fanatic" },
    { text = "chaos_marauder",                         value = "chaos_marauder" },
    { text = "chaos_marauder_with_shield",             value = "chaos_marauder_with_shield" },
    { text = "chaos_berzerker",                        value = "chaos_berzerker" },
    { text = "chaos_raider",                           value = "chaos_raider" },
    { text = "chaos_warrior",                          value = "chaos_warrior" },
    { text = "chaos_bulwark",                          value = "chaos_bulwark" },
    { text = "chaos_spawn",                            value = "chaos_spawn" },
    { text = "chaos_troll",                            value = "chaos_troll" },
    { text = "beastmen_ungor",                         value = "beastmen_ungor" },
    { text = "beastmen_ungor_archer",                  value = "beastmen_ungor_archer" },
    { text = "beastmen_gor",                           value = "beastmen_gor" },
    { text = "beastmen_bestigor",                      value = "beastmen_bestigor" },
    { text = "beastmen_minotaur",                      value = "beastmen_minotaur" },
    { text = "beastmen_standard_bearer",               value = "beastmen_standard_bearer" },
}

return {
    name = "Tweaker: Enemies",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "horde_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id    = "horde_preset",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("horde_preset_tooltip"),
                        options = {
                            { text = "Off",              value = "off" },
                            { text = "All Elites",       value = "all_elites" },
                            { text = "Beastmen Invasion", value = "beastmen_invasion" },
                            { text = "Chaos Only",       value = "chaos_only" },
                            { text = "Skaven Only",      value = "skaven_only" },
                            { text = "Mixed Factions",   value = "mixed_factions" },
                            { text = "Necromancer Skeletons", value = "necro_skeletons" },
                            { text = "Ghost Skeletons",  value = "ghost_skeletons" },
                            { text = "All Skeletons Mixed", value = "skeleton_mix" },
                        },
                    },
                    {
                        setting_id    = "horde_size_multiplier",
                        type          = "numeric",
                        default_value = 100,
                        range         = { 25, 300 },
                        tooltip       = mod:localize("horde_size_multiplier_tooltip"),
                    },
                },
            },
            {
                setting_id = "breed_swap_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id    = "breed_swap_from",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("breed_swap_from_tooltip"),
                        options       = breed_options,
                    },
                    {
                        setting_id    = "breed_swap_to",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("breed_swap_to_tooltip"),
                        options       = breed_options,
                    },
                },
            },
        },
    },
}
