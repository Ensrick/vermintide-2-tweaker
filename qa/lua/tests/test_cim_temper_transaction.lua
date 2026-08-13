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
end
