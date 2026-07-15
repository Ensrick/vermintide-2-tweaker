-- Pure bounded lifecycle for issue #316's Empire Longbow zoom probe.
-- Engine-free so target scope, due-time observation, and early-finish behavior
-- are covered by the repository's Lua 5.1 harness.
local M = {
    MAX_ATTEMPTS = 3,
}

local TARGET_CAREERS = {
    es_mercenary = true,
    es_knight = true,
    es_questingknight = true,
}

function M.is_target(template_name, career_name)
    local empire_longbow = template_name == "longbow_empire_template"
        or template_name == "longbow_empire_tutorial_template"
    return empire_longbow and TARGET_CAREERS[career_name] == true
end

function M.new(max_attempts)
    local probe = {
        max_attempts = max_attempts or M.MAX_ATTEMPTS,
        attempts = 0,
    }

    function probe:arm(template_name, career_name, item_name, started_at, due_at, fields)
        if not M.is_target(template_name, career_name) or self.attempts >= self.max_attempts then
            return nil
        end
        self.attempts = self.attempts + 1
        return {
            attempt = self.attempts,
            career = career_name,
            item = item_name,
            template = template_name,
            started_at = started_at,
            due_at = due_at,
            fields = fields or {},
            done = false,
        }
    end

    function probe:observe(record, now, zooming, zoom_mode)
        if not record or record.done then return nil end
        record.last_at = now
        if now < record.due_at then return nil end
        record.done = true
        return {
            -- Camera/status state cannot acknowledge body-clip playback. Keep
            -- that boundary explicit so successful zoom never closes a visible
            -- 3P animation regression by itself again.
            outcome = zooming and "camera_zoomed" or "camera_not_zoomed",
            elapsed = now - record.started_at,
            zooming = zooming == true,
            zoom_mode = zoom_mode,
            visible_draw = "unverified",
        }
    end

    function probe:finish(record, now, reason)
        if not record or record.done then return nil end
        now = now or record.last_at or record.started_at
        record.done = true
        return {
            outcome = "finished_before_observation",
            elapsed = now - record.started_at,
            reason = reason,
        }
    end

    return probe
end

return M
