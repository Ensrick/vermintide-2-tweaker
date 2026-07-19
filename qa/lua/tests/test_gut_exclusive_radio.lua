return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Layout = assert(loadfile(root .. "_mod_tweaker_exclusive_layout.lua"))()

    local members = {
        { mod_id = "crt", setting_id = "choice_a" },
        { mod_id = "crt", setting_id = "choice_b" },
    }
    local function api(overrides)
        local out = {
            mod_id = "crt",
            field = function(node, key) return node[key] end,
            get_group_id = function(mod_id, setting_id)
                if mod_id == "crt" and (setting_id == "choice_a" or setting_id == "choice_b") then
                    return "crt_choice"
                end
            end,
            get_members = function() return members end,
            get_presentation = function()
                return { control = "radio", label = "choice_group", none_label = "none_default" }
            end,
        }
        for k, v in pairs(overrides or {}) do out[k] = v end
        return out
    end

    H.test("exclusive choices become one collapsible radio plan", function()
        local nodes = {
            { type = "group", setting_id = "parent" },
            { type = "checkbox", setting_id = "choice_a", title = "Choice A", tooltip = "Tip A" },
            { type = "checkbox", setting_id = "unrelated" },
            { type = "checkbox", setting_id = "choice_b", title = "Choice B", tooltip = "Tip B" },
            { type = "checkbox", setting_id = "after" },
        }
        local planned, depths, count = Layout.plan(nodes, { 0, 1, 1, 1, 0 }, api())
        H.equal(count, 1)
        H.equal(#planned, 7, "two checkbox rows become group + None + two choices")
        H.equal(planned[2].type, "group")
        H.equal(planned[2].title, "choice_group")
        H.equal(depths[2], 1)
        H.equal(planned[3].type, "radio")
        H.truthy(planned[3]._mt_exclusive_none)
        H.equal(depths[3], 2)
        H.equal(planned[4].setting_id, "choice_a")
        H.equal(planned[4].tooltip, "Tip A")
        H.equal(planned[5].setting_id, "choice_b")
        H.equal(planned[6].setting_id, "unrelated")
        H.equal(planned[7].setting_id, "after")
    end)

    H.test("cross-mod exclusive groups fail closed to checkbox layout", function()
        local original = {
            { type = "checkbox", setting_id = "choice_a" },
            { type = "checkbox", setting_id = "choice_b" },
        }
        local cross = {
            { mod_id = "crt", setting_id = "choice_a" },
            { mod_id = "other", setting_id = "choice_b" },
        }
        local planned, depths, count = Layout.plan(original, { 0, 0 }, api({
            get_members = function() return cross end,
        }))
        H.equal(count, 0)
        H.equal(planned, original)
        H.equal(depths[1], 0)
        H.equal(planned[1].type, "checkbox")
    end)

    H.test("members under different parents fail closed", function()
        local original = {
            { type = "group", setting_id = "parent_a" },
            { type = "checkbox", setting_id = "choice_a" },
            { type = "group", setting_id = "parent_b" },
            { type = "checkbox", setting_id = "choice_b" },
        }
        local planned, _, count = Layout.plan(original, { 0, 1, 0, 1 }, api())
        H.equal(count, 0)
        H.equal(planned, original)
    end)

    H.test("radio renderer and input transaction stay wired", function()
        local function source(name)
            local f = assert(io.open(root .. name, "rb"))
            local text = f:read("*a")
            f:close()
            return text
        end
        local defs = source("_mod_tweaker_definitions.lua")
        H.truthy(string.find(defs, "local function create_radio", 1, true))
        H.truthy(string.find(defs, "content_check_function = function(c) return c.selected end", 1, true))
        local interaction = source("_mod_tweaker_view_interaction.lua")
        H.truthy(string.find(interaction, 'row._wtype == "radio"', 1, true))
        H.truthy(string.find(interaction, "self:_enforce_exclusive", 1, true))
        H.truthy(string.find(interaction, "row._mt_radio_none", 1, true))
    end)
end
