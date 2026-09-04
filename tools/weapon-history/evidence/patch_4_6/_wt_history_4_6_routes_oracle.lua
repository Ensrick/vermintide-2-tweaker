-- Regenerated from immutable decompiled-source Git objects; do not hand-edit.
return {
    current_revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    oracle_id = "wt_patch_4_6_hagbane_source_oracle_v1",
    routes = {
        hagbane_shortbow = {
            ["4_5_1"] = {
                [1] = {
                    native_name = "shortbow_hagbane_charged",
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "shoot_charged",
                        [4] = "impact_data",
                        [5] = "damage_profile",
                    },
                    template = "shortbow_hagbane_template_1",
                },
                [2] = {
                    native_name = "shortbow_hagbane",
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "default",
                        [4] = "impact_data",
                        [5] = "damage_profile",
                    },
                    template = "shortbow_hagbane_template_1",
                },
            },
        },
    },
    schema = 1,
    source_blobs = {
        ["0cec9547152a395c4f35f75288f29d8b18b8294f"] = {
            ["scripts/settings/equipment/damage_profile_templates.lua"] = "6653fb47c9ee40611bc0525fd62bc7f927c17fdf",
            ["scripts/settings/equipment/power_level_templates.lua"] = "13eeccec333d072261afd1705d4e18c8a411095e",
            ["scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua"] = "2450220312570da7d14a3741edcf6c4d3ae0ec70",
        },
        ["25fd7b8433e839b678d1c98a7a9af80918cbc252"] = {
            ["scripts/settings/equipment/damage_profile_templates.lua"] = "e8330328d0085f6aee09e0495ba88fdc0211d5aa",
            ["scripts/settings/equipment/power_level_templates.lua"] = "6eba753d985ea80057947ed1ae1a25214204783e",
            ["scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua"] = "9803627f8e1a4573b6dbea8b11f8836e7460214f",
        },
    },
}
