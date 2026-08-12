return function(H, repo_root)
    local text = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_text.lua")

    H.test("CWV item descriptions remove one repeated title and retain prose", function()
        H.equal(text.description("Greataxe", "Greataxe: A heavy two-handed axe."),
            "A heavy two-handed axe.")
        H.equal(text.description("Greataxe", "A heavy two-handed axe."),
            "A heavy two-handed axe.")
        H.equal(text.description("Greataxe", "Greataxe"),
            "A custom Career Weapon Variant.")
    end)

    H.test("CWV canonical localization applies item-text normalization", function()
        local path = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_item_text.description(def.display_name, def.description)", 1, true))
    end)

    H.test("CWV bomb-slot option is titled exactly Javelin", function()
        local path = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_localization.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('enable_cwv_tuskgor_javelin_bomb = { en = "Javelin" }', 1, true))
        H.equal(source:find("one-shot, full javelin moveset", 1, true), nil)
    end)
end
