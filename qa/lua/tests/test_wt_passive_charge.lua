return function(H, repo_root)
    local old_get_mod = rawget(_G, "get_mod")
    local old_script_unit = rawget(_G, "ScriptUnit")
    rawset(_G, "get_mod", function() return {} end)
    rawset(_G, "ScriptUnit", {})
    local Passive = assert(loadfile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_passive_charge.lua"))()
    rawset(_G, "get_mod", old_get_mod)
    rawset(_G, "ScriptUnit", old_script_unit)

    local moonfire = {
        actions = { action_one = { default = { kind = "bow_energy" } } },
    }
    local normal_bow = {
        actions = { action_one = { default = { kind = "bow" } } },
    }
    local function inventory(ranged, wielded)
        local inv = {
            wielded = wielded,
            slots = { slot_melee = {}, slot_ranged = ranged },
            reads = {},
        }
        function inv:get_wielded_slot_name()
            return self.wielded
        end
        function inv:get_slot_data(slot_name)
            self.reads[#self.reads + 1] = slot_name
            return self.slots[slot_name]
        end
        function inv:get_item_template(slot_data)
            return slot_data
        end
        return inv
    end

    H.test("WT Moonfire regen follows ranged slot while melee is active", function()
        local inv = inventory(moonfire, "slot_melee")
        H.equal(Passive.energy_regen_delta(inv, 0, 2), 3)
        H.deep_equal(inv.reads, { "slot_ranged" })
    end)

    H.test("WT Moonfire slot swaps keep one native-rate regen path", function()
        local inv = inventory(moonfire, "slot_ranged")
        H.equal(Passive.energy_regen_delta(inv, 0, 2), 3)
        inv.wielded = "slot_melee"
        H.equal(Passive.energy_regen_delta(inv, 0, 2), 3)
        inv.slots.slot_ranged = nil
        H.equal(Passive.energy_regen_delta(inv, 0, 2), nil)
    end)

    H.test("WT passive charge excludes native Kerillian and other ranged weapons", function()
        local inv = inventory(moonfire, "slot_melee")
        H.equal(Passive.energy_regen_delta(inv, 1.5, 2), nil)
        inv.slots.slot_ranged = normal_bow
        H.equal(Passive.energy_regen_delta(inv, 0, 2), nil)
    end)
end
