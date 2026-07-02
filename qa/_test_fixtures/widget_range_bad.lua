-- Fixture: a numeric widget with a malformed 3-element range.
-- Expected verdict from qa/check_vmf_widget_types.ps1: ERROR (range[3]).
-- This file is excluded from the normal scan (lives under _test_fixtures/).
--
-- VMF requires a numeric `range` to be EXACTLY { min, max } (2 elements). A
-- 3rd "step" element is fatal to options init, not ignored. Real-world burn:
-- ct_dev v0.7.188-dev `starting_coins` range { 0, 3000, 25 } (#164) killed the
-- entire mod until v0.7.189-dev reverted it.

return {
    name        = "Bad Range Fixture",
    description = "Fixture for qa/check_vmf_widget_types.ps1 (-SelfTest).",
    is_togglable = false,
    options = {
        widgets = {
            -- INVALID: 3-element range.
            { setting_id = "stepped", type = "numeric", default_value = 0, range = { 0, 3000, 25 }, decimals_number = 0 },
        },
    },
}
