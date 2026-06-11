-- Fixture: widget definition with an INVALID VMF type ("text_input").
-- Expected verdict from qa/check_vmf_widget_types.ps1: ERROR.
-- This file is excluded from the normal scan (lives under _test_fixtures/).
--
-- The bug class: VMF's options init does a strict whitelist match on
-- widget.type. "text_input" is not in the whitelist, so widget #N fails
-- validation and the entire mod's options page disappears in-game.
-- See docs/BUG_CLASSES.md "Invalid VMF widget type breaks options init"
-- and VMF_RECIPES.md "VMF widget type whitelist".

return {
    name        = "Bad Widget Fixture",
    description = "Fixture for qa/check_vmf_widget_types.ps1 (-SelfTest).",
    is_togglable = false,
    options = {
        widgets = {
            {
                setting_id    = "foo",
                type          = "text_input",
                default_value = "",
            },
        },
    },
}
