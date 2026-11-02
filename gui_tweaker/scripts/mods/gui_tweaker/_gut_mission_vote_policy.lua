-- _gut_mission_vote_policy.lua -- pure classification for the #700 HUD vote bridge.
--
-- The vanilla game-settings vote is intentionally marked non-ingame because it
-- normally runs in the keep's Start Game view. GUT reuses that same vote while an
-- Adventure mission is live, so only that exact context needs the HUD voter UI.
--
-- Owned by: _gut_mission_map.lua. Consumed via: mod:dofile and offline Lua tests.

local Policy = {}

-- A title is usable only when it is real player-facing text. VMF and engine
-- localizers can expose either the bare key or <key> when a lookup is absent.
-- Reject those shapes, any other underscore-delimited identifier, and
-- nil/empty/whitespace-only values so a different unresolved key cannot cross
-- the boundary merely because it differs from the requested key.
function Policy.usable_title(value, key)
    if type(value) ~= "string" then return false end
    local normalized = value:match("^%s*(.-)%s*$")
    if normalized == "" then return false end
    if type(key) == "string" then
        if normalized == key or normalized == "<" .. key .. ">" then return false end
    end
    if normalized:match("^[%w_%.:/%-]*_[%w_%.:/%-]+$") then return false end
    if normalized:match("^<[%w_%.:/%-]+>$") then return false end
    return true
end

function Policy.active_vote(value)
    return type(value) == "table" and value or nil
end

function Policy.promote_template(template, resolved_title)
    if type(template) ~= "table" then
        return nil
    end
    if not Policy.usable_title(resolved_title, template.text)
        or not Policy.usable_title(resolved_title, "gut_mission_vote_title") then
        return nil
    end

    local promoted = {}
    for key, value in pairs(template) do
        promoted[key] = value
    end

    promoted.ingame_vote = true
    local authored_modifier = type(promoted.modify_title_text) == "function"
        and promoted.modify_title_text or nil
    promoted.modify_title_text = function(localized_title, data)
        promoted._gut700_title_input = localized_title
        local output
        if authored_modifier then
            local ok, value = pcall(authored_modifier, localized_title, data)
            if ok and Policy.usable_title(value, template.text) then
                output = value
            end
        end
        output = output or resolved_title
        promoted._gut700_title_output = output
        return output
    end
    promoted._gut700_promoted = true

    return promoted
end

-- Full wrappers use these helpers so their complete return tuple survives,
-- including interior and trailing nil values. Keeping the operation in this
-- pure module makes the exact Lua 5.1 behavior executable in offline QA.
function Policy.pack_returns(...)
    return { n = select("#", ...), ... }
end

function Policy.forward_returns(packed)
    if type(packed) ~= "table" or type(packed.n) ~= "number" then
        return nil
    end
    return unpack(packed, 1, packed.n)
end

function Policy.title_boundary(source_key, localized_input, modifier_output, final_title)
    local source = type(source_key) == "string" and source_key or "?"
    local input_ok = Policy.usable_title(localized_input, source)
    local modifier_ok = Policy.usable_title(modifier_output, source)
    local final_ok = Policy.usable_title(final_title, source)
    local result = final_ok and "PASS" or (modifier_ok and "WIDGET_BLANK" or
        (input_ok and "MODIFIER_BLANK" or "SOURCE_BLANK"))
    return {
        source = source,
        input_len = type(localized_input) == "string" and #localized_input or -1,
        modifier_len = type(modifier_output) == "string" and #modifier_output or -1,
        final_len = type(final_title) == "string" and #final_title or -1,
        result = result,
    }
end

function Policy.needs_ingame_hud(vote_name, mechanism, level_key, is_in_inn)
    return vote_name == "game_settings_vote"
        and mechanism == "adventure"
        and type(level_key) == "string"
        and level_key ~= "inn_level"
        and not is_in_inn
end

return Policy
