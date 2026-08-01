local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function count_plain(text, needle)
    local count = 0
    local cursor = 1
    while true do
        local at = text:find(needle, cursor, true)
        if not at then return count end
        count = count + 1
        cursor = at + #needle
    end
end

return function(H, repo_root)
    local canonical_path = repo_root .. "/tools/shared_lib/_lib_ui_presentation_refresh.lua"
    local Lib = assert(loadfile(canonical_path))()

    H.test("ui presentation clients share one bounded generation ledger", function()
        local root = {}
        local producer = assert(Lib.attach(root, "producer", 8))
        local consumer = assert(Lib.attach(root, "consumer", 128))
        H.equal(producer:publish({ kind = "loadout", career_name = "es_mercenary",
            slot_name = "slot_hat", item_key = "hat_a" }), 1)
        H.truthy(consumer:has_pending())
        local rows = {}
        local report = consumer:drain(function(row)
            rows[#rows + 1] = row
            return true
        end, 8)
        H.equal(report.handled, 1)
        H.equal(report.pending, 0)
        H.equal(rows[1].source, "producer")
        H.equal(rows[1].item_key, "hat_a")
        H.equal(producer:stats().capacity, 8, "first attachment owns bounded capacity")
    end)

    H.test("ui presentation ledger drops old rows and reports missed generations", function()
        local root = {}
        local producer = assert(Lib.attach(root, "producer", 8))
        local consumer = assert(Lib.attach(root, "consumer", 8))
        for i = 1, 12 do
            producer:publish({ kind = "item-presentation", backend_id = "bid_" .. i })
        end
        local report = consumer:drain(function() return true end, 32)
        H.equal(report.dropped, 4)
        H.equal(report.seen, 8)
        H.equal(report.handled, 8)
        H.equal(report.pending, 0)
    end)

    H.test("ui presentation handler failures fail open and advance cursor", function()
        local root = {}
        local producer = assert(Lib.attach(root, "producer"))
        local consumer = assert(Lib.attach(root, "consumer"))
        producer:publish({ kind = "loadout" })
        local report = consumer:drain(function() error("planted") end)
        H.equal(report.failed, 1)
        H.equal(report.pending, 0)
        H.equal(consumer:has_pending(), false)
    end)

    H.test("ui presentation ledger rejects foreign schema and unbounded payload", function()
        local root = {}
        root[Lib.GLOBAL_KEY] = { schema = 99 }
        local client, reason = Lib.attach(root, "consumer")
        H.equal(client, nil)
        H.equal(reason, "schema-conflict")

        root = {}
        client = assert(Lib.attach(root, "producer"))
        local generation = assert(client:publish({ kind = "loadout",
            item_key = string.rep("x", 500), foreign = { unsafe = true } }))
        local observer = assert(Lib.attach(root, "observer"))
        observer.cursor = 0
        local row
        observer:drain(function(value) row = value end)
        H.equal(generation, 1)
        H.equal(#row.item_key, 160)
        H.equal(row.foreign, nil)
    end)

    H.test("ui presentation retained item card refresh is atomic and vanilla-shaped", function()
        local content = { icon_texture = "old", untouched = "keep" }
        local item = { rarity = "exotic", data = { slot_type = "slot_type_melee" } }
        local ok, old_icon, new_icon = Lib.refresh_item_card(content, item,
            "custom_icon", "custom_name", function(key) return "L:" .. key end,
            { exotic = "rarity_exotic" })
        H.equal(ok, true)
        H.equal(old_icon, "old")
        H.equal(new_icon, "custom_icon")
        H.equal(content.input_text, "L:custom_name")
        H.equal(content.sub_title, "L:slot_type_melee")
        H.equal(content.icon_bg, "rarity_exotic")
        H.equal(content.item, item)
        H.equal(content.untouched, "keep")

        local before = { icon_texture = "still-old", input_text = "still-name" }
        local failed, reason = Lib.refresh_item_card(before, item, nil, "bad",
            function() error("planted") end, {})
        H.equal(failed, false)
        H.equal(reason, "localize-failed")
        H.equal(before.icon_texture, "still-old", "failed resolve must not partially mutate")
        H.equal(before.input_text, "still-name", "failed resolve must preserve retained card")

        local malformed = { icon_texture = "safe", input_text = "safe-name" }
        local malformed_ok, malformed_reason = Lib.refresh_item_card(malformed,
            { data = { slot_type = "slot_type_melee" } }, nil, nil,
            function(key) return key end, {})
        H.equal(malformed_ok, false)
        H.equal(malformed_reason, "invalid-presentation-data")
        H.equal(malformed.icon_texture, "safe")
        H.equal(malformed.input_text, "safe-name")
    end)

    H.test("ui presentation consumer policy is scoped and Pusfume fails open", function()
        local allowed = { slot_hat = true, slot_skin = true }
        local slot, item = Lib.classify_loadout_event({
            kind = "loadout", career_name = "es_mercenary",
            slot_name = "slot_hat", item_key = "hat_a",
        }, "es_mercenary", allowed)
        H.equal(slot, "slot_hat")
        H.equal(item, "hat_a")
        H.equal(Lib.classify_loadout_event({
            kind = "loadout", career_name = "pusfume",
            slot_name = "slot_hat", item_key = "pusfume_hat",
        }, "es_mercenary", allowed), nil)
        H.equal(Lib.classify_loadout_event({
            kind = "loadout", career_name = "es_mercenary",
            slot_name = "slot_hat",
        }, "es_mercenary", allowed), nil)
        H.equal(Lib.classify_loadout_event({
            kind = "item-presentation", career_name = "es_mercenary",
            slot_name = "slot_hat", item_key = "hat_a",
        }, "es_mercenary", allowed), nil)
    end)

    H.test("ui presentation fallback publisher dedupes synchronous generations", function()
        H.equal(Lib.generation_unchanged(4, 4), true)
        H.equal(Lib.generation_unchanged(4, 5), false)
        H.equal(Lib.generation_unchanged(nil, 0), false)
    end)

    H.test("issue 925 consumers use exact synchronized library and adapters", function()
        local canonical = read(canonical_path)
        local consumers = {
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_ui_presentation_refresh.lua",
            "dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/_lib_ui_presentation_refresh.lua",
            "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_lib_ui_presentation_refresh.lua",
        }
        for _, relative in ipairs(consumers) do
            H.equal(read(repo_root .. "/" .. relative), canonical,
                "shared UI presentation library drift: " .. relative)
        end

        local cos = read(repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local dcp = read(repo_root .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua")
        local gut = read(repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        H.truthy(cos:find("_cos_ui_presentation_refresh", 1, true))
        H.truthy(cos:find("_cos925_publish_loadout", 1, true))
        H.equal(count_plain(cos,
            'mod:hook(BackendUtils, "set_loadout_item"'), 1,
            "Cosmetics must compose its singleton loadout hook")
        local illusion_owner = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua")
        H.equal(count_plain(illusion_owner,
            'mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete"'), 1,
            "Cosmetics must compose its singleton craft-complete hook")
        local cos_owner = read(repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_ui_presentation_refresh.lua")
        H.truthy(cos_owner:find("_cos925_publish_and_refresh", 1, true))
        H.truthy(cos_owner:find("refresh_item_card(content", 1, true))
        H.truthy(dcp:find("_drain_presentation_refresh", 1, true))
        H.truthy(dcp:find("_presentation_hints", 1, true))
        H.equal(count_plain(dcp,
            'mod:hook_safe("UnitFrameUI", "draw"'), 1,
            "DCP must compose its singleton frame hook")
        H.truthy(gut:find("_gut925_publish_if_unobserved", 1, true))
        H.equal(gut:find("Open the hero view to refresh the visual model", 1, true), nil)
    end)
end
