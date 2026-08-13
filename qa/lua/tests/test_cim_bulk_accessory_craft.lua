return function(H, repo_root)
    local policy_path = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_bulk_accessory_craft.lua"
    local entry_path = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua"
    local runtime_path = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_temper_runtime.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    H.test("CIM bulk accessory craft attempts every native accessory slot without edit state", function()
        local policy = assert(loadfile(policy_path))()
        local calls = {}
        local count = policy.craft_all(function(index, slot)
            calls[#calls + 1] = tostring(index) .. ":" .. slot
            return true
        end)

        H.equal(count, 3)
        H.equal(table.concat(calls, ","),
            "1:slot_ring,2:slot_necklace,3:slot_trinket_1")
    end)

    H.test("CIM bulk accessory craft continues after one slot fails", function()
        local policy = assert(loadfile(policy_path))()
        local calls = 0
        local count = policy.craft_all(function(index)
            calls = calls + 1
            return index ~= 2
        end)

        H.equal(calls, 3)
        H.equal(count, 2)
        H.equal(policy.craft_all(nil), 0)
    end)

    H.test("CIM production bulk button uses player-facing Accessories and the pure policy", function()
        local entry = read(entry_path)
        local source = read(runtime_path)
        H.truthy(source:find('"CRAFT MODDED ACCESSORIES"', 1, true))
        H.equal(source:find('"CRAFT MODDED JEWELLERY"', 1, true), nil)
        H.truthy(source:find("state.bulk_accessory_craft.craft_all", 1, true))
        H.truthy(entry:find("bulk_accessory_craft = _BULK_ACCESSORY_CRAFT", 1, true))

        local hook_at = assert(source:find(
            'mod:hook("HeroWindowWeaveProperties", "_upgrade_magic_level",', 1, true))
        local start_at = assert(source:find("if not item then", hook_at, true))
        local end_at = assert(source:find("if not item_key then", start_at, true))
        local bulk_branch = source:sub(start_at, end_at - 1)
        H.equal(bulk_branch:find("_amulet_dirty", 1, true), nil)
    end)
end
