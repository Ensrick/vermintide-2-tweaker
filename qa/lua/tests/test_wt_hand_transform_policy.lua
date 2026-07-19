return function(H, repo_root)
    local public_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
    local policy = dofile(public_root .. "_wt_grip_offset_policy.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    H.test("WT #735 receiver and hand policy is shared across transform channels", function()
        local left = { 25, -17.5, -15, hand = "left" }
        local catalog = { es_sword_shield_breton = { wh_ = left } }
        H.equal(policy.resolve(catalog, "es_sword_shield_breton", "wh_captain"), left)
        H.equal(policy.resolve(catalog, "es_sword_shield_breton", "es_knight"), nil)
        H.truthy(policy.applies_to_hand(left, "left"))
        H.equal(policy.applies_to_hand(left, "right"), false)
        H.equal(policy.unit_fields_3p(left)[1], "left_unit_3p")
        H.equal(#policy.unit_fields_3p(left), 1)
        local both = policy.unit_fields_3p({ 0, 0, 0 })
        H.equal(both[1], "left_unit_3p")
        H.equal(both[2], "right_unit_3p")
        H.equal(policy.contract.receiver_scope, "weapon_key_plus_career_prefix")
        H.equal(policy.contract.hand_scope, "descriptor_hand_field")
    end)

    H.test("WT #735 paired preview refuses ambiguous unit callback routing", function()
        local paired = { left_hand_unit = "shield", right_hand_unit = "weapon" }
        local field, reason = policy.preview_slot_field(paired, { hand = "left" })
        H.equal(field, nil)
        H.equal(reason, "paired-hand-ambiguous")
        H.equal(policy.preview_slot_field(paired, {}), "right_unit_3p")
        H.equal(policy.preview_slot_field({ left_hand_unit = "crossbow" }, { hand = "left" }),
            "left_unit_3p")
        H.equal(policy.contract.paired_scoped_preview, "post_spawn_data_hand_adapter")
    end)

    H.test("WT #735 paired preview adapter writes only the declared spawned hand", function()
        local adapter = dofile(public_root .. "_wt_paired_preview_transform.lua")
        local installed
        local fake_mod = {
            hook = function(_, class_name, method_name, callback)
                H.equal(class_name, "MenuWorldPreviewer")
                H.equal(method_name, "_spawn_item")
                installed = callback
            end,
        }
        local tracked = {}
        adapter.install(fake_mod, {
            local_career_name = function() return "wh_captain" end,
            resolve_rotation = function()
                return { 25, -17.5, -15, hand = "left" }
            end,
            resolve_offset = function() return nil end,
            offset_weapon_units = function() error("no offset expected") end,
            track_rotation = function(slot, _, _, _, _, _, _, role)
                tracked[#tracked + 1] = { slot = slot, role = role }
            end,
            is_unit = function(unit) return unit == "shield" or unit == "sword" end,
            policy = policy,
        })

        local previewer = {
            _equipment_units = { [4] = { left = "shield", right = "sword" } },
            _wielded_slot_type = "melee",
        }
        local spawn_data = {
            { slot_index = 4, item_slot_type = "melee", right_hand = true },
            { slot_index = 4, item_slot_type = "melee", left_hand = true },
        }
        local result = installed(function() return "vanilla-result" end,
            previewer, "es_sword_shield", spawn_data)
        H.equal(result, "vanilla-result")
        H.equal(#tracked, 1)
        H.equal(tracked[1].slot.left_unit_3p, "shield")
        H.equal(tracked[1].slot.right_unit_3p, nil)
        H.equal(tracked[1].role, "inventory_preview")
    end)

    H.test("WT #735 public and dev route shield rotation through exact hand adapters", function()
        for _, root in ipairs({ public_root, dev_root }) do
            local entry_name = root == public_root and "weapon_tweaker.lua"
                or "weapon_tweaker_dev.lua"
            local entry = read(root .. entry_name)
            local preview = read(root .. "_wt_paired_preview_transform.lua")
            local checks = read(root .. "_wt_runtime_checks.lua")
            H.truthy(entry:find(
                'local _SALTZ_KRUBER_SHIELD_ROTATION = { 25, -17.5, -15, hand = "left" }',
                1, true))
            H.truthy(entry:find("_wt_grip_offset_policy.applies_to_hand(baked_euler, hand)",
                1, true))
            H.truthy(entry:find("_wt_paired_preview_transform.install", 1, true))
            H.truthy(preview:find('mod:hook("MenuWorldPreviewer", "_spawn_item"', 1, true))
            H.truthy(preview:find("self._equipment_units[entry.slot_index]", 1, true))
            H.truthy(entry:find('role=%s career=%s weapon=%s hand=%s match=%s', 1, true)
                or read(root .. "_wt_grip_offset_policy.lua"):find(
                    'role=%s career=%s weapon=%s hand=%s match=%s', 1, true))
            H.truthy(checks:find("issue735_shield_rotation_left_only", 1, true))
        end
    end)

    H.test("WT #735 retained proof reads rotation back after the durable write", function()
        local source = read(public_root .. "_wt_grip_offset_policy.lua")
        local entry = read(public_root .. "weapon_tweaker.lua")
        H.truthy(source:find("Unit.local_rotation(unit, 0)", 1, true))
        H.truthy(source:find("Quaternion.to_elements", 1, true))
        H.truthy(source:find("[wt:735] retained", 1, true))
        H.truthy(source:find("max_q_error", 1, true))
        H.truthy(entry:find("log_issue735_retained_once(row, unit, desired)", 1, true))
        H.equal(policy.contract.retained_evidence, "post_write_engine_readback")
    end)
end
