return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Selector = assert(loadfile(root .. "_cim_template_selector.lua"))()

    local function selector(key)
        return {
            backend_id = "cim_template_" .. key,
            key = key,
            rarity = "default",
            cim_acquisition_template = true,
            cim_acquisition_key = key,
        }
    end

    H.test("CWV canonical identity survives inherited base keys", function()
        H.equal(Selector.canonical_key({
            backend_id = "cwv_es_longsword_001",
            key = "es_bastard_sword",
        }), "cwv_es_longsword")
        H.equal(Selector.canonical_key({
            backend_id = "opaque-guid",
            data = { key = "es_bastard_sword", cwv_key = "cwv_es_longsword" },
        }), "cwv_es_longsword")
    end)

    H.test("one real CWV blacksmith row suppresses all synthetic twins", function()
        local legacy = {
            backend_id = "cwv_es_longsword_001",
            rarity = "default",
            key = "es_bastard_sword",
        }
        local synth = selector("cwv_es_longsword")
        local rows = { legacy, synth, synth }
        Selector.inject(rows, { synth })
        H.equal(#rows, 1)
        H.equal(rows[1], legacy)
    end)

    H.test("real native row suppresses preview alias family", function()
        local real = {
            backend_id = "real_es_bastard_sword",
            rarity = "default",
            key = "es_bastard_sword",
            data = { slot_type = "melee", item_type = "es_bastard_sword" },
        }
        local preview = selector("es_bastard_sword_preview")
        preview.data = { slot_type = "melee", item_type = "es_bastard_sword", is_local = true }
        preview.cim_acquisition_family = "item_type:melee:es_bastard_sword"
        local rows = { real, preview, preview }
        Selector.inject(rows, { preview })
        H.equal(#rows, 1)
        H.equal(rows[1], real)
    end)

    H.test("shared item type does not collapse distinct CWV variants", function()
        local normal = selector("cwv_es_axe_shield")
        normal.data = {
            cwv_definition = true, cwv_key = "cwv_es_axe_shield",
            slot_type = "melee", item_type = "cwv_es_axe_shield",
        }
        normal.cim_acquisition_family = "cwv:cwv_es_axe_shield"
        local veteran = selector("cwv_es_axe_shield_veteran")
        veteran.data = {
            cwv_definition = true, cwv_key = "cwv_es_axe_shield_veteran",
            slot_type = "melee", item_type = "cwv_es_axe_shield",
        }
        veteran.cim_acquisition_family = "cwv:cwv_es_axe_shield_veteran"
        local rows = {}
        Selector.inject(rows, { normal = normal, veteran = veteran })
        H.equal(#rows, 2)
    end)

    H.test("repeated crafts and repeated injection keep exactly one selector", function()
        local synth = selector("cwv_es_longsword")
        local rows = {
            { backend_id = "cwv_es_longsword_100", rarity = "modded", data = { cwv_key = "cwv_es_longsword" } },
            { backend_id = "cwv_es_longsword_101", rarity = "modded", data = { cwv_key = "cwv_es_longsword" } },
        }
        Selector.inject(rows, { synth })
        Selector.inject(rows, { synth })
        H.equal(#rows, 3)
        H.equal(rows[1].backend_id, "cwv_es_longsword_100")
        H.equal(rows[2].backend_id, "cwv_es_longsword_101")
        H.equal(rows[3], synth)
    end)

    H.test("selector append order is deterministic and key bounded", function()
        local alpha = selector("cwv_alpha")
        local zulu = selector("cwv_zulu")
        local rows = {}
        Selector.inject(rows, { z = zulu, a = alpha, duplicate = alpha })
        H.equal(#rows, 2)
        H.equal(rows[1], alpha)
        H.equal(rows[2], zulu)
    end)

    H.test("production wires the pure policy and explicit selector identity", function()
        local file = assert(io.open(root .. "standard_forge.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local catalog_file = assert(io.open(root .. "_cim_template_catalog.lua", "rb"))
        local catalog_source = catalog_file:read("*a")
        catalog_file:close()
        H.truthy(source:find("_cim_template_selector", 1, true))
        H.truthy(source:find("_cim_template_catalog", 1, true))
        H.truthy(catalog_source:find("cim_acquisition_template = true", 1, true))
        H.truthy(source:find("return template_selector.inject(items, _template_cache)", 1, true))
    end)
end
