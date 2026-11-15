-- WP-CIM-04 (#1654): the boot restore of a saved craft injects without the
-- "new item" marker or an autosave, keeps a row that fails the mirror
-- postcondition and names the field, and can defer the per-item refresh.
-- Fixtures shared with the #1654 cases of test_cim_synthetic_item_contract.lua
-- (moved here to keep that file under the 1500-line target).
return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local contract = assert(loadfile(root .. "_cim_synthetic_item_contract.lua"))()

    -- #1654 fixtures: a lua-cjson-shaped codec (numbers at %.14g, the default
    -- encode precision) and a mirror whose add_item mirrors the fields
    -- PlayFabMirrorBase._update_data derives from CustomData
    -- (playfab_mirror_base.lua:1723-1785).
    local function json_encode(value)
        local kind = type(value)
        if kind == "number" then return string.format("%.14g", value) end
        if kind == "string" then return string.format("%q", value) end
        if kind == "boolean" then return tostring(value) end
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        if count == 0 then return "{}" end
        local parts = {}
        if #value == count then
            for i = 1, #value do parts[i] = json_encode(value[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        for i, key in ipairs(keys) do
            parts[i] = string.format("%q", key) .. ":" .. json_encode(value[key])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local function json_decode(text)
        local lua = text:gsub("%[", "{"):gsub("%]", "}")
            :gsub('"([%w_]+)":', '["%1"]=')
        return assert(loadstring("return " .. lua))()
    end
    local es_2h_sword = {
        slot_type = "melee", can_wield = { "es_mercenary" },
        template = "two_handed_swords_template_1", item_type = "es_2h_sword",
        inventory_icon = "icon_es_2h_sword", rarity = "plentiful",
    }
    local function playfab_mirror(masters)
        local mirror = { _inventory_items = {} }
        function mirror:add_item(backend_id, item)
            self._inventory_items[backend_id] = item
            local custom = item.CustomData
            if custom.properties then item.properties = json_decode(custom.properties) end
            if custom.traits then item.traits = json_decode(custom.traits) end
            if custom.power_level then item.power_level = tonumber(custom.power_level) end
            if custom.rarity then item.rarity = custom.rarity end
            if custom.skin then item.skin = custom.skin end
            item.backend_id, item.key = backend_id, item.ItemId
            item.data = masters[item.ItemId]
        end
        function mirror:remove_item(backend_id)
            self._inventory_items[backend_id] = nil
        end
        return mirror
    end
    local function saved_record(backend_id, properties, traits, skin)
        return {
            backend_id = backend_id, item_key = "es_2h_sword", owner = "cim",
            schema_version = 1, provider = "vanilla", rarity = "modded",
            power_level = 300, via_mirror = true, skin = skin,
            properties = properties, traits = traits, trait = traits[1],
        }
    end
    local function restore(mirror, record, decode, options)
        local normalized = assert(contract.gate_record("mirror_injection",
            record.backend_id, record, es_2h_sword))
        local payload, err, mirror_record = contract.build_mirror_payload(
            normalized, es_2h_sword, json_encode, decode)
        if not payload then return nil, err end
        return contract.inject_mirror_item(mirror, record.backend_id, payload,
            function() return "nonce-" .. record.backend_id end, mirror_record,
            options)
    end
    local function restore_payload(record)
        local normalized = assert(contract.gate_record("mirror_injection",
            record.backend_id, record, es_2h_sword))
        return contract.build_mirror_payload(
            normalized, es_2h_sword, json_encode, json_decode)
    end

    -- WP-CIM-04 (a): a restore passes skip_autosave and skip_mark_as_new
    -- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/
    -- playfab_mirror_base.lua:2494, item_helper.lua:128-158); a craft does not.
    H.test("CIM #1654 restore injection skips the new marker and the autosave", function()
        local mirror = playfab_mirror({ es_2h_sword = es_2h_sword })
        local seen = {}
        local base_add = mirror.add_item
        function mirror:add_item(backend_id, item, skip_autosave, skip_mark_as_new)
            seen[backend_id] = { skip_autosave, skip_mark_as_new }
            base_add(self, backend_id, item)
        end
        local restored = saved_record("restore-flags", { attack_speed = 0 }, {}, nil)
        local added, reason = restore(mirror, restored, json_decode, { restore = true })
        H.equal(reason, nil)
        H.truthy(added)
        H.equal(seen["restore-flags"][1], true, "skip_autosave")
        H.equal(seen["restore-flags"][2], true, "skip_mark_as_new")

        local crafted = saved_record("craft-flags", { attack_speed = 0 }, {}, nil)
        added, reason = restore(mirror, crafted, json_decode)
        H.equal(reason, nil)
        H.truthy(added)
        H.equal(seen["craft-flags"][1], nil, "craft keeps the autosave")
        H.equal(seen["craft-flags"][2], nil, "craft keeps the new marker")
    end)

    -- WP-CIM-04 (b, c): a restore keeps a row that fails the postcondition and
    -- names the field; a craft still removes it.
    H.test("CIM #1654 restore keeps a mismatching row and reports the field", function()
        local function perturbing_mirror()
            local mirror = playfab_mirror({ es_2h_sword = es_2h_sword })
            local base_add = mirror.add_item
            function mirror:add_item(backend_id, item, ...)
                base_add(self, backend_id, item, ...)
                item.properties.stamina = 0.5
            end
            return mirror
        end
        local mirror = perturbing_mirror()
        local added, reason, token, cleaned, rollback, warning = restore(mirror,
            saved_record("kept-probe", { stamina = 0.25 }, {}, nil), json_decode,
            { restore = true })
        H.equal(added, true)
        H.equal(reason, nil)
        H.truthy(token ~= nil, "ownership token returned")
        H.equal(cleaned, false)
        H.equal(type(rollback), "function")
        H.equal(type(warning), "string")
        H.truthy(warning:find("properties", 1, true), warning)
        H.truthy(mirror._inventory_items["kept-probe"] ~= nil, "row kept")

        mirror = perturbing_mirror()
        local removed, removed_reason, _, _, _, no_warning = restore(mirror,
            saved_record("removed-probe", { stamina = 0.25 }, {}, nil), json_decode)
        H.equal(removed, nil)
        H.truthy(removed_reason:find("mirror_postcondition:mismatch:properties", 1, true),
            removed_reason)
        H.equal(no_warning, nil)
        H.equal(mirror._inventory_items["removed-probe"], nil, "craft path removes the row")
    end)

    -- WP-CIM-04 (d): a deferred restore never runs the per-item refresh.
    H.test("CIM #1654 deferred restore skips the per-item refresh", function()
        local mirror = playfab_mirror({ es_2h_sword = es_2h_sword })
        local refreshes = 0
        local function refresh()
            refreshes = refreshes + 1
            return true
        end
        local record = saved_record("deferred-probe", { attack_speed = 0 }, {}, nil)
        local payload, err, mirror_record = restore_payload(record)
        H.truthy(payload, err)
        local added, reason, token, rollback, warning =
            contract.inject_and_refresh_mirror_item(mirror, record.backend_id,
                payload, function() return "nonce-deferred" end, mirror_record,
                refresh, { restore = true, defer_refresh = true })
        H.equal(reason, nil)
        H.equal(added, true)
        H.truthy(token ~= nil)
        H.equal(type(rollback), "function")
        H.equal(warning, nil)
        H.equal(refreshes, 0, "refresh deferred to the caller")
        H.truthy(mirror._inventory_items["deferred-probe"] ~= nil)

        -- The warning is the fifth value of the wrapper.
        local base_add = mirror.add_item
        function mirror:add_item(backend_id, item, ...)
            base_add(self, backend_id, item, ...)
            item.properties.stamina = 0.5
        end
        local perturbed = saved_record("deferred-warning", { stamina = 0.25 }, {}, nil)
        payload, err, mirror_record = restore_payload(perturbed)
        H.truthy(payload, err)
        local kept, _, _, _, kept_warning = contract.inject_and_refresh_mirror_item(
            mirror, perturbed.backend_id, payload,
            function() return "nonce-deferred-warning" end, mirror_record,
            refresh, { restore = true, defer_refresh = true })
        H.equal(kept, true)
        H.truthy(type(kept_warning) == "string" and kept_warning:find("properties", 1, true),
            tostring(kept_warning))
        H.equal(refreshes, 0)

        -- Without options the wrapper still refreshes once per craft.
        local crafted = saved_record("refreshed-probe", { attack_speed = 0 }, {}, nil)
        payload, err, mirror_record = restore_payload(crafted)
        local plain_mirror = playfab_mirror({ es_2h_sword = es_2h_sword })
        H.equal(contract.inject_and_refresh_mirror_item(plain_mirror, crafted.backend_id,
            payload, function() return "nonce-refreshed" end, mirror_record, refresh), true)
        H.equal(refreshes, 1)
    end)

end
