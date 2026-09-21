-- Behavioral coverage for the #1637 career-default spawn weapon policy against
-- the generated vanilla weapon fixture (qa/lua/fixtures/vanilla_weapon_master_list.lua).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local P = assert(loadfile(root .. "_gut_spawn_weapon_policy.lua"))()
    local F = assert(loadfile(repo_root .. "/qa/lua/fixtures/vanilla_weapon_master_list.lua"))()

    -- Fixture rows become master-list-shaped entries (key/name injected as
    -- item_master_list.lua:110-112 does at boot).
    local master = {}
    for key, row in pairs(F.weapons) do
        master[key] = {
            key = key, name = key, slot_type = row.slot_type, rarity = row.rarity,
            can_wield = row.can_wield == F.CAN_WIELD_ALL and {} or row.can_wield,
            right_hand_unit = row.right_hand_unit, left_hand_unit = row.left_hand_unit,
            template = row.template, item_type = row.item_type,
        }
    end
    local settings = {}
    for career, rows in pairs(F.careers) do
        settings[career] = { item_slot_types_by_slot_name = {
            slot_melee = rows.slot_melee, slot_ranged = rows.slot_ranged,
        } }
    end

    local function contains(list, value)
        for i = 1, #list do if list[i] == value then return true end end
        return false
    end

    H.test("GUT #1637 fixture carries every hero career and the demo seeds", function()
        H.equal(#F.hero_careers, 20)
        for _, career in ipairs(F.hero_careers) do
            H.truthy(F.careers[career], "career slot rows missing for " .. career)
        end
        local seeded = 0
        for career, seeds in pairs(P.SEED_WEAPONS) do
            seeded = seeded + 1
            H.truthy(F.demo_seeds[career], "seed career not in demo gear: " .. career)
            H.equal(seeds.slot_melee, (F.demo_seeds[career].slot_melee:gsub("_%d%d%d%d$", "")))
            H.equal(seeds.slot_ranged, (F.demo_seeds[career].slot_ranged:gsub("_%d%d%d%d$", "")))
        end
        H.equal(seeded, 15)
    end)

    H.test("GUT #1637 accepted slot types follow CareerSettings with a shaped fallback", function()
        H.deep_equal((P.accepted_slot_types(settings, "dr_slayer", "slot_ranged")), { "melee", "ranged" })
        H.deep_equal((P.accepted_slot_types(settings, "es_questingknight", "slot_ranged")), { "melee", "ranged" })
        H.deep_equal((P.accepted_slot_types(settings, "wh_priest", "slot_ranged")), { "melee", "ranged" })
        H.deep_equal((P.accepted_slot_types(settings, "bw_unchained", "slot_ranged")), { "ranged" })
        H.deep_equal((P.accepted_slot_types(settings, "bw_unchained", "slot_melee")), { "melee" })
        local types, how = P.accepted_slot_types(nil, "bw_unchained", "slot_ranged")
        H.deep_equal(types, { "ranged", "melee" })
        H.equal(how, "fallback")
        types, how = P.accepted_slot_types({}, "bw_unchained", "slot_hat")
        H.deep_equal(types, {})
        H.equal(how, "not-a-weapon-slot")
    end)

    H.test("GUT #1637 every demo seed validates against the real master list", function()
        for career, seeds in pairs(P.SEED_WEAPONS) do
            for slot, key in pairs(seeds) do
                local accepted = P.accepted_slot_types(settings, career, slot)
                local ok, why = P.is_default_candidate(key, master[key], career, accepted)
                H.truthy(ok, career .. " " .. slot .. " seed " .. key .. ": " .. tostring(why))
                local chosen, how = P.select_default_weapon_key(master, settings, career, slot)
                H.equal(chosen, key)
                H.equal(how, "seed")
            end
        end
    end)

    H.test("GUT #1637 census resolves a valid default for all 20 careers and both slots", function()
        local err, results = P.census(master, settings, F.hero_careers)
        H.equal(err, nil)
        H.equal(#results, 40)
        for _, r in ipairs(results) do
            local entry = master[r.key]
            H.truthy(entry, r.career .. " " .. r.slot .. " -> missing entry " .. r.key)
            H.truthy(contains(entry.can_wield, r.career), r.career .. " cannot wield " .. r.key)
            H.truthy(contains(P.accepted_slot_types(settings, r.career, r.slot), entry.slot_type),
                r.career .. " " .. r.slot .. " -> wrong slot type " .. r.key)
            H.truthy(r.key:sub(1, 3) ~= "vs_" and r.key:sub(-8) ~= "_preview", "excluded key " .. r.key)
            H.truthy(entry.rarity ~= "magic", "weave key " .. r.key)
            H.equal(r.how, P.SEED_WEAPONS[r.career] and "seed" or "scan")
        end
        -- Second-melee careers take a melee weapon in slot_ranged.
        for _, r in ipairs(results) do
            if r.slot == "slot_ranged" and (r.career == "dr_slayer" or r.career == "wh_priest"
                or r.career == "es_questingknight") then
                H.equal(master[r.key].slot_type, "melee", r.career .. " ranged slot default")
            end
        end
    end)

    H.test("GUT #1637 scan is deterministic and prefers plentiful adventure weapons", function()
        local a = select(1, P.select_default_weapon_key(master, settings, "dr_engineer", "slot_melee"))
        local b = select(1, P.select_default_weapon_key(master, settings, "dr_engineer", "slot_melee"))
        H.equal(a, b)
        H.equal(master[a].rarity, "plentiful")
        local list = {
            zz_axe = { slot_type = "melee", rarity = "common", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            aa_axe = { slot_type = "melee", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            ab_axe = { slot_type = "melee", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            vs_aa_axe = { slot_type = "melee", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            aa_axe_preview = { slot_type = "melee", rarity = "plentiful", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            a_magic = { slot_type = "melee", rarity = "magic", template = "t", right_hand_unit = "u", can_wield = { "x" } },
            a_nounits = { slot_type = "melee", rarity = "plentiful", template = "t", can_wield = { "x" } },
            a_notemplate = { slot_type = "melee", rarity = "plentiful", right_hand_unit = "u", can_wield = { "x" } },
            a_bow = { slot_type = "ranged", rarity = "plentiful", template = "t", left_hand_unit = "u", can_wield = { "x" } },
        }
        local key, how = P.select_default_weapon_key(list, nil, "x", "slot_melee")
        H.equal(key, "aa_axe")
        H.equal(how, "scan")
        key = P.select_default_weapon_key(list, nil, "x", "slot_ranged")
        H.equal(key, "a_bow", "fallback slot_ranged prefers a ranged item before melee")
        list.a_bow = nil
        key = P.select_default_weapon_key(list, nil, "x", "slot_ranged")
        H.equal(key, "aa_axe", "slot_ranged falls back to melee when no ranged item exists")
        local none, why = P.select_default_weapon_key(list, nil, "y", "slot_melee")
        H.equal(none, nil)
        H.equal(why, "no-candidate")
        H.equal(select(2, P.select_default_weapon_key(list, nil, "x", "slot_hat")), "invalid")
        H.equal(select(2, P.is_default_candidate("vs_aa_axe", list.vs_aa_axe, "x", { "melee" })), "versus-item")
        H.equal(select(2, P.is_default_candidate("aa_axe_preview", list.aa_axe_preview, "x", { "melee" })), "preview-item")
        H.equal(select(2, P.is_default_candidate("a_magic", list.a_magic, "x", { "melee" })), "weave-item")
        H.equal(select(2, P.is_default_candidate("a_nounits", list.a_nounits, "x", { "melee" })), "no-units")
        H.equal(select(2, P.is_default_candidate("a_notemplate", list.a_notemplate, "x", { "melee" })), "no-template")
        H.equal(select(2, P.is_default_candidate("aa_axe", list.aa_axe, "y", { "melee" })), "cannot-wield")
    end)

    H.test("GUT #1637 synthetic item is master-list data with no backend id", function()
        local entry = master.bw_sword
        local item = P.build_synthetic_item("bw_sword", entry)
        H.equal(item.data, entry)
        H.equal(item.backend_id, nil)
        H.equal(item.key, "bw_sword")
        H.equal(item.ItemId, "bw_sword")
        H.equal(item.rarity, "plentiful")
        H.equal(item.gut_synthetic_default, true)
        H.equal(P.validate_synthetic_item(item, "bw_sword", entry), nil)
        H.truthy(P.validate_synthetic_item({ data = entry, backend_id = "x", key = "bw_sword", ItemId = "bw_sword", rarity = "plentiful", gut_synthetic_default = true }, "bw_sword", entry))
        H.equal(P.build_synthetic_item(nil, entry), nil)
        H.equal(P.build_synthetic_item("bw_sword", nil), nil)
    end)

    H.test("GUT #1637 owned instance lookup is deterministic and key-matched", function()
        local items = {
            ["B2"] = { ItemId = "bw_sword" },
            ["A1"] = { data = { key = "bw_sword" } },
            ["C3"] = { key = "bw_sword" },
            ["D4"] = { ItemId = "bw_dagger" },
            [5] = { ItemId = "bw_sword" },
        }
        H.equal(P.find_owned_instance(items, "bw_sword"), "A1")
        H.equal(P.find_owned_instance(items, "bw_1h_mace"), nil)
        H.equal(P.find_owned_instance(nil, "bw_sword"), nil)
        H.equal(P.find_owned_instance(items, nil), nil)
    end)

    H.test("GUT #1637 sync shadow applies only to synthetic keys lacking a power level", function()
        local keys = { bw_sword = true }
        local raw = master.bw_sword
        H.equal(P.needs_sync_shadow("slot_melee", raw, keys), true)
        H.equal(P.needs_sync_shadow("slot_ranged", master.bw_skullstaff_fireball, keys), false)
        H.equal(P.needs_sync_shadow("slot_hat", raw, keys), false)
        H.equal(P.needs_sync_shadow("slot_melee", { key = "bw_sword", power_level = 200 }, keys), false)
        H.equal(P.needs_sync_shadow("slot_melee", raw, {}), false)
        H.equal(P.needs_sync_shadow("slot_melee", nil, keys), false)
        local shadow = P.shadow_sync_item(raw)
        H.equal(shadow.key, "bw_sword")
        H.equal(shadow.ItemId, "bw_sword")
        H.equal(shadow.data, raw)
        H.equal(shadow.rarity, "plentiful")
        H.equal(shadow.power_level, P.SYNTHETIC_POWER_LEVEL)
        H.equal(type(shadow.power_level), "number")
        H.equal(shadow.properties, nil)
        H.equal(shadow.traits, nil)
        H.equal(raw.power_level, nil, "shadow must not mutate the master-list row")
    end)

    -- Optional provenance: when the decompiled checkout is present, every seed
    -- key must appear in vanilla's demo starting gear table.
    local decompile = "C:/Users/danjo/source/repos/Vermintide-2-Source-Code/scripts/settings/demo_settings.lua"
    local demo_file = io.open(decompile, "rb")
    H.test_if(demo_file ~= nil, "GUT #1637 seeds trace to the decompiled demo_settings.lua", function()
        local text = demo_file:read("*a"):gsub("\r\n", "\n")
        demo_file:close()
        local gear = text:match("character_starting_gear = {(.-)\n\t},\n")
        H.truthy(gear, "character_starting_gear block not found")
        for career, seeds in pairs(P.SEED_WEAPONS) do
            local block = gear:match("\n\t\t" .. career .. " = {(.-)\n\t\t}")
            H.truthy(block, "demo gear block missing for " .. career)
            H.truthy(block:find('slot_melee = "' .. seeds.slot_melee, 1, true), career .. " melee seed")
            H.truthy(block:find('slot_ranged = "' .. seeds.slot_ranged, 1, true), career .. " ranged seed")
        end
    end, "decompiled vanilla source not present on this machine")
end
