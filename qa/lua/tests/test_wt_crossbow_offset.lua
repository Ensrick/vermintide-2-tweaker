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

    H.test("WT #701 crossbow transform is exact left-only durable and receiver-scoped", function()
        local entry = read(public_root .. "_wt_transform_runtime.lua")
        local checks = read(public_root .. "_wt_runtime_checks.lua")
        H.truthy(entry:find(
            'wh_crossbow = { es_ = {0, 0.100, 0.025, hand = "left"} }', 1, true))
        H.truthy(entry:find("wh_crossbow = true", 1, true))
        H.truthy(checks:find("issue701_kruber_crossbow_left_grip_offset", 1, true))
        H.truthy(checks:find('plan("wh_crossbow", "wh_captain")', 1, true))
        H.truthy(checks:find("native.offset == nil", 1, true))
        H.equal(policy.contract.first_person, "unchanged")
    end)

    H.test("WT #701 preview hand routing preserves paired and right-hand controls", function()
        H.equal(policy.preview_slot_field({ left_hand_unit = "" }), "left_unit_3p")
        H.equal(policy.preview_slot_field({ right_hand_unit = "" }), "right_unit_3p")
        H.equal(policy.preview_slot_field({ left_hand_unit = "", right_hand_unit = "" }),
            "right_unit_3p")
        H.equal(policy.preview_slot_field(nil), "right_unit_3p")
        H.equal(policy.contract.preview_hand_source, "left_only_template")
        H.equal(policy.contract.paired_preview_fallback, "right_unit_3p")
    end)

    H.test("WT #701 world adapters retain owner bot husk and preview fan-out", function()
        local entry = read(public_root .. "_wt_transform_runtime.lua")
        local policy_source = read(public_root .. "_wt_grip_offset_policy.lua")
        -- The preview fan-out moved to _wt_menu_preview_owner.lua in the #1159
        -- wave-14 slice; the owner/bot/husk adapters now live in the transform owner.
        local preview_owner = read(public_root .. "_wt_menu_preview_owner.lua")
        H.truthy(entry:find('is_bot and "bot" or "owner"', 1, true))
        H.truthy(entry:find('slot_name, "remote_husk"', 1, true))
        H.truthy(preview_owner:find("_wt_grip_offset_policy.preview_slot_field(item_template)", 1, true))
        H.truthy(entry:find("grip_policy.log_issue701_retained_once", 1, true))
        H.truthy(policy_source:find("Unit.local_position(unit, 0)", 1, true))
        H.truthy(policy_source:find("[wt:701] retained", 1, true))
        H.equal(policy.contract.retained_evidence, "post_write_engine_readback")
    end)

    H.test("WT #701 Kruber census contains one regular Saltzpyre Crossbow row", function()
        local unlocks = dofile(public_root .. "wt_unlock_data.lua").weapon_unlock_map
        local status = dofile(dev_root .. "wt_port_status.lua")
        for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local rows = status.audit_cross_character(career, unlocks[career])
            local found = 0
            for _, row in ipairs(rows) do
                if row.weapon_key == "wh_crossbow" then
                    found = found + 1
                    H.equal(row.state, "untested")
                    H.equal(row.routing_state, "needs_animations")
                end
            end
            H.equal(found, 1, career .. " regular Crossbow census row drift")
        end
    end)
end
