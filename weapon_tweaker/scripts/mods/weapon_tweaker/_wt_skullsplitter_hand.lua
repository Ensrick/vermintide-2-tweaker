-- Pure policy for issue #181: present Skullsplitter & Tome as a bare
-- right-handed Skullsplitter on Kruber without changing first-person units.

local M = {
    ITEM_KEY = "wh_hammer_book",
}

local _diag_seen = {}

function M.is_kruber(career_name)
    return type(career_name) == "string" and career_name:sub(1, 3) == "es_"
end

function M.runtime_action(item_name, career_name, hand)
    if item_name ~= M.ITEM_KEY or not M.is_kruber(career_name) then
        return nil
    end
    if hand == "right" then
        return "hide_book"
    end
    if hand == "left" then
        return "relink_hammer_right"
    end
    return nil
end

function M.resolve_right_hand_linking(weapons)
    local template = type(weapons) == "table"
        and weapons.one_handed_hammer_template_1
    local third_person = template
        and template.right_hand_attachment_node_linking
        and template.right_hand_attachment_node_linking.third_person
    local linking = third_person and third_person.wielded
    if type(linking) ~= "table" or #linking == 0 then
        return nil, "one_handed_hammer_template_1 right-hand 3P linking missing"
    end
    return linking
end

function M.resolve_right_hand_third_person(weapons)
    local template = type(weapons) == "table"
        and weapons.one_handed_hammer_template_1
    local third_person = template
        and template.right_hand_attachment_node_linking
        and template.right_hand_attachment_node_linking.third_person
    if type(third_person) ~= "table" or type(third_person.wielded) ~= "table"
            or #third_person.wielded == 0 then
        return nil, "one_handed_hammer_template_1 right-hand 3P linking missing"
    end
    return third_person
end

function M.validate_linking(linking, source_has_node, target_has_node)
    if type(linking) ~= "table" or type(source_has_node) ~= "function"
            or type(target_has_node) ~= "function" then
        return false, "invalid linking inputs"
    end
    for i, link in ipairs(linking) do
        if type(link) ~= "table" then
            return false, "link " .. tostring(i) .. " is not a table"
        end
        if type(link.source) == "string" and not source_has_node(link.source) then
            return false, "source node missing: " .. link.source
        end
        if type(link.target) == "string" and not target_has_node(link.target) then
            return false, "target node missing: " .. link.target
        end
    end
    return true
end

-- Build the preview update transactionally. The book entry is removed and the
-- existing hammer entry is reclassified as the right-hand unit with the same
-- receiver-native linking used in mission rendering. The input entries are not
-- mutated; an incomplete pair leaves the original spawn_data untouched.
function M.rewrite_preview_spawn_data(spawn_data, right_hand_third_person)
    if type(spawn_data) ~= "table" or type(right_hand_third_person) ~= "table"
            or type(right_hand_third_person.wielded) ~= "table" then
        return spawn_data, false, false
    end

    local rewritten = {}
    local hid_book = false
    local moved_hammer = false
    for _, entry in ipairs(spawn_data) do
        if type(entry) == "table" and entry.right_hand then
            hid_book = true
        elseif type(entry) == "table" and entry.left_hand then
            local copy = {}
            for key, value in pairs(entry) do copy[key] = value end
            copy.left_hand = nil
            copy.right_hand = true
            copy.despawn_both_hands_units = true
            copy.unit_attachment_node_linking = right_hand_third_person
            rewritten[#rewritten + 1] = copy
            moved_hammer = true
        else
            rewritten[#rewritten + 1] = entry
        end
    end

    if not hid_book or not moved_hammer then
        return spawn_data, false, false
    end
    return rewritten, true, true
end

function M.diag_once(key, emit, format_string, ...)
    if _diag_seen[key] or type(emit) ~= "function" then return end
    _diag_seen[key] = true
    emit(format_string, ...)
end

local function unit_alive(api, unit)
    return unit ~= nil and api and type(api.alive) == "function" and api.alive(unit)
end

local function relink(args, linking)
    return pcall(function()
        args.world_api.unlink_unit(args.world, args.weapon_unit_3p)
        args.gear_utils.link(args.world, linking, {}, args.owner_unit_3p,
            args.weapon_unit_3p)
    end)
end

-- Own the complete spawn-time presentation transaction. The root passes engine
-- APIs and the four relevant vanilla values, then returns all vanilla units
-- unchanged; in particular no first-person unit enters this module.
function M.apply_runtime(args)
    args = type(args) == "table" and args or {}
    local action = M.runtime_action(args.item_name, args.career_name, args.hand)
    if not action then return false, "not_applicable" end

    local perspective = args.perspective or "unknown"
    if action == "hide_book" then
        local hidden = unit_alive(args.unit_api, args.weapon_unit_3p)
        if hidden then
            if args.unit_api.has_visibility_group(args.weapon_unit_3p, "normal") then
                args.unit_api.set_visibility(args.weapon_unit_3p, "normal", false)
            else
                args.unit_api.set_unit_visibility(args.weapon_unit_3p, false)
            end
        end
        M.diag_once("runtime-book:" .. perspective .. ":" .. args.career_name,
            args.emit,
            "[wt:181] surface=runtime perspective=%s career=%s action=hide_book result=%s first_person=unchanged",
            perspective, args.career_name, hidden and "hidden" or "unit_missing")
        return true, hidden and "hidden" or "unit_missing"
    end

    local linking, reason = M.resolve_right_hand_linking(args.weapons)
    local result, detail = "skipped", reason or "unit_missing"
    local unit_api = args.unit_api
    if linking and unit_alive(unit_api, args.weapon_unit_3p)
            and unit_alive(unit_api, args.owner_unit_3p)
            and type(unit_api.has_node) == "function"
            and args.world_api and type(args.world_api.unlink_unit) == "function"
            and args.gear_utils and type(args.gear_utils.link) == "function" then
        local valid, validation_reason = M.validate_linking(linking,
            function(name) return unit_api.has_node(args.owner_unit_3p, name) end,
            function(name) return unit_api.has_node(args.weapon_unit_3p, name) end)
        if valid then
            local ok, err = relink(args, linking)
            if ok then
                result, detail = "relinked", tostring(linking[1] and linking[1].source)
            else
                local left_tp = args.item_template
                    and args.item_template.left_hand_attachment_node_linking
                local left = left_tp and left_tp.third_person
                    and left_tp.third_person.wielded
                local restored = type(left) == "table" and relink(args, left) or false
                result = restored and "fallback_left" or "relink_failed"
                detail = tostring(err)
            end
        else
            detail = validation_reason
        end
    end
    M.diag_once("runtime-hammer:" .. perspective .. ":" .. args.career_name,
        args.emit,
        "[wt:181] surface=runtime perspective=%s career=%s action=relink_hammer_right result=%s detail=%s first_person=unchanged",
        perspective, args.career_name, result, tostring(detail))
    return true, result, detail
end

-- HeroPreviewer bypasses GearUtils.spawn_inventory_unit. Own its parallel
-- transaction here so roots cannot drift between mission and inventory views.
function M.apply_preview(previewer, item_name, slot, weapons, emit)
    local career = type(previewer) == "table" and previewer._current_career_name
    if item_name ~= M.ITEM_KEY or not M.is_kruber(career) then
        return false, "not_applicable"
    end
    local slot_type = type(slot) == "table" and slot.type
    local info = slot_type and previewer._item_info_by_slot
        and previewer._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return false, "spawn_data_missing" end

    local third_person, reason = M.resolve_right_hand_third_person(weapons)
    if not third_person then
        M.diag_once("preview-missing-linking:" .. career, emit,
            "[wt:181] surface=preview career=%s result=skipped detail=%s",
            career, tostring(reason))
        return false, reason
    end
    local rewritten, hid_book, moved_hammer =
        M.rewrite_preview_spawn_data(info.spawn_data, third_person)
    local applied = hid_book and moved_hammer
    if applied then info.spawn_data = rewritten end
    M.diag_once("preview:" .. career, emit,
        "[wt:181] surface=preview career=%s action=hide_book_and_relink_hammer_right result=%s entries=%d first_person=not_applicable",
        career, applied and "rewritten" or "pair_incomplete",
        type(rewritten) == "table" and #rewritten or 0)
    return applied, applied and "rewritten" or "pair_incomplete"
end

return M
