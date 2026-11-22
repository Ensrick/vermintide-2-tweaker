-- #1933: deleting a craft that is still equipped crashed on the next frame:
-- the hero's queued resync spawn re-resolved its units, and vanilla
-- BackendUtils.get_item_units read get_skin of the deleted id
-- (Vermintide-2-Source-Code scripts/managers/backend/backend_utils.lua:156-168;
-- get_skin indexes the nil row, backend_interface_item_playfab.lua:344-347).
-- Rig run 20261122-054737-cim-cases-fc202dd9.
return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end
    local deletion = dofile(root .. "_cim_owned_deletion.lua")

    local CRAFT, OTHER = "7456daaf-craft", "DC47E749-native"
    local HALBERD = "units/weapons/player/wpn_wh_halberd_01/wpn_wh_halberd_01"

    local function items_with(rows)
        return {
            get_item_from_id = function(_, id) return rows[id] end,
            get_skin = function(self, id)
                local item = self:get_item_from_id(id)
                return item.skin   -- vanilla: no nil check
            end,
        }
    end
    -- The skin branch of vanilla BackendUtils.get_item_units.
    local function vanilla_get_item_units(items)
        local calls = {}
        local function units(item_data, backend_id, skin, career_name)
            calls[#calls + 1] = { item_data = item_data, backend_id = backend_id, skin = skin }
            local id = item_data.backend_id or backend_id
            if id or skin then
                if not skin then skin = items:get_skin(id) end
            end
            return { right_hand_unit = item_data.right_hand_unit, skin = skin, career = career_name }
        end
        return units, calls
    end
    local function with_backend(items, fn)
        local saved = rawget(_G, "Managers")
        rawset(_G, "Managers", { backend = { get_interface = function(_, name)
            return name == "items" and items or nil
        end } })
        local result = { pcall(fn) }
        rawset(_G, "Managers", saved)
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
    end

    H.test("#1933 get_item_units: a deleted backend id resolves the base units instead of crashing", function()
        local items = items_with({})
        local func, calls = vanilla_get_item_units(items)
        local item_data = { name = "es_halberd", backend_id = CRAFT, right_hand_unit = HALBERD }
        H.equal(pcall(func, item_data, nil, nil, "es_huntsman"), false,
            "vanilla indexes the missing row (FAIL premise)")
        local result = with_backend(items, function()
            return deletion.item_units(func, item_data, nil, nil, "es_huntsman")
        end)
        H.equal(result.right_hand_unit, HALBERD)
        H.equal(result.career, "es_huntsman")
        local last = calls[#calls]
        H.equal(last.item_data.backend_id, nil, "the base call carries no backend id")
        H.truthy(last.item_data ~= item_data, "the caller's item data is not mutated")
        H.equal(item_data.backend_id, CRAFT)
        -- A dangling id passed as the argument is handled the same way.
        local by_arg = with_backend(items, function()
            return deletion.item_units(func, { right_hand_unit = HALBERD }, CRAFT, nil, nil)
        end)
        H.equal(by_arg.right_hand_unit, HALBERD)
        H.equal(calls[#calls].backend_id, nil)
    end)

    H.test("#1933 get_item_units: resolvable ids, explicit skins and a missing backend pass through", function()
        local items = items_with({ [OTHER] = { skin = "native_skin" } })
        local func, calls = vanilla_get_item_units(items)
        local item_data = { backend_id = OTHER, right_hand_unit = HALBERD }
        local result = with_backend(items, function()
            return deletion.item_units(func, item_data, nil, nil, "es_mercenary")
        end)
        H.equal(result.skin, "native_skin")
        H.truthy(calls[#calls].item_data == item_data, "a resolvable id keeps the exact item data")
        local skinned = with_backend(items_with({}), function()
            return deletion.item_units(func, { backend_id = CRAFT }, nil, "explicit_skin", nil)
        end)
        H.equal(skinned.skin, "explicit_skin", "an explicit skin never reads the backend")
        local saved = rawget(_G, "Managers")
        rawset(_G, "Managers", nil)
        local ok = pcall(deletion.item_units, func, item_data, nil, nil, nil)
        rawset(_G, "Managers", saved)
        H.truthy(ok, "no backend: the original call runs unchanged")
        H.truthy(calls[#calls].item_data == item_data)
    end)

    H.test("#1933 held_ids reads equipped slots and queued resync spawns", function()
        local inventory = {
            _equipment = { slots = {
                slot_melee = { item_data = { backend_id = OTHER } },
                slot_ranged = { item_data = { name = "no_backend_id" } },
            } },
            _items_to_spawn = { slot_melee = { slot_id = "slot_melee", item_data = { backend_id = CRAFT } } },
        }
        local held = deletion.held_ids({ inventory, {}, { _equipment = 7 } })
        H.truthy(held[CRAFT], "a queued resync spawn holds the craft")
        H.truthy(held[OTHER], "an equipped slot holds its id")
        H.equal(held.no_backend_id, nil)
        H.equal(next(deletion.held_ids(nil)), nil)
    end)

    H.test("#1933 equipped_refusal refuses current, saved and live holders and fails closed", function()
        local current, saved = {}, {}
        local items = {
            equipped_by = function(_, id) return current[id] or {} end,
            is_equipped_by_any_loadout = function(_, id) return saved[id] or {} end,
        }
        H.equal(deletion.equipped_refusal(items, { CRAFT }, {}), nil)
        H.equal(deletion.equipped_refusal(items, {}, {}), nil)
        H.equal(deletion.equipped_refusal(items, nil, nil), nil)
        current[CRAFT] = { "es_huntsman" }
        H.truthy(tostring(deletion.equipped_refusal(items, { CRAFT }, {})):find("still equipped", 1, true))
        current[CRAFT], saved[CRAFT] = nil, { "es_huntsman_1" }
        H.truthy(tostring(deletion.equipped_refusal(items, { OTHER, CRAFT }, {})):find(CRAFT, 1, true))
        saved[CRAFT] = nil
        H.truthy(tostring(deletion.equipped_refusal(items, { CRAFT }, { [CRAFT] = true })):find("still equipped", 1, true),
            "the rig crash: loadout restored but the hero still had the craft queued")
        local broken = { equipped_by = function() error("not ready") end,
            is_equipped_by_any_loadout = function() return {} end }
        H.truthy(tostring(deletion.equipped_refusal(broken, { CRAFT }, {})):find("could not prove", 1, true))
        H.truthy(tostring(deletion.equipped_refusal({}, { CRAFT }, {})):find("could not prove", 1, true))
    end)

    H.test("#1933 the shared delete path refuses before the transaction and the hook routes the guard", function()
        local owner = read("_cim_command_owner.lua")
        local refusal_at = owner:find("local refusal = deletion.equipped_refusal(items, backend_ids, held)", 1, true)
        local wrapper_at = owner:find("mod._cim277_delete_owned_ids = function", 1, true)
        local execute_at = wrapper_at and owner:find("return deletion.execute({", wrapper_at, true)
        H.truthy(wrapper_at and refusal_at and execute_at and wrapper_at < refusal_at and refusal_at < execute_at,
            "the refusal runs inside the shared wrapper before deletion.execute")
        H.truthy(owner:find("deletion.equipped_refusal(items, foreign_ids, held)", 1, true))
        local forge = read("standard_forge.lua")
        H.truthy(forge:find("result = guard.item_units(func, item_data, backend_id, skin, career_name)", 1, true))
    end)
end
