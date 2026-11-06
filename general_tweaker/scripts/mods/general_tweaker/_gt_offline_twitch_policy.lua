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

-- Native _next_standard_vote (twitch_manager.lua:1403-1453) omits the
-- whitelist for candidate B and its package replacement. Keep its selection
-- order/cost/boss rules, adding the same composed gate used for candidate A.
-- No shared lookup or instance method is replaced, including during callbacks.
function P.next_standard_vote(self, template_a, dependencies)
    local templates_by_name = dependencies.templates
    local standard = dependencies.clone(dependencies.standard)
    local maximum_diff = dependencies.maximum_diff
    local rejected = {}
    local cleared = false
    local resolved_a

    if not self:_in_whitelist(template_a.name) then return nil end
    local attempts = 0
    local maximum_attempts = #standard + 2
    while attempts < maximum_attempts do
        attempts = attempts + 1
        local templates = dependencies.clone(standard)
        dependencies.shuffle(templates)
        local best_template, best_lookup_name
        local best_diff = math.huge
        local used = self._used_vote_templates
        for i = 1, #templates do
            local name = templates[i]
            if template_a.name ~= name and not used[name] and not rejected[name]
                    and self:_in_whitelist(name) then
                local candidate = templates_by_name[name]
                local allowed = not candidate.condition_func or candidate.condition_func()
                if allowed then
                    local invalid_matchup = template_a.boss
                        and not candidate.boss and not candidate.boss_equivalent
                    if not invalid_matchup then
                        local difference = math.abs(template_a.cost - candidate.cost)
                        if difference <= maximum_diff and difference < best_diff then
                            best_template, best_lookup_name, best_diff = candidate, name, difference
                        end
                    end
                end
            end
        end
        if not best_template then
            -- Native retries after clearing used votes. One retry is sufficient:
            -- a second empty rotation cannot become admissible without a change
            -- outside this call. Defer rather than recurse forever when all
            -- categories, conditions or boss/cost pairings exclude a ballot.
            if cleared then return nil end
            self:_clear_used_votes(true)
            cleared = true
        else
            if not resolved_a then
                resolved_a = self:_check_breed_package_loading(template_a)
                if not self:_in_whitelist(resolved_a.name) then return nil end
            end
            local resolved_b = self:_check_breed_package_loading(best_template, resolved_a)
            if self:_in_whitelist(resolved_b.name) then
                return "standard_vote", { resolved_a.name, resolved_b.name }, nil
            end
            -- A native package fallback may cross category/whitelist boundaries.
            -- Exclude only its source candidate in this invocation and retry the
            -- remaining finite lookup. Never mutate global lists or used votes
            -- merely to hide a disallowed replacement.
            rejected[best_lookup_name] = true
        end
    end
    return nil
end

return P
