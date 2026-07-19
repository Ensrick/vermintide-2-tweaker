-- _wt_grip_offset_policy.lua — receiver/hand routing and retained-state evidence for baked transforms.
--
-- Scale, offset, and rotation catalogs share one career-prefix resolver and one
-- hand discriminator. MenuWorldPreviewer does not pass a hand flag to
-- _spawn_item_unit, so a paired template with a hand-scoped transform must defer
-- to the post-_spawn_item adapter where spawn_data supplies exact hand identity.
-- Retained loggers read engine state after durable writes for #701 and #735.
--
-- Owned by: Weapon Tweaker entry point. Consumed via: the entry-point manifest.

local M = {}

function M.resolve(catalog, weapon_key, career_name)
    if type(catalog) ~= "table" or type(weapon_key) ~= "string"
            or type(career_name) ~= "string" then return nil end
    local overrides = catalog[weapon_key]
    if type(overrides) ~= "table" then return nil end
    for prefix, spec in pairs(overrides) do
        if type(prefix) == "string" and career_name:sub(1, #prefix) == prefix then
            return spec
        end
    end
    return nil
end

function M.applies_to_hand(spec, hand)
    if type(spec) ~= "table" or (hand ~= "left" and hand ~= "right") then
        return false
    end
    return spec.hand == nil or spec.hand == hand
end

function M.unit_fields_3p(spec)
    local fields = {}
    if M.applies_to_hand(spec, "left") then fields[#fields + 1] = "left_unit_3p" end
    if M.applies_to_hand(spec, "right") then fields[#fields + 1] = "right_unit_3p" end
    return fields
end

function M.preview_slot_field(item_template, spec)
    local paired = type(item_template) == "table"
        and item_template.left_hand_unit and item_template.right_hand_unit
    if paired and type(spec) == "table" and spec.hand ~= nil then
        return nil, "paired-hand-ambiguous"
    end
    if type(item_template) == "table"
            and item_template.left_hand_unit
            and not item_template.right_hand_unit then
        return "left_unit_3p"
    end
    return "right_unit_3p"
end

M.contract = {
    preview_hand_source = "left_only_template",
    paired_preview_fallback = "right_unit_3p",
    paired_scoped_preview = "post_spawn_data_hand_adapter",
    retained_evidence = "post_write_engine_readback",
    receiver_scope = "weapon_key_plus_career_prefix",
    hand_scope = "descriptor_hand_field",
    first_person = "unchanged",
}

function M.log_issue701_retained_once(row, unit, target)
    if not row or row.weapon_key ~= "wh_crossbow" or row.retained_logged
            or not unit or not target then return end

    local retained_text, target_text
    local ok = pcall(function()
        local retained = Unit.local_position(unit, 0)
        local rx, ry, rz = Vector3.to_elements(retained)
        local tx, ty, tz = Vector3.to_elements(target)
        retained_text = string.format("%.3f,%.3f,%.3f", rx, ry, rz)
        target_text = string.format("%.3f,%.3f,%.3f", tx, ty, tz)
    end)
    if not ok or not retained_text or not target_text then return end

    row.retained_logged = true
    pcall(printf,
        "[wt:701] retained role=%s career=%s weapon=%s hand=%s retained_pos=(%s) target_pos=(%s)",
        tostring(row.role or "owner"), tostring(row.career_name),
        tostring(row.weapon_key), tostring(row.hand), retained_text, target_text)
end

local function _quaternion_text(value)
    local ok, x, y, z, w = pcall(Quaternion.to_elements, value)
    if not ok then return nil end
    return string.format("%.4f,%.4f,%.4f,%.4f", x, y, z, w), { x, y, z, w }
end

function M.log_issue735_retained_once(row, unit, target)
    if not row or not row.euler or row.hand ~= "left" or row.retained_logged_735
            or not unit or not target then return end

    local retained_text, target_text, retained_parts, target_parts
    local ok = pcall(function()
        local retained = Unit.local_rotation(unit, 0)
        retained_text, retained_parts = _quaternion_text(retained)
        target_text, target_parts = _quaternion_text(target)
    end)
    if not ok or not retained_text or not target_text then return end

    local direct, negated = 0, 0
    for i = 1, 4 do
        direct = math.max(direct, math.abs(retained_parts[i] - target_parts[i]))
        negated = math.max(negated, math.abs(retained_parts[i] + target_parts[i]))
    end
    local error = math.min(direct, negated)
    row.retained_logged_735 = true
    pcall(printf,
        "[wt:735] retained role=%s career=%s weapon=%s hand=%s match=%s max_q_error=%.6f retained_rot=(%s) target_rot=(%s)",
        tostring(row.role or "preview"), tostring(row.career_name),
        tostring(row.weapon_key), tostring(row.hand), tostring(error <= 0.0001),
        error, retained_text, target_text)
end

return M
