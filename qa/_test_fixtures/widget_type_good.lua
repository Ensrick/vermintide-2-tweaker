-- Fixture: widget definitions using only valid VMF types.
-- Expected verdict from qa/check_vmf_widget_types.ps1: PASS.
-- This file is excluded from the normal scan (lives under _test_fixtures/).
--
-- Canonical VMF widget types: group / header / checkbox / dropdown /
-- numeric / keybind. Anything outside this set breaks options init.

return {
    name        = "Good Widget Fixture",
    description = "Fixture for qa/check_vmf_widget_types.ps1 (-SelfTest).",
    is_togglable = false,
    options = {
        widgets = {
            {
                setting_id    = "bar",
                type          = "checkbox",
                default_value = false,
            },
        },
    },
}
