local function en(s) return { en = s } end

return {
    mod_description = en("Replaces the default lighting on the three Verminious Dreams DLC missions whose vanilla lighting is too dark / muddy: The Forsaken Temple, Devious Delvings, The Well of Dreams. Each mission has its own toggle below; ON applies the tuned profile, OFF leaves vanilla untouched. Live console commands (prefix: vdl_) let you adjust further to taste — run `vdl_help` in chat for the full command list."),

    enable_dlc_termite_1         = en("The Forsaken Temple"),
    enable_dlc_termite_1_tooltip = en("ON (default): apply tuned lighting to The Forsaken Temple (dlc_termite_1). OFF: leave vanilla lighting on this mission untouched. Atmosphere reverts immediately on toggle; per-light overrides only fully clear on next level load."),

    enable_dlc_termite_2         = en("Devious Delvings"),
    enable_dlc_termite_2_tooltip = en("ON (default): apply tuned lighting to Devious Delvings (dlc_termite_2). OFF: leave vanilla lighting on this mission untouched. Atmosphere reverts immediately on toggle; per-light overrides only fully clear on next level load."),

    enable_dlc_termite_3         = en("The Well of Dreams"),
    enable_dlc_termite_3_tooltip = en("ON (default): apply tuned lighting to The Well of Dreams (dlc_termite_3). OFF: leave vanilla lighting on this mission untouched. Atmosphere reverts immediately on toggle; per-light overrides only fully clear on next level load."),

    -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
    enable_debug_logging         = en("Debug Logging"),
    enable_debug_logging_tooltip = en("Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable."),
}
