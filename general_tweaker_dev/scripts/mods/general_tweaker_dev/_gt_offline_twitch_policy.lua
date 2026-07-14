-- Pure policy for issue #333. Twitch's native candidate whitelist calls this
-- once per template; keeping classification engine-free makes the allow-list
-- contract testable without launching the game.

local P = {}

function P.category(template_name, template)
    template_name = type(template_name) == "string" and template_name or ""
    template = type(template) == "table" and template or {}

    if template_name:find("^twitch_give_") then return "items" end
    if template_name:find("^twitch_spawn_")
            or template.breed_name ~= nil or template.boss or template.special then
        return "spawns"
    end

    local description = type(template.description) == "string" and template.description or ""
    local text = type(template.text) == "string" and template.text or ""
    if description:find("^description_mutator_") or text:find("^display_name_mutator_") then
        return "mutators"
    end

    -- Buffs are the safe catch-all for ordinary effects and future templates.
    return "buffs"
end

function P.is_allowed(template_name, template, allowed)
    if type(allowed) ~= "table" then return true end
    return allowed[P.category(template_name, template)] == true
end

function P.any_allowed(allowed)
    return type(allowed) == "table" and (allowed.buffs == true or allowed.items == true
        or allowed.mutators == true or allowed.spawns == true)
end

return P
