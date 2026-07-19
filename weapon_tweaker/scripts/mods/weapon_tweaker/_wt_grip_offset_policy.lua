-- _wt_grip_offset_policy.lua — hand routing and retained-state evidence for baked grip offsets.
--
-- MenuWorldPreviewer does not pass a hand flag to _spawn_item_unit, so only a
-- left-only template can be identified unambiguously there. Animated gameplay
-- remains renderer-local; the retained logger reads the engine state back after
-- a durable write and emits one bounded line per tracked #701 unit.
--
-- Owned by: Weapon Tweaker entry point. Consumed via: the entry-point manifest.

local M = {}

function M.preview_slot_field(item_template)
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
    retained_evidence = "post_write_engine_readback",
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

return M
