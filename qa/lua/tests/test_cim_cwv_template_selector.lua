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
            data = { slot_type = "melee", item_type = "es_bastard_sword" },
        }
        local synth = selector("cwv_es_longsword")
        local rows = { legacy, synth, synth }
        Selector.inject(rows, { synth })
        H.equal(#rows, 1)
        H.equal(rows[1], legacy)
    end)

    H.test("duplicate real CWV rows collapse to one five-power selector", function()
        local older = {
            backend_id = "cwv_es_longsword_001",
            rarity = "default",
            power_level = 300,
            key = "es_bastard_sword",
            data = { slot_type = "melee", item_type = "es_bastard_sword" },
        }
        local canonical = {
            backend_id = "cwv_es_longsword_002",
            rarity = "default",
            power_level = 5,
            key = "es_bastard_sword",
            data = { slot_type = "melee", item_type = "es_bastard_sword" },
        }
        local rows = { older, canonical, selector("cwv_es_longsword") }
        Selector.inject(rows, {})
        H.equal(#rows, 1)
        H.equal(rows[1], canonical)
    end)

    H.test("distinct accessory icon selectors are not merged", function()
        local first = selector("necklace")
        first.data = { slot_type = "necklace", item_type = "necklace" }
        first.cim_acquisition_family = "accessory:necklace:necklace"
        local second = selector("necklace_02")
        second.data = { slot_type = "necklace", item_type = "necklace" }
        second.cim_acquisition_family = "accessory:necklace:necklace_02"
        local rows = {}
        Selector.inject(rows, { first = first, second = second })
        H.equal(#rows, 2)
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

    H.test("crafted instances fail closed out of the acquisition picker", function()
        local synth = selector("cwv_es_longsword")
        synth.data = {
            cwv_definition = true, cwv_key = "cwv_es_longsword",
            slot_type = "melee", item_type = "cwv_es_longsword",
        }
        local rows = {
            { backend_id = "cwv_es_longsword_100", rarity = "modded",
                data = { slot_type = "melee", cwv_key = "cwv_es_longsword" } },
            { backend_id = "cwv_es_longsword_101", CustomData = { rarity = "modded" },
                data = { slot_type = "melee", cwv_key = "cwv_es_longsword" } },
        }
        Selector.inject(rows, { synth })
        Selector.inject(rows, { synth })
        H.equal(#rows, 1)
        H.equal(rows[1], synth)
    end)

    H.test("crafted accessories do not consume authored icon selectors", function()
        local first = selector("necklace")
        first.data = { slot_type = "necklace", item_type = "necklace" }
        first.cim_acquisition_family = "accessory:necklace:necklace"
        local second = selector("necklace_02")
        second.data = { slot_type = "necklace", item_type = "necklace" }
        second.cim_acquisition_family = "accessory:necklace:necklace_02"
        local rows = {
            { backend_id = "crafted-necklace", rarity = "modded",
                data = { slot_type = "necklace", item_type = "necklace" } },
        }
        Selector.inject(rows, { first = first, second = second })
        H.equal(#rows, 2)
        H.equal(rows[1], first)
        H.equal(rows[2], second)
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

    H.test("slot-split craft queries append only matching synthetic selectors", function()
        local melee = selector("cwv_melee")
        melee.data = { slot_type = "melee", item_type = "cwv_melee" }
        local ranged = selector("cwv_ranged")
        ranged.data = { slot_type = "ranged", item_type = "cwv_ranged" }

        local melee_rows = {}
        Selector.inject(melee_rows, { melee = melee, ranged = ranged }, {
            allowed_slots = { melee = true },
        })
        H.equal(#melee_rows, 1)
        H.equal(melee_rows[1], melee)

        local ranged_rows = {}
        Selector.inject(ranged_rows, { melee = melee, ranged = ranged }, {
            allowed_slots = { ranged = true },
        })
        H.equal(#ranged_rows, 1)
        H.equal(ranged_rows[1], ranged)
    end)

    H.test("canonical_key delegates to the injected contract resolver", function()
        local seen = {}
        Selector.set_canonical_key_resolver(function(item)
            seen[#seen + 1] = item
            return "resolved:" .. tostring(item and item.key)
        end)
        H.equal(Selector.canonical_key({ key = "anything" }), "resolved:anything")
        H.equal(#seen, 1)
        -- Clearing restores the standalone inline policy for any later test.
        Selector.set_canonical_key_resolver(nil)
        H.equal(Selector.canonical_key({
            backend_id = "cwv_es_longsword_001", key = "es_bastard_sword",
        }), "cwv_es_longsword")
    end)

    H.test("identity contract owns key and picker row role", function()
        local calls = { key = 0, role = 0 }
        Selector.set_identity_contract({
            canonical_item_key = function(item)
                calls.key = calls.key + 1
                return item.exact
            end,
            craft_picker_role = function(item)
                calls.role = calls.role + 1
                return item.role
            end,
        })
        local real = {
            exact = "cwv_exact", role = "selector", rarity = "default",
            data = { slot_type = "melee", cwv_key = "cwv_exact" },
        }
        local crafted = {
            exact = "cwv_exact", role = "instance", rarity = "default",
            data = { slot_type = "melee", cwv_key = "cwv_exact" },
        }
        local rows = { crafted, real }
        Selector.inject(rows, {})
        H.equal(#rows, 1)
        H.equal(rows[1], real)
        H.truthy(calls.key > 0)
        H.truthy(calls.role > 0)
        Selector.set_identity_contract(nil)
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
        -- The pure policy call must stay wired with the template-cache identity and
        -- its result must be what production renders. v0.8.84-dev (issue 524) wraps
        -- the former one-liner: the inject result is captured as `result`, handed to
        -- the render-seam probe (observation-only, pcall'd), then returned unchanged,
        -- so the rendered-list identity is still exactly the selector's output.
        H.truthy(source:find("_single_slot_filter(filter)", 1, true))
        H.truthy(source:find("local result = template_selector.inject(items, _template_cache, {", 1, true))
        H.truthy(source:find("return result", 1, true))
		H.truthy(source:find("mod._cim592_cwv_bounded_seed = true", 1, true))
		H.equal(source:find("mod._cim592_cwv_registration_only", 1, true), nil)

		local stable_path = repo_root
			.. "/crafting_in_modded/scripts/mods/crafting_in_modded/standard_forge.lua"
		local stable_file = assert(io.open(stable_path, "rb"))
		local stable_source = stable_file:read("*a")
		stable_file:close()
		-- Stable remains promotion-only; this dev contract moves with the next
		-- explicitly authorized CIM promotion rather than leaking into stable.
		H.truthy(stable_source:find("mod._cim592_cwv_registration_only = true", 1, true))
		H.equal(stable_source:find("mod._cim592_cwv_bounded_seed", 1, true), nil)
    end)
end
