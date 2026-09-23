return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local temper = assert(loadfile(root .. "_cim_temper_transaction.lua"))()

    H.test("CIM #1141 classifies blacksmith templates as Craft only", function()
        H.equal(temper.action_for({ rarity = "default" }, "owned_default"), "craft")
        H.equal(temper.action_for({ data = { rarity = "default" } }, "wrapped"), "craft")
        H.equal(temper.action_for({ rarity = "modded" }, "cim_owned"), "apply")
        H.equal(temper.action_for({}, "cim_template_es_sword"), "craft")
    end)

    H.test("CIM #1141 materializes a deterministic draft without touching item", function()
        local item = {
            rarity = "modded",
            properties = { crit_chance = 0.2 },
            traits = { "old_trait" },
        }
        local draft = temper.payload_from_grid({
            properties = {
                weave_crit_chance = { 1, 2, 3 },
                weave_attack_speed = { 4, 5 },
            },
            traits = {
                weave_second_trait = 2,
                weave_first_trait = 1,
            },
        }, function(key)
            return key:gsub("^weave_", "")
        end, function(_, count)
            return count / 5
        end)

        H.deep_equal(draft.properties, {
            crit_chance = 0.6,
            attack_speed = 0.4,
        })
        H.deep_equal(draft.traits, { "first_trait", "second_trait" })
        H.deep_equal(item.properties, { crit_chance = 0.2 })
        H.deep_equal(item.traits, { "old_trait" })
    end)

    H.test("CIM #1141 Apply commits once and repeated Apply is a no-op", function()
        local item = {
            rarity = "modded",
            properties = { crit_chance = 0.2 },
            traits = { "old_trait" },
            CustomData = {},
        }
        local payload = {
            properties = { attack_speed = 1 },
            traits = { "new_trait" },
        }
        local encoded = 0
        local ok, changed = temper.apply_to_item(item, payload, function()
            encoded = encoded + 1
            return "json-" .. encoded
        end)
        H.truthy(ok)
        H.truthy(changed)
        H.deep_equal(item.properties, { attack_speed = 1 })
        H.deep_equal(item.traits, { "new_trait" })
        H.equal(item.CustomData.properties, "json-1")
        H.equal(item.CustomData.traits, "json-2")

        ok, changed = temper.apply_to_item(item, payload, function()
            encoded = encoded + 1
            return "unexpected"
        end)
        H.truthy(ok)
        H.equal(changed, false)
        H.equal(encoded, 2)
    end)

    H.test("CIM #1141 refuses to mutate a blacksmith template", function()
        local template = {
            rarity = "default",
            properties = {},
            traits = {},
        }
        local ok, reason = temper.apply_to_item(template, {
            properties = { crit_chance = 1 },
            traits = { "new_trait" },
        })
        H.equal(ok, false)
        H.equal(reason, "template")
        H.deep_equal(template.properties, {})
        H.deep_equal(template.traits, {})
    end)

    H.test("CIM #1141 draft copies do not alias persisted records", function()
        local source = {
            properties = { crit_chance = 1 },
            traits = { "trait" },
        }
        local copy = temper.copy_payload(source)
        copy.properties.crit_chance = 0
        copy.traits[1] = "changed"
        H.equal(source.properties.crit_chance, 1)
        H.equal(source.traits[1], "trait")
    end)

    H.test("CIM #1141 lists staged counts outside the storable range, key-sorted", function()
        local ranges = {
            weave_block_cost = { 2, 5 },
            weave_attack_speed = { 3, 5 },
            weave_crit_chance = { 1, 5 },
        }
        local function range(weave_key)
            local pair = ranges[weave_key]
            if pair then return pair[1], pair[2] end
            return nil
        end
        local function strip(key) return (key:gsub("^weave_", "")) end
        local rejected = temper.unrepresentable_properties({
            properties = {
                weave_crit_chance = { 1 },
                weave_block_cost = { 2 },
                weave_attack_speed = { 3, 4 },
                weave_unknown = { 5 },
                weave_empty = {},
            },
        }, strip, range)
        H.deep_equal(rejected, {
            { key = "attack_speed", weave_key = "weave_attack_speed",
              staged = 2, low = 3, high = 5 },
            { key = "block_cost", weave_key = "weave_block_cost",
              staged = 1, low = 2, high = 5 },
        })
        H.equal(temper.unrepresentable_properties({
            properties = { weave_block_cost = { 2, 3 }, weave_crit_chance = { 1 } },
        }, strip, range), nil)
        H.equal(temper.unrepresentable_properties({}, strip, range), nil)
        local over = temper.unrepresentable_properties({
            properties = { weave_block_cost = { 1, 2, 3, 4, 5, 6 } },
        }, strip, range)
        H.equal(over[1].staged, 6)
        H.equal(over[1].high, 5)
    end)

    H.test("CIM #1141 describes each refused count with its storable range", function()
        local rejected = {
            { key = "attack_speed", weave_key = "weave_attack_speed",
              staged = 1, low = 3, high = 5 },
            { key = "block_cost", weave_key = "weave_block_cost",
              staged = 1, low = 2, high = 5 },
        }
        H.equal(temper.describe_unrepresentable(rejected),
            "attack_speed needs 3 to 5 bubbles on this item (1 staged); "
            .. "block_cost needs 2 to 5 bubbles on this item (1 staged)")
        H.equal(temper.describe_unrepresentable(rejected, function(weave_key)
            if weave_key == "weave_block_cost" then return "Block Cost Reduction" end
            error("localizer exploded")
        end), "attack_speed needs 3 to 5 bubbles on this item (1 staged); "
            .. "Block Cost Reduction needs 2 to 5 bubbles on this item (1 staged)")
        H.equal(temper.describe_unrepresentable(nil), "")
    end)
end
