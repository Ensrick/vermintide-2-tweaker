-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "750fa8f8a393d807f2f7205dfed4b60b6abe3c46",
    old_revision = "b5a93414e883825f69c61eb3e90e73f52d6c2e80",
    records = {
        [1] = {
            ops = {
                [1] = {
                    expected_current = true,
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "default",
                        [4] = "ignore_shield_hit",
                    },
                    unset = true,
                },
                [2] = {
                    expected_current_unset = true,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "zoomed_shot",
                        [4] = "ignore_armour_hit",
                    },
                    unset = false,
                    value = true,
                },
                [3] = {
                    expected_current = true,
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "zoomed_shot",
                        [4] = "ignore_shield_hit",
                    },
                    unset = true,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/handguns.lua",
            template = "handgun_template_1",
            unsupported = {},
        },
    },
}
