-- CRT's single Mod Tweaker settings-owner v1 provider (#221, #1575). It
-- composes the armor cluster preimage owner with ownership of the derived
-- #445 family masters and #936 Tourney career presets (bug class 79):
--   * profile replay and automatic additions: those flags describe their
--     leaves, so they are consumed and never run a preset;
--   * an ordinary Apply: a flag whose staged value differs from its live value
--     is one preset command; family presets run before career presets, OFF
--     before ON, all before GUT commits the staged leaves, so staged leaves win.
-- Classification happens in prepare, before any write. Stock VMF clicks never
-- reach this provider and keep their per-setting callbacks.
return function(armor_api, family_ids, career_ids, runtime)
    local group = {}
    for i = 1, #family_ids do group[family_ids[i]] = 1 end
    for i = 1, #career_ids do group[career_ids[i]] = 2 end
    local api = { version = 1 }
    function api.capture(visible, defaults)
        return armor_api.capture(visible, defaults)
    end
    function api.prepare(pending, context)
        local armor_plan = armor_api.prepare(pending, context)
        local handled, derived, commands = {}, 0, {}
        if armor_plan then
            for id in pairs(armor_plan.handled) do handled[id] = true end
        end
        local replay = context.kind == "profile" or context.kind == "reconcile"
        for id, rank in pairs(group) do
            local value = pending[id]
            if value ~= nil then
                assert(type(value) == "boolean", "invalid indicator value")
                handled[id] = true
                if replay or runtime.get(id) == value then
                    derived = derived + 1
                else
                    commands[#commands + 1] = { id = id, value = value, rank = rank }
                end
            end
        end
        if not next(handled) then return nil end
        table.sort(commands, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.value ~= b.value then return not a.value end
            return a.id < b.id
        end)
        local kind = context.kind or "edit"
        return { handled = handled, commit = function()
            for i = 1, #commands do
                local command = commands[i]
                if command.rank == 1 then runtime.apply_family(command.id, command.value)
                else runtime.apply_career(command.id, command.value) end
            end
            if armor_plan and armor_plan.commit() == false then return false end
            if derived + #commands > 0 then runtime.finish(kind, derived, #commands) end
            return true
        end }
    end
    return api
end
