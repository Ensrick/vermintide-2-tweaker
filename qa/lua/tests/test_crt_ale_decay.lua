return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    local function literal_count(text, needle)
        local count, from = 0, 1
        while true do
            local at = text:find(needle, from, true)
            if not at then return count end
            count = count + 1
            from = at + #needle
        end
    end

    H.test("CRT ale decay targets both vanilla sub-buffs independently", function()
        H.truthy(source:find(
            '{ buff = "bardin_survival_ale_buff", sub_index = 1, field = "refresh_durations", value = false }',
            1, true))
        H.truthy(source:find(
            '{ buff = "bardin_survival_ale_buff", sub_index = 2, field = "refresh_durations", value = false }',
            1, true))
    end)

    H.test("CRT indexed patch engine preserves old callers and restores exact sub-buff", function()
        H.equal(literal_count(source, "local sub_index = patch.sub_index or 1"), 1,
            "apply path must default existing patches to sub-buff one")
        H.equal(literal_count(source,
            "template.buffs and template.buffs[entry.sub_index or 1]"), 2,
            "both reapply cleanup and disable restore must use the captured index")
        H.truthy(source:find("sub_index = sub_index,", 1, true),
            "saved patch state must retain the exact sub-buff index")
    end)
end
