local function en(s) return { en = s } end

return {
    mod_description = en("Improves the lighting on the three Verminious Dreams missions whose default lighting looks too dark or muddy: The Forsaken Temple, Devious Delvings, and The Well of Dreams. Each mission has its own toggle below, and you can fine-tune the look yourself with the vdl_ chat commands (type vdl_help in the chat console for the full list)."),

    enable_dlc_termite_1         = en("The Forsaken Temple"),
    enable_dlc_termite_1_tooltip = en("Turn on to apply the improved lighting to The Forsaken Temple, or off to keep the mission's original look. Overall atmosphere changes revert the moment you toggle this, but individual light tweaks only clear fully the next time the mission loads."),

    enable_dlc_termite_2         = en("Devious Delvings"),
    enable_dlc_termite_2_tooltip = en("Turn on to apply the improved lighting to Devious Delvings, or off to keep the mission's original look. Overall atmosphere changes revert the moment you toggle this, but individual light tweaks only clear fully the next time the mission loads."),

    enable_dlc_termite_3         = en("The Well of Dreams"),
    enable_dlc_termite_3_tooltip = en("Turn on to apply the improved lighting to The Well of Dreams, or off to keep the mission's original look. Overall atmosphere changes revert the moment you toggle this, but individual light tweaks only clear fully the next time the mission loads."),

    enable_cw_curse_adjust         = en("Chaos Wastes curse adjustment"),
    enable_cw_curse_adjust_tooltip = en("When one of these three missions appears in a Chaos Wastes expedition with an active curse, turn this on to blend the curse's deity color over the improved lighting instead of replacing it. Turn it off to keep the plain improved lighting in Chaos Wastes; it has no effect outside Chaos Wastes, and each curse's tint can be fine-tuned with the vdl_curse chat commands."),

}
