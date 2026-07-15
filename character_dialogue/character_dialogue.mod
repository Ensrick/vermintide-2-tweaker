return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Character Dialogue` must be below Vermintide Mod Framework in the launcher load order.")
        new_mod("character_dialogue", {
            mod_script = "scripts/mods/character_dialogue/character_dialogue",
            mod_data = "scripts/mods/character_dialogue/character_dialogue_data",
            mod_localization = "scripts/mods/character_dialogue/character_dialogue_localization",
        })
    end,
    packages = { "resource_packages/character_dialogue/character_dialogue" },
}
