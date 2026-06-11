return {
    mod_description = {
        en = "Quality-of-life tweaks for the Vermintide 2 hero/character GUI (save loadouts, etc.).",
    },

    -- ESC-menu button label. Injected by the IngameViewLayoutLogic.setup_button_layout
    -- hook in gui_tweaker.lua; the button widget style has localize=true
    -- (vanilla ingame_view.lua:138-140 + :252), so display_name MUST be a real
    -- loc key. (display_name_func is a dead vanilla field — never invoked in the
    -- decompiled ingame_view render path — so the literal there did not render.)
    mod_tweaker_button_name = {
        en = "Mod Tweaker",
    },

    -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
    enable_debug_logging = {
        en = "Debug Logging",
    },
    enable_debug_logging_tooltip = {
        en = "Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable.",
    },
}
